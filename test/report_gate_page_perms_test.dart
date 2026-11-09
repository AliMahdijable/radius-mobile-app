import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/reports/account_statement_screen.dart';
import 'package:rad_mysvcs/screens/reports/sessions_report_screen.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'emp_merged/emp_merged_fixture.dart';
import 'visual_perm/visual_perm_harness.dart';

/// مراجعة الإصدار 179 (للإصدار 180): «كل الصفحات» للموظّف — بوّابة التقرير (`ReportPermissionGate`) كانت تقرأ صلاحيّات صفحته
/// المفتوحة (`Perms.has`) لكشف حساب مشترك صفحةٍ أخرى ولسجلّ جلساته: يُمنع ما تسمح به صفحة المشترك، ويُعرض ما تمنعه. الآن
/// بصلاحيّته في صفحة المشترك (`MergedMode.can(companyKey, …)`) — خريطةٌ لكلّ صفحةٍ غير الأخرى.
void main() {
  setUpAll(visualSetUpAll);

  /// ردّ الصفحات: ألف (صفحته المفتوحة) بخريطة [openPerms] وباء بخريطة [pb].
  Map<String, Object?> body(Map<String, bool> pa, Map<String, bool> pb) {
    final c = companiesBody();
    final list = [for (final e in c['companies']! as List) Map<String, Object?>.from(e as Map)];
    list[0]['permissions'] = pa;
    list[1]['permissions'] = pb;
    return {...c, 'companies': list};
  }

  Future<void> up(WidgetTester t, {required Map<String, bool> openPerms, required Map<String, bool> pb}) async {
    await empUp(companies: body(openPerms, pb));
    // صلاحيّات صفحته المفتوحة (ألف) — PermissionsService كما يضبطها /me
    PermissionsService.debugSet(isEmployee: true, permissions: openPerms, pages: empPages);
    expect(await t.runAsync(() => MergedMode.enter()), isTrue);
    expect(MergedMode.employeeSession, isTrue);
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    await empDown();
  }

  Future<void> open(WidgetTester t, Widget screen) async {
    await pumpVisual(t, phone, home: (_) => screen);
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Finder locked() => find.text('reports.no_permission'.tr());

  const pb = {...permsB, 'reports.account_statement': true, 'reports.sessions': true};
  const pbNone = {...permsB, 'reports.account_statement': false, 'reports.sessions': false};
  const openWith = {...empKeys, 'reports.account_statement': true, 'reports.sessions': true};

  testWidgets('كشف حساب مشترك «صفحة باء»: تسمح به باء وتمنعه المفتوحة ⇒ يُعرض؛ تمنعه باء وتسمح به المفتوحة ⇒ مقفلٌ باسم باء',
      (t) async {
    await up(t, openPerms: empKeys, pb: pb);
    try {
      expect(Perms.has('reports.account_statement'), isFalse, reason: 'المفتوحة بلا كشف الحساب');
      await open(t, const AccountStatementScreen(username: 'u9', companyKey: kB));
      expect(locked(), findsNothing, reason: 'صفحة المشترك تسمح بكشف حسابه — قُرئت صلاحيّة المفتوحة');
      // خارج «كل الصفحات» أو بلا مفتاح ⇒ صفحته المفتوحة كما كان
      await open(t, const AccountStatementScreen(username: 'u1', companyKey: null));
      expect(locked(), findsOneWidget, reason: 'بلا مفتاح ⇒ صلاحيّة المفتوحة');
    } finally {
      await down(t);
    }

    await up(t, openPerms: openWith, pb: pbNone);
    try {
      await open(t, const AccountStatementScreen(username: 'u9', companyKey: kB));
      expect(locked(), findsOneWidget, reason: 'صفحة المشترك تمنع كشف حسابه — عُرض بصلاحيّة المفتوحة');
      expect(find.text(MergedMode.deniedText(MergedMode.companyOf(kB)!)), findsOneWidget, reason: 'الرفض يسمّي صفحته');
      await open(t, const AccountStatementScreen(username: 'u1', companyKey: kA));
      expect(locked(), findsNothing, reason: 'صفحته الحاليّة تسمح');
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('سجلّ جلسات مشترك «صفحة باء» (من نافذته) بصلاحيّته في باء؛ وتقرير الجلسات العامّ بصلاحيّة المفتوحة كما كان', (t) async {
    await up(t, openPerms: empKeys, pb: pb);
    try {
      await open(t, const SessionsReportScreen(initialUsername: 'u9', companyKey: kB));
      expect(locked(), findsNothing, reason: 'صفحة المشترك تسمح بسجلّ جلساته — قُرئت صلاحيّة المفتوحة');
      await open(t, const SessionsReportScreen());
      expect(locked(), findsOneWidget, reason: 'التقرير العامّ: صلاحيّة المفتوحة');
    } finally {
      await down(t);
    }

    await up(t, openPerms: openWith, pb: pbNone);
    try {
      await open(t, const SessionsReportScreen(initialUsername: 'u9', companyKey: kB));
      expect(locked(), findsOneWidget, reason: 'صفحة المشترك تمنع سجلّ جلساته — عُرض بصلاحيّة المفتوحة');
      expect(find.text(MergedMode.deniedText(MergedMode.companyOf(kB)!)), findsOneWidget);
      await open(t, const SessionsReportScreen());
      expect(locked(), findsNothing, reason: 'التقرير العامّ: المفتوحة تسمح');
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });
}
