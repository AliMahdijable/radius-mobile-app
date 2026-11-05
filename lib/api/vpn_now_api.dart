import 'package:dio/dio.dart';

import '../core/util/error_text.dart';
import 'api_client.dart';

/// «فحص الآن» عبر VPN بطلب الوكيل (٥ نوفمبر — المالك: «يدوس فحص الان… البوابة تظل تفتر حتى يفحص المشتركين وكذلك الاجهزة»).
/// الخادم (server/connVpn): `POST /api/v2/conn-vpn/check-now {what}` ⇒ رقم الفحص، و`GET …/check-now/:id` ⇒ التقدّم ثمّ النتيجة،
/// و`GET /api/v2/conn-vpn/route` ⇒ هل للوكيل طريق VPN (ملفّه، نفق شركته، قالبها).
enum VpnNowKind { subscribers, devices }

extension VpnNowKindX on VpnNowKind {
  String get wire => this == VpnNowKind.devices ? 'devices' : 'subscribers';
}

/// قراءة مشتركٍ واحد عبر الـVPN — من جهازه (cpe)، أو سكتره، أو أولته، أو البنك وحده (ping)، أو لا يستجيب (dead).
class VpnSubReading {
  const VpnSubReading({required this.src, this.sig, this.ccq, this.lan, this.ms, this.rx, this.temp});
  final String src;
  final int? sig;
  final int? ccq;
  final String? lan;
  final int? ms;
  final double? rx;
  final double? temp;

  bool get dead => src == 'dead';

  static int? _i(Object? v) => v is num ? v.round() : int.tryParse('${v ?? ''}');
  static double? _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  static VpnSubReading? fromJson(Object? j) {
    if (j is! Map) return null;
    final src = '${j['src'] ?? ''}';
    if (src.isEmpty) return null;
    return VpnSubReading(
      src: src,
      sig: _i(j['sig']),
      ccq: _i(j['ccq']),
      lan: j['lan'] == null ? null : '${j['lan']}',
      ms: _i(j['ms']),
      rx: _d(j['rx']),
      temp: _d(j['t']),
    );
  }
}

/// جهازٌ من أجهزة شبكة الوكيل بعد «فحص الآن» عبر الـVPN.
class VpnDeviceResult {
  const VpnDeviceResult({required this.id, required this.alive, this.name, this.ms, this.stations, this.vitals});
  final int id;
  final String? name;
  final bool alive;
  final int? ms;
  final int? stations;

  /// «المعلومات الحيّة» كما قرأها الخادم عبر النفق (٥ نوفمبر): kind ros|airos|olt ومقاييسه — [DeviceVitals.fromVpn].
  final Map<String, dynamic>? vitals;

  static VpnDeviceResult? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'] is num ? (j['id'] as num).toInt() : int.tryParse('${j['id']}');
    if (id == null) return null;
    return VpnDeviceResult(
      id: id,
      name: j['name'] == null ? null : '${j['name']}',
      alive: j['alive'] == true,
      ms: j['ms'] is num ? (j['ms'] as num).round() : null,
      stations: j['stations'] is num ? (j['stations'] as num).toInt() : null,
      vitals: j['v'] is Map ? Map<String, dynamic>.from(j['v'] as Map) : null,
    );
  }
}

class VpnNowProgress {
  const VpnNowProgress({this.phase, this.done = 0, this.total = 0});
  final String? phase;
  final int done;
  final int total;
}

class VpnNowResult {
  const VpnNowResult({
    required this.ok,
    required this.message,
    this.detail,
    this.reason,
    this.readings = const {},
    this.devices = const [],
    this.atMs,
  });
  final bool ok;
  final String message;
  final String? detail;
  final String? reason;

  /// يوزر المشترك (بأحرفٍ صغيرة) ⇒ قراءته.
  final Map<String, VpnSubReading> readings;
  final List<VpnDeviceResult> devices;
  final int? atMs;

  static VpnNowResult fromJson(Object? j) {
    if (j is! Map) return const VpnNowResult(ok: false, message: 'تعذّر الفحص الآن — حاول بعد قليل');
    final rd = <String, VpnSubReading>{};
    final list = j['readings'];
    if (list is List) {
      for (final x in list) {
        if (x is! Map) continue;
        final u = '${x['u'] ?? ''}'.trim().toLowerCase();
        final r = VpnSubReading.fromJson(x);
        if (u.isNotEmpty && r != null) rd[u] = r;
      }
    }
    final devs = <VpnDeviceResult>[];
    if (j['devices'] is List) {
      for (final x in j['devices'] as List) {
        final r = VpnDeviceResult.fromJson(x);
        if (r != null) devs.add(r);
      }
    }
    final msg = '${j['message'] ?? ''}'.trim();
    final detail = '${j['detail'] ?? ''}'.trim();
    return VpnNowResult(
      ok: j['ok'] == true,
      message: msg.isEmpty ? 'تعذّر الفحص الآن — حاول بعد قليل' : msg,
      detail: detail.isEmpty ? null : detail,
      reason: j['reason'] == null ? null : '${j['reason']}',
      readings: rd,
      devices: devs,
      atMs: j['at_ms'] is num ? (j['at_ms'] as num).toInt() : null,
    );
  }
}

class VpnNowApi {
  VpnNowApi._();

  /// هل للوكيل طريق VPN؟ ⇒ (linked, via) — أو null حين الميزة مغلقة لحسابه/لا صلاحيّة/تعذّر (لا هنت).
  static Future<({bool linked, String? via})?> route() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/conn-vpn/route',
          options: Options(validateStatus: (s) => s != null && s < 500));
      if (r.statusCode != 200 || r.data?['success'] != true) return null;
      final d = r.data?['data'];
      if (d is! Map) return null;
      return (linked: d['linked'] == true, via: d['via'] == null ? null : '${d['via']}');
    } catch (_) {
      return null;
    }
  }

  /// يبدأ الفحص ⇒ (id) أو (error) برسالة الخادم.
  static Future<({String? id, String? error})> start(VpnNowKind kind) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/v2/conn-vpn/check-now',
          data: {'what': kind.wire}, options: Options(validateStatus: (s) => s != null && s < 500));
      final id = (r.data?['data'] as Map?)?['check_id']?.toString();
      if (r.statusCode == 200 && id != null && id.isNotEmpty) return (id: id, error: null);
      return (id: null, error: r.data?['message']?.toString() ?? 'تعذّر الفحص الآن — حاول بعد قليل');
    } catch (e) {
      return (id: null, error: humanError(e, fallback: 'تعذّر الفحص الآن — حاول بعد قليل'));
    }
  }

  /// حال الفحص: (running + التقدّم) أو (done + النتيجة)؛ null = تعذّر السؤال هذه المرّة.
  static Future<({bool done, VpnNowProgress? progress, VpnNowResult? result})?> poll(String id) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/conn-vpn/check-now/$id',
          options: Options(validateStatus: (s) => s != null && s < 500));
      final d = r.data?['data'];
      if (r.statusCode == 404) {
        return (done: true, progress: null, result: const VpnNowResult(ok: false, message: 'انتهت مدّة الفحص — أعد المحاولة'));
      }
      if (d is! Map) return null;
      if (d['state'] == 'done') return (done: true, progress: null, result: VpnNowResult.fromJson(d['result']));
      final p = d['progress'];
      return (
        done: false,
        progress: p is Map
            ? VpnNowProgress(
                phase: p['phase']?.toString(),
                done: p['done'] is num ? (p['done'] as num).toInt() : 0,
                total: p['total'] is num ? (p['total'] as num).toInt() : 0,
              )
            : null,
        result: null,
      );
    } catch (_) {
      return null;
    }
  }
}
