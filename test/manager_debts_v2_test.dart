import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/reports/v2/manager_debts_v2_screen.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_export.dart';
import 'package:rad_mysvcs/services/merged_manager_debts.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «ديون المدراء» على الشكل الموحّد (٢٢ نوفمبر — «اكمل كلشي»): «كل الفترات» أوّل مرّة كما كان (لا تاريخ للخادم)، «إيرادات
/// مستحصَلة» = شحن نقديّ + تسديد SAS + تسديد أخرى بكلّ الفلاتر، المتبقّي من الساس ودفترنا وبحث المدير وحده يحصره، دين مديرٍ لم
/// يُقرأ يُسمّى ولا يُجمع، السقوف تُسمّى، والتصدير بالفلاتر حرفاً وكاملاً؛ و«كل الشركات»: كلّ شركة ساس بطلباتها والمتعذّرة تُسمّى.
final _now = DateTime(2026, 11, 22, 12);

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

Map<String, Object?> _bal(int id, String sub, int amount, String at) =>
    {'row_type': 'balance', 'id': id, 'sub_kind': sub, 'amount': amount, 'source': 'sas4', 'event_at': at};

// ═══════════════════════════════ المنفردة ═══════════════════════════════

class _Single implements HttpClientAdapter {
  _Single(this.inner, {this.busy = 0, this.failCore = false});
  final HttpClientAdapter inner;

  /// مديرون إضافيّون (m10…) بحركةٍ واحدة، وأوّلهم كثير الحركات — لاختبار السقوف.
  final int busy;
  final bool failCore;
  final asked = <(String, Map<String, dynamic>)>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final path = o.uri.path;
    Future<ResponseBody> ok(Map<String, Object?> body) async => _json(200, {'success': true, ...body});
    if (path.startsWith('/api/admin/') || path.startsWith('/api/v2/managers')) asked.add((path, Map.of(o.queryParameters)));
    if (path == '/api/admin/manager-debts/access') return ok({'hasSubAdmins': true, 'subAdmins': const []});
    if (path == '/api/v2/managers/full') {
      if (failCore) return _json(409, {'success': false, 'message': 'انتهت الجلسة — افتح الصفحة من جديد'});
      final rows = [
        {'id': 1, 'username': 'm1', 'full_name': 'علي', 'total_debt': 50000},
        {'id': 2, 'username': 'm2', 'total_debt': 9999, 'debt_unavailable': true},
        {'id': 3, 'username': 'm3', 'total_debt': 20000},
        for (var i = 0; i < busy; i++) {'id': 10 + i, 'username': 'x${10 + i}', 'total_debt': 0},
      ];
      return ok({'data': rows, 'total': rows.length});
    }
    if (path == '/api/admin/manager-debts/summary') {
      return ok({
        'totals': {'total_remaining': 15000, 'debts_count': 1},
        'perDebtor': [
          {'debtor_admin_id': 2, 'debtor_admin_username': 'm2', 'debts_count': 1, 'total_remaining': 15000},
        ],
      });
    }
    if (path == '/api/admin/manager-debts') {
      return ok({
        'debts': [
          {'id': 7, 'amount': 5000, 'paid_amount': 5000, 'remaining_amount': 0, 'debtor_admin_id': 2, 'status': 'paid'},
          {
            'id': 8,
            'amount': 15000,
            'paid_amount': 0,
            'remaining_amount': 15000,
            'debtor_admin_id': 2,
            'debtor_admin_username': 'm2',
            'debt_date': '2026-06-01',
            'status': 'open',
          },
        ],
      });
    }
    final mv = RegExp(r'^/api/admin/managers/(\d+)/movements$').firstMatch(path);
    if (mv != null) {
      final id = int.parse(mv.group(1)!);
      final limit = int.tryParse('${o.queryParameters['limit']}') ?? 100;
      final rows = switch (id) {
        1 => [
            _bal(101, 'deposit_cash', 50000, '2026-11-22 09:00:00'),
            _bal(102, 'deposit_loan', 30000, '2026-11-21 10:00:00'),
            _bal(103, 'sas_pay_debt', 10000, '2026-10-05 10:00:00'),
          ],
        2 => [
            {'row_type': 'debt_payment', 'id': 201, 'amount': 5000, 'debt_id': 7, 'event_at': '2026-11-20 11:00:00'},
          ],
        3 => [_bal(301, 'withdraw', 7000, '2026-11-22 10:00:00'), _bal(302, 'points', 100, '2026-11-22 11:00:00')],
        10 => [for (var k = 0; k < 600 && k < limit; k++) _bal(1000 + k, 'deposit_cash', 1000, '2026-11-${(k % 20 + 1).toString().padLeft(2, '0')} 09:00:00')],
        _ => [_bal(id * 1000, 'deposit_cash', 1000, '2026-11-22 09:30:00')],
      };
      return ok({'movements': rows});
    }
    return inner.fetch(o, rs, cf);
  }

  @override
  void close({bool force = false}) {}
}

// ═══════════════════════════════ كل الشركات ═══════════════════════════════

const _kA = 'c0000000000aa'; // سوبرنت — m5 مدين، m6 دينه لم يُقرأ
const _kB = 'c0000000000bb'; // الجزيرة — b5 بالمعرّف 5 نفسه
const _kC = 'c0000000000cc'; // ساس بلا مدراء فرعيّين
const _kF = 'c0000000000ff'; // ساس تتعذّر قائمة مدرائه
const _kN = 'c0000000000ee'; // مُضافة — لا مدراء فرعيّين بنوعها (لا تُطلب)

class _Merged implements HttpClientAdapter {
  _Merged(this.inner);
  final HttpClientAdapter inner;
  final asked = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    if (path.startsWith('/api/admin/') || path.startsWith('/api/v2/managers')) asked.add('${o.method} $path ${key ?? '-'}');
    if (key == null) return inner.fetch(o, rs, cf);
    final h = {'x-company-key': [key]};
    Future<ResponseBody> ok(Map<String, Object?> body) async => _json(200, {'success': true, ...body}, headers: h);
    if (path == '/api/admin/manager-debts/access') return ok({'hasSubAdmins': key != _kC, 'subAdmins': const []});
    if (path == '/api/v2/managers/full') {
      if (key == _kF) return _json(409, {'success': false, 'message': 'انتهت جلسة «فاشلة» — افتحها من «شركاتي»'}, headers: h);
      final rows = key == _kA
          ? [
              {'id': 5, 'username': 'm5', 'total_debt': 100000},
              {'id': 6, 'username': 'm6', 'total_debt': 0, 'debt_unavailable': true},
            ]
          : [
              {'id': 5, 'username': 'b5', 'total_debt': 30000},
            ];
      return ok({'data': rows, 'total': rows.length});
    }
    if (path == '/api/admin/manager-debts/summary') {
      return ok(key == _kA
          ? {
              'totals': {'total_remaining': 20000, 'debts_count': 1},
              'perDebtor': [
                {'debtor_admin_id': 5, 'debtor_admin_username': 'm5', 'debts_count': 1, 'total_remaining': 20000},
              ],
            }
          : {'totals': {'total_remaining': 0}, 'perDebtor': const []});
    }
    if (path == '/api/admin/manager-debts') return ok({'debts': const []});
    final mv = RegExp(r'^/api/admin/managers/(\d+)/movements$').firstMatch(path);
    if (mv != null) {
      final rows = switch ((key, mv.group(1))) {
        (_kA, '5') => [_bal(11, 'deposit_cash', 50000, '2026-11-22 09:00:00'), _bal(12, 'sas_pay_debt', 10000, '2026-11-22 11:00:00')],
        (_kB, '5') => [_bal(11, 'withdraw', 7000, '2026-11-22 10:00:00')],
        _ => const <Map<String, Object?>>[],
      };
      return ok({'movements': rows});
    }
    return _json(409, {'success': false, 'code': 'COMPANY_ROUTE_NOT_ALLOWED'}, headers: h);
  }

  @override
  void close({bool force = false}) {}
}

// ═══════════════════════════════ ايرث لنك ═══════════════════════════════

/// عقد d9 (٢٣ نوفمبر — المالك: «ليش الايرثلنك… ما تصير بنفس الصيغة بيها ديون مدراء؟»): المدراء حساباتها التابعة بلا دين ساس
/// (`sas_debt: false` بأعلى جسم managers/full)، وحركاتهم شحنٌ من سجلّنا (row_type balance، source el_topup، id سالب) والآجل بـdebt_id
/// صفّه في «ديون أخرى» — والخادم يرسل صفّ الدين نفسه (debt_created) فيُخفى عندنا. [old] = خادمٌ قبل العقد (قائمةٌ فارغة بلا علامة).
const _kE = 'c00000000000e'; // ايرث لنك في «كل الشركات»

Map<String, Object?> _elRows(String id) => switch (id) {
      '1025' => {
          'movements': [
            {'row_type': 'balance', 'id': -5, 'sub_kind': 'deposit_loan', 'amount': 50000, 'source': 'el_topup', 'debt_id': 77,
              'note': 'شحن آجل', 'event_at': '2026-11-18T09:30:00.000Z'},
            {'row_type': 'debt_created', 'id': 77, 'amount': 50000, 'debt_id': 77, 'event_at': '2026-11-18T09:30:00.000Z'},
            {'row_type': 'debt_payment', 'id': 301, 'amount': 20000, 'debt_id': 77, 'event_at': '2026-11-20T10:00:00.000Z'},
          ],
        },
      '2048' => {
          'movements': [
            {'row_type': 'balance', 'id': -6, 'sub_kind': 'deposit_cash', 'amount': 25000, 'source': 'el_topup', 'event_at': '2026-11-21T08:00:00.000Z'},
          ],
        },
      _ => {'movements': const <Object>[]},
    };

Future<ResponseBody>? _elReply(String path, Future<ResponseBody> Function(Map<String, Object?>) ok, {bool old = false}) {
  if (path == '/api/admin/manager-debts/access') return ok({'hasSubAdmins': true, 'subAdmins': const []});
  if (path == '/api/v2/managers/full') {
    if (old) return ok({'data': const <Object>[], 'total': 0});
    return ok({
      'data': [
        {'id': 1025, 'username': 'najaf40'},
        {'id': 2048, 'username': 'kufa7'},
      ],
      'total': 2,
      'sas_debt': false,
    });
  }
  if (path == '/api/admin/manager-debts/summary') {
    return ok({
      'totals': {'total_remaining': 30000, 'debts_count': 1},
      'perDebtor': [
        {'debtor_admin_id': 1025, 'debtor_admin_username': 'najaf40', 'debts_count': 1, 'total_remaining': 30000},
      ],
    });
  }
  if (path == '/api/admin/manager-debts') {
    return ok({
      'debts': [
        {'id': 77, 'amount': 50000, 'paid_amount': 20000, 'remaining_amount': 30000, 'debtor_admin_id': 1025,
          'debtor_admin_username': 'najaf40', 'debt_date': '2026-11-18', 'status': 'partial'},
      ],
    });
  }
  final mv = RegExp(r'^/api/admin/managers/(\d+)/movements$').firstMatch(path);
  if (mv != null) return ok({'target': {'id': int.parse(mv.group(1)!)}, ..._elRows(mv.group(1)!)});
  return null;
}

class _El implements HttpClientAdapter {
  _El(this.inner, {this.old = false, this.off = false});
  final HttpClientAdapter inner;
  final bool old;

  /// المفتاح مطفأٌ لصفحتها: access ⇒ {hasSubAdmins:false, enabled:false}.
  final bool off;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    Future<ResponseBody> ok(Map<String, Object?> body) async => _json(200, {'success': true, ...body});
    if (off && o.uri.path == '/api/admin/manager-debts/access') return ok({'hasSubAdmins': false, 'enabled': false});
    return await _elReply(o.uri.path, ok, old: old) ?? inner.fetch(o, rs, cf);
  }

  @override
  void close({bool force = false}) {}
}

/// «كل الشركات»: سوبرنت (ساس — كما في [_Merged]) + ايرث لنك.
class _MergedEl implements HttpClientAdapter {
  _MergedEl(this.inner) : sas = _Merged(inner);
  final HttpClientAdapter inner;
  final _Merged sas;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    if (key != _kE) return sas.fetch(o, rs, cf);
    Future<ResponseBody> ok(Map<String, Object?> body) async => _json(200, {'success': true, ...body}, headers: {'x-company-key': [key!]});
    return await _elReply(o.uri.path, ok) ?? _json(409, {'success': false, 'code': 'COMPANY_ROUTE_NOT_ALLOWED'});
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _companiesEl() => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kA, 'code': 'supernet', 'username': 'mahdi', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': 'supernet:12', 'ns': 'nA', 'currency': 'IQD', 'color_index': 0},
        {'key': _kE, 'code': 'earthlink', 'username': 'agent@el', 'name': 'ايرث لنك', 'provider': 'earthlink', 'status': 'ok', 'admin_id': 'earthlink:1025', 'ns': 'nE', 'currency': 'IQD', 'color_index': 1},
      ],
    };

Map<String, Object?> _companies() => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kA, 'code': 'supernet', 'username': 'mahdi', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': 'supernet:12', 'ns': 'nA', 'currency': 'IQD', 'color_index': 0},
        {'key': _kB, 'code': 'jt', 'username': 'admin@b', 'name': 'الجزيرة', 'status': 'ok', 'admin_id': 'jt:22', 'ns': 'nB', 'currency': 'IQD', 'color_index': 1},
        {'key': _kC, 'code': 'kr', 'username': 'k', 'name': 'كربلاء', 'status': 'ok', 'admin_id': 'kr:3', 'ns': 'nC', 'currency': 'IQD', 'color_index': 2},
        {'key': _kF, 'code': 'fx', 'username': 'f', 'name': 'فاشلة', 'status': 'ok', 'admin_id': 'fx:4', 'ns': 'nF', 'currency': 'IQD', 'color_index': 3},
        {'key': _kN, 'code': 'nabd', 'username': 'n', 'name': 'نبض', 'provider': 'kit', 'status': 'ok', 'admin_id': 'nabd:5', 'ns': 'nN', 'currency': 'IQD', 'color_index': 4},
      ],
    };

/// يفتح قسماً مطويّاً بلمسة عنوانه (المالك ٢٢ نوفمبر: الأقسام الفرعيّة مقفولةٌ حتى يُنقر عليها).
Future<void> unfold(WidgetTester t, Type card) async {
  final title = find.descendant(of: find.byType(card), matching: find.byType(RpTitle)).first;
  await t.ensureVisible(title);
  await t.tap(title);
  await t.pump();
}

void main() {
  setUpAll(visualSetUpAll);

  Future<void> settleAsync(WidgetTester t, [int n = 16]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester t, {double height = 2600}) async {
    await pumpVisual(t, VisualDevice('', Size(430, height), 2), home: (_) => const ManagerDebtsV2Screen());
    await settleAsync(t);
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    MergedMode.reset();
    ReportExportActions.debugSink = null;
    ManagerDebtsV2Screen.clock = DateTime.now;
    await visualTearDown();
  }

  Map<String, RpKpi> kpis(WidgetTester t) => {for (final k in t.widget<RpKpiGrid>(find.byType(RpKpiGrid)).kpis) k.id: k};
  num hero(WidgetTester t) => t.widget<RpHeroKpi>(find.byType(RpHeroKpi)).kpi.value;

  Future<void> tapExport(WidgetTester t, String label) async {
    await t.scrollUntilVisible(find.text(label), 600, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text(label));
    await settleAsync(t, 6);
  }

  Future<_Single> single(WidgetTester t, {Map<String, Object>? prefs, int busy = 0, bool failCore = false}) async {
    final srv = _Single(await visualSetUp(s1bSasOwner), busy: busy, failCore: failCore);
    ApiClient.dio.httpClientAdapter = srv;
    if (prefs != null) SharedPreferences.setMockInitialValues(prefs);
    ManagerDebtsV2Screen.clock = () => _now;
    return srv;
  }

  testWidgets('منفردة: «كل الفترات» بلا تاريخٍ للخادم، المستحصَل والمتبقّي والمدينون، والبحث يحصرها، والتصدير بالفلاتر', (t) async {
    final srv = await single(t);
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      await open(t);
      final summary = srv.asked.where((a) => a.$1 == '/api/admin/manager-debts/summary').single;
      expect(summary.$2.containsKey('from'), isFalse, reason: '«كل الفترات» كالشاشة السابقة أوّل مرّة');
      expect(find.text('كل الفترات'), findsWidgets);
      // شحن نقدي 50,000 + تسديد SAS 10,000 (الشهر الماضي داخل «كل الفترات») + تسديد أخرى 5,000 — الآجل والسحب والنقاط لا
      expect(hero(t), 65000);
      var k = kpis(t);
      expect(k['sas']!.value, 70000, reason: 'm1 + m3 — m2 لم يُقرأ دينه فلا يُجمع');
      expect(k['custom']!.value, 15000);
      expect(k['total']!.value, 85000);
      expect(k['debtors']!.value, 3, reason: 'm1 وm3 بالساس + m2 بالأخرى');
      expect(find.textContaining('دين 1 مدير لم يُقرأ من الساس'), findsOneWidget);
      await unfold(t, RpRowsCard);
      expect(find.text('تسديد كامل — دين أخرى'), findsWidgets, reason: 'الدين 7 متبقّيه صفر');
      // «عمر الدين»: المتبقّي من «ديون أخرى» بتاريخه — المسدَّد لا يدخل
      final card = t.widget<RpBreakdownCard>(find.byType(RpBreakdownCard));
      expect(card.tabs.last, 'عمر الدين');
      card.onTab!(card.tabs.length - 1);
      await t.pump();
      final ages = t.widget<RpBreakdownCard>(find.byType(RpBreakdownCard)).shares;
      expect([for (final a in ages) (a.name, a.amount, a.count)], [('3 – 6 أشهر', 15000, 1)]);
      card.onTab!(0);
      await t.pump();

      // بحث المدير يحصر الحركات والمتبقّي والمدينين
      await t.enterText(find.byType(TextField), 'm1');
      await settleAsync(t, 4);
      expect(hero(t), 60000);
      k = kpis(t);
      expect(k['sas']!.value, 50000);
      expect(k['custom']!.value, 0);
      expect(k['debtors']!.value, 1);

      await tapExport(t, 'Excel');
      final r = got.single;
      expect(r.rows.length, 3, reason: 'حركات m1 الثلاث — لا غيرها');
      expect(r.details, contains('المدير: «m1»'));
      expect(r.details, contains('عدد الحركات: 3'));
      expect(r.details.any((d) => d.startsWith('إيرادات مستحصَلة: 60,000')), isTrue);
      expect(r.subtitle, startsWith('كل الفترات'));
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('فترة «هذا الشهر» ونوع «شحن نقدي» محفوظان ⇒ التاريخ للخادم، والحركات بالفترة والنوع، وشارة النوع في الرأس', (t) async {
    final srv = await single(t, prefs: {
      'report.v2.manager_debts': jsonEncode({
        'p': 'thisMonth',
        't': ['deposit_cash'],
      }),
    });
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      await open(t);
      final summary = srv.asked.where((a) => a.$1 == '/api/admin/manager-debts/summary').single;
      expect(summary.$2['from'], '2026-11-01');
      expect(summary.$2['to'], '2026-11-22');
      expect(hero(t), 50000, reason: 'الشحن النقديّ وحده — وتسديد أكتوبر خارج الفترة');
      expect(find.text('النوع: شحن نقدي'), findsOneWidget);
      await tapExport(t, 'PDF');
      final r = got.single;
      expect(r.rows.length, 1);
      expect(r.details, contains('النوع: شحن نقدي'));
      expect(r.subtitle, startsWith('هذا الشهر'));
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('مديرٌ كثير الحركات ⇒ أقصى الخادم (500) ويُسمّى «ناقص» على الشاشة وفي رأس الملفّ', (t) async {
    final srv = await single(t, busy: 70);
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      await open(t);
      final limits = {for (final a in srv.asked) if (a.$1.endsWith('/movements')) a.$2['limit']};
      expect(limits, {kManagerMovementsLimit});
      expect(srv.asked.where((a) => a.$1.endsWith('/movements')).length, 73, reason: 'كلّ المدراء لا الستّون الأوائل');
      expect(find.textContaining('بلغت $kManagerMovementsLimit'), findsOneWidget);
      await tapExport(t, 'Excel');
      final r = got.single;
      expect(r.rows.length, 3 + 1 + 2 + 500 + 69, reason: 'كلّ ما قُرئ: m1 3، m2 1، m3 2، الكثير 500، وواحدةٌ لكلّ الباقين');
      expect(r.details.any((d) => d.startsWith('ناقص:') && d.contains('بلغت $kManagerMovementsLimit')), isTrue);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('قراءةٌ أساسيّة تتعذّر ⇒ سببها باسمه لا ملخّصٌ بأصفار', (t) async {
    await single(t, failCore: true);
    try {
      await open(t);
      expect(find.textContaining('انتهت الجلسة'), findsOneWidget);
      expect(find.byType(RpHeroKpi), findsNothing);
      expect(find.byType(RpKpiGrid), findsNothing);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('كل الشركات: كلّ ساسٍ بطلباتها، المجموع للمقروء وحده، المعرّف نفسه في شركتين مدينان، والضغط على شركة يعرضها وحدها', (t) async {
    final srv = _Merged(await visualSetUp(s1bSasOwner));
    ApiClient.dio.httpClientAdapter = srv;
    ManagerDebtsV2Screen.clock = () => _now;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    MergedMode.reset();
    MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
    SubscribersApi.clearAllCaches();
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      expect(await t.runAsync(() => MergedMode.enter()), isTrue);
      await open(t);
      expect(srv.asked.where((a) => a.endsWith(' -')), isEmpty, reason: 'لا طلبٌ بلا مفتاح في الوضع');
      expect(srv.asked.where((a) => a.contains(_kN)), isEmpty, reason: 'المُضافة لا تُطلب');
      expect(srv.asked.where((a) => a.contains(_kC)), ['GET /api/admin/manager-debts/access $_kC']);

      expect(hero(t), 60000, reason: 'شحن 50,000 + تسديد ساس 10,000 — السحب لا');
      final k = kpis(t);
      expect(k['sas']!.value, 130000, reason: 'm5 100,000 + b5 30,000 — m6 لم يُقرأ');
      expect(k['custom']!.value, 20000);
      expect(k['total']!.value, 150000);
      expect(k['debtors']!.value, 2, reason: 'المدير 5 في سوبرنت غير المدير 5 في الجزيرة');
      expect(find.textContaining('«فاشلة»'), findsWidgets);
      expect(find.textContaining('«سوبرنت»: دين 1 مدير لم يُقرأ من الساس'), findsOneWidget);
      expect(find.text('بلا مدراء فرعيّين: «كربلاء»، «نبض»'), findsOneWidget);
      final table = t.widget<RpCompanyTable>(find.byType(RpCompanyTable));
      expect([for (final l in table.lines) (l.company.key, l.state)], [
        (_kA, RpCompanyState.ok),
        (_kB, RpCompanyState.ok),
        (_kF, RpCompanyState.failed),
      ]);
      expect(table.total, [130000, 20000, 150000]);

      await tapExport(t, 'Excel');
      expect(got.single.rows.length, 3);
      expect(got.single.columns.first, 'الشركة');
      expect(got.single.details.first, 'الشركات: سوبرنت، الجزيرة');
      expect(got.single.details.any((d) => d.startsWith('ناقص:') && d.contains('«فاشلة»')), isTrue);

      // الجزيرة وحدها
      await t.scrollUntilVisible(find.byType(RpCompanyTable), -600, scrollable: find.byType(Scrollable).first);
      table.onTap!(table.lines[1].company);
      await settleAsync(t);
      expect(kpis(t)['sas']!.value, 30000);
      expect(hero(t), 0);
      expect(find.textContaining('«فاشلة»'), findsNothing);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  // ═══════════════════════════════ ايرث لنك (٢٣ نوفمبر) ═══════════════════════════════

  testWidgets('ايرث لنك منفردة: «متبقّي SAS» «—» لا صفر وملاحظتها، الآجل سطرٌ واحد «دين أخرى»، والمستحصَل والتصدير', (t) async {
    ApiClient.dio.httpClientAdapter = _El(await visualSetUp(s1Owner));
    ManagerDebtsV2Screen.clock = () => _now;
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      await open(t);
      // شحن نقديّ 25,000 (kufa7) + تسديد أخرى 20,000 (najaf40) — الآجل ليس مستحصَلاً
      expect(hero(t), 45000);
      final k = kpis(t);
      expect(k['sas']!.text, '—', reason: 'ايرث لنك لا تعطي أرصدة التوابع — لا «0 د.ع»');
      expect(k['sas']!.hint, 'ايرث لنك لا تعطي أرصدة التوابع');
      expect(k['custom']!.value, 30000);
      expect(k['total']!.value, 30000);
      expect(k['debtors']!.value, 1);
      expect(find.textContaining('لم يُقرأ من الساس'), findsNothing, reason: 'لا «دين مديرٍ لم يُقرأ» لايرث لنك');
      expect(find.text('شحن نقدي + تسديد ديون أخرى — تتبع كلّ الفلاتر'), findsOneWidget);
      await unfold(t, RpRowsCard);
      expect(find.textContaining('شحن آجل — دين أخرى'), findsOneWidget);
      expect(find.textContaining('دين SAS'), findsNothing);
      expect(find.textContaining('إضافة دين أخرى'), findsNothing, reason: 'صفّ الدين نفسه لا يُعرض ثانيةً');
      expect(find.textContaining('تسديد جزئي — دين أخرى'), findsOneWidget);
      await tapExport(t, 'Excel');
      final r = got.single;
      expect(r.rows.length, 3, reason: 'الآجل والتسديد والنقديّ — لا صفّ الدين المكرَّر');
      expect(r.details, contains('المتبقّي: SAS — · أخرى 30,000 د.ع · الإجمالي 30,000 د.ع'));
      expect(r.details, contains('ايرث لنك لا تعطي أرصدة التوابع'));
      final src = r.columns.indexOf('المصدر');
      expect({for (final row in r.rows) row[src]}, {'ايرث لنك', ''}, reason: 'الشحن «ايرث لنك»، و«ديون أخرى» بلا مصدر');
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  for (final (name, old, off) in [('خادمٌ قبل العقد (قائمةٌ فارغة بلا علامة)', true, false), ('المفتاح مطفأٌ لصفحتها (enabled:false)', false, true)]) {
    testWidgets('ايرث لنك و$name ⇒ «لم تُفتح بعد» لا «بلا مدراء فرعيّين» ولا تقريرٌ بلا حركاتٍ كأنّه كامل', (t) async {
      ApiClient.dio.httpClientAdapter = _El(await visualSetUp(s1Owner), old: old, off: off);
      ManagerDebtsV2Screen.clock = () => _now;
      try {
        await open(t);
        expect(find.text(kElManagerDebtsNotYet), findsOneWidget);
        expect(find.text('بلا مدراء فرعيّين'), findsNothing);
        expect(find.byType(RpHeroKpi), findsNothing);
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });
  }

  testWidgets('كل الشركات + ايرث لنك: تُطلب بمفتاحها، «—» في عمودها ومجموع SAS للساس وحده، وأخراها في المجموع', (t) async {
    final srv = _MergedEl(await visualSetUp(s1bSasOwner));
    ApiClient.dio.httpClientAdapter = srv;
    ManagerDebtsV2Screen.clock = () => _now;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    MergedMode.reset();
    MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companiesEl());
    SubscribersApi.clearAllCaches();
    try {
      expect(await t.runAsync(() => MergedMode.enter()), isTrue);
      await open(t);
      expect(srv.sas.asked.where((a) => a.contains(_kE)), isEmpty, reason: 'طلبات ايرث لنك لا تمرّ بخادم الساس الوهميّ');
      expect(hero(t), 60000 + 45000, reason: 'سوبرنت 60,000 + ايرث لنك 45,000');
      final k = kpis(t);
      expect(k['sas']!.value, 100000, reason: 'm5 وحده — ايرث لنك لا تُجمع صفراً ولا تُحسب');
      expect(k['sas']!.text, isNot('—'));
      expect(k['sas']!.hint, 'بلا ايرث لنك — لا تعطي أرصدة التوابع');
      expect(k['custom']!.value, 50000);
      expect(k['total']!.value, 150000);
      expect(find.textContaining('بلا مدراء فرعيّين'), findsNothing, reason: 'ايرث لنك لها مدراء الآن');
      final table = t.widget<RpCompanyTable>(find.byType(RpCompanyTable));
      expect([for (final l in table.lines) (l.company.key, l.state, l.a, l.b, l.c)], [
        (_kA, RpCompanyState.ok, 100000, 20000, 120000),
        (_kE, RpCompanyState.ok, null, 30000, 30000),
      ]);
      expect(table.lines[1].company.note, 'ايرث لنك لا تعطي أرصدة التوابع');
      expect(table.total, [100000, 50000, 150000]);
      // ايرث لنك وحدها ⇒ «—» لا صفر
      table.onTap!(table.lines[1].company);
      await settleAsync(t);
      expect(kpis(t)['sas']!.text, '—');
      expect(t.widget<RpCompanyTable>(find.byType(RpCompanyTable)).total.first, isNull);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  // ═══════════════════════════════ الصور (عرض 320 و480، فاتح وداكن) ═══════════════════════════════

  Future<void> shot(WidgetTester t, String id, VisualDevice d) async {
    final cut = <String>[
      for (final e in find.byType(RichText).evaluate())
        if (e.renderObject case final RenderParagraph ro when ro.didExceedMaxLines) ro.text.toPlainText(),
    ];
    final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(visualRootKey));
    final png = await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: d.dpr);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    final out = Directory('build/report_design')..createSync(recursive: true);
    File('${out.path}/md_$id.png').writeAsBytesSync(png!, flush: true);
    expect(cut, isEmpty, reason: 'نصٌّ مقصوص في $id: $cut');
    expect(t.takeException(), isNull);
  }

  for (final (id, w, dark) in [('single_320', 320.0, false), ('single_480_dark', 480.0, true)]) {
    testWidgets('صورة المنفردة $id', (t) async {
      await single(t);
      try {
        final d = VisualDevice('', Size(w, 2600), 2, dark: dark);
        await pumpVisual(t, d, home: (_) => const ManagerDebtsV2Screen());
        await settleAsync(t);
        // مطويّاً كما يفتحه الوكيل أوّل مرّة، ثمّ مفتوحاً (الحركات بأوقاتها صباحاً/مساءً على الضيّق)
        await shot(t, '${id}_folded', d);
        await unfold(t, RpBreakdownCard);
        await unfold(t, RpRowsCard);
        await t.scrollUntilVisible(find.byType(RpHeroKpi), -600, scrollable: find.byType(Scrollable).first);
        await shot(t, id, d);
      } finally {
        await down(t);
      }
    });
  }

  for (final (id, w) in [('merged_320', 320.0), ('merged_480', 480.0)]) {
    testWidgets('صورة كل الشركات $id', (t) async {
      final srv = _Merged(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = srv;
      ManagerDebtsV2Screen.clock = () => _now;
      AccountApi.tokenSource = ({bool force = false}) async => 'acct';
      MergedMode.reset();
      MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
      SubscribersApi.clearAllCaches();
      try {
        expect(await t.runAsync(() => MergedMode.enter()), isTrue);
        final d = VisualDevice('', Size(w, 2800), 2);
        await pumpVisual(t, d, home: (_) => const ManagerDebtsV2Screen());
        await settleAsync(t);
        // مطويّاً كما يفتحه الوكيل أوّل مرّة، ثمّ مفتوحاً (الحركات بأوقاتها صباحاً/مساءً على الضيّق)
        await shot(t, '${id}_folded', d);
        await unfold(t, RpBreakdownCard);
        await unfold(t, RpRowsCard);
        await t.scrollUntilVisible(find.byType(RpHeroKpi), -600, scrollable: find.byType(Scrollable).first);
        await shot(t, id, d);
      } finally {
        await down(t);
      }
    });
  }
}
