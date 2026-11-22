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
import 'package:rad_mysvcs/screens/reports/v2/package_dist_v2_screen.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_period.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_export.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «توزيع الباقات» على الشكل الموحّد (٢٢ نوفمبر — «اكمل كلشي»): آخر 30 يوماً أوّل مرّة، وبفترة بطاقة الرئيسيّة حين تفتحه، والموظّف
/// المنفِّذ للخادم؛ الإيراد بالدينار وحده والربح مجموع ربح كلّ شركةٍ بقاعدتها ومن لا يُعرف رقمها يُسمّى؛ ولمسة باقةٍ تفتح أرقامها؛
/// والتصدير كلّ الباقات بفلاتره ورأسه.
final _now = DateTime(2026, 11, 22, 12);

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

/// يسجّل طلبات التقرير ويمرّر الباقي للحاضنة (التي تخدم التقرير المنفرد نفسه).
class _Spy implements HttpClientAdapter {
  _Spy(this.inner);
  final HttpClientAdapter inner;
  final asked = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) {
    if (o.uri.path == '/api/reports/finance/packages') asked.add(Map.of(o.queryParameters));
    return inner.fetch(o, rs, cf);
  }

  @override
  void close({bool force = false}) {}
}

// ═══════════════════════════════ كل الشركات ═══════════════════════════════

const _kA = 'c0000000000aa'; // سوبرنت — صاحبها، بالدينار
const _kB = 'c0000000000bb'; // الجزيرة — موظّفٌ فيها (لا ربح)، بالدينار
const _kU = 'c0000000000dd'; // دولار — صاحبها
const _kF = 'c0000000000ff'; // تتعذّر
const _kT = 'c0000000000ee'; // الوطني — ليس من شركات التطبيق (appCapable) فلا يُطلب

Map<String, Object?> _row(String key, String name, int total, int acts, int revenue, {num? profit, num? cost}) => {
      'key': key,
      'name': name,
      'price': 35000,
      'subscribers_total': total,
      'subscribers_active': total - 5,
      'activations': acts,
      'extensions': 1,
      'revenue': revenue,
      if (profit != null) ...{'unit_cost': 20000, 'cost': cost, 'profit_total': profit, 'profit_estimated': profit * 3},
    };

class _Merged implements HttpClientAdapter {
  _Merged(this.inner);
  final HttpClientAdapter inner;
  final asked = <(String, Map<String, dynamic>)>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    if (o.uri.path != '/api/reports/finance/packages') return inner.fetch(o, rs, cf);
    asked.add((key ?? '-', Map.of(o.queryParameters)));
    final h = {'x-company-key': [key ?? '']};
    Map<String, Object?> rep({required bool owner, required List<Map<String, Object?>> rows, num? profit, num? cost}) => {
          'success': true,
          'data': {
            'owner': owner,
            'cost_exempt': false,
            'rows': rows,
            'totals': {
              'subscribers_total': rows.fold<int>(0, (a, r) => a + (r['subscribers_total'] as int)),
              'subscribers_active': rows.fold<int>(0, (a, r) => a + (r['subscribers_active'] as int)),
              'activations': rows.fold<int>(0, (a, r) => a + (r['activations'] as int)),
              'extensions': rows.length,
              'revenue': rows.fold<int>(0, (a, r) => a + (r['revenue'] as int)),
              if (profit != null) ...{'cost': cost, 'profit_total': profit, 'profit_estimated': profit * 3},
            },
          },
        };
    return switch (key) {
      _kA => _json(200, rep(owner: true, rows: [
          _row('p:1', 'سوبر 50', 300, 20, 700000, profit: 280000, cost: 420000),
          _row('p:2', 'سوبر 100', 100, 10, 300000, profit: -20000, cost: 320000),
        ], profit: 260000, cost: 740000), headers: h),
      _kB => _json(200, rep(owner: false, rows: [_row('p:1', 'جزيرة 40', 50, 5, 200000)]), headers: h),
      _kU => _json(200, rep(owner: true, rows: [_row('p:1', 'Dollar 20', 40, 4, 80, profit: 30, cost: 50)], profit: 30, cost: 50), headers: h),
      _ => _json(409, {'success': false, 'message': 'انتهت جلسة «فاشلة» — افتحها من «شركاتي»'}, headers: h),
    };
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _companies() => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kA, 'code': 'supernet', 'username': 'mahdi', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': 'supernet:12', 'ns': 'nA', 'currency': 'IQD', 'color_index': 0},
        {'key': _kB, 'code': 'jt', 'username': 'admin@b', 'name': 'الجزيرة', 'status': 'ok', 'admin_id': 'jt:22', 'ns': 'nB', 'currency': 'IQD', 'color_index': 1},
        {'key': _kU, 'code': 'us', 'username': 'u', 'name': 'دولار', 'status': 'ok', 'admin_id': 'us:3', 'ns': 'nU', 'currency': 'USD', 'color_index': 2},
        {'key': _kF, 'code': 'fx', 'username': 'f', 'name': 'فاشلة', 'status': 'ok', 'admin_id': 'fx:4', 'ns': 'nF', 'currency': 'IQD', 'color_index': 3},
        {'key': _kT, 'code': 'ftth', 'username': 't', 'name': 'الوطني', 'provider': 'ftth', 'status': 'ok', 'admin_id': 'ftth:5', 'ns': 'nT', 'currency': 'IQD', 'color_index': 4},
      ],
    };

void main() {
  setUpAll(visualSetUpAll);

  Future<void> settleAsync(WidgetTester t, [int n = 16]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester t, {PackageDistV2Screen screen = const PackageDistV2Screen(), Size size = const Size(430, 2600), bool dark = false}) async {
    await pumpVisual(t, VisualDevice('', size, 2, dark: dark), home: (_) => screen);
    await settleAsync(t);
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    MergedMode.reset();
    ReportExportActions.debugSink = null;
    PackageDistV2Screen.clock = DateTime.now;
    await visualTearDown();
  }

  Map<String, RpKpi> kpis(WidgetTester t) => {for (final k in t.widget<RpKpiGrid>(find.byType(RpKpiGrid)).kpis) k.id: k};
  RpKpi hero(WidgetTester t) => t.widget<RpHeroKpi>(find.byType(RpHeroKpi)).kpi;

  Future<void> tapExport(WidgetTester t, String label) async {
    await t.scrollUntilVisible(find.text(label), 600, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text(label));
    await settleAsync(t, 6);
  }

  Future<_Spy> single({Map<String, Object>? prefs}) async {
    final srv = _Spy(await visualSetUp(s1bSasOwner));
    ApiClient.dio.httpClientAdapter = srv;
    if (prefs != null) SharedPreferences.setMockInitialValues(prefs);
    PackageDistV2Screen.clock = () => _now;
    return srv;
  }

  Future<_Merged> merged(WidgetTester t) async {
    final srv = _Merged(await visualSetUp(s1bSasOwner));
    ApiClient.dio.httpClientAdapter = srv;
    PackageDistV2Screen.clock = () => _now;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    MergedMode.reset();
    MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
    SubscribersApi.clearAllCaches();
    expect(await t.runAsync(() => MergedMode.enter()), isTrue);
    return srv;
  }

  testWidgets('منفردة: آخر 30 يوماً، الإيراد والمشتركون والربحان بقاعدتها، لمسة باقةٍ تفتحها، والتصدير كلّ الباقات برأسه', (t) async {
    final srv = await single();
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      await open(t);
      final q = srv.asked.single;
      expect(q['date_from'], '2026-10-24 00:00:00');
      expect(q['date_to'], '2026-11-22 23:59:59');
      expect(q.containsKey('user_ids'), isTrue, reason: 'نطاق تقارير التطبيق كالشاشة السابقة');
      expect(q.containsKey('employee_id'), isFalse);
      expect(hero(t).value, 3980000);
      final k = kpis(t);
      expect(k['subs']!.text, '813');
      expect(k['subs']!.hint, 'الفعّالون 701');
      expect(k['acts']!.value, 82);
      expect(k['acts']!.hint, '25 تمديد');
      expect(k['profit']!.value, 1592000);
      expect(k['profit']!.hint, 'بعد كلفة 2,388,000 د.ع');
      expect(k['est']!.value, 11647000);
      final card = t.widget<RpBreakdownCard>(find.byType(RpBreakdownCard));
      expect(card.tabs, ['المشتركون', 'الحركة', 'الإيراد', 'الربح']);
      expect(card.shares.first.name, 'FTTH 50 ميغا');
      expect(card.shares.first.count, 412);

      // لمسة الباقة ⇒ أرقامها كلّها
      card.onShare!(0);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('سعر البيع'), findsOneWidget);
      expect(find.text('35,000 د.ع'), findsOneWidget);
      expect(find.text('الربح المقدَّر'), findsWidgets);
      await t.tapAt(const Offset(20, 20));
      await t.pump(const Duration(milliseconds: 400));

      await tapExport(t, 'Excel');
      final r = got.single;
      expect(r.rows.length, 5);
      expect(r.columns, contains('كلفة الباقة'));
      expect(r.details, contains('الترتيب: المشتركون'));
      expect(r.details, contains('الإيراد: 3,980,000 د.ع'));
      expect(r.details, contains('عدد الباقات: 5'));
      expect(r.subtitle, startsWith('آخر 30 يوماً'));
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('من بطاقة الرئيسيّة ⇒ فترتها نفسها لهذا الفتح وحده؛ والموظّف المحفوظ يذهب للخادم ويُسمّى في الرأس', (t) async {
    final srv = await single(prefs: {
      'report.v2.packages': jsonEncode({
        'p': 'last90',
        'e': {'open': '7'},
        'ot': 'supernet:12',
      }),
    });
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      await open(t, screen: const PackageDistV2Screen(initialPreset: RpPreset.yesterday));
      final q = srv.asked.first;
      expect(q['date_from'], '2026-11-21 00:00:00');
      expect(q['date_to'], '2026-11-21 23:59:59');
      expect(q['employee_id'], '7');
      expect(find.textContaining('الموظّف: '), findsOneWidget);
      await tapExport(t, 'PDF');
      expect(got.single.details.any((d) => d.startsWith('الموظّف: ')), isTrue);
      expect(got.single.subtitle, startsWith('أمس'));
      final saved = (await SharedPreferences.getInstance()).getString('report.v2.packages')!;
      expect(jsonDecode(saved)['p'], 'last90', reason: 'فترة البطاقة لا تُحفظ');
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('كل الشركات: كلٌّ بنطاقه، الإيراد بالدينار وحده، الربح لمن يُعرف ربحها، والمتعذّرة وغير المدعومة تُسمّيان', (t) async {
    final srv = await merged(t);
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      await open(t, size: const Size(430, 3200));
      final byKey = {for (final a in srv.asked) a.$1: a.$2};
      expect(byKey.keys.toSet(), {_kA, _kB, _kU, _kF}, reason: 'الوطني لا يُطلب');
      expect(byKey[_kA]!['user_ids'], 'supernet:12');
      expect(byKey[_kB]!['user_ids'], 'jt:22');

      final h = hero(t);
      expect(h.value, 1200000, reason: 'سوبرنت 1,000,000 + الجزيرة 200,000 — الدولار لا يُجمع');
      final heroCard = t.widget<RpHeroKpi>(find.byType(RpHeroKpi));
      expect(heroCard.note, 'لا يشمل: فاشلة، دولار');
      final k = kpis(t);
      expect(k['subs']!.text, '490', reason: '400 + 50 + 40 — العدد يُجمع');
      expect(k['profit']!.value, 260000, reason: 'سوبرنت وحدها: الجزيرة بلا ربحٍ للموظّف، والدولار عملةٌ أخرى');
      expect(k['profit']!.hint, 'لا يشمل: فاشلة، الجزيرة، دولار');
      expect(find.textContaining('الوطني'), findsNothing, reason: 'الوطني ليس من شركات التطبيق — لا يُطلب ولا يُسمّى');

      final table = t.widget<RpCompanyTable>(find.byType(RpCompanyTable));
      expect([for (final l in table.lines) (l.company.key, l.state, l.b, l.c)], [
        (_kA, RpCompanyState.ok, 1000000, 260000),
        (_kB, RpCompanyState.ok, 200000, null),
        (_kU, RpCompanyState.ok, null, null),
        (_kF, RpCompanyState.failed, null, null),
      ]);
      expect(table.total, [30 + 5 + 4, 1200000, 260000]);

      // الربح: باقات صاحب الحساب بالدينار — والخاسرة بإشارتها
      final card = t.widget<RpBreakdownCard>(find.byType(RpBreakdownCard));
      card.onTab!(3);
      await t.pump();
      final shares = t.widget<RpBreakdownCard>(find.byType(RpBreakdownCard)).shares;
      expect([for (final s in shares) (s.name, s.amount)], [('سوبر 50', 280000), ('سوبر 100', -20000)]);

      await tapExport(t, 'Excel');
      final r = got.single;
      expect(r.rows.length, 4, reason: 'كلّ الباقات — ما خارج تبويب الربح يُلحق آخر الملفّ');
      expect(r.columns.first, 'الشركة');
      expect(r.details.first, 'الشركات: سوبرنت، الجزيرة، دولار');
      expect(r.details, contains('الترتيب: الربح'));
      expect(r.details.any((d) => d.startsWith('ناقص:') && d.contains('«فاشلة»')), isTrue);
      expect(r.details.any((d) => d.startsWith('ناقص:') && d.contains('«دولار»')), isTrue);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  // ═══════════════════════════════ الصور ═══════════════════════════════

  Future<void> shot(WidgetTester t, String id, double w) async {
    final cut = <String>[
      for (final e in find.byType(RichText).evaluate())
        if (e.renderObject case final RenderParagraph ro when ro.didExceedMaxLines) ro.text.toPlainText(),
    ];
    final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(visualRootKey));
    final png = await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    final out = Directory('build/report_design')..createSync(recursive: true);
    File('${out.path}/pk_$id.png').writeAsBytesSync(png!, flush: true);
    expect(cut, isEmpty, reason: 'نصٌّ مقصوص في $id: $cut');
    expect(t.takeException(), isNull);
  }

  for (final (id, w, dark) in [('single_320', 320.0, false), ('single_480_dark', 480.0, true)]) {
    testWidgets('صورة المنفردة $id', (t) async {
      await single();
      try {
        await open(t, size: Size(w, 2600), dark: dark);
        await shot(t, id, w);
      } finally {
        await down(t);
      }
    });
  }

  for (final (id, w) in [('merged_320', 320.0), ('merged_480', 480.0)]) {
    testWidgets('صورة كل الشركات $id', (t) async {
      await merged(t);
      try {
        await open(t, size: Size(w, 3000));
        await shot(t, id, w);
      } finally {
        await down(t);
      }
    });
  }
}
