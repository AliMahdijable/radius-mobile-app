import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:rad_mysvcs/core/util/server_time.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_export.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_image.dart';
import 'package:rad_mysvcs/services/phone_output.dart';
import 'package:rad_mysvcs/services/print_output.dart';
import 'package:share_plus/share_plus.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «صورة» بالهاتف (٨ نوفمبر — المالك: «الوصولات بالهاتف صوره تكون اختيار افضل من pdf»):
///   ١. الوصل بالهاتف يسأل «صورة أم طباعة»: الصورة من صفحات الوصل نفسه بدقّةٍ تناسب عرضه، والطباعة كما كانت، والإغلاق لا شيء.
///   ٢. الحاسبة كما كانت: نافذة الطباعة بلا سؤال.
///   ٣. التقرير صورةً: صفحاتٌ بعرض الهاتف، وما زاد على الصور يُقال لا يُقصّ صامتاً.
///   ٤. زرّ «صورة» في شريط التصدير بالهاتف وحده.
///   ٥. وقت التصدير مقروءٌ («2026-11-07 21:21») لا «…T21:21:56.000Z».

class _FakeBackend implements PrintBackend {
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

Future<PrintDoc> _receiptLike() async {
  final doc = pw.Document();
  // لفّة ٨٠ ملم بطولٍ محدود (كالوصل بعد [PrintDoc.finite]) — الطول اللانهائيّ لا يُرسم
  final roll = PdfPageFormat(PdfPageFormat.roll80.width, 400);
  doc.addPage(pw.Page(pageFormat: roll, build: (_) => pw.SizedBox(width: 50, height: 50)));
  return PrintDoc.of(doc, name: 'Receipt-1.pdf', requested: roll);
}

void main() {
  setUpAll(visualSetUpAll);
  late _FakeBackend backend;
  late List<double> dpis;
  late List<List<XFile>> shared;
  final navKey = GlobalKey<NavigatorState>();

  setUp(() {
    backend = _FakeBackend();
    PrintOutput.backend = backend;
    dpis = [];
    shared = [];
    PhoneOutput.rasterizer = (pdf, dpi) async {
      dpis.add(dpi);
      return [Uint8List.fromList([137, 80, 78, 71]), Uint8List.fromList([137, 80, 78, 71])];
    };
    PhoneOutput.sharer = (files, {text, origin}) async {
      shared.add(files);
      return true;
    };
    PhoneOutput.navigatorKey = navKey;
    PhoneOutput.tempDir = () async => Directory.systemTemp.createTempSync('phone_output_test');
  });

  tearDown(() {
    PhoneOutput.debugActive = null;
    PhoneOutput.navigatorKey = null;
  });

  Future<void> host(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: SizedBox())),
    ));
  }

  testWidgets('١ الوصل بالهاتف: «صورة» ⇒ صفحاته صوراً بدقّة عرضه ثمّ المشاركة — لا نافذة طباعة', (t) async {
    PhoneOutput.debugActive = true;
    await host(t);
    final doc = (await t.runAsync(_receiptLike))!;
    // المستقبل يبدأ في المنطقة الحقيقيّة: ما بعد الاختيار كتابة ملفّات
    late Future<PrintResult> f;
    await t.runAsync(() async {
      f = PrintOutput.sendOrShare(doc, title: 'وصل تفعيل');
    });
    await t.pumpAndSettle();
    expect(find.text('وصل تفعيل'), findsOneWidget);
    expect(find.byKey(const ValueKey('output-image')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('output-image')));
    await t.pumpAndSettle();
    final r = (await t.runAsync(() => f))!;
    expect(r.outcome, PrintOutcome.shared);
    expect(r.ok, isTrue);
    expect(r.images, 2);
    expect(backend.calls, isEmpty, reason: 'لا نافذة طباعة');
    expect(shared.single.map((x) => x.path.endsWith('.png')), everyElement(isTrue));
    expect(shared.single.first.path, contains('Receipt-1_'));
    // لفّة ٨٠ ملم (٢٢٦ نقطة) ⇒ دقّةٌ تُخرجها بعرض ~١٠٨٠ بكسل
    expect(dpis.single, closeTo(1080 * 72 / PdfPageFormat.roll80.width, 0.5));
  });

  testWidgets('١ب «طباعة أو PDF» ⇒ نافذة الطباعة كما كانت؛ والإغلاق ⇒ لا شيء', (t) async {
    PhoneOutput.debugActive = true;
    await host(t);
    final doc = (await t.runAsync(_receiptLike))!;
    late Future<PrintResult> f;
    await t.runAsync(() async {
      f = PrintOutput.sendOrShare(doc, title: 'وصل');
    });
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('output-print')));
    await t.pumpAndSettle();
    expect((await t.runAsync(() => f))!.outcome, PrintOutcome.printed);
    expect(backend.calls, ['layout']);
    expect(shared, isEmpty);

    backend.calls.clear();
    late Future<PrintResult> g;
    await t.runAsync(() async {
      g = PrintOutput.sendOrShare(doc, title: 'وصل');
    });
    await t.pumpAndSettle();
    Navigator.of(navKey.currentContext!).pop();
    await t.pumpAndSettle();
    expect((await t.runAsync(() => g))!.outcome, PrintOutcome.cancelled);
    expect(backend.calls, isEmpty);
    expect(shared, isEmpty);
  });

  testWidgets('٢ الحاسبة: نافذة الطباعة بلا سؤال', (t) async {
    PhoneOutput.debugActive = false;
    await host(t);
    final doc = (await t.runAsync(_receiptLike))!;
    final r = (await t.runAsync(() => PrintOutput.sendOrShare(doc, title: 'وصل')))!;
    expect(r.outcome, PrintOutcome.printed);
    expect(backend.calls, ['layout']);
    expect(find.byKey(const ValueKey('output-image')), findsNothing);
  });

  test('٣ التقرير صورةً: بعرض الهاتف، وما زاد على الصور يُقال لا يُقصّ صامتاً', () async {
    final cols = ['اسم المشترك', 'اليوزر', 'المبلغ', 'التاريخ', 'الوصف', 'النوع', 'المنفّذ'];
    List<String> row(int i) =>
        ['مشترك $i', 'u$i', '${i * 1000}', '2026-11-07 21:21', 'تفعيل غير نقدي — السعر 35000 د.ع', 'تفعيل', 'admin'];
    final small = await ReportImageDoc.build(title: 'التفعيلات', subtitle: 'الفترة', columns: cols, rows: [for (var i = 0; i < 12; i++) row(i)]);
    expect(small.shownRows, 12);
    expect(small.pages, inInclusiveRange(1, 4));
    expect(String.fromCharCodes(small.bytes.take(5)), '%PDF-');

    final big = await ReportImageDoc.build(title: 'التفعيلات', columns: cols, rows: [for (var i = 0; i < 300; i++) row(i)]);
    expect(big.shownRows, lessThanOrEqualTo(ReportImageDoc.maxRows));
    expect(big.shownRows, lessThan(300));
    expect(big.pages, lessThanOrEqualTo(PhoneOutput.maxImages), reason: 'كلّ صفحةٍ صورة — لا صفحةٌ تُسقط');
    expect(ReportImageDoc.page.width, 400);
    expect(PhoneOutput.dpiFor(ReportImageDoc.page.width), closeTo(194.4, 0.1));
  });

  testWidgets('٤ زرّ «صورة» في شريط التصدير بالهاتف وحده — ويشارك صفحات التقرير', (t) async {
    Widget bar() => MaterialApp(
          navigatorKey: navKey,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Center(
                child: ReportExportBar(
                  title: 'التفعيلات',
                  subtitle: 'الفترة',
                  fileNameBase: 'activations',
                  columns: const ['اسم المشترك', 'المبلغ'],
                  rows: const [
                    ['علي', '15000'],
                  ],
                ),
              ),
            ),
          ),
        );
    PhoneOutput.debugActive = false;
    await t.pumpWidget(bar());
    expect(find.byKey(const ValueKey('report-share-image')), findsNothing);

    PhoneOutput.debugActive = true;
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(bar());
    expect(find.byKey(const ValueKey('report-share-image')), findsOneWidget);
    final btn = t.widget<InkResponse>(
        find.descendant(of: find.byKey(const ValueKey('report-share-image')), matching: find.byType(InkResponse)));
    await t.runAsync(() async {
      btn.onTap!();
      for (var i = 0; i < 100 && shared.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await t.pump();
    expect(shared, hasLength(1));
    expect(shared.single.first.path, contains('activations_'));
    expect(dpis.single, closeTo(194.4, 0.1));
  });

  test('٥ وقت التصدير مقروء', () {
    final t = DateTime.parse('2026-11-07T21:21:56.000Z').toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    expect(exportTime('2026-11-07T21:21:56.000Z'),
        '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}');
    expect(exportTime('2026-11-07'), '2026-11-07', reason: 'الصرفيات بتاريخٍ وحده');
    expect(exportTime(''), '');
    expect(exportTime('غير معروف'), 'غير معروف');
  });
}
