import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/screens/discounts/discounts_screen.dart';
import 'package:rad_mysvcs/screens/managers/managers_screen.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/screens/subscriber_prices/subscriber_prices_screen.dart';

import 'visual_perm/visual_perm_harness.dart';

class _Srv implements HttpClientAdapter {
  _Srv(this.inner);
  final HttpClientAdapter inner;
  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final p = o.path;
    if (o.method == 'GET' && p == '/api/discounts') {
      return _json(200, {'success': true, 'data': [
        {'id': 1, 'subscriber_username': 'zainab.k@najaf', 'discount_amount': 5000, 'package_name': 'Standard', 'package_price': 35000},
        {'id': 2, 'subscriber_username': 'ali1@najaf', 'discount_amount': 10000, 'package_name': 'Standard', 'package_price': 35000},
      ]});
    }
    if (o.method == 'GET' && p == '/api/v2/subscriber-prices') {
      return _json(200, {'success': true, 'data': [
        {'idx': '4', 'username': 'mustafa.office@najaf', 'price': 30000, 'profile_id': 7, 'profile_name': 'Economy'},
        {'idx': '1', 'username': 'ali1@najaf', 'price': 25000, 'profile_id': 7, 'profile_name': 'Economy'},
      ]});
    }
    if (o.method == 'GET' && p == '/api/v2/managers/full') {
      return _json(200, {
        'success': true,
        'data': [
          {'id': 31, 'username': 'ahmed_najaf', 'firstname': 'أحمد', 'lastname': 'كاظم', 'balance': 1250000, 'users_count': 184, 'acl_name': 'وكيل', 'mobile': '07801234567', 'enabled': 1, 'reward_points': 40},
          {'id': 32, 'username': 'hussein.kufa', 'firstname': 'حسين', 'lastname': 'علي', 'balance': -350000, 'total_debt': 350000, 'users_count': 62, 'acl_name': 'وكيل فرعي', 'enabled': 1},
          {'id': 33, 'username': 'old_agent', 'firstname': 'مدير', 'lastname': 'قديم', 'balance': 0, 'users_count': 0, 'enabled': 0},
        ],
        'total': 3,
      });
    }
    if (o.method == 'GET' && p == '/api/admin/manager-debts/summary') {
      return _json(200, {'success': true, 'data': {'per_debtor': [{'debtor_admin_id': 31, 'total_remaining': 75000}]}});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

/// المدراء والخصومات والسعر الثابت بالشكل الموحّد (المالك ٢٣ نوفمبر: «المدراء والخصومات والسعر الثابت كذلك»): بطاقات الأرقام كالتقارير،
/// وبطاقة القائمة؛ ولا فيض ولا قصّ من أضيق هاتف إلى ٤٨٠ بخطٍّ عاديّ ومكبَّر ×1.2.
void main() {
  setUpAll(visualSetUpAll);
  tearDown(visualTearDown);
  final screens = <String, Widget Function()>{
    'managers': () => const ManagersScreen(),
    'discounts': () => const DiscountsScreen(),
    'prices': () => const SubscriberPricesScreen(),
  };
  Future<void> open(WidgetTester t, String screen, double width, double scale, {bool dark = false}) async {
    final inner = await visualSetUp(s1bSasOwner);
    ApiClient.dio.httpClientAdapter = _Srv(inner);
    BigSubscribersApi.reset();
    await pumpVisual(
      t,
      VisualDevice(dark ? '_dark' : '', Size(width, 1700), 2, dark: dark),
      home: (_) => screens[screen]!(),
      wrap: (child) => Builder(
        builder: (ctx) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child),
      ),
    );
    await settle(t, seconds: 2);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
  }

  for (final screen in screens.keys) {
    for (final width in [320.0, 360.0, 480.0]) {
      for (final scale in [1.0, 1.2]) {
        testWidgets('$screen @$width ×$scale: بلا فيض', (t) async {
          await open(t, screen, width, scale, dark: width == 320);
          expect(t.takeException(), isNull);
          expect(find.byType(RpKpiCard), findsNWidgets(2), reason: 'بطاقتا الأرقام بشكل التقارير');
          await close(t);
        });
      }
    }
  }

  testWidgets('المدراء: بطاقة القائمة بعددها، الرصيد السالب بإشارته، والمعطّل بشارته، والبحث والترتيب', (t) async {
    await open(t, 'managers', 390, 1.0);
    expect(find.byKey(const ValueKey('mgr-list')), findsOneWidget);
    expect(find.text('3 مدير'), findsWidgets);
    expect(find.text('2 نشط · 1 معطّل'), findsOneWidget);
    expect(find.text('900,000 د.ع'), findsOneWidget, reason: 'إجمالي الأرصدة: 1,250,000 − 350,000');
    expect(find.text('\u2068−350,000\u2069'), findsOneWidget, reason: 'رصيدٌ سالب بإشارته — كان «350,000»');
    expect(find.text('معطّل'), findsOneWidget);
    expect(find.textContaining('دين SAS 350,000 د.ع'), findsOneWidget);
    // الترتيب بالرصيد تنازليّاً ⇒ الأعلى أوّلاً
    await t.tap(find.byKey(const ValueKey('mgr-sort-balance')));
    await settle(t, seconds: 1);
    await t.tap(find.byKey(const ValueKey('mgr-sort-balance')));
    await settle(t, seconds: 1);
    final top = t.getTopLeft(find.byKey(const ValueKey('mgr-row-31'))).dy;
    expect(top < t.getTopLeft(find.byKey(const ValueKey('mgr-row-32'))).dy, isTrue);
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('mgr-search')), matching: find.byType(TextField)), 'kufa');
    await settle(t, seconds: 1);
    expect(find.byKey(const ValueKey('mgr-row-32')), findsOneWidget);
    expect(find.byKey(const ValueKey('mgr-row-31')), findsNothing);
    expect(find.text('1 مدير'), findsOneWidget, reason: 'عدد القائمة بعد البحث');
    expect(t.takeException(), isNull);
    await close(t);
  });
}
