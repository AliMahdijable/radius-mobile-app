import 'dart:convert';

/// نوع الإشعار — يحدد الأيقونة/اللون في الـUI وأين ينقلنا الـtap.
///
/// الـkeys مطابقة `data.type` اللي يرسله backend
/// (adminExpiryNotifier.js:260 + مصادر أخرى في server.js).
enum NotificationKind {
  nearExpiryDigest, // اشتراكات قاربت الانتهاء
  expiredTodayDigest, // اشتراكات انتهت اليوم
  managerDebt, // دين مدير فرعي
  managerBalance, // تحديث رصيد مدير
  other; // fallback

  static NotificationKind fromString(String? s) {
    switch ((s ?? '').trim()) {
      case 'near_expiry_digest':
        return NotificationKind.nearExpiryDigest;
      case 'expired_today_digest':
        return NotificationKind.expiredTodayDigest;
      case 'manager_debt':
      case 'manager_debt_add':
        return NotificationKind.managerDebt;
      case 'manager_balance_update':
      case 'manager_balance':
        return NotificationKind.managerBalance;
      default:
        return NotificationKind.other;
    }
  }

  String get rawKey => switch (this) {
        NotificationKind.nearExpiryDigest => 'near_expiry_digest',
        NotificationKind.expiredTodayDigest => 'expired_today_digest',
        NotificationKind.managerDebt => 'manager_debt',
        NotificationKind.managerBalance => 'manager_balance_update',
        NotificationKind.other => 'other',
      };
}

/// إشعار واحد في inbox المحلي. immutable — كل تعديل يعطي نسخة جديدة
/// (copyWith).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.receivedAt,
    this.data = const {},
    this.readAt,
  });

  /// معرّف فريد. من FCM: `message.messageId`. لو ما فيه، نصنع من hash
  /// (kind|title|body|receivedAt) لضمان idempotency.
  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime receivedAt;

  /// payload الـdata من FCM (مسار routing عند الـtap).
  final Map<String, String> data;

  /// null = غير مقروء. DateTime = وقت القراءة.
  final DateTime? readAt;

  bool get isRead => readAt != null;

  AppNotification copyWith({
    DateTime? readAt,
  }) {
    return AppNotification(
      id: id,
      kind: kind,
      title: title,
      body: body,
      receivedAt: receivedAt,
      data: data,
      readAt: readAt ?? this.readAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.rawKey,
        'title': title,
        'body': body,
        'receivedAt': receivedAt.toIso8601String(),
        'data': data,
        if (readAt != null) 'readAt': readAt!.toIso8601String(),
      };

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    final rawData = j['data'];
    final data = <String, String>{};
    if (rawData is Map) {
      for (final e in rawData.entries) {
        data[e.key.toString()] = e.value?.toString() ?? '';
      }
    }
    return AppNotification(
      id: j['id']?.toString() ?? '',
      kind: NotificationKind.fromString(j['kind']?.toString()),
      title: j['title']?.toString() ?? '',
      body: j['body']?.toString() ?? '',
      receivedAt: DateTime.tryParse(j['receivedAt']?.toString() ?? '') ??
          DateTime.now(),
      data: data,
      readAt: j['readAt'] != null
          ? DateTime.tryParse(j['readAt'].toString())
          : null,
    );
  }

  /// Build from an FCM RemoteMessage payload (foreground/opened).
  /// [now] injection عشان الاختبار.
  static AppNotification fromFcmPayload({
    required String? messageId,
    required String? title,
    required String? body,
    required Map<String, dynamic>? data,
    DateTime? now,
  }) {
    final ts = now ?? DateTime.now();
    final normalizedData = <String, String>{};
    if (data != null) {
      for (final e in data.entries) {
        normalizedData[e.key.toString()] = e.value?.toString() ?? '';
      }
    }
    final kind = NotificationKind.fromString(normalizedData['type']);
    // نبني id ثابت لو messageId موجود، وإلا hash ثابت من المحتوى + ts
    // (بدقة ثانية) — يبقى idempotent لو نفس الرسالة وصلت مرّتين.
    final safeId = (messageId != null && messageId.isNotEmpty)
        ? messageId
        : '${kind.rawKey}|${title ?? ''}|${body ?? ''}|${ts.millisecondsSinceEpoch ~/ 1000}'
            .hashCode
            .toRadixString(16);
    return AppNotification(
      id: safeId,
      kind: kind,
      title: title ?? '',
      body: body ?? '',
      receivedAt: ts,
      data: normalizedData,
    );
  }

  /// serialization utilities للاستخدام في inbox_service
  static String encodeList(List<AppNotification> list) =>
      jsonEncode(list.map((n) => n.toJson()).toList());

  static List<AppNotification> decodeList(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => AppNotification.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
