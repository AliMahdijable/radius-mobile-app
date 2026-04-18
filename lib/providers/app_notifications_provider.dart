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

  const AppNotificationsState({
    this.notifications = const [],
    this.isLoading = false,
    this.error,
    this.lastSeenId = 0,
  });

  int get unreadCount =>
      notifications.where((notification) => notification.id > lastSeenId).length;

  AppNotificationsState copyWith({
    List<AppNotificationModel>? notifications,
    bool? isLoading,
    String? error,
    int? lastSeenId,
    bool clearError = false,
  }) {
    return AppNotificationsState(
      notifications: notifications ?? this.notifications,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
      lastSeenId: lastSeenId ?? this.lastSeenId,
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

  static const Set<String> _supportedTypes = {
    'cash_deposit',
    'loan_deposit',
    'pay_debt',
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

      state = state.copyWith(
        notifications: items,
        lastSeenId: lastSeenId,
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
