import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/services/storage_service.dart';
import '../core/services/socket_service.dart';
import '../core/services/expiry_push_service.dart';
import '../core/services/fcm_service.dart';
import '../models/user_model.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

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

  AuthNotifier(this._storage, this._socket) : super(const AuthState());

  Future<void> checkAuth() async {
    try {
      final isLoggedIn = await _storage.isLoggedIn();
      if (!isLoggedIn) {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          clearError: true,
        );
        return;
      }
      final token = await _storage.getToken();
      final adminId = await _storage.getAdminId();
      final username = await _storage.getAdminUsername();
      final expiry = await _storage.getTokenExpiry();

      if (token == null || adminId == null) {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          clearError: true,
        );
        return;
      }

      final user = UserModel(
        id: adminId,
        username: username ?? '',
        role: 'admin',
        token: token,
        expiresAt: expiry ?? '',
      );
      _socket.connect(adminId);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        error: null,
      );
      Future.microtask(() {
        ExpiryPushService.onLoggedIn(_storage);
        FcmService.onLoggedIn(_storage);
      });
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
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

        await _storage.saveAll(
          token: user.token,
          expiresAt: user.expiresAt,
          adminId: user.id,
          adminUsername: user.username,
        );

        _socket.connect(user.id);
        await ExpiryPushService.onLoggedIn(_storage);
        FcmService.onLoggedIn(_storage);

        state = AuthState(
          status: AuthStatus.authenticated,
          user: user,
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
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.read(storageServiceProvider),
    ref.read(socketServiceProvider),
  );
});
