import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/screens/comms/comms_screen.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';
import 'package:rad_mysvcs/screens/manager_alias_sheet.dart';
import 'package:rad_mysvcs/screens/settings_screen.dart';
import 'package:rad_mysvcs/screens/view_scope_screen.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'visual_perm/visual_perm_harness.dart';

/// بلاغ ٢٠٢٦-١٠-١٤: البند المبوّب في الإعدادات وورقة «+» **يبقى بمكانه
/// مقفلاً** بدل أن يختفي — والنقر عليه رسالةٌ لا شاشةٌ ولا إغلاق شيت.
///
/// العدّ بالنوع (`PermLockIcon`) لا بالنصّ. والخادم وهميّ (عدّة اللقطات):
/// لا شبكة حقيقيّة.
void main() {
  setUpAll(visualSetUpAll);

  /// موظّف ساس بلا أيّ مفتاح — كلّ المفاتيح ممّا يُمنح له، فكلّها مقفلة.
  const sasEmpNone = Scenario(
    id: 'T_sas_emp_none',
    title: 'موظّف ساس — بلا صلاحيّات',
    actor: Actor.elEmployee,
    provider: null,
  );

  /// يُفكّك الشجرة ويُفرغ المؤقّتات (رسالة القفل، تبريد الرئيسيّة، ومهلة
  /// جلبها الحيّ ٢٠ث — الرئيسيّة لا تحجب موظّف الساس فتجلب).
  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 25));
  }

  void lockedCase(
    String name,
    Scenario s,
    Future<void> Function(WidgetTester t) body,
  ) {
    testWidgets(name, (t) async {
      await visualSetUp(s);
      try {
        await body(t);
        await drain(t);
      } finally {
        await visualTearDown();
      }
    });
  }

  Future<GlobalKey<NavigatorState>> openSettings(WidgetTester t) async {
    final nav = GlobalKey<NavigatorState>();
    await pumpVisual(t, phoneTall,
        navigatorKey: nav,
        home: (_) => Scaffold(backgroundColor: AppColors.bg));
    await settle(t, seconds: 1);
    nav.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    await settle(t, seconds: 2);
    return nav;
  }

  Future<void> openQuickAdd(WidgetTester t) async {
    await pumpVisual(t, phone, home: (_) => const MainShell());
    await settle(t, seconds: 2);
    await t.tap(find.byIcon(Icons.add_rounded).last);
    await settle(t, seconds: 2);
  }

  group('الإعدادات', () {
    lockedCase('موظّف ساس بلا مفاتيح: «واتساب وتلغرام» + نطاق العرض + الأجهزة',
        sasEmpNone, (t) async {
      await openSettings(t);
      // ١ («واتساب وتلغرام» — صفوف الواتساب الأربعة صارت بنوداً في «التواصل»، ٢٠ نوفمبر) + ١ (نطاق العرض)
      // + ١ (بيانات دخول الأجهزة) + ١ («قوالب الطباعة»: تُفتح للعرض وتعديلها مقفل)
      // + ١ («اسم المدير في السجلات» — ٢٠ نوفمبر: لصاحب الصفحة، والموظّف يراه بمكانه مقفلاً).
      expect(find.byType(PermLockIcon), findsNWidgets(5));
      final logName = find.byKey(const ValueKey('settings-log-name'));
      expect(find.descendant(of: logName, matching: find.text('اسم المدير في السجلات')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('settings-comms-row')), matching: find.byType(PermLockIcon)),
          findsOneWidget);
      // «إشعاراتي» تفضيلاته هو — بلا قفل كما كان صفّ «الإشعارات».
      expect(find.descendant(of: find.byKey(const ValueKey('settings-my-alerts')), matching: find.byType(PermLockIcon)),
          findsNothing);
      expect(t.takeException(), isNull);
    });

    lockedCase('النقر على صفٍّ مقفل لا يفتح شاشته', sasEmpNone, (t) async {
      await openSettings(t);
      // الأوّل «اسم المدير في السجلات» (تحت بطاقة الحساب): لا نافذة
      await t.ensureVisible(find.byType(PermLockIcon).first);
      await t.tap(find.byType(PermLockIcon).first);
      await t.pump(const Duration(seconds: 3));
      expect(find.byType(ManagerAliasSheet), findsNothing);

      await t.ensureVisible(find.byType(PermLockIcon).at(1));
      await t.tap(find.byType(PermLockIcon).at(1));
      await t.pump(const Duration(seconds: 3));
      expect(find.byType(CommsScreen), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);

      await t.tap(find.byType(PermLockIcon).at(2));
      await t.pump(const Duration(seconds: 3));
      expect(find.byType(ViewScopeScreen), findsNothing);
    });

    lockedCase('موظّف ايرث لنك: لا قسم واتساب ولا عرض ولا أجهزة (لا تُمنح)',
        s3ElEmpNone, (t) async {
      await openSettings(t);
      // «واتساب وتلغرام» وحدها مقفلة بمكانها: فيها «حالة الرسائل» (مفتاحها يُمنح له) كبطاقتها في «قوائم أخرى» —
      // لا حالة الواتساب ولا قوالبه ولا جدولته ولا تلغرام (لا تُمنح لدوره)، ولا عرض ولا أجهزة.
      // + «اسم المدير في السجلات» مقفلاً (لصاحب الحساب — كالموقع للموظّف).
      expect(find.byType(PermLockIcon), findsNWidgets(2));
      expect(find.descendant(of: find.byKey(const ValueKey('settings-comms-row')), matching: find.byType(PermLockIcon)),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('settings-log-name')), matching: find.byType(PermLockIcon)),
          findsOneWidget);
      expect(buildCommsEntries().map((e) => e.module.id), ['message_logs']);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    lockedCase('المالك: لا قفل', s1bSasOwner, (t) async {
      await openSettings(t);
      expect(find.byType(PermLockIcon), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('settings-log-name')), matching: find.text('اسمك في السجلات')),
          findsOneWidget);
    });
  });

  group('ورقة «+» (الإضافة السريعة)', () {
    // الأقفال داخل الشيت وحده: الرئيسيّة خلفه صارت تُبقي أقسامها مقفلةً
    // بمكانها أيضاً (بطاقات LockedCard)، فالعدّ على الشجرة كلّها يخلطهما.
    Finder sheetLocks() => find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(PermLockIcon),
        );

    lockedCase('موظّف بلا مفاتيح: البنود الخمسة مقفلة بمكانها', s3ElEmpNone,
        (t) async {
      await openQuickAdd(t);
      expect(sheetLocks(), findsNWidgets(5));
      expect(find.text('dashboard.quick_add_empty'), findsNothing);
    });

    lockedCase('النقر على بندٍ مقفل لا يغلق الشيت', sasEmpNone, (t) async {
      await openQuickAdd(t);
      expect(sheetLocks(), findsNWidgets(5));
      await t.tap(sheetLocks().first);
      await t.pump(const Duration(seconds: 3));
      // الشيت باقٍ ببنوده — لا `Navigator.pop` ولا منتقٍ ولا شيت إضافة.
      expect(sheetLocks(), findsNWidgets(5));
    });

    lockedCase('موظّف ايرث لنك بـsubscribers.add وحدها: أربعة مقفلة',
        const Scenario(
          id: 'T_el_emp_add',
          title: 'موظّف ايرث لنك — subscribers.add',
          actor: Actor.elEmployee,
          provider: 'earthlink',
          keys: {'subscribers.view': true, 'subscribers.add': true},
        ), (t) async {
      await openQuickAdd(t);
      expect(sheetLocks(), findsNWidgets(4));
    });

    lockedCase('المالك: لا قفل', s1Owner, (t) async {
      await openQuickAdd(t);
      expect(sheetLocks(), findsNothing);
      // الشيت مفتوحٌ فعلاً ببنوده الخمسة وسهامها كما كانت.
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNWidgets(5));
    });
  });
}
