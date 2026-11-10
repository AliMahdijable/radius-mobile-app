import 'package:flutter/foundation.dart';

/// عرض البرج — شكل البرج ومكان كلّ جهاز عليه (المالك ٢٧ أكتوبر: «نرسم البرج… والشكل الرسمي يحدد ع نوع الجهاز»).
///
/// البرج = منطقةٌ من مناطق الأجهزة (`regionId`، و`0` لأجهزةٍ بلا منطقة). ما يُحفظ على خادمنا وصفُ مكانٍ فقط
/// (`/api/v2/admin/devices/towers`)؛ القراءات الحيّة يقرؤها الهاتف من الأجهزة نفسها كبقيّة قسم الأجهزة.

enum TowerType { lattice, pole, roof }

/// مستويات البرج من الأعلى للأسفل — `base` كابينة الأرض (الراوتر والسويج والأولت).
enum TowerLevel { top, upper, mid, lower, base }

/// شكل الجهاز بالرسم. `sw` = سويج (`switch` كلمةٌ محجوزة) ويُرسَل للخادم `switch`.
enum TowerShape { sector, dish, panel, omni, router, sw, olt, other }

extension TowerShapeWire on TowerShape {
  String get wire => this == TowerShape.sw ? 'switch' : name;

  static TowerShape? parse(Object? v) {
    if (v is! String) return null;
    if (v == 'switch') return TowerShape.sw;
    for (final s in TowerShape.values) {
      if (s.name == v && s != TowerShape.sw) return s;
    }
    return null;
  }
}

T? _enumByName<T extends Enum>(List<T> values, Object? v) {
  if (v is! String) return null;
  for (final e in values) {
    if (e.name == v) return e;
  }
  return null;
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num && v == v.roundToDouble()) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// شكل البرج نفسه: نوعه وارتفاعه وحلقات التثبيت.
@immutable
class TowerSettings {
  const TowerSettings({
    required this.regionId,
    this.type = TowerType.lattice,
    this.heightM = 30,
    this.rings = 4,
  });

  static const minHeight = 3;
  static const maxHeight = 120;
  static const minRings = 1;
  static const maxRings = 8;

  final int regionId;
  final TowerType type;
  final int heightM;
  final int rings;

  TowerSettings copyWith({TowerType? type, int? heightM, int? rings}) => TowerSettings(
        regionId: regionId,
        type: type ?? this.type,
        heightM: (heightM ?? this.heightM).clamp(minHeight, maxHeight),
        rings: (rings ?? this.rings).clamp(minRings, maxRings),
      );

  static TowerSettings? fromJson(Object? j) {
    if (j is! Map) return null;
    final region = _int(j['region_id']);
    if (region == null || region < 0) return null;
    return TowerSettings(
      regionId: region,
      type: _enumByName(TowerType.values, j['tower_type']) ?? TowerType.lattice,
      heightM: (_int(j['height_m']) ?? 30).clamp(minHeight, maxHeight),
      rings: (_int(j['rings']) ?? 4).clamp(minRings, maxRings),
    );
  }

  Map<String, dynamic> toJson() => {'tower_type': type.name, 'height_m': heightM, 'rings': rings};

  @override
  bool operator ==(Object other) =>
      other is TowerSettings &&
      other.regionId == regionId &&
      other.type == type &&
      other.heightM == heightM &&
      other.rings == rings;

  @override
  int get hashCode => Object.hash(regionId, type, heightM, rings);
}

/// مكان جهازٍ على البرج. `fixed` = ثبّته الوكيل (بالبوصلة أو بيده)؛ غيره تقريبيّ.
/// `shape == null` ⇒ الشكل من الموديل.
@immutable
class TowerPlacement {
  const TowerPlacement({
    required this.deviceId,
    this.level,
    this.azimuth,
    this.beamwidth,
    this.fixed = false,
    this.shape,
  });

  final int deviceId;
  final TowerLevel? level;
  final int? azimuth;
  final int? beamwidth;
  final bool fixed;
  final TowerShape? shape;

  TowerPlacement copyWith({
    TowerLevel? level,
    int? azimuth,
    int? beamwidth,
    bool? fixed,
    TowerShape? shape,
    bool clearShape = false,
    bool clearAzimuth = false,
  }) =>
      TowerPlacement(
        deviceId: deviceId,
        level: level ?? this.level,
        azimuth: clearAzimuth ? null : (azimuth == null ? this.azimuth : ((azimuth % 360) + 360) % 360),
        beamwidth: beamwidth ?? this.beamwidth,
        fixed: fixed ?? this.fixed,
        shape: clearShape ? null : (shape ?? this.shape),
      );

  static TowerPlacement? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = _int(j['device_id']);
    if (id == null || id <= 0) return null;
    final az = _int(j['azimuth']);
    final bw = _int(j['beamwidth']);
    return TowerPlacement(
      deviceId: id,
      level: _enumByName(TowerLevel.values, j['level']),
      azimuth: az == null ? null : ((az % 360) + 360) % 360,
      beamwidth: bw == null || bw < 1 || bw > 360 ? null : bw,
      fixed: j['fixed'] == true || j['fixed'] == 1,
      shape: TowerShapeWire.parse(j['shape']),
    );
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'level': level?.name,
        'azimuth': azimuth,
        'beamwidth': beamwidth,
        'fixed': fixed,
        'shape': shape?.wire,
      };

  @override
  bool operator ==(Object other) =>
      other is TowerPlacement &&
      other.deviceId == deviceId &&
      other.level == level &&
      other.azimuth == azimuth &&
      other.beamwidth == beamwidth &&
      other.fixed == fixed &&
      other.shape == shape;

  @override
  int get hashCode => Object.hash(deviceId, level, azimuth, beamwidth, fixed, shape);
}

/// لنكٌ بين برجين («الترابط» — المالك ١١ نوفمبر: «برج a منطي ٣ لنكات ماستر والابراج الفرعي سليف وياه»).
/// [aDeviceId] طرف البرج الرئيسيّ (الماستر — منه يخرج الترافيك) و[bDeviceId] طرف الفرعيّ (السليف). البرجان يُعرفان من
/// منطقة كلٍّ من الجهازين الآن، فنقل جهازٍ لبرجٍ آخر ينقل لنكه معه.
@immutable
class TowerLink {
  const TowerLink({required this.id, required this.aDeviceId, required this.bDeviceId, this.label});

  final int id;
  final int aDeviceId;
  final int bDeviceId;
  final String? label;

  static TowerLink? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = _int(j['id']);
    final a = _int(j['a_device_id']);
    final b = _int(j['b_device_id']);
    if (id == null || id <= 0 || a == null || a <= 0 || b == null || b <= 0 || a == b) return null;
    final label = j['label'];
    return TowerLink(id: id, aDeviceId: a, bDeviceId: b, label: label is String && label.trim().isNotEmpty ? label.trim() : null);
  }

  TowerLink flipped() => TowerLink(id: id, aDeviceId: bDeviceId, bDeviceId: aDeviceId, label: label);

  @override
  bool operator ==(Object other) =>
      other is TowerLink && other.id == id && other.aDeviceId == aDeviceId && other.bDeviceId == bDeviceId && other.label == label;

  @override
  int get hashCode => Object.hash(id, aDeviceId, bDeviceId, label);
}

/// ما رجع من الخادم: أبراج الحساب (بالمنطقة) ومواقع أجهزته (بالجهاز) واللنكات بين أبراجه.
@immutable
class TowerLayouts {
  const TowerLayouts({this.towers = const {}, this.placements = const {}, this.links = const [], this.linksReady = false});

  static const empty = TowerLayouts();

  final Map<int, TowerSettings> towers;
  final Map<int, TowerPlacement> placements;

  /// اللنكات بين الأبراج — فارغةٌ من خادمٍ أقدم.
  final List<TowerLink> links;

  /// الخادم يحفظ الترابط (الهجرة 086) — false: خادمٌ أقدم أو تعذّر، فيُعرض بلا ربط ولا تعديل.
  final bool linksReady;

  static TowerLayouts fromJson(Object? body) {
    if (body is! Map || body['success'] != true) return empty;
    final towers = <int, TowerSettings>{};
    for (final t in (body['towers'] is List ? body['towers'] as List : const [])) {
      final s = TowerSettings.fromJson(t);
      if (s != null) towers[s.regionId] = s;
    }
    final places = <int, TowerPlacement>{};
    for (final p in (body['placements'] is List ? body['placements'] as List : const [])) {
      final v = TowerPlacement.fromJson(p);
      if (v != null) places[v.deviceId] = v;
    }
    final links = <TowerLink>[];
    for (final l in (body['links'] is List ? body['links'] as List : const [])) {
      final v = TowerLink.fromJson(l);
      if (v != null) links.add(v);
    }
    return TowerLayouts(
      towers: Map.unmodifiable(towers),
      placements: Map.unmodifiable(places),
      links: List.unmodifiable(links),
      linksReady: body['links_ready'] == true,
    );
  }
}
