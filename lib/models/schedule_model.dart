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
  // Monthly mode support — when scheduleMode == 'monthly' the scheduler
  // checks monthDays (1..31) against today's day-of-month instead of
  // weekday. Value 31 is the sentinel "last day of the month".
  final String scheduleMode;
  final List<int> monthDays;

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
    this.scheduleMode = 'weekly',
    this.monthDays = const [],
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
      if (days is List) {
        try {
          return days.map((e) {
            if (e is int) return e;
            if (e is num) return e.toInt();
            return int.tryParse(e.toString().trim()) ?? 0;
          }).toList();
        } catch (_) {
          return [0, 1, 2, 3, 4, 5, 6];
        }
      }
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

    List<int> parseMonthDays(dynamic d) {
      if (d is List) {
        final out = <int>[];
        for (final e in d) {
          final n = e is int
              ? e
              : (e is num ? e.toInt() : int.tryParse(e.toString().trim()));
          if (n != null && n >= 1 && n <= 31) out.add(n);
        }
        return out;
      }
      if (d is String) {
        try {
          final cleaned = d.replaceAll('[', '').replaceAll(']', '').trim();
          if (cleaned.isEmpty) return const [];
          return cleaned
              .split(',')
              .map((e) => int.tryParse(e.trim()))
              .whereType<int>()
              .where((n) => n >= 1 && n <= 31)
              .toList();
        } catch (_) {
          return const [];
        }
      }
      return const [];
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
      scheduleMode: (json['schedule_mode'] ?? 'weekly').toString(),
      monthDays: parseMonthDays(json['month_days']),
    );
  }

  /// Payload for POST `/api/whatsapp/save-schedule` — must match web + [db.saveWhatsAppSchedule] (camelCase).
  Map<String, dynamic> toSaveJson() {
    final parts = scheduledTime.split(':');
    final hh = parts.isNotEmpty ? parts[0].padLeft(2, '0') : '10';
    final mm = parts.length > 1 ? parts[1].padLeft(2, '0') : '00';
    // Web sends HH:mm; DB accepts both; keep compact like WhatsAppSettings.js
    final scheduledTimeOut = '$hh:$mm';

    return {
      'adminId': adminId,
      'scheduleType': scheduleType,
      'scheduleData': {
        'isEnabled': isEnabled,
        'scheduledTime': scheduledTimeOut,
        'activeDays': activeDays,
        if (daysBefore != null) 'daysBefore': daysBefore,
        'scheduleMode': scheduleMode,
        'monthDays': monthDays,
      },
    };
  }
}
