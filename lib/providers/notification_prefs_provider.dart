import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/dio_client.dart';
import '../models/notification_prefs.dart';

/// Cached once per app session — the settings screen invalidates on
/// save. keepAlive means navigating away and coming back doesn't
/// re-hit the API unnecessarily.
final notificationPrefsProvider =
    FutureProvider.autoDispose<NotificationPrefs>((ref) async {
  ref.keepAlive();
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.get('/api/admin/notification-prefs');
    final data = res.data;
    if (data is Map && data['success'] == true && data['prefs'] is Map) {
      return NotificationPrefs.fromJson(Map<String, dynamic>.from(data['prefs']));
    }
    return NotificationPrefs.defaults;
  } catch (_) {
    return NotificationPrefs.defaults;
  }
});

Future<bool> saveNotificationPrefs(
  WidgetRef ref,
  NotificationPrefs prefs,
) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.put(
      '/api/admin/notification-prefs',
      data: prefs.toSaveJson(),
    );
    final ok = res.data is Map && res.data['success'] == true;
    if (ok) ref.invalidate(notificationPrefsProvider);
    return ok;
  } on DioException {
    return false;
  }
}
