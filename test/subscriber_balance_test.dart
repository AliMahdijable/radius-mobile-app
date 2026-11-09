import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// كارت الرصيد وكارت النانو — بلاغا ٢٠٢٦-٠٩-٠٢.
/// ⚠️ **درسٌ من ٢٠٢٦-٠٩-٠٣**: هذه الاختبارات مرّت كلّها بينما البطاقة
/// منهارة على شاشة المستخدم — المبلغ حرفاً في كلّ سطر. لأنّها تفتّش
/// **نصّ الملفّ** لا ما يُرسَم: «هل الزرّ مذكور؟» نعم، وهو مسحوقٌ إلى
/// صفر عرضاً.
///
/// فبقيت هنا لأنّها تحرس **النيّة** (الصفر محايد · الزرّ على البطاقة لا
/// مدفوناً)، أمّا التخطيط فيحرسه `text_crush_test.dart` بالرسم الفعليّ.
/// لا تُضِف هنا تأكيداً على شكلٍ بصريّ — أضِفه هناك.
void main() {
  late String src, card;
  setUpAll(() {
    src = File('lib/screens/subscribers/subscriber_detail_screen.dart')
        .readAsStringSync();
    card = File('lib/screens/subscribers/widgets/balance_card.dart')
        .readAsStringSync();
  });

  group('الرصيد ثلاث حالات لا اثنتان', () {
    test('🚨 البطاقة تظهر حتّى عند الصفر', () {
      // كانت تختفي كلّيّاً، فيبقى المدير بلا جواب عن سؤالٍ يسأله في
      // كلّ زيارة: «كم له وكم عليه؟». والصفر جوابٌ لا فراغ.
      expect(src.contains('if (sub.balanceAmount != 0) ...[\n'), isFalse,
          reason: 'عاد الشرط الذي يُخفي البطاقة');
      expect(card.contains('final isZero = sub.balanceAmount == 0;'), isTrue);
    });

    test('🚨 الصفر لا يُصبَغ أخضر ولا أحمر', () {
      // الأخضر يُوهم أنّ له مالاً عندك، والأحمر يتّهمه.
      expect(card.contains('final accent = isZero'), isTrue);
      expect(card.contains('? AppColors.textMid'), isTrue);
      expect(card.contains("'لا دين ولا رصيد'"), isTrue);
    });

    test('التسمية في الهيرو ثلاثيّة', () {
      expect(src.contains("? 'رصيد دائن'"), isTrue);
      expect(src.contains(": 'الرصيد',"), isTrue,
          reason: 'من رصيده صفر كان يُوسَم بـ«الدين»');
    });

    test('🚨 إضافة الدين على البطاقة لا مدفونة', () {
      // «كل الصفحات» (٩ نوفمبر): البوّابة بصلاحيّة صفحة المشترك (`_has` = خريطتها، وإلّا Perms كما كان)
      expect(src.contains('onAddDebt: _has(\'subscribers.add_debt\')'),
          isTrue);
      expect(card.contains("label: 'إضافة دين',"), isTrue);
    });

    test('التسديد للمدين وحده — الرصيد الدائن بابه «إضافة دين»', () {
      // شيتٌ يقول «لا يوجد دين» لا يفيد أحداً. و٥ سبتمبر: `balanceAmount != 0` كان يفتح «تسديد» لصاحب الرصيد الدائن
      // أيضاً — والتسديد يجمع على الرصيد لا يطرح منه، فمن له ٣٠٬٠٠٠ يصير له ٦٠٬٠٠٠. (كان الاختبار يحرس الشرط القديم.)
      expect(src.contains("onPay: sub.hasDebt && _has('subscribers.pay_debt')"), isTrue);
      expect(src.contains('onPay: sub.balanceAmount != 0 &&'), isFalse, reason: 'عاد الشرط الذي يفتح «تسديد» للرصيد الدائن');
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
