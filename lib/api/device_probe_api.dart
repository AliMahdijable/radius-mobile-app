import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/net/huawei_ont_service.dart';
import '../core/net/ubiquiti_service.dart';
import '../models/device_health.dart';
import 'device_config_api.dart';

/// Device probe API — 3-tier credential fallback (per-sub → admin → library)
/// with a stack of caches:
///
///   [_snapCache]     IP → snapshot, 5-min TTL. الأساسي.
///   [_snapByUser]    username → snapshot (نفس entry، فهرس ثاني للـUI).
///   [_kindByIp]      IP → آخر kind ناجح (ONT/UBNT). يجعل الـprobe التالي
///                    يذهب مباشرة للنوع الصحيح بدلاً من parallel race.
///                    مطلب المستخدم 2026-07-12 (تسريع ~50%).
///   [_deadCache]     IP → آخر وقت فشل. IPs الميتة تُتَجاهل 2 دقيقة قبل
///                    إعادة المحاولة (مطلب 2026-07-12، توفير bandwidth
///                    على silent refresh).
///   [_persistPrefs]  SharedPreferences يحفظ _snapCache على القرص بين
///                    الجلسات (مطلب 2026-07-12، "instant load").
///
/// Waves تدعم priority queue: الـpriorityUsernames تُفحص أوّلاً، الباقي
/// يلحق. يُستعمل مع viewport-visible subs في list view.
class DeviceProbeApi {
  static final _snapCache = <String, _Cached>{};
  static final _snapByUser = <String, _Cached>{};
  static final _kindByIp = <String, DeviceKind>{};
  static final _deadCache = <String, DateTime>{};
  static Future<AdminDeviceDefaults>? _adminFetch;

  static const _ttl = Duration(minutes: 5);
  // يطابق v1: 15s cap على probe واحد.
  static const _probeCap = Duration(seconds: 15);
  // IPs الميتة نتجاهلها 2د قبل إعادة المحاولة (يُلغى بـforce أو نجاح جديد).
  static const _deadTtl = Duration(minutes: 2);

  static const _prefsKey = 'device_probe.cache.v1';
  static bool _hydrated = false;
  static Timer? _persistDebounce;

  // Library defaults — last-resort. Matches v1.
  static const _kOntUser = 'telecomadmin';
  static const _kOntPass = 'admintelecom';
  static const _kUbntUser = 'ubnt';
  static const _kUbntPass = 'ubnt';

  /// يُستدعى مرّة واحدة عند boot لاستعادة snapshots من الجلسة السابقة.
  /// آمن للاستدعاء المتكرّر (idempotent).
  static Future<void> hydrateFromPrefs() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final now = DateTime.now();
      for (final entry in data.entries) {
        final v = entry.value;
        if (v is! Map) continue;
        final at = DateTime.tryParse(v['at']?.toString() ?? '');
        if (at == null) continue;
        // نتجاهل entries أقدم من TTL — بيانات بائتة ما تفيد.
        if (now.difference(at) >= _ttl) continue;
        final snapJson = v['snap'];
        if (snapJson is! Map) continue;
        final snap = DeviceHealthSnapshot.fromJson(
            Map<String, dynamic>.from(snapJson));
        if (snap == null) continue;
        _snapCache[entry.key.toString()] = _Cached(snap, at);
        _kindByIp[entry.key.toString()] = snap.kind;
        // ملاحظة: _snapByUser لا يُستعاد لأن key الـpersist بـIP فقط.
        // الجلسة الجديدة رح تُعبّئ _snapByUser مع أوّل probe.
      }
    } catch (_) {
      // Corrupt data — امسحه بدل ما نبقى نفشل كل boot.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefsKey);
      } catch (_) {}
    }
  }

  /// مسح كل الـcaches عند logout. Admin جديد قد يكون له defaults مختلفة
  /// وما نريد نلصق snapshots على IPs قد تنتمي لشبكة admin سابق.
  static Future<void> clearAllCaches() async {
    _snapCache.clear();
    _snapByUser.clear();
    _kindByIp.clear();
    _deadCache.clear();
    _adminFetch = null;
    _persistDebounce?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  /// Resolves credentials + probes the device.
  ///
  /// * [fallbackIp] — SAS4 IP لو موجود.
  /// * [subscriberUsername] — يُستعمل لجلب DeviceConfig (customIp override).
  /// * [force=true] — يتخطّى snapshot + dead caches (زر تحديث يدوي).
  static Future<DeviceHealthSnapshot?> probe({
    required String fallbackIp,
    String? subscriberUsername,
    bool force = false,
  }) async {
    final ip = fallbackIp.trim();
    DeviceConfig? cfg;
    String effectiveIp = ip;

    if (subscriberUsername != null && subscriberUsername.isNotEmpty) {
      cfg = await DeviceConfigApi.fetchConfig(subscriberUsername);
      final custom = cfg?.customIp?.trim();
      if (custom != null && custom.isNotEmpty) effectiveIp = custom;
    }
    if (effectiveIp.isEmpty) return null;

    // Dead-IP short-circuit — إلا لو force. الـUI zاليدوي يتخطّى هذا.
    if (!force) {
      final deadAt = _deadCache[effectiveIp];
      if (deadAt != null &&
          DateTime.now().difference(deadAt) < _deadTtl) {
        return null;
      }
    }

    // Snapshot cache
    if (!force) {
      final cached = _snapCache[effectiveIp];
      if (cached != null && DateTime.now().difference(cached.at) < _ttl) {
        // كمان نُثبّت _snapByUser لو مو موجود (hydrate case).
        if (subscriberUsername != null && subscriberUsername.isNotEmpty) {
          _snapByUser[subscriberUsername] ??= cached;
        }
        return cached.snap;
      }
    }

    final defaults = await _loadAdminDefaults();
    final snap = await _runProbe(effectiveIp, cfg, defaults)
        .timeout(_probeCap, onTimeout: () => null);
    final now = DateTime.now();
    final entry = _Cached(snap, now);
    _snapCache[effectiveIp] = entry;
    if (subscriberUsername != null && subscriberUsername.isNotEmpty) {
      _snapByUser[subscriberUsername] = entry;
    }
    if (snap != null) {
      _kindByIp[effectiveIp] = snap.kind;
      _deadCache.remove(effectiveIp); // نجاح → ما هو ميت
    } else {
      // فشل — نضيف لـdead cache حتى نوفّر محاولات متكرّرة قريبة.
      _deadCache[effectiveIp] = now;
      // Kind cache قد يكون قديم ونحن جربنا الـkind المخزّن وفشل — نمسحه
      // حتى المحاولة القادمة تفجّر parallel وتلقّط لو الجهاز اتبدّل.
      _kindByIp.remove(effectiveIp);
    }
    _schedulePersist();
    return snap;
  }

  /// Drop one IP's cached snapshot — call after editing per-sub
  /// config so the next render re-probes with new credentials.
  static void invalidateIp(String ip) {
    final k = ip.trim();
    _snapCache.remove(k);
    _kindByIp.remove(k);
    _deadCache.remove(k);
    _schedulePersist();
  }

  /// Read-only peek بالـIP.
  static DeviceHealthSnapshot? cached(String ip) {
    final c = _snapCache[ip.trim()];
    if (c == null) return null;
    if (DateTime.now().difference(c.at) >= _ttl) return null;
    return c.snap;
  }

  /// Read-only peek بالـusername.
  static DeviceHealthSnapshot? cachedForUser(String username) {
    if (username.isEmpty) return null;
    final c = _snapByUser[username];
    if (c == null) return null;
    if (DateTime.now().difference(c.at) >= _ttl) return null;
    return c.snap;
  }

  /// Wave batched probe.
  ///
  /// * [priorityUsernames] — تُفحص أوّلاً. للـviewport-visible subs،
  ///   يمنح إحساس بأن الفحص "فوري" حتى مع قوائم كبيرة.
  /// * [concurrency=25] — عدد probes متزامنة.
  static Future<void> warmProbe(
    List<({String username, String ip})> targets, {
    Set<String>? priorityUsernames,
    int concurrency = 25,
    void Function(int done, int total)? onProgress,
    bool Function()? isCanceled,
  }) async {
    if (targets.isEmpty) {
      onProgress?.call(0, 0);
      return;
    }
    // Priority ordering — الـpriority أوّلاً، الباقي بعده.
    List<({String username, String ip})> ordered;
    if (priorityUsernames != null && priorityUsernames.isNotEmpty) {
      final priority = <({String username, String ip})>[];
      final rest = <({String username, String ip})>[];
      for (final t in targets) {
        if (priorityUsernames.contains(t.username)) {
          priority.add(t);
        } else {
          rest.add(t);
        }
      }
      ordered = [...priority, ...rest];
    } else {
      ordered = targets;
    }

    // Prime DeviceConfig cache بـbatch endpoint (لو الـbackend يدعمه).
    // يمنع 500 fetch منفصلة عند أوّل wave.
    try {
      final usernames = ordered.map((t) => t.username).toList();
      await DeviceConfigApi.warmBatch(usernames);
    } catch (_) {}

    var done = 0;
    for (var i = 0; i < ordered.length; i += concurrency) {
      if (isCanceled?.call() ?? false) return;
      final batch = ordered.skip(i).take(concurrency).toList();
      await Future.wait(batch.map((t) async {
        try {
          await probe(fallbackIp: t.ip, subscriberUsername: t.username);
        } catch (_) {}
      }));
      done += batch.length;
      onProgress?.call(done, ordered.length);
    }
  }

  static void invalidateAdminDefaults() {
    _adminFetch = null;
    _snapCache.clear();
    _snapByUser.clear();
    _kindByIp.clear();
    _deadCache.clear();
    _schedulePersist();
  }

  static Future<AdminDeviceDefaults> _loadAdminDefaults() {
    return _adminFetch ??= AdminDeviceDefaultsApi.fetch();
  }

  static Future<DeviceHealthSnapshot?> _runProbe(
    String ip,
    DeviceConfig? cfg,
    AdminDeviceDefaults defaults,
  ) async {
    if (ip.isEmpty) return null;

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

    // Admin pinned kind → probe واحد فقط.
    if (overridesOnt) return _probeOnt(ip, ontUser, ontPass);
    if (overridesUbnt) return _probeUbnt(ip, ubntUser, ubntPass);

    // Kind cache — لو نعرف من probe سابق إن IP هذا ONT (أو UBNT)،
    // نفجّر النوع الصحيح فقط. توفير ~5s متوسط. مطلب المستخدم 2026-07-12.
    // احتياط: لو الـkind المخزّن فشل، نمسحه (فوق) والمحاولة القادمة
    // ترجع parallel لتتلاقط تغيير الجهاز.
    final knownKind = _kindByIp[ip];
    if (knownKind == DeviceKind.ont) {
      return _probeOnt(ip, ontUser, ontPass);
    }
    if (knownKind == DeviceKind.ubiquiti) {
      return _probeUbnt(ip, ubntUser, ubntPass);
    }

    // First-time أو kind cache cleared — parallel race.
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

  /// Debounced persist — نكتب على القرص كل ~3s بدل بعد كل probe.
  /// يمنع I/O ثقيل أثناء waves كبيرة.
  static void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 3), _persist);
  }

  static Future<void> _persist() async {
    try {
      final now = DateTime.now();
      final map = <String, Map<String, dynamic>>{};
      for (final e in _snapCache.entries) {
        final snap = e.value.snap;
        if (snap == null) continue;
        if (now.difference(e.value.at) >= _ttl) continue;
        map[e.key] = {
          'at': e.value.at.toIso8601String(),
          'snap': snap.toJson(),
        };
      }
      final prefs = await SharedPreferences.getInstance();
      if (map.isEmpty) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, jsonEncode(map));
      }
    } catch (_) {
      // فشل الكتابة على القرص لا يجب أن يعطّل الـUI. تجاهل.
    }
  }
}

class _Cached {
  const _Cached(this.snap, this.at);
  final DeviceHealthSnapshot? snap;
  final DateTime at;
}
