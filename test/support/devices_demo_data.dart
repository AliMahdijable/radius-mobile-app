/// أجهزةٌ ومناطق تجريبيّة لصفحة «الأجهزة» (أعلى الصفحة: البحث والفلاتر والتوزيع) — بشكل ردّ الخادم حرفاً
/// (`GET /api/v2/admin/devices` و`/regions`). أسماءٌ كشبكة مزوّدٍ عراقيّ، لا بيانات حقيقيّة.
///
/// التوزيع (يُعتمد عليه في الاختبارات): ١٤ جهازاً — متّصل ١١ · مفصول ٢ · لم يُفحص ١؛ سكاتر ٥ · لنكات ٣ · سويتشات ٢ ·
/// راوترات ٢ · أخرى ٢؛ برج الشهداء ٤ · الحيدريّة ٣ · الكورنيش ٣ · المركز ٣ · بلا منطقة ١.
class DevicesDemoData {
  DevicesDemoData._();

  static const regions = <Map<String, Object?>>[
    {'id': 1, 'name': 'برج الشهداء', 'color': '#16A34A', 'sort_order': 1, 'device_count': 4},
    {'id': 2, 'name': 'الحيدريّة', 'color': '#2563EB', 'sort_order': 2, 'device_count': 3},
    {'id': 3, 'name': 'الكورنيش', 'color': '#EA580C', 'sort_order': 3, 'device_count': 3},
    {'id': 4, 'name': 'المركز', 'color': '#7C3AED', 'sort_order': 4, 'device_count': 3},
  ];

  static Map<String, Object?> _d(int id, String name, String type, String brand, String model, String ip,
      {int? region, String status = 'online', int? ms, String protocol = 'api', String? location, Duration? since}) {
    final now = DateTime.now().toUtc();
    return {
      'id': id,
      'admin_id': '12',
      'region_id': region,
      'name': name,
      'type': type,
      'brand': brand,
      'model': model,
      'ip': ip,
      'port': protocol == 'snmp' ? 161 : (protocol == 'ssh' ? 22 : 8728),
      'api_port': protocol == 'api' ? 8728 : null,
      'protocol': protocol,
      'location': location,
      // بلا بيانات دخول: لا تسخين ولا اتّصال بأجهزةٍ وهميّة في الاختبار.
      'has_credentials': 0,
      'last_status': status,
      'last_response_ms': status == 'online' ? ms : null,
      'status_since': now.subtract(since ?? const Duration(days: 3)).toIso8601String(),
      'last_probed_at': status == 'unknown' ? null : now.subtract(const Duration(minutes: 1)).toIso8601String(),
      'created_at': '2026-09-01T00:00:00Z',
    };
  }

  static List<Map<String, Object?>> devices() => [
        _d(1, 'سكتر برج الشهداء ١', 'sector', 'ubnt', 'Rocket Prism 5AC Gen2', '10.70.241.10', region: 1, ms: 9, location: 'سطح البرج'),
        _d(2, 'سكتر برج الشهداء ٢', 'sector', 'mikrotik', 'RB921GS-5HPacD-19S', '10.70.241.11', region: 1, ms: 12),
        _d(3, 'سكتر برج الزهراء ٢', 'sector', 'ubnt', 'LiteBeam 5AC Gen2', '10.70.242.12',
            region: 2, status: 'offline', since: const Duration(hours: 3, minutes: 10)),
        _d(4, 'لنك الحيدريّة ⇄ البرج الرئيسيّ', 'link', 'mimosa', 'B5c', '10.70.240.2', region: 2, ms: 11, protocol: 'snmp'),
        _d(5, 'لنك الكورنيش 60G', 'link', 'mikrotik', 'Cube 60Pro ac', '10.70.240.6', region: 3, ms: 7),
        _d(6, 'سويتش غرفة البرج', 'switch', 'mikrotik', 'netPower 16P', '10.70.241.2', region: 1, ms: 5, location: 'غرفة المعدّات'),
        _d(7, 'سويتش الطابق الثاني', 'switch', 'cisco', 'WS-C2960X-24TS-L', '10.70.241.3', region: 4, ms: 6, protocol: 'ssh'),
        _d(8, 'أولت المركز', 'other', 'bdcom', 'BDCOM P3600-04', '10.83.150.2', region: 4, ms: 18, protocol: 'snmp'),
        _d(9, 'راوتر المركز CCR', 'router', 'mikrotik', 'CCR1036-8G-2S+', '10.70.0.1', region: 4, ms: 4),
        _d(10, 'سكتر الكورنيش ٣', 'sector', 'mikrotik', 'RB921GS-5HPacD-19S', '10.70.243.4', region: 3, ms: 12),
        _d(11, 'لنك الشهداء ⇄ المركز', 'link', 'ubnt', 'AF-5XHD', '10.70.240.10', region: 1, ms: 6),
        _d(12, 'سكتر الحيدريّة ١', 'sector', 'ubnt', 'PS-5AC', '10.70.242.10', region: 2, ms: 15),
        _d(13, 'أولت الكورنيش', 'other', 'vsol', 'V1600D4', '10.70.250.2',
            region: 3, status: 'offline', protocol: 'snmp', since: const Duration(minutes: 25)),
        _d(14, 'راوتر الطوارئ', 'router', 'mikrotik', 'hEX S', '192.168.88.1', status: 'unknown'),
      ];

  /// مسارات [AiStatusOverlay] — «METHOD path» ← جسم الردّ.
  static Map<String, Object> routes() => {
        'GET /api/v2/admin/devices': {'success': true, 'data': devices()},
        'GET /api/v2/admin/devices/regions': {'success': true, 'data': regions},
      };
}
