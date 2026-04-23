import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../core/services/fcm_service.dart';
import '../core/services/socket_service.dart';
import '../core/services/storage_service.dart';
import '../models/app_notification_model.dart';

class AppNotificationsState {
  final List<AppNotificationModel> notifications;
  final bool isLoading;
  final String? error;
  final int lastSeenId;
  // Locally-dismissed notification ids. Not sent to the server — the
  // activity_logs rows stay intact as an audit trail; this is purely a
  // view filter so tapping "مسح" or swiping hides them from the bell.
  final Set<int> dismissedIds;

  const AppNotificationsState({
    this.notifications = const [],
    this.isLoading = false,
    this.error,
    this.lastSeenId = 0,
    this.dismissedIds = const <int>{},
  });

  /// The notifications shown to the user — what's left after removing
  /// anything the user has dismissed locally. The raw list stays in
  /// `notifications` so the loader can still compare against it when
  /// new data arrives.
  List<AppNotificationModel> get visibleNotifications => notifications
      .where((n) => !dismissedIds.contains(n.id))
      .toList(growable: false);

  /// Unread = visible AND newer than lastSeenId. Dismissed rows don't
  /// count — if you swiped it away you don't want the badge reminding
  /// you about it.
  int get unreadCount => notifications
      .where((n) => !dismissedIds.contains(n.id) && n.id > lastSeenId)
      .length;

  AppNotificationsState copyWith({
    List<AppNotificationModel>? notifications,
    bool? isLoading,
    String? error,
    int? lastSeenId,
    Set<int>? dismissedIds,
    bool clearError = false,
  }) {
    return AppNotificationsState(
      notifications: notifications ?? this.notifications,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
      lastSeenId: lastSeenId ?? this.lastSeenId,
      dismissedIds: dismissedIds ?? this.dismissedIds,
    );
  }
}

class AppNotificationsNotifier extends StateNotifier<AppNotificationsState> {
  final Dio _dio;
  final SocketService _socket;
  final StorageService _storage;
  StreamSubscription<Map<String, dynamic>>? _socketSub;

  AppNotificationsNotifier(this._dio, this._socket, this._storage)
      : super(const AppNotificationsState()) {
    _listenToSocket();
  }

  // Types the bell surfaces to the admin. Extend here whenever the
  // server adds a new buildManagerFinancialNotificationPayload branch so
  // the client doesn't silently drop valid notifications.
  static const Set<String> _supportedTypes = {
    'cash_deposit',
    'loan_deposit',
    'pay_debt',
    'near_expiry',
    'expired_today',
  };

  bool _shouldInclude(AppNotificationModel notification) =>
      _supportedTypes.contains(notification.type);

  void _listenToSocket() {
    _socketSub = _socket.appNotifications.listen((payload) {
      final notification = AppNotificationModel.fromJson(payload);
      if (notification.id <= 0) return;
      if (!_shouldInclude(notification)) return;
      final existing = state.notifications;
      if (existing.any((item) => item.id == notification.id)) return;

      final next = [notification, ...existing];
      state = state.copyWith(
        notifications: next.take(50).toList(),
        clearError: true,
      );

      unawaited(FcmService.showAppNotificationAlert(notification));
    });
  }

  Future<void> loadNotifications({bool silent = false}) async {
    final adminId = await _storage.getAdminId();
    if (adminId == null || adminId.isEmpty) {
      state = const AppNotificationsState();
      return;
    }

    if (!silent) {
      state = state.copyWith(isLoading: true, clearError: true);
    }

    try {
      final response = await _dio.get(
        '${ApiConstants.managerFinancialNotifications}?limit=40',
      );
      final data = response.data;
      final items = data is Map && data['notifications'] is List
          ? (data['notifications'] as List)
              .whereType<Map>()
              .map((item) =>
                  AppNotificationModel.fromJson(Map<String, dynamic>.from(item)))
              .where(_shouldInclude)
              .toList()
          : <AppNotificationModel>[];

      final lastSeenId =
          await _storage.getLastSeenAppNotificationId(adminId);
      final dismissed =
          await _storage.getDismissedAppNotificationIds(adminId);

      state = state.copyWith(
        notifications: items,
        lastSeenId: lastSeenId,
        dismissedIds: dismissed,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: 'تعذر تحميل إشعارات التطبيق',
      );
    }
  }

  Future<void> markAllSeen() async {
    final adminId = await _storage.getAdminId();
    if (adminId == null || adminId.isEmpty || state.notifications.isEmpty) {
      return;
    }

    final highestId = state.notifications.first.id;
    await _storage.saveLastSeenAppNotificationId(adminId, highestId);
    state = state.copyWith(lastSeenId: highestId);
  }

  /// Hide a single notification from the bell list. Persisted so it
  /// stays hidden on app restart and the next /manager-financial fetch
  /// doesn't re-surface it.
  Future<void> dismiss(int id) async {
    final adminId = await _storage.getAdminId();
    if (adminId == null || adminId.isEmpty) return;
    final next = {...state.dismissedIds, id};
    await _storage.saveDismissedAppNotificationIds(adminId, next);
    state = state.copyWith(dismissedIds: next);
  }

  /// Clear the bell entirely — dismisses every currently-loaded id.
  /// New notifications arriving later (higher ids) still show up.
  Future<void> dismissAll() async {
    final adminId = await _storage.getAdminId();
    if (adminId == null || adminId.isEmpty) return;
    final ids = state.notifications.map((n) => n.id).toSet();
    final next = {...state.dismissedIds, ...ids};
    await _storage.saveDismissedAppNotificationIds(adminId, next);
    // Also bump lastSeenId so the red badge clears immediately even if
    // the user never opened the sheet before dismissing all.
    final highestId = state.notifications.isEmpty
        ? state.lastSeenId
        : state.notifications.first.id;
    if (highestId > state.lastSeenId) {
      await _storage.saveLastSeenAppNotificationId(adminId, highestId);
    }
    state = state.copyWith(
      dismissedIds: next,
      lastSeenId: highestId,
    );
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    super.dispose();
  }
}

final appNotificationsProvider = StateNotifierProvider<AppNotificationsNotifier,
    AppNotificationsState>((ref) {
  return AppNotificationsNotifier(
    ref.read(backendDioProvider),
    ref.read(socketServiceProvider),
    ref.read(storageServiceProvider),
  );
});
