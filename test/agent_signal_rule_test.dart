// «الإشارة» نفسها في كلّ عرض (المالك ٢٦ نوفمبر، صورتا «السكتر الاول»: «شوف الاختلاف بالفحص… بجميع الاوضاع»).
// البطاقة كانت تعرض ما نستقبله من المشترك وحده (-64) واللوحة «كيف يستقبلنا/كيف نستقبله» (-56/-64)، ولوحة يوبيكويتي بالترتيب المعكوس.
// القاعدة (٦ نوفمبر: «مفروض تقره الاشارة من عدنا… او تظهرهن الاثنين»): إشارة المشترك = كيف يستقبلنا أوّلاً، وإلّا ما نستقبله —
// منها اللون والترتيب والمتوسّط والأضعف، والنصّ «tx/rx» كلوحة الجهاز في البطاقة والبرج ولوحتي مايكروتك ويوبيكويتي.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/mikrotik_api.dart';
import 'package:rad_mysvcs/api/ubnt_api.dart';
import 'package:rad_mysvcs/core/util/bidi.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_big_card.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'support/app_fonts.dart';

// قراءة صورة المالك (لوحة الجهاز): الاسم، كيف يستقبلنا، كيف نستقبله، CCQ
const _owner = [
  ('om.bayda@popq', -36, -51, 99),
  ('azez.abo@popq', -56, -64, 99),
  ('abo.wisam@popq', -37, -51, 97),
  ('abbas.atala@po', -47, -64, 100),
  ('husein.ab@popq', -39, -66, 100),
];

void main() {
  group('القاعدة', () {
    test('PeerLink: إشارة الوكيل = كيف يستقبلنا أوّلاً، والنصّ «tx/rx»؛ المجهول لا يصير صفراً', () {
      const both = PeerLink(name: 'a', signal: -64, txSignal: -56);
      expect([both.agentSignal, both.signalPair], [-56, '-56/-64']);
      const rxOnly = PeerLink(name: 'b', signal: -60);
      expect([rxOnly.agentSignal, rxOnly.signalPair], [-60, '-60']);
      const txOnly = PeerLink(name: 'c', txSignal: -40, signal: 0);
      expect([txOnly.agentSignal, txOnly.signalPair], [-40, '-40']);
      const none = PeerLink(name: 'd', signal: 0);
      expect([none.agentSignal, none.signalPair], [null, null]);
    });

    test('مايكروتك ويوبيكويتي بالترتيب نفسه: «كيف يستقبلنا/كيف نستقبله»، والإشارة الأولى للّون والأضعف', () {
      final mk = MikrotikWirelessClient.fromApiMap({'mac-address': 'DC:9F:DB:5E:89:8F', 'signal-strength': '-64dBm@6Mbps',
        'tx-signal-strength': '-56', 'tx-ccq': '99'});
      expect([mk.signalDisplay, mk.agentSignal], ['-56/-64', -56]);
      const ub = UbntStation(mac: 'x', signal: -64, txSignal: -56, noise: -95, ccq: 99, txRate: 86, rxRate: 78, connTime: 60);
      expect([ub.signalDisplay, ub.agentSignal], ['-56/-64', -56], reason: 'كان «-64/-56» — عكس مايكروتك لنفس المشترك');
      const ubRx = UbntStation(mac: 'y', signal: -70, noise: -95, ccq: 90, txRate: 1, rxRate: 1, connTime: 1);
      expect([ubRx.signalDisplay, ubRx.agentSignal], ['-70', -70]);
    });
  });

  group('البطاقة الكبيرة = لوحة الجهاز', () {
    setUpAll(loadAppFonts);
    tearDown(() => AppColors.setDarkMode(false));
    final now = DateTime(2026, 11, 26, 9);
    final d = NetworkDevice(
        id: 41, adminId: '1', name: 'السكتر الاول', type: 'sector', brand: 'mikrotik', model: 'BaseBox 5', ip: '10.70.241.2',
        port: 8728, protocol: 'api', hasCredentials: true, lastStatus: 'online', lastResponseMs: 17, createdAt: DateTime(2026));
    final st = VitalsState(
      at: now.subtract(const Duration(seconds: 35)),
      detail: DeviceDetail(
        peers: [for (final o in _owner) PeerLink(name: o.$1, txSignal: o.$2, signal: o.$3, ccq: o.$4, txRate: 86, rxRate: 78)],
        peersLabel: 'العملاء اللاسلكيّون',
        glance: const DeviceGlance(peersKnown: true, isAp: true),
      ),
    );

    Future<void> pump(WidgetTester t, double w, bool dark) async {
      AppColors.setDarkMode(dark);
      t.view.physicalSize = Size(w, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'IBMPlexSansArabic'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: AppColors.bg,
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: DeviceBigCard(device: d, state: st, medianMs: 12, now: now),
            ),
          ),
        ),
      ));
      await t.pump();
    }

    bool shows(String s) => find.text(s).evaluate().isNotEmpty || find.text(iso(s)).evaluate().isNotEmpty;

    testWidgets('صورة المالك: كلّ مشتركٍ كيف يستقبلنا ثمّ «rx …» تحته (رقما اللوحة نفسهما)، والمتوسّط والأضعف من الأولى، والأضعف أوّلاً', (t) async {
      for (final w in [320.0, 360.0, 390.0, 430.0]) {
        for (final dark in [false, true]) {
          await pump(t, w, dark);
          for (final o in _owner) {
            expect(shows('${o.$2}'), isTrue, reason: '${o.$1} @$w — كيف يستقبلنا (أوّل رقم اللوحة)');
            expect(shows('rx ${o.$3}'), isTrue, reason: '${o.$1} @$w — وما نستقبله منه (ثاني رقم اللوحة) تحته');
          }
          expect(find.textContaining('-43'), findsWidgets, reason: 'متوسّط كيف يستقبلنا: (−36−56−37−47−39)/5 = −43 (كان −59 من الـrx)');
          expect(find.textContaining('-56'), findsWidgets, reason: 'الأضعف كيف يستقبلنا = azez −56 (كان −66 من الـrx)');
          final names = [for (final o in _owner) o.$1];
          final ys = {for (final n in names) n: t.getTopLeft(find.text(iso(n)).first).dy};
          expect(ys['azez.abo@popq']! <= ys['om.bayda@popq']!, isTrue, reason: 'الأضعف (−56) قبل الأقوى (−36)');
          expect(t.takeException(), isNull, reason: 'لا تجاوز @$w dark=$dark');
        }
      }
    });
  });
}
