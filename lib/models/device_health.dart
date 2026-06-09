/// Device kind a probe resolved against. Used by the snapshot below
/// so the card can render kind-specific metric rows.
enum DeviceKind { ont, ubiquiti, other }

DeviceKind? deviceKindFromString(String? s) {
  switch (s?.toLowerCase()) {
    case 'ont':
      return DeviceKind.ont;
    case 'ubiquiti':
      return DeviceKind.ubiquiti;
    case 'other':
      return DeviceKind.other;
    default:
      return null;
  }
}

String deviceKindToString(DeviceKind k) {
  switch (k) {
    case DeviceKind.ont:
      return 'ont';
    case DeviceKind.ubiquiti:
      return 'ubiquiti';
    case DeviceKind.other:
      return 'other';
  }
}

/// Optical metrics from a Huawei ONT — direct port of v1's OntOpticalInfo.
class OntOpticalInfo {
  const OntOpticalInfo({
    required this.txPower,
    required this.rxPower,
    required this.voltage,
    required this.temperature,
    required this.bias,
    required this.sendStatus,
  });
  final String txPower;
  final String rxPower;
  final String voltage;
  final String temperature;
  final String bias;
  final String sendStatus;

  bool get txOk {
    final v = double.tryParse(txPower);
    return v != null && v >= 0.5 && v <= 5.0;
  }

  bool get rxOk {
    final v = double.tryParse(rxPower);
    return v != null && v >= -27.0 && v <= -3.0;
  }

  bool get voltageOk {
    final v = double.tryParse(voltage);
    return v != null && v >= 3100 && v <= 3500;
  }

  bool get biasOk {
    final v = double.tryParse(bias);
    return v != null && v >= 0 && v <= 90;
  }

  bool get tempOk {
    final v = double.tryParse(temperature);
    return v != null && v >= -10 && v <= 85;
  }
}

class OntLoginResult {
  const OntLoginResult(
      {required this.sessionCookie, required this.baseUrl});
  final String sessionCookie;
  final String baseUrl;
}

/// Ubiquiti LAN port (one row per eth interface in the airOS json).
class LanPort {
  const LanPort(
      {required this.name, required this.speed, required this.plugged});
  final String name;
  final String? speed;
  final bool plugged;

  String get displaySpeed {
    if (!plugged) return 'Unplugged';
    final s = speed;
    if (s == null || s == '0Mbps' || s.startsWith('0')) return 'Unplugged';
    if (s.contains('1000')) return '1 Gbps';
    final m = RegExp(r'(\d+)Mbps').firstMatch(s);
    if (m != null) return '${m.group(1)} Mbps';
    return s;
  }

  String get label => name.toUpperCase();
}

/// Unified snapshot the UI consumes — same shape regardless of kind.
class UbiquitiStatus {
  const UbiquitiStatus({
    required this.hostname,
    required this.firmware,
    required this.uptimeSeconds,
    required this.ssid,
    required this.mode,
    required this.signalDbm,
    required this.noiseFloorDbm,
    required this.ccqPercent,
    required this.distanceMeters,
    required this.txRateKbps,
    required this.rxRateKbps,
    required this.lanPorts,
    required this.peerMac,
    required this.peerCount,
    required this.baseUrl,
  });
  final String hostname;
  final String firmware;
  final int? uptimeSeconds;
  final String ssid;
  final String mode;
  final int? signalDbm;
  final int? noiseFloorDbm;
  final int? ccqPercent;
  final int? distanceMeters;
  final int? txRateKbps;
  final int? rxRateKbps;
  final List<LanPort> lanPorts;
  final String? peerMac;
  final int? peerCount;
  final String baseUrl;

  LanPort? get primaryLan => lanPorts.firstWhere(
        (p) => p.plugged,
        orElse: () => lanPorts.isEmpty
            ? const LanPort(name: '', speed: null, plugged: false)
            : lanPorts.first,
      );

  bool get lanUp => primaryLan?.plugged ?? false;
  String? get lanSpeedShort =>
      primaryLan?.plugged == true ? primaryLan?.displaySpeed : null;

  String get signalHealth {
    final s = signalDbm;
    if (s == null) return 'unknown';
    if (s > -65) return 'good';
    if (s > -75) return 'warn';
    return 'bad';
  }

  String get ccqHealth {
    final c = ccqPercent;
    if (c == null) return 'unknown';
    return c >= 80 ? 'good' : 'bad';
  }

  String get lanHealth {
    if (!lanUp) return 'bad';
    final s = primaryLan?.speed ?? '';
    final m = RegExp(r'^(\d+)Mbps').firstMatch(s);
    final mbps = m == null ? null : int.tryParse(m.group(1)!);
    if (mbps == null) return 'bad';
    return mbps >= 100 ? 'good' : 'bad';
  }

  int? get snrDb {
    final s = signalDbm;
    final n = noiseFloorDbm;
    if (s == null || n == null) return null;
    return s - n;
  }
}

class UbiquitiLoginResult {
  const UbiquitiLoginResult({
    required this.baseUrl,
    required this.sessionCookie,
    required this.airosVariant,
    this.csrfToken,
  });
  final String baseUrl;
  final String sessionCookie;
  final String? csrfToken;
  final String airosVariant;
}

/// Final unified snapshot the subscriber detail card renders. One of
/// `ont` / `ubnt` is non-null depending on which probe won.
class DeviceHealthSnapshot {
  const DeviceHealthSnapshot({
    required this.kind,
    required this.ip,
    this.ont,
    this.ubnt,
  });
  final DeviceKind kind;
  final String ip;
  final OntOpticalInfo? ont;
  final UbiquitiStatus? ubnt;
}
