import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/balance_reports_api.dart';
import 'package:rad_mysvcs/screens/reports/balance_period_screen.dart';
import 'package:rad_mysvcs/screens/reports/balance_reports_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'employee_ledger/ledger_fixture.dart' show LedgerDiskLoader;

/// «تقارير الأرصدة» — عقد الخادم (١٦ نوفمبر): `balance_reports/server_contract.json` **ولّده كود الخادم الحيّ نفسه**
/// (server/balanceReports.js بمساراته كما هي، 9b13c86) على حركاتٍ تجريبيّة بقاعدةٍ في الذاكرة — لا يُكتب باليد
/// (المولّد: `~/kits/balance_reports/gen_contract.js <شجرة الخادم>` على الخادم، ونسخته `~/release_work/balance_reports/contract/`).
/// هنا: نماذج التطبيق تقرأ كلّ حقلٍ بمفتاحه الصحيح (مفتاحٌ خطأ = صفرٌ صامت على الشاشة)، مفتاحٌ جديد من الخادم بلا قرارٍ
/// هنا يُفشل الاختبار، ثمّ الشاشتان تعرضان الردّ الحقيقيّ بأرقامه وحالات ديونه الستّ.
/// الحركات: ثلاث فترات (مغلقة، بانتظار الإغلاق، جارية) فيها نقدي/آجل/جزئي بلهجتَي الساس وايرث لنك، دينٌ قديم، دينٌ يدويّ،
/// دفعةٌ مقدَّمة، نقدٌ زائد يسدّ الأقدم، تسديدٌ قبل الإغلاق وبعده، دينٌ لم يُسجَّل، دينٌ نقص خارج النظام، وإلغاء تسديد.
void main() {
  final contract = jsonDecode(File('test/balance_reports/server_contract.json').readAsStringSync()) as Map<String, dynamic>;
  Map<String, dynamic> data(String key) => (contract[key] as Map)['data'] as Map<String, dynamic>;
  final overviewJson = data('overview');
  final periodsJson = (overviewJson['periods'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> detailJson(int id) => ((contract['details'] as Map)['$id'] as Map)['data'] as Map<String, dynamic>;

  /// المقارنة: رقمٌ برقم، والنصّ الفارغ كغيابه.
  Object? norm(Object? v) => switch (v) {
        final num n => n.toDouble(),
        final String s when s.trim().isEmpty => null,
        _ => v,
      };
  void same(Object? model, Object? wire, String what) => expect(norm(model), norm(wire), reason: what);

  group('النماذج تقرأ ردّ الخادم الحقيقيّ حقلاً حقلاً', () {
    // مفتاح الخادم ⇒ قارئه في النموذج. null = لا يستعمله التطبيق عمداً (والسبب بجانبه).
    final periodFields = <String, Object? Function(BalancePeriod)?>{
      'id': (p) => p.id,
      'started_at_ms': (p) => p.startedAtMs,
      'ends_at_ms': (p) => p.endsAtMs,
      'amount': (p) => p.amount,
      'note': (p) => p.note,
      'state': (p) => p.state.name,
      'closed_at_ms': (p) => p.closedAtMs,
      'sales': (p) => p.sales,
      'cash_now': (p) => p.cashNow,
      'paid_in': (p) => p.paidIn,
      'collected': (p) => p.collected,
      'adjustments_sum': (p) => p.adjustmentsSum,
      'covered': null, // = collected + adjustments_sum (يُفحص أدناه)
      'remaining': (p) => p.remaining,
      'progress': (p) => p.progress,
      'can_close': (p) => p.canClose,
      'debts_created': (p) => p.debtsCreated,
      'debts_open': (p) => p.debtsOpen,
      'late_profit': (p) => p.lateProfit,
      'net': (p) => p.net,
      'profit': (p) => p.profit,
      'pocket_outstanding': (p) => p.pocketOutstanding,
      'written_off': (p) => p.writtenOff,
      'untracked': (p) => p.untracked,
      'income_in_window': (p) => p.incomeInWindow,
      'counts': null, // أدناه
      'adjustments': null, // أدناه
      'transfers': null, // أدناه
    };

    test('الفترات الثلاث: كلّ مفتاحٍ يرسله الخادم مقروءٌ بقيمته', () {
      final o = BalanceOverview.fromJson(overviewJson)!;
      expect(o.featureEnabled, isTrue);
      expect(o.periods.map((p) => p.state).toList(), [BalanceState.running, BalanceState.waiting, BalanceState.closed], reason: 'الأحدث أوّلاً');
      for (var i = 0; i < periodsJson.length; i++) {
        final j = periodsJson[i];
        final p = o.periods[i];
        expect(j.keys.toSet().difference(periodFields.keys.toSet()), isEmpty, reason: 'مفتاحٌ جديد من الخادم بلا قرارٍ في الاختبار');
        expect(periodFields.keys.toSet().difference(j.keys.toSet()), isEmpty, reason: 'مفتاحٌ يقرؤه التطبيق والخادم لا يرسله');
        for (final e in periodFields.entries) {
          if (e.value != null) same(e.value!(p), j[e.key], 'الفترة ${j['id']}: ${e.key}');
        }
        same(p.collected + p.adjustmentsSum, j['covered'], 'covered');
        final c = j['counts'] as Map;
        expect(c.keys.toSet(), {'cash', 'credit', 'partial', 'payments', 'activations'});
        expect([p.nCash, p.nCredit, p.nPartial, p.nPayments, p.nActivations], [c['cash'], c['credit'], c['partial'], c['payments'], c['activations']]);
        final t = j['transfers'] as Map;
        expect(t.keys.toSet(), {'count', 'sum'});
        same(p.transfersCount, t['count'], 'transfers.count');
        same(p.transfersSum, t['sum'], 'transfers.sum');
        final adj = (j['adjustments'] as List).cast<Map>();
        expect(p.adjustments.length, adj.length);
        for (var k = 0; k < adj.length; k++) {
          expect(adj[k].keys.toSet(), {'id', 'amount', 'source', 'note', 'created_at_ms'});
          final a = p.adjustments[k];
          expect([a.id, a.amount, a.source.wire, a.note, a.createdAtMs], [adj[k]['id'], (adj[k]['amount'] as num).toDouble(), adj[k]['source'], adj[k]['note'], adj[k]['created_at_ms']]);
        }
      }
      // أرقام السيناريو نفسها (محسوبةٌ باليد من الحركات): المغلقة 300 ألف — طبّلها 170 + تسوية 130، وبعد الإغلاق دخل 80
      final closed = o.periods.last;
      expect([closed.amount, closed.collected, closed.adjustmentsSum, closed.remaining, closed.lateProfit, closed.net, closed.profit, closed.pocketOutstanding, closed.debtsOpen],
          [300000, 170000, 130000, 0, 80000, -50000, 0, 50000, 50000]);
      final running = o.periods.first;
      expect([running.amount, running.collected, running.remaining, running.debtsCreated, running.debtsOpen, running.transfersCount, running.transfersSum], [400000, 95000, 305000, 135000, 90000, 2, 75000]);
    });

    test('الإجماليّات وجودة البيانات و«من أنا» واللوحة الفارغة', () {
      final t = overviewJson['totals'] as Map;
      final q = overviewJson['quality'] as Map;
      // closed_net و debts_open (إجماليّان) و rows و drift: لا يعرضها التطبيق
      expect(t.keys.toSet(), {'old_paid', 'manual_paid', 'other_paid', 'advance', 'closed_net', 'debts_open'});
      expect(q.keys.toSet(), {'rows', 'no_price', 'no_amount', 'no_snapshot', 'drift', 'transfers_unknown'});
      expect(overviewJson.keys.toSet(), {'feature_enabled', 'can_manage', 'now_ms', 'periods', 'totals', 'quality'});
      final o = BalanceOverview.fromJson(overviewJson)!;
      expect([o.oldPaid, o.manualPaid, o.otherPaid, o.advance], [t['old_paid'], t['manual_paid'], t['other_paid'], t['advance']].map((x) => (x as num).toDouble()).toList());
      expect([o.oldPaid, o.manualPaid], [30000, 25000], reason: 'دينٌ قديم ودينٌ يدويّ تسدّدا — خارج حساب الشحنات');
      expect([o.noPrice, o.noAmount, o.noSnapshot, o.transfersUnknown], [q['no_price'], q['no_amount'], q['no_snapshot'], q['transfers_unknown']]);
      final empty = BalanceOverview.fromJson(data('empty_overview'))!;
      expect([empty.featureEnabled, empty.periods.length], [true, 0]);
      expect(data('me_manager'), {'feature_enabled': true, 'can_manage': true, 'is_employee': false});
      expect(data('me_employee'), {'feature_enabled': true, 'can_manage': false, 'is_employee': true});
    });

    final actFields = <String, Object? Function(BalanceActMove)?>{
      'key': (m) => m.key,
      'kind': null, // يختار الصنف
      'at_ms': (m) => m.atMs,
      'sub': null, // معرّف المشترك — لا يُعرض
      'username': (m) => m.username,
      'package': (m) => m.package,
      'price': (m) => m.price,
      'pay': (m) => m.pay.name,
      'cash': (m) => m.cash,
      'debt': (m) => m.debt,
      'remaining': (m) => m.remaining,
      'debt_state': null, // أدناه (written_off ⇒ writtenOff)
      'turned': null, // أدناه
      'paid_in': (m) => m.paidIn,
      'paid_late': (m) => m.paidLate,
      'written_off': null, // حال الدين تكفي («نقص الدين بلا تسديد»)
      'untracked': (m) => m.untracked,
      'excess': (m) => m.excess,
      'last_paid_at_ms': (m) => m.lastPaidAtMs,
      'after_close': (m) => m.afterClose,
      'by': (m) => m.by,
    };
    final payFields = <String, Object? Function(BalancePayMove)>{
      'key': (m) => m.key,
      'at_ms': (m) => m.atMs,
      'username': (m) => m.username,
      'amount': (m) => m.amount,
      'after_close': (m) => m.afterClose,
      'advance': (m) => m.advance,
      'by': (m) => m.by,
    };

    test('حركات الفترات: التفعيل والتسديد والتسوية بكلّ حقولها، وحالات الدين الستّ', () {
      final seen = <BalanceDebtState>{};
      var acts = 0, pays = 0, adjusts = 0;
      for (final pj in periodsJson) {
        final dj = detailJson(pj['id'] as int);
        expect(dj.keys.toSet(), {'feature_enabled', 'period', 'filter', 'q', 'counts', 'movements'});
        final page = BalancePeriodPage.fromJson(dj)!;
        final items = ((dj['movements'] as Map)['items'] as List).cast<Map<String, dynamic>>();
        expect(page.items.length, items.length, reason: 'لا حركة تسقط عند القراءة');
        expect([page.total, page.offset], [(dj['movements'] as Map)['total'], (dj['movements'] as Map)['offset']]);
        expect((dj['counts'] as Map).keys.toSet(), BalanceFilter.values.map((f) => f.wire).toSet(), reason: 'فلاتر الخادم = فلاتر التطبيق');
        for (final f in BalanceFilter.values) {
          expect(page.counts[f], (dj['counts'] as Map)[f.wire], reason: 'عدد ${f.wire}');
        }
        same(page.period.collected, pj['collected'], 'فترة التفاصيل = فترة اللوحة');
        for (var i = 0; i < items.length; i++) {
          final j = items[i];
          final m = page.items[i];
          switch (j['kind']) {
            case 'activate':
              acts++;
              m as BalanceActMove;
              expect(j.keys.toSet().difference(actFields.keys.toSet()), isEmpty, reason: 'مفتاح تفعيلٍ جديد من الخادم');
              expect(actFields.keys.toSet().difference(j.keys.toSet()), isEmpty, reason: 'مفتاح تفعيلٍ لا يرسله الخادم');
              for (final e in actFields.entries) {
                if (e.value != null) same(e.value!(m), j[e.key], '${j['key']}: ${e.key}');
              }
              expect(m.debtState, switch (j['debt_state']) { 'written_off' => BalanceDebtState.writtenOff, final s => BalanceDebtState.values.byName('$s') }, reason: '${j['key']}');
              expect(m.turnedProfit, j['turned'] == 'profit');
              expect(j['turned'], anyOf(isNull, 'cash', 'profit'));
              seen.add(m.debtState);
            case 'payment':
              pays++;
              m as BalancePayMove;
              expect(j.keys.toSet(), {...payFields.keys, 'kind', 'sub'});
              for (final e in payFields.entries) {
                same(e.value(m), j[e.key], '${j['key']}: ${e.key}');
              }
            case 'adjust':
              adjusts++;
              m as BalanceAdjustMove;
              expect(j.keys.toSet(), {'key', 'kind', 'at_ms', 'amount', 'source', 'note'});
              expect([m.key, m.atMs, m.amount, m.source.wire, m.note], [j['key'], j['at_ms'], (j['amount'] as num).toDouble(), j['source'], j['note']]);
            default:
              fail('نوع حركةٍ لا يعرفه التطبيق: ${j['kind']}');
          }
        }
      }
      expect(seen, BalanceDebtState.values.toSet(), reason: 'العقد يغطّي حالات الدين كلّها');
      expect([acts, pays, adjusts], [19, 9, 1]);
    });

    test('علامة الدين من الردّ الحقيقيّ: تسدّد نقداً / صار ربحاً بعد الإغلاق / باقٍ / نقص / لم يُسجَّل', () {
      String? note(int period, String key) {
        final j = ((detailJson(period)['movements'] as Map)['items'] as List).cast<Map<String, dynamic>>().firstWhere((x) => x['key'] == key);
        return balanceDebtNote(BalanceMove.fromJson(j)! as BalanceActMove)?.text;
      }

      expect(note(1, 'a1003'), startsWith('كان دين وتسدّد — '), reason: 'تسدّد قبل الإغلاق ⇒ دخل «طبّلك»');
      expect(note(1, 'a1005'), startsWith('كان دين وتسدّد بعد الإغلاق — صار ربح — '));
      expect(note(1, 'a1008'), startsWith('كان دين وتسدّد بعد الإغلاق — صار ربح — '));
      expect(note(1, 'a1006'), 'تسدّد منه 10,000 · باقي 20,000');
      expect(note(1, 'a1012'), 'تسدّد منه 20,000 · باقي 15,000', reason: 'دفعةٌ مقدَّمة سدّت جزءاً من آجلٍ لاحق');
      expect(note(1, 'a1002'), isNull, reason: 'نقديّ بلا دين');
      expect(note(2, 'a1021'), 'نقص الدين بلا تسديد');
      expect(note(2, 'a1020'), 'الدين لم يُسجَّل على المشترك');
      expect(note(3, 'a1030'), 'دين باقي 30,000', reason: 'تسديده أُلغي فرجع الدين');
    });

    test('ردود الكتابة والرفض بشكلها: اللوحة الجديدة مع كلّ كتابة، والرفض برسالته ورمزه', () {
      for (final k in ['create_reply', 'adjust_reply', 'close_reply', 'reopen_reply']) {
        final r = contract[k] as Map;
        expect(r['success'], isTrue, reason: k);
        expect(BalanceOverview.fromJson(r['data']), isNotNull, reason: '$k يحمل اللوحة');
      }
      expect(BalanceOverview.fromJson((contract['close_reply'] as Map)['data'])!.periods.single.state, BalanceState.closed);
      final over = contract['over_remaining_error'] as Map;
      expect([over['status'], (over['body'] as Map)['code'], (over['body'] as Map)['success']], [409, 'OVER_REMAINING', false]);
      expect('${(over['body'] as Map)['message']}', contains('130,000'));
      expect((contract['note_required_error'] as Map)['status'], 400);
      expect(((contract['employee_overview'] as Map)['body'] as Map)['code'], 'MANAGER_ONLY');
      expect((contract['missing_period'] as Map)['status'], 404);
    });
  });

  group('الشاشتان تعرضان الردّ الحقيقيّ', () {
    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      PermissionsService.debugReset();
      PermissionsService.debugSet(isEmployee: false);
      BalanceReportsState.reset();
      ApiClient.dio.httpClientAdapter = _ContractServer(contract);
    });
    tearDown(PermissionsService.debugReset);

    Widget app(Widget child) => EasyLocalization(
          supportedLocales: const [Locale('ar'), Locale('en')],
          path: 'assets/translations',
          startLocale: const Locale('ar'),
          fallbackLocale: const Locale('ar'),
          saveLocale: false,
          assetLoader: const LedgerDiskLoader(),
          child: Builder(
            builder: (c) => MaterialApp(
              locale: c.locale,
              supportedLocales: c.supportedLocales,
              localizationsDelegates: c.localizationDelegates,
              home: Directionality(textDirection: TextDirection.rtl, child: child),
            ),
          ),
        );
    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Finder k(String key) => find.byKey(ValueKey(key));
    Finder inKey(String key, String text) => find.descendant(of: k(key), matching: find.text(text));
    Future<void> tap(WidgetTester t, Finder f) async {
      await t.ensureVisible(f);
      await t.pump();
      await t.tap(f);
      await settle(t);
    }

    testWidgets('الصفحة: الجارية بأرقامها وتنبيه التحويلات، «بانتظار الإغلاق»، المغلقة، وخارج الحساب', (t) async {
      t.view.physicalSize = const Size(400, 3200);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(const BalanceReportsScreen()));
      await settle(t);
      expect(t.takeException(), isNull);
      expect(t.widget<Text>(k('bal-amount')).data, '400,000 د.ع');
      expect(inKey('bal-stat-collected', '95,000 د.ع'), findsOneWidget);
      expect(inKey('bal-stat-remaining', '305,000 د.ع'), findsOneWidget);
      expect(inKey('bal-stat-debts', '90,000 د.ع'), findsOneWidget);
      expect(inKey('bal-stat-profit', '0 د.ع'), findsOneWidget);
      expect(t.widget<Text>(k('bal-transfers')).data, '2 تحويل رصيد لمدراء فرعيّين بمبلغ 75,000 د.ع — غير داخلة بالحساب');
      expect(find.descendant(of: k('bal-period-2'), matching: find.text('بانتظار الإغلاق')), findsOneWidget);
      expect(find.descendant(of: k('bal-period-2'), matching: find.text('160,000')), findsOneWidget);
      expect(find.descendant(of: k('bal-period-1'), matching: find.text('مغلقة')), findsOneWidget);
      expect(find.descendant(of: k('bal-period-1'), matching: find.text('170,000')), findsOneWidget);
      expect(inKey('bal-outside', '30,000 د.ع'), findsOneWidget);
      expect(inKey('bal-outside', '25,000 د.ع'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('تفاصيل المغلقة: الخلاصة بأرقام الخادم، ١٥ حركة، وعلامات الديون كما وقعت', (t) async {
      t.view.physicalSize = const Size(400, 4200);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(const BalanceReportsScreen()));
      await settle(t);
      await tap(t, find.descendant(of: k('bal-period-1'), matching: find.byType(InkWell)).first);
      expect(t.takeException(), isNull);
      expect(inKey('bal-sum-collected', '170,000 د.ع'), findsOneWidget);
      expect(inKey('bal-sum-late', '80,000 د.ع'), findsOneWidget);
      expect(inKey('bal-summary', 'مبيعات الفترة (8 تفعيل)'), findsOneWidget);
      expect(inKey('bal-summary', '300,000 د.ع'), findsWidgets);
      expect(find.text('الكل 15'), findsOneWidget);
      expect(find.byType(BalanceMoveRow), findsNWidgets(10));
      await tap(t, k('bal-moves-more'));
      expect(find.byType(BalanceMoveRow), findsNWidgets(15));
      final statuses = t.widgetList<BalanceMoveStatus>(k('bal-move-status')).map((c) => c.text).toList();
      expect(statuses.where((x) => x.startsWith('كان دين وتسدّد بعد الإغلاق — صار ربح — ')).length, 2);
      expect(statuses.where((x) => x.startsWith('كان دين وتسدّد — ')).length, 1);
      expect(statuses.where((x) => x.startsWith('تسدّد منه ')).length, 3);
      expect(statuses.where((x) => x == 'بعد الإغلاق — صار ربح').length, 2, reason: 'تسديدان بعد الإغلاق');
      expect(find.text('وزيادة 15,000 سدّت ديناً أقدم', findRichText: true), findsNothing, reason: 'جزءٌ من سطر التفاصيل لا نصٌّ مستقلّ');
      expect(find.textContaining('وزيادة 15,000 سدّت ديناً أقدم'), findsOneWidget);
      expect(find.textContaining('من دفعةٍ مقدَّمة'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 4));
    });
  });
}

/// يجيب بردود العقد كما هي: «من أنا»، اللوحة، وتفاصيل كلّ فترة (كلّ حركاتها في صفحةٍ واحدة).
class _ContractServer implements HttpClientAdapter {
  _ContractServer(this.contract);
  final Map<String, dynamic> contract;

  static final _period = RegExp(r'^/api/v2/balance-reports/periods/(\d+)$');

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    Object? body;
    var status = 200;
    final m = _period.firstMatch(o.path);
    if (o.path == '/api/v2/admin-widgets') {
      body = {'success': true, 'points': 0, 'balance': 120000};
    } else if (o.path == '/api/v2/balance-reports/me') {
      body = contract['me_manager'];
    } else if (o.path == '/api/v2/balance-reports' && o.method == 'GET') {
      body = contract['overview'];
    } else if (m != null && o.method == 'GET') {
      body = (contract['details'] as Map)[m.group(1)];
    }
    if (body == null) {
      status = 404;
      body = {'success': false, 'message': 'غير موجود'};
    }
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
