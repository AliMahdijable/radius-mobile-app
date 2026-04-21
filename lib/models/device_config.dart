enum DeviceKind { ont, ubiquiti, other }

DeviceKind? deviceKindFromString(String? s) {
  switch (s?.toLowerCase()) {
    case 'ont': return DeviceKind.ont;
    case 'ubiquiti': return DeviceKind.ubiquiti;
    case 'other': return DeviceKind.other;
    default: return null;
  }
}

String deviceKindToString(DeviceKind k) {
  switch (k) {
    case DeviceKind.ont: return 'ont';
    case DeviceKind.ubiquiti: return 'ubiquiti';
    case DeviceKind.other: return 'other';
  }
}

/// Per-admin, per-subscriber device credentials. When a field is null the
/// caller falls back to a sensible default:
///   - type     : ONT if unknown (most common on fiber setups)
///   - username : telecomadmin (ONT) / ubnt (Ubiquiti)
///   - password : admintelecom  (ONT) / ubnt (Ubiquiti)
///   - customIp : framedipaddress from SAS4
class DeviceConfig {
  final DeviceKind? deviceType;
  final String? username;
  final String? password;
  final String? customIp;

  const DeviceConfig({
    this.deviceType,
    this.username,
    this.password,
    this.customIp,
  });

  factory DeviceConfig.fromJson(Map<String, dynamic> j) => DeviceConfig(
        deviceType: deviceKindFromString(j['deviceType']?.toString()),
        username: j['username']?.toString(),
        password: j['password']?.toString(),
        customIp: j['customIp']?.toString(),
      );

  Map<String, dynamic> toPutJson() => {
        if (deviceType != null) 'deviceType': deviceKindToString(deviceType!),
        if (username != null) 'username': username,
        if (password != null) 'password': password,
        if (customIp != null) 'customIp': customIp,
      };

  DeviceConfig copyWith({
    DeviceKind? deviceType,
    String? username,
    String? password,
    String? customIp,
    bool clearDeviceType = false,
    bool clearCustomIp = false,
  }) {
    return DeviceConfig(
      deviceType: clearDeviceType ? null : (deviceType ?? this.deviceType),
      username: username ?? this.username,
      password: password ?? this.password,
      customIp: clearCustomIp ? null : (customIp ?? this.customIp),
    );
  }

  bool get isEmpty =>
      deviceType == null && username == null && password == null && customIp == null;

  /// Resolve the effective credentials for the given subscriber fallback.
  /// `fallbackIp` is the SAS4 framedipaddress. Returns null kind for "unknown
  /// yet — caller should try ONT first, Ubiquiti second".
  ResolvedDevice resolve({required String? fallbackIp}) {
    final kind = deviceType;
    String user;
    String pass;
    if (kind == DeviceKind.ubiquiti) {
      user = username?.isNotEmpty == true ? username! : 'ubnt';
      pass = password?.isNotEmpty == true ? password! : 'ubnt';
    } else {
      // Treat unknown the same as ONT for credential fallback — the caller
      // can still probe Ubiquiti separately if this fails.
      user = username?.isNotEmpty == true ? username! : 'telecomadmin';
      pass = password?.isNotEmpty == true ? password! : 'admintelecom';
    }
    final ip = customIp?.isNotEmpty == true ? customIp! : (fallbackIp ?? '');
    return ResolvedDevice(kind: kind, ip: ip, username: user, password: pass);
  }
}

class ResolvedDevice {
  final DeviceKind? kind; // null = unknown → caller tries both
  final String ip;
  final String username;
  final String password;
  const ResolvedDevice({
    required this.kind,
    required this.ip,
    required this.username,
    required this.password,
  });
}
