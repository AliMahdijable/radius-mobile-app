import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/dio_client.dart';
import '../core/services/huawei_ont_service.dart';
import '../core/services/ubiquiti_service.dart';
import '../models/admin_device_defaults.dart';
import '../models/device_config.dart';
import '../models/ont_info.dart';
import '../models/ubiquiti_info.dart';

// ─── Admin-wide defaults ────────────────────────────────────────────────
// One fetch per session — used as the 2nd fallback tier when a given
// subscriber has no override.

final adminDeviceDefaultsProvider =
    FutureProvider<AdminDeviceDefaults>((ref) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.get('/api/admin/device-defaults');
    final data = res.data;
    if (data is! Map || data['success'] != true) return AdminDeviceDefaults.empty();
    final d = data['defaults'];
    if (d is! Map) return AdminDeviceDefaults.empty();
    return AdminDeviceDefaults.fromJson(Map<String, dynamic>.from(d));
  } catch (_) {
    return AdminDeviceDefaults.empty();
  }
});

Future<bool> saveAdminDeviceDefaults(WidgetRef ref, AdminDeviceDefaults d) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.put('/api/admin/device-defaults', data: d.toJson());
    final ok = res.data is Map && res.data['success'] == true;
    if (ok) {
      // The defaults affect every subscriber's probe — dropping both the
      // defaults provider AND every cached status snapshot is the only
      // way to guarantee the next card render uses the new credentials.
      ref.invalidate(adminDeviceDefaultsProvider);
      ref.invalidate(deviceStatusProvider);
    }
    return ok;
  } on DioException {
    return false;
  }
}

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
    if (ok) {
      ref.invalidate(deviceConfigProvider(subscriberUsername));
      ref.invalidate(deviceStatusProvider);
    }
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
    if (ok) {
      ref.invalidate(deviceConfigProvider(subscriberUsername));
      ref.invalidate(deviceStatusProvider);
    }
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
/// Total probe time capped at 15s; anything slower is treated as "offline"
/// so the UI never sits on a spinner forever.
final deviceStatusProvider = FutureProvider.family
    .autoDispose<DeviceHealthSnapshot?, DeviceStatusArgs>((ref, args) async {
  // Keep the result warm for five minutes even if no widget watches.
  ref.cacheFor(const Duration(minutes: 5));
  try {
    return await _probeDevice(ref, args)
        .timeout(const Duration(seconds: 15), onTimeout: () => null);
  } catch (_) {
    return null;
  }
});

/// Probe the device at `ip` — when the subscriber hasn't pinned a kind,
/// fire ONT and Ubiquiti attempts **in parallel** and take the first one
/// that actually returns data. The previous sequential approach meant a
/// Ubiquiti-only IP still had to wait for the ONT login to time out
/// first, which routinely blew past the 15s UI cap.
///
/// Credentials follow a 3-tier fallback per type:
///   1. subscriber-specific override (only when cfg.deviceType matches)
///   2. admin-wide default (admin_device_defaults table)
///   3. library hard-coded default (telecomadmin/admintelecom, ubnt/ubnt)
Future<DeviceHealthSnapshot?> _probeDevice(Ref ref, DeviceStatusArgs args) async {
  final cfg = await ref.watch(deviceConfigProvider(args.subscriberUsername).future) ??
      const DeviceConfig();
  final adminDefaults = await ref.watch(adminDeviceDefaultsProvider.future);

  final ip = (cfg.customIp?.isNotEmpty == true ? cfg.customIp : args.fallbackIp) ?? '';
  if (ip.isEmpty) return null;

  // Per-type creds. Subscriber override applies ONLY when the admin
  // explicitly pinned that kind — otherwise we treat username/password
  // as auxiliary data that doesn't bias either probe.
  final subOverridesOnt = cfg.deviceType == DeviceKind.ont;
  final subOverridesUbnt = cfg.deviceType == DeviceKind.ubiquiti;

  final ontUser = subOverridesOnt && (cfg.username?.isNotEmpty ?? false)
      ? cfg.username!
      : (adminDefaults.ontUsername?.isNotEmpty == true
          ? adminDefaults.ontUsername!
          : 'telecomadmin');
  final ontPass = subOverridesOnt && (cfg.password?.isNotEmpty ?? false)
      ? cfg.password!
      : (adminDefaults.ontPassword?.isNotEmpty == true
          ? adminDefaults.ontPassword!
          : 'admintelecom');
  final ubntUser = subOverridesUbnt && (cfg.username?.isNotEmpty ?? false)
      ? cfg.username!
      : (adminDefaults.ubntUsername?.isNotEmpty == true
          ? adminDefaults.ubntUsername!
          : 'ubnt');
  final ubntPass = subOverridesUbnt && (cfg.password?.isNotEmpty ?? false)
      ? cfg.password!
      : (adminDefaults.ubntPassword?.isNotEmpty == true
          ? adminDefaults.ubntPassword!
          : 'ubnt');

  // If the admin pinned a kind on this subscriber, trust them — probe
  // only that one. Cheaper and avoids the cost of a doomed Ubiquiti
  // handshake when the admin already knows it's a fiber ONT.
  if (subOverridesOnt) return _probeOnt(ip, ontUser, ontPass);
  if (subOverridesUbnt) return _probeUbnt(ip, ubntUser, ubntPass);

  // Auto mode — fire both and take the first winner.
  final ont = _probeOnt(ip, ontUser, ontPass);
  final ubnt = _probeUbnt(ip, ubntUser, ubntPass);
  return _firstNonNull<DeviceHealthSnapshot>([ont, ubnt]);
}

Future<DeviceHealthSnapshot?> _probeOnt(String ip, String user, String pass) async {
  final session = await HuaweiOntService.login(ip, user, pass);
  if (session == null) return null;
  final optical = await HuaweiOntService.fetchOptical(session);
  if (optical == null) return null;
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

Future<DeviceHealthSnapshot?> _probeUbnt(String ip, String user, String pass) async {
  final session = await UbiquitiService.login(ip, user, pass);
  if (session == null) return null;
  final status = await UbiquitiService.fetchStatus(session);
  if (status == null) return null;
  return DeviceHealthSnapshot(
    kind: DeviceKind.ubiquiti,
    headlineLabel: 'الإشارة',
    headlineValue: status.signalDbm != null ? '${status.signalDbm} dBm' : '—',
    headlineHealth: status.signalHealth,
    secondaryLabel: 'CCQ',
    secondaryValue: status.ccqPercent != null ? '${status.ccqPercent}%' : '—',
    secondaryHealth: status.ccqHealth,
    tertiaryLabel: 'LAN',
    tertiaryValue: status.lanSpeedShort ?? '—',
    // Use the model's lanHealth getter (added on main alongside the
    // multi-port LAN parsing) so all call sites stay consistent.
    tertiaryHealth: status.lanHealth,
    ont: null,
    ubiquiti: status,
  );
}

/// Returns the first non-null result among [futures], or null if they all
/// resolve to null. Unlike Future.any, it doesn't reject on the first
/// error — both probes are expected to fail occasionally and we want the
/// other one to still have a chance.
Future<T?> _firstNonNull<T>(List<Future<T?>> futures) {
  final completer = Completer<T?>();
  var pending = futures.length;
  for (final f in futures) {
    f.then((value) {
      if (completer.isCompleted) return;
      if (value != null) {
        completer.complete(value);
      } else if (--pending == 0) {
        completer.complete(null);
      }
    }).catchError((_) {
      if (completer.isCompleted) return;
      if (--pending == 0) completer.complete(null);
    });
  }
  return completer.future;
}

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
