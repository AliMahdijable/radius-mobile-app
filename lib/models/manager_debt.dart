enum ManagerDebtStatus { open, partial, paid }

ManagerDebtStatus parseDebtStatus(String? raw) {
  switch ((raw ?? 'open').toLowerCase()) {
    case 'paid':
      return ManagerDebtStatus.paid;
    case 'partial':
      return ManagerDebtStatus.partial;
    default:
      return ManagerDebtStatus.open;
  }
}

String debtStatusLabel(ManagerDebtStatus s) {
  switch (s) {
    case ManagerDebtStatus.paid:
      return 'مسدّد';
    case ManagerDebtStatus.partial:
      return 'جزئي';
    case ManagerDebtStatus.open:
      return 'مفتوح';
  }
}

/// Inter-admin debt. `remaining_amount` is authoritative — the server
/// computes it from `amount - SUM(payments.amount_paid)` in the same
/// query, so we don't re-derive on the client.
class ManagerDebt {
  final int id;
  final int parentAdminId;
  final String? parentAdminUsername;
  final int debtorAdminId;
  final String? debtorAdminUsername;
  final double amount;
  final double paidAmount;
  final double remainingAmount;
  final String? note;
  final DateTime debtDate;
  final DateTime? lastPaymentDate;
  final ManagerDebtStatus status;
  final DateTime createdAt;

  const ManagerDebt({
    required this.id,
    required this.parentAdminId,
    required this.parentAdminUsername,
    required this.debtorAdminId,
    required this.debtorAdminUsername,
    required this.amount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.note,
    required this.debtDate,
    required this.lastPaymentDate,
    required this.status,
    required this.createdAt,
  });

  factory ManagerDebt.fromJson(Map<String, dynamic> j) {
    double _num(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;
    int _int(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
    DateTime _date(dynamic v) => DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
    DateTime? _dateN(dynamic v) {
      final s = v?.toString();
      if (s == null || s.isEmpty) return null;
      return DateTime.tryParse(s);
    }
    return ManagerDebt(
      id: _int(j['id']),
      parentAdminId: _int(j['parent_admin_id']),
      parentAdminUsername: j['parent_admin_username']?.toString(),
      debtorAdminId: _int(j['debtor_admin_id']),
      debtorAdminUsername: j['debtor_admin_username']?.toString(),
      amount: _num(j['amount']),
      paidAmount: _num(j['paid_amount']),
      remainingAmount: _num(j['remaining_amount']),
      note: (j['note']?.toString().isEmpty ?? true) ? null : j['note'].toString(),
      debtDate: _date(j['debt_date']),
      lastPaymentDate: _dateN(j['last_payment_date']),
      status: parseDebtStatus(j['status']?.toString()),
      createdAt: _date(j['created_at']),
    );
  }
}

/// Aggregate row returned by `/api/admin/manager-debts/summary`
/// under `perDebtor`. Used to show totals by sub-admin.
class ManagerDebtDebtorSummary {
  final int debtorAdminId;
  final String? debtorAdminUsername;
  final int debtsCount;
  final double totalAmount;
  final double totalPaid;
  final double totalRemaining;

  const ManagerDebtDebtorSummary({
    required this.debtorAdminId,
    required this.debtorAdminUsername,
    required this.debtsCount,
    required this.totalAmount,
    required this.totalPaid,
    required this.totalRemaining,
  });

  factory ManagerDebtDebtorSummary.fromJson(Map<String, dynamic> j) {
    double _num(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;
    int _int(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
    return ManagerDebtDebtorSummary(
      debtorAdminId: _int(j['debtor_admin_id']),
      debtorAdminUsername: j['debtor_admin_username']?.toString(),
      debtsCount: _int(j['debts_count']),
      totalAmount: _num(j['total_amount']),
      totalPaid: _num(j['total_paid']),
      totalRemaining: _num(j['total_remaining']),
    );
  }
}

class ManagerDebtsSummary {
  final int debtsCount;
  final int debtorsCount;
  final double totalAmount;
  final double totalPaid;
  final double totalRemaining;
  final int openCount;
  final int partialCount;
  final int paidCount;
  final List<ManagerDebtDebtorSummary> perDebtor;

  const ManagerDebtsSummary({
    required this.debtsCount,
    required this.debtorsCount,
    required this.totalAmount,
    required this.totalPaid,
    required this.totalRemaining,
    required this.openCount,
    required this.partialCount,
    required this.paidCount,
    required this.perDebtor,
  });

  factory ManagerDebtsSummary.fromJson(Map<String, dynamic> j) {
    final t = (j['totals'] as Map?) ?? const {};
    double _num(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;
    int _int(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
    final List per = (j['perDebtor'] as List?) ?? const [];
    return ManagerDebtsSummary(
      debtsCount: _int(t['debts_count']),
      debtorsCount: _int(t['debtors_count']),
      totalAmount: _num(t['total_amount']),
      totalPaid: _num(t['total_paid']),
      totalRemaining: _num(t['total_remaining']),
      openCount: _int(t['open_count']),
      partialCount: _int(t['partial_count']),
      paidCount: _int(t['paid_count']),
      perDebtor: per
          .whereType<Map<String, dynamic>>()
          .map(ManagerDebtDebtorSummary.fromJson)
          .toList(growable: false),
    );
  }

  static const empty = ManagerDebtsSummary(
    debtsCount: 0,
    debtorsCount: 0,
    totalAmount: 0,
    totalPaid: 0,
    totalRemaining: 0,
    openCount: 0,
    partialCount: 0,
    paidCount: 0,
    perDebtor: [],
  );
}

/// Entry in the sub-admin dropdown for creating a new debt.
class SubAdminRef {
  final int id;
  final String username;
  const SubAdminRef({required this.id, required this.username});

  factory SubAdminRef.fromJson(Map<String, dynamic> j) => SubAdminRef(
        id: j['id'] is int ? j['id'] : int.tryParse(j['id']?.toString() ?? '0') ?? 0,
        username: j['username']?.toString() ?? '',
      );
}

class ManagerDebtsAccess {
  final bool hasSubAdmins;
  final List<SubAdminRef> subAdmins;
  const ManagerDebtsAccess({required this.hasSubAdmins, required this.subAdmins});

  factory ManagerDebtsAccess.fromJson(Map<String, dynamic> j) {
    final List raw = (j['subAdmins'] as List?) ?? const [];
    return ManagerDebtsAccess(
      hasSubAdmins: j['hasSubAdmins'] == true,
      subAdmins: raw
          .whereType<Map<String, dynamic>>()
          .map(SubAdminRef.fromJson)
          .toList(growable: false),
    );
  }

  static const none = ManagerDebtsAccess(hasSubAdmins: false, subAdmins: []);
}
