import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/balance_reports_api.dart';
import 'package:rad_mysvcs/screens/reports/balance_period_screen.dart';
import 'package:rad_mysvcs/screens/reports/balance_reports_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'balance_reports/contract_server.dart';
import 'employee_ledger/ledger_fixture.dart' show LedgerDiskLoader;
import 'support/app_fonts.dart';

/// «الفائدة» على شحن المدراء الآجل في «تقارير الأرصدة» (٢٠ نوفمبر ٢٠٢٦) على **ردّ الخادم الحقيقيّ**:
/// `server_contract_fees.json` ولّده الخادم الحيّ (server/balanceReports.js + managerTopupFees.js على MySQL مؤقّتة، بلا بيانات إنتاج —
/// gen_fee_contract.js): فترةٌ بمليون، شحنٌ نقديّ ٥٠ ألفاً وآجلٌ ١٠٠ ألف لـmgr.north بفائدة ٢٪ (٢٬٠٠٠) سُدّد منها ١٬٠٠٠، وآجلٌ ٢٥ ألفاً
/// لـmgr.south بفائدةٍ ثابتة ٥٠٠ لم تُسدَّد. الموقع يُفحص على الملفّ نفسه.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final raw = jsonDecode(File('test/balance_reports/server_contract_fees.json').readAsStringSync()) as Map<String, dynamic>;
  final ov = (raw['overview'] as Map)['data'] as Map<String, dynamic>;
  final pid = ((ov['periods'] as List).first as Map)['id'] as int;
  final contract = <String, dynamic>{
    'me_manager': raw['me'],
    'overview': raw['overview'],
    'details': {'$pid': raw['detail_all']},
  };
  final items = ((((raw['detail_managers'] as Map)['data'] as Map)['movements'] as Map)['items'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> row(String key) => items.firstWhere((x) => x['key'] == key);
  BalanceMgrMove mv(String key) => BalanceMove.fromJson(row(key))! as BalanceMgrMove;

  test('الفترة: managers.fees بقارئه، والباقي على المدراء يحمل باقي الفوائد — والأرقام محسوبةٌ باليد', () {
    final j = ((ov['periods'] as List).first as Map)['managers'] as Map;
    expect(j.keys.toSet(), {'cash', 'withdrawn', 'loans', 'paid_in', 'open', 'late', 'count', 'fees'}, reason: 'مفتاحٌ جديد من الخادم بلا قرار');
    final p = BalanceOverview.fromJson(ov)!.periods.single;
    final m = p.managers!;
    // آجلان 100,000 + 25,000 · فائدتان 2,000 + 500 سُدّد من الأولى 1,000 ⇒ الباقي 125,000 + 1,000 + 500
    expect([m.cash, m.loans, m.fees, m.paidIn, m.open, m.withdrawn, m.count], [50000, 125000, 2500, 1000, 126500, 0, 6]);
    expect(p.debtsCreated, 127500, reason: 'ديون الفترة = الآجلان + الفائدتان');
    expect(p.collected, 51000, reason: 'النقديّ + تسديد الفائدة');
    // ردٌّ قديم بلا fees (الخادم يرسله حين يوجد وحده) ⇒ 0 لا خطأ
    expect(BalanceManagers.fromJson({...j}..remove('fees'))!.fees, 0);
  });

  test('حركة الفائدة: كلّ مفتاحٍ بقارئه، مواصفتها، وحال دينها', () {
    const moveKeys = {
      'key', 'kind', 'op', 'at_ms', 'sub', 'username', 'amount', 'remaining', 'debt_state', 'turned', 'paid_in', 'paid_late', //
      'last_paid_at_ms', 'after_close', 'by', 'note', 'fee',
    };
    final fees = items.where((x) => x['op'] == 'fee').toList();
    expect(fees.length, 2);
    for (final j in fees) {
      expect(j.keys.toSet(), moveKeys, reason: 'مفتاح حركة فائدةٍ جديد من الخادم');
      expect((j['fee'] as Map).keys.toSet(), {'kind', 'value', 'base'});
    }
    expect(items.where((x) => x['op'] != 'fee').every((x) => !x.containsKey('fee')), isTrue, reason: 'غير الفائدة بلا مواصفتها');
    final f1 = mv('f1');
    final f2 = mv('f2');
    expect([f1.op, f1.username, f1.amount, f1.remaining, f1.paidIn, f1.debtState, f1.by], [BalanceMgrOp.fee, 'mgr.north', 2000, 1000, 1000, BalanceDebtState.partly, 'admin@x']);
    expect([f1.fee!.percent, f1.fee!.value, f1.fee!.base], [true, 2, 100000]);
    expect([f2.fee!.percent, f2.fee!.value, f2.fee!.base, f2.debtState, f2.remaining], [false, 500, 25000, BalanceDebtState.open, 500]);
    expect(balanceMgrFeeDetail(f1), '2% على 100,000');
    expect(balanceMgrFeeDetail(f2), 'مبلغ ثابت على 25,000');
    expect(balanceMgrFeeDetail(mv('m2')), isNull, reason: 'الآجل نفسه بلا تفاصيل فائدة');
    expect(balanceMgrDebtNote(f1)?.text, 'تسدّد منه 1,000 · باقي 1,000');
    expect(balanceMgrDebtNote(f2)?.text, 'دين باقي 500');
    expect(balanceMgrDebtNote(mv('m1')), isNull, reason: 'النقديّ بلا علامة دين');
    expect(BalanceMgrOp.values.where((o) => o.debtLike).toSet(), {BalanceMgrOp.loan, BalanceMgrOp.fee});
    // نسبةٌ بكسر، ومواصفةٌ لا نعرفها: الحركة تبقى (لا تسقط) بلا تفاصيلها
    expect(balanceMgrFeeDetail(BalanceMove.fromJson({...row('f1'), 'fee': {'kind': 'percent', 'value': 2.5, 'base': 80000}})! as BalanceMgrMove),
        '2.5% على 80,000');
    final bare = BalanceMove.fromJson({...row('f1'), 'fee': {'kind': 'bonus'}})! as BalanceMgrMove;
    expect([bare.op, bare.fee, balanceMgrFeeDetail(bare)], [BalanceMgrOp.fee, null, null]);
  });

  group('الشاشة تعرض الردّ الحقيقيّ', () {
    // الخطّ الحقيقيّ: «هل يتّسع؟» بلا قياسٍ بالخطّ الاحتياطيّ (كلّ محرفٍ بعرض المقاس)
    setUpAll(loadAppFonts);
    late BalanceContractServer server;
    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      PermissionsService.debugReset();
      PermissionsService.debugSet(isEmployee: false);
      BalanceReportsState.reset();
      server = BalanceContractServer(contract);
      ApiClient.dio.httpClientAdapter = server;
    });
    tearDown(PermissionsService.debugReset);

    Widget app(Widget child, {double textScale = 1}) => EasyLocalization(
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
              builder: (ctx, w) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)), child: w!),
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

    Future<void> end(WidgetTester t) async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 4));
    }

    testWidgets('التفاصيل: سطر «منها فوائد الشحن الآجل»، الباقي على المدراء، وحركتا الفائدة بعلامتيهما وتفاصيلهما', (t) async {
      t.view.physicalSize = const Size(400, 4200);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(const BalanceReportsScreen()));
      await settle(t);
      expect(t.takeException(), isNull);
      await tap(t, k('bal-detail-$pid'));
      expect(t.takeException(), isNull);
      expect(inKey('bal-sum-mgr-loans', '125,000 د.ع'), findsOneWidget);
      expect(inKey('bal-sum-mgr-fees', '2,500 د.ع'), findsOneWidget);
      expect(inKey('bal-sum-mgr-fees', 'منها فوائد الشحن الآجل'), findsOneWidget);
      expect(inKey('bal-sum-mgr-open', '126,500 د.ع'), findsOneWidget);
      expect(inKey('bal-summary', 'الباقي منها بذمّة المشتركين والمدراء'), findsOneWidget);
      await tap(t, k('bal-filter-managers'));
      expect(server.filters.last, 'managers');
      final rows = t.widgetList<BalanceMoveRow>(find.byType(BalanceMoveRow)).map((r) => r.move).cast<BalanceMgrMove>().toList();
      expect(rows.map((m) => m.op.name).toList(), ['loan', 'loan', 'cash', 'pay', 'fee', 'fee']);
      expect(find.text('فائدة شحن آجل'), findsNWidgets(2));
      expect(find.textContaining('2% على 100,000'), findsOneWidget);
      expect(find.textContaining('مبلغ ثابت على 25,000'), findsOneWidget);
      final statuses = t.widgetList<BalanceMoveStatus>(k('bal-move-status')).map((c) => c.text).toList();
      expect(statuses.sublist(4), ['دين باقي 500', 'تسدّد منه 1,000 · باقي 1,000']);
      // الفائدة دينٌ بلا إشارة (كالآجل) — لا «+2,000» كنقدٍ دخل
      expect(find.text(balanceIqd(2000)), findsWidgets);
      expect(find.text(balanceSigned(2000, sign: '+')), findsNothing);
      await end(t);
    });

    testWidgets('بأضيق هاتف وخطٍّ ×1.2: الخلاصة وحركات الفائدة بلا فيض ولا نصٍّ مقصوص، وعلاماتها داخل كرتها', (t) async {
      for (final width in [320.0, 390.0, 480.0]) {
        t.view.physicalSize = Size(width, 5200);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(app(const BalanceReportsScreen(), textScale: 1.2));
        await settle(t);
        await tap(t, k('bal-detail-$pid'));
        expect(t.takeException(), isNull, reason: 'التفاصيل @$width');
        await tap(t, k('bal-filter-managers'));
        expect(t.takeException(), isNull, reason: 'حركات المدراء @$width');
        final card = t.getRect(k('bal-moves'));
        for (final e in find.byKey(const ValueKey('bal-move-status')).evaluate()) {
          final box = e.renderObject! as RenderBox;
          final r = box.localToGlobal(Offset.zero) & box.size;
          expect(r.left >= card.left && r.right <= card.right, isTrue, reason: 'علامةٌ خارج الكرت @$width');
        }
        final cut = <String>[];
        for (final e in find.descendant(of: k('bal-moves'), matching: find.byType(RichText)).evaluate()) {
          final p = e.renderObject! as RenderParagraph;
          if (p.didExceedMaxLines) cut.add(p.text.toPlainText());
        }
        expect(cut, isEmpty, reason: 'نصٌّ مقصوص في الحركات @$width');
        await end(t);
      }
    });
  });
}
