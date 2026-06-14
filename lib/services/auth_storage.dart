import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists auth token + admin id + auto-login preference in OS-encrypted
/// storage (Keychain on iOS, EncryptedSharedPrefs on Android). Survives
/// app restarts and isn't accessible to other apps.
class AuthStorage {
  AuthStorage._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kToken = 'auth.token';
  static const _kTokenExpiry = 'auth.token_expiry';
  static const _kAdminId = 'auth.admin_id';
  static const _kAdminUsername = 'auth.admin_username';
  static const _kDisplayName = 'auth.display_name';
  // When true, the splash screen skips login and goes straight to home
  // if a token is present. Persisted alongside credentials so toggling
  // "تذكرني" off makes the very next app launch ask for password again.
  static const _kAutoLogin = 'auth.auto_login';
  // The first successful login also marks that permissions screen has
  // been shown once; on later auto-logins we don't re-ask.
  static const _kPermsShown = 'auth.perms_shown';
  // True when the logged-in admin's SAS4 permissions resolve to
  // super_admin. Edit/add subscriber sheets gate the expiration +
  // parent fields on this flag (مطلب 2026-06-10).
  static const _kIsSuperAdmin = 'auth.is_super_admin';
  // Granular permission flags derived from the SAS4 prm_* list at
  // login time (مطابق v1: canAccessManagers = prm_managers_create,
  // canAccessPackages = prm_profiles_create). The edit/add subscriber
  // sheets gate on these instead of isSuperAdmin alone — non-super
  // admins who hold prm_managers_create still see the parent picker.
  static const _kCanAccessManagers = 'auth.can_access_managers';
  static const _kCanAccessPackages = 'auth.can_access_packages';
  // 2026-06-14 incident: حين يدخل موظف، الـserver يصدر empToken خاص.
  // عند 401 على أي endpoint، الـinterceptor كان ينادي
  // /api/auth/refresh-token الذي يجدد توكن SAS4 للأب (admin@popq) ثم
  // يكتبه فوق empToken. النتيجة: الموظف يصير admin بعد أول refresh،
  // me() يرجع is_employee:false، الـcache يصير empty، Perms.has()=true
  // لكل شي. الفلتر هذا flag يخلي refreshToken() ترفض التجديد للموظف
  // (يستعمل empToken طول مدته 24h، ثم relogin).
  static const _kIsEmployee = 'auth.is_employee';

  static Future<void> saveSession({
    required String token,
    required String adminId,
    required String adminUsername,
    required String displayName,
    required bool autoLogin,
    String? tokenExpiry,
    bool isSuperAdmin = false,
    bool canAccessManagers = false,
    bool canAccessPackages = false,
    bool isEmployee = false,
  }) async {
    await Future.wait([
      _storage.write(key: _kToken, value: token),
      _storage.write(key: _kAdminId, value: adminId),
      _storage.write(key: _kAdminUsername, value: adminUsername),
      _storage.write(key: _kDisplayName, value: displayName),
      _storage.write(key: _kAutoLogin, value: autoLogin ? '1' : '0'),
      _storage.write(key: _kIsSuperAdmin, value: isSuperAdmin ? '1' : '0'),
      _storage.write(
          key: _kCanAccessManagers, value: canAccessManagers ? '1' : '0'),
      _storage.write(
          key: _kCanAccessPackages, value: canAccessPackages ? '1' : '0'),
      _storage.write(key: _kIsEmployee, value: isEmployee ? '1' : '0'),
      if (tokenExpiry != null)
        _storage.write(key: _kTokenExpiry, value: tokenExpiry),
    ]);
  }

  /// True إذا الـuser سجل دخول كموظف (empToken). يقرأها
  /// AuthApi.refreshToken() لترفض refresh والـinterceptor لـ
  /// kick-to-login عند 401.
  static Future<bool> isEmployee() async {
    final v = await _storage.read(key: _kIsEmployee);
    return v == '1';
  }

  /// Replace just the token after a refresh. Keeps adminId / username /
  /// display name intact so the user stays logged in across refreshes.
  static Future<void> saveRefreshedToken({
    required String token,
    String? tokenExpiry,
  }) async {
    await Future.wait([
      _storage.write(key: _kToken, value: token),
      if (tokenExpiry != null)
        _storage.write(key: _kTokenExpiry, value: tokenExpiry),
    ]);
  }

  static Future<String?> readToken() => _storage.read(key: _kToken);
  static Future<String?> readTokenExpiry() =>
      _storage.read(key: _kTokenExpiry);
  static Future<String?> readAdminId() => _storage.read(key: _kAdminId);
  static Future<String?> readAdminUsername() =>
      _storage.read(key: _kAdminUsername);
  static Future<String?> readDisplayName() => _storage.read(key: _kDisplayName);

  /// Whether the splash should auto-route to home. Default `false` — if
  /// the user hasn't logged in yet, there's no preference and we must
  /// show login.
  static Future<bool> isAutoLoginEnabled() async {
    final v = await _storage.read(key: _kAutoLogin);
    return v == '1';
  }

  /// Has the one-time permissions screen been shown? Set true after the
  /// user taps "متابعة" or "تخطّى" once. After that, auto-login goes
  /// directly to home without re-asking.
  static Future<bool> hasShownPermissions() async {
    final v = await _storage.read(key: _kPermsShown);
    return v == '1';
  }

  /// Whether the logged-in admin is a SAS4 super-admin. Drives
  /// permission-gated UI (e.g. expiration date + parent picker on
  /// the add / edit subscriber sheets).
  static Future<bool> readIsSuperAdmin() async {
    final v = await _storage.read(key: _kIsSuperAdmin);
    return v == '1';
  }

  /// True when the admin can create sub-managers ('prm_managers_create'
  /// or super). Gates the parent picker on add/edit subscriber sheets.
  static Future<bool> readCanAccessManagers() async {
    final v = await _storage.read(key: _kCanAccessManagers);
    return v == '1';
  }

  /// True when the admin can create packages ('prm_profiles_create'
  /// or super). Combined with canAccessManagers to derive
  /// canEditExpiration — the expiration date picker shows for either.
  static Future<bool> readCanAccessPackages() async {
    final v = await _storage.read(key: _kCanAccessPackages);
    return v == '1';
  }

  static Future<void> markPermissionsShown() =>
      _storage.write(key: _kPermsShown, value: '1');

  /// Full logout — wipes only the `auth.*` namespace. Preferences that
  /// belong to other modules (theme mode, FCM toggles, etc.) live under
  /// their own keys and must survive logout/login cycles. Using
  /// `deleteAll()` here would reset the user's dark-mode choice every
  /// time they signed out.
  static Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _kToken),
      _storage.delete(key: _kTokenExpiry),
      _storage.delete(key: _kAdminId),
      _storage.delete(key: _kAdminUsername),
      _storage.delete(key: _kDisplayName),
      _storage.delete(key: _kAutoLogin),
      _storage.delete(key: _kPermsShown),
      _storage.delete(key: _kIsSuperAdmin),
      _storage.delete(key: _kCanAccessManagers),
      _storage.delete(key: _kCanAccessPackages),
      _storage.delete(key: _kIsEmployee),
    ]);
  }
}
