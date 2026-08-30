import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/network_device.dart';

/// بروتوكول أجهزة UBNT ومنفذها.
///
/// ⚠️ التباسٌ أوقع بلاغاً حقيقيّاً (2026-08-30): المشروع يسمّي المراقبة
/// الحيّة «api» لكلّ العلامات، بينما اتّصال UBNT **هو SSH على 22**
/// (mca-status — يعمل على airOS 5/6/7/8 بلا فروق). فالشارة كانت تعرض
/// «API» على جهاز Ubiquiti، والمستخدم — محقّاً — قال إنّها يجب أن تكون
/// SSH. والأسوأ أنّ من سجّل جهازه بـ`ssh` (الوصف الأصحّ) كان يُحرَم من
/// اللوحة كلّها ومن كشف الطراز معها.
void main() {
  test('UBNT + api ⇒ المنفذ 22 لا 8728 — SSH لا واجهة ثنائيّة', () {
    expect(NetworkDeviceLabels.portForBrandProtocol('ubnt', 'api'), 22);
    expect(NetworkDeviceLabels.portForBrandProtocol('mikrotik', 'api'), 8728);
  });

  test('ssh يعطي 22 لكلّ العلامات', () {
    for (final b in ['ubnt', 'mikrotik', 'mimosa', 'other']) {
      expect(NetworkDeviceLabels.portForBrandProtocol(b, 'ssh'), 22,
          reason: 'العلامة $b');
    }
  });

  test('Mimosa تبقى على SNMP — SSH مقفول في الـfirmware', () {
    expect(NetworkDeviceLabels.portForBrandProtocol('mimosa', 'snmp'), 161);
  });
}
