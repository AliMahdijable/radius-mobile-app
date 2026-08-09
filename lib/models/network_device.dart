/// Network device inventory model — routers/switches/APs/links.
/// Slice 1: أساسي فقط (بدون credentials/regions/alerts). راجع
/// project_devices_monitoring_plan في memory للخطّة الكاملة.
class NetworkDevice {
  final int id;
  final String adminId;
  final int? regionId;
  final String name;
  final String type;   // router|switch|ap|link|camera|other
  final String brand;  // mikrotik|ubnt|mimosa|cisco|roji|other
  final String? model;
  final String ip;
  final int port;
  final int? apiPort;
  final String? mac;
  final String? location;
  final String? notes;
  final DateTime? lastProbedAt;
  final String lastStatus;   // online|offline|unknown
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
    this.mac,
    this.location,
    this.notes,
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
        mac: j['mac']?.toString(),
        location: j['location']?.toString(),
        notes: j['notes']?.toString(),
        lastProbedAt: j['last_probed_at'] != null
            ? DateTime.tryParse(j['last_probed_at'].toString())
            : null,
        lastStatus: (j['last_status'] ?? 'unknown').toString(),
        lastResponseMs: j['last_response_ms'] as int?,
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toWriteJson() => {
        'name': name,
        'type': type,
        'brand': brand,
        'model': model,
        'ip': ip,
        'port': port,
        'api_port': apiPort,
        'mac': mac,
        'location': location,
        'notes': notes,
      };
}

/// Localized display labels
class NetworkDeviceLabels {
  static const types = <String, String>{
    'router': 'راوتر',
    'switch': 'سويتش',
    'ap': 'نقطة وصول (AP)',
    'link': 'لنك (Link)',
    'camera': 'كاميرا',
    'other': 'آخر',
  };

  static const brands = <String, String>{
    'mikrotik': 'Mikrotik',
    'ubnt': 'Ubiquiti',
    'mimosa': 'Mimosa',
    'cisco': 'Cisco',
    'roji': 'Roji',
    'other': 'آخر',
  };

  static String typeLabel(String t) => types[t] ?? t;
  static String brandLabel(String b) => brands[b] ?? b;
}
