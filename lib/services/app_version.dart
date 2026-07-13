import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// نسخة التطبيق — تُحمَّل مرّة واحدة عند بدء التشغيل من AndroidManifest/
/// Info.plist (والذي بدوره يستمدّ من pubspec.yaml.version)، ثم تُقرأ
/// synchronously في أي مكان بالتطبيق.
///
/// كل مرّة نرفع تحديث → pubspec.yaml `version:` يتغيّر → التطبيق يعرض
/// النسخة الجديدة تلقائياً بلا تعديل يدوي.
class AppVersion {
  AppVersion._();

  static String _version = '';
  static String _buildNumber = '';
  static String _appName = '';

  /// يُستدعى من main.dart قبل runApp() لضمان توفّر النسخة synchronously.
  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      _buildNumber = info.buildNumber;
      _appName = info.appName;
    } catch (e) {
      if (kDebugMode) debugPrint('[AppVersion] load failed: $e');
    }
  }

  /// "2.0.1" — من pubspec.yaml `version: 2.0.1+88`
  static String get version => _version;

  /// "88" — من pubspec.yaml (الرقم بعد +)
  static String get buildNumber => _buildNumber;

  /// اسم التطبيق كما هو في manifest
  static String get appName => _appName;

  /// "v2.0.1 (88)" — تنسيق موحّد للعرض في UI
  static String get displayVersion {
    if (_version.isEmpty) return '…';
    return 'v$_version (${_buildNumber.isEmpty ? '?' : _buildNumber})';
  }

  /// "v2.0.1" — بدون build number (للـfooter المضغوط)
  static String get shortVersion {
    if (_version.isEmpty) return '…';
    return 'v$_version';
  }
}
