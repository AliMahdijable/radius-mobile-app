import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
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

/// يُرفع لمّا SAS4 يرفض التوكن المخزَّن (تغيّر باسورد المدير من اللوحة،
/// أو إبطال الجلسة من شاشة "خروج من كل الأجهزة"). يلتقطه checkAuth
/// ويفرض handleSessionExpired.
class _TokenInvalidException implements Exception {
  const _TokenInvalidException();
}

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

  /// يجلب صلاحيات الموظف الفريش من backend (عبر `/api/auth/me`).
  /// نلجأ للـcache بالـstorage فقط لو الفحص فشل بسبب الشبكة. هذا
  /// يضمن إن أي تعديل بصلاحيات الموظف يصل خلال ثوانٍ بدون re-login.
  Future<Map<String, bool>> _fetchFreshEmployeePerms(Map<String, bool> cached) async {
    try {
      final dio = _ref.read(backendDioProvider);
      final response = await dio.get(ApiConstants.authMe);
      final data = response.data;
      if (data is Map && data['success'] == true) {
        final user = data['user'];
        if (user is Map && user['isEmployee'] == true) {
          final raw = user['permissions'];
          if (raw is Map) {
            final fresh = <String, bool>{};
            raw.forEach((k, v) { fresh[k.toString()] = v == true; });
            await _storage.saveEmployeePermissions(fresh);
            dev.log('Refreshed employee perms (${fresh.values.where((v) => v).length} granted)',
                name: 'AUTH');
            return fresh;
          }
        }
      }
    } on DioException catch (e) {
      dev.log('Employee perms refresh failed (${e.response?.statusCode}): ${e.message}',
          name: 'AUTH');
    } catch (e) {
      dev.log('Employee perms refresh unknown error: $e', name: 'AUTH');
    }
    return cached;
  }

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
    } on DioException catch (e) {
      // 401/403 = SAS4 رفض التوكن (الباسورد تغيّر بالـSAS4 بانل، أو الجلسة
      // أُبطلت). نرفع _TokenInvalidException ليلتقطها checkAuth ويفرض
      // تسجيل خروج. أي خطأ آخر (تايم آوت، شبكة) → نلجأ للـcached perms.
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        dev.log('SAS4 rejected token (status=$code) — forcing logout', name: 'AUTH');
        throw _TokenInvalidException();
      }
      dev.log(
        'Failed to fetch permissions (network/timeout): ${e.message} — using cached values',
        name: 'AUTH',
      );
      return _PermissionAccess(
        permissions: await _storage.getPermissions(),
        canAccessManagers: await _storage.getCanAccessManagers(),
        canAccessPackages: await _storage.getCanAccessPackages(),
      );
    } catch (_) {
      dev.log(
        'Failed to fetch permissions from SAS4 (unknown error), using cached values instead.',
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

  /// التوكن مرفوض من SAS4 — ترفعها _fetchPermissions ليتم تسجيل خروج.
  Future<void> _validateAdminToken(String sas4Token) async {
    final dio = Dio(BaseOptions(
      baseUrl: ApiConstants.sas4ApiUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    try {
      final res = await dio.get(
        ApiConstants.sas4Auth,
        options: Options(
          headers: {'Authorization': 'Bearer $sas4Token'},
          // ما نخلي Dio يرمي على status codes — نفحصها يدوياً
          validateStatus: (_) => true,
        ),
      );
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw _TokenInvalidException();
      }
    } on DioException {
      // أخطاء شبكة → نتسامح، ما نطرد المستخدم بسبب انقطاع نت
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

  void _schedulePushResyncRetry() {
    Future<void>.delayed(const Duration(seconds: 4), () async {
      try {
        await _syncNotificationServices(forcePushSync: true);
      } catch (_) {
        // نخلي المحاولة الثانية صامتة حتى لا تربك المستخدم
      }
    });
  }

  Future<void> _syncNotificationServices({bool forcePushSync = false}) async {
    final notificationsEnabled = await _storage.getFcmEnabled();
    if (!notificationsEnabled) return;

    if (!await _storage.getPushExpiryOutsideEnabled()) {
      await _storage.setPushExpiryOutsideEnabled(true);
    }

    // ExpiryPushService على iOS يستخدم Workmanager — لو فشل/عَلَّق ما نريد
    // يقطع تسجيل FCM. نحاصره بـtry/catch.
    try {
      await ExpiryPushService.onLoggedIn(_storage);
    } catch (e) {
      dev.log('ExpiryPushService.onLoggedIn warning: $e');
    }

    await FcmService.syncRegistrationIfNeeded(
      _storage,
      force: forcePushSync,
    );
  }

  Future<void> checkAuth() async {
    try {
      final session = await SessionRefreshService.ensureValidSession(_storage);
      final token = session?.token;
      final adminId = await _storage.getAdminId();
      final username = await _storage.getAdminUsername();
      final expiry = session?.expiresAt ?? await _storage.getTokenExpiry();

      if (token == null || adminId == null) {
        // تسجيل دخول تلقائي: الجلسة مفقودة/منتهية لكن المستخدم حافظ بياناته
        // («حفظ بيانات الدخول») → نسجّل دخول صامتاً بدل إجباره ينقر زر الدخول.
        if (await _tryAutoLogin()) return;
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          clearError: true,
        );
        return;
      }

      // ✅ تفعيل الإشعارات بشكل افتراضي عند التحقق من الجلسة
      await _storage.setFcmEnabled(true);

      // استرجاع سياق الموظف (لو موجود) قبل قرار جلب SAS4 perms.
      final isEmp = await _storage.getIsEmployee();
      var empPerms = isEmp ? await _storage.getEmployeePermissions() : const <String, bool>{};

      // الموظف ما يحتاج SAS4 perms (نظامنا الداخلي)، لكن لازم نتأكد إن
      // توكن الأب SAS4 لسه صالح (الأب ممكن يكون غيّر باسورده). نسوي
      // فحص خفيف عبر _validateAdminToken بـsas4Token المخزَّن.
      // وبنفس الوقت، نطلب صلاحيات الموظف الفريش من backend عشان أي
      // تعديل من الأدمن يطلع فوراً (بدون re-login).
      if (isEmp) {
        final sas4Token = await _storage.getSas4Token();
        if (sas4Token != null && sas4Token.isNotEmpty) {
          await _validateAdminToken(sas4Token);
        }
        empPerms = await _fetchFreshEmployeePerms(empPerms);
      }

      final access = isEmp
          ? _PermissionAccess(
              permissions: const [],
              canAccessManagers: true,
              canAccessPackages: true,
            )
          : await _fetchPermissions(token);
      final user = UserModel(
        id: adminId,
        username: username ?? '',
        role: isEmp ? 'employee' : 'admin',
        token: token,
        expiresAt: expiry ?? '',
        permissions: access.permissions,
        canAccessManagers: access.canAccessManagers,
        canAccessPackages: access.canAccessPackages,
        isEmployee: isEmp,
        employeeId: isEmp ? await _storage.getEmployeeId() : null,
        employeeUsername: isEmp ? await _storage.getEmployeeUsername() : null,
        employeeFullName: isEmp ? await _storage.getEmployeeFullName() : null,
        employeePermissions: empPerms,
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
        _syncNotificationServices(forcePushSync: true);
      });
      _schedulePushResyncRetry();
    } on _TokenInvalidException {
      // handleSessionExpired يحاول التسجيل التلقائي الصامت أولاً (لو «حفظ
      // بيانات الدخول» مفعّل) قبل أي طرد — فالتوكن المرفوض من SAS4 يتجدّد
      // صامتاً بدل ما نطلب من المستخدم ينقر «دخول».
      await handleSessionExpired(
        reason: 'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
      );
    } catch (e) {
      // أي فشل آخر (شبكة/صلاحيات) — نجرّب التسجيل التلقائي قبل شاشة الدخول.
      if (await _tryAutoLogin()) return;
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        clearError: true,
      );
    }
  }

  /// تسجيل دخول تلقائي بالبيانات المحفوظة («حفظ بيانات الدخول») — يُستدعى من
  /// [checkAuth] لمّا تكون الجلسة مفقودة/منتهية. لو نجح، [login] يضبط الـstate
  /// لـauthenticated ويرجّع true؛ غير ذلك نرجّع false ليكمل [checkAuth] إلى
  /// شاشة الدخول. لا نرمي استثناءً — أي فشل (شبكة/باسورد مغيّر) يرجع false.
  Future<bool>? _autoLoginFuture;

  /// تسجيل دخول تلقائي صامت بالبيانات المحفوظة. **صامت تماماً**: لا يغيّر
  /// الـstatus أثناء المحاولة (login يبقي الحالة كما هي حتى ينجح/يفشل)، فلا
  /// يومض نموذج الدخول ولا splash وسط الجلسة — مجرّد تجديد توكن بالخلفية.
  /// يُشارَك نفس الـFuture بين النداءات المتزامنة (عدّة طلبات تطيح 401 بنفس
  /// اللحظة) فما تصير عاصفة logins.
  Future<bool> _tryAutoLogin() {
    return _autoLoginFuture ??=
        _doAutoLogin().whenComplete(() => _autoLoginFuture = null);
  }

  Future<bool> _doAutoLogin() async {
    try {
      if (!await _storage.getRememberMe()) return false;
      final username = await _storage.getSavedUsername();
      final password = await _storage.getSavedPassword();
      if (username == null ||
          username.trim().isEmpty ||
          password == null ||
          password.isEmpty) {
        return false;
      }
      return await login(username.trim(), password);
    } catch (_) {
      return false;
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

    // فحص خفيف للتوكن مقابل SAS4 على كل resume — يمسك حالة "غيّر
    // المدير الباسورد من اللوحة والتطبيق ما يدري". مفصول عن
    // _syncNotificationServices حتى ما يتعطل الإشعارات لو الفحص فشل.
    try {
      final sas4Token = await _storage.getSas4Token() ?? token;
      await _validateAdminToken(sas4Token);
    } on _TokenInvalidException {
      await handleSessionExpired(
        reason: 'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
      );
      return;
    }

    // الموظف: حدّث الصلاحيات الفريش على كل resume — لو الأدمن غيّر
    // صلاحياته أثناء التطبيق بـbackground ينعكس فوراً عند العودة.
    final cur = state.user;
    if (cur != null && cur.isEmployee) {
      final fresh = await _fetchFreshEmployeePerms(cur.employeePermissions);
      if (!_mapEquals(fresh, cur.employeePermissions)) {
        state = state.copyWith(
          user: cur.copyWith(employeePermissions: fresh),
          clearError: true,
        );
      }
    }

    // fire-and-forget — لا نحجب resume بانتظار FCM (نفس السبب في login).
    unawaited(_syncNotificationServices());
  }

  bool _mapEquals(Map<String, bool> a, Map<String, bool> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
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
        // الموظف لا يحتاج SAS4 perms (الـmiddleware بالـbackend يبدّل
        // التوكن لتوكن الأب تلقائياً)؛ إنّما نخزّن صلاحياته الـ40 من الـlogin response.
        final access = user.isEmployee
            ? _PermissionAccess(
                permissions: const [],
                // نمرّر canAccess كـtrue لكي ما تنحجب صفحات لمجرد أنه ما عنده SAS4 prm.
                canAccessManagers: true,
                canAccessPackages: true,
              )
            : await _fetchPermissions(user.token);

        // ✅ تفعيل الإشعارات بشكل افتراضي عند تسجيل الدخول
        await _storage.setFcmEnabled(true);

        // sas4Token يجي مع response الموظف من الـbackend (توكن الأب).
        // الأدمن العادي يستخدم user.token كـsas4 token (هو نفسه SAS4).
        final sas4Token = user.isEmployee
            ? response.data['sas4Token']?.toString()
            : user.token;
        await _storage.saveAll(
          token: user.token,
          expiresAt: user.expiresAt,
          adminId: user.id,
          adminUsername: user.username,
          permissions: access.permissions,
          canAccessManagers: access.canAccessManagers,
          canAccessPackages: access.canAccessPackages,
          isEmployee: user.isEmployee,
          employeeId: user.employeeId,
          employeeUsername: user.employeeUsername,
          employeeFullName: user.employeeFullName,
          employeePermissions: user.employeePermissions,
          sas4Token: sas4Token,
        );

        _resetSessionScopedProviders();
        _socket.disconnect();
        _socket.connect(user.id);

        // لا ننتظر مزامنة الإشعارات قبل تغيير الحالة لـauthenticated —
        // على iOS بدون Push Notifications entitlement، FirebaseMessaging.
        // getToken() يعلّق ينتظر APNs token إلى الأبد، فيظل زرّ الدخول
        // يدور والمستخدم يحسّ التطبيق "جامد" (لو سكّر وفتح التطبيق رجع
        // يلقى نفسه مسجّل — لأن التوكن انحفظ، فقط الـUI ما تحرّك). الآن:
        // الـstate يتحوّل فوراً للـauthenticated، الـrouter يفتح الداش
        // بورد، ومزامنة FCM تنتهي في الخلفية. retry موجود في
        // _schedulePushResyncRetry يضمن إعادة المحاولة.
        unawaited(_syncNotificationServices(forcePushSync: true));

        state = AuthState(
          status: AuthStatus.authenticated,
          user: user.copyWith(
            permissions: access.permissions,
            canAccessManagers: access.canAccessManagers,
            canAccessPackages: access.canAccessPackages,
          ),
          error: null,
        );
        _schedulePushResyncRetry();
        return true;
      }

      final msg = response.data['message']?.toString() ?? 'فشل تسجيل الدخول';
      state = state.copyWith(status: AuthStatus.unauthenticated, error: msg);
      return false;
    } on DioException catch (e) {
      // الـbackend الآن يترجم rsp_* لعربي ويضعه في `message`. كنّا نتجاهله
      // ونعرض "خطأ في المعلومات المدخلة" للجميع — يضيع الفرق بين كلمة
      // مرور خاطئة، شبكة معطّلة، حساب موقوف، الخ.
      final body = e.response?.data;
      final serverMsg = body is Map ? body['message']?.toString() : null;
      final fallback = e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.connectionError
          ? 'تعذّر الاتصال بالخادم. تحقّق من الإنترنت وحاول مجدداً.'
          : 'اسم المستخدم أو كلمة المرور غير صحيحة';
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: serverMsg?.isNotEmpty == true ? serverMsg! : fallback,
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: 'حدث خطأ غير متوقّع. حاول مجدداً.',
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
    // الخروج اليدوي يلغي «حفظ بيانات الدخول» — وإلّا التسجيل التلقائي في
    // checkAuth يعيد إدخاله عند فتح التطبيق ويُبطل قرار الخروج. المستخدم
    // يقدر يفعّل «حفظ بيانات الدخول» من جديد عند تسجيل الدخول التالي.
    await _storage.clearCredentials();
    _resetSessionScopedProviders();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> handleSessionExpired({String? reason}) async {
    if (state.status == AuthStatus.unauthenticated) return;
    // استرجاع صامت: ما دام المستخدم مفعّل «حفظ بيانات الدخول» نعيد تسجيل
    // الدخول بالخفاء (توكن جديد) بدل ما نطرده ونعرض «انتهت الجلسة». ينجح
    // طالما الباسوورد المحفوظ صحيح — فلا ينقطع وسط الاستخدام لمجرّد انتهاء
    // التوكن. يفشل (ويُكمل الطرد تحت) فقط لو الباسوورد تغيّر فعلاً.
    if (await _tryAutoLogin()) return;
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
