import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// «إشعاراتي» — تنبيهات المال للوكيل (٢٠ نوفمبر — المالك: «قسم جديد اشعارات الوكيل… حد ادنى للشحن · سقف اعلى للديون · تذكير
/// بالمديونين بالأيام وبالمبلغ» ثمّ «نكدر ننطي صلاحيه هو يحدد واذا اكو تكرار؟»).
///
/// العقد (الخادم: GET/PUT `/api/v2/agent-notifs`): ثلاثة تنبيهات بإعدادها وحالها الآن، وآخر ما وصل. خادمٌ لا يعرف الميزة (404) ⇒
/// [AgentNotifsApi.load] تعيد null والقسم لا يظهر — النسخة المنشورة قبل الخادم تبقى كما كانت.

/// تكرار تنبيهٍ ما دام سببه قائماً (الرصيد تحت الحدّ، الديون فوق السقف): مرّةً · كلّ ساعتين/٦ ساعات · كلّ يومٍ بساعة.
enum AlertRepeatMode { once, everyHours, daily }

@immutable
class AlertRepeat {
  const AlertRepeat.once()
      : mode = AlertRepeatMode.once,
        hours = null,
        at = null;
  const AlertRepeat.everyHours(int this.hours)
      : mode = AlertRepeatMode.everyHours,
        at = null;
  const AlertRepeat.daily(String this.at)
      : mode = AlertRepeatMode.daily,
        hours = null;

  final AlertRepeatMode mode;
  final int? hours;

  /// «HH:mm» بتوقيت بغداد.
  final String? at;

  /// ما يقبله الخادم: لا تكرار أقرب من كلّ ساعتين (قرار ٢٠ نوفمبر).
  static const allowedHours = [2, 6];

  static AlertRepeat fromJson(Object? raw) {
    if (raw is! Map) return const AlertRepeat.once();
    switch (raw['mode']?.toString()) {
      case 'every_hours':
        final h = int.tryParse('${raw['hours']}');
        return h != null && allowedHours.contains(h) ? AlertRepeat.everyHours(h) : const AlertRepeat.once();
      case 'daily':
        final at = normalizeHm(raw['at']);
        return at == null ? const AlertRepeat.once() : AlertRepeat.daily(at);
      default:
        return const AlertRepeat.once();
    }
  }

  Map<String, Object?> toJson() => switch (mode) {
        AlertRepeatMode.once => {'mode': 'once'},
        AlertRepeatMode.everyHours => {'mode': 'every_hours', 'hours': hours},
        AlertRepeatMode.daily => {'mode': 'daily', 'at': at},
      };

  /// «مرّة وحدة» · «كل ساعتين» · «كل 6 ساعات» · «كل يوم 09:00».
  String get label => switch (mode) {
        AlertRepeatMode.once => 'مرّة وحدة',
        AlertRepeatMode.everyHours => hours == 2 ? 'كل ساعتين' : 'كل $hours ساعات',
        AlertRepeatMode.daily => 'كل يوم $at',
      };

  @override
  bool operator ==(Object other) => other is AlertRepeat && other.mode == mode && other.hours == hours && other.at == at;

  @override
  int get hashCode => Object.hash(mode, hours, at);
}

/// «HH:mm» صالحة أو null.
String? normalizeHm(Object? raw) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw?.toString().trim() ?? '');
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final mi = int.parse(m.group(2)!);
  if (h > 23 || mi > 59) return null;
  return '${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}';
}

/// موعد ملخّص المديونين: كلّ يوم · كلّ أسبوع بيوم · كلّ N أيّام — بساعة.
enum DigestMode { daily, weekly, everyDays }

@immutable
class DigestSchedule {
  const DigestSchedule({required this.mode, required this.at, this.weekday = 6, this.days = 3});

  final DigestMode mode;
  final String at;

  /// ١ الاثنين … ٧ الأحد (ISO) — للأسبوعيّ.
  final int weekday;

  /// كلّ كم يوم (٢–٣٠) — لـ[DigestMode.everyDays].
  final int days;

  static const weekdays = {
    6: 'السبت',
    7: 'الأحد',
    1: 'الاثنين',
    2: 'الثلاثاء',
    3: 'الأربعاء',
    4: 'الخميس',
    5: 'الجمعة',
  };

  static DigestSchedule fromJson(Object? raw) {
    const def = DigestSchedule(mode: DigestMode.daily, at: '10:00');
    if (raw is! Map) return def;
    final at = normalizeHm(raw['at']) ?? def.at;
    switch (raw['mode']?.toString()) {
      case 'weekly':
        final wd = int.tryParse('${raw['weekday']}');
        return DigestSchedule(mode: DigestMode.weekly, at: at, weekday: wd != null && wd >= 1 && wd <= 7 ? wd : 6);
      case 'every_days':
        final d = int.tryParse('${raw['days']}');
        return DigestSchedule(mode: DigestMode.everyDays, at: at, days: d != null && d >= 2 && d <= 30 ? d : 3);
      default:
        return DigestSchedule(mode: DigestMode.daily, at: at);
    }
  }

  Map<String, Object?> toJson() => switch (mode) {
        DigestMode.daily => {'mode': 'daily', 'at': at},
        DigestMode.weekly => {'mode': 'weekly', 'at': at, 'weekday': weekday},
        DigestMode.everyDays => {'mode': 'every_days', 'at': at, 'days': days},
      };

  /// «كل يوم 10:00» · «كل سبت 10:00» · «كل 3 أيام 10:00».
  String get label => switch (mode) {
        DigestMode.daily => 'كل يوم $at',
        DigestMode.weekly => 'كل ${weekdays[weekday] ?? 'سبت'} $at'.replaceFirst('كل ال', 'كل '),
        DigestMode.everyDays => days == 2 ? 'كل يومين $at' : 'كل $days ${days >= 3 && days <= 10 ? 'أيام' : 'يوم'} $at',
      };

  DigestSchedule copyWith({DigestMode? mode, String? at, int? weekday, int? days}) =>
      DigestSchedule(mode: mode ?? this.mode, at: at ?? this.at, weekday: weekday ?? this.weekday, days: days ?? this.days);

  @override
  bool operator ==(Object other) =>
      other is DigestSchedule && other.mode == mode && other.at == at && other.weekday == weekday && other.days == days;

  @override
  int get hashCode => Object.hash(mode, at, weekday, days);
}

num? _num(Object? v) {
  if (v == null || v is bool) return null;
  if (v is num) return v.isFinite ? v : null;
  return num.tryParse(v.toString().replaceAll(',', '').trim());
}

int? _int(Object? v) {
  final n = _num(v);
  return n?.round();
}

/// «رصيدك تحت حدّ».
@immutable
class BalanceAlert {
  const BalanceAlert({required this.enabled, this.threshold, this.repeat = const AlertRepeat.once(), this.now, this.daysLeft});
  final bool enabled;
  final num? threshold;
  final AlertRepeat repeat;

  /// الرصيد الآن (null = تعذّرت قراءته — لا تنبيه كاذب).
  final num? now;

  /// كم يوماً يكفي بمعدّل صرف الأسبوع (null = لا معدّل بعد).
  final int? daysLeft;

  static BalanceAlert fromJson(Object? raw) {
    final m = raw is Map ? raw : const {};
    return BalanceAlert(
      enabled: m['enabled'] == true,
      threshold: _num(m['threshold']),
      repeat: AlertRepeat.fromJson(m['repeat']),
      now: _num(m['now']),
      daysLeft: _int(m['days_left']),
    );
  }
}

/// «سقف ديون مشتركيك» — ينبّه عند ٨٠٪ و١٠٠٪.
@immutable
class DebtCapAlert {
  const DebtCapAlert({required this.enabled, this.cap, this.repeat = const AlertRepeat.once(), this.now});
  final bool enabled;
  final num? cap;
  final AlertRepeat repeat;
  final num? now;

  /// النسبة الآن من السقف (null بلا سقفٍ أو بلا رقم).
  int? get percent => cap == null || cap! <= 0 || now == null ? null : (now! * 100 / cap!).round();

  static DebtCapAlert fromJson(Object? raw) {
    final m = raw is Map ? raw : const {};
    return DebtCapAlert(
      enabled: m['enabled'] == true,
      cap: _num(m['cap']),
      repeat: AlertRepeat.fromJson(m['repeat']),
      now: _num(m['now']),
    );
  }
}

/// «ملخّص المديونين» بعمر الدين و/أو مبلغه.
@immutable
class DebtorsDigest {
  const DebtorsDigest({
    required this.enabled,
    this.minDays,
    this.minAmount,
    this.maxAmount,
    this.schedule = const DigestSchedule(mode: DigestMode.daily, at: '10:00'),
    this.matchCount,
    this.matchTotal,
  });
  final bool enabled;
  final int? minDays;
  final num? minAmount;
  final num? maxAmount;
  final DigestSchedule schedule;

  /// من يطابق الآن (null = لم يُحسب).
  final int? matchCount;
  final num? matchTotal;

  static DebtorsDigest fromJson(Object? raw) {
    final m = raw is Map ? raw : const {};
    final match = m['matching'] is Map ? m['matching'] as Map : const {};
    return DebtorsDigest(
      enabled: m['enabled'] == true,
      minDays: _int(m['min_days']),
      minAmount: _num(m['min_amount']),
      maxAmount: _num(m['max_amount']),
      schedule: DigestSchedule.fromJson(m['schedule']),
      matchCount: _int(match['count']),
      matchTotal: _num(match['total']),
    );
  }
}

/// سطرٌ من «آخر التنبيهات».
@immutable
class AgentNotifLine {
  const AgentNotifLine({required this.kind, required this.title, required this.at});
  final String kind; // balance | debt_cap | debtors
  final String title;
  final DateTime at;

  static AgentNotifLine? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse(raw['at']?.toString() ?? '');
    final title = raw['title']?.toString().trim() ?? '';
    if (at == null || title.isEmpty) return null;
    return AgentNotifLine(kind: raw['kind']?.toString() ?? '', title: title, at: at.toLocal());
  }
}

@immutable
class AgentNotifs {
  const AgentNotifs({required this.balance, required this.debtCap, required this.debtors, this.recent = const [], this.currency = 'IQD'});
  final BalanceAlert balance;
  final DebtCapAlert debtCap;
  final DebtorsDigest debtors;
  final List<AgentNotifLine> recent;
  final String currency;

  static AgentNotifs? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return AgentNotifs(
      balance: BalanceAlert.fromJson(raw['balance']),
      debtCap: DebtCapAlert.fromJson(raw['debt_cap']),
      debtors: DebtorsDigest.fromJson(raw['debtors']),
      recent: [
        for (final r in (raw['recent'] is List ? raw['recent'] as List : const []))
          if (AgentNotifLine.fromJson(r) case final l?) l,
      ],
      currency: raw['currency']?.toString() ?? 'IQD',
    );
  }
}

class AgentNotifsApi {
  AgentNotifsApi._();

  static const path = '/api/v2/agent-notifs';

  /// الإعداد والحال الآن — null حين لا يعرف الخادم الميزة (404) أو تعذّرت القراءة: القسم لا يظهر.
  static Future<AgentNotifs?> load() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(path);
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      return AgentNotifs.fromJson(body['data']);
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('[AgentNotifsApi] load: ${e.response?.statusCode ?? e.type}');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[AgentNotifsApi] load: $e');
      return null;
    }
  }

  /// يحفظ جزءاً من الإعداد (`{"balance": {...}}` …) ⇒ الإعداد كما فهمه الخادم، أو الرسالة.
  static Future<({bool ok, String? message, AgentNotifs? data})> save(Map<String, Object?> patch) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(path, data: patch);
      final body = r.data ?? const {};
      if (body['success'] != true) return (ok: false, message: body['message']?.toString(), data: null);
      return (ok: true, message: null, data: AgentNotifs.fromJson(body['data']));
    } on DioException catch (e) {
      final b = e.response?.data;
      return (ok: false, message: b is Map ? b['message']?.toString() : null, data: null);
    } catch (_) {
      return (ok: false, message: null, data: null);
    }
  }
}
