// جولة تصميم الحاسبة: التطبيق كلّه بمقاس 1440×900 على الخادم الوهميّ للقطات الصلاحيّات، كلّ صفحةٍ لقطة
// (فاتح + داكن) — لمراجعة التصميم دون حسابٍ حقيقيّ. لا تجري مع الحزمة: تُشغَّل يدويّاً
//
//   DESKTOP_TOUR=1 flutter test test/desktop_tour/desktop_tour_test.dart
//
// واللقطات في `build/desktop_tour/` (أو VISUAL_OUT).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/core/platform/desktop_layout.dart';
import 'package:rad_mysvcs/screens/account/account_login_screen.dart';
import 'package:rad_mysvcs/screens/app_modules.dart';
import 'package:rad_mysvcs/screens/login_screen.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import '../sim_el/sim_harness.dart' show simTheme, SimDiskLoader;
import '../visual_perm/visual_perm_harness.dart';

const _size = Size(1440, 900);
const _dpr = 1.25;
const _rootKey = ValueKey<String>('desk-tour-root');

String _outDir() {
  final env = Platform.environment['VISUAL_OUT'] ?? '';
  return env.isNotEmpty ? env : '${Directory.current.path}/build/desktop_tour';
}

Future<void> _pump(WidgetTester t, {required bool dark, required WidgetBuilder home, bool authFrame = false}) async {
  t.view.physicalSize = _size * _dpr;
  t.view.devicePixelRatio = _dpr;
  t.view.padding = FakeViewPadding.zero;
  t.view.viewPadding = FakeViewPadding.zero;
  t.platformDispatcher.platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
  AppColors.setDarkMode(dark);
  addTearDown(() => AppColors.setDarkMode(false));
  await t.pumpWidget(RepaintBoundary(
    key: _rootKey,
    child: EasyLocalization(
      supportedLocales: const [Locale('ar'), Locale('en')],
      path: 'assets/translations',
      startLocale: const Locale('ar'),
      fallbackLocale: const Locale('ar'),
      saveLocale: false,
      assetLoader: const SimDiskLoader(),
      child: Builder(
        builder: (ctx) => MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          theme: simTheme(Brightness.light),
          darkTheme: simTheme(Brightness.dark),
          locale: ctx.locale,
          supportedLocales: ctx.supportedLocales,
          localizationsDelegates: ctx.localizationDelegates,
          // كإطار main.dart على الحاسبة قبل الغلاف: الشاشات ترسم لوحة العلامة بنفسها.
          builder: (context, child) =>
              authFrame ? DeskAuthScope(child: child ?? const SizedBox.shrink()) : child ?? const SizedBox.shrink(),
          home: Builder(builder: home),
        ),
      ),
    ),
  ));
}

Future<void> _shot(WidgetTester t, String name) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(_rootKey));
  final png = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final f = File('${_outDir()}/$name.png');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(png!, flush: true);
}

/// ينقر عنصر القائمة الجانبيّة — يمرّرها حتى يظهر (القائمة تبني الظاهر وحده)، وأوّل نصٍّ مطابق لأنّ
/// القائمة قبل المحتوى في الشجرة.
Future<void> _nav(WidgetTester t, String title) async {
  final list = find.byKey(const ValueKey('desk-sidebar'));
  final sidebar = find.descendant(of: list, matching: find.byType(Scrollable)).first;
  final item = find.descendant(of: list, matching: find.text(title));
  // لأعلى أوّلاً (العنصر قد يكون فوق ما مُرِّر إليه)، ثمّ لأسفل.
  await t.drag(sidebar, const Offset(0, 3000), warnIfMissed: false);
  await t.pump();
  for (var k = 0; k < 30 && item.evaluate().isEmpty; k++) {
    await t.drag(sidebar, const Offset(0, -120), warnIfMissed: false);
    await t.pump();
  }
  // وسط القائمة لا طرفها — نقرةٌ على عنصرٍ مقصوصٍ أسفلها تقع على «طيّ القائمة».
  await t.runAsync(() => Scrollable.ensureVisible(item.evaluate().first, alignment: 0.5));
  await t.pump();
  await t.tap(item.first, warnIfMissed: false);
  await settle(t, seconds: 3);
}

void main() {
  if (Platform.environment['DESKTOP_TOUR'] != '1') return;
  setUpAll(visualSetUpAll);

  for (final dark in [false, true]) {
    final tag = dark ? '_dark' : '';

    testWidgets('shell pages$tag', (t) async {
      debugDisableShadows = false;
      AppPlatform.debugIsDesktop = true;
      await visualSetUp(s1bSasOwner);
      try {
        await _pump(t, dark: dark, home: (_) => const MainShell());
        await settle(t, seconds: 6);
        await _shot(t, '01_dashboard$tag');

        await _nav(t, 'nav.subscribers'.tr());
        await _shot(t, '02_subscribers$tag');
        // لوحة التفاصيل: أوّل صفّ.
        await t.tap(find.text('علي حسن الموسوي').first, warnIfMissed: false);
        await settle(t, seconds: 3);
        await _shot(t, '03_subscriber_pane$tag');

        await _nav(t, 'nav.devices'.tr());
        await _shot(t, '04_devices$tag');

        var i = 5;
        for (final m in buildAppModules()) {
          if (m.locked || m.unavailable != null) continue;
          try {
            await _nav(t, m.title);
          } catch (e) {
            // ignore: avoid_print
            print('tour: skip ${m.id} (${m.title}): $e');
            t.takeException();
            continue;
          }
          await _shot(t, '${(i++).toString().padLeft(2, '0')}_${m.id}$tag');
        }
        await _nav(t, 'settings.title'.tr());
        await _shot(t, '${i.toString().padLeft(2, '0')}_settings$tag');

        // النوافذ والطبقات فوق الغلاف.
        await _nav(t, 'nav.subscribers'.tr());
        await t.tap(find.text('desktop.new_subscriber'.tr()).first, warnIfMissed: false);
        await settle(t, seconds: 3);
        await _shot(t, '80_dialog_add_subscriber$tag');
        await t.tapAt(const Offset(40, 860));
        await settle(t, seconds: 2);

        await t.tap(find.text('desktop.search_hint'.tr()).first, warnIfMissed: false);
        await settle(t, seconds: 2);
        await t.enterText(find.byType(TextField).last, 'علي');
        await settle(t, seconds: 2);
        await _shot(t, '81_quick_search$tag');
        await t.tapAt(const Offset(40, 860));
        await settle(t, seconds: 2);

        await t.tap(find.byKey(const ValueKey('top-actions-notifications')), warnIfMissed: false);
        await settle(t, seconds: 3);
        await _shot(t, '82_notifications$tag');
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 6));
        await visualTearDown();
        AppPlatform.debugIsDesktop = null;
        debugDisableShadows = true;
      }
    });

    testWidgets('start screens$tag', (t) async {
      debugDisableShadows = false;
      AppPlatform.debugIsDesktop = true;
      await visualSetUp(s1bSasOwner);
      try {
        await _pump(t, dark: dark, home: (_) => const AccountLoginScreen(), authFrame: true);
        await settle(t, seconds: 2);
        await _shot(t, '90_account_login$tag');
        // نافذةٌ منبثقة فوق شاشة البداية: تغطّي النافذة كلّها لا عمود النموذج.
        final ctx = t.element(find.byType(AccountLoginScreen));
        showDialog<void>(
          context: ctx,
          builder: (_) => const AlertDialog(title: Text('تسجيل الخروج من الحساب'), content: Text('تجربة')),
        );
        await settle(t, seconds: 1);
        await _shot(t, '92_start_dialog$tag');
        Navigator.of(ctx).pop();
        await settle(t, seconds: 1);
        await _pump(t, dark: dark, home: (_) => const LoginScreen(), authFrame: true);
        await settle(t, seconds: 3);
        await _shot(t, '91_sas_login$tag');
      } finally {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 6));
        await visualTearDown();
        AppPlatform.debugIsDesktop = null;
        debugDisableShadows = true;
      }
    });
  }
}
