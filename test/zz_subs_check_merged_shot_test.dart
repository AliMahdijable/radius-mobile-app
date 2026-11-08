import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/vpn_now_api.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_check_screen.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/subscribers_check.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';

import 'visual_perm/visual_perm_harness.dart';

/// صفحة «الفحص العامّ» للمشتركين (٨ نوفمبر — المالك مع صورتها: «يحتاجلها ترتيب اكثر واظهار معلومات ال ccq كذلك وتصميم افضل»):
///   ١. ملخّصٌ بثلاثة أقسام (بمشكلة · سليم · لم يُقرأ) بأعدادها، وكم قُرئ من كم.
///   ٢. كلّ مشتركٍ بمقاييسه كلّها — CCQ ظاهرٌ ولو لم يكن هو المشكلة — والمجموعات بنوع المشكلة.
///   ٣. «سليم» الأقرب للحدّ أوّلاً، و«لم يُقرأ» بسببه.
///   ٤. شريحة النوع تحصر القائمة فيه.
///   ٥. «كل الشركات»: كلّ شركةٍ بطريقها (المفتوحة من شبكتك، وغيرها عبر VPN شركتها، وبلا طريقٍ تُسمّى) — بطاقة «الشركات» بعدد
///      المقروء والمشاكل لكلٍّ، والضغط على شركةٍ يعرض مشتركيها وحدهم (المالك: «مايعرض مثل الاجهزه مشتركين كل شركه ونتيجه فحوصاتهم»).
Subscriber _s(String u, String f, {bool online = true}) =>
    Subscriber.fromJson({'username': u, 'firstname': f, 'lastname': '', 'online_status': online ? 1 : 0});

void main() {
  setUpAll(visualSetUpAll);

  testWidgets('٥ «كل الشركات»: كلّ شركةٍ بطريقها وبطاقة «الشركات» والضغط على شركة', (t) async {
    final inner = await visualSetUp(s1bSasOwner);
    const kS = 'c0000000000a1', kE = 'c0000000000e1', kX = 'c0000000000b1';
    MergedMode.reset();
    MergedMode.data.value = MergedCompaniesData.from({
      'routing': true,
      'writes': true,
      'companies': [
        {'key': kS, 'code': 'supernet', 'username': 'u0', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': '12', 'ns': 'a', 'color_index': 0, 'home': true},
        {'key': kE, 'code': 'earthlink', 'username': 'u1', 'name': 'ايرث لنك', 'status': 'ok', 'admin_id': 'earthlink:77', 'ns': 'e', 'color_index': 3},
        {'key': kX, 'code': 'jt', 'username': 'u2', 'name': 'الجزيرة', 'status': 'ok', 'admin_id': 'jt:22', 'ns': 'j', 'color_index': 1},
      ],
    });
    MergedCompany co(String k) => MergedMode.companies.firstWhere((c) => c.key == k);
    Subscriber sub(String u, String k) => _s(u, u).withCompany(k);
    final subs = [sub('s.bad', kS), sub('s.ok', kS), sub('e.bad', kE), sub('e.ok', kE), sub('e.none', kE), sub('x.one', kX)];
    UbiquitiStatus ubnt(int sig) => UbiquitiStatus(
        hostname: 'h', firmware: 'XC.v8', uptimeSeconds: 1, ssid: 's', mode: 'sta', signalDbm: sig, noiseFloorDbm: -95,
        ccqPercent: 95, distanceMeters: 1, txRateKbps: 1, rxRateKbps: 1, lanPorts: const [], peerMac: null, peerCount: 1,
        baseUrl: 'http://x');
    final snaps = {
      's.bad': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '1', ubnt: ubnt(-80)),
      's.ok': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '2', ubnt: ubnt(-50)),
    };
    SubscribersCheck.debugPeek =
        (s) => snaps[s.username] == null ? null : (snap: snaps[s.username], stale: false, at: DateTime.now());
    VpnNow.debugApplyCompany(kE, const VpnNowResult(ok: true, message: 'تم', readings: {
      'e.bad': VpnSubReading(src: 'cpe', sig: -55, ccq: 30, lan: '100'),
      'e.ok': VpnSubReading(src: 'cpe', sig: -52, ccq: 96, lan: '100'),
    }));
    VpnNow.debugNote(kX, '«الجزيرة» تحتاج VPN');
    // فحصٌ جارٍ ⇒ الفتح لا يبدأ آخر (لا شبكة في الاختبار)
    VpnNow.subscribers.phase = VpnBarPhase.running;
    addTearDown(() {
      SubscribersCheck.debugPeek = null;
      VpnNow.debugNote(kX, null);
      VpnNow.subscribers.reset();
      VpnNow.clearCompanyReadings();
      MergedMode.reset();
    });

    const d = VisualDevice('_dark', Size(390, 1300), 3, dark: true);
    await pumpVisual(t, d,
        home: (_) => SubscribersCheckScreen(
              subscribers: () => subs,
              viaVpn: false,
              companies: [co(kS), co(kE), co(kX)],
              openCompany: kS,
            ));
    await settle(t, seconds: 1);

    await shoot(t, s1bSasOwner, 'subs_check_merged', d, inner);
    await t.tap(find.byKey(const ValueKey('subs-check-company-c0000000000e1')));
    await settle(t, seconds: 1);
    await shoot(t, s1bSasOwner, 'subs_check_merged_pick', d, inner);
    await t.pumpWidget(const SizedBox());
    await visualTearDown();
  });
}
