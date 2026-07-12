import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

/// طبقة رقيقة فوق `easy_localization` — نُبقيها كنقطة اتفاق واحدة لكل
/// المشروع حتى لا نستدعي `context.setLocale(...)` مبعثراً في كل شاشة،
/// وحتى نُخفي أي تغيير مستقبلي في backing storage.
///
/// - **UI فقط:** التطبيق يترجم labels/buttons/hints فقط. الـdata القادم
///   من backend (أسماء المشتركين، الوصف، الرسائل...) يبقى كما هو.
/// - **الأرقام:** إنجليزية دائماً بغضّ النظر عن اللغة (1234 مو ١٢٣٤).
/// - **الاتجاه:** يُحسب تلقائياً من `MaterialApp.locale`. ما نحتاج
///   نُجبر Directionality في `builder`.
///
/// الـsaveLocale: true على مستوى EasyLocalization يحفظ الاختيار في
/// SharedPreferences ويستعيده عند التشغيل التالي، فما نحتاج persistence
/// يدوي هنا.
class LocaleService {
  LocaleService._();

  static const Locale arabic = Locale('ar');
  static const Locale english = Locale('en');

  static const List<Locale> supported = [arabic, english];

  /// كود اللغة الحالي ('ar' / 'en') — قصير للاستعمال في الشاشات.
  static String codeOf(BuildContext context) => context.locale.languageCode;

  static bool isArabic(BuildContext context) => codeOf(context) == 'ar';
  static bool isEnglish(BuildContext context) => codeOf(context) == 'en';

  /// تبديل مع البدائل: ar ↔ en. يُستدعى من زر التبديل السريع لو أضفناه
  /// لاحقاً في الـAppBar.
  static Future<void> toggle(BuildContext context) async {
    final next = isArabic(context) ? english : arabic;
    await context.setLocale(next);
  }

  /// تبديل مباشر لأي لغة مدعومة. تُستعمل من `RadioListTile` في شاشة
  /// اللغة.
  static Future<void> setLocale(BuildContext context, Locale locale) async {
    if (!supported.any((s) => s.languageCode == locale.languageCode)) {
      return; // guard: لغة غير مدعومة
    }
    await context.setLocale(locale);
  }

  /// اسم مُترجَم للعرض في القوائم/الأزرار — بدون اعتماد على key
  /// خارجي حتى نتفادى circular deps.
  static String labelFor(Locale locale) {
    switch (locale.languageCode) {
      case 'en':
        return 'English';
      case 'ar':
      default:
        return 'العربية';
    }
  }
}
