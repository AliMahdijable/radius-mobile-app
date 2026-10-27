import 'package:flutter/material.dart';

import '../../../api/network_devices_api.dart';
import '../../../models/network_device.dart';
import '../../../services/fiber/fiber_monitor.dart';
import '../../../services/fiber/fiber_store.dart';
import 'fiber_outage_screen.dart';

/// نقرة إشعار عطل الألياف (`type: fiber_outage`): «العطل الآن» لذلك الأولت — من القراءة الحيّة إن وصلنا الأولت، وإلّا
/// من سجلّ الخادم (هاتفٌ بعيدٌ عن الشبكة). `false` = ليس إشعار ألياف أو لم نجد أولته، فيكمل الموجِّه طريقه.
Future<bool> openFiberPush(NavigatorState nav, Map<String, String> data) async {
  if (data['type'] != 'fiber_outage') return false;
  final olt = int.tryParse(data['olt_id'] ?? '');
  final scope = data['scope_key']?.trim();
  if (olt == null || scope == null || scope.isEmpty) return false;
  await FiberStore.ensureLoaded(force: true);
  NetworkDevice? d = FiberMonitor.existing(olt)?.device;
  if (d == null) {
    try {
      d = (await NetworkDevicesApi.list()).where((x) => x.id == olt).firstOrNull;
    } catch (_) {}
  }
  if (d == null) return false;
  final device = d;
  await nav.push(MaterialPageRoute(builder: (_) => FiberOutageScreen(monitor: FiberMonitor.of(device), scopeKey: scope)));
  return true;
}
