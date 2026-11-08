import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

/// صلاحيّات الموظّف (٨ نوفمبر — المالك: «صلاحيه موظف يربط vpn ويفحص شامل ويفحص مشترك»): كما يفرضها الخادم (agentRoutes):
/// صاحب الحساب كلّ شيء؛ الموظّف بمفتاحه — «ربط VPN» لا يفتح الفحصين، و«الفحص الشامل» لا يفتح فحص المشتركين، و«تنبيهات المشتركين»
/// يفتح الفحصين كما كان.
void main() {
  tearDown(PermissionsService.debugReset);

  test('صاحب الحساب: كلّ شيء', () {
    PermissionsService.debugSet(isEmployee: false);
    expect([
      PermissionsService.canLinkVpn,
      PermissionsService.canDeepCheck,
      PermissionsService.canSubsVpnCheck,
      PermissionsService.canDevicesVpn,
    ], [true, true, true, true]);
  });

  test('الموظّف بلا مفاتيح: لا شيء (مكانها مقفلاً بالواجهة)', () {
    PermissionsService.debugSet(isEmployee: true, permissions: const {'devices.view': true, 'subscribers.view': true});
    expect([
      PermissionsService.canLinkVpn,
      PermissionsService.canDeepCheck,
      PermissionsService.canSubsVpnCheck,
      PermissionsService.canDevicesVpn,
    ], [false, false, false, false]);
  });

  test('كلّ مفتاحٍ يفتح ما له وحده', () {
    PermissionsService.debugSet(isEmployee: true, permissions: const {'conn_vpn.link': true});
    expect([PermissionsService.canLinkVpn, PermissionsService.canDeepCheck, PermissionsService.canSubsVpnCheck, PermissionsService.canDevicesVpn],
        [true, false, false, true], reason: '«ربط VPN»: الشاشة ووضع VPN للأجهزة');
    PermissionsService.debugSet(isEmployee: true, permissions: const {'devices.deep_check': true});
    expect([PermissionsService.canLinkVpn, PermissionsService.canDeepCheck, PermissionsService.canSubsVpnCheck, PermissionsService.canDevicesVpn],
        [false, true, false, true]);
    PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.vpn_check': true});
    expect([PermissionsService.canLinkVpn, PermissionsService.canDeepCheck, PermissionsService.canSubsVpnCheck, PermissionsService.canDevicesVpn],
        [false, false, true, false]);
    PermissionsService.debugSet(isEmployee: true, permissions: const {'conn_alerts.use': true});
    expect([PermissionsService.canLinkVpn, PermissionsService.canDeepCheck, PermissionsService.canSubsVpnCheck, PermissionsService.canDevicesVpn],
        [false, true, true, true], reason: 'قسم «تنبيهات المشتركين» يفتح الفحصين كما كان');
  });
}
