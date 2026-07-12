import 'api_client.dart';
import '../models/device_health.dart';

/// Per-subscriber CPE credentials override. When non-null fields are
/// present, they take precedence over the admin-wide defaults during
/// the device probe credential chain.
class DeviceConfig {
  const DeviceConfig({
    this.deviceType,
    this.username,
    this.password,
    this.customIp,
    this.notes,
  });
  final DeviceKind? deviceType;
  final String? username;
  final String? password;
  final String? customIp;
  final String? notes;

  static DeviceConfig fromJson(Map<String, dynamic> j) => DeviceConfig(
        deviceType: deviceKindFromString(j['deviceType']?.toString()),
        username: _nullIfBlank(j['username']?.toString()),
        password: _nullIfBlank(j['password']?.toString()),
        customIp: _nullIfBlank(j['customIp']?.toString()),
        notes: _nullIfBlank(j['notes']?.toString()),
      );

  Map<String, dynamic> toPutJson() => {
        if (deviceType != null) 'deviceType': deviceKindToString(deviceType!),
        if (username != null) 'username': username,
        if (password != null) 'password': password,
        if (customIp != null) 'customIp': customIp,
        // Always send notes (even null) so clearing it persists.
        'notes': notes,
      };

  bool get isEmpty =>
      deviceType == null &&
      (username == null || username!.isEmpty) &&
      (password == null || password!.isEmpty) &&
      (customIp == null || customIp!.isEmpty) &&
      (notes == null || notes!.isEmpty);
}

/// Admin-wide defaults for the two protocols. Empty fields fall back
/// to the library hard-coded values (telecomadmin/admintelecom, ubnt/ubnt).
class AdminDeviceDefaults {
  const AdminDeviceDefaults({
    this.ontUsername,
    this.ontPassword,
    this.ubntUsername,
    this.ubntPassword,
  });
  final String? ontUsername;
  final String? ontPassword;
  final String? ubntUsername;
  final String? ubntPassword;

  static const empty = AdminDeviceDefaults();

  static AdminDeviceDefaults fromJson(Map<String, dynamic> j) =>
      AdminDeviceDefaults(
        ontUsername: _nullIfBlank(j['ontUsername']?.toString()),
        ontPassword: _nullIfBlank(j['ontPassword']?.toString()),
        ubntUsername: _nullIfBlank(j['ubntUsername']?.toString()),
        ubntPassword: _nullIfBlank(j['ubntPassword']?.toString()),
      );

  Map<String, dynamic> toJson() => {
        'ontUsername': ontUsername,
        'ontPassword': ontPassword,
        'ubntUsername': ubntUsername,
        'ubntPassword': ubntPassword,
      };
}

String? _nullIfBlank(String? s) {
  if (s == null) return null;
  final t = s.trim();
  return t.isEmpty ? null : t;
}

class DeviceConfigApi {
  // مطلب المستخدم 2026-07-12: كاش 5د لـfetchConfig. v1 يستعمل Riverpod
  // family provider اللي يكاش تلقائياً؛ v2 كان يعمل network call لكل
  // مشترك في كل wave (500 مشترك × poll 5s = 6000 request/min).
  // الآن كاش يُلغى عند saveConfig/resetConfig.
  static final _cache = <String, _CachedConfig>{};
  static const _cacheTtl = Duration(minutes: 5);

  /// GET /api/subscribers/:username/device — per-subscriber override.
  /// Returns an empty DeviceConfig when the subscriber has none pinned.
  /// Returns null on hard errors (network/auth) so the caller can
  /// degrade gracefully.
  ///
  /// يستفيد من كاش 5 دقائق للـwaves المتكرّرة (silent refresh).
  static Future<DeviceConfig?> fetchConfig(String username) async {
    final key = username.trim();
    if (key.isEmpty) return const DeviceConfig();
    final now = DateTime.now();
    final cached = _cache[key];
    if (cached != null && now.difference(cached.at) < _cacheTtl) {
      return cached.cfg;
    }
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/subscribers/$username/device',
      );
      final body = r.data ?? const {};
      DeviceConfig cfg = const DeviceConfig();
      if (body['success'] == true) {
        final dev = body['device'];
        if (dev is Map) {
          cfg = DeviceConfig.fromJson(Map<String, dynamic>.from(dev));
        }
      }
      _cache[key] = _CachedConfig(cfg, now);
      return cfg;
    } catch (_) {
      return const DeviceConfig();
    }
  }

  /// يُستدعى بعد saveConfig/resetConfig حتى الـprobe التالي يستعمل
  /// الاعتمادات الجديدة بدلاً من الكاش القديم.
  static void invalidateCache(String username) {
    _cache.remove(username.trim());
  }

  /// يُستدعى عند logout حتى admin جديد لا يقرأ رواسب config للأدمن السابق.
  static void clearAllCaches() {
    _cache.clear();
  }

  /// PUT /api/subscribers/:username/device — saves override.
  static Future<bool> saveConfig(String username, DeviceConfig cfg) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/subscribers/$username/device',
        data: cfg.toPutJson(),
      );
      final ok = r.data?['success'] == true;
      if (ok) invalidateCache(username);
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// DELETE /api/subscribers/:username/device — drops the override
  /// so the probe falls through to admin defaults + library defaults.
  static Future<bool> resetConfig(String username) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/subscribers/$username/device',
      );
      final ok = r.data?['success'] == true;
      if (ok) invalidateCache(username);
      return ok;
    } catch (_) {
      return false;
    }
  }
}

class _CachedConfig {
  const _CachedConfig(this.cfg, this.at);
  final DeviceConfig cfg;
  final DateTime at;
}

class AdminDeviceDefaultsApi {
  /// One fetch per session at most — but we don't cache here; the
  /// DeviceProbeApi memoizes the resolved credentials inline since it
  /// already runs serially per IP.
  static Future<AdminDeviceDefaults> fetch() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/admin/device-defaults',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return AdminDeviceDefaults.empty;
      final d = body['defaults'];
      if (d is! Map) return AdminDeviceDefaults.empty;
      return AdminDeviceDefaults.fromJson(Map<String, dynamic>.from(d));
    } catch (_) {
      return AdminDeviceDefaults.empty;
    }
  }

  /// PUT /api/admin/device-defaults — saves the 4 fields. Returns true
  /// on success so the caller can show a confirmation snackbar.
  static Future<bool> save(AdminDeviceDefaults d) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/admin/device-defaults',
        data: d.toJson(),
      );
      return r.data?['success'] == true;
    } catch (_) {
      return false;
    }
  }
}
