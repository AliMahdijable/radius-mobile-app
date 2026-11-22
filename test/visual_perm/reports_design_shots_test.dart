import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/screens/reports/financial_report_screen.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_sheets.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/theme/colors.dart';
import 'package:rad_mysvcs/theme/spacing.dart';
import 'package:rad_mysvcs/theme/typography.dart';

import 'visual_perm_harness.dart';

// صور مقترح «التقارير — الشكل الموحّد» (٢٢ نوفمبر — المالك: «صور وشرح تكدر تسوي حتى وراها نبلش؟»).
//
// المرحلة ١ (phones): كلّ شاشة بعرض شاشته (480) أو هاتفٍ ضيّق (360) — صفحات المقترح من report_kit/report_sheets ببياناتٍ تجريبيّة،
// و«قبل» = التقرير الماليّ الحاليّ نفسه أمام خادمٍ وهميّ (شركة منفردة، ثمّ «كل الشركات»). يُحفظ لكلّ لقطة: الصورة، وارتفاع
// محتواها، ومواضع ما يشرحه الشرح (من الشاشة نفسها بالقياس).
// المرحلة ٢ (notes): لوحة الشرح بارتفاع اللقطة، كلّ ملاحظةٍ بمحاذاة جزئها وخطٌّ يصلها به — «الشرح بجانب الشاشة لا داخلها».
// ثمّ يُجمعان بصورةٍ واحدة خارج الاختبار (compose.py).

final _out = Directory('build/report_design');

// ═══════════════════════════════ البيانات التجريبيّة ═══════════════════════════════

const _period = RpPeriod(name: 'هذا الشهر', range: '2026/11/01 – 2026/11/22');
const _cmp = 'بالشهر الماضي';
const _vs = 'عن الشهر الماضي';

const _sup = RpCompany(name: 'سوبرنت', colorIndex: 0, selected: true);
const _earth = RpCompany(name: 'ايرث لنك', colorIndex: 1, selected: true);
const _fiber = RpCompany(name: 'فايبر لنك', colorIndex: 2, selected: true);
const _hala = RpCompany(name: 'هالة سات', colorIndex: 3, selected: true);
const _amwaj = RpCompany(name: 'أمواج', colorIndex: 4);
const _companies = [_sup, _earth, _fiber, _hala, _amwaj];

List<RpTrendPoint> _trend({double scale = 1}) {
  const a = [520, 610, 480, 700, 830, 560, 450, 620, 760, 880, 540, 470, 650, 720, 910, 600, 530, 690, 780, 940, 610, 560];
  const b = [140, 120, 180, 90, 160, 210, 130, 110, 170, 150, 190, 120, 100, 160, 140, 220, 130, 150, 120, 170, 110, 160];
  return [for (var i = 0; i < a.length; i++) RpTrendPoint(i + 1, a[i] * 1000 * scale, b[i] * 1000 * scale)];
}

/// «كل الشركات» = سوبرنت + ايرث لنك (التي وصلت) — نفس مجموع جدول «حسب الشركة».
List<RpKpi> _kpis({required bool merged}) => [
      RpKpi(label: 'الواصل نقداً', value: merged ? 19850000 : 11450000, icon: LucideIcons.wallet, tone: RpTone.money, delta: merged ? 0.11 : 0.12),
      RpKpi(label: 'المبيعات (تفعيل وتمديد)', value: merged ? 25500000 : 14700000, icon: LucideIcons.shoppingCart, tone: RpTone.brand, delta: merged ? 0.07 : 0.08),
      RpKpi(label: 'الدين الجديد', value: merged ? 5400000 : 3250000, icon: LucideIcons.creditCard, tone: RpTone.debt, delta: merged ? -0.02 : -0.04, upIsGood: false),
      RpKpi(label: 'تسديد الديون', value: merged ? 3640000 : 2100000, icon: LucideIcons.banknote, tone: RpTone.money, delta: merged ? 0.18 : 0.15),
      RpKpi(label: 'الصرفيّات', value: merged ? 1990000 : 1150000, icon: LucideIcons.receipt, tone: RpTone.loss, delta: merged ? 0.05 : 0.03, upIsGood: false),
      RpKpi(label: 'إضافة دين يدوي', value: merged ? 780000 : 450000, icon: LucideIcons.plus, tone: RpTone.debt, delta: merged ? -0.12 : -0.2, upIsGood: false),
    ];

RpKpi _profit({required bool merged}) => RpKpi(
      label: 'صافي الربح',
      value: merged ? 7960000 : 4820000,
      icon: LucideIcons.trendingUp,
      tone: RpTone.brand,
      delta: merged ? 0.09 : 0.10,
    );

List<RpKpi> _counts({required bool merged}) => [
      RpKpi(label: 'تفعيل', value: merged ? 311 : 182, icon: LucideIcons.zap, tone: RpTone.brand, isCount: true),
      RpKpi(label: 'تمديد', value: merged ? 109 : 64, icon: LucideIcons.repeat, tone: RpTone.info, isCount: true),
      RpKpi(label: 'صرفيّة', value: merged ? 39 : 23, icon: LucideIcons.receipt, tone: RpTone.loss, isCount: true),
    ];

List<RpDay> _days({required bool merged}) {
  RpCompany? c(RpCompany x) => merged ? x : null;
  return [
    RpDay(date: '2026/11/22', count: merged ? 26 : 14, sum: merged ? 2190000 : 1250000, rows: [
      RpRow(icon: LucideIcons.zap, tone: RpTone.money, title: 'محمد عبد الله', detail: 'تفعيل نقدي · FTTH 50 ميغا · علي حسن', amount: 35000, time: '18:05', company: c(_sup)),
      RpRow(icon: LucideIcons.banknote, tone: RpTone.money, title: 'سارة علي', detail: 'تسديد دين · زينب (موظّفة)', amount: 20000, time: '17:40', company: c(_earth)),
      RpRow(icon: LucideIcons.creditCard, tone: RpTone.debt, title: 'حسن كاظم', detail: 'تفعيل بالدين · Gaming 100 · مصطفى كريم', amount: 45000, time: '16:12', company: c(_sup)),
      RpRow(icon: LucideIcons.receipt, tone: RpTone.loss, title: 'إيجار البرج', detail: 'صرفيّة · علي حسن', amount: 150000, time: '12:00', negative: true, company: c(_earth)),
    ]),
    RpDay(date: '2026/11/21', count: merged ? 37 : 22, sum: merged ? 3060000 : 1780000, rows: [
      RpRow(icon: LucideIcons.repeat, tone: RpTone.brand, title: 'زهراء محمود', detail: 'تمديد شهر · D-Active 75 · حسين (موظّف)', amount: 25000, time: '21:30', company: c(_sup)),
      RpRow(icon: LucideIcons.zap, tone: RpTone.money, title: 'علي جبار', detail: 'تفعيل نقدي · FTTH 50 ميغا · حيدر جاسم', amount: 35000, time: '20:15', company: c(_earth)),
    ]),
  ];
}

const _tabsSingle = ['المدير', 'الموظّف', 'الباقة', 'النوع', 'اليوم'];
const _tabsMerged = ['الشركة', 'المدير', 'الموظّف', 'الباقة', 'النوع', 'اليوم'];

const _sharesSingle = [
  RpShare(name: 'علي حسن', amount: 6300000, count: 94, share: 0.55),
  RpShare(name: 'مصطفى كريم', sub: 'مدير فرعيّ لعلي حسن', amount: 3150000, count: 47, share: 0.27),
  RpShare(name: 'حيدر الموسوي', amount: 2000000, count: 31, share: 0.18),
];

const _sharesMerged = [
  RpShare(name: 'علي حسن', company: _sup, amount: 6300000, count: 94, share: 0.32),
  RpShare(name: 'حيدر جاسم', company: _earth, amount: 5100000, count: 77, share: 0.26),
  RpShare(name: 'سجاد علي', company: _earth, amount: 3300000, count: 51, share: 0.17),
  RpShare(name: 'مصطفى كريم', company: _sup, sub: 'فرعيّ', amount: 3150000, count: 47, share: 0.15),
  RpShare(name: 'حيدر الموسوي', company: _sup, amount: 2000000, count: 31, share: 0.10),
];

const _periods = ['اليوم', 'أمس', 'هذا الأسبوع', 'الأسبوع الماضي', 'هذا الشهر', 'الشهر الماضي', 'آخر 30 يوماً', 'هذه السنة', 'مخصّص…'];
const _types = [
  ('تفعيل نقدي', true),
  ('تفعيل بالدين', false),
  ('تمديد', false),
  ('تسديد دين', true),
  ('إضافة دين', false),
  ('صرفيّة', false),
  ('بيع مواد', false),
];
const _payments = [('نقد', true), ('دين', false), ('من الرصيد', false)];

// ═══════════════════════════════ الصفحات ═══════════════════════════════

// ألوان الصفحة تُقرأ عند الرسم (Builder) لا عند بناء الكائن — الوضع الليليّ يُضبط بعد إنشائها.
Widget _page(String title, List<Widget> parts) => Builder(builder: (_) => _pageNow(title, parts));

Widget _pageNow(String title, List<Widget> parts) => Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(title, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        iconTheme: IconThemeData(color: AppColors.textHi),
        leading: const Icon(LucideIcons.arrowRight),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
        children: [
          for (var i = 0; i < parts.length; i++) ...[if (i > 0) const SizedBox(height: Sp.md), parts[i]],
        ],
      ),
    );

Widget _financeSingle() => _page('التقرير الماليّ', [
      const RpPeriodBar(period: _period, compareOn: true, compareWith: _cmp),
      const RpFilterBar(chips: ['المدير: علي حسن + الفرعيّين', 'النوع: تفعيل نقدي، تسديد', 'الدفع: نقد']),
      RpHeroKpi(kpi: _profit(merged: false), compareWith: _vs, spark: [for (final p in _trend()) p.a - p.b * 0.6], note: 'الواصل − الصرفيّات − كلفة الباقات'),
      RpKpiGrid(kpis: _kpis(merged: false), compareWith: _vs),
      RpCountsRow(items: _counts(merged: false)),
      RpTrendCard(points: _trend(), aLabel: 'الواصل', bLabel: 'الدين'),
      const RpBreakdownCard(tabs: _tabsSingle, selected: 0, shares: _sharesSingle),
      RpRowsCard(total: 246, days: _days(merged: false), more: 'عرض المزيد (240)'),
      const RpExportBar(),
    ]);

Widget _financeMerged() => _page('التقرير الماليّ · كل الشركات', [
      const RpPeriodBar(period: _period, compareOn: true, compareWith: _cmp),
      const RpCompanyChips(companies: _companies),
      const RpFilterBar(chips: ['المدير: علي (سوبرنت)، حيدر (ايرث لنك)', 'الموظّف: زينب (سوبرنت)']),
      const RpCompanyTable(
        heads: ['الواصل', 'الدين', 'الربح'],
        lines: [
          RpCompanyLine(company: _sup, a: 11450000, b: 3250000, c: 4820000),
          RpCompanyLine(company: _earth, a: 8400000, b: 2150000, c: 3140000),
          RpCompanyLine(company: _fiber, state: RpCompanyState.loading),
          RpCompanyLine(company: _hala, state: RpCompanyState.failed),
        ],
        total: [19850000, 5400000, 7960000],
        outside: 'خارج المجموع الآن: فايبر لنك (تُقرأ) · هالة سات (تعذّرت قراءتها)',
      ),
      RpHeroKpi(kpi: _profit(merged: true), compareWith: _vs, spark: [for (final p in _trend(scale: 1.7)) p.a - p.b * 0.6]),
      RpKpiGrid(kpis: _kpis(merged: true), compareWith: _vs),
      RpCountsRow(items: _counts(merged: true)),
      RpTrendCard(points: _trend(scale: 1.7), aLabel: 'الواصل', bLabel: 'الدين'),
      const RpBreakdownCard(tabs: _tabsMerged, selected: 1, shares: _sharesMerged),
      RpRowsCard(total: 418, days: _days(merged: true), more: 'عرض المزيد (412)'),
      const RpExportBar(),
    ]);

Widget _activations() => _page('التفعيلات والتمديدات', [
      const RpPeriodBar(period: _period, compareOn: true, compareWith: _cmp),
      const RpFilterBar(chips: ['الباقة: FTTH 50 ميغا', 'الموظّف: زينب']),
      const RpKpiGrid(compareWith: _vs, kpis: [
        RpKpi(label: 'التفعيلات', value: 182, unit: 'تفعيل', isCount: true, icon: LucideIcons.zap, tone: RpTone.brand, delta: 0.06),
        RpKpi(label: 'التمديدات', value: 64, unit: 'تمديد', isCount: true, icon: LucideIcons.repeat, tone: RpTone.info, delta: 0.12),
        RpKpi(label: 'نقداً', value: 9350000, icon: LucideIcons.wallet, tone: RpTone.money, delta: 0.09),
        RpKpi(label: 'بالدين', value: 3250000, icon: LucideIcons.creditCard, tone: RpTone.debt, delta: -0.04, upIsGood: false),
      ]),
      RpTrendCard(
        title: 'العدد يوماً بيوم',
        points: [for (final p in _trend()) RpTrendPoint(p.day, (p.a / 70000).round(), (p.b / 50000).round())],
        aLabel: 'تفعيل',
        bLabel: 'تمديد',
        aTone: RpTone.brand,
        bTone: RpTone.info,
      ),
      const RpBreakdownCard(tabs: ['الباقة', 'المدير', 'الموظّف', 'اليوم'], selected: 0, tone: RpTone.brand, shares: [
        RpShare(name: 'FTTH 50 ميغا', amount: 3430000, count: 98, share: 0.54),
        RpShare(name: 'D-Active 75 العائليّة', amount: 2860000, count: 52, share: 0.29),
        RpShare(name: 'Gaming 100', amount: 1725000, count: 23, share: 0.13),
        RpShare(name: 'أعمال 200', amount: 900000, count: 9, share: 0.05),
      ]),
      const RpRowsCard(total: 246, more: 'عرض المزيد (242)', days: [
        RpDay(date: '2026/11/22', count: 11, sum: 410000, rows: [
          RpRow(icon: LucideIcons.zap, tone: RpTone.money, title: 'محمد عبد الله', detail: 'تفعيل نقدي · FTTH 50 ميغا · زينب', amount: 35000, time: '18:05'),
          RpRow(icon: LucideIcons.creditCard, tone: RpTone.debt, title: 'حسن كاظم', detail: 'تفعيل بالدين · FTTH 50 ميغا · زينب', amount: 35000, time: '16:12'),
        ]),
        RpDay(date: '2026/11/21', count: 9, sum: 315000, rows: [
          RpRow(icon: LucideIcons.repeat, tone: RpTone.brand, title: 'زهراء محمود', detail: 'تمديد شهر · FTTH 50 ميغا · زينب', amount: 35000, time: '21:30'),
        ]),
      ]),
      const RpExportBar(),
    ]);

RpFilterSheet _filterSheet({required bool merged}) => RpFilterSheet(
      subtitle: merged ? 'التقرير الماليّ · كل الشركات' : 'التقرير الماليّ · سوبرنت',
      periods: _periods,
      period: 'هذا الشهر',
      compareOn: true,
      companies: merged ? _companies : null,
      managers: merged
          ? const [
              RpPickGroup(company: _sup, items: [
                RpPick('علي حسن', on: true),
                RpPick('مصطفى كريم', depth: 1, sub: 'فرعيّ'),
                RpPick('حيدر الموسوي'),
              ]),
              RpPickGroup(company: _earth, items: [RpPick('حيدر جاسم', on: true), RpPick('سجاد علي')]),
              RpPickGroup(company: _fiber, items: [RpPick('كرار سعد')]),
            ]
          : const [
              RpPickGroup(items: [
                RpPick('علي حسن', on: true),
                RpPick('مصطفى كريم', depth: 1, sub: 'فرعيّ'),
                RpPick('كرار حيدر', depth: 1, sub: 'فرعيّ'),
                RpPick('حيدر الموسوي'),
              ]),
            ],
      withSubs: true,
      employees: merged
          ? const [
              RpPickGroup(company: _sup, items: [RpPick('زينب', on: true, sub: 'موظّفة'), RpPick('حسين', sub: 'موظّف')]),
              RpPickGroup(company: _earth, items: [RpPick('مريم', sub: 'موظّفة')]),
            ]
          : const [
              RpPickGroup(items: [RpPick('زينب', on: true, sub: 'موظّفة'), RpPick('حسين', sub: 'موظّف'), RpPick('مريم', sub: 'موظّفة')]),
            ],
      types: _types,
      payments: _payments,
      results: merged ? 124 : 71,
    );

RpDrillSheet _drill() => RpDrillSheet(
      kpi: _kpis(merged: true)[2],
      scope: 'هذا الشهر · سوبرنت، ايرث لنك',
      chips: const ['المدير: علي (سوبرنت)، حيدر (ايرث لنك)'],
      rows: const RpRowsCard(total: 41, more: 'عرض المزيد (37)', days: [
        RpDay(date: '2026/11/22', count: 3, sum: 125000, rows: [
          RpRow(icon: LucideIcons.creditCard, tone: RpTone.debt, title: 'حسن كاظم', detail: 'تفعيل بالدين · Gaming 100 · علي حسن', amount: 45000, time: '16:12', company: _sup),
          RpRow(icon: LucideIcons.creditCard, tone: RpTone.debt, title: 'نور الهدى', detail: 'تفعيل بالدين · FTTH 50 ميغا · حيدر جاسم', amount: 35000, time: '13:40', company: _earth),
        ]),
        RpDay(date: '2026/11/21', count: 2, sum: 80000, rows: [
          RpRow(icon: LucideIcons.plus, tone: RpTone.debt, title: 'كرار هادي', detail: 'إضافة دين يدوي · علي حسن', amount: 45000, time: '19:02', company: _sup),
        ]),
      ]),
    );

// ═══════════════════════════════ «قبل»: الخادم الوهميّ للتقرير الحاليّ ═══════════════════════════════

const _kSup = 'c000000000a01';
const _kEarth = 'c000000000a02';

Map<String, Object?> _mergedCompanies() => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kSup, 'code': 'supernet', 'username': 'admin@sup', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': '11', 'ns': 'nA', 'currency': 'IQD', 'color_index': 0},
        {'key': _kEarth, 'code': 'earthlink', 'username': 'admin@el', 'name': 'ايرث لنك', 'status': 'ok', 'admin_id': 'earthlink:22', 'ns': 'nB', 'currency': 'IQD', 'color_index': 1},
      ],
    };

Map<String, Object?> _financeBody(double k) {
  num r(num v) => (v * k / 1000).round() * 1000;
  Map<String, Object?> log(int id, String type, String desc, num amount, String first, String last, String at, {String? emp}) => {
        'id': id,
        'action_type': type,
        'action_description': desc,
        'amount': amount,
        'admin_username': 'admin@sup',
        if (emp != null) 'acting_employee_full_name': emp,
        'user_username': 'u$id',
        'user_firstname': first,
        'user_lastname': last,
        'created_at': at,
      };
  return {
    'success': true,
    'data': {
      'kpis': {
        'activate_cash_sum': r(9350000),
        'debt_pay_sum': r(2100000),
        'payments_sum': 0,
        'balance_deduct_sum': 0,
        'activate_non_cash_sum': r(3250000),
        'balance_add_sum': r(450000),
        'expenses_sum': r(1150000),
        'expenses_count': (23 * k).round(),
        'activations_count': (182 * k).round(),
        'extend_count': (64 * k).round(),
      },
      'recentLogs': [
        log(1, 'SUBSCRIBER_ACTIVATE', 'تفعيل نقدي — FTTH 50 ميغا', 35000, 'محمد', 'عبد الله', '2026-11-22 18:05:00'),
        log(2, 'BALANCE_DEDUCT', 'تسديد دين', 20000, 'سارة', 'علي', '2026-11-22 17:40:00', emp: 'زينب'),
        log(3, 'SUBSCRIBER_ACTIVATE', 'تفعيل غير نقدي — Gaming 100', 45000, 'حسن', 'كاظم', '2026-11-22 16:12:00'),
        log(4, 'SUBSCRIBER_EXTEND', 'تمديد شهر — D-Active 75', 25000, 'زهراء', 'محمود', '2026-11-21 21:30:00', emp: 'حسين'),
        log(5, 'SUBSCRIBER_ACTIVATE', 'تفعيل نقدي — FTTH 50 ميغا', 35000, 'علي', 'جبار', '2026-11-21 20:15:00'),
        log(6, 'BALANCE_ADD', 'إضافة دين', 45000, 'كرار', 'هادي', '2026-11-21 19:02:00'),
      ],
    },
  };
}

class _BeforeServer implements HttpClientAdapter {
  _BeforeServer(this.inner);
  final VisualServer inner;

  ResponseBody _json(Object body, String? key) => ResponseBody.fromString(jsonEncode(body), 200, headers: {
        Headers.contentTypeHeader: ['application/json'],
        if (key != null) 'x-company-key': [key],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final p = o.uri.path;
    final key = o.headers['x-company-key']?.toString();
    final get = o.method.toUpperCase() == 'GET';
    if (get && p == '/api/reports/finance') return _json(_financeBody(key == _kEarth ? 0.73 : 1), key);
    if (get && p == '/api/v2/managers') {
      return _json({
        'success': true,
        'data': [
          {'id': 101, 'username': 'ali.h', 'firstname': 'علي', 'lastname': 'حسن'},
          {'id': 102, 'username': 'mustafa.k', 'firstname': 'مصطفى', 'lastname': 'كريم'},
        ],
      }, key);
    }
    if (get && p == '/api/v2/employees') {
      return _json({
        'success': true,
        'data': [
          {'id': 7, 'username': 'zainab', 'full_name': 'زينب'},
          {'id': 8, 'username': 'hussein', 'full_name': 'حسين'},
        ],
      }, key);
    }
    if (key != null) return _json({'success': true, 'data': const []}, key);
    return inner.fetch(o, body, cancel);
  }

  @override
  void close({bool force = false}) {}
}

// ═══════════════════════════════ القياس والحفظ ═══════════════════════════════

Future<void> _savePhone(WidgetTester t, String id, VisualDevice d, Map<String, Finder> anchors, {Finder? bottom, double? height}) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(visualRootKey));
  final png = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: d.dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  _out.createSync(recursive: true);
  File('${_out.path}/${id}_phone.png').writeAsBytesSync(png!, flush: true);
  final ys = <String, double>{};
  anchors.forEach((k, f) {
    final hits = f.evaluate();
    if (hits.isEmpty) {
      ys[k] = -1;
      return;
    }
    ys[k] = t.getTopLeft(f.first).dy;
  });
  final h = height ?? (bottom == null ? d.size.height : math.min(d.size.height, t.getBottomLeft(bottom.first).dy + Sp.xxl));
  File('${_out.path}/${id}_meta.json').writeAsStringSync(jsonEncode({
    'id': id,
    'width': d.size.width,
    'dpr': d.dpr,
    'dark': d.dark,
    'height': h,
    'anchors': ys,
  }));
  final ex = t.takeException();
  expect(ex, isNull, reason: 'استثناء في $id:\n$ex');
}

/// ما لا يتّسع يُرى هنا: نصٌّ مقصوص بـ«…» أو فاض عن مكانه (قاعدة المالك ١٤ نوفمبر).
List<String> _cut(WidgetTester t) {
  final out = <String>[];
  for (final e in find.byType(RichText).evaluate()) {
    final ro = e.renderObject;
    if (ro is RenderParagraph && ro.didExceedMaxLines) out.add(ro.text.toPlainText());
  }
  return out;
}

Future<void> _drain(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 6));
}

VisualDevice _dev(double w, {double h = 3400, bool dark = false}) => VisualDevice('_${w.round()}${dark ? '_dark' : ''}', Size(w, h), 2, dark: dark);

// ═══════════════════════════════ لوحة الشرح ═══════════════════════════════

class _Note {
  const _Note(this.anchor, this.title, this.body);
  final String anchor;
  final String title;
  final String body;
}

class _NotesSpec {
  const _NotesSpec(this.title, this.subtitle, this.notes, {this.before = false});
  final String title;
  final String subtitle;
  final List<_Note> notes;
  final bool before;
}

class _Holder {
  final rects = <Rect>[];
  final targets = <double>[];
}

class _NotesDelegate extends MultiChildLayoutDelegate {
  _NotesDelegate(this.ys, this.minTop, this.holder);
  final List<double> ys;
  final double minTop;
  final _Holder holder;

  static const _edge = 34.0;

  @override
  void performLayout(Size size) {
    holder.rects.clear();
    holder.targets.clear();
    var prev = minTop;
    for (var i = 0; i < ys.length; i++) {
      final w = size.width - _edge - Sp.md;
      final s = layoutChild(i, BoxConstraints(minWidth: w, maxWidth: w));
      final top = math.max(ys[i] - Sp.xs, prev);
      positionChild(i, Offset(Sp.md, top));
      holder.rects.add(Rect.fromLTWH(Sp.md, top, s.width, s.height));
      holder.targets.add(ys[i]);
      prev = top + s.height + Sp.md;
    }
  }

  @override
  bool shouldRelayout(covariant MultiChildLayoutDelegate oldDelegate) => true;
}

class _Connectors extends CustomPainter {
  _Connectors(this.holder, this.color);
  final _Holder holder;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = color;
    for (var i = 0; i < holder.rects.length; i++) {
      final r = holder.rects[i];
      final y0 = r.top + 18;
      final y1 = holder.targets[i] + 14;
      final path = Path()
        ..moveTo(r.right, y0)
        ..lineTo(r.right + 12, y0)
        ..lineTo(size.width - 8, y1)
        ..lineTo(size.width, y1);
      canvas.drawPath(path, line);
      canvas.drawCircle(Offset(size.width - 3, y1), 3.5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _NotesPanel extends StatelessWidget {
  const _NotesPanel({required this.spec, required this.ys, this.headTop = 56});
  final _NotesSpec spec;
  final List<double> ys;

  /// أعلى صندوق العنوان — في لقطة الورقة تُقصّ الصورة من فوق الورقة بقليل، فينزل العنوان معها.
  final double headTop;

  static const _head = 132.0;

  @override
  Widget build(BuildContext context) {
    final holder = _Holder();
    final accent = spec.before ? AppColors.warning : AppColors.brand;
    return Material(
      color: AppColors.bg,
      child: Stack(
        children: [
          Positioned(
            top: headTop,
            left: Sp.md,
            right: Sp.xxl,
            child: Container(
              padding: const EdgeInsets.all(Sp.md),
              decoration: BoxDecoration(
                color: spec.before ? AppColors.warningSoftBg : AppColors.brandSoftBg,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: accent.withValues(alpha: 0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(spec.title, style: AppType.cardTitleBold(color: AppColors.textHi)),
                  const SizedBox(height: Sp.xxs),
                  Text(spec.subtitle, style: AppType.body(color: AppColors.textMid)),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              foregroundPainter: _Connectors(holder, accent.withValues(alpha: 0.55)),
              child: CustomMultiChildLayout(
                delegate: _NotesDelegate(ys, _head + headTop, holder),
                children: [
                  for (var i = 0; i < spec.notes.length; i++)
                    LayoutId(
                      id: i,
                      child: Container(
                        padding: const EdgeInsets.all(Sp.md),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(R.md),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                              child: Text('${i + 1}', style: AppType.microBold(color: AppColors.onBrand)),
                            ),
                            const SizedBox(width: Sp.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(spec.notes[i].title, style: AppType.bodyBold(color: AppColors.textHi)),
                                  const SizedBox(height: Sp.xxs),
                                  Text(spec.notes[i].body, style: AppType.body(color: AppColors.textMid)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════ الشروح ═══════════════════════════════

const _specs = <String, _NotesSpec>{
  '01_before_single': _NotesSpec('1 · قبل — التقرير الماليّ اليوم (شركة منفردة)', 'الشاشة الحاليّة نفسها ببياناتٍ تجريبيّة', before: true, [
    _Note('range', 'الفترة', 'فترات جاهزة واختيار التاريخ، بس بلا مقارنة بالفترة السابقة.'),
    _Note('filters', 'التصفية', 'أربع قوائم ظاهرة دائماً تاخذ مساحة، وما تبيّن شنو مختار إلّا تفتحها.'),
    _Note('hero', 'الإيراد والصافي', 'رقم كبير واحد، والمصاريف وإضافة الدين تحته.'),
    _Note('kpis', 'البطاقات', 'صغيرة، بلا فرق عن الشهر الماضي، ولمسها ما يفتح حركاتها.'),
    _Note('counts', 'الأعداد', 'كلّ عدد ببطاقة كاملة.'),
    _Note('logs', 'آخر الحركات', 'قائمة طويلة بلا تجميع حسب اليوم ولا بحث، والتصدير أيقونتان صغيرتان. وما في رسم ولا «قسّم حسب».'),
  ]),
  '02_before_merged': _NotesSpec('2 · قبل — التقرير الماليّ اليوم (كل الشركات)', 'الشاشة الحاليّة نفسها بشركتين', before: true, [
    _Note('strip', 'الشركات', 'شركة وحدة أو «الكل» فقط — ما تكدر تختار شركتين من خمس.'),
    _Note('filters', 'التصفية بكل الشركات', 'تبقى «نوع الحركة» وحدها: المدير والموظّف مخفيّة.'),
    _Note('hero', 'المجموع', 'رقم واحد لكلّ الشركات بلا مقارنة.'),
    _Note('bycompany', 'حسب الشركة', 'تحت البطاقات: الإيراد والصافي لكلّ شركة، بلا الدين.'),
    _Note('logs', 'الحركات', 'قائمة طويلة، وكلّ حركة ببطاقة كاملة.'),
  ]),
  '03_after_single': _NotesSpec('3 · بعد — التقرير الماليّ (شركة منفردة)', 'كلّ التقارير بهذا الترتيب نفسه', [
    _Note('period', 'الفترة والمقارنة', 'لمسة تفتح تسع فترات جاهزة + مخصّص. و«قارن» يكتب تحت كلّ رقم فرقه عن الشهر الماضي.'),
    _Note('filters', 'الفلاتر المختارة ظاهرة', 'كلّ فلتر رقيقة تنشال بلمسة على علامتها، و«الفلاتر» يفتح الورقة الكاملة (صورة 6).'),
    _Note('hero', 'صافي الربح أوّلاً', 'أكبر رقم بالصفحة، وتحته خطّ الشهر وكيف انحسب.'),
    _Note('kpis', 'بطاقات أوضح', 'كلّ رقم بلونه (المال أخضر، الدين كهرماني، الصرف أحمر)، وتحته فرقه عن الشهر الماضي بسهم. لمسها يفتح حركاتها (صورة 7).'),
    _Note('counts', 'الأعداد بصفّ واحد', 'التفعيلات والتمديدات والصرفيّات.'),
    _Note('trend', 'يوماً بيوم', 'الواصل والدين لكلّ يوم من الشهر.'),
    _Note('breakdown', 'قسّم حسب', 'نفس الأرقام حسب المدير أو الموظّف أو الباقة أو النوع أو اليوم.'),
    _Note('rows', 'الحركات', 'بحث باسم المشترك أو يوزره أو رقمه، ومجمّعة حسب اليوم بعددها ومجموعها.'),
    _Note('export', 'التصدير', 'PDF باسم شركتك، Excel، أو إرسال بالواتساب — بنفس الفلاتر.'),
  ]),
  '04_after_merged': _NotesSpec('4 · بعد — التقرير الماليّ (كل الشركات)', 'نفس الترتيب + ما يخصّ تعدّد الشركات', [
    _Note('companies', 'تختار أكثر من شركة', 'تؤشّر على كلّ شركة تريدها (هنا 4 من 5)، وكلّ شركة بلونها.'),
    _Note('filters', 'المدير والموظّف رجعوا', 'تختار مدراء من شركات مختلفة معاً، وكلّ شركة تنسأل بفلاترها هي.'),
    _Note('table', 'حسب الشركة أوّلاً', 'لكلّ شركة الواصل والدين والربح، ولمسة على شركة تحصر التقرير عليها.'),
    _Note('loading', 'شركة بعد شركة', 'كلّ شركة تظهر أرقامها لحظة توصل، والباقية «جارٍ» — ما تنتظر الأبطأ.'),
    _Note('failed', 'التي تعذّرت', 'تنذكر باسمها ويمّها «أعد».'),
    _Note('outside', 'المجموع صادق', 'يجمع اللي وصل فقط، ويكتب شنو خارجه.'),
    _Note('hero', 'نفس البطاقات', 'مجموع الشركات المختارة، والفرق عن الشهر الماضي.'),
    _Note('breakdown', 'قسّم حسب', 'أوّلها «الشركة»، وكلّ مدير بوسم شركته.'),
    _Note('rows', 'كلّ حركة بشركتها', 'وسم الشركة بلونها تحت كلّ حركة.'),
  ]),
  '05_filters_merged': _NotesSpec('5 · بعد — ورقة الفلاتر (كل الشركات)', 'كلّ الفلاتر بمكانٍ واحد، وكلّ شركةٍ بقوائمها', [
    _Note('periods', 'الفترة', 'تسع فترات جاهزة + مخصّص.'),
    _Note('compare', 'المقارنة', 'تشغّلها أو تطفيها من هنا.'),
    _Note('companies', 'الشركات', 'تختار أكثر من شركة.'),
    _Note('managers', 'المدير', 'مدراء كلّ شركة تحت اسمها، وتختار من أكثر من شركة.'),
    _Note('subs', 'مع الفرعيّين', 'حركات مدرائه الفرعيّين تدخل معه.'),
    _Note('employees', 'الموظّف', 'من نفّذ الحركة — موظّفو كلّ شركة تحت اسمها.'),
    _Note('types', 'النوع وطريقة الدفع', 'أنواع الحركة، ونقد أو دين أو من الرصيد.'),
    _Note('footer', 'عرض النتائج', 'الزرّ يقول كم حركة قبل ما تطبّق، و«مسح الكلّ» يرجّع كلشي.'),
  ]),
  '06_filters_single': _NotesSpec('6 · بعد — ورقة الفلاتر (شركة منفردة)', 'نفس الورقة بلا قسم الشركات', [
    _Note('periods', 'نفس الورقة', 'الفترة والمقارنة بنفس المكان.'),
    _Note('managers', 'المدير بشجرته', 'المدير الرئيسيّ وتحته مدراؤه الفرعيّون.'),
    _Note('tree', 'الفرعيّ تحت مديره', 'تختار الفرعيّ وحده، أو مديره ومعه كلّ فرعيّيه.'),
    _Note('employees', 'الموظّف', 'موظّفو الشركة.'),
    _Note('payments', 'طريقة الدفع', 'نقد، دين، أو من الرصيد.'),
    _Note('footer', 'عرض النتائج', 'نفس زرّ «كل الشركات».'),
  ]),
  '07_drill': _NotesSpec('7 · بعد — لمس رقم يفتح حركاته', 'مثال: بطاقة «الدين الجديد» بكل الشركات', [
    _Note('head', 'لمست بطاقة الدين الجديد', 'تنفتح حركاته بنفس الفترة والشركات.'),
    _Note('sum', 'المجموع والعدد', 'نفس رقم البطاقة وعدد حركاته.'),
    _Note('chips', 'نفس الفلاتر', 'المختارة تبقى، وتكدر تغيّرها من هنا.'),
    _Note('rows', 'الحركات', 'مجمّعة حسب اليوم، وكلّ حركة بشركتها.'),
    _Note('footer', 'تصدير', 'هذه الحركات وحدها.'),
  ]),
  '08_activations': _NotesSpec('8 · بعد — تقرير التفعيلات بنفس الشكل', 'وهكذا بقيّة التقارير', [
    _Note('period', 'نفس الترتيب', 'الفترة والمقارنة والفلاتر بنفس المكان بكلّ تقرير.'),
    _Note('kpis', 'أرقام التفعيلات', 'العدد، والمبلغ نقداً وبالدين، وفرق كلّ واحد عن الشهر الماضي.'),
    _Note('trend', 'العدد يوماً بيوم', 'التفعيل والتمديد لكلّ يوم.'),
    _Note('breakdown', 'قسّم حسب الباقة', 'أكثر الباقات تفعيلاً وحصّة كلّ وحدة.'),
    _Note('rows', 'الحركات', 'نفس القائمة والبحث.'),
    _Note('export', 'التصدير', 'نفس الأزرار.'),
  ]),
  '09_merged_360': _NotesSpec('9 · هاتف ضيّق (360)', 'الشاشة رقم 4 على أضيق هاتف', [
    _Note('companies', 'الشركات والفلاتر', 'تتمرّر يمين ويسار بإصبع.'),
    _Note('table', 'الأرقام تصغر ولا تنقصّ', 'الجدول يصغّر الرقم بدل ما يقصّه.'),
    _Note('kpis', 'البطاقات بعمودين', 'الاسم الطويل ينزل لسطر ثاني.'),
  ]),
  '10_single_dark': _NotesSpec('10 · الوضع الليليّ', 'الشاشة رقم 3 بالوضع الليليّ', [
    _Note('period', 'نفس الشاشة', 'الألوان بدرجاتها الليليّة.'),
    _Note('kpis', 'البطاقات', 'الأرقام وألوانها مقروءة بالليل.'),
    _Note('trend', 'الرسم', 'خطوطه واضحة على الخلفيّة الداكنة.'),
  ]),
};

void main() {
  setUpAll(visualSetUpAll);

  group('phones', () {
    late VisualServer server;

    Future<void> up() async {
      debugDisableShadows = false;
      server = await visualSetUp(s1bSasOwner);
      ApiClient.dio.httpClientAdapter = _BeforeServer(server);
    }

    Future<void> down(WidgetTester t) async {
      await _drain(t);
      MergedMode.reset();
      await visualTearDown();
      debugDisableShadows = true;
    }

    Future<void> afterPage(WidgetTester t, String id, VisualDevice d, Widget page, Map<String, Finder> anchors) async {
      await up();
      await pumpVisual(t, d, home: (_) => page);
      await settle(t, seconds: 2);
      final cut = _cut(t);
      expect(cut, isEmpty, reason: 'نصٌّ مقصوص في $id: $cut');
      await _savePhone(t, id, d, anchors, bottom: find.byType(RpExportBar));
      await down(t);
    }

    Map<String, Finder> pageAnchors() => {
          'period': find.byType(RpPeriodBar),
          'companies': find.byType(RpCompanyChips),
          'filters': find.byType(RpFilterBar),
          'table': find.byType(RpCompanyTable),
          'hero': find.byType(RpHeroKpi),
          'kpis': find.byType(RpKpiGrid),
          'counts': find.byType(RpCountsRow),
          'trend': find.byType(RpTrendCard),
          'breakdown': find.byType(RpBreakdownCard),
          'rows': find.byType(RpRowsCard),
          'export': find.byType(RpExportBar),
          'loading': find.text('جارٍ قراءة أرقامها…'),
          'failed': find.text('تعذّرت القراءة'),
          'outside': find.textContaining('خارج المجموع'),
        };

    testWidgets('03_after_single', (t) async => afterPage(t, '03_after_single', _dev(480), _financeSingle(), pageAnchors()));
    testWidgets('04_after_merged', (t) async => afterPage(t, '04_after_merged', _dev(480), _financeMerged(), pageAnchors()));
    testWidgets('08_activations', (t) async => afterPage(t, '08_activations', _dev(480), _activations(), pageAnchors()));
    testWidgets('09_merged_360', (t) async => afterPage(t, '09_merged_360', _dev(360), _financeMerged(), pageAnchors()));
    testWidgets('10_single_dark', (t) async => afterPage(t, '10_single_dark', _dev(480, dark: true), _financeSingle(), pageAnchors()));

    Future<void> sheet(WidgetTester t, String id, Widget page, Widget sheet, Map<String, Finder Function(Finder inSheet)> anchors) async {
      await up();
      final d = _dev(480, h: 1560);
      final nav = GlobalKey<NavigatorState>();
      await pumpVisual(t, d, navigatorKey: nav, home: (_) => page);
      await settle(t, seconds: 1);
      showModalBottomSheet<void>(
        context: nav.currentContext!,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: AppColors.scrim,
        builder: (_) => sheet,
      );
      await settle(t, seconds: 2);
      final cut = _cut(t);
      expect(cut, isEmpty, reason: 'نصٌّ مقصوص في $id: $cut');
      final inSheet = find.byType(sheet.runtimeType);
      await _savePhone(t, id, d, {
        'sheet': inSheet,
        for (final e in anchors.entries) e.key: e.value(inSheet),
      });
      await down(t);
    }

    testWidgets('05_filters_merged', (t) async => sheet(t, '05_filters_merged', _financeMerged(), _filterSheet(merged: true), {
          'periods': (s) => find.descendant(of: s, matching: find.text('الفترة')),
          'compare': (s) => find.descendant(of: s, matching: find.text('قارن بالفترة السابقة')),
          'companies': (s) => find.descendant(of: s, matching: find.text('الشركات')),
          'managers': (s) => find.descendant(of: s, matching: find.text('المدير')),
          'subs': (s) => find.descendant(of: s, matching: find.text('مع مدرائه الفرعيّين')),
          'employees': (s) => find.descendant(of: s, matching: find.text('الموظّف')),
          'types': (s) => find.descendant(of: s, matching: find.text('نوع الحركة')),
          'footer': (s) => find.descendant(of: s, matching: find.text('عرض النتائج · 124')),
        }));
    testWidgets('06_filters_single', (t) async => sheet(t, '06_filters_single', _financeSingle(), _filterSheet(merged: false), {
          'periods': (s) => find.descendant(of: s, matching: find.text('الفترة')),
          'managers': (s) => find.descendant(of: s, matching: find.text('المدير')),
          'tree': (s) => find.descendant(of: s, matching: find.text('مصطفى كريم')),
          'employees': (s) => find.descendant(of: s, matching: find.text('الموظّف')),
          'payments': (s) => find.descendant(of: s, matching: find.text('طريقة الدفع')),
          'footer': (s) => find.descendant(of: s, matching: find.text('عرض النتائج · 71')),
        }));
    testWidgets('07_drill', (t) async => sheet(t, '07_drill', _financeMerged(), _drill(), {
          'head': (s) => find.descendant(of: s, matching: find.text('الدين الجديد')),
          'sum': (s) => find.descendant(of: s, matching: find.text('المجموع')),
          'chips': (s) => find.descendant(of: s, matching: find.byType(RpFilterBar)),
          'rows': (s) => find.descendant(of: s, matching: find.byType(RpRowsCard)),
          'footer': (s) => find.descendant(of: s, matching: find.text('تصدير هذه الحركات')),
        }));

    // «قبل» — التقرير الماليّ الحاليّ نفسه
    testWidgets('01_before_single', (t) async {
      await up();
      final d = _dev(480, h: 2600);
      await pumpVisual(t, d, home: (_) => const FinancialReportScreen());
      await settle(t, seconds: 4);
      await _savePhone(t, '01_before_single', d, {
        'range': find.text('هذا الشهر'),
        'filters': find.text('التصفية'),
        'hero': find.text('الإيراد النقدي الإجمالي'),
        'kpis': find.text('تفعيل نقدي'),
        'counts': find.text('# تفعيلات'),
        'logs': find.text('آخر الحركات'),
      }, bottom: find.textContaining('هادي'));
      await down(t);
    });

    testWidgets('02_before_merged', (t) async {
      await up();
      AccountApi.tokenSource = ({bool force = false}) async => 'acct';
      MergedMode.reset();
      MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_mergedCompanies());
      await t.runAsync(() => MergedMode.enter());
      expect(MergedMode.active.value, isTrue);
      final d = _dev(480, h: 2600);
      await pumpVisual(t, d, home: (_) => const FinancialReportScreen());
      await settle(t, seconds: 5);
      await _savePhone(t, '02_before_merged', d, {
        'strip': find.text('الكل'),
        'filters': find.text('التصفية'),
        'hero': find.text('الإيراد النقدي الإجمالي'),
        'bycompany': find.text('حسب الشركة'),
        'logs': find.text('آخر الحركات'),
      }, bottom: find.textContaining('هادي'));
      await down(t);
    });
  });

  group('notes', () {
    for (final e in _specs.entries) {
      testWidgets(e.key, (t) async {
        final metaFile = File('${_out.path}/${e.key}_meta.json');
        if (!metaFile.existsSync() || e.value.notes.isEmpty) return;
        final meta = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        final anchors = Map<String, dynamic>.from(meta['anchors'] as Map);
        final notes = [for (final n in e.value.notes) if (((anchors[n.anchor] as num?) ?? -1) >= 0) n];
        final ys = [for (final n in notes) (anchors[n.anchor] as num).toDouble()];
        final h = (meta['height'] as num).toDouble();
        final d = VisualDevice('_notes', Size(400, h), 2, dark: meta['dark'] == true);
        await visualSetUp(s1bSasOwner);
        final sheetTop = ((anchors['sheet'] as num?) ?? -1).toDouble();
        final headTop = sheetTop > 0 ? math.max(56.0, sheetTop - 150 + 24) : 56.0;
        await pumpVisual(t, d,
            home: (_) => _NotesPanel(spec: _NotesSpec(e.value.title, e.value.subtitle, notes, before: e.value.before), ys: ys, headTop: headTop));
        await t.pump(const Duration(milliseconds: 300));
        final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(visualRootKey));
        final png = await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: d.dpr);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          return data!.buffer.asUint8List();
        });
        File('${_out.path}/${e.key}_notes.png').writeAsBytesSync(png!, flush: true);
        await _drain(t);
        await visualTearDown();
      });
    }
  });
}
