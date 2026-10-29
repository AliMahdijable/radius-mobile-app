import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../api/company_route.dart';
import '../api/receipt_settings_api.dart';
import '../api/sales_api.dart';
import 'print_output.dart';
import 'print_prefs.dart';
import 'receipt_pdf.dart';
import 'receipt_service.dart';

/// فاتورة البيع (قسم «المبيعات») — بتصميم وصل النظام نفسه ([ReceiptPdf] و«قوالب الطباعة» في الموقع: الشعار والترويسة
/// والأقسام الظاهرة والتذييل وعرض الورق). المالك ٢٩ أكتوبر: «الفاتورة نسوي الها تصميم خاص بقسم المبيعات اشبه بفاتورة
/// النظام… يعني نفسه الفاتورة لكن تصير مبيعات». بلا أرشفة: البيع محفوظٌ في جدوله برقمه (رقم الفاتورة). المُلغى بختم
/// «مُلغاة» وسببه.
class SalePrint {
  SalePrint._();

  /// [companyKey] شركة البيع في «كل الشركات» (تصميمها واسمها هي)؛ بلاه الجلسة المفتوحة.
  static Future<PrintResult> printReceipt(Sale s, {String? companyKey}) async {
    try {
      final settingsF = CompanyRoute.run(companyKey, ReceiptSettingsApi.fetch);
      final id = await ReceiptService.identityFor(companyKey);
      final look = await settingsF ?? const ReceiptSettings();
      final d = doc(s, look: look, shop: look.shopName ?? id.shop, issuer: id.issuer);
      return PrintOutput.send(await ReceiptPdf.build(d, a4: PrintPrefs.currentTemplateType == 'a4'));
    } catch (e) {
      if (kDebugMode) debugPrint('[SalePrint] failed: $e');
      return PrintResult.failed('$e');
    }
  }

  static String _qty(num q) {
    if (q == q.roundToDouble()) return q.round().toString();
    var s = q.toStringAsFixed(3);
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
  }

  static String customerOf(Sale s) {
    if (s.customerKind == 'subscriber') {
      final parts = [s.customerName, s.username].whereType<String>().where((x) => x.trim().isNotEmpty).toList();
      return parts.isEmpty ? 'مشترك' : parts.join(' — ');
    }
    final n = (s.customerName ?? '').trim();
    return n.isEmpty ? 'زبون' : n;
  }

  /// الفاتورة وصلاً ([ReceiptKind.sale]) — منفصلةٌ عن الشبكة والطابعة (تُختبر وحدها). «أصدره» البائع إن كان موظّفاً.
  static ReceiptDoc doc(Sale s, {ReceiptSettings look = const ReceiptSettings(), required String shop, String? issuer}) {
    final sub = s.customerKind == 'subscriber';
    final name = (s.customerName ?? '').trim();
    final user = (s.username ?? '').trim();
    final phone = (s.phone ?? '').trim();
    final by = (s.by ?? '').trim();
    return ReceiptDoc(
      kind: ReceiptKind.sale,
      issuedAt: s.createdAt ?? DateTime.now(),
      look: look,
      shopName: shop,
      subscriberName: name.isNotEmpty ? name : (sub ? (user.isEmpty ? 'مشترك' : user) : 'زبون'),
      username: sub ? user : '',
      phone: phone.isEmpty ? null : phone,
      issuer: s.employeeId != null && by.isNotEmpty ? by : issuer,
      sale: SaleInvoiceDoc(
        id: s.id,
        lines: [
          for (final l in s.lines)
            (name: l.name, qty: '${_qty(l.qty)} ${saleUnitLabel(l.unit)}', unitPrice: l.unitPrice, total: l.total),
        ],
        total: s.total,
        debt: s.isDebt,
        note: s.note,
        voided: s.isVoid,
        voidReason: s.voidReason,
      ),
    );
  }

  /// PDF الفاتورة بورقٍ ما — للاختبار ([fonts] = false: Helvetica بلا تحميل خطّ).
  @visibleForTesting
  static Future<Uint8List> build(Sale s, PdfPageFormat format, {String? company, bool fonts = true}) async {
    final d = doc(s, shop: (company ?? '').trim().isEmpty ? 'MyServices' : company!.trim());
    final theme = fonts ? null : pw.ThemeData.withFont(base: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
    return (await ReceiptPdf.build(d, a4: format.width > PdfPageFormat.roll80.width + 5, theme: theme)).bytes;
  }
}
