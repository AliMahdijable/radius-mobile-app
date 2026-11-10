import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/dashboard_api.dart';
import 'package:rad_mysvcs/api/merged_dashboard_api.dart';
import 'package:rad_mysvcs/core/util/bidi.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/models/dashboard.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/desktop_overview.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/stats_grid.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/merged_rows.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/widgets/merged_balance_lines.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sim_el/sim_harness.dart' show SimVariant, pumpSim, simSetUpAll;

/// «المدينون — لكلّ شركة» (١٠ نوفمبر — المالك: «حبي ضيف وياك فصل دين الشركه بوضع الشركات يعني ديون المشتركين حسب
/// الشركه» ثمّ «وهنت بالاعلى الدين الكلي مجموعهن»): في «كل الشركات» و«الكل» المجموع أعلى بطاقة المدينين ثمّ سطرٌ لكلّ
/// شركة؛ المجموع = جمع الأسطر التي لها مبلغ، ومن لا تُقرأ ديونها تُسمّى بسببها ولا تُجمع (لا صفرٌ صامت)، والمشترك يُعدّ
/// مرّةً بقاعدة الدمج نفسها، وبلا طلب.
const _kA = 'c0000000000a1';
const _kB = 'c0000000000b2';
const _kC = 'c0000000000c3';
const _kF = 'c0000000000f4';
const _kD = 'c0000000000d5';
const _kE = 'c0000000000e6';
const _kU = 'c0000000000a6';
const _kP = 'c0000000000a7';
const _kN = 'c0000000000a8';
const _kX = 'c0000000000a9';

MergedCompany _co(
  String key,
  String name,
  int index, {
  String? user,
  String? ns,
  String? adminId,
  String? currency = 'IQD',
  MergedProvider provider = MergedProvider.sas4,
  MergedStatus status = MergedStatus.ok,
}) =>
    MergedCompany(
      key: key,
      code: 'x',
      username: user ?? 'admin@$index',
      name: name,
      provider: provider,
      colorIndex: index,
      adminId: adminId ?? '$index',
      ns: ns ?? 'ns$index',
      currency: currency,
      home: index == 0,
      status: status,
      index: index,
    );

Subscriber _s(String idx, {String parent = '', String debt = '', bool abandoned = false}) => Subscriber(
      idx: idx,
      username: 'u$idx',
      firstname: 'مشترك',
      lastname: idx,
      parentUsername: parent,
      profileName: abandoned ? null : 'Gold',
      expiration: abandoned ? null : '2026-12-01 00:00:00',
      notes: debt.isEmpty ? null : debt,
    );

/// كدمج MergedSubscribers نفسه (_combine): الصفوف من القوائم التي وصلت، والبقيّة بحالها.
MergedListResult _result(List<MergedCompanyList> parts, {List<MergedCompany> missing = const []}) => MergedListResult(
      rows: mergeRows([
        for (final p in parts)
          if (p.rows != null) MergePart(company: p.company, rows: p.rows!, partial: p.partial),
      ]),
      parts: parts,
      missing: missing,
    );

int _shownSum(MergedDebts d) => d.lines.fold(0, (n, l) => n + (l.amount ?? 0));

DebtorsResult _debtors(int count, int total) => DebtorsResult(
      count: count,
      total: total,
      nearExpiry: 0,
      online: 3,
      offline: 1,
      active: 4,
      expired: 1,
      totalSubs: 5,
      onlineNoPlan: 0,
      disabled: 0,
    );

void main() {
  tearDown(() {
    PermissionsService.debugReset();
    MergedMode.reset();
  });

  group('الحساب (MergedDashboardApi.debtsByCompany)', () {
    test('(أ) شركتان بديونهما: المجموع = جمع السطرين، وكلٌّ بمبلغه وعدده — بتعريف debtorsFrom حرفاً', () {
      final a = _co(_kA, 'ألف', 0);
      final b = _co(_kB, 'باء', 1);
      final r = _result([
        MergedCompanyList(company: a, rows: [
          _s('1', debt: '-5000'),
          _s('2', debt: '-1,500'),
          _s('3'),
          _s('4', debt: '-9000', abandoned: true),
          _s('5', debt: '2000'),
        ]),
        MergedCompanyList(company: b, rows: [_s('1', debt: '-2500'), _s('2')]),
      ]);
      final d = MergedDashboardApi.debtsByCompany(r);
      expect(d.lines, [
        (key: _kA, amount: 6500, count: 2, reason: null),
        (key: _kB, amount: 2500, count: 1, reason: null),
      ], reason: 'المهمَل والرصيد الموجب (له لا عليه) خارج الدين؛ idx 1 في ساسين مختلفين ⇒ مشتركان');
      expect(d.total, 9000);
      expect(d.count, 3);
      expect(d.total, _shownSum(d));
      final today = MergedDashboardApi.debtorsFrom(r.rows);
      expect((d.total, d.count), (today.total, today.count), reason: 'كلّها داخلة ⇒ رقم بطاقة اليوم نفسه');
      expect(d.any, isTrue);
      expect(d.leftNote((k) => k), isNull, reason: 'لا «بلا» حين تدخل كلّها');
    });

    test('مشتركٌ تراه صفحتان مربوطتان يُعدّ مرّةً تحت الأقرب إليه، وربطٌ ثانٍ للمدير نفسه بلا سطر', () {
      final a = _co(_kA, 'ألف', 0, user: 'admin@a', ns: 'n1');
      final b = _co(_kB, 'باء', 1, user: 'admin@b', ns: 'n1');
      final a2 = _co(_kX, 'ألف · ثانٍ', 2, user: 'admin@a', ns: 'n1', adminId: '0');
      final aRows = [_s('1', parent: 'admin@a', debt: '-1000'), _s('2', parent: 'admin@b', debt: '-4000')];
      final r = _result([
        MergedCompanyList(company: a, rows: aRows),
        MergedCompanyList(company: b, rows: [_s('2', parent: 'admin@b', debt: '-4000')]),
        MergedCompanyList(company: a2, rows: aRows),
      ]);
      final d = MergedDashboardApi.debtsByCompany(r);
      expect(d.lines, [
        (key: _kA, amount: 1000, count: 1, reason: null),
        (key: _kB, amount: 4000, count: 1, reason: null),
      ], reason: 'الصفّ 2 تحت باء (مديره المباشر)، والربط الثاني لمدير ألف قائمته قائمتها');
      expect(d.total, 5000, reason: 'لا 9000 ولا 10000');
      expect(d.total, MergedDashboardApi.debtorsFrom(r.rows).total);
    });

    test('(ب) شركةٌ لا تُقرأ ديونها تُسمّى بسببها وتبقى خارج المجموع — والمجموع جمع الأسطر التي لها مبلغ', () {
      final a = _co(_kA, 'ألف', 0);
      final b = _co(_kB, 'باء', 1);
      final c = _co(_kC, 'كبيرة', 2);
      final f = _co(_kF, 'كلاود ساس', 3);
      final dl = _co(_kD, 'تحتاج دخول', 4, status: MergedStatus.needsLogin);
      final e = _co(_kE, 'ايرث لنك', 5, provider: MergedProvider.earthlink);
      final u = _co(_kU, 'بالدولار', 6, currency: 'USD');
      final p = _co(_kP, 'ناقصة', 7);
      final n = _co(_kN, 'الوطني', 8, provider: MergedProvider.ftth);
      // ربطٌ ثانٍ لمدير ألف يحتاج دخولاً: ديونه تحت ألف — لا «بلا» له
      final x = _co(_kX, 'ألف · ثانٍ', 9, adminId: '0', ns: 'ns0', status: MergedStatus.needsLogin);
      final r = _result([
        MergedCompanyList(company: a, rows: [_s('1', debt: '-5000')]),
        MergedCompanyList(company: b, rows: [_s('1', debt: '-2500')]),
        MergedCompanyList(company: c, bigTotal: 89217),
        MergedCompanyList(company: f, error: 'تعذّر جلب مشتركي «كلاود ساس» الآن'),
        MergedCompanyList(company: e, rows: [_s('1', debt: '-7000')], debtsUnavailable: true),
        MergedCompanyList(company: u, rows: [_s('1', debt: '-30')]),
        MergedCompanyList(company: p, rows: [_s('1', debt: '-1000')], partial: true),
      ], missing: [dl, n, x]);
      final d = MergedDashboardApi.debtsByCompany(r);
      expect(d.lines, [
        (key: _kA, amount: 5000, count: 1, reason: null),
        (key: _kB, amount: 2500, count: 1, reason: null),
        (key: _kC, amount: null, count: null, reason: 'كبيرة، افتحها وحدها'),
        (key: _kF, amount: null, count: null, reason: 'تعذّرت قراءة ديونها'),
        (key: _kD, amount: null, count: null, reason: 'تحتاج دخول'),
        (key: _kE, amount: null, count: null, reason: 'تعذّرت قراءة ديونها'),
        (key: _kU, amount: null, count: null, reason: 'عملتها USD'),
        (key: _kP, amount: null, count: null, reason: 'قائمتها ناقصة من مزوّدها'),
        (key: _kN, amount: null, count: null, reason: 'ديونها لا تُجمع هنا بعد'),
      ]);
      expect(d.total, 7500, reason: 'ألف + باء وحدهما — لا 7000 ايرث لنك (دفترها لم يُقرأ) ولا الدولار ولا الناقصة');
      expect(d.count, 2);
      expect(d.total, _shownSum(d));
      expect(d.left.map((l) => l.key), [_kC, _kF, _kD, _kE, _kU, _kP, _kN]);
      String name(String k) => [a, b, c, f, dl, e, u, p, n, x].firstWhere((co) => co.key == k).name;
      expect(d.leftNote(name), 'بلا 7 شركات — السبب بجانب كلٍّ منها', reason: 'ثلاثٌ فأكثر بعددها — سطرٌ قصير');
      // شركةٌ واحدة خارجه: اسمها (معزول الاتّجاه) وسببها
      final one = MergedDashboardApi.debtsByCompany(_result([
        MergedCompanyList(company: a, rows: [_s('1', debt: '-5000')]),
        MergedCompanyList(company: f, error: 'x'),
      ]));
      expect(one.leftNote(name), 'بلا «${iso('كلاود ساس')}» — تعذّرت قراءة ديونها');
      // شركتان بسببٍ واحد: باسميهما وسببهما
      final two = MergedDashboardApi.debtsByCompany(_result([
        MergedCompanyList(company: a, rows: [_s('1', debt: '-5000')]),
        MergedCompanyList(company: f, error: 'x'),
        MergedCompanyList(company: e, rows: [_s('1', debt: '-7000')], debtsUnavailable: true),
      ]));
      expect(two.leftNote(name), 'بلا «${iso('كلاود ساس')}»، «${iso('ايرث لنك')}» — تعذّرت قراءة ديونها');
      expect(one.total, 5000);
    });

    test('قائمة أختٍ على الساس نفسه تعذّرت: دين الصفحة لا يُجمع ويُقال لماذا — والكبيرة والمرفوضة لا تحجبان', () {
      final a = _co(_kA, 'ألف', 0, ns: 'n1');
      final f = _co(_kF, 'فاء', 1, ns: 'n1', user: 'admin@f');
      final rows = MergedCompanyList(company: a, rows: [_s('1', debt: '-5000')]);
      final blocked = MergedDashboardApi.debtsByCompany(_result([rows, MergedCompanyList(company: f, error: 'x')]));
      expect(blocked.lines.first,
          (key: _kA, amount: null, count: null, reason: 'تعذّرت قائمة «${iso('فاء')}» المرتبطة بها'));
      expect(blocked.any, isFalse, reason: 'لا شركة دخلت ⇒ لا رقم («—» لا «٠»)');
      expect(blocked.total, 0);
      for (final other in [
        MergedCompanyList(company: f, bigTotal: 6000),
        MergedCompanyList(company: f, denied: true, error: 'لا صلاحيّة'),
      ]) {
        final d = MergedDashboardApi.debtsByCompany(_result([rows, other]));
        expect(d.lines.first, (key: _kA, amount: 5000, count: 1, reason: null));
      }
    });

    test('«كل الصفحات» للموظّف: الأسباب بكلمته («صفحاتي»، «مديرها»، «لا صلاحيّة»)', () {
      PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
      final d = MergedDashboardApi.debtsByCompany(_result([
        MergedCompanyList(company: _co(_kA, 'ألف', 0), rows: [_s('1', debt: '-5000')]),
        MergedCompanyList(company: _co(_kC, 'كبيرة', 1), bigTotal: 6000),
        MergedCompanyList(company: _co(_kF, 'مرفوضة', 2), denied: true, error: 'x'),
      ], missing: [_co(_kD, 'تحتاج دخول', 3, status: MergedStatus.needsLogin)]));
      expect(d.lines.map((l) => l.reason).toList(), [
        null,
        'كبيرة، انتقل إليها من «صفحاتي»',
        'لا صلاحيّة لك على مشتركيها',
        'تحتاج دخول مديرها',
      ]);
    });
  });

  group('البطاقة', () {
    setUpAll(() async {
      await simSetUpAll();
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });

    // أسماءٌ طويلة كحسابات المالك («سوبرنت (SuperNet) · admin@…») ومبلغٌ كبير — ما يفيض إن فاض
    final companies = [
      _co(_kA, 'سوبرنت (SuperNet) · admin@supernet-baghdad-center-01', 0),
      _co(_kB, 'شركة الجزيرة للاتصالات والإنترنت الفضائيّ', 1),
      _co(_kC, 'سوبرنت (SuperNet) · admin@full', 2),
      _co(_kF, 'كلاود ساس CloudSaaS الرئيسيّة', 3),
      _co(_kD, 'نبض', 4, status: MergedStatus.needsLogin),
    ];
    MergedDebts split() => MergedDashboardApi.debtsByCompany(_result([
          MergedCompanyList(company: companies[0], rows: [_s('1', debt: '-123456789'), _s('2', debt: '-5000')]),
          MergedCompanyList(company: companies[1], rows: [_s('1', debt: '-2500')]),
          MergedCompanyList(company: companies[2], bigTotal: 89217),
          MergedCompanyList(company: companies[3], error: 'x'),
        ], missing: [companies[4]]));
    void seed() => MergedMode.data.value = MergedCompaniesData(routing: true, writes: true, companies: companies);
    const List<MergedBalanceLine> walletLines = [
      (key: _kA, balance: 150000, reason: null),
      (key: _kB, balance: -20000, reason: null),
      (key: _kC, balance: null, reason: 'تعذّرت قراءة الرصيد'),
    ];

    for (final v in const [
      SimVariant(320, dark: false),
      SimVariant(320, dark: true),
      SimVariant(390, dark: false),
      SimVariant(390, dark: true),
    ]) {
      testWidgets('(د) الهاتف @${v.tag}: المجموع أعلاه ثمّ خانةٌ لكلّ شركة بجانب خانات الرصيد — بلا فيض', (t) async {
        seed();
        var taps = 0;
        await pumpSim(t, v,
            home: (_) => Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: StatsGrid(
                      wallet: const WalletResult(balance: 130000, points: 0),
                      walletLines: walletLines,
                      debtors: _debtors(3, 123464289),
                      debtSplit: split(),
                      onOpenDebtors: () => taps++,
                    ),
                  ),
                ));
        expect(t.takeException(), isNull, reason: 'لا فيض ولا استثناء @${v.tag}');
        expect(find.text('الرصيد — لكلّ شركة'), findsOneWidget);
        expect(find.text('المدينون — لكلّ شركة'), findsOneWidget, reason: 'البطاقتان زوج');
        final card = find.byKey(const ValueKey('merged-debt-card'));
        expect(find.descendant(of: card, matching: find.text('123,464,289')), findsOneWidget,
            reason: 'المجموع أعلاه = 123,456,789 + 5,000 + 2,500');
        expect(find.descendant(of: card, matching: find.text('3 مشترك · مجموع الشركات')), findsOneWidget);
        Finder tile(String k) => find.byKey(ValueKey('merged-debt-$k'));
        expect(find.descendant(of: tile(_kA), matching: find.text('123,461,789')), findsOneWidget);
        expect(find.descendant(of: tile(_kA), matching: find.text('2 مشترك')), findsOneWidget);
        expect(find.descendant(of: tile(_kB), matching: find.text('2,500')), findsOneWidget);
        expect(find.descendant(of: tile(_kB), matching: find.text('1 مشترك')), findsOneWidget);
        expect(find.descendant(of: tile(_kC), matching: find.text('كبيرة، افتحها وحدها')), findsOneWidget);
        expect(find.descendant(of: tile(_kF), matching: find.text('تعذّرت قراءة ديونها')), findsOneWidget);
        expect(find.descendant(of: tile(_kD), matching: find.text('تحتاج دخول')), findsOneWidget);
        expect(
            find.descendant(
                of: find.byKey(const ValueKey('merged-debt-note')),
                matching: find.text('بلا 3 شركات — السبب بجانب كلٍّ منها')),
            findsOneWidget,
            reason: 'من خارج المجموع بسطرٍ واحد تحته');
        // النقر كما كان: المشتركون بفلتر المدينين
        await t.tap(find.text('المدينون — لكلّ شركة'));
        expect(taps, 1);
      });
    }

    testWidgets('(ج) شركةٌ مختارة في الشريط (لا تقسيم): بطاقة المدينين الواحدة كما هي', (t) async {
      seed();
      await pumpSim(t, const SimVariant(390, dark: false),
          home: (_) => Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StatsGrid(
                    wallet: const WalletResult(balance: 50000, points: 0),
                    debtors: _debtors(1, 2500),
                  ),
                ),
              ));
      expect(t.takeException(), isNull);
      expect(find.text('المدينون'), findsOneWidget);
      expect(find.text('2,500'), findsOneWidget);
      expect(find.text('1 مشترك'), findsOneWidget);
      expect(find.byKey(const ValueKey('merged-debt-lines')), findsNothing);
      expect(find.byKey(const ValueKey('merged-debt-card')), findsNothing);
      expect(find.textContaining('لكلّ شركة'), findsNothing);
    });

    testWidgets('لا شركة دخلت المجموع: «—» لا «٠ IQD»، والسبب بسطره', (t) async {
      final a = _co(_kA, 'ألف', 0, ns: 'n1');
      final f = _co(_kF, 'فاء', 1, ns: 'n1', user: 'admin@f');
      MergedMode.data.value = MergedCompaniesData(routing: true, writes: true, companies: [a, f]);
      final d = MergedDashboardApi.debtsByCompany(_result([
        MergedCompanyList(company: a, rows: [_s('1', debt: '-5000')]),
        MergedCompanyList(company: f, error: 'x'),
      ]));
      await pumpSim(t, const SimVariant(320, dark: false),
          home: (_) => Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StatsGrid(wallet: null, debtors: _debtors(1, 5000), debtSplit: d, balanceLocked: true),
                ),
              ));
      expect(t.takeException(), isNull);
      final card = find.byKey(const ValueKey('merged-debt-card'));
      expect(find.descendant(of: card, matching: find.text('—')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining('IQD')), findsNothing);
      expect(find.text('5,000'), findsNothing, reason: 'دين ألف لا يُعرض: قد يكون فيه مشتركو فاء');
      expect(find.text('بلا «${iso('ألف')}»، «${iso('فاء')}» — السبب بجانب كلٍّ منها'), findsOneWidget);
      expect(find.byType(LockedCard), findsOneWidget, reason: 'الرصيد المقفل بمكانه فوقها');
    });

    testWidgets('«كل الصفحات» للموظّف: «لكلّ صفحة» و«مجموع الصفحات» — لا كلمة «شركة» في البطاقة', (t) async {
      PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
      final a = _co(_kA, 'صفحة ألف', 0);
      final b = _co(_kB, 'صفحة باء', 1);
      MergedMode.data.value = MergedCompaniesData(routing: true, writes: true, companies: [a, b]);
      final d = MergedDashboardApi.debtsByCompany(_result([
        MergedCompanyList(company: a, rows: [_s('1', debt: '-5000')]),
        MergedCompanyList(company: b, bigTotal: 6000),
      ]));
      await pumpSim(t, const SimVariant(320, dark: true),
          home: (_) => Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StatsGrid(wallet: null, debtors: _debtors(1, 5000), debtSplit: d, balanceLocked: true),
                ),
              ));
      expect(t.takeException(), isNull);
      expect(find.text('المدينون — لكلّ صفحة'), findsOneWidget);
      expect(find.text('1 مشترك · مجموع الصفحات'), findsOneWidget);
      expect(find.textContaining('انتقل إليها من «صفحاتي»'), findsWidgets);
      final words = t
          .widgetList<Text>(
              find.descendant(of: find.byKey(const ValueKey('merged-debt-card')), matching: find.byType(Text)))
          .map((w) => w.data ?? '')
          .join(' | ');
      expect(words.contains('شركة') || words.contains('الشركات'), isFalse, reason: words);
    });

    testWidgets('المدينون مقفلون (بلا subscribers.view): القفل بمكانه ولا خانات', (t) async {
      seed();
      await pumpSim(t, const SimVariant(390, dark: false),
          home: (_) => Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StatsGrid(
                      wallet: const WalletResult(balance: 50000, points: 0),
                      debtors: null,
                      debtSplit: split(),
                      debtLocked: true),
                ),
              ));
      expect(t.takeException(), isNull);
      expect(find.byType(LockedCard), findsOneWidget);
      expect(find.byKey(const ValueKey('merged-debt-lines')), findsNothing);
    });

    for (final dark in [false, true]) {
      testWidgets('(هـ) الحاسبة «الكل» (${dark ? 'داكن' : 'فاتح'}): المجموع رقم البطاقة ثمّ سطرٌ لكلّ شركة — بلا فيض',
          (t) async {
        seed();
        var opened = 0;
        await pumpSim(t, SimVariant(1200, dark: dark),
            home: (_) => Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: DesktopOverview(
                      stats: const SubscribersStats(
                          total: 5,
                          active: 4,
                          online: 3,
                          offline: 1,
                          expired: 1,
                          nearExpiry: 0,
                          onlineNoPlan: 0,
                          disabled: 0),
                      wallet: const WalletResult(balance: 130000, points: 0),
                      walletLines: walletLines,
                      debtors: _debtors(3, 123464289),
                      debtSplit: split(),
                      subsLocked: false,
                      balanceLocked: false,
                      debtLocked: false,
                      onOpen: (_) => opened++,
                    ),
                  ),
                ));
        expect(t.takeException(), isNull);
        final card = find.byKey(const ValueKey('merged-debt-card'));
        expect(card, findsOneWidget);
        expect(find.text('123,464,289'), findsOneWidget, reason: 'المجموع رقم البطاقة');
        expect(find.text('على 3 مشتركين · مجموع الشركات'), findsOneWidget);
        Finder line(String k) => find.byKey(ValueKey('merged-debt-$k'));
        expect(find.descendant(of: line(_kA), matching: find.text('123,461,789')), findsOneWidget);
        expect(find.descendant(of: line(_kA), matching: find.text('2 مشترك')), findsOneWidget);
        expect(find.descendant(of: line(_kB), matching: find.text('2,500')), findsOneWidget);
        expect(find.descendant(of: line(_kC), matching: find.text('كبيرة، افتحها وحدها')), findsOneWidget);
        expect(find.descendant(of: line(_kD), matching: find.text('تحتاج دخول')), findsOneWidget);
        expect(find.descendant(of: card, matching: find.byKey(const ValueKey('merged-debt-note'))), findsOneWidget);
        expect(find.byKey(const ValueKey('merged-balance-lines')), findsOneWidget,
            reason: 'أرصدة الشركات بجانبها كما كانت');
        await t.tap(find.text('123,464,289'));
        expect(opened, 1, reason: 'النقر كما كان: المشتركون بفلتر المدينين');
      });
    }

    testWidgets('الحاسبة بلا تقسيم (شركةٌ مختارة): البطاقة كما كانت بنسبتها', (t) async {
      seed();
      await pumpSim(t, const SimVariant(1200, dark: false),
          home: (_) => Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DesktopOverview(
                    stats: null,
                    wallet: const WalletResult(balance: 50000, points: 0),
                    debtors: _debtors(1, 2500),
                    subsLocked: false,
                    balanceLocked: false,
                    debtLocked: false,
                  ),
                ),
              ));
      expect(t.takeException(), isNull);
      expect(find.text('2,500'), findsOneWidget);
      expect(find.text('على 1 مشتركين'), findsOneWidget);
      expect(find.text('20%'), findsOneWidget, reason: '1 من 5');
      expect(find.byKey(const ValueKey('merged-debt-card')), findsNothing);
    });
  });
}
