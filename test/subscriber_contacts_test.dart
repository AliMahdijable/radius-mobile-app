import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/subscriber_contacts_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_contacts_card.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «أرقام تواصل إضافيّة» (المالك ١٤ نوفمبر: «اضافة امكانيه اضافة رقم واتساب ومعرف او رقم تلي كرام للمشترك … يستعين بالرقم الثاني …
/// بمعرف تلي»): الكرت للأرقام القائمة وحدها (الإضافة من «المزيد» كالملاحظة)، والورقة تحفظ الحقلين (PUT) وتُظهر خطأ الخادم تحت حقله،
/// والمفتاح المطفأ ⇒ لا كرت، و«كل الشركات» ⇒ لا جلب، والموظّف بلا subscribers.edit ⇒ «تعديل» مقفل.
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

  Future<SubscriberContactsController> open(WidgetTester t, {Subscriber? sub, bool canEdit = true}) async {
    final c = SubscriberContactsController(sub ?? _sub());
    addTearDown(c.dispose);
    await pumpSim(t, _v,
        home: (_) => Scaffold(body: SingleChildScrollView(child: SubscriberContactsCard(controller: c, canEdit: canEdit))));
    return c;
  }

  testWidgets('أرقامٌ قائمة: تظهر بالكرت، و«تعديل» يحفظ الحقلين ويُرسل رقم المشترك ليُرفض الرقم نفسه', (t) async {
    server.on('GET', _path, (o) {
      expect(o.queryParameters['username'], 'ali.hasan');
      return const SimReply(200, {'success': true, 'enabled': true, 'contact': {'wa_phone2': '07801234567', 'tg_contact': '@ali_hasan'}});
    });
    server.on('PUT', _path, (o) {
      final b = o.data as Map;
      return SimReply(200, {'success': true, 'contact': {'wa_phone2': b['wa_phone2'], 'tg_contact': '@ali_new'}});
    });
    await open(t);
    expect(find.text('أرقام تواصل إضافيّة'), findsOneWidget);
    expect(find.text('07801234567'), findsOneWidget);
    expect(find.text('@ali_hasan'), findsOneWidget);

    await t.tap(find.text('تعديل'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('sub-contacts-wa_phone2')), '07901234567');
    await t.enterText(find.byKey(const ValueKey('sub-contacts-tg_contact')), 'ali_new');
    await t.pumpAndSettle();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    expect(server.bodies('PUT', _path).single,
        {'username': 'ali.hasan', 'wa_phone2': '07901234567', 'tg_contact': 'ali_new', 'phone': '07701234567'});
    expect(find.text('07901234567'), findsOneWidget);
    expect(find.text('@ali_new'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('خطأ الخادم بحقله: يظهر تحت الحقل والورقة باقية', (t) async {
    server.reply('GET', _path, 200, {'success': true, 'enabled': true, 'contact': {'wa_phone2': '07801234567'}});
    server.reply('PUT', _path, 400, {'success': false, 'field': 'wa_phone2', 'message': 'رقم الواتساب غير صحيح — اكتبه مثل 07701234567'});
    final c = await open(t);
    unawaited(c.edit(t.element(find.byType(SubscriberContactsCard))));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('sub-contacts-wa_phone2')), '0770');
    await t.pumpAndSettle();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    expect(find.text('رقم الواتساب غير صحيح — اكتبه مثل 07701234567'), findsOneWidget);
    expect(find.byKey(const ValueKey('sub-contacts-wa_phone2')), findsOneWidget, reason: 'الورقة باقية للتصحيح');
    expect(c.contact?.waPhone2, '07801234567');
    await simDrain(t);
  });

  testWidgets('بلا أرقام: لا كرت (الإضافة من «المزيد»)، والإضافة بالمتحكّم تُظهره', (t) async {
    server.reply('GET', _path, 200, {'success': true, 'enabled': true, 'contact': null});
    server.reply('PUT', _path, 200, {'success': true, 'contact': {'wa_phone2': null, 'tg_contact': '@ali_hasan'}});
    final c = await open(t);
    expect(find.text('أرقام تواصل إضافيّة'), findsNothing);
    expect(c.ready && c.enabled, isTrue);
    unawaited(c.edit(t.element(find.byType(SubscriberContactsCard))));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('sub-contacts-tg_contact')), '@ali_hasan');
    await t.pumpAndSettle();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    expect(find.text('@ali_hasan'), findsOneWidget);
    expect(find.text('واتساب ثانٍ'), findsNothing, reason: 'سطر الواتساب الفارغ لا يظهر');
    await simDrain(t);
  });

  testWidgets('المفتاح مطفأ للحساب: لا كرت ولا تعديل', (t) async {
    server.reply('GET', _path, 200, {'success': true, 'enabled': false, 'contact': null});
    final c = await open(t);
    expect(c.enabled, isFalse);
    expect(find.text('أرقام تواصل إضافيّة'), findsNothing);
    await c.edit(t.element(find.byType(SubscriberContactsCard)));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await simDrain(t);
  });

  testWidgets('«كل الشركات» (مشتركٌ من شركةٍ أخرى): لا جلب ولا كرت', (t) async {
    server.reply('GET', _path, 200, {'success': true, 'enabled': true, 'contact': {'wa_phone2': '07801234567'}});
    final c = await open(t, sub: _sub(companyKey: 'earthlink:1025'));
    expect(server.calls('GET', _path), isEmpty);
    expect(c.loaded, isFalse);
    expect(find.text('أرقام تواصل إضافيّة'), findsNothing);
    await simDrain(t);
  });

  testWidgets('الموظّف بلا subscribers.edit: الأرقام تُقرأ و«تعديل» مقفل ولا ورقة', (t) async {
    PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
    server.reply('GET', _path, 200, {'success': true, 'enabled': true, 'contact': {'wa_phone2': '07801234567'}});
    await open(t, canEdit: false);
    expect(find.text('07801234567'), findsOneWidget);
    expect(find.byIcon(LucideIcons.lock), findsOneWidget);
    await t.tap(find.text('تعديل'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await simDrain(t);
  });
}
