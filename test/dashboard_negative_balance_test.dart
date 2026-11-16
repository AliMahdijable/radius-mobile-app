import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/dashboard_api.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/desktop_overview.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/stats_grid.dart';
import 'package:rad_mysvcs/theme/colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sim_el/sim_harness.dart';

/// المالك ١٦ نوفمبر («صلّحها»، بعد لقطة ورقة التمديد «الرصيد غير كافٍ» ورصيدٌ «110,378,803»): رصيد المدير في الساس قد يكون
/// **سالباً** (يعمل بالآجل، أو أدمن رئيسيّ) — وكانت الرئيسيّة تعرضه بلا ناقص (`formatIQD` يُسقط الإشارة) كأنّه رصيدٌ موجود.
/// الآن بإشارته وبلون الخطأ، على الهاتف وعلى الحاسبة؛ والموجب ومجموع الديون كما كانا.
DebtorsResult _debtors() => const DebtorsResult(
      count: 2,
      total: 75000,
      nearExpiry: 0,
      online: 3,
      offline: 1,
      active: 4,
      expired: 1,
      totalSubs: 5,
      onlineNoPlan: 0,
      disabled: 0,
    );

Text _amount(WidgetTester t, String digits) =>
    t.widget<Text>(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(digits)));

void main() {
  setUpAll(simSetUpAll);

  group('الهاتف — بطاقة الرصيد', () {
    Future<void> pump(WidgetTester t, SimVariant v, num balance) async {
      await pumpSim(t, v,
          home: (_) => Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StatsGrid(wallet: WalletResult(balance: balance, points: 0), debtors: _debtors()),
                ),
              ));
      expect(t.takeException(), isNull, reason: 'لا فيض ولا استثناء @${v.tag}');
    }

    for (final v in const [SimVariant(390, dark: false), SimVariant(320, dark: true)]) {
      testWidgets('رصيدٌ سالب ⇒ «−110,378,803» بلون الخطأ @${v.tag}', (t) async {
        await pump(t, v, -110378803);
        final a = _amount(t, '110,378,803');
        expect(a.data, '−110,378,803', reason: 'كان «110,378,803» كأنّه رصيدٌ موجود');
        expect(a.textDirection, TextDirection.ltr, reason: 'وإلّا قفز الناقص يمين الرقم في السطر العربيّ');
        expect(a.style?.color, AppColors.error);
        // مجموع الديون (موجبٌ دائماً) لم يتغيّر
        expect(find.text('75,000'), findsOneWidget);
      });
    }

    testWidgets('رصيدٌ موجب ⇒ كما كان: بلا ناقص ولا لون خطأ', (t) async {
      await pump(t, const SimVariant(390, dark: false), 110378803);
      final a = _amount(t, '110,378,803');
      expect(a.data, '110,378,803');
      expect(a.style?.color, isNot(AppColors.error));
    });

    testWidgets('صفر ⇒ «0» بلا ناقص', (t) async {
      await pump(t, const SimVariant(390, dark: false), 0);
      expect(find.text('0'), findsOneWidget);
      expect(find.textContaining('−'), findsNothing);
    });
  });

  group('الحاسبة — بطاقة الرصيد في النظرة العامّة', () {
    Future<void> pump(WidgetTester t, num balance) async {
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
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: DesktopOverview(
                  stats: null,
                  wallet: WalletResult(balance: balance, points: 0),
                  debtors: _debtors(),
                  subsLocked: false,
                  balanceLocked: false,
                  debtLocked: false,
                ),
              ),
            ),
          ),
        ),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
    }

    testWidgets('رصيدٌ سالب ⇒ «−110,378,803» بلون الخطأ', (t) async {
      await pump(t, -110378803);
      final a = _amount(t, '110,378,803');
      expect(a.data, '−110,378,803');
      expect(a.textDirection, TextDirection.ltr);
      expect(a.style?.color, AppColors.error);
    });

    testWidgets('رصيدٌ موجب ⇒ كما كان', (t) async {
      await pump(t, 110378803);
      final a = _amount(t, '110,378,803');
      expect(a.data, '110,378,803');
      expect(a.style?.color, isNot(AppColors.error));
    });
  });
}
