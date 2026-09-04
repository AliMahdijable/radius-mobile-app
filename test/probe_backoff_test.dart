import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/network_devices/probe_backoff.dart';

/// حارس بلاغ ٢٠٢٦-٠٩-٠٤: «الدخول ع الأجهزة يجلب ٣ ويوقف، أخرج وأرجع
/// للقسم ٣ مرّات حتّى يظهرهم كلّهم».
///
/// المحاكاة أدناه تُعيد إنتاج الشكوى بالأرقام، ثمّ تُثبت أنّ `force`
/// يُلغيها. وقيمة ذلك أنّ العطل لم يكن في التباطؤ نفسه — التباطؤ سليمٌ
/// ومقصود — بل في تطبيقه على أفعالٍ يطلبها المستخدم وينتظر جوابها.
void main() {
  group('التباطؤ نفسه', () {
    test('جهازٌ سليم يُفحص كلّ جولة', () {
      for (var round = 1; round <= 12; round++) {
        expect(
          deviceProbeDue(force: false, consecutiveFailures: 0, round: round),
          isTrue,
          reason: 'الجولة $round',
        );
      }
    });

    test('إخفاقٌ واحد لا يُبطئ شيئاً', () {
      for (var round = 1; round <= 12; round++) {
        expect(
          deviceProbeDue(force: false, consecutiveFailures: 1, round: round),
          isTrue,
        );
      }
    });

    test('ستّة إخفاقاتٍ = مرّة كلّ ستّ جولات', () {
      final due = <int>[
        for (var r = 1; r <= 18; r++)
          if (deviceProbeDue(force: false, consecutiveFailures: 6, round: r)) r,
      ];
      expect(due, [6, 12, 18]);
    });

    test('🚨 السقف لا يُتجاوز مهما تراكم الإخفاق', () {
      // بلا `clamp` يصير جهازٌ أخفق ٥٠ مرّة يُفحص كلّ ٥٠ جولة = ١٧ دقيقة،
      // فيبدو ميّتاً بعد عودته بوقتٍ طويل.
      final due = <int>[
        for (var r = 1; r <= 18; r++)
          if (deviceProbeDue(force: false, consecutiveFailures: 50, round: r))
            r,
      ];
      expect(due, [6, 12, 18], reason: 'يجب أن يتصرّف كالسقف ٦ تماماً');
    });
  });

  group('🐛 إعادة إنتاج الشكوى', () {
    // حالةٌ واقعيّة: هاتف المدير على بيانات الجوّال، فأكثر الأجهزة
    // أخفقت مراراً. والشاشة داخل `IndexedStack` فلا تُهدَم — يبقى عدّاد
    // الجولات وخريطة الإخفاقات حيّين، ولا يبدآن من الصفر مع كلّ دخول.
    final fails = <int, int>{
      for (var id = 1; id <= 12; id++) id: 6, // كلّها بلغت السقف
    };

    int coveredAt(int round, {required bool force}) => fails.entries
        .where((e) => deviceProbeDue(
            force: force, consecutiveFailures: e.value, round: round))
        .length;

    test('🚨 بلا force: دخولٌ واحد يفحص أقلّيّة أو لا شيء', () {
      // الدخلات المتتالية ترفع رقم الجولة واحداً واحداً.
      final perEntry = [
        for (var round = 1; round <= 5; round++)
          coveredAt(round, force: false)
      ];
      expect(
        perEntry,
        [0, 0, 0, 0, 0],
        reason: 'الجولات ١-٥ لا تقسم ٦ — فلا يُفحص جهازٌ واحد.'
            ' وهذا ما رآه المستخدم: يدخل فلا يتحدّث شيء.',
      );
      expect(coveredAt(6, force: false), 12,
          reason: 'الجولة السادسة وحدها تغطّي الجميع');
    });

    test('🚨 وبخليطٍ واقعيّ: كلّ دخولٍ يكشف مجموعةً مختلفة', () {
      // أجهزة بإخفاقاتٍ متفاوتة — الأقرب لواقع شبكةٍ نصفُها يعمل.
      final mixed = <int, int>{
        1: 2, 2: 2, 3: 3, 4: 3, 5: 4, 6: 6, 7: 6, 8: 6, 9: 5, 10: 6,
      };
      int cov(int round) => mixed.values
          .where((f) => deviceProbeDue(
              force: false, consecutiveFailures: f, round: round))
          .length;

      final counts = [for (var r = 1; r <= 3; r++) cov(r)];
      // الجولة ١: لا شيء. ٢: أصحاب الـ٢ فقط. ٣: أصحاب الـ٣ فقط.
      expect(counts, [0, 2, 2],
          reason: 'ثلاث دخلاتٍ تكشف ٤ من ١٠ — «يجلب ٣ ويوقف»');

      // ولا تكتمل التغطية إلّا عند الجولة ٦٠ (م.م.ص لـ٢·٣·٤·٥·٦).
      final seen = <int>{};
      var round = 0;
      while (seen.length < mixed.length && round < 200) {
        round++;
        for (final e in mixed.entries) {
          if (deviceProbeDue(
              force: false, consecutiveFailures: e.value, round: round)) {
            seen.add(e.key);
          }
        }
      }
      expect(round, 6,
          reason: 'ستّ جولاتٍ لتغطية الجميع — والمستخدم عدّ ثلاثاً '
              'لأنّه توقّف حين ظهر أكثرهم');
    });

    test('✅ مع force: دخولٌ واحد يغطّي الجميع — في أيّ جولة', () {
      for (var round = 1; round <= 12; round++) {
        expect(coveredAt(round, force: true), 12,
            reason: 'الجولة $round');
      }
    });

    test('✅ وحتّى الجهاز الأسوأ حالاً لا يُستثنى', () {
      expect(
        deviceProbeDue(force: true, consecutiveFailures: 999, round: 7),
        isTrue,
      );
    });
  });
}
