import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// كارت الرصيد وكارت النانو — بلاغا ٢٠٢٦-٠٩-٠٢.
void main() {
  late String src;
  setUpAll(() {
    src = File('lib/screens/subscribers/subscriber_detail_screen.dart')
        .readAsStringSync();
  });

  group('الرصيد ثلاث حالات لا اثنتان', () {
    test('🚨 البطاقة تظهر حتّى عند الصفر', () {
      // كانت تختفي كلّيّاً، فيبقى المدير بلا جواب عن سؤالٍ يسأله في
      // كلّ زيارة: «كم له وكم عليه؟». والصفر جوابٌ لا فراغ.
      expect(src.contains('if (sub.balanceAmount != 0) ...[\n'), isFalse,
          reason: 'عاد الشرط الذي يُخفي البطاقة');
      expect(src.contains('final isZero = sub.balanceAmount == 0;'), isTrue);
    });

    test('🚨 الصفر لا يُصبَغ أخضر ولا أحمر', () {
      // الأخضر يُوهم أنّ له مالاً عندك، والأحمر يتّهمه.
      expect(src.contains('final accent = isZero\n        ? AppColors.textMid'),
          isTrue);
      expect(src.contains("isZero ? 'لا دين ولا رصيد'"), isTrue);
    });

    test('التسمية في الهيرو ثلاثيّة', () {
      expect(src.contains("? 'رصيد دائن'"), isTrue);
      expect(src.contains(": 'الرصيد',"), isTrue,
          reason: 'من رصيده صفر كان يُوسَم بـ«الدين»');
    });

    test('🚨 إضافة الدين على البطاقة لا مدفونة', () {
      expect(src.contains('onAddDebt: Perms.has(\'subscribers.add_debt\')'),
          isTrue);
      expect(src.contains("label: 'إضافة دين',"), isTrue);
    });

    test('التسديد يبقى مشروطاً برصيدٍ غير صفر', () {
      // شيتٌ يقول «لا يوجد دين» لا يفيد أحداً.
      expect(src.contains('onPay: sub.balanceAmount != 0 &&'), isTrue);
    });
  });

  group('كارت النانو', () {
    test('🚨 يظهر للمعطَّل والمنتهي', () {
      // التعطيل قرارٌ في الفوترة، والنانو جهازٌ على سطح بيت. ومن
      // يُعطَّل هو بالضبط من تحتاج فحص جهازه.
      expect(src.contains('if (!sub.isExpired && !sub.isDisabled) ...['), isFalse,
          reason: 'عاد الشرط الذي يُخفي الكارت عن المعطَّل');
      final i = src.indexOf('DeviceProbeCard(');
      expect(i, greaterThan(0));
      final before = src.substring(i - 200, i);
      expect(before.contains('isDisabled'), isFalse);
    });
  });
}
