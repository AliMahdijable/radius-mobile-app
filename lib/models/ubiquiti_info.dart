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
  final int? txRateKbps;        // 130000
  final int? rxRateKbps;        // 130000
  final String? lanSpeed;       // "100Mbps-Full"
  final bool lanUp;
  final String? peerMac;        // station mode: connected AP mac
  final int? peerCount;         // ap mode: number of connected stations
  final String baseUrl;         // the URL that actually worked

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
    required this.lanSpeed,
    required this.lanUp,
    required this.peerMac,
    required this.peerCount,
    required this.baseUrl,
  });

  // Signal health thresholds (dBm). More-negative = weaker.
  //   green : > -65
  //   yellow: -65 .. -75
  //   red   : < -75
  String get signalHealth {
    final s = signalDbm;
    if (s == null) return 'unknown';
    if (s > -65) return 'good';
    if (s > -75) return 'warn';
    return 'bad';
  }

  // CCQ thresholds (%).
  //   green : >= 80
  //   yellow: 50..79
  //   red   : < 50
  String get ccqHealth {
    final c = ccqPercent;
    if (c == null) return 'unknown';
    if (c >= 80) return 'good';
    if (c >= 50) return 'warn';
    return 'bad';
  }

  // SNR = signal - noise. Higher is better.
  int? get snrDb {
    final s = signalDbm; final n = noiseFloorDbm;
    if (s == null || n == null) return null;
    return s - n;
  }
}

class UbiquitiLoginResult {
  final String baseUrl;
  final String sessionCookie;
  final String? csrfToken;   // airOS 8.x only
  final String airosVariant; // 'v6' or 'v8'

  const UbiquitiLoginResult({
    required this.baseUrl,
    required this.sessionCookie,
    required this.airosVariant,
    this.csrfToken,
  });
}
