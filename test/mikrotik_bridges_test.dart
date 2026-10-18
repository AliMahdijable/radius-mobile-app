import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/mikrotik_api.dart';

/// بريدجات مايكروتيك (١٨ أكتوبر): أعضاء كلّ بريدج من /interface/bridge/port، وبريدج كلّ منفذ.
void main() {
  group('parseBridgePorts', () {
    test('يجمع منافذ كلّ بريدج بترتيبها ويتجاهل المعطّل والناقص', () {
      final m = MikrotikApi.parseBridgePorts([
        {'interface': 'ether2', 'bridge': 'bridge-lan', 'disabled': 'false'},
        {'interface': 'ether3', 'bridge': 'bridge-lan', 'disabled': 'false'},
        {'interface': 'ether4', 'bridge': 'bridge-lan', 'disabled': 'true'},
        {'interface': 'sfp1', 'bridge': 'bridge-wan'},
        {'interface': '', 'bridge': 'bridge-lan'},
        {'interface': 'ether9', 'bridge': ''},
      ]);
      expect(m, {
        'bridge-lan': ['ether2', 'ether3'],
        'bridge-wan': ['sfp1'],
      });
    });

    test('لا صفوف ⇒ خريطة فارغة', () {
      expect(MikrotikApi.parseBridgePorts(const []), isEmpty);
    });
  });

  test('bridgeOf: البريدج الذي ينتمي له المنفذ، وnull لغير العضو', () {
    const s = MikrotikStats(
      cpuLoad: 0,
      memUsedPercent: 0,
      memTotalBytes: 0,
      memFreeBytes: 0,
      uptime: '',
      version: '',
      boardName: '',
      architectureName: '',
      cpuCount: 1,
      cpuFrequencyMhz: 0,
      interfaces: [],
      pppActiveCount: 0,
      bridgePorts: {
        'bridge-lan': ['ether2', 'ether3'],
      },
    );
    expect(s.bridgeOf('ether3'), 'bridge-lan');
    expect(s.bridgeOf('ether1'), isNull);
    expect(s.copyWith(pppActiveCount: 3).bridgePorts, s.bridgePorts,
        reason: 'copyWith (الطبقة الثانية) يحفظ الأعضاء');
  });
}
