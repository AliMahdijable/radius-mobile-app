import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// «النسخ الاحتياطيّ إلى Google Drive» (٢٣ نوفمبر — المالك: «ميزه لكل وكيل يربط حساب كوكل درايف مالته للنسخ التلقائي للديون
/// يومي سبوعي شهري يكدر يحدده ويحدد الوقت… بشكل اكسل»، ثمّ «ملف واحد، وخلّي آخر ٣٠ نسخة» و«خليها اسهل لان الوكلاء اغلبهم صعب
/// يعرفون هجي ربط»).
///
/// الخادم ينسخ (server/gdriveBackup): الوكيل يربط درايفه مرّةً (صفحة موافقة Google في المتصفّح)، وأوّل نسخةٍ تُحفظ لحظتها، ثمّ بموعدها
/// (كلّ يوم 03:00 افتراضاً). العقد: `/api/v2/gdrive-backup` — `GET /me` · `GET` (الحال) · `POST /connect {via:'app'}` ⇒ `{url}` ·
/// `PUT /schedule` · `POST /run` · `DELETE /link`. خادمٌ لا يعرف الميزة أو مفتاحٌ مطفأ ⇒ [GdriveBackupApi.me] null والبند لا يظهر.

/// الموعد: `daily` · `weekly` (يوم الأسبوع ٠ الأحد … ٦ السبت) · `monthly` (١–٢٨، ٠ = آخر يوم) + «HH:mm» بتوقيت بغداد.
@immutable
class GdbSchedule {
  const GdbSchedule({required this.frequency, required this.time, this.weekday, this.monthday, this.enabled = true});

  static const daily = GdbSchedule(frequency: 'daily', time: '03:00');

  final String frequency;
  final String time;
  final int? weekday;
  final int? monthday;
  final bool enabled;

  static GdbSchedule fromJson(Object? raw) {
    if (raw is! Map) return daily;
    final f = raw['frequency']?.toString();
    final freq = const ['daily', 'weekly', 'monthly'].contains(f) ? f! : 'daily';
    return GdbSchedule(
      frequency: freq,
      time: gdbNormalizeHm(raw['time']) ?? '03:00',
      weekday: freq == 'weekly' ? _int(raw['weekday']) : null,
      monthday: freq == 'monthly' ? _int(raw['monthday']) : null,
      enabled: raw['enabled'] != false,
    );
  }

  Map<String, Object?> toJson() => {
        'frequency': frequency,
        'time': time,
        'weekday': frequency == 'weekly' ? weekday ?? 6 : null,
        'monthday': frequency == 'monthly' ? monthday ?? 1 : null,
        'enabled': enabled,
      };

  GdbSchedule copyWith({String? frequency, String? time, int? weekday, int? monthday, bool? enabled}) => GdbSchedule(
        frequency: frequency ?? this.frequency,
        time: time ?? this.time,
        weekday: weekday ?? this.weekday,
        monthday: monthday ?? this.monthday,
        enabled: enabled ?? this.enabled,
      );

  @override
  bool operator ==(Object other) =>
      other is GdbSchedule &&
      other.frequency == frequency &&
      other.time == time &&
      other.weekday == weekday &&
      other.monthday == monthday &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(frequency, time, weekday, monthday, enabled);
}

/// نسخةٌ واحدة في السجلّ: `trigger` schedule/manual/first · `status` running/ok/failed.
@immutable
class GdbRun {
  const GdbRun({
    required this.id,
    required this.trigger,
    required this.status,
    this.startedAt,
    this.finishedAt,
    this.subscribers,
    this.debtors,
    this.debtTotal,
    this.fileUrl,
    this.errorMessage,
  });

  final int id;
  final String trigger;
  final String status;
  final int? startedAt;
  final int? finishedAt;
  final int? subscribers;
  final int? debtors;
  final int? debtTotal;
  final String? fileUrl;
  final String? errorMessage;

  bool get ok => status == 'ok';
  bool get failed => status == 'failed';

  static GdbRun? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _int(raw['id']);
    if (id == null) return null;
    return GdbRun(
      id: id,
      trigger: raw['trigger']?.toString() ?? 'schedule',
      status: raw['status']?.toString() ?? '',
      startedAt: _int(raw['started_at']),
      finishedAt: _int(raw['finished_at']),
      subscribers: _int(raw['subscribers']),
      debtors: _int(raw['debtors']),
      debtTotal: _int(raw['debt_total']),
      fileUrl: _str(raw['file_url']),
      errorMessage: _str(raw['error_message']),
    );
  }
}

/// الحساب المربوط: إيميله، وانقطاعه إن سحب الوكيل الإذن (يُعاد الربط بالزرّ نفسه)، ورابط مجلّد الصفحة في درايفه.
@immutable
class GdbLink {
  const GdbLink({this.email, this.linkedAt, this.brokenCode, this.brokenMessage, this.folderUrl});

  final String? email;
  final int? linkedAt;
  final String? brokenCode;
  final String? brokenMessage;
  final String? folderUrl;

  bool get broken => brokenCode != null;

  static GdbLink? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final b = raw['broken'];
    return GdbLink(
      email: _str(raw['email']),
      linkedAt: _int(raw['linked_at']),
      brokenCode: b is Map ? _str(b['code']) : null,
      brokenMessage: b is Map ? _str(b['message']) : null,
      folderUrl: _str(raw['folder_url']),
    );
  }
}

@immutable
class GdbStatus {
  const GdbStatus({
    required this.featureEnabled,
    required this.configured,
    required this.schedule,
    required this.scheduleText,
    required this.keep,
    required this.runs,
    this.link,
    this.nextAt,
    this.jobState,
  });

  final bool featureEnabled;
  final bool configured;
  final GdbLink? link;
  final GdbSchedule schedule;

  /// «كلّ يوم الساعة 03:00» — من الخادم، بنصّ الموقع نفسه.
  final String scheduleText;
  final int? nextAt;
  final int keep;

  /// نسخةٌ جارية الآن (`running`) أو بالدور (`queued`)، أو null.
  final String? jobState;
  final List<GdbRun> runs;

  bool get linked => link != null;
  bool get working => jobState != null;
  GdbRun? get lastOk {
    for (final r in runs) {
      if (r.ok) return r;
    }
    return null;
  }

  static GdbStatus? fromJson(Object? raw) {
    if (raw is! Map || raw['success'] != true) return null;
    final runs = raw['runs'] is List ? (raw['runs'] as List).map(GdbRun.fromJson).whereType<GdbRun>().toList() : <GdbRun>[];
    final job = raw['job'];
    return GdbStatus(
      featureEnabled: raw['feature_enabled'] == true,
      configured: raw['configured'] == true,
      link: GdbLink.fromJson(raw['link']),
      schedule: GdbSchedule.fromJson(raw['schedule']),
      scheduleText: _str(raw['schedule_text']) ?? 'كلّ يوم الساعة 03:00',
      nextAt: _int(raw['next_at']),
      keep: _int(raw['keep']) ?? 30,
      jobState: job is Map ? _str(job['state']) : null,
      runs: List.unmodifiable(runs),
    );
  }
}

/// «من أنا» للقسم: مفتوحٌ لصفحتي؟ جاهزٌ من جهتنا؟ موظّف (يراه مقفلاً)؟
@immutable
class GdbMe {
  const GdbMe({required this.featureEnabled, required this.configured, required this.isEmployee});

  final bool featureEnabled;
  final bool configured;
  final bool isEmployee;

  static GdbMe? fromJson(Object? raw) {
    if (raw is! Map || raw['success'] != true) return null;
    return GdbMe(
      featureEnabled: raw['feature_enabled'] == true,
      configured: raw['configured'] == true,
      isEmployee: raw['is_employee'] == true,
    );
  }
}

/// نتيجة نداءٍ يكتب: الحال الجديدة، أو الرسالة (ورمزها).
typedef GdbResult = ({GdbStatus? data, String? message, String? code});

class GdriveBackupApi {
  GdriveBackupApi._();

  static const path = '/api/v2/gdrive-backup';

  /// آخر «من أنا» في هذه الجلسة — يُظهر البند في الإعدادات بلا انتظار.
  static final ValueNotifier<GdbMe?> me = ValueNotifier<GdbMe?>(null);

  /// خروجٌ أو تبديل شركة ⇒ لا يبقى «من أنا» الصفحة السابقة (SessionManager).
  static void reset() => me.value = null;

  /// يقرأ «من أنا» (للبند في الإعدادات). خادمٌ لا يعرف الميزة (404) أو تعذّرٌ ⇒ null.
  static Future<GdbMe?> loadMe() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('$path/me');
      final m = GdbMe.fromJson(r.data);
      me.value = m;
      return m;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('[GdriveBackupApi] me: ${e.response?.statusCode ?? e.type}');
      if (e.response?.statusCode == 404) me.value = null;
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[GdriveBackupApi] me: $e');
      return null;
    }
  }

  /// الحال الآن (للمدير وحده).
  static Future<GdbResult> status() => _call(() => ApiClient.dio.get<Map<String, dynamic>>(path));

  /// رابط صفحة موافقة Google — يُفتح في المتصفّح، وصفحة الرجوع تقول «ارجع للتطبيق».
  static Future<({String? url, String? message, String? code})> connect() async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$path/connect', data: const {'via': 'app'});
      final body = r.data ?? const {};
      final url = _str(body['url']);
      if (body['success'] == true && url != null && url.startsWith('https://accounts.google.com/')) {
        return (url: url, message: null, code: null);
      }
      return (url: null, message: _str(body['message']), code: _str(body['code']));
    } on DioException catch (e) {
      final b = e.response?.data;
      return (url: null, message: b is Map ? _str(b['message']) : null, code: b is Map ? _str(b['code']) : null);
    } catch (_) {
      return (url: null, message: null, code: null);
    }
  }

  static Future<GdbResult> saveSchedule(GdbSchedule s) =>
      _call(() => ApiClient.dio.put<Map<String, dynamic>>('$path/schedule', data: s.toJson()));

  static Future<GdbResult> runNow() => _call(() => ApiClient.dio.post<Map<String, dynamic>>('$path/run'));

  static Future<GdbResult> unlink() => _call(() => ApiClient.dio.delete<Map<String, dynamic>>('$path/link'));

  static Future<GdbResult> _call(Future<Response<Map<String, dynamic>>> Function() send) async {
    try {
      final r = await send();
      final data = GdbStatus.fromJson(r.data);
      if (data != null) return (data: data, message: null, code: null);
      final body = r.data ?? const {};
      return (data: null, message: _str(body['message']), code: _str(body['code']));
    } on DioException catch (e) {
      final b = e.response?.data;
      return (data: null, message: b is Map ? _str(b['message']) : null, code: b is Map ? _str(b['code']) : null);
    } catch (_) {
      return (data: null, message: null, code: null);
    }
  }
}

// ── نصوص الشاشة (مشتركةٌ مع اختباراتها) ─────────────────────────────────────────────────────────────────────────

/// أيّام الأسبوع بترتيب العراق (السبت أوّلاً) — الرقم كما يحفظه الخادم.
const gdbWeekdays = <(int, String)>[
  (6, 'السبت'),
  (0, 'الأحد'),
  (1, 'الاثنين'),
  (2, 'الثلاثاء'),
  (3, 'الأربعاء'),
  (4, 'الخميس'),
  (5, 'الجمعة'),
];

/// خطوات الربط كما يراها الوكيل (المالك: «خليها اسهل»).
const gdbSteps = <String>['اضغط «ربط Google Drive»', 'اختر إيميلك', 'اضغط «Allow» (سماح) — وخلصت'];

String gdbTriggerLabel(String t) => switch (t) {
      'first' => 'أوّل نسخة',
      'manual' => 'يدويّة',
      _ => 'تلقائيّة',
    };

const _bgOffsetMs = 3 * 3600 * 1000;

String _bgDay(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms + _bgOffsetMs, isUtc: true);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String _bgHm(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms + _bgOffsetMs, isUtc: true);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// وقت النسخة بتوقيت بغداد: «اليوم 03:00» · «أمس 03:00» · «2026-11-20 03:00».
String gdbRunWhen(int? ms, {required int now}) {
  if (ms == null || ms <= 0) return '—';
  final day = _bgDay(ms);
  final hm = _bgHm(ms);
  if (day == _bgDay(now)) return 'اليوم $hm';
  if (day == _bgDay(now - 86400000)) return 'أمس $hm';
  return '$day $hm';
}

String _group(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return n < 0 ? '-$b' : b.toString();
}

/// ما حفظته النسخة: «1,234 مشترك · 56 مديناً» · «… · بلا ديون».
String gdbRunCounts(GdbRun r) {
  final subs = r.subscribers;
  if (subs == null) return '';
  final d = r.debtors ?? 0;
  final head = '${_group(subs)} مشترك';
  if (d <= 0) return '$head · بلا ديون';
  return '$head · ${_group(d)} ${d == 1 ? 'مدين' : 'مديناً'}';
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num && v.isFinite) return v.round();
  return int.tryParse(v?.toString() ?? '');
}

String? _str(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

/// «HH:mm» صالحة أو null.
String? gdbNormalizeHm(Object? raw) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw?.toString().trim() ?? '');
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final mi = int.parse(m.group(2)!);
  if (h > 23 || mi > 59) return null;
  return '${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}';
}
