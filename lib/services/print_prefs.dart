import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pdf/pdf.dart';

import '../core/platform/app_platform.dart';

/// نوع الطابعة الافتراضية للـmobile receipts.
///   • pos → 80mm thermal (الأشهر بين المكاتب)
///   • a4  → طابعة A4 عادية
enum PrintFormatChoice { pos, a4 }

/// «الطابعة المباشرة» المحفوظة على الحاسبة: يُرسَل إليها الوصل بلا نافذة طباعة.
/// [url] معرّفها عند النظام (اسمها على ويندوز والماك).
@immutable
class SavedPrinter {
  const SavedPrinter({required this.url, required this.name});

  final String url;
  final String name;

  String encode() => jsonEncode({'url': url, 'name': name});

  static SavedPrinter? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      final url = m is Map ? '${m['url'] ?? ''}' : '';
      if (url.isEmpty) return null;
      final name = '${m['name'] ?? ''}';
      return SavedPrinter(url: url, name: name.isEmpty ? url : name);
    } catch (_) {
      return null;
    }
  }
}

/// تفضيلات الطباعة — يقرّرها المدير مرة واحدة من الإعدادات. تُطبَّق على
/// كل زر "طباعة الوصل" بعد التفعيل/التسديد. لا نوقف الطباعة نهائيّاً —
/// المدير هو الذي يضغط الزر متى شاء (اختيار).
class PrintPrefs {
  PrintPrefs._();

  static const _storage = FlutterSecureStorage(
    // ٢٠٢٦-٠٩-٢٢: `encryptedSharedPreferences` أُهمل في 10.x (‏Google
    // أهملت Jetpack Security) ويُزال في 11. والهجرة إلى التشفير
    // الجديد تجري تلقائيّاً عند أوّل قراءة.
    aOptions: AndroidOptions(
      // ٢٠٢٦-٠٩-٢٢ — `resetOnError` انقلب افتراضيّاً في 10.x من false إلى
      // true، وDart يرسله دائماً فلا تُقرأ قيمة جافا الافتراضيّة أبداً.
      // معناه أنّ أيّ خطأ قراءةٍ عابر يحذف المفتاح بدل أن يُبلّغ عنه —
      // فيتحوّل عطلٌ مؤقّت إلى فقدٍ دائمٍ صامت. نُبقي سلوك 9.2.4.
      resetOnError: false,
    ),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kFormat = 'app.print_format';
  static const _kPrinter = 'app.print_printer';
  static const _kSaleInvoice = 'app.sale_invoice';

  /// «إصدار فاتورة» بعد البيع (قسم المبيعات) — اختياريٌّ ويُحفظ على الجهاز (المالك ٢٩ أكتوبر: «بيع المادة بيها
  /// اصدار فاتورة اختياري»).
  static final ValueNotifier<bool> saleInvoice = ValueNotifier<bool>(false);

  /// الافتراضي POS — أكثر انتشاراً في مكاتب الاشتراك.
  static final ValueNotifier<PrintFormatChoice> notifier =
      ValueNotifier<PrintFormatChoice>(PrintFormatChoice.pos);

  /// «الطابعة المباشرة» (الحاسبة) — null = نافذة الطباعة كلّ مرّة.
  static final ValueNotifier<SavedPrinter?> printer = ValueNotifier<SavedPrinter?>(null);

  /// الطباعة بلا نافذة للحاسبة وحدها: أندرويد لا يسمح بها أصلاً، ومكتبة الطباعة (5.14) على
  /// آيفون تُرسل للطابعة المختارة قبل أن يُبنى المستند فتخرج ورقةٌ فارغة.
  static bool get directSupported => AppPlatform.isDesktop;

  static Future<void> load() async {
    // ٢٠٢٦-٠٩-٢٢ — انظر ThemeService.load: قراءةٌ ترمي داخل Future.wait
    // في main تُسقط الإقلاع كلّه. قالب الطباعة يُستبدل بالافتراضيّ.
    try {
      final raw = await _storage.read(key: _kFormat);
      notifier.value = _decode(raw);
    } catch (_) {
      notifier.value = _decode(null);
    }
    try {
      printer.value = SavedPrinter.decode(await _storage.read(key: _kPrinter));
    } catch (_) {
      printer.value = null;
    }
    try {
      saleInvoice.value = await _storage.read(key: _kSaleInvoice) == '1';
    } catch (_) {
      saleInvoice.value = false;
    }
  }

  static Future<void> setSaleInvoice(bool on) async {
    saleInvoice.value = on;
    try {
      await _storage.write(key: _kSaleInvoice, value: on ? '1' : '0');
    } catch (_) {
      // تفضيلٌ لا يُحفظ لا يُسقط البيع — يبقى للجلسة.
    }
  }

  static Future<void> setFormat(PrintFormatChoice choice) async {
    notifier.value = choice;
    await _storage.write(key: _kFormat, value: _encode(choice));
  }

  static Future<void> setPrinter(SavedPrinter? p) async {
    printer.value = p;
    if (p == null) {
      await _storage.delete(key: _kPrinter);
    } else {
      await _storage.write(key: _kPrinter, value: p.encode());
    }
  }

  static String _encode(PrintFormatChoice c) => c.name;

  static PrintFormatChoice _decode(String? raw) {
    switch (raw) {
      case 'a4':
        return PrintFormatChoice.a4;
      case 'pos':
      default:
        return PrintFormatChoice.pos;
    }
  }

  /// اختصار: قيمة templateType المطابقة للـchoice الحالي.
  static String get currentTemplateType =>
      notifier.value == PrintFormatChoice.a4 ? 'a4' : 'pos';

  /// ورق الوصولات والسندات: لفّة الكاشير (عرضها ٨٠ ملم وطولها طول المحتوى) أو A4.
  static PdfPageFormat get pageFormat =>
      notifier.value == PrintFormatChoice.a4 ? PdfPageFormat.a4 : PdfPageFormat.roll80;
}
