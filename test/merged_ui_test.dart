import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/merged_dashboard_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/core/platform/desktop_layout.dart';
import 'package:rad_mysvcs/core/util/bidi.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/account/company_switch_sheet.dart';
import 'package:rad_mysvcs/screens/dashboard/dashboard_screen.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/subscribers_card.dart';
import 'package:rad_mysvcs/screens/reports/financial_report_screen.dart';
import 'package:rad_mysvcs/screens/notifications/inbox_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/add_subscriber_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/subscriber_picker_sheet.dart';
import 'package:rad_mysvcs/screens/search/quick_search_overlay.dart';
import 'package:rad_mysvcs/services/alerts_service.dart';
import 'package:rad_mysvcs/widgets/merged_company_pick.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/movements_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/subscriber_usage_store.dart';
import 'package:rad_mysvcs/widgets/merged_company_strip.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «كل الشركات» في التطبيق — الواجهة (٢١ أكتوبر): خيارٌ في «تبديل الشركة»، والمشتركين من شركتين معاً بشارة كلٍّ منهما،
/// والكبيرة والمتعذّرة تُسمّيان، والكتابة على مشتركٍ مدموج تحمل مفتاح شركته ومرجع نافذته. الخادم وهميّ.
const _kA = 'c0000000000aa';
const _kB = 'c0000000000bb';
const _kC = 'c0000000000cc';

Map<String, Object?> _row(int i, {String parent = 'admin@a', String debt = ''}) => {
      'idx': i,
      'username': 'u$i',
      'firstname': 'مشترك',
      'lastname': '$i',
      'parent_username': parent,
      'profile_name': 'Gold',
      'remaining_days': 10,
      'expiration': '2026-12-01 00:00:00',
      'enabled': 1,
      'online_status': 1,
      if (debt.isNotEmpty) 'notes': debt,
    };

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

String _inHours(int h) {
  final d = DateTime.now().add(Duration(hours: h));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

class _Srv implements HttpClientAdapter {
  _Srv(this.inner);
  final HttpClientAdapter inner;
  final routed = <RequestOptions>[];

  /// الجرس: صفٌّ قريب الانتهاء لكلّ شركة (لا يُلمس عدد المشتركين في الاختبارات الأخرى).
  bool nearRows = false;

  /// الترتيب بالاستهلاك: صفوفٌ بأسماء مميّزة واستهلاكٌ معروف لكلّ شركة (ومثلها للشركة المفتوحة وحدها).
  bool usage = false;
  final usageAsked = <String>[];

  static const _usageRows = {
    _kA: [
      {'idx': 1, 'username': 'a1', 'firstname': 'ألف', 'lastname': 'واحد', 'daily_traffic': {'traffic': 50}},
      {'idx': 2, 'username': 'a2', 'firstname': 'ألف', 'lastname': 'اثنان', 'daily_traffic': {'traffic': 300}},
    ],
    _kB: [
      {'idx': 1, 'username': 'b1', 'firstname': 'باء', 'lastname': 'واحد', 'daily_traffic': {'traffic': 10}},
      {'idx': 9, 'username': 'b9', 'firstname': 'باء', 'lastname': 'تسعة', 'daily_traffic': {'traffic': 700}},
    ],
    '-': [
      {'idx': 1, 'username': 's1', 'firstname': 'سين', 'lastname': 'واحد'},
      {'idx': 2, 'username': 's2', 'firstname': 'سين', 'lastname': 'اثنان'},
      {'idx': 3, 'username': 's3', 'firstname': 'سين', 'lastname': 'ثلاثة'},
    ],
  };
  static const _usageMonth = {
    _kA: {'1': 500, '2': 100},
    _kB: {'1': 300, '9': 900},
    '-': {'1': 200, '2': 900, '3': 400},
  };

  ResponseBody? _usageFetch(RequestOptions o, String? key) {
    final path = o.uri.path;
    final k = key ?? '-';
    if (o.method == 'GET' && path == '/api/v2/subscribers' && o.queryParameters['page'] == null && _usageRows.containsKey(k)) {
      return _json(200, {
        'success': true,
        'data': [
          for (final r in _usageRows[k]!) {...r, 'profile_name': 'Gold', 'remaining_days': 10, 'expiration': '2026-12-01 00:00:00', 'enabled': 1},
        ],
      }, headers: key == null ? const {} : {'x-company-key': [key]});
    }
    if (o.method == 'GET' && path == '/api/v2/subscribers-usage') {
      final ids = '${o.queryParameters['ids'] ?? ''}'.split(',').where((x) => x.isNotEmpty).toList();
      usageAsked.add('$k:${ids.join(',')}');
      final m = _usageMonth[k] ?? const <String, int>{};
      return _json(200, {
        'success': true,
        'data': {for (final id in ids) if (m[id] != null) id: {'today': m[id]! ~/ 10, 'month': m[id]}},
      }, headers: key == null ? const {} : {'x-company-key': [key]});
    }
    return null;
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    if (usage) {
      final u = _usageFetch(o, key);
      if (u != null) {
        if (key != null) routed.add(o);
        return u;
      }
    }
    if (key == null) return inner.fetch(o, rs, cf);
    routed.add(o);
    final h = {'x-company-key': [key]};
    final path = o.uri.path;
    if (o.method == 'GET' && path == '/api/v2/subscribers') {
      if (o.queryParameters['page'] != null) {
        // تبويبا الجرس للكبيرة: «أقلّ من ٢٤ ساعة» ٢٥٠ (صفحتها الأولى صفٌّ هنا) و«انتهوا اليوم» صفر
        final tab = o.queryParameters['tab'];
        if (tab == 'expiring_24h' || tab == 'expired_today') {
          final rows = tab == 'expiring_24h' && key == _kC
              ? [
                  {'idx': 777, 'username': 'big777', 'firstname': 'قريب', 'lastname': 'كبير', 'enabled': 1, 'expiration': _inHours(3)},
                ]
              : const <Map<String, Object?>>[];
          return _json(200, {'success': true, 'paged': true, 'total': rows.isEmpty ? 0 : 250, 'last_page': 3, 'data': rows}, headers: h);
        }
        // البحث بالنصّ في الكبيرة (البحث السريع): صفٌّ واحد يطابق
        if (o.queryParameters['q'] != null) {
          final rows = key == _kC
              ? [
                  {'idx': 501, 'username': 'big501', 'firstname': 'مشترك', 'lastname': 'كبير', 'enabled': 1, 'remaining_days': 5,
                    'expiration': '2026-12-01 00:00:00'},
                ]
              : const <Map<String, Object?>>[];
          return _json(200, {'success': true, 'paged': true, 'total': rows.length, 'last_page': 1, 'data': rows}, headers: h);
        }
        return _json(200, {'success': true, 'paged': true, 'total': key == _kC ? 89217 : 3}, headers: h);
      }
      final rows = key == _kA
          ? [_row(1), _row(2, debt: '-5000')]
          : [_row(1, parent: 'admin@b'), _row(9, parent: 'admin@b', debt: '-2500')];
      if (nearRows) rows.add({..._row(key == _kA ? 3 : 10, parent: key == _kA ? 'admin@a' : 'admin@b'), 'expiration': _inHours(5)});
      return _json(200, {'success': true, 'data': rows}, headers: h);
    }
    if (o.method == 'GET' && RegExp(r'^/api/v2/subscribers/\d+$').hasMatch(path)) {
      return _json(200, {'success': true, 'data': {'idx': path.split('/').last}},
          headers: {...h, 'x-company-ref': ['r_${'R' * 22}']});
    }
    if (o.method == 'GET' && path == '/api/reports/finance') {
      final cash = key == _kA ? 10000 : (key == _kB ? 20000 : 7000);
      return _json(200, {
        'success': true,
        'data': {
          'kpis': {'activate_cash_sum': cash, 'debt_pay_sum': key == _kA ? 5000 : 0},
          'recentLogs': [
            {'id': 1, 'action_type': 'DEBT_PAY', 'amount': 1000, 'created_at': key == _kA ? '2026-10-21 12:00:00' : '2026-10-21 11:00:00', 'user_username': 'u$key'},
          ],
        },
      }, headers: h);
    }
    if (o.method == 'GET' && path == '/api/reports/account-statement') {
      return _json(200, {
        'success': true,
        'data': {
          'transactions': [
            {'id': 1, 'action_type': 'DEBT_PAY', 'amount': 2500, 'balance_after': -2500, 'created_at': '2026-10-21T09:00:00Z',
              'description': 'تسديد دين ${key == _kB ? 'باء' : 'ألف'}', 'admin_name': 'admin'},
          ],
        },
      }, headers: h);
    }
    // واتساب كلّ صفحة (٨ نوفمبر): ألف متّصلة، باء منقطعة، الكبيرة تعذّر فحصها
    if (o.method == 'GET' && path.startsWith('/api/whatsapp/connection-status/')) {
      if (key == _kC) return _json(409, {'success': false, 'code': 'COMPANY_UPSTREAM_UNAVAILABLE', 'message': 'x'}, headers: h);
      return _json(200, {'success': true, 'connected': key == _kA, 'phone': key == _kA ? '+9647701112222' : null}, headers: h);
    }
    // «مشترك جديد» داخل شركة: باقاتها ومدراؤها (لا مدراء ⇒ يُنشأ تحت مديرها نفسه)
    if (o.method == 'GET' && path == '/api/v2/packages') {
      return _json(200, {'success': true, 'data': [{'id': 7, 'name': 'Gold', 'price': 25000}]}, headers: h);
    }
    if (o.method == 'GET' && path == '/api/v2/managers') {
      return _json(200, {'success': true, 'data': const []}, headers: h);
    }
    if (o.method == 'GET' && path == '/api/v2/admin-widgets') {
      return _json(200, {'success': true, 'balance': key == _kA ? 100000 : 50000, 'points': 0}, headers: h);
    }
    return _json(200, {'success': true, 'message': 'تم'}, headers: h);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _companies() => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kA, 'code': 'supernet', 'username': 'admin@a', 'name': 'شركة ألف', 'status': 'ok', 'admin_id': '11', 'ns': 'nA', 'currency': 'IQD', 'color_index': 0},
        {'key': _kB, 'code': 'jt', 'username': 'admin@b', 'name': 'شركة باء', 'status': 'ok', 'admin_id': 'jt:22', 'ns': 'nB', 'currency': 'IQD', 'color_index': 1},
        {'key': _kC, 'code': 'full', 'username': 'admin@full', 'name': 'شركة كبيرة', 'status': 'ok', 'admin_id': '33', 'ns': 'nC', 'currency': 'IQD', 'color_index': 2},
        {'key': 'c0000000000dd', 'code': 'x', 'username': 'u', 'name': 'شركة تحتاج دخول', 'status': 'needs_login', 'admin_id': '44', 'ns': 'nD'},
      ],
    };

void main() {
  setUpAll(visualSetUpAll);

  late _Srv srv;
  Future<void> up() async {
    final inner = await visualSetUp(s1bSasOwner);
    srv = _Srv(inner);
    ApiClient.dio.httpClientAdapter = srv;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    MergedMode.reset();
    MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
    SubscribersApi.clearAllCaches();
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    MergedMode.reset();
    await visualTearDown();
  }

  testWidgets('«تبديل الشركة»: «كل الشركات» أعلى الورقة، والنقر يدخله بلا تسجيل', (t) async {
    await up();
    await pumpVisual(t, phone, home: (_) => const CompanySwitchSheet());
    await settle(t, seconds: 2);
    expect(find.text('كل الشركات'), findsOneWidget);
    expect(find.textContaining('3 شركات معاً'), findsOneWidget, reason: 'الصالحة وحدها (لا التي تحتاج دخول)');
    await t.tap(find.text('كل الشركات'));
    await settle(t, seconds: 2);
    expect(MergedMode.active.value, isTrue);
    await down(t);
  });

  testWidgets('المشتركين في «كل الشركات»: صفوف الشركتين بشارة كلٍّ منهما، والكبيرة والتي تحتاج دخول مسمّاتان', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    expect(MergedMode.active.value, isTrue);
    final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
    await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
    await settle(t, seconds: 3);
    expect(find.text('شركة ألف'), findsWidgets);
    expect(find.text('شركة باء'), findsWidgets);
    expect(find.textContaining('كل الشركات · 3 شركات • 4 مشترك'), findsOneWidget,
        reason: 'idx 1 في ساسين مختلفين ⇒ صفّان، والكبيرة خارجها');
    expect(find.textContaining('«شركة كبيرة» كبيرة'), findsOneWidget, reason: 'الكبيرة تُفتح منفردة');
    expect(find.textContaining('شركة تحتاج دخول'), findsWidgets, reason: 'على شارتها وفي سطر «لا تظهر هنا»');
    final full = srv.routed.where((o) => o.uri.path == '/api/v2/subscribers' && o.queryParameters['page'] == null);
    expect(full.map((o) => o.headers['x-company-key']).toSet(), {_kA, _kB}, reason: 'الكبيرة لا تُجلب كاملة');
    // حالة الاتصال بالكارت (٢٢ أكتوبر): موجة الفحص تجري في «كل الشركات» — إعداد أجهزة كلّ شركةٍ منها هي
    final batches = srv.routed.where((o) => o.uri.path == '/api/v2/subscribers/device-batch');
    expect(batches.map((o) => o.headers['x-company-key']).toSet(), {_kA, _kB},
        reason: 'دفعة إعداداتٍ لكلّ شركةٍ في القائمة');
    await down(t);
  });

  testWidgets('٧ نوفمبر (صورة المالك من ويندوز): الحاسبة بـ«كل الشركات» — «مشترك جديد» يبقى ويسمّي الشركة المفتوحة', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    expect(MergedMode.active.value, isTrue);
    final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
    await pumpVisual(t, const VisualDevice('_desk', Size(1440, 900), 1),
        home: (_) => DesktopScope(child: SubscribersScreen(filterCmd: cmd)));
    await settle(t, seconds: 3);
    expect(find.text('مشترك جديد · سوبرنت'), findsOneWidget, reason: 'كان مخفيّاً بالوضع المدموج — يُضاف للشركة المفتوحة');
    await down(t);
    // خارج الوضع المدموج: كما كان
    await up();
    await pumpVisual(t, const VisualDevice('_desk', Size(1440, 900), 1),
        home: (_) => DesktopScope(child: SubscribersScreen(filterCmd: ValueNotifier<SubscriberFilter?>(SubscriberFilter.all))));
    await settle(t, seconds: 3);
    expect(find.text('مشترك جديد'), findsOneWidget);
    await down(t);
  });

  testWidgets('كتابةٌ على مشتركٍ مدموج: مفتاح شركته ومرجع نافذته (هويّته أوّلاً)، والقائمة العاديّة بلا توجيه', (t) async {
    await up();
    await t.runAsync(() => MergedMode.load(fresh: true));
    final sub = Subscriber(idx: '9', username: 'u9', firstname: 'x', lastname: 'y', companyKey: _kB);
    await t.runAsync(() => MergedOps.write(sub, () => SubscribersApi.payDebt(idx: '9', amount: 2500, skipAutoWa: true)));
    final get = srv.routed.firstWhere((o) => o.method == 'GET' && o.uri.path == '/api/v2/subscribers/9');
    expect(get.headers['x-company-key'], _kB);
    final pay = srv.routed.firstWhere((o) => o.method == 'POST' && o.uri.path == '/api/v2/subscribers/9/pay-debt');
    expect(pay.headers['x-company-key'], _kB);
    expect(pay.headers['x-company-ref'], 'r_${'R' * 22}');
    expect(pay.headers.containsKey('Authorization'), isFalse);
    expect(CompanyRefs.lookup(_kB, '9', CompanyRefKind.subject), isNotNull);
    // الوضع العاديّ: المسار نفسه بلا توجيه
    final before = srv.routed.length;
    final plain = Subscriber(idx: '9', username: 'u9', firstname: 'x', lastname: 'y');
    await t.runAsync(() => MergedOps.write(plain, () => SubscribersApi.payDebt(idx: '9', amount: 1, skipAutoWa: true)));
    expect(srv.routed.length, before, reason: 'بلا شركة ⇒ الطلب العاديّ');
    await down(t);
  });

  testWidgets('سجل الحركات لمشتركٍ مدموج (٢٢ أكتوبر): كشف حسابه من شركته — لا «يعمل من الشركة وحدها»', (t) async {
    await up();
    await t.runAsync(() => MergedMode.load(fresh: true));
    final sub = Subscriber(idx: '9', username: 'u9', firstname: 'x', lastname: 'y', companyKey: _kB);
    await pumpVisual(t, phone,
        home: (_) => Builder(
            builder: (c) => Center(child: TextButton(onPressed: () => showMovementsSheet(c, sub), child: const Text('افتح')))));
    await settle(t, seconds: 2);
    await t.tap(find.text('افتح'));
    await settle(t, seconds: 2);
    expect(find.textContaining('تسديد دين باء'), findsOneWidget, reason: 'حركات المشترك من شركته (باء)');
    expect(find.textContaining('يعمل من الشركة وحدها'), findsNothing);
    final st = srv.routed.where((o) => o.uri.path == '/api/reports/account-statement');
    expect(st.map((o) => o.headers['x-company-key']).toSet(), {_kB});
    expect(st.every((o) => !o.headers.containsKey('Authorization')), isTrue);
    await down(t);
  });

  testWidgets('الرئيسية: الرصيد مجموع الشركات بالدينار، والكبيرة داخل الرصيد (لا قائمتها)', (t) async {
    await up();
    await t.runAsync(() => MergedMode.load(fresh: true));
    final w = await t.runAsync(MergedDashboardApi.wallet);
    expect(w!.value!.balance, 100000 + 50000 + 50000, reason: 'الثلاث الصالحة (الكبيرة رصيدها يُقرأ)');
    expect(w.excluded, isEmpty);
    final rows = await t.runAsync(() => MergedSubscribers.load(fresh: true));
    final d = MergedDashboardApi.debtorsFrom(rows!.rows);
    expect(d.totalSubs, 4, reason: 'idx 1 في ساسين مختلفين ⇒ صفّان');
    expect(d.count, 2);
    expect(d.total, 7500);
    await down(t);
  });

  Finder chip(String name) => find.descendant(of: find.byType(MergedCompanyStrip), matching: find.text(name));

  testWidgets('شريط الشركات بالمشتركين: عدد كلٍّ منها، والضغط يعرض الشركة وحدها، و«الكل» يعيد المدموج', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
    await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
    await settle(t, seconds: 3);
    expect(chip('الكل'), findsOneWidget);
    expect(chip('شركة ألف'), findsOneWidget);
    expect(find.descendant(of: find.byType(MergedCompanyStrip), matching: find.text('4')), findsOneWidget, reason: '«الكل» 4');
    await t.tap(chip('شركة باء'));
    await settle(t, seconds: 1);
    expect(MergedMode.focus.value, _kB);
    expect(find.textContaining('«شركة باء» • 2 مشترك'), findsOneWidget);
    expect(find.textContaining('تعرض «شركة باء» وحدها'), findsOneWidget);
    await t.tap(chip('الكل'));
    await settle(t, seconds: 1);
    expect(MergedMode.focus.value, isNull);
    expect(find.textContaining('كل الشركات · 3 شركات • 4 مشترك'), findsOneWidget);
    await t.tap(chip('شركة كبيرة'));
    await settle(t, seconds: 1);
    expect(MergedMode.focus.value, isNull, reason: 'الكبيرة لا تُختار — تقول سببها');
    await down(t);
  });

  testWidgets('واتساب «كل الشركات» (المالك ٨ نوفمبر: «يضل جاري التحقق»): كلّ صفحةٍ بمعرّف مديرها، «واتساب N/M»، وقائمتها بالضغط', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, phone, home: (_) => const DashboardScreen());
    await settle(t, seconds: 3);
    expect(t.takeException(), isNull);
    // كلّ صفحةٍ بطلبٍ موجَّهٍ لها بمعرّف مديرها (المكرَّر لا — والتي تحتاج دخولاً لا تُطلب)
    final wa = srv.routed.where((o) => o.uri.path.startsWith('/api/whatsapp/connection-status/')).toList();
    final byKey = {for (final o in wa) o.headers['x-company-key'] as String: Uri.decodeComponent(o.uri.path.split('/').last)};
    expect(byKey, {_kA: '11', _kB: 'jt:22', _kC: '33'});
    expect(wa.every((o) => o.uri.queryParameters['live'] == null), isTrue, reason: 'لا إعادة ربطٍ من الرئيسية');
    expect(find.text('جارٍ التحقق…'), findsNothing, reason: 'لا تبقى «جارٍ التحقق» في الوضع');
    expect(find.text('واتساب 1/3'), findsOneWidget, reason: 'المتعذّرة لا تُعدّ متّصلة ولا تُخفى');
    await t.tap(find.text('واتساب 1/3'));
    await settle(t, seconds: 1);
    Finder row(String k) => find.byKey(ValueKey('wa-co-$k'));
    expect(find.descendant(of: row(_kA), matching: find.text('واتساب متصل')), findsOneWidget);
    expect(find.descendant(of: row(_kA), matching: find.text('+9647701112222')), findsOneWidget);
    expect(find.descendant(of: row(_kB), matching: find.text('واتساب منقطع')), findsOneWidget);
    expect(find.descendant(of: row(_kC), matching: find.text('تعذّر الفحص')), findsOneWidget);
    expect(find.textContaining('بدّل إليها'), findsOneWidget);
    Navigator.of(t.element(row(_kA))).pop();
    await settle(t, seconds: 1);
    // الشركة المختارة: حالها وحده
    await t.tap(chip('شركة ألف'));
    await settle(t, seconds: 1);
    expect(find.text('واتساب متصل'), findsOneWidget);
    await t.tap(chip('شركة كبيرة'));
    await settle(t, seconds: 1);
    await down(t);
  });

  testWidgets('الرئيسية: الشريط بدل زرّ «العودة» الكبير، والشركة المختارة تغيّر عدد المشتركين', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, phone, home: (_) => const DashboardScreen());
    await settle(t, seconds: 3);
    expect(find.byType(MergedCompanyStrip), findsOneWidget);
    expect(find.text('العودة للشركة المفتوحة'), findsNothing);
    expect(find.descendant(of: find.byType(SubscribersCard), matching: find.text('4')), findsWidgets);
    await t.tap(chip('شركة باء'));
    await settle(t, seconds: 1);
    expect(find.descendant(of: find.byType(SubscribersCard), matching: find.text('2')), findsWidgets);
    await down(t);
  });

  testWidgets('٨ نوفمبر (المالك: «الارصده افصلهن… رصيد كل صفحه بيبن منفصل ولكن بنفس الكارت»): بطاقة الرصيد سطرٌ لكلّ شركة بلا مجموع، والمختارة رصيدها وحده', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, phone, home: (_) => const DashboardScreen());
    await settle(t, seconds: 3);
    expect(find.byKey(const ValueKey('merged-balance-lines')), findsOneWidget);
    expect(find.byKey(const ValueKey('merged-balance-$_kA')), findsOneWidget);
    expect(find.byKey(const ValueKey('merged-balance-$_kB')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('merged-balance-$_kA')), matching: find.text('100,000')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('merged-balance-$_kB')), matching: find.text('50,000')), findsOneWidget);
    expect(find.text('200,000'), findsNothing, reason: 'لا مجموع يخلط أرصدة الصفحات');
    // الشركة المختارة: رصيدها وحده كما كان
    await t.tap(chip('شركة باء'));
    await settle(t, seconds: 1);
    expect(find.byKey(const ValueKey('merged-balance-lines')), findsNothing);
    expect(find.text('50,000'), findsWidgets);
    await down(t);
  });

  // ١٠ نوفمبر — المالك: «حبي ضيف وياك فصل دين الشركه بوضع الشركات يعني ديون المشتركين حسب الشركه» ثمّ «وهنت بالاعلى
  // الدين الكلي مجموعهن». ألف 5,000 (u2) وباء 2,500 (u9)؛ الكبيرة لا قائمة لها والتي تحتاج دخولاً خارج الوضع.
  int fullLists() =>
      srv.routed.where((o) => o.uri.path == '/api/v2/subscribers' && o.queryParameters['page'] == null).length;
  Finder debtTile(String k) => find.byKey(ValueKey('merged-debt-$k'));
  final debtCard = find.byKey(const ValueKey('merged-debt-card'));
  final debtNote = 'بلا «${iso('شركة كبيرة')}»، «${iso('شركة تحتاج دخول')}» — السبب بجانب كلٍّ منها';

  testWidgets('١٠ نوفمبر: «الكل» — المدينون مجموعاً أعلاه ثمّ خانةٌ لكلّ شركة، والكبيرة والتي تحتاج دخولاً خارجه',
      (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, phone, home: (_) => const DashboardScreen());
    await settle(t, seconds: 3);
    expect(t.takeException(), isNull);
    expect(find.text('المدينون — لكلّ شركة'), findsOneWidget);
    expect(find.descendant(of: debtCard, matching: find.text('7,500')), findsOneWidget,
        reason: 'المجموع = 5,000 + 2,500');
    expect(find.descendant(of: debtCard, matching: find.text('2 مشترك · مجموع الشركات')), findsOneWidget);
    expect(find.descendant(of: debtTile(_kA), matching: find.text('5,000')), findsOneWidget);
    expect(find.descendant(of: debtTile(_kA), matching: find.text('1 مشترك')), findsOneWidget);
    expect(find.descendant(of: debtTile(_kB), matching: find.text('2,500')), findsOneWidget);
    expect(find.descendant(of: debtTile(_kB), matching: find.text('1 مشترك')), findsOneWidget);
    expect(find.descendant(of: debtTile(_kC), matching: find.text('كبيرة، افتحها وحدها')), findsOneWidget,
        reason: 'لا صفر لكبيرةٍ لم تُجلب قائمتها');
    expect(find.descendant(of: debtTile('c0000000000dd'), matching: find.text('تحتاج دخول')), findsOneWidget);
    expect(find.descendant(of: debtCard, matching: find.text(debtNote)), findsOneWidget,
        reason: 'من خارج المجموع بسطرٍ واحد');
    // شركةٌ مختارة: بطاقة المدينين الواحدة كما كانت — والاختيار و«الكل» بلا طلب
    final lists = fullLists();
    await t.tap(chip('شركة باء'));
    await settle(t, seconds: 1);
    expect(debtCard, findsNothing);
    expect(find.byKey(const ValueKey('merged-debt-lines')), findsNothing);
    expect(find.text('المدينون'), findsOneWidget);
    expect(find.text('2,500'), findsOneWidget);
    await t.tap(chip('الكل'));
    await settle(t, seconds: 1);
    expect(find.descendant(of: debtCard, matching: find.text('7,500')), findsOneWidget);
    expect(fullLists(), lists, reason: 'من القائمة المدموجة المحفوظة — لا طلب جديد');
    await down(t);
  });

  testWidgets('١٠ نوفمبر: الحاسبة بـ«كل الشركات» و«الكل» — المدينون مجموعاً ثمّ سطرٌ لكلّ شركة بجانب أرصدتها',
      (t) async {
    await up();
    AppPlatform.debugIsDesktop = true;
    addTearDown(() => AppPlatform.debugIsDesktop = null);
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, const VisualDevice('_desk', Size(1440, 900), 1),
        home: (_) => const DesktopScope(child: DashboardScreen()));
    await settle(t, seconds: 3);
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('merged-debt-lines')), findsOneWidget);
    expect(find.text('7,500'), findsOneWidget, reason: 'المجموع رقم البطاقة');
    expect(find.descendant(of: debtTile(_kA), matching: find.text('5,000')), findsOneWidget);
    expect(find.descendant(of: debtTile(_kB), matching: find.text('2,500')), findsOneWidget);
    expect(find.descendant(of: debtTile(_kC), matching: find.text('كبيرة، افتحها وحدها')), findsOneWidget);
    expect(find.descendant(of: debtCard, matching: find.text(debtNote)), findsOneWidget);
    expect(find.byKey(const ValueKey('merged-balance-lines')), findsOneWidget,
        reason: 'أرصدة الشركات بجانبها كما كانت');
    await t.tap(chip('شركة باء'));
    await settle(t, seconds: 1);
    expect(find.byKey(const ValueKey('merged-debt-lines')), findsNothing, reason: 'المختارة: بطاقة اليوم');
    expect(find.text('2,500'), findsOneWidget);
    await down(t);
  });

  testWidgets('التقرير الماليّ: تقريرٌ لكلّ شركة بمديرها ثمّ المجموع وتفصيلٌ لكلّ شركة، والشركة المختارة بلا طلبٍ جديد', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, phone, home: (_) => const FinancialReportScreen());
    await settle(t, seconds: 3);
    final fin = srv.routed.where((o) => o.uri.path == '/api/reports/finance').toList();
    expect({for (final o in fin) o.headers['x-company-key']: o.queryParameters['user_ids']},
        {_kA: '11', _kB: 'jt:22', _kC: '33'}, reason: 'كلّ شركةٍ بمديرها وحده — كطلب الشاشة العاديّة لشركتها');
    expect(find.textContaining('42,000'), findsWidgets, reason: '10000+5000 + 20000 + 7000');
    expect(find.text('حسب الشركة'), findsOneWidget);
    final before = fin.length;
    await t.tap(chip('شركة باء'));
    await settle(t, seconds: 1);
    expect(srv.routed.where((o) => o.uri.path == '/api/reports/finance').length, before, reason: 'تقريرها في المجموع المحفوظ');
    expect(find.textContaining('20,000'), findsWidgets);
    expect(find.text('حسب الشركة'), findsNothing);
    await down(t);
  });

  testWidgets('البحث السريع بـ«كل الشركات»: مشتركو كلّ الشركات بشارة كلٍّ منها، والكبيرة بنصّها موجَّهةً لها — لا قائمة المفتوحة وحدها', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, phone, home: (_) => const QuickSearchOverlay());
    await settle(t, seconds: 2);
    await t.enterText(find.byType(TextField), 'مشترك');
    await settle(t, seconds: 3);
    expect(t.takeException(), isNull);
    expect(find.text('شركة ألف'), findsWidgets, reason: 'شارة الشركة تحت كلّ نتيجة');
    expect(find.text('شركة باء'), findsWidgets);
    expect(find.textContaining('«شركة كبيرة»: 1 نتيجة'), findsOneWidget, reason: 'الكبيرة تُبحث بنصّها');
    expect(find.textContaining('big501'), findsOneWidget);
    final big = srv.routed.where((o) => o.uri.path == '/api/v2/subscribers' && o.queryParameters['q'] != null).toList();
    expect(big.map((o) => o.headers['x-company-key']).toSet(), {_kC}, reason: 'بحث النصّ في الكبيرة وحدها، بمفتاحها');
    final open = (srv.inner as VisualServer).log.where((l) => l.startsWith('GET /api/v2/subscribers '));
    expect(open, isEmpty, reason: 'لا قائمة المفتوحة وحدها في «كل الشركات»');

    // الشركة المختارة في الشريط: نتائجها وحدها
    MergedMode.focus.value = _kB;
    await t.pumpWidget(const SizedBox());
    await pumpVisual(t, phone, home: (_) => const QuickSearchOverlay());
    await settle(t, seconds: 2);
    await t.enterText(find.byType(TextField), 'مشترك');
    await settle(t, seconds: 3);
    expect(find.text('شركة باء'), findsWidgets);
    expect(find.text('شركة ألف'), findsNothing);
    expect(find.textContaining('big501'), findsNothing);
    MergedMode.focus.value = null;
    await down(t);
  });

  testWidgets('الجرس بـ«كل الشركات»: قريبو الانتهاء من كلّ الشركات بشارة كلٍّ منها، والكبيرة بتبويبها موجَّهاً ومجموعها الحقيقيّ', (t) async {
    await up();
    srv.nearRows = true;
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, phone, home: (_) => const InboxScreen());
    await settle(t, seconds: 3);
    expect(t.takeException(), isNull);
    expect(find.text('شركة ألف'), findsWidgets);
    expect(find.text('شركة باء'), findsWidgets);
    expect(find.text('شركة كبيرة'), findsWidgets, reason: 'صفّ الكبيرة من تبويبها بشارتها');
    expect(find.textContaining('big777'), findsOneWidget);
    // ألف + باء + صفّ الكبيرة + ٢٤٩ لم تُحمَّل من صفحتها الأولى
    expect(find.text('252'), findsOneWidget, reason: 'العنوان بالمجموع الحقيقيّ');
    expect(AlertsService.count.value, 252, reason: 'شارة الجرس على الرقم نفسه');
    final tabs = srv.routed.where((o) => o.uri.path == '/api/v2/subscribers' && o.queryParameters['tab'] == 'expiring_24h');
    expect(tabs.map((o) => o.headers['x-company-key']).toSet(), {_kC}, reason: 'تبويب الكبيرة وحدها بمفتاحها');
    final open = (srv.inner as VisualServer).log.where((l) => l.startsWith('GET /api/v2/subscribers '));
    expect(open, isEmpty, reason: 'لا قائمة المفتوحة وحدها في «كل الشركات»');
    srv.nearRows = false;
    await down(t);
  });

  testWidgets('منتقي «+» (تجديد/تسديد/دين) بـ«كل الشركات»: مشتركو كلّ الشركات بشارتها، والكبيرة بنصّها موجَّهةً، والمختار يحمل شركته', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    Subscriber? picked;
    await pumpVisual(t, phone, home: (_) => Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => picked = await showSubscriberPickerSheet(ctx, title: 'تسديد دين', debtorsOnly: true),
                child: const Text('افتح المنتقي'),
              ),
            ),
          ),
        ));
    await settle(t, seconds: 1);
    await t.tap(find.text('افتح المنتقي'));
    await settle(t, seconds: 3);
    expect(t.takeException(), isNull);
    expect(find.textContaining('من كلّ شركاتك'), findsOneWidget);
    // المدينون: u2 (ألف) و u9 (باء) بشارتي شركتيهما
    expect(find.text('شركة ألف'), findsWidgets);
    expect(find.text('شركة باء'), findsWidgets);
    await t.enterText(find.byType(TextField), 'u9');
    await settle(t, seconds: 2);
    expect(srv.routed.where((o) => o.headers['x-company-key'] == _kC && o.queryParameters['q'] == 'u9'), isNotEmpty,
        reason: 'الكبيرة تُبحث بالنصّ موجَّهةً لها');
    expect(find.textContaining('big501'), findsNothing, reason: '«تسديد دين»: صفّ الكبيرة بلا دين لا يظهر');
    await t.tap(find.textContaining('(u9)'));
    await settle(t, seconds: 1);
    expect(picked?.companyKey, _kB, reason: 'الشيت التالي يعمل موجَّهاً لشركة المختار');
    expect(picked?.username, 'u9');
    await down(t);
  });

  testWidgets('«مشترك جديد» بـ«كل الشركات»: «في أيّ شركة؟» ثمّ نافذة الإضافة داخل المختارة — باقاتها وإنشاؤها موجَّهة والمدير الأب مديرها', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    await pumpVisual(t, phone, home: (_) => Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(onPressed: () => showAddSubscriberSheet(ctx), child: const Text('أضف')),
            ),
          ),
        ));
    await settle(t, seconds: 1);
    await t.tap(find.text('أضف'));
    await settle(t, seconds: 2);
    expect(t.takeException(), isNull);
    expect(find.text('في أيّ شركة؟'), findsOneWidget);
    expect(find.textContaining('يُضاف إليها من هنا'), findsWidgets);
    // شركة باء (غير المفتوحة) ⇒ نافذة الإضافة داخلها
    await t.tap(find.byKey(const ValueKey('merged-pick-$_kB')));
    await settle(t, seconds: 2);
    expect(find.textContaining('في «شركة باء»'), findsOneWidget);
    expect(srv.routed.where((o) => o.uri.path == '/api/v2/packages').map((o) => o.headers['x-company-key']).toSet(), {_kB},
        reason: 'باقاتها لا باقات المفتوحة');
    await t.enterText(find.widgetWithText(TextField, 'مثال: ahmed@rezz'), 'new.user');
    await t.enterText(find.widgetWithText(TextField, '••••••••'), 'pw123456');
    await t.tap(find.byType(DropdownButton<int>));
    await settle(t, seconds: 1);
    await t.tap(find.text('Gold').last);
    await settle(t, seconds: 1);
    await t.tap(find.text('إضافة المشترك'));
    await settle(t, seconds: 2);
    final add = srv.routed.where((o) => o.method == 'POST' && o.uri.path == '/api/v2/subscribers').toList();
    expect(add, hasLength(1), reason: 'إنشاءٌ واحد موجَّه');
    expect(add.single.headers['x-company-key'], _kB);
    expect((add.single.data as Map)['parent_id'], 22, reason: 'مدير شركة باء (jt:22) لا مدير المفتوحة');
    expect((add.single.data as Map)['profile_id'], 7);
    await down(t);
  });

  testWidgets('ترتيب المشتركين باستهلاك الشهر واليوم (٨ نوفمبر): بالشركتين وبالشركة الواحدة، تنازليّاً وتصاعديّاً — والقراءة لشركة كلّ صفّ', (t) async {
    await up();
    srv.usage = true;
    // قوائم «كل الشركات» محفوظة ٤٥ث واستهلاكها ٥ د من اختباراتٍ سابقة في الملفّ — هذا الاختبار بصفوفه هو
    MergedSubscribers.reset();
    SubscriberUsageStore.reset();
    Future<void> sortBy(String field, String dir) async {
      await t.tap(find.byIcon(Icons.swap_vert_rounded));
      await settle(t, seconds: 1);
      await t.tap(find.text(field).last);
      await t.tap(find.text(dir).last);
      await t.tap(find.text('تطبيق').last);
      await settle(t, seconds: 3);
    }

    List<String> order(List<String> names) {
      final ys = {for (final n in names) n: t.getTopLeft(find.text(n).first).dy};
      final out = [...names]..sort((a, b) => ys[a]!.compareTo(ys[b]!));
      return out;
    }

    // ── بالشركتين ──
    await t.runAsync(() => MergedMode.enter());
    final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
    // شاشةٌ طويلة: الصفوف كلّها مبنيّة (القائمة كسولة)
    const tall = VisualDevice('', Size(390, 2600), 1);
    await pumpVisual(t, tall, home: (_) => SubscribersScreen(filterCmd: cmd));
    await settle(t, seconds: 3);
    expect(t.takeException(), isNull);
    const merged = ['ألف واحد', 'ألف اثنان', 'باء واحد', 'باء تسعة'];
    await sortBy('استهلاك الشهر', 'تنازلي');
    expect(t.takeException(), isNull);
    expect(order(merged), ['باء تسعة', 'ألف واحد', 'باء واحد', 'ألف اثنان'], reason: '900 · 500 · 300 · 100');
    expect(srv.usageAsked.toSet(), {'$_kA:1,2', '$_kB:1,9'}, reason: 'كلّ شركةٍ بطلبها الموجَّه لصفوفها وحدها');
    await sortBy('استهلاك الشهر', 'تصاعدي');
    expect(order(merged), ['ألف اثنان', 'باء واحد', 'ألف واحد', 'باء تسعة']);
    expect(srv.usageAsked, hasLength(2), reason: 'المقروء قبل ٥ دقائق لا يُعاد');
    // اليوم: من صفّ الساس نفسه بلا طلب (700 · 300 · 50 · 10)
    await sortBy('استهلاك اليوم', 'تنازلي');
    expect(order(merged), ['باء تسعة', 'ألف اثنان', 'ألف واحد', 'باء واحد']);
    await sortBy('استهلاك اليوم', 'تصاعدي');
    expect(order(merged), ['باء واحد', 'ألف واحد', 'ألف اثنان', 'باء تسعة']);
    expect(srv.usageAsked, hasLength(2), reason: 'اليوم لا يحتاج قراءة للساس');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    MergedMode.reset();

    // ── بالشركة الواحدة ──
    SubscribersApi.clearAllCaches();
    srv.usageAsked.clear();
    final cmd2 = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
    await pumpVisual(t, tall, home: (_) => SubscribersScreen(filterCmd: cmd2));
    await settle(t, seconds: 3);
    const single = ['سين واحد', 'سين اثنان', 'سين ثلاثة'];
    await sortBy('استهلاك الشهر', 'تنازلي');
    expect(order(single), ['سين اثنان', 'سين ثلاثة', 'سين واحد'], reason: '900 · 400 · 200');
    expect(srv.usageAsked, ['-:1,2,3'], reason: 'طلبٌ واحد للمفتوحة بلا توجيه');
    await sortBy('استهلاك الشهر', 'تصاعدي');
    expect(order(single), ['سين واحد', 'سين ثلاثة', 'سين اثنان']);
    srv.usage = false;
    await down(t);
  });

  testWidgets('«+ إضافة صرفية» بـ«كل الشركات»: «في أيّ شركة؟» — المفتوحة تُكمل، وغيرها يذهب لقسمها (onOther) لا للمفتوحة', (t) async {
    await up();
    await t.runAsync(() => MergedMode.enter());
    bool? result;
    MergedCompany? other;
    await pumpVisual(t, phone, home: (_) => Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => result = await pickOpenCompanyFor(ctx,
                    action: 'صرفية جديدة',
                    reason: 'الصرفيّة لها من صرفياتها',
                    otherHint: 'تُضاف من صرفياتها — تُفتح هنا',
                    onOther: (c) async => other = c),
                child: const Text('صرفية'),
              ),
            ),
          ),
        ));
    await settle(t, seconds: 1);
    await t.tap(find.text('صرفية'));
    await settle(t, seconds: 2);
    expect(find.text('في أيّ شركة؟'), findsOneWidget);
    expect(find.textContaining('تُضاف من صرفياتها — تُفتح هنا'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('merged-pick-$_kB')));
    await settle(t, seconds: 1);
    expect(result, isFalse, reason: 'لا شيت إضافةٍ للمفتوحة');
    expect(other?.key, _kB, reason: 'قسم صرفيات «شركة باء» هو ما يُفتح');
    await down(t);
  });
}
