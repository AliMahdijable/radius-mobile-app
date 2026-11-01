import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/services/receipt_pdf.dart';
import 'package:rad_mysvcs/services/receipt_preview.dart';
import 'package:rad_mysvcs/services/receipt_samples.dart';

/// معاينة «تصميم الوصل» (spec §4.5/§4.6): التحويل لصورةٍ مستبدَل (نداءٌ للنظام لا يجري في الاختبار)، والجيل القديم يُسقط،
/// والتعديل أثناء البناء يُبنى بعده، وبنّاء الخيط الآخر يعيد البايتات.
ReceiptDoc _sample(String shop) => receiptSampleDoc(
      ReceiptKind.activation,
      look: ReceiptSettings.fromJson({'shop_name': shop}),
      shopName: shop,
      issuer: 'admin',
      issuedAt: DateTime.utc(2026, 11, 1, 7, 5),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('الأجيال والإعادة', () {
    late List<Completer<ReceiptPreviewBytes>> builds;
    late List<String> built;
    late List<Uint8List> rastered;
    late ReceiptPreviewController p;

    setUp(() {
      builds = [];
      built = [];
      rastered = [];
      p = ReceiptPreviewController(
        debounce: const Duration(milliseconds: 1),
        builder: (doc, a4) {
          built.add(doc.shopName);
          final c = Completer<ReceiptPreviewBytes>();
          builds.add(c);
          return c.future;
        },
        rasterizer: (bytes, dpi) async {
          rastered.add(bytes);
          return createTestImage(width: 8, height: 20);
        },
      );
    });
    tearDown(() => p.dispose());

    ReceiptPreviewBytes bytes(String tag) =>
        (bytes: Uint8List.fromList(tag.codeUnits), widthPt: 80 * PdfPageFormat.mm, heightPt: 200 * PdfPageFormat.mm);

    Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 10));

    test('تعديلٌ أثناء البناء: نتيجة الجيل القديم لا تُحوَّل صورةً، والأحدث يُبنى بعده', () async {
      p.request(_sample('A'), a4: false, dpi: 150);
      await tick();
      expect(built, ['A']);
      p.request(_sample('B'), a4: false, dpi: 150);
      await tick();
      expect(built, ['A'], reason: 'لا بناءين معاً');
      builds[0].complete(bytes('A'));
      await tick();
      expect(rastered, isEmpty, reason: 'A قديم ⇒ يُسقط');
      expect(built, ['A', 'B'], reason: 'إعادةٌ للمسوّدة الأحدث');
      builds[1].complete(bytes('B'));
      await tick();
      expect(rastered.map(String.fromCharCodes), ['B']);
      expect(p.image, isNotNull);
      expect(p.heightMm, moreOrLessEquals(200, epsilon: 0.001));
      expect(p.builds, 2);
      expect(p.busy, isFalse);
    });

    test('طلبات متتالية قبل المهلة = بناءٌ واحد بآخرها', () async {
      final slow = ReceiptPreviewController(
        debounce: const Duration(milliseconds: 40),
        builder: (doc, a4) async {
          built.add(doc.shopName);
          return bytes(doc.shopName);
        },
        rasterizer: (bytes, dpi) => createTestImage(width: 8, height: 20),
      );
      addTearDown(slow.dispose);
      for (final s in ['1', '2', '3']) {
        slow.request(_sample(s), a4: false, dpi: 150);
        await tick();
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(built, ['3']);
      expect(slow.image, isNotNull);
    });

    test('فشل البناء: «تعذّرت المعاينة» ولا صورة', () async {
      final bad = ReceiptPreviewController(
        debounce: const Duration(milliseconds: 1),
        builder: (doc, a4) async => throw StateError('font'),
        rasterizer: (bytes, dpi) => createTestImage(width: 8, height: 20),
      );
      addTearDown(bad.dispose);
      bad.request(_sample('X'), a4: false, dpi: 150);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect([bad.image, bad.error], [null, 'تعذّرت المعاينة']);
    });
  });

  test('الدقّة: لا تتجاوز ٢٠٠ ولا تقلّ عن ٧٢', () {
    expect(ReceiptPreviewController.dpiFor(paneWidthDp: 360, devicePixelRatio: 3, paperMm: 80), 200);
    expect(ReceiptPreviewController.dpiFor(paneWidthDp: 300, devicePixelRatio: 1, paperMm: 210), 72);
    expect(ReceiptPreviewController.dpiFor(paneWidthDp: 200, devicePixelRatio: 2, paperMm: 80), closeTo(127, 0.1));
  });

  test('بنّاء الخيط الآخر: بايتات PDF بلا ضغط وطول الصفحة — داخل Isolate.run', () async {
    final regular = ByteData.sublistView(File('assets/fonts/IBMPlexSansArabic-400.ttf').readAsBytesSync());
    final bold = ByteData.sublistView(File('assets/fonts/IBMPlexSansArabic-700.ttf').readAsBytesSync());
    final doc = _sample('مكتب النجف');
    final r = await Isolate.run(() => buildPreviewBytes(doc, false, regular, bold));
    expect(String.fromCharCodes(r.bytes.take(4)), '%PDF');
    expect(r.widthPt, moreOrLessEquals(80 * PdfPageFormat.mm, epsilon: 0.01));
    expect(r.heightPt, greaterThan(100));
    expect(String.fromCharCodes(r.bytes).contains('/FlateDecode'), isFalse, reason: 'المعاينة بلا ضغط');
    // البايتات نفسها خارج الخيط (حتميّ).
    final again = await buildPreviewBytes(doc, false, regular, bold);
    expect(again.heightPt, r.heightPt);
  });

  test('عيّنات المعاينة الخمس: الفاتورة بلا QR، وQR العيّنة لغيرها', () {
    for (final k in ReceiptKind.values) {
      final d = receiptSampleDoc(k, look: const ReceiptSettings(), shopName: 'م', issuedAt: DateTime.utc(2026));
      expect(d.qrUrl, k == ReceiptKind.sale ? isNull : receiptSampleQrUrl, reason: k.name);
    }
    expect(receiptSampleDoc(ReceiptKind.info, look: const ReceiptSettings(), shopName: 'م', qr: false).qrUrl, isNull);
  });

  test('الصورة تُحرَّر (لا تسرّب ذاكرة الصورة السابقة)', () async {
    final images = <ui.Image>[];
    final p = ReceiptPreviewController(
      debounce: const Duration(milliseconds: 1),
      builder: (doc, a4) async => (bytes: Uint8List(1), widthPt: 100.0, heightPt: 200.0),
      rasterizer: (bytes, dpi) async {
        final i = await createTestImage(width: 4, height: 4);
        images.add(i);
        return i;
      },
    );
    p.request(_sample('1'), a4: false, dpi: 100);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    p.request(_sample('2'), a4: false, dpi: 100);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(images, hasLength(2));
    expect(images.first.debugDisposed, isTrue);
    p.dispose();
    expect(images.last.debugDisposed, isTrue);
  });
}
