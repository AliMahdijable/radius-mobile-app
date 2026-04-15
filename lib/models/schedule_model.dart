class ScheduleModel {
  final int? id;
  final String adminId;
  final String scheduleType;
  final bool isEnabled;
  final String scheduledTime;
  final List<int> activeDays;
  final int? daysBefore;
  final String? lastRunAt;
  final int executionCount;

  const ScheduleModel({
    this.id,
    required this.adminId,
    required this.scheduleType,
    this.isEnabled = false,
    required this.scheduledTime,
    required this.activeDays,
    this.daysBefore,
    this.lastRunAt,
    this.executionCount = 0,
  });

  static String getArabicType(String type) {
    switch (type) {
      case 'debt_reminder':
        return 'تذكير ديون';
      case 'expiry_warning':
        return 'تحذير انتهاء';
      case 'service_end':
        return 'انتهاء الخدمة';
      default:
        return type;
    }
  }

  factory ScheduleModel.fromJson(Map<String, dynamic> json) {
    List<int> parseDays(dynamic days) {
      if (days is List) return days.cast<int>();
      if (days is String) {
        try {
          final parsed = List<int>.from(
            (days.replaceAll('[', '').replaceAll(']', ''))
                .split(',')
                .map((e) => int.parse(e.trim())),
          );
          return parsed;
        } catch (_) {
          return [0, 1, 2, 3, 4, 5, 6];
        }
      }
      return [0, 1, 2, 3, 4, 5, 6];
    }

    return ScheduleModel(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? ''),
      adminId: (json['admin_id'] ?? '').toString(),
      scheduleType: (json['schedule_type'] ?? '').toString(),
      isEnabled: json['is_enabled'] == true || json['is_enabled'] == 1,
      scheduledTime: (json['scheduled_time'] ?? '12:00:00').toString(),
      activeDays: parseDays(json['active_days']),
      daysBefore: json['days_before'] is int
          ? json['days_before']
          : int.tryParse(json['days_before']?.toString() ?? ''),
      lastRunAt: json['last_run_at']?.toString(),
      executionCount: json['execution_count'] is int
          ? json['execution_count']
          : int.tryParse(json['execution_count']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toSaveJson() => {
        'adminId': adminId,
        'scheduleType': scheduleType,
        'scheduleData': {
          'scheduled_time': scheduledTime,
          'active_days': activeDays,
          'is_enabled': isEnabled,
          if (daysBefore != null) 'days_before': daysBefore,
        },
      };
}
