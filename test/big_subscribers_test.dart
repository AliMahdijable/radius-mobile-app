import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/dashboard_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/broadcast/broadcast_screen.dart';
import 'package:rad_mysvcs/screens/discounts/discounts_screen.dart';
import 'package:rad_mysvcs/screens/subscriber_prices/subscriber_prices_screen.dart';
import 'package:rad_mysvcs/screens/notifications/inbox_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/subscriber_picker_sheet.dart';
import 'package:rad_mysvcs/services/alerts_service.dart';
import 'package:rad_mysvcs/services/subscribers_offline_cache.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';

import 'visual_perm/visual_perm_harness.dart';

/// الحسابات الكبيرة (٢١ أكتوبر، طلب المالك: admin@full ٨٩٬١٧٧ مشتركاً — القائمة الكاملة ٩٦ث وتنقطع): ≥ ٥٠٠٠ مشترك ⇒ لا قائمة
/// كاملة ولا قائمة متصلين؛ الصفحة والتبويب والبحث من الخادم والعدّادات من summary.app بتعريفات هذا التطبيق. الخادم وهميّ.
const _bigTotals = {
  'all': 89177,
  'active_all': 66865,
  'expired_all': 22312,
  'online_all': 52000,
  'offline': 14865,
  'disabled': 745,
  'near_expiry': 9012,
  'online_no_plan': 1170,
  'neglected': 0,
  'expired_today': 546,
  'expiring_24h': 130,
  'debtors': 21064,
};
const _app = {
  'all': 89177,
  'active': 66865,
  'expired': 22312,
  'online': 52000,
  'offline': 14865,
  'disabled': 745,
  'nearExpiry': 9012,
  'onlineNoPlan': 1170,
  'debtors': null,
  'neglected': 0,
  'expiredToday': 546,
  'expiring24h': 130,
};

String _two(int n) => n.toString().padLeft(2, '0');

Map<String, Object?> _bigRow(int i, String tab) {
  final days = tab == 'near_expiry' ? i % 3 + 1 : tab.startsWith('expired') ? -(1 + i % 20) : 5 + i % 40;
  final exp = tab == 'expired_today'
      ? DateTime.now().subtract(const Duration(minutes: 5))
      : tab == 'expiring_24h'
          ? DateTime.now().add(Duration(hours: 1 + i % 20))
          : DateTime.now().add(Duration(days: days, hours: 2));
  return {
    'idx': '${100000 + i}',
    'username': 'big${i.toString().padLeft(6, '0')}',
    'firstname': 'مشترك',
    'lastname': '$i',
    'phone': '0770${2000000 + i}',
    'profile_name': 'Gold',
    'profile_id': 7,
    'expiration': '${exp.year}-${_two(exp.month)}-${_two(exp.day)} ${_two(exp.hour)}:00:00',
    'remaining_days': days,
    'online_status': tab == 'offline' ? 0 : 1,
    'enabled': tab == 'disabled' ? 0 : 1,
    if (tab == 'debtors') 'notes': '-${(1 + i % 9) * 5000}',
  };
}

/// خادمٌ فوق خادم لقطات الصلاحيّات: يجيب الصفحات والملخّص، ويسجّل كلّ طلب (لإثبات أنّ القائمة الكاملة لا تُطلب).
class _BigServer implements HttpClientAdapter {
  _BigServer(this.inner, {this.total = 89177, this.debtors = 'rows', this.debtCounts = 'known'});
  final HttpClientAdapter inner;
  final int total;

  /// «مديون»: 'rows' صفوفٌ (سوبرنت notes) · 'unsupported' شركةٌ على دفترنا (409).
  final String debtors;

  /// الملخّص: 'known' (عددٌ ومجموع) · 'pending' (جارٍ العدّ) · 'none' (لا يُعرف).
  final String debtCounts;
  final requests = <RequestOptions>[];
  int get summaryCalls => requests.where((r) => r.path == '/api/v2/subscribers-summary').length;

  bool get askedFullList => requests.any((r) => r.method == 'GET' && r.path == '/api/v2/subscribers' && r.queryParameters['page'] == null);
  bool get askedOnline => requests.any((r) => r.path == '/api/v2/online-users');
  List<Map<String, dynamic>> bodiesOf(String path) => [
        for (final r in requests)
          if (r.method == 'POST' && r.path == path) Map<String, dynamic>.from(r.data as Map),
      ];
  List<Map<String, dynamic>> get pageQueries => [
        for (final r in requests)
          if (r.path == '/api/v2/subscribers' && r.queryParameters['page'] != null) Map<String, dynamic>.from(r.queryParameters),
      ];

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(o);
    if (o.method == 'GET' && o.path == '/api/v2/subscribers' && o.queryParameters['page'] != null) {
      final page = int.parse('${o.queryParameters['page']}');
      final size = int.parse('${o.queryParameters['size'] ?? 50}');
      final tab = '${o.queryParameters['tab'] ?? 'all'}';
      if (total < BigSubscribersApi.threshold) {
        return _json(200, {'success': true, 'data': const [], 'total': total, 'paged': true, 'page': page, 'size': size, 'last_page': 1});
      }
      if (tab == 'debtors' && debtors == 'unsupported') {
        return _json(409, {'success': false, 'code': 'TAB_UNSUPPORTED', 'message': '«مديون» غير متاح بالصفحة للقوائم الكبيرة'});
      }
      final base = _bigTotals[tab] ?? 0;
      final eff = o.queryParameters['q'] != null ? math.min(base, 7) : base;
      final start = (page - 1) * size;
      final n = math.max(0, math.min(size, eff - start));
      return _json(200, {
        'success': true,
        'data': [for (var k = 0; k < n; k++) _bigRow(start + k + 1, tab)],
        'total': eff,
        'paged': true,
        'page': page,
        'size': size,
        'last_page': math.max(1, (eff / size).ceil()),
      });
    }
    if (o.method == 'GET' && o.path == '/api/v2/subscribers-summary') {
      final app = Map<String, Object?>.from(_app);
      if (debtCounts == 'known') {
        app['debtors'] = 21064;
        app['totalDebt'] = 1416647673;
        app['debtorsAt'] = DateTime.now().millisecondsSinceEpoch;
      } else if (debtCounts == 'pending') {
        app['debtorsPending'] = true;
      }
      return _json(200, {'success': true, 'summary': {'all': 89177, 'debtors': null, 'app': app}});
    }
    if (o.method == 'GET' && o.path == '/api/v2/packages') {
      return _json(200, {'success': true, 'data': [
        {'id': 7, 'name': 'Gold'},
        {'id': 9, 'name': 'Silver'},
      ]});
    }
    if (o.method == 'POST' && o.path == '/api/v2/subscribers/lookup') {
      final b = Map<String, dynamic>.from(o.data as Map);
      String user(int i) => 'big${i.toString().padLeft(6, '0')}';
      return _json(200, {'success': true, 'data': [
        for (final u in (b['usernames'] as List? ?? const []))
          {'idx': '${100000 + int.parse('$u'.substring(3))}', 'username': '$u', 'firstname': 'اسم', 'lastname': '$u'.substring(3)},
        for (final i in (b['idxs'] as List? ?? const []))
          {'idx': '$i', 'username': user(int.parse('$i') - 100000), 'firstname': 'اسم', 'lastname': '$i'},
      ]});
    }
    if (o.method == 'POST' && o.path == '/api/whatsapp/broadcast') {
      return _json(200, {
        'success': true,
        'pending': true,
        'total': 89177,
        'message': 'بدأ تجهيز التبليغ لحسابٍ كبير (89,177 مشترك) — قد يأخذ بضع دقائق، ويصلك إشعارٌ بالنتيجة',
      });
    }
    if (o.method == 'GET' && o.path == '/api/v2/managers') {
      return _json(200, {'success': true, 'data': [
        {'id': 501, 'username': 'branch-a'},
        {'id': 502, 'username': 'branch-b'},
      ]});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

/// حسابٌ «متوسّط» (١٬٢٠٠): الصفحات من الخادم فوراً، والقائمة الكاملة تتأخّر [fullDelay] — لإثبات العرض التدريجيّ.
class _MediumServer implements HttpClientAdapter {
  _MediumServer(this.inner, {this.fullDelay = const Duration(seconds: 3), this.fullFails = false, this.total = 1200});
  final HttpClientAdapter inner;
  final int total;

  /// صفوف القائمة الكاملة — أقلّ من [total] عمداً: جسمٌ فوق ٥٠ك يفكّه dio في isolate (وقتٌ حقيقيّ لا يتقدّم بـpump)،
  /// والعدّاد بعد وصولها يُثبت أنّه من القائمة لا من الخادم.
  final int fullRows = 120;
  final Duration fullDelay;
  final bool fullFails;
  final requests = <RequestOptions>[];
  int get summaryCalls => requests.where((r) => r.path == '/api/v2/subscribers-summary').length;
  bool get askedFullList => requests.any((r) => r.method == 'GET' && r.path == '/api/v2/subscribers' && r.queryParameters['page'] == null);
  List<Map<String, dynamic>> get pageQueries => [
        for (final r in requests)
          if (r.path == '/api/v2/subscribers' && r.queryParameters['page'] != null) Map<String, dynamic>.from(r.queryParameters),
      ];

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(o);
    if (o.method == 'GET' && o.path == '/api/v2/subscribers') {
      if (o.queryParameters['page'] == null) {
        await Future<void>.delayed(fullDelay);
        if (fullFails) return _json(503, {'success': false, 'message': 'SAS timeout'});
        return _json(200, {'success': true, 'data': [for (var i = 1; i <= fullRows; i++) _bigRow(i, 'all')]});
      }
      final page = int.parse('${o.queryParameters['page']}');
      final size = int.parse('${o.queryParameters['size'] ?? 50}');
      final start = (page - 1) * size;
      final n = math.max(0, math.min(size, total - start));
      return _json(200, {
        'success': true,
        'data': [for (var k = 0; k < n; k++) _bigRow(start + k + 1, 'all')],
        'total': total,
        'paged': true,
        'page': page,
        'size': size,
        'last_page': math.max(1, (total / size).ceil()),
      });
    }
    if (o.method == 'GET' && o.path == '/api/v2/subscribers-summary') {
      return _json(200, {'success': true, 'summary': {'all': total, 'debtors': null, 'app': {'all': total, 'active': total, 'expired': 0, 'online': total, 'offline': 0, 'disabled': 0, 'nearExpiry': 0, 'onlineNoPlan': 0, 'neglected': 0}}});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(visualSetUpAll);

  late _BigServer server;
  late ValueNotifier<SubscriberFilter?> cmd;

  Future<void> open(WidgetTester t, {int total = 89177}) async {
    final inner = await visualSetUp(s1bSasOwner);
    server = _BigServer(inner, total: total);
    ApiClient.dio.httpClientAdapter = server;
    BigSubscribersApi.reset();
    SubscribersApi.clearAllCaches();
    cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
    await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
    await settle(t, seconds: 2);
  }

  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    await visualTearDown();
    BigSubscribersApi.reset();
    SubscribersApi.clearAllCaches();
  }

  group('شاشة المشتركين — حسابٌ كبير (٨٩٬١٧٧)', () {
    testWidgets('الصفحة الأولى من الخادم، والعدّادات من الملخّص، بلا قائمةٍ كاملة ولا قائمة متصلين', (t) async {
      await open(t);
      expect(find.text('big000001'), findsWidgets);
      expect(server.askedFullList, isFalse, reason: 'الحساب الكبير لا يطلب القائمة الكاملة');
      expect(server.askedOnline, isFalse, reason: 'ولا قائمة المتصلين الكاملة');
      expect(find.text('89177'), findsWidgets, reason: 'عدّاد «الكل» من الملخّص');
      final q = server.pageQueries.where((m) => '${m['size']}' == '50').toList();
      expect(q, isNotEmpty);
      expect(q.first['tab'], 'all');
      await drain(t);
    });

    testWidgets('التبويب والبحث وتحميل المزيد تُسأل من الخادم', (t) async {
      await open(t);
      // «قارب» = near_expiry (تعريف التطبيق: أقلّ من ٤ أيّام) — بأمر التبويب كما ترسله الرئيسيّة
      cmd.value = SubscriberFilter.nearExpiry;
      await settle(t, seconds: 2);
      expect(server.pageQueries.any((m) => m['tab'] == 'near_expiry'), isTrue);
      // البحث بعد توقّف الكتابة
      await t.enterText(find.byType(TextField).first, 'big0001');
      await settle(t, seconds: 2);
      expect(server.pageQueries.any((m) => m['q'] == 'big0001'), isTrue);
      // العودة لـ«الكل» بلا بحث ثمّ «تحميل المزيد» ⇒ الصفحة ٢
      await t.enterText(find.byType(TextField).first, '');
      await settle(t, seconds: 2);
      cmd.value = SubscriberFilter.all;
      await settle(t, seconds: 2);
      final more = find.text('تحميل المزيد');
      await t.scrollUntilVisible(more, 800,
          scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
      await t.tap(more);
      await settle(t, seconds: 2);
      expect(server.pageQueries.any((m) => '${m['page']}' == '2'), isTrue);
      expect(server.askedFullList, isFalse);
      await drain(t);
    });

    testWidgets('متوسّط (١٬٢٠٠): الصفحة الأولى فوراً والشرائح «…»، ثمّ القائمة الكاملة بعدّاداتها — بلا ملخّص', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      final srv = _MediumServer(inner);
      ApiClient.dio.httpClientAdapter = srv;
      BigSubscribersApi.reset();
      SubscribersApi.clearAllCaches();
      cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
      await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
      await settle(t, seconds: 1);
      expect(find.text('big000001'), findsWidgets, reason: 'الصفحة الأولى من الخادم قبل القائمة الكاملة');
      expect(srv.askedFullList, isTrue, reason: 'القائمة الكاملة تبدأ معها في الخلفيّة');
      expect(srv.pageQueries.any((m) => '${m['size']}' == '50'), isTrue);
      expect(find.text('…'), findsWidgets, reason: 'العدّادات من القائمة حين تصل — لا أرقامٌ تتبدّل');
      expect(srv.summaryCalls, 0, reason: 'لا ملخّص يزاحم القائمة على ساسٍ بطيء');
      await settle(t, seconds: 4);
      expect(find.text('120'), findsWidgets, reason: 'عدّاد «الكل» من القائمة الكاملة (لا من الخادم)');
      expect(find.text('…'), findsNothing);
      expect(srv.summaryCalls, 0);
      await drain(t);
    });

    testWidgets('متوسّط والقائمة الكاملة تعذّرت ⇒ تبقى الصفحات بعدّادات الملخّص (لا شاشة فارغة)', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      final srv = _MediumServer(inner, fullDelay: const Duration(milliseconds: 500), fullFails: true);
      ApiClient.dio.httpClientAdapter = srv;
      BigSubscribersApi.reset();
      SubscribersApi.clearAllCaches();
      // بلا نسخة قرصٍ من اختبارٍ سابق (القائمة الفاشلة تعود إليها كما كانت)
      await t.runAsync(SubscribersOfflineCache.clear);
      cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
      await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
      await settle(t, seconds: 3); // الطلب وإعادته (بوّابة عابرة) ثمّ الفشل
      // ثمّ نسخة القرص (قراءة ملفٍّ حقيقيّة لا تتقدّم بـpump) — فارغةٌ هنا
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await settle(t, seconds: 2);
      expect(find.text('big000001'), findsWidgets);
      expect(srv.summaryCalls, greaterThan(0), reason: 'بلا قائمة: العدّادات من الملخّص كالكبير');
      expect(find.text('1200'), findsWidgets);
      await drain(t);
    });

    testWidgets('حسابٌ صغير (١٬٢٠٠) ⇒ القائمة الكاملة كما كانت', (t) async {
      await open(t, total: 1200);
      expect(server.askedFullList, isTrue);
      await drain(t);
    });

    // ٢٥ أكتوبر — وكيلٌ ٧٤٦ مشتركاً على ساسٍ بطيء (قائمته الكاملة ≈٦٫٥ث في ساسه نفسه): بعد مهلةٍ قصيرة يصير تدريجيّاً كالمتوسّط.
    testWidgets('صغير (٧٤٦) على ساسٍ بطيء ⇒ الصفحة الأولى بعد المهلة والشرائح «…»، ثمّ القائمة الكاملة بعدّاداتها', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      final srv = _MediumServer(inner, total: 746, fullDelay: const Duration(seconds: 4));
      ApiClient.dio.httpClientAdapter = srv;
      BigSubscribersApi.reset();
      SubscribersApi.clearAllCaches();
      await t.runAsync(SubscribersOfflineCache.clear);
      cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
      await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
      await settle(t, seconds: 2);
      expect(srv.askedFullList, isTrue, reason: 'القائمة الكاملة بدأت أوّلاً');
      expect(srv.pageQueries.where((m) => '${m['size']}' != '1'), isNotEmpty, reason: 'بعد المهلة: الصفحة الأولى من الخادم');
      expect(find.text('big000001'), findsWidgets);
      expect(find.text('…'), findsWidgets, reason: 'العدّادات من القائمة حين تصل — لا أرقامٌ تتبدّل');
      expect(srv.summaryCalls, 0);
      await settle(t, seconds: 4);
      expect(find.text('120'), findsWidgets, reason: 'عدّاد «الكل» من القائمة الكاملة');
      expect(find.text('…'), findsNothing);
      await drain(t);
    });

    testWidgets('صغير على ساسٍ سريع ⇒ القائمة الكاملة مباشرةً بلا صفحاتٍ ولا «…» (كما كان)', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      final srv = _MediumServer(inner, total: 746, fullDelay: const Duration(milliseconds: 300));
      ApiClient.dio.httpClientAdapter = srv;
      BigSubscribersApi.reset();
      SubscribersApi.clearAllCaches();
      await t.runAsync(SubscribersOfflineCache.clear);
      cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
      await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
      await settle(t, seconds: 2);
      expect(srv.askedFullList, isTrue);
      expect(srv.pageQueries.where((m) => '${m['size']}' != '1'), isEmpty, reason: 'لا صفحات: وصلت قبل المهلة');
      expect(find.text('120'), findsWidgets);
      expect(find.text('…'), findsNothing);
      await drain(t);
    });
  });

  group('نافذة «اختر مشتركاً» (الإضافة السريعة) — حسابٌ كبير', () {
    Future<void> openPicker(WidgetTester t, {bool debtorsOnly = false}) async {
      final inner = await visualSetUp(s1bSasOwner);
      server = _BigServer(inner);
      ApiClient.dio.httpClientAdapter = server;
      BigSubscribersApi.reset();
      SubscribersApi.clearAllCaches();
      await pumpVisual(t, phone,
          home: (_) => Builder(
                builder: (ctx) => Center(
                  child: TextButton(
                    onPressed: () => showSubscriberPickerSheet(ctx, title: 'تفعيل', debtorsOnly: debtorsOnly),
                    child: const Text('افتح'),
                  ),
                ),
              ));
      await settle(t, seconds: 1); // الترجمة تُحمَّل قبل أوّل بناء
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 2);
    }

    testWidgets('الأوائل ثمّ البحث من الساس، بلا قائمةٍ كاملة', (t) async {
      await openPicker(t);
      expect(find.text('(big000001)'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'big0001');
      await settle(t, seconds: 2);
      expect(server.pageQueries.any((m) => m['q'] == 'big0001'), isTrue);
      expect(server.askedFullList, isFalse);
      await drain(t);
    });

    testWidgets('«عليه دين» تنتظر البحث وتقول لماذا، ثمّ ترشّح النتائج', (t) async {
      await openPicker(t, debtorsOnly: true);
      expect(find.textContaining('قائمة المدينين غير متاحة بعد'), findsOneWidget);
      expect(server.pageQueries.where((m) => '${m['size']}' == '50'), isEmpty, reason: 'لا صفحة قبل البحث');
      await t.enterText(find.byType(TextField).first, 'big0001');
      await settle(t, seconds: 2);
      expect(server.pageQueries.any((m) => m['q'] == 'big0001'), isTrue);
      // صفوف الخادم الوهميّ بلا دين ⇒ لا مدين يطابق
      expect(find.text('لا يوجد مدين يطابق البحث'), findsOneWidget);
      expect(server.askedFullList, isFalse);
      await drain(t);
    });
  });

  group('الحساب الكبير — الدفعة الثانية', () {
    Future<_BigServer> setUpServer({String debtors = 'rows', String debtCounts = 'known'}) async {
      final inner = await visualSetUp(s1bSasOwner);
      final srv = _BigServer(inner, debtors: debtors, debtCounts: debtCounts);
      ApiClient.dio.httpClientAdapter = srv;
      BigSubscribersApi.reset();
      SubscribersApi.clearAllCaches();
      return srv;
    }

    testWidgets('«مدين»: الصفوف من الخادم، والعدّاد وبطاقة المجموع من الملخّص', (t) async {
      await open(t);
      cmd.value = SubscriberFilter.debtors;
      await settle(t, seconds: 2);
      expect(server.pageQueries.any((m) => m['tab'] == 'debtors'), isTrue);
      expect(find.text('big000001'), findsWidgets);
      expect(find.textContaining('إجمالي الديون'), findsOneWidget);
      expect(find.textContaining('21064 مشترك'), findsOneWidget);
      expect(find.descendant(of: find.byType(FilterChipsBar), matching: find.text('21064')), findsOneWidget);
      await drain(t);
    });

    testWidgets('«مدين» لشركةٍ على دفترنا (TAB_UNSUPPORTED) ⇒ نصٌّ يقول لماذا بلا قائمة', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      server = _BigServer(inner, debtors: 'unsupported', debtCounts: 'none');
      ApiClient.dio.httpClientAdapter = server;
      BigSubscribersApi.reset();
      SubscribersApi.clearAllCaches();
      cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.debtors);
      await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
      await settle(t, seconds: 3);
      expect(find.textContaining('غير متاح بعد للقوائم الكبيرة في هذه الشركة'), findsOneWidget);
      expect(find.text('big000001'), findsNothing);
      expect(find.descendant(of: find.byType(FilterChipsBar), matching: find.text('—')), findsOneWidget);
      await drain(t);
    });

    testWidgets('عدّ المدينين جارٍ ⇒ «…» على الشريحة وسطرٌ يقول ذلك', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      server = _BigServer(inner, debtCounts: 'pending');
      ApiClient.dio.httpClientAdapter = server;
      BigSubscribersApi.reset();
      SubscribersApi.clearAllCaches();
      cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.debtors);
      await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
      await settle(t, seconds: 3);
      expect(find.descendant(of: find.byType(FilterChipsBar), matching: find.text('…')), findsOneWidget);
      expect(find.textContaining('جارٍ عدّ المدينين'), findsOneWidget);
      await drain(t);
    });

    testWidgets('الجرس: العدّان من الملخّص (انتهى اليوم + أقلّ من ٢٤ ساعة) بلا قائمة كاملة', (t) async {
      final srv = await setUpServer();
      await t.runAsync(AlertsService.refresh);
      expect(AlertsService.expiredTodayCount.value, 546);
      expect(AlertsService.nearExpiryCount.value, 130);
      expect(AlertsService.count.value, 676);
      expect(srv.askedFullList, isFalse);
      AlertsService.reset();
      await visualTearDown();
      BigSubscribersApi.reset();
    });

    testWidgets('صندوق الإشعارات: القائمتان من الخادم بمجموعهما، و«عرض المزيد» يجلب الصفحة التالية', (t) async {
      final srv = await setUpServer();
      server = srv;
      await pumpVisual(t, phone, home: (_) => const InboxScreen());
      await settle(t, seconds: 3);
      expect(srv.pageQueries.any((m) => m['tab'] == 'expired_today' && '${m['size']}' == '100'), isTrue);
      expect(srv.pageQueries.any((m) => m['tab'] == 'expiring_24h'), isTrue);
      expect(find.text('546'), findsWidgets, reason: 'عنوان «انتهى اليوم» بمجموعه لا بما حُمِّل');
      expect(AlertsService.count.value, 676);
      final more = find.text('عرض المزيد');
      await t.scrollUntilVisible(more, 600,
          scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
      await t.tap(more.first);
      await settle(t, seconds: 2);
      expect(srv.pageQueries.any((m) => m['tab'] == 'expired_today' && '${m['page']}' == '2'), isTrue);
      expect(srv.askedFullList, isFalse);
      AlertsService.reset();
      await drain(t);
    });

    testWidgets('الإرسال الجماعي: «عام» يرسل الفئة كلّها بلا قائمةٍ من الهاتف — الخادم يجهّزها ويردّ فوراً', (t) async {
      final srv = await setUpServer();
      server = srv;
      await pumpVisual(t, phone, home: (_) => const BroadcastScreen());
      await settle(t, seconds: 3);
      expect(find.textContaining('حسابك كبير'), findsOneWidget);
      expect(find.text('كلّ الفئة — يُجهَّز في الخلفيّة'), findsOneWidget);
      expect(srv.pageQueries.any((m) => m['tab'] == 'all'), isTrue, reason: '«محدّد» افتراضيّاً: بحث الساس');
      await t.tap(find.text('عام'));
      await settle(t);
      expect(find.text('89177 مشترك'), findsOneWidget, reason: 'العدد من ملخّص الساس لا من القائمة');
      await t.enterText(find.byType(TextField).last, 'تبليغ تجربة');
      await settle(t);
      expect(find.text('إرسال للكل'), findsOneWidget);
      await t.tap(find.widgetWithText(ElevatedButton, 'إرسال'));
      await settle(t);
      expect(find.textContaining('إرسال لنحو 89177 مشترك'), findsOneWidget);
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('إرسال')));
      await settle(t, seconds: 2);
      final sent = srv.bodiesOf('/api/whatsapp/broadcast');
      expect(sent, hasLength(1));
      expect(sent.single.containsKey('targetUsernames'), isFalse, reason: 'الخادم يجمع الفئة بنفسه');
      expect(sent.single['type'], 'general');
      expect(sent.single['message'], 'تبليغ تجربة');
      expect(find.textContaining('بدأ تجهيز التبليغ'), findsOneWidget, reason: 'ردّ الخادم كما هو');
      expect(srv.askedFullList, isFalse);
      await drain(t);
    });

    testWidgets('lookup: أسماء أصحاب الخصومات/ارتباطات تلغرام بأعيانهم — POST بلا قائمةٍ كاملة', (t) async {
      final srv = await setUpServer();
      final rows = await t.runAsync(() => BigSubscribersApi.lookup(usernames: ['big000003'], idxs: ['100005']));
      expect(rows, hasLength(2));
      expect(rows!.first.username, 'big000003');
      expect(rows.first.firstname, 'اسم');
      expect(rows.last.idx, '100005');
      final b = srv.bodiesOf('/api/v2/subscribers/lookup').single;
      expect(b['usernames'], ['big000003']);
      expect(b['idxs'], ['100005']);
      final none = await t.runAsync(() => BigSubscribersApi.lookup());
      expect(none, isEmpty, reason: 'لا طلب بلا أسماء');
      expect(srv.bodiesOf('/api/v2/subscribers/lookup'), hasLength(1));
      expect(srv.askedFullList, isFalse);
      await visualTearDown();
      BigSubscribersApi.reset();
    });

    testWidgets('فلتر الباقة يُمرَّر للساس profile_id في الصفحة والملخّص', (t) async {
      final srv = await setUpServer();
      await t.runAsync(() async {
        await BigSubscribersApi.page(page: 1, tab: 'all', profileId: 7);
        await BigSubscribersApi.summary(profileId: 7);
      });
      expect(srv.pageQueries.any((m) => '${m['profile_id']}' == '7'), isTrue);
      expect(srv.requests.any((r) => r.path == '/api/v2/subscribers-summary' && '${r.queryParameters['profile_id']}' == '7'), isTrue);
      await visualTearDown();
      BigSubscribersApi.reset();
    });

    testWidgets('شاشة المشتركين: «الباقة» في نافذة التصفية من كتالوج الباقات، واختيارها يسأل الساس profile_id', (t) async {
      await open(t);
      final btn = find.byIcon(Icons.tune_rounded).evaluate().isNotEmpty
          ? find.byIcon(Icons.tune_rounded)
          : find.byIcon(LucideIcons.slidersHorizontal);
      await t.tap(btn.first);
      await settle(t);
      expect(find.text('الباقة'), findsOneWidget);
      await t.tap(find.text('Silver'));
      await settle(t);
      await t.tap(find.text('تطبيق'));
      await settle(t, seconds: 2);
      expect(server.pageQueries.any((m) => '${m['profile_id']}' == '9'), isTrue);
      expect(server.requests.any((r) => r.path == '/api/v2/subscribers-summary' && '${r.queryParameters['profile_id']}' == '9'), isTrue);
      expect(server.askedFullList, isFalse);
      await drain(t);
    });

    testWidgets('الخصومات: المشتركون من بحث الساس، والبحث يُسأل منه', (t) async {
      final srv = await setUpServer();
      server = srv;
      await pumpVisual(t, phone, home: (_) => const DiscountsScreen());
      await settle(t, seconds: 3);
      expect(find.textContaining('big000001'), findsWidgets);
      await t.enterText(find.byType(TextField).last, 'big0002');
      await settle(t, seconds: 2);
      expect(srv.pageQueries.any((m) => m['q'] == 'big0002'), isTrue);
      expect(srv.askedFullList, isFalse);
      await drain(t);
    });

    testWidgets('الخصومات: «N من المجموع» لا «١٠٠ نتيجة»، والتمرير للآخر يجلب الصفحة التالية من الساس', (t) async {
      final srv = await setUpServer();
      server = srv;
      await pumpVisual(t, phone, home: (_) => const DiscountsScreen());
      await settle(t, seconds: 3);
      expect(find.textContaining('100 من 89177'), findsOneWidget, reason: 'المعروض من مجموع الساس');
      final grid = find.byType(GridView);
      for (var i = 0; i < 12 && !srv.pageQueries.any((m) => '${m['page']}' == '2'); i++) {
        await t.drag(grid, const Offset(0, -1500));
        await t.pump(const Duration(milliseconds: 300));
      }
      await settle(t, seconds: 2);
      expect(srv.pageQueries.any((m) => '${m['page']}' == '2' && '${m['size']}' == '100' && m['tab'] == 'all'), isTrue);
      expect(find.textContaining('200 من 89177'), findsOneWidget, reason: 'الصفحة الثانية أُلحقت');
      expect(srv.askedFullList, isFalse);
      await drain(t);
    });

    testWidgets('السعر الثابت: «N من المجموع»، والتمرير للآخر يجلب الصفحة التالية', (t) async {
      final srv = await setUpServer();
      server = srv;
      await pumpVisual(t, phone, home: (_) => const SubscriberPricesScreen());
      await settle(t, seconds: 3);
      expect(find.textContaining('100 من 89177'), findsOneWidget);
      final grid = find.byType(GridView);
      for (var i = 0; i < 12 && !srv.pageQueries.any((m) => '${m['page']}' == '2'); i++) {
        await t.drag(grid, const Offset(0, -1500));
        await t.pump(const Duration(milliseconds: 300));
      }
      await settle(t, seconds: 2);
      expect(srv.pageQueries.any((m) => '${m['page']}' == '2' && '${m['size']}' == '100'), isTrue);
      expect(find.textContaining('200 من 89177'), findsOneWidget);
      expect(srv.askedFullList, isFalse);
      await drain(t);
    });

    testWidgets('BigSearch.more: الصفحة التالية لآخر بحث، وبحثٌ جديد يصفّرها', (t) async {
      final srv = await setUpServer();
      final b = BigSearch();
      List<Subscriber>? first;
      await t.runAsync(() async {
        b.search('', onRows: (r) => first = r, now: true);
        for (var i = 0; i < 50 && first == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      expect(first, hasLength(100));
      expect(b.total, 89177);
      expect(b.hasMore, isTrue);
      final more = await t.runAsync(b.more);
      expect(more, hasLength(100));
      expect(more!.first.username, 'big000101');
      expect('${srv.pageQueries.last['page']}', '2');
      b.search('x', onRows: (_) {});
      expect(b.hasMore, isFalse, reason: 'بحثٌ جديد قيد الانتظار لا يُلحق صفحة سابقه');
      b.dispose();
      await visualTearDown();
      BigSubscribersApi.reset();
    });

    testWidgets('الملخّص يُطلب مرّةً لكلّ ٢٠ثانية من الجهات الثلاث، وfresh يتخطّاه', (t) async {
      final srv = await setUpServer();
      await t.runAsync(() async {
        await Future.wait([BigSubscribersApi.summary(), BigSubscribersApi.summary(), BigSubscribersApi.summary()]);
        await BigSubscribersApi.summary();
      });
      expect(srv.summaryCalls, 1);
      await t.runAsync(() => BigSubscribersApi.summary(fresh: true));
      expect(srv.summaryCalls, 2);
      expect(srv.requests.lastWhere((r) => r.path == '/api/v2/subscribers-summary').queryParameters['for'], 'app');
      await visualTearDown();
      BigSubscribersApi.reset();
    });

    testWidgets('فلتر المدير يُمرَّر للساس parent_id في الصفحة والملخّص', (t) async {
      final srv = await setUpServer();
      await t.runAsync(() async {
        await BigSubscribersApi.page(page: 1, tab: 'all', parentId: 501);
        await BigSubscribersApi.summary(parentId: 501);
      });
      expect(srv.pageQueries.any((m) => '${m['parent_id']}' == '501'), isTrue);
      expect(srv.requests.any((r) => r.path == '/api/v2/subscribers-summary' && '${r.queryParameters['parent_id']}' == '501'), isTrue);
      await visualTearDown();
      BigSubscribersApi.reset();
    });
  });

  group('الرئيسية — عدّادات الحساب الكبير', () {
    testWidgets('fetchDebtors من summary.app: العدّادات والدين المعروف', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      server = _BigServer(inner);
      ApiClient.dio.httpClientAdapter = server;
      BigSubscribersApi.reset();
      SubscribersApi.clearAllCaches();
      final r = await t.runAsync(DashboardApi.fetchDebtors);
      expect(r, isNotNull);
      expect(r!.debtsUnknown, isFalse, reason: 'الملخّص يعرف الدين (سوبرنت notes)');
      expect(r.count, 21064);
      expect(r.total, 1416647673);
      expect(r.totalSubs, 89177);
      expect(r.active, 66865);
      expect(r.expired, 22312);
      expect(r.nearExpiry, 9012);
      expect(r.disabled, 745);
      expect(server.askedFullList, isFalse);
      await visualTearDown();
      BigSubscribersApi.reset();
    });
  });
}

