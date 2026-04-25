/// One row in the unified manager-movements timeline returned by
/// `/api/admin/managers/:targetId/movements`. Three subtypes share
/// a flat shape so the timeline renders without per-type branching:
///
///   • balance       — manager_balance_movements row (subKind names
///                     deposit_cash / deposit_loan / withdraw /
///                     points / sas_pay_debt)
///   • debt_created  — manager_debts row (subKind = status:
///                     open / partial / paid)
///   • debt_payment  — manager_debt_payments row (subKind null,
///                     relatedDebtId points at the parent debt)
class ManagerMovement {
  final String rowType;
  final int id;
  final String? subKind;
  final double amount;
  final String? note;
  final String? source;
  final int? reversesId;
  final DateTime eventAt;
  final int? debtId;
  final int? relatedDebtId;

  const ManagerMovement({
    required this.rowType,
    required this.id,
    required this.subKind,
    required this.amount,
    required this.note,
    required this.source,
    required this.reversesId,
    required this.eventAt,
    required this.debtId,
    required this.relatedDebtId,
  });

  factory ManagerMovement.fromJson(Map<String, dynamic> j) {
    double _num(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;
    int? _intN(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }
    // The server stores created_at as UTC (the host timezone is UTC and
    // mysql2 hands back a JS Date that res.json serializes with the Z
    // suffix). The app's convention is to display every date in Baghdad
    // time regardless of the device's locale, so parse to UTC and shift
    // by +3h. We deliberately keep the result in `isUtc=true` so
    // DateFormat.format prints the Baghdad clock-face value without
    // applying another toLocal() conversion.
    DateTime _date(dynamic v) {
      final raw = v?.toString();
      if (raw == null || raw.isEmpty) return DateTime.now().toUtc();
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) return DateTime.now().toUtc();
      return parsed.toUtc().add(const Duration(hours: 3));
    }
    return ManagerMovement(
      rowType: j['row_type']?.toString() ?? '',
      id: _intN(j['id']) ?? 0,
      subKind: j['sub_kind']?.toString(),
      amount: _num(j['amount']),
      note: (j['note']?.toString().isEmpty ?? true)
          ? null
          : j['note'].toString(),
      source: j['source']?.toString(),
      reversesId: _intN(j['reverses_id']),
      eventAt: _date(j['event_at']),
      debtId: _intN(j['debt_id']),
      relatedDebtId: _intN(j['related_debt_id']),
    );
  }
}
