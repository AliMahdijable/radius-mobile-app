import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_traffic_chart.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'sim_el/sim_harness.dart' show simTheme;
import 'visual_perm/visual_perm_harness.dart' show visualSetUpAll;

void main() {
  setUpAll(visualSetUpAll);
  tearDown(() => AppColors.setDarkMode(false));
  final start = DateTime(2026, 11, 5);

  test('الانقطاع فاصل لا صفر، التاريخ محدود ويبدأ من جديد عند تبديل الجهاز',
      () {
    final h = SubscriberTrafficHistory();
    h.gap(start);
    expect(h.samples, isEmpty);
    h.add(start, 0, 0);
    h.gap(start.add(const Duration(seconds: 5)));
    h.gap(start.add(const Duration(seconds: 10)));
    h.add(start.add(const Duration(seconds: 15)), 8000000, 500000);
    expect(h.samples.map((s) => s.valid), [true, false, true]);
    expect(h.samples.first.down, 0);
    for (var i = 16; i < 400; i++) {
      h.add(start.add(Duration(seconds: i)), i, i);
    }
    expect(
        h.samples.length, lessThanOrEqualTo(SubscriberTrafficHistory.capacity));
    expect(h.samples.last.at.difference(h.samples.first.at),
        lessThanOrEqualTo(SubscriberTrafficHistory.window));
    h.add(start.add(const Duration(minutes: 20)), 1, 2);
    expect(h.samples, hasLength(1), reason: 'لا تاريخ قديم بعد رجوع طويل');
    h.add(start, 3, 4);
    expect(h.samples, hasLength(1), reason: 'تصحيح الساعة لا يرسم للخلف');
    h.clear();
    expect(h.samples, isEmpty);
  });

  test('الصفر قراءة حقيقية، والوحدات لا تختلط بين كيلو وميغا وغيغا', () {
    expect(subscriberTrafficRate(null), '—');
    expect(subscriberTrafficRate(0), '0 Kbps');
    expect(subscriberTrafficRate(995000), '995 Kbps');
    expect(subscriberTrafficRate(8000000), '8.0 Mbps');
    expect(subscriberTrafficRate(2500000000), '2.5 Gbps');
  });

  for (final design in SubscriberTrafficDesign.values) {
    for (final dark in [false, true]) {
      testWidgets(
          '${design.name}: فارغة ثم قراءات ثم انقطاع، عروض صغيرة ونص مكبر (${dark ? 'dark' : 'light'})',
          (t) async {
        AppColors.setDarkMode(dark);
        final history = SubscriberTrafficHistory();
        final boundaryKey = GlobalKey();
        Future<void> pump(double width, int? down, int? up,
            {bool unavailable = false}) async {
          await t.pumpWidget(MaterialApp(
            theme: simTheme(dark ? Brightness.dark : Brightness.light),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.2)),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                    body: Center(
                        child: RepaintBoundary(
                  key: boundaryKey,
                  child: SizedBox(
                      width: width,
                      child: SubscriberTrafficChart(
                        design: design,
                        samples: history.samples,
                        downBps: down,
                        upBps: up,
                        unavailable: unavailable,
                      )),
                ))),
              ),
            ),
          ));
          await t.pump();
          expect(t.takeException(), isNull);
          if (design == SubscriberTrafficDesign.gauges) {
            final dials = find.descendant(
                of: find.byType(SubscriberTrafficChart),
                matching: find.byType(CustomPaint));
            expect(dials, findsNWidgets(2));
            for (final dial in dials.evaluate()) {
              expect(
                  t.getSize(find.byWidget(dial.widget)).width, greaterThan(60),
                  reason: 'العدّاد يستعمل عرض العمود، لا عرض كلمة التسمية');
            }
          }
        }

        await pump(248, null, null);
        expect(find.text('بانتظار القراءة'), findsOneWidget);
        expect(find.text('يظهر الرسم عند وصول القراءات'), findsOneWidget);
        await pump(248, null, null, unavailable: true);
        expect(find.text('تعذّرت قراءة الترافيك'), findsOneWidget);
        expect(find.text('بانتظار إعادة المحاولة'), findsOneWidget);
        history.add(start, 0, 0);
        await pump(248, 0, 0);
        expect(find.text('0 Kbps'), findsNWidgets(2));
        expect(find.text('تجميع القراءات…'), findsOneWidget);
        for (var i = 1; i < 48; i++) {
          history.add(
              start.add(Duration(seconds: 5 * i)),
              ((6 +
                          3 * math.sin(i / 4) +
                          10 * math.exp(-math.pow((i - 30) / 4, 2))) *
                      1000000)
                  .round(),
              ((0.7 + 0.2 * math.sin(i / 3)) * 1000000).round());
        }
        for (final width in [248.0, 320.0, 600.0]) {
          await pump(width, 8000000, 995000);
          expect(find.text('8.0 Mbps'), findsOneWidget);
          expect(find.text('995 Kbps'), findsOneWidget);
        }
        final output = Platform.environment['TRAFFIC_SHOTS_DIR'];
        if (output != null) {
          await pump(340, 8000000, 995000);
          final boundary =
              t.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
          await t.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            final file = File(
                '$output/traffic-${design.name}-${dark ? 'dark' : 'light'}.png');
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(data!.buffer.asUint8List());
          });
        }
        history.gap(start.add(const Duration(minutes: 4)));
        await pump(248, null, null);
        expect(find.text('القراءة متوقفة'), findsOneWidget);
        expect(find.text('8.0 Mbps'), findsNothing);
        expect(find.text('—'), findsNWidgets(2));
      });
    }
  }
}
