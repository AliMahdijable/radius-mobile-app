import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/theme/colors.dart';
import 'package:rad_mysvcs/theme/spacing.dart';

import '../sim_el/sim_harness.dart' show simTheme;
import 'visual_perm_harness.dart' show visualSetUpAll, visualOutDir;

// معاينة مكوّنات القفل الموحّد — أداة مراجعة بصريّة لا اختبار يُشحن.
// تدمج مفاتيح `locked.*` المقترحة فوق ملفّ الترجمة إن لم تُدمج بعد.
const _ar = {
  'toast': 'ليس لديك صلاحيّة لهذا القسم — اطلبها من مديرك',
  'toast_action': 'ليس لديك صلاحيّة لهذا الإجراء — اطلبها من مديرك',
  'badge': 'مقفل',
  'short': 'لا صلاحيّة للعرض',
  'view': 'ليس لديك صلاحيّة لعرض هذا القسم',
  'ask': 'اطلبها من مديرك',
  'a11y': '{} — مقفل',
};

class _Loader extends AssetLoader {
  const _Loader();
  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    final m = jsonDecode(File('assets/translations/${locale.languageCode}.json')
        .readAsStringSync()) as Map<String, dynamic>;
    m['locked'] ??= _ar;
    return m;
  }
}

void main() {
  setUpAll(visualSetUpAll);

  for (final dark in [false, true]) {
    testWidgets('locked preview ${dark ? 'dark' : 'light'}', (t) async {
      t.view.physicalSize = const Size(430, 1100) * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      AppColors.setDarkMode(dark);
      addTearDown(() => AppColors.setDarkMode(false));
      const key = ValueKey('root');
      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: EasyLocalization(
          supportedLocales: const [Locale('ar')],
          path: 'x',
          startLocale: const Locale('ar'),
          saveLocale: false,
          assetLoader: const _Loader(),
          child: Builder(
            builder: (ctx) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: simTheme(dark ? Brightness.dark : Brightness.light),
              locale: ctx.locale,
              supportedLocales: ctx.supportedLocales,
              localizationsDelegates: ctx.localizationDelegates,
              home: Scaffold(
                backgroundColor: AppColors.bg,
                body: Builder(builder: (c) {
                  return ListView(
                    padding: const EdgeInsets.all(Sp.lg),
                    children: [
                      const LockedCard(
                        title: 'المشتركون',
                        icon: LucideIcons.users,
                        block: true,
                        height: 285,
                        radius: R.card,
                        padding: EdgeInsets.all(Sp.xl),
                      ),
                      const SizedBox(height: Sp.md),
                      const IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                                child: LockedCard(
                                    title: 'الرصيد',
                                    icon: LucideIcons.wallet)),
                            SizedBox(width: Sp.md),
                            Expanded(
                                child: LockedCard(
                                    title: 'المدينون',
                                    icon: LucideIcons.creditCard)),
                          ],
                        ),
                      ),
                      const SizedBox(height: Sp.md),
                      const LockedCard(title: 'الإيرادات'),
                      const SizedBox(height: Sp.md),
                      const LockedCard(
                          title: 'آخر النشاطات',
                          icon: LucideIcons.activity,
                          block: true),
                      const SizedBox(height: Sp.md),
                      Row(children: [
                        PermLockBadge(
                          child: Icon(LucideIcons.calendarPlus,
                              size: 22, color: AppColors.textHint),
                        ),
                        const SizedBox(width: Sp.xl),
                        PermissionLocked(
                          locked: true,
                          label: 'تذكير',
                          child: FilledButton(
                              onPressed: () {}, child: const Text('تذكير')),
                        ),
                        const SizedBox(width: Sp.xl),
                        const PermLockIcon(),
                      ]),
                      const SizedBox(height: Sp.md),
                      Builder(
                        builder: (bc) => TextButton(
                          key: const ValueKey('tap'),
                          onPressed: () => showNoPermission(bc),
                          child: const Text('tap'),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.tap(find.byKey(const ValueKey('tap')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(PermLockIcon), findsWidgets);
      final b = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final png = await t.runAsync(() async {
        final img = await b.toImage(pixelRatio: 2);
        final d = await img.toByteData(format: ui.ImageByteFormat.png);
        return d!.buffer.asUint8List();
      });
      final f = File('${visualOutDir()}/locked_preview${dark ? '_dark' : ''}.png');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(png!);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 3));
    });
  }
}
