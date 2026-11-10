import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/app_platform.dart';
import '../ai_assistant_state.dart';

/// لغة الكلام في «أمر صوتي» (١٠ نوفمبر — المالك: «نخلي يتعرف على اللغة انكليزي عربي من النطق»).
///
/// • **auto** «تلقائي»: التسجيل لخادمنا، وهو يتعرّف العربيّة والإنكليزيّة من النطق نفسه. ويندوز عليه دائماً (لا محرّك عربيّ به)؛
///   والهاتف حين يفتحه الخادم لمنصّته ([AiAssistantState.voiceAuto]).
/// • **ar** / **en**: على الهاتف محرّك الجهاز بتلك اللغة (يكتب وأنت تحچي، ويسمع لغةً واحدة في الجلسة)؛ وعلى ويندوز إلزام خادمنا
///   بها (أدقّ وأسرع حين تُعرف).
///
/// الاختيار يُحفظ على الجهاز. الافتراضيّ ما كان قبلها: الهاتف عربيّ، ويندوز تلقائيّ.
class VoiceLangPref {
  VoiceLangPref._();

  static const _key = 'voice.lang.v1';
  static const auto = 'auto';
  static const ar = 'ar';
  static const en = 'en';

  static String? _saved;
  static bool _loaded = false;

  /// المنصّة التي لا محرّك إملاءٍ عربيّ بها — التحويل على خادمنا بكلّ الأوضاع.
  static bool get serverOnly => AppPlatform.isWindows;

  static bool get autoAllowed => serverOnly || AiAssistantState.voiceAuto;

  /// الأوضاع المعروضة لهذا الجهاز الآن.
  static List<String> get options => [if (autoAllowed) auto, ar, en];

  static String get current {
    final v = _saved;
    if (v == ar || v == en) return v!;
    if (v == auto && autoAllowed) return auto;
    return serverOnly ? auto : ar;
  }

  /// تُقرأ مرّةً قبل فتح الورقة (المايك يبدأ بنفسه — يجب أن يعرف لغته).
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      _saved = p.getString(_key);
    } catch (_) {/* بلا تخزين ⇒ الافتراضيّ */}
  }

  static Future<void> set(String value) async {
    if (value != auto && value != ar && value != en) return;
    _saved = value;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, value);
    } catch (_) {/* الاختيار باقٍ لهذه الجلسة */}
  }

  static String label(String value) => switch (value) {
        auto => 'تلقائي',
        en => 'English',
        _ => 'عربي',
      };

  /// للاختبار.
  static void debugReset([String? value]) {
    _saved = value;
    _loaded = value != null;
  }
}
