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
  static String? _installer;

  /// يُستدعى من main.dart قبل runApp() لضمان توفّر النسخة synchronously.
  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      _buildNumber = info.buildNumber;
      _appName = info.appName;
      _installer = info.installerStore;
    } catch (e) {
      if (kDebugMode) debugPrint('[AppVersion] load failed: $e');
    }
  }

  @visibleForTesting
  static void debugSet({String version = '', String build = '', String? installer}) {
    _version = version;
    _buildNumber = build;
    _installer = installer;
  }

  /// من نصّب التطبيق (٢٦ نوفمبر — رابط «حدّث» بمصدر التنصيب، [UpdateGate.storeUrlFor]): اسم حزمة المثبِّت —
  /// `com.android.vending` = Google Play؛ غيره = مثبّت الحزم لملفّ APK أو متجرٌ آخر؛ null = adb أو لا يُعرف (ونظامٌ غير أندرويد).
  /// أندرويد 11+ يقرأ initiatingPackageName (لا يتغيّر بعد التنصيب)، وما قبله getInstallerPackageName.
  static String? get installerStore => _installer;

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
