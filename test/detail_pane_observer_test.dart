import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/detail_pane_observer.dart';

/// بلاغ المالك ٢٧ أكتوبر (الحاسبة): «من ينقر على مشترك يطلعله القائمة الجانبيه، بس ينقره مره ثانيه تختفي، واذا نقر
/// مره ثالثه ما يصير شي إلّا يخرج ويرجع». اللوحة نفسها كما تبنيها شاشة المشتركين: Navigator أوّله صفحةٌ فارغة،
/// وكلّ نقرة `pushAndRemoveUntil` لتفاصيل المشترك.
void main() {
  testWidgets('🚨 ثلاث نقرات (المشترك نفسه وغيره) واللوحة باقية مفتوحة؛ والرجوع والحذف يطويانها', (t) async {
    var emptied = 0;
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      home: Navigator(
        key: nav,
        observers: [DetailPaneObserver(() => emptied++)],
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const Text('فارغة')),
      ),
    ));
    Route<void> detail(String name) => PageRouteBuilder<void>(
          pageBuilder: (_, __, ___) => Text(name),
          transitionDuration: const Duration(milliseconds: 160),
          reverseTransitionDuration: const Duration(milliseconds: 120),
        );

    for (final name in ['أحمد', 'أحمد', 'علي', 'حسين']) {
      nav.currentState!.pushAndRemoveUntil(detail(name), (r) => r.isFirst);
      await t.pumpAndSettle();
      expect(emptied, 0, reason: 'فتح «$name» لا يطوي اللوحة');
      expect(find.text(name), findsOneWidget);
    }

    // زرّ الرجوع / Esc
    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(emptied, 1);
    expect(find.text('فارغة'), findsOneWidget);

    // حذف المشترك: تُزال صفحته من اللوحة
    final r = detail('مريم');
    nav.currentState!.pushAndRemoveUntil(r, (x) => x.isFirst);
    await t.pumpAndSettle();
    expect(emptied, 1);
    nav.currentState!.removeRoute(r);
    await t.pumpAndSettle();
    expect(emptied, 2);
  });
}
