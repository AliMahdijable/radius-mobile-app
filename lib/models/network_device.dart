/// Network device inventory — routers/switches/APs/links/sectors.
/// راجع project_devices_monitoring_plan في memory.
class NetworkDevice {
  final int id;
  final String adminId;
  final int? regionId;
  final String name;
  final String type;      // router|switch|ap|link|sector|camera|other
  final String brand;     // mikrotik|ubnt|mimosa|cisco|roji|other
  final String? model;
  final String ip;
  final int port;
  final int? apiPort;
  final String? protocol;  // api|ssh|telnet|snmp
  final String? mac;
  final String? location;
  final String? notes;
  final bool hasCredentials;
  final DateTime? lastProbedAt;
  final String lastStatus; // online|offline|unknown
  final int? lastResponseMs;
  final DateTime createdAt;

  const NetworkDevice({
    required this.id,
    required this.adminId,
    this.regionId,
    required this.name,
    required this.type,
    required this.brand,
    this.model,
    required this.ip,
    required this.port,
    this.apiPort,
    this.protocol,
    this.mac,
    this.location,
    this.notes,
    this.hasCredentials = false,
    this.lastProbedAt,
    required this.lastStatus,
    this.lastResponseMs,
    required this.createdAt,
  });

  factory NetworkDevice.fromJson(Map<String, dynamic> j) => NetworkDevice(
        id: j['id'] as int,
        adminId: (j['admin_id'] ?? '').toString(),
        regionId: j['region_id'] as int?,
        name: (j['name'] ?? '').toString(),
        type: (j['type'] ?? 'other').toString(),
        brand: (j['brand'] ?? 'other').toString(),
        model: j['model']?.toString(),
        ip: (j['ip'] ?? '').toString(),
        port: (j['port'] is int) ? j['port'] as int : int.tryParse('${j['port']}') ?? 80,
        apiPort: j['api_port'] as int?,
        protocol: j['protocol']?.toString(),
        mac: j['mac']?.toString(),
        location: j['location']?.toString(),
        notes: j['notes']?.toString(),
        hasCredentials: _parseHasCreds(j['has_credentials']),
        lastProbedAt: j['last_probed_at'] != null
            ? DateTime.tryParse(j['last_probed_at'].toString())
            : null,
        lastStatus: (j['last_status'] ?? 'unknown').toString(),
        lastResponseMs: j['last_response_ms'] as int?,
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// MySQL `(x IS NOT NULL)` قد يأتي كـint (0/1)، String ('0'/'1')، أو bool.
/// نغطّي كل الأشكال — الـfalse الافتراضي عند null أو غير معروف.
bool _parseHasCreds(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v > 0;
  final s = v.toString().toLowerCase();
  return s == '1' || s == 'true';
}

class NetworkDeviceLabels {
  /// ترتيب مقصود حسب أهميّة WISP (لنكات/سويتشات/سكاتر أوّلاً)
  /// 2026-08-12: أُزيلت 'ap' و 'camera' حسب طلب المستخدم — غير مستعملة.
  /// (الـENUM في DB ما يزال يقبلها للسجلات القديمة، لكن ما تظهر في UI)
  static const types = <String, String>{
    'link': 'لنكات',
    'switch': 'سويتشات',
    'sector': 'سكاتر',
    'router': 'راوترات',
    'other': 'أخرى',
  };

  static const brands = <String, String>{
    'mikrotik': 'Mikrotik',
    'ubnt': 'Ubiquiti',
    'mimosa': 'Mimosa',
    'cisco': 'Cisco',
    'roji': 'Roji',
    'other': 'آخر',
  };

  static const protocols = <String, String>{
    'api': 'API (HTTP)',
    'ssh': 'SSH',
    'telnet': 'Telnet',
    'snmp': 'SNMP',
  };

  /// Default ports حسب الـprotocol (عامّة، ما تعرف البراند).
  /// للـapi يفضّل استعمال portForBrandProtocol التي تعرف الفرق:
  /// - Mikrotik = 8728 (binary)
  /// - UBNT / Mimosa = 443 (HTTPS)
  static const protocolPorts = <String, int>{
    'api': 8728,       // Mikrotik default
    'ssh': 22,
    'telnet': 23,
    'snmp': 161,
  };

  /// المنفذ المناسب حسب الـbrand + protocol.
  /// Mikrotik API = 8728 binary. UBNT API = 22 SSH (mca-status، أوثق من HTTP).
  /// Mimosa: SSH مقفول في firmware → SNMP فقط (161). لو المستخدم اختار 'api'
  /// نعطي 443 (REST XML) لكن نُحذّر في UI أنه SNMP أفضل.
  static int portForBrandProtocol(String brand, String? protocol) {
    if (protocol == null) return 80;
    if (protocol == 'api') {
      return switch (brand) {
        'mikrotik' => 8728,
        'ubnt' => 22,       // SSH لأنه يعمل على كل airOS 5/6/7/8 بدون issues
        'mimosa' => 443,
        _ => 80,
      };
    }
    if (protocol == 'snmp') return 161;
    return protocolPorts[protocol] ?? 80;
  }

  static String typeLabel(String t) => types[t] ?? t;
  static String brandLabel(String b) => brands[b] ?? b;
  static String protocolLabel(String p) => protocols[p] ?? p;
}
