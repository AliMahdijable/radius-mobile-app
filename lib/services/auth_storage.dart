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

  static Future<void> saveSession({
    required String token,
    required String adminId,
    required String adminUsername,
    required String displayName,
    required bool autoLogin,
    String? tokenExpiry,
    bool isSuperAdmin = false,
  }) async {
    await Future.wait([
      _storage.write(key: _kToken, value: token),
      _storage.write(key: _kAdminId, value: adminId),
      _storage.write(key: _kAdminUsername, value: adminUsername),
      _storage.write(key: _kDisplayName, value: displayName),
      _storage.write(key: _kAutoLogin, value: autoLogin ? '1' : '0'),
      _storage.write(key: _kIsSuperAdmin, value: isSuperAdmin ? '1' : '0'),
      if (tokenExpiry != null)
        _storage.write(key: _kTokenExpiry, value: tokenExpiry),
    ]);
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

  static Future<void> markPermissionsShown() =>
      _storage.write(key: _kPermsShown, value: '1');

  /// Full logout — wipes everything including the auto-login preference.
  static Future<void> clear() => _storage.deleteAll();
}
