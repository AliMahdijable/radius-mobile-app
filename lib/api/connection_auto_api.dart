import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// «تنبيه المشترك» التلقائيّ (٣ نوفمبر — الخادم server/connAlertsAuto.js).
///
/// التطبيق يقيس أجهزة المشتركين (موجة فحص القائمة) ويرفع القراءات الخام ([uploadReadings])، والخادم وحده يقرّر بحدود الوكيل
/// ويؤكّد (قراءتان بينهما [ConnAutoSettings.confirmMin]) ويضع «بانتظار موافقتك» (الافتراضيّ) أو يرسل تلقائيّاً في ساعات الوكيل
/// وتحت سقفه، ويذكّر كلّ [ConnAutoSettings.remindDays] حتى [ConnAutoSettings.maxSends]. خلف مفتاحٍ بالخادم: حسابٌ لم يُفتح له ⇒
/// [ConnAutoStatus.available] false ولا يظهر شيء.
class ConnAutoSettings {
  const ConnAutoSettings({
    this.mode = 'approval',
    this.remindDays = 3,
    this.maxSends = 3,
    this.dailyCap = 30,
    this.hourFrom = 10,
    this.hourTo = 20,
    this.confirmMin = 30,
    this.kinds = kAllKinds,
  });

  static const kAllKinds = <String>['cable', 'signal', 'ccq', 'fiber_rx', 'fiber_temp'];

  /// manual (يدويّ: لا شيء تلقائيّ) · approval (بموافقتي) · auto (تلقائيّ)
  final String mode;
  final int remindDays;
  final int maxSends;
  final int dailyCap;
  final int hourFrom;
  final int hourTo;
  final int confirmMin;
  final List<String> kinds;

  factory ConnAutoSettings.fromJson(Map<String, dynamic> j) {
    int i(String k, int d) => (j[k] is num) ? (j[k] as num).toInt() : int.tryParse('${j[k]}') ?? d;
    return ConnAutoSettings(
      mode: const ['manual', 'approval', 'auto'].contains(j['mode']) ? j['mode'] as String : 'approval',
      remindDays: i('remind_days', 3),
      maxSends: i('max_sends', 3),
      dailyCap: i('daily_cap', 30),
      hourFrom: i('hour_from', 10),
      hourTo: i('hour_to', 20),
      confirmMin: i('confirm_min', 30),
      kinds: j['kinds'] is List ? (j['kinds'] as List).map((e) => '$e').where(kAllKinds.contains).toList() : kAllKinds,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'remind_days': remindDays,
        'max_sends': maxSends,
        'daily_cap': dailyCap,
        'hour_from': hourFrom,
        'hour_to': hourTo,
        'confirm_min': confirmMin,
        'kinds': kinds,
      };

  ConnAutoSettings copyWith({
    String? mode,
    int? remindDays,
    int? maxSends,
    int? dailyCap,
    int? hourFrom,
    int? hourTo,
    int? confirmMin,
    List<String>? kinds,
  }) =>
      ConnAutoSettings(
        mode: mode ?? this.mode,
        remindDays: remindDays ?? this.remindDays,
        maxSends: maxSends ?? this.maxSends,
        dailyCap: dailyCap ?? this.dailyCap,
        hourFrom: hourFrom ?? this.hourFrom,
        hourTo: hourTo ?? this.hourTo,
        confirmMin: confirmMin ?? this.confirmMin,
        kinds: kinds ?? this.kinds,
      );

  @override
  bool operator ==(Object other) =>
      other is ConnAutoSettings &&
      other.mode == mode &&
      other.remindDays == remindDays &&
      other.maxSends == maxSends &&
      other.dailyCap == dailyCap &&
      other.hourFrom == hourFrom &&
      other.hourTo == hourTo &&
      other.confirmMin == confirmMin &&
      listEquals([...other.kinds]..sort(), [...kinds]..sort());

  @override
  int get hashCode => Object.hash(mode, remindDays, maxSends, dailyCap, hourFrom, hourTo, confirmMin, kinds.length);
}

class ConnAutoStatus {
  const ConnAutoStatus({
    required this.available,
    this.dryRun = false,
    this.alertsEnabled = false,
    this.settings = const ConnAutoSettings(),
    this.counts = const {},
    this.inWindow = false,
  });

  static const off = ConnAutoStatus(available: false);

  final bool available;

  /// محاكاة: كلّ شيءٍ كما هو إلّا أنّ «الإرسال» سطرٌ في السجلّ — لا رسالة تصل للمشترك.
  final bool dryRun;

  /// «تنبيه المشترك» نفسه مفعّل (مفتاح الشاشة) — بدونه لا يُقاس ولا يُرسل شيء.
  final bool alertsEnabled;
  final ConnAutoSettings settings;

  /// pending · queued · watching · sent · skipped · muted · sent_today
  final Map<String, int> counts;
  final bool inWindow;

  int count(String k) => counts[k] ?? 0;

  /// يُرفع القياس؟ (الحساب مفتوح، والتنبيه مفعّل، والوضع غير يدويّ)
  bool get collects => available && alertsEnabled && settings.mode != 'manual';

  factory ConnAutoStatus.fromJson(Map<String, dynamic> j) {
    if (j['available'] != true) return off;
    final c = <String, int>{};
    if (j['counts'] is Map) {
      (j['counts'] as Map).forEach((k, v) => c['$k'] = v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    }
    return ConnAutoStatus(
      available: true,
      dryRun: j['dry_run'] == true,
      alertsEnabled: j['alerts_enabled'] == true,
      settings: j['settings'] is Map ? ConnAutoSettings.fromJson(Map<String, dynamic>.from(j['settings'] as Map)) : const ConnAutoSettings(),
      counts: c,
      inWindow: j['in_window'] == true,
    );
  }
}

class ConnAlertProblem {
  const ConnAlertProblem({required this.kind, required this.label, required this.text});
  final String kind;
  final String label;

  /// القيمة كما تدخل الرسالة («‎-70 dBm» · «يقرأ 10 ميكا»)
  final String text;
}

/// مشتركٌ في «تنبيه المشترك» التلقائيّ: حالته ومشاكله الحاليّة وأوقاتها.
class ConnAlertCase {
  const ConnAlertCase({
    required this.key,
    required this.state,
    this.idx,
    this.username,
    this.name,
    this.phone,
    this.problems = const [],
    this.firstBadAt,
    this.lastReadingAt,
    this.confirmedAt,
    this.lastSentAt,
    this.sends = 0,
    this.muted = false,
    this.lastError,
  });

  final String key;

  /// watching · pending · queued · sent · skipped · ok
  final String state;
  final String? idx;
  final String? username;
  final String? name;
  final String? phone;
  final List<ConnAlertProblem> problems;
  final DateTime? firstBadAt;
  final DateTime? lastReadingAt;
  final DateTime? confirmedAt;
  final DateTime? lastSentAt;
  final int sends;
  final bool muted;
  final String? lastError;

  String get title {
    final n = (name ?? '').trim();
    return n.isNotEmpty ? n : (username ?? key);
  }

  static DateTime? _ms(Object? v) {
    final n = v is num ? v.toInt() : int.tryParse('$v');
    return n == null || n <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(n);
  }

  factory ConnAlertCase.fromJson(Map<String, dynamic> j) => ConnAlertCase(
        key: '${j['key']}',
        state: '${j['state'] ?? 'ok'}',
        idx: j['idx']?.toString(),
        username: j['username']?.toString(),
        name: j['name']?.toString(),
        phone: j['phone']?.toString(),
        problems: j['problems'] is List
            ? (j['problems'] as List)
                .whereType<Map>()
                .map((p) => ConnAlertProblem(kind: '${p['kind']}', label: '${p['label'] ?? p['kind']}', text: '${p['text'] ?? ''}'))
                .toList()
            : const [],
        firstBadAt: _ms(j['first_bad_ms']),
        lastReadingAt: _ms(j['last_reading_ms']),
        confirmedAt: _ms(j['confirmed_ms']),
        lastSentAt: _ms(j['last_sent_ms']),
        sends: j['sends'] is num ? (j['sends'] as num).toInt() : 0,
        muted: j['muted'] == true,
        lastError: (j['last_error'] ?? '').toString().trim().isEmpty ? null : '${j['last_error']}',
      );
}

class ConnAlertLogEntry {
  const ConnAlertLogEntry({required this.action, this.name, this.kinds = const [], this.dry = false, this.detail, this.at});
  final String action;
  final String? name;
  final List<String> kinds;
  final bool dry;
  final String? detail;
  final DateTime? at;
}

class ConnectionAutoApi {
  ConnectionAutoApi._();

  /// آخر حالةٍ معروفة (شارة «بانتظار موافقتك» وقرار رفع القراءات).
  static final ValueNotifier<ConnAutoStatus> status = ValueNotifier(ConnAutoStatus.off);
  static DateTime? _at;
  static Future<ConnAutoStatus>? _flight;
  static const _ttl = Duration(minutes: 5);

  @visibleForTesting
  static void debugReset() {
    status.value = ConnAutoStatus.off;
    _at = null;
    _flight = null;
  }

  static Future<ConnAutoStatus> load({bool force = false}) {
    if (!force && _at != null && DateTime.now().difference(_at!) < _ttl) return Future.value(status.value);
    return _flight ??= _load().whenComplete(() => _flight = null);
  }

  static Future<ConnAutoStatus> _load() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/connection-alerts/auto');
      final d = r.data?['data'];
      if (r.data?['success'] == true && d is Map) {
        status.value = ConnAutoStatus.fromJson(Map<String, dynamic>.from(d));
        _at = DateTime.now();
      }
    } catch (e) {
      // خادمٌ أقدم أو بلا صلاحيّة ⇒ الميزة غائبة كما كانت
      if (!kReleaseMode) debugPrint('🔴 connection-alerts/auto: $e');
    }
    return status.value;
  }

  static String _msg(Object e, String fallback) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['message'] != null) return '${d['message']}';
    }
    return fallback;
  }

  static Future<({bool ok, String? message})> save(ConnAutoSettings s) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>('/api/v2/connection-alerts/auto', data: s.toJson());
      if (r.data?['success'] == true) {
        await load(force: true);
        return (ok: true, message: r.data?['message']?.toString());
      }
      return (ok: false, message: r.data?['message']?.toString() ?? 'تعذّر الحفظ');
    } catch (e) {
      return (ok: false, message: _msg(e, 'تعذّر الحفظ — تحقّق من الاتّصال'));
    }
  }

  /// قراءاتٌ خام (دفعة ≤ ٤٠٠). صامتة: فشلها لا يُزعج أحداً — الموجة التالية تعيدها.
  static Future<bool> uploadReadings(List<Map<String, dynamic>> readings) async {
    if (readings.isEmpty) return true;
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/v2/connection-alerts/readings', data: {'readings': readings});
      final d = r.data?['data'];
      if (d is Map && d['active'] == false) {
        // الخادم يقول: لا قياس (أُطفئ/صار يدويّاً) ⇒ تُحدَّث الحالة فيتوقّف الرفع
        unawaitedLoad();
      }
      return r.data?['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static void unawaitedLoad() {
    load(force: true).ignore();
  }

  static Future<List<ConnAlertCase>> queue(String state) async {
    final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/connection-alerts/queue', queryParameters: {'state': state, 'limit': 300});
    final d = r.data?['data'];
    if (d is! Map || d['items'] is! List) return const [];
    return (d['items'] as List).whereType<Map>().map((m) => ConnAlertCase.fromJson(Map<String, dynamic>.from(m))).toList();
  }

  /// approve · skip · mute · unmute · requeue — أو «أرسل للكلّ» ([all])
  static Future<({bool ok, int done, String? message})> act(String action, List<String> keys, {bool all = false}) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/v2/connection-alerts/queue/action',
          data: {'action': action, if (all) 'all': true else 'keys': keys});
      final d = r.data?['data'];
      final done = d is Map && d['done'] is num ? (d['done'] as num).toInt() : 0;
      unawaitedLoad();
      return (ok: r.data?['success'] == true, done: done, message: r.data?['message']?.toString());
    } catch (e) {
      return (ok: false, done: 0, message: _msg(e, 'تعذّر الآن — حاول بعد قليل'));
    }
  }

  static Future<List<ConnAlertLogEntry>> log() async {
    final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/connection-alerts/log', queryParameters: {'limit': 100});
    final d = r.data?['data'];
    if (d is! Map || d['items'] is! List) return const [];
    return (d['items'] as List).whereType<Map>().map((m) {
      final name = '${m['name'] ?? ''}'.trim();
      final user = '${m['username'] ?? ''}'.trim();
      final at = m['at_ms'] is num ? DateTime.fromMillisecondsSinceEpoch((m['at_ms'] as num).toInt()) : null;
      return ConnAlertLogEntry(
        action: '${m['action']}',
        name: name.isNotEmpty ? name : (user.isNotEmpty ? user : null),
        kinds: m['kinds'] is List ? (m['kinds'] as List).map((e) => '$e').toList() : const [],
        dry: m['dry'] == true,
        detail: m['detail']?.toString(),
        at: at,
      );
    }).toList();
  }
}
