import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/platform/desk_nav_guard.dart';

/// المالك ٢٤ أكتوبر: «النقر على أي شي — شعارات، أي قائمة — مرّتين يفتح مرّتين الصفحة، ومن ترجع لازم ترجع خطوتين —
/// مشكلة عامّة، مال ويندوز».
///
/// ما يحدث على الحاسبة: أزرار الشريط العلويّ والقائمة الجانبيّة وصفوف جدول المشتركين **خارج** الـNavigator الذي تُفتح
/// فيه الصفحة (قسمٌ أو لوحة التفاصيل)، فالصفحة الجديدة لا تغطّيها — والنقرة الثانية تقع على الزرّ نفسه فتفتح نسخةً
/// ثانية. هنا: زرٌّ فوق Navigator داخليّ يفتح فيه صفحة، كالجرس فوق القسم.
void main() {
  setUp(DeskNavGuard.debugReset);

  Future<({List<int> pushes, GlobalKey<NavigatorState> inner})> pump(WidgetTester t, {required bool guard}) async {
    final pushes = <int>[0];
    final inner = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorObservers: guard ? [DeskNavGuard.observer()] : const [],
      builder: (c, child) => guard ? DeskNavGuardScope(child: child!) : child!,
      home: Scaffold(
        body: Column(
          children: [
            TextButton(
              onPressed: () {
                pushes[0]++;
                inner.currentState!.push(MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Center(child: Text('الصفحة'))),
                ));
              },
              child: const Text('الجرس'),
            ),
            Expanded(
              child: Navigator(
                key: inner,
                observers: guard ? [DeskNavGuard.observer()] : const [],
                onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('القسم'))),
              ),
            ),
          ],
        ),
      ),
    ));
    return (pushes: pushes, inner: inner);
  }

  /// كم صفحةً مفتوحة فوق القسم (الصفحات المغطّاة تبقى مبنيّةً خارج الشاشة).
  int pages() => find.text('الصفحة', skipOffstage: false).evaluate().length;

  Future<void> doubleClick(WidgetTester t) async {
    final at = t.getCenter(find.text('الجرس'));
    await t.tapAt(at);
    await t.pump(const Duration(milliseconds: 120)); // نقرةٌ مزدوجة عاديّة
    await t.tapAt(at);
    await t.pumpAndSettle();
  }

  testWidgets('بلا الحارس: النقرة المزدوجة على زرٍّ خارج القسم تفتح الصفحة مرّتين (ما يشكو منه المالك)', (t) async {
    final r = await pump(t, guard: false);
    await doubleClick(t);
    expect(r.pushes[0], 2);
    expect(pages(), 2);
  });

  testWidgets('مع الحارس: النقرة المزدوجة تفتح مرّة واحدة — والرجوع خطوةٌ واحدة', (t) async {
    final r = await pump(t, guard: true);
    await doubleClick(t);
    expect(r.pushes[0], 1);
    expect(pages(), 1);
    expect(DeskNavGuard.busy.value, isFalse);
    r.inner.currentState!.pop();
    await t.pumpAndSettle();
    expect(pages(), 0);
    expect(find.text('القسم'), findsOneWidget);
  });

  testWidgets('مع الحارس: نقرةٌ أثناء الرجوع لا تفتح شيئاً، وبعد الهدوء يعمل النقر كالعادة', (t) async {
    final r = await pump(t, guard: true);
    await t.tap(find.text('الجرس'));
    await t.pumpAndSettle();
    r.inner.currentState!.pop();
    await t.pump(const Duration(milliseconds: 60));
    await t.tap(find.text('الجرس'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(r.pushes[0], 1);
    expect(pages(), 0);
    await t.tap(find.text('الجرس'));
    await t.pumpAndSettle();
    expect(r.pushes[0], 2);
    expect(pages(), 1);
  });

  testWidgets('الحارس لا يعلق: يُفلت بعد الانتقال', (t) async {
    await pump(t, guard: true);
    await t.tap(find.text('الجرس'));
    expect(DeskNavGuard.busy.value, isTrue);
    await t.pump(const Duration(milliseconds: 16));
    expect(DeskNavGuard.busy.value, isTrue);
    await t.pump(DeskNavGuard.maxHold);
    expect(DeskNavGuard.busy.value, isFalse);
    await t.pumpAndSettle();
  });
}
