import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/national_wallet_api.dart';
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/screens/print_templates/designer/designer_controller.dart';

/// ٢ نوفمبر: وصلٌ مصمَّمٌ بالسحب والتحريك (layout v4 «الشبكة») — قالبٌ جاهز أو «أسود فقط» من مصمّم التطبيق كان يُدخل خيارات
/// المعتاد (density/mono) في الشبكة فيرفض الخادم الحفظ كلّه «خيارٌ لا يعرفه الخادم: mono». الآن: الورق والأحجام ومعلومات المحلّ
/// تُحفظ مع الشبكة كما هي، وخيارات المعتاد ترجعه للمعتاد بتأكيد (willDropGrid).
const _grid = {
  'v': 4,
  'grid': {
    'rows': [
      {'id': 'r1', 'cells': [{'id': 'c1', 'type': 'text', 'text': '{shop_name}'}]},
      {'id': 'r2', 'cells': [{'id': 'c2', 'type': 'field', 'var': 'subscriber_name', 'label': 'اسم المشترك'}]},
    ],
  },
};

Map<String, dynamic> _row(Map<String, dynamic>? design) => {
      'shop_name': 'محل تجربة',
      'show_qr': 1,
      'paper_size': 'pos',
      'auto_print': 0,
      'design': design,
      'updated_at': '2026-11-01T07:05:00.000Z',
    };

Future<(ReceiptDesignController, List<Map<String, dynamic>>)> _ctl(Map<String, dynamic>? design) async {
  final sent = <Map<String, dynamic>>[];
  final c = ReceiptDesignController(
    fetch: () async => ReceiptDesignLoad.ok(ReceiptSettings.fromJson(_row(design))),
    save: (body) async {
      sent.add(jsonDecode(jsonEncode(body)) as Map<String, dynamic>);
      return ReceiptSaveResult(
        ok: true,
        status: 200,
        message: 'تم',
        design: Map<String, dynamic>.from(body['design'] as Map),
        hasDesign: true,
        updatedAt: '2026-11-01T08:00:00.000Z',
        hasUpdatedAt: true,
      );
    },
  );
  await c.load();
  return (c, sent);
}

void main() {
  test('وصل الشبكة: قالبٌ جاهز (كاشير ٥٨) يضبط الورق ويُبقي الشبكة كما هي — بلا density/mono', () async {
    final (c, sent) = await _ctl({'paper_width_mm': 80, 'layout': _grid});
    expect(c.isGrid, isTrue);
    c.applyTemplate('pos58_compact');
    expect(c.willDropGrid, isFalse, reason: 'القالب لا يمسّ خيارات المعتاد في وصل الشبكة');
    final r = await c.save();
    expect(r.ok, isTrue);
    final d = sent.single['design'] as Map;
    expect(d['paper_width_mm'], 58);
    expect(d['layout'], _grid, reason: 'الشبكة كما حُمّلت حرفاً');
    expect((d['layout'] as Map).containsKey('mono'), isFalse);
    expect(r.notSaved, isEmpty, reason: 'لا «لم يحفظ الخادم» على الشبكة');
    expect(c.isGrid, isTrue, reason: 'بعد الحفظ ما زال وصل الشبكة');
  });

  test('وصل الشبكة: «أسود فقط» (خيار المعتاد) ⇒ willDropGrid، والحفظ يرسل المعتاد v3 بلا الشبكة', () async {
    final (c, sent) = await _ctl({'paper_width_mm': 80, 'layout': _grid});
    c.setLayoutKey('mono', true);
    expect(c.willDropGrid, isTrue);
    await c.save();
    final l = (sent.single['design'] as Map)['layout'] as Map;
    expect(l['v'], 3);
    expect(l['mono'], isTrue);
    expect(l.containsKey('grid'), isFalse);
  });

  test('وصلٌ معتاد (بلا شبكة): القالب يكتب الكثافة و«أسود فقط» كما كان', () async {
    final (c, sent) = await _ctl({'paper_width_mm': 80});
    expect(c.isGrid, isFalse);
    c.applyTemplate('pos58_compact');
    expect(c.willDropGrid, isFalse);
    await c.save();
    final l = (sent.single['design'] as Map)['layout'] as Map;
    expect(l['mono'], isTrue);
    expect(l['density'], 'compact');
  });

  group('محفظة المشترك في شيت التفعيل (CustomerWalletInfo)', () {
    test('غائبة أو ليست كائناً ⇒ null (الخيار مخفيّ)', () {
      expect(CustomerWalletInfo.of(null), isNull);
      expect(CustomerWalletInfo.of('x'), isNull);
      expect(CustomerWalletInfo.of(true), isNull);
    });
    test('enough من الخادم يُحترم، وإلّا يُحسب من الرصيد والسعر', () {
      final a = CustomerWalletInfo.of({'balance': 20000, 'price': 35000, 'enough': false, 'topup': true})!;
      expect([a.balance, a.price, a.enough, a.topup, a.shortBy], [20000, 35000, false, true, 15000]);
      final b = CustomerWalletInfo.of({'balance': '50000', 'price': 35000})!;
      expect([b.enough, b.shortBy, b.topup], [true, null, false]);
    });
    test('رصيدٌ غير مقروء ⇒ enough null (يُتحقَّق عند التفعيل) ولا «ينقصه»', () {
      final c = CustomerWalletInfo.of({'balance': null, 'price': 35000, 'topup': true})!;
      expect([c.balance, c.enough, c.shortBy], [null, null, null]);
    });
  });
}
