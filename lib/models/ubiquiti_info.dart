class LanPort {
  final String name;    // eth0 / eth1
  final String? speed;  // "100Mbps-Full" or null
  final bool plugged;

  const LanPort({required this.name, required this.speed, required this.plugged});

  String get displaySpeed {
    if (!plugged) return 'Unplugged';
    final s = speed;
    if (s == null || s == '0Mbps' || s.startsWith('0')) return 'Unplugged';
    if (s.contains('1000')) return '1 Gbps';
    final m = RegExp(r'(\d+)Mbps').firstMatch(s);
    if (m != null) return '${m.group(1)} Mbps';
    return s;
  }

  String get label => name.toUpperCase(); // ETH0 → show as LAN0
}

class UbiquitiStatus {
  final String hostname;
  final String firmware;
  final int? uptimeSeconds;
  final String ssid;
  final String mode;            // station / ap / ap-ptp / etc
  final int? signalDbm;         // -62
  final int? noiseFloorDbm;     // -96
  final int? ccqPercent;        // 0..100
  final int? distanceMeters;    // 2500
  final int? txRateKbps;
  final int? rxRateKbps;
  final List<LanPort> lanPorts; // all eth interfaces
  final String? peerMac;        // station mode: connected AP mac
  final int? peerCount;         // ap mode: number of connected stations
  final String baseUrl;

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

  // Primary LAN = first plugged port, or first port if all unplugged.
  LanPort? get primaryLan =>
      lanPorts.firstWhere((p) => p.plugged, orElse: () => lanPorts.isEmpty ? const LanPort(name: '', speed: null, plugged: false) : lanPorts.first);

  String? get lanSpeed => primaryLan?.speed;
  bool get lanUp => primaryLan?.plugged ?? false;

  String? get lanSpeedShort => primaryLan?.plugged == true ? primaryLan?.displaySpeed : null;

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
    if (c >= 80) return 'good';
    if (c >= 50) return 'warn';
    return 'bad';
  }

  String get lanHealth {
    if (!lanUp) return 'bad';
    final s = lanSpeed ?? '';
    if (s.contains('1000')) return 'good';
    if (s.contains('100')) return 'warn';
    return 'bad';
  }

  int? get snrDb {
    final s = signalDbm; final n = noiseFloorDbm;
    if (s == null || n == null) return null;
    return s - n;
  }
}

class UbiquitiLoginResult {
  final String baseUrl;
  final String sessionCookie;
  final String? csrfToken;
  final String airosVariant;

  const UbiquitiLoginResult({
    required this.baseUrl,
    required this.sessionCookie,
    required this.airosVariant,
    this.csrfToken,
  });
}
