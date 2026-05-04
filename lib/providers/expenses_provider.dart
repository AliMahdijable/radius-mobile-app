import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/dio_client.dart';
import '../models/admin_expense.dart';

class ExpensesRangeArgs {
  final DateTime? from;
  final DateTime? to;
  final String? employeeId;
  const ExpensesRangeArgs({this.from, this.to, this.employeeId});

  String? get fromIso => from?.toIso8601String();
  String? get toIso => to?.toIso8601String();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExpensesRangeArgs &&
          other.from == from &&
          other.to == to &&
          other.employeeId == employeeId);

  @override
  int get hashCode => Object.hash(from, to, employeeId);
}

final expensesProvider = FutureProvider.family
    .autoDispose<AdminExpensesPage, ExpensesRangeArgs>((ref, args) async {
  final dio = ref.read(backendDioProvider);
  final qp = <String, String>{};
  if (args.fromIso != null) qp['from'] = args.fromIso!;
  if (args.toIso != null) qp['to'] = args.toIso!;
  if (args.employeeId != null && args.employeeId != 'all') {
    qp['employee_id'] = args.employeeId!;
  }
  try {
    final res = await dio.get(
      '/api/admin/expenses',
      queryParameters: qp,
    );
    final data = res.data;
    if (data is! Map || data['success'] != true) {
      return const AdminExpensesPage(expenses: [], total: 0);
    }
    final list = (data['expenses'] as List? ?? [])
        .map((e) => AdminExpense.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final total = double.tryParse(data['total']?.toString() ?? '0') ?? 0;
    return AdminExpensesPage(expenses: list, total: total);
  } catch (_) {
    return const AdminExpensesPage(expenses: [], total: 0);
  }
});

Future<bool> createExpense(
  WidgetRef ref, {
  required double amount,
  String? note,
  DateTime? date,
}) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.post('/api/admin/expenses', data: {
      'amount': amount,
      if (note != null && note.isNotEmpty) 'note': note,
      if (date != null) 'expenseDate': date.toIso8601String(),
    });
    final ok = res.data is Map && res.data['success'] == true;
    if (ok) ref.invalidate(expensesProvider);
    return ok;
  } on DioException {
    return false;
  }
}

Future<bool> updateExpense(
  WidgetRef ref,
  int id, {
  required double amount,
  String? note,
  DateTime? date,
}) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.put('/api/admin/expenses/$id', data: {
      'amount': amount,
      if (note != null) 'note': note,
      if (date != null) 'expenseDate': date.toIso8601String(),
    });
    final ok = res.data is Map && res.data['success'] == true;
    if (ok) ref.invalidate(expensesProvider);
    return ok;
  } on DioException {
    return false;
  }
}

Future<bool> deleteExpense(WidgetRef ref, int id) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.delete('/api/admin/expenses/$id');
    final ok = res.data is Map && res.data['success'] == true;
    if (ok) ref.invalidate(expensesProvider);
    return ok;
  } on DioException {
    return false;
  }
}
