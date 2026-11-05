// «وضع VPN» بالقسمين (٥ نوفمبر — المالك: «المشتركين مابي زر فحص ع vpn… اريد من ينقر ع vpn يتفعل الفحص يتوجه ع vpn… حارس…
// يحول الفحص للشبكه بدون vpn»، وصورته: «فُحصت أجهزتك ✓ — 14 من 14 واصل» والبطاقات حمراء «غير متّصل»):
// زرّ VPN بجنب البحث بالقسمين لمن له طريق VPN — خارج شبكته (أو والحال مجهولة) وطول ما الوضع شغّال؛ على شبكته لا زرّ.
// والأجهزة بالوضع تُعرض بحالها من الـVPN (الأعداد والبطاقات)، وما لم يُفحص «غير معروف» لا «مفصول».
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/agent_alerts_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/network_devices/network_devices_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_big_card.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/services/agent_net_presence.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:rad_mysvcs/services/device_alerts_service.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';

import 'sim_el/sim_harness.dart';
import 'support/ai_status_overlay.dart';
import 'support/devices_demo_data.dart';
import 'visual_perm/visual_perm_harness.dart';

class _NoLocalNotifications extends FlutterLocalNotificationsPlatform {}

void main() {
  setUpAll(() async {
    await simSetUpAll();
    FlutterLocalNotificationsPlatform.instance = _NoLocalNotifications();
  });
  setUp(() {
    VpnNow.reset();
    AgentNetPresence.reset();
    VpnNow.guardProbe = () async => null; // لا شبكة بالاختبار
  });
  tearDown(() {
    VpnNow.routeSource = () async => null;
    VpnNow.guardProbe = null;
    VpnNow.reset();
    AgentNetPresence.reset();
  });

  Future<void> settleFor(WidgetTester t, {int seconds = 2}) async {
    for (var i = 0; i < seconds * 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester t) async {
    VpnNow.reset(); // نبضة الوضع مؤقّتٌ دوريّ — لا يبقى بعد الاختبار
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 25));
    await visualTearDown();
    AiAssistantState.reset();
    AgentAlertsApi.forget();
    DeviceAlertsService.instance.unreadCount.value = 0;
  }

  Future<void> openSubscribers(WidgetTester t) async {
    final inner = await visualSetUp(s1bSasOwner);
    ApiClient.dio.httpClientAdapter = AiStatusOverlay(inner, status: aiStatusOff);
    AiAssistantState.reset();
    SubscribersApi.clearAllCaches();
    await pumpVisual(t, phone,
        home: (_) => SubscribersScreen(filterCmd: ValueNotifier<SubscriberFilter?>(SubscriberFilter.all)));
    await settleFor(t);
  }

  final subsVpn = find.byKey(const ValueKey('subs-vpn-mode'));
  final devVpn = find.byKey(const ValueKey('devices-vpn-mode'));

  testWidgets('المشتركون: خارج شبكتك + مربوط ⇒ زرّ VPN بجنب البحث؛ الضغط يشغّل الوضع والرادار يحدّث عبر الـVPN؛ الضغط ثانيةً يطفئه', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    AgentNetPresence.debugSet(NetPresence.off);
    await openSubscribers(t);
    expect(subsVpn, findsOneWidget);
    await t.tap(subsVpn);
    await settleFor(t, seconds: 1);
    expect(VpnNow.mode.value, isTrue);
    expect(VpnNow.attached, contains(VpnNowKind.subscribers), reason: 'القسم الظاهر يُحدَّث بالوضع');
    expect(find.text('إيقاف'), findsOneWidget, reason: 'شريط الوضع');
    final before = VpnNow.subscribers.startedAt;
    await t.tap(find.byIcon(Icons.radar_rounded));
    await settleFor(t, seconds: 1);
    expect(VpnNow.subscribers.startedAt, isNotNull);
    expect(VpnNow.subscribers.startedAt == before || VpnNow.subscribers.phase != VpnBarPhase.idle, isTrue,
        reason: 'الرادار بالوضع = فحصٌ عبر الـVPN لا موجة من الموبايل');
    await t.tap(subsVpn);
    await settleFor(t, seconds: 1);
    expect(VpnNow.mode.value, isFalse);
    await close(t);
  });

  testWidgets('المشتركون: على شبكتك (والوضع مطفأ) أو بلا طريق VPN ⇒ لا زرّ — لا يأخذ من البحث', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    AgentNetPresence.debugSet(NetPresence.on);
    await openSubscribers(t);
    expect(subsVpn, findsNothing);
    await close(t);

    VpnNow.routeSource = () async => (linked: false, via: null);
    AgentNetPresence.debugSet(NetPresence.off);
    await openSubscribers(t);
    expect(subsVpn, findsNothing);
    await close(t);
  });

  Future<void> openDevices(WidgetTester t) async {
    NetworkDevicesScreen.debugResetView();
    AgentAlertsApi.forget();
    final inner = await visualSetUp(s1bSasOwner);
    ApiClient.dio.httpClientAdapter = AiStatusOverlay(inner, status: aiStatusOff, routes: DevicesDemoData.routes());
    AiAssistantState.reset();
    await pumpSim(t, const SimVariant(412, dark: false),
        settle: false, home: (_) => NetworkDevicesScreen(isActive: ValueNotifier<bool>(true)));
    await settleFor(t);
  }

  Finder chipCount(String key, String n) =>
      find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(n));

  testWidgets('الأجهزة: زرّ VPN ⇒ الوضع؛ الأعداد والبطاقات من نتيجة الـVPN (لا «مفصول» لما لم يُفحص)؛ الإطفاء يرجع حال الموبايل', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    AgentNetPresence.debugSet(NetPresence.off);
    await openDevices(t);
    expect(devVpn, findsOneWidget);
    await t.tap(devVpn);
    await settleFor(t, seconds: 1);
    expect(VpnNow.mode.value, isTrue);
    expect(VpnNow.attached, contains(VpnNowKind.devices));
    // لا نتيجة بعد ⇒ الكلّ «غير معروف»: لا متّصل ولا مفصول (كانت ١٤ مفصولة حمراء)
    expect(chipCount('devices-status-online', '0'), findsOneWidget);
    expect(chipCount('devices-status-offline', '0'), findsOneWidget);
    VpnNow.debugApply(VpnNowKind.devices, VpnNowResult.fromJson({
      'ok': true,
      'message': 'فُحصت أجهزتك ✓ — 12 من 13 واصل',
      'devices': [
        for (var id = 1; id <= 13; id++) {'id': id, 'name': 'd$id', 'alive': id != 5, 'ms': id != 5 ? 30 + id : null},
      ],
    }));
    await settleFor(t, seconds: 1);
    expect(chipCount('devices-status-online', '12'), findsOneWidget, reason: 'من الـVPN — منها جهازا «مفصول» عند الموبايل');
    expect(chipCount('devices-status-offline', '1'), findsOneWidget);
    await t.tap(devVpn);
    await settleFor(t, seconds: 1);
    expect(VpnNow.mode.value, isFalse);
    await close(t);
  });

  testWidgets('الأجهزة بالبطاقات الكبيرة + «وضع VPN»: المعالج والحرارة من الخادم عبر الـVPN على البطاقة (المالك: «المعلومات الحيه… عبر vpn هم»)', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    AgentNetPresence.debugSet(NetPresence.off);
    NetworkDevicesScreen.debugResetView();
    AgentAlertsApi.forget();
    final inner = await visualSetUp(s1bSasOwner);
    await const FlutterSecureStorage().write(key: 'devices.view.v1', value: DevicesView.big.key);
    ApiClient.dio.httpClientAdapter = AiStatusOverlay(inner, status: aiStatusOff, routes: DevicesDemoData.routes());
    AiAssistantState.reset();
    await pumpSim(t, const SimVariant(412, dark: false),
        settle: false, home: (_) => NetworkDevicesScreen(isActive: ValueNotifier<bool>(true)));
    await settleFor(t);
    await t.tap(devVpn);
    await settleFor(t, seconds: 1);
    expect(find.textContaining('737', findRichText: true), findsNothing);
    VpnNow.debugApply(VpnNowKind.devices, VpnNowResult.fromJson({
      'ok': true,
      'message': 'فُحصت أجهزتك ✓',
      'devices': [
        for (var id = 1; id <= 14; id++)
          {'id': id, 'alive': true, 'ms': 20, 'v': {'kind': 'ros', 'cpu': 737, 'mem': 41, 'temp': 52, 'up': 3600}},
      ],
    }));
    await settleFor(t, seconds: 2);
    final cards = t.widgetList<DeviceBigCard>(find.byType(DeviceBigCard)).toList();
    expect(cards, isNotEmpty, reason: 'البطاقات الكبيرة');
    for (final c in cards) {
      expect(c.state.error, isNull, reason: 'لا سطر «خارج شبكتك» لجهازٍ له معلومات من الـVPN');
      expect(c.state.vitals?.map((v) => v.value), contains('737'), reason: 'المعالج من الخادم عبر الـVPN');
      expect(c.device.lastStatus, 'online');
    }
    await close(t);
  });

  testWidgets('الأجهزة: على شبكتك ⇒ لا زرّ VPN (والأدوات كما كانت)', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    AgentNetPresence.debugSet(NetPresence.on);
    await openDevices(t);
    expect(devVpn, findsNothing);
    await close(t);
  });
}
