import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/earthlink_api.dart';
import 'package:rad_mysvcs/api/el_deposit_password.dart';
import 'package:rad_mysvcs/screens/el/card_order_screen.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_harness.dart';

/// محاكاة «طلب الكارتات» لايرث لنك (`el/card_order_screen.dart`) — مالٌ حقيقيّ
/// يُخصم من رصيد الإيداع، فما يُحرس فوق الرسم (عقد الخادم ~/q2_elrest):
///   • لا إرسال بلا تأكيد بتقدير الخادم (`POST /api/v2/el/card-order/quote`):
///     سعر الكارت لدى ايرث لنك × العدد، والرصيد قبل وبعد.
///   • العقد: `POST /api/v2/el/card-order` بـ`cards:[{profile_id,count}]` +
///     `expected_total` (مجموع التقدير) + `request_id` + باسورد الإيداع في
///     **الجسم** — نداءٌ واحد لا يُعاد تلقائيّاً.
///   • حارس التكرار: الطلب نفسه بعد قليل (هنا أو عند الخادم 409) ⇒ إقرارٌ
///     صريح ثمّ `confirmRepeat`.
///   • `COST_CHANGED` ⇒ تقديرٌ جديد وتأكيدٌ من جديد بالكلفة الجديدة.
///   • غير المؤكَّد (مهلة/`ORDER_UNCONFIRMED`): تنبيهٌ باقٍ + تحديث السجلّ؛
///     وطلبٌ جديدٌ فعلاً بعده = إقرارٌ **بمفتاحٍ جديد** (المفتاح القديم بعد غموض
///     يرفضه الخادم `ORDER_UNRESOLVED`، والإقرار طلبٌ آخر لا إعادةٌ للأوّل).
///   • «لا يكفي» تنبيهٌ لا منع (ايرث لنك تحكم الرصيد؛ الكلفة تقدير).
///   • السجلّ: الحالات بالعربيّة والتاريخ مقروءاً، وبلا PIN ولا أرقام كارتات.
const _screen = 'el_card_order';
const _orderPath = '/api/v2/el/card-order';
const _quotePath = '/api/v2/el/card-order/quote';
const _ordersPath = '/api/v2/el/card-orders';
const _neededPath = '/api/v2/el/prepaid-needed';
const _secret = 'Dep#4417secret';

/// «الكارتات المطلوبة» (accountCost — كلفة التفعيل).
List<Map<String, Object?>> _packages() => [
      {
        'profile_id': 7,
        'name': 'Economy',
        'cost': 20000,
        'available': 12,
        'used': 30,
        'needed': 18,
        'image': null,
      },
      {
        'profile_id': 12,
        'name': 'Ta3leem 50,000 Plus 3 Months (طلاب الجامعات)',
        'cost': 93000,
        'available': 0,
        'used': 4,
        'needed': 4,
        'image': null,
      },
      {
        'profile_id': 13,
        'name': 'Business Pro 100M',
        'cost': 180000,
        'available': 3,
        'used': 0,
        'needed': 0,
        'image': null,
      },
    ];

/// سعر الكارت لدى ايرث لنك (accountPrice — ما يحسبه تقدير الخادم).
final Map<int, int> _price = {7: 22000, 12: 95000, 13: 185000, 14: 30000};
const _names = {
  7: 'Economy',
  12: 'Ta3leem 50,000 Plus 3 Months (طلاب الجامعات)',
  13: 'Business Pro 100M',
  14: 'Turbo',
};

/// باقات الموزّع (`/v2/packages`) — و«Turbo» ليست في «الكارتات المطلوبة».
List<Map<String, Object?>> _pkgList() => [
      for (final e in _names.entries)
        {'id': e.key, 'name': e.value, 'price': 35000, 'cost_price': 20000},
    ];

/// تقدير الخادم (elCards.quoteOrder) من جسم الطلب.
SimReply _quote(RequestOptions o, {int balance = 1250000}) {
  final cards = ((o.data as Map)['cards'] as List).cast<Map>();
  final items = <Map<String, Object?>>[];
  var total = 0;
  var count = 0;
  for (final c in cards) {
    final id = c['profile_id'] as int;
    final n = c['count'] as int;
    final unit = _price[id]!;
    total += unit * n;
    count += n;
    items.add({
      'profile_id': id,
      'name': _names[id],
      'count': n,
      'unit_cost': unit,
      'total': unit * n,
    });
  }
  return SimReply(200, {
    'success': true,
    'data': {
      'items': items,
      'unknown': const <int>[],
      'total': total,
      'balance': balance,
      'enough': balance >= total,
      'after': balance - total,
      'count': count,
      'currency': 'IQD',
      'expected_total': total,
      'note': 'الكلفة تقديرٌ بسعر الكارت لدى ايرث لنك — المبلغ النهائيّ ما تخصمه ايرث لنك من رصيد الإيداع',
    },
  });
}

/// السجلّ بشكل الخادم (earthlinkAdapter.getCardOrders) — وحالة ايرث لنك نصّاً.
List<Map<String, Object?>> _orders() => [
      {
        'batch_no': 5521,
        'status': 'Pending',
        'created_at': '18/10/2026 02:05 PM',
        'can_cancel': true,
        'cards': [
          {'name': 'Economy', 'amount': 20, 'price': 22000, 'approved_count': 0},
        ],
      },
      {
        'batch_no': 5498,
        'status': 'Approved',
        'created_at': '2026-10-11T09:30:00',
        'can_cancel': false,
        'cards': [
          {'name': 'Economy', 'amount': 10, 'price': 22000, 'approved_count': 10},
          {
            'name': 'Ta3leem 50,000 Plus 3 Months (طلاب الجامعات)',
            'amount': 2,
            'price': 95000,
            'approved_count': 2,
          },
        ],
      },
      {
        'batch_no': 5400,
        'status': 'Rejected',
        'created_at': '01/10/2026 11:00 AM',
        'can_cancel': false,
        'cards': [
          {'name': 'Business Pro 100M', 'amount': 1, 'price': 185000, 'approved_count': 0},
        ],
      },
    ];

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp();
    ProviderService.debugSet('earthlink');
    ElDepositPassword.reset();
    debugClearElCardOrderRecent();
    server.reply('GET', '/api/v2/admin-widgets', 200, {
      'success': true,
      'balance': 1250000,
      'points': 3,
      'cards': {'remaining': null},
    });
    server.on('GET', _neededPath,
        (_) => SimReply(200, {'success': true, 'data': _packages(), 'days': 7}));
    server.reply(
        'GET', _ordersPath, 200, {'success': true, 'data': <Object>[], 'total': 0});
    // السجلّ بباسورد مكتوب (لا محفوظ) يُطلب POST بالباسورد في الجسم.
    server.reply(
        'POST', _ordersPath, 200, {'success': true, 'data': <Object>[], 'total': 0});
    server.on('POST', _quotePath, (o) => _quote(o));
    server.on('GET', '/api/v2/packages',
        (_) => SimReply(200, {'success': true, 'data': _pkgList()}));
    server.reply('POST', _orderPath, 200,
        {'success': true, 'message': 'تم إرسال طلب الكروت'});
  });

  Future<void> open(WidgetTester t, SimVariant v,
      {Map<int, int>? counts}) async {
    await pumpSim(t, v,
        home: (_) => ElCardOrderScreen(days: 7, initialCounts: counts));
    expect(find.text('طلب الكارتات'), findsOneWidget);
  }

  /// القائمة كسولة: ما خارج الشاشة لا يُبنى — نعود لأعلاها ثمّ نمرّر إليه.
  Future<void> reveal(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) {
      // قفزةٌ لأعلى القائمة لا سحب: السحب عند القمّة يُطلق «اسحب للتحديث».
      final list = find.byType(Scrollable).first;
      final pos = t.state<ScrollableState>(list).position;
      pos.jumpTo(pos.minScrollExtent);
      await t.pumpAndSettle();
      if (f.evaluate().isEmpty) {
        await t.scrollUntilVisible(f, 200, scrollable: list);
      }
    }
    await t.ensureVisible(f.first);
    await t.pumpAndSettle();
  }

  bool enabled(WidgetTester t, Finder label) {
    final ink = t.widget<InkWell>(
        find.ancestor(of: label, matching: find.byType(InkWell)).first);
    return ink.onTap != null;
  }

  Finder review() => find.textContaining('مراجعة الطلب');

  /// زرّ المُعدِّد بتسميته لقارئ الشاشة («زيادة Economy»).
  Finder step(String label) => find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == label,
      description: 'زرّ «$label»');
  Finder pass() => find.widgetWithText(TextField, '••••••');

  Future<void> typePassword(WidgetTester t) async {
    await reveal(t, pass());
    await t.enterText(pass(), _secret);
    await t.pumpAndSettle();
  }

  Future<void> openConfirm(WidgetTester t) async {
    await reveal(t, review());
    await t.tap(review());
    await t.pumpAndSettle();
    expect(find.text('تأكيد طلب الكارتات'), findsOneWidget);
  }

  Future<void> acknowledge(WidgetTester t) async {
    await reveal(t, find.text('أعرف — أريد طلباً جديداً فعلاً'));
    await t.tap(find.text('أعرف — أريد طلباً جديداً فعلاً'));
    await t.pumpAndSettle();
  }

  Finder confirmButton() => find.textContaining('تأكيد الطلب —');

  /// الطلبات المُرسَلة (لا التقدير).
  List<Map<String, dynamic>> orders() => server.bodies('POST', _orderPath);

  /// آخر تقديرٍ أُرسل (المراجعة — بعد التقدير الأوّليّ للأسعار).
  Map<String, dynamic> lastQuote() => server.bodies('POST', _quotePath).last;

  // ─────────────────────────── الشاشة ───────────────────────────

  simCase(_screen, 'loaded_empty', (t, v) async {
    await open(t, v);
    expect(find.text('1,250,000'), findsOneWidget);
    expect(find.text('Economy'), findsOneWidget);
    expect(find.text('املأ بالمطلوب'), findsOneWidget);
    expect(enabled(t, review()), isFalse, reason: 'لا كارت مختار');
    // سعر الكارت من تقدير الخادم الأوّليّ (لا كلفة «الكارتات المطلوبة»).
    expect(find.textContaining('سعر الكارت 22,000 د.ع'), findsOneWidget);
    final first = server.bodies('POST', _quotePath).single;
    expect(first['cards'], [
      {'profile_id': 7, 'count': 1},
      {'profile_id': 12, 'count': 1},
      {'profile_id': 13, 'count': 1},
      {'profile_id': 14, 'count': 1},
    ]);
    // «Turbo» من قائمة الموزّع ولو غابت عن «الكارتات المطلوبة» — بلا «المتوفّر».
    await reveal(t, find.text('Turbo'));
    expect(find.text('سعر الكارت 30,000 د.ع'), findsOneWidget);
    expect(orders(), isEmpty, reason: 'التقدير قراءةٌ — لا طلب');
    await simCheck(t, v, _screen, 'loaded_empty');
    await reveal(t, find.text('لا طلبات كارتات سابقة'));
    await simCheck(t, v, _screen, 'history_empty');
    expect(server.calls('GET', _neededPath).single.queryParameters['days'], 7);
  });

  simCase(_screen, 'prices_estimate_fallback', (t, v) async {
    // التقدير الأوّليّ يتعذّر ⇒ كلفة «الكارتات المطلوبة» معلَّمةً «≈».
    server.reply('POST', _quotePath, 503,
        {'success': false, 'message': 'تعذّر حساب كلفة الطلب — أعد المحاولة'});
    await open(t, v, counts: const {7: 2});
    expect(find.textContaining('سعر الكارت ≈ 20,000 د.ع'), findsOneWidget);
    expect(find.text('المجموع ≈ 40,000 د.ع'), findsOneWidget);
    await simCheck(t, v, _screen, 'prices_estimate_fallback');
  });

  simCase(_screen, 'fill_needed', (t, v) async {
    await open(t, v);
    await t.tap(find.text('املأ بالمطلوب'));
    await t.pumpAndSettle();
    // ١٨ × ٢٢٬٠٠٠ + ٤ × ٩٥٬٠٠٠ = ٧٧٦٬٠٠٠ — وBusiness (مطلوب ٠) لا يُملأ.
    expect(find.text('المجموع 396,000 د.ع'), findsOneWidget);
    expect(find.text('المجموع 380,000 د.ع'), findsOneWidget);
    await reveal(t, find.text('776,000 د.ع'));
    expect(find.text('22'), findsWidgets, reason: 'عدد الكارتات بالملخّص');
    await simCheck(t, v, _screen, 'fill_needed');
  });

  simCase(_screen, 'stepper', (t, v) async {
    await open(t, v);
    final plus = step('زيادة Business Pro 100M');
    await reveal(t, plus);
    await t.tap(plus);
    await t.tap(plus);
    await t.pumpAndSettle();
    expect(find.text('المجموع 370,000 د.ع'), findsOneWidget,
        reason: 'نقرتان متتاليتان = اثنتان');
    final minus = step('إنقاص Business Pro 100M');
    await t.tap(minus);
    await t.pumpAndSettle();
    expect(find.text('المجموع 185,000 د.ع'), findsOneWidget);
    await simCheck(t, v, _screen, 'stepper');
  });

  simCase(_screen, 'confirm_sheet', (t, v) async {
    await open(t, v, counts: const {7: 18, 12: 4});
    await typePassword(t);
    expect(enabled(t, review()), isTrue);
    await openConfirm(t);
    expect(lastQuote()['cards'], [
      {'profile_id': 7, 'count': 18},
      {'profile_id': 12, 'count': 4},
    ]);
    expect(find.text('18 كارت × 22,000 د.ع'), findsOneWidget);
    expect(find.text('4 كارت × 95,000 د.ع'), findsOneWidget);
    expect(find.text('الكلفة — 22 كارت'), findsOneWidget);
    expect(find.text('776,000 د.ع'), findsWidgets);
    expect(find.text('474,000 د.ع'), findsWidgets, reason: 'الرصيد بعده');
    expect(find.textContaining('لا يُلغى'), findsOneWidget);
    await simCheck(t, v, _screen, 'confirm_sheet');
    // الإغلاق ⇒ لا طلب.
    await t.tap(find.byIcon(Icons.close_rounded));
    await t.pumpAndSettle();
    expect(orders(), isEmpty);
  });

  simCase(_screen, 'order_ok_contract', (t, v) async {
    await open(t, v, counts: const {7: 18, 12: 4});
    await typePassword(t);
    await openConfirm(t);
    await t.tap(confirmButton());
    await t.pumpAndSettle();
    final calls = server.calls('POST', _orderPath);
    expect(calls, hasLength(1), reason: 'نداءٌ واحد');
    final req = calls.single;
    expect(req.uri.query, isEmpty);
    expect(Uri.decodeFull(req.uri.toString()), isNot(contains(_secret)));
    final body = Map<String, dynamic>.from(req.data as Map);
    expect(body['cards'], [
      {'profile_id': 7, 'count': 18},
      {'profile_id': 12, 'count': 4},
    ]);
    expect(body['expected_total'], 776000, reason: 'مجموع التقدير الذي رآه');
    expect(body['depositPassword'], _secret);
    expect('${body['request_id']}', matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(body.containsKey('confirmRepeat'), isFalse);
    expect(find.text('تم إرسال طلب الكروت'), findsOneWidget);
    expect(find.text('المجموع 396,000 د.ع'), findsNothing, reason: 'الأعداد مُسحت');
    // السجلّ تحدّث — بالباسورد المكتوب في **جسم** POST، لا في الرابط.
    expect(server.calls('GET', _ordersPath), hasLength(1), reason: 'أوّل فتح');
    final refresh = server.calls('POST', _ordersPath);
    expect(refresh, hasLength(1), reason: 'السجلّ تحدّث');
    expect(refresh.single.uri.query, isEmpty);
    expect((refresh.single.data as Map)['depositPassword'], _secret);
    expect(server.calls('GET', '/api/v2/admin-widgets'), hasLength(2));
    await simCheck(t, v, _screen, 'order_ok');
    await simDrain(t);
  });

  simCase(_screen, 'duplicate_guard', (t, v) async {
    await open(t, v, counts: const {7: 18});
    await typePassword(t);
    await openConfirm(t);
    await t.tap(confirmButton());
    await t.pumpAndSettle();
    expect(orders(), hasLength(1));
    await simDrain(t);
    // الطلب نفسه مرّةً ثانية.
    await reveal(t, find.text('املأ بالمطلوب'));
    await t.tap(find.text('املأ بالمطلوب'));
    await t.pumpAndSettle();
    final minusTaleem =
        step('إنقاص Ta3leem 50,000 Plus 3 Months (طلاب الجامعات)');
    await reveal(t, minusTaleem);
    for (var i = 0; i < 4; i++) {
      await t.tap(minusTaleem);
    }
    await t.pumpAndSettle();
    await openConfirm(t);
    expect(find.textContaining('طلبتَ الكارتات نفسها'), findsOneWidget);
    expect(enabled(t, confirmButton()), isFalse, reason: 'بلا إقرار');
    await reveal(t, find.text('أعرف — أريد طلباً جديداً فعلاً'));
    await simCheck(t, v, _screen, 'duplicate_guard');
    await acknowledge(t);
    expect(enabled(t, confirmButton()), isTrue);
    await t.tap(confirmButton());
    await t.pumpAndSettle();
    expect(orders(), hasLength(2));
    expect(orders().last['confirmRepeat'], isTrue);
    expect(orders().map((b) => b['request_id']).toSet(), hasLength(2),
        reason: 'بعد النجاح مفتاحٌ جديد لطلبٍ جديد');
    await simDrain(t);
  });

  simCase(_screen, 'server_repeat_guard', (t, v) async {
    // طلبٌ من جهازٍ آخر لا يعرفه التطبيق: الخادم يردّ 409 ⇒ إقرارٌ ثمّ إعادة.
    var n = 0;
    server.on('POST', _orderPath, (o) {
      n++;
      if ((o.data as Map)['confirmRepeat'] == true) {
        return const SimReply(
            200, {'success': true, 'message': 'تم إرسال طلب الكروت'});
      }
      return const SimReply(409, {
        'success': false,
        'code': 'RECENT_DUPLICATE',
        'message':
            'طلبت الكروت نفسها قبل 3 دقيقة — راجع سجلّ الطلبات، وإن أردت طلباً ثانياً فأكّده',
      });
    });
    await open(t, v, counts: const {7: 5});
    await typePassword(t);
    await openConfirm(t);
    await t.tap(confirmButton());
    await t.pumpAndSettle();
    expect(n, 1);
    expect(find.text('تأكيد طلب الكارتات'), findsOneWidget, reason: 'التأكيد عاد');
    expect(find.textContaining('قبل 3 دقيقة'), findsWidgets);
    expect(enabled(t, confirmButton()), isFalse);
    await simCheck(t, v, _screen, 'server_repeat_guard');
    await acknowledge(t);
    await t.tap(confirmButton());
    await t.pumpAndSettle();
    expect(n, 2);
    expect(orders().last['confirmRepeat'], isTrue);
    expect(orders()[0]['request_id'], isNot(orders()[1]['request_id']),
        reason: 'الإقرار طلبٌ جديد ⇒ مفتاحٌ جديد (الأوّل رُفض قبل الإرسال فلا أثر له)');
    expect(find.text('تم إرسال طلب الكروت'), findsOneWidget);
    await simDrain(t);
  });

  simCase(_screen, 'cost_changed', (t, v) async {
    var first = true;
    server.on('POST', _orderPath, (o) {
      if (first) {
        first = false;
        _price[7] = 23000; // ايرث لنك رفعت السعر بين المراجعة والطلب
        return const SimReply(409, {
          'success': false,
          'code': 'COST_CHANGED',
          'message': 'تغيّرت كلفة الكروت منذ المراجعة — راجع الطلب من جديد',
          'data': {'expected_total': 115000},
        });
      }
      return const SimReply(
          200, {'success': true, 'message': 'تم إرسال طلب الكروت'});
    });
    addTearDown(() => _price[7] = 22000);
    await open(t, v, counts: const {7: 5});
    await typePassword(t);
    await openConfirm(t);
    await t.tap(confirmButton());
    await t.pumpAndSettle();
    expect(find.textContaining('هذه الكلفة الجديدة'), findsOneWidget);
    expect(find.text('5 كارت × 23,000 د.ع'), findsOneWidget);
    await simCheck(t, v, _screen, 'cost_changed');
    await t.tap(confirmButton());
    await t.pumpAndSettle();
    expect(orders().map((b) => b['expected_total']), [110000, 115000]);
    await simDrain(t);
  });

  simCase(_screen, 'unclear_unconfirmed', (t, v) async {
    server.reply('POST', _orderPath, 502, {
      'success': false,
      'code': 'ORDER_UNCONFIRMED',
      'message':
          'لم يصل ردّ ايرث لنك — ربما أُرسل الطلب؛ راجع سجلّ الطلبات قبل أن تطلب ثانيةً',
    });
    await open(t, v, counts: const {7: 5});
    await typePassword(t);
    await openConfirm(t);
    await t.tap(confirmButton());
    await t.pumpAndSettle();
    expect(orders(), hasLength(1), reason: 'لا إعادة');
    expect(find.textContaining('لم يصل ردّ ايرث لنك'), findsOneWidget);
    expect(server.calls('GET', _ordersPath).length +
            server.calls('POST', _ordersPath).length,
        2,
        reason: 'السجلّ تحدّث بعد «ربّما أُرسل»');
    await reveal(t, find.textContaining('آخر طلبٍ لم يصل ردّه'));
    await simCheck(t, v, _screen, 'unclear_unconfirmed');
    await simDrain(t);
    // الطلب نفسه بعده ⇒ «لم يصل ردّه» وإقرار، ثمّ **مفتاحٌ جديد** مع
    // confirmRepeat (الإقرار طلبٌ آخر؛ الخادم يقرأ سجلّ ايرث لنك قبله).
    server.reply('POST', _orderPath, 200,
        {'success': true, 'message': 'تم إرسال طلب الكروت'});
    await openConfirm(t);
    expect(find.textContaining('ولم يصل ردّه'), findsOneWidget);
    expect(enabled(t, confirmButton()), isFalse);
    await acknowledge(t);
    await t.tap(confirmButton());
    await t.pumpAndSettle();
    expect(orders(), hasLength(2));
    expect(orders()[1]['confirmRepeat'], isTrue);
    expect(orders()[0]['request_id'], isNot(orders()[1]['request_id']),
        reason: 'الإقرار بطلبٍ جديد لا يعيد المفتاح الغامض');
    expect(find.text('تم إرسال طلب الكروت'), findsOneWidget);
    await simDrain(t);
  });

  simCase(_screen, 'unresolved_same_key', (t, v) async {
    // ردٌّ ضائع ثمّ (بعد نافذة التطبيق) إرسالٌ بلا إقرار بالمفتاح نفسه ⇒ الخادم:
    // ORDER_UNRESOLVED (لم يُرسَل) ⇒ تنبيهٌ باقٍ + إقرارٌ صريح + مفتاحٌ جديد.
    String? firstRef;
    server.on('POST', _orderPath, (o) {
      final b = o.data as Map;
      if (firstRef == null) {
        firstRef = '${b['request_id']}';
        return const SimReply(502, {
          'success': false,
          'code': 'ORDER_UNCONFIRMED',
          'message':
              'لم يصل ردّ ايرث لنك — ربما أُرسل الطلب؛ راجع سجلّ الطلبات قبل أن تطلب ثانيةً',
        });
      }
      if ('${b['request_id']}' == firstRef) {
        return const SimReply(409, {
          'success': false,
          'code': 'ORDER_UNRESOLVED',
          'message':
              'محاولتك السابقة لهذا الطلب لم يُعرف مصيرها — ربما وصلت وخُصم ثمنها، فلم نُرسله ثانيةً. راجع سجلّ الطلبات، وإن أردت طلباً جديداً فأكّده من جديد',
        });
      }
      return const SimReply(
          200, {'success': true, 'message': 'تم إرسال طلب الكروت'});
    });
    await open(t, v, counts: const {7: 5});
    await typePassword(t);
    await openConfirm(t);
    await t.tap(confirmButton());
    await t.pumpAndSettle();
    await simDrain(t);
    // مرّت نافذة التطبيق (١٠ دقائق): لا تنبيه محلّيّ ⇒ تأكيدٌ بلا إقرار.
    debugClearElCardOrderRecent();
    await openConfirm(t);
    expect(enabled(t, confirmButton()), isTrue);
    await t.tap(confirmButton());
    await t.pumpAndSettle();
    expect(orders(), hasLength(2));
    expect(orders()[1]['request_id'], firstRef, reason: 'بلا إقرار: المفتاح نفسه');
    expect(orders()[1].containsKey('confirmRepeat'), isFalse);
    // الخادم رفض المفتاح الغامض ⇒ التأكيد عاد بسببه وإقرارٍ صريح.
    expect(find.text('تأكيد طلب الكارتات'), findsOneWidget);
    expect(find.textContaining('لم يُعرف مصيرها'), findsWidgets);
    expect(enabled(t, confirmButton()), isFalse);
    await simCheck(t, v, _screen, 'unresolved_same_key');
    await acknowledge(t);
    await t.tap(confirmButton());
    await t.pumpAndSettle();
    expect(orders(), hasLength(3));
    expect(orders()[2]['confirmRepeat'], isTrue);
    expect(orders()[2]['request_id'], isNot(firstRef), reason: 'طلبٌ جديد = مفتاحٌ جديد');
    expect(find.text('تم إرسال طلب الكروت'), findsOneWidget);
    await simDrain(t);
  });

  simCase(_screen, 'maybe_placed', (t, v) async {
    // التأكيد بعد غموض: الخادم وجد في سجلّ ايرث لنك طلباً منذ المحاولة ⇒ لم يُرسَل.
    var n = 0;
    server.on('POST', _orderPath, (o) {
      n++;
      if (n == 1) return simTimeout(o);
      return const SimReply(409, {
        'success': false,
        'code': 'ORDER_MAYBE_PLACED',
        'message':
            'في سجلّ طلبات ايرث لنك طلبٌ بعد محاولتك السابقة — غالباً وصل الطلب الأوّل وخُصم ثمنه، فلم يُرسَل طلبٌ ثانٍ. راجع السجلّ',
      });
    });
    await open(t, v, counts: const {7: 5});
    await typePassword(t);
    await openConfirm(t);
    await t.tap(confirmButton());
    await t.pumpAndSettle();
    await simDrain(t);
    await openConfirm(t);
    await acknowledge(t);
    await t.tap(confirmButton());
    await t.pumpAndSettle();
    expect(n, 2);
    expect(find.textContaining('غالباً وصل الطلب الأوّل'), findsOneWidget);
    expect(find.text('تأكيد طلب الكارتات'), findsNothing, reason: 'لا إعادة تلقائيّة');
    await reveal(t, find.textContaining('آخر طلبٍ لم يصل ردّه'));
    await simDrain(t);
  });

  simCase(_screen, 'unclear_timeout', (t, v) async {
    server.on('POST', _orderPath, simTimeout);
    await open(t, v, counts: const {7: 5});
    await typePassword(t);
    await openConfirm(t);
    await t.tap(confirmButton());
    await t.pumpAndSettle();
    expect(orders(), hasLength(1), reason: 'لا إعادة');
    expect(find.textContaining('لم يصل ردٌّ مؤكَّد'), findsOneWidget);
    await reveal(t, find.textContaining('ربّما أُرسل'));
    await simCheck(t, v, _screen, 'unclear_timeout');
    await simDrain(t);
  });

  simCase(_screen, 'rejected_password', (t, v) async {
    server.reply('POST', _orderPath, 400, {
      'success': false,
      'code': 'DEPOSIT_PASSWORD',
      'message': 'باسورد الإيداع غير صحيح'
    });
    await open(t, v, counts: const {7: 5});
    await typePassword(t);
    await openConfirm(t);
    await t.tap(confirmButton());
    await t.pumpAndSettle();
    expect(find.text('باسورد الإيداع غير صحيح'), findsOneWidget);
    expect(find.text('المجموع 110,000 د.ع'), findsOneWidget,
        reason: 'الأعداد باقية');
    expect(find.textContaining('ربّما أُرسل'), findsNothing);
    await simCheck(t, v, _screen, 'rejected_password');
    await simDrain(t);
    // فشلٌ مؤكَّد: إعادة المحاولة بلا إقرار تكرار.
    await openConfirm(t);
    expect(find.textContaining('طلبتَ الكارتات نفسها'), findsNothing);
    expect(enabled(t, confirmButton()), isTrue);
  });

  simCase(_screen, 'quote_failed', (t, v) async {
    await open(t, v, counts: const {7: 5});
    await typePassword(t);
    server.reply('POST', _quotePath, 400, {
      'success': false,
      'code': 'PACKAGE_UNKNOWN',
      'message':
          'باقةٌ غير متاحة لحسابك في ايرث لنك — حدّث الصفحة واختر من القائمة',
    });
    await reveal(t, review());
    await t.tap(review());
    await t.pumpAndSettle();
    expect(find.text('تأكيد طلب الكارتات'), findsNothing,
        reason: 'لا تأكيد بلا تقدير');
    expect(find.textContaining('باقةٌ غير متاحة لحسابك'), findsOneWidget);
    expect(orders(), isEmpty);
    await simDrain(t);
  });

  simCase(_screen, 'packages_list_failed_uses_needed', (t, v) async {
    // قائمة الباقات تتعذّر ⇒ «الكارتات المطلوبة» وحدها مصدراً (بلا Turbo).
    server.reply('GET', '/api/v2/packages', 503,
        {'success': false, 'message': 'فشل جلب الباقات'});
    await open(t, v);
    expect(find.text('Economy'), findsOneWidget);
    expect(find.text('Turbo'), findsNothing);
    expect(server.bodies('POST', _quotePath).single['cards'], hasLength(3));
  });

  simCase(_screen, 'insufficient_warns', (t, v) async {
    // «لا يكفي» تنبيهٌ لا منع: الكلفة تقدير، وايرث لنك تحكم الرصيد عند الطلب.
    server.on('POST', _quotePath, (o) => _quote(o, balance: 100000));
    await open(t, v, counts: const {13: 2});
    await typePassword(t);
    await openConfirm(t);
    expect(find.textContaining('رصيد الإيداع أقلّ من الكلفة التقديريّة'),
        findsOneWidget);
    expect(find.text('-270,000 د.ع'), findsOneWidget, reason: 'الرصيد بعده سالب');
    expect(enabled(t, confirmButton()), isTrue, reason: 'تنبيهٌ لا منع');
    await simCheck(t, v, _screen, 'insufficient_warns');
    expect(orders(), isEmpty, reason: 'لا طلب بلا ضغط التأكيد');
  });

  simCase(_screen, 'history_rows', (t, v) async {
    server.reply('GET', _ordersPath, 200,
        {'success': true, 'data': _orders(), 'total': 3});
    await open(t, v);
    await reveal(t, find.text('طلب رقم 5521'));
    expect(find.text('قيد المراجعة'), findsOneWidget);
    expect(find.text('2026/10/18 · 14:05'), findsOneWidget);
    await reveal(t, find.text('طلب رقم 5400'));
    expect(find.text('معتمد'), findsOneWidget);
    expect(find.text('مرفوض'), findsOneWidget);
    expect(find.text('10 كارت · اعتُمد 10'), findsOneWidget);
    expect(find.text('20 كارت'), findsOneWidget,
        reason: 'قيد المراجعة: بلا معتمد');
    await simCheck(t, v, _screen, 'history_rows');
  });

  simCase(_screen, 'history_needs_password', (t, v) async {
    // لا باسورد إيداعٍ محفوظ: الخادم يطلبه للسجلّ — يُكتب في حقل الشاشة ثمّ
    // «إعادة المحاولة» ⇒ POST بالباسورد في الجسم (لا في الرابط).
    const need =
        'سجلّ الطلبات يحتاج باسورد الإيداع — احفظه من الإعدادات ثمّ أعد المحاولة';
    server.reply('GET', _ordersPath, 400,
        {'success': false, 'code': 'DEPOSIT_PASSWORD_REQUIRED', 'message': need});
    server.reply('POST', _ordersPath, 200,
        {'success': true, 'data': _orders(), 'total': 3});
    await open(t, v);
    await reveal(t, find.text(need));
    await simCheck(t, v, _screen, 'history_needs_password');
    await typePassword(t);
    await reveal(t, find.text('إعادة المحاولة'));
    await t.tap(find.text('إعادة المحاولة'));
    await t.pumpAndSettle();
    final post = server.calls('POST', _ordersPath).single;
    expect(post.uri.query, isEmpty);
    expect((post.data as Map)['depositPassword'], _secret);
    await reveal(t, find.text('طلب رقم 5521'));
    expect(find.text(need), findsNothing);
    expect(orders(), isEmpty, reason: 'قراءةٌ فقط');
  });

  simCase(_screen, 'needed_failed_uses_list', (t, v) async {
    // «الكارتات المطلوبة» تتعذّر ⇒ قائمة الموزّع وحدها (بلا متوفّر/مطلوب).
    server.reply('GET', _neededPath, 503,
        {'success': false, 'message': 'تعذّر جلب الكروت المطلوبة'});
    await open(t, v);
    expect(find.text('Economy'), findsOneWidget);
    expect(find.text('املأ بالمطلوب'), findsNothing);
    expect(find.textContaining('المتوفّر'), findsNothing);
  });

  simCase(_screen, 'packages_failed', (t, v) async {
    server.reply('GET', _neededPath, 503,
        {'success': false, 'message': 'تعذّر جلب الكروت المطلوبة'});
    server.reply('GET', '/api/v2/packages', 503,
        {'success': false, 'message': 'فشل جلب الباقات'});
    await open(t, v);
    expect(find.text('فشل جلب الباقات'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(enabled(t, review()), isFalse);
    await simCheck(t, v, _screen, 'packages_failed');
  });

  simCase(_screen, 'short_balance', (t, v) async {
    server.reply('GET', '/api/v2/admin-widgets', 200,
        {'success': true, 'balance': 50000, 'points': 0});
    await open(t, v, counts: const {13: 2});
    await reveal(t, find.textContaining('لا يكفي'));
    expect(find.text('-320,000 د.ع'), findsOneWidget);
    await simCheck(t, v, _screen, 'short_balance');
  });

  // ─────────────── تصنيف النتيجة (بلا رسم) ───────────────

  bool unclearOf(DioException e) =>
      EarthlinkApi.cardOrderResultFromError(e).unclear;

  test('5xx بلا غلافنا أو بلا ردّ ⇒ ربّما أُرسل؛ 503 بغلافنا ⇒ لم يُرسَل', () {
    DioException err(int? status, [Object? data]) => DioException(
          requestOptions: RequestOptions(path: _orderPath),
          response: status == null
              ? null
              : Response(
                  requestOptions: RequestOptions(path: _orderPath),
                  statusCode: status,
                  data: data,
                ),
          type: status == null
              ? DioExceptionType.receiveTimeout
              : DioExceptionType.badResponse,
        );
    expect(unclearOf(err(null)), isTrue);
    expect(unclearOf(err(502, '<html>')), isTrue);
    expect(unclearOf(err(504)), isTrue);
    expect(unclearOf(err(500, {'success': false, 'message': 'فشل الطلب'})),
        isTrue,
        reason: 'عطلٌ مجهول قد يقع بعد الإرسال');
    expect(
        unclearOf(err(
            503, {'success': false, 'message': 'توكن EarthLink غير متوفر'})),
        isFalse);
    expect(
        unclearOf(err(503, {
          'success': false,
          'message': 'تعذّر التحقّق من كلفة الكروت — لم يُرسَل الطلب، أعد المحاولة'
        })),
        isFalse);
    expect(
        unclearOf(err(502, {
          'success': false,
          'code': 'ORDER_UNCONFIRMED',
          'message': 'ربّما أُرسل'
        })),
        isTrue);
  });
}
