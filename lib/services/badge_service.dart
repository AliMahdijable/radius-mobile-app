import 'package:flutter/foundation.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';

import 'inbox_service.dart';

/// خدمة مزامنة عدد الإشعارات على أيقونة التطبيق (iOS + Samsung/Google
/// Android launchers) مع InboxService.unreadCount.
///
/// المشكلة قبل الإصلاح: iOS badge كان يزيد مع كل push notification لكن
/// لا يُصفَّر عند فتح التطبيق، بينما داخل التطبيق العدد دقيق (يعدّ الـcache
/// المحلي). النتيجة: 12 على الأيقونة و 4 داخل التطبيق.
///
/// الحلّ: نستمع لتغيّرات InboxService.changes وننعكس على badge فوراً.
/// + نُصفّر عند فتح التطبيق (app resume) لضمان التوازن.
class BadgeService {
  BadgeService._();

  static bool _initialized = false;
  static bool _supported = false;

  /// يُستدعى مرّة واحدة من main.dart بعد InboxService.init().
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _supported = await FlutterAppBadger.isAppBadgeSupported();
    } catch (e) {
      _supported = false;
      if (kDebugMode) debugPrint('[BadgeService] isSupported check: $e');
    }
    // مزامنة أوّليّة
    await sync();
    // نستمع لأي تغيير في inbox (إشعار جديد، mark read، mark all read)
    InboxService.changes.addListener(sync);
  }

  /// يزامن الـbadge مع InboxService.unreadCount الحالي.
  /// يُستدعى تلقائياً عند تغيير inbox، ويمكن استدعاؤه يدوياً عند
  /// app resume من WidgetsBindingObserver.
  static Future<void> sync() async {
    if (!_supported) return;
    final count = InboxService.unreadCount;
    try {
      if (count == 0) {
        await FlutterAppBadger.removeBadge();
      } else {
        await FlutterAppBadger.updateBadgeCount(count);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BadgeService] sync failed: $e');
    }
  }

  /// يمسح الـbadge نهائياً (مثلاً عند logout).
  static Future<void> clear() async {
    if (!_supported) return;
    try {
      await FlutterAppBadger.removeBadge();
    } catch (_) {}
  }
}
