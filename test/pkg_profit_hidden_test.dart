import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/hero_revenue_card.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/money_tabs_card.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/packages_summary_card.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_perm/visual_perm_harness.dart';

/// رئيسيّة الهاتف (المالك ٢٥ أكتوبر): «الإيرادات» و«توزيع الباقات» بطاقةٌ واحدة بتبويبين، والأرباح مع الباقات — مخفيّةٌ حتى
/// يُظهرها صاحب الحساب («خلي مخفي الا يظهر الشخص»)، وبعد الإظهار المتحقّق فوق المقدَّر («الربح المستلم اعلى الربح المقدر»).
void main() {
  setUpAll(visualSetUpAll);

  Finder inCard(Finder f) =>
      find.descendant(of: find.byType(PackagesSummaryCard), matching: f);
  Finder inTabs(Finder f) =>
      find.descendant(of: find.byType(MoneyTabsCard), matching: f);

  testWidgets('الهاتف: بطاقةٌ بتبويبين؛ الأرباح مخفيّة ثمّ «إظهار» يُظهر المتحقّق فوق المقدَّر، والاختيار يُحفظ', (t) async {
    final server = await visualSetUp(s1bSasOwner);
    try {
      await pumpVisual(t, const VisualDevice('', Size(390, 2400), 2),
          home: (_) => const MainShell());
      await settle(t);
      expect(server, isNotNull);

      // بطاقةٌ واحدة، تبويب الإيرادات أوّلاً — والباقات حيّةٌ خلفه بلا إطارٍ ثانٍ.
      expect(find.byType(MoneyTabsCard), findsOneWidget);
      expect(find.byType(HeroRevenueCard), findsOneWidget);
      expect(find.byType(PackagesSummaryCard), findsNothing, reason: 'خارج الشاشة حتى يُختار تبويبها');
      expect(find.byType(PackagesSummaryCard, skipOffstage: false), findsOneWidget);

      await t.tap(inTabs(find.text('توزيع الباقات')));
      await t.pump(const Duration(milliseconds: 300));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(MoneyTabsCard.prefKey), 'packages');
      expect(find.byType(HeroRevenueCard), findsNothing);

      expect(inCard(find.text('الأرباح')), findsOneWidget);
      expect(inCard(find.textContaining('1,592,000')), findsNothing, reason: 'لا رقم قبل الإظهار');
      expect(inCard(find.textContaining('11,647,000')), findsNothing);

      await t.tap(inCard(find.text('إظهار')));
      await t.pump();
      expect(inCard(find.text('الربح المتحقّق')), findsOneWidget);
      expect(inCard(find.text('الربح المقدَّر')), findsOneWidget);
      final realized = t.getTopLeft(inCard(find.textContaining('1,592,000')));
      final estimated = t.getTopLeft(inCard(find.textContaining('11,647,000')));
      expect(realized.dy, lessThan(estimated.dy), reason: 'المتحقّق فوق المقدَّر');
      expect(prefs.getBool('pkgcard.show_profit'), isTrue);

      await t.tap(inCard(find.byTooltip('إخفاء الأرباح')));
      await t.pump();
      expect(inCard(find.textContaining('1,592,000')), findsNothing);
      expect(inCard(find.textContaining('11,647,000')), findsNothing);
      expect(prefs.getBool('pkgcard.show_profit'), isFalse);

      await t.tap(inTabs(find.text('الإيرادات')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(HeroRevenueCard), findsOneWidget);
      expect(prefs.getString(MoneyTabsCard.prefKey), 'revenue');

      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
    } finally {
      await visualTearDown();
    }
  });
}
