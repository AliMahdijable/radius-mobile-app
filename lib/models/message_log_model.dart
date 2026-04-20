class MessageLogModel {
  final int id;
  final String adminId;
  final String? recipientUsername;
  final String? recipientFirstname;
  final String? recipientLastname;
  final String? recipientPhone;
  final String? messageContent;
  final String messageType;
  final String status;
  final String? errorMessage;
  final int retryCount;
  final int? maxRetries;
  final String? createdAt;
  final String? processedAt;

  const MessageLogModel({
    required this.id,
    required this.adminId,
    this.recipientUsername,
    this.recipientFirstname,
    this.recipientLastname,
    this.recipientPhone,
    this.messageContent,
    required this.messageType,
    required this.status,
    this.errorMessage,
    this.retryCount = 0,
    this.maxRetries,
    this.createdAt,
    this.processedAt,
  });

  bool get canRetry =>
      status == 'failed' && (maxRetries == null || retryCount < maxRetries!);

  /// "الاسم الأول [الاسم الثاني]" if available, otherwise falls back to the
  /// recipient_name extracted from the message body (عزيزي X،), otherwise
  /// the username so the log row always has a human-readable title.
  String get displayName {
    final parts = [recipientFirstname, recipientLastname]
        .where((p) => p != null && p!.trim().isNotEmpty)
        .map((p) => p!.trim())
        .toList();
    if (parts.isNotEmpty) return parts.join(' ');
    return recipientUsername ?? '';
  }

  bool get hasArabicName =>
      (recipientFirstname != null && recipientFirstname!.trim().isNotEmpty) ||
      (recipientLastname != null && recipientLastname!.trim().isNotEmpty);

  factory MessageLogModel.fromJson(Map<String, dynamic> json) {
    return MessageLogModel(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      adminId: (json['admin_id'] ?? '').toString(),
      recipientUsername: json['recipient_username']?.toString(),
      recipientFirstname:
          (json['recipient_firstname'] ?? json['recipient_name'])?.toString(),
      recipientLastname: json['recipient_lastname']?.toString(),
      recipientPhone: json['recipient_phone']?.toString(),
      messageContent: (json['message_content'] ?? json['message_preview'])?.toString(),
      messageType: (json['message_type'] ?? 'manual').toString(),
      status: (json['status'] ?? 'pending').toString(),
      errorMessage: json['error_message']?.toString(),
      retryCount: json['retry_count'] is int
          ? json['retry_count']
          : int.tryParse(json['retry_count']?.toString() ?? '0') ?? 0,
      maxRetries: json['max_retries'] is int
          ? json['max_retries']
          : int.tryParse(json['max_retries']?.toString() ?? ''),
      createdAt: json['created_at']?.toString(),
      processedAt: json['processed_at']?.toString(),
    );
  }
}

class MessageStats {
  final int sent;
  final int failed;
  final int pending;
  final int cancelled;

  const MessageStats({
    this.sent = 0,
    this.failed = 0,
    this.pending = 0,
    this.cancelled = 0,
  });

  int get total => sent + failed + pending + cancelled;

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  factory MessageStats.fromJson(Map<String, dynamic> json) {
    return MessageStats(
      sent: _toInt(json['sent']),
      failed: _toInt(json['failed']),
      pending: _toInt(json['pending']),
      cancelled: _toInt(json['cancelled']),
    );
  }
}
