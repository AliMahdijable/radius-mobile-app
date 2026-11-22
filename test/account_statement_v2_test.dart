import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/screens/reports/v2/account_statement_v2_screen.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_export.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_perm/visual_perm_harness.dart';

// «كشف حساب المشترك» على الشكل الموحّد (٢٢ نوفمبر): الأرقام كما كانت حرفاً من ملخّص الخادم، والفترة «آخر 90 يوماً» أوّل مرّة،
// والأنواع من الورقة إلى الخادم (action_types)، و«الدين بعدها» على كلّ سطر، والتصدير بالفلاتر والبحث ومعه «الرصيد بعدها».

final _now = DateTime(2026, 11, 22, 18);

class _Server implements HttpClientAdapter {
  _Server(this.inner);
  final VisualServer inner;
  final asked = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    if (o.method.toUpperCase() == 'GET' && o.uri.path == '/api/reports/account-statement') {
      final q = Map<String, dynamic>.from(o.queryParameters);
      asked.add(q);
      final types = '${q['action_types'] ?? ''}'.split(',').where((s) => s.isNotEmpty).toSet();
      final tx = [
        {'id': 1, 'created_at': '2026-11-20 15:00:00', 'action_type': 'SUBSCRIBER_ACTIVATE', 'description': 'تفعيل غير نقدي — FTTH 50', 'amount': 35000, 'admin_name': 'admin@sup', 'balance_after': -35000},
        {'id': 2, 'created_at': '2026-11-21 12:00:00', 'action_type': 'DEBT_PAY', 'description': 'تسديد دين', 'amount': 20000, 'admin_name': 'زينب', 'balance_after': -15000},
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
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });
}
