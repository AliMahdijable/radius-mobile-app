import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/packages_summary_card.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «الربح المقدَّر» في بطاقة توزيع الباقات مخفيٌّ حتى يُظهره صاحب الحساب (المالك ٢٥ أكتوبر: «خلي مخفي الا يظهر الشخص…
/// حتى لاتصير خربطه بينه وبين الايرادات اعلاه»)، والاختيار يُحفظ على الجهاز.
void main() {
  setUpAll(visualSetUpAll);

  Finder inCard(Finder f) =>
      find.descendant(of: find.byType(PackagesSummaryCard), matching: f);

  testWidgets('مخفيٌّ افتراضيّاً؛ «إظهار» يُظهره ويحفظه، والإخفاء يعيده', (t) async {
    final server = await visualSetUp(s1bSasOwner);
    try {
      await pumpVisual(t, const VisualDevice('', Size(390, 2400), 2),
          home: (_) => const MainShell());
      await settle(t);
      expect(server, isNotNull);

      expect(inCard(find.text('الربح المقدَّر')), findsOneWidget);
      expect(inCard(find.textContaining('11,647,000')), findsNothing,
          reason: 'لا رقم بجانب التفعيلات قبل الإظهار');

      await t.tap(inCard(find.text('إظهار')));
      await t.pump();
      expect(inCard(find.textContaining('11,647,000')), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pkgcard.show_profit'), isTrue);

      await t.tap(inCard(find.byTooltip('إخفاء الربح المقدَّر')));
      await t.pump();
      expect(inCard(find.textContaining('11,647,000')), findsNothing);
      expect(inCard(find.text('إظهار')), findsOneWidget);
      expect(prefs.getBool('pkgcard.show_profit'), isFalse);

      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
    } finally {
      await visualTearDown();
    }
  });
}
