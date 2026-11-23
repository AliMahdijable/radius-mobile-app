import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/util/edit_summary.dart';

// «من → إلى» لسطر التعديل في سجلّ الحركات (المالك ٢٢ نوفمبر: «سابقاً قلنا بالتعديل وصف التعديل… كيف تعديل من إلى») — بقواعد «سجلّ التعديلات».
String plain(String? s) => (s ?? '').replaceAll(RegExp('[\u2066-\u2069]'), '');

void main() {
  test('القيم «من … إلى …»، والتاريخ أرقاماً، والجديد «صار»، وعند الانتهاء', () {
    final s = editSummaryOf({
      'diff': [
        {'f': 'phone', 'from': '07701234567', 'to': '07809876543'},
        {'f': 'expiration', 'from': '2026-12-01 00:00:00', 'to': '2026-12-15 00:00:00'},
        {'f': 'wa_phone2', 'from': '', 'to': '07712223344'},
        {'f': 'profile', 'from': 'FTTH 35', 'to': 'FTTH 50', 'at_expiry': true},
      ],
    });
    expect(plain(s),
        'رقم الهاتف: من 07701234567 إلى 07809876543 · تاريخ الانتهاء: من 2026/12/01 00:00 إلى 2026/12/15 00:00 · الرقم الثاني (واتساب): صار 07712223344 · الباقة: من FTTH 35 إلى FTTH 50 (عند انتهاء الاشتراك)');
    expect(s, contains('\u206607701234567\u2069'), reason: 'الرقم معزولٌ LTR فلا ينقلب في سطرٍ عربيّ');
  });

  test('الأسرار «تغيّرت» بلا قيمة، الملاحظة بلا نصّها، والجهاز بلا قيمه، والمجهول يُترك', () {
    final s = editSummaryOf({
      'diff': [
        {'f': 'password', 'secret': true},
        {'f': 'device_pass', 'from': 'x', 'to': 'y'},
        {'f': 'note', 'change': 'added'},
        {'f': 'device_ip', 'from': '10.0.0.5', 'to': '10.0.0.9'},
        {'f': 'mystery', 'from': 'a', 'to': 'b'},
      ],
    });
    expect(s, 'كلمة المرور: تغيّرت · كلمة مرور الجهاز: تغيّرت · الملاحظة الخاصّة: أُضيفت · عنوان الجهاز: تغيّر');
    expect(s, isNot(contains('10.0.0')));
  });

  test('السطر القديم: أسماء الحقول بالعربيّة بلا «كلمة المرور»، والفارغ null', () {
    expect(editSummaryOf({
      'changes': ['profile → 6', 'phone', 'password', 'parent_id', 'profile_change_cancelled'],
    }), 'عُدّل: الباقة، رقم الهاتف، المدير، إلغاء تغيير الباقة المجدول');
    expect(editSummaryOf({}), isNull);
    expect(editSummaryOf({'diff': []}), isNull);
    expect(editSummaryOf({'changes': ['password']}), isNull);
  });
}
