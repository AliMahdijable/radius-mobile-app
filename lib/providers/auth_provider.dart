import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/services/session_refresh_service.dart';
import '../core/services/storage_service.dart';
import '../core/services/socket_service.dart';
import '../core/services/expiry_push_service.dart';
import '../core/services/fcm_service.dart';
import '../models/user_model.dart';
import 'dashboard_provider.dart';
import 'discounts_provider.dart';
import 'app_notifications_provider.dart';
import 'messages_provider.dart';
import 'managers_provider.dart';
import 'print_templates_provider.dart';
import 'reports_provider.dart';
import 'schedules_provider.dart';
import 'settings_provider.dart';
import 'subscribers_provider.dart';
import 'templates_provider.dart';
import 'whatsapp_provider.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class _PermissionAccess {
  final List<String> permissions;
  final bool canAccessManagers;
  final bool canAccessPackages;

  const _PermissionAccess({
    this.permissions = const [],
    this.canAccessManagers = false,
    this.canAccessPackages = false,
  });
}

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? error;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final StorageService _storage;
  final SocketService _socket;
  final Ref _ref;

  AuthNotifier(this._storage, this._socket, this._ref)
      : super(const AuthState());

  Future<_PermissionAccess> _fetchPermissions(String token) async {
    final dio = Dio(BaseOptions(
      baseUrl: ApiConstants.sas4ApiUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json'},
    ));

    try {
      final response = await dio.get(
        ApiConstants.sas4Auth,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'X-Auth-Token': token,
          },
        ),
      );

      final raw = response.data;
      final rawPermissions =
          raw is Map && raw['permissions'] is List ? raw['permissions'] as List : const [];
      final permissions = rawPermissions
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
      final access = _PermissionAccess(
        permissions: permissions,
        canAccessManagers: permissions.contains('prm_managers_create'),
        canAccessPackages: permissions.contains('prm_profiles_create'),
      );

      dev.log(
        'Fetched permissions: ${access.permissions.join(', ')} | canAccessManagers=${access.canAccessManagers} | canAccessPackages=${access.canAccessPackages}',
        name: 'AUTH',
      );

      await _storage.savePermissions(access.permissions);
      await _storage.saveCanAccessManagers(access.canAccessManagers);
      await _storage.saveCanAccessPackages(access.canAccessPackages);
      return access;
    } catch (_) {
      dev.log(
        'Failed to fetch permissions from SAS4, using cached values instead.',
        name: 'AUTH',
      );
      return _PermissionAccess(
        permissions: await _storage.getPermissions(),
        canAccessManagers: await _storage.getCanAccessManagers(),
        canAccessPackages: await _storage.getCanAccessPackages(),
      );
    } finally {
      dio.close();
    }
  }

  void _resetSessionScopedProviders() {
    _ref.invalidate(dashboardProvider);
    _ref.invalidate(subscribersProvider);
    _ref.invalidate(managersProvider);
    _ref.invalidate(whatsappProvider);
    _ref.invalidate(templatesProvider);
    _ref.invalidate(printTemplatesProvider);
    _ref.invalidate(messagesProvider);
    _ref.invalidate(appNotificationsProvider);
    _ref.invalidate(reportsProvider);
    _ref.invalidate(discountsProvider);
    _ref.invalidate(settingsProvider);
    _ref.invalidate(schedulesProvider);
  }

  Future<void> _syncNotificationServices() async {
    final notificationsEnabled = await _storage.getFcmEnabled();
    if (!notificationsEnabled) return;

    if (!await _storage.getPushExpiryOutsideEnabled()) {
      await _storage.setPushExpiryOutsideEnabled(true);
    }

    await ExpiryPushService.onLoggedIn(_storage);
    await FcmService.onLoggedIn(_storage);
  }

  Future<void> checkAuth() async {
    try {
      final session = await SessionRefreshService.ensureValidSession(_storage);
      final token = session?.token;
      final adminId = await _storage.getAdminId();
      final username = await _storage.getAdminUsername();
      final expiry = session?.expiresAt ?? await _storage.getTokenExpiry();

      if (token == null || adminId == null) {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          clearError: true,
        );
        return;
      }

      final access = await _fetchPermissions(token);
      final user = UserModel(
        id: adminId,
        username: username ?? '',
        role: 'admin',
        token: token,
        expiresAt: expiry ?? '',
        permissions: access.permissions,
        canAccessManagers: access.canAccessManagers,
        canAccessPackages: access.canAccessPackages,
      );
      _resetSessionScopedProviders();
      _socket.disconnect();
      _socket.connect(adminId);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        error: null,
      );
      Future.microtask(() {
        _syncNotificationServices();
      });
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        clearError: true,
      );
    }
  }

  Future<void> syncSessionState() async {
    final session = await SessionRefreshService.ensureValidSession(_storage);
    final token = session?.token;
    final adminId = await _storage.getAdminId();
    final username = await _storage.getAdminUsername();
    final expiry = session?.expiresAt ?? await _storage.getTokenExpiry();

    if (token == null || adminId == null) {
      if (state.status == AuthStatus.authenticated) {
        await handleSessionExpired();
      } else {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          clearError: true,
        );
      }
      return;
    }

    if (state.status != AuthStatus.authenticated || state.user == null) {
      await checkAuth();
      return;
    }

    final currentUser = state.user!;
    if (currentUser.token != token ||
        currentUser.id != adminId ||
        currentUser.username != (username ?? currentUser.username) ||
        (expiry != null && currentUser.expiresAt != expiry)) {
      state = state.copyWith(
        user: currentUser.copyWith(
          id: adminId,
          username: username ?? currentUser.username,
          token: token,
          expiresAt: expiry ?? currentUser.expiresAt,
        ),
        clearError: true,
      );
    }
  }

  Future<bool> login(String username, String password) async {
    final dio = Dio(BaseOptions(
      baseUrl: ApiConstants.backendUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    state = state.copyWith(clearError: true);

    try {
      final response = await dio.post(
        ApiConstants.login,
        data: {'username': username, 'password': password},
      );

      if (response.data['success'] == true) {
        final user = UserModel.fromJson(response.data);
        final access = await _fetchPermissions(user.token);

        await _storage.saveAll(
          token: user.token,
          expiresAt: user.expiresAt,
          adminId: user.id,
          adminUsername: user.username,
          permissions: access.permissions,
          canAccessManagers: access.canAccessManagers,
          canAccessPackages: access.canAccessPackages,
        );

        _resetSessionScopedProviders();
        _socket.disconnect();
        _socket.connect(user.id);
        await _syncNotificationServices();

        state = AuthState(
          status: AuthStatus.authenticated,
          user: user.copyWith(
            permissions: access.permissions,
            canAccessManagers: access.canAccessManagers,
            canAccessPackages: access.canAccessPackages,
          ),
          error: null,
        );
        return true;
      }

      final msg = response.data['message']?.toString() ?? 'فشل تسجيل الدخول';
      state = state.copyWith(status: AuthStatus.unauthenticated, error: msg);
      return false;
    } on DioException catch (_) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: 'خطأ في المعلومات المدخلة',
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: 'خطأ في المعلومات المدخلة',
      );
      return false;
    } finally {
      dio.close();
    }
  }

  Future<void> logout() async {
    _socket.disconnect();
    await FcmService.onLoggedOut();
    await ExpiryPushService.onLoggedOut();
    await _storage.clearAll();
    _resetSessionScopedProviders();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> handleSessionExpired({String? reason}) async {
    if (state.status == AuthStatus.unauthenticated) return;
    _socket.disconnect();
    await FcmService.onLoggedOut();
    await ExpiryPushService.onLoggedOut();
    await _storage.clearAll();
    _resetSessionScopedProviders();
    state = AuthState(
      status: AuthStatus.unauthenticated,
      error: reason ?? 'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
    );
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.read(storageServiceProvider),
    ref.read(socketServiceProvider),
    ref,
  );
});
