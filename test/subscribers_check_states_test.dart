import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_check_screen.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/subscribers_check.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «الفحص العامّ» — حالاته بلا أرقامٍ ولا علاماتٍ كاذبة (مراجعة الإصدار 180، مجموعة الشاشة): القسم الفارغ يقول ما يعنيه
/// وحده، والفحص المنتهي لا يُقال «يُفحص الآن»، وعمر المعروض ظاهرٌ ما لم يقله الشريط.
Subscriber _s(String u, {bool online = true, String? ip}) => Subscriber.fromJson({
      'username': u,
      'firstname': u,
      'lastname': '',
      'online_status': online ? 1 : 0,
      if (ip != null) 'ip': ip,
    });

UbiquitiStatus _nano(int sig, int ccq) => UbiquitiStatus(
    hostname: 'Nano', firmware: 'XC.v8', uptimeSeconds: 1, ssid: 's', mode: 'sta', signalDbm: sig, noiseFloorDbm: -95,
    ccqPercent: ccq, distanceMeters: 1, txRateKbps: 1, rxRateKbps: 1,
    lanPorts: const [LanPort(name: 'eth0', speed: '100Mbps-Full', plugged: true)], peerMac: null, peerCount: 1,
    baseUrl: 'http://x');

typedef _Peek = ({DeviceHealthSnapshot? snap, bool stale, DateTime at});

_Peek _read(DateTime at, {int sig = -50}) =>
    (snap: DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '1', ubnt: _nano(sig, 95)), stale: false, at: at);

Finder _inSeg(String seg, String text) =>
    find.descendant(of: find.byKey(ValueKey('subs-check-seg-$seg')), matching: find.text(text));

const _phone = VisualDevice('', Size(390, 844), 3);

Future<void> _tapSeg(WidgetTester t, String seg) async {
  await t.tap(find.byKey(ValueKey('subs-check-seg-$seg')));
  await settle(t, seconds: 1);
}

Future<void> _done(WidgetTester t) async {
  expect(t.takeException(), isNull);
  await t.pumpWidget(const SizedBox());
  await visualTearDown();
}

/// ثلاث شركات كاختبار «كل الشركات» في subscribers_check_screen_test.
const _kS = 'c0000000000a1', _kE = 'c0000000000e1';

void _mergedTwo() {
  MergedMode.reset();
  MergedMode.data.value = MergedCompaniesData.from({
    'routing': true,
    'writes': true,
    'companies': [
      {'key': _kS, 'code': 'supernet', 'username': 'u0', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': '12', 'ns': 'a',
        'color_index': 0, 'home': true},
      {'key': _kE, 'code': 'earthlink', 'username': 'u1', 'name': 'ايرث لنك', 'status': 'ok',
        'admin_id': 'earthlink:77', 'ns': 'e', 'color_index': 3},
    ],
  });
}

MergedCompany _co(String k) => MergedMode.companies.firstWhere((c) => c.key == k);

void main() {
  setUpAll(visualSetUpAll);

  // ───────────── F4 + F13: «جهازه ما ردّ» فارغاً لا يدّعي أنّ كلّ متّصلٍ قُرئ ─────────────

  group('F4/F13 — القسم الفارغ يقول ما يعنيه وحده', () {
    testWidgets('🚨 فحص VPN تعذّر بلا قراءات: «جهازه ما ردّ 0» ⇒ لا ✓ «كلّ المتّصلين قُرئت أجهزتهم» — بل كم لم يُفحص',
        (t) async {
      await visualSetUp(s1bSasOwner);
      final subs = [_s('a.u'), _s('b.u'), _s('off.u', online: false)];
      final job = VpnNow.subscribers;
      addTearDown(() {
        job.reset();
        VpnNow.reset();
      });
      // الفتح بلا قراءات يبدأ فحص الخادم — والخادم الوهميّ لا يعطي رقم فحص ⇒ يتعذّر (كنفقٍ لم يتّصل)
      await pumpVisual(t, _phone, home: (_) => SubscribersCheckScreen(subscribers: () => subs, viaVpn: true));
      await settle(t, seconds: 1);
      expect(job.phase, VpnBarPhase.failed);
      expect(_inSeg('noReply', '0'), findsOneWidget);
      expect(_inSeg('unchecked', '2'), findsOneWidget);

      await _tapSeg(t, 'noReply');
      expect(find.textContaining('قُرئت أجهزتهم'), findsNothing, reason: 'لم يُقرأ أحد');
      expect(find.textContaining('✓'), findsNothing);
      expect(find.text('لا أحد جهازه ما ردّ\nمتّصلون بلا قراءة: «لم يُفحص» 2'), findsOneWidget);
      await _done(t);
    });

    testWidgets('«كل الشركات»: شركةٌ تحتاج VPN ⇒ «جهازه ما ردّ» فارغٌ بلا ✓، ومن شبكتك والكلّ مقروء ⇒ ✓ صادقة',
        (t) async {
      await visualSetUp(s1bSasOwner);
      _mergedTwo();
      final subs = [_s('s.ok').withCompany(_kS), _s('e.one').withCompany(_kE), _s('e.two').withCompany(_kE)];
      final now = DateTime.now();
      SubscribersCheck.debugPeek = (s) => s.username == 's.ok' ? _read(now) : null;
      VpnNow.debugNote(_kE, '«ايرث لنك» تحتاج VPN');
      VpnNow.subscribers.phase = VpnBarPhase.running; // الفتح لا يبدأ فحصاً (لا شبكة)
      addTearDown(() {
        SubscribersCheck.debugPeek = null;
        VpnNow.debugNote(_kE, null);
        VpnNow.subscribers.reset();
        VpnNow.clearCompanyReadings();
        MergedMode.reset();
      });
      await pumpVisual(t, const VisualDevice('', Size(390, 1200), 3),
          home: (_) => SubscribersCheckScreen(
              subscribers: () => subs, viaVpn: false, companies: [_co(_kS), _co(_kE)], openCompany: _kS));
      await settle(t, seconds: 1);
      VpnNow.subscribers.reset();
      await settle(t, seconds: 1);

      await t.tap(find.byKey(const ValueKey('subs-check-company-$_kE')));
      await settle(t, seconds: 1);
      await _tapSeg(t, 'noReply');
      expect(find.textContaining('✓'), findsNothing, reason: 'مشتركو ايرث لنك لم يُفحصوا — شركتهم تحتاج VPN');
      expect(find.text('لا أحد جهازه ما ردّ\nمتّصلون بلا قراءة: «لم يُفحص» 2'), findsOneWidget);

      // سوبرنت: كلّ متّصليها قُرئوا ⇒ ✓ صادقة
      await t.tap(find.byKey(const ValueKey('subs-check-company-$_kS')));
      await settle(t, seconds: 1);
      expect(find.text('كلّ المتّصلين قُرئت أجهزتهم ✓'), findsOneWidget);
      await _done(t);
    });

    testWidgets('من الهاتف: بلا مقاييس وبلا عنوان ⇒ يُعدّان؛ وغير متّصلٍ بقراءةٍ سابقة ⇒ لا «الكلّ متّصل الآن ✓»',
        (t) async {
      await visualSetUp(s1bSasOwner);
      _mergedTwo();
      final at = DateTime.now().subtract(const Duration(minutes: 2));
      final subs = [
        _s('s.ok', ip: '1').withCompany(_kS),
        _s('s.router', ip: '2').withCompany(_kS),
        _s('s.noip').withCompany(_kS),
        _s('s.off', online: false).withCompany(_kS),
        _s('e.ok', ip: '3').withCompany(_kE),
        _s('e.off.read', online: false, ip: '4').withCompany(_kE),
      ];
      final peeks = <String, _Peek>{
        's.ok': _read(at),
        's.router': (snap: const DeviceHealthSnapshot(kind: DeviceKind.other, ip: '2'), stale: false, at: at),
        'e.ok': _read(at),
        // انطفأ بعد أن قُرئ جهازه — قراءته السابقة تُعدّ بقسمها
        'e.off.read': _read(at),
      };
      SubscribersCheck.debugPeek = (s) => peeks[s.username];
      final wave = ValueNotifier(SubsWave(endedAt: at));
      VpnNow.subscribers.phase = VpnBarPhase.running;
      addTearDown(() {
        SubscribersCheck.debugPeek = null;
        wave.dispose();
        VpnNow.subscribers.reset();
        VpnNow.clearCompanyReadings();
        MergedMode.reset();
      });
      await pumpVisual(t, const VisualDevice('', Size(390, 1200), 3),
          home: (_) => SubscribersCheckScreen(
              subscribers: () => subs,
              viaVpn: false,
              wave: wave,
              vpnAllowed: false,
              companies: [_co(_kS), _co(_kE)],
              openCompany: _kS));
      await settle(t, seconds: 1);
      VpnNow.subscribers.reset();
      await settle(t, seconds: 1);

      await t.tap(find.byKey(const ValueKey('subs-check-company-$_kS')));
      await settle(t, seconds: 1);
      await _tapSeg(t, 'noReply');
      expect(find.textContaining('قُرئت أجهزتهم'), findsNothing, reason: 's.router بلا مقاييس وs.noip بلا عنوان');
      expect(find.text('لا أحد جهازه ما ردّ\nمتّصلون بلا قراءة: «لم يُفحص» 1 · «بلا مقاييس» 1'), findsOneWidget);

      // غير متّصل الآن: s.off (بلا قراءة) — ثمّ ايرث لنك وحدها: e.off.read غير متّصل وقراءته السابقة في «سليم»
      await _tapSeg(t, 'offline');
      expect(find.byKey(const ValueKey('subs-check-miss-$_kS|s.off')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('subs-check-company-$_kE')));
      await settle(t, seconds: 1);
      expect(find.text('الكلّ متّصل الآن ✓'), findsNothing, reason: 'e.off.read غير متّصل');
      // قسمه بقراءته السابقة «سليم» (أو «غير متّصل الآن» إن صُنّف فيه) — والفراغ لا يقول «الكلّ متّصل»
      if (find.byKey(const ValueKey('subs-check-miss-$_kE|e.off.read')).evaluate().isEmpty) {
        expect(find.text('لا أحد هنا — 1 غير متّصل الآن بقراءةٍ سابقة في «سليم» أو «بمشكلة»'), findsOneWidget);
      }
      await _done(t);
    });
  });
}
