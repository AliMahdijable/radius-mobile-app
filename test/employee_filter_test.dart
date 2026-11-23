import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/employee_filter.dart';

/// «أكثر من موظّف بالفلاتر» (المالك ٢٣ نوفمبر) — عقد الخادم (d9 dff8f91): واحدٌ ⇒ employee_id، اثنان فأكثر ⇒ employee_ids،
/// والخادم الذي طبّقها يعلّم ردّه بـemployee_filter؛ غيابها مع اثنين فأكثر ⇒ لا أرقام.
void main() {
  test('البارامترات: لا أحد ⇒ لا شيء، واحدٌ ⇒ employee_id كالقديم، اثنان فأكثر ⇒ employee_ids مرتّبةً بلا تكرار', () {
    expect(employeeQuery(const []), isEmpty);
    expect(employeeQuery(const [7]), {'employee_id': '7'});
    expect(employeeQuery(const [7, 7]), {'employee_id': '7'}, reason: 'التكرار واحد');
    expect(employeeQuery(const [9, 7, 9, 3]), {'employee_ids': '3,7,9'});
  });

  test('الإشارة: واحدٌ لا يحتاجها؛ اثنان فأكثر يُعتمدان فقط إن ردّ الخادم بالمعرّفات نفسها', () {
    expect(employeeFilterHonored(const [], null), isTrue);
    expect(employeeFilterHonored(const [7], {'success': true}), isTrue, reason: 'خادمٌ قديم يفهم employee_id');
    expect(employeeFilterHonored(const [7, 9], {'success': true}), isFalse, reason: 'خادمٌ قديم تجاهل employee_ids');
    expect(employeeFilterHonored(const [7, 9], null), isFalse);
    expect(employeeFilterHonored(const [7, 9], {'employee_filter': [9, 7]}), isTrue);
    expect(employeeFilterHonored(const [7, 9], {'employee_filter': ['7', '9']}), isTrue, reason: 'نصوصٌ أو أرقام');
    expect(employeeFilterHonored(const [7, 9], {'employee_filter': [7]}), isFalse, reason: 'طبّق بعضها ⇒ لا');
    expect(employeeFilterHonored(const [7, 9], {'employee_filter': [7, 9, 11]}), isFalse);
    expect(employeeFilterHonored(const [7, 9], {'employee_filter': '7,9'}), isFalse, reason: 'ليست قائمة');
  });
}
