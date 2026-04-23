import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/dio_client.dart';
import '../models/manager_debt.dart';
import '../models/manager_debt_payment.dart';

/// Access check — tells the drawer whether to render "ديون المدراء".
/// Cached briefly because the drawer is built on every push.
final managerDebtsAccessProvider =
    FutureProvider.autoDispose<ManagerDebtsAccess>((ref) async {
  ref.keepAlive();
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.get('/api/admin/manager-debts/access');
    final data = res.data;
    if (data is! Map || data['success'] != true) return ManagerDebtsAccess.none;
    return ManagerDebtsAccess.fromJson(Map<String, dynamic>.from(data));
  } catch (_) {
    return ManagerDebtsAccess.none;
  }
});

class DebtsFilterArgs {
  final String? status; // null | 'open' | 'partial' | 'paid'
  final int? debtorAdminId;
  final DateTime? from;
  final DateTime? to;
  const DebtsFilterArgs({this.status, this.debtorAdminId, this.from, this.to});

  @override
  bool operator ==(Object o) =>
      identical(this, o) ||
      (o is DebtsFilterArgs &&
          o.status == status &&
          o.debtorAdminId == debtorAdminId &&
          o.from == from &&
          o.to == to);

  @override
  int get hashCode => Object.hash(status, debtorAdminId, from, to);
}

/// List of debts the current user is owed (parent admin view).
final managerDebtsListProvider =
    FutureProvider.family.autoDispose<List<ManagerDebt>, DebtsFilterArgs>(
        (ref, args) async {
  final dio = ref.read(backendDioProvider);
  final qp = <String, dynamic>{};
  if (args.status != null) qp['status'] = args.status;
  if (args.debtorAdminId != null) qp['debtor_admin_id'] = args.debtorAdminId;
  if (args.from != null) qp['from'] = args.from!.toIso8601String().substring(0, 10);
  if (args.to != null) qp['to'] = args.to!.toIso8601String().substring(0, 10);
  try {
    final res = await dio.get('/api/admin/manager-debts', queryParameters: qp);
    final data = res.data;
    if (data is! Map || data['success'] != true) return const [];
    final list = (data['debts'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => ManagerDebt.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
    return list;
  } catch (_) {
    return const [];
  }
});

/// Aggregated totals (per-debtor + grand totals) for the header strip.
final managerDebtsSummaryProvider =
    FutureProvider.autoDispose<ManagerDebtsSummary>((ref) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.get('/api/admin/manager-debts/summary');
    final data = res.data;
    if (data is! Map || data['success'] != true) return ManagerDebtsSummary.empty;
    return ManagerDebtsSummary.fromJson(Map<String, dynamic>.from(data));
  } catch (_) {
    return ManagerDebtsSummary.empty;
  }
});

/// Payments timeline for one debt (parent view).
final managerDebtPaymentsProvider = FutureProvider.family
    .autoDispose<List<ManagerDebtPayment>, int>((ref, debtId) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.get('/api/admin/manager-debts/$debtId/payments');
    final data = res.data;
    if (data is! Map || data['success'] != true) return const [];
    return (data['payments'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => ManagerDebtPayment.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
});

/// Debts owed BY me (sub-admin view). Read-only from the mobile side —
/// per product decision, sub-admins don't record payments from the app.
final myDebtsProvider = FutureProvider.autoDispose<List<ManagerDebt>>((ref) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.get('/api/admin/my-debts');
    final data = res.data;
    if (data is! Map || data['success'] != true) return const [];
    return (data['debts'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => ManagerDebt.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
});

// ─── Mutations ─────────────────────────────────────────────────────────

/// After any write we invalidate list + summary (and payments for detail
/// screens if open) so the UI re-fetches fresh balances.
void _invalidateAll(WidgetRef ref, {int? debtId}) {
  ref.invalidate(managerDebtsListProvider);
  ref.invalidate(managerDebtsSummaryProvider);
  ref.invalidate(managerDebtsAccessProvider);
  if (debtId != null) ref.invalidate(managerDebtPaymentsProvider(debtId));
}

Future<bool> createManagerDebt(
  WidgetRef ref, {
  required int debtorAdminId,
  required double amount,
  String? note,
  DateTime? debtDate,
}) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.post('/api/admin/manager-debts', data: {
      'debtorAdminId': debtorAdminId,
      'amount': amount,
      if (note != null && note.isNotEmpty) 'note': note,
      if (debtDate != null) 'debtDate': debtDate.toIso8601String().substring(0, 10),
    });
    final ok = res.data is Map && res.data['success'] == true;
    if (ok) _invalidateAll(ref);
    return ok;
  } on DioException {
    return false;
  }
}

Future<bool> updateManagerDebt(
  WidgetRef ref,
  int id, {
  double? amount,
  String? note,
  DateTime? debtDate,
}) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.patch('/api/admin/manager-debts/$id', data: {
      if (amount != null) 'amount': amount,
      if (note != null) 'note': note,
      if (debtDate != null) 'debtDate': debtDate.toIso8601String().substring(0, 10),
    });
    final ok = res.data is Map && res.data['success'] == true;
    if (ok) _invalidateAll(ref, debtId: id);
    return ok;
  } on DioException {
    return false;
  }
}

Future<bool> deleteManagerDebt(WidgetRef ref, int id) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.delete('/api/admin/manager-debts/$id');
    final ok = res.data is Map && res.data['success'] == true;
    if (ok) _invalidateAll(ref, debtId: id);
    return ok;
  } on DioException {
    return false;
  }
}

class AddPaymentResult {
  final bool success;
  final String? status; // server-derived 'open' | 'partial' | 'paid'
  final String? errorMessage;
  final double? remaining; // set when server rejects for exceeding remaining
  const AddPaymentResult({
    required this.success,
    this.status,
    this.errorMessage,
    this.remaining,
  });
}

Future<AddPaymentResult> addManagerDebtPayment(
  WidgetRef ref,
  int debtId, {
  required double amountPaid,
  String? note,
  DateTime? paymentDate,
}) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.post('/api/admin/manager-debts/$debtId/payments', data: {
      'amountPaid': amountPaid,
      if (note != null && note.isNotEmpty) 'note': note,
      if (paymentDate != null)
        'paymentDate': paymentDate.toIso8601String().substring(0, 10),
    });
    final data = res.data;
    if (data is Map && data['success'] == true) {
      _invalidateAll(ref, debtId: debtId);
      return AddPaymentResult(success: true, status: data['status']?.toString());
    }
    return const AddPaymentResult(success: false, errorMessage: 'تعذّر التسجيل');
  } on DioException catch (e) {
    final data = e.response?.data;
    if (data is Map) {
      final remaining = double.tryParse(data['remaining']?.toString() ?? '');
      return AddPaymentResult(
        success: false,
        errorMessage: data['message']?.toString(),
        remaining: remaining,
      );
    }
    return const AddPaymentResult(success: false, errorMessage: 'فشل الاتصال');
  }
}

Future<bool> deleteManagerDebtPayment(
  WidgetRef ref,
  int paymentId,
  int debtId,
) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.delete('/api/admin/manager-debts/payments/$paymentId');
    final ok = res.data is Map && res.data['success'] == true;
    if (ok) _invalidateAll(ref, debtId: debtId);
    return ok;
  } on DioException {
    return false;
  }
}

Future<bool> sendManagerDebtWhatsApp(WidgetRef ref, int debtId) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.post('/api/admin/manager-debts/$debtId/whatsapp');
    return res.data is Map && res.data['success'] == true;
  } on DioException {
    return false;
  }
}
