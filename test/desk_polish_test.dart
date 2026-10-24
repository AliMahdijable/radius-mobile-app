import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/util/ar_date.dart';
import 'package:rad_mysvcs/core/widgets/desk_pressable.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/desktop_overview.dart';
import 'package:rad_mysvcs/screens/desktop/desk_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sim_el/sim_harness.dart' show SimDiskLoader, simSetUpAll;

/// إعادة تصميم الحاسبة بالإضافات (المالك ٢٤ أكتوبر: «عيد التصميم باستخدام الاضافات»): الكيبورد يصل كلّ عنصرٍ يُنقر،
/// والأرقام الحيّة تُعلَن بوقت تحديثها، والتاريخ بالأشهر العراقيّة، ومكان الرقم قبل وصوله خطٌّ لا «…».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(simSetUpAll);

  Future<void> pump(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(1200, 800);
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
    await t.pump();
    await t.pump();
  }

  BoxDecoration? ringOf(WidgetTester t, Finder pressable) {
    final box = t.widget<DecoratedBox>(find
        .descendant(of: pressable, matching: find.byType(DecoratedBox))
        .first);
    return box.decoration as BoxDecoration?;
  }

  testWidgets('Tab يصل العنصر وEnter ينقره، والإطار مع الكيبورد وحده', (t) async {
    var taps = 0;
    await pump(
      t,
      DeskPressable(
        onTap: () => taps++,
        radius: BorderRadius.circular(8),
        builder: (_, hover) => const SizedBox(width: 120, height: 40, child: Text('عنصر')),
      ),
    );
    final p = find.byType(DeskPressable);
    // الفأر: نقرةٌ بلا إطار.
    await t.tap(find.text('عنصر'));
    await t.pump();
    expect(taps, 1);
    expect(ringOf(t, p)?.border, isNull);
    // الكيبورد: Tab ثمّ Enter.
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(ringOf(t, p)?.border, isNotNull);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(taps, 2);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(taps, 3);
  });

  testWidgets('بلا onTap: لا يصله Tab ولا يُنقر', (t) async {
    await pump(
      t,
      DeskPressable(onTap: null, builder: (_, hover) => const SizedBox(width: 50, height: 20)),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(ringOf(t, find.byType(DeskPressable))?.border, isNull);
  });

  testWidgets('«حُدّث الآن»، وبعد ربع ساعةٍ بلون التنبيه', (t) async {
    await pump(t, DeskFreshness(at: DateTime.now()));
    expect(find.text('حُدّث الآن'), findsOneWidget);
    await pump(t, DeskFreshness(at: DateTime.now().subtract(const Duration(minutes: 15))));
    expect(find.text('حُدّث منذ 15 دقيقة'), findsOneWidget);
    final pill = t.widget<Container>(find
        .ancestor(of: find.text('حُدّث منذ 15 دقيقة'), matching: find.byType(Container))
        .first);
    expect((pill.decoration as BoxDecoration).color, isNotNull, reason: 'القديمة بخلفيّة التنبيه');
  });

  testWidgets('التاريخ الطويل بالأشهر العراقيّة بلا نقاطٍ فاصلة', (t) async {
    await pump(t, const SizedBox());
    final s = iqLongDate(DateTime(2026, 10, 24));
    expect(s, 'السبت 24 تشرين الأوّل 2026');
    expect(s.contains('·'), isFalse);
    expect(iqLongDate(DateTime(2027, 1, 1)), 'الجمعة 1 كانون الثاني 2027');
  });

  testWidgets('الأرقام قبل وصولها: خطٌّ مكان كلّ رقم لا «…»، بلا فيض', (t) async {
    await pump(
      t,
      const DesktopOverview(
        stats: null,
        wallet: null,
        debtors: null,
        subsLocked: false,
        balanceLocked: false,
        debtLocked: false,
      ),
    );
    expect(find.text('…'), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Skeleton'),
      findsWidgets,
    );
    expect(t.takeException(), isNull);
  });
}
