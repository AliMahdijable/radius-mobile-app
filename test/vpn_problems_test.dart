// «المشاكل» من شريط «وضع VPN» تعرض المشتركين بمشاكلهم (٦ نوفمبر — المالك: «من انقر ع المشاكل المفروض يعرض المشاكل كبل يوديني للقسم
// وليس المشاكل»)، وكرت الجهاز بصفحة المشترك يعرض قراءة الـVPN بدل «غير واصل» («من افعل وضع vpn للمشتركين مفروض هنا هم يعرض القراءات»).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/device_probe_card.dart';
import 'package:rad_mysvcs/services/agent_net_presence.dart';
import 'package:rad_mysvcs/services/connection_alerts.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';
import 'package:rad_mysvcs/widgets/vpn_problems_sheet.dart';

import 'visual_perm/visual_perm_harness.dart';

void main() {
  setUpAll(visualSetUpAll);
  tearDown(() {
    VpnNow.reset();
    AgentNetPresence.reset();
  });

  VpnNowResult result() => VpnNowResult.fromJson({
        'ok': true,
        'message': 'فُحص عبر VPN ✓',
        'readings': [
          {'u': 'ali@popq', 'src': 'cpe', 'sig': -72, 'ccq': 88, 'lan': '10'},
          {'u': 'sara@popq', 'src': 'olt', 'rx': -28.4, 't': 46},
          {'u': 'ok@popq', 'src': 'cpe', 'sig': -55, 'ccq': 95, 'lan': 'ok'},
          {'u': 'dead@popq', 'src': 'dead'},
        ],
      });

  test('مشاكل القراءة بحدود الوكيل: الكيبل والإشارة وCCQ والضوئيّ والحرارة؛ السليم والبنگ والساقط بلا مشكلة', () {
    const t = ConnectionAlertThresholds();
    final r = result().readings;
    expect(vpnProblemsOf(r['ali@popq']!, t).length, 2, reason: 'الكيبل 10 ميكا + إشارة -72');
    expect(vpnProblemsOf(r['sara@popq']!, t).single, contains('ضوئي'));
    expect(vpnProblemsOf(r['ok@popq']!, t), isEmpty);
    expect(vpnProblemsOf(r['dead@popq']!, t), isEmpty);
  });

  testWidgets('«المشاكل» ⇒ قائمة المشتركين بمشاكلهم، والنقر يفتح المشترك؛ و«تنبيهات المشتركين» تحتها', (t) async {
    await visualSetUp(s1bSasOwner);
    VpnNow.debugApply(VpnNowKind.subscribers, result());
    final subs = [
      Subscriber.fromJson({'idx': 1, 'username': 'ali@popq', 'firstname': 'علي', 'lastname': 'حسن'}),
      Subscriber.fromJson({'idx': 2, 'username': 'sara@popq', 'firstname': 'سارة'}),
    ];
    Subscriber? opened;
    var section = 0;
    await pumpVisual(t, phone, home: (_) => Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => showVpnProblemsSheet(ctx, subscribers: subs, onOpen: (s) => opened = s, onSection: () => section++),
                child: const Text('افتح'),
              ),
            ),
          ),
        ));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.text('افتح'));
    await t.pumpAndSettle();
    expect(find.text('2 بمشكلة بآخر فحص'), findsOneWidget);
    expect(find.text('علي حسن'), findsOneWidget);
    expect(find.textContaining('الكيبل 10 ميكا'), findsOneWidget);
    expect(find.textContaining('ضوئي'), findsOneWidget);
    await t.tap(find.text('علي حسن'));
    await t.pumpAndSettle();
    expect(opened?.username, 'ali@popq');
    await t.tap(find.text('افتح'));
    await t.pumpAndSettle();
    await t.tap(find.text('تنبيهات المشتركين'));
    await t.pumpAndSettle();
    expect(section, 1);
    await visualTearDown();
  });

  testWidgets('كرت الجهاز بصفحة المشترك: «وضع VPN» ⇒ قراءة الـVPN (الإشارة وCCQ والكيبل) بعلامة VPN بدل «غير واصل»', (t) async {
    await visualSetUp(s1bSasOwner);
    AgentNetPresence.debugSet(NetPresence.off);
    VpnNow.debugApply(VpnNowKind.subscribers, result());
    await pumpVisual(t, phone, home: (_) => Scaffold(body: ListView(children: const [DeviceProbeCard(username: 'ali@popq', ip: '')])));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('device-card-vpn')), findsOneWidget);
    expect(find.text('-72 dBm'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);
    expect(find.text('10M'), findsOneWidget);
    expect(find.text('الجهاز غير واصل'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 20));
    await visualTearDown();
  });
}
