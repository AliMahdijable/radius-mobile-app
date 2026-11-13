import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/platform/app_platform.dart';
import '../core/util/format.dart';
import '../services/app_resumed_signal.dart';
import '../services/auth_storage.dart';
import '../services/permissions_service.dart';
import 'api_client.dart';
import 'company_route.dart';

/// «الموظف المتّصل الآن» (١٤ نوفمبر — المالك: «المدير يشوف اي موظف متصل حاليا … يستخدم البرنامج فعليا او ما يستخدمه»).
///
/// الخادم (server/employeePresence.js) يحسب كلّ شيء — التطبيق يعرض ويرسل نبضته فقط:
/// - لمدير الصفحة وحده: حال كلّ موظّف (متّصل الآن · آخر ظهور · عمليّات اليوم وآخر عمليّة) ونشاطه لثلاثين يوماً.
/// - برنامج الموظّف المفتوح يرسل نبضةً كلّ دقيقة ([EmployeePresenceBeat]) — أوقاتٌ وحدها، بلا موقعٍ ولا محتوى.
/// - كلّ نداءٍ للشركة **المفتوحة** صراحةً ([CompanyRoute.explicit]): هذه المسارات لا تُوجَّه في «كل الشركات».

DateTime? _t(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

int _i(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

String? _s(Object? v) {
  final t = v?.toString().trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// «منذ 5 دقائق» / «منذ ساعتين» / «منذ 3 أيام» / «الآن» — لزمنٍ مضى.
String presenceAgo(DateTime at, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inSeconds < 60) return 'الآن';
  if (d.inMinutes < 60) return 'منذ ${arMinutes(d.inMinutes)}';
  if (d.inHours < 24) return 'منذ ${arHours(d.inHours)}';
  return 'منذ ${arDays(d.inDays)}';
}

/// «14:05» بتوقيت الجهاز، أو «—».
String presenceClock(DateTime? at) {
  if (at == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(at.hour)}:${two(at.minute)}';
}

/// «45 د» / «ساعتان و10 د» / «—».
String presenceUsage(int minutes) {
  if (minutes <= 0) return '—';
  if (minutes < 60) return '$minutes د';
  final h = minutes ~/ 60;
  final rest = minutes % 60;
  final hours = arCount(h, one: 'ساعة', two: 'ساعتان', few: 'ساعات', many: 'ساعة');
  return rest == 0 ? hours : '$hours و$rest د';
}

/// «5 عمليّات اليوم» / «عمليّة واحدة اليوم» / «لا عمليّات اليوم» / null (تعذّرت القراءة).
String? presenceOpsToday(int? n) {
  if (n == null) return null;
  if (n == 0) return 'لا عمليّات اليوم';
  return '${arCount(n, one: 'عمليّة واحدة', two: 'عمليّتان', few: 'عمليّات', many: 'عمليّة')} اليوم';
}

/// آخر عمليّةٍ باسمه.
class PresenceOp {
  const PresenceOp({required this.label, this.at});
  final String label;
  final DateTime? at;

  /// «تفعيل · منذ 10 دقائق».
  String text({DateTime? now}) => at == null ? label : '$label · ${presenceAgo(at!, now: now)}';

  static PresenceOp? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final label = _s(raw['label']);
    return label == null ? null : PresenceOp(label: label, at: _t(raw['at']));
  }
}

/// حال موظّفٍ الآن (سطر القائمة).
class PresenceRow {
  const PresenceRow({
    required this.employeeId,
    this.username,
    this.name,
    this.active = true,
    this.online = false,
    this.lastSeenAt,
    this.platformLabel,
    this.appBuild,
    this.lastLoginAt,
    this.minutesToday = 0,
    this.opsToday,
    this.lastOp,
  });
  final int employeeId;
  final String? username;
  final String? name;
  final bool active;

  /// برنامجه مفتوحٌ ويعمل خلال آخر دقيقتين ونصف.
  final bool online;
  final DateTime? lastSeenAt;
  final String? platformLabel;
  final String? appBuild;
  final DateTime? lastLoginAt;
  final int minutesToday;

  /// null = تعذّرت قراءة سجلّ الحركات الآن (لا صفر).
  final int? opsToday;
  final PresenceOp? lastOp;

  String get displayName => (name != null && name!.trim().isNotEmpty) ? name!.trim() : (username ?? '#$employeeId');

  /// «متّصل الآن» / «آخر ظهور منذ 5 دقائق» / «آخر دخول منذ يومين» (قبل الميزة) / «لم يظهر بعد».
  String seenText({DateTime? now}) {
    if (online) return 'متّصل الآن';
    if (lastSeenAt != null) return 'آخر ظهور ${presenceAgo(lastSeenAt!, now: now)}';
    if (lastLoginAt != null) return 'آخر دخول ${presenceAgo(lastLoginAt!, now: now)}';
    return 'لم يظهر بعد';
  }

  /// سطرٌ واحد للقائمة: «متّصل الآن · 12 عمليّة اليوم».
  String line({DateTime? now}) {
    final ops = (opsToday ?? 0) > 0 ? presenceOpsToday(opsToday) : null;
    return ops == null ? seenText(now: now) : '${seenText(now: now)} · $ops';
  }

  static PresenceRow? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final emp = raw['employee'];
    final id = _i(emp is Map ? emp['id'] : null);
    if (id <= 0) return null;
    final ops = raw['ops_today'];
    return PresenceRow(
      employeeId: id,
      username: emp is Map ? _s(emp['username']) : null,
      name: emp is Map ? _s(emp['name']) : null,
      active: raw['active'] != false,
      online: raw['online'] == true,
      lastSeenAt: _t(raw['last_seen_at']),
      platformLabel: _s(raw['platform_label']),
      appBuild: _s(raw['app_build']),
      lastLoginAt: _t(raw['last_login_at']),
      minutesToday: _i(raw['minutes_today']),
      opsToday: ops == null ? null : _i(ops),
      lastOp: PresenceOp.fromJson(raw['last_op']),
    );
  }
}

/// موظّفو الصفحة بحالهم الآن.
class PresenceList {
  const PresenceList({required this.rows, this.onlineCount = 0, this.opsUnavailable = false});
  final List<PresenceRow> rows;
  final int onlineCount;
  final bool opsUnavailable;

  int get total => rows.length;
  PresenceRow? of(int employeeId) {
    for (final r in rows) {
      if (r.employeeId == employeeId) return r;
    }
    return null;
  }

  static PresenceList? fromJson(Object? raw) {
    if (raw is! Map || raw['feature_enabled'] != true) return null;
    final list = raw['employees'];
    final rows = list is List ? list.map(PresenceRow.fromJson).whereType<PresenceRow>().toList() : <PresenceRow>[];
    return PresenceList(rows: rows, onlineCount: _i(raw['online_count']), opsUnavailable: raw['ops_unavailable'] == true);
  }
}

/// يومٌ في سجلّ الموظّف.
class PresenceDay {
  const PresenceDay({required this.day, this.firstSeenAt, this.lastSeenAt, this.minutes = 0, this.ops});

  /// 'YYYY-MM-DD' (يوم بغداد).
  final String day;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;
  final int minutes;
  final int? ops;

  static PresenceDay? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final day = _s(raw['day']);
    if (day == null) return null;
    final ops = raw['ops'];
    return PresenceDay(
      day: day,
      firstSeenAt: _t(raw['first_seen_at']),
      lastSeenAt: _t(raw['last_seen_at']),
      minutes: _i(raw['minutes']),
      ops: ops == null ? null : _i(ops),
    );
  }
}

/// نشاط موظّفٍ واحد: حاله الآن، اليوم بأنواع عمليّاته، وسجلّ الأيّام.
class PresenceDetail {
  const PresenceDetail({
    required this.row,
    required this.today,
    this.opsByType = const [],
    this.days = const [],
    this.keepDays = 30,
    this.opsUnavailable = false,
  });
  final PresenceRow row;

  /// يوم بغداد الحاليّ ('YYYY-MM-DD').
  final String today;
  final List<({String label, int count})> opsByType;
  final List<PresenceDay> days;
  final int keepDays;
  final bool opsUnavailable;

  PresenceDay? get todayRow => days.isNotEmpty && days.first.day == today ? days.first : null;

  static PresenceDetail? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final summary = raw['today_summary'];
    // الحال نفسه بشكل سطر القائمة (عمليّات اليوم من ملخّص اليوم)
    final row = PresenceRow.fromJson({
      ...raw,
      'ops_today': summary is Map ? summary['ops'] : null,
      'minutes_today': summary is Map ? summary['minutes'] : 0,
    });
    if (row == null) return null;
    final types = <({String label, int count})>[];
    final rawTypes = summary is Map ? summary['ops_by_type'] : null;
    if (rawTypes is List) {
      for (final t in rawTypes) {
        final label = t is Map ? _s(t['label']) : null;
        if (label != null) types.add((label: label, count: _i((t as Map)['count'])));
      }
    }
    final days = raw['days'];
    return PresenceDetail(
      row: row,
      today: _s(raw['today']) ?? '',
      opsByType: types,
      days: days is List ? days.map(PresenceDay.fromJson).whereType<PresenceDay>().toList() : const [],
      keepDays: _i(raw['keep_days']) > 0 ? _i(raw['keep_days']) : 30,
      opsUnavailable: raw['ops_unavailable'] == true,
    );
  }
}

class EmployeePresenceApi {
  EmployeePresenceApi._();

  static const _base = '/api/v2/employee-presence';

  /// للشركة المفتوحة صراحةً — لا تأخذ وجهة قسمٍ موجَّه.
  static Options get _open => CompanyRoute.explicit(null);

  static void _log(String what, Object e) {
    if (!kReleaseMode) debugPrint('🔴 employee-presence $what: $e');
  }

  /// موظّفو الصفحة بحالهم الآن — للمدير وحده. null = الميزة مطفأة لهذه الصفحة، أو المستعمل موظّف، أو تعذّر السؤال.
  static Future<PresenceList?> list() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(_base, options: _open);
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      return PresenceList.fromJson(body['data']);
    } catch (e) {
      _log('list', e);
      return null;
    }
  }

  /// نشاط موظّفٍ واحد. (data, message): تعذّر ⇒ رسالة الخادم العربيّة.
  static Future<({PresenceDetail? data, String? message})> detail(int id) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('$_base/$id', options: _open);
      final body = r.data ?? const {};
      final d = body['success'] == true ? PresenceDetail.fromJson(body['data']) : null;
      return (data: d, message: d == null ? (body['message']?.toString() ?? 'تعذّر تحميل نشاط الموظف') : null);
    } catch (e) {
      _log('detail', e);
      return (data: null, message: 'تعذّر تحميل نشاط الموظف الآن — حاول بعد قليل');
    }
  }

  /// نبضة «البرنامج مفتوحٌ أمامي». (enabled, everySec) أو null إن تعذّرت — الكتابة نفسها عند الخادم لكلّ طلبٍ بتوكن الموظّف.
  static Future<({bool enabled, int everySec})?> beat() async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/beat', options: _open, data: const <String, dynamic>{});
      final body = r.data ?? const {};
      final data = body['data'];
      if (body['success'] != true || data is! Map) return null;
      final every = _i(data['beat_every_sec']);
      return (enabled: data['feature_enabled'] == true, everySec: every < 30 ? 60 : (every > 600 ? 600 : every));
    } catch (e) {
      _log('beat', e);
      return null;
    }
  }
}

/// نبضة برنامج الموظّف: ما دام التطبيق مفتوحاً أمامه (جلسة موظّف) تُرسَل نبضةٌ كلّ دقيقة فيراه مديره «متّصلاً الآن» ولو لم يضغط
/// شيئاً. الميزة مطفأة لصفحته ⇒ يُسأل ثانيةً بعد عشر دقائق. في الخلفيّة لا مؤقّت يعمل فعلاً (النظام يوقفه) — والعودة للواجهة
/// ([AppResumedSignal]) ترسل نبضةً فوراً. فشلها صامت، وتبديل الجلسة يوقفها ([stop]).
class EmployeePresenceBeat {
  EmployeePresenceBeat._();

  static Timer? _timer;
  static bool _running = false;
  static int _epoch = 0;
  static DateTime? _lastBeatAt;

  static const _offRetry = Duration(minutes: 10);

  /// للاختبار: مصدرٌ بديل للنبضة، وتشغيلٌ رغم بيئة الاختبار.
  @visibleForTesting
  static Future<({bool enabled, int everySec})?> Function()? beatOverride;
  @visibleForTesting
  static bool debugAllowInTests = false;

  /// مصدر الوقت — يُستبدل في الاختبارات (ساعةٌ وهميّة).
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  static bool get running => _running;

  /// يبدأ النبض لجلسة موظّف (لا شيء للمدير). آمنٌ أن يُنادى مراراً.
  static void start() {
    if (_running) return;
    if (!PermissionsService.isEmployee) return;
    // مؤقّتٌ دوريّ في اختبارات الواجهة يُبقيها معلّقة — يعمل هناك حين يُطلب صراحةً وحده
    if (AppPlatform.isUnderTest && !debugAllowInTests) return;
    _running = true;
    _epoch++;
    AppResumedSignal.tick.addListener(_onResumed);
    _schedule(const Duration(seconds: 5), _epoch);
  }

  /// يوقفه (خروج، تبديل جلسة، إغلاق الغلاف).
  static void stop() {
    if (!_running && _timer == null) return;
    _running = false;
    _epoch++;
    _timer?.cancel();
    _timer = null;
    _lastBeatAt = null;
    AppResumedSignal.tick.removeListener(_onResumed);
  }

  static void _schedule(Duration wait, int epoch) {
    _timer?.cancel();
    _timer = Timer(wait, () => _beat(epoch));
  }

  static void _onResumed() {
    if (!_running) return;
    // عاد للواجهة: نبضةٌ الآن إن مضت نصف دقيقة على السابقة
    final last = _lastBeatAt;
    if (last != null && now().difference(last) < const Duration(seconds: 30)) return;
    _schedule(Duration.zero, _epoch);
  }

  static Future<void> _beat(int epoch) async {
    if (!_running || epoch != _epoch) return;
    ({bool enabled, int everySec})? r;
    try {
      if (beatOverride != null) {
        r = await beatOverride!();
      } else {
        final token = await AuthStorage.readToken();
        r = (token == null || token.isEmpty) ? null : await EmployeePresenceApi.beat();
      }
    } catch (_) {
      r = null;
    }
    if (!_running || epoch != _epoch) return;
    _lastBeatAt = now();
    final wait = r == null
        ? const Duration(seconds: 60)
        : r.enabled
            ? Duration(seconds: r.everySec)
            : _offRetry;
    _schedule(wait, epoch);
  }
}
