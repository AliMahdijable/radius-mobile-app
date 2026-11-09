// مراقبة أعطال الألياف بالحاسبة (FiberWatch) ملكٌ لغلافها — المراجعة الثانية للفحص الشامل (٩ نوفمبر): استبدال الغلاف
// (البصمة، تبديل الشركة أو المدير الفرعيّ أو صفحة الموظّف — pushAndRemoveUntil) يُنهي الغلاف القديم **بعد** أن يبدأ الجديد، فكان
// إيقاف القديم يُطفئ المراقبة بقيّة الجلسة: لا قراءة للأولت ولا إشعار عطلٍ لهاتف الوكيل حتى يُعاد تشغيل البرنامج. (كـ3e992035 لفحص
// أجهزة المشتركين، واختباره بنافذة هاتفٍ لا يركّب غلاف الحاسبة.)
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/olt_profile.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/models/fiber_network.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/desktop/desktop_shell.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';
import 'package:rad_mysvcs/services/fiber/fiber_monitor.dart';
import 'package:rad_mysvcs/services/fiber/fiber_store.dart';
import 'package:rad_mysvcs/services/fiber/fiber_watch.dart';

import 'visual_perm/visual_perm_harness.dart';

class _Silent extends FiberBackend {
  const _Silent();
  @override
  Future<String?> community(NetworkDevice d) async => null;
  @override
  Future<VsolOltStats> structure(NetworkDevice d, String community, OltProfile p, {Map<int, String>? knownNames}) async =>
      const VsolOltStats();
}

NetworkDevice _olt(int id) => NetworkDevice(
      id: id,
      adminId: '2',
      name: 'OLT $id',
      type: 'other',
      brand: 'bdcom',
      model: 'BDCOM P3600-04',
      ip: '10.0.0.$id',
      port: 161,
      apiPort: 161,
      protocol: 'snmp',
      hasCredentials: true,
      lastStatus: 'online',
      createdAt: DateTime.utc(2026),
    );

void main() {
  setUpAll(visualSetUpAll);

  testWidgets('الحاسبة: غلافٌ جديد فوق القديم (البصمة/تبديل الشركة) ⇒ مراقبة الأعطال باقية بعد إنهاء القديم', (t) async {
    AppPlatform.debugIsDesktop = true;
    await visualSetUp(s1bSasOwner);
    FiberStore.debugSet(FiberLayout.empty.withBox(const FiberBox(id: 1, oltId: 9, pon: 'EPON0/3', name: 'صندوق')));
    FiberWatch.devices = () async => [_olt(9)];
    FiberMonitor.backend = const _Silent();
    try {
      await pumpVisual(t, const VisualDevice('', Size(1440, 900), 1), home: (_) => const MainShell());
      await settle(t, seconds: 3);
      expect(find.byType(DesktopShell), findsOneWidget, reason: 'غلاف الحاسبة');
      expect(FiberWatch.held, {9}, reason: 'الأولت المرتَّب يُراقَب بالخلفيّة');

      // البصمة أو تبديل الشركة: MainShell جديد بـpushAndRemoveUntil — القديم يبقى مركّباً حتى ينتهي انتقال الجديد
      final nav = Navigator.of(t.element(find.byType(DesktopShell)), rootNavigator: true);
      unawaited(nav.pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const MainShell()), (_) => false));
      await settle(t, seconds: 3);
      expect(find.byType(DesktopShell), findsOneWidget, reason: 'الغلاف الجديد وحده بعد الانتقال');
      expect(FiberWatch.held, {9}, reason: 'إنهاء القديم بعد بدء الجديد لا يُطفئ المراقبة');
      expect(FiberMonitor.existing(9)?.background, isTrue);
    } finally {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
      FiberWatch.debugReset();
      FiberMonitor.debugReset();
      await visualTearDown();
      AppPlatform.debugIsDesktop = null;
    }
  });
}
