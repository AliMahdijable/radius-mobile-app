/// Mock dashboard data — replaced screen-by-screen by real API calls in
/// the next iteration. Keeping these in one file so wiring is a single
/// search-and-replace.

class DailyStats {
  const DailyStats({
    required this.netToday,
    required this.netDeltaPct,
    required this.activations,
    required this.activationsDelta,
    required this.payments,
    required this.paymentsDeltaPct,
    required this.debtorsCount,
    required this.debtorsTotal,
    required this.expiredToday,
    required this.last7Days,
  });

  final int netToday;
  final double netDeltaPct; // 0.12 = +12%
  final int activations;
  final int activationsDelta;
  final int payments;
  final double paymentsDeltaPct;
  final int debtorsCount;
  final int debtorsTotal;
  final int expiredToday;
  final List<int> last7Days; // chronological, oldest first
}

const mockDailyStats = DailyStats(
  netToday: 635000,
  netDeltaPct: 0.12,
  activations: 12,
  activationsDelta: 3,
  payments: 540000,
  paymentsDeltaPct: 0.12,
  debtorsCount: 23,
  debtorsTotal: 1250000,
  expiredToday: 8,
  last7Days: [420000, 380000, 510000, 590000, 470000, 540000, 635000],
);

/// Net revenue summary for a period (daily / weekly / monthly).
/// The hero card cycles between these via its tab selector.
class NetRevenuePeriod {
  const NetRevenuePeriod({
    required this.label,
    required this.amount,
    required this.deltaPct,
    required this.points,
  });
  final String label;
  final int amount;
  final double deltaPct;
  final List<int> points;
}

const mockRevenueDaily = NetRevenuePeriod(
  label: 'اليوم',
  amount: 635000,
  deltaPct: 0.12,
  points: [420000, 380000, 510000, 590000, 470000, 540000, 635000],
);

const mockRevenueWeekly = NetRevenuePeriod(
  label: 'هذا الأسبوع',
  amount: 3545000,
  deltaPct: 0.08,
  points: [2900000, 3200000, 3100000, 3400000, 3545000],
);

const mockRevenueMonthly = NetRevenuePeriod(
  label: 'هذا الشهر',
  amount: 14250000,
  deltaPct: 0.15,
  points: [
    8500000, 10200000, 11800000, 12500000, 13100000, 13700000, 14250000,
  ],
);

class SubscribersStats {
  const SubscribersStats({
    required this.total,
    required this.active,
    required this.online,
    required this.expired,
    required this.nearExpiry,
  });

  final int total;
  final int active;
  final int online;
  final int expired;
  final int nearExpiry;
}

const mockSubscribers = SubscribersStats(
  total: 1284,
  active: 1129,
  online: 487,
  expired: 142,
  nearExpiry: 38,
);

class WhatsAppStatus {
  const WhatsAppStatus({
    required this.connected,
    required this.phone,
    required this.sentToday,
    required this.queuePending,
  });

  final bool connected;
  final String phone;
  final int sentToday;
  final int queuePending;
}

const mockWhatsApp = WhatsAppStatus(
  connected: true,
  phone: '0782 444 1234',
  sentToday: 87,
  queuePending: 3,
);

enum ActivityKind { activation, extension, payment, debt, message, system }

class Activity {
  const Activity({
    required this.kind,
    required this.title,
    required this.amount, // 0 if N/A; negative for debt
    required this.minutesAgo,
  });
  final ActivityKind kind;
  final String title;
  final int amount;
  final int minutesAgo;
}

const mockActivities = <Activity>[
  Activity(
    kind: ActivityKind.activation,
    title: 'تفعيل: غيث الخفاجي',
    amount: 50000,
    minutesAgo: 3,
  ),
  Activity(
    kind: ActivityKind.payment,
    title: 'تسديد دين: مصطفى الحلو',
    amount: 25000,
    minutesAgo: 12,
  ),
  Activity(
    kind: ActivityKind.message,
    title: 'تذكير 23 مدين عبر واتساب',
    amount: 0,
    minutesAgo: 28,
  ),
  Activity(
    kind: ActivityKind.extension,
    title: 'تمديد: شمسي',
    amount: 35000,
    minutesAgo: 41,
  ),
  Activity(
    kind: ActivityKind.debt,
    title: 'إضافة دين: حسن محمد',
    amount: -15000,
    minutesAgo: 67,
  ),
];
