import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// «خريطة المشتركين» للمشروع الوطنيّ في التطبيق (٢ نوفمبر — نسخة الموقع `client-v2/src/lib/{watani-map,watani-geo}.ts`):
///   GET /api/v2/subscribers           — الزون والحالة لكلّ مشترك (قائمة الحساب نفسها، مكاشةٌ بالخادم)
///   GET /api/v2/ftth/fat-map           — FAT/FDT ومنفذ كلّ مشترك (كاشٌ يوميّ يُملأ بالخلفيّة: warming ⇒ يُسأل ثانيةً)
///   GET /api/v2/ftth/geo               — مواقع الزونات (مضلّعٌ/نقطة) والفاتات (نقطة) المستوردة من KML في الموقع
/// خلف مفتاح watani_map (والمواقع watani_geo) بالخادم — مطفأٌ ⇒ رسالته.

String _s(dynamic v) => v == null ? '' : v.toString().trim();
String? _sn(dynamic v) {
  final s = _s(v);
  return s.isEmpty ? null : s;
}

double? _d(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

class MapFatInfo {
  const MapFatInfo({this.fatId, this.fatName, this.fdtName, this.port});
  final String? fatId;
  final String? fatName;
  final String? fdtName;
  final int? port;

  static MapFatInfo from(Map m) {
    final f = m['fat'] is Map ? m['fat'] as Map : null;
    final d = m['fdt'] is Map ? m['fdt'] as Map : null;
    final p = m['port'];
    return MapFatInfo(
      fatId: _sn(f?['id']),
      fatName: _sn(f?['name']),
      fdtName: _sn(d?['name']),
      port: p is num ? p.toInt() : int.tryParse(p?.toString() ?? ''),
    );
  }
}

/// صفّ مشتركٍ بما تقرؤه الخريطة وحده (والصفّ الخامّ لفتح كرته).
class MapRow {
  const MapRow({required this.raw});
  final Map<String, dynamic> raw;

  String get key => _s(raw['idx']).isNotEmpty ? _s(raw['idx']) : _s(raw['username']);
  String get username => _s(raw['username']);
  String get name {
    final n = [_s(raw['firstname']), _s(raw['lastname'])].where((x) => x.isNotEmpty).join(' ').trim();
    return n.isEmpty ? username : n;
  }

  Map get _w => raw['watani'] is Map ? raw['watani'] as Map : const {};
  String get zoneName => _sn(_w['zone']) ?? _sn(raw['parent_username']) ?? 'بلا زون';
  String get zoneKey => _sn(_w['zoneId']) ?? zoneName;

  /// منتهٍ أوّلاً، ثمّ الموقوف (تعليق البوّابة أو المعطَّل)، وإلّا فعّال — كالموقع statusOf.
  String get status {
    final st = _s(_w['status']).toLowerCase();
    final rd = raw['remaining_days'];
    if (st == 'expired' || (rd is num && rd < 0)) return 'expired';
    final en = raw['enabled'];
    if (_w['suspended'] == true || en == false || en == 0) return 'suspended';
    return 'active';
  }

  bool get online {
    final o = raw['is_online'];
    if (o == true) return true;
    final n = o ?? raw['online_status'];
    return n is num ? n == 1 : n?.toString() == '1';
  }
}

class MapCounts {
  int total = 0;
  int active = 0;
  int suspended = 0;
  int expired = 0;
  int online = 0;

  void add(MapRow r) {
    total += 1;
    switch (r.status) {
      case 'expired':
        expired += 1;
      case 'suspended':
        suspended += 1;
      default:
        active += 1;
    }
    if (r.online) online += 1;
  }
}

/// fat = FAT معروف؛ nofat = لا عنوان/جهاز له في البوّابة؛ pending = لم يُجلب بعد.
enum MapFatKind { fat, nofat, pending }

class MapFat extends MapCounts {
  MapFat(this.key, this.name, this.kind, this.fdt);
  final String key;
  final String name;
  final MapFatKind kind;
  final String? fdt;
  final List<int> ports = [];
  final List<MapRow> rows = [];
}

class MapZone extends MapCounts {
  MapZone(this.key, this.name);
  final String key;
  final String name;
  final List<MapFat> fats = [];
  int pending = 0;
  int get fatCount => fats.where((f) => f.kind == MapFatKind.fat).length;
}

const String mapNoZone = 'بلا زون';
const String mapNoFat = 'بلا FAT';
const String mapPendingFat = 'لم يُعرف بعد';

int _byNameNum(String a, String b) {
  // ترتيبٌ طبيعيّ للأرقام داخل الأسماء (FAT2 قبل FAT10)
  final ra = RegExp(r'(\d+)|(\D+)');
  final pa = ra.allMatches(a).map((m) => m.group(0)!).toList();
  final pb = ra.allMatches(b).map((m) => m.group(0)!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = pa[i];
    final y = pb[i];
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final c = nx != null && ny != null ? nx.compareTo(ny) : x.toLowerCase().compareTo(y.toLowerCase());
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

/// الشجرة: الزونات (الأكثر مشتركين أوّلاً) ← فاتاتها (المعروفة بالأكثر، ثمّ «بلا FAT» ثمّ «لم يُعرف بعد») ← مشتركوها (بالمنفذ ثمّ
/// الاسم) — كالموقع buildMap.
({List<MapZone> zones, MapCounts totals, int fatCount}) buildNationalMap(List<MapRow> rows, Map<String, MapFatInfo>? items) {
  final zones = <String, MapZone>{};
  final fatsOf = <String, Map<String, MapFat>>{};
  final totals = MapCounts();
  int portOf(MapRow r) => items?[_s(r.raw['idx'])]?.port ?? 9999;
  for (final r in rows) {
    totals.add(r);
    final z = zones.putIfAbsent(r.zoneKey, () => MapZone(r.zoneKey, r.zoneName));
    z.add(r);
    final info = items?[_s(r.raw['idx'])];
    MapFatKind kind;
    String fkey;
    String fname;
    if (info == null) {
      kind = MapFatKind.pending;
      fkey = '~pending';
      fname = mapPendingFat;
      z.pending += 1;
    } else if (info.fatName == null) {
      kind = MapFatKind.nofat;
      fkey = '~nofat';
      fname = mapNoFat;
    } else {
      kind = MapFatKind.fat;
      fkey = info.fatId ?? info.fatName!;
      fname = info.fatName!;
    }
    final fm = fatsOf.putIfAbsent(z.key, () => {});
    final f = fm.putIfAbsent(fkey, () => MapFat(fkey, fname, kind, kind == MapFatKind.fat ? info?.fdtName : null));
    f.add(r);
    f.rows.add(r);
    final port = kind == MapFatKind.fat ? info?.port : null;
    if (port != null && !f.ports.contains(port)) f.ports.add(port);
  }
  const order = {MapFatKind.fat: 0, MapFatKind.nofat: 1, MapFatKind.pending: 2};
  final out = zones.values.toList();
  for (final z in out) {
    final fs = (fatsOf[z.key] ?? const {}).values.toList();
    for (final f in fs) {
      f.ports.sort();
      f.rows.sort((a, b) {
        final c = portOf(a).compareTo(portOf(b));
        return c != 0 ? c : _byNameNum(a.name, b.name);
      });
    }
    fs.sort((a, b) {
      final k = order[a.kind]!.compareTo(order[b.kind]!);
      if (k != 0) return k;
      final t = b.total.compareTo(a.total);
      return t != 0 ? t : _byNameNum(a.name, b.name);
    });
    z.fats.addAll(fs);
  }
  out.sort((a, b) {
    final n = (a.name == mapNoZone ? 1 : 0).compareTo(b.name == mapNoZone ? 1 : 0);
    if (n != 0) return n;
    final t = b.total.compareTo(a.total);
    return t != 0 ? t : _byNameNum(a.name, b.name);
  });
  return (zones: out, totals: totals, fatCount: out.fold(0, (s, z) => s + z.fatCount));
}

/* ───────────── المواقع (KML من الموقع) ───────────── */

class GeoPlace {
  const GeoPlace({required this.ref, this.name, this.lat, this.lng, this.polygon = const []});
  final String ref;
  final String? name;
  final double? lat;
  final double? lng;

  /// [[lat,lng]…] — للزون وحده.
  final List<List<double>> polygon;

  bool get hasPoint => lat != null && lng != null;

  static GeoPlace? from(dynamic v) {
    if (v is! Map) return null;
    final ref = _s(v['ref']);
    if (ref.isEmpty) return null;
    final p = v['point'] is Map ? v['point'] as Map : null;
    final poly = v['polygon'];
    return GeoPlace(
      ref: ref,
      name: _sn(v['name']),
      lat: _d(p?['lat']),
      lng: _d(p?['lng']),
      polygon: poly is List
          ? [
              for (final q in poly)
                if (q is List && q.length >= 2 && _d(q[0]) != null && _d(q[1]) != null) [_d(q[0])!, _d(q[1])!],
            ]
          : const [],
    );
  }
}

/// أوّل كودٍ بشكل حروفٍ + ٣–٦ أرقام ليس «FAT…»: FBG2251-2 ⇒ FBG2251 · FAT7-FBG2251 ⇒ FBG2251.
String? geoZoneCode(String? s) {
  for (final m in RegExp(r'([A-Za-z]{2,6})[-_ ]?(\d{3,6})').allMatches(s ?? '')) {
    if (m.group(1)!.toUpperCase() != 'FAT') return '${m.group(1)}${m.group(2)}'.toUpperCase();
  }
  return null;
}

/// رقم الفات: FAT7 · FAT-07 · fat 7 ⇒ 7.
int? geoFatNumber(String? s) {
  final m = RegExp(r'FAT[-_ ]?0*(\d{1,4})', caseSensitive: false).firstMatch(s ?? '');
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// مرجع الفات الموحّد «FAT7-FBG2251» من اسمه واسم الـFDT أو الزون (كالموقع fatGeoRef).
String? geoFatRef(String? fatName, String? zoneName) {
  final n = geoFatNumber(fatName);
  final z = geoZoneCode(fatName) ?? geoZoneCode(zoneName);
  return n != null && z != null ? 'FAT$n-$z' : null;
}

class NationalMapResult<T> {
  const NationalMapResult.ok(this.data)
      : error = null,
        off = false;
  const NationalMapResult.fail(this.error, {this.off = false}) : data = null;
  final T? data;
  final String? error;

  /// مفتاحه مطفأٌ لهذا الحساب (لا خطأ — رسالةٌ بمكانه).
  final bool off;
  bool get ok => error == null;
}

class NationalMapApi {
  NationalMapApi._();

  static Future<NationalMapResult<Map<String, dynamic>>> _get(String path, [Map<String, Object?> q = const {}]) async {
    try {
      final r = await ApiClient.dio.get<dynamic>(path, queryParameters: q, options: Options(receiveTimeout: const Duration(seconds: 60)));
      final b = r.data;
      if (b is! Map) return const NationalMapResult.fail('ردٌّ غير متوقّع من الخادم');
      if (b['success'] != true) {
        final code = _s(b['code']);
        final m = _s(b['message']);
        return NationalMapResult.fail(m.isNotEmpty && m.length < 220 ? m : 'تعذّر جلب الخريطة الآن', off: code.endsWith('_OFF') || code == 'BETA_OFF');
      }
      return NationalMapResult.ok(Map<String, dynamic>.from(b));
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 $path: $e');
      return const NationalMapResult.fail('تعذّر الاتّصال — أعد المحاولة');
    }
  }

  /// صفوف المشتركين (الخامّ).
  static Future<NationalMapResult<List<MapRow>>> rows() async {
    final r = await _get('/api/v2/subscribers');
    if (!r.ok) return NationalMapResult.fail(r.error, off: r.off);
    final d = r.data!['data'];
    return NationalMapResult.ok([
      if (d is List)
        for (final x in d)
          if (x is Map) MapRow(raw: Map<String, dynamic>.from(x)),
    ]);
  }

  /// FAT كلّ مشترك — data null حين warming ولم يُعرف شيء بعد (اسأل ثانيةً).
  static Future<NationalMapResult<({Map<String, MapFatInfo> items, bool warming, int known, int total})>> fatMap() async {
    final r = await _get('/api/v2/ftth/fat-map');
    if (!r.ok) return NationalMapResult.fail(r.error, off: r.off);
    final d = r.data!['data'] is Map ? r.data!['data'] as Map : const {};
    final items = <String, MapFatInfo>{};
    final it = d['items'];
    if (it is Map) {
      for (final e in it.entries) {
        if (e.value is Map) items[e.key.toString()] = MapFatInfo.from(e.value as Map);
      }
    }
    int n(dynamic v) => v is num ? v.toInt() : 0;
    return NationalMapResult.ok((items: items, warming: d['warming'] == true, known: n(d['known']), total: n(d['total'])));
  }

  /// مواقع الزونات والفاتات — null داخل ok حين لا مواقع بعد.
  static Future<NationalMapResult<({List<GeoPlace> zones, List<GeoPlace> fats})>> geo() async {
    final r = await _get('/api/v2/ftth/geo');
    if (!r.ok) return NationalMapResult.fail(r.error, off: r.off);
    final d = r.data!['data'] is Map ? r.data!['data'] as Map : const {};
    List<GeoPlace> list(dynamic v) => v is List ? v.map(GeoPlace.from).whereType<GeoPlace>().toList() : const [];
    return NationalMapResult.ok((zones: list(d['zones']), fats: list(d['fats'])));
  }
}
