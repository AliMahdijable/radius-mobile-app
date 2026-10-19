import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/platform/store_policy.dart';

/// سياسة المتجر ورسائل المساعد الذكيّ — الأمر العراقيّ «رقّي باقتك» (بالياء)
/// كان يفلت من قاعدة «أو رقّ باقتك» ومن فحص الدعوة معاً (SPEC §16.1).
void main() {
  tearDown(() => StorePolicy.debugHidePurchaseFlows = null);

  group('آيفون', () {
    setUp(() => StorePolicy.debugHidePurchaseFlows = true);

    test('«خلصت أسئلة اليوم — ترجع باچر أو رقّي باقتك» ← بلا الدعوة', () {
      expect(
        StorePolicy.storeSafe('خلصت أسئلة اليوم — ترجع باچر أو رقّي باقتك'),
        'خلصت أسئلة اليوم — ترجع باچر',
      );
    });

    test('«… — رقّي باقتك لأسئلة أكثر» تُحذف قطعتها', () {
      expect(
        StorePolicy.storeSafe('وصلت حدّ الأسئلة — رقّي باقتك لأسئلة أكثر'),
        'وصلت حدّ الأسئلة',
      );
    });

    test('القديمة باقية: «أو رقِّ باقتك» و«رقّ باقتك»', () {
      expect(
          StorePolicy.storeSafe('وصلت حدّ الأجهزة أو رقِّ باقتك لأجهزة أكثر'),
          'وصلت حدّ الأجهزة');
      expect(StorePolicy.storeSafe('حدّ الشركات (3) — رقّ باقتك لإضافة المزيد'),
          'حدّ الشركات (3)');
    });

    test(
        'سطرٌ كلّه دعوة: storeSafe ← جملةٌ محايدة، وstoreSafeLine ← فراغ (يُسقَط)',
        () {
      expect(StorePolicy.storeSafe('رقّي باقتك'), 'تعذّر إتمام العمليّة');
      expect(StorePolicy.storeSafeLine('رقّي باقتك من الإعدادات'), isEmpty);
      expect(StorePolicy.storeSafeLine('افتح المشترك واضغط «تعديل»'),
          'افتح المشترك واضغط «تعديل»');
    });

    test('«ترقية» عن غير الباقة وعمل المشتركين لا تُمسّ', () {
      expect(StorePolicy.storeSafe('كود التفعيل غير صحيح'),
          'كود التفعيل غير صحيح');
      expect(
          StorePolicy.storeSafe('رقم الهاتف غير صحيح'), 'رقم الهاتف غير صحيح');
    });
  });

  group('آيفون — أجوبة المساعد (assistantSafeLine)', () {
    setUp(() => StorePolicy.debugHidePurchaseFlows = true);

    test('دعوة شراء/تفعيل/زيادة حدّ بصياغة النموذج تُحذف', () {
      for (final line in [
        'صاحب الحساب يجدّد الاشتراك بكود تفعيل من فريق MyServices.',
        'اطلب كود تفعيل من فريق MyServices وفعّله من «الاشتراك وكود التفعيل».',
        'جدّد اشتراكك حتى ترجع تدخل شركاتك.',
        'تواصل معنا حتى نزيد حدّ الشركات بباقتك.',
        'أو تواصل معنا لزيادة الحدّ.',
        'اشترك بالباقة الأعلى حتى تحصل على موظّفين أكثر.',
        'من «الحساب والاشتراك» اضغط «تفعيل كود».',
      ]) {
        expect(StorePolicy.assistantSafeLine(line), isEmpty, reason: line);
      }
    });

    test('الجملة الداعية وحدها تسقط وتبقى المعلومة', () {
      expect(
        StorePolicy.assistantSafeLine(
            'وصلت حدّ الشركات. شيل شركة ما تستعملها من «شركاتي». أو تواصل معنا لزيادة الحدّ.'),
        'وصلت حدّ الشركات. شيل شركة ما تستعملها من «شركاتي».',
      );
    });

    test('عمل المشتركين يبقى كما هو', () {
      for (final line in [
        'جدّد اشتراك المشترك من نافذة التفعيل.',
        'غيّر المشترك لباقة أعلى من «تعديل».',
        'كود التفعيل المطبوع على الكارت لازم يتكتب كامل.',
        'افتح «أجهزتي» وأزل جهازاً ما تستعمله.',
      ]) {
        expect(StorePolicy.assistantSafeLine(line), line, reason: line);
      }
    });

    test('رسائل الخادم (storeSafe) لا تتغيّر بقواعد المساعد', () {
      expect(StorePolicy.storeSafe('كود التفعيل غير صحيح'),
          'كود التفعيل غير صحيح');
    });
  });

  test('غير آيفون: الرسالة كما هي حرفيّاً', () {
    StorePolicy.debugHidePurchaseFlows = false;
    const m = 'خلصت أسئلة اليوم — ترجع باچر أو رقّي باقتك';
    expect(StorePolicy.storeSafe(m), m);
    expect(StorePolicy.storeSafeLine(m), m);
    const cta = 'اطلب كود تفعيل من فريق MyServices.';
    expect(StorePolicy.assistantSafeLine(cta), cta);
  });

  group('سياق اشتراك الحساب (روابط الدعم على آيفون)', () {
    test('آيفون: الباقة والحدود والترقية ⇒ نعم', () {
      StorePolicy.debugHidePurchaseFlows = true;
      for (final s in [
        'شلون أرقّي باقتي؟',
        'شلون أزيد حدّ الموظّفين؟',
        'بلغت الحدّ الأقصى لعدد الموظّفين لهذا الحساب (3).',
        'وصلت حدّ الأجهزة',
        'وصلت حدّ الشركات',
        'انتهى اشتراكك',
        'بيش الترقية؟',
        'how do I upgrade my plan?',
      ]) {
        expect(StorePolicy.isAccountPlanContext(s), isTrue, reason: s);
      }
    });

    test('آيفون: عمل المشتركين ⇒ لا', () {
      StorePolicy.debugHidePurchaseFlows = true;
      for (final s in [
        'شلون أغيّر باقة المشترك؟',
        'جدّد اشتراك المشترك',
        'المشترك غير موجود في حساب هذا المدير',
        'شلون أضيف موظف واحد؟',
        'حسابك ما يسمح بالتفعيل بالرصيد',
        '',
      ]) {
        expect(StorePolicy.isAccountPlanContext(s), isFalse, reason: s);
      }
    });

    test('غير آيفون: لا شيء', () {
      StorePolicy.debugHidePurchaseFlows = false;
      expect(StorePolicy.isAccountPlanContext('شلون أرقّي باقتي؟'), isFalse);
    });
  });
}
