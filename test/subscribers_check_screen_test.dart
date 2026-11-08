import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/vpn_now_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_check_screen.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';

import 'visual_perm/visual_perm_harness.dart';

/// صفحة «الفحص العامّ» للمشتركين (٨ نوفمبر — المالك مع صورتها: «يحتاجلها ترتيب اكثر واظهار معلومات ال ccq كذلك وتصميم افضل»):
///   ١. ملخّصٌ بثلاثة أقسام (بمشكلة · سليم · لم يُقرأ) بأعدادها، وكم قُرئ من كم.
///   ٢. كلّ مشتركٍ بمقاييسه كلّها — CCQ ظاهرٌ ولو لم يكن هو المشكلة — والمجموعات بنوع المشكلة.
///   ٣. «سليم» الأقرب للحدّ أوّلاً، و«لم يُقرأ» بسببه.
///   ٤. شريحة النوع تحصر القائمة فيه.
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
}
