import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:rad_mysvcs/api/settlements_api.dart';
import 'package:rad_mysvcs/services/phone_output.dart';
import 'package:rad_mysvcs/services/print_output.dart';
import 'package:rad_mysvcs/services/receipt_pdf.dart';
import 'package:rad_mysvcs/services/receipt_printer/escpos.dart';
import 'package:rad_mysvcs/services/receipt_printer/receipt_printer_prefs.dart';
import 'package:rad_mysvcs/services/receipt_printer/thermal_render.dart';
import 'package:rad_mysvcs/services/settlement_print.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_receipt_printer.dart';

/// «طابعة الوصولات» (٩ نوفمبر) — النظام القائم كما كان، والجديد اختياريّ:
///   ١. الإعداد يُحفظ ويُقرأ؛ الافتراضيّ نافذة الطباعة؛ الحاسبة لا ترى الجديد ولو بقي محفوظاً.
///   ٢. التوجيه: بلا طابعة وصولات ⇒ نافذة الطباعة حرفاً؛ معها ⇒ الطابعة؛ التقارير (A4) ⇒ النافذة دائماً.
///   ٣. نافذة «صورة أم طباعة» بالهاتف: الخياران كما كانا، و«اطبع على …» أوّلاً حين تُختار طابعة — و«طباعة أو PDF»
///      تبقى نافذة النظام.
///   ٤. الصورة للطابعة: لفّةٌ بعرض الورق (ولو كان الاختيار A4)، مرسومةٌ بـ٨ نقاط/ملم ومقصوصةٌ لعرض الرأس.

class _Backend implements PrintBackend {
  final calls = <String>[];

  @override
  Future<bool> layout(PrintDoc doc) async {
    calls.add('layout');
    return true;
  }

  @override
  Future<bool> direct(Printer printer, PrintDoc doc) async {
    calls.add('direct');
    return true;
  }

  @override
  Future<List<Printer>> printers() async => const [];
}

PrintDoc _doc(String name) => PrintDoc(Uint8List.fromList(const [1]), PdfPageFormat.roll80, name: name);

/// عرض الصفحة الأولى وطولها (نقطة PDF) من PDF غير مضغوط.
(double, double) _mediaBox(Uint8List pdf) {
  final m = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]').firstMatch(latin1.decode(pdf))!;
  return (double.parse(m.group(1)!), double.parse(m.group(2)!));
}

class _DiskLoader extends AssetLoader {
  const _DiskLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => Future.value(
        jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>,
      );
}

void main() {
  late ReceiptPrinterHarness h;
  late _Backend backend;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    h = ReceiptPrinterHarness();
    backend = _Backend();
    PrintOutput.backend = backend;
  });

  tearDown(() {
    h.restore();
    PhoneOutput.debugActive = null;
    PhoneOutput.navigatorKey = null;
    ReceiptPdf.debugCompress = true;
  });

  group('١ الإعداد', () {
    test('خزنةٌ فارغة ⇒ نافذة الطباعة، بلا طابعة، ورق ٥٨ — والجديد مطفأ', () async {
      await ReceiptPrinterPrefs.load();
      expect(ReceiptPrinterPrefs.mode.value, ReceiptPrinterMode.system);
      expect(ReceiptPrinterPrefs.device.value, isNull);
      expect(ReceiptPrinterPrefs.paper.value, ReceiptPaper.mm58);
      expect(ReceiptPrinterPrefs.enabled, isFalse);
      expect(ReceiptPrinterPrefs.choice, isNull);
    });

    test('يُحفظ ويُقرأ بعد إعادة التشغيل (الطريقة والطابعة والورق)', () async {
      await ReceiptPrinterPrefs.setMode(ReceiptPrinterMode.bluetooth);
      await ReceiptPrinterPrefs.setDevice(const SavedReceiptPrinter(id: 'AA:BB:CC:DD:EE:01', name: 'MPT-II'));
      await ReceiptPrinterPrefs.setPaper(ReceiptPaper.mm80);
      ReceiptPrinterPrefs.reset();
      expect(ReceiptPrinterPrefs.enabled, isFalse);
      await ReceiptPrinterPrefs.load();
      expect(ReceiptPrinterPrefs.mode.value, ReceiptPrinterMode.bluetooth);
      expect(ReceiptPrinterPrefs.device.value, const SavedReceiptPrinter(id: 'AA:BB:CC:DD:EE:01', name: 'MPT-II'));
      expect(ReceiptPrinterPrefs.paper.value, ReceiptPaper.mm80);
      expect(ReceiptPrinterPrefs.enabled, isTrue);
      final c = ReceiptPrinterPrefs.choice!;
      expect([c.name, c.paper.mm], ['MPT-II', 80]);
    });

    test('بلوتوث بلا طابعة ⇒ مطفأ؛ طابعة الجهاز على غير أندرويد ⇒ تعود لنافذة الطباعة', () async {
      ReceiptPrinterPrefs.mode.value = ReceiptPrinterMode.bluetooth;
      expect(ReceiptPrinterPrefs.enabled, isFalse);
      await ReceiptPrinterPrefs.setMode(ReceiptPrinterMode.builtin);
      ReceiptPrinterPrefs.debugBuiltinSupported = false;
      await ReceiptPrinterPrefs.load();
      expect(ReceiptPrinterPrefs.mode.value, ReceiptPrinterMode.system);
    });

    test('الحاسبة/الويب: لا يُقرأ ولا يُفعَّل ولو بقي محفوظاً', () async {
      FlutterSecureStorage.setMockInitialValues({
        'app.receipt_printer.mode': 'bluetooth',
        'app.receipt_printer.device': '{"id":"AA:BB:CC:DD:EE:01","name":"MPT-II"}',
      });
      ReceiptPrinterPrefs.debugSupported = false;
      await ReceiptPrinterPrefs.load();
      expect(ReceiptPrinterPrefs.mode.value, ReceiptPrinterMode.system);
      expect(ReceiptPrinterPrefs.enabled, isFalse);
    });

    test('طابعةٌ محفوظة تالفة ⇒ لا طابعة (لا عطل)', () {
      expect(SavedReceiptPrinter.decode('{bad'), isNull);
      expect(SavedReceiptPrinter.decode('{"name":"x"}'), isNull);
      expect(SavedReceiptPrinter.decode('{"id":"A1","name":""}')!.name, 'A1');
    });

    test('الورق: ٥٨ = ٣٨٤ نقطة وحافّة ٥ ملم؛ ٨٠ = ٥٧٦ وحافّة ٤ — ونصف ملم أمانٍ داخل الرأس، لفّةٌ بطولٍ مفتوح', () {
      final f58 = ReceiptPaper.mm58.pageFormat;
      expect(f58.width, moreOrLessEquals(58 * PdfPageFormat.mm, epsilon: 0.001));
      expect(f58.height, double.infinity);
      expect([f58.marginLeft, f58.marginRight].map((m) => m / PdfPageFormat.mm), [closeTo(5.5, 1e-9), closeTo(5.5, 1e-9)]);
      expect(ReceiptPaper.mm58.leftDots, 40, reason: 'القصّ عند حافّة الرأس نفسها');
      final f80 = ReceiptPaper.mm80.pageFormat;
      expect(f80.marginLeft / PdfPageFormat.mm, closeTo(4.5, 1e-9));
      expect(ReceiptPaper.mm80.leftDots, 32);
      expect(ReceiptPaper.dpi, closeTo(203.2, 1e-9));
    });
  });

  group('٢ التوجيه', () {
    test('بلا طابعة وصولات (الافتراضيّ) ⇒ نافذة الطباعة كما كانت حرفاً', () async {
      final r = await PrintOutput.send(_doc('activation-a'));
      expect(r.outcome, PrintOutcome.printed);
      expect(backend.calls, ['layout']);
      expect(h.bridge.calls, isEmpty);
    });

    test('طابعة بلوتوث مختارة ⇒ الوصل إليها لا لنافذة الطباعة', () async {
      h.useBluetooth();
      final r = await PrintOutput.send(_doc('activation-a'));
      expect(r.ack, PrintAck.sent);
      expect(backend.calls, isEmpty);
      expect(h.bridge.receiptWrites, isNotEmpty);
    });

    test('التقارير (allowDirect: false) ⇒ نافذة الطباعة دائماً — لا تذهب لطابعة الكاشير', () async {
      h.useBluetooth();
      await PrintOutput.send(_doc('report'), allowDirect: false);
      expect(backend.calls, ['layout']);
      expect(h.bridge.calls, isEmpty);
    });
  });

  group('٣ نافذة «صورة أم طباعة» بالهاتف', () {
    final navKey = GlobalKey<NavigatorState>();

    Future<void> host(WidgetTester t) async {
      PhoneOutput.debugActive = true;
      PhoneOutput.navigatorKey = navKey;
      await t.pumpWidget(EasyLocalization(
        supportedLocales: const [Locale('ar'), Locale('en')],
        path: 'assets/translations',
        startLocale: const Locale('ar'),
        fallbackLocale: const Locale('ar'),
        saveLocale: false,
        assetLoader: const _DiskLoader(),
        child: Builder(
          builder: (ctx) => MaterialApp(
            navigatorKey: navKey,
            locale: ctx.locale,
            supportedLocales: ctx.supportedLocales,
            localizationsDelegates: ctx.localizationDelegates,
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('بلا طابعة وصولات: الخياران كما كانا ولا ثالث', (t) async {
      await host(t);
      late Future<PrintResult> f;
      await t.runAsync(() async {
        f = PrintOutput.sendOrShare(_doc('activation-a'), title: 'وصل تفعيل');
      });
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('output-image')), findsOneWidget);
      expect(find.byKey(const ValueKey('output-print')), findsOneWidget);
      expect(find.byKey(const ValueKey('output-receipt-printer')), findsNothing);
      await t.tap(find.byKey(const ValueKey('output-print')));
      await t.pumpAndSettle();
      await t.runAsync(() => f);
      expect(backend.calls, ['layout']);
    });

    testWidgets('طابعة بلوتوث مختارة: «اطبع على MPT-II» أوّلاً ويطبع عليها', (t) async {
      h.useBluetooth();
      await host(t);
      late Future<PrintResult> f;
      await t.runAsync(() async {
        f = PrintOutput.sendOrShare(_doc('activation-a'), title: 'وصل تفعيل');
      });
      await t.pumpAndSettle();
      expect(find.text('اطبع على «MPT-II»'), findsOneWidget);
      expect(find.text('طابعة بلوتوث · ورق 58 ملم'), findsOneWidget);
      final printer = t.getTopLeft(find.byKey(const ValueKey('output-receipt-printer')));
      final image = t.getTopLeft(find.byKey(const ValueKey('output-image')));
      expect(printer.dy, lessThan(image.dy), reason: 'الطابعة المختارة أوّل خيار');
      await t.tap(find.byKey(const ValueKey('output-receipt-printer')));
      await t.pumpAndSettle();
      final r = (await t.runAsync(() => f))!;
      expect(r.ack, PrintAck.sent);
      expect(backend.calls, isEmpty);
    });

    testWidgets('مع الطابعة المختارة: «طباعة أو PDF» تبقى نافذة النظام لا الطابعة', (t) async {
      h.useBluetooth();
      await host(t);
      late Future<PrintResult> f;
      await t.runAsync(() async {
        f = PrintOutput.sendOrShare(_doc('activation-a'), title: 'وصل');
      });
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('output-print')));
      await t.pumpAndSettle();
      await t.runAsync(() => f);
      expect(backend.calls, ['layout']);
      expect(h.bridge.calls, isEmpty);
    });

    testWidgets('طابعة الجهاز: «اطبع على طابعة الجهاز»', (t) async {
      h.useBuiltin(paper: ReceiptPaper.mm80);
      await host(t);
      await t.runAsync(() async {
        unawaited(PrintOutput.sendOrShare(_doc('activation-a'), title: 'وصل'));
      });
      await t.pumpAndSettle();
      expect(find.text('اطبع على طابعة الجهاز'), findsOneWidget);
      expect(find.text('طابعة الجهاز المدمجة · ورق 80 ملم'), findsOneWidget);
      Navigator.of(navKey.currentContext!).pop();
      await t.pumpAndSettle();
    });
  });

  group('٤ الصورة للطابعة', () {
    test('لفّة: تُرسم بـ٢٠٣٫٢ نقطة/إنش ويُقصّ منها الرأس (٤٠ … ٤٢٣ على ٥٨ ملم)', () async {
      final saved = ThermalRender.rasterizer;
      addTearDown(() => ThermalRender.rasterizer = saved);
      late double dpi;
      Uint8List? got;
      ThermalRender.rasterizer = (pdf, d) async {
        dpi = d;
        got = pdf;
        final px = Uint8List(464 * 20 * 4);
        void ink(int x, int y) => px[(y * 464 + x) * 4 + 3] = 255;
        ink(40, 0);
        ink(423, 19);
        ink(10, 5); // في الحافّة غير المطبوعة
        return RgbaPage(464, 20, px);
      };
      final doc = PrintDoc(
        Uint8List.fromList(const [9]),
        PdfPageFormat.a4,
        name: 'r',
        roll: (paper) async {
          expect(paper.width, moreOrLessEquals(58 * PdfPageFormat.mm, epsilon: 0.001));
          return Uint8List.fromList(const [7, 7]);
        },
      );
      final img = await ThermalRender.receipt(doc, ReceiptPaper.mm58);
      expect(got, [7, 7], reason: 'اللفّة لا المستند A4');
      expect(dpi, closeTo(203.2, 1e-9));
      expect(img.width, 384);
      expect(img.isBlack(0, 0), isTrue);
      expect(img.isBlack(383, 19), isTrue);
      expect([for (var y = 0; y < 20; y++) for (var x = 0; x < 384; x++) if (img.isBlack(x, y)) 1].length, 2);
    });

    test('مستندٌ بلا لفّة: الصفحة كلّها تصغر لعرض الرأس', () async {
      final saved = ThermalRender.rasterizer;
      addTearDown(() => ThermalRender.rasterizer = saved);
      late double dpi;
      ThermalRender.rasterizer = (pdf, d) async {
        dpi = d;
        return RgbaPage(576, 4, Uint8List(576 * 4 * 4));
      };
      await ThermalRender.receipt(PrintDoc(Uint8List(1), PdfPageFormat.a4, name: 'x'), ReceiptPaper.mm80);
      expect(dpi, closeTo(576 * 72 / PdfPageFormat.a4.width, 1e-9));
    });

    test('وصل A4 ⇒ لفّته على ورق ٥٨ بعرض الورق وطولٍ محدود', () async {
      ReceiptPdf.debugCompress = false;
      final d = await ReceiptPdf.build(
        ReceiptDoc(
          kind: ReceiptKind.activation,
          issuedAt: DateTime(2026, 11, 9, 10),
          shopName: 'شركة النور',
          subscriberName: 'أحمد محمد',
          username: 'ahmed01',
          packageName: 'باقة 35 ميغا',
          packagePrice: 35000,
          amount: 35000,
        ),
        a4: true,
      );
      expect(d.format.width, PdfPageFormat.a4.width);
      expect(d.roll, isNotNull);
      final (w, hgt) = _mediaBox(await d.roll!(ReceiptPaper.mm58.pageFormat));
      expect(w, moreOrLessEquals(58 * PdfPageFormat.mm, epsilon: 0.01));
      expect(hgt.isFinite && hgt > 100 && hgt < PdfPageFormat.a4.height, isTrue, reason: 'لفّة بطول محتواها: $hgt');
    });

    test('سند التسوية لفّةً على ورق ٨٠ ولو كان الاختيار A4', () async {
      ReceiptPdf.debugCompress = false;
      h.useBluetooth(paper: ReceiptPaper.mm80);
      PrintDoc? captured;
      h.printer.render = (doc, paper) async {
        captured = doc;
        return MonoImage.blank(paper.dots, 10);
      };
      final s = SettlementRecord.fromJson(const {'id': 1, 'kind': 'settlement', 'number': 5})!;
      final r = await SettlementPrint.printVoucher(s);
      expect(r.ack, PrintAck.sent);
      expect(captured!.name, 'Settlement-5');
      final roll = await captured!.roll!(ReceiptPaper.mm80.pageFormat);
      final (w, _) = _mediaBox(roll);
      expect(w, moreOrLessEquals(80 * PdfPageFormat.mm, epsilon: 0.01));
    });
  });
}
