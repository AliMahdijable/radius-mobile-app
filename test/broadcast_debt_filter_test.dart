import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/broadcast_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/broadcast/broadcast_screen.dart';
import 'package:rad_mysvcs/screens/discounts/discounts_screen.dart';
import 'package:rad_mysvcs/screens/subscriber_prices/subscriber_prices_screen.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «تحديد المدينين» في التبليغات + التصميم الجديد للخصومات وأسعار المشتركين (٩ نوفمبر).
/// العمر = عمر أقدم دينٍ لم يُسدَّد (قرار المالك) — يحسبه الخادم؛ التطبيق يرسل الحدود، ويعرض المعاينة، ويرسل ببصمتها. الخادم وهميّ:
/// لا رسالة تُرسَل، والطلبات تُسجَّل لتُثبت ما يُرسَل حرفاً.
class _BcServer implements HttpClientAdapter {
  _BcServer(this.inner, {this.capable = true, this.ageAvailable = true, this.subManagers = const [], this.rows, this.highRisk = 0});
  final int highRisk;
  final HttpClientAdapter inner;
  final bool capable;
  final bool ageAvailable;
  final List<String> subManagers;
  final List<Map<String, Object?>>? rows;
  final requests = <RequestOptions>[];

  List<Map<String, dynamic>> bodiesOf(String path) => [
        for (final r in requests)
          if (r.method == 'POST' && r.path == path) Map<String, dynamic>.from(r.data as Map),
      ];

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  static const previewRows = [
    {'username': 'ahmed.k@najaf', 'name': 'أحمد كامل', 'debt': 75000, 'days': null, 'legacy': true},
    {'username': 'hussein77@najaf', 'name': 'حسين عبد الأمير', 'debt': 61000, 'days': 92, 'legacy': false},
    {'username': 'haider.s@najaf', 'name': 'حيدر سالم', 'debt': 52000, 'days': 31, 'legacy': false},
  ];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(o);
    final p = o.path;
    if (o.method == 'GET' && p == '/api/whatsapp/broadcast/debt-filter') {
      if (!capable) return _json(404, {'success': false, 'message': 'غير موجود'});
      return _json(200, {
        'success': true,
        'debtFilter': {
          'version': 2, 'amount': true, 'age': ageAvailable, 'ageMeaning': 'oldest_unpaid',
          if (!ageAvailable) 'ageNote': 'عمر الدين غير معروف لمشتركي هذه الشركة بعد (ديونها في الساس) — التحديد بالمبلغ وحده',
          'presets': [7, 15, 30, 60, 90], 'maxAgeDays': 3650, 'maxAmount': 10000000000, 'previewRequired': true,
        },
      });
    }
    if (o.method == 'POST' && p == '/api/whatsapp/broadcast') {
      final b = Map<String, dynamic>.from(o.data as Map);
      if (b['dryRun'] == true) {
        final targets = (b['targetUsernames'] as List?)?.map((e) => '$e').toSet();
        final list = [for (final r in previewRows) if (targets == null || targets.contains(r['username'])) r];
        return _json(200, {
          'success': true, 'dryRun': true, 'mode': 'debtors', 'count': list.length - highRisk, 'audience': list.length,
          'excludedHighRisk': highRisk, 'deduped': 0, 'rows': list, 'truncated': false,
          'audienceKey': 'a${list.length}'.padRight(32, '0'), 'missing': 0,
          'debtFilter': {'summary': 'x', 'considered': 4, 'kept': list.length, 'amountOut': 1, 'ageOut': 0, 'unknownAge': 1, 'legacy': 1},
        });
      }
      return _json(200, {'success': true, 'message': 'تمت إضافة رسائل', 'summary': {'queued': 3, 'excludedHighRisk': 0}});
    }
    if (o.method == 'POST' && p == '/api/v2/whatsapp/bulk-risk') {
      return _json(200, {'success': true, 'total': 0, 'noInbound': 0, 'highRisk': 0});
    }
    if (o.method == 'GET' && p.startsWith('/api/whatsapp/send-scope/')) {
      return _json(200, {'success': true, 'sendToAll': true, 'subManagers': subManagers});
    }
    if (o.method == 'GET' && p == '/api/v2/subscribers' && rows != null && o.queryParameters['page'] == null) {
      return _json(200, {'success': true, 'data': rows});
    }
    if (o.method == 'GET' && p == '/api/discounts') {
      return _json(200, {'success': true, 'data': [
        {'id': 1, 'subscriber_username': 'zainab.k@najaf', 'discount_amount': 5000, 'package_name': 'Standard', 'package_price': 35000},
      ]});
    }
    if (o.method == 'POST' && p == '/api/v2/discounts/bulk-apply') {
      return _json(200, {'success': true, 'applied': 2, 'updated': 0, 'failed': 0});
    }
    if (o.method == 'GET' && p == '/api/v2/subscriber-prices') {
      return _json(200, {'success': true, 'data': [
        {'idx': '4', 'username': 'mustafa.office@najaf', 'price': 30000, 'profile_id': 7, 'profile_name': 'Economy'},
      ]});
    }
    if (o.method == 'POST' && p == '/api/v2/subscriber-prices/bulk-apply') {
      return _json(200, {'success': true, 'data': {'applied': ['1', '2'], 'failed': []}});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

const _p390 = VisualDevice('', Size(390, 1600), 3);

void main() {
  setUpAll(visualSetUpAll);

  group('النموذج', () {
    test('DebtFilter: الجسم أرقامٌ وحدها، والوصف بكلمات الوكيل، والخطأ قبل الإرسال', () {
      const f = DebtFilter(minAgeDays: 30, minAmount: 50000, maxAmount: 100000);
      expect(f.active, isTrue);
      expect(f.toJson(), {'minAgeDays': 30, 'minAmount': 50000, 'maxAmount': 100000});
      expect(f.describe(), 'أقدم دين 30 يوماً فأكثر · من 50,000 إلى 100,000 د.ع');
      expect(const DebtFilter(minAgeDays: 7).describe(), 'أقدم دين 7 أيام فأكثر');
      expect(const DebtFilter(maxAmount: 25000).toJson(), {'maxAmount': 25000}, reason: 'الغائب لا يُرسَل');
      expect(DebtFilter.none.active, isFalse);
      expect(const DebtFilter(minAmount: 9, maxAmount: 1).problem(), 'الحدّ الأدنى أكبر من الأعلى');
      expect(const DebtFilter(minAgeDays: 0).problem(), isNotNull);
      expect(const DebtFilter(minAgeDays: 4000).problem(), isNotNull);
      expect(f.problem(), isNull);
      expect([1, 2, 5, 11, 30, 100].map(arDaysCount).toList(), ['يوم', 'يومين', '5 أيام', '11 يوماً', '30 يوماً', '100 يوم']);
    });

    test('BroadcastPreview: الصفوف و«دين قديم» والبصمة والمجهولون من ردّ الخادم', () {
      final pv = BroadcastPreview.fromJson({
        'count': 2, 'audience': 3, 'excludedHighRisk': 1, 'deduped': 0, 'audienceKey': 'k' * 32, 'truncated': false,
        'rows': _BcServer.previewRows,
        'debtFilter': {'unknownAge': 4, 'legacy': 1, 'ageUnsupported': true},
      });
      expect([pv.count, pv.audience, pv.excludedHighRisk, pv.unknownAge, pv.legacy, pv.ageUnsupported], [2, 3, 1, 4, 1, true]);
      expect(pv.rows.first.legacy, isTrue);
      expect(pv.rows.first.days, isNull);
      expect(pv.rows[1].days, 92);
      expect(pv.audienceKey, 'k' * 32);
    });
  });

  group('التبليغات — تحديد المدينين', () {
    Future<_BcServer> up(WidgetTester t,
        {bool capable = true, bool age = true, List<String> subManagers = const [], List<Map<String, Object?>>? rows, int highRisk = 0}) async {
      final inner = await visualSetUp(s1bSasOwner);
      final srv = _BcServer(inner, capable: capable, ageAvailable: age, subManagers: subManagers, rows: rows, highRisk: highRisk);
      ApiClient.dio.httpClientAdapter = srv;
      BigSubscribersApi.reset();
      SubscribersApi.clearAllCaches();
      await pumpVisual(t, _p390, home: (_) => const BroadcastScreen());
      await settle(t, seconds: 2);
      return srv;
    }

    Future<void> down(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      await visualTearDown();
      BigSubscribersApi.reset();
    }

    testWidgets('المدينون ⇒ اللوحة؛ عمرٌ ومبلغ ⇒ معاينةٌ من الخادم؛ الإرسال بالبصمة والحدود نفسها', (t) async {
      final srv = await up(t);
      expect(find.byKey(const ValueKey('debt-filter-panel')), findsNothing, reason: 'اللوحة تحت «المدينون» وحدها');
      await t.tap(find.text('المدينون'));
      await settle(t);
      expect(find.byKey(const ValueKey('debt-filter-panel')), findsOneWidget);
      expect(find.textContaining('أقدم دين لم يُسدَّد', findRichText: true), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('df-age-30')));
      await t.tap(find.text('50 إلى 100 ألف'));
      await settle(t, seconds: 2);
      final previews = srv.bodiesOf('/api/whatsapp/broadcast').where((b) => b['dryRun'] == true).toList();
      expect(previews, isNotEmpty);
      expect(previews.last['type'], 'debtors');
      expect(previews.last['debtFilter'], {'minAgeDays': 30, 'minAmount': 50000, 'maxAmount': 100000});
      expect(previews.last.containsKey('targetUsernames'), isFalse, reason: 'الكلّ: الخادم يختار');
      expect(find.text('3', findRichText: true), findsWidgets);
      expect(find.textContaining('1 دين قديم'), findsOneWidget);
      expect(find.textContaining('1 بلا عمر معروف'), findsOneWidget);
      // الإرسال: معاينةٌ للطلب نفسه ⇒ ورقة التأكيد بالأسماء و«دين قديم» ⇒ الإرسال بالبصمة
      await t.tap(find.byKey(const ValueKey('broadcast-send')));
      await settle(t, seconds: 2);
      expect(find.text('تأكيد الإرسال'), findsOneWidget);
      expect(find.text('أحمد كامل'), findsWidgets);
      expect(find.text('دين قديم'), findsWidgets);
      await t.tap(find.text('إرسال إلى 3'));
      await settle(t, seconds: 2);
      final sends = srv.bodiesOf('/api/whatsapp/broadcast').where((b) => b['dryRun'] != true).toList();
      expect(sends, hasLength(1));
      expect(sends.single['type'], 'debtors');
      expect(sends.single['debtFilter'], {'minAgeDays': 30, 'minAmount': 50000, 'maxAmount': 100000});
      expect(sends.single['audienceKey'], 'a3'.padRight(32, '0'));
      expect(sends.single['audienceCount'], 3);
      expect(sends.single.containsKey('dryRun'), isFalse);
      await down(t);
    });

    testWidgets('«أختار بنفسي» بالتحديد: القائمة من المعاينة، والمختارون وحدهم يُعاينون ويُرسَلون', (t) async {
      final srv = await up(t);
      await t.tap(find.text('المدينون'));
      await settle(t);
      await t.tap(find.text('100 ألف فأكثر'));
      await settle(t, seconds: 2);
      await t.tap(find.textContaining('أختار بنفسي'));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('df-row-hussein77@najaf')));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('broadcast-send')));
      await settle(t, seconds: 2);
      final dry = srv.bodiesOf('/api/whatsapp/broadcast').where((b) => b['dryRun'] == true).last;
      expect(dry['targetUsernames'], ['hussein77@najaf']);
      expect(dry['debtFilter'], {'minAmount': 100000});
      await t.tap(find.text('إرسال إلى 1'));
      await settle(t, seconds: 2);
      final send = srv.bodiesOf('/api/whatsapp/broadcast').where((b) => b['dryRun'] != true).single;
      expect(send['targetUsernames'], ['hussein77@najaf']);
      expect(send['audienceKey'], 'a1'.padRight(32, '0'));
      await down(t);
    });

    testWidgets('حارس الحظر في ورقة التأكيد: يُستبعدون افتراضيّاً، والمفتاح يعيدهم ويُرسل includeHighRisk', (t) async {
      final srv = await up(t, highRisk: 1);
      await t.tap(find.text('المدينون'));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('df-age-30')));
      await settle(t, seconds: 2);
      await t.tap(find.byKey(const ValueKey('broadcast-send')));
      await settle(t, seconds: 2);
      expect(t.takeException(), isNull, reason: 'لا تحذير ListTile داخل الصندوق الملوّن');
      expect(find.text('إرسال إلى 2'), findsOneWidget, reason: 'الثالث مستبعَدٌ افتراضيّاً');
      await t.tap(find.byKey(const ValueKey('df-include-risk')));
      await settle(t);
      await t.tap(find.text('إرسال إلى 3'));
      await settle(t, seconds: 2);
      final send = srv.bodiesOf('/api/whatsapp/broadcast').where((b) => b['dryRun'] != true).single;
      expect(send['includeHighRisk'], isTrue);
      await down(t);
    });

    testWidgets('خادمٌ أقدم (404) ⇒ لا لوحة والإرسال كما كان بلا تحديد', (t) async {
      final srv = await up(t, capable: false);
      await t.tap(find.text('المدينون'));
      await settle(t);
      expect(find.byKey(const ValueKey('debt-filter-panel')), findsNothing);
      expect(srv.bodiesOf('/api/whatsapp/broadcast').where((b) => b['dryRun'] == true), isEmpty);
      await down(t);
    });

    testWidgets('شركةٌ بلا دفترٍ لديونها ⇒ العمر بسببه والمبلغ يعمل', (t) async {
      await up(t, age: false);
      await t.tap(find.text('المدينون'));
      await settle(t);
      expect(find.byKey(const ValueKey('df-age-30')), findsNothing);
      expect(find.textContaining('ديونها في الساس'), findsOneWidget);
      expect(find.text('حتى 25 ألف'), findsOneWidget);
      await down(t);
    });

    testWidgets('«الكلّ» مع فلتر مديرٍ فرعيّ ⇒ أسماء الفئة بعد الفلتر صراحةً (لا الفئة كلّها)', (t) async {
      Map<String, Object?> row(String u, String parent, {String? notes}) => {
            'idx': '${u.hashCode.abs() % 9000}', 'username': u, 'firstname': u, 'lastname': '', 'phone': '07701234${u.length}${u.length}',
            'profile_name': 'Economy', 'profile_id': 7, 'expiration': '2030-01-01 10:00:00', 'remaining_days': 400, 'online_status': 0,
            'enabled': 1, 'parent_username': parent, if (notes != null) 'notes': notes,
          };
      final srv = await up(t, subManagers: const ['branch-a', 'branch-b'], rows: [
        row('a1@x', 'branch-a'), row('a22@x', 'branch-a'), row('b1@x', 'branch-b'),
      ]);
      await t.tap(find.text('branch-a'));
      await settle(t);
      await t.enterText(find.byType(TextField).last, 'تبليغ تجربة');
      await settle(t);
      await t.tap(find.byKey(const ValueKey('broadcast-send')));
      await settle(t);
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('إرسال')));
      await settle(t, seconds: 2);
      final send = srv.bodiesOf('/api/whatsapp/broadcast').single;
      expect((send['targetUsernames'] as List).toSet(), {'a1@x', 'a22@x'}, reason: 'الخادم لا يعرف فلتر المدير');
      await down(t);
    });
  });

  group('الخصومات وأسعار المشتركين — الصفوف وشريط التحديد وورقة المبلغ', () {
    testWidgets('الخصومات: تحديدٌ ⇒ «خصم» ⇒ الورقة ⇒ bulk-apply بالأسماء والمبلغ', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      final srv = _BcServer(inner);
      ApiClient.dio.httpClientAdapter = srv;
      BigSubscribersApi.reset();
      await pumpVisual(t, _p390, home: (_) => const DiscountsScreen());
      await settle(t, seconds: 2);
      expect(find.byKey(const ValueKey('discounts-apply')), findsNothing, reason: 'لا شريط قبل التحديد');
      await t.tap(find.byKey(const ValueKey('discount-row-ali1@najaf')));
      await t.tap(find.byKey(const ValueKey('discount-row-abbas.r@najaf')));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('discounts-apply')));
      await settle(t);
      expect(find.text('خصم على 2 مشترك'), findsOneWidget);
      await t.tap(find.text('+5,000'));
      await t.tap(find.text('+5,000'));
      await settle(t);
      await t.tap(find.text('تطبيق 10,000 على 2'));
      await settle(t, seconds: 2);
      final b = srv.bodiesOf('/api/v2/discounts/bulk-apply').single;
      expect((b['usernames'] as List).toSet(), {'ali1@najaf', 'abbas.r@najaf'});
      expect(b['discount_amount'], 10000);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      await visualTearDown();
    });

    testWidgets('أسعار المشتركين: تحديدٌ ⇒ «سعر ثابت» ⇒ الورقة ⇒ bulk-apply بالأرقام والسعر', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      final srv = _BcServer(inner);
      ApiClient.dio.httpClientAdapter = srv;
      BigSubscribersApi.reset();
      await pumpVisual(t, _p390, home: (_) => const SubscriberPricesScreen());
      await settle(t, seconds: 2);
      await t.tap(find.byKey(const ValueKey('price-row-1')));
      await t.tap(find.byKey(const ValueKey('price-row-2')));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('prices-apply')));
      await settle(t);
      await t.tap(find.text('35,000'));
      await settle(t);
      await t.tap(find.textContaining('على 2'));
      await settle(t, seconds: 2);
      final b = srv.bodiesOf('/api/v2/subscriber-prices/bulk-apply').single;
      expect((b['idxs'] as List).toSet(), {'1', '2'});
      expect(b['price'], 35000);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      await visualTearDown();
    });
  });
}
