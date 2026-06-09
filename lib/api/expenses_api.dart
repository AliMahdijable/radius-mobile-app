import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Admin expenses API — مطلب 2026-06-10 (FAB → 'إضافة صرفية').
/// Backend wraps the admin_expenses table at /api/admin/expenses.
class ExpensesApi {
  ExpensesApi._();

  /// POST /api/admin/expenses — create a new expense row for the
  /// logged-in admin. expenseDate accepts 'YYYY-MM-DD' or null (the
  /// backend defaults to today's date in Baghdad time).
  static Future<({bool ok, String? message, int? id})> create({
    required num amount,
    String? note,
    String? expenseDate,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/admin/expenses',
        data: {
          'amount': amount,
          if (note != null && note.isNotEmpty) 'note': note,
          if (expenseDate != null && expenseDate.isNotEmpty)
            'expenseDate': expenseDate,
        },
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      final rawId = body['id'];
      final id = rawId is int
          ? rawId
          : int.tryParse(rawId?.toString() ?? '');
      return (ok: ok, message: body['message']?.toString(), id: id);
    } on DioException catch (e) {
      _log('admin/expenses (POST)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (
        ok: false,
        message: msg ?? 'تعذّر إضافة الصرفية',
        id: null,
      );
    } catch (e) {
      _log('admin/expenses (POST)', e);
      return (ok: false, message: 'تعذّر إضافة الصرفية', id: null);
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
