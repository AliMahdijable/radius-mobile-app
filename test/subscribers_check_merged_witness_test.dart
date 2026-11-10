import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_check_screen.dart';
import 'package:rad_mysvcs/services/connection_alerts.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/subscribers_check.dart';
import 'package:rad_mysvcs/services/voice/voice_check.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';

import 'visual_perm/visual_perm_harness.dart';

/// المراجعة ١٠ نوفمبر (إصدار 180) — «كل الشركات»: موجة صفحة المشتركين تفحص صفوف كلّ الشركات من الهاتف، والهاتف على شبكة
/// المفتوحة لا يشهد على جهاز مشتركٍ في شركةٍ طريقها VPN شركتها. شركة VPN بلا نتيجةٍ حاليّة — قراءاتها انتهت (٣٠ د)، أو
/// الفحص الجاري لغيرها، أو أُلغي («وضع VPN» انطفأ) — كان متّصلوها «جهازه ما ردّ — ما ردّ من شبكتك». يكفيها 4c1aa5c1 +
/// 18efa4b4 (الشاشة تمرّر localFailsFor: المفتوحة على الشبكة وحدها)؛ هذه تحرس الحالات الثلاث.
Subscriber _s(String u, String company) =>
    Subscriber.fromJson({'username': u, 'firstname': u, 'lastname': '', 'online_status': 1, 'ip': '10.0.0.5'})
        .withCompany(company);

DeviceHealthSnapshot _nano() => const DeviceHealthSnapshot(
    kind: DeviceKind.ubiquiti,
    ip: '10.0.0.6',
    ubnt: UbiquitiStatus(
        hostname: 'Nano', firmware: 'XC.v8', uptimeSeconds: 1, ssid: 's', mode: 'sta', signalDbm: -52,
        noiseFloorDbm: -95, ccqPercent: 96, distanceMeters: 1, txRateKbps: 1, rxRateKbps: 1,
        lanPorts: [LanPort(name: 'eth0', speed: '100Mbps-Full', plugged: true)], peerMac: null, peerCount: 1,
        baseUrl: 'http://x'));

void main() {
  setUpAll(visualSetUpAll);

  const kS = 'c0000000000a1'; // المفتوحة — من شبكتك
  const kE = 'c0000000000e1'; // عبر VPN شركتها
  const kX = 'c0000000000b1';
  const limits = ConnectionAlertThresholds(signalDbm: -70, ccqPct: 60);

  test('mixed(): فشل الهاتف لمشترك شركةٍ ليست المفتوحة وبلا نتيجة VPN حاليّة ⇒ «لم يُفحص» لا «جهازه ما ردّ»', () {
    final now = DateTime.now();
    final subs = [_s('s.fail', kS), _s('e.fail', kE)];
    final r = SubscribersCheck.mixed(subs, (_) => limits,
        peek: (_) => (snap: null, stale: false, at: now), // موجة الهاتف سألت الاثنين وما ردّا
        reading: (_) => null,
        readAt: (_) => null, // قراءات ايرث لنك انتهت (٣٠ د) أو لم تُفحص
        companyNote: (_) => null, // نجحت آخر مرّة ⇒ بلا سبب
        vpnWaits: (_) => false,
        localFailsFor: (c) => c == kS); // كما تمرّره الشاشة على الشبكة
    expect(r.missingIn(SubsCheckCat.noReply).map((m) => m.sub.username), ['s.fail'],
        reason: 'المفتوحة: سُئل جهازه من شبكتها وما ردّ');
    expect(SubscribersCheck.missText(r.missingIn(SubsCheckCat.noReply).single), 'ما ردّ من شبكتك');
    expect(r.missingIn(SubsCheckCat.unchecked).map((m) => m.sub.username), ['e.fail']);
  });

  // المراجعة الثالثة: «كل الشركات» عبر الـVPN — قراءة هاتفٍ من ساعتين في الجلسة نفسها كانت تغلب فحص VPN شركته قبل
  // دقيقتين إن قال «لا يستجيب» أو ردّ بالبنك وحده: «سليم» بـ-52 dBm و96% بلا عمر. الأحدث يغلب — والأقدم منها لا، وجهازٌ
  // قرأه الخادم بلا أرقام ليس سبباً لإسقاط قراءةٍ حقيقيّة، والمفتوحة على شبكتك (الهاتف شاهدها) كما كانت.
  test('mixed(): نتيجة VPN شركته أحدث من قراءة الهاتف تغلب ولو «لا يستجيب» أو البنك وحده', () {
    final now = DateTime.now();
    final old = now.subtract(const Duration(hours: 2));
    final subs = [_s('e.dead', kE), _s('e.ping', kE), _s('e.cpe', kE), _s('e.after', kE), _s('s.dead', kS)];
    SubsCheckReport check(bool Function(String? c) local) => SubscribersCheck.mixed(subs, (_) => limits,
        peek: (s) => (
              snap: _nano(),
              stale: s.username != 'e.after' && s.username != 's.dead',
              at: switch (s.username) {
                'e.after' => now.subtract(const Duration(minutes: 1)), // بعد فحص الـVPN
                's.dead' => now.subtract(const Duration(minutes: 3)), // موجة المفتوحة
                _ => old,
              },
            ),
        reading: (s) => switch (s.username) {
              'e.ping' => const VpnSubReading(src: 'ping', ms: 7),
              'e.cpe' => const VpnSubReading(src: 'cpe'),
              _ => const VpnSubReading(src: 'dead'),
            },
        readAt: (_) => now.subtract(const Duration(minutes: 2)),
        companyNote: (_) => null,
        vpnWaits: (_) => false,
        localFailsFor: local);
    Map<String, String> cats(SubsCheckReport r) => {
          for (final x in r.healthy) x.sub.username: SubsCheckCat.healthy.label,
          for (final x in r.rows) x.sub.username: SubsCheckCat.problems.label,
          for (final m in r.missing)
            m.sub.username: '${SubscribersCheck.catOf(m.why).label} — ${SubscribersCheck.missText(m)}',
        };
    const dead = 'جهازه ما ردّ — لا يستجيب';
    // عبر الـVPN: الهاتف لا يشهد على أيّ شركة
    final viaVpn = check((_) => false);
    expect(cats(viaVpn), {
      'e.dead': dead,
      'e.ping': 'جهازه ما ردّ — يردّ، ما انقرت مقاييسه',
      'e.cpe': 'سليم',
      'e.after': 'سليم',
      's.dead': dead,
    });
    expect(viaVpn.oldest, old, reason: 'قراءة e.cpe وحدها من ساعتين داخلة');
    expect(
        SubscribersCheck.reportText(viaVpn,
            progress: SubscribersCheck.progress(subs: viaVpn.total, merged: true, at: now)),
        contains('• e.dead (e.dead) — لا يستجيب'));
    // على شبكة المفتوحة: قراءة هاتفها طريقها (الموجة تعيدها) — كما كانت
    expect(cats(check((c) => c == kS))['s.dead'], 'سليم');
    expect(cats(check((c) => c == kS))['e.dead'], dead);
  });

  group('الشاشة', () {
    Future<void> open(WidgetTester t) async {
      await visualSetUp(s1bSasOwner);
      MergedMode.reset();
      MergedMode.data.value = MergedCompaniesData.from({
        'routing': true,
        'writes': true,
        'companies': [
          {'key': kS, 'code': 'supernet', 'username': 'u0', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': '12',
            'ns': 'a', 'color_index': 0, 'home': true},
          {'key': kE, 'code': 'earthlink', 'username': 'u1', 'name': 'ايرث لنك', 'status': 'ok',
            'admin_id': 'earthlink:77', 'ns': 'e', 'color_index': 3},
        ],
      });
      MergedCompany co(String k) => MergedMode.companies.firstWhere((c) => c.key == k);
      final subs = [_s('s.ok', kS), _s('s.fail', kS), _s('e.fail', kE)];
      final now = DateTime.now();
      SubscribersCheck.debugPeek =
          (s) => (snap: s.username == 's.ok' ? _nano() : null, stale: false, at: now); // الهاتف سأل الكلّ
      addTearDown(() {
        SubscribersCheck.debugPeek = null;
        VpnNow.subscribers.reset();
        VpnNow.clearCompanyReadings();
        MergedMode.reset();
      });
      await pumpVisual(t, const VisualDevice('', Size(390, 1400), 3),
          home: (_) => SubscribersCheckScreen(
                subscribers: () => subs,
                viaVpn: false,
                companies: [co(kS), co(kE)],
                openCompany: kS,
              ));
      await settle(t, seconds: 1);
    }

    Finder inSeg(String seg, String text) =>
        find.descendant(of: find.byKey(ValueKey('subs-check-seg-$seg')), matching: find.text(text));
    Finder miss(String key, String u) => find.byKey(ValueKey('subs-check-miss-$key|$u'));

    Future<void> expectOnlyOpenNoReply(WidgetTester t) async {
      expect(inSeg('noReply', '1'), findsOneWidget, reason: 'المفتوحة وحدها — لا مشترك ايرث لنك');
      await t.tap(find.byKey(const ValueKey('subs-check-seg-noReply')));
      await settle(t, seconds: 1);
      expect(find.descendant(of: miss(kS, 's.fail'), matching: find.text('ما ردّ من شبكتك')), findsOneWidget);
      expect(miss(kE, 'e.fail'), findsNothing, reason: 'الهاتف على شبكة المفتوحة لا يشهد على جهازه');
      await t.tap(find.byKey(const ValueKey('subs-check-seg-unchecked')));
      await settle(t, seconds: 1);
      expect(miss(kE, 'e.fail'), findsOneWidget);
    }

    testWidgets('الفحص عبر الـVPN أُلغي في دور ايرث لنك («وضع VPN» انطفأ) ⇒ متّصلوها «لم يُفحص» لا «جهازه ما ردّ»',
        (t) async {
      VpnNow.subscribers
        ..phase = VpnBarPhase.running // يجري لايرث لنك ⇒ الفتح لا يبدأ آخر (لا شبكة في الاختبار)
        ..queue = [kE]
        ..current = kE;
      await open(t);
      expect(inSeg('noReply', '1'), findsOneWidget);
      VpnNow.subscribers.cancel(); // exitMode
      await settle(t, seconds: 1);
      await expectOnlyOpenNoReply(t);
      await t.pumpWidget(const SizedBox());
      await visualTearDown();
    });

    testWidgets('الفحص الجاري لغير ايرث لنك عند الفتح ⇒ متّصلوها «لم يُفحص» لا «جهازه ما ردّ»', (t) async {
      VpnNow.subscribers
        ..phase = VpnBarPhase.running
        ..queue = [kX]
        ..current = kX;
      await open(t);
      await expectOnlyOpenNoReply(t);
      await t.pumpWidget(const SizedBox());
      await visualTearDown();
    });

    // المراجعة الثانية: سببٌ واحد لـ«شركته لم تُفحص عبر VPN بعد» — كان صفّه «لم يصله الفحص» وجواب الأمر الصوتيّ «لم
    // يُفحص — لم يُفحص عبر VPN بعد» وبطاقة الشركات «لم تُفحص بعد عبر VPN»
    testWidgets('ايرث لنك لم يكتمل لها فحصٌ عبر VPN ⇒ صفّه وبطاقة الشركات وجواب الأمر الصوتيّ بالكلمات نفسها',
        (t) async {
      VpnNow.subscribers
        ..phase = VpnBarPhase.running
        ..queue = [kE]
        ..current = kE;
      await open(t);
      VpnNow.subscribers.cancel(); // «وضع VPN» انطفأ في دورها
      await settle(t, seconds: 1);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('subs-check-company-$kE')),
              matching: find.textContaining('لم تُفحص بعد عبر VPN')),
          findsOneWidget);
      await t.tap(find.byKey(const ValueKey('subs-check-seg-unchecked')));
      await settle(t, seconds: 1);
      expect(find.descendant(of: miss(kE, 'e.fail'), matching: find.text('لم يُفحص بعد عبر VPN')), findsOneWidget);
      // جواب «افحص المشترك e.fail» في اللحظة نفسها: الهاتف على شبكة سوبرنت سأله وما ردّ، ولا فحص عبر VPN شركته
      SubscriberVoiceCheck.debugLocalAllowed = () => true;
      SubscriberVoiceCheck.debugVpnAllowed = () => true;
      SubscriberVoiceCheck.debugIsOpen = (c) async => c.key == kS;
      SubscriberVoiceCheck.debugProbe = (_) async => null;
      SubscriberVoiceCheck.debugVpnRun = (s, c) async {};
      addTearDown(() {
        SubscriberVoiceCheck.debugLocalAllowed = null;
        SubscriberVoiceCheck.debugVpnAllowed = null;
        SubscriberVoiceCheck.debugIsOpen = null;
        SubscriberVoiceCheck.debugProbe = null;
        SubscriberVoiceCheck.debugVpnRun = null;
      });
      final e = MergedMode.companies.firstWhere((c) => c.key == kE);
      final voice = SubscriberVoiceCheck(_s('e.fail', kE), company: e);
      await voice.run();
      expect([voice.cat, voice.deviceLine], [SubsCheckCat.unchecked, 'لم يُفحص بعد عبر VPN']);
      voice.dispose();
      await t.pumpWidget(const SizedBox());
      await visualTearDown();
    });
  });
}
