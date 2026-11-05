import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/usage_on_demand.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/services/subscriber_usage_store.dart';

/// خادم «عند الطلب» كالوطنيّ (⑯، ٥ نوفمبر): الدفعة من ذاكرته وحدها (`on_demand`، بلا قيم)، وطلب مشتركٍ واحد يجيب.
class _OnDemandServer implements HttpClientAdapter {
  final asked = <Map<String, dynamic>>[];
  final companies = <String?>[];
  bool busy = false;
  bool echo = true;
  Completer<void>? hold;
  final arrived = Completer<void>();

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    asked.add(Map<String, dynamic>.from(o.queryParameters));
    final company = o.headers['x-company-key'] as String?;
    companies.add(company);
    if (!arrived.isCompleted) arrived.complete();
    await hold?.future;
    ResponseBody reply(Object data, [int status = 200]) =>
        _json(data, status, company: echo ? company : null);
    final ids = (o.queryParameters['ids'] ?? '').toString().split(',');
    if (o.queryParameters['one'] != '1')
      return reply(
          {'success': true, 'data': {}, 'errors': 0, 'on_demand': true});
    if (busy)
      return reply({
        'success': false,
        'code': 'PROVIDER_BUSY',
        'message': 'المشروع الوطني مشغولة الآن — أعد بعد دقيقة'
      }, 503);
    return reply({
      'success': true,
      'data': {
        ids.single: {
          'today': 1073741824 * 2,
          'month': 1073741824 * (company == 'c0000000000bb' ? 80 : 40)
        }
      },
      'errors': 0,
      'on_demand': true,
    });
  }

  static ResponseBody _json(Object b, int status, {String? company}) =>
      ResponseBody.fromString(jsonEncode(b), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        if (company != null) 'x-company-key': [company]
      });

  @override
  void close({bool force = false}) {}
}

void main() {
  late _OnDemandServer server;
  final originalTokenSource = AccountApi.tokenSource;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AccountApi.tokenSource = ({bool force = false}) async => 'test-account';
    server = _OnDemandServer();
    ApiClient.dio.httpClientAdapter = server;
    SubscriberUsageStore.reset();
    UsagePrefs.enabled.value = true;
    SubscriberUsageStore.columnShown = false;
    ProviderService.debugSet(null);
  });
  tearDown(() {
    AccountApi.tokenSource = originalTokenSource;
    if (server.hold != null && !server.hold!.isCompleted)
      server.hold!.complete();
    SubscriberUsageStore.reset();
    UsagePrefs.enabled.value = false;
    ProviderService.debugSet(null);
  });

  test('الشركة المفتوحة وطنيّة ⇒ لا دفعة للصفوف الظاهرة أصلاً', () async {
    ProviderService.debugSet('watani');
    expect(SubscriberUsageStore.isOnDemand(null), isTrue);
    SubscriberUsageStore.want('11');
    SubscriberUsageStore.want('12');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(server.asked, isEmpty);
  });

  test(
      'دفعةٌ ردّها on_demand (شركة صفٍّ مدموج) ⇒ تُعرف الشركة: صفوفها بلا «—» ولا دفعاتٍ بعدها',
      () async {
    SubscriberUsageStore.want('21', company: 'c0000000000aa');
    SubscriberUsageStore.want('22', company: 'c0000000000aa');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(server.asked, hasLength(1));
    expect(server.companies, ['c0000000000aa']);
    expect(SubscriberUsageStore.isOnDemand('c0000000000aa'), isTrue);
    expect(SubscriberUsageStore.get('21', company: 'c0000000000aa'), isNull,
        reason: 'لا «تعذّر» — زرٌّ');
    SubscriberUsageStore.want('23', company: 'c0000000000aa');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(server.asked, hasLength(1));
    expect(SubscriberUsageStore.isOnDemand(null), isFalse,
        reason: 'الشركة المفتوحة كما هي');
  });

  test('نفس معرّف المشترك في شركتين ⇒ كل طلب وكاش لشركته، والرد بلا صدى مرفوض',
      () async {
    await SubscriberUsageStore.requestOne('31', company: 'c0000000000aa');
    await SubscriberUsageStore.requestOne('31', company: 'c0000000000bb');
    expect(server.companies, ['c0000000000aa', 'c0000000000bb']);
    expect(SubscriberUsageStore.one('31', company: 'c0000000000aa').v?.month,
        1073741824 * 40);
    expect(SubscriberUsageStore.one('31', company: 'c0000000000bb').v?.month,
        1073741824 * 80);
    expect(SubscriberUsageStore.one('31').v, isNull);
    server.echo = false;
    await SubscriberUsageStore.requestOne('32', company: 'c0000000000aa');
    expect(SubscriberUsageStore.one('32', company: 'c0000000000aa').v, isNull);
    expect(SubscriberUsageStore.one('32', company: 'c0000000000aa').err,
        contains('الشركة'));
  });

  test('النقر المتكرر طلب واحد، ورد الحساب السابق لا يغيّر الحساب الجديد',
      () async {
    server.hold = Completer<void>();
    final first = SubscriberUsageStore.requestOne('51');
    await server.arrived.future;
    await SubscriberUsageStore.requestOne('51');
    expect(server.asked, hasLength(1));
    expect(SubscriberUsageStore.one('51').loading, isTrue);
    SubscriberUsageStore.reset();
    server.hold!.complete();
    await first;
    expect(SubscriberUsageStore.one('51').v, isNull);
    expect(SubscriberUsageStore.one('51').loading, isFalse);
    await SubscriberUsageStore.requestOne('51');
    expect(server.asked, hasLength(2));
    expect(SubscriberUsageStore.one('51').v, isNotNull);
  });

  test(
      'requestOne: مشتركٌ واحد بـ one=1 · القيمة تبقى · fresh للتحديث · التعذّر برسالة الخادم',
      () async {
    ProviderService.debugSet('watani');
    await SubscriberUsageStore.requestOne('31');
    expect(server.asked.single['ids'], '31');
    expect(server.asked.single['one'], '1');
    var s = SubscriberUsageStore.one('31');
    expect(s.v?.month, 1073741824 * 40);
    expect(s.loading, isFalse);
    await SubscriberUsageStore.requestOne('31', fresh: true);
    expect(server.asked.last['fresh'], '1');
    server.busy = true;
    await SubscriberUsageStore.requestOne('32');
    s = SubscriberUsageStore.one('32');
    expect(s.v, isNull);
    expect(s.err, contains('مشغولة'));
  });

  testWidgets(
      'الزرّ ⇒ يُجلب ⇒ اليوم · الشهر وزرّ التحديث (كارت الهاتف والجدول)',
      (t) async {
    ProviderService.debugSet('watani');
    Future<void> pump(bool stacked) => t.pumpWidget(MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
                body:
                    Center(child: UsageOnDemand(idx: '41', stacked: stacked))),
          ),
        ));
    await pump(false);
    expect(find.text('عرض الاستهلاك'), findsOneWidget);
    expect(server.asked, isEmpty, reason: 'لا شيء قبل اللمس');
    await t.tap(find.text('عرض الاستهلاك'));
    // الطلب يمرّ بعميل dio الحقيقيّ (مجاري الردّ) ⇒ وقتٌ حقيقيّ يتناوب مع ضخّ الإطارات
    for (var i = 0; i < 30 && SubscriberUsageStore.one('41').v == null; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(server.asked.single['ids'], '41');
    expect(find.textContaining('2.00 GB'), findsOneWidget);
    expect(find.textContaining('40.0 GB'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    await pump(true);
    await t.pump();
    expect(find.textContaining('40.0 GB'), findsOneWidget);
  });

  testWidgets(
      'عمود ضيق ونص مكبّر: الزر والأرقام والخطأ بلا تجاوز، والتحديث الفاشل يبيّن القيمة السابقة',
      (t) async {
    ProviderService.debugSet('watani');
    for (final stacked in [false, true]) {
      for (final width in [80.0, 112.0, 280.0]) {
        SubscriberUsageStore.reset();
        server.busy = false;
        await t.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.2)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                  body: Center(
                      child: SizedBox(
                width: width,
                child: UsageOnDemand(idx: '61', stacked: stacked),
              ))),
            ),
          ),
        ));
        expect(t.takeException(), isNull);
        await t.runAsync(() => SubscriberUsageStore.requestOne('61'));
        await t.pump();
        expect(t.takeException(), isNull);
        expect(find.textContaining('40.0 GB'), findsOneWidget);
        server.busy = true;
        await t
            .runAsync(() => SubscriberUsageStore.requestOne('61', fresh: true));
        await t.pump();
        expect(find.text('تعذّر التحديث — القيمة السابقة'), findsOneWidget);
        expect(find.textContaining('40.0 GB'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          SubscriberUsageStore.reset();
          await SubscriberUsageStore.requestOne('61');
        });
        await t.pump();
        expect(find.text('أعد المحاولة'), findsOneWidget);
        expect(t.takeException(), isNull);
      }
    }
  });
}
