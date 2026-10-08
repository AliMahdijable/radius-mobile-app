import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/auth_api.dart';

// Pro البند ٤: نماذج ردود /api/account/* — الشكل كما يرسله الخادم (accounts.js).
void main() {
  group('AccountSubscription', () {
    test('تجربة فعّالة', () {
      final s = AccountSubscription.fromJson({
        'status': 'trial',
        'active': true,
        'daysLeft': 12,
        'endsAt': '2026-10-20T10:00:00.000Z',
        'trialEndsAt': '2026-10-20T10:00:00.000Z',
        'validUntil': null,
      });
      expect(s.isTrial, isTrue);
      expect(s.active, isTrue);
      expect(s.daysLeft, 12);
      expect(s.endsAt, isNotNull);
      expect(s.trialUsedElsewhere, isFalse);
    });

    test('بريدٌ أخذ تجربته بحسابٍ آخر: منتهٍ بلا أيّ تاريخ', () {
      final s = AccountSubscription.fromJson({'status': 'expired', 'active': false, 'daysLeft': 0});
      expect(s.active, isFalse);
      expect(s.trialUsedElsewhere, isTrue);
    });

    test('تجربةٌ انتهت ليست «أُخذت سابقاً»', () {
      final s = AccountSubscription.fromJson({
        'status': 'expired',
        'active': false,
        'trialEndsAt': '2026-09-01T00:00:00.000Z',
      });
      expect(s.trialUsedElsewhere, isFalse);
    });

    test('حقولٌ ناقصة لا ترمي', () {
      final s = AccountSubscription.fromJson(const {});
      expect(s.status, 'none');
      expect(s.active, isFalse);
      expect(s.daysLeft, 0);
    });
  });

  test('AccountMe: معطّل ومسجَّل', () {
    final me = AccountMe.fromJson({
      'registered': true,
      'email': 'a@b.com',
      'accountStatus': 'disabled',
      'subscription': {'status': 'active', 'active': true, 'daysLeft': 30},
    });
    expect(me.registered, isTrue);
    expect(me.disabled, isTrue);
    expect(me.subscription.active, isTrue);
  });

  test('LinkedCompany: رابط الساس والدور', () {
    final c = LinkedCompany.fromJson({
      'sasCode': 'jt',
      'sasUrl': 'https://sas.jt.iq',
      'username': 'admin@ali122',
      'label': 'sas.jt.iq',
      'role': 'employee',
      'lastLoginAt': '2026-10-08T12:00:00.000Z',
    });
    expect(c.sasUrl, 'https://sas.jt.iq');
    expect(c.isEmployee, isTrue);
    expect(c.lastLoginAt, isNotNull);
  });

  test('LinkedCompany: بلا label يُعرض الرمز', () {
    final c = LinkedCompany.fromJson({'sasCode': 'otto', 'username': 'u'});
    expect(c.label, 'otto');
    expect(c.role, 'admin');
    expect(c.sasUrl, isNull);
  });

  group('كابتشا دخول الساس', () {
    test('SasCaptcha: معرّف + صورة base64', () {
      final c = SasCaptcha.tryParse({'id': '3f2a-…', 'image': '/9j/4AAQ'});
      expect(c, isNotNull);
      expect(c!.id, '3f2a-…');
      expect(c.image.take(3).toList(), [0xFF, 0xD8, 0xFF]); // JPEG
    });

    test('SasCaptcha: ناقصٌ أو معطوب ← null', () {
      expect(SasCaptcha.tryParse(null), isNull);
      expect(SasCaptcha.tryParse({'id': 'x'}), isNull);
      expect(SasCaptcha.tryParse({'id': 'x', 'image': '%%%'}), isNull);
    });

    test('رموز الكابتشا والرابط ليست بوّابة الحساب', () {
      final cap = SasCaptcha.tryParse({'id': 'x', 'image': '/9j/4AAQ'});
      final need = LoginFailure('اكتب الرمز', code: 'captcha-required', captcha: cap);
      expect(need.needsCaptcha, isTrue);
      expect(need.isAccountGate, isFalse);
      expect(const LoginFailure('', code: 'captcha-cancelled').isCancelled, isTrue);
      expect(const LoginFailure('', code: 'captcha-cancelled').isAccountGate, isFalse);
      expect(const LoginFailure('x', code: 'bad-sas-url').isAccountGate, isFalse);
      expect(const LoginFailure('x').isAccountGate, isFalse);
      expect(const LoginFailure('x', code: 'subscription-ended').isAccountGate, isTrue);
      // captcha-required بلا صورةٍ صالحة لا يفتح النافذة
      expect(const LoginFailure('x', code: 'captcha-required').needsCaptcha, isFalse);
    });
  });

  test('AccountApiException: الشبكة تُعرف', () {
    expect(const AccountApiException('network', 'x', 0).isNetwork, isTrue);
    expect(const AccountApiException('auth-unavailable', 'x', 503).isNetwork, isTrue);
    expect(const AccountApiException('not-found', 'x', 400).isNetwork, isFalse);
  });
}
