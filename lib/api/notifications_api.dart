import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// تفضيلات الإشعارات لكل أدمن. الـbackend يخزّنها في
/// admin_notification_prefs. الـfields:
///   • pushNearExpiry — تذكير اقتراب انتهاء اشتراك
///   • pushExpiredToday — تنبيه انتهاء اشتراك اليوم
///   • pushManagerDebt — تنبيه دين مدير فرعي
///   • quietHoursEnabled — تفعيل أوقات السكون
///   • quietHoursStart/End — "HH:MM" (24h)
class NotificationPrefs {
  const NotificationPrefs({
    required this.pushNearExpiry,
    required this.pushExpiredToday,
    required this.pushManagerDebt,
    required this.quietHoursEnabled,
    required this.quietHoursStart,
    required this.quietHoursEnd,
  });

  final bool pushNearExpiry;
  final bool pushExpiredToday;
  final bool pushManagerDebt;
  final bool quietHoursEnabled;
  final String quietHoursStart;
  final String quietHoursEnd;

  /// قيم افتراضية تستعمل لو الـbackend رجّع null أو الـadmin أول مرة.
  /// مطابقة default الـbackend.
  static const defaults = NotificationPrefs(
    pushNearExpiry: true,
    pushExpiredToday: true,
    pushManagerDebt: true,
    quietHoursEnabled: false,
    quietHoursStart: '22:00',
    quietHoursEnd: '08:00',
  );

  NotificationPrefs copyWith({
    bool? pushNearExpiry,
    bool? pushExpiredToday,
    bool? pushManagerDebt,
    bool? quietHoursEnabled,
    String? quietHoursStart,
    String? quietHoursEnd,
  }) =>
      NotificationPrefs(
        pushNearExpiry: pushNearExpiry ?? this.pushNearExpiry,
        pushExpiredToday: pushExpiredToday ?? this.pushExpiredToday,
        pushManagerDebt: pushManagerDebt ?? this.pushManagerDebt,
        quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
        quietHoursStart: quietHoursStart ?? this.quietHoursStart,
        quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
      );

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) {
    bool b(dynamic v, bool fallback) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) return v == '1' || v.toLowerCase() == 'true';
      return fallback;
    }

    String t(dynamic v, String fallback) {
      if (v == null) return fallback;
      final s = v.toString();
      // الـbackend قد يرجّع "HH:MM:SS" — نقصّ أول 5 خانات فقط.
      return s.length >= 5 ? s.substring(0, 5) : s;
    }

    return NotificationPrefs(
      pushNearExpiry: b(j['push_near_expiry'], true),
      pushExpiredToday: b(j['push_expired_today'], true),
      pushManagerDebt: b(j['push_manager_debt'], true),
      quietHoursEnabled: b(j['quiet_hours_enabled'], false),
      quietHoursStart: t(j['quiet_hours_start'], '22:00'),
      quietHoursEnd: t(j['quiet_hours_end'], '08:00'),
    );
  }
}

class NotificationsApi {
  NotificationsApi._();

  /// GET /api/admin/notification-prefs — يجلب التفضيلات الحالية.
  /// لو الـadmin أول مرة يفتح الإعدادات، الـbackend يعيد defaults.
  static Future<NotificationPrefs?> load() async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/admin/notification-prefs');
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final prefs = body['prefs'];
      if (prefs is! Map) return null;
      return NotificationPrefs.fromJson(Map<String, dynamic>.from(prefs));
    } on DioException catch (e) {
      _log('notification-prefs (GET)', e);
      return null;
    } catch (e) {
      _log('notification-prefs (GET)', e);
      return null;
    }
  }

  /// PUT /api/admin/notification-prefs — يحفظ المفاتيح المعدّلة.
  static Future<({bool ok, String? message, NotificationPrefs? prefs})>
      save(NotificationPrefs p) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/admin/notification-prefs',
        data: {
          'pushNearExpiry': p.pushNearExpiry,
          'pushExpiredToday': p.pushExpiredToday,
          'pushManagerDebt': p.pushManagerDebt,
          'quietHoursEnabled': p.quietHoursEnabled,
          'quietHoursStart': p.quietHoursStart,
          'quietHoursEnd': p.quietHoursEnd,
        },
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      NotificationPrefs? returned;
      final returnedRaw = body['prefs'];
      if (returnedRaw is Map) {
        returned = NotificationPrefs.fromJson(
            Map<String, dynamic>.from(returnedRaw));
      }
      return (
        ok: ok,
        message: body['message']?.toString(),
        prefs: returned,
      );
    } on DioException catch (e) {
      _log('notification-prefs (PUT)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر الحفظ', prefs: null);
    } catch (e) {
      _log('notification-prefs (PUT)', e);
      return (ok: false, message: 'تعذّر الحفظ', prefs: null);
    }
  }

  static void _log(String endpoint, Object err) {
    if (kReleaseMode) return;
    if (err is DioException) {
      debugPrint(
        '🔴 $endpoint: status=${err.response?.statusCode} body=${err.response?.data}',
      );
    } else {
      debugPrint('🔴 $endpoint: $err');
    }
  }
}
