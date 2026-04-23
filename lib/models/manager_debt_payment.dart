class ManagerDebtPayment {
  final int id;
  final int debtId;
  final double amountPaid;
  final String? note;
  final DateTime paymentDate;
  final DateTime createdAt;

  const ManagerDebtPayment({
    required this.id,
    required this.debtId,
    required this.amountPaid,
    required this.note,
    required this.paymentDate,
    required this.createdAt,
  });

  factory ManagerDebtPayment.fromJson(Map<String, dynamic> j) {
    double _num(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;
    int _int(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
    DateTime _date(dynamic v) => DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
    return ManagerDebtPayment(
      id: _int(j['id']),
      debtId: _int(j['debt_id']),
      amountPaid: _num(j['amount_paid']),
      note: (j['note']?.toString().isEmpty ?? true) ? null : j['note'].toString(),
      paymentDate: _date(j['payment_date']),
      createdAt: _date(j['created_at']),
    );
  }
}
