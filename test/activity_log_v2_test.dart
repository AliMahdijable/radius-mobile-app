import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/reports_api.dart';
import 'package:rad_mysvcs/screens/reports/v2/activity_log_v2_screen.dart';
import 'package:rad_mysvcs/screens/reports/v2/activity_log_view.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_export.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_perm/visual_perm_harness.dart';

// «سجلّ الحركات» على الشكل الموحّد (٢٢ نوفمبر — «كمل بقية التقارير»): كلّ حركات الفترة صفحةً صفحة بلا الإشعارات (الخادم 9bfabd2:
// exclude_types/activity_types)، والصرفيّات من قائمتها للمفتوحة، و«الدين بعدها» على سطره، والتصدير بالفلاتر حرفاً وكاملاً.

final _now = DateTime(2026, 11, 22, 18); // الأحد — «هذا الأسبوع» من 16 نوفمبر

Map<String, Object?> _row(int id, String type, String desc, String at, {num? money, num? balance, String? emp}) => {
      'id': id,
      'action_type': type,
      'action_description': desc,
      'admin_username': 'admin@sup',
      if (emp != null) 'acting_employee_full_name': emp,
      'user_username': 'u$id',
      'user_firstname': 'مشترك',
      'user_lastname': '$id',
      'created_at': at,
      'from_sas': 0,
      if (money != null) 'money_amount': '$money.00',
      if (balance != null) 'balance_after': '$balance.00',
      'action_data': '{}',
    };

/// يومٌ: تفعيلان نقديّان، تسديد (والدين بعده)، إضافة دين، تعديل مشترك، و4 إشعارات آليّة.
List<Map<String, Object?>> _day(int d) {
  String at(int h) => '2026-11-${d.toString().padLeft(2, '0')} ${h.toString().padLeft(2, '0')}:00:00';
  final b = d * 100;
  return [
    _row(b + 1, 'SUBSCRIBER_ACTIVATE', 'تفعيل نقدي — FTTH 50', at(15), money: 35000),
    _row(b + 2, 'SUBSCRIBER_ACTIVATE', 'تفعيل نقدي — Gaming 100', at(14), money: 45000, emp: 'زينب'),
    _row(b + 3, 'DEBT_PAY', 'تسديد دين', at(13), money: 20000, balance: -5000),
    _row(b + 4, 'BALANCE_ADD', 'إضافة دين', at(12), money: 10000, balance: -15000),
    _row(b + 5, 'SUBSCRIBER_EDIT', 'تعديل بيانات المشترك', at(11)),
    for (var i = 0; i < 4; i++) _row(b + 10 + i, 'EXPIRY_NOTIFICATION', 'إشعار انتهاء', at(10)),
  ];
}

List<Map<String, Object?>> _month() => [for (var d = 22; d >= 1; d--) ..._day(d)];

const _kSup = 'c000000000a01';
const _kEarth = 'c000000000a02';

class _Server implements HttpClientAdapter {
  _Server(this.inner);
  final VisualServer inner;
  final rows = <String?, List<Map<String, Object?>>>{};
  final asked = <(String?, Map<String, dynamic>)>[];
  final expensesAsked = <(String?, Map<String, dynamic>)>[];
  final failing = <String>{};

  ResponseBody _json(Object body, String? key) => ResponseBody.fromString(jsonEncode(body), 200, headers: {
        Headers.contentTypeHeader: ['application/json'],
        if (key != null) 'x-company-key': [key],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final key = o.headers['x-company-key']?.toString();
    final q = Map<String, dynamic>.from(o.queryParameters);
    if (o.method.toUpperCase() == 'GET' && o.uri.path == '/api/activities') {
      asked.add((key, q));
      if (key != null && failing.contains(key)) return _json({'success': false, 'message': 'انتهت جلستها'}, key);
      final lo = '${q['date_from']}', hi = '${q['date_to']}';
      final inT = '${q['activity_types'] ?? ''}'.split(',').where((s) => s.isNotEmpty).toSet();
      final exT = '${q['exclude_types'] ?? ''}'.split(',').where((s) => s.isNotEmpty).toSet();
      final all = [
        for (final r in rows[key] ?? const <Map<String, Object?>>[])
          if ('${r['created_at']}'.compareTo(lo) >= 0 &&
              '${r['created_at']}'.compareTo(hi) <= 0 &&
              (inT.isEmpty || inT.contains(r['action_type'])) &&
              !exT.contains(r['action_type']))
            r,
      ];
      final limit = int.tryParse('${q['limit']}') ?? 100;
      final page = int.tryParse('${q['page'] ?? 1}') ?? 1;
      return _json({
        'success': true,
        'data': all.skip((page - 1) * limit).take(limit).toList(),
        'pagination': {'total': all.length, 'page': page, 'limit': limit},
      }, key);
    }
    if (o.method.toUpperCase() == 'GET' && o.uri.path == '/api/admin/expenses') {
      expensesAsked.add((key, q));
      return _json({
        'success': true,
        'expenses': [
          {'id': 1, 'amount': 15000, 'expense_date': '2026-11-20', 'note': 'وقود المولّدة'},
          {'id': 2, 'amount': 5000, 'expense_date': '2026-11-21', 'note': 'قرطاسية'},
        ],
        'total': 20000,
      }, key);
    }
    if (key != null) return _json({'success': true, 'data': const []}, key);
    return inner.fetch(o, body, cancel);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _companies() => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kSup, 'code': 'supernet', 'username': 'admin@sup', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': '11', 'ns': 'nA', 'currency': 'IQD', 'color_index': 0},
        {'key': _kEarth, 'code': 'earthlink', 'username': 'admin@el', 'name': 'ايرث لنك', 'status': 'ok', 'admin_id': 'earthlink:22', 'ns': 'nB', 'currency': 'IQD', 'color_index': 1},
      ],
    };

void main() {
  group('ActivityLogView', () {
    List<ActivityRow> rows(List<Map<String, Object?>> raw) => [for (final m in raw) ActivityRow.fromJson(Map<String, dynamic>.from(m))!];

    test('الإشعارات خارج السجلّ، والأعداد، والمال على سطره وحده (والتعديل بلا رقم)', () {
      final r = ActivityLogView.filter(rows(_day(20)), const []);
      expect(r.length, 5);
      final k = {for (final x in ActivityLogView.kpis(r)) x.id: x.value};
      expect(k, {LogKpiIds.all: 5, LogKpiIds.subs: 2, LogKpiIds.debts: 2, LogKpiIds.expenses: 0});
      final edit = r.firstWhere((x) => x.actionType == 'SUBSCRIBER_EDIT');
      expect(ActivityLogView.moneyOf(edit), isNull);
      final pay = r.firstWhere((x) => x.actionType == 'DEBT_PAY');
      expect(ActivityLogView.moneyOf(pay), 20000);
      final row = ActivityLogView.row(pay);
      expect(row.balanceAfter, -5000, reason: '«الدين بعدها» (طلب ٤ سبتمبر) على سطره');
      expect(rpBalanceText(-5000), 'الدين بعدها: 5,000 د.ع');
      expect(rpBalanceText(0), 'لا دين بعدها');
      expect(rpBalanceText(2500), 'رصيد دائن: 2,500 د.ع');
      expect(ActivityLogView.row(edit).amount, isNull);
    });

    test('مجموع اليوم ما دخل نقداً (تفعيلٌ نقديّ وتسديد)، والصرفيّة صفّاً بتاريخها', () {
      final r = [...rows(_day(20)), ActivityLogView.expenseRow(id: 1, amount: 15000, date: '2026-11-20', note: 'وقود')];
      final days = ActivityLogView.days(ActivityLogView.filter(r, const []));
      expect(days.single.sum, 35000 + 45000 + 20000);
      expect(days.single.count, 6);
      final exp = days.single.rows.firstWhere((x) => x.title == 'وقود' || x.detail.startsWith('وقود'));
      expect(exp.amount, 15000);
      expect(exp.negative, isTrue);
    });
  });

  group('الشاشة', () {
    setUpAll(visualSetUpAll);
    late _Server server;

    Future<void> up({Map<String, Object>? prefs}) async {
      server = _Server(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      if (prefs != null) SharedPreferences.setMockInitialValues(prefs);
      ActivityLogV2Screen.clock = () => _now;
    }

    Future<void> down(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      MergedMode.reset();
      ReportExportActions.debugSink = null;
      ActivityLogV2Screen.clock = DateTime.now;
      await visualTearDown();
    }

    Future<void> settleAsync(WidgetTester t, [int n = 12]) async {
      for (var i = 0; i < n; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> open(WidgetTester t) async {
      await pumpVisual(t, const VisualDevice('', Size(430, 2600), 2), home: (_) => const ActivityLogV2Screen());
      await settleAsync(t);
    }

    Map<String, num> kpis(WidgetTester t) => {for (final k in t.widget<RpKpiGrid>(find.byType(RpKpiGrid)).kpis) k.id: k.value};

    Future<void> tapExport(WidgetTester t, String label) async {
      await t.scrollUntilVisible(find.text(label), 600, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text(label));
      await settleAsync(t, 6);
    }

    testWidgets('هذا الأسبوع افتراضاً: الإشعارات تُستثنى من الخادم، والصرفيّات تُدمج، ولا مقارنة', (t) async {
      await up();
      server.rows[null] = _month();
      try {
        await open(t);
        expect(server.asked, isNotEmpty);
        expect(server.asked.first.$2['date_from'], '2026-11-16 00:00:00');
        expect(server.asked.first.$2['exclude_types'], 'EXPIRY_NOTIFICATION,NEAR_EXPIRY_NOTIFICATION,AUTO_NOTIFICATION');
        expect(server.asked.first.$2.containsKey('activity_types'), isFalse);
        expect(server.expensesAsked.single.$2['include_archived'], 1);
        final k = kpis(t);
        expect(k[LogKpiIds.all], 7 * 5 + 2, reason: '7 أيّام × 5 حركات + صرفيّتان');
        expect(k[LogKpiIds.expenses], 2);
        expect(find.text('قارن'), findsNothing, reason: 'سجلّ تدقيق بلا مقارنة');
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });

    testWidgets('نوعٌ مختار ⇒ activity_types من الخادم ولا صرفيّات؛ والتصدير به وبالبحث، ورأسه يسمّيهما، والصفوف كلّها', (t) async {
      await up(prefs: {
        'report.v2.activity_log': jsonEncode({
          'p': 'thisMonth',
          't': ['DEBT_PAY'],
        }),
      });
      server.rows[null] = _month();
      final got = <ReportExportRequest>[];
      ReportExportActions.debugSink = (r) async => got.add(r);
      try {
        await open(t);
        expect(server.asked.first.$2['activity_types'], 'DEBT_PAY');
        expect(server.asked.first.$2.containsKey('exclude_types'), isFalse);
        expect(server.expensesAsked, isEmpty, reason: 'نوعٌ ليس صرفيّة ⇒ لا قائمة صرفيّات');
        await tapExport(t, 'Excel');
        expect(got.single.rows.length, 22);
        expect(got.single.details, contains('عدد الحركات: 22'));
        expect(got.single.details.any((d) => d.startsWith('النوع: ')), isTrue);
        got.clear();
        final rows = find.byType(RpRowsCard);
        await t.scrollUntilVisible(find.descendant(of: rows, matching: find.byType(TextField)), 600,
            scrollable: find.byType(Scrollable).first);
        await t.enterText(find.descendant(of: rows, matching: find.byType(TextField)), '2003');
        await t.pump(const Duration(milliseconds: 200));
        await tapExport(t, 'PDF');
        expect(got.single.rows.length, 1);
        expect(got.single.details, contains('بحث: «2003»'));
        expect(got.single.columnWeights, isNotNull);
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });

    testWidgets('كل الشركات: كلّ شركةٍ بمفتاحها، والصرفيّات لا تُخلط (ويُقال)، والمتعذّرة خارج المجموع', (t) async {
      await up();
      server.rows[_kSup] = _month();
      server.rows[_kEarth] = _month();
      server.failing.add(_kEarth);
      try {
        AccountApi.tokenSource = ({bool force = false}) async => 'acct';
        MergedMode.reset();
        MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
        expect(await t.runAsync(() => MergedMode.enter()), isTrue);
        await open(t);
        expect({for (final a in server.asked) a.$1}, {_kSup, _kEarth});
        expect(server.expensesAsked, isEmpty);
        final table = t.widget<RpCompanyTable>(find.byType(RpCompanyTable));
        expect(table.lines.firstWhere((l) => l.company.key == _kEarth).state, RpCompanyState.failed);
        expect(kpis(t)[LogKpiIds.all], 7 * 5);
        expect(find.textContaining('الصرفيّات لا تُخلط هنا'), findsOneWidget);
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });
  });
}
