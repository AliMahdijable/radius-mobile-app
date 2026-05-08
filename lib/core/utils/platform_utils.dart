// Platform feature detection — مكان واحد لمعرفة المتاح بكل platform.
// يبسّط الـguards عبر التطبيق بدل ما تكتب
//   `if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))` بكل مكان.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

class PlatformUtils {
  PlatformUtils._();

  /// تطبيقات الموبايل (Android/iOS) — تدعم push، contacts، badges.
  static bool get isMobile {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// سطح المكتب (Windows/macOS/Linux) — شاشة كبيرة، نوافذ، طابعات.
  static bool get isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// Windows تحديداً — لإستعمال DPAPI أو SNMP الـnative.
  static bool get isWindows {
    if (kIsWeb) return false;
    return Platform.isWindows;
  }

  /// FCM/WorkManager متاح فقط على Android/iOS. سطح المكتب يحتاج آلية
  /// بديلة (polling أو socket.io محلي مفتوح طول التشغيل).
  static bool get supportsPushNotifications => isMobile;

  /// Contact picker (flutter_native_contact_picker) — Android/iOS فقط.
  static bool get supportsContactPicker => isMobile;

  /// App badge (لون الـicon بالـlauncher) — Android/iOS فقط.
  static bool get supportsAppBadge => isMobile;

  /// SNMP الأصلي (من اللاب مباشرة لجهاز LAN) — desktop فقط لأن:
  ///   - الموبايل بشبكات mobile تبقى خلف NAT/firewall
  ///   - الموبايل عنده حدود concurrent UDP sockets
  ///   - desktop عنده Node FFI / Dart pure SNMP يشتغل بصلاحيات كاملة
  static bool get supportsLocalSnmp => isDesktop;

  /// عرض الشاشة المتوقّع — تستفيد منه الـlayouts للتبديل بين mobile/desktop.
  static bool isWideScreen(double width) => width >= 800;
}
