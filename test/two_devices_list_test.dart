import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_card_v3.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «مشترك بجهازين» بالقائمة (١٤ نوفمبر — المقترح الذي قبله المالك: «الاولية تكون للنانو وبالنسبة لوضع الراوتر فيكفي اظهار عدد
/// المتصلين والايثر شكد يقره»): موجة القائمة تفحص الراوتر بعد النانو لمن له جهازٌ ثانٍ (والنانو يردّ)، والكرت يُظهر شريحة الراوتر
/// بنهاية سطر «متصل منذ» — المتّصلون · سرعة منفذه، أو «مطفي» — بلا أن يطول الكرت. لا جهاز ثانٍ / النانو لا يردّ ⇒ لا شريحة.
const _nanoIp = '10.9.1.1';
const _routerIp = '10.9.9.2';

Map<String, dynamic> _row(String user) {
  final exp = DateTime.now().add(const Duration(days: 20, hours: 3));
  String two(int n) => n.toString().padLeft(2, '0');
  return {
    'idx': user == 'twodev' ? '7001' : '7002',
    'username': user,
    'firstname': 'علي',
    'lastname': 'حسن',
    'profile_name': 'Economy--2',
    'package_price': 35000,
    'expiration': '${exp.year}-${two(exp.month)}-${two(exp.day)} ${two(exp.hour)}:${two(exp.minute)}:00',
    'remaining_days': 20,
    'online_status': 1,
    'enabled': 1,
    'ip': _nanoIp,
    'session_time': 86400 * 2 + 3600,
  };
}

DeviceHealthSnapshot _nano() => DeviceHealthSnapshot.fromJson({
      'k': 'ubiquiti',
      'ip': _nanoIp,
      'ubnt': {'h': 'nano', 'sig': -58, 'ccq': 96, 'lan': [{'n': 'eth0', 's': '100Mbps-Full', 'p': 1}]},
    })!;

DeviceHealthSnapshot _router() => DeviceHealthSnapshot.fromJson({
      'k': 'ubiquiti',
      'ip': _routerIp,
      'ubnt': {'h': 'Tenda', 'vd': 'tenda', 'pc': 6, 'wl': 100},
    })!;

void main() {
  late SimServer server;
  var nanoUp = true;
  var routerUp = true;
  var routerCalls = 0;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'myservices'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
    DeviceConfigApi.clearAllCaches();
    nanoUp = true;
    routerUp = true;
    routerCalls = 0;
    server.reply('POST', '/api/v2/subscribers/device-batch', 200, {
      'success': true,
      'configs': {
        'twodev': {'secondAddress': _routerIp, 'secondUsername': 'admin', 'secondPassword': 'x1'},
        'onedev': {'customIp': ''},
      },
    });
    server.reply('GET', '/api/admin/device-defaults', 200, {'success': true, 'defaults': {}});
    DeviceProbeApi.debugRunProbe = (ip) async {
      if (ip == _nanoIp) return nanoUp ? _nano() : null;
      if (ip == _routerIp) {
        routerCalls++;
        return routerUp ? _router() : null;
      }
      return null;
    };
  });

  tearDown(() {
    DeviceProbeApi.debugRunProbe = null;
    PermissionsService.debugReset();
  });

  Future<void> wave() async {
    await DeviceProbeApi.warmProbe([
      (username: 'twodev', ip: _nanoIp, company: null),
      (username: 'onedev', ip: _nanoIp, company: null),
    ], force: true, concurrency: 1);
  }

  Future<double> card(WidgetTester t, String user, {double width = 480}) async {
    await pumpSim(t, SimVariant(width, dark: false),
        home: (_) => Scaffold(
              body: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                SubscriberCardV3(sub: Subscriber.fromJson(_row(user)), selected: false, onTap: () {}, onLongPress: () {}),
              ]),
            ));
    await t.pump();
    return t.getSize(find.byType(SubscriberCardV3)).height;
  }

  testWidgets('الموجة تفحص الراوتر بعد النانو لمن له جهازٌ ثانٍ وحده، والكرت يُظهر «6 · 100M» بلا أن يطول', (t) async {
    await t.runAsync(wave);
    expect(routerCalls, 1, reason: 'الراوتر مرّةً لـtwodev، ولا شيء لـonedev');
    final h1 = await card(t, 'onedev');
    expect(find.byType(RouterChip), findsNothing);
    final h2 = await card(t, 'twodev');
    expect(find.byType(RouterChip), findsOneWidget);
    expect(find.descendant(of: find.byType(RouterChip), matching: find.text('6')), findsOneWidget);
    expect(find.descendant(of: find.byType(RouterChip), matching: find.text('100M')), findsOneWidget);
    expect(h2, h1, reason: 'الشريحة بارتفاع سطر الجلسة ⇒ الكرت بطوله');
    expect(t.takeException(), isNull);
    await simDrain(t);
  });

  testWidgets('هاتف 390: الشريحة تنزل مع سطر الجلسة ولا تُطيل الكرت ولا تفيض', (t) async {
    await t.runAsync(wave);
    final h1 = await card(t, 'onedev', width: 390);
    final h2 = await card(t, 'twodev', width: 390);
    expect(find.byType(RouterChip), findsOneWidget);
    expect(h2, h1);
    expect(t.takeException(), isNull);
    await simDrain(t);
  });

  testWidgets('الراوتر لا يردّ والنانو يردّ ⇒ «مطفي»؛ والنانو لا يردّ ⇒ لا يُسأل الراوتر ولا شريحة', (t) async {
    routerUp = false;
    await t.runAsync(wave);
    await card(t, 'twodev');
    expect(find.descendant(of: find.byType(RouterChip), matching: find.text('مطفي')), findsOneWidget);

    nanoUp = false;
    routerCalls = 0;
    await t.runAsync(wave);
    expect(routerCalls, 0, reason: 'لا حكم على الراوتر بلا النانو');
    await card(t, 'twodev');
    expect(find.byType(RouterChip), findsNothing);
    await simDrain(t);
  });
}
