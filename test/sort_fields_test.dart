import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/sort_sheet.dart';

/// كلّ حقل فرز له بلاطة وتسمية مترجَمة في اللغتين.
///
/// 🐛 لماذا وُجد (بلاغ 2026-08-31): «الترتيب حسب البور والإشارة — شو
/// اختفى هذا؟». الالتزام d3f443b حذف شريط شرائح فرز الأجهزة بحجّة أنّ
/// «شيت ترتيب القائمة يغطّي الحاجة» — ولم يكن يغطّيها: الشريط ذهب ولم
/// يصل شيء إلى الشيت، فضاعت أربعة مقاييس (RX الضوئي · إشارة اللاسلكي ·
/// CCQ · سرعة LAN) بلا أن يلاحظ أحد.
///
/// وهذا شكلٌ من فقدان الميزات لا يمسكه أيّ اختبار سلوكيّ: الكود يُترجم
/// ويعمل، والوظيفة غائبة. الحارس الوحيد الممكن هو إحصاء التعداد مقابل
/// ما يُعرَض فعلاً.
void main() {
  // ملاحظة: `easy_localization` غير مهيّأة هنا، فـ`.tr()` تُرجع المفتاح
  // نفسه — وهذا مفيد: الخرج يصير هو المفتاح، فنتحقّق من وجوده في
  // ملفّي الترجمة مباشرةً بدل الاكتفاء بأنّه «غير فارغ».
  test('كلّ قيمة في SortField لها بلاطة ومفتاح مترجَم', () {
    final ar = File('assets/translations/ar.json').readAsStringSync();
    final en = File('assets/translations/en.json').readAsStringSync();
    final seen = <String>{};
    for (final f in SortField.values) {
      final key = sortFieldLabel(f);
      // '' يعني أنّ الحقل غير مدرَج في `_fieldDefs` — أُضيف إلى التعداد
      // ونُسي في الشيت، فلا تظهر له بلاطة ولا يستطيع أحد اختياره.
      expect(key, isNotEmpty, reason: '$f غير مدرَج في _fieldDefs');
      expect(seen.add(key), isTrue, reason: '$f يتقاسم مفتاح «$key»');
      final suffix = key.split('.').last;
      expect(ar.contains('"$suffix"'), isTrue,
          reason: 'sort.$suffix مفقود في ar.json');
      expect(en.contains('"$suffix"'), isTrue,
          reason: 'sort.$suffix مفقود في en.json');
    }
  });

  test('مقاييس الأجهزة الأربعة موجودة', () {
    // تُذكَر بالاسم لا بالعدد: من يحذف واحداً يجب أن يواجه هذا السطر.
    for (final f in [
      SortField.deviceRx,
      SortField.deviceSignal,
      SortField.deviceCcq,
      SortField.deviceLan,
    ]) {
      expect(SortField.values, contains(f));
    }
  });

  test('كلّ مفتاح فرز مترجَم في العربيّة والإنجليزيّة', () {
    for (final loc in ['ar', 'en']) {
      final raw = File('assets/translations/$loc.json').readAsStringSync();
      for (final key in [
        'device_rx',
        'device_signal',
        'device_ccq',
        'device_lan',
      ]) {
        expect(raw.contains('"$key"'), isTrue,
            reason: 'sort.$key مفقود في $loc.json');
      }
    }
  });
}
