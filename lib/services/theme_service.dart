import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App-wide theme mode (system / light / dark) with persistence.
///
/// The preference survives logout — it lives in the same OS-encrypted
/// keystore as auth, but `AuthStorage.clear()` only removes its own
/// `auth.*` keys so a logout doesn't reset the user's chosen mode.
///
/// Consumed in `main.dart` via `ValueListenableBuilder` on `notifier`:
/// each change rebuilds `MaterialApp` with the new `themeMode` AND
/// flips `AppColors._isDark` so non-Material widgets that read
/// `AppColors.surface` / `AppColors.textHi` directly still paint
/// against the correct palette.
class ThemeService {
  ThemeService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kThemeMode = 'app.theme_mode';

  /// Default to `system` so the very first launch follows the OS;
  /// a user who chose otherwise will see their preference applied
  /// after `load()` finishes.
  static final ValueNotifier<ThemeMode> notifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> load() async {
    final raw = await _storage.read(key: _kThemeMode);
    notifier.value = _decode(raw);
  }

  static Future<void> setMode(ThemeMode mode) async {
    notifier.value = mode;
    await _storage.write(key: _kThemeMode, value: _encode(mode));
  }

  /// Convenience for use inside `MaterialApp.builder` — resolves
  /// `ThemeMode.system` against the platform brightness so the global
  /// `AppColors._isDark` flag can be flipped on every rebuild before
  /// the widget tree paints.
  static bool resolveIsDark(ThemeMode mode, Brightness platformBrightness) {
    switch (mode) {
      case ThemeMode.light:
        return false;
      case ThemeMode.dark:
        return true;
      case ThemeMode.system:
        return platformBrightness == Brightness.dark;
    }
  }

  static String labelFor(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'فاتح';
      case ThemeMode.dark:
        return 'داكن';
      case ThemeMode.system:
        return 'تلقائي';
    }
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static ThemeMode _decode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
