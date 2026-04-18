class AppNotificationModel {
  final int id;
  final String type;
  final String actionType;
  final String title;
  final String body;
  final String? senderUsername;
  final String? targetName;
  final String? createdAt;
  final Map<String, dynamic> metadata;

  const AppNotificationModel({
    required this.id,
    required this.type,
    required this.actionType,
    required this.title,
    required this.body,
    this.senderUsername,
    this.targetName,
    this.createdAt,
    this.metadata = const {},
  });

  factory AppNotificationModel.fromJson(Map<String, dynamic> json) {
    final rawMetadata = json['metadata'];
    final metadata = rawMetadata is Map
        ? Map<String, dynamic>.from(rawMetadata)
        : const <String, dynamic>{};

    return AppNotificationModel(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      type: (json['type'] ?? '').toString(),
      actionType: (json['actionType'] ?? json['action_type'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      senderUsername:
          (json['senderUsername'] ?? json['sender_username'])?.toString(),
      targetName: (json['targetName'] ?? json['target_name'])?.toString(),
      createdAt: (json['createdAt'] ?? json['created_at'])?.toString(),
      metadata: metadata,
    );
  }
}
