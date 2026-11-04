import 'dart:io';

/// مصدر خادم Pro للاختبارات التي تطابق التطبيق بالخادم (عقد): PRO_SERVER_ROOT، أو مستودع Pro على الخادم نفسه.
/// (كانت تقرأ مسار الكلاسيك «/home/ali/MyServices Raduis» — حُذف بالنقل للبرو ١٨ أكتوبر فصارت تفشل في كلّ مكان.)
/// null ⇒ غير متاحٍ هنا (الماك) — يُتخطّى الاختبار بسببٍ مكتوب، لا يفشل كذباً.
String? proServerRoot() {
  final env = Platform.environment['PRO_SERVER_ROOT'];
  final home = Platform.environment['HOME'] ?? '';
  for (final c in [
    if (env != null && env.isNotEmpty) env,
    '$home/MyServices-Pro',
    '/home/ali/MyServices-Pro',
  ]) {
    if (File('$c/server.js').existsSync() && File('$c/database/db.js').existsSync()) return c;
  }
  return null;
}

const serverSourceSkip = 'مصدر خادم Pro غير متاحٍ هنا — شغّله على الخادم أو اضبط PRO_SERVER_ROOT على نسخةٍ منه';
