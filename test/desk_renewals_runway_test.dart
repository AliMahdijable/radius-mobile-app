import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/dashboard_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/desk_renewals_runway.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sim_el/sim_harness.dart' show SimDiskLoader, simSetUpAll;

/// «التجديدات القادمة» على رئيسيّة الحاسبة (المالك ٢٤ أكتوبر: «إعادة تصميم النسخة الويندوز بشكلٍ احترافي»): من ينتهي
/// اشتراكه في كلّ يومٍ من الأسبوعين القادمين — بلا رقمٍ مخترَع.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(simSetUpAll);

  group('خانة اليوم لكلّ مشترك', () {
    final now = DateTime(2026, 10, 24, 12, 0);
    Subscriber sub({String? exp, int? days, bool enabled = true}) => Subscriber.fromJson({
          'username': 'u',
          'profile_name': 'Economy',
          if (exp != null) 'expiration': exp,
          if (days != null) 'remaining_days': days,
          'enabled': enabled,
        });

    test('بالتقويم: ينتهي اليوم مساءً ⇒ ٠، وبعد منتصف الليل ⇒ ١', () {
      expect(DashboardApi.expiryDayOf(sub(exp: '2026-10-24 18:00:00'), now), 0);
      expect(DashboardApi.expiryDayOf(sub(exp: '2026-10-25 01:00:00'), now), 1);
      expect(DashboardApi.expiryDayOf(sub(exp: '2026-10-27 23:59:00'), now), 3);
      expect(DashboardApi.expiryDayOf(sub(exp: '2026-11-07 09:00:00'), now), 14); // خارج الخانات الـ١٤
    });

    test('المنتهي والموقوف لا يُعدّان، وبلا تاريخ تُؤخذ الأيّام الباقية', () {
      expect(DashboardApi.expiryDayOf(sub(exp: '2026-10-24 10:00:00'), now), isNull);
      expect(DashboardApi.expiryDayOf(sub(exp: '2026-10-26 10:00:00', enabled: false), now), isNull);
      expect(DashboardApi.expiryDayOf(sub(days: 5), now), 5);
      expect(DashboardApi.expiryDayOf(sub(days: -1), now), isNull);
    });
  });

  Future<void> pump(WidgetTester t, Widget child, {double width = 900}) async {
    t.view.physicalSize = Size(width, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
    await t.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('ar'), Locale('en')],
      path: 'assets/translations',
      startLocale: const Locale('ar'),
      fallbackLocale: const Locale('ar'),
      saveLocale: false,
      assetLoader: const SimDiskLoader(),
      child: Builder(
        builder: (ctx) => MaterialApp(
          locale: ctx.locale,
          supportedLocales: ctx.supportedLocales,
          localizationsDelegates: ctx.localizationDelegates,
          home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  // ٢ غداً و٣ بعد ثلاثة أيّام (عاجلة)، و٥ بعد ستّة أيّام (ليست عاجلة).
  final days = [0, 2, 0, 3, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0];

  testWidgets('اليوم أوّلاً، والصفر بلا رقم، والنقر على يومٍ عاجل يفتح «قربوا الانتهاء» وحده', (t) async {
    final opened = <SubscriberFilter?>[];
    await pump(
      t,
      DeskRenewalsRunway(days: days, nearExpiry: 5, today: DateTime(2026, 10, 24), onOpen: opened.add),
    );
    expect(find.text('اليوم'), findsOneWidget);
    // «0» محجوزٌ مكانه (الأعمدة بمستوى واحد) لكنّه لا يُرى.
    final zeros = find.text('0');
    expect(zeros, findsWidgets);
    for (final e in zeros.evaluate()) {
      final op = e.findAncestorWidgetOfExactType<Opacity>();
      expect(op?.opacity, 0);
    }
    await t.tap(find.text('5').first); // يومٌ غير عاجل
    await t.pump();
    expect(opened, isEmpty);
    await t.tap(find.text('3').first); // عدد اليوم الرابع (العاجل) قبل رقم «3 تشرين الثاني» في الشجرة
    await t.pump();
    expect(opened, [SubscriberFilter.nearExpiry]);
    // الجملة بعدد الفلتر نفسه (٥) ومجموع الأسبوعين (١٠).
    expect(find.text('ينتهي اشتراك 5 خلال 3 أيّام، ومجموع الأسبوعين 10'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('بلا قائمة (الحسابات الكبيرة/«كل الشركات») ⇒ العدد وحده بلا أعمدةٍ مخترعة', (t) async {
    await pump(t, const DeskRenewalsRunway(days: null, nearExpiry: 7));
    expect(find.text('7'), findsOneWidget);
    expect(find.text('اليوم'), findsNothing);
    expect(find.textContaining('التفصيل اليوميّ'), findsOneWidget);
  });

  testWidgets('أضيق عمودٍ على الحاسبة (٥٦٠) بلا فيض', (t) async {
    await pump(
      t,
      DeskRenewalsRunway(days: days, nearExpiry: 5, today: DateTime(2026, 10, 24), onOpen: (_) {}),
      width: 560,
    );
    expect(t.takeException(), isNull);
  });
}
