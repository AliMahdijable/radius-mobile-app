/// Mirror of admin_notification_prefs on the server. Defaults match
/// the server-side DEFAULT_NOTIFICATION_PREFS so the UI can paint
/// "all on" immediately even before the first GET returns.
class NotificationPrefs {
  final bool pushNearExpiry;
  final bool pushExpiredToday;
  final bool pushManagerDebt;
  final bool quietHoursEnabled;
  final String quietHoursStart; // "HH:mm"
  final String quietHoursEnd;   // "HH:mm"

  const NotificationPrefs({
    required this.pushNearExpiry,
    required this.pushExpiredToday,
    required this.pushManagerDebt,
    required this.quietHoursEnabled,
    required this.quietHoursStart,
    required this.quietHoursEnd,
  });

  static const defaults = NotificationPrefs(
    pushNearExpiry: true,
    pushExpiredToday: true,
    pushManagerDebt: true,
    quietHoursEnabled: false,
    quietHoursStart: '22:00',
    quietHoursEnd: '07:00',
  );

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) {
    bool _bool(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';
    String _hhmm(dynamic v, String fallback) {
      final s = v?.toString().trim() ?? '';
      return RegExp(r'^\d{2}:\d{2}$').hasMatch(s) ? s : fallback;
    }
    return NotificationPrefs(
      pushNearExpiry: _bool(j['push_near_expiry']),
      pushExpiredToday: _bool(j['push_expired_today']),
      pushManagerDebt: _bool(j['push_manager_debt']),
      quietHoursEnabled: _bool(j['quiet_hours_enabled']),
      quietHoursStart: _hhmm(j['quiet_hours_start'], '22:00'),
      quietHoursEnd: _hhmm(j['quiet_hours_end'], '07:00'),
    );
  }

  Map<String, dynamic> toSaveJson() => {
        'pushNearExpiry': pushNearExpiry,
        'pushExpiredToday': pushExpiredToday,
        'pushManagerDebt': pushManagerDebt,
        'quietHoursEnabled': quietHoursEnabled,
        'quietHoursStart': quietHoursStart,
        'quietHoursEnd': quietHoursEnd,
      };

  NotificationPrefs copyWith({
    bool? pushNearExpiry,
    bool? pushExpiredToday,
    bool? pushManagerDebt,
    bool? quietHoursEnabled,
    String? quietHoursStart,
    String? quietHoursEnd,
  }) =>
      NotificationPrefs(
        pushNearExpiry: pushNearExpiry ?? this.pushNearExpiry,
        pushExpiredToday: pushExpiredToday ?? this.pushExpiredToday,
        pushManagerDebt: pushManagerDebt ?? this.pushManagerDebt,
        quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
        quietHoursStart: quietHoursStart ?? this.quietHoursStart,
        quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
      );
}
