import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/dio_client.dart';
import '../core/services/huawei_ont_service.dart';
import '../core/services/ubiquiti_service.dart';
import '../models/device_config.dart';
import '../models/ont_info.dart';
import '../models/ubiquiti_info.dart';

// ─── Config (server-side, per-admin) ────────────────────────────────────
//
// Family-provider keyed by subscriber username. Lives across rebuilds so
// the subscriber_details_screen can watch it without re-fetching on every
// frame.

final deviceConfigProvider =
    FutureProvider.family<DeviceConfig?, String>((ref, subscriberUsername) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.get('/api/subscribers/$subscriberUsername/device');
    final data = res.data;
    if (data is! Map || data['success'] != true) return null;
    final dev = data['device'];
    if (dev == null) return const DeviceConfig();
    return DeviceConfig.fromJson(Map<String, dynamic>.from(dev));
  } catch (_) {
    // Soft-fail: UI treats this as "no config yet" and uses defaults.
    return const DeviceConfig();
  }
});

Future<bool> saveDeviceConfig(
  WidgetRef ref,
  String subscriberUsername,
  DeviceConfig cfg,
) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.put(
      '/api/subscribers/$subscriberUsername/device',
      data: cfg.toPutJson(),
    );
    final ok = res.data is Map && res.data['success'] == true;
    if (ok) ref.invalidate(deviceConfigProvider(subscriberUsername));
    return ok;
  } on DioException {
    return false;
  }
}

Future<bool> resetDeviceConfig(WidgetRef ref, String subscriberUsername) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.delete('/api/subscribers/$subscriberUsername/device');
    final ok = res.data is Map && res.data['success'] == true;
    if (ok) ref.invalidate(deviceConfigProvider(subscriberUsername));
    return ok;
  } on DioException {
    return false;
  }
}

// ─── Status snapshot (card-friendly unified shape) ──────────────────────

class DeviceHealthSnapshot {
  final DeviceKind kind;
  final String? headlineLabel;   // "RX Power" | "الإشارة"
  final String? headlineValue;   // "-18.5 dBm"
  final String headlineHealth;   // 'good' / 'warn' / 'bad' / 'unknown'
  final String? secondaryLabel;  // "Temp" | "CCQ"
  final String? secondaryValue;  // "42°C" | "95%"
  final String secondaryHealth;
  final String? tertiaryLabel;   // "LAN" (Ubiquiti)
  final String? tertiaryValue;   // "100Mbps-Full"
  final String tertiaryHealth;
  final OntOpticalInfo? ont;     // for the detail screen
  final UbiquitiStatus? ubiquiti;

  const DeviceHealthSnapshot({
    required this.kind,
    required this.headlineLabel,
    required this.headlineValue,
    required this.headlineHealth,
    required this.secondaryLabel,
    required this.secondaryValue,
    required this.secondaryHealth,
    required this.tertiaryLabel,
    required this.tertiaryValue,
    required this.tertiaryHealth,
    required this.ont,
    required this.ubiquiti,
  });

  /// Overall health = worst of the three individual healths.
  String get overallHealth {
    const order = {'unknown': 0, 'good': 1, 'warn': 2, 'bad': 3};
    final v = [headlineHealth, secondaryHealth, tertiaryHealth]
        .map((h) => order[h] ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    return order.keys.firstWhere((k) => order[k] == v);
  }
}

String _ontRxHealth(String rx) {
  final v = double.tryParse(rx);
  if (v == null) return 'unknown';
  // Per user spec: better than -25 = green, -25..-30 = yellow, < -30 = red.
  if (v > -25) return 'good';
  if (v >= -30) return 'warn';
  return 'bad';
}

String _ontTempHealth(String temp) {
  final v = double.tryParse(temp);
  if (v == null) return 'unknown';
  if (v < 70) return 'good';
  if (v <= 85) return 'warn';
  return 'bad';
}

/// Device status: resolves credentials, probes the device, returns the
/// unified snapshot. Triggered lazily when the widget subscribes.
final deviceStatusProvider = FutureProvider.family
    .autoDispose<DeviceHealthSnapshot?, DeviceStatusArgs>((ref, args) async {
  // Keep the result warm for five minutes even if no widget watches.
  ref.cacheFor(const Duration(minutes: 5));

  final cfg = await ref.watch(deviceConfigProvider(args.subscriberUsername).future) ??
      const DeviceConfig();
  final resolved = cfg.resolve(fallbackIp: args.fallbackIp);
  final ip = resolved.ip;
  if (ip.isEmpty) return null;

  // Decide probe order. Explicit kind → probe only that one. Unknown kind →
  // ONT first (more common on fiber), then Ubiquiti.
  final order = <DeviceKind>[];
  if (resolved.kind == DeviceKind.ubiquiti) {
    order.add(DeviceKind.ubiquiti);
  } else if (resolved.kind == DeviceKind.ont) {
    order.add(DeviceKind.ont);
  } else {
    order..add(DeviceKind.ont)..add(DeviceKind.ubiquiti);
  }

  for (final kind in order) {
    if (kind == DeviceKind.ont) {
      final session = await HuaweiOntService.login(
          ip, resolved.username, resolved.password);
      if (session == null) continue;
      final optical = await HuaweiOntService.fetchOptical(session);
      if (optical == null) continue;
      return DeviceHealthSnapshot(
        kind: DeviceKind.ont,
        headlineLabel: 'RX Power',
        headlineValue: '${optical.rxPower} dBm',
        headlineHealth: _ontRxHealth(optical.rxPower),
        secondaryLabel: 'TX Power',
        secondaryValue: '${optical.txPower} dBm',
        secondaryHealth: optical.txOk ? 'good' : 'warn',
        tertiaryLabel: 'Temp',
        tertiaryValue: '${optical.temperature}°C',
        tertiaryHealth: _ontTempHealth(optical.temperature),
        ont: optical,
        ubiquiti: null,
      );
    }
    if (kind == DeviceKind.ubiquiti) {
      // Fallback credentials for Ubiquiti when the resolved set came from
      // ONT defaults (e.g. kind was unknown and we're now on the 2nd try).
      final user = resolved.kind == DeviceKind.ubiquiti ? resolved.username : 'ubnt';
      final pass = resolved.kind == DeviceKind.ubiquiti ? resolved.password : 'ubnt';
      final session = await UbiquitiService.login(ip, user, pass);
      if (session == null) continue;
      final status = await UbiquitiService.fetchStatus(session);
      if (status == null) continue;
      final lan = status.lanSpeed ?? '';
      final lanHealth = !status.lanUp
          ? 'bad'
          : lan.contains('1000')
              ? 'good'
              : lan.contains('100')
                  ? 'warn'
                  : 'bad';
      return DeviceHealthSnapshot(
        kind: DeviceKind.ubiquiti,
        headlineLabel: 'الإشارة',
        headlineValue: status.signalDbm != null ? '${status.signalDbm} dBm' : '—',
        headlineHealth: status.signalHealth,
        secondaryLabel: 'CCQ',
        secondaryValue: status.ccqPercent != null ? '${status.ccqPercent}%' : '—',
        secondaryHealth: status.ccqHealth,
        tertiaryLabel: 'LAN',
        tertiaryValue: lan.isEmpty ? '—' : lan,
        tertiaryHealth: lanHealth,
        ont: null,
        ubiquiti: status,
      );
    }
  }
  return null;
});

class DeviceStatusArgs {
  final String subscriberUsername;
  final String? fallbackIp; // SAS4 framedipaddress
  const DeviceStatusArgs({required this.subscriberUsername, this.fallbackIp});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceStatusArgs &&
          other.subscriberUsername == subscriberUsername &&
          other.fallbackIp == fallbackIp);

  @override
  int get hashCode => Object.hash(subscriberUsername, fallbackIp);
}

// Tiny extension so the cacheFor trick above reads naturally.
extension _AutoDisposeCacheExt on AutoDisposeRef {
  void cacheFor(Duration d) {
    final link = keepAlive();
    final timer = Future<void>.delayed(d);
    timer.then((_) => link.close());
  }
}
