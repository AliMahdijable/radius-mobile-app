import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// يُحمّل خطّ التطبيق الحقيقيّ داخل الاختبار.
///
/// ── لماذا هذا ضروريّ ──────────────────────────────────────────────
/// `flutter test` يستبدل افتراضيّاً خطّاً احتياطيّاً كلّ محرفٍ فيه بعرض
/// حجم الخطّ تماماً. قِيس: «تسديد دين قبل 22 س» ١٨ محرفاً × ١٢٫٥ =
/// ٢٢٥٫٥ نقطة بالضبط — رقمٌ لا علاقة له بالواقع.
///
/// فأيّ اختبارٍ يسأل «هل يتّسع النصّ؟» بلا الخطّ الحقيقيّ يقيس الخطّ
/// الاحتياطيّ: يُنذر كذباً على تصميمٍ سليم، ويصمت عن ضيقٍ حقيقيّ.
///
/// ⚠️ وIBM Plex Sans Arabic **مرفقٌ في المستودع** لا يُجلب من الشبكة
/// (`assets/fonts/`) — فتحميلُه في الاختبار ممكنٌ وحتميّ النتيجة.
Future<void> loadAppFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loader = FontLoader('IBMPlexSansArabic');
  for (final w in const ['400', '500', '600', '700']) {
    loader.addFont(
      rootBundle.load('assets/fonts/IBMPlexSansArabic-$w.ttf'),
    );
  }
  await loader.load();
}
