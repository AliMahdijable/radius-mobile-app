import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the auth token + admin id in OS-encrypted storage. Survives
/// app restarts and is shielded from filesystem access.
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

  static Future<void> saveSession({
    required String token,
    required String adminId,
    required String adminUsername,
    required String displayName,
  }) async {
    await Future.wait([
      _storage.write(key: _kToken, value: token),
      _storage.write(key: _kAdminId, value: adminId),
      _storage.write(key: _kAdminUsername, value: adminUsername),
      _storage.write(key: _kDisplayName, value: displayName),
    ]);
  }

  static Future<String?> readToken() => _storage.read(key: _kToken);
  static Future<String?> readAdminId() => _storage.read(key: _kAdminId);
  static Future<String?> readDisplayName() => _storage.read(key: _kDisplayName);

  static Future<void> clear() => _storage.deleteAll();
}
