import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:rad_mysvcs/core/widgets/print_feedback.dart';
import 'package:rad_mysvcs/screens/print_templates/receipt_printer_sheet.dart';
import 'package:rad_mysvcs/services/print_output.dart';
import 'package:rad_mysvcs/services/receipt_printer/printer_bridge.dart';
import 'package:rad_mysvcs/services/receipt_printer/receipt_printer_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';
import 'support/fake_receipt_printer.dart';

/// «طابعة الوصولات» في الإعدادات (٩ نوفمبر) — الورقة بخطّ التطبيق وعرض الهاتف:
///   ١. الافتراضيّ «نافذة الطباعة» بلا زرّ تجربة؛ أندرويد بثلاث طرق، والآيفون بطريقتين (لا طابعة مدمجة) ووصف BLE.
///   ٢. البلوتوث: المقترنة (الطابعة أوّلاً) ⇒ اختيارٌ يُحفظ، والورق ٥٨/٨٠، و«طباعة تجريبيّة» ونتيجتها.
///   ٣. الإذن المرفوض والبلوتوث المطفأ ⇒ سببٌ مفهوم وزرّه.
///   ٤. طابعة الجهاز: «SUNMI … جاهزة · ورق ٨٠» وورقها يُعتمد؛ وبلاها سببٌ وتلميح InnerPrinter.
///   ٥. نتيجة طباعةٍ غير مؤكَّدة بعد التفعيل ⇒ ورقة «الطباعة غير مؤكَّدة» و«إعادة الطباعة» تطبع ثانيةً.
///   (مراجعة 179) الآيفون: البلوتوث المرفوض ⇒ «فتح الإعدادات» بكلمات الآيفون؛ الهاتف العاديّ: «طابعة الجهاز» معطّلةٌ بسببها
///   ولا تبقى مختارة؛ ورقة السبب: جوابها بنقرةٍ وحدها، والإعادة داخلها، وما بدأ منها يُنتظر ولو أُغلقت.

class _DiskLoader extends AssetLoader {
  const _DiskLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => Future.value(
        jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>,
      );
}

PrintDoc _sample() => PrintDoc(Uint8List.fromList(const [1]), PdfPageFormat.roll80, name: 'activation-ahmed01');

void main() {
  late ReceiptPrinterHarness h;

  setUpAll(() async {
    await loadAppFonts();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    h = ReceiptPrinterHarness();
  });

  tearDown(() => h.restore());

  Future<void> pumpApp(WidgetTester t, Widget Function(BuildContext) home) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('ar'), Locale('en')],
      path: 'assets/translations',
      startLocale: const Locale('ar'),
      fallbackLocale: const Locale('ar'),
      saveLocale: false,
      assetLoader: const _DiskLoader(),
      child: Builder(
        builder: (ctx) => MaterialApp(
          locale: ctx.locale,
          supportedLocales: ctx.supportedLocales,
          localizationsDelegates: ctx.localizationDelegates,
          home: Scaffold(body: Builder(builder: home)),
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  /// يفتح الورقة كما من الإعدادات (لكن بوصلٍ تجريبيّ لا يطلب الخادم).
  Future<void> openSheet(WidgetTester t) async {
    await pumpApp(
      t,
      (c) => Center(
        child: TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: c,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => ReceiptPrinterSheet(sampleBuilder: () async => _sample()),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(ValueKey(key));
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  testWidgets('١ أندرويد: الافتراضيّ نافذة الطباعة بلا زرّ تجربة، والطرق الثلاث بأسمائها', (t) async {
    await openSheet(t);
    expect(find.text('طابعة الوصولات'), findsOneWidget);
    expect(find.text('نافذة الطباعة'), findsOneWidget);
    expect(find.text('طابعة بلوتوث'), findsOneWidget);
    expect(find.text('طابعة الجهاز المدمجة'), findsOneWidget);
    expect(find.text('طباعة تجريبيّة'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('١ب الآيفون: بلا طابعة مدمجة، ووصف البلوتوث يقول BLE فقط', (t) async {
    ReceiptPrinterPrefs.debugIos = true;
    ReceiptPrinterPrefs.debugBuiltinSupported = false;
    await openSheet(t);
    expect(find.text('طابعة الجهاز المدمجة'), findsNothing);
    expect(find.text('على الآيفون: الطابعات التي تدعم بلوتوث BLE فقط'), findsOneWidget);
    // اختيار البلوتوث يبحث (الآيفون لا يعرف «المقترنة»)
    await tapKey(t, 'receipt-mode-bluetooth');
    expect(h.bridge.calls, contains('scan'));
    await tapKey(t, 'receipt-device-6F1C2D3E-0000-0000-0000-000000000001');
    expect(ReceiptPrinterPrefs.device.value!.ble, isTrue);
    expect(ReceiptPrinterPrefs.device.value!.name, 'Printer001');
  });

  testWidgets('٢ البلوتوث: المقترنة ⇒ اختيار ⇒ ورق ٨٠ ⇒ طباعة تجريبيّة «أُرسل»', (t) async {
    await openSheet(t);
    await tapKey(t, 'receipt-mode-bluetooth');
    expect(h.permission.asked, greaterThanOrEqualTo(1), reason: 'الإذن يُطلب لحظة اختيار البلوتوث');
    expect(ReceiptPrinterPrefs.mode.value, ReceiptPrinterMode.bluetooth);
    expect(find.text('MPT-II'), findsOneWidget);
    expect(find.text('Headset'), findsOneWidget);
    final printer = t.getTopLeft(find.text('MPT-II'));
    final other = t.getTopLeft(find.text('Headset'));
    expect(printer.dy, lessThan(other.dy), reason: 'الطابعة أوّلاً');
    // بلا طابعة مختارة: زرّ التجربة معطّل
    expect(ReceiptPrinterPrefs.enabled, isFalse);
    await tapKey(t, 'receipt-device-AA:BB:CC:DD:EE:01');
    expect(ReceiptPrinterPrefs.device.value!.id, 'AA:BB:CC:DD:EE:01');
    expect(ReceiptPrinterPrefs.enabled, isTrue);
    await t.ensureVisible(find.text('80 ملم'));
    await t.tap(find.text('80 ملم'));
    await t.pumpAndSettle();
    expect(ReceiptPrinterPrefs.paper.value, ReceiptPaper.mm80);
    await t.runAsync(() async {
      await t.tap(find.text('طباعة تجريبيّة'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(h.bridge.receiptWrites, isNotEmpty);
    expect(h.renders.single, ReceiptPaper.mm80);
    expect(find.textContaining('أُرسل الوصل التجريبيّ'), findsOneWidget);
    // حُفظ في الخزنة
    ReceiptPrinterPrefs.reset();
    await ReceiptPrinterPrefs.load();
    expect(ReceiptPrinterPrefs.device.value!.name, 'MPT-II');
    expect(ReceiptPrinterPrefs.paper.value, ReceiptPaper.mm80);
  });

  testWidgets('٢ب طابعةٌ تؤكّد ⇒ «تأكّدت الطباعة»؛ انقطاعٌ أثناء الإرسال ⇒ «غير مؤكَّدة»', (t) async {
    h.useBluetooth();
    ReceiptPrinterPrefs.mode.value = ReceiptPrinterMode.bluetooth;
    h.bridge
      ..replyRealtime4 = [0x12]
      ..replyRealtime2 = [0x12]
      ..replyPaperInSequence = [0x00];
    await openSheet(t);
    await t.runAsync(() async {
      await t.tap(find.text('طباعة تجريبيّة'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(find.textContaining('تأكّدت الطباعة'), findsOneWidget);
    h.bridge
      ..replyRealtime4 = null
      // الكتابات التالية: سؤال الورق (بلا ردّ) · ESC @ · الشريط الأوّل · الثاني ← ينقطع هنا
      ..dropAtWrite = h.bridge.writes.length + 4;
    await t.runAsync(() async {
      await t.tap(find.text('طباعة تجريبيّة'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(find.textContaining('الطباعة غير مؤكَّدة'), findsOneWidget);
    expect(find.textContaining('أثناء الإرسال'), findsOneWidget);
  });

  testWidgets('٣ الإذن مرفوض ⇒ سببه و«حاول ثانيةً»؛ البلوتوث مطفأ ⇒ «إعدادات البلوتوث»', (t) async {
    h.permission.permit = BtPermit.denied;
    await openSheet(t);
    await tapKey(t, 'receipt-mode-bluetooth');
    expect(find.byKey(const ValueKey('receipt-printer-issue')), findsOneWidget);
    expect(find.textContaining('اسمح للتطبيق باستخدام البلوتوث'), findsOneWidget);
    expect(find.text('حاول ثانيةً'), findsOneWidget);
    h.permission.permit = BtPermit.granted;
    h.bridge.state = const BtState(supported: true, enabled: false);
    await t.tap(find.text('حاول ثانيةً'));
    await t.pumpAndSettle();
    expect(find.textContaining('البلوتوث مطفأ'), findsOneWidget);
    await t.tap(find.text('إعدادات البلوتوث'));
    await t.pumpAndSettle();
    expect(h.bridge.calls, contains('settings'));
  });

  testWidgets('٣ج الآيفون: البلوتوث مرفوضٌ للتطبيق ⇒ كلمات الآيفون و«فتح الإعدادات» يفتحها (لا «حاول ثانيةً» وحدها)', (t) async {
    ReceiptPrinterPrefs.debugIos = true;
    ReceiptPrinterPrefs.debugBuiltinSupported = false;
    h.bridge.state = const BtState(supported: true, enabled: true, authorized: false);
    await openSheet(t);
    await tapKey(t, 'receipt-mode-bluetooth');
    expect(find.byKey(const ValueKey('receipt-printer-issue')), findsOneWidget);
    expect(find.textContaining('افتح الإعدادات ← التطبيق ← فعّل «البلوتوث»'), findsOneWidget);
    expect(find.textContaining('الأجهزة المجاورة'), findsNothing);
    await t.tap(find.text('فتح الإعدادات'));
    await t.pumpAndSettle();
    expect(h.permission.opened, 1);
  });

  testWidgets('٣د الآيفون بعد وصل: ورقة السبب «فتح الإعدادات» بنقرته وحدها — «إغلاق» لا يفتح شيئاً', (t) async {
    ReceiptPrinterPrefs.debugIos = true;
    final r = PrintResult.failed(
      'bt: unauthorized',
      printer: 'MPT-II',
      issue: PrintIssue.permissionBlocked,
      retry: () async => const PrintResult.cancelled(),
    );
    await pumpApp(
      t,
      (c) => Center(child: TextButton(onPressed: () => showPrintResult(c, r), child: const Text('done'))),
    );
    await t.tap(find.text('done'));
    await t.pumpAndSettle();
    expect(find.textContaining('افتح الإعدادات ← التطبيق'), findsOneWidget);
    await t.tap(find.text('إغلاق'));
    await t.pumpAndSettle();
    expect(h.permission.opened, 0);
    await t.tap(find.text('done'));
    await t.pumpAndSettle();
    await t.tap(find.text('فتح الإعدادات'));
    await t.pumpAndSettle();
    expect(h.permission.opened, 1);
    await t.pump(const Duration(seconds: 7));
  });

  testWidgets('٣ب لا مقترنة ⇒ شرح الإقران (الرمز 0000/1234) وزرّ إعدادات البلوتوث', (t) async {
    h.bridge.paired = const [];
    await openSheet(t);
    await tapKey(t, 'receipt-mode-bluetooth');
    expect(find.byKey(const ValueKey('receipt-printer-empty')), findsOneWidget);
    expect(find.textContaining('0000 أو 1234'), findsOneWidget);
  });

  testWidgets('٤ طابعة الجهاز: SUNMI جاهزة بورق ٨٠ ⇒ يُعتمد ورقها؛ وبلاها تلميح InnerPrinter', (t) async {
    h.bridge.builtin =
        const BuiltinInfo(available: true, vendor: 'sunmi', status: 1, paperMm: 80, model: 'SUNMI T2');
    await openSheet(t);
    await tapKey(t, 'receipt-mode-builtin');
    expect(find.text('«SUNMI T2» جاهزة · ورق 80 ملم'), findsOneWidget);
    expect(ReceiptPrinterPrefs.paper.value, ReceiptPaper.mm80);
    expect(ReceiptPrinterPrefs.enabled, isTrue);
    h.bridge.builtin = const BuiltinInfo(available: false);
    await t.ensureVisible(find.text('إعادة الفحص'));
    await t.pumpAndSettle();
    await t.tap(find.text('إعادة الفحص'));
    await t.pumpAndSettle();
    expect(find.textContaining('InnerPrinter'), findsOneWidget);
  });

  testWidgets('٥ بعد التفعيل: «غير مؤكَّدة» ⇒ ورقةٌ بإعادة الطباعة تطبع ثانيةً', (t) async {
    var retried = 0;
    final r = PrintResult.failed(
      'bt: io',
      printer: 'MPT-II',
      issue: PrintIssue.disconnectedMidway,
      retry: () async {
        retried++;
        return const PrintResult.printed(printer: 'MPT-II', ack: PrintAck.confirmed);
      },
    );
    await pumpApp(
      t,
      (c) => Center(child: TextButton(onPressed: () => showPrintResult(c, r), child: const Text('done'))),
    );
    await t.tap(find.text('done'));
    await t.pumpAndSettle();
    expect(find.text('الطباعة غير مؤكَّدة'), findsOneWidget);
    expect(find.textContaining('قد يكون خرج جزءٌ من الوصل'), findsOneWidget);
    await t.tap(find.text('إعادة الطباعة'));
    await t.pumpAndSettle();
    expect(retried, 1);
    expect(find.text('طُبع الوصل على «MPT-II» — أكّدت الطابعة'), findsOneWidget);
    // الإشعار وتشخيص الفشل (مهلته ٦ ث) ينقضيان
    await t.pump(const Duration(seconds: 7));
  });
  testWidgets('٥ب إعادةٌ تفشل ثانيةً ⇒ الورقة نفسها بسببها الجديد و«أعدنا المحاولة»؛ ثمّ تُغلق بلا طباعةٍ أخرى', (t) async {
    var retried = 0;
    late PrintResult again;
    again = PrintResult.failed(
      'bt: connect',
      printer: 'MPT-II',
      issue: PrintIssue.connectFailed,
      retry: () async {
        retried++;
        return again;
      },
    );
    final r = PrintResult.failed(
      'bt: io',
      printer: 'MPT-II',
      issue: PrintIssue.disconnectedMidway,
      retry: () async {
        retried++;
        return again;
      },
    );
    var finished = false;
    await pumpApp(
      t,
      (c) => Center(
        child: TextButton(
          onPressed: () async {
            await showPrintResult(c, r);
            finished = true;
          },
          child: const Text('done'),
        ),
      ),
    );
    await t.tap(find.text('done'));
    await t.pumpAndSettle();
    await t.tap(find.text('إعادة الطباعة'));
    await t.pumpAndSettle();
    expect(retried, 1);
    expect(find.text('لم يُطبع الوصل'), findsOneWidget);
    expect(find.textContaining('تعذّر الاتصال بالطابعة «MPT-II»'), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-problem-again')), findsOneWidget);
    expect(find.text('حاول مرّة ثانية'), findsOneWidget);
    expect(finished, isFalse, reason: 'من فتحها ينتظر قرار الوكيل');
    await t.tap(find.text('إغلاق'));
    await t.pumpAndSettle();
    expect(retried, 1);
    expect(finished, isTrue);
    await t.pump(const Duration(seconds: 7));
  });

  testWidgets('٥ج أُغلقت الورقة أثناء الإعادة ⇒ من فتحها ينتظرها ويقول نتيجتها (لا ضياع ولا إعادةٌ ثانية)', (t) async {
    var retried = 0;
    final gate = Completer<PrintResult>();
    final r = PrintResult.failed(
      'bt: io',
      printer: 'MPT-II',
      issue: PrintIssue.disconnectedMidway,
      retry: () {
        retried++;
        return gate.future;
      },
    );
    var finished = false;
    await pumpApp(
      t,
      (c) => Center(
        child: TextButton(
          onPressed: () async {
            await showPrintResult(c, r);
            finished = true;
          },
          child: const Text('done'),
        ),
      ),
    );
    await t.tap(find.text('done'));
    await t.pumpAndSettle();
    await t.tap(find.text('إعادة الطباعة'));
    await t.pump();
    expect(retried, 1);
    // يُغلقها الوكيل والإعادة جارية
    await t.tap(find.text('إغلاق'));
    await t.pumpAndSettle();
    expect(find.text('الطباعة غير مؤكَّدة'), findsNothing);
    expect(finished, isFalse, reason: 'الإعادة الجارية تُنتظر');
    gate.complete(const PrintResult.printed(printer: 'MPT-II', ack: PrintAck.confirmed));
    await t.pumpAndSettle();
    expect(finished, isTrue);
    expect(find.text('طُبع الوصل على «MPT-II» — أكّدت الطابعة'), findsOneWidget);
    expect(retried, 1);
    await t.pump(const Duration(seconds: 7));
  });
}
