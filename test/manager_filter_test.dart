import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';

/// فلتر المدير الفرعي — «الكل» يجب أن تعني «بلا فلتر» لا «فلتر فارغ».
///
/// بلاغ 2026-08-31: المدير يختار مديراً فرعيّاً، يتصفّح، ثمّ يرجع إلى
/// «الكل» — فتُفرَّغ القائمة كلّها (0 مشترك · 0 نتيجة) ولا تعود القيم
/// إلّا بإغلاق التطبيق وفتحه.
void main() {
  test('«الكل» تصل سلسلةً فارغة — يجب أن تُطبَّع إلى null', () {
    // هذا هو البلاغ حرفيّاً: الشيت يُرجع `_picked ?? ''`.
    expect(normalizeManagerFilter(''), isNull);
  });

  test('الإغلاق بلا تطبيق لا يترك فلتراً', () {
    expect(normalizeManagerFilter(null), isNull);
  });

  test('مدير مختار يمرّ كما هو', () {
    expect(normalizeManagerFilter('admin@xuuo12'), 'admin@xuuo12');
  });

  test('الفراغ وحده يُطبَّع — لا يصير فلتراً على اسم فارغ', () {
    expect(normalizeManagerFilter('   '), isNull);
  });

  test('المسافات الطرفيّة تُقصّ ولا تُفسد المطابقة', () {
    // `_managerScoped` يقارن `parentUsername == _managerFilter` مقارنةً
    // حرفيّة، فمسافة واحدة زائدة كانت تكفي لتفريغ القائمة.
    expect(normalizeManagerFilter(' admin@xuuo4 '), 'admin@xuuo4');
  });

  test('نوع غير نصّي لا يصير فلتراً', () {
    expect(normalizeManagerFilter(42), isNull);
    expect(normalizeManagerFilter(const <String>[]), isNull);
  });
}
