import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart' as intl;

import '../api/print_templates_api.dart';
import '../models/subscriber.dart';
import '../services/auth_storage.dart';
import 'print_prefs.dart';
import 'print_service.dart';

/// خدمة طباعة الوصولات — تجمع (بيانات المشترك + عملية التفعيل/التسديد)
/// مع القالب المحفوظ من الويب وتفتح system print dialog.
///
/// المدير من الويب يحدّد شكل الوصل (HTML template)، والموبايل هنا يعبّئ
/// المتغيّرات ثم يستدعي PrintService.
class ReceiptService {
  ReceiptService._();

  /// طباعة وصل تفعيل. يُستدعى بعد نجاح /api/v2/subscribers/:idx/activate.
  /// يُفضَّل أن يُستدعى بأزرار "طباعة الوصل" في UI (بلا AUTO print).
  ///
  /// [paidAmount] = المبلغ المدفوع فعلاً (cash: كامل السعر، partial: الجزئي،
  /// debt: 0).
  /// [newExpiration] = تاريخ الانتهاء الجديد بعد التفعيل (لو معلوم — اختياري).
  static Future<bool> printActivationReceipt({
    required Subscriber sub,
    required num packagePrice,
    required num paidAmount,
    String? newExpiration,
    int? durationDays,
  }) async {
    final remaining = (packagePrice - paidAmount).clamp(0, double.infinity);
    final data = _buildActivationData(
      sub: sub,
      packagePrice: packagePrice,
      paidAmount: paidAmount,
      remainingAmount: remaining,
      newExpiration: newExpiration,
      durationDays: durationDays,
    );
    return _emitReceipt(
      data: data,
      title: 'فاتورة تفعيل',
      documentName: 'Activation-${sub.username}',
    );
  }

  /// طباعة وصل تسديد دين. يُستدعى بعد نجاح /api/v2/subscribers/:idx/pay-debt.
  ///
  /// [paidAmount] = المبلغ المسدّد الآن.
  /// [remainingDebt] = المتبقّي من الدين بعد التسديد (0 لو انتهى).
  static Future<bool> printDebtPaymentReceipt({
    required Subscriber sub,
    required num paidAmount,
    required num remainingDebt,
  }) async {
    final data = _buildDebtPaymentData(
      sub: sub,
      paidAmount: paidAmount,
      remainingDebt: remainingDebt,
    );
    return _emitReceipt(
      data: data,
      title: 'وصل تسديد دين',
      documentName: 'DebtPayment-${sub.username}',
    );
  }

  // ─── internal ──────────────────────────────────

  /// يفتح system print dialog. الاستراتيجيّة:
  /// 1. جيب قالب المدير المحفوظ من الويب (PrintTemplatesApi.byType).
  /// 2. لو موجود + فعّال: املأ placeholders في HTML وحاول convertHtml
  ///    (WebView-based) — يُعطي أفضل شكل مطابق تصميم الويب بالضبط.
  /// 3. لو convertHtml فشل (WebView crash) أو لا قالب: نلجأ لـPDF مبني
  ///    مباشرة بـpw widgets (يعمل على كل جهاز).
  ///
  /// اسم الشركة يُقرأ من AuthStorage (المدير حفظه عند login).
  static Future<bool> _emitReceipt({
    required Map<String, String> data,
    required String title,
    required String documentName,
  }) async {
    try {
      final type = PrintPrefs.currentTemplateType; // 'a4' | 'pos'
      final companyName = await AuthStorage.readDisplayName();
      final format = PrintService.formatForType(type);

      // Step 1: جيب قالب المدير المحفوظ (لو موجود + فعّال).
      final template = await PrintTemplatesApi.byType(type);
      if (template != null &&
          template.isActive &&
          template.content.trim().isNotEmpty) {
        // Step 2: املأ placeholders + جرّب convertHtml (يحترم تصميم الأدمن).
        final filled = PrintService.fillTemplate(template.content, data);
        final htmlOk = await PrintService.printHtml(
          html: filled,
          format: format,
          documentName: documentName,
        );
        if (htmlOk) return true;
        if (kDebugMode) {
          debugPrint(
              '[ReceiptService] HTML template فشل (WebView crash?) — fallback لـPDF مبني.');
        }
      }
      // Step 3: fallback — PDF مبني مباشرة (يعمل بلا WebView).
      return await PrintService.printReceipt(
        data: data,
        format: format,
        title: title,
        documentName: documentName,
        companyName:
            companyName?.trim().isNotEmpty == true ? companyName : null,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ReceiptService] error: $e');
      return false;
    }
  }

  static Map<String, String> _buildActivationData({
    required Subscriber sub,
    required num packagePrice,
    required num paidAmount,
    required num remainingAmount,
    String? newExpiration,
    int? durationDays,
  }) {
    final now = DateTime.now();
    DateTime expiry = _parseExpiration(newExpiration) ??
        (durationDays != null && durationDays > 0
            ? now.add(Duration(days: durationDays))
            : _addMonth(now));
    return {
      'invoice_number': _invoiceNumber(now),
      'date': _formatDate(now),
      'subscriber_name': _fullName(sub),
      'phone_number': (sub.phone ?? sub.mobile ?? '—').trim(),
      'package_name': (sub.profileName ?? '—').trim(),
      'package_price': _money(packagePrice),
      'paid_amount': _money(paidAmount),
      'remaining_amount': _money(remainingAmount),
      'expiry_date': _formatDate(expiry),
      'debt_amount': _money(sub.debt ?? 0),
    };
  }

  static Map<String, String> _buildDebtPaymentData({
    required Subscriber sub,
    required num paidAmount,
    required num remainingDebt,
  }) {
    final now = DateTime.now();
    return {
      'invoice_number': _invoiceNumber(now),
      'date': _formatDate(now),
      'subscriber_name': _fullName(sub),
      'phone_number': (sub.phone ?? sub.mobile ?? '—').trim(),
      'package_name': (sub.profileName ?? '—').trim(),
      'package_price': '—',
      'paid_amount': _money(paidAmount),
      'remaining_amount': _money(remainingDebt),
      'expiry_date': _formatExpirationOrDash(sub.expiration),
      'debt_amount': _money(remainingDebt),
    };
  }

  static String _invoiceNumber(DateTime now) {
    // NO-YYYYMMDDHHmmss — بسيط + تُنِس الترتيب الزمني
    final f = intl.DateFormat('yyyyMMddHHmmss');
    return 'NO-${f.format(now)}';
  }

  static String _fullName(Subscriber sub) {
    final n = '${sub.firstname} ${sub.lastname}'.trim();
    return n.isNotEmpty ? n : sub.username;
  }

  static String _money(num v) {
    final abs = v.abs().round();
    return intl.NumberFormat('#,###').format(abs);
  }

  static String _formatDate(DateTime dt) {
    return intl.DateFormat('yyyy-MM-dd HH:mm').format(dt);
  }

  static String _formatExpirationOrDash(String? s) {
    if (s == null || s.trim().isEmpty) return '—';
    final d = DateTime.tryParse(s.replaceAll(' ', 'T'));
    if (d == null) return s;
    return _formatDate(d.toLocal());
  }

  static DateTime? _parseExpiration(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    return DateTime.tryParse(s.replaceAll(' ', 'T'))?.toLocal();
  }

  static DateTime _addMonth(DateTime d) {
    final y = d.year + ((d.month) ~/ 12);
    final m = ((d.month) % 12) + 1;
    final day = d.day.clamp(1, _daysInMonth(y, m));
    return DateTime(y, m, day, d.hour, d.minute);
  }

  static int _daysInMonth(int year, int month) {
    final beginNext =
        (month == 12) ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    return beginNext.subtract(const Duration(days: 1)).day;
  }
}
