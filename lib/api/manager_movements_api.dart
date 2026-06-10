import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// نوع الحركة المالية على المدير. يطابق v1 manager_movements_provider.
enum MovementKind {
  depositCash('شحن نقدي'),
  depositLoan('إيداع آجل'),
  withdraw('سحب'),
  sasPayDebt('تسديد دين SAS'),
  addPoints('إضافة نقاط'),
  debtCreated('إضافة دين'),
  debtPayment('تسديد دين خارجي'),
  unknown('حركة');

  const MovementKind(this.label);
  final String label;
}

class ManagerMovement {
  const ManagerMovement({
    required this.id,
    required this.kind,
    required this.amount,
    this.note,
    this.createdAt,
    this.actorUsername,
  });
  final int id;
  final MovementKind kind;
  final num amount;
  final String? note;
  final String? createdAt;
  final String? actorUsername;

  /// إشارة الـamount: + للزيادة في رصيد المدير، - للنقص.
  bool get isCredit =>
      kind == MovementKind.depositCash ||
      kind == MovementKind.addPoints ||
      kind == MovementKind.debtPayment;

  static MovementKind _resolveKind(String? raw) {
    switch (raw) {
      case 'deposit_cash':
      case 'cash_deposit':
        return MovementKind.depositCash;
      case 'deposit_loan':
      case 'loan_deposit':
        return MovementKind.depositLoan;
      case 'withdraw':
        return MovementKind.withdraw;
      case 'sas_pay_debt':
      case 'pay_debt':
        return MovementKind.sasPayDebt;
      case 'add_points':
      case 'points':
        return MovementKind.addPoints;
      case 'debt_created':
        return MovementKind.debtCreated;
      case 'debt_payment':
        return MovementKind.debtPayment;
      default:
        return MovementKind.unknown;
    }
  }

  static ManagerMovement? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final idInt = id is int ? id : int.tryParse(id?.toString() ?? '');
    if (idInt == null) return null;
    num? toNum(dynamic v) =>
        v is num ? v : (v == null ? null : num.tryParse(v.toString()));
    return ManagerMovement(
      id: idInt,
      kind: _resolveKind(
          (j['kind'] ?? j['type'] ?? j['manager_action'] ?? j['action_type'])
              ?.toString()),
      amount: toNum(j['amount']) ?? 0,
      note: (j['note'] ?? j['comment'] ?? j['description'])?.toString(),
      createdAt: j['created_at']?.toString(),
      actorUsername: (j['admin_username'] ?? j['actor_username'])
          ?.toString(),
    );
  }
}

class ManagerMovementsApi {
  ManagerMovementsApi._();

  /// GET /api/admin/managers/:targetAdminId/movements
  static Future<List<ManagerMovement>> list(int targetAdminId,
      {int limit = 200}) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/admin/managers/$targetAdminId/movements',
        queryParameters: {'limit': limit},
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return const [];
      final list = body['movements'] ?? body['data'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((m) => ManagerMovement.fromJson(Map<String, dynamic>.from(m)))
          .whereType<ManagerMovement>()
          .toList();
    } on DioException catch (e) {
      _log('manager-movements list/$targetAdminId', e);
      return const [];
    } catch (e) {
      _log('manager-movements list/$targetAdminId', e);
      return const [];
    }
  }

  /// DELETE /api/admin/manager-movements/:id — يحذف حركة من سجل
  /// التدقيق (لا يعكس العملية في SAS4 — فقط حذف من تاريخ التطبيق).
  static Future<({bool ok, String? message})> delete(int id) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/admin/manager-movements/$id',
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
      );
    } catch (e) {
      _log('manager-movements delete/$id', e);
      return (ok: false, message: 'تعذّر الحذف');
    }
  }

  static void _log(String endpoint, Object err) {
    if (kReleaseMode) return;
    if (err is DioException) {
      debugPrint(
          '🔴 $endpoint: status=${err.response?.statusCode} body=${err.response?.data}');
    } else {
      debugPrint('🔴 $endpoint: $err');
    }
  }
}
