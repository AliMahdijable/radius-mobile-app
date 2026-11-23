import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/employee_filter.dart';
import 'package:rad_mysvcs/api/reports_api.dart';
import 'package:rad_mysvcs/screens/reports/v2/activations_report_v2_screen.dart';
import 'package:rad_mysvcs/screens/reports/v2/activations_view.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_period.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_sheets.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_export.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_perm/visual_perm_harness.dart';

// «التفعيلات» على الشكل الموحّد (٢٢ نوفمبر — «ادمج التفعيلات واليوميّة»):
//  ١) السطر: money_amount من الخادم (قاعدة التقرير الماليّ)، وغير المدفوع من «نقدي جزئي» (partialUnpaidExpr حرفاً)، والمزامَن.
//  ٢) الأرقام: «نقداً» = activate_cash_sum، «بالدين» = activate_non_cash_sum (+ الجزئيّ)، والعدّ يشمل المزامَن؛ المال المجهول لا يُعرض.
//  ٣) الجلب: نوعاً نوعاً صفحةً صفحة — الإشعارات لا تملأ السقف فتنقص التفعيلات.
//  ٤) الشاشة: الفترة والمقارنة، «اليوميّة» وحدها ⇒ اليوم وحده، كل الشركات، والتصدير بالفلاتر حرفاً.

final _now = DateTime(2026, 11, 22, 18);

Map<String, Object?> _row(int id, String type, String desc, String at,
        {num? money, bool sas = false, Map<String, Object?>? data, String first = 'مشترك', String? emp}) =>
    {
      'id': id,
      'action_type': type,
      'action_description': desc,
      'admin_username': 'admin@sup',
      if (emp != null) 'acting_employee_full_name': emp,
      'user_username': 'u$id',
      'user_firstname': first,
      'user_lastname': '$id',
      'created_at': at,
      'from_sas': sas ? 1 : 0,
      if (money != null) 'money_amount': '$money.00',
      'action_data': jsonEncode(data ?? const {}),
    };

/// يومٌ نموذجيّ: 3 نقديّ (35,000) + جزئيّ (دفع 20,000 من 35,000) + غير نقديّ (45,000) + مزامَن + تمديدان + 5 إشعارات.
List<Map<String, Object?>> _day(DateTime d, {int cash = 3, bool money = true}) {
  String at(int h) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${h.toString().padLeft(2, '0')}:10:00';
  final base = (d.month * 100 + d.day) * 100;
  num? m(num v) => money ? v : null;
  return [
    for (var i = 0; i < cash; i++)
      _row(base + i, 'SUBSCRIBER_ACTIVATE', 'تفعيل نقدي — FTTH 50 ميغا', at(15 - i),
          money: m(35000), data: {'package_name': 'FTTH 50', 'payment_type': 'نقدي', 'user_price': 35000}),
    _row(base + 10, 'SUBSCRIBER_ACTIVATE', 'تفعيل نقدي جزئي — Gaming 100', at(11),
        money: m(20000), data: {'package_name': 'Gaming 100', 'payment_type': 'نقدي جزئي', 'user_price': 35000, 'partial_cash_amount': 20000}),
    _row(base + 11, 'SUBSCRIBER_ACTIVATE', 'تفعيل غير نقدي — Gaming 100', at(10),
        money: m(45000), data: {'package_name': 'Gaming 100', 'payment_type': 'غير نقدي', 'user_price': 45000}, emp: 'زينب'),
    _row(base + 12, 'SUBSCRIBER_ACTIVATE', 'تفعيل (من الساس)', at(9), money: 0, sas: true, data: {'package_name': 'FTTH 50'}),
    _row(base + 13, 'SUBSCRIBER_EXTEND', 'تمديد', at(8), money: 0),
    _row(base + 14, 'SUBSCRIBER_EXTEND', 'تمديد', at(7), money: 0),
    for (var i = 0; i < 5; i++) _row(base + 20 + i, 'EXPIRY_NOTIFICATION', 'إشعار انتهاء', at(6)),
  ];
}

const _kSup = 'c000000000a01';
const _kEarth = 'c000000000a02';

class _Server implements HttpClientAdapter {
  _Server(this.inner);
  final VisualServer inner;

  /// كلّ السطور (الأحدث أوّلاً) لكلّ شركة (null = المفتوحة).
  final rows = <String?, List<Map<String, Object?>>>{};
  final asked = <(String?, Map<String, dynamic>)>[];
  bool echoEmployees = true;
  final failing = <String>{};

  ResponseBody _json(Object body, String? key) => ResponseBody.fromString(jsonEncode(body), 200, headers: {
        Headers.contentTypeHeader: ['application/json'],
        if (key != null) 'x-company-key': [key],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final key = o.headers['x-company-key']?.toString();
    if (o.method.toUpperCase() == 'GET' && o.uri.path == '/api/activities') {
      final q = Map<String, dynamic>.from(o.queryParameters);
      asked.add((key, q));
      if (key != null && failing.contains(key)) return _json({'success': false, 'message': 'انتهت جلستها'}, key);
      final lo = '${q['date_from']}', hi = '${q['date_to']}';
      final type = q['activity_type']?.toString();
      final all = [
        for (final r in rows[key] ?? const <Map<String, Object?>>[])
          if ('${r['created_at']}'.compareTo(lo) >= 0 &&
              '${r['created_at']}'.compareTo(hi) <= 0 &&
              (type == null || r['action_type'] == type))
            r,
      ];
      final limit = int.tryParse('${q['limit']}') ?? 100;
      final page = int.tryParse('${q['page'] ?? 1}') ?? 1;
      final slice = all.skip((page - 1) * limit).take(limit).toList();
      final emps = q['employee_ids']?.toString();
      return _json({
        'success': true,
        'data': slice,
        'pagination': {'total': all.length, 'page': page, 'limit': limit},
        // خادمٌ بعد dff8f91 يعلّم ردّه بالموظّفين الذين طبّقهم — echoEmployees=false خادمٌ قديم يتجاهلها
        if (echoEmployees && emps != null) 'employee_filter': [for (final s in emps.split(',')) int.parse(s)],
      }, key);
    }
    if (key != null) return _json({'success': true, 'data': const []}, key);
    return inner.fetch(o, body, cancel);
  }

  @override
  void close({bool force = false}) {}
}

List<Map<String, Object?>> _month({int toDay = 22, bool money = true}) => [
      for (var d = toDay; d >= 1; d--) ..._day(DateTime(2026, 11, d), money: money),
      for (var d = 31; d >= 1; d--) ..._day(DateTime(2026, 10, d), cash: 2, money: money),
    ];

Map<String, Object?> _companies() => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kSup, 'code': 'supernet', 'username': 'admin@sup', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': '11', 'ns': 'nA', 'currency': 'IQD', 'color_index': 0},
        {'key': _kEarth, 'code': 'earthlink', 'username': 'admin@el', 'name': 'ايرث لنك', 'status': 'ok', 'admin_id': 'earthlink:22', 'ns': 'nB', 'currency': 'IQD', 'color_index': 1},
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
  // ═══════════════════════════════ ١) السطر ═══════════════════════════════

  group('ActivityRow', () {
    test('money_amount والمزامَن والباقة — action_data نصّاً أو خريطة؛ غياب المبلغ مجهولٌ لا صفر', () {
      final a = ActivityRow.fromJson(Map<String, dynamic>.from(_day(DateTime(2026, 11, 3))[3]))!;
      expect(a.moneyAmount, 20000);
      expect(a.packageName, 'Gaming 100');
      expect(a.partialUnpaid, 15000);
      expect(a.fromSas, isFalse);
      final sas = ActivityRow.fromJson(Map<String, dynamic>.from(_day(DateTime(2026, 11, 3))[5]))!;
      expect(sas.fromSas, isTrue);
      final asMap = ActivityRow.fromJson({
        'id': 1,
        'action_type': 'SUBSCRIBER_ACTIVATE',
        'created_at': '2026-11-03 10:00:00',
        'action_data': {'package_name': 'X'},
      })!;
      expect(asMap.packageName, 'X');
      expect(asMap.moneyAmount, isNull, reason: 'خادمٌ لا يرسله ⇒ مجهول');
    });

    test('غير المدفوع من «نقدي جزئي» = partialUnpaidExpr حرفاً', () {
      num f(Map<String, dynamic> d, [String desc = '']) => ActivityRow.partialUnpaidOf(d, desc);
      expect(f({'payment_type': 'نقدي جزئي', 'user_price': 35000, 'partial_cash_amount': 20000}), 15000);
      expect(f({'user_price': '35000', 'partial_cash_amount': '20000'}, 'تفعيل نقدي جزئي'), 15000, reason: 'بالوصف، والأرقام نصّاً');
      expect(f({'payment_type': 'نقدي جزئي', 'price': 30000, 'partial_cash_amount': 10000}), 20000, reason: 'price حين لا user_price');
      expect(f({'payment_type': 'نقدي جزئي', 'user_price': 35000, 'partial_cash_amount': 50000}), 0, reason: 'لا دين سالب');
      expect(f({'payment_type': 'نقدي جزئي', 'user_price': 35000}), 0, reason: 'غياب partial_cash_amount صفرٌ لا السعر');
      expect(f({'payment_type': 'نقدي', 'user_price': 35000, 'partial_cash_amount': 0}), 0, reason: 'الكلاسيك يكتبه 0 لكلّ تفعيل');
    });
  });

  // ═══════════════════════════════ ٢) الأرقام ═══════════════════════════════

  group('ActivationsView', () {
    List<ActivityRow> rows(List<Map<String, Object?>> raw) =>
        [for (final m in raw) ActivityRow.fromJson(Map<String, dynamic>.from(m))!].where(ActivationsView.relevant).toList();

    test('قاعدة التقرير الماليّ: نقداً = النقديّ (والجزئيّ بما دُفع)، بالدين = غير النقديّ + غير المدفوع، والعدّ يشمل المزامَن', () {
      final r = rows(_day(DateTime(2026, 11, 3)));
      expect(r.length, 8, reason: 'الإشعارات خارج التقرير');
      final t = ActivationsView.totals(r);
      expect(t.activations, 6);
      expect(t.extends_, 2);
      expect(t.cashCount, 4);
      expect(t.debtCount, 1);
      expect(t.sasCount, 1);
      expect(t.cash, 3 * 35000 + 20000);
      expect(t.debt, 45000 + 15000);
      expect(t.known, isTrue);
      final k = {for (final x in ActivationsView.kpis(r, null)) x.id: x};
      expect(k.keys, [ActKpiIds.activations, ActKpiIds.extends_, ActKpiIds.cash, ActKpiIds.debt]);
      expect(k[ActKpiIds.debt]!.upIsGood, isFalse);
    });

    test('مبلغٌ مجهول (خادمٌ قديم) ⇒ لا بطاقة مال ولا صفرٌ كاذب — الأعداد وحدها', () {
      final r = rows(_day(DateTime(2026, 11, 3), money: false));
      expect(ActivationsView.totals(r).known, isFalse);
      expect([for (final k in ActivationsView.kpis(r, null)) k.id], [ActKpiIds.activations, ActKpiIds.extends_]);
    });

    test('النوع والبطاقة والبحث والفرق', () {
      final r = rows(_day(DateTime(2026, 11, 3)));
      expect(ActivationsView.filter(r, const ['debt']).length, 1);
      expect(ActivationsView.filter(r, const ['cash', 'sas']).length, 5);
      expect(r.where(ActivationsView.drill(ActKpiIds.debt)).length, 2, reason: 'غير النقديّ والجزئيّ');
      expect(r.where(ActivationsView.drill(ActKpiIds.extends_)).length, 2);
      expect(ActivationsView.search(r, 'gaming').length, 2, reason: 'بالباقة');
      final prev = rows(_day(DateTime(2026, 10, 3), cash: 2));
      final k = {for (final x in ActivationsView.kpis(r, prev)) x.id: x};
      expect(k[ActKpiIds.activations]!.delta, closeTo((6 - 5) / 5, 1e-9));
      expect(k[ActKpiIds.cash]!.delta, closeTo((125000 - 90000) / 90000, 1e-9));
    });

    test('العدد يوماً بيوم عبر الشهرين بترتيبه، و«قسّم حسب» بالعدد', () {
      final r = rows(_month());
      final range = RpRange.of(RpPreset.last30, now: _now);
      final inRange = r.where((x) => x.createdAt.compareTo('2026-10-24') >= 0).toList();
      final t = ActivationsView.trend(inRange, range);
      expect([for (final p in t) p.day], [for (var d = 24; d <= 31; d++) d, for (var d = 1; d <= 22; d++) d]);
      expect(t.first.a, 5);
      expect(t.last.a, 6);
      expect(t.last.b, 2);
      final byPackage = ActivationsView.shares(r, (x) => x.packageName ?? 'بلا باقة');
      expect(byPackage.first.name, 'FTTH 50', reason: 'الأكثر عدداً أوّلاً');
      expect(byPackage.fold<double>(0, (a, s) => a + s.share), closeTo(1, 1e-9));
    });
  });

  // ═══════════════════════════════ ٣) الجلب ═══════════════════════════════

  group('ReportsApi.activitiesAll', () {
    setUpAll(visualSetUpAll);
    testWidgets('نوعاً نوعاً صفحةً صفحة حتى آخرها — بلا تكرار، والإشعارات لا تزاحم', (t) async {
      final server = _Server(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      try {
        server.rows[null] = [
          for (var i = 4499; i >= 0; i--)
            _row(i, 'SUBSCRIBER_ACTIVATE', 'تفعيل نقدي', '2026-11-${(1 + i % 20).toString().padLeft(2, '0')} 10:00:00', money: 1),
          for (var i = 0; i < 6000; i++) _row(100000 + i, 'EXPIRY_NOTIFICATION', 'إشعار', '2026-11-05 10:00:00'),
        ];
        final r = await t.runAsync(() => ReportsApi.activitiesAll(
            from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 22), activityType: 'SUBSCRIBER_ACTIVATE'));
        expect(r!.ok, isTrue);
        expect(r.complete, isTrue);
        expect(r.rows.length, 4500);
        expect(r.rows.map((x) => x.id).toSet().length, 4500);
        expect(server.asked.length, 3, reason: '2000 + 2000 + 500');
        expect(server.asked.every((a) => a.$2['activity_type'] == 'SUBSCRIBER_ACTIVATE'), isTrue);
        server.asked.clear();
        final capped = await t.runAsync(() => ReportsApi.activitiesAll(
            from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 22), activityType: 'SUBSCRIBER_ACTIVATE', maxPages: 2));
        expect(capped!.complete, isFalse, reason: 'بلغ حدّ الصفحات ⇒ يُقال');
        expect(capped.rows.length, 4000);
      } finally {
        await visualTearDown();
      }
    });
  });

  // ═══════════════════════════════ ٤) الشاشة ═══════════════════════════════

  group('الشاشة', () {
    setUpAll(visualSetUpAll);
    late _Server server;

    Future<void> up({Map<String, Object>? prefs}) async {
      server = _Server(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      if (prefs != null) SharedPreferences.setMockInitialValues(prefs);
      ActivationsReportV2Screen.clock = () => _now;
    }

    Future<void> down(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      MergedMode.reset();
      ReportExportActions.debugSink = null;
      ActivationsReportV2Screen.clock = DateTime.now;
      await visualTearDown();
    }

    Future<void> settleAsync(WidgetTester t, [int n = 12]) async {
      for (var i = 0; i < n; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> open(WidgetTester t) async {
      await pumpVisual(t, const VisualDevice('', Size(430, 2600), 2), home: (_) => const ActivationsReportV2Screen());
      await settleAsync(t);
    }

    Future<void> merged(WidgetTester t) async {
      AccountApi.tokenSource = ({bool force = false}) async => 'acct';
      MergedMode.reset();
      MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
      expect(await t.runAsync(() => MergedMode.enter()), isTrue);
    }

    Map<String, RpKpi> kpis(WidgetTester t) => {for (final k in t.widget<RpKpiGrid>(find.byType(RpKpiGrid)).kpis) k.id: k};

    // المالك (٢٣ نوفمبر): «ماكدر اختار اكثر من موظف بالفلاتر بجميع التقارير»
    for (final echo in [true, false]) {
      testWidgets('موظّفان: employee_ids لكلّ نوع — ${echo ? 'الخادم يطبّقها ⇒ الأرقام' : 'خادمٌ قديم ⇒ «لا يدعم بعد» بلا أرقام'}', (t) async {
        await up(prefs: {
          'report.v2.activations': jsonEncode({
            'p': 'thisMonth',
            'e': {
              'open': ['9', '7'],
            },
            'ot': 'supernet:12',
          }),
        });
        server.echoEmployees = echo;
        try {
          await open(t);
          expect(server.asked, isNotEmpty);
          expect(server.asked.every((a) => a.$2['employee_ids'] == '7,9' && !a.$2.containsKey('employee_id')), isTrue);
          if (echo) {
            expect(find.byType(RpKpiGrid), findsOneWidget);
            expect(find.textContaining('الموظّفون: '), findsOneWidget);
          } else {
            expect(find.textContaining(kEmployeesUnsupported), findsWidgets);
            expect(find.byType(RpKpiGrid), findsNothing, reason: 'لا أرقامٌ غير مفلترة كأنّها مفلترة');
          }
          expect(t.takeException(), isNull);
        } finally {
          await down(t);
        }
      });
    }

    Future<void> tapExport(WidgetTester t, String label) async {
      await t.scrollUntilVisible(find.text(label), 600, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text(label));
      await settleAsync(t, 6);
    }

    testWidgets('منفردة: هذا الشهر كاملاً بأنواعه الثلاثة، والأرقام بقاعدة الماليّ، والمقارنة بالأيّام نفسها من الماضي', (t) async {
      await up();
      server.rows[null] = _month();
      try {
        await open(t);
        final types = {for (final a in server.asked) a.$2['activity_type']};
        expect(types, {'SUBSCRIBER_ACTIVATE', 'SUBSCRIBER_EXTEND', 'SUBSCRIBER_ADD'});
        expect(server.asked.first.$2['date_from'], '2026-11-01 00:00:00');
        expect(server.asked.any((a) => a.$2['date_from'] == '2026-10-01 00:00:00' && a.$2['date_to'] == '2026-10-22 23:59:59'), isTrue,
            reason: 'المقارنة');
        final k = kpis(t);
        expect(k[ActKpiIds.activations]!.value, 22 * 6);
        expect(k[ActKpiIds.extends_]!.value, 44);
        expect(k[ActKpiIds.cash]!.value, 22 * 125000);
        expect(k[ActKpiIds.debt]!.value, 22 * 60000);
        expect(k[ActKpiIds.activations]!.delta, closeTo((132 - 110) / 110, 1e-9));
        expect(find.byType(RpTrendCard), findsNothing, reason: '«يوماً بيوم» أُلغي من كلّ التقارير (المالك ٢٢ نوفمبر)');
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });

    testWidgets('«التفعيلات اليوميّة» وحدها ⇒ اليوم وحده بلا مقارنة، ولو حُفظت فترةٌ أخرى', (t) async {
      await up(prefs: {'report.v2.activations': jsonEncode({'p': 'thisMonth', 'c': true})});
      PermissionsService.debugSet(isEmployee: true, permissions: const {'reports.daily_activations': true});
      server.rows[null] = _month();
      try {
        await open(t);
        expect(server.asked, isNotEmpty);
        expect(server.asked.every((a) => a.$2['date_from'] == '2026-11-22 00:00:00' && a.$2['date_to'] == '2026-11-22 23:59:59'), isTrue,
            reason: 'لا شهر ولا مقارنة');
        expect(kpis(t)[ActKpiIds.activations]!.value, 6);
        expect(kpis(t)[ActKpiIds.activations]!.delta, isNull);
        // الرأس بسطرٍ واحد (٢٢ نوفمبر): الفترة لا تُلمس لصلاحيّة اليوميّة وحدها، ولا «قارن»
        expect(t.widget<RpHeader>(find.byType(RpHeader)).onPeriod, isNull);
        expect(find.byKey(const ValueKey('rp-head-compare')), findsNothing);
        expect(find.textContaining('صلاحيّتك «التفعيلات اليوميّة»'), findsOneWidget);
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });

    testWidgets('التصدير بالفلاتر حرفاً: النوع والبحث، ورأسه يسمّيهما، والصفوف كاملة', (t) async {
      await up(prefs: {
        'report.v2.activations': jsonEncode({
          'p': 'thisMonth',
          'c': false,
          't': ['debt'],
        }),
      });
      server.rows[null] = _month();
      final got = <ReportExportRequest>[];
      ReportExportActions.debugSink = (r) async => got.add(r);
      try {
        await open(t);
        await tapExport(t, 'Excel');
        final r = got.single;
        expect(r.rows.length, 22, reason: 'غير النقديّ وحده، كلّ أيّام الشهر');
        expect(r.rows.every((row) => row.contains('تفعيل بالدين')), isTrue);
        expect(r.details, contains('النوع: تفعيل بالدين'));
        expect(r.details, contains('عدد الحركات: 22'));
        expect(r.details.any((d) => d.startsWith('ناقص')), isFalse);
        got.clear();
        await unfold(t, RpRowsCard);
        final rows = find.byType(RpRowsCard);
        await t.scrollUntilVisible(find.descendant(of: rows, matching: find.byType(TextField)), 600,
            scrollable: find.byType(Scrollable).first);
        await t.enterText(find.descendant(of: rows, matching: find.byType(TextField)), '11031');
        await t.pump(const Duration(milliseconds: 200));
        await tapExport(t, 'PDF');
        expect(got.single.rows.length, 1);
        expect(got.single.details, contains('بحث: «11031»'));
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });

    testWidgets('فلتر الباقة (بند المقترح ١٢): الأرقام والملفّ لباقتها وحدها، وورقة الفلاتر بباقات الفترة', (t) async {
      await up(prefs: {
        'report.v2.activations': jsonEncode({
          'p': 'thisMonth',
          'c': false,
          'pk': ['|Gaming 100'],
          'ot': 'supernet:12',
        }),
      });
      server.rows[null] = _month();
      final got = <ReportExportRequest>[];
      ReportExportActions.debugSink = (r) async => got.add(r);
      try {
        await open(t);
        final k = kpis(t);
        expect(k[ActKpiIds.activations]!.value, 22 * 2, reason: 'الجزئيّ وغير النقديّ كلّ يوم');
        expect(k[ActKpiIds.cash]!.value, 22 * 20000);
        expect(k[ActKpiIds.debt]!.value, 22 * 60000, reason: 'بالدين + غير المدفوع من الجزئيّ');
        expect(find.text('الباقة: Gaming 100'), findsOneWidget);
        // الورقة: باقات الفترة كلّها (والتمديد بلا باقة اسمٌ صريح)
        await t.tap(find.byKey(const ValueKey('rp-head-period')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
        final sheet = t.widget<RpFilterSheet>(find.byType(RpFilterSheet));
        expect([for (final p in sheet.packages) p.$2], ['FTTH 50', 'Gaming 100', 'تمديد (بلا باقة)']);
        Navigator.of(t.element(find.byType(RpFilterSheet))).pop();
        await t.pump(const Duration(milliseconds: 500));
        await tapExport(t, 'Excel');
        final r = got.single;
        expect(r.rows.length, 44);
        expect(r.details, contains('الباقة: Gaming 100'));
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });

    testWidgets('كل الشركات: كلّ شركةٍ بمفتاحها ومديرها، والمتعذّرة خارج المجموع، والمال المجهول «—»', (t) async {
      await up();
      server.rows[_kSup] = _month();
      server.rows[_kEarth] = _month(money: false); // خادمٌ بلا money_amount
      try {
        await merged(t);
        await open(t);
        final ids = {for (final a in server.asked) a.$1: a.$2['user_ids']};
        expect(ids, {_kSup: '11', _kEarth: 'earthlink:22'});
        final table = t.widget<RpCompanyTable>(find.byType(RpCompanyTable));
        expect(table.heads, ['نقداً', 'بالدين', 'الحركات']);
        final earth = table.lines.firstWhere((l) => l.company.key == _kEarth);
        expect(earth.a, isNull, reason: 'مالٌ مجهول لا صفر');
        expect(table.total[0], isNull, reason: 'لا جمعٌ ناقص');
        expect(table.total[2], 2 * 22 * 8);
        expect(find.text('الشركات · 2 من 2'), findsOneWidget);
        expect([for (final k in t.widget<RpKpiGrid>(find.byType(RpKpiGrid)).kpis) k.id], [ActKpiIds.activations, ActKpiIds.extends_]);
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });

    testWidgets('كل الشركات: المتعذّرة تُسمّى خارج المجموع ولا تُعدّ صفراً، وتصديرها يسمّيها', (t) async {
      await up();
      server.rows[_kSup] = _month();
      server.rows[_kEarth] = _month();
      server.failing.add(_kEarth);
      final got = <ReportExportRequest>[];
      ReportExportActions.debugSink = (r) async => got.add(r);
      try {
        await merged(t);
        await open(t);
        final table = t.widget<RpCompanyTable>(find.byType(RpCompanyTable));
        expect(table.lines.firstWhere((l) => l.company.key == _kEarth).state, RpCompanyState.failed);
        expect(table.outside, contains('ايرث لنك'));
        expect(kpis(t)[ActKpiIds.activations]!.value, 22 * 6, reason: 'سوبرنت وحدها');
        await tapExport(t, 'Excel');
        expect(got.single.details.first, 'الشركات: سوبرنت');
        expect(got.single.details[1], startsWith('خارج الملفّ: ايرث لنك'));
        expect({for (final r in got.single.rows) r.first}, {'سوبرنت'});
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });
  });
}
