import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/balance_reports_api.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/screens/reports/balance_period_screen.dart';
import 'package:rad_mysvcs/screens/reports/balance_reports_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'balance_reports/balance_fixture.dart';
import 'balance_reports/contract_server.dart';
import 'employee_ledger/ledger_fixture.dart' show LedgerDiskLoader;

/// «تقارير الأرصدة» — «الفترة التالية تُفتح عند الإغلاق» (المالك ١٦ نوفمبر مساءً: «من يسوي غلق فترة تنفتح فترة بدون سعر مفتوحة…
/// وعليها تنبيه انه سعر هاي الفترة. بحيث اي تفعيل ثاني… لازم يصير على هاي الفترة الجديدة. بمجرد ما الفترة الجديدة صار بها حركة
/// حركتين، الفترة القديمة… تنقفل نهائيا»).
///
/// - النماذج تقرأ ردّ الخادم الحقيقيّ والمفتاح مفتوح (`balance_reports/server_contract_next.json` — ولّده كود الخادم الحيّ نفسه:
///   `gen_contract.js <شجرة الخادم> next`): `auto_next`، `amount_pending`، `reopen_locked`، وردود الرفض بنصوصها.
/// - الشاشتان تعرضان الفترة بلا مبلغ: «فترة جديدة · بلا مبلغ»، التنبيه، «لم يُكتب بعد»، المتبقّي والربح «—» (لا صفر)، وزرّ الشاشة
///   «كتابة مبلغ الشحن» بدل «شحن جديد» — مرّةً واحدة.
/// - الدورة على خادمٍ وهميّ بالقاعدة نفسها: الإغلاق يقول ما سيحدث ثمّ يفتح الفترة، كتابة مبلغها بورقةٍ بلا تاريخ، إلغاء الإغلاق
///   (رجوعٌ كامل والجديدة فارغة · مقفلٌ بسببه حين فيها حركة · رفض الخادم يُحدّث اللوحة)، والمطفأ كما كان.
void main() {
  final contract = jsonDecode(File('test/balance_reports/server_contract_next.json').readAsStringSync()) as Map<String, dynamic>;
  final plain = jsonDecode(File('test/balance_reports/server_contract.json').readAsStringSync()) as Map<String, dynamic>;
  Map<String, dynamic> data(String key) => (contract[key] as Map)['data'] as Map<String, dynamic>;
  final ids = (contract['ids'] as Map).cast<String, dynamic>();
  final int p1 = ids['p1'] as int, p2 = ids['p2'] as int, p3 = ids['p3'] as int;

  late BalanceServer server;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    PermissionsService.debugReset();
    BalanceReportsState.reset();
  });

  tearDown(() {
    PermissionsService.debugReset();
    BalanceReportsState.reset();
  });

  void use(BalanceServer s) {
    server = s;
    ApiClient.dio.httpClientAdapter = s;
  }

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

  Future<void> settle(WidgetTester t, {int frames = 20}) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> done(WidgetTester t) async {
    await t.pump(const Duration(seconds: 4));
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 1));
  }

  Future<void> open(WidgetTester t, {double width = 400, double textScale = 1}) async {
    t.view.physicalSize = Size(width, 2600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(app(const BalanceReportsScreen(), textScale: textScale));
    await settle(t);
  }

  Finder k(String key) => find.byKey(ValueKey(key));
  Finder inKey(String key, String text) => find.descendant(of: k(key), matching: find.text(text));
  Finder field(String key) => find.descendant(of: k(key), matching: find.byType(TextField));
  Future<void> tap(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pump();
    await t.tap(f);
    await settle(t);
  }

  /// رجوعٌ من شاشة تفاصيل الفترة (زرّ الرجوع معرَّب فلا يجده pageBack).
  Future<void> back(WidgetTester t) async {
    Navigator.of(t.element(find.byType(BalancePeriodScreen))).pop();
    await settle(t);
  }

  group('النماذج تقرأ ردّ الخادم الحقيقيّ والمفتاح مفتوح', () {
    test('اللوحة: auto_next، آخر فترةٍ بلا مبلغ بمحصَّلها الحقيقيّ، والمغلقتان مقفلتان — والمفاتيح الجديدة وحدها زادت', () {
      final j = data('overview');
      final o = BalanceOverview.fromJson(j)!;
      expect(o.autoNext, isTrue);
      expect(o.periods.map((p) => [p.id, p.state, p.amountPending, p.reopenLocked]).toList(), [
        [p3, BalanceState.running, true, false],
        [p2, BalanceState.closed, false, true],
        [p1, BalanceState.closed, false, true],
      ]);
      final pend = o.periods.first;
      expect([pend.amount, pend.collected, pend.debtsOpen, pend.remaining, pend.net, pend.profit, pend.canClose, pend.progress], [0, 95000, 90000, 0, 0, 0, false, 0],
          reason: 'المحصَّل والديون حقيقيّة؛ المتبقّي والصافي والربح أصفارٌ معلَّمة بـamount_pending');
      expect(o.waitingAmount, same(pend));
      // «فُتحت بإغلاقها»: تبدأ من لحظة إغلاق سابقتها نفسها
      expect([o.openedAfter(o.periods[1])?.id, o.openedAfter(o.periods[2])?.id, o.openedAfter(pend)], [p3, p2, isNull]);
      expect([o.openedByClose(pend), o.openedByClose(o.periods[1]), o.openedByClose(o.periods[2])], [true, true, false]);
      expect([o.pinned(pend), o.pinned(o.periods[1]), o.pinned(o.periods[2])], [true, true, false]);
      expect([pend.startedAtMs, o.periods[1].startedAtMs], [o.periods[1].closedAtMs, o.periods[2].closedAtMs]);
      // مفاتيح الخادم: كما في العقد المطفأ + الثلاثة الجديدة وحدها
      final plainOverview = (plain['overview'] as Map)['data'] as Map;
      final plainPeriod = ((plainOverview['periods'] as List).first as Map).keys.toSet();
      expect(j.keys.toSet().difference(plainOverview.keys.toSet()), {'auto_next'});
      for (final p in (j['periods'] as List).cast<Map>()) {
        expect(p.keys.toSet().difference(plainPeriod), p['amount_pending'] == true ? {'amount_pending'} : {'reopen_locked'}, reason: 'الفترة ${p['id']}');
        expect(plainPeriod.difference(p.keys.toSet()), isEmpty, reason: 'لا مفتاح قديم غاب');
      }
      // والمفتاح مطفأ (العقد الأوّل): لا شيء من هذا
      final off = BalanceOverview.fromJson(plainOverview)!;
      expect([off.autoNext, off.waitingAmount, off.periods.any((p) => p.amountPending || p.reopenLocked), off.periods.any(off.pinned)], [false, isNull, false, false]);
    });

    test('العنوان والتنبيه: «فترة جديدة» وتنبيه المبلغ — لا «اكتمل» ولا «نفد رصيدك» على فترةٍ بلا مبلغ', () {
      final o = BalanceOverview.fromJson(data('overview'))!;
      final pend = o.periods.first;
      expect(balancePeriodTitle(pend), 'فترة جديدة');
      expect(balancePeriodTitle(o.periods[1]), startsWith('شحن '));
      for (final live in <num?>[null, 0, 5000, 900000000]) {
        final b = balanceBanner(pend, live)!;
        expect([b.kind, b.text], [BalanceBannerKind.amount, 'هذه الفترة بلا مبلغ شحن — اكتب مبلغها ليظهر المتبقّي والربح'], reason: 'الرصيد $live');
      }
      expect(balanceBanner(o.periods[1], 0), isNull, reason: 'المغلقة بلا تنبيه');
    });

    test('ردود الكتابة والرفض: next_id و removed_id، والرفض برمزه ونصّه العربيّ', () {
      final close = contract['close_reply'] as Map;
      expect((close['result'] as Map)['next_id'], ids['removed']);
      final afterClose = BalanceOverview.fromJson(close['data'])!;
      expect([afterClose.periods.first.amountPending, afterClose.periods.first.collected, afterClose.periods.last.reopenLocked], [true, 0, false], reason: 'فارغةٌ لتوّها: القديمة غير مقفلة');
      final reopen = contract['reopen_empty_reply'] as Map;
      expect(reopen['result'], {'id': p1, 'closed': false, 'removed_id': ids['removed']});
      expect(BalanceOverview.fromJson(reopen['data'])!.periods.map((p) => [p.id, p.state]).toList(), [
        [p1, BalanceState.running]
      ]);
      final amount = BalanceOverview.fromJson((contract['amount_reply'] as Map)['data'])!;
      expect([amount.periods.first.amountPending, amount.periods.first.amount, amount.periods.first.remaining, amount.waitingAmount], [false, 200000, 115000, isNull]);
      for (final e in {
        'pending_create_error': 'AMOUNT_PENDING',
        'pending_close_error': 'AMOUNT_PENDING',
        'pending_adjust_error': 'AMOUNT_PENDING',
        'auto_delete_error': 'AUTO_PERIOD',
        'start_pinned_error': 'START_PINNED',
        'reopen_locked_error': 'REOPEN_LOCKED',
      }.entries) {
        final r = contract[e.key] as Map;
        final body = r['body'] as Map;
        expect([r['status'], body['success'], body['code']], [409, false, e.value], reason: e.key);
        expect(RegExp(r'[؀-ۿ]').hasMatch('${body['message']}'), isTrue, reason: e.key);
        expect(balanceStaleCodes.contains(body['code']), isTrue, reason: 'رفضٌ معناه أنّ الشاشة قديمة ⇒ تُقرأ اللوحة');
      }
      expect(((contract['pending_create_error'] as Map)['body'] as Map)['period_id'], p2);
    });
  });

  group('الشاشتان على ردّ الخادم الحقيقيّ', () {
    testWidgets('آخر فترةٍ بلا مبلغ: «فترة جديدة · جارية · بلا مبلغ»، التنبيه، «لم يُكتب بعد»، المتبقّي والربح «—»، وزرّ الشاشة «كتابة مبلغ الشحن» مرّةً واحدة', (t) async {
      ApiClient.dio.httpClientAdapter = BalanceContractServer(contract);
      await open(t);
      expect(inKey('bal-hero', 'فترة جديدة'), findsOneWidget);
      expect(t.widget<ToneChip>(k('bal-state')).label, 'جارية');
      expect(t.widget<ToneChip>(k('bal-no-amount')).label, 'بلا مبلغ');
      expect(t.widget<Text>(k('bal-amount')).data, 'لم يُكتب بعد', reason: 'لا «0 د.ع»');
      expect(k('bal-percent'), findsNothing);
      expect(find.descendant(of: k('bal-hero'), matching: find.byType(BalanceProgress)), findsNothing, reason: 'لا شريط بلا مبلغ يُقاس عليه');
      expect(inKey('bal-banner', 'هذه الفترة بلا مبلغ شحن — اكتب مبلغها ليظهر المتبقّي والربح'), findsOneWidget);
      expect(inKey('bal-stat-collected', '95,000 د.ع'), findsOneWidget);
      expect(inKey('bal-stat-debts', '90,000 د.ع'), findsOneWidget);
      expect([inKey('bal-stat-remaining', '—'), inKey('bal-stat-remaining', 'يظهر بعد كتابة مبلغ الشحن')].every((f) => f.evaluate().length == 1), isTrue);
      expect([inKey('bal-stat-profit', '—'), inKey('bal-stat-profit', 'يُحسب بعد كتابة مبلغ الشحن')].every((f) => f.evaluate().length == 1), isTrue);
      expect(find.textContaining('نفد رصيدك'), findsNothing);
      expect(find.textContaining('اكتمل مبلغ الشحن'), findsNothing);
      // زرّ الشاشة: «كتابة مبلغ الشحن» بدل «شحن جديد» — والكرت بلا نسخةٍ ثانية منه، وبلا حذف (فُتحت بالإغلاق)
      expect(k('bal-amount-btn'), findsOneWidget);
      expect(k('bal-new'), findsNothing);
      expect(find.text('كتابة مبلغ الشحن'), findsOneWidget);
      expect([k('bal-amount-$p3'), k('bal-close-$p3'), k('bal-adjust-$p3'), k('bal-delete-$p3')].every((f) => f.evaluate().isEmpty), isTrue);
      expect(t.widget<IconButton>(k('bal-edit-$p3')).tooltip, 'كتابة مبلغ الشحن');
      // المغلقتان في «الفترات السابقة»: صافٍ سالب بناقصه قبل الرقم (معزولٌ LTR)
      final net = t.widget<Text>(find.descendant(of: k('bal-period-$p2'), matching: find.textContaining('40,000')));
      expect(net.data, '\u2066−40,000\u2069');
      expect(t.takeException(), isNull);
      await done(t);
    });

    testWidgets('تفاصيل الفترة بلا مبلغ: التنبيه فوق الخلاصة، «لم يُكتب بعد» و«—»، وزرّ «كتابة مبلغ الشحن»؛ والمغلقة مقفلةٌ بسببها بلا «إلغاء الإغلاق»', (t) async {
      ApiClient.dio.httpClientAdapter = BalanceContractServer(contract);
      await open(t);
      await tap(t, k('bal-detail-$p3'));
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('فترة جديدة')), findsOneWidget);
      expect(inKey('bal-banner', 'هذه الفترة بلا مبلغ شحن — اكتب مبلغها ليظهر المتبقّي والربح'), findsOneWidget);
      expect(inKey('bal-sum-amount', 'لم يُكتب بعد'), findsOneWidget);
      expect(inKey('bal-sum-collected', '95,000 د.ع'), findsOneWidget);
      expect(inKey('bal-sum-remaining', '—'), findsOneWidget);
      expect(inKey('bal-sum-net', 'الصافي (يُحسب بعد كتابة مبلغ الشحن)'), findsOneWidget);
      expect(inKey('bal-sum-net', '—'), findsOneWidget);
      expect(find.textContaining('مكتمل'), findsNothing, reason: 'لا «مكتمل» على فترةٍ بلا مبلغ');
      expect(k('bal-amount-$p3'), findsOneWidget);
      expect([k('bal-close-$p3'), k('bal-adjust-$p3')].every((f) => f.evaluate().isEmpty), isTrue);
      final total = ((((contract['details'] as Map)['$p3'] as Map)['data'] as Map)['movements'] as Map)['total'] as int;
      expect(t.widget<SheetQuickChip>(k('bal-filter-all')).label, 'الكل $total');
      await back(t);
      // المغلقة الأولى: reopen_locked من الخادم
      await tap(t, k('bal-period-$p1'));
      expect(k('bal-reopen-$p1'), findsNothing);
      expect(inKey('bal-reopen-locked-$p1', 'إغلاق هذه الفترة نهائيّ — في الفترة التي بعدها حركات'), findsOneWidget);
      expect(inKey('bal-sum-late', '80,000 د.ع'), findsOneWidget, reason: 'تسديد ديونها بعد الإغلاق وحده — التفعيلات بعده ذهبت للفترة التالية');
      expect(t.takeException(), isNull);
      await done(t);
    });
  });

  group('الدورة', () {
    testWidgets('الإغلاق يقول قبل الضغط ما سيحدث ثمّ يفتح الفترة بلا مبلغ؛ وإلغاؤه والجديدة فارغة يقول إنّها تُحذف ويرجع كلّ شيء', (t) async {
      final s = BalanceServer.ownerExample()..autoNext = true;
      s.periods.first['amount'] = 1750000; // اكتمل
      use(s);
      await open(t);
      expect([k('bal-new'), k('bal-amount-btn')].map((f) => f.evaluate().length).toList(), [1, 0]);
      await tap(t, k('bal-close-1'));
      expect(find.textContaining('ينحسب ربح'), findsOneWidget);
      expect(find.textContaining('تُفتح بعدها فترة جديدة بلا مبلغ شحن، وكلّ تفعيلٍ بعد الإغلاق يُحسب عليها. إلغاء الإغلاق ممكن حتى أوّل حركة في الفترة الجديدة.'), findsOneWidget);
      await t.tap(find.text('إغلاق الفترة').last);
      await settle(t);
      expect(server.lastWrite('POST', RegExp(r'/periods/1/close$')), isNotNull);
      final next = server.periods.firstWhere((x) => x['id'] != 1);
      expect(next['started_at_ms'], server.periods.firstWhere((x) => x['id'] == 1)['closed_at_ms'], reason: 'تبدأ من لحظة الإغلاق نفسها');
      expect(find.text('أُغلقت الفترة وفُتحت فترة جديدة — اكتب مبلغ شحنها'), findsOneWidget);
      expect(inKey('bal-hero', 'فترة جديدة'), findsOneWidget);
      expect(t.widget<Text>(k('bal-amount')).data, 'لم يُكتب بعد');
      expect(inKey('bal-stat-collected', '0 د.ع'), findsOneWidget, reason: 'المحصَّل صفرٌ حقيقيّ');
      expect(inKey('bal-stat-remaining', '—'), findsOneWidget);
      expect([k('bal-new'), k('bal-amount-btn'), k('bal-delete-${next['id']}')].map((f) => f.evaluate().length).toList(), [0, 1, 0]);
      expect(inKey('bal-period-1', 'مغلقة'), findsOneWidget);
      // إلغاء الإغلاق من تفاصيل القديمة: الجديدة فارغة بلا مبلغ ⇒ تُحذف
      await tap(t, k('bal-period-1'));
      expect(k('bal-reopen-locked-1'), findsNothing);
      await tap(t, k('bal-reopen-1'));
      expect(find.textContaining('الفترة الجديدة التي فُتحت بعدها — بلا مبلغ ولا حركات — تُحذف، وترجع هذه آخر فترة.'), findsOneWidget);
      await t.tap(find.text('إلغاء الإغلاق').last);
      await settle(t);
      expect(server.lastWrite('POST', RegExp(r'/periods/1/reopen$')), isNotNull);
      expect(find.text('رجعت الفترة مفتوحة وحُذفت الفترة الجديدة الفارغة'), findsOneWidget);
      await back(t);
      expect(server.periods.length, 1);
      expect(t.widget<ToneChip>(k('bal-state')).label, 'جارية');
      expect(t.widget<Text>(k('bal-amount')).data, '1,750,000 د.ع');
      expect([k('bal-new'), k('bal-amount-btn')].map((f) => f.evaluate().length).toList(), [1, 0]);
      expect(server.listReads, 1, reason: 'كلّ كتابةٍ ردّت اللوحة — لا قراءة ثانية');
      await done(t);
    });

    testWidgets('كتابة مبلغ الفترة: ورقةٌ بلا تاريخٍ ولا وقت، الطلب بالمبلغ وحده، وبعده فترةٌ عاديّة — وتعديلها بلا تاريخ وبلا حذف', (t) async {
      use(BalanceServer.closedWithPending());
      await open(t);
      expect(inKey('bal-stat-collected', '445,000 د.ع'), findsOneWidget);
      expect(inKey('bal-stat-debts', '150,000 د.ع'), findsOneWidget);
      await tap(t, k('bal-amount-btn'));
      expect(find.text('مبلغ الشحن لهذه الفترة'), findsOneWidget);
      expect([k('bal-topup-date'), k('bal-topup-time')].every((f) => f.evaluate().isEmpty), isTrue);
      expect(t.widget<Text>(k('bal-topup-fixed')).data, matches(RegExp(r'^تبدأ هذه الفترة من لحظة إغلاق الفترة التي قبلها \(.+ · 14:00\) — تاريخها لا يتغيّر، وكلّ تفعيلٍ بعدها محسوبٌ عليها\.$')));
      expect(t.widget<TextField>(field('bal-topup-amount')).controller!.text, '', reason: 'لا «0» في الحقل');
      expect(find.text('اكتب مبلغ الشحن'), findsOneWidget);
      // الزرّ معطّل بلا مبلغ: الضغط لا يرسل
      await t.tap(k('bal-topup-save'));
      await settle(t, frames: 4);
      expect(server.writes, isEmpty);
      await t.enterText(field('bal-topup-amount'), '2000000');
      await settle(t, frames: 4);
      expect(find.text('حفظ المبلغ — 2,000,000 د.ع'), findsOneWidget);
      await t.tap(k('bal-topup-save'));
      await settle(t);
      final put = server.lastWrite('PUT', RegExp(r'/periods/2$'))!;
      expect([put.body['amount'], put.body.containsKey('started_at_ms')], [2000000, false]);
      expect(find.text('حُفظ مبلغ الشحن 2,000,000 د.ع'), findsOneWidget);
      // فترةٌ عاديّة الآن
      expect(find.descendant(of: k('bal-hero'), matching: find.textContaining('شحن ')), findsWidgets);
      expect(t.widget<Text>(k('bal-amount')).data, '2,000,000 د.ع');
      expect(inKey('bal-stat-remaining', '1,555,000 د.ع'), findsOneWidget);
      expect(t.widget<Text>(k('bal-percent')).data, '22%');
      expect([k('bal-no-amount'), k('bal-amount-btn'), k('bal-delete-2')].every((f) => f.evaluate().isEmpty), isTrue, reason: 'فُتحت بالإغلاق: لا زرّ حذف');
      expect([k('bal-new'), k('bal-adjust-2'), k('bal-edit-2')].every((f) => f.evaluate().length == 1), isTrue);
      // تعديلها: بلا تاريخ، والمبلغ بقيمته، والطلب بلا تاريخ
      await tap(t, k('bal-edit-2'));
      expect(find.text('تعديل الشحن'), findsOneWidget);
      expect([k('bal-topup-date'), k('bal-topup-time')].every((f) => f.evaluate().isEmpty), isTrue);
      expect(k('bal-topup-fixed'), findsOneWidget);
      expect(t.widget<TextField>(field('bal-topup-amount')).controller!.text, '2,000,000');
      await t.enterText(field('bal-topup-amount'), '2100000');
      await settle(t, frames: 4);
      await t.tap(k('bal-topup-save'));
      await settle(t);
      final put2 = server.lastWrite('PUT', RegExp(r'/periods/2$'))!;
      expect([put2.body['amount'], put2.body.containsKey('started_at_ms')], [2100000, false]);
      // والقديمة: في الجديدة حركات ⇒ مقفلة بسببها
      await tap(t, k('bal-period-1'));
      expect(k('bal-reopen-1'), findsNothing);
      expect(inKey('bal-reopen-locked-1', 'إغلاق هذه الفترة نهائيّ — في الفترة التي بعدها حركات'), findsOneWidget);
      expect(server.lastWrite('POST', RegExp(r'/reopen$')), isNull);
      await done(t);
    });

    testWidgets('كتابة المبلغ من تفاصيل الفترة: الزرّ تحت الخلاصة، وبعد الحفظ الخلاصة بأرقامها', (t) async {
      use(BalanceServer.closedWithPending());
      await open(t);
      await tap(t, k('bal-detail-2'));
      expect(inKey('bal-sum-amount', 'لم يُكتب بعد'), findsOneWidget);
      await tap(t, k('bal-amount-2'));
      expect(find.text('مبلغ الشحن لهذه الفترة'), findsOneWidget);
      await t.enterText(field('bal-topup-amount'), '500000');
      await settle(t, frames: 4);
      await t.tap(k('bal-topup-save'));
      await settle(t);
      expect(inKey('bal-sum-amount', '500,000 د.ع'), findsOneWidget);
      expect(inKey('bal-sum-remaining', '55,000 د.ع'), findsOneWidget);
      expect([k('bal-banner'), k('bal-amount-2')].every((f) => f.evaluate().isEmpty), isTrue);
      expect(k('bal-adjust-2'), findsOneWidget);
      await done(t);
    });

    testWidgets('سباق: حركةٌ وصلت للفترة الجديدة بعد آخر قراءة ⇒ رسالة الخادم تظهر، واللوحة تُقرأ ثانيةً فيظهر القفل بمكان الزرّ', (t) async {
      use(BalanceServer.closedWithPending(moves: 0)..reopenRace = true);
      await open(t);
      await tap(t, k('bal-period-1'));
      expect(k('bal-reopen-1'), findsOneWidget, reason: 'على الشاشة ما زال الإلغاء ممكناً');
      await tap(t, k('bal-reopen-1'));
      final reads = server.listReads;
      await t.tap(find.text('إلغاء الإغلاق').last);
      await settle(t);
      expect(find.text('لا يُلغى إغلاق هذه الفترة — الفترة التي بعدها صار فيها حركات'), findsOneWidget);
      expect(server.listReads, reads + 1, reason: 'الرفض معناه أنّ الشاشة قديمة');
      expect(k('bal-reopen-1'), findsNothing);
      expect(k('bal-reopen-locked-1'), findsOneWidget);
      expect(server.periods.length, 2, reason: 'لا شيء تغيّر عند الخادم');
      await done(t);
    });

    testWidgets('المفتاح مطفأ: الإغلاق كما كان — بلا جملة الفترة الجديدة ولا فترةٍ تُفتح، و«إلغاء الإغلاق» بنصّه القديم', (t) async {
      final s = BalanceServer.ownerExample();
      s.periods.first['amount'] = 1750000;
      use(s);
      await open(t);
      await tap(t, k('bal-close-1'));
      expect(find.textContaining('ينحسب ربح'), findsOneWidget);
      expect(find.textContaining('تُفتح بعدها فترة جديدة'), findsNothing);
      await t.tap(find.text('إغلاق الفترة').last);
      await settle(t);
      expect(find.text('أُغلقت الفترة'), findsOneWidget);
      expect(server.periods.length, 1);
      expect(t.widget<ToneChip>(k('bal-state')).label, 'مغلقة');
      await tap(t, k('bal-reopen-1'));
      expect(find.textContaining('ما دخل بعد إغلاقها سيُحسب ضمن «المحصَّل» لا ضمن الربح.'), findsOneWidget);
      expect(find.textContaining('تُحذف'), findsNothing);
      await t.tap(find.text('إلغاء الإغلاق').last);
      await settle(t);
      expect(find.text('رجعت الفترة مفتوحة'), findsOneWidget);
      await done(t);
    });

    testWidgets('الشكل: أضيق هاتف وخطٌّ ×1.2 وأرقامٌ بعشر خانات — الكرت بلا مبلغ، ورقة المبلغ، وتفاصيل المغلقة بسطر قفلها بلا فيض', (t) async {
      for (final width in [320.0, 390.0, 480.0]) {
        use(BalanceServer.closedWithPending(long: true, big: true));
        await open(t, width: width, textScale: 1.2);
        expect(t.takeException(), isNull, reason: 'الصفحة @$width');
        expect(k('bal-no-amount'), findsOneWidget);
        await tap(t, k('bal-amount-btn'));
        await t.enterText(field('bal-topup-amount'), '1250000000');
        await settle(t, frames: 4);
        expect(t.takeException(), isNull, reason: 'ورقة المبلغ @$width');
        expect(find.text('حفظ المبلغ — 1,250,000,000 د.ع'), findsOneWidget);
        await t.tapAt(const Offset(10, 10));
        await settle(t);
        await tap(t, k('bal-detail-2'));
        expect(t.takeException(), isNull, reason: 'تفاصيل الفترة بلا مبلغ @$width');
        await back(t);
        await tap(t, k('bal-period-1'));
        expect(k('bal-reopen-locked-1'), findsOneWidget);
        expect(t.takeException(), isNull, reason: 'تفاصيل المغلقة المقفلة @$width');
        await done(t);
      }
    });
  });
}
