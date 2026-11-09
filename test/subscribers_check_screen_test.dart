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
    expect(inSeg('missing', '3'), findsOneWidget);
    expect(find.text('قُرئ 5 من 8'), findsOneWidget);

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

    // ٣ لم يُقرأ: بسببه
    await t.tap(find.byKey(const ValueKey('subs-check-seg-missing')));
    await settle(t, seconds: 1);
    expect(find.descendant(of: find.byKey(const ValueKey('subs-check-miss-|dead.u')), matching: find.text('لا يستجيب')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('subs-check-miss-|off.u')), matching: find.text('غير متّصل')),
        findsOneWidget);
    expect(
        find.descendant(of: find.byKey(const ValueKey('subs-check-miss-|none.u')), matching: find.text('لم يُقرأ عبر VPN')),
        findsOneWidget);

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
    expect(find.byKey(ValueKey('subs-check-row-$kS|s.bad')), findsOneWidget);
    expect(find.byKey(ValueKey('subs-check-row-$kE|e.bad')), findsOneWidget);

    // الضغط على ايرث لنك ⇒ مشتركوها وحدهم
    await t.tap(company(kE));
    await settle(t, seconds: 1);
    expect(find.byKey(ValueKey('subs-check-row-$kS|s.bad')), findsNothing);
    expect(find.byKey(ValueKey('subs-check-row-$kE|e.bad')), findsOneWidget);
    expect(find.text('«ايرث لنك» وحدها — اضغطها ثانيةً لعرض الكلّ'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('subs-check-seg-problems')), matching: find.text('1')), findsOneWidget);

    // من لم يُقرأ: الجزيرة بسببها
    await t.tap(company(kE));
    await settle(t, seconds: 1);
    await t.tap(find.byKey(const ValueKey('subs-check-seg-missing')));
    await settle(t, seconds: 1);
    expect(find.descendant(of: find.byKey(ValueKey('subs-check-miss-$kX|x.one')), matching: find.text('شركته تحتاج VPN')),
        findsOneWidget);
    expect(find.byKey(ValueKey('subs-check-miss-$kE|e.none')), findsOneWidget);

    await t.pumpWidget(const SizedBox());
    await visualTearDown();
  });
  testWidgets('٩ نوفمبر: يردّ عبر الـVPN بلا مقاييس ⇒ «لم يُقرأ» بسببه لا «سليم» — على ٣٢٠ بلا فيضان، فاتحاً وداكناً', (t) async {
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
      expect(inSeg('missing', '2'), findsOneWidget);
      expect(find.text('قُرئ 1 من 3'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('subs-check-seg-missing')));
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
}
