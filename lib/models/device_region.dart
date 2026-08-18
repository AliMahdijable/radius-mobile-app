import '../core/util/format.dart';

/// منطقة أجهزة (كرخ/رصافة/شرق/غرب…) — grouping للـfilter و bulk-scan.
/// راجع [[project_devices_monitoring_plan]] في memory.
class DeviceRegion {
  final int id;
  final String name;
  final String? color;    // #RRGGBB أو null
  final int sortOrder;
  final int deviceCount;  // من backend JOIN — 0 لو ما فيها أجهزة بعد
  final DateTime createdAt;

  const DeviceRegion({
    required this.id,
    required this.name,
    this.color,
    this.sortOrder = 0,
    this.deviceCount = 0,
    required this.createdAt,
  });

  factory DeviceRegion.fromJson(Map<String, dynamic> j) => DeviceRegion(
        id: j['id'] as int,
        // 2026-08-18: normalize digits (١٢ → 12) — Cairo يرندرها كـlr
        name: normalizeDigits((j['name'] ?? '').toString()) ?? '',
        color: j['color']?.toString(),
        sortOrder: (j['sort_order'] is int)
            ? j['sort_order'] as int
            : int.tryParse('${j['sort_order']}') ?? 0,
        deviceCount: (j['device_count'] is int)
            ? j['device_count'] as int
            : int.tryParse('${j['device_count']}') ?? 0,
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}
