import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/models/device_health.dart';

/// اعتمادات فحص جهاز المشترك (٢٧ أكتوبر، المالك على ZTE MH80: «خليت يوزر وباسورد وميجلب شي»): ما ضبطه الوكيل للمشترك
/// يُستعمل ولو بقي النوع «تلقائي» — كان يُهمل فيُجرَّب الافتراض ويرفضه الجهاز. القيم هنا وهميّة.
void main() {
  const admin = AdminDeviceDefaults(ontUsername: 'adm-ont', ontPassword: 'adm-ont-p', ubntUsername: 'adm-ub', ubntPassword: 'adm-ub-p');

  test('«تلقائي» + اعتمادات المشترك ⇒ للنوعين (ONT وUBNT)', () {
    final c = DeviceProbeApi.credsFor(const DeviceConfig(username: 'sub-u', password: 'sub-p'), admin);
    expect([c.ontUser, c.ontPass, c.ubntUser, c.ubntPass], ['sub-u', 'sub-p', 'sub-u', 'sub-p']);
  });

  test('النوع المختار يحصر اعتمادات المشترك فيه، والآخر من افتراضات المدير', () {
    final ont = DeviceProbeApi.credsFor(const DeviceConfig(deviceType: DeviceKind.ont, username: 'sub-u', password: 'sub-p'), admin);
    expect([ont.ontUser, ont.ontPass, ont.ubntUser, ont.ubntPass], ['sub-u', 'sub-p', 'adm-ub', 'adm-ub-p']);
    final ub = DeviceProbeApi.credsFor(const DeviceConfig(deviceType: DeviceKind.ubiquiti, username: 'sub-u', password: 'sub-p'), admin);
    expect([ub.ontUser, ub.ontPass, ub.ubntUser, ub.ubntPass], ['adm-ont', 'adm-ont-p', 'sub-u', 'sub-p']);
  });

  test('بلا اعتمادات للمشترك ⇒ افتراضات المدير، وبلاها افتراض المصنّع', () {
    final c = DeviceProbeApi.credsFor(null, admin);
    expect([c.ontUser, c.ubntUser], ['adm-ont', 'adm-ub']);
    final f = DeviceProbeApi.credsFor(const DeviceConfig(username: '  '), AdminDeviceDefaults.empty);
    expect(f.ontUser, isNotEmpty);
    expect(f.ubntUser, isNotEmpty);
    expect(f.ontUser, isNot('  '), reason: 'يوزرٌ فارغ لا يُعدّ اعتماداً');
  });

  // ⑦ (٢٩ أكتوبر — المالك: «مرات عدهم أكثر من يوزر وباسورد موحّد»): حتى ثلاثة اعتماداتٍ لكلّ نوع، تُجرَّب بالترتيب.
  group('مرشّحو الاعتماد', () {
    final factory = DeviceProbeApi.credsFor(null, AdminDeviceDefaults.empty);
    final ontFactory = DeviceCred(factory.ontUser, factory.ontPass);
    final ubntFactory = DeviceCred(factory.ubntUser, factory.ubntPass);
    const e1 = DeviceCred('x-1', 'x-1-p');
    const e2 = DeviceCred('x-2', 'x-2-p');

    test('الخانة الأولى ثمّ الإضافيّان بالترتيب، ولا افتراض مصنّع', () {
      const d = AdminDeviceDefaults(
          ontUsername: 'adm-ont', ontPassword: 'adm-ont-p', ontExtra: [e1, e2],
          ubntUsername: 'adm-ub', ubntPassword: 'adm-ub-p', ubntExtra: [e2]);
      final c = DeviceProbeApi.candidatesFor(null, d);
      expect(c.ont, [const DeviceCred('adm-ont', 'adm-ont-p'), e1, e2]);
      expect(c.ubnt, [const DeviceCred('adm-ub', 'adm-ub-p'), e2]);
      expect(c.ontFactory, isNull);
    });

    test('الخانة الأولى فارغة ⇒ الإضافيّان ثمّ افتراض المصنّع آخراً، ومعلَّمٌ كي لا يُجرَّب على ZTE', () {
      const d = AdminDeviceDefaults(ontExtra: [e1], ubntExtra: [e1, e2]);
      final c = DeviceProbeApi.candidatesFor(null, d);
      expect(c.ont, [e1, ontFactory], reason: 'جهاز هواوي يعمل بالافتراض لا يتوقّف لأنّ الوكيل أضاف إضافيّاً');
      expect(c.ontFactory, ontFactory);
      expect(c.ubnt, [e1, e2, ubntFactory]);
    });

    test('اعتماد المشترك وحده — ضبطه الوكيل لهذا الجهاز', () {
      const d = AdminDeviceDefaults(ontUsername: 'adm-ont', ontPassword: 'p', ontExtra: [e1], ubntExtra: [e2]);
      final c = DeviceProbeApi.candidatesFor(const DeviceConfig(username: 'sub-u', password: 'sub-p'), d);
      expect(c.ont, [const DeviceCred('sub-u', 'sub-p')]);
      expect(c.ubnt, [const DeviceCred('sub-u', 'sub-p')]);
      expect(c.ontFactory, isNull);
      final pinned = DeviceProbeApi.candidatesFor(
          const DeviceConfig(deviceType: DeviceKind.ont, username: 'sub-u', password: 'sub-p'), d);
      expect(pinned.ont, [const DeviceCred('sub-u', 'sub-p')]);
      expect(pinned.ubnt, [e2, ubntFactory], reason: 'النوع الآخر من سلسلة المدير');
    });

    test('بلا تكرار، وبلا شيء ⇒ افتراض المصنّع وحده', () {
      const d = AdminDeviceDefaults(ontUsername: 'x-1', ontPassword: 'x-1-p', ontExtra: [e1, e2, e2]);
      expect(DeviceProbeApi.candidatesFor(null, d).ont, [e1, e2]);
      final none = DeviceProbeApi.candidatesFor(null, AdminDeviceDefaults.empty);
      expect(none.ont, [ontFactory]);
      expect(none.ontFactory, ontFactory);
      expect(none.ubnt, [ubntFactory]);
    });

    test('من الخادم وإليه: اليوزر الفارغ يُسقط، وبحدّ اثنين، والقائمتان تُرسلان دائماً', () {
      final d = AdminDeviceDefaults.fromJson({
        'ontUsername': 'adm-ont',
        'ontPassword': 'p',
        'ontExtra': [
          {'username': '  ', 'password': 'ignored'},
          {'username': ' x-1 ', 'password': 'x-1-p'},
          {'username': 'x-2', 'password': 'x-2-p'},
          {'username': 'x-3', 'password': 'x-3-p'},
        ],
        'ubntExtra': 'not-a-list',
      });
      expect(d.ontExtra, [e1, e2]);
      expect(d.ubntExtra, isEmpty);
      final j = d.toJson();
      expect(j['ontExtra'], [
        {'username': 'x-1', 'password': 'x-1-p'},
        {'username': 'x-2', 'password': 'x-2-p'},
      ]);
      expect(j['ubntExtra'], isEmpty, reason: 'قائمةٌ فارغة تمسح ما حُفظ — لا غيابٌ يبقيه');
      expect(AdminDeviceDefaults.fromJson({'ontUsername': 'a'}).ontExtra, isEmpty, reason: 'خادمٌ قديم بلا الحقل');
    });
  });
}
