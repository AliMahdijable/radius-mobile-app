import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/cards_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';

// مراجعة §١٢: عدد الكارتات لا يُرسم من كاشٍ قديم، ونتيجة التفعيل الملتبسة
// لا تُعرض «تعذّراً» يُغري بضغطةٍ (وكارتٍ) ثانية.
void main() {
  setUp(CardsState.reset);

  group('CardsState — الحيّ لا المبذور', () {
    test('بذر كاش اللوحة يرسم العدد لكنّه ليس حيّاً (فيُطلب الحيّ)', () {
      CardsState.seed(const CardsBadge(enabled: true, remaining: 3));
      expect(CardsState.badge.value?.remaining, 3);
      expect(CardsState.isLive, isFalse);
    });

    test('admin-widgets يجعله حيّاً، وغياب الحقل (خادمٌ أقدم) لا', () {
      CardsState.applyAdminWidgets(null);
      expect(CardsState.isLive, isFalse);
      CardsState.applyAdminWidgets({'enabled': true, 'remaining': 2});
      expect(CardsState.isLive, isTrue);
      expect(CardsState.badge.value?.remaining, 2);
    });

    test('نتيجةٌ ملتبسة تُبطل الحيّ — والعدد الظاهر يبقى حتى يصل الجديد', () {
      CardsState.applyAdminWidgets({'enabled': true, 'remaining': 2});
      CardsState.invalidate();
      expect(CardsState.isLive, isFalse);
      expect(CardsState.badge.value?.remaining, 2);
    });

    test('خادمٌ بلا الميزة يُسجَّل مرّة، والخروج يمسح كلّ شيء', () {
      CardsState.markUnsupported();
      expect(CardsState.isUnsupported, isTrue);
      CardsState.applyAdminWidgets({'enabled': true, 'remaining': 1});
      CardsState.reset();
      expect(CardsState.isUnsupported, isFalse);
      expect(CardsState.isLive, isFalse);
      expect(CardsState.badge.value, isNull);
    });
  });

  group('نتيجة التفعيل الملتبسة', () {
    test('رموز «ربّما نُفّذ» من الخادم ومن المهلة', () {
      for (final c in ['OUTCOME_UNKNOWN', 'NOT_CONFIRMED', 'APPLIED_WITH_ERRORS', 'IN_PROGRESS']) {
        expect(SubscribersApi.activateUnclearCodes.contains(c), isTrue, reason: c);
      }
      expect(SubscribersApi.activateUnclearCodes.contains(CardsApi.codeNoCards), isFalse);
      expect(SubscribersApi.activateUnclearCodes.contains(CardsApi.codeCardNotAllowed), isFalse);
    });

    test('ردّ 409 OUTCOME_UNKNOWN يُقرأ رمزاً لا نجاحاً', () {
      final r = SubscribersApi.activateResultFromBody({
        'success': false,
        'code': 'OUTCOME_UNKNOWN',
        'message': 'لا نعرف إن نُفّذ',
      });
      expect(r.ok, isFalse);
      expect(r.code, SubscribersApi.activateOutcomeUnknown);
      expect(r.card, isNull);
    });
  });
}
