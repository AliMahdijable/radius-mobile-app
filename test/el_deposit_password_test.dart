import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/el_deposit_password.dart';
import 'package:rad_mysvcs/services/subscriber_usage_store.dart';
import 'package:rad_mysvcs/widgets/el_deposit_password_field.dart';

/// باسورد إيداع ايرث لنك المحفوظ (160): الحالة من ردود الخادم، وما يُرسَل.
void main() {
  setUp(ElDepositPassword.reset);

  group('observe — ردود عمليّات الرصيد', () {
    test('saved_cleared ⇒ غير محفوظ (رفضته ايرث لنك فمُسح)', () {
      ElDepositPassword.status.value =
          const ElDepositStatus(saved: true, canManage: true);
      ElDepositPassword.observe({'success': false, 'code': 'DEPOSIT_PASSWORD', 'saved_cleared': true});
      expect(ElDepositPassword.status.value!.saved, isFalse);
      expect(ElDepositPassword.status.value!.canManage, isTrue);
    });

    test('deposit_password_saved ⇒ محفوظ (حُفظ مع العمليّة)', () {
      ElDepositPassword.status.value =
          const ElDepositStatus(saved: false, canManage: true);
      ElDepositPassword.observe({'success': true, 'deposit_password_saved': true});
      expect(ElDepositPassword.status.value!.saved, isTrue);
    });

    test('مطلوبٌ والتطبيق يظنّه محفوظاً ⇒ غير محفوظ (مُسح من جهازٍ آخر)', () {
      ElDepositPassword.status.value =
          const ElDepositStatus(saved: true, canManage: false);
      ElDepositPassword.observe({'success': false, 'code': 'DEPOSIT_PASSWORD_REQUIRED'});
      expect(ElDepositPassword.status.value!.saved, isFalse);
    });

    test('رفضٌ لباسورد مكتوب (بلا saved_cleared) لا يغيّر المحفوظ', () {
      ElDepositPassword.status.value =
          const ElDepositStatus(saved: true, canManage: true);
      ElDepositPassword.observe({'success': false, 'code': 'DEPOSIT_PASSWORD'});
      expect(ElDepositPassword.status.value!.saved, isTrue);
    });

    test('جسمٌ غير خريطة يُهمل', () {
      ElDepositPassword.observe('<html>');
      ElDepositPassword.observe(null);
      expect(ElDepositPassword.status.value, isNull);
    });
  });

  group('ElDepositPasswordController — ما يُرسَل', () {
    test('محفوظ ⇒ لا نصّ يُرسَل والزرّ جاهز', () {
      ElDepositPassword.status.value =
          const ElDepositStatus(saved: true, canManage: true);
      final c = ElDepositPasswordController();
      expect(c.useSaved, isTrue);
      expect(c.ready, isTrue);
      expect(c.passwordToSend, isNull);
      expect(c.rememberToSend, isFalse);
      c.dispose();
    });

    test('غير محفوظ ⇒ المكتوب + «احفظه» للمالك وحده', () {
      ElDepositPassword.status.value =
          const ElDepositStatus(saved: false, canManage: true);
      final c = ElDepositPasswordController();
      expect(c.ready, isFalse);
      c.text.text = ' dep-1 ';
      expect(c.ready, isTrue);
      expect(c.passwordToSend, 'dep-1');
      expect(c.rememberToSend, isTrue);
      c.remember = false;
      expect(c.rememberToSend, isFalse);
      c.dispose();

      ElDepositPassword.status.value =
          const ElDepositStatus(saved: false, canManage: false); // موظّف
      final e = ElDepositPasswordController();
      e.text.text = 'dep-2';
      expect(e.passwordToSend, 'dep-2');
      expect(e.rememberToSend, isFalse);
      e.dispose();
    });

    test('«تغيير» ⇒ يُرسَل الجديد، و«استعمال المحفوظ» يعود بلا نصّ', () {
      ElDepositPassword.status.value =
          const ElDepositStatus(saved: true, canManage: true);
      final c = ElDepositPasswordController();
      c.startChange();
      expect(c.useSaved, isFalse);
      expect(c.ready, isFalse);
      c.text.text = 'new-dep';
      expect(c.passwordToSend, 'new-dep');
      c.useSavedAgain();
      expect(c.useSaved, isTrue);
      expect(c.text.text, isEmpty);
      c.dispose();
    });

    test('مُسح المحفوظ (رُفض) ⇒ يُفرَّغ المكتوب ويعود الحقل', () {
      ElDepositPassword.status.value =
          const ElDepositStatus(saved: true, canManage: true);
      final c = ElDepositPasswordController();
      c.startChange();
      c.text.text = 'x';
      ElDepositPassword.observe({'saved_cleared': true});
      expect(c.saved, isFalse);
      expect(c.changing, isFalse);
      expect(c.text.text, isEmpty);
      expect(c.ready, isFalse);
      c.dispose();
    });

    test('لم تُحمَّل الحالة بعد ⇒ loading ولا جاهزيّة بلا نصّ', () {
      final c = ElDepositPasswordController();
      expect(c.loading, isTrue);
      expect(c.ready, isFalse);
      c.dispose();
    });
  });

  test('reset يمسح الحالة (خروج/تبديل حساب)', () {
    ElDepositPassword.status.value =
        const ElDepositStatus(saved: true, canManage: true);
    ElDepositPassword.reset();
    expect(ElDepositPassword.status.value, isNull);
  });

  group('formatUsageBytes', () {
    test('الصفر «0» والغائب «—»', () {
      expect(formatUsageBytes(null), '—');
      expect(formatUsageBytes(0), '0');
    });
    test('MB/GB/TB', () {
      expect(formatUsageBytes(500 * 1024), '<1 MB');
      expect(formatUsageBytes(5 * 1048576 + 524288), '5.5 MB');
      expect(formatUsageBytes(820 * 1048576), '820 MB');
      expect(formatUsageBytes((5.6 * 1073741824).round()), '5.60 GB');
      expect(formatUsageBytes((52.8 * 1073741824).round()), '52.8 GB');
      expect(formatUsageBytes(248 * 1073741824), '248 GB');
      expect(formatUsageBytes((1.56 * 1099511627776).round()), '1.56 TB');
    });
  });
}
