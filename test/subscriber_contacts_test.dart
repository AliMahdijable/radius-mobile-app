import 'dart:async';

import 'package:dio/dio.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/subscriber_contacts_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_contacts_card.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «أرقام تواصل إضافيّة» (المالك ١٤ نوفمبر: «اضافة امكانيه اضافة رقم واتساب ومعرف او رقم تلي كرام للمشترك … يستعين بالرقم الثاني …
/// بمعرف تلي»): المتحكّم يجلبها مرّة، والورقة (من «المزيد») تحفظ الحقلين (PUT) وتُظهر خطأ الخادم تحت حقله، والمفتاح المطفأ ⇒ لا
/// ورقة، و«كل الشركات» ⇒ بشركة المشترك ومرجع نافذته (الدفعة ب، ٢١ نوفمبر). عرضها داخل بطاقة الهويّة (المالك ١٤ نوفمبر: «يظهرهن هنا وي كارت») ⇒
/// subscriber_hero_contacts_test.dart.
const _v = SimVariant(390, dark: false);
const _path = SubscriberContactsApi.path;

Subscriber _sub({String? companyKey}) => Subscriber.fromJson({
      'idx': '900004',
      'username': 'ali.hasan',
      'firstname': 'علي حسن',
      'phone': '07701234567',
      'expiration': '2026-12-01 18:00:00',
      'remaining_days': 17,
    }).withCompany(companyKey);

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'myservices'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
  });

  tearDown(PermissionsService.debugReset);

  /// المتحكّم كما تملكه شاشة المشترك (يجلب عند إنشائه)، وزرٌّ يفتح ورقته كما يفتحها «المزيد».
  Future<SubscriberContactsController> open(WidgetTester t, {Subscriber? sub}) async {
    final c = SubscriberContactsController(sub ?? _sub());
    addTearDown(c.dispose);
    await pumpSim(t, _v, home: (_) => simLauncher((ctx) => c.edit(ctx)));
    unawaited(c.load());
    await t.pumpAndSettle();
    return c;
  }

  testWidgets('أرقامٌ قائمة: تظهر بالكرت، و«تعديل» يحفظ الحقلين ويُرسل رقم المشترك ليُرفض الرقم نفسه', (t) async {
    server.reply('GET', _path, 200, {'success': true, 'enabled': true, 'contact': {'wa_phone2': '07801234567', 'tg_contact': '@ali_hasan'}});
    server.on('PUT', _path, (o) {
      final b = o.data as Map;
      return SimReply(200, {'success': true, 'contact': {'wa_phone2': b['wa_phone2'], 'tg_contact': '@ali_new'}});
    });
    final c = await open(t);
    expect(server.calls('GET', _path).single.queryParameters['username'], 'ali.hasan');
    expect(c.contact?.waPhone2, '07801234567');
    expect(c.contact?.tgContact, '@ali_hasan');

    await simOpen(t);
    await t.enterText(find.byKey(const ValueKey('sub-contacts-wa_phone2')), '07901234567');
    await t.enterText(find.byKey(const ValueKey('sub-contacts-tg_contact')), 'ali_new');
    await t.pumpAndSettle();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    expect(server.bodies('PUT', _path).single,
        {'username': 'ali.hasan', 'wa_phone2': '07901234567', 'tg_contact': 'ali_new', 'phone': '07701234567'});
    expect(c.contact?.waPhone2, '07901234567', reason: 'ما حُفظ يصل البطاقة عبر المتحكّم');
    expect(c.contact?.tgContact, '@ali_new');
    await simDrain(t);
  });

  testWidgets('خطأ الخادم بحقله: يظهر تحت الحقل والورقة باقية', (t) async {
    server.reply('GET', _path, 200, {'success': true, 'enabled': true, 'contact': {'wa_phone2': '07801234567'}});
    server.reply('PUT', _path, 400, {'success': false, 'field': 'wa_phone2', 'message': 'رقم الواتساب غير صحيح — اكتبه مثل 07701234567'});
    final c = await open(t);
    await simOpen(t);
    await t.enterText(find.byKey(const ValueKey('sub-contacts-wa_phone2')), '0770');
    await t.pumpAndSettle();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    expect(find.text('رقم الواتساب غير صحيح — اكتبه مثل 07701234567'), findsOneWidget);
    expect(find.byKey(const ValueKey('sub-contacts-wa_phone2')), findsOneWidget, reason: 'الورقة باقية للتصحيح');
    expect(c.contact?.waPhone2, '07801234567');
    await simDrain(t);
  });

  testWidgets('بلا أرقام: الإضافة من الورقة تملأ المتحكّم (فتظهر بالبطاقة)', (t) async {
    server.reply('GET', _path, 200, {'success': true, 'enabled': true, 'contact': null});
    server.reply('PUT', _path, 200, {'success': true, 'contact': {'wa_phone2': null, 'tg_contact': '@ali_hasan'}});
    final c = await open(t);
    expect(c.contact, isNull);
    expect(c.ready && c.enabled, isTrue);
    await simOpen(t);
    await t.enterText(find.byKey(const ValueKey('sub-contacts-tg_contact')), '@ali_hasan');
    await t.pumpAndSettle();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    expect(c.contact?.tgContact, '@ali_hasan');
    expect(c.contact?.waPhone2, isNull, reason: 'الواتساب الفارغ لا يُخترع');
    await simDrain(t);
  });

  testWidgets('المفتاح مطفأ للحساب: لا ورقة', (t) async {
    server.reply('GET', _path, 200, {'success': true, 'enabled': false, 'contact': null});
    final c = await open(t);
    expect(c.enabled, isFalse);
    await simOpen(t);
    expect(find.byType(TextField), findsNothing);
    await simDrain(t);
  });

  testWidgets('«كل الشركات» (الدفعة ب، ٢١ نوفمبر): الجلب والحفظ لشركة المشترك بمرجع نافذته (يوزره) — لا شيء للمفتوحة', (t) async {
    const key = 'c0000000000b2';
    final ref = 'r_${'k' * 22}';
    server.echoCompanyKey = true;
    final prev = AccountApi.tokenSource;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    addTearDown(() {
      AccountApi.tokenSource = prev;
      CompanyRefs.reset();
    });
    // نافذة المشترك فُتحت في شركته (صفحته) — الخادم سكّ مرجعها، والعميل يحفظه بيوزره أيضاً
    CompanyRefs.reset();
    CompanyRefs.capture(key, 'GET', '/api/v2/subscribers/900004', Headers.fromMap({'x-company-ref': [ref]}),
        {'success': true, 'data': {'idx': '900004', 'username': 'ali.hasan'}});
    server.reply('GET', _path, 200, {'success': true, 'enabled': true, 'contact': {'wa_phone2': '07801234567'}});
    server.on('PUT', _path, (o) {
      final b = o.data as Map;
      return SimReply(200, {'success': true, 'contact': {'wa_phone2': b['wa_phone2'], 'tg_contact': null}});
    });
    final c = await open(t, sub: _sub(companyKey: key));
    final g = server.calls('GET', _path).single;
    expect([g.headers['x-company-key'], g.queryParameters['username']], [key, 'ali.hasan'], reason: 'من شركة المشترك');
    expect(c.ready && c.enabled, isTrue);
    expect(c.contact?.waPhone2, '07801234567');
    await simOpen(t);
    await t.enterText(find.byKey(const ValueKey('sub-contacts-wa_phone2')), '07901234567');
    await t.pumpAndSettle();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    final p = server.calls('PUT', _path).single;
    expect([p.headers['x-company-key'], p.headers['x-company-ref']], [key, ref], reason: 'لشركته بمرجع نافذته');
    expect((p.data as Map)['username'], 'ali.hasan');
    expect(server.requests.where((o) => o.method != 'GET' && o.headers['x-company-key'] == null), isEmpty, reason: 'لا كتابة للمفتوحة');
    expect(c.contact?.waPhone2, '07901234567');
    await simDrain(t);
  });

  testWidgets('الموظّف بلا subscribers.edit: الأرقام تُقرأ (تظهر بالبطاقة) — والإضافة مقفلةٌ بمكانها في «المزيد»', (t) async {
    PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
    server.reply('GET', _path, 200, {'success': true, 'enabled': true, 'contact': {'wa_phone2': '07801234567'}});
    final c = await open(t);
    expect(c.ready && c.enabled, isTrue);
    expect(c.contact?.waPhone2, '07801234567');
    await simDrain(t);
  });
}
