import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/services/employee_visibility.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

/// «ما يشوفه الموظّف» (٢٣ نوفمبر): قراءة `hidden` من الخادم، وأسئلة الشاشات ([Sees]) للموظّف وصاحب الحساب.
void main() {
  tearDown(PermissionsService.debugReset);

  test('hiddenFrom: الأصناف الخمسة المعروفة وحدها، وما ليس قائمةً ⇒ لا شيء', () {
    expect(hiddenFrom(['debts', 'phones', 'x', null, 3, 'usernames']), {'debts', 'phones', 'usernames'});
    expect(hiddenFrom(null), isEmpty);
    expect(hiddenFrom('debts'), isEmpty);
    expect(hiddenFrom({'debts': true}), isEmpty);
    expect(kSeeCategories, {'debts', 'usernames', 'phones', 'counts', 'balance'});
  });

  test('CurrentIdentity: hidden من /employees/me، وغيابه ⇒ لا شيء مخفيّ (خادمٌ أقدم/الميزة مطفأة)', () {
    final a = CurrentIdentity.fromJson({'is_employee': true, 'permissions': {'subscribers.view': true}, 'hidden': ['balance', 'debts']})!;
    expect(a.hidden, {'balance', 'debts'});
    final b = CurrentIdentity.fromJson({'is_employee': true, 'permissions': {'subscribers.view': true}})!;
    expect(b.hidden, isEmpty);
  });

  test('Sees: الموظّف بما أخفاه مديره، وصاحب الحساب يرى كلّ شيء ولو حُمّلت قائمة', () {
    PermissionsService.debugSet(isEmployee: true, permissions: {'subscribers.view': true}, hidden: {'debts', 'usernames'});
    expect([Sees.debts, Sees.usernames, Sees.phones, Sees.counts, Sees.balance], [false, false, true, true, true]);
    expect(PermissionsService.hidden, {'debts', 'usernames'});
    expect(Sees.nameOf('علي حسن', 'ali1@najaf'), 'علي حسن');
    expect(Sees.nameOf('  ', 'ali1@najaf'), kNoNameWord, reason: 'بلا اسمٍ واليوزر مخفيّ');
    PermissionsService.debugSet(isEmployee: false, hidden: {'debts', 'usernames', 'phones', 'counts', 'balance'});
    expect([Sees.debts, Sees.usernames, Sees.phones, Sees.counts, Sees.balance], everyElement(isTrue));
    expect(PermissionsService.hidden, isEmpty);
    expect(Sees.nameOf(null, 'ali1@najaf'), 'ali1@najaf');
  });
}
