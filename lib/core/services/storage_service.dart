import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

class StorageService {
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _sp async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> saveToken(String token) async =>
      (await _sp).setString(AppConstants.storageToken, token);

  Future<String?> getToken() async =>
      (await _sp).getString(AppConstants.storageToken);

  Future<void> saveTokenExpiry(String expiry) async =>
      (await _sp).setString(AppConstants.storageTokenExpiry, expiry);

  Future<String?> getTokenExpiry() async =>
      (await _sp).getString(AppConstants.storageTokenExpiry);

  Future<void> saveAdminId(String id) async =>
      (await _sp).setString(AppConstants.storageAdminId, id);

  Future<String?> getAdminId() async =>
      (await _sp).getString(AppConstants.storageAdminId);

  Future<void> saveAdminUsername(String username) async =>
      (await _sp).setString(AppConstants.storageAdminUsername, username);

  Future<String?> getAdminUsername() async =>
      (await _sp).getString(AppConstants.storageAdminUsername);

  Future<void> saveThemeMode(String mode) async =>
      (await _sp).setString(AppConstants.storageThemeMode, mode);

  Future<String?> getThemeMode() async =>
      (await _sp).getString(AppConstants.storageThemeMode);

  Future<void> saveAll({
    required String token,
    required String expiresAt,
    required String adminId,
    required String adminUsername,
  }) async {
    final sp = await _sp;
    await Future.wait([
      sp.setString(AppConstants.storageToken, token),
      sp.setString(AppConstants.storageTokenExpiry, expiresAt),
      sp.setString(AppConstants.storageAdminId, adminId),
      sp.setString(AppConstants.storageAdminUsername, adminUsername),
    ]);
  }

  Future<void> clearAll() async {
    final sp = await _sp;
    await sp.remove(AppConstants.storageToken);
    await sp.remove(AppConstants.storageTokenExpiry);
    await sp.remove(AppConstants.storageAdminId);
    await sp.remove(AppConstants.storageAdminUsername);
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    if (token == null) return false;
    final expiry = await getTokenExpiry();
    if (expiry == null) return false;
    final expiryDate = DateTime.tryParse(expiry);
    if (expiryDate == null) return false;
    return expiryDate.isAfter(DateTime.now().toUtc());
  }

  Future<void> saveCredentials(String username, String password) async {
    final sp = await _sp;
    await sp.setBool(AppConstants.storageRememberMe, true);
    await sp.setString(AppConstants.storageSavedUsername, username);
    await sp.setString(AppConstants.storageSavedPassword, password);
  }

  Future<void> clearCredentials() async {
    final sp = await _sp;
    await sp.remove(AppConstants.storageRememberMe);
    await sp.remove(AppConstants.storageSavedUsername);
    await sp.remove(AppConstants.storageSavedPassword);
  }

  Future<bool> getRememberMe() async =>
      (await _sp).getBool(AppConstants.storageRememberMe) ?? false;

  Future<String?> getSavedUsername() async =>
      (await _sp).getString(AppConstants.storageSavedUsername);

  Future<String?> getSavedPassword() async =>
      (await _sp).getString(AppConstants.storageSavedPassword);

  Future<void> setAlertsEnabled(bool enabled) async =>
      (await _sp).setBool(AppConstants.storageAlertsEnabled, enabled);

  Future<bool> getAlertsEnabled() async =>
      (await _sp).getBool(AppConstants.storageAlertsEnabled) ?? true;
}
