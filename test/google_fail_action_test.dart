import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:rad_mysvcs/services/account_service.dart';

/// بلاغ ٢٠٢٦-١٠-١٦: على أجهزةٍ (تكنو/هونر…) يختفي اختيار حساب Google بعد النقر بلا دخول —
/// Credential Manager يُرجع «إلغاء». القرار: الإلغاء صامتٌ (والشاشة تعرض «عبر المتصفّح» بأندرويد)،
/// وأيّ عطلٍ آخر بأندرويد يذهب للمتصفّح تلقائيّاً، وiOS يرمي كما كان.
void main() {
  const cancelLike = {
    GoogleSignInExceptionCode.canceled,
    GoogleSignInExceptionCode.interrupted,
  };

  test('إلغاء/مقاطعة ⇒ صامت على المنصّتين', () {
    for (final android in [true, false]) {
      for (final c in cancelLike) {
        expect(AccountService.googleFailAction(c, android: android), GoogleFailAction.cancel,
            reason: '$c android=$android');
      }
    }
  });

  test('أندرويد: كلّ عطلٍ غير الإلغاء ⇒ المتصفّح تلقائيّاً · iOS: يُرمى', () {
    for (final c in GoogleSignInExceptionCode.values) {
      if (cancelLike.contains(c)) continue;
      expect(AccountService.googleFailAction(c, android: true), GoogleFailAction.browser, reason: '$c');
      expect(AccountService.googleFailAction(c, android: false), GoogleFailAction.rethrowError, reason: '$c');
    }
  });
}
