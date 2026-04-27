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
///   - notes    : free-form admin note (no fallback — purely informational)
class DeviceConfig {
  final DeviceKind? deviceType;
  final String? username;
  final String? password;
  final String? customIp;
  final String? notes;

  const DeviceConfig({
    this.deviceType,
    this.username,
    this.password,
    this.customIp,
    this.notes,
  });

  factory DeviceConfig.fromJson(Map<String, dynamic> j) => DeviceConfig(
        deviceType: deviceKindFromString(j['deviceType']?.toString()),
        username: j['username']?.toString(),
        password: j['password']?.toString(),
        customIp: j['customIp']?.toString(),
        notes: j['notes']?.toString(),
      );

  Map<String, dynamic> toPutJson() => {
        if (deviceType != null) 'deviceType': deviceKindToString(deviceType!),
        if (username != null) 'username': username,
        if (password != null) 'password': password,
        if (customIp != null) 'customIp': customIp,
        // Always send notes (even when null) so an admin clearing the
        // field can persist that — without this the upsert would keep
        // the previous value.
        'notes': notes,
      };

  DeviceConfig copyWith({
    DeviceKind? deviceType,
    String? username,
    String? password,
    String? customIp,
    String? notes,
    bool clearDeviceType = false,
    bool clearCustomIp = false,
    bool clearNotes = false,
  }) {
    return DeviceConfig(
      deviceType: clearDeviceType ? null : (deviceType ?? this.deviceType),
      username: username ?? this.username,
      password: password ?? this.password,
      customIp: clearCustomIp ? null : (customIp ?? this.customIp),
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }

  bool get isEmpty =>
      deviceType == null &&
      username == null &&
      password == null &&
      customIp == null &&
      (notes == null || notes!.isEmpty);

  /// Resolve the effective credentials. Three-tier fallback:
  ///   1. subscriber-specific override (username/password on this object)
  ///   2. admin-wide defaults (from AdminDeviceDefaults)
  ///   3. library hard-coded defaults (telecomadmin/admintelecom, ubnt/ubnt)
  ///
  /// `fallbackIp` is the SAS4 framedipaddress. Returns null kind for "unknown
  /// yet — caller should try ONT first, Ubiquiti second".
  ResolvedDevice resolve({
    required String? fallbackIp,
    String? adminOntUsername,
    String? adminOntPassword,
    String? adminUbntUsername,
    String? adminUbntPassword,
  }) {
    final kind = deviceType;
    String pick(String? override, String? adminDefault, String hardcoded) {
      if (override != null && override.isNotEmpty) return override;
      if (adminDefault != null && adminDefault.isNotEmpty) return adminDefault;
      return hardcoded;
    }

    String user;
    String pass;
    if (kind == DeviceKind.ubiquiti) {
      user = pick(username, adminUbntUsername, 'ubnt');
      pass = pick(password, adminUbntPassword, 'ubnt');
    } else {
      // Treat unknown the same as ONT for credential fallback — the caller
      // can still probe Ubiquiti separately if this fails.
      user = pick(username, adminOntUsername, 'telecomadmin');
      pass = pick(password, adminOntPassword, 'admintelecom');
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
