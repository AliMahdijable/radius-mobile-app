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
    final id = int.tryParse(j['id']?.toString() ?? '');
    final at = j['action_type']?.toString();
    final ts = j['created_at']?.toString();
    if (id == null || at == null || ts == null) return null;
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
    final id = int.tryParse(j['id']?.toString() ?? '');
    final at = j['action_type']?.toString();
    final ts = j['created_at']?.toString();
    if (id == null || at == null || ts == null) return null;
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
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.startedAt,
    this.endedAt,
  });
  final int id;
  final String? username;
  final String? userManager;
  final String? ipAddress;
  final num bytesIn;
  final num bytesOut;
  final String? startedAt;
  final String? endedAt;

  bool get isOnline => endedAt == null || endedAt!.isEmpty;

  static SessionRow? fromJson(Map<String, dynamic> j) {
    final id = int.tryParse(j['id']?.toString() ?? '');
    if (id == null) return null;
    return SessionRow(
      id: id,
      username: j['username']?.toString(),
      userManager: j['user_manager']?.toString(),
      ipAddress: j['ip_address']?.toString() ?? j['ip']?.toString(),
      bytesIn: FinanceKPIs._n(j['bytes_in'] ?? j['acctinputoctets']),
      bytesOut: FinanceKPIs._n(j['bytes_out'] ?? j['acctoutputoctets']),
      startedAt: j['started_at']?.toString() ?? j['acctstarttime']?.toString(),
      endedAt: j['ended_at']?.toString() ?? j['acctstoptime']?.toString(),
    );
  }
}

class ReportsApi {
  ReportsApi._();

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// التقرير المالي — KPIs + آخر السجلات.
  /// dateFrom/dateTo بصيغة YYYY-MM-DD. لو فاضي يرجع الـbackend الافتراضي.
  static Future<({bool ok, FinanceReport? data, String? error})> finance({
    DateTime? from,
    DateTime? to,
    int recentLimit = 50,
  }) async {
    try {
      final qp = <String, String>{
        'limit_logs': '$recentLimit',
        if (from != null) 'date_from': _date(from),
        if (to != null) 'date_to': _date(to),
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
  /// actionType: فلتر اختياري (مثلاً 'SUBSCRIBER_ACTIVATE'). فاضي = الكل.
  static Future<({bool ok, List<ActivityRow> rows, String? error})> activities({
    DateTime? from,
    DateTime? to,
    String? actionType,
    String? search,
    int limit = 200,
  }) async {
    try {
      final qp = <String, String>{
        'limit': '$limit',
        if (from != null) 'date_from': _date(from),
        if (to != null) 'date_to': _date(to),
        if (actionType != null && actionType.isNotEmpty)
          'action_type': actionType,
        if (search != null && search.isNotEmpty) 'search': search,
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

  /// التفعيلات اليومية — مُجمَّعة حسب اليوم.
  static Future<({bool ok, List<DailyActivationRow> rows, String? error})>
      dailyActivations({DateTime? from, DateTime? to}) async {
    try {
      final qp = <String, String>{
        if (from != null) 'date_from': _date(from),
        if (to != null) 'date_to': _date(to),
      };
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/activations/daily',
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
      return (
        ok: true,
        rows: list
            .whereType<Map>()
            .map((m) =>
                DailyActivationRow.fromJson(Map<String, dynamic>.from(m)))
            .whereType<DailyActivationRow>()
            .toList(),
        error: null,
      );
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
  static Future<({bool ok, List<SessionRow> rows, String? error})> sessions({
    bool onlineOnly = false,
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async {
    try {
      final qp = <String, String>{
        'limit': '$limit',
        if (onlineOnly) 'status': 'online',
        if (from != null) 'date_from': _date(from),
        if (to != null) 'date_to': _date(to),
      };
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/sessions',
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
