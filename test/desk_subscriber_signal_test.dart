import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_card_v3.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_columns.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ⑥ جدول المشتركين على الحاسبة (٢٩ أكتوبر — المالك: «ما يظهر اشارات المشتركين ولا يظهر النانو… تكدر تحقنهن
/// وي حقل الماك ip» + «والماك واسم الجهاز اعزله بحقل ثاني اختيار الاظهار»).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final now = DateTime.now().toIso8601String();
    SharedPreferences.setMockInitialValues({
      'device_probe.cache.v1': jsonEncode({
        '10.1.1.1': {
          'at': now,
          'snap': {
            'k': 'ubiquiti',
            'ip': '10.1.1.1',
            'ubnt': {
              'h': 'Ali-Nano',
              'sig': -63,
              'lan': [
                {'n': 'eth0', 's': '100Mbps', 'p': 1},
              ],
            },
          },
        },
        '10.1.1.2': {
          'at': now,
          'snap': {
            'k': 'ont',
            'ip': '10.1.1.2',
            'ont': {'tx': '1.8', 'rx': '-18.1', 'v': '3312', 't': '55', 'b': '11.4', 's': '', 'vd': 'zte', 'md': 'HS8546V6'},
          },
        },
        // ONT بلا طراز ولا مورّد مكتوب ⇒ هواوي (الأصل).
        '10.1.1.3': {
          'at': now,
          'snap': {
            'k': 'ont',
            'ip': '10.1.1.3',
            'ont': {'tx': '2.0', 'rx': '-20.0', 'v': '3300', 't': '50', 'b': '10', 's': ''},
          },
        },
      }),
    });
    await DeviceProbeApi.hydrateFromPrefs();
  });

  Subscriber sub(String user, {String? ip, String? mac, String? oui}) =>
      Subscriber.fromJson({'username': user}).copyWithOnline(online: true, ip: ip, mac: mac, device: oui);

  test('ماك الجلسة الحيّة يصل للمشترك (كان يُجلب ويُرمى)، والفارغ لا يمسح القديم', () {
    final base = Subscriber.fromJson({'username': 'u1', 'last_mac': 'AA:AA:AA:AA:AA:AA'});
    expect(base.copyWithOnline(online: true, mac: 'BB:BB:BB:BB:BB:BB').lastMac, 'BB:BB:BB:BB:BB:BB');
    expect(base.copyWithOnline(online: true, mac: ' cc:cc:cc:cc:cc:cc ').lastMac, 'cc:cc:cc:cc:cc:cc');
    expect(base.copyWithOnline(online: true).lastMac, 'AA:AA:AA:AA:AA:AA');
    expect(base.copyWithOnline(online: true, mac: '   ').lastMac, 'AA:AA:AA:AA:AA:AA');
  });

  test('اسم الجهاز: اسم النانو، ثمّ طراز الـONU، ثمّ مورّده، ثمّ مصنّع الراوتر من الساس', () {
    final nano = sub('n', ip: '10.1.1.1');
    expect(SubscriberNetworkMetrics.deviceNameOf(nano, SubscriberNetworkMetrics.snapshotOf(nano)), 'Ali-Nano');
    final zte = sub('z', ip: '10.1.1.2');
    expect(SubscriberNetworkMetrics.deviceNameOf(zte, SubscriberNetworkMetrics.snapshotOf(zte)), 'HS8546V6');
    final hw = sub('h', ip: '10.1.1.3');
    expect(SubscriberNetworkMetrics.deviceNameOf(hw, SubscriberNetworkMetrics.snapshotOf(hw)), 'Huawei');
    final router = sub('r', ip: '10.9.9.9', oui: 'Mikrotik');
    expect(SubscriberNetworkMetrics.snapshotOf(router), isNull, reason: 'لا لقطة لهذا العنوان');
    expect(SubscriberNetworkMetrics.deviceNameOf(router, null), 'Mikrotik');
    expect(SubscriberNetworkMetrics.deviceNameOf(sub('x'), null), isNull);
  });

  test('عمود «الماك / الجهاز» الجديد ظاهرٌ افتراضيّاً ويُلحق بعد «IP / الإشارة» عند من حفظ تخطيطاً قديماً', () {
    expect(SubscriberColumnPrefs.defaults.any((e) => e.$1 == SubCol.device && e.$2), isTrue);
    const old = 'phone:1,package:1,manager:1,expiration:1,remaining:1,session:1,mac:1,usage:1,balance:0';
    final l = SubscriberColumnPrefs.decode(old);
    final order = l.map((e) => e.$1).toList();
    expect(order.indexOf(SubCol.device), order.indexOf(SubCol.mac) + 1);
    expect(l.firstWhere((e) => e.$1 == SubCol.device).$2, isTrue);
    expect(l.firstWhere((e) => e.$1 == SubCol.balance).$2, isFalse, reason: 'ما أخفاه المدير يبقى مخفيّاً');
    expect(SubCol.device.sortField, isNull);
    expect(SubCol.device.minWidth, SubCol.mac.minWidth);
  });

  testWidgets('خليّة الإشارة تقرأ الكاش وحده: النانو إشارته وLAN، والـONU ضوءه وحرارته، وبلا لقطة لا شيء', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SubscriberNetworkMetrics(sub: sub('n', ip: '10.1.1.1'), wrap: true),
            SubscriberNetworkMetrics(sub: sub('z', ip: '10.1.1.2'), wrap: true),
            SubscriberNetworkMetrics(sub: sub('none', ip: '10.9.9.9'), wrap: true),
          ],
        ),
      ),
    ));
    expect(find.text('-63 dBm'), findsOneWidget);
    expect(find.text('100 Mbps'), findsOneWidget);
    expect(find.text('-18.1 dBm'), findsOneWidget);
    expect(find.text('55°C'), findsOneWidget);
    expect(find.byType(Wrap), findsNWidgets(2), reason: 'الجدول يلتفّ بدل أن يفيض؛ بلا لقطة لا يُرسم شيء');
  });
}
