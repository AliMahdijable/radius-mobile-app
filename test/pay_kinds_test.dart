// «طريقة الدفع» بكلّ التقارير (٢٤ نوفمبر — المالك: «… بالتقارير ضمنت هاي الشي بالفلاتر؟» ثمّ «يكون ضمنه بكل العمليات المرتبط بها»).
// الخادم paykind1 (7d09ac9): pay= بالماليّ (صداه type_filter.pay) وسجلّ الحركات (صداه pay_filter)، وpay_kind لكلّ سطر.
// هنا: PayKinds، الطلبات وصداها (بلا صدى ⇒ «غير مدعوم» لا أرقام)، فلتر التفعيلات وكشف الحساب بطريقة السطر، حوالة حركات الأرصدة،
// ورقة الفلاتر، والتقرير الماليّ بفلترٍ محفوظ.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/balance_reports_api.dart';
import 'package:rad_mysvcs/api/reports_api.dart';
import 'package:rad_mysvcs/screens/reports/v2/activations_view.dart';
import 'package:rad_mysvcs/screens/reports/v2/finance_report_v2_screen.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_period.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_sheets.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/pay_kinds.dart';
import 'package:rad_mysvcs/services/transfer_pay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_perm/visual_perm_harness.dart';

ResponseBody _json(Object body) => ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

/// خادمٌ يطبّق pay كما يطبّقه الخادم الحقيقيّ ويعيد صداه — أو لا يعيده (خادمٌ لا يعرفه).
class _Rec implements HttpClientAdapter {
  _Rec(this.inner, {this.echo = true});
  final VisualServer inner;
  final bool echo;
  final finance = <Map<String, String>>[];
  final acts = <Map<String, String>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final q = o.uri.queryParameters;
    switch (o.uri.path) {
      case '/api/v2/transfer-pay':
        return _json({
          'success': true,
          'data': {'available': true, 'names': <String>[]},
        });
      case '/api/reports/finance':
        finance.add(q);
        final pay = q['pay'];
        return _json({
          'success': true,
          'data': {
            'kpis': {'activate_cash_sum': pay == null ? 55000 : 30000},
            'recentLogs': <Object>[],
            if (q['strict_types'] == '1')
              'type_filter': {
                'strict': true,
                'types': <String>[],
                'packages': null,
                'expenses': pay == null,
                if (echo && pay != null) 'pay': pay.split(','),
              },
          },
        });
      case '/api/activities':
        acts.add(q);
        final pay = q['pay'];
        return _json({
          'success': true,
          if (echo && pay != null) 'pay_filter': pay.split(','),
          'data': [
            {'id': 12, 'action_type': 'SUBSCRIBER_ACTIVATE', 'action_description': 'تفعيل نقدي — حوالة ماستر', 'created_at': '2026-11-24 10:00:00', 'pay_kind': 'master'},
          ],
          'pagination': {'total': 1, 'page': 1, 'limit': 2000},
        });
    }
    return inner.fetch(o, body, cancel);
  }

  @override
  void close({bool force = false}) {}
}

ActivityRow _row(int id, String desc, {String? pay, String type = 'SUBSCRIBER_ACTIVATE'}) => ActivityRow.fromJson({
      'id': id,
      'action_type': type,
      'action_description': desc,
      'created_at': '2026-11-24 10:00:00',
      if (pay != null) 'pay_kind': pay,
    })!;

void main() {
  group('PayKinds', () {
    test('الترتيب والشريحة والقراءة والصدى', () {
      expect(PayKinds.sorted({'debt', 'master', 'x', 'cash'}), ['cash', 'master', 'debt']);
      expect(PayKinds.chip({'master', 'zaincash'}), 'طريقة الدفع: زين كاش، ماستر');
      expect(PayKinds.of('master'), 'master');
      expect(PayKinds.of('card'), isNull);
      expect(PayKinds.of(null), isNull);
      expect(PayKinds.honored(const [], null), isTrue);
      expect(PayKinds.honored(const ['master', 'cash'], ['cash', 'master']), isTrue);
      expect(PayKinds.honored(const ['master'], null), isFalse);
      expect(PayKinds.honored(const ['master'], ['cash']), isFalse);
      expect(PayKinds.honored(const ['master', 'cash'], ['master']), isFalse);
      expect(PayKinds.options().map((e) => e.$2), ['كاش', 'زين كاش', 'ماستر', 'أخرى', 'بالدين']);
    });
  });

  group('الطلبات', () {
    setUpAll(visualSetUpAll);
    late _Rec rec;
    Future<void> up({bool echo = true}) async {
      rec = _Rec(await visualSetUp(s1bSasOwner), echo: echo);
      ApiClient.dio.httpClientAdapter = rec;
    }

    tearDown(visualTearDown);

    test('الماليّ: pay مع strict_types، والصدى ⇒ الأرقام وtype_filter.pay', () async {
      await up();
      final r = await ReportsApi.finance(from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 24), userIds: const ['2251'], pay: const ['master']);
      expect(r.ok, isTrue, reason: r.error);
      expect(rec.finance.single['pay'], 'master');
      expect(rec.finance.single['strict_types'], '1');
      expect(r.data!.typeFilter?.pay, ['master']);
    });

    test('الماليّ: بلا صدى ⇒ «غير مدعوم» بلا أرقام', () async {
      await up(echo: false);
      final r = await ReportsApi.finance(from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 24), userIds: const ['2251'], pay: const ['master']);
      expect(r.ok, isFalse);
      expect(r.data, isNull);
      expect(r.error, PayKinds.unsupported);
    });

    test('الماليّ: بلا pay كما كان حرفاً (لا strict ولا pay)', () async {
      await up();
      final r = await ReportsApi.finance(from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 24), userIds: const ['2251']);
      expect(r.ok, isTrue);
      expect(rec.finance.single.containsKey('pay'), isFalse);
      expect(rec.finance.single.containsKey('strict_types'), isFalse);
    });

    test('سجلّ الحركات: pay مرتّباً، والصدى pay_filter، وpay_kind لكلّ سطر', () async {
      await up();
      final r = await ReportsApi.activitiesAll(from: DateTime(2026, 11, 21), to: DateTime(2026, 11, 24), userIds: const ['2251'], pay: const ['debt', 'master']);
      expect(r.ok, isTrue, reason: r.error);
      expect(rec.acts.single['pay'], 'master,debt');
      expect(r.rows.single.payKind, 'master');
    });

    test('سجلّ الحركات: بلا صدى ⇒ «غير مدعوم» بلا سطور', () async {
      await up(echo: false);
      final r = await ReportsApi.activitiesAll(from: DateTime(2026, 11, 21), to: DateTime(2026, 11, 24), userIds: const ['2251'], pay: const ['master']);
      expect(r.ok, isFalse);
      expect(r.rows, isEmpty);
      expect(r.error, PayKinds.unsupported);
    });
  });

  group('السطور', () {
    test('كشف الحساب: pay_kind يُقرأ والمجهول null', () {
      expect(StatementRow.fromJson({'id': 1, 'created_at': '2026-11-24 10:00:00', 'pay_kind': 'zaincash'})!.payKind, 'zaincash');
      expect(StatementRow.fromJson({'id': 2, 'created_at': '2026-11-24 10:00:00', 'pay_kind': 'card'})!.payKind, isNull);
      expect(StatementRow.fromJson({'id': 3, 'created_at': '2026-11-24 10:00:00'})!.payKind, isNull);
    });

    test('التفعيلات: الفلتر بطريقة السطر، والقديم بلا pay_kind من نوعه، والنوع يتقاطع', () {
      final rows = [
        _row(1, 'تفعيل نقدي'),
        _row(2, 'تفعيل نقدي — حوالة ماستر', pay: 'master'),
        _row(3, 'تفعيل غير نقدي', pay: 'debt'),
        _row(4, 'تمديد', type: 'SUBSCRIBER_EXTEND'),
      ];
      List<int> ids(Set<String> pays, [List<String> kinds = const []]) => [for (final r in ActivationsView.filter(rows, kinds, pays: pays)) r.id];
      expect(ids({}), [1, 2, 3, 4]);
      expect(ids({'master'}), [2]);
      expect(ids({'cash'}), [1]);
      expect(ids({'debt'}), [3]);
      expect(ids({'cash', 'master'}), [1, 2]);
      expect(ids({'master'}, ['debt']), isEmpty, reason: 'تقاطعٌ لا اتّحاد');
      expect(ActivationsView.kindWithVia(rows[1], ActivationsView.kindOf(rows[1])), 'تفعيل نقدي · ماستر');
      expect(ActivationsView.kindWithVia(rows[0], ActivationsView.kindOf(rows[0])), 'تفعيل نقدي');
    });

    test('تقارير الأرصدة: الحوالة على الحركة وتسديدها، والنصّ، وفلاتر الطرق', () {
      final a = BalanceMove.fromJson({'key': 'a1', 'kind': 'activate', 'at_ms': 1, 'username': 'u', 'price': 30000, 'pay': 'cash', 'cash': 30000, 'debt': 0, 'via': 'master'})
          as BalanceActMove;
      final p = BalanceMove.fromJson({'key': 'p1', 'kind': 'payment', 'at_ms': 2, 'username': 'u', 'amount': 5000, 'via': 'other', 'via_name': 'آسيا حوالة'}) as BalancePayMove;
      final c = BalanceMove.fromJson({'key': 'p2', 'kind': 'payment', 'at_ms': 3, 'username': 'u', 'amount': 5000}) as BalancePayMove;
      expect(balanceViaText(a.via, a.viaName), 'حوالة ماستر');
      expect(balanceViaText(p.via, p.viaName), 'حوالة آسيا حوالة');
      expect(balanceViaText(c.via, c.viaName), isNull);
      expect([for (final f in BalanceFilter.values) if (f.isVia) f.wire], ['zaincash', 'master', 'other']);
    });
  });

  group('الورقة والشاشة', () {
    setUpAll(visualSetUpAll);
    final now = DateTime(2026, 11, 24, 12);

    Widget sheet(List<(String, String)> payKinds, void Function(RpFilterValue) done) => Scaffold(
          body: RpFilterSheet(
            subtitle: 'التقرير الماليّ · هذا الشهر',
            initial: RpFilterValue(range: RpRange.of(RpPreset.thisMonth, now: now)),
            people: const [],
            types: const [],
            payments: const [
              RpPayShortcut('نقد', ['SUBSCRIBER_ACTIVATE_CASH', 'BALANCE_DEDUCT']),
              RpPayShortcut('بالدين', ['SUBSCRIBER_ACTIVATE_NON_CASH', 'BALANCE_ADD']),
            ],
            payKinds: payKinds,
            now: now,
            onDone: done,
          ),
        );

    testWidgets('الورقة: «طريقة الدفع» خمسٌ مستقلّة تحلّ محلّ «نقد/بالدين»، ولمسةٌ تختار ولمسةٌ تلغي', (t) async {
      await visualSetUp(s1bSasOwner);
      RpFilterValue? got;
      try {
        await pumpVisual(t, const VisualDevice('', Size(430, 2400), 2), home: (_) => sheet(PayKinds.options(), (v) => got = v));
        await t.pump();
        expect(find.text('كاش أو حوالة أو بالدين'), findsOneWidget);
        expect(find.text('اختصارٌ لأنواع الحركة'), findsNothing);
        for (final n in ['ماستر', 'بالدين', 'زين كاش', 'زين كاش']) {
          await t.ensureVisible(find.text(n));
          await t.tap(find.text(n));
          await t.pump();
        }
        await t.ensureVisible(find.text('عرض النتائج'));
        await t.tap(find.text('عرض النتائج'));
        await t.pump();
        expect(got?.pays, {'master', 'debt'});
        expect(got?.types, isEmpty, reason: 'بعدٌ مستقلّ لا أنواع');
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        await visualTearDown();
      }
    });

    testWidgets('الورقة: صفحةٌ بلا «الحوالات» ⇒ «نقد/بالدين» اختصاراً كما كان حرفاً', (t) async {
      await visualSetUp(s1bSasOwner);
      RpFilterValue? got;
      try {
        await pumpVisual(t, const VisualDevice('', Size(430, 2400), 2), home: (_) => sheet(const [], (v) => got = v));
        await t.pump();
        expect(find.text('اختصارٌ لأنواع الحركة'), findsOneWidget);
        expect(find.text('كاش أو حوالة أو بالدين'), findsNothing);
        await t.ensureVisible(find.text('نقد'));
        await t.tap(find.text('نقد'));
        await t.pump();
        await t.ensureVisible(find.text('عرض النتائج'));
        await t.tap(find.text('عرض النتائج'));
        await t.pump();
        expect(got?.types, ['SUBSCRIBER_ACTIVATE_CASH', 'BALANCE_DEDUCT']);
        expect(got?.pays, isEmpty);
      } finally {
        await t.pumpWidget(const SizedBox());
        await visualTearDown();
      }
    });

    testWidgets('التقرير الماليّ: «ماستر» محفوظ وصفحةٌ بالحوالات ⇒ pay=master مع strict والشريحة', (t) async {
      final rec = _Rec(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = rec;
      SharedPreferences.setMockInitialValues({
        'report.v2.finance': jsonEncode({'p': 'thisMonth', 'pv': ['master']}),
      });
      TransferPay.debugSet(on: true);
      FinanceReportV2Screen.clock = () => now;
      try {
        await pumpVisual(t, const VisualDevice('', Size(430, 2400), 2), home: (_) => const FinanceReportV2Screen());
        for (var i = 0; i < 12; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(rec.finance.any((q) => q['pay'] == 'master' && q['strict_types'] == '1'), isTrue, reason: '${rec.finance}');
        expect(find.text('طريقة الدفع: ماستر'), findsWidgets);
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 6));
        TransferPay.reset();
        MergedMode.reset();
        FinanceReportV2Screen.clock = DateTime.now;
        await visualTearDown();
      }
    });

    testWidgets('التقرير الماليّ: الفلتر المحفوظ لا يُرسل لصفحةٍ بلا «الحوالات»', (t) async {
      final rec = _Rec(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = rec;
      SharedPreferences.setMockInitialValues({
        'report.v2.finance': jsonEncode({'p': 'thisMonth', 'pv': ['master']}),
      });
      TransferPay.debugSet(on: false);
      FinanceReportV2Screen.clock = () => now;
      try {
        await pumpVisual(t, const VisualDevice('', Size(430, 2400), 2), home: (_) => const FinanceReportV2Screen());
        for (var i = 0; i < 12; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(rec.finance, isNotEmpty);
        expect(rec.finance.every((q) => !q.containsKey('pay')), isTrue, reason: '${rec.finance}');
        expect(find.text('طريقة الدفع: ماستر'), findsNothing);
      } finally {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 6));
        TransferPay.reset();
        MergedMode.reset();
        FinanceReportV2Screen.clock = DateTime.now;
        await visualTearDown();
      }
    });
  });
}
