import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/dashboard_api.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/hero_revenue_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «الإيرادات» والتفعيل الآجل (٢٩ أكتوبر — المالك على popq: «الإيرادات اليوم كيف صفر… واكو حركة تفعيل!»): الإيرادات ما دخل
/// نقداً (`totals.total_payments`)، والتفعيل على الدين ليس منها حتى يُسدَّد — فيُقال تحت الرقم «+ X آجل (دين)» من
/// `kpis.activate_non_cash_sum` في الطلب نفسه، والرقم نفسه لا يتغيّر.
void main() {
  late _Server server;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({'auth.token': 'tok', 'auth.admin_id': '2'});
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    server = _Server();
    final adapter = ApiClient.dio.httpClientAdapter;
    ApiClient.dio.httpClientAdapter = server;
    addTearDown(() => ApiClient.dio.httpClientAdapter = adapter);
  });

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('ar'), Locale('en')],
      path: 'assets/translations',
      startLocale: const Locale('ar'),
      fallbackLocale: const Locale('ar'),
      saveLocale: false,
      assetLoader: const _DiskLoader(),
      child: Builder(
        builder: (ctx) => MaterialApp(
          locale: ctx.locale,
          supportedLocales: ctx.supportedLocales,
          localizationsDelegates: ctx.localizationDelegates,
          home: const Scaffold(body: Padding(padding: EdgeInsets.all(16), child: HeroRevenueCard())),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('يومٌ بتفعيلٍ على الدين وحده: الإيرادات 0 وتحتها «+ 30,000 د.ع آجل (دين)»', (t) async {
    server.payments = 0;
    server.deferred = 30000;
    await pump(t);
    expect(find.text('0'), findsOneWidget, reason: 'الرقم نفسه — ما دخل نقداً');
    expect(find.text('+ 30,000 د.ع آجل (دين) — يدخل الإيرادات عند التسديد'), findsOneWidget);
  });

  testWidgets('يومٌ نقديّ بلا آجل: لا سطر', (t) async {
    server.payments = 45000;
    server.deferred = 0;
    await pump(t);
    expect(find.text('45,000'), findsOneWidget);
    expect(find.textContaining('آجل'), findsNothing);
  });

  test('الخادم الأقدم بلا kpis ⇒ deferred null (لا صفرٌ مخترَع)', () async {
    server.payments = 1000;
    server.deferred = null;
    final r = await DashboardApi.fetchRevenue(RevenuePeriod.day);
    expect(r?.amount, 1000);
    expect(r?.deferred, isNull);
  });
}

class _DiskLoader extends AssetLoader {
  const _DiskLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => Future.value(
        jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>,
      );
}

class _Server implements HttpClientAdapter {
  int payments = 0;
  int? deferred;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    final Object body = o.path == '/api/reports/finance'
        ? {
            'success': true,
            'data': {
              'totals': {'total_payments': payments},
              if (deferred != null) 'kpis': {'activate_non_cash_sum': deferred},
              'timeseries': const [],
            },
          }
        : {'success': true};
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
