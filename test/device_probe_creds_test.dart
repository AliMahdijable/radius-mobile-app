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
}
