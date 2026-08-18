/// Dashboard data shapes. Plain immutable classes — no defaults, no
/// mock constants. When real data isn't loaded yet, callers pass `null`
/// and the receiving widget renders a loading state.

class DailyStats {
  const DailyStats({
    required this.activations,
    required this.debtorsCount,
    required this.debtorsTotal,
  });

  final int activations;
  final int debtorsCount;
  final int debtorsTotal;
}

class SubscribersStats {
  const SubscribersStats({
    required this.total,
    required this.active,
    required this.online,
    required this.offline,
    required this.expired,
    required this.nearExpiry,
    required this.onlineNoPlan,
  });

  final int total;
  final int active;
  final int online;
  final int offline;
  final int expired;
  final int nearExpiry;

  /// "بدون نت" — subscribers whose session is up but plan has expired
  /// (isOnline && isExpired). Iraqi ISP colloquial: they're consuming
  /// bandwidth without a valid subscription; admin needs to either
  /// extend or disconnect them.
  final int onlineNoPlan;
}

class WhatsAppStatus {
  const WhatsAppStatus({
    required this.connected,
    required this.phone,
    this.needsPairing = false,
    this.sendingRestricted = false,
    this.cappingWarning = false,
  });

  final bool connected;
  final String phone;
  final bool needsPairing;
  final bool sendingRestricted;
  final bool cappingWarning;
}
