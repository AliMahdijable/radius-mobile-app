import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// دفق نتائج الفحص — بلاغ ٢٠٢٦-٠٩-٠٢: «فحص الأجهزة بطيء بالعرض، كأنّه
/// ينتظر جواب جهاز جهاز».
void main() {
  late String list;
  late String card;
  late String detail;
  late String regions;

  setUpAll(() {
    list = File('lib/screens/network_devices/network_devices_screen.dart')
        .readAsStringSync();
    card = File('lib/screens/network_devices/widgets/device_big_card.dart')
        .readAsStringSync();
    detail = File('lib/screens/subscribers/subscriber_detail_screen.dart')
        .readAsStringSync();
    regions = File('lib/screens/network_devices/regions_screen.dart')
        .readAsStringSync();
  });

  group('الرسم لا ينتظر اكتمال الجولة', () {
    test('🚨 القائمة تدفق تدريجيّاً', () {
      // الجولة كانت ترسم مرّةً بعد اكتمالها كلّها: ثمانون جهازاً على
      // ٢٤ عاملاً، والمنقطع يستهلك مهلته كاملةً — أربع موجاتٍ = ثماني
      // ثوانٍ جمود، وأوّل جهازٍ ردّ بعد جزءٍ من الثانية. («نظرة عامّة»
      // أُلغيت ٣١ أكتوبر — صار عرضها «بطاقات كبيرة» بجولة القائمة نفسها.)
      for (final e in {'القائمة': list}.entries) {
        expect(e.value.contains('scheduleFlush();'), isTrue,
            reason: '${e.key} ما زالت ترسم مرّةً واحدة');
        expect(e.value.contains('void flush()'), isTrue, reason: e.key);
      }
    });

    test('🚨 مخنوق لا لكلّ جهاز', () {
      // ثمانون إعادة بناء كاملة للقائمة = إطارات ساقطة، وهو ما تجنّبته
      // النسخة الأصليّة بـsetState واحد. الخنق يجمع الفائدتين.
      for (final src in [list]) {
        expect(src.contains('if (pendingFlush) return;'), isTrue);
        expect(src.contains('Duration(milliseconds: 400)'), isTrue,
            reason: 'رسمتان أو ثلاث في الثانية على الأكثر');
      }
    });
  });

  group('صورة الجهاز', () {
    test('🚨 «البطاقات الكبيرة» تعرضها', () {
      // كانت في مخطّط «نظرة عامّة» وسقطت من التنفيذ (بلاغ ٢٠٢٦-٠٩-٠٢). والصورة تُميّز السكتور من
      // السويتش من البرج بلمحة، قبل قراءة اسمٍ واحد.
      expect(card.contains('DeviceImage(brand: device.brand, model: device.model'), isTrue);
    });
  });

  group('الاستهلاك', () {
    test('🚨 بلا شرط اتّصال', () {
      // الاستهلاك **تاريخ** يقرأه SAS4 من سجلّاته، لا قياسٌ لحظيّ.
      // بل هو أنفع للمنقطع: من يشكو انقطاعاً تُسأل عن استهلاكه أمس.
      final i = detail.indexOf("'subscribers.op_consumption'");
      expect(i, greaterThan(0));
      final before = detail.substring(i - 400, i);
      expect(before.contains('if (sub.isOnline)'), isFalse,
          reason: 'عاد شرط الاتّصال — يُخفي بيانات من يحتاجها');
    });
  });

  group('الحشو السفليّ', () {
    test('🚨 وضع التحديد وشاشة المناطق أيضاً', () {
      // فاتا الحارس الأوّل لأنّه فحص سطراً سطراً والاستدعاء ملفوف.
      expect(list.contains('Sp.md, 0, Sp.md, Inset.tabBar(context)'), isTrue);
      expect(
          RegExp(r'Inset\.tabBar\(context\)').allMatches(list).length, 2,
          reason: 'الوضعان العاديّ والتحديد كلاهما');
      expect(regions.contains('Inset.route(context)'), isTrue);
    });
  });
}
