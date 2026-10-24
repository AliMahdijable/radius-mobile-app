import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../core/platform/app_platform.dart';
import '../core/util/format.dart';
import '../models/app_notification.dart';
import 'auth_storage.dart';
import 'device_alerts_service.dart';
import 'fcm_service.dart';
import 'inbox_service.dart';
import 'notification_router.dart';

/// إشعارات الحاسبة (ويندوز/الماك) — المالك ٢٥ أكتوبر: «الاشعارات مهمه اريده».
///
/// لا FCM على الحاسبة، فلم يكن يصلها إشعارٌ واحد (الجرس يعدّ قرب الانتهاء وحده). الآن:
/// * الجهاز يُسجَّل لدى الخادم بمعرّف تثبيتٍ ثابت (POST /api/push/desktop/register) — صفٌّ في أجهزة الإشعارات يعدّه الخادم
///   «تطبيقاً حاضراً» كالهاتف، فتصله الملخّصات وإشعارات النظام. يُجدَّد كلّ ١٢ ساعة.
/// * كلّ ~٢٠ ثانية وهو مفتوح يقرأ ما أُرسل لمديره بعد آخر ما رآه (GET /api/push/feed): إشعار ويندوز + الجرس — ما يصل
///   الهاتف دفعاً حرفاً (ملخّص الانتهاء، ديون المدراء والرصيد، انقطاع الواتساب، الإعلانات…)، بتفضيلات الإشعارات نفسها.
/// * أوّل قراءةٍ على الجهاز: آخر ٢٤ ساعة للجرس بلا إشعارات. ورجوعٌ بعد غياب أو دفعةٌ كبيرة: إشعارٌ واحد يلخّصها.
/// * المسكَّر لا يقرأ — إشعارات البرنامج المسكَّر بعد المتجر (WNS).
///
/// يُشغَّل ويُطفأ من [FcmService] (initAfterLogin/unregister) — نقطتا الدخول والخروج نفسهما للهاتف.
class DesktopPushService {
  DesktopPushService._();

  static const Duration pollEvery = Duration(seconds: 20);
  static const Duration maxBackoff = Duration(minutes: 5);
  static const Duration reRegisterEvery = Duration(hours: 12);

  /// أقدم من هذا لا يُعرض وحده (وصل والبرنامج مسكَّر) — يدخل ملخّص «أثناء غيابك».
  static const Duration staleAfter = Duration(minutes: 30);

  /// أكثر من هذا في قراءةٍ واحدة ⇒ إشعارٌ واحد بعددها.
  static const int burst = 3;

  static const _installKey = 'desktop_push_install_v1';
  static const _cursorKey = 'desktop_push_cursor_v1:';
  static const _summaryPayload = 'desktop-push:inbox';
  static const _window = MethodChannel('mysvcs/window');

  static Timer? _timer;
  static String? _adminId;
  static int? _cursor;
  static int _failures = 0;
  static int _gen = 0;
  static DateTime? _registeredAt;

  /// الاختبارات: المدير بلا خزنة، وإشعار النظام بلا إضافة.
  @visibleForTesting
  static Future<String?> Function()? debugAdminId;
  @visibleForTesting
  static Future<void> Function(String title, String body, String payload)? debugShow;

  static bool get running => _adminId != null;

  /// بعد الدخول (ومع كلّ تبديل شركة): يربط الجهاز بالمدير الحاليّ ويبدأ القراءة. آمنٌ للتكرار.
  static Future<void> start() async {
    if (!AppPlatform.isDesktop) return;
    final adminId = ((await (debugAdminId ?? AuthStorage.readAdminId)()) ?? '').trim();
    if (adminId.isEmpty) return;
    if (adminId == _adminId) return; // جارٍ للمدير نفسه
    _timer?.cancel();
    final gen = ++_gen;
    _adminId = adminId;
    _failures = 0;
    _registeredAt = null;
    _cursor = await _readCursor(adminId);
    if (debugShow == null) {
      // الإضافة تُهيَّأ مرّةً للتطبيق كلّه (ويندوز: الاسم ومعرّف التطبيق والـGUID) — والنقر يصلنا من هنا.
      await DeviceAlertsService.instance.init();
      DeviceAlertsService.onTap = _onTap;
      await _askMacPermission();
    }
    if (gen != _gen) return;
    await _tick(gen);
  }

  /// الخروج: تتوقّف القراءة، ويُفكّ ربط الجهاز (لا تصله إشعارات حسابٍ خرج منه).
  static Future<void> stop({bool unregister = true}) async {
    final adminId = _adminId;
    _timer?.cancel();
    _timer = null;
    _adminId = null;
    _gen++;
    if (!unregister || adminId == null) return;
    try {
      await ApiClient.dio.post<Map<String, dynamic>>('/api/push/desktop/unregister',
          data: {'adminId': adminId, 'installId': await _installId()});
    } catch (e) {
      if (kDebugMode) debugPrint('DesktopPush unregister failed: $e');
    }
  }

  /// الاختبارات: قراءةٌ واحدة الآن بلا مؤقّت.
  @visibleForTesting
  static Future<void> tickNow() async {
    _timer?.cancel();
    await _tick(_gen);
  }

  @visibleForTesting
  static void reset() {
    _timer?.cancel();
    _timer = null;
    _adminId = null;
    _cursor = null;
    _failures = 0;
    _registeredAt = null;
    _gen++;
  }

  static Future<void> _tick(int gen) async {
    final adminId = _adminId;
    if (gen != _gen || adminId == null) return;
    try {
      if (_registeredAt == null || DateTime.now().difference(_registeredAt!) > reRegisterEvery) {
        await _register(adminId);
      }
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/push/feed', queryParameters: {
        'adminId': adminId,
        if (_cursor != null) 'after': _cursor,
      });
      if (gen != _gen) return;
      final body = r.data ?? const <String, dynamic>{};
      if (body['success'] != true) throw StateError('feed: ${r.statusCode}');
      await _apply(adminId, body);
      _failures = 0;
    } catch (e) {
      _failures++;
      if (kDebugMode) debugPrint('DesktopPush tick failed ($_failures): $e');
    } finally {
      _schedule(gen);
    }
  }

  static void _schedule(int gen) {
    if (gen != _gen || _adminId == null) return;
    _timer?.cancel();
    final secs = _failures == 0
        ? pollEvery.inSeconds
        : min(maxBackoff.inSeconds, pollEvery.inSeconds * (1 << min(_failures, 4)));
    _timer = Timer(Duration(seconds: secs), () => _tick(gen));
  }

  static Future<void> _register(String adminId) async {
    final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/push/desktop/register', data: {
      'adminId': adminId,
      'installId': await _installId(),
      'deviceInfo': AppPlatform.isWindows ? 'Windows' : 'macOS',
    });
    if (r.data?['success'] == true) _registeredAt = DateTime.now();
  }

  static Future<void> _apply(String adminId, Map<String, dynamic> body) async {
    final items = (body['items'] as List?) ?? const [];
    final catchup = body['catchup'] == true;
    final now = DateTime.now();
    final live = <AppNotification>[];
    var missed = 0;
    for (final raw in items.whereType<Map>()) {
      final j = raw.map((k, v) => MapEntry(k.toString(), v));
      final n = fromFeed(j, now: now);
      if (n == null) continue;
      final seen = InboxService.all.any((x) => x.id == n.id);
      await InboxService.add(n);
      if (catchup || seen) continue;
      final age = (j['age_sec'] as num?)?.toInt() ?? 0;
      if (age > staleAfter.inSeconds) {
        missed++;
      } else {
        live.add(n);
      }
    }
    final c = (body['cursor'] as num?)?.toInt();
    if (c != null) {
      _cursor = c;
      await _writeCursor(adminId, c);
    }
    if (missed > 0 || live.length > burst) {
      final total = missed + live.length;
      await _show(
        missed > 0 ? 'وصلتك إشعارات أثناء غيابك' : 'إشعارات جديدة',
        arCount(total, one: 'إشعارٌ واحد', two: 'إشعاران', few: 'إشعارات', many: 'إشعاراً'),
        _summaryPayload,
      );
    } else {
      for (final n in live) {
        await _show(n.title, n.body, n.id);
      }
    }
  }

  /// صفّ الخادم ⇒ إشعار الصندوق نفسه الذي يبنيه FCM (النوع من data.type)، ومعرّفه «feed-<id>» فلا يتكرّر.
  @visibleForTesting
  static AppNotification? fromFeed(Map<String, dynamic> j, {DateTime? now}) {
    final id = (j['id'] as num?)?.toInt();
    if (id == null) return null;
    final age = (j['age_sec'] as num?)?.toInt() ?? 0;
    final data = j['data'] is Map
        ? (j['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    return AppNotification.fromFcmPayload(
      messageId: 'feed-$id',
      title: j['title']?.toString(),
      body: j['body']?.toString(),
      data: data,
      now: (now ?? DateTime.now()).subtract(Duration(seconds: max(0, age))),
    );
  }

  static Future<void> _show(String title, String body, String payload) async {
    final f = debugShow;
    if (f != null) return f(title, body, payload);
    try {
      await FlutterLocalNotificationsPlugin().show(
        payload.hashCode & 0x7FFFFFFF,
        title,
        body,
        const NotificationDetails(
          windows: WindowsNotificationDetails(),
          macOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('DesktopPush show failed: $e');
    }
  }

  /// نقر إشعار النظام: النافذة إلى الأمام (ويندوز لا يقدّمها وحده)، ثمّ وجهة الإشعار كما في الهاتف — والملخّص يفتح الصندوق.
  static void _onTap(NotificationResponse r) {
    final p = r.payload;
    if (p == null || p.isEmpty) return;
    unawaited(_focusWindow());
    if (p == _summaryPayload) {
      unawaited(NotificationRouter.openInbox());
      return;
    }
    for (final n in InboxService.all) {
      if (n.id == p) {
        unawaited(InboxService.markRead(n.id));
        FcmService.onNotificationTap?.call(n);
        return;
      }
    }
  }

  static Future<void> _focusWindow() async {
    if (!AppPlatform.isWindows) return; // الماك يقدّم التطبيق عند النقر بنفسه
    try {
      await _window.invokeMethod<void>('focus');
    } catch (_) {/* نسخةٌ قديمة بلا القناة */}
  }

  static Future<void> _askMacPermission() async {
    if (!AppPlatform.isMacDesktop) return;
    try {
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {}
  }

  static Future<String> _installId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_installKey);
    if (id == null || !RegExp(r'^[A-Za-z0-9-]{8,64}$').hasMatch(id)) {
      final rnd = Random.secure();
      id = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(_installKey, id);
    }
    return id;
  }

  static Future<int?> _readCursor(String adminId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_cursorKey$adminId');
  }

  static Future<void> _writeCursor(String adminId, int cursor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_cursorKey$adminId', cursor);
  }
}
