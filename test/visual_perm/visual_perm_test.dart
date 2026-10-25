import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';
import 'package:rad_mysvcs/screens/reports/package_distribution_screen.dart';
import 'package:rad_mysvcs/screens/reports/reports_hub_screen.dart';
import 'package:rad_mysvcs/screens/settings_screen.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'visual_perm_harness.dart';

/// لقطات الصلاحيّات: كلّ سيناريو × كلّ شاشة → PNG في مجلّد الإخراج.
///
///   الرئيسيّة (MainShell)       <S>_dashboard.png  (+ _dark لـS1/S2/S3، و_full بطولها، و_ipad)
///   «قوائم أخرى»               <S>_more.png
///   ورقة «+» (الإجراءات)       <S>_fab.png
///   مركز التقارير              <S>_reports.png
///   الإعدادات (من الترس)       <S>_settings.png
///   القائمتان بطولهما كاملاً    <S>_more_full.png · <S>_settings_full.png
///
/// وبجانب كلّ لقطة `<name>.requests.txt`: كلّ نداءٍ أطلقته الشاشة وردّه.
void main() {
  setUpAll(visualSetUpAll);

  /// يُفكّك الشجرة ويُفرغ المؤقّتات (تبريد الرئيسيّة ٣ث، الإشعارات…).
  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
  }

  void visualCase(
    Scenario s,
    String screen,
    Future<void> Function(WidgetTester t, VisualServer server) body,
  ) {
    testWidgets('${s.id} · $screen', (t) async {
      // ظلالٌ حقيقيّة في اللقطة (الإطار يرسمها كتلاً سوداء افتراضاً).
      debugDisableShadows = false;
      final server = await visualSetUp(s);
      try {
        await body(t, server);
        await drain(t);
      } finally {
        await visualTearDown();
        debugDisableShadows = true;
      }
    });
  }

  for (final s in allScenarios) {
    group(s.title, () {
      // ── الرئيسيّة داخل الغلاف (كما في لقطة المالك) ──
      visualCase(s, 'dashboard', (t, server) async {
        await pumpVisual(t, phone, home: (_) => const MainShell());
        await settle(t);
        await shoot(t, s, 'dashboard', phone, server);
      });

      // وضعٌ ليليّ للموظّفين والمالك — أين يقع «الفراغ» على الخلفيّة الداكنة.
      if (s.id != s1bSasOwner.id && s.id != s4SasSub.id) {
        visualCase(s, 'dashboard_dark', (t, server) async {
          await pumpVisual(t, phoneDark, home: (_) => const MainShell());
          await settle(t);
          await shoot(t, s, 'dashboard', phoneDark, server);
        });
      }

      // الرئيسيّة بطولها — ما تحت الطيّة («توزيع الباقات» #٥، آخر النشاطات).
      visualCase(s, 'dashboard_full', (t, server) async {
        await pumpVisual(t, phoneTall, home: (_) => const MainShell());
        await settle(t);
        await shoot(t, s, 'dashboard', phoneTall, server);
      });

      // «توزيع الباقات والأرباح» (#٥) — الصفحة بطولها: المالك بالكلفة والربح، والموظّف بلا مفتاحٍ يرى بوّابة القفل.
      visualCase(s, 'pkgdist', (t, server) async {
        await pumpVisual(t, phoneTall, home: (_) => const PackageDistributionScreen());
        await settle(t);
        await shoot(t, s, 'pkgdist', phoneTall, server);
      });

      visualCase(s, 'dashboard_ipad', (t, server) async {
        await pumpVisual(t, ipad, home: (_) => const MainShell());
        await settle(t);
        await shoot(t, s, 'dashboard', ipad, server);
      });

      // ── «قوائم أخرى»: نقرة التبويب في الشريط السفليّ ──
      visualCase(s, 'more', (t, server) async {
        await pumpVisual(t, phone, home: (_) => const MainShell());
        await settle(t, seconds: 2);
        await t.tap(find.text('nav.more'.tr()).last);
        await settle(t, seconds: 2);
        await shoot(t, s, 'more', phone, server);
      });

      visualCase(s, 'more_full', (t, server) async {
        await pumpVisual(t, phoneTall, home: (_) => const MainShell());
        await settle(t, seconds: 2);
        await t.tap(find.text('nav.more'.tr()).last);
        await settle(t, seconds: 2);
        await shoot(t, s, 'more', phoneTall, server);
      });

      // ── تبويب «المشتركون»: بلا subscribers.view إطارٌ مقفل بلا نداء ──
      visualCase(s, 'substab', (t, server) async {
        await pumpVisual(t, phone, home: (_) => const MainShell());
        await settle(t, seconds: 2);
        await t.tap(find.text('nav.subscribers'.tr()).last);
        await settle(t, seconds: 3);
        await shoot(t, s, 'substab', phone, server);
      });

      // ── تبويب «الأجهزة» لايرث لنك: الخانة باقية والشاشة مقفلة (لا تُبنى شاشة الأجهزة) ──
      if (s.isEl) {
        visualCase(s, 'devtab', (t, server) async {
          await pumpVisual(t, phone, home: (_) => const MainShell());
          await settle(t, seconds: 2);
          await t.tap(find.text('nav.devices'.tr()).last);
          await settle(t, seconds: 2);
          await shoot(t, s, 'devtab', phone, server);
        });
      }

      // ── ورقة «+» (الإجراءات السريعة) ──
      visualCase(s, 'fab', (t, server) async {
        await pumpVisual(t, phone, home: (_) => const MainShell());
        await settle(t, seconds: 2);
        await t.tap(find.byIcon(Icons.add_rounded).last);
        await settle(t, seconds: 2);
        await shoot(t, s, 'fab', phone, server);
      });

      // ── مركز التقارير والإعدادات: يُدفعان كصفحةٍ (سهم رجوع) كما في التطبيق ──
      visualCase(s, 'reports', (t, server) async {
        final nav = GlobalKey<NavigatorState>();
        await pumpVisual(t, phone,
            navigatorKey: nav, home: (_) => Scaffold(backgroundColor: AppColors.bg));
        await settle(t, seconds: 1);
        nav.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const ReportsHubScreen()),
        );
        await settle(t, seconds: 2);
        await shoot(t, s, 'reports', phone, server);
      });

      visualCase(s, 'settings', (t, server) async {
        final nav = GlobalKey<NavigatorState>();
        await pumpVisual(t, phone,
            navigatorKey: nav, home: (_) => Scaffold(backgroundColor: AppColors.bg));
        await settle(t, seconds: 1);
        nav.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        );
        await settle(t, seconds: 2);
        await shoot(t, s, 'settings', phone, server);
      });

      visualCase(s, 'settings_full', (t, server) async {
        final nav = GlobalKey<NavigatorState>();
        await pumpVisual(t, phoneTall,
            navigatorKey: nav, home: (_) => Scaffold(backgroundColor: AppColors.bg));
        await settle(t, seconds: 1);
        nav.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        );
        await settle(t, seconds: 2);
        await shoot(t, s, 'settings', phoneTall, server);
      });
    });
  }
}
