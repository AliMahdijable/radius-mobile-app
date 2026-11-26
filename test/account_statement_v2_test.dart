import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/core/util/order_rules.dart';
import 'package:rad_mysvcs/screens/reports/v2/account_statement_v2_screen.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_export.dart';
import 'package:rad_mysvcs/services/transfer_pay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_perm/visual_perm_harness.dart';

// «كشف حساب المشترك» على الشكل الموحّد (٢٢ نوفمبر): الأرقام كما كانت حرفاً من ملخّص الخادم، والفترة «آخر 90 يوماً» أوّل مرّة،
// والأنواع من الورقة إلى الخادم (action_types)، و«الدين بعدها» على كلّ سطر، والتصدير بالفلاتر والبحث ومعه «الرصيد بعدها».

final _now = DateTime(2026, 11, 22, 18);

class _Server implements HttpClientAdapter {
  _Server(this.inner);
  final VisualServer inner;
  final asked = <Map<String, dynamic>>[];

  /// «لم تُسحب / سُحبت» (٢٦ نوفمبر): سطر التسديد (2) بماستر، وردّ /api/v2/transfer-pots/rows — null = الحاضنة.
  Map<String, Object?>? twRows;
  final twAsked = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    if (twRows != null && o.uri.path == '/api/v2/transfer-pay') {
      return ResponseBody.fromString(jsonEncode({'success': true, 'data': {'available': true, 'methods': ['cash', 'zaincash', 'master', 'other'], 'names': []}}), 200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    if (twRows != null && o.uri.path == '/api/v2/transfer-pots/rows') {
      twAsked.add('${o.queryParameters['ids']}');
      return ResponseBody.fromString(jsonEncode({'success': true, 'data': {'rows': twRows, 'unmatched': 0}}), 200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    if (o.method.toUpperCase() == 'GET' && o.uri.path == '/api/reports/account-statement') {
      final q = Map<String, dynamic>.from(o.queryParameters);
      asked.add(q);
      final types = '${q['action_types'] ?? ''}'.split(',').where((s) => s.isNotEmpty).toSet();
      final tx = [
        {'id': 1, 'created_at': '2026-11-20 15:00:00', 'action_type': 'SUBSCRIBER_ACTIVATE', 'description': 'تفعيل غير نقدي — FTTH 50', 'amount': 35000, 'admin_name': 'admin@sup', 'balance_after': -35000},
        {'id': 2, 'created_at': '2026-11-21 12:00:00', 'action_type': 'DEBT_PAY', 'description': 'تسديد دين', 'amount': 20000, 'admin_name': 'زينب', 'balance_after': -15000,
          if (twRows != null) 'pay_kind': 'master'},
        {'id': 3, 'created_at': '2026-11-22 09:00:00', 'action_type': 'SUBSCRIBER_EXTEND', 'description': 'تمديد', 'amount': 0, 'admin_name': 'admin@sup'},
      ].where((t) => types.isEmpty || types.contains(t['action_type'])).toList().reversed.toList(); // ORDER BY created_at DESC كالخادم
      return ResponseBody.fromString(
          jsonEncode({
            'success': true,
            'data': {
              'transactions': tx,
              'summary': {'totalTransactions': tx.length, 'totalDebt': 15000, 'totalPayments': 20000, 'totalActivations': 1},
              'subscriber': {'username': 'u7', 'firstname': 'زهراء', 'lastname': 'محمود'},
            },
          }),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          });
    }
    return inner.fetch(o, body, cancel);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(visualSetUpAll);
  late _Server server;

  Future<void> up({Map<String, Object>? prefs}) async {
    server = _Server(await visualSetUp(s1bSasOwner));
    ApiClient.dio.httpClientAdapter = server;
    if (prefs != null) SharedPreferences.setMockInitialValues(prefs);
    AccountStatementV2Screen.clock = () => _now;
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    ReportExportActions.debugSink = null;
    AccountStatementV2Screen.clock = DateTime.now;
    await visualTearDown();
  }

  Future<void> open(WidgetTester t) async {
    await pumpVisual(t, const VisualDevice('', Size(430, 2400), 2),
        home: (_) => const AccountStatementV2Screen(username: 'u7', companyKey: null, displayName: 'زهراء محمود'));
    for (var i = 0; i < 10; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('آخر 90 يوماً أوّل مرّة، وأرقام الملخّص كما كانت، و«الدين بعدها» على السطور', (t) async {
    await up();
    try {
      await open(t);
      expect(server.asked.single['username'], 'u7');
      expect(server.asked.single['date_from'], '2026-08-25 00:00:00');
      expect(server.asked.single['date_to'], '2026-11-22 23:59:59');
      final hero = t.widget<RpHeroKpi>(find.byType(RpHeroKpi));
      expect(hero.kpi.value, 5000, reason: 'المدفوع 20,000 − الدين 15,000 = له 5,000 (معنى الكشف السابق)');
      expect(hero.kpi.tone, RpTone.money);
      final kpis = t.widget<RpKpiGrid>(find.byType(RpKpiGrid)).kpis;
      expect([for (final k in kpis) k.value], [20000, 15000, 1, 3]);
      final rows = t.widget<RpRowsCard>(find.byType(RpRowsCard));
      final all = [for (final d in rows.days) ...d.rows];
      expect(all.length, 3);
      expect(all.where((r) => r.balanceAfter != null).map((r) => r.balanceAfter), [-15000, -35000]);
      expect(all.firstWhere((r) => r.title.contains('تمديد')).amount, isNull, reason: 'بلا مال ⇒ بلا رقم');
      expect(find.text('قارن'), findsNothing);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('«لم تُسحب / سُحبت» (٢٦ نوفمبر): سطر الحوالة وحده يُسأل، وحاله بعد وصفه على السطر وفي الملفّ', (t) async {
    await up();
    server.twRows = {
      '2': {'pending': 20000, 'withdrawn': 0, 'at_ms': null},
    };
    TransferPay.available.value = true;
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      await open(t);
      expect(server.twAsked, ['2']);
      final rows = t.widget<RpRowsCard>(find.byType(RpRowsCard));
      final all = [for (final d in rows.days) ...d.rows];
      final pay = all.singleWhere((r) => r.detail.contains('لم تُسحب'), orElse: () => throw StateError('لا سطر بحالٍ'));
      expect(pay.title, contains('تسديد'));
      expect(pay.detail, 'لم تُسحب · زينب', reason: 'الحال جزءٌ بذاته قبل المنفّذ — وغير الحوالة بلا حال');
      final export = find.text('Excel');
      await t.scrollUntilVisible(export, 600, scrollable: find.byType(Scrollable).first);
      await t.tap(export);
      for (var i = 0; i < 8; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 100));
      }
      expect([for (final row in got.single.rows) ...row], contains('تسديد دين — لم تُسحب'));
      expect(t.takeException(), isNull);
    } finally {
      TransferPay.available.value = false;
      await down(t);
    }
  });

  testWidgets('النوع إلى الخادم، والتصدير بالنوع والبحث ومعه «الرصيد بعدها»، ورأسه يسمّي المشترك والفلاتر', (t) async {
    await up(prefs: {
      'report.v2.account_statement': jsonEncode({
        'p': 'last30',
        't': ['DEBT_PAY', 'SUBSCRIBER_ACTIVATE'],
      }),
    });
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      await open(t);
      expect(server.asked.single['action_types'], 'DEBT_PAY,SUBSCRIBER_ACTIVATE');
      expect(server.asked.single['date_from'], '2026-10-24 00:00:00');
      final rows = find.byType(RpRowsCard);
      await t.scrollUntilVisible(find.descendant(of: rows, matching: find.byType(TextField)), 400,
          scrollable: find.byType(Scrollable).first);
      await t.enterText(find.descendant(of: rows, matching: find.byType(TextField)), 'تسديد');
      await t.pump(const Duration(milliseconds: 200));
      await t.scrollUntilVisible(find.text('Excel'), 400, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('Excel'));
      for (var i = 0; i < 4; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 100));
      }
      final r = got.single;
      expect(r.rows.length, 1);
      expect(r.columns.last, 'الرصيد بعدها');
      expect(r.rows.single.last, 'الدين بعدها: 15,000 د.ع');
      expect(r.details.first, 'المشترك: زهراء محمود (u7)');
      expect(r.details.any((d) => d.startsWith('النوع: ')), isTrue);
      expect(r.details, contains('بحث: «تسديد»'));
      expect(r.details, contains('عدد الحركات: 1'));
      // تصميم الـPDF (٢٦ نوفمبر): البحث يحصر السطور ⇒ لا بطاقات الكشف في الرأس؛ بلا بحث ⇒ بطاقات الشاشة نفسها
      got.clear();
      await t.tap(find.text('PDF'));
      for (var i = 0; i < 4; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(got.single.how, 'pdf');
      expect(got.single.summary, isEmpty, reason: 'ملخّص الحساب كلّه لا يصف سطور البحث');
      await t.scrollUntilVisible(find.descendant(of: rows, matching: find.byType(TextField)), -400,
          scrollable: find.byType(Scrollable).first);
      await t.enterText(find.descendant(of: rows, matching: find.byType(TextField)), '');
      await t.pump(const Duration(milliseconds: 200));
      got.clear();
      await t.scrollUntilVisible(find.text('PDF'), 400, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('PDF'));
      for (var i = 0; i < 4; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 100));
      }
      final onScreen = t.widget<RpKpiGrid>(find.byType(RpKpiGrid).first).kpis;
      final hero = t.widget<RpHeroKpi>(find.byType(RpHeroKpi).first).kpi;
      expect([for (final s in got.single.summary) s.label], [hero.label, for (final k in onScreen) k.label]);
      expect([for (final s in got.single.summary) s.value], [hero.text, for (final k in onScreen) k.text]);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  test('ملخّص الكشف في الـPDF: لا بحث ولا «طريقة الدفع»', () {
    expect(AccountStatementV2Screen.summaryFits(query: '', pays: const {}), isTrue);
    expect(AccountStatementV2Screen.summaryFits(query: '  ', pays: const {}), isTrue);
    expect(AccountStatementV2Screen.summaryFits(query: 'تسديد', pays: const {}), isFalse);
    expect(AccountStatementV2Screen.summaryFits(query: '', pays: const {'cash'}), isFalse, reason: 'الكاش وحده ≠ مدفوع الحساب كلّه');
  });

  // «الترتيب بالنقر» (المالك ٢٣ نوفمبر): «رتّب حسب» فوق الحركات — المبلغ الأكبر أوّلاً قائمةً واحدة والتاريخ على كلّ سطر، الصفر
  // (بلا مال) آخراً، النقرة الثانية تقلب، يُحفظ للتقرير ويرجع عند الفتح، والتصدير بترتيب الشاشة وسطر «مرتّب حسب».
  testWidgets('رتّب حسب المبلغ: قائمةٌ واحدة، تقلب، تُحفظ، والتصدير بترتيبها', (t) async {
    await up();
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      await open(t);
      RpRowsCard card() => t.widget<RpRowsCard>(find.byType(RpRowsCard));
      expect(card().sort!.value, rpDateDesc, reason: 'الافتراض: التاريخ — الأحدث أوّلاً');
      expect(card().days.length, 3, reason: 'يوماً بيوم كما كان');
      expect(card().days.every((d) => !d.flat), isTrue);
      final amount = find.byKey(RpSortChips.chipKey('amount'));
      await t.scrollUntilVisible(amount, 300, scrollable: find.byType(Scrollable).first);
      await t.tap(amount);
      await t.pump(const Duration(milliseconds: 200));
      expect(card().sort!.value, const OrderValue('amount', OrderDir.desc));
      var days = card().days;
      expect(days.length, 1);
      expect(days.single.flat, isTrue);
      expect([for (final r in days.single.rows) r.amount], [35000, 20000, null], reason: 'الأكبر أوّلاً والصفر (بلا مال) آخراً');
      expect([for (final r in days.single.rows) r.date], ['2026/11/20', '2026/11/21', '2026/11/22'], reason: 'تاريخ كلّ سطرٍ عليه');
      expect(find.text('2026/11/20'), findsOneWidget);
      await t.tap(amount);
      await t.pump(const Duration(milliseconds: 200));
      days = card().days;
      expect([for (final r in days.single.rows) r.amount], [20000, 35000, null], reason: 'الثانية تقلب — والفارغ آخراً بالاتّجاهين');
      for (var i = 0; i < 3; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 50));
      }
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('report.v2.account_statement.sort')!), {'k': 'amount', 'd': 'asc'});
      await t.scrollUntilVisible(find.text('Excel'), 400, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('Excel'));
      for (var i = 0; i < 4; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 100));
      }
      final r = got.single;
      expect([for (final row in r.rows) row[2]], ['20000', '35000', ''], reason: 'الملفّ بترتيب الشاشة');
      expect(r.details, contains('مرتّب حسب: المبلغ — الأصغر أوّلاً'));
      // الفتح من جديد على الترتيب المحفوظ
      await t.pumpWidget(const SizedBox());
      await open(t);
      expect(card().sort!.value, const OrderValue('amount', OrderDir.asc));
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });
}
