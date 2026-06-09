import 'dart:async';

import '../core/net/huawei_ont_service.dart';
import '../core/net/tcp_reachability.dart';
import '../core/net/ubiquiti_service.dart';
import '../models/device_health.dart';
import 'device_config_api.dart';

/// One probe per subscriber. v1's three-tier credential chain applies:
///   1. per-subscriber override (DeviceConfig)
///   2. admin-wide defaults (AdminDeviceDefaults)
///   3. library hardcoded (telecomadmin/admintelecom, ubnt/ubnt)
///
/// Two caches:
///   _snapCache  — IP → DeviceHealthSnapshot, 5-min TTL. The probe wave
///                 on the list view shares this with the detail screen
///                 so a card you scroll past doesn't re-hit the router.
///   _adminDefaults — one fetch per session, used by every probe.
class DeviceProbeApi {
  static final _snapCache = <String, _Cached>{};
  static Future<AdminDeviceDefaults>? _adminFetch;
  static const _ttl = Duration(minutes: 5);
  static const _probeCap = Duration(seconds: 6);

  // Library defaults — last-resort. Matches v1.
  static const _kOntUser = 'telecomadmin';
  static const _kOntPass = 'admintelecom';
  static const _kUbntUser = 'ubnt';
  static const _kUbntPass = 'ubnt';

  /// Resolves credentials + probes the device. `subscriberUsername`
  /// is OPTIONAL — pass it to consult the per-subscriber override
  /// (worth ~50ms extra on first read, cached after). Pass null for
  /// list-view probes that want minimal latency.
  ///
  /// `fallbackIp` is the IP from SAS4 (sub.ipAddress); used when the
  /// per-subscriber config doesn't pin a customIp.
  ///
  /// `force=true` bypasses the snapshot cache (manual refresh button).
  static Future<DeviceHealthSnapshot?> probe({
    required String fallbackIp,
    String? subscriberUsername,
    bool force = false,
  }) async {
    final ip = fallbackIp.trim();
    // We may overwrite `ip` with customIp from the per-sub config
    // after we've fetched it. Cache key keys off the FINAL ip used.
    DeviceConfig? cfg;
    String effectiveIp = ip;

    if (subscriberUsername != null) {
      cfg = await DeviceConfigApi.fetchConfig(subscriberUsername);
      final custom = cfg?.customIp?.trim();
      if (custom != null && custom.isNotEmpty) effectiveIp = custom;
    }
    if (effectiveIp.isEmpty) return null;

    if (!force) {
      final cached = _snapCache[effectiveIp];
      if (cached != null && DateTime.now().difference(cached.at) < _ttl) {
        return cached.snap;
      }
    }

    final defaults = await _loadAdminDefaults();
    final snap = await _runProbe(effectiveIp, cfg, defaults)
        .timeout(_probeCap, onTimeout: () => null);
    _snapCache[effectiveIp] = _Cached(snap, DateTime.now());
    return snap;
  }

  /// Drop one IP's cached snapshot — call after editing per-sub
  /// config so the next render re-probes with new credentials.
  static void invalidateIp(String ip) => _snapCache.remove(ip.trim());

  /// Read-only peek into the cache. Used by list-view chips so they
  /// can light up the moment a wave finishes without re-fetching.
  /// Returns null if no entry OR the entry expired.
  static DeviceHealthSnapshot? cached(String ip) {
    final c = _snapCache[ip.trim()];
    if (c == null) return null;
    if (DateTime.now().difference(c.at) >= _ttl) return null;
    return c.snap;
  }

  /// Batched probe wave for the visible subscriber list. v1 fans out 25
  /// at a time so dead IPs (capped at 1.2s reachability + 6s probe cap)
  /// don't stall the queue. Each individual sub goes through the same
  /// `probe()` flow so the 5-min snapshot cache stays warm afterward.
  ///
  /// `onProgress(done, total)` fires after each batch so the screen can
  /// surface "يفحص N/M" while running. Pass null to skip.
  ///
  /// `runId` lets the caller invalidate an in-flight wave when the list
  /// changes — pass a fresh int per call, then check it equals the
  /// caller's stored id before consuming results.
  static Future<void> warmProbe(
    List<({String username, String ip})> targets, {
    int concurrency = 25,
    void Function(int done, int total)? onProgress,
    bool Function()? isCanceled,
  }) async {
    if (targets.isEmpty) {
      onProgress?.call(0, 0);
      return;
    }
    var done = 0;
    for (var i = 0; i < targets.length; i += concurrency) {
      if (isCanceled?.call() ?? false) return;
      final batch = targets.skip(i).take(concurrency).toList();
      await Future.wait(batch.map((t) async {
        try {
          await probe(fallbackIp: t.ip, subscriberUsername: t.username);
        } catch (_) {}
      }));
      done += batch.length;
      onProgress?.call(done, targets.length);
    }
  }

  /// Drop the admin-defaults cache — call after saving them so the
  /// next probe picks up the new values.
  static void invalidateAdminDefaults() {
    _adminFetch = null;
    // Cached snapshots used the old defaults; invalidate them too so
    // the next probe re-runs against the fresh creds.
    _snapCache.clear();
  }

  static Future<AdminDeviceDefaults> _loadAdminDefaults() {
    return _adminFetch ??= AdminDeviceDefaultsApi.fetch();
  }

  static Future<DeviceHealthSnapshot?> _runProbe(
    String ip,
    DeviceConfig? cfg,
    AdminDeviceDefaults defaults,
  ) async {
    final reachable = await TcpReachability.isReachable(ip);
    if (!reachable) return null;

    // Per-tier creds. Subscriber override applies ONLY when the
    // admin pinned that exact kind on this subscriber — otherwise we
    // treat username/password as auxiliary, matching v1.
    final overridesOnt = cfg?.deviceType == DeviceKind.ont;
    final overridesUbnt = cfg?.deviceType == DeviceKind.ubiquiti;

    final ontUser = overridesOnt && (cfg?.username?.isNotEmpty ?? false)
        ? cfg!.username!
        : (defaults.ontUsername?.isNotEmpty == true
            ? defaults.ontUsername!
            : _kOntUser);
    final ontPass = overridesOnt && (cfg?.password?.isNotEmpty ?? false)
        ? cfg!.password!
        : (defaults.ontPassword?.isNotEmpty == true
            ? defaults.ontPassword!
            : _kOntPass);
    final ubntUser = overridesUbnt && (cfg?.username?.isNotEmpty ?? false)
        ? cfg!.username!
        : (defaults.ubntUsername?.isNotEmpty == true
            ? defaults.ubntUsername!
            : _kUbntUser);
    final ubntPass = overridesUbnt && (cfg?.password?.isNotEmpty ?? false)
        ? cfg!.password!
        : (defaults.ubntPassword?.isNotEmpty == true
            ? defaults.ubntPassword!
            : _kUbntPass);

    if (overridesOnt) return _probeOnt(ip, ontUser, ontPass);
    if (overridesUbnt) return _probeUbnt(ip, ubntUser, ubntPass);

    final ont = _probeOnt(ip, ontUser, ontPass);
    final ubnt = _probeUbnt(ip, ubntUser, ubntPass);
    return _firstNonNull<DeviceHealthSnapshot>([ont, ubnt]);
  }

  static Future<DeviceHealthSnapshot?> _probeOnt(
      String ip, String user, String pass) async {
    final session = await HuaweiOntService.login(ip, user, pass);
    if (session == null) return null;
    final optical = await HuaweiOntService.fetchOptical(session);
    if (optical == null) return null;
    return DeviceHealthSnapshot(kind: DeviceKind.ont, ip: ip, ont: optical);
  }

  static Future<DeviceHealthSnapshot?> _probeUbnt(
      String ip, String user, String pass) async {
    final session = await UbiquitiService.login(ip, user, pass);
    if (session == null) return null;
    final status = await UbiquitiService.fetchStatus(session);
    if (status == null) return null;
    return DeviceHealthSnapshot(
        kind: DeviceKind.ubiquiti, ip: ip, ubnt: status);
  }

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
