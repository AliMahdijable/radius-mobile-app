import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// واحد من الديون الخارجية المُسجَّلة على مدير فرعي. مطابق v1
/// ManagerDebt model (mobile-app/lib/providers/manager_debts_provider.dart).
class ManagerDebt {
  const ManagerDebt({
    required this.id,
    required this.debtorAdminId,
    required this.debtorUsername,
    required this.amount,
    required this.paidAmount,
    this.note,
    this.debtDate,
    this.createdAt,
  });
  final int id;
  final int debtorAdminId;
  final String debtorUsername;
  final num amount;
  final num paidAmount;
  final String? note;
  final String? debtDate;
  final String? createdAt;

  num get remaining {
    final r = amount - paidAmount;
    return r < 0 ? 0 : r;
  }

  bool get isClosed => remaining <= 0;

  static ManagerDebt? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final idInt = id is int ? id : int.tryParse(id?.toString() ?? '');
    if (idInt == null) return null;
    num? toNum(dynamic v) =>
        v is num ? v : (v == null ? null : num.tryParse(v.toString()));
    int? toInt(dynamic v) =>
        v is int ? v : (v == null ? null : int.tryParse(v.toString()));
    return ManagerDebt(
      id: idInt,
      debtorAdminId: toInt(j['debtor_admin_id']) ?? 0,
      debtorUsername: (j['debtor_admin_username'] ?? '').toString(),
      amount: toNum(j['amount']) ?? 0,
      paidAmount: toNum(j['paid_amount']) ?? 0,
      note: j['note']?.toString(),
      debtDate: j['debt_date']?.toString(),
      createdAt: j['created_at']?.toString(),
    );
  }
}

/// تسديد دين خارجي. مطابق v1 ManagerDebtPayment.
class ManagerDebtPayment {
  const ManagerDebtPayment({
    required this.id,
    required this.amount,
    this.note,
    this.paymentDate,
    this.createdAt,
  });
  final int id;
  final num amount;
  final String? note;
  final String? paymentDate;
  final String? createdAt;

  static ManagerDebtPayment? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final idInt = id is int ? id : int.tryParse(id?.toString() ?? '');
    if (idInt == null) return null;
    num? toNum(dynamic v) =>
        v is num ? v : (v == null ? null : num.tryParse(v.toString()));
    return ManagerDebtPayment(
      id: idInt,
      amount: toNum(j['amount']) ?? 0,
      note: j['note']?.toString(),
      paymentDate: j['payment_date']?.toString(),
      createdAt: j['created_at']?.toString(),
    );
  }
}

/// Summary خفيف لكل مدير: مجموع الديون + ما تبقى مفتوحاً. يُستعمل
/// في الـActions Sheet عشان نظهر "ديون أخرى: X" badge قبل ما المدير
/// يدخل لشاشة التفاصيل.
class ManagerDebtSummary {
  const ManagerDebtSummary({
    required this.debtorAdminId,
    required this.totalOwed,
    required this.totalPaid,
  });
  final int debtorAdminId;
  final num totalOwed;
  final num totalPaid;

  num get remaining {
    final r = totalOwed - totalPaid;
    return r < 0 ? 0 : r;
  }
}

class ManagerDebtsApi {
  ManagerDebtsApi._();

  /// GET /api/admin/manager-debts/access — يرجّع true لو المدير عنده
  /// صلاحية على المديول. الـscreen يستعملها عشان يخفي الـUI لو
  /// السوبر ادمن يرفض.
  static Future<bool> hasAccess() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/admin/manager-debts/access',
      );
      final body = r.data ?? const {};
      return body['success'] == true && body['access'] == true;
    } catch (_) {
      return false;
    }
  }

  /// GET /api/admin/manager-debts?debtor_admin_id=X — ديون مدير محدد.
  static Future<List<ManagerDebt>> listForManager(int debtorAdminId) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/admin/manager-debts',
        queryParameters: {'debtor_admin_id': debtorAdminId},
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
      _log('manager-debts list/$debtorAdminId', e);
      return const [];
    } catch (e) {
      _log('manager-debts list/$debtorAdminId', e);
      return const [];
    }
  }

  /// GET /api/admin/manager-debts/summary — مجاميع لكل مدير.
  /// مفيد للـActions Sheet لعرض badge "ديون أخرى: X".
  static Future<Map<int, ManagerDebtSummary>> summary() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/admin/manager-debts/summary',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return const {};
      final list = body['summary'] ?? body['data'];
      if (list is! List) return const {};
      final out = <int, ManagerDebtSummary>{};
      for (final row in list) {
        if (row is! Map) continue;
        final idRaw = row['debtor_admin_id'];
        final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');
        if (id == null) continue;
        num toN(dynamic v) =>
            v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
        out[id] = ManagerDebtSummary(
          debtorAdminId: id,
          totalOwed: toN(row['total_owed'] ?? row['amount']),
          totalPaid: toN(row['total_paid'] ?? row['paid_amount']),
        );
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// POST /api/admin/manager-debts — أضف دين جديد على المدير.
  static Future<({bool ok, String? message, int? id})> create({
    required int debtorAdminId,
    required num amount,
    String? note,
    String? debtDate,
    String? phone,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/admin/manager-debts',
        data: {
          'debtorAdminId': debtorAdminId,
          'amount': amount,
          if (note != null && note.isNotEmpty) 'note': note,
          if (debtDate != null && debtDate.isNotEmpty) 'debtDate': debtDate,
          if (phone != null && phone.isNotEmpty) 'debtorPhone': phone,
        },
      );
      final body = r.data ?? const {};
      final rawId = body['id'] ?? body['data']?['id'];
      final id =
          rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
        id: id,
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

  /// DELETE /api/admin/manager-debts/:id
  static Future<({bool ok, String? message})> delete(int debtId) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/admin/manager-debts/$debtId',
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString()
      );
    } catch (e) {
      _log('manager-debts delete', e);
      return (ok: false, message: 'تعذّر الحذف');
    }
  }

  /// GET /api/admin/manager-debts/:id/payments
  static Future<List<ManagerDebtPayment>> listPayments(int debtId) async {
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
    } catch (_) {
      return const [];
    }
  }

  /// POST /api/admin/manager-debts/:id/payments — أضف تسديد جزئي/كلي.
  static Future<({bool ok, String? message, int? id})> addPayment({
    required int debtId,
    required num amount,
    String? note,
    String? paymentDate,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/admin/manager-debts/$debtId/payments',
        data: {
          'amount': amount,
          if (note != null && note.isNotEmpty) 'note': note,
          if (paymentDate != null && paymentDate.isNotEmpty)
            'paymentDate': paymentDate,
        },
      );
      final body = r.data ?? const {};
      final rawId = body['id'] ?? body['data']?['id'];
      final id =
          rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
        id: id,
      );
    } on DioException catch (e) {
      _log('manager-debts/$debtId/payments POST', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر التسديد', id: null);
    } catch (e) {
      _log('manager-debts/$debtId/payments POST', e);
      return (ok: false, message: 'تعذّر التسديد', id: null);
    }
  }

  /// DELETE /api/admin/manager-debts/payments/:paymentId — حذف تسديد.
  static Future<({bool ok, String? message})> deletePayment(int paymentId) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/admin/manager-debts/payments/$paymentId',
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString()
      );
    } catch (e) {
      _log('manager-debts/payments delete', e);
      return (ok: false, message: 'تعذّر الحذف');
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
