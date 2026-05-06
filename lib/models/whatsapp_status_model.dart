class WhatsAppStatusModel {
  final bool connected;
  final String? phone;
  final String? pushname;
  final String? platform;
  final bool reconnecting;
  final bool stabilizing;

  const WhatsAppStatusModel({
    this.connected = false,
    this.phone,
    this.pushname,
    this.platform,
    this.reconnecting = false,
    this.stabilizing = false,
  });

  factory WhatsAppStatusModel.fromJson(Map<String, dynamic> json) {
    return WhatsAppStatusModel(
      connected: json['connected'] == true,
      phone: json['phone']?.toString(),
      pushname: json['pushname']?.toString(),
      platform: json['platform']?.toString(),
      reconnecting: json['reconnecting'] == true,
      stabilizing: json['stabilizing'] == true,
    );
  }

  WhatsAppStatusModel copyWith({
    bool? connected,
    String? phone,
    String? pushname,
    String? platform,
    bool? reconnecting,
    bool? stabilizing,
  }) {
    return WhatsAppStatusModel(
      connected: connected ?? this.connected,
      phone: phone ?? this.phone,
      pushname: pushname ?? this.pushname,
      platform: platform ?? this.platform,
      reconnecting: reconnecting ?? this.reconnecting,
      stabilizing: stabilizing ?? this.stabilizing,
    );
  }
}

class FeaturesModel {
  /// Master switch — لو false يتجاوز الـbackend كل الـflags الفردية
  /// وما يبعث أي إشعار. الافتراضي true عشان السلوك القديم ما ينكسر.
  final bool notificationsEnabled;
  final bool sendOnActivation;
  final bool expiryReminder;
  final bool debtReminder;
  final bool serviceEndNotification;
  final bool welcomeMessage;
  final bool sendOnExtension;

  const FeaturesModel({
    this.notificationsEnabled = true,
    this.sendOnActivation = false,
    this.expiryReminder = false,
    this.debtReminder = false,
    this.serviceEndNotification = false,
    this.welcomeMessage = false,
    this.sendOnExtension = false,
  });

  factory FeaturesModel.fromJson(Map<String, dynamic> json) {
    // notificationsEnabled غايب من الـAPI القديم → نعتبر مفعّل افتراضياً.
    final notif = json['notificationsEnabled'];
    return FeaturesModel(
      notificationsEnabled: notif == null ? true : notif == true,
      sendOnActivation: json['sendOnActivation'] == true,
      expiryReminder: json['expiryReminder'] == true,
      debtReminder: json['debtReminder'] == true,
      serviceEndNotification: json['serviceEndNotification'] == true,
      welcomeMessage: json['welcomeMessage'] == true,
      sendOnExtension: json['sendOnExtension'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'notificationsEnabled': notificationsEnabled,
        'sendOnActivation': sendOnActivation,
        'expiryReminder': expiryReminder,
        'debtReminder': debtReminder,
        'serviceEndNotification': serviceEndNotification,
        'welcomeMessage': welcomeMessage,
        'sendOnExtension': sendOnExtension,
      };

  FeaturesModel copyWith({
    bool? notificationsEnabled,
    bool? sendOnActivation,
    bool? expiryReminder,
    bool? debtReminder,
    bool? serviceEndNotification,
    bool? welcomeMessage,
    bool? sendOnExtension,
  }) {
    return FeaturesModel(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      sendOnActivation: sendOnActivation ?? this.sendOnActivation,
      expiryReminder: expiryReminder ?? this.expiryReminder,
      debtReminder: debtReminder ?? this.debtReminder,
      serviceEndNotification:
          serviceEndNotification ?? this.serviceEndNotification,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
      sendOnExtension: sendOnExtension ?? this.sendOnExtension,
    );
  }
}
