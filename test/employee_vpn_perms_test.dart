import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

/// صلاحيّتا الفحصين بوجهين (٨ نوفمبر — المالك: «تفصله للموظف… بتخيره بوضع vpn او على الشبكه هم يكدر يختارهن الاثنين او واحد ع
/// الاقل… الافتراضي يكون لديه صلاحيه على شبكه فقط»): على الشبكة مفعّلٌ افتراضاً (والموظّف القديم بلا المفتاح يأخذه)، وعبر VPN بمفتاحه
/// — كما يفرضه الخادم (agentRoutes).
void main() {
  tearDown(PermissionsService.debugReset);

  List<bool> all() => [
        PermissionsService.canLinkVpn,
        PermissionsService.deepCheckNet,
        PermissionsService.deepCheckVpn,
        PermissionsService.subsCheckNet,
        PermissionsService.subsCheckVpn,
        PermissionsService.canDevicesVpn,
      ];

  test('صاحب الحساب: كلّ شيء', () {
    PermissionsService.debugSet(isEmployee: false);
    expect(all(), [true, true, true, true, true, true]);
  });

  test('موظّفٌ قديم بلا المفاتيح الجديدة: على الشبكة وحده (الافتراضيّ)', () {
    PermissionsService.debugSet(isEmployee: true, permissions: const {'devices.view': true, 'subscribers.view': true});
    expect(all(), [false, true, false, true, false, false]);
  });

  test('المدير أطفأ «على الشبكة» صراحةً ولم يفعّل VPN ⇒ لا شيء (الميزة تختفي)', () {
    PermissionsService.debugSet(
        isEmployee: true, permissions: const {'devices.deep_check': false, 'subscribers.check': false});
    expect(all(), [false, false, false, false, false, false]);
  });

  test('عبر VPN وحده، أو الوجهان معاً', () {
    PermissionsService.debugSet(isEmployee: true, permissions: const {
      'devices.deep_check': false,
      'devices.deep_check_vpn': true,
      'subscribers.check': false,
      'subscribers.vpn_check': true,
    });
    expect(all(), [false, false, true, false, true, true]);
    PermissionsService.debugSet(isEmployee: true, permissions: const {
      'devices.deep_check': true,
      'devices.deep_check_vpn': true,
      'subscribers.check': true,
      'subscribers.vpn_check': true,
      'conn_vpn.link': true,
    });
    expect(all(), [true, true, true, true, true, true]);
  });

  test('قسم «تنبيهات المشتركين» يفتح فحص المشتركين عبر VPN وحده (لا الأجهزة ولا الممرّ)', () {
    PermissionsService.debugSet(isEmployee: true, permissions: const {'conn_alerts.use': true});
    expect(all(), [false, true, false, true, true, false]);
  });
}
