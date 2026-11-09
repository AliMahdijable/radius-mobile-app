import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pdf/pdf.dart';

/// كيف يخرج الوصل من الهاتف (الإعدادات ← الطباعة ← «طابعة الوصولات»).
enum ReceiptPrinterMode {
  /// نافذة الطباعة (أو «صورة») — الافتراضيّ، كما كان قبل ٩ نوفمبر.
  system,

  /// طابعة كاشير حراريّة (ESC/POS) عبر البلوتوث — أندرويد: المقترنة بالهاتف؛ آيفون: التي تدعم BLE.
  bluetooth,

  /// طابعة الجهاز المدمجة (أجهزة الكاشير بأندرويد — SUNMI الآن).
  builtin,
}

/// عرض ورق الطابعة الحراريّة ونقاط رأسها (٢٠٣ نقطة في الإنش = ٨ نقاط لكلّ ملم).
enum ReceiptPaper {
  /// ٥٨ ملم: الرأس ٤٨ ملم = ٣٨٤ نقطة، وحافّةٌ غير مطبوعة ٥ ملم من كلّ جانب.
  mm58(58, 384, 5),

  /// ٨٠ ملم: الرأس ٧٢ ملم = ٥٧٦ نقطة، والحافّة ٤ ملم.
  mm80(80, 576, 4);

  const ReceiptPaper(this.mm, this.dots, this.sideMm);

  final int mm;
  final int dots;
  final int sideMm;

  static const int dotsPerMm = 8;

  /// دقّة الرسم: ٨ نقاط لكلّ ملم.
  static const double dpi = dotsPerMm * 25.4;

  /// نصف ملم (٤ نقاط) داخل الرأس من كلّ جانب: رأسٌ لا يتوسّط الورق تماماً يقصّ أوّل نقطةٍ وآخرها.
  static const double safetyMm = 0.5;

  /// ورق الوصل كما تراه [ReceiptPdf.build]: عرضه كاملاً وطوله طول المحتوى، والحافّتان غير المطبوعتين (وهامش الأمان)
  /// حواشٍ دنيا — حواشي المصمّم الأكبر تبقى كما هي.
  PdfPageFormat get pageFormat => PdfPageFormat(
        mm * PdfPageFormat.mm,
        double.infinity,
        marginLeft: (sideMm + safetyMm) * PdfPageFormat.mm,
        marginRight: (sideMm + safetyMm) * PdfPageFormat.mm,
      );

  /// أوّل عمودٍ مطبوع في صورة الورق كاملاً.
  int get leftDots => sideMm * dotsPerMm;

  static ReceiptPaper decode(String? raw) => raw == '80' ? mm80 : mm58;

  String encode() => '$mm';
}

/// طابعة البلوتوث المحفوظة.
@immutable
class SavedReceiptPrinter {
  const SavedReceiptPrinter({required this.id, required this.name, this.ble = false});

  /// أندرويد: عنوانها (MAC)؛ آيفون: معرّفها عند الهاتف.
  final String id;
  final String name;

  /// على الآيفون: BLE (أندرويد: البلوتوث المعتاد SPP).
  final bool ble;

  String encode() => jsonEncode({'id': id, 'name': name, if (ble) 'ble': true});

  static SavedReceiptPrinter? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final id = '${m['id'] ?? ''}'.trim();
      if (id.isEmpty) return null;
      final name = '${m['name'] ?? ''}'.trim();
      return SavedReceiptPrinter(id: id, name: name.isEmpty ? id : name, ble: m['ble'] == true);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SavedReceiptPrinter && other.id == id && other.name == name && other.ble == ble;

  @override
  int get hashCode => Object.hash(id, name, ble);
}

/// خيار «اطبع على …» في نافذة «صورة أم طباعة».
@immutable
class ReceiptPrinterChoice {
  const ReceiptPrinterChoice({required this.mode, required this.name, required this.paper});

  final ReceiptPrinterMode mode;

  /// اسم طابعة البلوتوث؛ فارغٌ لطابعة الجهاز (يُسمّى في الواجهة).
  final String name;
  final ReceiptPaper paper;
}

/// تفضيل «طابعة الوصولات» على هذا الجهاز — يُحفظ في خزنة التطبيق كاختيار A4/الكاشير.
class ReceiptPrinterPrefs {
  ReceiptPrinterPrefs._();

  static const _storage = FlutterSecureStorage(
    // كـ[PrintPrefs]: خطأ قراءةٍ عابر لا يمحو التفضيل.
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kMode = 'app.receipt_printer.mode';
  static const _kDevice = 'app.receipt_printer.device';
  static const _kPaper = 'app.receipt_printer.paper';

  @visibleForTesting
  static bool? debugSupported;

  @visibleForTesting
  static bool? debugBuiltinSupported;

  @visibleForTesting
  static bool? debugIos;

  /// الهاتف وحده (أندرويد/آيفون) — الحاسبة والويب كما كانا: «الطباعة المباشرة» هناك طابعة النظام.
  static bool get supported => debugSupported ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

  /// طابعة الجهاز المدمجة: أندرويد وحده (SUNMI وأمثالها).
  static bool get builtinSupported => debugBuiltinSupported ?? (!kIsWeb && Platform.isAndroid);

  /// الآيفون: لا بلوتوث «عاديّ» للتطبيقات (SPP لأجهزة MFi وحدها) — الطابعات التي تدعم BLE فقط.
  static bool get isIos => debugIos ?? (!kIsWeb && Platform.isIOS);

  static final ValueNotifier<ReceiptPrinterMode> mode = ValueNotifier<ReceiptPrinterMode>(ReceiptPrinterMode.system);
  static final ValueNotifier<SavedReceiptPrinter?> device = ValueNotifier<SavedReceiptPrinter?>(null);
  static final ValueNotifier<ReceiptPaper> paper = ValueNotifier<ReceiptPaper>(ReceiptPaper.mm58);

  /// هل في **هذا** الجهاز خدمة طابعةٍ مدمجة؟ كما قالها آخر فحص (للجلسة، لا يُحفظ): null = لم يُفحص بعد، false =
  /// لا (هاتفٌ عاديّ) ⇒ «طابعة الجهاز المدمجة» لا تُختار ولا تبقى مختارة. لا فحص عند الإقلاع: الإعدادات والطباعة.
  static final ValueNotifier<bool?> builtinPresent = ValueNotifier<bool?>(null);

  /// أيّ تغيير في الطريقة والطابعة والورق — ونتيجة فحص طابعة الجهاز.
  static Listenable get changes => Listenable.merge([mode, device, paper, builtinPresent]);

  /// هل يذهب الوصل لطابعة الوصولات؟ الهاتف + طريقةٌ غير النافذة + طابعةٌ مختارة.
  static bool get enabled {
    if (!supported) return false;
    return switch (mode.value) {
      ReceiptPrinterMode.system => false,
      ReceiptPrinterMode.bluetooth => device.value != null,
      ReceiptPrinterMode.builtin => builtinSupported && builtinPresent.value != false,
    };
  }

  /// خيار «اطبع على …» — null حين لا طابعة وصولات (فتبقى النافذة كما كانت).
  static ReceiptPrinterChoice? get choice {
    if (!enabled) return null;
    return ReceiptPrinterChoice(
      mode: mode.value,
      name: mode.value == ReceiptPrinterMode.bluetooth ? device.value!.name : '',
      paper: paper.value,
    );
  }

  static Future<void> load() async {
    if (!supported) {
      reset();
      return;
    }
    try {
      final raw = await _storage.read(key: _kMode);
      mode.value = ReceiptPrinterMode.values.firstWhere((m) => m.name == raw, orElse: () => ReceiptPrinterMode.system);
    } catch (_) {
      mode.value = ReceiptPrinterMode.system;
    }
    if (mode.value == ReceiptPrinterMode.builtin && !builtinSupported) mode.value = ReceiptPrinterMode.system;
    try {
      device.value = SavedReceiptPrinter.decode(await _storage.read(key: _kDevice));
    } catch (_) {
      device.value = null;
    }
    try {
      paper.value = ReceiptPaper.decode(await _storage.read(key: _kPaper));
    } catch (_) {
      paper.value = ReceiptPaper.mm58;
    }
  }

  static Future<void> setMode(ReceiptPrinterMode m) async {
    mode.value = m;
    await _write(_kMode, m.name);
  }

  static Future<void> setDevice(SavedReceiptPrinter? d) async {
    device.value = d;
    await _write(_kDevice, d?.encode());
  }

  static Future<void> setPaper(ReceiptPaper p) async {
    paper.value = p;
    await _write(_kPaper, p.encode());
  }

  /// نتيجة فحص طابعة الجهاز ([present] = في الجهاز خدمة طابعةٍ مدمجة). غيابها وهي مختارة ⇒ تعود «نافذة الطباعة» وتُحفظ.
  static Future<void> setBuiltinPresent(bool present) async {
    builtinPresent.value = present;
    if (!present && mode.value == ReceiptPrinterMode.builtin) await setMode(ReceiptPrinterMode.system);
  }

  /// تفضيلٌ لا يُحفظ لا يُسقط شيئاً — يبقى للجلسة.
  static Future<void> _write(String key, String? value) async {
    try {
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } catch (_) {}
  }

  @visibleForTesting
  static void reset() {
    mode.value = ReceiptPrinterMode.system;
    device.value = null;
    paper.value = ReceiptPaper.mm58;
    builtinPresent.value = null;
  }
}
