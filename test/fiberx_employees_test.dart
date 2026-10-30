import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/screens/app_modules.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

/// موظّفونا لحساب فايبر اكس (٣١ أكتوبر — المالك: «فايبر اكس خلي موظفينا فقط معلينها بموظفيهم… احنه اصلا موفرين هلمزية»).
/// الخادم 575b931 يفرض مفاتيح كتالوج الموظّفين على مسارات فايبر اكس؛ هنا ما يعرضه التطبيق: مفاتيح فايبر اكس وحدها في
/// المحرّر وما يُرسل، وقسم «الموظّفون» مفتوحٌ لحساب فايبر اكس.
void main() {
  tearDown(() {
    ProviderService.debugSet(null);
    PermissionsService.debugReset();
  });

  test('المفاتيح تتبع الشركة المفتوحة: فايبر اكس بلا إضافة/تعديل/إيقاف مشترك ولا كلمة سرّه أو موقعه ولا الجلسات', () {
    ProviderService.debugSet('fiberx');
    final k = ElEmployeePerms.keys;
    for (final on in ['subscribers.view', 'subscribers.activate', 'subscribers.extend', 'subscribers.pay_debt', 'reports.financial', 'sales.sell']) {
      expect(k.contains(on), isTrue, reason: on);
    }
    for (final off in [
      'subscribers.add',
      'subscribers.edit',
      'subscribers.toggle',
      'subscribers.view_credentials',
      'subscribers.edit_location',
      'reports.sessions',
      'employees.manage',
      'managers.view',
    ]) {
      expect(k.contains(off), isFalse, reason: off);
    }
    expect(ElEmployeePerms.hintFor('reports.financial'), 'يشمل رصيد المحفظة وحركاتها');
    ProviderService.debugSet('earthlink');
    expect(ElEmployeePerms.keys.contains('subscribers.add'), isTrue, reason: 'ايرث لنك كما كان');
    expect(ElEmployeePerms.hintFor('reports.financial'), 'يشمل رصيد الوكيل والكارتات المطلوبة');
  });

  test('ما يُرسل لموظّف فايبر اكس: مفاتيحه بقيمها والباقي false (لا يُمنح ما لا يراه المالك)', () {
    ProviderService.debugSet('fiberx');
    final out = ElEmployeePerms.outgoing(
      const ['subscribers.view', 'subscribers.add', 'subscribers.toggle', 'whatsapp.send', 'subscribers.send_whatsapp'],
      {'subscribers.view': true, 'subscribers.add': true, 'subscribers.toggle': true, 'subscribers.send_whatsapp': true},
    );
    expect(out, {
      'subscribers.view': true,
      'subscribers.add': false,
      'subscribers.toggle': false,
      'whatsapp.send': true,
      'subscribers.send_whatsapp': true,
    });
    expect(ElEmployeePerms.activeCount({'subscribers.view': true, 'subscribers.add': true}), 1);
  });

  test('قسم «الموظّفون» مفتوحٌ لحساب فايبر اكس (كان «غير متاح لحساب فايبر اكس بعد»)', () {
    ProviderService.debugSet('fiberx');
    PermissionsService.debugSet(isEmployee: false);
    final m = buildAppModules().where((x) => x.id == 'employees').toList();
    expect(m, hasLength(1));
    expect(m.single.unavailable, isNull);
    expect(m.single.isLocked, isFalse);
  });
}
