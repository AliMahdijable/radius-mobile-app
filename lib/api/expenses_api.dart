import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'archive_info.dart';

/// One row from /api/admin/expenses. Backend returns ISO dates; we
/// parse to DateTime so the UI can sort and format consistently.
class ExpenseRow {
  const ExpenseRow({
    required this.id,
    required this.amount,
    required this.expenseDate,
    this.note,
    this.actingEmployeeUsername,
    this.settlementNumber,
  });
  final int id;
  final num amount;

  /// 'YYYY-MM-DD' from the backend — kept as a string for round-trip
  /// safety (date-only, no TZ).
  final String expenseDate;
  final String? note;

  /// Set when an employee created the row instead of the admin.
  final String? actingEmployeeUsername;

  /// رقم التسوية التي أقفلت الصرفية (`null` = مفتوحة). المقفلة لا تُعدَّل
  /// ولا تُحذف — الخادم يرفضها بـ409 أيضاً (server/accountSettlements.js).
  final int? settlementNumber;

  bool get isLocked => settlementNumber != null;

  static ExpenseRow? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id == null) return null;
    final idInt = id is int ? id : int.tryParse(id.toString());
    if (idInt == null) return null;
    final rawAmount = j['amount'];
    final amount = rawAmount is num
        ? rawAmount
        : num.tryParse(rawAmount?.toString() ?? '') ?? 0;
    // Backend's expense_date is TIMESTAMP — could come as ISO. Keep
    // just the date portion (yyyy-MM-dd) for the UI; full timestamp
    // brings noise we don't display.
    var date = (j['expense_date'] ?? j['expenseDate'] ?? '').toString();
    if (date.length >= 10) date = date.substring(0, 10);
    return ExpenseRow(
      id: idInt,
      amount: amount,
      expenseDate: date,
      note: j['note']?.toString(),
      actingEmployeeUsername:
          (j['acting_employee_full_name'] ?? j['acting_employee_username'])
              ?.toString(),
      settlementNumber: int.tryParse(j['settlement_number']?.toString() ?? ''),
    );
  }
}

/// Admin expenses API — مطلب 2026-06-10 (FAB → 'إضافة صرفية').
/// Backend wraps the admin_expenses table at /api/admin/expenses.
class ExpensesApi {
  ExpensesApi._();

  /// GET /api/admin/expenses — list expenses for the caller admin.
  /// Optional `from`/`to` ISO date strings (YYYY-MM-DD) filter the
  /// window. Returns the rows AND the SUM(amount) for the window so
  /// the screen can show a running total without a separate request.
  ///
  /// ما غطّته تسويةٌ فعّالة مخفيٌّ **افتراضيّاً** من الخادم،
  /// و[includeArchived] تُرجعه. ووصف الأرشيف في `archive` على **جذر**
  /// الجسم بجوار `expenses` و`total`، لا تحت `data`
  /// (`docs/settlements-prompt.md` §٤).
  static Future<({List<ExpenseRow> rows, num total, ArchiveInfo? archive})>
      list({
    String? from,
    String? to,
    int limit = 500,
    bool includeArchived = false,
  }) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/admin/expenses',
        queryParameters: {
          if (from != null && from.isNotEmpty) 'from': from,
          if (to != null && to.isNotEmpty) 'to': to,
          'limit': limit,
          if (includeArchived) 'include_archived': 1,
        },
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (rows: const <ExpenseRow>[], total: 0, archive: null);
      }
      final list = body['expenses'];
      if (list is! List) return (rows: const <ExpenseRow>[], total: 0, archive: null);
      final rows = list
          .whereType<Map>()
          .map((m) => ExpenseRow.fromJson(Map<String, dynamic>.from(m)))
          .whereType<ExpenseRow>()
          .toList();
      final rawTotal = body['total'];
      final total = rawTotal is num
          ? rawTotal
          : num.tryParse(rawTotal?.toString() ?? '') ?? 0;
      return (
        rows: rows,
        total: total,
        archive: ArchiveInfo.fromJson(body['archive']),
      );
    } on DioException catch (e) {
      _log('admin/expenses (GET)', e);
      return (rows: const <ExpenseRow>[], total: 0, archive: null);
    } catch (e) {
      _log('admin/expenses (GET)', e);
      return (rows: const <ExpenseRow>[], total: 0, archive: null);
    }
  }

  /// PUT /api/admin/expenses/:id — edit an existing row.
  static Future<({bool ok, String? message})> update({
    required int id,
    required num amount,
    String? note,
    String? expenseDate,
  }) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/admin/expenses/$id',
        data: {
          'amount': amount,
          'note': note,
          'expenseDate': expenseDate,
        },
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString()
      );
    } on DioException catch (e) {
      _log('admin/expenses (PUT)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر التعديل');
    } catch (e) {
      _log('admin/expenses (PUT)', e);
      return (ok: false, message: 'تعذّر التعديل');
    }
  }

  /// DELETE /api/admin/expenses/:id
  static Future<({bool ok, String? message})> delete(int id) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/admin/expenses/$id',
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString()
      );
    } on DioException catch (e) {
      _log('admin/expenses (DELETE)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر الحذف');
    } catch (e) {
      _log('admin/expenses (DELETE)', e);
      return (ok: false, message: 'تعذّر الحذف');
    }
  }

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
      final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
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
