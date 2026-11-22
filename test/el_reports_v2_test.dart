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
import 'package:rad_mysvcs/screens/reports/v2/el_reports_v2.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_export.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';

import 'visual_perm/visual_perm_harness.dart';

/// تقريرا ايرث لنك على الشكل الموحّد (٢٢ نوفمبر): شركات ايرث لنك وحدها في الشريط (المالك ٨ نوفمبر)، كلٌّ بطلبٍ موجَّه، والمتعذّرة
/// تُسمّى ولا تُجمع؛ الباقة الواحدة من الشركات سطرٌ واحد؛ والتصدير بما على الشاشة (البحث، وعمودٌ لكلّ شركة).
const _kS = 'c0000000000aa'; // ساس — لا يُطلب ولا يظهر
const _kL1 = 'c00000000e101';
const _kL2 = 'c00000000e102';
const _kL3 = 'c00000000e103'; // ايرث لنك تتعذّر

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

class _Srv implements HttpClientAdapter {
  _Srv(this.inner);
  final HttpClientAdapter inner;
  final asked = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    if (!path.startsWith('/api/v2/el/')) return inner.fetch(o, rs, cf);
    asked.add('$path ${key ?? '-'}');
    final h = {'x-company-key': [key ?? '']};
    if (key == _kL3) return _json(409, {'success': false, 'message': 'انتهت جلسة «ايرث لنك ٣»'}, headers: h);
    if (path == '/api/v2/el/by-package') {
      final rows = switch (key) {
        _kL1 => [{'name': 'FTTH 50M', 'count': 30}, {'name': 'FTTH 100M', 'count': 5}],
        _kL2 => [{'name': 'FTTH 50M', 'count': 12}],
        _ => [{'name': 'FTTH 75M', 'count': 9}, {'name': 'FTTH 35M', 'count': 4}],
      };
      return _json(200, {'success': true, 'data': rows}, headers: h);
    }
    if (path == '/api/v2/el/test-usage') {
      final rows = switch (key) {
        _kL1 => [
            {'name': 'تجربة ١', 'username': 't1@el', 'date': '2026-11-21 10:00:00', 'usage': 512},
            {'name': 'علي التجريبي', 'username': 'ali@el', 'date': '2026-11-22 09:30:00'},
          ],
        _kL2 => [{'name': 'تجربة ٢', 'username': 't2@el', 'date': '2026-11-20 18:00:00'}],
        _ => [{'name': 'تجربتي', 'username': 'me@el', 'date': '2026-11-22 08:00:00', 'usage': 3}],
      };
      return _json(200, {'success': true, 'data': rows}, headers: h);
    }
    return _json(404, {'success': false}, headers: h);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _companies() => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kS, 'code': 'supernet', 'username': 'mahdi', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': '2', 'ns': 'nA', 'currency': 'IQD', 'color_index': 0},
        {'key': _kL1, 'code': 'earthlink', 'provider': 'earthlink', 'username': 'el1', 'name': 'ايرث لنك ١', 'status': 'ok', 'admin_id': 'earthlink:31', 'ns': 'nL1', 'currency': 'IQD', 'color_index': 6},
        {'key': _kL2, 'code': 'earthlink', 'provider': 'earthlink', 'username': 'el2', 'name': 'ايرث لنك ٢', 'status': 'ok', 'admin_id': 'earthlink:32', 'ns': 'nL2', 'currency': 'IQD', 'color_index': 7},
        {'key': _kL3, 'code': 'earthlink', 'provider': 'earthlink', 'username': 'el3', 'name': 'ايرث لنك ٣', 'status': 'ok', 'admin_id': 'earthlink:33', 'ns': 'nL3', 'currency': 'IQD', 'color_index': 8},
      ],
    };

void main() {
  setUpAll(visualSetUpAll);
  late _Srv srv;

  Future<void> settleAsync(WidgetTester t, [int n = 14]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> up(WidgetTester t, {bool merged = false}) async {
    srv = _Srv(await visualSetUp(s1Owner));
    ApiClient.dio.httpClientAdapter = srv;
    if (merged) {
      AccountApi.tokenSource = ({bool force = false}) async => 'acct';
      MergedMode.reset();
      MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
      SubscribersApi.clearAllCaches();
      expect(await t.runAsync(() => MergedMode.enter()), isTrue);
    }
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    MergedMode.reset();
    ReportExportActions.debugSink = null;
    await visualTearDown();
  }

  Future<void> open(WidgetTester t, Widget screen, {Size size = const Size(430, 2400)}) async {
    await pumpVisual(t, VisualDevice('', size, 2), home: (_) => screen);
    await settleAsync(t);
  }

  Future<void> tapExport(WidgetTester t, String label) async {
    await t.scrollUntilVisible(find.text(label), 600, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text(label));
    await settleAsync(t, 4);
  }

  testWidgets('الباقات منفردة: المجموع والعدد، والتصدير كلّ الباقات', (t) async {
    await up(t);
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      await open(t, const ElByPackageV2Screen());
      expect(srv.asked, ['/api/v2/el/by-package -']);
      expect(t.widget<RpHeroKpi>(find.byType(RpHeroKpi)).kpi.value, 13);
      final card = t.widget<RpBreakdownCard>(find.byType(RpBreakdownCard));
      expect([for (final s in card.shares) (s.name, s.count)], [('FTTH 75M', 9), ('FTTH 35M', 4)]);
      expect(find.byType(RpCompanyTable), findsNothing);
      await tapExport(t, 'Excel');
      expect(got.single.columns, ['الباقة', 'المشتركون']);
      expect(got.single.rows, [
        ['FTTH 75M', '9'],
        ['FTTH 35M', '4'],
      ]);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('الباقات بكل الشركات: ايرث لنك وحدها، الباقة سطرٌ واحد، المتعذّرة تُسمّى، والتصدير بعمودٍ لكلّ شركة', (t) async {
    await up(t, merged: true);
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      await open(t, const ElByPackageV2Screen());
      expect(srv.asked.toSet(), {'/api/v2/el/by-package $_kL1', '/api/v2/el/by-package $_kL2', '/api/v2/el/by-package $_kL3'});
      expect(find.textContaining('سوبرنت'), findsNothing, reason: 'شركات الساس لا شارة لها هنا');
      expect(t.widget<RpHeroKpi>(find.byType(RpHeroKpi)).kpi.value, 47);
      final card = t.widget<RpBreakdownCard>(find.byType(RpBreakdownCard));
      expect([for (final s in card.shares) (s.name, s.count)], [('FTTH 50M', 42), ('FTTH 100M', 5)]);
      expect(card.shares.first.sub, 'ايرث لنك ١ 30 · ايرث لنك ٢ 12');
      final table = t.widget<RpCompanyTable>(find.byType(RpCompanyTable));
      expect([for (final l in table.lines) (l.company.key, l.state, l.a, l.b)], [
        (_kL1, RpCompanyState.ok, 35, 2),
        (_kL2, RpCompanyState.ok, 12, 1),
        (_kL3, RpCompanyState.failed, null, null),
      ]);
      expect(table.total, [47, 3]);
      await tapExport(t, 'PDF');
      final r = got.single;
      expect(r.columns, ['الباقة', 'المشتركون', 'ايرث لنك ١', 'ايرث لنك ٢']);
      expect(r.rows.first, ['FTTH 50M', '42', '30', '12']);
      expect(r.details.first, 'الشركات: ايرث لنك ١، ايرث لنك ٢');
      expect(r.details.any((d) => d.startsWith('ناقص:') && d.contains('«ايرث لنك ٣»')), isTrue);

      // ايرث لنك ٢ وحدها (لمسة سطرها)
      table.onTap!(table.lines[1].company);
      await settleAsync(t);
      expect(t.widget<RpHeroKpi>(find.byType(RpHeroKpi)).kpi.value, 12);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('التجريبيّ بكل الشركات: العدد، يوماً بيوم بشارة الشركة، والبحث يحصر الملفّ', (t) async {
    await up(t, merged: true);
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      await open(t, const ElTestUsageV2Screen());
      expect(t.widget<RpHeroKpi>(find.byType(RpHeroKpi)).kpi.value, 3);
      final rows = t.widget<RpRowsCard>(find.byType(RpRowsCard));
      expect([for (final d in rows.days) d.date], ['2026/11/22', '2026/11/21', '2026/11/20'], reason: 'الأحدث أوّلاً');
      expect(rows.days.first.rows.single.company?.name, 'ايرث لنك ١');
      expect(rows.days[1].rows.single.trailing, '512');
      await t.enterText(find.byType(TextField), 'تجربة');
      await settleAsync(t, 3);
      await tapExport(t, 'Excel');
      final r = got.single;
      expect(r.rows.length, 2, reason: 'تجربة ١ وتجربة ٢ — البحث يحصر');
      expect(r.columns, ['الشركة', 'الاسم', 'اسم المستخدم', 'التاريخ', 'الاستهلاك']);
      expect(r.details, contains('البحث: «تجربة»'));
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  // ═══════════════════════════════ الصور (320) ═══════════════════════════════

  for (final (id, merged, screen) in [
    ('pkg_merged_320', true, const ElByPackageV2Screen() as Widget),
    ('test_merged_320', true, const ElTestUsageV2Screen() as Widget),
    ('pkg_single_320', false, const ElByPackageV2Screen() as Widget),
  ]) {
    testWidgets('صورة $id: لا نصّ مقصوص', (t) async {
      await up(t, merged: merged);
      try {
        await open(t, screen, size: const Size(320, 2200));
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
        Directory('build/report_design').createSync(recursive: true);
        File('build/report_design/el_$id.png').writeAsBytesSync(png!, flush: true);
        expect(cut, isEmpty, reason: 'نصٌّ مقصوص: $cut');
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });
  }
}
