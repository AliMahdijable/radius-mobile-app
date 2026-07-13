import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// نوع الطابعة الافتراضية للـmobile receipts.
///   • pos → 80mm thermal (الأشهر بين المكاتب)
///   • a4  → طابعة A4 عادية
enum PrintFormatChoice { pos, a4 }

/// تفضيلات الطباعة — يقرّرها المدير مرة واحدة من الإعدادات. تُطبَّق على
/// كل زر "طباعة الوصل" بعد التفعيل/التسديد. لا نوقف الطباعة نهائيّاً —
/// المدير هو الذي يضغط الزر متى شاء (اختيار).
class PrintPrefs {
  PrintPrefs._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kFormat = 'app.print_format';

  /// الافتراضي POS — أكثر انتشاراً في مكاتب الاشتراك.
  static final ValueNotifier<PrintFormatChoice> notifier =
      ValueNotifier<PrintFormatChoice>(PrintFormatChoice.pos);

  static Future<void> load() async {
    final raw = await _storage.read(key: _kFormat);
    notifier.value = _decode(raw);
  }

  static Future<void> setFormat(PrintFormatChoice choice) async {
    notifier.value = choice;
    await _storage.write(key: _kFormat, value: _encode(choice));
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
}
