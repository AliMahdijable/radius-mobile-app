import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// «الصرفيات الثابتة» (٢٣ أكتوبر ٢٠٢٦) — عقد /api/v2/expenses/recurring* (server/recurringExpenses.js والويب
/// lib/recurring-expenses.ts). المالك: «وكيل عنده مصاريف شهريه ثابته كل شهر تستقطع ايجار مولد او ماشابه، هو يكتبه
/// هاي حتى لايضطر كل ما يسوي تسويه يعيدها كتابه». القالب يُكتب مرّة، وكلّ استحقاقٍ **صرفيّةٌ عاديّة** (تظهر بقائمة
/// الصرفيات بشارة «ثابتة»، وتدخل التقرير والتسوية كأيّ صرفيّة). تلقائيّ (تُكتب يوم الاستحقاق) أو بتأكيد (تُعلَّق حتى
/// تؤكّد المبلغ أو تتخطّاها). صلاحيّة الصرفيات نفسها، والكتابة خلف مفتاح الخادم (مطفأ ⇒ 409 RECURRING_OFF).

int? _int(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '');
num _num(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
String? _str(dynamic v) {
  final s = v?.toString();
  return s == null || s.isEmpty ? null : s;
}

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};

/// استحقاقٌ واحد: created (كُتبت صرفيّة) · pending (بانتظار التأكيد) · skipped (تُخطّيت، أو «فائت» بعد توقّفٍ طويل).
class RecurringRun {
  const RecurringRun({
    required this.id,
    required this.templateId,
    required this.period,
    required this.dueDate,
    required this.status,
    required this.amount,
    this.name,
    this.how,
    this.expenseId,
  });

  final int id;
  final int templateId;
  final String? name;

  /// 'YYYY-MM'.
  final String period;

  /// 'YYYY-MM-DD'.
  final String dueDate;
  final String status;

  /// auto · confirm · now · missed · skip.
  final String? how;
  final num amount;
  final int? expenseId;

  bool get isPending => status == 'pending';

  static RecurringRun? fromJson(Map<String, dynamic> j) {
    final id = _int(j['id']);
    final tid = _int(j['template_id']);
    if (id == null || tid == null) return null;
    return RecurringRun(
      id: id,
      templateId: tid,
      name: _str(j['name']),
      period: _str(j['period']) ?? '',
      dueDate: (_str(j['due_date']) ?? '').padRight(10).substring(0, 10).trim(),
      status: _str(j['status']) ?? 'created',
      how: _str(j['how']),
      amount: _num(j['amount']),
      expenseId: _int(j['expense_id']),
    );
  }
}

class RecurringTemplate {
  const RecurringTemplate({
    required this.id,
    required this.name,
    required this.amount,
    required this.day,
    required this.every,
    required this.startPeriod,
    required this.mode,
    required this.status,
    this.endPeriod,
    this.note,
    this.nextPeriod,
    this.nextDueDate,
    this.last,
  });

  final int id;
  final String name;
  final num amount;

  /// ١–٣١ — ٣١ = آخر الشهر.
  final int day;

  /// كلّ كم شهراً: ١ / ٢ / ٣ / ٦ / ١٢.
  final int every;
  final String startPeriod;
  final String? endPeriod;

  /// auto · confirm.
  final String mode;
  final String? note;

  /// active · paused · ended.
  final String status;
  final String? nextPeriod;
  final String? nextDueDate;
  final RecurringRun? last;

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isEnded => status == 'ended';
  bool get isAuto => mode == 'auto';

  static RecurringTemplate? fromJson(Map<String, dynamic> j) {
    final id = _int(j['id']);
    final name = _str(j['name']);
    if (id == null || name == null) return null;
    final nd = _map(j['next_due']);
    final last = j['last'] is Map ? RecurringRun.fromJson(_map(j['last'])) : null;
    return RecurringTemplate(
      id: id,
      name: name,
      amount: _num(j['amount']),
      day: _int(j['day']) ?? 1,
      every: _int(j['every']) ?? 1,
      startPeriod: _str(j['start_period']) ?? '',
      endPeriod: _str(j['end_period']),
      mode: _str(j['mode']) ?? 'auto',
      note: _str(j['note']),
      status: _str(j['status']) ?? 'active',
      nextPeriod: _str(nd['period']),
      nextDueDate: _str(nd['due_date']),
      last: last,
    );
  }
}

class RecurringPage {
  const RecurringPage({required this.enabled, required this.today, required this.templates, required this.pending});
  final bool enabled;

  /// اليوم بتوقيت بغداد من الخادم ('YYYY-MM-DD').
  final String today;
  final List<RecurringTemplate> templates;
  final List<RecurringRun> pending;

  /// القسم يظهر حين يفتحه الخادم للحساب، أو حين له قوالب/معلَّقة سابقة (للعرض بعد الإطفاء).
  bool get visible => enabled || templates.isNotEmpty || pending.isNotEmpty;
}

/// نتيجة كتابة: [ok]، ورسالة الخادم، ورمزه، وما كُتب الآن ([generated]) أو الاستحقاق ([run]).
typedef RecurringWrite = ({bool ok, String? message, String? code, List<RecurringRun> generated, RecurringRun? run});

class RecurringExpensesApi {
  RecurringExpensesApi._();

  static const _base = '/api/v2/expenses/recurring';
  static const everyOptions = [1, 2, 3, 6, 12];

  static Future<({RecurringPage? page, String? error})> list() async {
    try {
      final r = await ApiClient.dio.get<Object?>(_base);
      final body = _map(r.data);
      if (body['success'] != true) return (page: null, error: _str(body['message']));
      List<T> rows<T>(dynamic raw, T? Function(Map<String, dynamic>) f) => raw is List
          ? raw.whereType<Map>().map((m) => f(Map<String, dynamic>.from(m))).whereType<T>().toList()
          : <T>[];
      return (
        page: RecurringPage(
          enabled: body['enabled'] == true,
          today: _str(body['today']) ?? '',
          templates: rows(body['data'], RecurringTemplate.fromJson),
          pending: rows(body['pending'], RecurringRun.fromJson),
        ),
        error: null,
      );
    } catch (e) {
      _log('list', e);
      return (page: null, error: 'تعذّر جلب الصرفيات الثابتة');
    }
  }

  /// قالبٌ جديد. [clientRef] يمنع قالبين من ضغطتين.
  static Future<RecurringWrite> create({
    required String name,
    required int amount,
    required int day,
    required int every,
    required String startPeriod,
    String? endPeriod,
    required String mode,
    String? note,
    required String clientRef,
  }) =>
      _write(() => ApiClient.dio.post<Object?>(_base, data: {
            'name': name,
            'amount': amount,
            'day': day,
            'every': every,
            'start_period': startPeriod,
            'end_period': endPeriod,
            'mode': mode,
            if (note != null && note.isNotEmpty) 'note': note,
            'client_ref': clientRef,
          }));

  /// تعديل — للقادم وحده (المضافة سابقاً كما هي).
  static Future<RecurringWrite> update(int id, Map<String, dynamic> patch) =>
      _write(() => ApiClient.dio.put<Object?>('$_base/$id', data: patch));

  static Future<RecurringWrite> pause(int id) => _write(() => ApiClient.dio.post<Object?>('$_base/$id/pause'));
  static Future<RecurringWrite> resume(int id) => _write(() => ApiClient.dio.post<Object?>('$_base/$id/resume'));
  static Future<RecurringWrite> delete(int id) => _write(() => ApiClient.dio.delete<Object?>('$_base/$id'));

  /// «دفعتها الآن»: أقرب استحقاقٍ قادم يُكتب اليوم بالمبلغ المدفوع.
  static Future<RecurringWrite> payNow(int id, {required int amount}) =>
      _write(() => ApiClient.dio.post<Object?>('$_base/$id/now', data: {'amount': amount}));

  static Future<RecurringWrite> confirm(int runId, {required int amount, String? note}) =>
      _write(() => ApiClient.dio.post<Object?>('$_base/runs/$runId/confirm', data: {
            'amount': amount,
            if (note != null && note.isNotEmpty) 'note': note,
          }));

  static Future<RecurringWrite> skip(int runId) => _write(() => ApiClient.dio.post<Object?>('$_base/runs/$runId/skip'));

  static Future<RecurringWrite> _write(Future<Response<Object?>> Function() call) async {
    try {
      final r = await call();
      final body = _map(r.data);
      final ok = body['success'] == true;
      final gen = body['generated'];
      return (
        ok: ok,
        message: _str(body['message']),
        code: ok ? null : _str(body['code']),
        generated: gen is List
            ? gen.whereType<Map>().map((m) => RecurringRun.fromJson(Map<String, dynamic>.from(m))).whereType<RecurringRun>().toList()
            : const <RecurringRun>[],
        run: body['run'] is Map ? RecurringRun.fromJson(_map(body['run'])) : null,
      );
    } on DioException catch (e) {
      _log('write', e);
      final d = e.response?.data;
      final m = d is Map ? Map<String, dynamic>.from(d) : const <String, dynamic>{};
      return (
        ok: false,
        message: _str(m['message']) ?? 'تعذّر الاتّصال — أعد المحاولة',
        code: _str(m['code']),
        generated: const <RecurringRun>[],
        run: null,
      );
    } catch (e) {
      _log('write', e);
      return (ok: false, message: 'تعذّر الاتّصال — أعد المحاولة', code: null, generated: const <RecurringRun>[], run: null);
    }
  }

  static void _log(String what, Object e) {
    if (kReleaseMode) return;
    debugPrint('🔴 recurring/$what: $e');
  }
}

// ─────────────── العرض ───────────────

/// 'YYYY-MM' + n شهراً.
String recurringAddMonths(String period, int n) {
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(period);
  if (m == null) return period;
  final idx = int.parse(m.group(1)!) * 12 + (int.parse(m.group(2)!) - 1) + n;
  return '${idx ~/ 12}-${((idx % 12) + 1).toString().padLeft(2, '0')}';
}

/// يوم الاستحقاق في شهر: يوم القالب أو آخر الشهر إن قصر (كالخادم).
String recurringDueDate(String period, int day) {
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(period);
  if (m == null) return '';
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final last = DateTime.utc(y, mo + 1, 0).day;
  final d = day.clamp(1, last);
  return '$period-${d.toString().padLeft(2, '0')}';
}

/// «تشرين الأوّل 2026».
String recurringPeriodLabel(String? period) {
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(period ?? '');
  if (m == null) return period ?? '';
  return '${'rexp.m${int.parse(m.group(2)!)}'.tr()} ${m.group(1)}';
}

/// «5 تشرين الأوّل 2026».
String recurringDateLabel(String? date) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(date ?? '');
  if (m == null) return date ?? '';
  return '${int.parse(m.group(3)!)} ${'rexp.m${int.parse(m.group(2)!)}'.tr()} ${m.group(1)}';
}

String recurringEveryLabel(int every) => 'rexp.every_$every'.tr();

String recurringDayLabel(int day) => day >= 31 ? 'rexp.day_last'.tr() : 'rexp.day_n'.tr(namedArgs: {'n': '$day'});

/// «كلّ شهر · يوم 1 · حتى أيّار 2027».
String recurringScheduleText({required int every, required int day, String? endPeriod}) => [
      recurringEveryLabel(every),
      recurringDayLabel(day),
      if (endPeriod != null) 'rexp.until_n'.tr(namedArgs: {'p': recurringPeriodLabel(endPeriod)}),
    ].join(' · ');

/// «تشرين الأوّل 2026 — أُضيفت تلقائيّاً».
String recurringLastText(RecurringRun r) {
  final how = switch ((r.status, r.how)) {
    ('pending', _) => 'rexp.last_pending'.tr(),
    ('skipped', 'missed') => 'rexp.last_missed'.tr(),
    ('skipped', _) => 'rexp.last_skipped'.tr(),
    (_, 'confirm') => 'rexp.last_confirmed'.tr(),
    (_, 'now') => 'rexp.last_now'.tr(),
    _ => 'rexp.last_auto'.tr(),
  };
  return '${recurringPeriodLabel(r.period)} — $how';
}
