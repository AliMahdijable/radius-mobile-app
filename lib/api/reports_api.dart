import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// ============================================================
/// Reports API — موحّد لكل التقارير الـ8 في v2 web:
///   • financial — /api/reports/finance
///   • activations / daily_activations — /api/activities
///   • activity_log — /api/activities (filter شامل)
///   • sessions — /api/v2/sessions
///   • account_statement — /api/reports/account-statement
///   • expenses + manager_debts — الـAPIs الموجودة أصلاً في
///     expenses_api / manager_debts_api، نُحيل لها (لا duplication).
///
/// كل دالة ترجع record مع `ok` + الـdata + رسالة خطأ ودودة. الـUI
/// يعرض إما الـdata أو الخطأ. لا exception trapping يدوي.
/// ============================================================

// ─────────── Financial ───────────

class FinanceKPIs {
  const FinanceKPIs({
    this.paymentsSum = 0,
    this.debtPaySum = 0,
    this.balanceDeductSum = 0,
    this.activateCashSum = 0,
    this.balanceAddSum = 0,
    this.activateNonCashSum = 0,
    this.expensesSum = 0,
    this.expensesCount = 0,
    this.managerDebtsOutstanding = 0,
    this.activationsCount = 0,
    this.extendCount = 0,
  });
  final num paymentsSum;
  final num debtPaySum;
  final num balanceDeductSum;
  final num activateCashSum;
  final num balanceAddSum;
  final num activateNonCashSum;
  final num expensesSum;
  final int expensesCount;
  final num managerDebtsOutstanding;
  final int activationsCount;
  final int extendCount;

  static num _n(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
  static int _i(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

  /// إيراد نقدي حقيقي = activate_cash + debt_pay + balance_deduct
  /// (مطابق Financial.tsx). balance_add يدخل debt — لا revenue.
  num get totalCashRevenue =>
      activateCashSum + debtPaySum + balanceDeductSum;
  num get netCash => totalCashRevenue - expensesSum;

  static FinanceKPIs fromJson(Map<String, dynamic> j) {
    return FinanceKPIs(
      paymentsSum: _n(j['payments_sum']),
      debtPaySum: _n(j['debt_pay_sum']),
      balanceDeductSum: _n(j['balance_deduct_sum']),
      activateCashSum: _n(j['activate_cash_sum']),
      balanceAddSum: _n(j['balance_add_sum']),
      activateNonCashSum: _n(j['activate_non_cash_sum']),
      expensesSum: _n(j['expenses_sum']),
      expensesCount: _i(j['expenses_count']),
      managerDebtsOutstanding: _n(j['manager_debts_outstanding']),
      activationsCount: _i(j['activations_count']),
      extendCount: _i(j['extend_count']),
    );
  }
}

class FinanceLog {
  const FinanceLog({
    required this.id,
    required this.actionType,
    this.actionDescription,
    this.amount = 0,
    this.adminUsername,
    this.actingEmployeeFullName,
    this.actingEmployeeUsername,
    this.userUsername,
    this.userManager,
    this.targetName,
    required this.createdAt,
  });
  final int id;
  final String actionType;
  final String? actionDescription;
  final num amount;
  final String? adminUsername;
  final String? actingEmployeeFullName;
  final String? actingEmployeeUsername;
  final String? userUsername;
  final String? userManager;
  final String? targetName;
  final String createdAt;

  static FinanceLog? fromJson(Map<String, dynamic> j) {
    // backend `/api/reports/finance` يحقن صفوف صناعية بمعرّفات نصّية
    // (id: "expense_5"، "mdebt_12"). لا نرفضها — نصنع hash id من الـstring.
    // ملاحظة: كنّا نرفضها بـint.tryParse فتختفي الصرفيات من قائمة "آخر
    // الحركات" رغم أن counters "# مصاريف" في KPIs تعمل صح (bug 2026-07-10).
    final at = j['action_type']?.toString();
    final ts = j['created_at']?.toString();
    if (at == null || ts == null) return null;
    final rawId = j['id']?.toString() ?? '';
    final id = int.tryParse(rawId) ?? rawId.hashCode.abs();
    return FinanceLog(
      id: id,
      actionType: at,
      actionDescription: j['action_description']?.toString(),
      amount: FinanceKPIs._n(j['amount']),
      adminUsername: j['admin_username']?.toString(),
      actingEmployeeFullName: j['acting_employee_full_name']?.toString(),
      actingEmployeeUsername: j['acting_employee_username']?.toString(),
      userUsername: j['user_username']?.toString(),
      userManager: j['user_manager']?.toString(),
      targetName: j['target_name']?.toString(),
      createdAt: ts,
    );
  }
}

class FinanceReport {
  const FinanceReport({required this.kpis, required this.recentLogs});
  final FinanceKPIs kpis;
  final List<FinanceLog> recentLogs;
}

// ─────────── Activities (Activations + ActivityLog) ───────────

class ActivityRow {
  const ActivityRow({
    required this.id,
    required this.actionType,
    this.actionDescription,
    this.amount = 0,
    this.adminUsername,
    this.actingEmployeeFullName,
    this.userUsername,
    this.targetName,
    required this.createdAt,
  });
  final int id;
  final String actionType;
  final String? actionDescription;
  final num amount;
  final String? adminUsername;
  final String? actingEmployeeFullName;
  final String? userUsername;
  final String? targetName;
  final String createdAt;

  static ActivityRow? fromJson(Map<String, dynamic> j) {
    // نتقبّل معرّفات نصّية (مثل "expense_5") ونصنع hash لها. مطابق منطق
    // FinanceLog.fromJson (bug 2026-07-10: الصفوف الصناعية بمعرّف نصّي
    // كانت تُرفض).
    final at = j['action_type']?.toString();
    final ts = j['created_at']?.toString();
    if (at == null || ts == null) return null;
    final rawId = j['id']?.toString() ?? '';
    final id = int.tryParse(rawId) ?? rawId.hashCode.abs();
    return ActivityRow(
      id: id,
      actionType: at,
      actionDescription: j['action_description']?.toString(),
      amount: FinanceKPIs._n(j['amount']),
      adminUsername: j['admin_username']?.toString(),
      actingEmployeeFullName: j['acting_employee_full_name']?.toString(),
      userUsername: j['user_username']?.toString(),
      targetName: j['target_name']?.toString(),
      createdAt: ts,
    );
  }
}

// ─────────── Daily Activations ───────────

class DailyActivationRow {
  const DailyActivationRow({
    required this.day,
    required this.count,
    required this.cashSum,
    required this.nonCashCount,
  });
  final String day;
  final int count;
  final num cashSum;
  final int nonCashCount;

  static DailyActivationRow? fromJson(Map<String, dynamic> j) {
    final day = j['day']?.toString();
    if (day == null) return null;
    return DailyActivationRow(
      day: day,
      count: FinanceKPIs._i(j['count']),
      cashSum: FinanceKPIs._n(j['cash_sum']),
      nonCashCount: FinanceKPIs._i(j['non_cash_count']),
    );
  }
}

// ─────────── Sessions ───────────

class SessionRow {
  const SessionRow({
    required this.id,
    this.username,
    this.userManager,
    this.ipAddress,
    this.mac,
    this.device,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.startedAt,
    this.endedAt,
    this.sessionTime,
    this.isOnlineOverride,
  });
  final int id;
  final String? username;
  final String? userManager;
  final String? ipAddress;
  final String? mac;
  final String? device;
  final num bytesIn;
  final num bytesOut;
  final String? startedAt;
  final String? endedAt;
  final num? sessionTime;
  final bool? isOnlineOverride;

  bool get isOnline =>
      isOnlineOverride ?? (endedAt == null || endedAt!.isEmpty);

  static SessionRow? fromJson(Map<String, dynamic> j) {
    // نمطان محتملان:
    //  (1) /api/v2/sessions (historical): radacctid + framedipaddress + callingstationid + acctstarttime/acctstoptime
    //  (2) /api/v2/online-users (live): بدون id، ip/mac/session_time مباشرة
    final id = int.tryParse(j['id']?.toString() ?? '') ??
        int.tryParse(j['radacctid']?.toString() ?? '');
    // لو ما ملقينا id، نصنع hash من username+mac كـfallback عشان
    // ما نرفض صف online-users. الـid يستعمل بس داخل الـUI.
    final username = j['username']?.toString();
    final ip = j['ip_address']?.toString() ??
        j['ip']?.toString() ??
        j['framedipaddress']?.toString();
    final mac = j['mac']?.toString() ?? j['callingstationid']?.toString();
    if (id == null && (username == null || username.isEmpty)) return null;
    final finalId = id ?? '$username|$mac'.hashCode.abs();
    final st = j['session_time'];
    final sessionTime = st is num
        ? st
        : (st != null ? num.tryParse(st.toString()) : null);
    // online-users ما فيه endedAt — نضبطها = null، والـisOnline يعتمد
    // على المصدر (لو مافيه radacctid عادة يعني /online-users).
    final endedAt =
        j['ended_at']?.toString() ?? j['acctstoptime']?.toString();
    final isOnlineOverride = id == null && endedAt == null ? true : null;
    return SessionRow(
      id: finalId,
      username: username,
      userManager: j['user_manager']?.toString() ??
          j['manager']?.toString() ??
          j['parent']?.toString(),
      ipAddress: ip,
      mac: (mac != null && mac.isNotEmpty) ? mac : null,
      device: j['device']?.toString() ?? j['oui']?.toString(),
      bytesIn: FinanceKPIs._n(
          j['bytes_in'] ?? j['download_bytes'] ?? j['acctinputoctets']),
      bytesOut: FinanceKPIs._n(
          j['bytes_out'] ?? j['upload_bytes'] ?? j['acctoutputoctets']),
      startedAt:
          j['started_at']?.toString() ?? j['acctstarttime']?.toString(),
      endedAt: endedAt,
      sessionTime: sessionTime,
      isOnlineOverride: isOnlineOverride,
    );
  }
}

class ReportsApi {
  ReportsApi._();

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// التقرير المالي — KPIs + آخر السجلات.
  /// dateFrom/dateTo بصيغة YYYY-MM-DD. لو فاضي يرجع الـbackend الافتراضي.
  /// userIds — قائمة IDs المدراء المرشّحين (المدير الحالي + الفرعيين). لو
  /// فاضي يرجع الـbackend كل المدراء (سلوك خطأ للمدير العادي).
  static Future<({bool ok, FinanceReport? data, String? error})> finance({
    DateTime? from,
    DateTime? to,
    int recentLimit = 50,
    List<String>? userIds,
  }) async {
    try {
      final qp = <String, String>{
        'limit_logs': '$recentLimit',
        if (from != null) 'date_from': _date(from),
        if (to != null) 'date_to': _date(to),
        if (userIds != null && userIds.isNotEmpty)
          'user_ids': userIds.where((id) => id.isNotEmpty).join(','),
      };
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/reports/finance',
        queryParameters: qp,
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (ok: false, data: null, error: body['message']?.toString());
      }
      final data = body['data'];
      if (data is! Map) return (ok: false, data: null, error: 'تنسيق غير متوقع');
      final kpisRaw = data['kpis'];
      final logsRaw = data['recentLogs'];
      final kpis = kpisRaw is Map
          ? FinanceKPIs.fromJson(Map<String, dynamic>.from(kpisRaw))
          : const FinanceKPIs();
      final logs = (logsRaw is List)
          ? logsRaw
              .whereType<Map>()
              .map((m) => FinanceLog.fromJson(Map<String, dynamic>.from(m)))
              .whereType<FinanceLog>()
              .toList()
          : const <FinanceLog>[];
      return (
        ok: true,
        data: FinanceReport(kpis: kpis, recentLogs: logs),
        error: null,
      );
    } on DioException catch (e) {
      _log('finance', e);
      return (ok: false, data: null, error: _friendly(e));
    } catch (e) {
      _log('finance', e);
      return (ok: false, data: null, error: 'تعذّر تحميل التقرير');
    }
  }

  /// قائمة activities — يستعمل للـActivations + ActivityLog.
  /// activityType: فلتر اختياري (مثلاً 'SUBSCRIBER_ACTIVATE'). فاضي = الكل.
  /// backend يقبل واحد فقط — للفلترة على أكثر من نوع اجلب الكل وفلتر client-side.
  /// userIds — قائمة IDs المدراء المرشّحين. لو فاضي يرجع الكل (خطأ للمدير العادي).
  static Future<({bool ok, List<ActivityRow> rows, String? error})> activities({
    DateTime? from,
    DateTime? to,
    String? activityType,
    String? search,
    List<String>? userIds,
    int limit = 200,
  }) async {
    try {
      final qp = <String, String>{
        'limit': '$limit',
        if (from != null) 'date_from': _date(from),
        if (to != null) 'date_to': _date(to),
        if (activityType != null && activityType.isNotEmpty)
          'activity_type': activityType,
        if (search != null && search.isNotEmpty) 'search': search,
        if (userIds != null && userIds.isNotEmpty)
          'user_ids': userIds.where((id) => id.isNotEmpty).join(','),
      };
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/activities',
        queryParameters: qp,
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          ok: false,
          rows: const <ActivityRow>[],
          error: body['message']?.toString(),
        );
      }
      final list = body['data'];
      if (list is! List) return (ok: true, rows: const <ActivityRow>[], error: null);
      return (
        ok: true,
        rows: list
            .whereType<Map>()
            .map((m) => ActivityRow.fromJson(Map<String, dynamic>.from(m)))
            .whereType<ActivityRow>()
            .toList(),
        error: null,
      );
    } on DioException catch (e) {
      _log('activities', e);
      return (ok: false, rows: const <ActivityRow>[], error: _friendly(e));
    } catch (e) {
      _log('activities', e);
      return (ok: false, rows: const <ActivityRow>[], error: 'تعذّر التحميل');
    }
  }

  /// التفعيلات اليومية — مُجمَّعة حسب اليوم عبر الفترة.
  ///
  /// backend `/api/activities/daily-activations` يرجع "اليوم فقط" (ليس
  /// مُجمَّعاً لفترة). فنستخدم `/api/activities` مع فلتر تفعيلات +
  /// نُجمّع محلياً حسب تاريخ اليوم.
  static Future<({bool ok, List<DailyActivationRow> rows, String? error})>
      dailyActivations({
    DateTime? from,
    DateTime? to,
    List<String>? userIds,
  }) async {
    try {
      final qp = <String, String>{
        'limit': '5000',
        if (from != null) 'date_from': _date(from),
        if (to != null) 'date_to': _date(to),
        if (userIds != null && userIds.isNotEmpty)
          'user_ids': userIds.where((id) => id.isNotEmpty).join(','),
      };
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/activities',
        queryParameters: qp,
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          ok: false,
          rows: const <DailyActivationRow>[],
          error: body['message']?.toString(),
        );
      }
      final list = body['data'];
      if (list is! List) {
        return (ok: true, rows: const <DailyActivationRow>[], error: null);
      }
      // نفلتر ونجمّع محلياً حسب اليوم.
      final byDay = <String, ({int cash, int nonCash, num cashSum})>{};
      for (final row in list) {
        if (row is! Map) continue;
        final at = (row['action_type']?.toString() ?? '').toUpperCase().trim();
        final desc = (row['action_description']?.toString() ?? '').toLowerCase();
        final isActivate = at == 'SUBSCRIBER_ACTIVATE' ||
            (at == 'SUBSCRIBER_ADD' && desc.contains('تفعيل'));
        if (!isActivate) continue;
        final ts = row['created_at']?.toString();
        if (ts == null || ts.length < 10) continue;
        final day = ts.substring(0, 10); // YYYY-MM-DD
        final isCash =
            desc.contains('نقدي') && !desc.contains('غير نقدي');
        num amount = 0;
        // نجرّب استخراج المبلغ من action_data (JSON string) → ثم من الوصف.
        final dataRaw = row['action_data'];
        if (dataRaw is String && dataRaw.isNotEmpty) {
          try {
            final map = jsonDecode(dataRaw);
            if (map is Map) {
              final v = map['final_price'] ??
                  map['partial_cash_amount'] ??
                  map['amount'] ??
                  map['price'] ??
                  map['user_price'] ??
                  0;
              amount = v is num ? v : num.tryParse(v.toString()) ?? 0;
            }
          } catch (_) {}
        } else if (dataRaw is Map) {
          final v = dataRaw['final_price'] ??
              dataRaw['partial_cash_amount'] ??
              dataRaw['amount'] ??
              dataRaw['price'] ??
              dataRaw['user_price'] ??
              0;
          amount = v is num ? v : num.tryParse(v.toString()) ?? 0;
        }
        if (amount == 0) {
          final m = RegExp(r'IQD\s*([0-9][0-9,]*)').firstMatch(desc);
          if (m != null) {
            amount = num.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0;
          }
        }
        final prev = byDay[day] ?? (cash: 0, nonCash: 0, cashSum: 0);
        byDay[day] = (
          cash: prev.cash + (isCash ? 1 : 0),
          nonCash: prev.nonCash + (isCash ? 0 : 1),
          cashSum: prev.cashSum + (isCash ? amount : 0),
        );
      }
      final rows = byDay.entries
          .map((e) => DailyActivationRow(
                day: e.key,
                count: e.value.cash,
                cashSum: e.value.cashSum,
                nonCashCount: e.value.nonCash,
              ))
          .toList()
        ..sort((a, b) => b.day.compareTo(a.day));
      return (ok: true, rows: rows, error: null);
    } on DioException catch (e) {
      _log('daily activations', e);
      return (
        ok: false,
        rows: const <DailyActivationRow>[],
        error: _friendly(e),
      );
    } catch (e) {
      _log('daily activations', e);
      return (
        ok: false,
        rows: const <DailyActivationRow>[],
        error: 'تعذّر التحميل',
      );
    }
  }

  /// الجلسات الحالية + التاريخية (filter بـonlineOnly).
  /// search: filter عام (SAS4 يفهمه). أو تعطي username/ip/mac منفردين.
  static Future<({bool ok, List<SessionRow> rows, String? error})> sessions({
    bool onlineOnly = false,
    DateTime? from,
    DateTime? to,
    String? search,
    String? username,
    String? ip,
    String? mac,
    int limit = 200,
  }) async {
    try {
      final qp = <String, String>{
        'count': '$limit',
        'page': '1',
        if (from != null) 'from': _date(from),
        if (to != null) 'to': _date(to),
        if (search != null && search.isNotEmpty) 'search': search,
        if (username != null && username.isNotEmpty) 'username': username,
        if (ip != null && ip.isNotEmpty) 'ip': ip,
        if (mac != null && mac.isNotEmpty) 'mac': mac,
      };
      final endpoint =
          onlineOnly ? '/api/v2/online-users' : '/api/v2/sessions';
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        endpoint,
        queryParameters: qp,
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          ok: false,
          rows: const <SessionRow>[],
          error: body['message']?.toString(),
        );
      }
      final list = body['data'];
      if (list is! List) return (ok: true, rows: const <SessionRow>[], error: null);
      return (
        ok: true,
        rows: list
            .whereType<Map>()
            .map((m) => SessionRow.fromJson(Map<String, dynamic>.from(m)))
            .whereType<SessionRow>()
            .toList(),
        error: null,
      );
    } on DioException catch (e) {
      _log('sessions', e);
      return (ok: false, rows: const <SessionRow>[], error: _friendly(e));
    } catch (e) {
      _log('sessions', e);
      return (ok: false, rows: const <SessionRow>[], error: 'تعذّر التحميل');
    }
  }

  static String _friendly(DioException e) {
    final code = e.response?.statusCode ?? 0;
    if (code == 403) return 'لا تملك صلاحية لهذا التقرير';
    if (code == 401) return 'انتهت الجلسة';
    return 'تعذّر التحميل';
  }

  static void _log(String endpoint, Object err) {
    if (kReleaseMode) return;
    if (err is DioException) {
      debugPrint(
        '🔴 reports $endpoint: status=${err.response?.statusCode} body=${err.response?.data}',
      );
    } else {
      debugPrint('🔴 reports $endpoint: $err');
    }
  }
}
