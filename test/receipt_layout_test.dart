import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/services/receipt_layout.dart';
import 'package:rad_mysvcs/services/receipt_pdf.dart';
import 'package:rad_mysvcs/services/receipt_pdf_v2.dart';


/// «تصميم الوصل» v2 في التطبيق (المالك ١ نوفمبر: «الطباعه اضافة ميزات اخفاء وتقليص الوصل والتحكم اكثر بالمتغيرات…»):
///   ١. المحلِّل هو محلِّل الموقع حرفاً بحرف — ملفّ التثبيت المشترك نسخةٌ بالبايت (بصمته مثبّتة هنا وفي الموقع)، ثوابته
///      وكلّ حالاته.
///   ٢. قراءة الإعدادات: بلا `layout` ⇒ طريق v1 كما كان؛ التالف افتراضيّ؛ «حجم الوصل» والعدّادات.
///   ٣. PDF: «مضغوط جداً» < «مضغوط» < «عادي»، وورق ٥٨، والمخفيّ لا يُرسم، وبلا تشكيلٍ ولا رموزٍ عند الرسم.
///   ٤. v3 (المصمّم الاحترافيّ): الضغط (compact_cases) والقوالب (template_cases) وصالحات الخادم، وتصاميم v2 كما هي
///      حرفاً (بند 29: المحلِّل الجديد على حالات الملفّ الأوّل المجمَّد = ناتجه بلا مفاتيح v3).
const _fixturePath = 'test/fixtures/receipt_layout.fixtures.json';
const _frozenPath = 'test/fixtures/receipt_layout.fixtures.v1.json';

/// البصمة المثبّتة — هي `RECEIPT_FIXTURES_SHA256` في الموقع. ملفٌّ تغيّر في جهةٍ واحدة يُسقط هذا الاختبار.
const _pinnedSha = '8e0aa26e3ab0a3773be82acdbd68ca2a4221ed81fad72bd5a9110792718821c5';

/// الملفّ الأوّل مجمَّداً (بند 29) — لا يتغيّر أبداً.
const _frozenSha = 'd18f3130a40e532cdaed7301fb32f6adfdd699cae87dde0a399a5e54f07614f1';

/// ناتج v3 بلا مفاتيحه الجديدة — ويذكر أيّ مفتاحٍ جديد خرج بغير قيمته الحياديّة (`stripV3` في فحص الموقع).
({Map<String, dynamic> out, List<String> bad}) _stripV3(Map<String, dynamic> r) {
  final out = jsonDecode(jsonEncode(r)) as Map<String, dynamic>;
  final bad = <String>[];
  void g(Map o, String w) {
    if (o['gap_before'] != 0 || o['gap_after'] != 0 || o['sep'] != null) bad.add(w);
    o
      ..remove('gap_before')
      ..remove('gap_after')
      ..remove('sep');
  }

  for (final b in (out['blocks'] as List).cast<Map<String, dynamic>>()) {
    final t = b['t'] as String;
    g(b, t);
    if (t == 'shop_name' || t == 'title' || t == 'text') {
      if (b['pt'] != null) bad.add('$t.pt');
      b.remove('pt');
    }
    if (t == 'shop_lines' || t == 'footer') {
      for (final l in (b['lines'] as List).cast<Map<String, dynamic>>()) {
        if (l['align'] != b['align'] || l['pt'] != null || l['stack'] != false) bad.add('${l['id']}');
        g(l, '${l['id']}');
        l
          ..remove('align')
          ..remove('pt')
          ..remove('stack');
      }
    }
    if (t == 'meta') {
      const keys = [
        'split', 'no_align', 'at_align', 'no_pt', 'at_pt', 'no_bold', 'at_bold', //
        'no_gap_before', 'no_gap_after', 'at_gap_before', 'at_gap_after',
      ];
      if (b['split'] == true ||
          b['no_align'] != null ||
          b['at_align'] != null ||
          b['no_pt'] != null ||
          b['at_pt'] != null ||
          b['no_bold'] == true ||
          b['at_bold'] == true ||
          b['no_gap_before'] != 0 ||
          b['no_gap_after'] != 0 ||
          b['at_gap_before'] != 0 ||
          b['at_gap_after'] != 0) {
        bad.add('meta');
      }
      for (final k in keys) {
        b.remove(k);
      }
    }
    if (t == 'section' || t == 'sale_items') {
      if (b['title_pt'] != null || b['title_align'] != null) bad.add('$t title');
      b
        ..remove('title_pt')
        ..remove('title_align');
    }
    if (t == 'section') {
      for (final row in (b['rows'] as List).cast<Map<String, dynamic>>()) {
        if (row['align'] != null || row['stack'] == true || row['pt'] != null || row['label_pt'] != null) {
          bad.add('${row['id']}');
        }
        g(row, '${row['id']}');
        row
          ..remove('align')
          ..remove('stack')
          ..remove('pt')
          ..remove('label_pt');
      }
    }
    if (t == 'qr') {
      if (b['caption_pt'] != null || b['caption_align'] != b['align'] || b['caption_bold'] == true) bad.add('qr caption');
      b
        ..remove('caption_pt')
        ..remove('caption_align')
        ..remove('caption_bold');
    }
  }
  return (out: out, bad: bad);
}

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
  final frozenBytes = File(_frozenPath).readAsBytesSync();
  final frozen = jsonDecode(utf8.decode(frozenBytes)) as Map<String, dynamic>;

  group('١. محلِّل الموقع حرفاً بحرف (ملفّ التثبيت المشترك)', () {
    test('الملفّ نسخةٌ بالبايت: بصمته هي المثبّتة هنا وفي المحلِّل', () {
      final sha = sha256.convert(bytes).toString();
      expect(sha, _pinnedSha, reason: 'غيّر الملفّ وبصمته في الموقع والتطبيق معاً');
      expect(receiptFixturesSha256, _pinnedSha);
      expect(fixture['schema'], 'receipt-layout-fixtures/2');
      expect(cases.length, greaterThanOrEqualTo(40), reason: 'c01–c30 بفروعها');
      expect(sha256.convert(frozenBytes).toString(), _frozenSha, reason: 'الملفّ الأوّل مجمَّد');
      expect(frozen['schema'], 'receipt-layout-fixtures/1');
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

  group('١ب. v3: الضغط والقوالب، وv2 كما هو (بند 29)', () {
    test('بند 29: حالات الملفّ الأوّل بمحلِّل v3 = ناتجها القديم + مفاتيحٌ حياديّة وحدها', () {
      final old = (frozen['cases'] as List).cast<Map<String, dynamic>>();
      final byName = {for (final c in cases) c['name']: c};
      for (final c in old) {
        final now = byName[c['name']];
        expect(now, isNotNull, reason: '${c['name']} حُذفت من الملفّ الثاني');
        expect(now!['design'], equals(c['design']), reason: '${c['name']}: تغيّر مُدخلها');
        expect(now['input'], equals(c['input']), reason: '${c['name']}: تغيّر مُدخلها');
        final got = ReceiptResolver.resolve(c['design'], ReceiptInput.fromJson(c['input'] as Map<String, dynamic>)).toJson();
        final r = _stripV3(got);
        expect(r.bad, isEmpty, reason: '${c['name']}: مفتاح v3 بغير قيمته الحياديّة');
        expect(r.out, equals(c['expected']), reason: '${c['name']}');
      }
      expect(old.length, 21);
    });

    for (final k in (fixture['compact_cases'] as List).cast<Map<String, dynamic>>()) {
      test('ضغط ${k['name']}', () {
        expect(receiptCompactLayout(k['input']), equals(k['expected']), reason: '${k['note']}');
      });
    }

    for (final t in (fixture['template_cases'] as List).cast<Map<String, dynamic>>()) {
      test('قالب ${t['name']}', () {
        final input = jsonDecode(jsonEncode(t['input'])) as Map<String, dynamic>;
        final got = receiptApplyTemplate(
          (
            paperSize: input['paper_size'] as String,
            design: Map<String, dynamic>.from(input['design'] as Map),
            layout: input['layout'] is Map ? Map<String, dynamic>.from(input['layout'] as Map) : null,
          ),
          t['template'] as String,
        );
        expect({'paper_size': got.paperSize, 'design': got.design, 'layout': got.layout}, equals(t['expected']));
        expect(receiptCompactLayout(got.layout), equals(t['expected_compact']));
        final il = (input['layout'] as Map?) ?? const {};
        for (final k in const ['fields', 'texts', 'titles', 'emoji']) {
          expect(got.layout[k], equals(il[k]), reason: 'القالب لا يمسّ $k');
        }
      });
    }

    test('صالحات الخادم: الضغط لا يغيّر الوصل، ولا يحفظ خاصيّةً خارج قدرات العنصر', () {
      final bases = [
        for (final c in cases)
          if (RegExp(r'^c0[14]_|^c11a_|^c12_|^c14_').hasMatch(c['name'] as String)) c['input'] as Map<String, dynamic>,
      ];
      expect(bases, hasLength(5));
      var n = 0;
      for (final c in (fixture['sanitize_cases'] as List).cast<Map<String, dynamic>>()) {
        if (!c.containsKey('expect') || c['expect'] == null) continue;
        n++;
        final packed = receiptCompactLayout(c['expect']);
        for (final inp in bases) {
          final a = ReceiptResolver.resolve({'layout': c['expect']}, ReceiptInput.fromJson(inp)).toJson();
          final b = ReceiptResolver.resolve({'layout': packed}, ReceiptInput.fromJson(inp)).toJson();
          expect(b, equals(a), reason: '${c['name']}: الضغط غيّر وصل ${inp['kind']}');
        }
        final fields = (packed?['fields'] as Map?) ?? const {};
        for (final e in fields.entries) {
          for (final p in (e.value as Map).keys) {
            expect(receiptFieldCaps[e.key]!.contains(p), isTrue, reason: '${c['name']}: ${e.key}.$p ليست من قدراته');
          }
        }
      }
      expect(n, greaterThanOrEqualTo(3));
    });

    test('labelPt وuiPt وpinnedCount وunpinAll وlayoutDiff', () {
      expect([receiptLabelPt(12), receiptLabelPt(14), receiptLabelPt(9)], [11, 12.5, 8]);
      final design = {'font_size_base': 13, 'font_size_title': 16};
      expect(receiptUiPt(design, null, field: 'username'), (pt: 9, pinned: false));
      expect(receiptUiPt(design, {'fields': {'username': {'pt': 12}}}, field: 'username'), (pt: 12, pinned: true));
      expect(receiptUiPt(design, null, field: 'shop_name').pt, 12);
      expect(receiptUiPt(design, null, field: 'qr_caption').pt, 7.5);
      expect(receiptUiPt(design, null, section: 'package').pt, 8.5, reason: 'round(13×0.85)=11px ⇒ 8.25 ⇒ نصف نقطة 8.5');
      final l = {
        'v': 3,
        'fields': {'username': {'pt': 12, 'size': 'lg'}, 'phone': {'pt': 9}},
        'sections': {'package': {'pt': 10}},
        'texts': [{'at': 'top', 'text': 'x', 'pt': 7}],
      };
      expect(receiptPinnedCount(l), 4);
      final un = receiptUnpinAll(l);
      expect(receiptPinnedCount(un), 0);
      expect((un['fields'] as Map)['username'], {'size': 'lg'});
      expect(
          receiptLayoutDiff({'v': 3, 'fields': {'username': {'pt': 9}}}, {'v': 3, 'fields': {'username': {'pt': 9.0}}}),
          isEmpty);
      expect(receiptLayoutDiff({'v': 3, 'fields': {'username': {'pt': 12}}, 'currency': 'IQD'}, {'v': 3}),
          unorderedEquals(['fields', 'currency']));
      expect(
        receiptLayoutDiff({'texts': [{'at': 'bottom', 'text': 'a'}]}, {'texts': [{'at': 'bottom', 'text': 'b'}]}),
        ['texts[0].text'],
      );
    });

    // الخادم ينظّف كلّ نصّ (cleanStr): NFC، و\r\n ⇒ \n، والجدولة ⇒ فراغ، بلا محارف تحكّم ولا قلب اتّجاه ولا U+FEFF، وبلا
    // فراغٍ في آخر كلّ سطرٍ ولا في الطرفين. القيم المتوقّعة هنا ناتج cleanStr الحقيقيّ (Node، Unicode 16 كالخادم).
    test('receiptServerCleanText = cleanStr الخادم (أسطرٌ للنصوص، وسطرٌ لغيرها)', () {
      final cases = <(String, String, String)>[
        // (المكتوب، أسطر، سطر)
        ('سدّد قبل {expiry_date} ', 'سدّد قبل {expiry_date}', 'سدّد قبل {expiry_date}'),
        ('شكراً لكم\n', 'شكراً لكم', 'شكراً لكم'),
        (' سطر\r\nثانٍ ', 'سطر\nثانٍ', 'سطر ثانٍ'),
        ('x  \ny \t', 'x\ny', 'x   y'),
        ('\u2068{phone}\u2069 ', '{phone}', '{phone}'),
        ('\u200Fنص ', '\u200Fنص', '\u200Fنص'), // RLM يبقى
        ('a\u0085', 'a\u0085', 'a\u0085'), // NEL ليس فراغاً عند JavaScript (يحذفه String.trim في Dart)
        ('م\u064Fحم\u0651\u064Eد', 'م\u064Fحم\u064E\u0651د', 'م\u064Fحم\u064E\u0651د'), // NFC: الفتحة قبل الشدّة
        ('ا\u0654', '\u0623', '\u0623'), // NFC: ا + همزة ⇒ أ
        ('ب\u0651\u202B\u064E', 'ب\u0651\u064E', 'ب\u0651\u064E'), // NFC قبل حذف العزل: الترتيب يبقى
        ('  ', '', ''),
      ];
      for (final (typed, multi, one) in cases) {
        expect(receiptServerCleanText(typed, multiline: true), multi, reason: jsonEncode(typed));
        expect(receiptServerCleanText(typed), one, reason: jsonEncode(typed));
      }
    });

    test('ما حفظه الخادم بعد تنظيفه = ما أُرسل: s03 والنصوص بفراغٍ أو سطرٍ في آخرها لا تُنذر «لم يحفظ»', () {
      // s03: تصميمٌ ينظّفه الخادم بلا خطأ؛ expect = ناتج الخادم الصارم له. المُرسل = ضغط التطبيق للتصميم كما كُتب.
      final s03 = (fixture['sanitize_cases'] as List).cast<Map<String, dynamic>>().firstWhere(
            (c) => (c['name'] as String).startsWith('s03'),
          );
      final sent = receiptCompactLayout(s03['layout'])!;
      final stored = receiptCompactLayout(s03['expect'])!;
      expect((sent['texts'] as List).first['text'], isNot((stored['texts'] as List).first['text']),
          reason: 'النصّ أُرسل كما كُتب (« سطر\\r\\nثانٍ ») والخادم نظّفه');
      expect(receiptLayoutDiff(sent, stored), isEmpty);

      List<Map<String, dynamic>> texts(List<String> xs) => [
            for (var i = 0; i < xs.length; i++) {'id': 't${i + 1}', 'at': 'bottom', 'text': xs[i]},
          ];
      // مثال المراجعة نفسه: كيبورد الهاتف يضيف فراغاً بعد الكلمة المقترحة.
      expect(
        receiptLayoutDiff(
          {'v': 3, 'texts': texts(['سدّد قبل {expiry_date} ', 'شكراً لكم\n'])},
          {'v': 3, 'texts': texts(['سدّد قبل {expiry_date}', 'شكراً لكم'])},
        ),
        isEmpty,
      );
      // ترتيب الحركات (NFC)، وعلامتان فصلهما عزلٌ يحذفه الخادم بعد NFC.
      expect(
        receiptLayoutDiff(
          {'v': 3, 'texts': texts(['م\u064Fحم\u0651\u064Eد', 'ب\u0651\u202B\u064E'])},
          {'v': 3, 'texts': texts(['مُحمَّد', 'بَّ'])},
        ),
        isEmpty,
      );
      // نصٌّ لا يبقى منه شيء بعد التنظيف يُسقطه الخادم وتُرقَّم النصوص بعده.
      expect(
        receiptLayoutDiff({'v': 3, 'texts': texts(['\u202B\u202C', 'ثالث'])}, {'v': 3, 'texts': texts(['ثالث'])}),
        isEmpty,
      );
      // تسميةٌ بعزلٍ حول الافتراضيّة: الخادم يحفظها الافتراضيّة، فلا تُحفظ في الضغط.
      final def = receiptFieldDefs['amount']!.label;
      expect(receiptLayoutDiff({'v': 3, 'fields': {'amount': {'label': '\u2068$def\u2069'}}}, {'v': 3}), isEmpty);

      // وما لم يُحفظ فعلاً يُقال بمساره.
      expect(
        receiptLayoutDiff({'v': 3, 'texts': texts(['سدّد قبل {expiry_date} '])}, {'v': 3, 'texts': texts(['سدّد قبل'])}),
        ['texts[0].text'],
      );
      expect(receiptLayoutDiff({'v': 3, 'texts': texts(['أوّل', 'ثانٍ'])}, {'v': 3, 'texts': texts(['أوّل'])}),
          ['texts[1]']);
      expect(receiptLayoutDiff({'v': 3, 'fields': {'amount': {'label': 'المدفوع '}}}, {'v': 3}), ['fields']);
      expect(
        receiptLayoutDiff(
          {'v': 3, 'fields': {'amount': {'label': 'المدفوع', 'pt': 12}}},
          {'v': 3, 'fields': {'amount': {'label': 'المدفوع'}}},
        ),
        ['fields.amount.pt'],
      );
    });
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
}
