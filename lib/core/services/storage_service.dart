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

  Future<void> savePermissions(List<String> permissions) async =>
      (await _sp).setStringList(AppConstants.storagePermissions, permissions);

  Future<List<String>> getPermissions() async =>
      (await _sp).getStringList(AppConstants.storagePermissions) ?? const [];

  Future<void> saveCanAccessManagers(bool value) async =>
      (await _sp).setBool(AppConstants.storageCanAccessManagers, value);

  Future<bool> getCanAccessManagers() async =>
      (await _sp).getBool(AppConstants.storageCanAccessManagers) ?? false;

  Future<void> saveCanAccessPackages(bool value) async =>
      (await _sp).setBool(AppConstants.storageCanAccessPackages, value);

  Future<bool> getCanAccessPackages() async =>
      (await _sp).getBool(AppConstants.storageCanAccessPackages) ?? false;

  Future<void> saveThemeMode(String mode) async =>
      (await _sp).setString(AppConstants.storageThemeMode, mode);

  Future<String?> getThemeMode() async =>
      (await _sp).getString(AppConstants.storageThemeMode);

  Future<void> saveAll({
    required String token,
    required String expiresAt,
    required String adminId,
    required String adminUsername,
    List<String> permissions = const [],
    bool canAccessManagers = false,
    bool canAccessPackages = false,
  }) async {
    final sp = await _sp;
    await Future.wait([
      sp.setString(AppConstants.storageToken, token),
      sp.setString(AppConstants.storageTokenExpiry, expiresAt),
      sp.setString(AppConstants.storageAdminId, adminId),
      sp.setString(AppConstants.storageAdminUsername, adminUsername),
      sp.setStringList(AppConstants.storagePermissions, permissions),
      sp.setBool(AppConstants.storageCanAccessManagers, canAccessManagers),
      sp.setBool(AppConstants.storageCanAccessPackages, canAccessPackages),
    ]);
  }

  Future<void> clearAll() async {
    final sp = await _sp;
    await sp.remove(AppConstants.storageToken);
    await sp.remove(AppConstants.storageTokenExpiry);
    await sp.remove(AppConstants.storageAdminId);
    await sp.remove(AppConstants.storageAdminUsername);
    await sp.remove(AppConstants.storagePermissions);
    await sp.remove(AppConstants.storageCanAccessManagers);
    await sp.remove(AppConstants.storageCanAccessPackages);
    final appNotificationKeys = sp
        .getKeys()
        .where(
          (key) =>
              key.startsWith(AppConstants.storageAppNotificationLastSeenPrefix),
        )
        .toList();
    for (final key in appNotificationKeys) {
      await sp.remove(key);
    }
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

  Future<void> setPushExpiryOutsideEnabled(bool enabled) async =>
      (await _sp).setBool(AppConstants.storagePushExpiryOutsideEnabled, enabled);

  Future<bool> getPushExpiryOutsideEnabled() async =>
      (await _sp).getBool(AppConstants.storagePushExpiryOutsideEnabled) ?? false;

  Future<void> setFcmEnabled(bool enabled) async =>
      (await _sp).setBool(AppConstants.storageFcmEnabled, enabled);

  Future<bool> getFcmEnabled() async =>
      (await _sp).getBool(AppConstants.storageFcmEnabled) ?? false;

  Future<void> saveLastSeenAppNotificationId(String adminId, int id) async =>
      (await _sp).setInt(
        '${AppConstants.storageAppNotificationLastSeenPrefix}$adminId',
        id,
      );

  Future<int> getLastSeenAppNotificationId(String adminId) async =>
      (await _sp).getInt(
        '${AppConstants.storageAppNotificationLastSeenPrefix}$adminId',
      ) ??
      0;

  // Dismissed notification ids — stored as a comma-separated string per
  // admin in SharedPreferences. Keeping it local (not on the server) is
  // deliberate: the activity_logs rows are an audit trail we don't want
  // to mutate, and the dismissed state is purely a view preference.
  Future<Set<int>> getDismissedAppNotificationIds(String adminId) async {
    final raw = (await _sp)
            .getString('${AppConstants.storageAppNotificationDismissedPrefix}$adminId') ??
        '';
    if (raw.isEmpty) return <int>{};
    return raw
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
  }

  Future<void> saveDismissedAppNotificationIds(
    String adminId,
    Set<int> ids,
  ) async {
    // Cap at 500 ids to keep the key size reasonable. Oldest-first is
    // safe because ids from activity_logs are monotonically increasing,
    // so we drop the smallest (oldest) first.
    final sorted = ids.toList()..sort((a, b) => b.compareTo(a));
    final capped = sorted.take(500);
    await (await _sp).setString(
      '${AppConstants.storageAppNotificationDismissedPrefix}$adminId',
      capped.join(','),
    );
  }
}
