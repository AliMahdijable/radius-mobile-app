// ١٢ نوفمبر (بلاغ وكيل: «الواتساب فصل نهائياً ومجاي يربط»): الحساب مربوطٌ على 0788… والمدير يطلب رمزاً لـ0773…
// الخادم صار يردّ 409 LINKED_TO_OTHER_NUMBER (بدل إعادة الربط القديم بصمت)، والرقم نفسه ⇒ «متّصل أصلاً».
// هذا يثبت قراءة الردود: «code» في الرفض رمزُ سبب لا رمز اقتران، و«متّصل أصلاً» ليس خطأً.
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';

void main() {
  group('WaPairCodeStart.fromBody', () {
    test('رمز اقترانٍ عاديّ', () {
      final r = WaPairCodeStart.fromBody({
        'success': true,
        'pairCode': 'K7QX-2M9P',
        'phone': '9647730830030',
        'message': 'أدخل الكود في واتساب',
      });
      expect(r.ok, isTrue);
      expect(r.code, 'K7QX-2M9P');
      expect(r.alreadyConnected, isFalse);
      expect(r.linkedToOtherNumber, isFalse);
    });

    test('خادمٌ قديم يرسل الرمز في code مع success ⇒ يُقرأ رمزاً', () {
      final r = WaPairCodeStart.fromBody({'success': true, 'code': 'ABCD-EFGH'});
      expect(r.code, 'ABCD-EFGH');
    });

    test('409 LINKED_TO_OTHER_NUMBER ⇒ ليس رمزاً، ومعه المربوط والمطلوب', () {
      final r = WaPairCodeStart.fromBody({
        'success': false,
        'code': 'LINKED_TO_OTHER_NUMBER',
        'linkedToOtherNumber': true,
        'unlinkRequired': true,
        'linkedPhone': '9647883330099',
        'pushname': 'مركز البرق',
        'requestedPhone': '9647730830030',
        'message': 'واتساب هذا الحساب مربوط على الرقم 07883330099',
      });
      expect(r.ok, isFalse);
      expect(r.code, isNull, reason: 'رمز السبب لا يُعرض رمزَ اقتران');
      expect(r.linkedToOtherNumber, isTrue);
      expect(r.alreadyConnected, isFalse);
      expect(r.linkedPhone, '9647883330099');
      expect(r.pushname, 'مركز البرق');
      expect(r.requestedPhone, '9647730830030');
      expect(r.message, contains('07883330099'));
    });

    test('الرمز السببيّ وحده (بلا linkedToOtherNumber) يكفي', () {
      final r = WaPairCodeStart.fromBody({'success': false, 'code': 'LINKED_TO_OTHER_NUMBER'});
      expect(r.linkedToOtherNumber, isTrue);
      expect(r.code, isNull);
    });

    test('الرقم نفسه متّصل ⇒ alreadyConnected بلا رمز ولا خطأ', () {
      final r = WaPairCodeStart.fromBody({
        'success': true,
        'alreadyConnected': true,
        'phone': '9647730830030',
        'message': 'واتساب متّصل أصلاً على هذا الرقم ✅ — ما يحتاج رمز',
      });
      expect(r.ok, isTrue);
      expect(r.alreadyConnected, isTrue);
      expect(r.code, isNull);
      expect(r.linkedToOtherNumber, isFalse);
    });

    test('فشلٌ آخر برمز سبب ⇒ لا رمز اقتران', () {
      final r = WaPairCodeStart.fromBody({'success': false, 'code': 'COMPOSITE_RESET_BLOCKED', 'message': 'x'});
      expect(r.ok, isFalse);
      expect(r.code, isNull);
      expect(r.linkedToOtherNumber, isFalse);
    });
  });

  group('WaPairCodeStart.localPhone', () {
    test('9647… ⇒ 07…', () {
      expect(WaPairCodeStart.localPhone('9647883330099'), '07883330099');
      expect(WaPairCodeStart.localPhone('9647730830030@c.us'), '07730830030');
    });
    test('غير العراقيّ والفارغ كما هما', () {
      expect(WaPairCodeStart.localPhone('96170123456'), '96170123456');
      expect(WaPairCodeStart.localPhone(null), '');
      expect(WaPairCodeStart.localPhone(''), '');
    });
  });

  test('isLinkedToOtherNumber على Map عامّ (ردّ Dio)', () {
    expect(WaPairCodeStart.isLinkedToOtherNumber(<dynamic, dynamic>{'code': 'LINKED_TO_OTHER_NUMBER'}), isTrue);
    expect(WaPairCodeStart.isLinkedToOtherNumber(<dynamic, dynamic>{'linkedToOtherNumber': true}), isTrue);
    expect(WaPairCodeStart.isLinkedToOtherNumber(<dynamic, dynamic>{'code': 'X'}), isFalse);
  });
}
