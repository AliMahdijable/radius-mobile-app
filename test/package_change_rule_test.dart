import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/edit_subscriber_sheet.dart';

/// تغيير باقة مشتركٍ فعّال (١٨ أكتوبر): الساس يصفّر تاريخ الانتهاء عند التغيير، فيُسمح فقط
/// حين يُرسَل التاريخ الأصليّ مع الطلب (مديرٌ يملك تعديل التاريخ — كالكلاسيك)، وايرث لنك على قاعدتها.
///
/// ⚠️ هذه القاعدة **السابقة** لـSAS4 وتبقى أمام خادمٍ لا يعرف «حالاً / عند انتهاء الاشتراك»
/// (activation-data بلا حقوله) — ولايرث لنك دائماً. والخادم الذي يعرفهما يسلك قرار المالك
/// (اختيار «متى؟» بلا منع): `package_change_timing_test.dart`.
void main() {
  final now = DateTime(2026, 10, 18, 2);
  final active = DateTime(2026, 11, 16, 14, 42, 31);
  final expired = DateTime(2026, 10, 1);
  // ايرث لنك: بقي أقلّ من يوم — نافذة canChangeAccount.
  final lastDay = DateTime(2026, 10, 18, 12);

  bool blocked({
    bool changes = true,
    DateTime? until,
    bool noExpiry = false,
    bool keeps = false,
    bool el = false,
    bool? elAllows,
  }) =>
      packageChangeBlocked(
        changesPackage: changes,
        activeUntil: noExpiry ? null : (until ?? active),
        keepsDate: keeps,
        isEarthlink: el,
        earthlinkAllows: elAllows,
        now: now,
      );

  test('سوبرنت/SAS4 بمديرٍ يملك التاريخ: يُسمح ويبقى التاريخ (يُرسَل مع الطلب)', () {
    expect(blocked(keeps: true), isFalse);
  });

  test('مديرٌ بلا صلاحيّة التاريخ: يُمنع أثناء التفعيل (وإلّا يُقطع اشتراك المشترك)', () {
    expect(blocked(keeps: false), isTrue);
  });

  test('ايرث لنك بلا حكم الخادم: يُمنع وقد بقي أكثر من يوم، ولو أُرسل التاريخ', () {
    expect(blocked(keeps: true, el: true), isTrue);
    expect(blocked(el: true), isTrue);
  });

  test('المنتهي أو غير المفعَّل: لا منع لأحد', () {
    expect(blocked(until: expired), isFalse);
    expect(blocked(until: expired, el: true), isFalse);
    expect(blocked(noExpiry: true), isFalse);
    expect(blocked(noExpiry: true, el: true), isFalse);
  });

  test('لا تغيير للباقة: لا منع', () {
    expect(blocked(changes: false), isFalse);
    expect(blocked(changes: false, el: true), isFalse);
    expect(blocked(changes: false, el: true, elAllows: false), isFalse);
  });

  // تدقيق ١٨ أكتوبر (الدفعة ①): التطبيق كان يمنع ايرث لنك كلّما كان فعّالاً، والويب
  // والخادم يسمحان بيومه الأخير (canChangeAccount — مؤكَّدٌ حيّاً ١٣ أكتوبر).
  group('ايرث لنك على canChangeAccount', () {
    test('🚨 يومه الأخير مسموح — بلا حكم الخادم (نافذة ٢٤ ساعة)', () {
      expect(blocked(until: lastDay, el: true), isFalse);
    });

    test('حكم الخادم يغلب النافذة: يسمح ⇒ يُسمح ولو بقي شهر', () {
      expect(blocked(el: true, elAllows: true), isFalse);
      expect(blocked(until: lastDay, el: true, elAllows: true), isFalse);
    });

    test('حكم الخادم يمنع ⇒ يُمنع ولو في يومه الأخير، و«More» ولو منتهياً', () {
      expect(blocked(until: lastDay, el: true, elAllows: false), isTrue);
      expect(blocked(until: expired, el: true, elAllows: false), isTrue);
    });

    test('إرسال التاريخ لا يغيّر حكمها (لا تاريخ يُضبط عندها)', () {
      expect(blocked(until: lastDay, el: true, keeps: true), isFalse);
      expect(blocked(el: true, elAllows: false, keeps: true), isTrue);
    });

    test('والساس لا يتأثّر بحكم ايرث لنك', () {
      expect(blocked(keeps: false, elAllows: true), isTrue);
      expect(blocked(keeps: true, elAllows: false), isFalse);
    });
  });
}
