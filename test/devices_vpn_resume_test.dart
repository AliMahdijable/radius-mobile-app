// «وضع VPN» بقسم الأجهزة بعد العودة من الخلفيّة (المراجعة الثالثة لإصدار 180 — F21): فحصٌ شامل أمسك القسم (فانفصل عن «وضع VPN»)
// وانتهى والتطبيق بالخلفيّة ⇒ الإفلات هناك لا يعيد الاتّصال (التطبيق مختفٍ)، والعودة يجب أن تعيده — وإلّا تتخطّى نبضة «وضع VPN»
// قسم الأجهزة (فحص الطريق كلّ دقيقة وإظهار الشريط حين يسقط النفق) حتى يُبدَّل التبويب أو يجري فحصٌ آخر.
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/agent_alerts_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/screens/network_devices/network_devices_screen.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:rad_mysvcs/services/device_alerts_service.dart';
import 'package:rad_mysvcs/services/device_sweep_coordinator.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';

import 'sim_el/sim_harness.dart';
import 'support/ai_status_overlay.dart';
import 'visual_perm/visual_perm_harness.dart';

/// شاشة الأجهزة تطلب صلاحيّة الإشعارات المحلّيّة عند فتحها — لا منصّة هنا.
class _NoLocalNotifications extends FlutterLocalNotificationsPlatform {}

void main() {
  setUpAll(() async {
    await simSetUpAll();
    FlutterLocalNotificationsPlatform.instance = _NoLocalNotifications();
  });

  testWidgets('🚨 فحصٌ انتهى والتطبيق بالخلفيّة ⇒ العودة تعيد قسم الأجهزة إلى «وضع VPN»', (t) async {
    NetworkDevicesApi.debugService = (d) async => (status: 'online', responseMs: 3, packetLoss: 0.0);
    addTearDown(() => NetworkDevicesApi.debugService = null);
    NetworkDevicesScreen.debugResetView();
    AgentAlertsApi.forget();
    final inner = await visualSetUp(s1bSasOwner);
    ApiClient.dio.httpClientAdapter = AiStatusOverlay(inner, status: aiStatusOff, routes: {
      'GET /api/v2/admin/devices': {
        'success': true,
        'data': [
          {'id': 1, 'admin_id': 2, 'name': 'راوتر التوزيع', 'type': 'router', 'brand': 'mikrotik', 'ip': '10.0.0.1',
            'port': 8728, 'has_credentials': 1, 'last_status': 'online', 'created_at': '2026-11-01T10:00:00Z'},
        ],
      },
    });
    AiAssistantState.reset();
    await pumpSim(t, const SimVariant(390, dark: false),
        settle: false, home: (_) => NetworkDevicesScreen(isActive: ValueNotifier<bool>(true)));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    void life(List<AppLifecycleState> states) {
      for (final s in states) {
        t.binding.handleAppLifecycleStateChanged(s);
      }
    }

    expect(VpnNow.attached, contains(VpnNowKind.devices), reason: 'القسم ظاهر');
    DeviceSweep.acquire(); // فحصٌ شامل يجري فوق القسم ⇒ ينفصل
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(VpnNow.attached, isNot(contains(VpnNowKind.devices)));
    life(const [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
    await t.pump();
    DeviceSweep.release(); // انتهى والتطبيق بالخلفيّة
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(VpnNow.attached, isNot(contains(VpnNowKind.devices)), reason: 'بالخلفيّة لا يتّصل');
    life(const [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(VpnNow.attached, contains(VpnNowKind.devices), reason: 'العودة ⇒ القسم ظاهر ⇒ «وضع VPN» يحدّثه');

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 25));
    expect(VpnNow.attached, isNot(contains(VpnNowKind.devices)), reason: 'الإغلاق يفصله');
    await visualTearDown();
    AiAssistantState.reset();
    DeviceAlertsService.instance.unreadCount.value = 0;
    AgentAlertsApi.forget();
  });
}
