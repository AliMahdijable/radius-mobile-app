/// WhatsApp notification schedule — واحد صف لكل نوع إشعار (expiry_warning /
/// debt_reminder / service_end). يطابق جدول `whatsapp_schedules` على السيرفر.
///
/// UI (whatsapp_schedules_screen) يعرض كارت لكل نوع مع: toggle + وقت + أيام
/// (weekly أو monthly). تُحفَظ عبر POST /api/whatsapp/save-schedule
/// (نفس endpoint v1 web + v1 mobile).
class WhatsAppSchedule {
  final int? id;
  final String adminId;
  final String scheduleType;
  final bool isEnabled;

  /// HH:mm:ss (backend يقبل HH:mm أيضاً — نُطبّع للـHH:mm عند الحفظ).
  final String scheduledTime;

  /// 0..6 (الأحد = 0). للـweekly mode.
  final List<int> activeDays;

  /// عدد الأيام قبل الانتهاء — expiry_warning فقط (1..30).
  final int? daysBefore;

  final String? lastRunAt;
  final int executionCount;

  /// 'weekly' أو 'monthly'. debt_reminder وحده يدعم monthly.
  final String scheduleMode;

  /// 1..31. القيمة 31 sentinel = "آخر يوم في الشهر".
  final List<int> monthDays;

  /// 2026-08-26: قناة الإرسال المفضّلة لهذه الجدولة.
  /// 'auto' = يحترم binding المشترك (default).
  /// 'whatsapp' = يجبر واتساب.
  /// 'telegram' = يجبر تلغرام (المشترك يجب يكون مربوطاً).
  final String channelPreference;

  /// «تحديد المدينين» المحفوظ مع تذكير الديون (١٢ نوفمبر): مفاتيحه minAgeDays · minAmount · maxAmount بأرقامٍ صحيحة،
  /// وفارغٌ = بلا تحديد (التذكير لكلّ المدينين). الخادم يعيده كائناً نظيفاً أو null.
  final Map<String, int> debtFilter;

  /// المخزَّن على الخادم تالف: المجدول لا يرسل حتى يُحفظ من جديد.
  final bool debtFilterInvalid;

  /// هل يُرسَل مفتاح التحديد مع الحفظ؟ false ⇒ لا يُرسَل فيبقى ما على الخادم كما هو (الخادم: الغائب = «لا تمسّه»).
  /// يُضبط true حين غيّر المدير التحديد وحده — فحفظُ الوقت أو الأيّام لا يمسّ التحديد أبداً.
  final bool sendDebtFilter;

  const WhatsAppSchedule({
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
    this.channelPreference = 'auto',
    this.debtFilter = const {},
    this.debtFilterInvalid = false,
    this.sendDebtFilter = false,
  });

  factory WhatsAppSchedule.fromJson(Map<String, dynamic> json) {
    return WhatsAppSchedule(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse(json['id']?.toString() ?? ''),
      adminId: (json['admin_id'] ?? '').toString(),
      scheduleType: (json['schedule_type'] ?? '').toString(),
      isEnabled: json['is_enabled'] == true || json['is_enabled'] == 1,
      scheduledTime: (json['scheduled_time'] ?? '10:00:00').toString(),
      activeDays: _parseIntList(json['active_days'],
          defaultVal: const [0, 1, 2, 3, 4, 5, 6]),
      daysBefore: json['days_before'] is int
          ? json['days_before'] as int
          : int.tryParse(json['days_before']?.toString() ?? ''),
      lastRunAt: json['last_run_at']?.toString(),
      executionCount: json['execution_count'] is int
          ? json['execution_count'] as int
          : int.tryParse(json['execution_count']?.toString() ?? '0') ?? 0,
      scheduleMode: (json['schedule_mode'] ?? 'weekly').toString(),
      monthDays: _parseIntList(json['month_days'], defaultVal: const [])
          .where((n) => n >= 1 && n <= 31)
          .toList(),
      channelPreference: () {
        final raw = (json['channel_preference'] ?? 'auto').toString();
        return ['auto', 'whatsapp', 'telegram'].contains(raw) ? raw : 'auto';
      }(),
      debtFilter: _parseDebtFilter(json['debt_filter']),
      debtFilterInvalid: json['debt_filter_invalid'] == true,
    );
  }

  static const _debtFilterKeys = ['minAgeDays', 'minAmount', 'maxAmount'];

  /// كائن الخادم ⇒ أرقامٌ صحيحة غير سالبة للمفاتيح المعروفة وحدها — غير ذلك يُهمَل (لا تحديد يُختلق).
  static Map<String, int> _parseDebtFilter(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    for (final k in _debtFilterKeys) {
      final v = raw[k];
      if (v is num && v.isFinite && v >= 0 && v == v.roundToDouble()) out[k] = v.toInt();
    }
    return out;
  }

  /// Payload لـPOST /api/whatsapp/save-schedule (camelCase مثل web/v1).
  Map<String, dynamic> toSaveJson() {
    final parts = scheduledTime.split(':');
    final hh = parts.isNotEmpty ? parts[0].padLeft(2, '0') : '10';
    final mm = parts.length > 1 ? parts[1].padLeft(2, '0') : '00';
    return {
      'adminId': adminId,
      'scheduleType': scheduleType,
      'scheduleData': {
        'isEnabled': isEnabled,
        'scheduledTime': '$hh:$mm',
        'activeDays': activeDays,
        if (daysBefore != null) 'daysBefore': daysBefore,
        'scheduleMode': scheduleMode,
        'monthDays': monthDays,
        'channelPreference': channelPreference,
        // كائنٌ بحدوده أو null للمسح — ولا يُرسَل كائنٌ فارغ (الخادم يرفضه: لا يُفهم «امسح» من جسمٍ أسقط قيمه)
        if (sendDebtFilter) 'debtFilter': debtFilter.isEmpty ? null : debtFilter,
      },
    };
  }

  WhatsAppSchedule copyWith({
    int? id,
    String? adminId,
    String? scheduleType,
    bool? isEnabled,
    String? scheduledTime,
    List<int>? activeDays,
    int? daysBefore,
    String? lastRunAt,
    int? executionCount,
    String? scheduleMode,
    List<int>? monthDays,
    String? channelPreference,
    Map<String, int>? debtFilter,
    bool? debtFilterInvalid,
    bool? sendDebtFilter,
  }) {
    return WhatsAppSchedule(
      id: id ?? this.id,
      adminId: adminId ?? this.adminId,
      scheduleType: scheduleType ?? this.scheduleType,
      isEnabled: isEnabled ?? this.isEnabled,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      activeDays: activeDays ?? this.activeDays,
      daysBefore: daysBefore ?? this.daysBefore,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      executionCount: executionCount ?? this.executionCount,
      scheduleMode: scheduleMode ?? this.scheduleMode,
      monthDays: monthDays ?? this.monthDays,
      channelPreference: channelPreference ?? this.channelPreference,
      debtFilter: debtFilter ?? this.debtFilter,
      debtFilterInvalid: debtFilterInvalid ?? this.debtFilterInvalid,
      sendDebtFilter: sendDebtFilter ?? this.sendDebtFilter,
    );
  }

  static List<int> _parseIntList(dynamic raw, {required List<int> defaultVal}) {
    if (raw is List) {
      try {
        return raw.map((e) {
          if (e is int) return e;
          if (e is num) return e.toInt();
          return int.tryParse(e.toString().trim()) ?? 0;
        }).toList();
      } catch (_) {
        return defaultVal;
      }
    }
    if (raw is String) {
      try {
        final cleaned = raw.replaceAll('[', '').replaceAll(']', '').trim();
        if (cleaned.isEmpty) return defaultVal;
        return cleaned
            .split(',')
            .map((e) => int.tryParse(e.trim()))
            .whereType<int>()
            .toList();
      } catch (_) {
        return defaultVal;
      }
    }
    return defaultVal;
  }
}
