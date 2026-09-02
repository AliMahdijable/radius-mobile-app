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

  group('ذاكرة الطريق', () {
    test('🚨 تُتخطّى المحاولة الفاشلة بعد تعلّم SSH', () {
      expect(api.contains('_regTableNeedsSsh[ip] != true'), isTrue,
          reason: 'الصيغة متعدّدة الكلمات تُجرَّب رغم أنّنا نعرف أنّها تفشل');
      expect(api.contains('_regTableNeedsSsh[ip] = true;'), isTrue,
          reason: 'لا نتعلّم شيئاً من نجاح SSH');
    });

    test('🚨 نتعلّم من النجاح لا من الفشل', () {
      // جهازٌ بلا عملاء اليوم يعطي صفراً من الطريقين، وتذكُّرُ ذلك
      // يمنعنا من قراءة عملائه غداً.
      final i = api.indexOf('_regTableNeedsSsh[ip] = true;');
      expect(i, greaterThan(0));
      final before = api.substring(i - 300, i);
      expect(before.contains('sshClients.isNotEmpty'), isTrue,
          reason: 'التعلّم يجب أن يكون داخل فرع النجاح');
    });

    test('ننسى إن نجح الـAPI — ترقية firmware', () {
      expect(api.contains('_regTableNeedsSsh.remove(ip);'), isTrue,
          reason: 'الذاكرة يجب أن تتبع الواقع لا أن تُجمّده');
    });

    test('عمرُها عمرُ التشغيل لا القرص', () {
      // حفظُها بين تشغيلين يُجمّد حكماً على جهازٍ قد يُرقّى.
      expect(api.contains('SharedPreferences'), isFalse);
      expect(api.contains('static final Map<String, bool> _regTableNeedsSsh'),
          isTrue);
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
