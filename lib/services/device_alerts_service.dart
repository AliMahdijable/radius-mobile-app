import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/colors.dart';

/// نوع الـalert.
enum DeviceAlertKind {
  offline, // جهاز فصل (online → offline)
  online, // جهاز عاد (offline → online) — recovery
}

class DeviceAlert {
  final int id; // timestamp millis كـID
  final int deviceId;
  final String deviceName;
  final String deviceIp;
  final DeviceAlertKind kind;
  final DateTime at;
  final bool read;

  const DeviceAlert({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.deviceIp,
    required this.kind,
    required this.at,
    this.read = false,
  });

  DeviceAlert copyWith({bool? read}) => DeviceAlert(
        id: id,
        deviceId: deviceId,
        deviceName: deviceName,
        deviceIp: deviceIp,
        kind: kind,
        at: at,
        read: read ?? this.read,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'deviceIp': deviceIp,
        'kind': kind.name,
        'at': at.toIso8601String(),
        'read': read,
      };

  factory DeviceAlert.fromJson(Map<String, dynamic> j) => DeviceAlert(
        id: j['id'] as int,
        deviceId: j['deviceId'] as int,
        deviceName: (j['deviceName'] ?? '').toString(),
        deviceIp: (j['deviceIp'] ?? '').toString(),
        kind: DeviceAlertKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => DeviceAlertKind.offline,
        ),
        at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.now(),
        read: j['read'] == true,
      );
}

/// خدمة **client-side** لإدارة تنبيهات الأجهزة.
///
/// **لا سيرفر ولا FCM** — الموبايل هو الي يفحص، الموبايل هو الي يُنبِّه.
/// المسوّغ: أجهزة LAN خلف NAT، السيرفر ما يقدر يوصلها.
///
/// **آليّة العمل**:
/// 1. NetworkDevicesScreen يعمل probe دوري (كل 60s) لكل الأجهزة
/// 2. لكل جهاز يستدعي [checkTransition] مع الحالة السابقة والحاليّة
/// 3. لو صار transition نُنشئ [DeviceAlert] + OS notification + نُضيفها للـlist
/// 4. الـlist محفوظة في SharedPreferences (آخر 100 alert فقط)
///
/// **الاستخدام**:
/// ```dart
/// await DeviceAlertsService.instance.init();
/// DeviceAlertsService.instance.checkTransition(
///   deviceId: 5, deviceName: 'LR 60', deviceIp: '192.168.1.1',
///   oldStatus: 'online', newStatus: 'offline',
/// );
/// ```
class DeviceAlertsService {
  DeviceAlertsService._();
  static final DeviceAlertsService instance = DeviceAlertsService._();

  static const _prefsKey = 'device_alerts_v1';
  static const _maxAlerts = 100;
  static const _channelId = 'device_alerts';
  static const _channelName = 'تنبيهات الأجهزة';

  final _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  List<DeviceAlert> _alerts = [];

  /// dedup: آخر وقت أُطلق alert لكل (deviceId، kind).
  /// جهاز يومض (يفصل ويعود كل دقيقة) → alerts تنسدّ إذا < 5 دقائق منذ آخر مماثل.
  static const _dedupWindow = Duration(minutes: 5);
  final Map<String, DateTime> _lastFiredAt = {};

  /// عدد الـalerts غير المقروءة — يُستعمل للـbell badge.
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  /// كل الـalerts (من أحدث إلى أقدم) — للـlist screen.
  List<DeviceAlert> get all => List.unmodifiable(_alerts);

  /// تهيئة الخدمة — تُستدعى من main.dart قبل runApp.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // OS notification setup
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false, // نطلبها لاحقاً بعد ما المستخدم يفهم
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _notifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // Load من SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = json.decode(raw) as List;
        _alerts = list
            .whereType<Map>()
            .map((e) => DeviceAlert.fromJson(e.cast<String, dynamic>()))
            .toList();
        _updateUnreadCount();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ DeviceAlertsService init load failed: $e');
    }
  }

  /// اطلب صلاحيّة الإشعارات من OS. تُستدعى مرّة عند فتح صفحة الأجهزة
  /// (بدل عند startup — عشان المستخدم يعرف ليش نطلبها).
  Future<bool> requestPermission() async {
    if (!_initialized) await init();
    // Android 13+
    final androidGranted = await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    // iOS
    final iosGranted = await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    return (androidGranted ?? true) && (iosGranted ?? true);
  }

  /// النقطة الرئيسيّة — يُستدعى بعد كل probe. يرصد التغيّرات.
  ///
  /// - `oldStatus` = 'unknown' (فحص أوّل) → لا alert (نتجنّب spam ابتدائي)
  /// - online → offline → alert offline + OS notification
  /// - offline → online → alert recovery (info، بدون صوت)
  /// - نفس الحالة → لا شيء
  Future<void> checkTransition({
    required int deviceId,
    required String deviceName,
    required String deviceIp,
    required String oldStatus,
    required String newStatus,

    /// 2026-08-18: bypass dedup للاختبار من UI (long-press على البيل).
    /// المستخدم يظنّ الإشعارات مكسورة لو dedup يُسكت الاختبار الثاني.
    bool bypassDedup = false,
  }) async {
    if (!_initialized) await init();
    // نتجنّب أول فحص (unknown → x) — spam خطير عند تركيب التطبيق
    if (oldStatus == 'unknown' || oldStatus.isEmpty) return;
    if (oldStatus == newStatus) return;

    DeviceAlertKind? kind;
    if (oldStatus == 'online' && newStatus == 'offline') {
      kind = DeviceAlertKind.offline;
    } else if (oldStatus == 'offline' && newStatus == 'online') {
      kind = DeviceAlertKind.online;
    }
    if (kind == null) return;

    // dedup: نمنع نفس (deviceId، kind) خلال 5 دقائق — يحمي من spam جهاز flapping
    final dedupKey = '$deviceId:${kind.name}';
    if (!bypassDedup) {
      final lastFired = _lastFiredAt[dedupKey];
      if (lastFired != null &&
          DateTime.now().difference(lastFired) < _dedupWindow) {
        if (kDebugMode) {
          debugPrint('🔕 dedup: $dedupKey فُلتِر (نفس النوع خلال 5د)');
        }
        return;
      }
    }
    _lastFiredAt[dedupKey] = DateTime.now();

    final alert = DeviceAlert(
      id: DateTime.now().millisecondsSinceEpoch,
      deviceId: deviceId,
      deviceName: deviceName,
      deviceIp: deviceIp,
      kind: kind,
      at: DateTime.now(),
    );

    _alerts.insert(0, alert);
    if (_alerts.length > _maxAlerts) {
      _alerts = _alerts.sublist(0, _maxAlerts);
    }
    _updateUnreadCount();
    await _persist();
    // 2026-08-18: أُلغي OS notification صراحةً — طلب المستخدم:
    // "تنبيهات الأجهزة **داخل التطبيق فقط**" (bell badge + list في
    // shell التطبيق). لا نريد push من نوع FCM/local-OS لهذه الفئة.
    // النقل: _showOsNotification موجود لكن غير مستدعى — احتياط لو غيّرنا
    // الرأي لاحقاً.
    // await _showOsNotification(alert);
  }

  Future<void> markAllRead() async {
    _alerts = _alerts.map((a) => a.copyWith(read: true)).toList();
    _updateUnreadCount();
    await _persist();
  }

  Future<void> markRead(int id) async {
    final idx = _alerts.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    _alerts[idx] = _alerts[idx].copyWith(read: true);
    _updateUnreadCount();
    await _persist();
  }

  Future<void> dismiss(int id) async {
    _alerts.removeWhere((a) => a.id == id);
    _updateUnreadCount();
    await _persist();
  }

  Future<void> clear() async {
    _alerts.clear();
    _updateUnreadCount();
    await _persist();
  }

  /// Reset كامل — للاستدعاء عند logout. يُفرغ الـalerts + dedup map
  /// + يمسح OS notifications + يعيد unreadCount إلى 0.
  /// المدير التالي ما يرث أي تنبيهات من السابق. 2026-08-18.
  Future<void> reset() async {
    _alerts.clear();
    _lastFiredAt.clear();
    unreadCount.value = 0;
    try {
      await _notifications.cancelAll(); // يمسح إشعارات OS المعلّقة
    } catch (_) {/* best-effort */}
    await _persist(); // يحفظ الـempty list ليُبقي storage نظيف
  }

  void _updateUnreadCount() {
    unreadCount.value = _alerts.where((a) => !a.read).length;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = json.encode(_alerts.map((a) => a.toJson()).toList());
      await prefs.setString(_prefsKey, raw);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ DeviceAlertsService persist failed: $e');
    }
  }

  Future<void> _showOsNotification(DeviceAlert a) async {
    final isOffline = a.kind == DeviceAlertKind.offline;
    final title = isOffline
        ? '⚠️ جهاز فصل: ${a.deviceName}'
        : '✅ عاد للاتصال: ${a.deviceName}';
    final body = isOffline
        ? '${a.deviceIp} لم يستجب — تحقّق فوراً'
        : '${a.deviceIp} صار متّصل';

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'تنبيهات عندما جهاز يفصل أو يعود',
      importance: isOffline ? Importance.high : Importance.defaultImportance,
      priority: isOffline ? Priority.high : Priority.defaultPriority,
      color: isOffline ? AppColors.error : AppColors.success,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    try {
      await _notifications.show(
        a.id.remainder(0x7FFFFFFF), // int32 safe
        title, body,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ OS notification failed: $e');
    }
  }
}
