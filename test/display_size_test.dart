import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/core/platform/display_size.dart';
import 'package:rad_mysvcs/screens/settings_screen.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «حجم العرض» (المالك ٢٠ نوفمبر ٢٠٢٦: «نحتاج فد شي نكبر بي خط للعالم مجاي تشوف»): عادي · كبير · كبير جداً تكبّر الواجهة كلّها،
/// ولا ينزل العرض المنطقيّ تحت 320 (أضيق ما فُحصت عليه الشاشات) — فلا نصّ يخرج ولا رقم يُقصّ بالتكبير.
void main() {
  tearDown(() {
    DisplaySizePref.choice.value = DisplaySize.normal;
    AppPlatform.debugIsDesktop = null;
  });

  group('النسب', () {
    test('أكبر تكبيرٍ لكلّ هاتف: أقصر ضلعٍ ÷ 320 حتى 130٪ — لا يتغيّر بالتدوير', () {
      double mx(double w, double h) => DisplaySizePref.maxFor(Size(w, h));
      expect(mx(320, 568), 1.0, reason: 'أضيق هاتف: لا تكبير');
      expect(mx(360, 780), 1.12);
      expect(mx(375, 667), 1.17);
      expect(mx(390, 844), 1.21);
      expect(mx(412, 915), 1.28);
      expect(mx(430, 932), 1.3, reason: 'السقف');
      expect(mx(768, 1024), 1.3, reason: 'التابلت: السقف');
      expect(mx(844, 390), mx(390, 844), reason: 'بالعرض كبالطول');
      expect(DisplaySizePref.maxFor(Size.zero), 1.0);
    });

    test('«كبير» نصف الطريق و«كبير جداً» أقصاه — والعرض المنطقيّ ≥ 320 دائماً', () {
      for (final w in const <double>[320, 340, 360, 375, 384, 390, 393, 400, 411, 412, 414, 428, 430, 480, 600, 768, 1024]) {
        final screen = Size(w, w * 2.1);
        final l = DisplaySizePref.scaleFor(DisplaySize.large, screen);
        final x = DisplaySizePref.scaleFor(DisplaySize.xlarge, screen);
        expect(DisplaySizePref.scaleFor(DisplaySize.normal, screen), 1.0);
        expect(l >= 1 && l <= x && x <= DisplaySizePref.maxScale, isTrue, reason: '@$w: $l / $x');
        expect(w / x >= DisplaySizePref.minLogicalWidth, isTrue, reason: '@$w: ${w / x}');
        if (w >= 360) expect(x - l, greaterThan(0.04), reason: 'الدرجتان مختلفتان فعلاً @$w');
      }
      expect(DisplaySizePref.scaleFor(DisplaySize.large, const Size(390, 844)), 1.10);
      expect(DisplaySizePref.scaleFor(DisplaySize.large, const Size(430, 932)), 1.15);
      expect([DisplaySizePref.percent(1.21), DisplaySizePref.percent(1.1)], ['121٪', '110٪']);
    });
  });

  group('الحفظ', () {
    test('يُحفظ على الجهاز ويُقرأ قبل أوّل إطار؛ «عادي» يمحو المفتاح؛ وقيمةٌ غريبة ⇒ عادي', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const st = FlutterSecureStorage();
      await DisplaySizePref.load();
      expect(DisplaySizePref.choice.value, DisplaySize.normal);
      await DisplaySizePref.set(DisplaySize.xlarge);
      expect(await st.read(key: 'app.display_size.v1'), 'xlarge');
      DisplaySizePref.choice.value = DisplaySize.normal;
      await DisplaySizePref.load();
      expect(DisplaySizePref.choice.value, DisplaySize.xlarge);
      await DisplaySizePref.set(DisplaySize.normal);
      expect(await st.read(key: 'app.display_size.v1'), isNull);
      FlutterSecureStorage.setMockInitialValues({'app.display_size.v1': 'huge'});
      await DisplaySizePref.load();
      expect(DisplaySizePref.choice.value, DisplaySize.normal);
    });
  });

  group('التكبير', () {
    final probe = GlobalKey();
    final field = TextEditingController();
    final nav = GlobalKey<NavigatorState>();
    var taps = 0;
    // فوق الـScaffold (الذي يستهلك الحواشي واللوحة لجسمه): ما تراه الشاشات من MediaQuery
    late BuildContext top;

    Future<void> pump(WidgetTester t) async {
      // آيفون 390×844 بكثافة ٣: الشقّ ٤٧ والمؤشّر ٣٤، ولوحة المفاتيح ٣٠٠
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      t.view.padding = const FakeViewPadding(top: 141, bottom: 102);
      t.view.viewPadding = const FakeViewPadding(top: 141, bottom: 102);
      t.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(t.view.reset);
      taps = 0;
      await t.pumpWidget(MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DisplaySizeScope(child: child!),
        home: Builder(builder: (c) {
          top = c;
          return Scaffold(
          body: Column(
            children: [
              SizedBox(key: probe, height: 10, width: double.infinity),
              TextField(controller: field),
              const Spacer(),
              Align(
                alignment: AlignmentDirectional.bottomEnd,
                child: TextButton(onPressed: () => taps++, child: const Text('زرّ')),
              ),
            ],
          ),
        );
        }),
      ));
    }

    MediaQueryData inner(WidgetTester t) => MediaQuery.of(top);

    testWidgets('«عادي» كما كان حرفاً: لا تحويل ولا MediaQuery آخر', (t) async {
      await pump(t);
      expect(find.byType(DisplayZoom), findsNothing);
      expect(inner(t).size, const Size(390, 844));
      expect(inner(t).viewInsets.bottom, 300);
    });

    testWidgets('«كبير جداً»: الداخل بعرض 390÷1.21، والحواشي ولوحة المفاتيح مقسومة — والرسم يملأ الشاشة كما هي', (t) async {
      await pump(t);
      DisplaySizePref.choice.value = DisplaySize.xlarge;
      await t.pump();
      const s = 1.21;
      final mq = inner(t);
      expect(mq.size.width, closeTo(390 / s, 0.01));
      expect(mq.size.width, greaterThanOrEqualTo(320));
      expect(mq.size.height, closeTo(844 / s, 0.01));
      expect(mq.padding.top, closeTo(47 / s, 0.01));
      expect(mq.viewPadding.bottom, closeTo(34 / s, 0.01));
      expect(mq.viewInsets.bottom, closeTo(300 / s, 0.01), reason: 'الورقة تُرفع فوق اللوحة بقدرها لا أكثر');
      expect(mq.devicePixelRatio, closeTo(3 * s, 0.001), reason: 'الصور بدقّتها بعد التكبير');
      // عرض الشريط الداخليّ بعد الرسم = عرض الشاشة كلّه
      final box = probe.currentContext!.findRenderObject()! as RenderBox;
      final topLeft = box.localToGlobal(Offset.zero);
      final topRight = box.localToGlobal(Offset(box.size.width, 0));
      expect((topRight - topLeft).dx, closeTo(390, 0.01));
      // النقر يصل عبر التحويل
      await t.tap(find.text('زرّ'));
      expect(taps, 1);
    });

    testWidgets('تغيير الحجم لا يعيد بناء التطبيق: الصفحة المفتوحة وما كُتب يبقيان', (t) async {
      await pump(t);
      field.text = 'نصٌّ مكتوب';
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('صفحة ثانية'))));
      await t.pumpAndSettle();
      for (final s in [DisplaySize.large, DisplaySize.xlarge, DisplaySize.normal, DisplaySize.xlarge]) {
        DisplaySizePref.choice.value = s;
        await t.pumpAndSettle();
        expect(find.text('صفحة ثانية'), findsOneWidget, reason: '$s');
        expect(t.takeException(), isNull);
      }
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(find.text('نصٌّ مكتوب'), findsOneWidget);
    });

    testWidgets('الحاسبة: لا تكبير هنا (لها «حجم الواجهة»)', (t) async {
      AppPlatform.debugIsDesktop = true;
      await pump(t);
      DisplaySizePref.choice.value = DisplaySize.xlarge;
      await t.pump();
      expect(find.byType(DisplayZoom), findsNothing);
      expect(inner(t).size, const Size(390, 844));
    });
  });

  group('الإعدادات', () {
    setUpAll(visualSetUpAll);
    const phone = VisualDevice('_390', Size(390, 2600), 3);

    Future<void> openSettings(WidgetTester t, {VisualDevice d = phone}) async {
      await visualSetUp(s1bSasOwner);
      FlutterSecureStorage.setMockInitialValues({});
      final nav = GlobalKey<NavigatorState>();
      await pumpVisual(t, d,
          navigatorKey: nav, home: (_) => Scaffold(backgroundColor: AppColors.bg), wrap: (c) => DisplaySizeScope(child: c));
      await settle(t, seconds: 1);
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
      await settle(t, seconds: 2);
    }

    Future<void> drain(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 25));
    }

    final row = find.byKey(const ValueKey('settings-display-size'));

    testWidgets('صفّ «حجم العرض» تحت المظهر ⇒ ورقةٌ بثلاثة أحجامٍ ونسبها لهذه الشاشة ⇒ يُطبَّق فوراً ويُحفظ', (t) async {
      await openSettings(t);
      await t.ensureVisible(row);
      await t.pumpAndSettle();
      expect(find.descendant(of: row, matching: find.text('حجم العرض')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('عادي')), findsOneWidget);
      await t.tap(row);
      await settle(t, seconds: 1);
      expect(find.text('أكبر بقليل — 110٪'), findsOneWidget);
      expect(find.text('أكبر ما تتّسع له شاشتك — 121٪'), findsOneWidget);
      expect(find.byKey(const ValueKey('display-size-narrow')), findsNothing);
      await t.tap(find.byKey(const ValueKey('display-size-xlarge')));
      await settle(t, seconds: 1);
      expect(DisplaySizePref.choice.value, DisplaySize.xlarge);
      expect(await const FlutterSecureStorage().read(key: 'app.display_size.v1'), 'xlarge');
      expect(find.byType(DisplayZoom), findsOneWidget, reason: 'التطبيق كلّه مكبَّر');
      expect(find.byKey(const ValueKey('display-size-xlarge')), findsNothing, reason: 'الورقة أُغلقت');
      await t.ensureVisible(row);
      await t.pumpAndSettle();
      expect(find.descendant(of: row, matching: find.text('كبير جداً')), findsOneWidget, reason: 'الإعدادات باقيةٌ مفتوحة');
      expect(t.takeException(), isNull);
      // ورجوعاً إلى «عادي»
      await t.tap(row);
      await settle(t, seconds: 1);
      await t.tap(find.byKey(const ValueKey('display-size-normal')));
      await settle(t, seconds: 1);
      expect(find.byType(DisplayZoom), findsNothing);
      expect(await const FlutterSecureStorage().read(key: 'app.display_size.v1'), isNull);
      await drain(t);
    });

    testWidgets('مكبَّرةً «كبير جداً» على هواتف مختلفة وبخطٍّ ×1.2: الإعدادات والورقة بلا فيضٍ ولا نصٍّ مقصوص', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = 1.2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      for (final d in const [VisualDevice('_360', Size(360, 2600), 3), VisualDevice('_390', Size(390, 2600), 3), VisualDevice('_430', Size(430, 2600), 3)]) {
        DisplaySizePref.choice.value = DisplaySize.xlarge;
        await openSettings(t, d: d);
        expect(t.takeException(), isNull, reason: d.tag);
        final cut = <String>[];
        for (final e in find.byType(RichText).evaluate()) {
          final p = e.renderObject! as RenderParagraph;
          if (p.didExceedMaxLines) cut.add(p.text.toPlainText());
        }
        // صفوف الإعدادات تسمياتٌ بسطرٍ واحد بـ«…» عمداً — المهمّ صفّنا كاملاً
        await t.ensureVisible(row);
        await t.pumpAndSettle();
        expect(cut.where((x) => x.contains('حجم العرض') || x.contains('كبير جداً')), isEmpty, reason: '${d.tag}: $cut');
        await t.tap(row);
        await settle(t, seconds: 1);
        expect(t.takeException(), isNull, reason: 'الورقة ${d.tag}');
        final sheetCut = <String>[
          for (final e in find.byType(RichText).evaluate())
            if ((e.renderObject! as RenderParagraph).didExceedMaxLines) (e.renderObject! as RenderParagraph).text.toPlainText(),
        ];
        expect(sheetCut.where((x) => x.contains('أكبر') || x.contains('الحجم') || x.contains('يكبّر')), isEmpty, reason: '${d.tag}: $sheetCut');
        await drain(t);
      }
    });

    testWidgets('الحاسبة: لا صفّ «حجم العرض» (لها «حجم الواجهة»)', (t) async {
      AppPlatform.debugIsDesktop = true;
      await openSettings(t);
      expect(row, findsNothing);
      await drain(t);
    });
  });
}
