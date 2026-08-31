import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/subscriber_events.dart';

/// ختم نسخة البيانات — «قارن ما رأيتَه» بدل «تذكّر أن تُحدّث».
///
/// 🐛 بلاغ 2026-08-31: «الداش بورد يتحدث تلقائي فقط المشتركون الا رفرش».
/// الرئيسيّة مستمعها بلا بوّابة فتُحدَّث فوراً؛ وشاشة المشتركين مبوَّبة
/// لمنع setState على تبويب مخفيّ، فكان تحديثها معلَّقاً على سلسلة أحداث
/// (تغيّر الراية ← المستمع ← علم منطقيّ) — وأيّ حلقة تُفلت تعني بياناتٍ
/// بائتة إلى الأبد.
///
/// هذه الاختبارات تحرس الخاصّيّة التي تجعل الختم أمتن من العلم: الفارق
/// يبقى قائماً حتّى يُستهلك، فأيّ مسارٍ يعود إلى الرؤية يلتقطه — لا
/// المسار الذي صُمّم له وحده.
void main() {
  setUp(() => SubscriberEvents.dataChanged.value = 0);

  test('بلا تغيير ⇒ لا بيات', () {
    final seen = SubscriberEvents.dataChanged.value;
    expect(SubscriberEvents.dataChanged.value != seen, isFalse);
  });

  test('التغيير يبقى ملحوظاً مهما تأخّر الالتقاط', () {
    final seen = SubscriberEvents.dataChanged.value;
    SubscriberEvents.dataChanged.value++; // تبديل «إخفاء مدير»
    // العلم المنطقيّ كان يضيع لو لم يقرأه المسار المقصود؛ الفارق لا يضيع.
    for (var tick = 0; tick < 10; tick++) {
      expect(SubscriberEvents.dataChanged.value != seen, isTrue,
          reason: 'النبضة $tick ما زالت ترى الفارق');
    }
  });

  test('تغييرات متتالية تبقى فارقاً واحداً — لا تحديث لكلّ واحدة', () {
    final seen = SubscriberEvents.dataChanged.value;
    for (var i = 0; i < 5; i++) {
      SubscriberEvents.dataChanged.value++;
    }
    expect(SubscriberEvents.dataChanged.value != seen, isTrue);
    // بعد الاستهلاك مرّة واحدة يزول الفارق كلّه.
    final consumed = SubscriberEvents.dataChanged.value;
    expect(SubscriberEvents.dataChanged.value != consumed, isFalse);
  });

  test('العدّاد يتقدّم ولا يعود — فلا التباس بين نسختين', () {
    var last = SubscriberEvents.dataChanged.value;
    for (var i = 0; i < 20; i++) {
      SubscriberEvents.dataChanged.value++;
      expect(SubscriberEvents.dataChanged.value, greaterThan(last));
      last = SubscriberEvents.dataChanged.value;
    }
  });
}
