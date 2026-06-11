import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Status of a custom debt — derived server-side from
/// (amount − sum(payments)).
enum ManagerDebtStatus {
  open,
  partial,
  paid,
}

ManagerDebtStatus _parseStatus(dynamic v) {
  switch (v?.toString().toLowerCase()) {
    case 'paid':
      return ManagerDebtStatus.paid;
    case 'partial':
      return ManagerDebtStatus.partial;
    default:
      return ManagerDebtStatus.open;
  }
}

/// One custom (parent-recorded, non-SAS4) debt against a sub-manager.
/// Mirrors v1 mobile-app/lib/models/manager_debt.dart.
class ManagerDebt {
  const ManagerDebt({
    required this.id,
    required this.parentAdminId,
    required this.debtorAdminId,
    this.parentAdminUsername,
    this.debtorAdminUsername,
    this.debtorAdminPhone,
    required this.amount,
    required this.paidAmount,
    required this.remainingAmount,
    this.note,
    required this.debtDate,
    this.lastPaymentDate,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final int parentAdminId;
  final int debtorAdminId;
  final String? parentAdminUsername;
  final String? debtorAdminUsername;
  final String? debtorAdminPhone;
  final double amount;
  final double paidAmount;
  final double remainingAmount;
  final String? note;
  final DateTime debtDate;
  final DateTime? lastPaymentDate;
  final ManagerDebtStatus status;
  final DateTime createdAt;

  bool get isClosed => status == ManagerDebtStatus.paid;

  static ManagerDebt? fromJson(Map<String, dynamic> j) {
    final id = _toInt(j['id']);
    if (id == 0) return null;
    final amount = _toDouble(j['amount']);
    final paid = _toDouble(j['paid_amount']);
    final rawRemaining = j['remaining_amount'];
    final remaining =
        rawRemaining != null ? _toDouble(rawRemaining) : (amount - paid);
    return ManagerDebt(
      id: id,
      parentAdminId: _toInt(j['parent_admin_id']),
      debtorAdminId: _toInt(j['debtor_admin_id']),
      parentAdminUsername: j['parent_admin_username']?.toString(),
      debtorAdminUsername: j['debtor_admin_username']?.toString(),
      debtorAdminPhone: j['debtor_admin_phone']?.toString(),
      amount: amount,
      paidAmount: paid,
      remainingAmount: remaining < 0 ? 0 : remaining,
      note: j['note']?.toString(),
      debtDate: _parseDate(j['debt_date']) ?? DateTime.now(),
      lastPaymentDate: _parseDate(j['last_payment_date']),
      status: _parseStatus(j['status']),
      createdAt: _parseDate(j['created_at']) ?? DateTime.now(),
    );
  }
}

/// One payment against a custom debt.
class ManagerDebtPayment {
  const ManagerDebtPayment({
    required this.id,
    required this.debtId,
    required this.amountPaid,
    this.note,
    required this.paymentDate,
    required this.createdAt,
  });

  final int id;
  final int debtId;
  final double amountPaid;
  final String? note;
  final DateTime paymentDate;
  final DateTime createdAt;

  static ManagerDebtPayment? fromJson(Map<String, dynamic> j) {
    final id = _toInt(j['id']);
    if (id == 0) return null;
    return ManagerDebtPayment(
      id: id,
      debtId: _toInt(j['debt_id']),
      amountPaid: _toDouble(j['amount_paid'] ?? j['amount']),
      note: j['note']?.toString(),
      paymentDate: _parseDate(j['payment_date']) ?? DateTime.now(),
      createdAt: _parseDate(j['created_at']) ?? DateTime.now(),
    );
  }
}

/// Aggregate totals across every custom debt under the current
/// parent admin. Used by the dashboard summary card + the
/// "ديون أخرى" badge on the manager actions sheet.
class ManagerDebtsSummary {
  const ManagerDebtsSummary({
    required this.totals,
    required this.perDebtor,
  });

  final ManagerDebtsTotals totals;
  final List<ManagerDebtsDebtorSummary> perDebtor;

  /// Convenience — pull the remaining (unpaid) total for a single
  /// sub-manager so the actions sheet can show a "ديون أخرى: X" chip
  /// without fetching the whole list.
  double remainingForDebtor(int debtorAdminId) {
    for (final row in perDebtor) {
      if (row.debtorAdminId == debtorAdminId) return row.totalRemaining;
    }
    return 0;
  }

  factory ManagerDebtsSummary.fromJson(Map<String, dynamic> j) {
    final totals = j['totals'];
    final perDebtor = j['perDebtor'];
    return ManagerDebtsSummary(
      totals: totals is Map
          ? ManagerDebtsTotals.fromJson(Map<String, dynamic>.from(totals))
          : const ManagerDebtsTotals.empty(),
      perDebtor: perDebtor is List
          ? perDebtor
              .whereType<Map>()
              .map((m) => ManagerDebtsDebtorSummary.fromJson(
                  Map<String, dynamic>.from(m)))
              .toList()
          : const [],
    );
  }
}

class ManagerDebtsTotals {
  const ManagerDebtsTotals({
    required this.debtsCount,
    required this.debtorsCount,
    required this.totalAmount,
    required this.totalPaid,
    required this.totalRemaining,
    required this.openCount,
    required this.partialCount,
    required this.paidCount,
  });

  const ManagerDebtsTotals.empty()
      : debtsCount = 0,
        debtorsCount = 0,
        totalAmount = 0,
        totalPaid = 0,
        totalRemaining = 0,
        openCount = 0,
        partialCount = 0,
        paidCount = 0;

  final int debtsCount;
  final int debtorsCount;
  final double totalAmount;
  final double totalPaid;
  final double totalRemaining;
  final int openCount;
  final int partialCount;
  final int paidCount;

  factory ManagerDebtsTotals.fromJson(Map<String, dynamic> j) =>
      ManagerDebtsTotals(
        debtsCount: _toInt(j['debts_count']),
        debtorsCount: _toInt(j['debtors_count']),
        totalAmount: _toDouble(j['total_amount']),
        totalPaid: _toDouble(j['total_paid']),
        totalRemaining: _toDouble(j['total_remaining']),
        openCount: _toInt(j['open_count']),
        partialCount: _toInt(j['partial_count']),
        paidCount: _toInt(j['paid_count']),
      );
}

class ManagerDebtsDebtorSummary {
  const ManagerDebtsDebtorSummary({
    required this.debtorAdminId,
    this.debtorAdminUsername,
    required this.debtsCount,
    required this.totalAmount,
    required this.totalPaid,
    required this.totalRemaining,
  });

  final int debtorAdminId;
  final String? debtorAdminUsername;
  final int debtsCount;
  final double totalAmount;
  final double totalPaid;
  final double totalRemaining;

  factory ManagerDebtsDebtorSummary.fromJson(Map<String, dynamic> j) =>
      ManagerDebtsDebtorSummary(
        debtorAdminId: _toInt(j['debtor_admin_id']),
        debtorAdminUsername: j['debtor_admin_username']?.toString(),
        debtsCount: _toInt(j['debts_count']),
        totalAmount: _toDouble(j['total_amount']),
        totalPaid: _toDouble(j['total_paid']),
        totalRemaining: _toDouble(j['total_remaining']),
      );
}

/// Returned by GET /api/admin/manager-debts/access — the drawer/menu
/// uses this to decide whether to show the "ديون أخرى" feature for
/// the current admin (e.g. the admin must have at least one sub-admin
/// for the feature to make sense).
class ManagerDebtsAccess {
  const ManagerDebtsAccess({
    required this.hasSubAdmins,
    required this.subAdmins,
  });

  final bool hasSubAdmins;
  final List<SubAdminRef> subAdmins;

  factory ManagerDebtsAccess.fromJson(Map<String, dynamic> j) {
    final list = j['subAdmins'];
    return ManagerDebtsAccess(
      hasSubAdmins: j['hasSubAdmins'] == true,
      subAdmins: list is List
          ? list
              .whereType<Map>()
              .map((m) => SubAdminRef.fromJson(Map<String, dynamic>.from(m)))
              .whereType<SubAdminRef>()
              .toList()
          : const [],
    );
  }
}

class SubAdminRef {
  const SubAdminRef({required this.id, required this.username, this.phone});
  final int id;
  final String username;
  final String? phone;

  static SubAdminRef? fromJson(Map<String, dynamic> j) {
    final id = _toInt(j['id']);
    final username = (j['username'] ?? '').toString();
    if (id == 0 || username.isEmpty) return null;
    return SubAdminRef(id: id, username: username, phone: j['phone']?.toString());
  }
}

/// Result of POST .../payments. Server returns the recomputed status
/// after the payment landed so the UI can flip the row from "partial"
/// to "paid" without a refetch, and `remaining` is set if the caller
/// overpaid so the sheet can warn instead of silently rounding.
class AddPaymentResult {
  const AddPaymentResult({
    required this.ok,
    this.errorMessage,
    this.status,
    this.remaining,
  });
  final bool ok;
  final String? errorMessage;
  final ManagerDebtStatus? status;
  final double? remaining;
}

class ManagerDebtsApi {
  ManagerDebtsApi._();

  /// GET /api/admin/manager-debts/access — gate the feature for
  /// admins who don't have sub-admins / don't hold the permission.
  static Future<ManagerDebtsAccess?> access() async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/admin/manager-debts/access');
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      return ManagerDebtsAccess.fromJson(Map<String, dynamic>.from(body));
    } catch (e) {
      _log('manager-debts/access', e);
      return null;
    }
  }

  /// GET /api/admin/manager-debts?status=...&debtor_admin_id=...
  /// Lists every custom debt (optionally filtered to one debtor /
  /// status range / date range).
  static Future<List<ManagerDebt>> list({
    int? debtorAdminId,
    ManagerDebtStatus? status,
    String? from,
    String? to,
  }) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/admin/manager-debts',
        queryParameters: {
          if (debtorAdminId != null) 'debtor_admin_id': debtorAdminId,
          if (status != null) 'status': status.name,
          if (from != null && from.isNotEmpty) 'from': from,
          if (to != null && to.isNotEmpty) 'to': to,
        },
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return const [];
      final list = body['debts'] ?? body['data'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((m) => ManagerDebt.fromJson(Map<String, dynamic>.from(m)))
          .whereType<ManagerDebt>()
          .toList();
    } on DioException catch (e) {
      _log('manager-debts list', e);
      return const [];
    } catch (e) {
      _log('manager-debts list', e);
      return const [];
    }
  }

  /// GET /api/admin/manager-debts/summary — totals + per-debtor
  /// breakdown. The dashboard reads totals; the actions sheet reads
  /// `perDebtor` for the badge on each card.
  static Future<ManagerDebtsSummary?> summary({
    String? from,
    String? to,
  }) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/admin/manager-debts/summary',
        queryParameters: {
          if (from != null && from.isNotEmpty) 'from': from,
          if (to != null && to.isNotEmpty) 'to': to,
        },
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      return ManagerDebtsSummary.fromJson(Map<String, dynamic>.from(body));
    } catch (e) {
      _log('manager-debts/summary', e);
      return null;
    }
  }

  /// GET /api/admin/manager-debts/:id/payments
  static Future<List<ManagerDebtPayment>> payments(int debtId) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/admin/manager-debts/$debtId/payments',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return const [];
      final list = body['payments'] ?? body['data'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((m) =>
              ManagerDebtPayment.fromJson(Map<String, dynamic>.from(m)))
          .whereType<ManagerDebtPayment>()
          .toList();
    } catch (e) {
      _log('manager-debts/$debtId/payments', e);
      return const [];
    }
  }

  /// POST /api/admin/manager-debts — create a new custom debt.
  static Future<({bool ok, String? message, int? id})> create({
    required int debtorAdminId,
    required num amount,
    String? note,
    String? debtDate,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/admin/manager-debts',
        data: {
          'debtorAdminId': debtorAdminId,
          'amount': amount,
          if (note != null && note.isNotEmpty) 'note': note,
          if (debtDate != null && debtDate.isNotEmpty) 'debtDate': debtDate,
        },
      );
      final body = r.data ?? const {};
      final rawId = body['id'] ?? body['data']?['id'];
      final id = _toInt(rawId);
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
        id: id == 0 ? null : id,
      );
    } on DioException catch (e) {
      _log('manager-debts create', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر إضافة الدين', id: null);
    } catch (e) {
      _log('manager-debts create', e);
      return (ok: false, message: 'تعذّر إضافة الدين', id: null);
    }
  }

  /// PATCH /api/admin/manager-debts/:id — partial update.
  static Future<({bool ok, String? message})> update({
    required int id,
    num? amount,
    String? note,
    String? debtDate,
  }) async {
    try {
      final r = await ApiClient.dio.patch<Map<String, dynamic>>(
        '/api/admin/manager-debts/$id',
        data: {
          if (amount != null) 'amount': amount,
          if (note != null) 'note': note,
          if (debtDate != null) 'debtDate': debtDate,
        },
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } catch (e) {
      _log('manager-debts/$id PATCH', e);
      return (ok: false, message: 'تعذّر التعديل');
    }
  }

  /// DELETE /api/admin/manager-debts/:id — cascades to payments.
  static Future<({bool ok, String? message})> delete(int debtId) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/admin/manager-debts/$debtId',
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } catch (e) {
      _log('manager-debts/$debtId DELETE', e);
      return (ok: false, message: 'تعذّر الحذف');
    }
  }

  /// POST /api/admin/manager-debts/:debtId/payments — record one
  /// payment. Returns the recomputed status so the UI can flip the
  /// row without a refetch.
  static Future<AddPaymentResult> addPayment({
    required int debtId,
    required num amountPaid,
    String? note,
    String? paymentDate,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/admin/manager-debts/$debtId/payments',
        data: {
          'amountPaid': amountPaid,
          if (note != null && note.isNotEmpty) 'note': note,
          if (paymentDate != null && paymentDate.isNotEmpty)
            'paymentDate': paymentDate,
        },
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return AddPaymentResult(
          ok: false,
          errorMessage: body['message']?.toString() ?? 'تعذّر التسديد',
          remaining: body['remaining'] != null
              ? _toDouble(body['remaining'])
              : null,
        );
      }
      return AddPaymentResult(
        ok: true,
        status: _parseStatus(body['status']),
        remaining:
            body['remaining'] != null ? _toDouble(body['remaining']) : null,
      );
    } on DioException catch (e) {
      _log('manager-debts/$debtId/payments POST', e);
      final body = e.response?.data;
      final msg = body is Map
          ? body['message']?.toString()
          : 'تعذّر التسديد';
      final remaining = body is Map && body['remaining'] != null
          ? _toDouble(body['remaining'])
          : null;
      return AddPaymentResult(
        ok: false,
        errorMessage: msg ?? 'تعذّر التسديد',
        remaining: remaining,
      );
    } catch (e) {
      _log('manager-debts/$debtId/payments POST', e);
      return const AddPaymentResult(ok: false, errorMessage: 'تعذّر التسديد');
    }
  }

  /// DELETE /api/admin/manager-debts/payments/:paymentId
  static Future<({bool ok, String? message})> deletePayment(int paymentId) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/admin/manager-debts/payments/$paymentId',
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } catch (e) {
      _log('manager-debts/payments/$paymentId DELETE', e);
      return (ok: false, message: 'تعذّر الحذف');
    }
  }

  /// POST /api/admin/manager-debts/:debtId/whatsapp — sends a reminder.
  static Future<({bool ok, String? message})> sendWhatsapp({
    required int debtId,
    String? phone,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/admin/manager-debts/$debtId/whatsapp',
        data: {
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        },
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } catch (e) {
      _log('manager-debts/$debtId/whatsapp', e);
      return (ok: false, message: 'تعذّر الإرسال');
    }
  }

  /// GET /api/admin/my-debts — debts owed BY the current admin
  /// (sub-admin view). Read-only.
  static Future<List<ManagerDebt>> myDebts() async {
    try {
      final r =
          await ApiClient.dio.get<Map<String, dynamic>>('/api/admin/my-debts');
      final body = r.data ?? const {};
      if (body['success'] != true) return const [];
      final list = body['debts'] ?? body['data'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((m) => ManagerDebt.fromJson(Map<String, dynamic>.from(m)))
          .whereType<ManagerDebt>()
          .toList();
    } catch (e) {
      _log('my-debts', e);
      return const [];
    }
  }

  static void _log(String endpoint, Object err) {
    if (kReleaseMode) return;
    if (err is DioException) {
      debugPrint(
        '🔴 $endpoint: status=${err.response?.statusCode} body=${err.response?.data}',
      );
    } else {
      debugPrint('🔴 $endpoint: $err');
    }
  }
}

// =====================
// Local helpers
// =====================

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double _toDouble(dynamic v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}
