import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/vpn_now_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_check_screen.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';

import 'visual_perm/visual_perm_harness.dart';

// لقطة «الفحص العامّ» للمشتركين (مؤقّت للمراجعة — لا يُحفظ في المستودع).
Subscriber _s(String u, String f, String l, {bool online = true}) =>
    Subscriber.fromJson({'username': u, 'firstname': f, 'lastname': l, 'online_status': online ? 1 : 0});

void main() {
  setUpAll(visualSetUpAll);
  for (final dark in [false, true]) {
    testWidgets('general check ${dark ? 'dark' : 'light'}', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      final subs = [
        _s('hussein.k', 'حسين', 'كاظم'), _s('zainab.a', 'زينب', 'علي'), _s('ali.home', 'علي', 'حسن'),
        _s('noor.shop', 'نور', 'محمد'), _s('karrar99', 'كرار', 'جاسم'), _s('ahmed.s', 'أحمد', 'سعد'),
        _s('fatima.h', 'فاطمة', 'حيدر'), _s('yaseen', 'ياسين', 'طه'), _s('mustafa.r', 'مصطفى', 'رعد'),
        _s('sara.n', 'سارة', 'نبيل'), _s('omar.f', 'عمر', 'فاضل', online: false), _s('huda', 'هدى', 'كريم'),
      ];
      VpnNow.debugApply(VpnNowKind.subscribers, VpnNowResult(ok: true, message: 'تم', atMs: DateTime.now().millisecondsSinceEpoch, readings: {
        'hussein.k': const VpnSubReading(src: 'cpe', sig: -79, ccq: 61, lan: 'unplugged'),
        'zainab.a': const VpnSubReading(src: 'cpe', sig: -72, ccq: 88, lan: '100'),
        'ali.home': const VpnSubReading(src: 'cpe', sig: -58, ccq: 64, lan: '10'),
        'noor.shop': const VpnSubReading(src: 'olt', rx: -27.4, temp: 52),
        'karrar99': const VpnSubReading(src: 'cpe', sig: -55, ccq: 97, lan: '100'),
        'ahmed.s': const VpnSubReading(src: 'sector', sig: -61, ccq: 93),
        'fatima.h': const VpnSubReading(src: 'dead'),
        'mustafa.r': const VpnSubReading(src: 'cpe', sig: -66, ccq: 42, lan: '100'),
        'sara.n': const VpnSubReading(src: 'olt', rx: -21.3, temp: 47),
        'huda': const VpnSubReading(src: 'cpe', sig: -52, ccq: 99, lan: '1000'),
      }));
      final d = VisualDevice(dark ? '_dark' : '', const Size(390, 844), 3, dark: dark);
      await pumpVisual(t, d, home: (_) => SubscribersCheckScreen(subscribers: () => subs, viaVpn: true));
      await settle(t, seconds: 2);
      await shoot(t, s1bSasOwner, 'subs_check_problems', d, inner);
      await t.tap(find.byKey(const ValueKey('subs-check-seg-healthy')));
      await settle(t, seconds: 1);
      await shoot(t, s1bSasOwner, 'subs_check_healthy', d, inner);
      await t.tap(find.byKey(const ValueKey('subs-check-seg-missing')));
      await settle(t, seconds: 1);
      await shoot(t, s1bSasOwner, 'subs_check_missing', d, inner);
      await t.tap(find.byKey(const ValueKey('subs-check-seg-problems')));
      await settle(t, seconds: 1);
      await t.tap(find.byKey(const ValueKey('subs-check-kind-ccq')));
      await settle(t, seconds: 1);
      await shoot(t, s1bSasOwner, 'subs_check_ccq', d, inner);
      await t.pumpWidget(const SizedBox());
      await visualTearDown();
    });
  }
}
