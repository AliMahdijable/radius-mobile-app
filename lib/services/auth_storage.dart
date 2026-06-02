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

  static Future<void> saveSession({
    required String token,
    required String adminId,
    required String adminUsername,
    required String displayName,
    required bool autoLogin,
  }) async {
    await Future.wait([
      _storage.write(key: _kToken, value: token),
      _storage.write(key: _kAdminId, value: adminId),
      _storage.write(key: _kAdminUsername, value: adminUsername),
      _storage.write(key: _kDisplayName, value: displayName),
      _storage.write(key: _kAutoLogin, value: autoLogin ? '1' : '0'),
    ]);
  }

  static Future<String?> readToken() => _storage.read(key: _kToken);
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

  static Future<void> markPermissionsShown() =>
      _storage.write(key: _kPermsShown, value: '1');

  /// Full logout — wipes everything including the auto-login preference.
  static Future<void> clear() => _storage.deleteAll();
}
