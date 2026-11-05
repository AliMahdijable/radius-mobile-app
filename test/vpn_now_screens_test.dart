// «فحص عبر VPN» بضغطة الوكيل في القسمين (٥ نوفمبر — المالك: «الطبيعي بدون vpn بس من ينقر عبر vpn بكل الواجهتين»):
// المشتركون: زرّ الرادار ⇒ «فحص من موبايلي» · «فحص عبر VPN» (خارج الشبكة يتقدّم الـVPN)، وبلا ربط ⇒ فحصٌ من الموبايل كما كان.
// الأجهزة: «المزيد» ⇒ «فحص عبر VPN» لمن له طريق VPN وحده. (كان زرّ الرادار بلا مفتاحه فلا تُفتح القائمة أبداً.)
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/agent_alerts_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/network_devices/network_devices_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/services/agent_net_presence.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';

import 'sim_el/sim_harness.dart';
import 'support/ai_status_overlay.dart';
import 'visual_perm/visual_perm_harness.dart';

class _NoLocalNotifications extends FlutterLocalNotificationsPlatform {}

void main() {
  setUpAll(() async {
    await simSetUpAll();
    FlutterLocalNotificationsPlatform.instance = _NoLocalNotifications();
  });
  tearDown(() {
    VpnNow.routeSource = () async => null;
    VpnNow.reset();
    AgentNetPresence.reset();
  });

  Future<void> settleFor(WidgetTester t, {int seconds = 2}) async {
    for (var i = 0; i < seconds * 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
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

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 25));
    await visualTearDown();
    AiAssistantState.reset();
    AgentAlertsApi.forget();
  }

  final radar = find.byIcon(Icons.radar_rounded);
  final viaVpn = find.text('فحص عبر VPN');
  final fromPhone = find.text('فحص من موبايلي');

  testWidgets('المشتركون — مربوط: الرادار يفتح «من موبايلي · عبر VPN»؛ خارج الشبكة يتقدّم الـVPN', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    VpnNow.reset();
    await openSubscribers(t);
    expect(radar, findsOneWidget);
    final radarRect = t.getRect(radar);

    await t.tap(radar);
    await t.pumpAndSettle();
    expect(fromPhone, findsOneWidget);
    expect(viaVpn, findsOneWidget);
    expect(t.getCenter(fromPhone).dy, lessThan(t.getCenter(viaVpn).dy), reason: 'على الشبكة: الموبايل أوّلاً');
    expect(t.getRect(viaVpn).top, greaterThan(radarRect.top), reason: 'القائمة تحت الزرّ');
    await t.tapAt(const Offset(10, 700));
    await t.pumpAndSettle();

    AgentNetPresence.debugSet(NetPresence.off);
    await t.pump();
    await t.tap(radar);
    await t.pumpAndSettle();
    expect(t.getCenter(viaVpn).dy, lessThan(t.getCenter(fromPhone).dy), reason: 'خارج الشبكة: الـVPN أوّلاً');
    await t.tapAt(const Offset(10, 700));
    await t.pumpAndSettle();
    await close(t);
  });

  testWidgets('المشتركون — بلا ربط VPN: الرادار يفحص من الموبايل مباشرةً (لا قائمة)', (t) async {
    VpnNow.routeSource = () async => (linked: false, via: null);
    VpnNow.reset();
    await openSubscribers(t);
    await t.tap(radar);
    await t.pump(const Duration(milliseconds: 300));
    expect(viaVpn, findsNothing);
    expect(fromPhone, findsNothing);
    await settleFor(t);
    await close(t);
  });

  Future<void> openDevices(WidgetTester t) async {
    NetworkDevicesScreen.debugResetView();
    AgentAlertsApi.forget();
    final inner = await visualSetUp(s1bSasOwner);
    ApiClient.dio.httpClientAdapter = AiStatusOverlay(inner, status: aiStatusOff);
    AiAssistantState.reset();
    await pumpSim(t, const SimVariant(390, dark: false),
        settle: false, home: (_) => NetworkDevicesScreen(isActive: ValueNotifier<bool>(true)));
    await settleFor(t);
  }

  final more = find.byIcon(LucideIcons.ellipsisVertical);

  testWidgets('الأجهزة: «المزيد» فيها «فحص عبر VPN» لمن له طريق VPN وحده', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'own');
    VpnNow.reset();
    await openDevices(t);
    await t.tap(more);
    await t.pumpAndSettle();
    expect(viaVpn, findsOneWidget);
    await t.tapAt(const Offset(10, 700));
    await t.pumpAndSettle();
    await close(t);

    VpnNow.routeSource = () async => (linked: false, via: null);
    VpnNow.reset();
    await openDevices(t);
    await t.tap(more);
    await t.pumpAndSettle();
    expect(viaVpn, findsNothing);
    expect(find.text('شبكة الألياف'), findsOneWidget, reason: 'بقيّة القائمة كما هي');
    await t.tapAt(const Offset(10, 700));
    await t.pumpAndSettle();
    await close(t);
  });
}
