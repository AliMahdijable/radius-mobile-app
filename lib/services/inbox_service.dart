import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_notification.dart';

/// Inbox محلي بسيط للـFCM notifications.
///
/// * يخزّن قائمة الإشعارات في ملف JSON داخل ApplicationDocuments.
/// * `changes` ValueNotifier<int> — كل تغيير يزيد value؛ الـUI يلتصق
///   بـValueListenableBuilder ويعيد البناء تلقائياً.
/// * قائمة الإشعارات محدودة بـ200 (LRU trim) — نُبقي الأحدث ونحذف
///   الأقدم. كافية للاستخدام العملي والـfootprint صغير.
/// * كل الـmutations idempotent بـid (add لنفس id → update).
class InboxService {
  InboxService._();

  static const int _maxItems = 200;
  static const String _fileName = 'notifications_inbox.json';

  /// إشارة تغيير — يزيد كل mutation. الـUI يعيد البناء عند التغيّر.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// الحالة داخل الذاكرة. `null` قبل الـinit.
  static List<AppNotification>? _cache;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// يجب استدعاؤها مرة واحدة عند إقلاع التطبيق (main() أو splash) قبل
  /// أي stream من FCM.
  static Future<void> init() async {
    if (_cache != null) return;
    try {
      final f = await _file();
      if (!await f.exists()) {
        _cache = <AppNotification>[];
        return;
      }
      final raw = await f.readAsString();
      _cache = AppNotification.decodeList(raw).toList()
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    } catch (e) {
      if (kDebugMode) debugPrint('InboxService.init failed: $e');
      _cache = <AppNotification>[];
    }
  }

  static List<AppNotification> get all => List.unmodifiable(_cache ?? const []);

  static int get unreadCount =>
      (_cache ?? const []).where((n) => !n.isRead).length;

  /// أضف إشعار جديد. لو الـid موجود مسبقاً، نُبقي الأصلي (idempotent).
  static Future<void> add(AppNotification n) async {
    await init();
    final list = _cache!;
    if (list.any((x) => x.id == n.id)) return;
    list.insert(0, n);
    // LRU trim.
    while (list.length > _maxItems) {
      list.removeLast();
    }
    await _persist();
    changes.value = changes.value + 1;
  }

  /// علّم إشعار كمقروء.
  static Future<void> markRead(String id) async {
    await init();
    final list = _cache!;
    for (int i = 0; i < list.length; i++) {
      if (list[i].id == id && !list[i].isRead) {
        list[i] = list[i].copyWith(readAt: DateTime.now());
        await _persist();
        changes.value = changes.value + 1;
        return;
      }
    }
  }

  /// علّم الكل كمقروء.
  static Future<void> markAllRead() async {
    await init();
    final list = _cache!;
    final now = DateTime.now();
    bool any = false;
    for (int i = 0; i < list.length; i++) {
      if (!list[i].isRead) {
        list[i] = list[i].copyWith(readAt: now);
        any = true;
      }
    }
    if (any) {
      await _persist();
      changes.value = changes.value + 1;
    }
  }

  /// حذف إشعار واحد.
  static Future<void> remove(String id) async {
    await init();
    final list = _cache!;
    final before = list.length;
    list.removeWhere((n) => n.id == id);
    if (list.length != before) {
      await _persist();
      changes.value = changes.value + 1;
    }
  }

  /// تفريغ الـinbox بالكامل.
  static Future<void> clear() async {
    await init();
    _cache!.clear();
    await _persist();
    changes.value = changes.value + 1;
  }

  static Future<void> _persist() async {
    try {
      final f = await _file();
      await f.writeAsString(AppNotification.encodeList(_cache ?? const []));
    } catch (e) {
      if (kDebugMode) debugPrint('InboxService._persist failed: $e');
    }
  }
}
