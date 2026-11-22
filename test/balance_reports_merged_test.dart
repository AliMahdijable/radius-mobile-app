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
import 'package:rad_mysvcs/api/balance_reports_api.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/screens/reports/balance_reports_screen.dart';
import 'package:rad_mysvcs/screens/reports/reports_hub_screen.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/widgets/merged_section.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «تقارير الأرصدة» في «كل الشركات» بالتطبيق (١٦ نوفمبر — المالك: «اي ضيفها بالتطبيق وابنيلي نسخة فحص»؛ الخادم c41c8de):
///   ١. «الكل» = المفتوحة كما كانت: طلباتها بلا مفتاح، وأزرار الكتابة كلّها.
///   ٢. شركةٌ غير المفتوحة والخادم لم يفتح كتابتها (routed_writes:false): كلّ طلبٍ بمفتاحها، للعرض وحده — لا زرّ كتابة.
///   ٣. فتحها الخادم: «شحن جديد» ⇒ الشيت يسمّيها ⇒ الحفظ بمفتاحها؛ والتفاصيل (شاشةٌ مدفوعة بلا الشريط) بمفتاحها واسمها.
///   ٤. المشروع الوطنيّ: «من صفحتها» بلا أيّ طلب.
///   ٥. «التقارير» في «كل الشركات»: الكرت ظاهرٌ ويفتح القسم بغلافه.
/// ردود الخادم من عقده الحقيقيّ (balance_reports/server_contract.json).
const _kOpen = 'c0000000000a1';
const _kEl = 'c0000000000e1';
const _kFt = 'c0000000000f1';

final Map<String, dynamic> _contract =
    jsonDecode(File('test/balance_reports/server_contract.json').readAsStringSync()) as Map<String, dynamic>;

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

class _Srv implements HttpClientAdapter {
  final asked = <String>[];
  final posted = <(String, String?, Map<String, dynamic>)>[];
  bool elWrites = false;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    asked.add('${o.method} $path ${key ?? '-'}');
    final h = key == null ? const <String, List<String>>{} : {'x-company-key': [key]};
    if (path == '/api/v2/balance-reports/me') {
      return _json(200, {
        'success': true,
        'data': {'feature_enabled': true, 'can_manage': true, 'is_employee': false, if (key != null) 'routed_writes': key == _kEl && elWrites},
      }, headers: h);
    }
    if (path == '/api/v2/balance-reports' && o.method == 'GET') return _json(200, _contract['overview'] as Object, headers: h);
    final m = RegExp(r'^/api/v2/balance-reports/periods/(\d+)$').firstMatch(path);
    if (m != null && o.method == 'GET') {
      final d = (_contract['details'] as Map<String, dynamic>)[m.group(1)];
      return _json(200, d as Object, headers: h);
    }
    if (path == '/api/v2/balance-reports/periods' && o.method == 'POST') {
      posted.add((path, key, Map<String, dynamic>.from(o.data as Map)));
      return _json(200, {'success': true, 'result': {'id': 4}, 'data': (_contract['overview'] as Map)['data']}, headers: h);
    }
    if (path == '/api/v2/admin-widgets') return _json(200, {'success': true, 'balance': 123000}, headers: h);
    return _json(200, {'success': true, 'data': []}, headers: h);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _companies() => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kOpen, 'code': 'supernet', 'username': 'u0', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': 'supernet:12', 'ns': 'a', 'currency': 'IQD', 'color_index': 0},
        {'key': _kEl, 'code': 'earthlink', 'provider': 'earthlink', 'username': 'u1', 'name': 'ايرث لنك', 'status': 'ok', 'admin_id': 'earthlink:77', 'ns': 'e', 'currency': 'IQD', 'color_index': 3},
        {'key': _kFt, 'code': 'ftth', 'provider': 'ftth', 'username': 'u2', 'name': 'المشروع الوطني', 'status': 'ok', 'admin_id': 'ftth:5', 'ns': 'f', 'currency': 'IQD', 'color_index': 5},
      ],
    };

void main() {
  setUpAll(visualSetUpAll);
  late _Srv srv;

  Future<void> up(WidgetTester t) async {
    await visualSetUp(s1bSasOwner);
    srv = _Srv();
    ApiClient.dio.httpClientAdapter = srv;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    MergedMode.reset();
    BalanceReportsState.reset();
    MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
    expect(await t.runAsync(() => MergedMode.enter()), isTrue);
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
    MergedMode.reset();
    BalanceReportsState.reset();
    await visualTearDown();
  }

  Future<void> settleReal(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Iterable<String> balanceCalls() => srv.asked.where((a) => a.contains('/api/v2/balance-reports') || a.contains('/api/v2/admin-widgets'));

  testWidgets('١–٢ «الكل» = المفتوحة بأزرارها؛ ايرث لنك بمفتاحها وللعرض وحده حتى يفتح الخادم كتابتها', (t) async {
    await up(t);
    await pumpVisual(t, const VisualDevice('', Size(390, 1600), 1), home: (_) => BalanceReportsScreen.mergedPage());
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(balanceCalls(), isNotEmpty);
    // «الكل»: تفاصيل المفتوحة كما كانت بلا توجيه؛ وجدول «حسب الشركة» فوقها (٢٢ نوفمبر — بند المقترح) يقرأ لوحة كلّ شركةٍ بمفتاحها
    // قراءةً وحدها — لا /me ولا كتابة، والمشروع الوطنيّ لا يُطلب
    expect(balanceCalls().where((a) => a.endsWith(' -')), contains('GET /api/v2/balance-reports -'), reason: '${balanceCalls()}');
    expect(balanceCalls().where((a) => !a.endsWith(' -')).toSet(), {'GET /api/v2/balance-reports $_kOpen', 'GET /api/v2/balance-reports $_kEl'},
        reason: '${balanceCalls()}');
    expect(balanceCalls().where((a) => a.contains('/me')), isEmpty, reason: 'المفتوحة لا تسأل routed_writes');
    final table = t.widget<RpCompanyTable>(find.byType(RpCompanyTable));
    expect([for (final l in table.lines) (l.company.key, l.state)], [(_kOpen, RpCompanyState.ok), (_kEl, RpCompanyState.ok)]);
    final cur = BalanceOverview.fromJson((_contract['overview'] as Map)['data'])!.periods.first;
    expect([table.lines.first.a, table.lines.first.b, table.lines.first.c],
        [cur.collected, cur.amountPending ? null : cur.remaining, cur.amountPending ? null : cur.profit], reason: 'أرقام الفترة الجارية كما يحسبها الخادم');
    expect(table.total.first, cur.collected * 2);
    expect(find.text('تفاصيل «سوبرنت» — المفتوحة'), findsOneWidget);
    expect(find.byKey(const ValueKey('bal-new')), findsOneWidget);
    expect(find.byKey(const ValueKey('bal-edit-3')), findsOneWidget);
    expect(find.text('تسوية الرصيد'), findsWidgets);
    expect(find.byKey(const ValueKey('bal-routed-readonly')), findsNothing);

    // ايرث لنك: موجَّهة، ومقفلة (routed_writes:false)
    srv.asked.clear();
    MergedMode.focus.value = _kEl;
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(balanceCalls(), contains('GET /api/v2/balance-reports/me $_kEl'));
    expect(balanceCalls(), contains('GET /api/v2/balance-reports $_kEl'));
    expect(balanceCalls(), contains('GET /api/v2/admin-widgets $_kEl'), reason: 'رصيد شركتها لا المفتوحة');
    expect(balanceCalls().every((a) => a.endsWith(_kEl)), isTrue, reason: '${balanceCalls()}');
    expect(find.byKey(const ValueKey('bal-routed-readonly')), findsOneWidget);
    for (final k in ['bal-new', 'bal-edit-3', 'bal-delete-3', 'bal-adjust-3', 'bal-adjust-2', 'bal-reopen-1']) {
      expect(find.byKey(ValueKey(k)), findsNothing, reason: '$k: لا كتابة لشركةٍ لم يفتح الخادم كتابتها');
    }
    expect(find.byKey(const ValueKey('bal-detail-3')), findsOneWidget, reason: 'التفاصيل تبقى');
    // التفاصيل: شاشةٌ مدفوعة فوق القسم — حركاتها بمفتاح شركتها، واسمها تحت العنوان، ولا أزرار
    srv.asked.clear();
    await t.tap(find.byKey(const ValueKey('bal-detail-3')));
    await settleReal(t);
    expect(balanceCalls().where((a) => a.contains('/periods/3')), isNotEmpty);
    expect(balanceCalls().every((a) => a.endsWith(_kEl)), isTrue, reason: '${balanceCalls()}');
    expect(find.textContaining('«ايرث لنك» · للعرض هنا'), findsOneWidget);
    expect(find.text('تسوية الرصيد'), findsNothing);
    expect(t.takeException(), isNull);
    await down(t);
  });

  testWidgets('٣ الخادم يفتح كتابتها: «شحن جديد» يسمّيها، والحفظ بمفتاحها وحده', (t) async {
    await up(t);
    srv.elWrites = true;
    MergedMode.focus.value = _kEl;
    await pumpVisual(t, const VisualDevice('', Size(390, 1600), 1), home: (_) => BalanceReportsScreen.mergedPage());
    await settleReal(t);
    expect(find.byKey(const ValueKey('bal-routed-readonly')), findsNothing);
    expect(find.byKey(const ValueKey('bal-edit-3')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('bal-new')));
    await settleReal(t);
    expect(find.text('شحن رصيد جديد'), findsOneWidget);
    final sub = find.textContaining('في «ايرث لنك»');
    expect(sub, findsOneWidget, reason: 'الشيت يسمّي شركته قبل الحفظ');
    expect(t.renderObject<RenderParagraph>(sub).didExceedMaxLines, isFalse, reason: 'اسم الشركة لا يُقصّ');
    await t.enterText(find.byKey(const ValueKey('bal-topup-amount')), '250000');
    await settleReal(t);
    await t.tap(find.byKey(const ValueKey('bal-topup-save')));
    await settleReal(t);
    expect(srv.posted, hasLength(1));
    expect(srv.posted.single.$2, _kEl, reason: 'الحفظ لشركة الشريط لحظة فتح الشيت');
    expect(srv.posted.single.$3['amount'], 250000);
    expect(srv.asked.where((a) => a.startsWith('POST')).every((a) => a.endsWith(_kEl)), isTrue, reason: '${srv.asked}');
    expect(t.takeException(), isNull);
    await down(t);
  });

  testWidgets('٤ المشروع الوطنيّ (من الموقع وحده في التطبيق): لا يُطلب القسم بمفتاحه أبداً', (t) async {
    await up(t);
    MergedMode.focus.value = _kFt;
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1), home: (_) => BalanceReportsScreen.mergedPage());
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(srv.asked.where((a) => a.endsWith(_kFt)), isEmpty, reason: '${srv.asked}');
    await down(t);
  });

  testWidgets('٥ «التقارير» في «كل الشركات»: الكرت ظاهرٌ بعلامة الدمج ويفتح القسم بغلافه', (t) async {
    await up(t);
    await pumpVisual(t, const VisualDevice('', Size(390, 2400), 1), home: (_) => const ReportsHubScreen());
    await settleReal(t);
    final card = find.byKey(const ValueKey('report-balances'));
    expect(card, findsOneWidget);
    await t.ensureVisible(card);
    await t.tap(card);
    await settleReal(t);
    expect(find.byType(MergedSection), findsOneWidget, reason: 'القسم بغلافه (الشريط ومفتاح الشركة)');
    expect(find.byType(BalanceReportsScreen), findsOneWidget);
    expect(t.takeException(), isNull);
    expect(CompanyRoute.sectionKey, isNull, reason: '«الكل» لا وجهة');
    await down(t);
  });

  testWidgets('٦ «الكل» على 320: جدول «حسب الشركة» وتفاصيل المفتوحة بلا نصٍّ مقصوص', (t) async {
    await up(t);
    const d = VisualDevice('', Size(320, 2000), 2);
    await pumpVisual(t, d, home: (_) => BalanceReportsScreen.mergedPage());
    await settleReal(t);
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
    File('build/report_design/bal_merged_320.png').writeAsBytesSync(png!, flush: true);
    expect(cut, isEmpty, reason: 'نصٌّ مقصوص: $cut');
    expect(t.takeException(), isNull);
    await down(t);
  });
}
