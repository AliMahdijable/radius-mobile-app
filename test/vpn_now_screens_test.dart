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
import 'package:rad_mysvcs/api/vpn_now_api.dart';
import 'package:rad_mysvcs/screens/network_devices/check/devices_check_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/network_devices_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_big_card.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/screens/whatsapp/conn_vpn_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/services/agent_net_presence.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:rad_mysvcs/services/device_alerts_service.dart';
import 'package:rad_mysvcs/services/devices_check.dart';
import 'package:rad_mysvcs/services/devices_check_runner.dart';
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

  testWidgets('«فحص شامل» (٦ نوفمبر): الرادار مكان «تحديث» بوجود أجهزة — على شبكتك يفحص منها، وبوضع VPN عبر الـVPN', (t) async {
    DevicesCheckRunner.debugLimits = () async => const CheckLimits();
    DevicesCheckRunner.debugSubscribers = () async => const [];
    DevicesCheckRunner.debugProbe = (d) async => (status: 'offline', responseMs: null, packetLoss: null, serviceOk: null);
    addTearDown(() {
      DevicesCheckRunner.debugLimits = null;
      DevicesCheckRunner.debugProbe = null;
      DevicesCheckRunner.debugSubscribers = null;
    });
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    AgentNetPresence.debugSet(NetPresence.on);
    await openDevices(t);
    final deep = find.byKey(const ValueKey('devices-deep-check'));
    expect(deep, findsOneWidget);
    expect(find.byTooltip('تحديث فوري'), findsNothing, reason: 'التحديث انتقل إلى «المزيد»');
    await t.tap(deep);
    await settleFor(t, seconds: 2);
    final screen = t.widget<DevicesCheckScreen>(find.byType(DevicesCheckScreen));
    expect(screen.viaVpn, isFalse);
    expect(screen.devices.length, 14);
    expect(find.text('فُحصت 14 أجهزة'), findsOneWidget);
    await close(t);
  });

  testWidgets('الأجهزة: على شبكتك ⇒ لا زرّ VPN (والأدوات كما كانت)', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    AgentNetPresence.debugSet(NetPresence.on);
    await openDevices(t);
    expect(devVpn, findsNothing);
    await close(t);
  });

  // ٦ نوفمبر (المالك: «ايرثلنك وكل الشركات البقية مجاي الكه بيها مكان اضيف ملف vpn» ثمّ «ابدي بي»): «ربط VPN» مدخلٌ ثابت في «المزيد»
  // بقسم الأجهزة — على شبكتك أو خارجها، مربوطاً أو لا؛ لصاحب الحساب حين يُفتح له، لا للموظّف.
  Future<void> openMore(WidgetTester t) async {
    await t.tap(find.byTooltip('المزيد'));
    await settleFor(t, seconds: 1);
  }

  final vpnItem = find.text('ربط VPN');

  testWidgets('«ربط VPN» في «المزيد»: يفتح صفحته وعلى شبكتك أيضاً، وبعد الرجوع يُسأل الطريق من جديد', (t) async {
    var asks = 0;
    VpnNow.routeSource = () async {
      asks++;
      return (linked: false, via: null);
    };
    AgentNetPresence.debugSet(NetPresence.on);
    await openDevices(t);
    await openMore(t);
    expect(vpnItem, findsOneWidget, reason: 'مكانٌ ثابت لا يحتاج «خارج شبكتك»');
    expect(find.byIcon(LucideIcons.shieldPlus), findsOneWidget, reason: 'غير مربوط ⇒ درعٌ بـ«+»');
    final before = asks;
    await t.tap(vpnItem);
    await settleFor(t, seconds: 1);
    expect(find.byType(ConnVpnScreen), findsOneWidget);
    Navigator.of(t.element(find.byType(ConnVpnScreen))).pop();
    await settleFor(t, seconds: 1);
    expect(find.byType(ConnVpnScreen), findsNothing);
    expect(asks, greaterThan(before), reason: 'ربطه هناك ⇒ زرّ «وضع VPN» يظهر بلا إعادة فتح القسم');
    await close(t);
  });

  testWidgets('«ربط VPN» مربوطاً: نفس المكان بدرع العلامة', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    AgentNetPresence.debugSet(NetPresence.on);
    await openDevices(t);
    await openMore(t);
    expect(vpnItem, findsOneWidget);
    expect(find.byIcon(LucideIcons.shieldCheck), findsOneWidget);
    await close(t);
  });

  testWidgets('لا «ربط VPN» في «المزيد»: الميزة غير مفتوحة لحسابه، أو موظّف (أسرار شبكة صاحب الحساب)', (t) async {
    VpnNow.routeSource = () async => null;
    AgentNetPresence.debugSet(NetPresence.on);
    await openDevices(t);
    await openMore(t);
    expect(vpnItem, findsNothing);
    expect(find.text('شبكة الألياف'), findsOneWidget, reason: 'القائمة نفسها مفتوحة');
    await close(t);

    VpnNow.routeSource = () async => (linked: true, via: 'company');
    await openDevices(t);
    PermissionsService.debugSet(isEmployee: true, permissions: const {'devices.monitor': true, 'devices.manage': true});
    addTearDown(() => PermissionsService.debugSet(isEmployee: false));
    await openMore(t);
    expect(vpnItem, findsNothing);
    await close(t);
  });

  testWidgets('٦ نوفمبر: الوطنيّ/فايبر اكس (الطريق subscribers=false) ⇒ لا زرّ VPN ولا هنت بالمشتركين — والأجهزة كما هي', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'own');
    VpnNowApi.lastSubscribers = false;
    AgentNetPresence.debugSet(NetPresence.off);
    await openSubscribers(t);
    expect(subsVpn, findsNothing);
    expect(find.text('تشغيل VPN'), findsNothing);
    expect(find.text('ربط VPN'), findsNothing);
    await close(t);
    VpnNowApi.lastSubscribers = false;
    addTearDown(() => VpnNowApi.lastSubscribers = true);
    await openDevices(t);
    expect(devVpn, findsOneWidget, reason: 'أجهزة الوكيل تُفحص عبر ملفّه');
    await close(t);
  });
}
