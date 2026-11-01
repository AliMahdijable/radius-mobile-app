import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/screens/print_templates/print_templates_screen.dart';
import 'package:rad_mysvcs/services/receipt_layout.dart';
import 'package:rad_mysvcs/services/receipt_pdf.dart';
import 'package:rad_mysvcs/services/receipt_pdf_v2.dart';

import 'sim_el/sim_harness.dart';

/// «تصميم الوصل» v2 في التطبيق (المالك ١ نوفمبر: «الطباعه اضافة ميزات اخفاء وتقليص الوصل والتحكم اكثر بالمتغيرات…»):
///   ١. المحلِّل هو محلِّل الموقع حرفاً بحرف — ملفّ التثبيت المشترك نسخةٌ بالبايت (بصمته مثبّتة هنا وفي الموقع)، ثوابته
///      وكلّ حالاته.
///   ٢. قراءة الإعدادات: بلا `layout` ⇒ طريق v1 كما كان؛ التالف افتراضيّ؛ «حجم الوصل» والعدّادات.
///   ٣. PDF: «مضغوط جداً» < «مضغوط» < «عادي»، وورق ٥٨، والمخفيّ لا يُرسم، وبلا تشكيلٍ ولا رموزٍ عند الرسم.
///   ٤. «قوالب الطباعة»: الحجم والحقول المخفيّة والنصوص الإضافيّة.
const _fixturePath = 'test/fixtures/receipt_layout.fixtures.json';

/// البصمة المثبّتة — هي `RECEIPT_FIXTURES_SHA256` في الموقع. ملفٌّ تغيّر في جهةٍ واحدة يُسقط هذا الاختبار.
const _pinnedSha = 'd18f3130a40e532cdaed7301fb32f6adfdd699cae87dde0a399a5e54f07614f1';

ReceiptDoc _doc(ReceiptKind kind, ReceiptSettings look, {String? qr = 'https://pro.mysvcs.net/user-info/abc', SaleInvoiceDoc? sale}) =>
    ReceiptDoc(
      kind: kind,
      issuedAt: DateTime.utc(2026, 11, 1, 7, 5),
      look: look,
      receiptNo: 12,
      shopName: 'مكتب النور للإنترنت',
      subscriberName: 'علي حسن',
      username: 'ali1@najaf',
      phone: '07701000001',
      packageName: 'Plus 50M',
      packagePrice: 35000,
      expiration: '2026-12-01 10:05:00',
      remainingDays: 30,
      pay: ReceiptPay.partial,
      amount: 35000,
      partialAmount: 25000,
      newBalance: -10000,
      qrUrl: kind == ReceiptKind.sale ? null : qr,
      issuer: 'admin@najaf',
      sale: sale,
    );

/// تصميمٌ بمقاس «حجم الوصل» (مفاتيح v1 + الضغط والرموز) وما يُضاف إلى `layout`.
Map<String, dynamic> _preset(String id, [Map<String, dynamic> layout = const {}]) {
  final p = receiptPresets[id]!;
  return {
    ...p.v1,
    'layout': {'v': 2, 'density': p.density, 'emoji': p.emoji, ...layout},
  };
}

ReceiptSettings _look(Map<String, dynamic> design, {String? footer}) => ReceiptSettings.fromJson({
      'shop_name': 'مكتب النور للإنترنت',
      'shop_address': 'النجف — حيّ الأمير',
      'shop_phone': '0780 111 2222',
      'footer_text': footer,
      'design': design,
    });

Future<double> _height(ReceiptDoc d, {double? paperMm}) async => (await ReceiptPdf.build(
      d,
      a4: false,
      paper: paperMm == null ? null : PdfPageFormat(paperMm * PdfPageFormat.mm, 297 * PdfPageFormat.mm),
    ))
        .format
        .height;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bytes = File(_fixturePath).readAsBytesSync();
  final fixture = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  group('١. محلِّل الموقع حرفاً بحرف (ملفّ التثبيت المشترك)', () {
    test('الملفّ نسخةٌ بالبايت: بصمته هي المثبّتة هنا وفي المحلِّل', () {
      final sha = sha256.convert(bytes).toString();
      expect(sha, _pinnedSha, reason: 'غيّر الملفّ وبصمته في الموقع والتطبيق معاً');
      expect(receiptFixturesSha256, _pinnedSha);
      expect(fixture['schema'], 'receipt-layout-fixtures/1');
      expect(cases.length, greaterThanOrEqualTo(15), reason: 'الحالات الخمس عشرة في التصميم على الأقلّ');
    });

    test('الثوابت (tokens) هي ثوابت الموقع', () {
      final tokens = fixture['tokens'] as Map<String, dynamic>;
      final mine = receiptLayoutTokens();
      expect(mine.keys.toSet(), tokens.keys.toSet());
      for (final k in tokens.keys) {
        expect(mine[k], equals(tokens[k]), reason: k);
      }
    });

    for (final c in cases) {
      test('${c['name']}', () {
        final got = ReceiptResolver.resolve(c['design'], ReceiptInput.fromJson(c['input'] as Map<String, dynamic>)).toJson();
        final want = c['expected'] as Map<String, dynamic>;
        // كتلةً كتلة أوّلاً: الفرق يظهر بمكانه.
        final gb = got['blocks'] as List;
        final wb = want['blocks'] as List;
        for (var i = 0; i < wb.length && i < gb.length; i++) {
          expect(gb[i], equals(wb[i]), reason: '${c['name']} — الكتلة $i');
        }
        expect(got, equals(want), reason: '${c['note']}');
      });
    }
  });

  group('٢. قراءة إعدادات الوصل', () {
    test('بلا layout ⇒ طريق v1 (null)؛ الكائن وحده v2، والتالف افتراضيّ لا يرمي', () {
      expect(ReceiptSettings.fromJson(const {}).layout, isNull);
      expect(ReceiptSettings.fromJson({'design': {'font_size_base': 11}}).layout, isNull);
      for (final bad in ['x', 3, true, [], null]) {
        expect(ReceiptSettings.fromJson({'design': {'layout': bad}}).layout, isNull, reason: '$bad');
      }
      final empty = ReceiptSettings.fromJson({'design': {'layout': <String, dynamic>{}}}).layout!;
      expect([empty.density, empty.emoji, empty.mono, empty.fields, empty.texts], ['normal', true, false, isEmpty, isEmpty]);

      final bad = ReceiptSettings.fromJson({
        'design': {
          'layout': {
            'v': 2,
            'density': 'ultra',
            'emoji': 'no',
            'mono': 1,
            'fields': {'username': {'show': 'no', 'size': 'huge', 'label': 5}, 'foo': {'show': false}},
            'texts': [null, {'at': 'middle', 'text': 'x'}, {'at': 'top', 'text': 'ن', 'only': ['nope']}],
            'order': ['x'],
          },
          'row_separator': 'wavy',
          'section_title_underline': false,
          'line_height': 9,
          'some_future_key': {'a': 1},
        },
      });
      final l = bad.layout!;
      expect([l.density, l.emoji, l.mono], ['normal', true, false]);
      expect(l.fields.keys, ['username']);
      expect([l.fields['username']!.show, l.fields['username']!.size, l.fields['username']!.label], [null, null, null]);
      expect(l.texts.single.id, 't1');
      expect(l.texts.single.only, isEmpty, reason: 'only بلا نوعٍ معروف ⇒ كلّ الأنواع');
      expect([bad.rowSeparator, bad.sectionTitleUnderline, bad.lineHeight], ['dotted', false, 2.2]);
    });

    test('«حجم الوصل»: المقاسات الثلاثة، والافتراضيّ «عادي»، وأيّ تعديل «مخصّص»', () {
      expect(ReceiptSettings.fromJson(const {}).preset, 'normal', reason: 'تصميم v1 الافتراضيّ = «عادي»');
      for (final id in ['normal', 'compact', 'tight']) {
        expect(_look(_preset(id)).preset, id);
      }
      expect(_look({..._preset('compact'), 'font_size_base': 12}).preset, isNull);
      expect(_look(_preset('compact', {'emoji': true})).preset, isNull);
      expect(_look({...receiptPresets['compact']!.v1}).preset, isNull, reason: 'مفاتيح v1 وحدها بلا الضغط ⇒ «مخصّص»');
    });

    test('العدّادات: الحقول المخفيّة (مفاتيح v1 الأربعة + v2) والنصوص الإضافيّة', () {
      final s = _look({
        'show_manager_signature': false,
        'show_package_price': false,
        'layout': {
          'v': 2,
          'fields': {
            'username': {'show': false},
            'phone': {'show': false, 'label': 'الموبايل'},
            'receipt_no': {'show': false},
            'amount': {'label': 'المدفوع'},
          },
          'texts': [
            {'at': 'top', 'text': 'أهلاً'},
            {'at': 'bottom', 'text': 'للدعم'},
          ],
        },
      });
      expect(s.hiddenFields, 4, reason: '«أصدره» وسعر الباقة (v1) + اسم المستخدم والهاتف؛ receipt_no.show يُهمل');
      expect(s.customTexts, 2);
      expect(ReceiptSettings.fromJson(const {}).hiddenFields, 0);
      expect(ReceiptSettings.fromJson(const {}).customTexts, 0);
    });
  });

  group('٣. وصل PDF v2', () {
    test('المقاسات تقصّر الوصل: «مضغوط جداً» < «مضغوط» < «عادي»، و«عادي» قريبٌ من v1', () async {
      final v1 = await _height(_doc(ReceiptKind.activation, _look(const {})));
      final normal = await _height(_doc(ReceiptKind.activation, _look(_preset('normal'))));
      final compact = await _height(_doc(ReceiptKind.activation, _look(_preset('compact'))));
      final tight = await _height(_doc(ReceiptKind.activation, _look(_preset('tight'))));
      expect(tight, lessThan(compact));
      expect(compact, lessThan(normal));
      expect(normal, closeTo(v1, v1 * 0.08), reason: '«عادي» = أرقام وصل اليوم (وخطّ التاريخ والرمز كالموقع)');
      expect(tight, lessThan(normal * 0.7));
    });

    test('ورق ٥٨ (paper:): بعرضه، وطولٌ محدود لا يقلّ عن ٨٠', () async {
      for (final id in ['normal', 'compact', 'tight']) {
        final d = _doc(ReceiptKind.activation, _look(_preset(id)));
        final pdf = await ReceiptPdf.build(d, a4: false, paper: const PdfPageFormat(58 * PdfPageFormat.mm, 297 * PdfPageFormat.mm));
        expect(pdf.format.width, moreOrLessEquals(58 * PdfPageFormat.mm, epsilon: 0.01));
        expect(pdf.format.height.isFinite, isTrue);
        expect(pdf.format.height, greaterThanOrEqualTo(await _height(d)), reason: '$id: الأضيق لا يقصر');
      }
    });

    test('مفاتيح v2 بلا layout لا تمسّ وصل v1 (التطبيق 3.0.13 وما قبله)', () async {
      final plain = await _height(_doc(ReceiptKind.activation, _look(const {})));
      final keys = await _height(_doc(
          ReceiptKind.activation, _look({'row_separator': 'none', 'section_title_underline': false, 'default_align': 'left', 'header_align': 'right'})));
      expect(keys, plain);
    });

    test('المخفيّ لا يُحلَّل، والتسمية الفارغة قيمةٌ وحدها، والنصّ بمتغيّره — ويُبنى PDF', () async {
      final look = _look(_preset('compact', {
        'fields': {
          'username': {'show': false},
          'phone': {'label': ''},
          'balance_debt': {'size': 'lg'},
        },
        'texts': [
          {'at': 'after_title', 'text': 'أهلاً {subscriber_name}', 'boxed': true, 'bold': true},
          {'at': 'before_qr', 'text': 'باقي {days_remaining} يوم', 'only': ['activation']},
        ],
      }));
      final d = _doc(ReceiptKind.activation, look);
      final body = ReceiptV2Body(d, logo: null, a4: false, width: 200);
      final rows = [for (final b in body.r.blocks.whereType<RSection>()) ...b.rows];
      expect(rows.map((r) => r.id), isNot(contains('username')));
      final phone = rows.firstWhere((r) => r.id == 'phone');
      expect([phone.label, phone.value], [null, '07701000001']);
      expect(rows.firstWhere((r) => r.id == 'balance_debt').scale, 1.2);
      final texts = body.r.blocks.whereType<RText>().map((t) => t.text).toList();
      expect(texts, ['أهلاً علي حسن', 'باقي 30 يوم']);
      final pdf = await ReceiptPdf.build(d, a4: false);
      expect(pdf.bytes, isNotEmpty);

      // وصل التسديد: النصّ بمتغيّر الأيّام لا يُطبع (لا قيمة له في هذا النوع).
      final pay = ReceiptV2Body(_doc(ReceiptKind.payment, look), logo: null, a4: false, width: 200);
      expect(pay.r.blocks.whereType<RText>().map((t) => t.text), ['أهلاً علي حسن']);
    });

    test('الرسم بلا تشكيل ولا رموزٍ تعبيريّة — والمحلِّل يُبقيهما', () async {
      expect(ReceiptV2Body.drawn('شُكْراً لكم 🙏'), 'شكرا لكم ');
      expect(ReceiptV2Body.drawn('📍 النجف'), ' النجف');
      final look = _look({
        'layout': {
          'v': 2,
          'texts': [
            {'at': 'top', 'text': 'شُكْراً 🙏'},
          ],
        },
      });
      final body = ReceiptV2Body(_doc(ReceiptKind.info, look), logo: null, a4: false, width: 200);
      expect(body.r.blocks.whereType<RText>().single.text, 'شُكْراً 🙏');
      expect((await ReceiptPdf.build(_doc(ReceiptKind.info, look), a4: false)).bytes, isNotEmpty);
    });

    test('اللاتينيّ وحده LTR، والمختلط RTL بمقاطع: التاريخ والهاتف وحدةٌ واحدة كـ<bdi> الموقع', () async {
      // مكتبة PDF لا تشكّل العربيّ في سطرٍ LTR، وفي سطرٍ RTL تفكّ المقطع متعدّد الأجزاء («10:05 01-11-2026»).
      expect(ReceiptV2Body.directionFor('0780 111 2222'), pw.TextDirection.ltr);
      expect(ReceiptV2Body.directionFor('#No. 00012'), pw.TextDirection.ltr);
      expect(ReceiptV2Body.directionFor('هاتف: 0780 111 2222'), isNull);
      expect(ReceiptV2Body.runsOf('التاريخ: 2026-11-01 10:05'), ['التاريخ: ', '2026-11-01 10:05']);
      expect(ReceiptV2Body.runsOf('للدعم: 0780 000 0000 — شكراً'), ['للدعم: ', '0780 000 0000', ' — شكراً']);
      expect(ReceiptV2Body.runsOf('دفع 25,000 د.ع'), ['دفع ', '25,000', ' د.ع']);
      expect(ReceiptV2Body.runsOf('رقم الوصل: #No. 00012'), ['رقم الوصل: ', '#No. 00012']);
      expect(ReceiptV2Body.runsOf('بلا لاتينيّ'), ['بلا لاتينيّ']);
      final look = _look({
        'layout': {
          'v': 2,
          'fields': {
            'shop_phone': {'label': 'هاتف'},
            'receipt_no': {'label': 'رقم الوصل'},
            'issued_at': {'label': 'التاريخ:'},
          },
        },
      });
      final body = ReceiptV2Body(_doc(ReceiptKind.activation, look), logo: null, a4: false, width: 200);
      final meta = body.r.blocks.whereType<RMeta>().single;
      expect([meta.no, meta.at], ['رقم الوصل: No. 00012', 'التاريخ: 2026-11-01 10:05']);
      expect(body.r.blocks.whereType<RShopLines>().single.lines.last.text, 'هاتف: 0780 111 2222');
      expect((await ReceiptPdf.build(_doc(ReceiptKind.activation, look), a4: false)).bytes, isNotEmpty);
    });

    test('A4 و«أسود فقط» وفاتورة البيع والمُلغاة تُبنى بطريق v2', () async {
      final a4 = await ReceiptPdf.build(_doc(ReceiptKind.activation, _look(_preset('normal', {'mono': true}))), a4: true);
      expect([a4.format.width, a4.format.height], [PdfPageFormat.a4.width, PdfPageFormat.a4.height]);
      const sale = SaleInvoiceDoc(
        id: 15,
        lines: [(name: 'راوتر', qty: '1 قطعة', unitPrice: 45000, total: 45000)],
        total: 45000,
        debt: true,
        note: 'يُسدَّد مع الاشتراك',
        voided: true,
        voidReason: 'خطأ',
      );
      final d = _doc(ReceiptKind.sale, _look(_preset('compact')), sale: sale);
      final body = ReceiptV2Body(d, logo: null, a4: false, width: 200);
      expect(body.r.blocks.whereType<RTitle>().single.text, 'فاتورة بيع رقم 15');
      expect(body.r.blocks.whereType<RSaleVoid>().single.text, 'مُلغاة — خطأ');
      expect(body.r.blocks.whereType<RQr>(), isEmpty);
      expect((await ReceiptPdf.build(d, a4: false)).bytes, isNotEmpty);
    });

    test('بيانات الوصل للمحلِّل: الرقم بخمس خانات، والفاتورة برقمها، وبلا أرشيف «R-…»، وطريقة الدفع', () {
      final d = _doc(ReceiptKind.activation, _look(_preset('normal')));
      final i = receiptInputOf(d, hasLogo: false);
      expect([i.receiptId, i.receiptNoText, i.issuedText, i.paymentType], ['No. 00012', '00012', '2026-11-01 10:05', 'partial-cash']);
      final none = ReceiptDoc(
          kind: ReceiptKind.info, issuedAt: DateTime.utc(2026, 11, 1), shopName: 'م', subscriberName: 'س', username: 'u');
      expect(receiptInputOf(none, hasLogo: false).receiptNoText, startsWith('R-'));
      final sale = ReceiptDoc(
        kind: ReceiptKind.sale,
        issuedAt: DateTime.utc(2026, 11, 1),
        shopName: 'م',
        subscriberName: 'س',
        username: '',
        sale: const SaleInvoiceDoc(id: 42, lines: [], total: 0, debt: false),
      );
      expect(receiptInputOf(sale, hasLogo: false).receiptNoText, '42');
    });
  });

  group('٤. «قوالب الطباعة»', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp();
      ReceiptSettingsApi.clearCache();
    });
    tearDown(ReceiptSettingsApi.clearCache);

    testWidgets('حجم الوصل والحقول المخفيّة والنصوص الإضافيّة من تصميم الموقع', (t) async {
      server.reply('GET', '/api/v2/receipt-settings', 200, {
        'success': true,
        'data': {
          'shop_name': 'مكتب النور',
          'shop_address': 'النجف',
          'show_qr': 1,
          'auto_print': 0,
          'design': _preset('compact', {
            'fields': {
              'username': {'show': false},
              'phone': {'show': false},
            },
            'texts': [
              {'at': 'bottom', 'text': 'للدعم'},
            ],
          })
            ..['show_manager_signature'] = false,
        },
      });
      await pumpSim(t, const SimVariant(390, dark: false), home: (_) => const PrintTemplatesScreen());
      expect(find.text('حجم الوصل'), findsOneWidget);
      expect(find.text('مضغوط'), findsOneWidget);
      expect(find.text('حقول مخفيّة'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('نصوص إضافيّة'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('تصميم v1 بلا تعديل: «عادي» و«لا شيء»', (t) async {
      server.reply('GET', '/api/v2/receipt-settings', 200, {
        'success': true,
        'data': {'shop_name': 'مكتب النور', 'show_qr': 1, 'auto_print': 0, 'design': null},
      });
      await pumpSim(t, const SimVariant(390, dark: false), home: (_) => const PrintTemplatesScreen());
      expect(find.text('عادي'), findsOneWidget);
      expect(find.text('لا شيء'), findsNWidgets(2));
      await simDrain(t);
    });
  });
}
