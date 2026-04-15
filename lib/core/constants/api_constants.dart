class ApiConstants {
  static const String backendUrl = 'https://rad.mysvcs.net';
  static const String sas4ApiUrl =
      'https://reseller-supernet.net/admin/api/index.php/api';
  static const String socketUrl = 'https://rad.mysvcs.net';

  static const String sas4EncryptionKey =
      'abcdefghijuklmno0123456789012345';

  // Auth
  static const String login = '/api/auth/login';
  static const String refreshToken = '/api/auth/refresh-token';
  static const String verifyToken = '/api/auth/verify-token';

  // Subscribers
  static const String subscribersWithPhones = '/api/subscribers/with-phones';
  static const String subscribersSearch = '/api/subscribers/search';
  static const String lastPayments = '/api/subscribers/last-payments';

  // WhatsApp Connection
  static const String waStartSession = '/api/whatsapp/start-session';
  static const String waReconnect = '/api/whatsapp/reconnect';
  static const String waDisconnect = '/api/whatsapp/disconnect';
  static const String waConnectionStatus = '/api/whatsapp/connection-status';
  static const String waPendingQr = '/api/whatsapp/pending-qr';
  static const String waGetQr = '/api/whatsapp/get-qr';

  // WhatsApp Messaging
  static const String waSendMessage = '/api/whatsapp/send-message';
  static const String waBroadcast = '/api/whatsapp/broadcast';
  static const String waBroadcastCancel = '/api/whatsapp/broadcast/cancel';
  static const String waClearPending = '/api/whatsapp/clear-pending';
  static const String waRetryMessage = '/api/whatsapp/retry-message';
  static const String waMessageLogs = '/api/whatsapp/message-logs';
  static const String waQueueStatus = '/api/whatsapp/queue-status';

  // Templates
  static const String waTemplates = '/api/whatsapp/templates';
  static const String waSaveTemplate = '/api/whatsapp/save-template';
  static const String waTemplate = '/api/whatsapp/template';
  static const String waTemplateToggle = '/api/whatsapp/template-toggle';

  // Schedules
  static const String waSchedules = '/api/whatsapp/schedules';
  static const String waSchedule = '/api/whatsapp/schedule';
  static const String waSaveSchedule = '/api/whatsapp/save-schedule';
  static const String waScheduleToggle = '/api/whatsapp/schedule-toggle';
  static const String waScheduledLogs = '/api/whatsapp/scheduled-logs';
  static const String waScheduledStats = '/api/whatsapp/scheduled-stats';
  static const String waTriggerSchedule = '/api/whatsapp/trigger-schedule';

  // Features
  static const String waSaveFeatures = '/api/whatsapp/save-features';
  static const String waGetFeatures = '/api/whatsapp/get-features';
  static const String waVerifyTokens = '/api/whatsapp/verify-tokens';

  // Activities
  static const String activities = '/api/activities';
  static const String dailyActivations = '/api/activities/daily-activations';
  static const String activityStats = '/api/activities/statistics';

  // Discounts
  static const String discounts = '/api/discounts';

  // Reports
  static const String financeReport = '/api/reports/finance';
  static const String accountStatement = '/api/reports/account-statement';

  // User Info Link
  static const String generateUserLink = '/api/generate-user-link';

  // Settings
  static const String settingsTheme = '/api/settings/theme';
  static const String settingsDashboard = '/api/settings/dashboard';

  // SAS4 Direct Endpoints
  static const String sas4ListUsers = '/index/user';
  static const String sas4GetUser = '/user';
  static const String sas4UserOverview = '/user/overview';
  static const String sas4ActivateUser = '/user/activate';
  static const String sas4ExtendUser = '/user/extend';
  static const String sas4DisableUser = '/user/disable';
  static const String sas4EnableUser = '/user/enable';
  static const String sas4ChangeProfile = '/user/changeProfile';
  static const String sas4UserDebt = '/user/debt';
  static const String sas4RenameUser = '/user/rename';
  static const String sas4ExtensionData = '/user/extensionData';
  static const String sas4ActivationData = '/user/activationData';
  static const String sas4OnlineUsers = '/index/online';
  static const String sas4Profiles = '/index/profile';
  static const String sas4Managers = '/index/manager';
  static const String sas4ManagerTree = '/manager/tree';
  static const String sas4UserSessions = '/index/UserSessions';
  static const String sas4Auth = '/auth';

  static const String sas4AllowedExtensions = '/allowedExtensions';
  static const String sas4ProfileDetail = '/profile';
  static const String sas4ListProfile = '/list/profile/5';

  // SAS4 Simple GET endpoints (no encryption)
  static const String sas4PriceList = '/priceList';

  // SAS4 Widget endpoints (simple GET, no encryption)
  static const String sas4WdUsersCount = '/widgetData/internal/wd_users_count';
  static const String sas4WdActiveCount = '/widgetData/internal/wd_users_active_count';
  static const String sas4WdExpiredCount = '/widgetData/internal/wd_users_expired_count';
  static const String sas4WdOnline = '/widgetData/internal/wd_users_online';
  static const String sas4WdBalance = '/widgetData/internal/wd_balance';
  static const String sas4WdRewardPoints = '/widgetData/internal/wd_reward_points';
}
