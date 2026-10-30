import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:rad_mysvcs/api/receipt_facts.dart';
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/print_output.dart';
import 'package:rad_mysvcs/services/print_prefs.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/services/receipt_pdf.dart';
import 'package:rad_mysvcs/services/receipt_service.dart';

import 'sim_el/sim_harness.dart';

/// المالك ٢٤ أكتوبر: «الويب من يطبع وصل ماكو أمر يصير مباشر، والتطبيق مابي طباعه وصل مباشر مثل
/// الويب للمشترك، والتطبيق الحاسوب كذلك زر طباعه مباشر ماكو، وأصلاً الزر ميشتغل بكل الحالات».
///
///   ١. ما يصل النظامَ مقاسٌ محدود دائماً — لفّة الكاشير بطولٍ لا نهائيّ كانت تُفشل ويندوز بصمت.
///   ٢. الطابعة المباشرة (الحاسبة): بلا نافذة، وطابعةٌ غائبة/معطّلة ⇒ نافذة الطباعة لا تعليق.
///   ٣. الوصل بأقسام الموقع وتسمياته، والانتهاء والرصيد كما أعادهما الخادم لا تقديراً.
///   ٤. «طباعة وصل» في صفحة المشترك: رمز QR للساس وحده، وبلا أرشفة (كالموقع).

class _FakeBackend implements PrintBackend {
  final calls = <String>[];
  List<Printer> list = const [];
  bool layoutResult = true;
  Object? layoutError;
  bool directResult = true;
  Object? directError;
  PrintDoc? last;

  @override
  Future<bool> layout(PrintDoc doc) async {
    calls.add('layout');
    last = doc;
    if (layoutError != null) throw layoutError!;
    return layoutResult;
  }

  @override
  Future<bool> direct(Printer printer, PrintDoc doc) async {
    calls.add('direct:${printer.url}');
    last = doc;
    if (directError != null) throw directError!;
    return directResult;
  }

  @override
  Future<List<Printer>> printers() async {
    calls.add('printers');
    return list;
  }
}

PrintDoc _doc() => PrintDoc(
      Uint8List.fromList(utf8.encode('%PDF-1.4')),
      PdfPageFormat(80 * PdfPageFormat.mm, 300),
      name: 'r',
    );

ReceiptDoc _receipt(ReceiptKind kind, {ReceiptSettings look = const ReceiptSettings(), String? qr}) => ReceiptDoc(
      kind: kind,
      issuedAt: DateTime.utc(2026, 10, 24, 15, 30),
      look: look,
      shopName: 'مكتب النجف',
      subscriberName: 'علي حسن',
      username: 'user7',
      phone: '07701234567',
      packageName: '10M-Unlimited',
      packagePrice: 25000,
      expiration: '2026-11-24 15:30:00',
      remainingDays: 31,
      pay: ReceiptPay.partial,
      amount: 25000,
      partialAmount: 10000,
      newBalance: -15000,
      qrUrl: qr,
      issuer: 'najaf650',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('١. مقاسٌ محدود للنظام', () {
    test('اللفّة تأخذ طول محتواها، وA4 كما هي', () async {
      for (final kind in ReceiptKind.values) {
        final pos = await ReceiptPdf.build(_receipt(kind, qr: 'https://pro.mysvcs.net/user-info/abc'), a4: false);
        expect(String.fromCharCodes(pos.bytes.take(4)), '%PDF');
        expect(pos.format.width, moreOrLessEquals(80 * PdfPageFormat.mm, epsilon: 0.01));
        expect(pos.format.height.isFinite, isTrue, reason: '${kind.name}: لا طول لا نهائيّ يصل النظام');
        expect(pos.format.height, inInclusiveRange(150, 1600));
      }
      final a4 = await ReceiptPdf.build(_receipt(ReceiptKind.activation), a4: true);
      expect([a4.format.width, a4.format.height], [PdfPageFormat.a4.width, PdfPageFormat.a4.height]);
    });

    test('عرض ورق الكاشير من مصمّم الموقع (طابعات ٥٨)', () async {
      final d = await ReceiptPdf.build(
          _receipt(ReceiptKind.info, look: const ReceiptSettings(paperWidthMm: 58)), a4: false);
      expect(d.format.width, moreOrLessEquals(58 * PdfPageFormat.mm, epsilon: 0.01));
    });

    test('شعارٌ تالف لا يُسقط الوصل', () async {
      final d = await ReceiptPdf.build(
          _receipt(ReceiptKind.info,
              look: ReceiptSettings(logo: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4, 5]))),
          a4: false);
      expect(d.bytes, isNotEmpty);
    });

    test('finite: البُعد اللانهائيّ يُستبدل', () {
      final f = PrintDoc.finite(PdfPageFormat.roll80, PdfPageFormat.roll80);
      expect(f.height.isFinite, isTrue);
      expect(f.width, PdfPageFormat.roll80.width);
    });
  });

  group('٢. الطابعة المباشرة والنافذة', () {
    late _FakeBackend fake;
    setUp(() {
      fake = _FakeBackend();
      PrintOutput.backend = fake;
      AppPlatform.debugIsDesktop = true;
      PrintPrefs.printer.value = null;
    });
    tearDown(() {
      AppPlatform.debugIsDesktop = null;
      PrintPrefs.printer.value = null;
    });

    const xp = Printer(url: 'XP-80C', name: 'XP-80C', isAvailable: true);

    test('بلا طابعةٍ محفوظة: نافذة الطباعة', () async {
      final r = await PrintOutput.send(_doc());
      expect(fake.calls, ['layout']);
      expect(r.ok, isTrue);
      expect(r.printer, isNull);
    });

    test('طابعةٌ محفوظة موجودة: مباشرةً بلا نافذة، والنتيجة باسمها', () async {
      fake.list = [xp];
      PrintPrefs.printer.value = const SavedPrinter(url: 'XP-80C', name: 'XP-80C');
      final r = await PrintOutput.send(_doc());
      expect(fake.calls, ['printers', 'direct:XP-80C']);
      expect(r.printer, 'XP-80C');
    });

    test('🚨 طابعةٌ غائبة أو معطّلة: النافذة — لا إرسال يعلق', () async {
      PrintPrefs.printer.value = const SavedPrinter(url: 'XP-80C', name: 'XP-80C');
      fake.list = const [Printer(url: 'Other', name: 'Other')];
      await PrintOutput.send(_doc());
      expect(fake.calls, ['printers', 'layout']);

      fake.calls.clear();
      fake.list = const [Printer(url: 'XP-80C', name: 'XP-80C', isAvailable: false)];
      await PrintOutput.send(_doc());
      expect(fake.calls, ['printers', 'layout']);
    });

    test('المباشرة رُفضت أو رمت: النافذة بدلها، والوصل لا يضيع', () async {
      fake.list = [xp];
      PrintPrefs.printer.value = const SavedPrinter(url: 'XP-80C', name: 'XP-80C');
      fake.directResult = false;
      await PrintOutput.send(_doc());
      expect(fake.calls, ['printers', 'direct:XP-80C', 'layout']);

      fake.calls.clear();
      fake.directError = Exception('spooler');
      final r = await PrintOutput.send(_doc());
      expect(fake.calls.last, 'layout');
      expect(r.ok, isTrue);
    });

    test('التقارير (allowDirect: false) والهاتف: النافذة دائماً', () async {
      fake.list = [xp];
      PrintPrefs.printer.value = const SavedPrinter(url: 'XP-80C', name: 'XP-80C');
      await PrintOutput.send(_doc(), allowDirect: false);
      expect(fake.calls, ['layout']);

      fake.calls.clear();
      AppPlatform.debugIsDesktop = false;
      await PrintOutput.send(_doc());
      expect(fake.calls, ['layout'], reason: 'أندرويد بلا طباعةٍ مباشرة');
    });

    test('إلغاء النافذة صامت، وفشلها يُقال', () async {
      fake.layoutResult = false;
      expect((await PrintOutput.send(_doc())).outcome, PrintOutcome.cancelled);
      fake.layoutError = Exception('no printers');
      expect((await PrintOutput.send(_doc())).outcome, PrintOutcome.failed);
    });

    test('SavedPrinter يُحفظ ويُقرأ، والتالف null', () {
      const p = SavedPrinter(url: 'XP-80C', name: 'طابعة الكاشير');
      final back = SavedPrinter.decode(p.encode())!;
      expect([back.url, back.name], ['XP-80C', 'طابعة الكاشير']);
      expect(SavedPrinter.decode('{bad'), isNull);
      expect(SavedPrinter.decode('{"name":"x"}'), isNull);
      expect(SavedPrinter.decode(null), isNull);
    });
  });

  group('٣. محتوى الوصل كالموقع', () {
    test('صفوف «المعاملة» وتسمية الرصيد', () {
      expect(_receipt(ReceiptKind.activation).transactionRows.map((r) => r.$1), [
        'طريقة الدفع',
        'المبلغ',
        'المُدفَع نقداً',
        'الدين المتبقّي',
      ]);
      final pay = ReceiptDoc(
        kind: ReceiptKind.payment,
        issuedAt: DateTime.utc(2026),
        shopName: 'م',
        subscriberName: 'س',
        username: 'u',
        amount: 5000,
        newBalance: 2000,
      );
      expect(pay.transactionRows.map((r) => (r.$1, r.$2)), [
        ('المبلغ المسدَّد', '5,000 د.ع'),
        ('الرصيد المتبقّي', '2,000 د.ع'),
      ]);
      final zero = ReceiptDoc(
          kind: ReceiptKind.info, issuedAt: DateTime.utc(2026), shopName: 'م', subscriberName: 'س', username: 'u', newBalance: 0);
      expect(zero.transactionRows.single.$1, 'الرصيد');
    });

    test('رقم الأرشيف «No. 00012»، وبلاه مرجعٌ زمنيّ؛ والوقت بتوقيت بغداد', () {
      final d = _receipt(ReceiptKind.activation);
      expect(d.receiptId, startsWith('R-'));
      final n = ReceiptDoc(
          kind: ReceiptKind.activation, issuedAt: DateTime.utc(2026, 10, 24, 21, 5), shopName: 'م', subscriberName: 'س', username: 'u', receiptNo: 12);
      expect(n.receiptId, 'No. 00012');
      expect(n.issuedText, '2026-10-25 00:05');
      expect(ReceiptPdf.expiry('2026-11-24 15:30:00'), '2026-11-24 15:30');
    });

    test('ReceiptFacts: الانتهاء والرصيد من ردّ الخادم، بشركة الطلب، ويُقرأ مرّة', () {
      ReceiptFacts.clear();
      final act = ReceiptFacts.parse({
        'success': true,
        'data': {
          'new_balance': -15000,
          'updated': {'expiration': '2026-11-24 15:30:00', 'remaining_days': '31', 'notes': '-15000'},
        },
      })!;
      expect([act.expiration, act.remainingDays, act.newBalance], ['2026-11-24 15:30:00', 31, -15000]);
      final ext = ReceiptFacts.parse({
        'data': {
          'updated': {'expiration': '2026-12-24 15:30:00', 'notes': '-2500'},
        },
      })!;
      expect(ext.newBalance, -2500, reason: 'التمديد: الرصيد في updated.notes');
      final pay = ReceiptFacts.parse({
        'data': {'amount_paid': 35000, 'new_balance': 0},
      })!;
      expect([pay.amountPaid, pay.newBalance], [35000, 0]);
      expect(ReceiptFacts.parse({'success': true}), isNull);

      ReceiptFacts.capture('7', {
        'data': {'new_balance': -1},
      });
      expect(ReceiptFacts.take('7', companyKey: 'c0123456789ab'), isNull, reason: 'شركةٌ أخرى');
      expect(ReceiptFacts.take('7')!.newBalance, -1);
      expect(ReceiptFacts.take('7'), isNull, reason: 'يُقرأ مرّةً واحدة');
    });
  });

  group('٤. «طباعة وصل» من صفحة المشترك', () {
    late SimServer server;
    late _FakeBackend fake;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp();
      SubscribersApi.clearAllCaches();
      ReceiptSettingsApi.clearCache();
      fake = _FakeBackend();
      PrintOutput.backend = fake;
      server.reply('GET', '/api/v2/receipt-settings', 200, {
        'success': true,
        'data': {'shop_name': 'مكتب النجف', 'show_qr': 1, 'auto_print': 0},
      });
      server.reply('POST', '/api/v2/subscribers/7/generate-link', 200, {
        'success': true,
        'data': {'linkUrl': 'https://pro.mysvcs.net/user-info/t1'},
      });
      server.reply('POST', '/api/printed-receipts', 200, {'success': true, 'receipt_no': 12});
    });
    tearDown(() {
      PermissionsService.debugReset();
      ProviderService.debugSet(null);
      ReceiptSettingsApi.clearCache();
    });

    const v = SimVariant(390, dark: false);

    Subscriber sub() => Subscriber.fromJson({
          'idx': '7',
          'username': 'user7',
          'firstname': 'علي',
          'lastname': 'حسن',
          'phone': '07701234567',
          'profile_name': '10M-Unlimited',
          'expiration': '2026-11-20 14:30:00',
          'enabled': 1,
          'notes': '-35000',
        });

    Future<void> open(WidgetTester t) async {
      await pumpSim(t, v, home: (_) => SubscriberDetailScreen(sub: sub()), settle: false);
      await t.pump(const Duration(seconds: 1));
    }

    Future<void> close(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
    }

    for (final el in [false, true]) {
      testWidgets(el ? 'ايرث لنك: يُطبع بلا رمز QR' : 'ساس: زرّ الرأس يطبع البطاقة برمز QR بلا أرشفة',
          (t) async {
        PermissionsService.debugSet(isEmployee: false);
        if (el) ProviderService.debugSet('earthlink');
        await open(t);
        await t.tap(find.byTooltip('printer.receipt'.tr()));
        // الطلبات الوهميّة تمضي بالوقت المزيّف، وقراءة الخطّ وبناء الـPDF بالحقيقيّ — نناوب بينهما.
        for (var i = 0; i < 40 && !fake.calls.contains('layout'); i++) {
          await t.pump(const Duration(milliseconds: 100));
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        }
        expect(fake.calls, contains('layout'));
        expect(fake.last!.format.height.isFinite, isTrue);
        expect(server.calls('POST', '/api/v2/subscribers/7/generate-link'), hasLength(el ? 0 : 1));
        expect(server.calls('POST', '/api/printed-receipts'), isEmpty, reason: 'البطاقة لا تُؤرشف (كالموقع)');
        await close(t);
      });
    }

    testWidgets('وصل التسديد: يُؤرشف بالمبلغ الفعليّ والرصيد من ردّ الخادم', (t) async {
      PermissionsService.debugSet(isEmployee: false);
      ReceiptFacts.clear();
      ReceiptFacts.capture('7', {
        'data': {'amount_paid': 35000, 'new_balance': 0},
      });
      late PrintResult r;
      await t.runAsync(() async => r = await ReceiptService.printDebtPayment(sub: sub(), paid: 30000));
      expect(r.ok, isTrue);
      final body = server.calls('POST', '/api/printed-receipts').single.data as Map;
      expect(body['operation_type'], 'pay_debt');
      expect(body['amount'], 35000, reason: '«كامل الدين» يقرؤه الخادم حيّاً');
      expect((body['payload'] as Map)['newBalance'], 0);
    });

    testWidgets('«الطباعة التلقائيّة» في مصمّم الموقع', (t) async {
      server.reply('GET', '/api/v2/receipt-settings', 200, {
        'success': true,
        'data': {'auto_print': 1},
      });
      late bool on;
      await t.runAsync(() async => on = await ReceiptService.autoPrintFor(null));
      expect(on, isTrue);
    });
  });

  /// المالك ٣٠ أكتوبر: «تطبيق الويندوز طباعه الوصل الابعاد مجاي تتصح مثل الويب».
  ///   ١. ويندوز يرسل ورق الطابعة قبل الطباعة ويطبع الصفحة بمقاسها الحقيقيّ — الوصل يُعاد بناؤه على ذلك الورق
  ///      (كالمتصفّح بوصل الموقع): لا قصّ على ٥٨/٧٢ ولا وصلاً صغيراً في زاوية A4.
  ///   ٢. أبعاد مصمّم الموقع (الحواشي، الخطّ، الشعار، QR، المسافات) — كان التطبيق يقرأ عرض الورق وحده.
  group('٥. أبعاد الموقع وورق طابعة ويندوز', () {
    const mm = PdfPageFormat.mm;
    tearDown(() => PrintOutput.debugFitToPrinter = null);

    PdfPageFormat printerPaper(double wMm, double hMm, {double sideMm = 4}) =>
        PdfPageFormat(wMm * mm, hMm * mm, marginLeft: sideMm * mm, marginRight: sideMm * mm);

    test('fromJson: أبعاد المصمّم بمدياته، والغائب والتالف افتراض الموقع', () {
      final s = ReceiptSettings.fromJson({
        'design': {
          'margin_top_mm': 0,
          'margin_right_mm': 7,
          'margin_bottom_mm': 99,
          'margin_left_mm': 'x',
          'font_size_base': 15,
          'font_size_title': 40,
          'logo_size_mm': 25,
          'qr_size_mm': 5,
          'section_gap_mm': '2',
        },
      });
      expect([s.marginTopMm, s.marginRightMm, s.marginBottomMm, s.marginLeftMm], [0, 7, 30, 4]);
      expect([s.fontBasePx, s.fontTitlePx, s.logoSizeMm, s.qrSizeMm, s.sectionGapMm], [15, 36, 25, 15, 2]);
      final none = ReceiptSettings.fromJson(const {});
      expect([none.fontBasePx, none.fontTitlePx, none.logoSizeMm, none.qrSizeMm, none.sectionGapMm], [13, 16, 18, 35, 6]);
      expect([none.marginTopMm, none.marginRightMm, none.marginBottomMm, none.marginLeftMm], [4, 4, 4, 4]);
    });

    test('خطّ المصمّم ومسافاته تغيّر الوصل (الكبير أطول)', () async {
      Future<double> height(ReceiptSettings look) async =>
          (await ReceiptPdf.build(_receipt(ReceiptKind.activation, look: look, qr: 'https://x.y/z'), a4: false))
              .format
              .height;
      final small = await height(const ReceiptSettings(fontBasePx: 9, fontTitlePx: 12, sectionGapMm: 0, qrSizeMm: 15));
      final big = await height(const ReceiptSettings(fontBasePx: 22, fontTitlePx: 36, sectionGapMm: 20, qrSizeMm: 60));
      expect(big, greaterThan(small * 1.5));
    });

    test('QR والشعار لا يتجاوزان عرض الورق (QR ٦٠ على ٥٨)', () async {
      final d = await ReceiptPdf.build(
          _receipt(ReceiptKind.activation,
              look: const ReceiptSettings(paperWidthMm: 58, qrSizeMm: 60), qr: 'https://x.y/z'),
          a4: false);
      expect(d.format.width, moreOrLessEquals(58 * mm, epsilon: 0.01));
      expect(d.bytes, isNotEmpty);
    });

    test('🚨 ويندوز: وصل الـ٨٠ يُعاد بناؤه على ورق طابعة ٥٨ — وحواشيه لا تقلّ عن حواشي الطابعة', () async {
      PrintOutput.debugFitToPrinter = true;
      final d = await ReceiptPdf.build(_receipt(ReceiptKind.activation, qr: 'https://x.y/z'), a4: false);
      expect(d.format.width, moreOrLessEquals(80 * mm, epsilon: 0.01));
      expect(d.refit, isNotNull);
      final bytes = await PrintOutput.bytesFor(d, printerPaper(58, 297, sideMm: 5));
      expect(bytes, isNot(d.bytes));
      final again = await ReceiptPdf.build(_receipt(ReceiptKind.activation, qr: 'https://x.y/z'),
          a4: false, paper: printerPaper(58, 297, sideMm: 5));
      expect(again.format.width, moreOrLessEquals(58 * mm, epsilon: 0.01));
      expect(again.refit, isNull, reason: 'المُعاد بناؤه لا يُعاد ثانيةً');
      expect(again.format.height, greaterThanOrEqualTo(d.format.height), reason: 'الأضيق لا يقصر');
    });

    test('ويندوز: وصل الكاشير على طابعة A4 بعرض الورق كالموقع، وA4 بورق الطابعة', () async {
      final pos = await ReceiptPdf.build(_receipt(ReceiptKind.info), a4: false, paper: printerPaper(210, 297));
      expect(pos.format.width, moreOrLessEquals(210 * mm, epsilon: 0.01));
      final letter = await ReceiptPdf.build(_receipt(ReceiptKind.info), a4: true,
          paper: PdfPageFormat(PdfPageFormat.letter.width, PdfPageFormat.letter.height));
      expect([letter.format.width, letter.format.height], [PdfPageFormat.letter.width, PdfPageFormat.letter.height]);
    });

    test('غير ويندوز، أو ورقٌ غير معقول، أو فشل إعادة البناء: المستند كما بُني', () async {
      var calls = 0;
      final doc = PrintDoc(
        Uint8List.fromList(utf8.encode('%PDF-1.4 original')),
        PdfPageFormat(80 * mm, 300),
        name: 'r',
        refit: (paper) async {
          calls++;
          if (paper.width < 60 * mm) throw StateError('boom');
          return Uint8List.fromList(utf8.encode('%PDF-1.4 refit'));
        },
      );
      PrintOutput.debugFitToPrinter = false;
      expect(await PrintOutput.bytesFor(doc, printerPaper(80, 297)), doc.bytes);
      PrintOutput.debugFitToPrinter = true;
      expect(utf8.decode(await PrintOutput.bytesFor(doc, printerPaper(80, 297))), '%PDF-1.4 refit');
      expect(await PrintOutput.bytesFor(doc, printerPaper(58, 297)), doc.bytes, reason: 'رمى ⇒ كما بُني');
      for (final bad in [
        PdfPageFormat(10 * mm, 297 * mm),
        PdfPageFormat(double.infinity, 297 * mm),
        PdfPageFormat(80 * mm, 297 * mm, marginLeft: 30 * mm, marginRight: 20 * mm),
      ]) {
        expect(PrintOutput.usablePaper(bad), isFalse);
        expect(await PrintOutput.bytesFor(doc, bad), doc.bytes);
      }
      expect(calls, 2);
      final plain = PrintDoc(doc.bytes, doc.format, name: 'r');
      expect(await PrintOutput.bytesFor(plain, printerPaper(80, 297)), doc.bytes, reason: 'بلا إعادة بناء');
    });

    test('finite: صفحةٌ أقصر من عرضها تطول (ويندوز يقلب الأعرض أفقيّاً)', () {
      final f = PrintDoc.finite(PdfPageFormat(80 * mm, 50 * mm), PdfPageFormat.roll80);
      expect(f.height, greaterThan(f.width));
    });
  });
}
