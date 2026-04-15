class AppConstants {
  static const String appName = 'MyServices Radius';
  static const String appNameAr = 'ماي سيرفسز';

  static const String storageToken = 'token';
  static const String storageTokenExpiry = 'tokenExpiresAt';
  static const String storageAdminId = 'adminId';
  static const String storageAdminUsername = 'adminUsername';
  static const String storageThemeMode = 'themeMode';
  static const String storageServerUrl = 'serverUrl';
  static const String storageRememberMe = 'rememberMe';
  static const String storageSavedUsername = 'savedUsername';
  static const String storageSavedPassword = 'savedPassword';
  static const String storageAlertsEnabled = 'alertsEnabled';

  static const String baghdadTimezone = 'Asia/Baghdad';
  static const int baghdadUtcOffset = 3;

  static const int defaultPageLimit = 20;
  static const int searchMinChars = 2;
}

class MessageTypes {
  static const String debtReminder = 'debt_reminder';
  static const String expiryWarning = 'expiry_warning';
  static const String serviceEnd = 'service_end';
  static const String broadcast = 'broadcast';
  static const String manual = 'manual';
  static const String activationNotice = 'activation_notice';
  static const String payment = 'payment';
  static const String welcomeMessage = 'welcome_message';
  static const String renewal = 'renewal';

  static String getArabicLabel(String type) {
    switch (type) {
      case debtReminder:
        return 'تذكير دين';
      case expiryWarning:
        return 'تحذير انتهاء';
      case serviceEnd:
        return 'انتهاء الخدمة';
      case broadcast:
        return 'تبليغ عام';
      case manual:
        return 'يدوي';
      case activationNotice:
        return 'إشعار تفعيل';
      case payment:
        return 'تسديد';
      case welcomeMessage:
        return 'ترحيب';
      case renewal:
        return 'تجديد';
      default:
        return type;
    }
  }
}

class MessageStatuses {
  static const String pending = 'pending';
  static const String processing = 'processing';
  static const String sent = 'sent';
  static const String failed = 'failed';
  static const String cancelled = 'cancelled';

  static String getArabicLabel(String status) {
    switch (status) {
      case pending:
        return 'قيد الانتظار';
      case processing:
        return 'جاري الإرسال';
      case sent:
        return 'مرسلة';
      case failed:
        return 'فاشلة';
      case cancelled:
        return 'ملغية';
      default:
        return status;
    }
  }
}
