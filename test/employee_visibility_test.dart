import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/api/renew_requests_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/sort_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_columns.dart';
import 'package:rad_mysvcs/services/employee_visibility.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

/// «ما يراه الموظّف» (٢٣ نوفمبر): قراءة `hidden` من الخادم، وأسئلة الشاشات ([Sees]) للموظّف وصاحب الحساب.
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

  test('المرحلة الثانية: مشتركٌ بلا اسم لا يُكشف يوزره من أيّ طريق (fullName يرجع اليوزر)', () {
    final nameless = Subscriber.fromJson({'idx': '18', 'username': 'x7@najaf', 'firstname': '', 'lastname': ''});
    expect(nameless.fullName, 'x7@najaf', reason: 'النموذج كما هو — بياناتٌ تُرسَل بها رسائل وقراءات');
    PermissionsService.debugSet(isEmployee: true, permissions: {'subscribers.view': true}, hidden: {'usernames'});
    expect(Sees.nameOf(nameless.fullName, nameless.username), kNoNameWord, reason: 'اسمٌ هو اليوزر نفسه = بلا اسم');
    expect(Sees.nameOf('X7@NAJAF ', 'x7@najaf'), kNoNameWord, reason: 'بلا فرق حروفٍ ولا مسافات');
    expect(Sees.nameOf('علي', 'x7@najaf'), 'علي');
    // التقارير: الاسم، وإلّا «بلا اسم» لسطر مشترك، وإلّا نوع الحركة
    expect(rpSubjectTitle(fullName: null, target: 'x7@najaf', username: 'x7@najaf', fallback: 'تفعيل'), kNoNameWord);
    expect(rpSubjectTitle(fullName: 'x7@najaf', username: 'x7@najaf', fallback: 'تفعيل'), kNoNameWord);
    expect(rpSubjectTitle(fullName: null, target: 'm1', username: null, fallback: 'تحويل رصيد'), 'تحويل رصيد');
    expect(rpHideUser('تفعيل نقدي - المستخدم: X7@najaf', 'x7@najaf'), 'تفعيل نقدي - المستخدم: —');
    expect(rpUserAfterName(title: 'علي', username: 'x7@najaf'), isNull);
    // طلبات التجديد: العنوان (والأفاتار والنوافذ تتبعه)
    final r = RenewRequest.fromJson({'id': 1, 'status': 'pending', 'subscriber': {'idx': '18', 'username': 'x7@najaf', 'name': ''}});
    expect(r, isNotNull, reason: 'الطلب يُقرأ');
    expect(r!.title, kNoNameWord);
    // جدول الحاسبة والترتيب: الهاتف/الرصيد/أيّام الدين/اليوزر خارجها
    PermissionsService.debugSet(
        isEmployee: true, permissions: {'subscribers.view': true}, hidden: {'usernames', 'phones', 'debts'});
    expect([for (final c in SubCol.values) if (!c.available) c], [SubCol.phone, SubCol.balance, SubCol.debtAge]);
    expect(sortFieldOptions, isNot(anyOf(contains(SortField.username), contains(SortField.phone), contains(SortField.notes),
        contains(SortField.debtAge))));
    // صاحب الحساب: كلّ شيء كما كان
    PermissionsService.debugSet(isEmployee: false);
    expect(Sees.nameOf(nameless.fullName, nameless.username), 'x7@najaf');
    expect(rpSubjectTitle(fullName: null, target: null, username: 'x7@najaf', fallback: 'تفعيل'), 'x7@najaf');
    expect(SubCol.values.where((c) => c != SubCol.usage).every((c) => c.available), isTrue);
    expect(sortFieldOptions, containsAll([SortField.username, SortField.phone, SortField.notes, SortField.debtAge]));
    expect(r.title, 'x7@najaf');
  });
}
