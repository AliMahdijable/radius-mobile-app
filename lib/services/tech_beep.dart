import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// صفّارة «وضع الفنّي» (شبكة الألياف) — نغمةٌ حقيقيّة بصوت الوسائط.
///
/// كانت `SystemSound.play(SystemSoundType.click)`: «صوت اللمس» للنظام — مطفأٌ بأغلب الهواتف (ولا يُسمع بآيفون إلّا مع نقرات
/// لوحة المفاتيح)، فالصفّارة بلا صوت (بلاغ المالك ١٠ نوفمبر: «الصفاره الي موجوده بوضع الكيبل الضوئي… مابيها صوت»).
/// الآن عبر قناة التطبيق: أندرويد `ToneGenerator` وآيفون `AVAudioPlayer` — بصوت الوسائط، فتُسمع والهاتف على «صامت»؛ والحاسبة
/// صوت تنبيه النظام. والشاشة تبقى مضاءةً ما دامت الصفّارة شغّالة ([keepAwake]).
class TechBeep {
  TechBeep._();

  static const channel = MethodChannel('com.mysvcs.rad_mysvcs/beep');

  /// نغمةٌ قصيرة. ⇒ false حين صوت الوسائط على الصفر (تشتغل ولا تُسمع — يُقال للفنّي)، true مسموعة، null لا يُعرف.
  static Future<bool?> play({int ms = 90}) async {
    if (kIsWeb) return null;
    if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final r = await channel.invokeMethod<Object?>('beep', {'ms': ms});
        return r is bool ? r : null;
      } catch (_) {
        // بلا القناة (نسخةٌ لم تُبنَ معها) ⇒ صوت اللمس كما كان
        unawaited(SystemSound.play(SystemSoundType.click).catchError((Object _) {}));
        return null;
      }
    }
    // ويندوز/ماك: صوت تنبيه النظام (الوحيد الذي تدعمه الحاسبة)
    unawaited(SystemSound.play(SystemSoundType.alert).catchError((Object _) {}));
    return null;
  }

  /// الشاشة لا تنطفئ ما دامت الصفّارة شغّالة: الفنّي عينه على الوصلة ولا يلمس الهاتف، وانطفاء الشاشة يقفل الهاتف فتقف
  /// القراءة والصفّارة معاً (آيفون يعلّق التطبيق بعد القفل بثوانٍ). تُرفع بإطفاء الصفّارة أو الخروج من الشاشة.
  static Future<void> keepAwake(bool on) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await channel.invokeMethod<Object?>('keepAwake', {'on': on});
    } catch (_) {
      // بلا القناة ⇒ الشاشة بإعداد الهاتف كما كانت
    }
  }
}
