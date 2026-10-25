import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/screens/dashboard/dashboard_screen.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/hero_revenue_card.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/packages_summary_card.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/money_tabs_card.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/subscribers_card.dart';

import 'visual_perm/visual_perm_harness.dart';

/// الرئيسيّة لموظّف ايرث لنك: الأقسام المحجوبة **تبقى في أماكنها مقفلة**.
///
/// بلاغ ٢٠٢٦-١٠-١٤ (لقطة 10.png): موظّفٌ بـ`subscribers.view` وحدها رأى
/// بطاقتين ثمّ فراغاً أبيض — الأقسام المحجوبة كانت تختفي. والمطلوب أن تبقى
/// بإطارها مقفلةً، **بلا نداء** (الخادم يردّ 403) وبلا «تعذّر الجلب».
///
/// العدّ بالنوع لا بالنصّ: مفاتيح `locked.*` قد لا تكون في ملفّ الترجمة بعد.
void main() {
  Future<VisualServer> open(WidgetTester t, Scenario s) async {
    final server = await visualSetUp(s);
    await pumpVisual(t, phone, home: (_) => const DashboardScreen());
    await settle(t);
    return server;
  }

  /// يُفكّك الشجرة ويُفرغ المؤقّتات (تبريد ٣ث، رسالة القفل…).
  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    await visualTearDown();
  }

  final allHidden =
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_AllHidden');
  final activitiesLocked = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_ActivitiesLocked');

  testWidgets('موظّف ايرث لنك بـsubscribers.view: الباقي مقفلٌ بلا نداء',
      (t) async {
    final server = await open(t, s2ElEmpSubs);

    expect(find.byType(SubscribersCard), findsOneWidget);
    // ⚠️ لا يُبنى أصلاً — `initState` فيه يُطلق `reports/finance`.
    expect(find.byType(HeroRevenueCard), findsNothing);
    // الرصيد + الإيرادات + توزيع الباقات (#٥) بطاقاتٌ مقفلة، والنشاطات إطارها المقفل.
    expect(find.byType(LockedCard), findsNWidgets(3));
    // ⚠️ لا يُبنى أصلاً — `initState` فيه يُطلق `reports/finance/packages` (يغطّيه فحص المسارات أدناه).
    expect(find.byType(PackagesSummaryCard), findsNothing);
    expect(activitiesLocked, findsOneWidget);
    // لا «الكارتات» تحت رصيده المقفل: بلا تفعيلٍ ولا تمديد لا يملك المخزون
    // (الخادم يردّه 403) — فلا نداء ملخّصٍ أصلاً (أدناه).
    expect(find.textContaining('340'), findsNothing);
    expect(
        find.byType(LockedCard).evaluate().length +
            activitiesLocked.evaluate().length,
        greaterThanOrEqualTo(3));
    expect(allHidden, findsNothing);

    // المقفل لا يكلّف نداءً.
    final paths = server.log.join('\n');
    expect(paths.contains('/api/reports/finance'), isFalse);
    expect(paths.contains('/api/activities/daily-activations'), isFalse);
    expect(paths.contains('/api/v2/admin-widgets'), isFalse);
    expect(paths.contains('/api/v2/cards/summary'), isFalse,
        reason: 'المخزون بصلاحيّة التفعيل/التمديد وحدها:\n$paths');
    expect(paths.contains('→ 403'), isFalse,
        reason: 'نداءٌ يعرف الخادم أنّه سيرفضه:\n$paths');

    // النقر على المقفل: رسالةٌ لا تنقّل.
    await t.tap(find.byType(LockedCard).first);
    await t.pump();
    await t.pump(const Duration(seconds: 3));
    expect(t.takeException(), isNull);

    await drain(t);
  });

  testWidgets(
      'موظّف ايرث لنك بلا مفاتيح: خمسة إطارات مقفلة لا «كلّ شيء مخفيّ»',
      (t) async {
    final server = await open(t, s3ElEmpNone);

    expect(allHidden, findsNothing);
    expect(find.byType(SubscribersCard), findsNothing);
    expect(find.byType(HeroRevenueCard), findsNothing);
    // المشتركون + الرصيد + المدينون + الإيرادات + توزيع الباقات، ثمّ إطار النشاطات.
    expect(find.byType(LockedCard), findsNWidgets(5));
    expect(find.byType(PackagesSummaryCard), findsNothing);
    expect(activitiesLocked, findsOneWidget);
    expect(server.log.join('\n').contains('→ 403'), isFalse,
        reason: server.log.join('\n'));

    await drain(t);
  });

  // مراجعة ٢٠٢٦-١٠-١٤: القفل كان لموظّف ايرث لنك وحده، فالمدير الفرعيّ
  // المقيَّد (بلا reports.financial) رأى «الإيرادات — تعذّر الجلب» ورصيداً
  // صفراً، بينما «قوائم أخرى» والتقارير تُريه «التقارير الماليّة» مقفلة.
  testWidgets('مدير فرعيّ ساس بلا reports.financial: الإيرادات والرصيد مقفلان',
      (t) async {
    final server = await open(t, s4SasSub);

    expect(find.byType(SubscribersCard), findsOneWidget);
    expect(find.byType(HeroRevenueCard), findsNothing);
    // الرصيد + الإيرادات + توزيع الباقات؛ والمدينون حيّ (يملك subscribers.view).
    expect(find.byType(LockedCard), findsNWidgets(3));
    expect(find.byType(PackagesSummaryCard), findsNothing);
    expect(
        find.text('dashboard.recent_activity_fetch_failed'.tr()), findsNothing);
    expect(allHidden, findsNothing);
    // سطر الكارتات باقٍ تحت الرصيد المقفل — يعمل بها ولو حُجب الرصيد.
    expect(find.textContaining('340'), findsOneWidget);

    final paths = server.log.join('\n');
    expect(paths.contains('/api/reports/finance'), isFalse, reason: paths);
    expect(paths.contains('/api/v2/admin-widgets'), isFalse, reason: paths);
    expect(paths.contains('→ 403'), isFalse, reason: paths);

    await drain(t);
  });

  testWidgets('المالك: لا قفل ولا إطار مقفل', (t) async {
    await open(t, s1Owner);

    expect(find.byType(PermLockIcon), findsNothing);
    expect(find.byType(LockedCard), findsNothing);
    expect(activitiesLocked, findsNothing);
    expect(find.byType(SubscribersCard), findsOneWidget);
    // الهاتف: الإيرادات والباقات بطاقةٌ واحدة بتبويبين (٢٥ أكتوبر) — الباقات حيّةٌ خلف تبويبها.
    expect(find.byType(MoneyTabsCard), findsOneWidget);
    expect(find.byType(HeroRevenueCard), findsOneWidget);
    expect(find.byType(PackagesSummaryCard, skipOffstage: false), findsOneWidget);

    await drain(t);
  });
}
