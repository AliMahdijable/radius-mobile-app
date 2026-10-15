import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/util/email_shape.dart';

/// بلاغ ٢٠٢٦-١٠-١٥: يوزر سوبرنت (`admin@najaf202`) يُكتب في خانة إيميل الحساب.
void main() {
  test('يوزرات الساس بشكل الإيميل تُكشف', () {
    for (final u in ['admin@najaf202', 'admin@sk24', ' admin@LGAS ', 'abusaleh@qn331', 'fras@adya10']) {
      expect(looksLikeSasUsername(u), isTrue, reason: u);
    }
  });

  test('الإيميلات الحقيقيّة وما ليس يوزراً لا تُكشف', () {
    for (final e in [
      'hassan@gmail.com',
      'owner@test.local',
      'test@mysvcs.net',
      'name@sub.domain.iq',
      'admin', // بلا @
      '@najaf202', // بلا اسم
      'a@b@c', // @ مرّتان
      'admin@', // بلا نطاق
      '',
    ]) {
      expect(looksLikeSasUsername(e), isFalse, reason: e);
    }
  });
}
