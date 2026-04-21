class AdminExpense {
  final int id;
  final double amount;
  final String? note;
  final DateTime expenseDate;
  final DateTime createdAt;
  final String? adminUsername; // only set in super-admin "all" view

  const AdminExpense({
    required this.id,
    required this.amount,
    required this.note,
    required this.expenseDate,
    required this.createdAt,
    this.adminUsername,
  });

  factory AdminExpense.fromJson(Map<String, dynamic> j) {
    return AdminExpense(
      id: j['id'] is int ? j['id'] : int.tryParse(j['id']?.toString() ?? '0') ?? 0,
      amount: double.tryParse(j['amount']?.toString() ?? '0') ?? 0,
      note: (j['note']?.toString().isEmpty ?? true) ? null : j['note'].toString(),
      expenseDate: DateTime.tryParse(j['expense_date']?.toString() ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
      adminUsername: j['admin_username']?.toString(),
    );
  }
}

class AdminExpensesPage {
  final List<AdminExpense> expenses;
  final double total;
  const AdminExpensesPage({required this.expenses, required this.total});
}
