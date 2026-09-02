import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/util/dev_log.dart';

/// ذاكرة طريق جدول التسجيل + خنق السجلّ.
///
/// 🐛 سجلّ المستخدم ٢٠٢٦-٠٩-٠٢: كلّ نقطة وصول ميكروتك تدفع الثمن
/// كاملاً في **كلّ** نبضة — جدول عبر الـAPI (٠ صفوف)، ثمّ صيغة
/// متعدّدة الكلمات (`!trap`)، ثمّ SSH. والمحاولتان الأوليان لم تنجحا
/// مرّةً واحدة في سجلٍّ كامل.
void main() {
  late String api;
  late String binary;

  setUpAll(() {
    api = File('lib/api/mikrotik_api.dart').readAsStringSync();
    binary = File('lib/api/mikrotik_binary_api.dart').readAsStringSync();
  });

  group('مساران لا ثلاثة', () {
    test('🚨 الصيغة متعدّدة الكلمات حُذفت', () {
      // قاعدة المستخدم ٢٠٢٦-٠٩-٠٢: «خلّ ميكروتك ثابت API، والأولويّة
      // له، وUBNT SSH». والمحاولة الثالثة لم تنجح مرّةً واحدة في سجلٍّ
      // كامل — ترد !trap دائماً، فهي جولة شبكةٍ مهدورة قبل كلّ سقوط.
      expect(api.contains("'/interface', 'wireless', 'registration-table'"),
          isFalse, reason: 'عادت الصيغة الفاشلة');
      expect(api.contains('multi-word format'), isFalse);
    });

    test('والذاكرة التي كانت تخدمها حُذفت معها', () {
      // كانت تتخطّى المحاولة الثالثة وحدها؛ بلا تلك المحاولة لا وظيفة
      // لها — وحقلٌ يُكتب ولا يُقرأ دَيْنٌ لا أصل.
      expect(api.contains('_regTableNeedsSsh'), isFalse);
    });

    test('🚨 SSH في المسار المفصَّل وحده', () {
      // الجدار والخلفيّة يقفان عند vitalsOnly قبل قسم اللاسلكيّ.
      final iVitals = api.indexOf('if (vitalsOnly) return tier1;');
      final iSsh = api.indexOf('_fetchClientsViaSsh(ip, user, pass)');
      expect(iVitals, greaterThan(0));
      expect(iSsh, greaterThan(iVitals),
          reason: 'SSH قبل مخرج الوضع الخفيف — الجدار سيدفع ثمنه');
    });
  });

  group('خنق السجلّ', () {
    test('الافتراضيّ هادئ', () {
      // آلافُ الأسطر تُخفي العطل الذي نبحث عنه. السجلّ الذي لا يُقرأ
      // ليس سجلّاً.
      expect(DevLog.level, LogLevel.quiet);
    });

    test('🚨 تفاصيل البروتوكول لا تظهر إلّا في verbose', () {
      for (final e in {'binary': binary, 'api': api}.entries) {
        expect(e.value.contains('DevLog.trace('), isTrue, reason: e.key);
      }
      // أضجّ ثلاثة أسطر في السجلّ: كلّ أمرٍ، كلّ جملة، كلّ حمولة خام.
      expect(binary.contains("DevLog.trace(() => '▶️ [mtk-api] send:"), isTrue);
      expect(binary.contains('DevLog.trace(() =>\n            \'◀️ [mtk-api] sentence'),
          isTrue);
      expect(api.contains("DevLog.trace(() => '📥 [mikrotik SSH] raw:"), isTrue);
    });

    test('🚨 UBNT أيضاً — آخر مصدر ضجيج', () {
      // خمسون سطراً لكلّ جهاز UBNT في كلّ نبضة، بقيت بعد إسكات ميكروتك.
      final ubnt = File('lib/api/ubnt_api.dart').readAsStringSync();
      expect(ubnt.contains("DevLog.trace(() =>\n          '══════ UBNT output"),
          isTrue, reason: 'الحمولة الخام ما زالت تُطبع دائماً');
      expect(ubnt.contains("debugPrint(\n            '══════ UBNT output"),
          isFalse);
      expect(ubnt.contains("DevLog.trace(() => '🔑 UBNT SSH try"), isTrue);
    });

    test('🚨 الوسيط دالّة لا نصّ', () {
      // بناء السلسلة نفسه يكلّف، وفي `quiet` لا ندفع ثمن نصٍّ لن يُطبع.
      final src = File('lib/core/util/dev_log.dart').readAsStringSync();
      for (final m in ['warn', 'info', 'trace']) {
        expect(src.contains('void $m(String Function() msg)'), isTrue,
            reason: '$m تأخذ نصّاً جاهزاً — يُبنى ولو لم يُطبع');
      }
    });
  });
}
