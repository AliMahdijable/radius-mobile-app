import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/employees_api.dart';

/// مفتاح «المساعد الذكي» لا يظهر بمحرّر الموظّفين قبل تفعيل المساعد: الكتالوج
/// بلاه ([PermissionsCatalog.without]) — لا يُعرض ولا يُعدّ ولا يُرسل، فيُبقي
/// الخادم قيمة الموظّف المحفوظة.
void main() {
  final catalog = PermissionsCatalog.fromJson({
    'permissions': {
      'subscribers.view': {
        'category': 'subscribers',
        'label': 'عرض المشتركين',
        'default': true,
      },
      'assistant.use': {
        'category': 'tools',
        'label': 'المساعد الذكي',
        'default': true,
      },
    },
    'categories': {
      'subscribers': {'label': 'المشتركون'},
      'tools': {'label': 'أدوات'},
    },
    'defaults': {'subscribers.view': true, 'assistant.use': true},
    'presets': {
      'cashier': {
        'label': 'كاشير',
        'description': 'يفعّل',
        'permissions': {'subscribers.view': true, 'assistant.use': true},
      },
    },
  });

  test('without(assistant.use): لا مفتاح بالكتالوج ولا الافتراضيّ ولا القوالب',
      () {
    final c = catalog.without(const {ElEmployeePerms.assistantKey});
    expect(c.permissions.keys, ['subscribers.view']);
    expect(c.defaults.keys, ['subscribers.view']);
    expect(c.permsByCategory.keys, ['subscribers'], reason: 'فئةٌ فارغة تسقط');
    expect(c.presets['cashier']!.permissions, {'subscribers.view': true});
    expect(c.categories.keys, containsAll(['subscribers', 'tools']));
  });

  test('ما لا يحمل المفتاح يعود كما هو', () {
    final c = catalog.without(const {'no.such.key'});
    expect(identical(c, catalog), isTrue);
  });

  test('عدّ صلاحيّات البلاطة (ساس) بلا المساعد — كعدّ ايرث لنك', () {
    final e = Employee.fromJson({
      'id': 7,
      'username': 'cashier1',
      'permissions': {
        'subscribers.view': true,
        'subscribers.activate': 1,
        'assistant.use': true,
        'debts.pay': false,
      },
    })!;
    expect(e.activePermsCount, 2);
    expect(ElEmployeePerms.activeCount(e.permissions), e.activePermsCount,
        reason: 'العدّان بلا المساعد');
  });

  test('موظّف ايرث لنك: المفتاح خارج الكتالوج لا يُرسل (outgoing)', () {
    final c = catalog.without(const {ElEmployeePerms.assistantKey});
    final out = ElEmployeePerms.outgoing(
        c.permissions.keys, {'subscribers.view': true, 'assistant.use': false});
    expect(out.containsKey('assistant.use'), isFalse);
  });
}
