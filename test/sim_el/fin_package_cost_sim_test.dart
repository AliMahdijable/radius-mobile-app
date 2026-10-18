import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/reports/financial_report_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_harness.dart';

/// محاكاة «صافي الربح بعد كلفة الباقات» في التقرير الماليّ (٢٠٢٦-١٠-١٨).
///
/// قرار المالك: «صافي الربح استثني فقط سوبرنت من سعر الباقات اما بقية
/// الساسات لا طبقها عليها كلهن». فالكلفة وصافي الربح بعدها لمالك حسابٍ على
/// ساسٍ بعيد أو ايرث لنك وحده؛ والموظّف وسوبرنت يريان الشاشة كما كانت
/// حرفيّاً — حتّى لو أرسل الخادم الحقول خطأً (الحاجز الثاني في التطبيق).
///
/// الأرقام: نقد 1,400,000 − صرفيات 75,000 − إضافة دين 30,000 = 1,295,000
/// («الصافي» النقديّ — يبقى كما كان). وصافي الربح بعد الكلفة على المبيعات:
/// 1,150,000 + 140,000 = 1,290,000 − 75,000 − 960,000 = 255,000 (لا النقد −
/// الكلفة). ‏`profit_after_cost`/`sales_sum` الخادم لا يُقرآن.
/// اللقطات في `shots/fin_cost/`.
const _screen = 'fin_cost';
const _financePath = '/api/reports/finance';

Map<String, Object?> _kpis({
  num costSum = 960000,
  int rows = 48,
  int known = 48,
  int estimated = 0,
}) =>
    {
      'payments_sum': 0,
      'debt_pay_sum': '250000.00',
      'balance_add_sum': '30000.00',
      'balance_deduct_sum': 0,
      'activate_cash_sum': '1150000.00',
      'activate_non_cash_sum': 140000,
      'expenses_sum': 75000,
      'expenses_count': 3,
      'manager_debts_outstanding': 0,
      'activations_count': 42,
      'extend_count': 6,
      'package_cost_sum': costSum,
      'sales_sum': 1290000,
      'profit_after_cost': 1290000 - 75000 - costSum,
      'cost_rows': rows,
      'cost_known_rows': known,
      'cost_estimated_rows': estimated,
      'cost_coverage': rows == 0 ? 1 : known / rows,
      'cost_has_estimates': estimated > 0,
    };

/// آخر الحركات: تفعيلٌ بكلفةٍ مؤكَّدة، تمديدٌ بكلفةٍ تقديريّة، تسديد (لا كلفة
/// له)، وتفعيلٌ لم تُسجَّل كلفته بعد (null صريح). [perRow]=false: خادمٌ لا
/// يرسل كلفة السطر أصلاً (الحقول محذوفة).
List<Map<String, Object?>> _logs({bool perRow = true}) => [
      for (final r in _allLogs)
        perRow
            ? r
            : (Map.of(r)
              ..remove('package_cost')
              ..remove('package_cost_source')),
    ];

const _allLogs = <Map<String, Object?>>[
      {
        'id': 501,
        'action_type': 'SUBSCRIBER_ACTIVATE',
        'action_description': 'تفعيل نقدي — Economy',
        'amount': 35000,
        'user_username': 'ali1@alnoor-net',
        'user_firstname': 'علي',
        'user_lastname': 'حسن',
        'created_at': '2026-10-18T07:30:00.000Z',
        'from_sas': 0,
        'package_cost': '20000.00',
        'package_cost_source': 'live',
      },
      {
        'id': 502,
        'action_type': 'SUBSCRIBER_EXTEND',
        'action_description': 'تمديد اشتراك — Economy',
        'amount': 0,
        'user_username': 'zainab@alnoor-net',
        'user_firstname': 'زينب',
        'user_lastname': 'كاظم',
        'created_at': '2026-10-18T06:10:00.000Z',
        'from_sas': 0,
        'package_cost': 20000,
        'package_cost_source': 'estimate',
      },
      {
        'id': 503,
        'action_type': 'DEBT_PAY',
        'action_description': 'تسديد دين',
        'amount': 25000,
        'user_username': 'omar@alnoor-net',
        'user_firstname': 'عمر',
        'user_lastname': 'سالم',
        'created_at': '2026-10-17T15:00:00.000Z',
        'from_sas': 0,
      },
      {
        'id': 504,
        'action_type': 'SUBSCRIBER_ACTIVATE',
        'action_description': 'تفعيل غير نقدي — Family',
        'amount': 45000,
        'user_username': 'huda@alnoor-net',
        'user_firstname': 'هدى',
        'user_lastname': 'جاسم',
        'created_at': '2026-10-17T12:00:00.000Z',
        'from_sas': 0,
        'package_cost': null,
      },
    ];

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  /// جلسةٌ بمعرّف [adminId] — والخادم يرسل حقول الكلفة دائماً، فما يحجبها في
  /// حالتَي الموظّف وسوبرنت هو التطبيق نفسه.
  Future<void> session(String adminId, {bool employee = false}) async {
    server = await simSetUp(secure: {'auth.admin_id': adminId});
    ProviderService.debugSet(adminId.startsWith('earthlink:') ? 'earthlink' : null);
    PermissionsService.debugSet(
      isEmployee: employee,
      permissions: const {'reports.financial': true},
    );
    addTearDown(PermissionsService.debugReset);
    server.reply('GET', '/api/v2/managers', 200, {'success': true, 'data': []});
    server.reply('GET', '/api/v2/employees', 200, {'success': true, 'data': []});
  }

  void finance(Map<String, Object?> kpis, {bool perRow = true}) =>
      server.reply('GET', _financePath, 200, {
        'success': true,
        'data': {'kpis': kpis, 'recentLogs': _logs(perRow: perRow)},
      });

  /// فلتر النوع «تمديد اشتراك» من لوحة الفلاتر — أرقامه تُحسب من السطور.
  Future<void> filterExtensions(WidgetTester t) async {
    await t.tap(find.text('كل الحركات'));
    await t.pumpAndSettle();
    await t.tap(find.text('تمديد اشتراك'));
    await t.pumpAndSettle();
    await t.tap(find.text('تطبيق (1)'));
    await t.pumpAndSettle();
    expect(server.calls('GET', _financePath), hasLength(2));
  }

  Future<void> open(WidgetTester t, SimVariant v) async {
    await pumpSim(t, v, home: (_) => const FinancialReportScreen());
    expect(server.calls('GET', _financePath), hasLength(1));
  }

  /// يمرّر حتى يظهر [f] ثمّ يضعه أعلى الشاشة (`ensureVisible` يحاذي للبداية).
  Future<void> reveal(WidgetTester t, Finder f) async {
    await t.scrollUntilVisible(f, 160,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
  }

  /// الهيرو كاملاً أعلى الشاشة — أقرب `Container` يلفّ عنوانه.
  Future<void> showHero(WidgetTester t) async {
    await t.ensureVisible(find
        .ancestor(
          of: find.text('الإيراد النقدي الإجمالي'),
          matching: find.byType(Container),
        )
        .first);
    await t.pumpAndSettle();
  }

  /// الهيرو كما كان: «الصافي» القديم بلا سطر كلفة.
  void expectOldHero() {
    expect(find.text('صافي الربح بعد كلفة الباقات'), findsNothing);
    expect(find.text('الصافي'), findsOneWidget);
    expect(find.text('1,295,000'), findsOneWidget,
        reason: 'الصافي القديم: النقد − الصرفيات − إضافة الدين');
  }

  /// لا أثر للكلفة في أيّ نصٍّ مبنيّ — الهيرو ولا السطور.
  void expectNoCostText() =>
      expect(find.textContaining('كلفة'), findsNothing);

  simCase(_screen, 'owner_el_hero', (t, v) async {
    await session('earthlink:5');
    finance(_kpis());
    await open(t, v);
    expect(find.text('كلفة الباقات'), findsOneWidget);
    expect(find.text('-960,000'), findsOneWidget);
    expect(find.text('صافي الربح بعد كلفة الباقات'), findsOneWidget);
    expect(find.text('255,000'), findsOneWidget,
        reason: 'المبيعات 1,290,000 − المصاريف 75,000 − الكلفة 960,000');
    expect(find.text('مبيعات 1,290,000 − مصاريف 75,000 − كلفة الباقات 960,000'),
        findsOneWidget);
    expect(find.text('335,000'), findsNothing,
        reason: 'لا النقد − الكلفة');
    expect(find.text('الصافي'), findsOneWidget, reason: 'صافي النقد باقٍ');
    expect(find.text('1,295,000'), findsOneWidget);
    expect(find.textContaining('عمليّاتٌ بلا كلفةٍ'), findsNothing,
        reason: 'تغطيةٌ كاملة — لا تنبيه');
    expect(find.textContaining('تقديريّة إلى أن'), findsNothing);
    await showHero(t);
    await simCheck(t, v, _screen, 'owner_el_hero');
  });

  simCase(_screen, 'owner_el_logs', (t, v) async {
    await session('earthlink:5');
    finance(_kpis());
    await open(t, v);
    await reveal(t, find.text('كلفة الباقة غير معروفة بعد'));
    expect(find.text('كلفة الباقة: 20,000 د.ع'), findsOneWidget);
    expect(find.text('كلفة الباقة: 20,000 د.ع · تقديريّة'), findsOneWidget);
    expect(find.text('كلفة الباقة غير معروفة بعد'), findsOneWidget,
        reason: 'تفعيلٌ أرسل الخادم كلفته null صراحةً');
    await reveal(t, find.text('آخر الحركات'));
    await simCheck(t, v, _screen, 'owner_el_logs');
  });

  simCase(_screen, 'owner_sas_partial', (t, v) async {
    await session('jt:5136');
    finance(_kpis(costSum: 2760000, rows: 150, known: 138, estimated: 9));
    await open(t, v);
    expect(find.text('-2,760,000'), findsOneWidget);
    // 1,290,000 − 75,000 − 2,760,000 = −1,545,000 — خسارة بعد الكلفة.
    expect(find.text('-1,545,000'), findsOneWidget);
    expect(
      find.text('عمليّاتٌ بلا كلفةٍ مسجّلة بعد: 12 من 150 — '
          'فالصافي الحقيقيّ أقلّ من المعروض'),
      findsOneWidget,
    );
    expect(
      find.text('عمليّاتٌ كلفتها تقديريّة إلى أن تؤكّدها الشركة: 9'),
      findsOneWidget,
    );
    await showHero(t);
    await simCheck(t, v, _screen, 'owner_sas_partial');
  });

  simCase(_screen, 'employee_hidden', (t, v) async {
    await session('earthlink:5', employee: true);
    finance(_kpis()); // خادمٌ أرسلها خطأً — التطبيق يُسقطها
    await open(t, v);
    expectOldHero();
    expectNoCostText();
    await showHero(t);
    await simCheck(t, v, _screen, 'employee_hidden');
    await reveal(t, find.text('هدى جاسم'));
    expectNoCostText();
    await simCheck(t, v, _screen, 'employee_hidden_logs');
  });

  simCase(_screen, 'supernet_unchanged', (t, v) async {
    await session('2');
    finance(_kpis()); // سوبرنت لا كلفة لها ولو وصلت الحقول
    await open(t, v);
    expectOldHero();
    expectNoCostText();
    await showHero(t);
    await simCheck(t, v, _screen, 'supernet_unchanged');
    await reveal(t, find.text('هدى جاسم'));
    expectNoCostText();
    await simCheck(t, v, _screen, 'supernet_unchanged_logs');
  });
  simCase(_screen, 'owner_filter_rows', (t, v) async {
    await session('jt:5136');
    finance(_kpis());
    await open(t, v);
    await filterExtensions(t);
    // تمديدٌ واحد بكلفة 20,000 تقديريّة: لا مبيعات ⇒ صافي الربح بعد الكلفة −20,000.
    expect(find.text('كلفة الباقات'), findsOneWidget);
    expect(find.text('-20,000'), findsNWidgets(2), reason: 'الكلفة والربح');
    expect(find.text('صافي الربح بعد كلفة الباقات'), findsOneWidget);
    expect(find.text('مبيعات 0 − مصاريف 0 − كلفة الباقات 20,000'), findsOneWidget);
    expect(
      find.text('عمليّاتٌ كلفتها تقديريّة إلى أن تؤكّدها الشركة: 1'),
      findsOneWidget,
    );
    expect(find.textContaining('عمليّاتٌ بلا كلفةٍ'), findsNothing);
    await showHero(t);
    await simCheck(t, v, _screen, 'owner_filter_rows');
  });

  simCase(_screen, 'owner_filter_no_rows', (t, v) async {
    await session('jt:5136');
    finance(_kpis(), perRow: false); // خادمٌ لا يرسل كلفة السطر
    await open(t, v);
    await filterExtensions(t);
    // لا صفرٌ كاذب يُطرح: الصافي قبل الكلفة، ويُقال ذلك صراحةً.
    expect(find.text('كلفة الباقات'), findsNothing);
    expect(find.text('الصافي'), findsOneWidget);
    expect(
      find.text('صافي الربح بعد كلفة الباقات لا يُحسب مع فلتر النوع هنا — '
          'أزل الفلتر لتراه'),
      findsOneWidget,
    );
    await showHero(t);
    await simCheck(t, v, _screen, 'owner_filter_no_rows');
  });

  simCase(_screen, 'owner_zero_cost', (t, v) async {
    await session('jt:5136');
    finance(_kpis(costSum: 0, rows: 0, known: 0));
    await open(t, v);
    // كلفةٌ صفرٌ معروفة: «0» لا «-0»، والربح = المبيعات − المصاريف.
    expect(find.text('-0'), findsNothing);
    expect(find.text('كلفة الباقات'), findsOneWidget);
    expect(find.text('1,215,000'), findsOneWidget);
    await showHero(t);
    await simCheck(t, v, _screen, 'owner_zero_cost');
  });
}
