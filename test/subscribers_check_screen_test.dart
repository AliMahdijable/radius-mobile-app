import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_check_screen.dart';
import 'package:rad_mysvcs/services/connection_alerts.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/subscribers_check.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';

import 'visual_perm/visual_perm_harness.dart';

/// صفحة «الفحص العامّ» للمشتركين (٨ نوفمبر — المالك مع صورتها: «يحتاجلها ترتيب اكثر واظهار معلومات ال ccq كذلك وتصميم افضل»):
///   ١. ملخّصٌ بأقسامه بأعدادها — ١٠ نوفمبر (المالك مع صورة «قُرئ 58 من 113»: «مفروض العداد يمثل الفحص»): بمشكلة · سليم ·
///      جهازه ما ردّ، وتحتها غير متّصل الآن · بلا مقاييس · لم يُفحص؛ والشريط شريط الفحص («يفحص… x من y» ثمّ «انتهى الفحص»).
///   ٢. كلّ مشتركٍ بمقاييسه كلّها — CCQ ظاهرٌ ولو لم يكن هو المشكلة — والمجموعات بنوع المشكلة.
///   ٣. «سليم» الأقرب للحدّ أوّلاً، و«لم يُقرأ» بسببه.
///   ٤. شريحة النوع تحصر القائمة فيه.
///   ٥. «كل الشركات»: كلّ شركةٍ بطريقها (المفتوحة من شبكتك، وغيرها عبر VPN شركتها، وبلا طريقٍ تُسمّى) — بطاقة «الشركات» بعدد
///      المقروء والمشاكل لكلٍّ، والضغط على شركةٍ يعرض مشتركيها وحدهم (المالك: «مايعرض مثل الاجهزه مشتركين كل شركه ونتيجه فحوصاتهم»).
Subscriber _s(String u, String f, {bool online = true}) =>
    Subscriber.fromJson({'username': u, 'firstname': f, 'lastname': '', 'online_status': online ? 1 : 0});

UbiquitiStatus _nano(int sig, int ccq) => UbiquitiStatus(
    hostname: 'Nano', firmware: 'XC.v8', uptimeSeconds: 1, ssid: 's', mode: 'sta', signalDbm: sig, noiseFloorDbm: -95,
    ccqPercent: ccq, distanceMeters: 1, txRateKbps: 1, rxRateKbps: 1,
    lanPorts: const [LanPort(name: 'eth0', speed: '100Mbps-Full', plugged: true)], peerMac: null, peerCount: 1,
    baseUrl: 'http://x');

typedef _Peek = ({DeviceHealthSnapshot? snap, bool stale, DateTime at});

Finder _inSeg(String seg, String text) =>
    find.descendant(of: find.byKey(ValueKey('subs-check-seg-$seg')), matching: find.text(text));

String _progressText(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('subs-check-progress-text'))).data!;

double? _barValue(WidgetTester t) =>
    t.widget<LinearProgressIndicator>(find.byKey(const ValueKey('subs-check-progress-bar'))).value;

void main() {
  setUpAll(visualSetUpAll);

  testWidgets('الأقسام الثلاثة والمقاييس كاملةً', (t) async {
    await visualSetUp(s1bSasOwner);
    final subs = [
      _s('cable.u', 'كيبل'), _s('weak.u', 'ضعيف'), _s('ccq.u', 'سي سي كيو'), _s('ok.near', 'قريب'),
      _s('ok.far', 'بعيد'), _s('dead.u', 'ميّت'), _s('off.u', 'مطفأ', online: false), _s('none.u', 'بلا'),
    ];
    VpnNow.debugApply(VpnNowKind.subscribers, VpnNowResult(ok: true, message: 'تم', atMs: DateTime.now().millisecondsSinceEpoch, readings: {
      'cable.u': const VpnSubReading(src: 'cpe', sig: -58, ccq: 61, lan: 'unplugged'),
      'weak.u': const VpnSubReading(src: 'cpe', sig: -72, ccq: 88, lan: '100'),
      'ccq.u': const VpnSubReading(src: 'cpe', sig: -55, ccq: 42, lan: '100'),
      'ok.near': const VpnSubReading(src: 'cpe', sig: -57, ccq: 97, lan: '100'),
      'ok.far': const VpnSubReading(src: 'cpe', sig: -45, ccq: 99, lan: '1000'),
      'dead.u': const VpnSubReading(src: 'dead'),
    }));
    const d = VisualDevice('', Size(390, 844), 3);
    await pumpVisual(t, d, home: (_) => SubscribersCheckScreen(subscribers: () => subs, viaVpn: true));
    await settle(t, seconds: 1);

    Finder inSeg(String seg, String text) =>
        find.descendant(of: find.byKey(ValueKey('subs-check-seg-$seg')), matching: find.text(text));
    expect(inSeg('problems', '3'), findsOneWidget);
    expect(inSeg('healthy', '2'), findsOneWidget);
    // ١٠ نوفمبر: كان «لم يُقرأ 3» يخلط الميّت وغير المتّصل ومن لا قراءة له — والشريط «قُرئ 5 من 8»
    expect(inSeg('noReply', '1'), findsOneWidget, reason: 'الميّت وحده — لا غير المتّصل');
    // ١٠ نوفمبر (المحاكي): فحصٌ مكتمل بلا قراءةٍ له = الخادم لم يسأل جهازه ⇒ «لم يُفحص» لا «ما ردّ»
    expect(inSeg('unchecked', '1'), findsOneWidget, reason: 'none.u: فُحصت شركته ولم يُسأل جهازه');
    expect(inSeg('offline', '1'), findsOneWidget);
    expect(find.text('قُرئ 5 من 8'), findsNothing);
    expect(find.text('انتهى الفحص — 8 مشترك'), findsOneWidget);
    expect(t.widget<LinearProgressIndicator>(find.byKey(const ValueKey('subs-check-progress-bar'))).value, 1.0);

    // ٢ CCQ ظاهرٌ في صفّ مشكلته الكيبل (61% ليست مشكلة بالحدّ 50)
    final cableRow = find.byKey(const ValueKey('subs-check-row-|cable.u'));
    expect(find.descendant(of: cableRow, matching: find.text('61%')), findsOneWidget);
    expect(find.descendant(of: cableRow, matching: find.text('مفصول')), findsOneWidget);
    expect(find.descendant(of: cableRow, matching: find.text('-58 dBm')), findsOneWidget);
    expect(find.text('الكيبل مفصول أو 10 ميكا'), findsOneWidget);
    expect(find.text('إشارة ضعيفة'), findsOneWidget);
    expect(find.text('CCQ منخفض'), findsOneWidget);

    // ٤ شريحة CCQ
    await t.tap(find.byKey(const ValueKey('subs-check-kind-ccq')));
    await settle(t, seconds: 1);
    expect(find.byKey(const ValueKey('subs-check-row-|ccq.u')), findsOneWidget);
    expect(find.byKey(const ValueKey('subs-check-row-|weak.u')), findsNothing);

    // ٣ سليم: الأقرب أوّلاً
    await t.tap(find.byKey(const ValueKey('subs-check-seg-healthy')));
    await settle(t, seconds: 1);
    final near = t.getTopLeft(find.byKey(const ValueKey('subs-check-row-|ok.near'))).dy;
    final far = t.getTopLeft(find.byKey(const ValueKey('subs-check-row-|ok.far'))).dy;
    expect(near, lessThan(far), reason: '‎-57 أقرب لحدّ ‎-60 من ‎-45');
    expect(find.byKey(const ValueKey('subs-check-row-|cable.u')), findsNothing);
    expect(find.text('1G'), findsOneWidget);

    // ٣ جهازه ما ردّ: بسببه — وغير المتّصل ليس فيه
    await t.tap(find.byKey(const ValueKey('subs-check-seg-noReply')));
    await settle(t, seconds: 1);
    expect(find.descendant(of: find.byKey(const ValueKey('subs-check-miss-|dead.u')), matching: find.text('لا يستجيب')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('subs-check-miss-|none.u')), findsNothing, reason: 'لم يُسأل جهازه — ليس «ما ردّ»');
    expect(find.byKey(const ValueKey('subs-check-miss-|off.u')), findsNothing);
    await t.tap(find.byKey(const ValueKey('subs-check-seg-unchecked')));
    await settle(t, seconds: 1);
    expect(
        find.descendant(of: find.byKey(const ValueKey('subs-check-miss-|none.u')), matching: find.text('لم يُقرأ عبر VPN')),
        findsOneWidget);
    // غير متّصل الآن: قسمه وحده
    await t.tap(find.byKey(const ValueKey('subs-check-seg-offline')));
    await settle(t, seconds: 1);
    expect(find.descendant(of: find.byKey(const ValueKey('subs-check-miss-|off.u')), matching: find.text('غير متّصل')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('subs-check-miss-|dead.u')), findsNothing);

    await t.pumpWidget(const SizedBox());
    await visualTearDown();
  });
  testWidgets('٥ «كل الشركات»: كلّ شركةٍ بطريقها وبطاقة «الشركات» والضغط على شركة', (t) async {
    await visualSetUp(s1bSasOwner);
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
    final subs = [
      sub('s.bad', kS), sub('s.ok', kS), sub('e.bad', kE), sub('e.ok', kE), sub('e.none', kE), sub('x.one', kX),
      sub('x.near', kX), // الجزيرة بلا VPN لكنّ جهاز هذا يصله موبايلك (شبكته)
    ];
    UbiquitiStatus ubnt(int sig) => UbiquitiStatus(
        hostname: 'h', firmware: 'XC.v8', uptimeSeconds: 1, ssid: 's', mode: 'sta', signalDbm: sig, noiseFloorDbm: -95,
        ccqPercent: 95, distanceMeters: 1, txRateKbps: 1, rxRateKbps: 1, lanPorts: const [], peerMac: null, peerCount: 1,
        baseUrl: 'http://x');
    final snaps = {
      's.bad': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '1', ubnt: ubnt(-80)),
      's.ok': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '2', ubnt: ubnt(-50)),
      'x.near': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '3', ubnt: ubnt(-48)),
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

    const d = VisualDevice('', Size(390, 1400), 3);
    await pumpVisual(t, d,
        home: (_) => SubscribersCheckScreen(
              subscribers: () => subs,
              viaVpn: false,
              companies: [co(kS), co(kE), co(kX)],
              openCompany: kS,
            ));
    await settle(t, seconds: 1);

    Finder company(String k) => find.byKey(ValueKey('subs-check-company-$k'));
    expect(find.byKey(const ValueKey('subs-check-companies')), findsOneWidget);
    expect(find.descendant(of: company(kS), matching: find.textContaining('من شبكتك')), findsOneWidget);
    expect(find.descendant(of: company(kS), matching: find.textContaining('قُرئ 2 من 2')), findsOneWidget);
    expect(find.descendant(of: company(kE), matching: find.textContaining('عبر VPN الشركة')), findsOneWidget);
    expect(find.descendant(of: company(kE), matching: find.textContaining('قُرئ 2 من 3')), findsOneWidget);
    expect(find.descendant(of: company(kE), matching: find.text('1 بمشكلة')), findsOneWidget);
    // الجزيرة بلا VPN: من وصله موبايلك قُرئ «من شبكتك»، والباقي يُقال
    expect(find.descendant(of: company(kX), matching: find.text('من شبكتك · قُرئ 1 من 2 · بلا VPN للباقي')), findsOneWidget);
    // المشاكل من الطريقين معاً
    expect(find.byKey(const ValueKey('subs-check-row-$kS|s.bad')), findsOneWidget);
    expect(find.byKey(const ValueKey('subs-check-row-$kE|e.bad')), findsOneWidget);

    // الضغط على ايرث لنك ⇒ مشتركوها وحدهم
    await t.tap(company(kE));
    await settle(t, seconds: 1);
    expect(find.byKey(const ValueKey('subs-check-row-$kS|s.bad')), findsNothing);
    expect(find.byKey(const ValueKey('subs-check-row-$kE|e.bad')), findsOneWidget);
    expect(find.text('«ايرث لنك» وحدها — اضغطها ثانيةً لعرض الكلّ'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('subs-check-seg-problems')), matching: find.text('1')), findsOneWidget);

    // من لم يُقرأ: الجزيرة بسببها تحت «لم يُفحص»، وe.none (فُحصت شركته ولم يُسأل جهازه) تحته أيضاً بسببه — لا «ما ردّ» (١٠ نوفمبر)
    await t.tap(company(kE));
    await settle(t, seconds: 1);
    await t.tap(find.byKey(const ValueKey('subs-check-seg-unchecked')));
    await settle(t, seconds: 1);
    expect(find.descendant(of: find.byKey(const ValueKey('subs-check-miss-$kX|x.one')), matching: find.text('شركته تحتاج VPN')),
        findsOneWidget);
    expect(
        find.descendant(of: find.byKey(const ValueKey('subs-check-miss-$kE|e.none')), matching: find.text('لم يُقرأ عبر VPN')),
        findsOneWidget);
    await t.tap(find.byKey(const ValueKey('subs-check-seg-noReply')));
    await settle(t, seconds: 1);
    expect(find.byKey(const ValueKey('subs-check-miss-$kE|e.none')), findsNothing);

    await t.pumpWidget(const SizedBox());
    await visualTearDown();
  });
  testWidgets('٩ نوفمبر: يردّ عبر الـVPN بلا مقاييس ⇒ «جهازه ما ردّ» بسببه لا «سليم» — على ٣٢٠ بلا فيضان، فاتحاً وداكناً', (t) async {
    for (final dark in [false, true]) {
      await visualSetUp(s1bSasOwner);
      final subs = [_s('ok.u', 'سليم'), _s('ping.u', 'بنك وحده باسمٍ طويلٍ جدّاً للتجربة'), _s('auth.u', 'رمزه غلط')];
      VpnNow.debugApply(VpnNowKind.subscribers, VpnNowResult(ok: true, message: 'تم', atMs: DateTime.now().millisecondsSinceEpoch, readings: {
        'ok.u': const VpnSubReading(src: 'cpe', sig: -55, ccq: 95, lan: '100'),
        'ping.u': const VpnSubReading(src: 'ping', ms: 14),
        'auth.u': const VpnSubReading(src: 'ping', ms: 9, err: 'login_failed'),
      }));
      await pumpVisual(t, VisualDevice('', const Size(320, 700), 3, dark: dark),
          home: (_) => SubscribersCheckScreen(subscribers: () => subs, viaVpn: true));
      await settle(t, seconds: 1);
      Finder inSeg(String seg, String text) =>
          find.descendant(of: find.byKey(ValueKey('subs-check-seg-$seg')), matching: find.text(text));
      expect(inSeg('healthy', '1'), findsOneWidget, reason: 'المقروء بمقاييسه وحده');
      expect(inSeg('noReply', '2'), findsOneWidget);
      expect(find.text('انتهى الفحص — 3 مشترك'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('subs-check-seg-noReply')));
      await settle(t, seconds: 1);
      expect(
          find.descendant(of: find.byKey(const ValueKey('subs-check-miss-|ping.u')), matching: find.text('يردّ، ما انقرت مقاييسه')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('subs-check-miss-|auth.u')), matching: find.text('يردّ، ما انفتح برمزه المحفوظ')),
          findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await visualTearDown();
    }
  });

  // ───────────── ١٠ نوفمبر: الشريط يعدّ الفحص، والأقسام بمعناها ─────────────
  // المالك مع صورة «قُرئ 58 من 113» (51%) و«لم يُقرأ 55»: «شنو علاقة العداد بالعدد مفروض العداد يمثل الفحص هيج راح يبرك الوكيل».

  testWidgets('١٠ نوفمبر · من الهاتف: «يفحص… 12 من 30» بتقدّم الموجة، ومن لم يبلغه دوره «لم يُفحص بعد» — ثمّ «انتهى الفحص» ممتلئاً',
      (t) async {
    await visualSetUp(s1bSasOwner);
    final started = DateTime.now().subtract(const Duration(seconds: 5));
    final subs = [_s('ok.u', 'سليم'), _s('wait.u', 'بالدور'), _s('dead.u', 'ما ردّ'), _s('off.u', 'مطفأ', online: false)];
    final peeks = <String, _Peek>{
      'ok.u': (snap: DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '1', ubnt: _nano(-50, 95)), stale: false, at: started),
      'dead.u': (snap: null, stale: false, at: DateTime.now()),
    };
    SubscribersCheck.debugPeek = (s) => peeks[s.username];
    addTearDown(() => SubscribersCheck.debugPeek = null);
    final wave = ValueNotifier(SubsWave.idle
        .start([for (final u in ['wait.u', 'dead.u', 'off.u']) SubsWave.keyOf(null, u)], started)
        .progress(12, 30));
    addTearDown(wave.dispose);
    await pumpVisual(t, const VisualDevice('', Size(390, 844), 3),
        home: (_) => SubscribersCheckScreen(subscribers: () => subs, viaVpn: false, wave: wave, onForceAll: () {}));
    await settle(t, seconds: 1);

    expect(_progressText(t), 'يفحص… 12 من 30');
    expect(_barValue(t), 0.4);
    expect(find.text('40%'), findsOneWidget);
    expect(_inSeg('noReply', '1'), findsOneWidget, reason: 'dead.u وحده — wait.u لم يُسأل جهازه بعد');
    expect(_inSeg('unchecked', '1'), findsOneWidget);
    expect(_inSeg('unchecked', 'لم يُفحص بعد'), findsOneWidget);
    expect(_inSeg('offline', '1'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('subs-check-seg-unchecked')));
    await settle(t, seconds: 1);
    expect(find.descendant(of: find.byKey(const ValueKey('subs-check-miss-|wait.u')), matching: find.text('بانتظار الفحص')),
        findsOneWidget);

    // انتهت الموجة وما ردّ wait.u ⇒ «جهازه ما ردّ»؛ والشريط ممتلئ لا عالقٌ عند نسبة
    peeks['wait.u'] = (snap: null, stale: false, at: DateTime.now());
    wave.value = wave.value.progress(30, 30).finish(DateTime.now());
    await settle(t, seconds: 1);
    expect(_progressText(t), 'انتهى الفحص — 4 مشترك');
    expect(_barValue(t), 1.0);
    expect(find.descendant(of: find.byKey(const ValueKey('subs-check-progress')), matching: find.text('الآن')), findsOneWidget);
    expect(_inSeg('noReply', '2'), findsOneWidget);
    expect(find.byKey(const ValueKey('subs-check-seg-unchecked')), findsOneWidget, reason: 'المختار يبقى ظاهراً ولو صفراً');
    expect(_inSeg('unchecked', 'لم يُفحص'), findsOneWidget);
    expect(find.text('وصل الفحص الجميع ✓'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await visualTearDown();
  });

  testWidgets('١٠ نوفمبر · عبر الـVPN: «يفحص… 120 من 310»، ومراحل الخادم بكلماتها، ثمّ «انتهى الفحص» — أو سبب التعذّر بلا شريط',
      (t) async {
    await visualSetUp(s1bSasOwner);
    final subs = [_s('a.u', 'أ'), _s('b.u', 'ب'), _s('off.u', 'مطفأ', online: false)];
    final job = VpnNow.subscribers;
    addTearDown(() {
      job.reset();
      VpnNow.reset();
    });
    job
      ..phase = VpnBarPhase.running
      ..done = 120
      ..total = 310;
    await pumpVisual(t, const VisualDevice('', Size(390, 844), 3),
        home: (_) => SubscribersCheckScreen(subscribers: () => subs, viaVpn: true));
    await settle(t, seconds: 1);
    expect(_progressText(t), 'يفحص… 120 من 310');
    expect(_barValue(t), closeTo(120 / 310, 1e-9));
    expect(_inSeg('unchecked', '2'), findsOneWidget, reason: 'لا قراءة لهما والفحص جارٍ — لا «ما ردّ»');
    expect(_inSeg('noReply', '0'), findsOneWidget);

    job
      ..done = 0
      ..total = 0
      ..line = 'يقرأ السكترات…';
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    job.notifyListeners();
    await settle(t, seconds: 1);
    expect(_progressText(t), 'يقرأ السكترات…');
    expect(_barValue(t), isNull, reason: 'مرحلةٌ بلا عدد ⇒ شريطٌ متحرّك لا نسبة كاذبة');

    VpnNow.debugApply(VpnNowKind.subscribers, VpnNowResult(ok: true, message: 'تم', atMs: DateTime.now().millisecondsSinceEpoch, readings: {
      'a.u': const VpnSubReading(src: 'cpe', sig: -52, ccq: 96, lan: '100'),
      'b.u': const VpnSubReading(src: 'dead'),
    }));
    job.reset();
    await settle(t, seconds: 1);
    expect(_progressText(t), 'انتهى الفحص — 3 مشترك');
    expect(_barValue(t), 1.0);
    expect(_inSeg('noReply', '1'), findsOneWidget);
    expect(_inSeg('offline', '1'), findsOneWidget);

    job
      ..phase = VpnBarPhase.failed
      ..line = 'الـVPN ما اتّصل الآن — حاول بعد قليل';
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    job.notifyListeners();
    await settle(t, seconds: 1);
    expect(_progressText(t), 'الـVPN ما اتّصل الآن — حاول بعد قليل');
    expect(find.byKey(const ValueKey('subs-check-progress-bar')), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await visualTearDown();
  });

  testWidgets('١٠ نوفمبر · «كل الشركات»: شبكتك ثمّ الخادم باسم الشركة، و«انتهى الفحص» حين ينتهي الاثنان', (t) async {
    await visualSetUp(s1bSasOwner);
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
    final subs = [_s('s.ok', 's').withCompany(kS), _s('e.one', 'e').withCompany(kE), _s('x.one', 'x').withCompany(kX)];
    final now = DateTime.now();
    SubscribersCheck.debugPeek = (s) => s.username == 's.ok'
        ? (snap: DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '1', ubnt: _nano(-50, 95)), stale: false, at: now)
        : null;
    final job = VpnNow.subscribers;
    final wave = ValueNotifier(SubsWave.idle.start([SubsWave.keyOf(kS, 's.ok')], now).progress(3, 9));
    // الخادم يفحص الجزيرة الآن وايرث لنك قبلها في الفحص نفسه ⇒ ايرث لنك لا «بانتظار دورها»
    job
      ..phase = VpnBarPhase.running
      ..queue = [kE, kX]
      ..current = kX
      ..done = 9
      ..total = 22;
    addTearDown(() {
      SubscribersCheck.debugPeek = null;
      wave.dispose();
      job.reset();
      VpnNow.clearCompanyReadings();
      MergedMode.reset();
    });
    VpnNow.debugApplyCompany(kE, const VpnNowResult(ok: true, message: 'تم', readings: {
      'e.one': VpnSubReading(src: 'cpe', sig: -55, ccq: 94, lan: '100'),
    }));
    await pumpVisual(t, const VisualDevice('', Size(390, 1300), 3),
        home: (_) => SubscribersCheckScreen(
              subscribers: () => subs,
              viaVpn: false,
              wave: wave,
              companies: [co(kS), co(kE), co(kX)],
              openCompany: kS,
            ));
    await settle(t, seconds: 1);
    expect(_progressText(t), 'يفحص من شبكتك… 3 من 9');
    expect(find.descendant(of: find.byKey(const ValueKey('subs-check-company-$kE')), matching: find.textContaining('بانتظار دورها')),
        findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('subs-check-company-$kX')), matching: find.textContaining('يُفحص عبر VPN')),
        findsOneWidget);
    expect(_inSeg('unchecked', '1'), findsOneWidget, reason: 'x.one: شركته يفحصها الخادم الآن');

    wave.value = wave.value.finish(DateTime.now());
    await settle(t, seconds: 1);
    expect(_progressText(t), 'يفحص… 9 من 22 · «الجزيرة» عبر VPN');

    VpnNow.debugApplyCompany(kX, const VpnNowResult(ok: true, message: 'تم', readings: {'x.one': VpnSubReading(src: 'dead')}));
    job.reset();
    await settle(t, seconds: 1);
    expect(_progressText(t), 'انتهى الفحص — 3 مشترك');
    expect(_barValue(t), 1.0);
    expect(_inSeg('noReply', '1'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await visualTearDown();
  });

  testWidgets('١٠ نوفمبر · صورة المالك على ٣٢٠ (فاتحاً وداكناً): 4 · 54 · جهازه ما ردّ 12 وغير متّصل الآن 43 — والتقرير المنسوخ بالأقسام نفسها',
      (t) async {
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    for (final dark in [false, true]) {
      await visualSetUp(s1bSasOwner);
      ConnectionAlertSettings.current.value = const ConnectionAlertThresholds(signalDbm: -70, ccqPct: 60);
      // ١١٣ تجريبيّاً: ٤ بمشكلة · ٥٤ سليم · ١٢ متّصلٌ فُحص وما ردّ · ٤٣ غير متّصل
      final subs = [
        for (var i = 0; i < 113; i++) _s('demo${i.toString().padLeft(3, '0')}', 'تجريبي $i', online: i < 70),
      ];
      final at = DateTime.now().subtract(const Duration(minutes: 2));
      SubscribersCheck.debugPeek = (s) {
        final i = int.parse(s.username.substring(4));
        if (i >= 70) return null;
        if (i >= 58) return (snap: null, stale: false, at: at);
        final bad = [(-79, 90), (-74, 88), (-58, 41), (-66, 55)];
        final (sig, ccq) = i < 4 ? bad[i] : (-45 - i % 12, 90 + i % 9);
        return (snap: DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '$i', ubnt: _nano(sig, ccq)), stale: false, at: at);
      };
      final wave = ValueNotifier(SubsWave(endedAt: at));
      await pumpVisual(t, VisualDevice('', const Size(320, 700), 3, dark: dark),
          home: (_) => SubscribersCheckScreen(subscribers: () => subs, viaVpn: false, wave: wave, onForceAll: () {}));
      await settle(t, seconds: 1);
      expect(_inSeg('problems', '4'), findsOneWidget);
      expect(_inSeg('healthy', '54'), findsOneWidget);
      expect(_inSeg('noReply', '12'), findsOneWidget);
      expect(_inSeg('noReply', 'جهازه ما ردّ'), findsOneWidget);
      expect(_inSeg('offline', '43'), findsOneWidget);
      expect(_inSeg('offline', 'غير متّصل الآن'), findsOneWidget);
      expect(find.byKey(const ValueKey('subs-check-seg-noMetrics')), findsNothing, reason: 'صفرٌ ⇒ لا حبّة');
      expect(find.textContaining('لم يُقرأ'), findsNothing);
      expect(find.text('51%'), findsNothing);
      expect(_progressText(t), 'انتهى الفحص — 113 مشترك');
      expect(_barValue(t), 1.0);
      expect(find.text('منذ دقيقتين'), findsOneWidget);
      expect(find.byKey(const ValueKey('subs-check-copy')), findsOneWidget);
      expect(
          find.descendant(of: find.byType(AppBar), matching: find.byKey(const ValueKey('subs-check-copy'))), findsNothing,
          reason: 'لا مربّع جديد بالرأس');

      await t.tap(find.byKey(const ValueKey('subs-check-seg-offline')));
      await settle(t, seconds: 1);
      expect(find.byKey(const ValueKey('subs-check-miss-|demo070')), findsOneWidget);
      expect(find.byKey(const ValueKey('subs-check-miss-|demo058')), findsNothing, reason: 'ما ردّ ليس غير متّصل');
      await t.tap(find.byKey(const ValueKey('subs-check-seg-noReply')));
      await settle(t, seconds: 1);
      expect(find.descendant(of: find.byKey(const ValueKey('subs-check-miss-|demo058')), matching: find.text('ما ردّ من شبكتك')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('subs-check-miss-|demo070')), findsNothing);

      copied = null;
      await t.tap(find.byKey(const ValueKey('subs-check-copy')));
      await settle(t, seconds: 3);
      final lines = copied!.split('\n');
      expect(lines[0], 'الفحص العامّ للمشتركين — من موبايلك على الشبكة');
      expect(lines[1], 'انتهى الفحص — 113 مشترك · منذ دقيقتين');
      expect(lines[2], 'بمشكلة 4 · سليم 54 · جهازه ما ردّ 12 · غير متّصل الآن 43');
      expect(copied, contains('جهازه ما ردّ (12):\n• تجريبي 58 (demo058) — ما ردّ من شبكتك'));
      expect(copied, isNot(contains('demo070')), reason: 'غير المتّصل عددٌ وحده');
      expect(t.takeException(), isNull);
      SubscribersCheck.debugPeek = null;
      ConnectionAlertSettings.current.value = const ConnectionAlertThresholds();
      wave.dispose();
      await t.pumpWidget(const SizedBox());
      await visualTearDown();
    }
  });
}
