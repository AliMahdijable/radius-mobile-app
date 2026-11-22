import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/reports_api.dart';
import 'package:rad_mysvcs/core/util/ar_date.dart';
import 'package:rad_mysvcs/screens/reports/v2/finance_report_v2_screen.dart';
import 'package:rad_mysvcs/screens/reports/v2/finance_view.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_period.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_prefs.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_sheets.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_perm/visual_perm_harness.dart';

// التقرير الماليّ على الشكل الموحّد (٢٢ نوفمبر — «اي التطبيق أوّلاً … وانطلق»):
//  ١) حساب الفترات ومقارنتها، والحفظ (ومدراء الشركة المفتوحة لا يُطبَّقون على غيرها).
//  ٢) [FinanceView]: القواعد نفسها حرفاً (الصافي، تسديد الديون بلا المقدّم نقداً، إضافة الدين اليدويّة، الأيّام، البحث، «يوماً بيوم»).
//  ٣) الشاشة الحقيقيّة أمام خادمٍ وهميّ: ما تطلبه (التواريخ، السقف، طلب المقارنة)، وما ترسمه — شركة منفردة و«كل الشركات»
//     (كلّ شركةٍ بمفتاحها ومديرها، المتعذّرة خارج المجموع ومعها «أعد»)، وفلتر النوع من السطور بلا مقارنة.

final _now = DateTime(2026, 11, 22, 18); // الأحد

String _d(DateTime d) => iqDateOf(d);

FinanceLog _log(int id, String type, num amount, {String? desc, String at = '2026-11-22 10:00:00', bool credit = false, String? kind, String? first, String? user}) =>
    FinanceLog(
      id: id,
      actionType: type,
      actionDescription: desc,
      amount: amount,
      createdAt: at,
      isCredit: credit,
      creditKind: kind,
      userFirstname: first,
      userUsername: user,
    );

// ═══════════════════════════════ الخادم الوهميّ ═══════════════════════════════

const _kSup = 'c000000000a01';
const _kEarth = 'c000000000a02';

Map<String, Object?> _companies() => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kSup, 'code': 'supernet', 'username': 'admin@sup', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': '11', 'ns': 'nA', 'currency': 'IQD', 'color_index': 0},
        {'key': _kEarth, 'code': 'earthlink', 'username': 'admin@el', 'name': 'ايرث لنك', 'status': 'ok', 'admin_id': 'earthlink:22', 'ns': 'nB', 'currency': 'IQD', 'color_index': 1},
      ],
    };

/// تقريرٌ بمقياس [k]: الصافي عند ١ = 11,450,000 − 1,150,000 − 450,000 = 9,850,000.
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
        'expenses_count': 23,
        'activations_count': 182,
        'extend_count': 64,
      },
      'perAdmin': [
        {'admin_id': '11', 'admin_username': 'admin@sup', 'revenue_total': r(7150000), 'debt_total': 0, 'expenses_total': 0, 'net_balance': 0, 'activations_count': 118, 'extend_count': 40, 'total_count': 190},
      ],
      // بلا debt_sum (خادم اليوم) ⇒ لا خطّ «الدين» صفراً
      'timeseries': [
        for (var d = 1; d <= 22; d++) {'date': '2026-11-${d.toString().padLeft(2, '0')}', 'payments_sum': r(500000 + d * 1000), 'payments_count': 9},
      ],
      'stacked': [
        {'action_type': 'SUBSCRIBER_ACTIVATE', 'count': 182, 'amount_sum': r(12600000)},
      ],
      'recentLogs': [
        log(1, 'SUBSCRIBER_ACTIVATE', 'تفعيل نقدي — FTTH 50 ميغا', 35000, 'محمد', 'عبد الله', '2026-11-22 15:05:00'),
        log(2, 'BALANCE_DEDUCT', 'تسديد دين', 20000, 'سارة', 'علي', '2026-11-22 14:40:00', emp: 'زينب'),
        log(3, 'SUBSCRIBER_ACTIVATE', 'تفعيل غير نقدي — Gaming 100', 45000, 'حسن', 'كاظم', '2026-11-22 13:12:00'),
        log(4, 'SUBSCRIBER_EXTEND', 'تمديد شهر — D-Active 75', 25000, 'زهراء', 'محمود', '2026-11-21 18:30:00', emp: 'حسين'),
        log(5, 'SUBSCRIBER_ACTIVATE', 'تفعيل نقدي — FTTH 50 ميغا', 35000, 'علي', 'جبار', '2026-11-21 17:15:00'),
        log(6, 'BALANCE_ADD', 'إضافة دين', 45000, 'كرار', 'هادي', '2026-11-21 16:02:00'),
      ],
    },
  };
}

class _Server implements HttpClientAdapter {
  _Server(this.inner);
  final VisualServer inner;

  /// طلبات التقرير بترتيبها: (مفتاح الشركة، المعاملات).
  final finance = <(String?, Map<String, dynamic>)>[];

  /// شركاتٌ يتعذّر تقريرها الآن.
  final failing = <String>{};

  ResponseBody _json(Object body, String? key) => ResponseBody.fromString(jsonEncode(body), 200, headers: {
        Headers.contentTypeHeader: ['application/json'],
        if (key != null) 'x-company-key': [key],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final p = o.uri.path;
    final key = o.headers['x-company-key']?.toString();
    if (o.method.toUpperCase() == 'GET' && p == '/api/reports/finance') {
      finance.add((key, Map<String, dynamic>.from(o.queryParameters)));
      if (key != null && failing.contains(key)) return _json({'success': false, 'message': 'انتهت جلستها'}, key);
      final prev = o.queryParameters['limit_logs']?.toString() == '1';
      return _json(_financeBody((key == _kEarth ? 0.73 : 1) * (prev ? 0.9 : 1)), key);
    }
    if (key != null) return _json({'success': true, 'data': const []}, key);
    return inner.fetch(o, body, cancel);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  // ═══════════════════════════════ ١) الفترات ═══════════════════════════════

  group('RpRange', () {
    test('الفترات الجاهزة من الأحد ٢٢ نوفمبر — الأسبوع يبدأ الإثنين', () {
      RpRange of(RpPreset p) => RpRange.of(p, now: _now);
      expect([_d(of(RpPreset.today).from), _d(of(RpPreset.today).to)], ['2026/11/22', '2026/11/22']);
      expect(of(RpPreset.today).to, DateTime(2026, 11, 22, 23, 59, 59));
      expect(_d(of(RpPreset.yesterday).from), '2026/11/21');
      expect([_d(of(RpPreset.thisWeek).from), _d(of(RpPreset.thisWeek).to)], ['2026/11/16', '2026/11/22']);
      expect([_d(of(RpPreset.lastWeek).from), _d(of(RpPreset.lastWeek).to)], ['2026/11/09', '2026/11/15']);
      expect([_d(of(RpPreset.thisMonth).from), _d(of(RpPreset.thisMonth).to)], ['2026/11/01', '2026/11/22']);
      expect([_d(of(RpPreset.lastMonth).from), _d(of(RpPreset.lastMonth).to)], ['2026/10/01', '2026/10/31']);
      expect([_d(of(RpPreset.last30).from), _d(of(RpPreset.last30).to)], ['2026/10/24', '2026/11/22']);
      expect(of(RpPreset.last30).days, 30);
      expect([_d(of(RpPreset.thisYear).from), _d(of(RpPreset.thisYear).to)], ['2026/01/01', '2026/11/22']);
      // المخصّصة بالمقلوب تُعدَّل لا تُرفض
      final c = RpRange.of(RpPreset.custom, now: _now, from: DateTime(2026, 11, 10), to: DateTime(2026, 11, 3));
      expect([_d(c.from), _d(c.to), c.days], ['2026/11/03', '2026/11/10', 8]);
    });

    test('ما تُقارن به: الأيّام نفسها من الشهر/الأسبوع الماضي، والكاملة بالكاملة، والطول نفسه قبلها', () {
      String pv(RpRange r) => '${_d(r.previous.from)}–${_d(r.previous.to)}';
      expect(pv(RpRange.of(RpPreset.thisMonth, now: _now)), '2026/10/01–2026/10/22');
      expect(pv(RpRange.of(RpPreset.lastMonth, now: _now)), '2026/09/01–2026/09/30');
      expect(pv(RpRange.of(RpPreset.thisWeek, now: _now)), '2026/11/09–2026/11/15');
      expect(pv(RpRange.of(RpPreset.today, now: _now)), '2026/11/21–2026/11/21');
      expect(pv(RpRange.of(RpPreset.last30, now: _now)), '2026/09/24–2026/10/23');
      expect(pv(RpRange.of(RpPreset.thisYear, now: _now)), '2025/01/01–2025/11/22');
      expect(pv(RpRange.of(RpPreset.custom, now: _now, from: DateTime(2026, 11, 10), to: DateTime(2026, 11, 14))), '2026/11/05–2026/11/09');
      // ٣١ آذار ⇐ شباط ينتهي يوم ٢٨ (لا ٣ آذار)، و٢٩ شباط ٢٠٢٨ ⇐ ٢٨ شباط ٢٠٢٧
      expect(pv(RpRange.of(RpPreset.thisMonth, now: DateTime(2026, 3, 31))), '2026/02/01–2026/02/28');
      expect(pv(RpRange.of(RpPreset.thisYear, now: DateTime(2028, 2, 29))), '2027/01/01–2027/02/28');
      // طولها كطول الأصل
      for (final p in RpRange.presets) {
        final r = RpRange.of(p, now: _now);
        if (p == RpPreset.thisMonth || p == RpPreset.lastMonth || p == RpPreset.thisYear) continue;
        expect(r.previous.days, r.days, reason: p.name);
      }
    });

    test('الحفظ: الجاهزة باسمها (تُحسب من جديد)، والمخصّصة بتاريخيها، والمجهول ⇐ هذا الشهر', () {
      final c = RpRange.of(RpPreset.custom, now: _now, from: DateTime(2026, 11, 3), to: DateTime(2026, 11, 10));
      expect(RpRange.fromKey(c.key, now: _now), c);
      expect(RpRange.fromKey('thisMonth', now: DateTime(2026, 12, 5)).from, DateTime(2026, 12, 1));
      expect(RpRange.fromKey('شيء', now: _now).preset, RpPreset.thisMonth);
      expect(RpRange.fromKey(null, now: _now).preset, RpPreset.thisMonth);
    });

    test('الفرق: بلا أساس (صفر أو مجهول) ⇐ null لا «∞»، والسالب بقيمته المطلقة', () {
      expect(rpDelta(110, 100), closeTo(0.10, 1e-9));
      expect(rpDelta(5, 0), isNull);
      expect(rpDelta(5, null), isNull);
      expect(rpDelta(-50, -100), closeTo(0.5, 1e-9));
    });
  });

  group('RpPrefs', () {
    test('مدراء الشركة المفتوحة يُحفظون معها ويُسقطون حين تُفتح غيرها — ومفاتيح «كل الشركات» تبقى', () async {
      SharedPreferences.setMockInitialValues({});
      final v = RpFilterValue(
        range: RpRange.of(RpPreset.lastMonth, now: _now),
        compare: false,
        managers: {
          RpPrefs.openGroup: {'101'},
          _kEarth: {'5'},
        },
        employees: {RpPrefs.openGroup: '7', _kSup: '8'},
        types: const ['ADMIN_EXPENSE'],
      );
      await RpPrefs.save('t', v, openTag: '11');
      final same = await RpPrefs.load('t', now: _now, openTag: '11');
      expect(same.range.preset, RpPreset.lastMonth);
      expect(same.compare, isFalse);
      expect(same.types, ['ADMIN_EXPENSE']);
      expect(same.managers, {
        RpPrefs.openGroup: {'101'},
        _kEarth: {'5'},
      });
      expect(same.employees, {RpPrefs.openGroup: '7', _kSup: '8'});
      final other = await RpPrefs.load('t', now: _now, openTag: 'earthlink:22');
      expect(other.managers, {
        _kEarth: {'5'},
      }, reason: '«علي» (101) في شركةٍ لا يصير 101 في غيرها');
      expect(other.employees, {_kSup: '8'});
      expect(other.range.preset, RpPreset.lastMonth, reason: 'الفترة والنوع ليسا من شركة');
      expect(other.types, ['ADMIN_EXPENSE']);
    });
  });

  // ═══════════════════════════════ ٢) الأرقام ═══════════════════════════════

  group('FinanceView', () {
    test('البطاقة الكبرى: «الصافي» النقديّ بلا كلفة، و«صافي الربح بعد كلفة الباقات» معها — وفرقها عن السابقة', () {
      const k = FinanceKPIs(activateCashSum: 1000, debtPaySum: 500, expensesSum: 200, balanceAddSum: 100, activateNonCashSum: 400);
      final h = FinanceView.hero(k, const FinanceKPIs(activateCashSum: 1000));
      expect(h.label, 'الصافي');
      expect(h.value, 1200); // 1500 − 200 − 100
      expect(h.delta, closeTo(0.2, 1e-9));
      const withCost = FinanceKPIs(activateCashSum: 1000, activateNonCashSum: 400, expensesSum: 200, packageCost: PackageCostKpis(sum: 300));
      final c = FinanceView.hero(withCost, null);
      expect(c.label, 'صافي الربح بعد كلفة الباقات');
      expect(c.value, 900); // المبيعات 1400 − 200 − 300
      expect(c.delta, isNull);
      expect(FinanceView.hero(const FinanceKPIs(expensesSum: 50), null).tone, RpTone.loss);
    });

    test('البطاقات: «تسديد الديون» بلا المقدّم نقداً، و«إضافة دين» اليدويّة وحدها، والمشروطة حين يوجد ما تعرضه', () {
      const k = FinanceKPIs(debtPaySum: 900, creditCashSum: 300, balanceAddSum: 500, balanceAddSalesSum: 200, creditCompSum: 40);
      final byId = {for (final x in FinanceView.kpis(k, null)) x.id: x};
      expect(byId[FinanceKpiIds.debtPay]!.value, 600);
      expect(byId[FinanceKpiIds.debtAdd]!.value, 300);
      expect(byId[FinanceKpiIds.creditCash]!.value, 300);
      expect(byId[FinanceKpiIds.creditComp]!.value, 40);
      expect(byId[FinanceKpiIds.expenses]!.upIsGood, isFalse);
      expect(byId.containsKey(FinanceKpiIds.packageCost), isFalse, reason: 'لا كلفة ⇒ لا بطاقة «صفر»');
      final plain = {for (final x in FinanceView.kpis(const FinanceKPIs(), null)) x.id};
      expect(plain.contains(FinanceKpiIds.creditCash), isFalse);
      expect(plain.contains(FinanceKpiIds.goodsRevenue), isFalse);
    });

    test('حركات البطاقة: ما يصنع رقمها وحده', () {
      final logs = [
        _log(1, 'SUBSCRIBER_ACTIVATE', 35000, desc: 'تفعيل نقدي'),
        _log(2, 'SUBSCRIBER_ACTIVATE', 45000, desc: 'تفعيل غير نقدي'),
        _log(3, 'BALANCE_ADD', 45000, desc: 'إضافة دين'),
        _log(4, 'BALANCE_ADD', -10000, desc: 'إضافة رصيد', credit: true, kind: 'cash'),
        _log(5, 'BALANCE_ADD', 15000, desc: 'دين - بيع #12'),
        _log(6, 'BALANCE_DEDUCT', 20000),
        _log(7, 'ADMIN_EXPENSE', 5000),
      ];
      List<int> ids(String id) => [for (final l in logs.where(FinanceView.drill(id))) l.id];
      expect(ids(FinanceKpiIds.activateCash), [1]);
      expect(ids(FinanceKpiIds.activateNonCash), [2]);
      expect(ids(FinanceKpiIds.debtAdd), [3], reason: 'لا المقدّم ولا دين البيع');
      expect(ids(FinanceKpiIds.creditCash), [4]);
      expect(ids(FinanceKpiIds.debtPay), [6]);
      expect(ids(FinanceKpiIds.expenses), [7]);
      expect(ids(FinanceKpiIds.cash), [1, 4, 6], reason: 'ما دخل الصندوق نقداً');
      expect(ids(FinanceKpiIds.hero).length, logs.length);
    });

    test('الأيّام: بتوقيت الجهاز، الأحدث أوّلاً، مجموع كلّ يوم نقدُه، و[limit] يقصّ السطور لا العدد', () {
      final logs = [
        _log(1, 'SUBSCRIBER_ACTIVATE', 35000, desc: 'تفعيل نقدي', at: '2026-11-22 09:00:00'),
        _log(2, 'SUBSCRIBER_ACTIVATE', 45000, desc: 'تفعيل غير نقدي', at: '2026-11-22 08:00:00'),
        _log(3, 'BALANCE_DEDUCT', 20000, at: '2026-11-21 22:30:00'),
        _log(4, 'ADMIN_EXPENSE', 5000, at: '2026-11-20 10:00:00'),
      ];
      String day(String at) => iqDateOf(DateTime.parse('${at.replaceFirst(' ', 'T')}Z').toLocal());
      final days = FinanceView.days(logs, limit: 3);
      final order = <String>[];
      for (final l in logs) {
        if (!order.contains(day(l.createdAt))) order.add(day(l.createdAt));
      }
      expect([for (final d in days) d.date], order.take(days.length).toList());
      num cash(FinanceLog l) => l.id == 1 ? 35000 : (l.id == 3 ? 20000 : 0); // غير النقديّ والصرفيّة لا يدخلان «واصل»
      for (final d in days) {
        final mine = logs.where((l) => day(l.createdAt) == d.date);
        expect(d.sum, mine.fold<num>(0, (a, l) => a + cash(l)), reason: d.date);
        expect(d.count, mine.length, reason: 'عدد اليوم كلّه ولو قُصّت سطوره');
      }
      expect(days.fold<int>(0, (a, d) => a + d.rows.length), 3);
      final r = FinanceView.row(logs.last);
      expect(r.negative, isTrue);
      expect(r.tone, RpTone.loss);
    });

    test('البحث: الاسم واليوزر والوصف، والأرقام بأيّ صيغة', () {
      final logs = [
        _log(1, 'SUBSCRIBER_ACTIVATE', 1, first: 'زهراء', user: 'z44'),
        _log(2, 'SUBSCRIBER_ACTIVATE', 1, first: 'علي', user: 'ali7', desc: 'FTTH 50'),
      ];
      expect([for (final l in FinanceView.search(logs, 'زهر')) l.id], [1]);
      expect([for (final l in FinanceView.search(logs, 'Z٤٤')) l.id], [1]);
      expect([for (final l in FinanceView.search(logs, 'ftth')) l.id], [2]);
      expect(FinanceView.search(logs, '  ').length, 2);
    });

    test('«يوماً بيوم»: أيّامٌ متّصلة بترتيبها ولو عبرت الشهر، والغائب صفر، وما زاد عن شهرين شهراً شهراً', () {
      final series = [
        FinanceDayRow(day: DateTime(2026, 10, 30), revenue: 700, count: 1),
        FinanceDayRow(day: DateTime(2026, 11, 2), revenue: 900, count: 1),
      ];
      final last30 = FinanceView.trend(series, RpRange.of(RpPreset.last30, now: _now));
      expect(last30.length, 30);
      expect([for (final p in last30) p.day], [for (var d = 24; d <= 31; d++) d, for (var d = 1; d <= 22; d++) d]);
      expect(last30[6].a, 700);
      expect(last30[9].a, 900);
      expect(last30.where((p) => p.a != 0).length, 2);
      final year = FinanceView.trend(series, RpRange.of(RpPreset.thisYear, now: _now));
      expect([for (final p in year) p.day], [for (var m = 1; m <= 11; m++) m]);
      expect(year[9].a, 700);
      expect(year[10].a, 900);
      expect(FinanceView.trend(series, RpRange.of(RpPreset.today, now: _now)), isEmpty);
    });

    test('السطور مقطوعةٌ عند سقف الخادم أو حين يقول إنّها ناقصة', () {
      FinanceReport rep(int n, {List<String> parts = const []}) => FinanceReport(
            kpis: const FinanceKPIs(),
            recentLogs: [for (var i = 0; i < n; i++) _log(i, 'SUBSCRIBER_EXTEND', 1)],
            unavailableParts: parts,
          );
      expect(FinanceView.truncated(rep(10)), isFalse);
      expect(FinanceView.truncated(rep(PackageCostKpis.recentLogsServerCap)), isTrue);
      expect(FinanceView.truncated(rep(3, parts: ['recent_logs'])), isTrue);
    });
  });

  // ═══════════════════════════════ ٣) الشاشة ═══════════════════════════════

  group('الشاشة', () {
    setUpAll(visualSetUpAll);
    late _Server server;

    Future<void> up({Map<String, Object>? prefs}) async {
      server = _Server(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      if (prefs != null) SharedPreferences.setMockInitialValues(prefs);
      FinanceReportV2Screen.clock = () => _now;
    }

    Future<void> down(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      MergedMode.reset();
      FinanceReportV2Screen.clock = DateTime.now;
      await visualTearDown();
    }

    Future<void> open(WidgetTester t) async {
      await pumpVisual(t, const VisualDevice('', Size(430, 2400), 2), home: (_) => const FinanceReportV2Screen());
      for (var i = 0; i < 10; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> merged(WidgetTester t) async {
      AccountApi.tokenSource = ({bool force = false}) async => 'acct';
      MergedMode.reset();
      MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
      expect(await t.runAsync(() => MergedMode.enter()), isTrue);
    }

    RpHeroKpi hero(WidgetTester t) => t.widget<RpHeroKpi>(find.byType(RpHeroKpi));

    testWidgets('شركة منفردة: هذا الشهر حتى اليوم ثمّ الأيّام نفسها من الشهر الماضي بسطرٍ واحد — والصافي وفرقه', (t) async {
      await up();
      try {
        await open(t);
        expect(server.finance.length, 2);
        final (k1, cur) = server.finance[0];
        expect(k1, isNull, reason: 'الشركة المفتوحة بلا توجيه');
        expect(cur['date_from'], '2026-11-01 00:00:00');
        expect(cur['date_to'], '2026-11-22 23:59:59');
        expect(cur['limit_logs'], '2000');
        final (_, prev) = server.finance[1];
        expect(prev['date_from'], '2026-10-01 00:00:00');
        expect(prev['date_to'], '2026-10-22 23:59:59');
        expect(prev['limit_logs'], '1', reason: 'المقارنة أرقامٌ وحدها');
        expect(hero(t).kpi.value, 9850000);
        expect(hero(t).kpi.delta, closeTo((9850000 - 8865000) / 8865000, 1e-9));
        final trend = t.widget<RpTrendCard>(find.byType(RpTrendCard));
        expect(trend.points.length, 22);
        expect(trend.bLabel, isNull, reason: 'الخادم لا يرسل الدين يوماً بيوم ⇒ لا خطّ صفرٍ كاذب');
        expect(find.byType(RpCompanyChips), findsNothing);
        expect(find.byType(RpCompanyTable), findsNothing);
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });

    testWidgets('لمس بطاقة ⇒ حركاتها وحدها؛ والبحث يصفّي الحركات', (t) async {
      await up();
      try {
        await open(t);
        await t.tap(find.text('تفعيل بالدين'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        final sheet = find.byType(RpDrillSheet);
        expect(sheet, findsOneWidget);
        expect(find.descendant(of: sheet, matching: find.text('حسن كاظم')), findsOneWidget);
        expect(find.descendant(of: sheet, matching: find.text('محمد عبد الله')), findsNothing);
        Navigator.of(t.element(sheet)).pop();
        await t.pump(const Duration(milliseconds: 400));

        final rows = find.byType(RpRowsCard);
        await t.enterText(find.descendant(of: rows, matching: find.byType(TextField)), 'زهراء');
        await t.pump(const Duration(milliseconds: 200));
        expect(find.descendant(of: rows, matching: find.text('زهراء محمود')), findsOneWidget);
        expect(find.descendant(of: rows, matching: find.text('محمد عبد الله')), findsNothing);
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });

    testWidgets('آخر 30 يوماً: من ٢٤ أكتوبر، والمقارنة بالثلاثين قبلها، و«يوماً بيوم» بترتيبه عبر الشهرين', (t) async {
      await up(prefs: {'report.v2.finance': jsonEncode({'p': 'last30'})});
      try {
        await open(t);
        expect(server.finance[0].$2['date_from'], '2026-10-24 00:00:00');
        expect(server.finance[1].$2['date_from'], '2026-09-24 00:00:00');
        expect(server.finance[1].$2['date_to'], '2026-10-23 23:59:59');
        final trend = t.widget<RpTrendCard>(find.byType(RpTrendCard));
        expect([for (final p in trend.points) p.day], [for (var d = 24; d <= 31; d++) d, for (var d = 1; d <= 22; d++) d]);
        // الرسم نفسه: المحور بترتيب النقاط (رقم اليوم محوراً كان يرجع من 31 إلى 1)، وخطٌّ واحد بلا دين الخادم
        final chart = t.widget<LineChart>(find.descendant(of: find.byType(RpTrendCard), matching: find.byType(LineChart)));
        expect(chart.data.lineBarsData.length, 1);
        final xs = [for (final s in chart.data.lineBarsData.first.spots) s.x];
        expect(xs, [for (var i = 0; i < 30; i++) i.toDouble()]);
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });

    testWidgets('فلتر النوع: الأرقام من السطور كالشاشة السابقة، بلا طلب مقارنة ولا «يوماً بيوم»', (t) async {
      await up(prefs: {
        'report.v2.finance': jsonEncode({
          'p': 'thisMonth',
          't': ['SUBSCRIBER_ACTIVATE_CASH'],
        }),
      });
      try {
        await open(t);
        expect(server.finance.length, 1, reason: 'لا مقارنة تحت فلتر النوع ⇒ لا طلب لها');
        expect(hero(t).kpi.value, 70000, reason: 'تفعيلان نقديّان 35,000 من السطور');
        expect(hero(t).kpi.delta, isNull);
        expect(find.byType(RpTrendCard), findsNothing);
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });

    testWidgets('كل الشركات: كلّ شركةٍ بمفتاحها ومديرها، والمجموع = جمع الشركات، و«الشركات · 2 من 2»', (t) async {
      await up();
      try {
        await merged(t);
        await open(t);
        final cur = [for (final r in server.finance) if (r.$2['limit_logs'] == '2000') r];
        expect({for (final r in cur) r.$1: r.$2['user_ids']}, {_kSup: '11', _kEarth: 'earthlink:22'});
        expect(server.finance.where((r) => r.$2['limit_logs'] == '1').length, 2, reason: 'مقارنةٌ لكلّ شركة');
        final table = t.widget<RpCompanyTable>(find.byType(RpCompanyTable));
        expect(table.lines.map((l) => l.state), everyElement(RpCompanyState.ok));
        expect(table.total[2], 9850000 + 7190000);
        expect(hero(t).kpi.value, 17040000);
        expect(hero(t).kpi.delta, isNotNull);
        expect(find.text('الشركات · 2 من 2'), findsOneWidget);
        expect(table.outside, isNull);
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });

    testWidgets('كل الشركات: المتعذّرة تُسمّى خارج المجموع ولا تُجمع صفراً — و«أعد» يعيدها إليه', (t) async {
      await up();
      try {
        await merged(t);
        server.failing.add(_kEarth);
        await open(t);
        var table = t.widget<RpCompanyTable>(find.byType(RpCompanyTable));
        expect(table.lines.firstWhere((l) => l.company.key == _kEarth).state, RpCompanyState.failed);
        expect(table.outside, contains('ايرث لنك'));
        expect(hero(t).kpi.value, 9850000, reason: 'سوبرنت وحدها');

        server.failing.clear();
        await t.tap(find.text('أعد'));
        for (var i = 0; i < 8; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          await t.pump(const Duration(milliseconds: 100));
        }
        table = t.widget<RpCompanyTable>(find.byType(RpCompanyTable));
        expect(table.lines.map((l) => l.state), everyElement(RpCompanyState.ok));
        expect(hero(t).kpi.value, 17040000);
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });
  });
}
