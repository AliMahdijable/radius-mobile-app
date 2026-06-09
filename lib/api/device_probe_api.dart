import 'dart:async';

import '../core/net/huawei_ont_service.dart';
import '../core/net/tcp_reachability.dart';
import '../core/net/ubiquiti_service.dart';
import '../models/device_health.dart';

/// One probe per subscriber IP. Tries ONT and Ubiquiti in parallel
/// (when no kind hint is given), keeps the result warm for 5 minutes,
/// caps the total probe time at 6s so the UI never sits forever.
///
/// First iteration uses hard-coded credential defaults:
///   ONT       → telecomadmin / admintelecom
///   Ubiquiti  → ubnt / ubnt
/// A later pass will add admin-wide defaults + per-subscriber override
/// (see [[v2-dev-progress]]).
class DeviceProbeApi {
  static final _cache = <String, _Cached>{};
  static const _ttl = Duration(minutes: 5);
  static const _probeCap = Duration(seconds: 6);

  /// Returns a cached snapshot if fresh, otherwise fires a new probe.
  /// `force=true` ignores the cache (used by the manual refresh button).
  /// Returns null for unreachable / wrong-creds / non-router IPs.
  static Future<DeviceHealthSnapshot?> probe({
    required String ip,
    DeviceKind? kindHint,
    bool force = false,
  }) async {
    final clean = ip.trim();
    if (clean.isEmpty) return null;
    final now = DateTime.now();
    if (!force) {
      final cached = _cache[clean];
      if (cached != null && now.difference(cached.at) < _ttl) {
        return cached.snap;
      }
    }
    final snap = await _runProbe(clean, kindHint)
        .timeout(_probeCap, onTimeout: () => null);
    _cache[clean] = _Cached(snap, now);
    return snap;
  }

  /// Drops the cached snapshot for one IP — call when a manual gear
  /// edit changes credentials so the next render re-probes.
  static void invalidate(String ip) => _cache.remove(ip.trim());

  static Future<DeviceHealthSnapshot?> _runProbe(
      String ip, DeviceKind? hint) async {
    final reachable = await TcpReachability.isReachable(ip);
    if (!reachable) return null;

    if (hint == DeviceKind.ont) return _probeOnt(ip);
    if (hint == DeviceKind.ubiquiti) return _probeUbnt(ip);

    // Auto mode — race both, take first non-null. _firstNonNull cancels
    // the loser implicitly when the cap timeout fires.
    final ont = _probeOnt(ip);
    final ubnt = _probeUbnt(ip);
    return _firstNonNull<DeviceHealthSnapshot>([ont, ubnt]);
  }

  static Future<DeviceHealthSnapshot?> _probeOnt(String ip) async {
    final session = await HuaweiOntService.login(ip, 'telecomadmin', 'admintelecom');
    if (session == null) return null;
    final optical = await HuaweiOntService.fetchOptical(session);
    if (optical == null) return null;
    return DeviceHealthSnapshot(kind: DeviceKind.ont, ip: ip, ont: optical);
  }

  static Future<DeviceHealthSnapshot?> _probeUbnt(String ip) async {
    final session = await UbiquitiService.login(ip, 'ubnt', 'ubnt');
    if (session == null) return null;
    final status = await UbiquitiService.fetchStatus(session);
    if (status == null) return null;
    return DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: ip, ubnt: status);
  }

  /// Resolves to the first non-null result from a list of futures.
  /// Resolves null only if EVERY future resolves null.
  static Future<T?> _firstNonNull<T>(List<Future<T?>> futures) {
    final completer = Completer<T?>();
    var pending = futures.length;
    for (final f in futures) {
      f.then((v) {
        if (completer.isCompleted) return;
        if (v != null) {
          completer.complete(v);
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
}

class _Cached {
  const _Cached(this.snap, this.at);
  final DeviceHealthSnapshot? snap;
  final DateTime at;
}
