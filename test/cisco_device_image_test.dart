import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_image.dart';

void main() {
  test('Cisco product identifiers resolve to their own family', () {
    const cases = {
      'WS-C2960-24TT-L': 'WS-C2960-24TT-L.png',
      'WS-C2960-24TC-L': 'WS-C2960-24TC-L.png',
      'WS-C2960X-24TS-L': 'Catalyst 2960-X.png',
      'WS-C2960L-24TS-LL': 'Catalyst 2960-L.png',
      'WS-C2960CX-8TC-L': 'Catalyst 2960-CX.png',
      'WS-C3560CX-12PC-S': 'Catalyst 3560-CX.png',
      'WS-C2960S-48TS-L': 'Catalyst 2960-S.jpg',
      'C9200L-24T-4G': 'Catalyst 9200.png',
      'C9300-48P': 'Catalyst 9300.png',
      'WS-C3750G-16TD-S': 'WS-C3750G-16TD.jpg',
    };
    for (final entry in cases.entries) {
      expect(DeviceImage.assetFor(entry.key, brand: 'cisco'), entry.value,
          reason: entry.key);
      expect(File('assets/devices-images/${entry.value}').existsSync(), isTrue);
      expect(DeviceImage.assetFor(entry.key, brand: 'mikrotik'), isNull);
    }
  });

  test('unknown and adjacent Cisco families are not guessed', () {
    for (final model in ['Cisco', 'WS-C2960XR-24TS', 'C93000', 'C9500-24Y4C']) {
      expect(DeviceImage.assetFor(model, brand: 'cisco'), isNull,
          reason: model);
    }
  });

  test('all Cisco pictures can be selected manually', () {
    for (final file in DeviceImage.allAssets
        .where((f) => f.startsWith('Catalyst ') || f.startsWith('WS-C'))) {
      expect(
          DeviceImage.assetFor(DeviceImage.boardNameOf(file), brand: 'cisco'),
          file);
    }
  });
}
