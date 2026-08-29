import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Source of the movement — SAS4 deposit/withdraw records mark
/// 'sas4' on the row, while custom debt entries leave it null /
/// 'manual'. The mobile UI prints a subtle "الساس" / "يدوي" badge.
enum MovementSource { sas4, manual }

MovementSource? _parseSource(dynamic v) {
  switch (v?.toString().toLowerCase()) {
    case 'sas4':
      return MovementSource.sas4;
    case 'manual':
    case 'يدوي':
      return MovementSource.manual;
    default:
      return null;
  }
}

/// One unified row in the manager-movements timeline. The backend
/// `/api/admin/managers/:targetAdminId/movements` returns a single
/// list with three row types stitched together (balance ops, custom
/// debt creations, custom debt payments), each marked with `rowType`.
class ManagerMovement {
  const ManagerMovement({
    required this.rowType,
    required this.id,
    this.subKind,
    required this.amount,
    this.note,
    this.source,
    this.reversesId,
    required this.eventAt,
    this.debtId,
    this.relatedDebtId,
  });

  /// 'balance' | 'debt_created' | 'debt_payment'
  final String rowType;

  /// Primary key inside the underlying table.
  final int id;

  /// For 'balance' rows: 'deposit_cash' | 'deposit_loan' | 'withdraw'
  /// | 'points' | 'sas_pay_debt' — drives the icon + color.
  /// For 'debt_created' rows: the debt's status ('open' | 'partial' |
  /// 'paid'). Null for 'debt_payment'.
  final String? subKind;

  final double amount;
  final String? note;
  final MovementSource? source;

  /// If this row is an auditor's reversal of an earlier movement,
  /// points back to the row it cancels. UI may render a strikethrough.
  final int? reversesId;

  /// Mirrors v1 normalization (mobile-app/lib/models/manager_movement.
  /// dart:51-56): server stamps UTC then we add +3 hours (Baghdad
  /// time). Kept `isUtc=true` so DateTime comparisons line up.
  final DateTime eventAt;

  /// Populated only on 'debt_created' — points to the manager_debts row.
  final int? debtId;

  /// Populated only on 'debt_payment' — points to the parent debt id.
  final int? relatedDebtId;

  static ManagerMovement? fromJson(Map<String, dynamic> j) {
    final id = _toInt(j['id']);
    final rowType = (j['row_type'] ?? '').toString();
    if (id == 0 || rowType.isEmpty) return null;
    return ManagerMovement(
      rowType: rowType,
      id: id,
      subKind: j['sub_kind']?.toString(),
      amount: _toDouble(j['amount']),
      note: j['note']?.toString(),
      source: _parseSource(j['source']),
      reversesId: j['reverses_id'] != null ? _toInt(j['reverses_id']) : null,
      eventAt: _baghdadTime(j['event_at']),
      debtId: j['debt_id'] != null ? _toInt(j['debt_id']) : null,
      relatedDebtId:
          j['related_debt_id'] != null ? _toInt(j['related_debt_id']) : null,
    );
  }

  /// Human-readable Arabic label for the row, picked by rowType +
  /// subKind. Mirrors v1's _MovementCard mapping so the same labels
  /// show across versions.
  String get arabicLabel {
    if (rowType == 'debt_created') return 'دين جديد';
    if (rowType == 'debt_payment') return 'تسديد دين آخر';
    switch (subKind) {
      case 'deposit_cash':
        return 'إضافة رصيد نقدي';
      case 'deposit_loan':
        return 'إضافة رصيد آجل';
      case 'withdraw':
        return 'سحب رصيد';
      case 'points':
        return 'نقاط';
      case 'sas_pay_debt':
        return 'تسديد دين الساس';
      default:
        return 'حركة';
    }
  }

  /// '+' / '−' indicator used in the card's amount chip.
  String get signLabel {
    if (rowType == 'debt_created') return '+';
    if (rowType == 'debt_payment') return '−';
    if (subKind == 'withdraw' || subKind == 'sas_pay_debt') return '−';
    return '+';
  }
}

class ManagerMovementsApi {
  ManagerMovementsApi._();

  /// GET /api/admin/managers/:targetAdminId/movements — full timeline.
  static Future<List<ManagerMovement>> list({
    required int targetAdminId,
    int limit = 200,
  }) async {
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
      _log('managers/$targetAdminId/movements GET', e);
      return const [];
    } catch (e) {
      _log('managers/$targetAdminId/movements GET', e);
      return const [];
    }
  }

  /// PATCH /api/admin/manager-movements/:id — note + amount only.
  /// Kind is fixed; SAS4-side state is NOT reversed (audit-only).
  /// The UI must warn the admin before calling.
  static Future<({bool ok, String? message})> update({
    required int id,
    String? note,
    num? amount,
  }) async {
    try {
      final r = await ApiClient.dio.patch<Map<String, dynamic>>(
        '/api/admin/manager-movements/$id',
        data: {
          if (note != null) 'note': note,
          if (amount != null) 'amount': amount,
        },
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString()
      );
    } on DioException catch (e) {
      _log('manager-movements/$id PATCH', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر التعديل');
    } catch (e) {
      _log('manager-movements/$id PATCH', e);
      return (ok: false, message: 'تعذّر التعديل');
    }
  }

  /// DELETE /api/admin/manager-movements/:id — audit log row only.
  /// Does NOT undo the SAS4-side balance/debt change.
  static Future<({bool ok, String? message})> delete(int id) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/admin/manager-movements/$id',
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString()
      );
    } catch (e) {
      _log('manager-movements/$id DELETE', e);
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

/// Mirrors v1 manager_movement.dart:51-56 — server stamps UTC; we
/// add +3h so the displayed timestamp matches Baghdad local. Kept
/// `isUtc=true` so equality/comparisons in DateTime don't apply the
/// system's local offset on top.
DateTime _baghdadTime(dynamic v) {
  final parsed = DateTime.tryParse(v?.toString() ?? '');
  return parsed?.toUtc().add(const Duration(hours: 3)) ??
      DateTime.now().toUtc();
}
