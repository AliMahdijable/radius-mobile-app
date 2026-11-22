import 'dart:io';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/balance_reports_api.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/reports/balance_period_screen.dart';
import 'package:rad_mysvcs/screens/reports/balance_reports_screen.dart';
import 'package:rad_mysvcs/screens/reports/reports_hub_screen.dart';
import 'package:rad_mysvcs/services/balance_sub_names.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'balance_reports/balance_fixture.dart';
import 'employee_ledger/ledger_fixture.dart' show LedgerDiskLoader;

/// «تقارير الأرصدة» (١٥–١٦ نوفمبر): النماذج والنصوص، الشاشة (مثال المالك 2,000,000 / 1,750,000 / معوز 250,000، تنبيه الرصيد)،
/// «تسوية الرصيد» والإغلاق وإلغاؤه، تفاصيل الفترة (عشرةٌ ثمّ «عرض المزيد»، الفلاتر، البحث، علامة «كان دين وتسدّد»)، فشل الصفحات،
/// التحديث بعد كتابة، التعديل والحذف، الأخطاء، كرت التقارير (مفتوح/غائب/مقفل للموظّف)، والشكل بأضيق هاتف وخطٍّ مكبَّر.
void main() {
  late BalanceServer server;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    PermissionsService.debugReset();
    BalanceReportsState.reset();
    // أسماء المشتركين (٢٠ نوفمبر): بلا قائمةٍ افتراضاً — مجموعة «الأسماء» تضبطها
    BalanceSubNames.probe = () async => 0;
    BalanceSubNames.loadAll = () async => null;
    BalanceSubNames.lookup = (_) async => const <Subscriber>[];
  });

  tearDown(() {
    PermissionsService.debugReset();
    BalanceReportsState.reset();
    BalanceSubNames.debugReset();
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

  void phone(WidgetTester t, {double width = 400, double height = 2600}) {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  /// إطاراتٌ بزمنٍ محدود (لا pumpAndSettle حين تدور دوّارةٌ أو إشعار).
  Future<void> settle(WidgetTester t, {int frames = 20}) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// إشعارات الأسفل ومؤقّتاتها تنتهي قبل نهاية الاختبار.
  Future<void> done(WidgetTester t) async {
    await t.pump(const Duration(seconds: 4));
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 1));
  }

  Future<void> open(WidgetTester t, {double width = 400, double textScale = 1}) async {
    phone(t, width: width);
    await t.pumpWidget(app(const BalanceReportsScreen(), textScale: textScale));
    await settle(t);
  }

  Finder k(String key) => find.byKey(ValueKey(key));
  Finder inKey(String key, String text) => find.descendant(of: k(key), matching: find.text(text));
  Finder field(String key) => find.descendant(of: k(key), matching: find.byType(TextField));
  Finder rows() => find.byType(BalanceMoveRow);
  List<String> statuses(WidgetTester t) => t.widgetList<BalanceMoveStatus>(k('bal-move-status')).map((c) => c.text).toList();
  Future<void> tap(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pump();
    await t.tap(f);
    await settle(t);
  }

  /// حالات الحركات («كان دين وتسدّد — 22 آب»…) كاملةٌ داخل كرتها: تلتفّ ولا تُقصّ «…» ولا تخرج حافّتها من الكرت.
  /// ترجع أعلى ارتفاعٍ بينها (ليُعرف أنّ الالتفاف جُرّب فعلاً).
  double statusesWhole(WidgetTester t, String reason) {
    final card = t.getRect(k('bal-moves'));
    final boxes = find.byKey(const ValueKey('bal-move-status'));
    expect(boxes, findsWidgets, reason: reason);
    var tallest = 0.0;
    for (final e in boxes.evaluate()) {
      final box = e.renderObject! as RenderBox;
      final r = box.localToGlobal(Offset.zero) & box.size;
      expect(r.left >= card.left && r.right <= card.right, isTrue, reason: '$reason: الحالة خارج الكرت $r / $card');
      if (r.height > tallest) tallest = r.height;
    }
    for (final x in t.widgetList<Text>(find.descendant(of: boxes, matching: find.byType(Text)))) {
      expect([x.maxLines, x.overflow], [null, null], reason: '$reason: «${x.data}» بسطرٍ محدود يُقصّ');
    }
    for (final x in t.renderObjectList<RenderParagraph>(find.descendant(of: boxes, matching: find.byType(RichText)))) {
      expect(x.didExceedMaxLines, isFalse, reason: reason);
    }
    return tallest;
  }

  group('النماذج والنصوص', () {
    test('اللوحة من JSON الخادم، وردٌّ بغير شكله null (لا «لا شحنات» كاذبة)', () {
      final s = BalanceServer.ownerExample();
      final o = BalanceOverview.fromJson(s.overview())!;
      final p = o.periods.single;
      expect([p.id, p.amount, p.collected, p.remaining, p.debtsOpen, p.profit, p.net], [1, 2000000, 1750000, 250000, 600000, 0, -250000]);
      expect([p.state, p.canClose, p.progress, p.nActivations, p.nCash, p.nCredit, p.nPartial, p.nPayments], [BalanceState.running, false, 0.875, 43, 26, 16, 1, 6]);
      expect(o.periodOf(1), same(p));
      expect(o.periodOf(9), isNull);
      expect(BalanceOverview.fromJson({'feature_enabled': true}), isNull);
      expect(BalanceOverview.fromJson('x'), isNull);
      expect(BalancePeriodPage.fromJson({'period': s.periods.first, 'movements': {'nope': 1}}), isNull);
      final off = BalanceOverview.fromJson({'feature_enabled': false, 'periods': <Object>[]})!;
      expect([off.featureEnabled, off.periods], [false, isEmpty]);
    });

    test('خارج الحساب وجودة البيانات: ما لم يدخل يُقال', () {
      final o = BalanceOverview.fromJson({
        'feature_enabled': true,
        'periods': <Object>[],
        'totals': {'old_paid': 1365000, 'manual_paid': 0, 'other_paid': 25000, 'advance': 15000},
        'quality': {'no_price': 1, 'no_amount': 2, 'no_snapshot': 0, 'transfers_unknown': true},
      })!;
      expect(o.outside.map((x) => x.id), ['old', 'other', 'advance']);
      expect(o.qualityNotes.length, 3);
      expect(o.qualityNotes[1], contains('2 حركة بلا مبلغٍ مسجَّل'));
    });

    test('حال دين التفعيل بكلامه: «كان دين وتسدّد» (نقداً أو ربحاً)، الباقي، وما لم يُسجَّل', () {
      BalanceActMove act(String state, {String? turned, num remaining = 0, num paidIn = 0, num paidLate = 0, int? last}) => BalanceMove.fromJson({
            'key': 'a1', 'kind': 'activate', 'at_ms': balanceStart(5), 'username': 'u@x', 'price': 40000, 'pay': 'credit', 'cash': 0, 'debt': 40000,
            'remaining': remaining, 'debt_state': state, 'turned': turned, 'paid_in': paidIn, 'paid_late': paidLate, 'untracked': 0, 'excess': 0, 'last_paid_at_ms': last,
            'after_close': false,
          })! as BalanceActMove;
      final when = balanceDay(balanceStart(3), nowMs: balanceNowMs);
      expect(balanceDebtNote(act('paid', turned: 'cash', paidIn: 40000, last: balanceStart(3)), nowMs: balanceNowMs), (text: 'كان دين وتسدّد — $when', tone: BalanceTone.success));
      expect(balanceDebtNote(act('paid', turned: 'profit', paidLate: 40000, last: balanceStart(3)), nowMs: balanceNowMs),
          (text: 'كان دين وتسدّد بعد الإغلاق — صار ربح — $when', tone: BalanceTone.brand));
      expect(balanceDebtNote(act('partly', turned: 'cash', remaining: 25000, paidIn: 15000))!.text, 'تسدّد منه 15,000 · باقي 25,000');
      expect(balanceDebtNote(act('open', remaining: 40000)), (text: 'دين باقي 40,000', tone: BalanceTone.danger));
      expect(balanceDebtNote(act('untracked'))!.text, 'الدين لم يُسجَّل على المشترك');
      expect(balanceDebtNote(act('written_off'))!.tone, BalanceTone.neutral);
      expect(balanceDebtNote(act('none')), isNull);
    });

    test('تنبيه الفترة: اكتمل، انتهت ولم تكتمل، الرصيد خلص — ورصيدٌ مجهول لا يقول «خلص»', () {
      final s = BalanceServer.three();
      final o = BalanceOverview.fromJson(s.overview())!;
      final running = o.periods[0];
      final waiting = o.periods[1];
      final closed = o.periods[2];
      expect(balanceBanner(running, 3000)!.kind, BalanceBannerKind.empty);
      expect(balanceBanner(running, 3000)!.text, 'نفد رصيدك ولم يكتمل المبلغ — المتبقّي 250,000 د.ع');
      expect(balanceBanner(running, 20000)!.kind, BalanceBannerKind.empty, reason: 'واحدٌ بالمئة من 2,000,000');
      expect(balanceBanner(running, 20001), isNull);
      expect(balanceBanner(running, null), isNull);
      expect(balanceBanner(waiting, 900000)!.kind, BalanceBannerKind.ended);
      expect(balanceBanner(closed, 0), isNull);
      expect(balanceLowMark(500000), 10000);
    });

    test('وقت بغداد ⇄ لحظة، والإشارة معزولةٌ مع رقمها', () {
      final ms = balanceMsFromBaghdad(2026, 10, 10, 9, 30);
      expect(ms, DateTime.utc(2026, 10, 10, 6, 30).millisecondsSinceEpoch);
      final d = balanceBaghdad(ms);
      expect([d.year, d.month, d.day, d.hour, d.minute], [2026, 10, 10, 9, 30]);
      // منتصف الليل ببغداد = اليوم نفسه (لا يرجع ليوم أمس)
      expect(balanceBaghdad(balanceMsFromBaghdad(2026, 11, 1, 0, 5)).day, 1);
      // أرقامٌ لا اسم شهر (المالك ١٦ نوفمبر) — بتوقيت بغداد، والسنة دائماً
      expect(balanceDay(ms, nowMs: ms), '2026/10/10');
      expect(balanceDayTime(ms, nowMs: ms), '2026/10/10 · 09:30');
      final signed = balanceSigned(-250000, sign: '−');
      expect(signed.codeUnits.first, 0x2066);
      expect(signed, contains('−250,000'));
      expect(signed.endsWith(' د.ع'), isTrue);
    });
  });

  group('الشاشة', () {
    testWidgets('لا شحنات: شرحٌ وزرّ، ثمّ تسجيل أوّل شحنة — الطلب بالمبلغ ووقتٍ بدقيقته ومرجعٍ فريد، واللوحة من ردّ الكتابة', (t) async {
      use(BalanceServer());
      await open(t);
      expect(find.text('سجّل أوّل شحن للرصيد'), findsOneWidget);
      expect(k('bal-new'), findsNothing, reason: 'الزرّ العائم بعد أوّل شحنة');
      await tap(t, k('bal-first'));
      expect(find.text('اكتب مبلغ الشحن'), findsOneWidget);
      await t.enterText(field('bal-topup-amount'), '2000000');
      await settle(t, frames: 4);
      expect(find.text('تسجيل الشحن — 2,000,000 د.ع'), findsOneWidget);
      await t.tap(k('bal-topup-save'));
      await settle(t);
      final w = server.lastWrite('POST', RegExp(r'/periods$'))!;
      final at = w.body['started_at_ms'] as int;
      expect(w.body['amount'], 2000000);
      expect(at % 60000, 0, reason: 'بدقيقته');
      expect((DateTime.now().millisecondsSinceEpoch - at).abs() < 120000, isTrue);
      expect(RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch('${w.body['client_ref']}'), isTrue);
      expect(k('bal-hero'), findsOneWidget);
      expect(t.widget<Text>(k('bal-amount')).data, '2,000,000 د.ع');
      expect(server.listReads, 1, reason: 'لا قراءة ثانية بعد الكتابة');
      expect(k('bal-new'), findsOneWidget);
      await done(t);
    });

    testWidgets('مثال المالك: شحن 2,000,000 وطبّله 1,750,000 ⇒ المعوز 250,000، ديون الفترة 600,000، والربح يبدأ بعد رجوع المبلغ', (t) async {
      use(BalanceServer.ownerExample()..balance = 3000);
      await open(t);
      expect(t.widget<Text>(k('bal-amount')).data, '2,000,000 د.ع');
      expect(inKey('bal-stat-collected', '1,750,000 د.ع'), findsOneWidget);
      expect(inKey('bal-stat-collected', 'نقد التفعيلات 1,450,000'), findsOneWidget);
      expect(inKey('bal-stat-collected', 'تسديد ديونها 300,000'), findsOneWidget);
      expect(inKey('bal-stat-remaining', '250,000 د.ع'), findsOneWidget);
      expect(inKey('bal-stat-debts', '600,000 د.ع'), findsOneWidget);
      expect(inKey('bal-stat-profit', '0 د.ع'), findsOneWidget);
      expect(inKey('bal-stat-profit', 'يبدأ بعد أن يعود مبلغ الشحن'), findsOneWidget);
      expect(t.widget<Text>(k('bal-percent')).data, '88%');
      // الشريط يُرى: ارتفاعه ١٠ وجزؤه الأخضر ٨٧٫٥٪ من عرضه (كان بلا ارتفاع فلا يظهر)
      final bar = t.getSize(find.byType(BalanceProgress).first);
      final green = t.getSize(find.descendant(of: find.byType(BalanceProgress).first, matching: find.byType(ColoredBox)).first);
      expect(bar.height, 10);
      expect(green.height, 10);
      expect((green.width / bar.width - 0.875).abs() < 0.01, isTrue, reason: '${green.width} / ${bar.width}');
      expect(t.widget<ToneChip>(k('bal-state')).label, 'جارية');
      expect(inKey('bal-banner', 'نفد رصيدك ولم يكتمل المبلغ — المتبقّي 250,000 د.ع'), findsOneWidget);
      expect(inKey('bal-live', '3,000 د.ع'), findsOneWidget);
      expect(inKey('bal-income', '400,000 د.ع'), findsOneWidget);
      expect(k('bal-close-1'), findsNothing);
      expect(k('bal-adjust-1'), findsOneWidget);
      await done(t);
    });

    testWidgets('الرصيد: فيه رصيد ⇒ لا تنبيه؛ تعذّرت قراءته ⇒ لا تنبيه ولا «0 د.ع»', (t) async {
      use(BalanceServer.ownerExample()..balance = 800000);
      await open(t);
      expect(k('bal-banner'), findsNothing);
      expect(inKey('bal-live', '800,000 د.ع'), findsOneWidget);
      await done(t);
      use(BalanceServer.ownerExample()..balanceUnknown = true);
      await open(t);
      expect(k('bal-banner'), findsNothing);
      expect(k('bal-live'), findsNothing);
      await done(t);
    });

    testWidgets('تسوية الرصيد ثمّ الإغلاق ثمّ إلغاؤه: المبلغ مقترحٌ بالمعوز، الطلب بمصدره ومرجعه، واللوحة تتحدّث من الردّ', (t) async {
      use(BalanceServer.ownerExample());
      await open(t);
      await tap(t, k('bal-adjust-1'));
      expect(inKey('bal-adjust-remaining', '250,000 د.ع'), findsOneWidget);
      expect(find.text('تسجيل التسوية — 250,000 د.ع'), findsOneWidget);
      expect(k('bal-adjust-income'), findsOneWidget);
      await t.tap(find.descendant(of: k('bal-adjust-source'), matching: find.text('من مالي الخاصّ')));
      await settle(t, frames: 4);
      expect(k('bal-adjust-income'), findsNothing);
      await t.tap(k('bal-adjust-save'));
      await settle(t);
      final a = server.lastWrite('POST', RegExp(r'/periods/1/adjustments$'))!;
      expect([a.body['amount'], a.body['source'], a.body.containsKey('note')], [250000, 'pocket', false]);
      expect(inKey('bal-stat-remaining', 'مكتمل'), findsOneWidget);
      expect(inKey('bal-stat-remaining', 'منها تسوية 250,000'), findsOneWidget);
      expect(inKey('bal-banner', 'اكتمل مبلغ الشحن — يمكنك إغلاق الفترة'), findsOneWidget);
      expect(inKey('bal-stat-profit', 'دفعت 250,000 بالتسوية وبعدها ما رجعت'), findsOneWidget);
      expect(t.widget<Text>(k('bal-percent')).data, '100%');
      expect(k('bal-unadjust-100'), findsOneWidget);
      expect(k('bal-adjust-1'), findsNothing);
      // الإغلاق
      await tap(t, k('bal-close-1'));
      expect(find.textContaining('ينحسب ربح'), findsOneWidget);
      await t.tap(find.text('إغلاق الفترة').last);
      await settle(t);
      expect(server.lastWrite('POST', RegExp(r'/periods/1/close$')), isNotNull);
      expect(t.widget<ToneChip>(k('bal-state')).label, 'مغلقة');
      expect([k('bal-edit-1'), k('bal-delete-1'), k('bal-close-1'), k('bal-adjust-1'), k('bal-unadjust-100')].every((f) => f.evaluate().isEmpty), isTrue);
      // إلغاء الإغلاق
      await tap(t, k('bal-reopen-1'));
      await t.tap(find.text('إلغاء الإغلاق').last);
      await settle(t);
      expect(server.lastWrite('POST', RegExp(r'/periods/1/reopen$')), isNotNull);
      expect(t.widget<ToneChip>(k('bal-state')).label, 'جارية');
      expect(server.listReads, 1);
      await done(t);
    });

    testWidgets('قواعد التسوية: أكبر من المعوز، «غير ذلك» بلا ملاحظة، ورفض الخادم يُبقي الورقة والمحاولة الثانية بالمرجع نفسه', (t) async {
      use(BalanceServer.ownerExample());
      await open(t);
      await tap(t, k('bal-adjust-1'));
      await t.enterText(field('bal-adjust-amount'), '300000');
      await settle(t, frames: 4);
      expect(find.text('المبلغ أكبر من المتبقّي (250,000 د.ع)'), findsOneWidget);
      await t.enterText(field('bal-adjust-amount'), '100000');
      await t.tap(find.descendant(of: k('bal-adjust-source'), matching: find.text('غير ذلك')));
      await settle(t, frames: 4);
      expect(find.text('اكتب ملاحظة توضّح مصدر المبلغ'), findsOneWidget);
      await t.enterText(find.descendant(of: k('bal-adjust-note'), matching: find.byType(TextField)), 'من بيع راوتر');
      await settle(t, frames: 4);
      expect(find.text('تسجيل التسوية — 100,000 د.ع'), findsOneWidget);
      server.adjustFail = {'code': 'BUSY', 'message': 'عمليّة أخرى جارية على تقارير الأرصدة — أعد المحاولة بعد لحظات'};
      await t.tap(k('bal-adjust-save'));
      await settle(t);
      expect(find.textContaining('عمليّة أخرى جارية'), findsOneWidget);
      expect(k('bal-adjust-save'), findsOneWidget, reason: 'الورقة باقية');
      server.adjustFail = null;
      await t.pump(const Duration(seconds: 4));
      await t.tap(k('bal-adjust-save'));
      await settle(t);
      final two = server.writes.where((w) => w.method == 'POST' && w.path.endsWith('/adjustments')).toList();
      expect(two.length, 2);
      expect(two[0].body['client_ref'], two[1].body['client_ref']);
      expect([two[1].body['source'], two[1].body['note']], ['other', 'من بيع راوتر']);
      expect(inKey('bal-stat-remaining', '150,000 د.ع'), findsOneWidget);
      // حذف التسوية يرجّع المعوز
      await tap(t, k('bal-unadjust-100'));
      await t.tap(find.text('حذف التسوية').last);
      await settle(t);
      expect(server.lastWrite('DELETE', RegExp(r'/adjustments/100$')), isNotNull);
      expect(inKey('bal-stat-remaining', '250,000 د.ع'), findsOneWidget);
      await done(t);
    });

    testWidgets('تفاصيل الفترة: الخلاصة، عشرةٌ ثمّ «عرض المزيد»، الفلاتر بأعدادها، البحث، وعلامة «كان دين وتسدّد»', (t) async {
      use(BalanceServer.ownerExample());
      await open(t);
      await tap(t, k('bal-detail-1'));
      expect(inKey('bal-sum-collected', '1,750,000 د.ع'), findsOneWidget);
      expect(inKey('bal-sum-remaining', '250,000 د.ع'), findsOneWidget);
      expect(find.text('الصافي (لم يعُد مبلغ الشحن بعد)'), findsOneWidget);
      expect(inKey('bal-sum-net', balanceSigned(-250000, sign: '−')), findsOneWidget);
      expect(rows(), findsNWidgets(10));
      expect(find.text('عرض المزيد (10 من 47)'), findsOneWidget);
      expect(find.text('الكل 47'), findsOneWidget);
      await tap(t, k('bal-moves-more'));
      expect(rows(), findsNWidgets(30));
      expect(server.pageReqs.any((r) => r.offset == 20 && r.filter == 'all'), isTrue);
      await tap(t, k('bal-moves-more'));
      expect(rows(), findsNWidgets(47));
      expect(k('bal-moves-more'), findsNothing);
      await tap(t, k('bal-moves-less'));
      expect(rows(), findsNWidgets(10));
      // «كان دين وتسدّد»
      await tap(t, k('bal-filter-paid'));
      expect(server.pageReqs.any((r) => r.filter == 'paid' && r.offset == 0), isTrue);
      final paid = statuses(t);
      expect(paid, isNotEmpty);
      expect(paid.every((x) => x.startsWith('كان دين وتسدّد')), isTrue, reason: paid.join(' | '));
      await tap(t, k('bal-filter-open'));
      final open_ = statuses(t);
      expect(open_.isNotEmpty && open_.every((x) => RegExp(r'^دين باقي [\d,]+$|^تسدّد منه [\d,]+ · باقي [\d,]+$').hasMatch(x)), isTrue, reason: open_.join(' | '));
      await tap(t, k('bal-filter-payments'));
      expect(statuses(t).toSet(), {'أُضيف إلى «المحصَّل»'});
      // البحث بعد التوقّف عن الكتابة
      await tap(t, k('bal-filter-all'));
      await t.enterText(field('bal-search'), 'USER7');
      await t.pump(const Duration(milliseconds: 200));
      expect(server.pageReqs.any((r) => r.q == 'USER7'), isFalse, reason: 'ليس مع كلّ حرف');
      await t.pump(const Duration(milliseconds: 250));
      await settle(t);
      expect(server.pageReqs.any((r) => r.q == 'USER7' && r.offset == 0), isTrue);
      expect(rows(), findsOneWidget);
      expect(find.text('user7@net'), findsOneWidget);
      await t.enterText(field('bal-search'), 'zzzz');
      await t.pump(const Duration(milliseconds: 400));
      await settle(t);
      expect(find.text('لا حركة بهذا الاسم'), findsOneWidget);
      await done(t);
    });

    testWidgets('أطول حالة «كان دين وتسدّد بعد الإغلاق — صار ربح — التاريخ» بأضيق هاتف وخطٍّ ×1.2: تلتفّ كاملةً ولا يُقصّ تاريخها', (t) async {
      use(BalanceServer.three());
      await open(t, width: 320, textScale: 1.2);
      await tap(t, find.descendant(of: k('bal-period-3'), matching: find.byType(InkWell)).first);
      await tap(t, k('bal-filter-paid'));
      final paid = statuses(t);
      final late_ = paid.where((x) => x.startsWith('كان دين وتسدّد بعد الإغلاق — صار ربح — ')).toList();
      expect(late_, isNotEmpty, reason: paid.join(' | '));
      expect(late_.every((x) => RegExp(r' — \d{4}/\d{2}/\d{2}$').hasMatch(x)), isTrue, reason: 'التاريخ بآخرها: ${late_.join(' | ')}');
      final oneLine = t.getSize(find.descendant(of: k('bal-moves'), matching: find.byType(ToneChip)).first).height;
      final tallest = statusesWhole(t, 'الفترة المغلقة @320');
      expect(tallest, greaterThan(oneLine * 1.5), reason: 'الحالة الطويلة التفّت على أكثر من سطر');
      expect(t.takeException(), isNull);
      await done(t);
    });

    testWidgets('فشل صفحةٍ تالية: المحمَّل باقٍ و«أعد المحاولة» بلا إعادةٍ تلقائيّة؛ وردٌّ بغير شكله ليس «لا حركات»', (t) async {
      for (final shape in [false, true]) {
        use(BalanceServer.ownerExample()
          ..failOffsets.add(20)
          ..shapeFail = shape);
        await open(t);
        await tap(t, k('bal-detail-1'));
        await tap(t, k('bal-moves-more'));
        expect(rows(), findsNWidgets(20), reason: 'ما حُمل باقٍ (shape=$shape)');
        expect(find.text('تعذّر تحميل المزيد — أعد المحاولة'), findsOneWidget);
        final before = server.pageReqs.where((r) => r.offset == 20).length;
        await t.pump(const Duration(seconds: 2));
        expect(server.pageReqs.where((r) => r.offset == 20).length, before);
        server.failOffsets.clear();
        await tap(t, k('bal-moves-retry'));
        expect(rows(), findsNWidgets(30));
        await done(t);
      }
      use(BalanceServer.ownerExample()..failOffsets.add(0));
      await open(t);
      await tap(t, k('bal-detail-1'));
      expect(find.textContaining('تعذّر تحميل تقارير الأرصدة الآن'), findsOneWidget);
      expect(find.text('لا حركات هنا'), findsNothing);
      server.failOffsets.clear();
      await tap(t, k('bal-moves-retry'));
      expect(rows(), findsNWidgets(10));
      await done(t);
    });

    testWidgets('كتابةٌ والتفاصيل مفتوحة: الخلاصة بالرقم الجديد والحركات تُعاد من الخادم — وما كان معروضاً يبقى', (t) async {
      use(BalanceServer.ownerExample());
      await open(t);
      await tap(t, k('bal-detail-1'));
      await tap(t, k('bal-moves-more'));
      expect(rows(), findsNWidgets(30));
      final mark = server.pageReqs.length;
      await tap(t, k('bal-adjust-1'));
      await t.enterText(field('bal-adjust-amount'), '50000');
      await settle(t, frames: 4);
      await t.tap(k('bal-adjust-save'));
      await settle(t);
      expect(inKey('bal-sum-remaining', '200,000 د.ع'), findsOneWidget);
      final after = server.pageReqs.skip(mark).where((r) => r.filter == 'all').map((r) => r.offset).toList();
      expect(after, containsAll([0, 20]));
      expect(rows(), findsNWidgets(30), reason: 'لا يرجع لعشرة تحت يده');
      expect(k('bal-move-j100'), findsOneWidget, reason: 'سطر التسوية أوّل الحركات');
      await done(t);
    });

    testWidgets('ثلاث فترات: الجارية كرتٌ كبير، «بانتظار الإغلاق» بزرّ تسويتها، المغلقة بصافي ربحها — وخارج الحساب وجودة البيانات', (t) async {
      use(BalanceServer.three()
        ..totals = {'old_paid': 1365000, 'manual_paid': 40000, 'other_paid': 0, 'advance': 15000, 'closed_net': 200000, 'debts_open': 1050000}
        ..quality = {'rows': 300, 'no_price': 0, 'no_amount': 2, 'no_snapshot': 0, 'drift': 0, 'transfers_unknown': false}
        ..periods.first['transfers'] = {'count': 2, 'sum': 500000});
      await open(t);
      expect(k('bal-hero'), findsOneWidget);
      expect(inKey('bal-period-2', 'بانتظار الإغلاق'), findsOneWidget);
      expect(inKey('bal-period-2', '250,000'), findsOneWidget);
      expect(k('bal-adjust-2'), findsOneWidget);
      expect(inKey('bal-period-3', 'مغلقة'), findsOneWidget);
      expect(inKey('bal-period-3', 'صافي الربح'), findsOneWidget);
      expect(inKey('bal-period-3', '200,000'), findsOneWidget);
      expect(k('bal-adjust-3'), findsNothing);
      expect(t.widget<Text>(k('bal-transfers')).data, '2 تحويل رصيد لمدراء فرعيّين بمبلغ 500,000 د.ع — غير داخلة بالحساب');
      // «خارج حساب الشحن» قسمٌ فرعيّ مطويّ (المالك ٢٢ نوفمبر): مجموعه بجانب عنوانه، وسطوره بلمسة — وملاحظات الدقّة ظاهرةٌ دائماً
      expect(k('bal-outside-old'), findsNothing);
      expect(inKey('bal-outside', '1,420,000'), findsOneWidget);
      await tap(t, find.descendant(of: k('bal-outside'), matching: find.text('خارج حساب الشحن')));
      expect(inKey('bal-outside-old', '1,365,000 د.ع'), findsOneWidget);
      expect(inKey('bal-outside-manual', '40,000 د.ع'), findsOneWidget);
      expect(inKey('bal-outside-advance', '15,000 د.ع'), findsOneWidget);
      expect(k('bal-outside-other'), findsNothing);
      expect(t.widget<Text>(k('bal-quality')).data, contains('2 حركة بلا مبلغٍ مسجَّل'));
      // تفاصيل المغلقة: دخلٌ بعد الإغلاق، ودينٌ تسدّد بعده «صار ربح»
      await tap(t, find.descendant(of: k('bal-period-3'), matching: find.byType(InkWell)).first);
      expect(inKey('bal-sum-late', '300,000 د.ع'), findsOneWidget);
      expect(find.text('صافي ربح الفترة'), findsOneWidget);
      await tap(t, k('bal-filter-paid'));
      expect(statuses(t).any((x) => x.startsWith('كان دين وتسدّد بعد الإغلاق — صار ربح')), isTrue);
      await done(t);
    });

    testWidgets('شاشةٌ عريضة: مبلغ الشحنة في كروت الفترات السابقة ملزوقٌ بحافّة الكرت لا عائمٌ بوسط السطر', (t) async {
      use(BalanceServer.three());
      await open(t, width: 900);
      for (final id in [2, 3]) {
        final card = t.getRect(k('bal-period-$id'));
        final amount = t.getRect(find.descendant(of: k('bal-period-amount-$id'), matching: find.byType(Text)));
        // الحافّة البعيدة يسارٌ (الواجهة من اليمين): حشوة الكرت 16 + حدّه
        expect(amount.left - card.left, closeTo(17, 1.5), reason: 'الفترة $id: ${amount.left - card.left}');
        expect(amount.width, lessThan(card.width * 0.3), reason: 'المبلغ أضيق من خانته — وإلّا لا يفحص هذا الاختبار شيئاً');
      }
      await done(t);
    });

    testWidgets('تعديل الشحنة وحذفها: الورقة بقيمها، الوقت لا يُرسل إن لم يتغيّر، والحذف يرجّع الشرح الأوّل', (t) async {
      use(BalanceServer.ownerExample(note: 'شحنة الشهر'));
      await open(t);
      await tap(t, k('bal-edit-1'));
      expect(t.widget<TextField>(field('bal-topup-amount')).controller!.text, '2,000,000');
      await t.enterText(field('bal-topup-amount'), '2500000');
      await settle(t, frames: 4);
      expect(find.text('حفظ التعديل'), findsOneWidget);
      await t.tap(k('bal-topup-save'));
      await settle(t);
      final put = server.lastWrite('PUT', RegExp(r'/periods/1$'))!;
      expect([put.body['amount'], put.body.containsKey('started_at_ms'), put.body['note']], [2500000, false, 'شحنة الشهر']);
      expect(inKey('bal-stat-remaining', '750,000 د.ع'), findsOneWidget);
      await tap(t, k('bal-delete-1'));
      expect(find.textContaining('حركات المشتركين وديونهم ما تتغيّر'), findsOneWidget);
      await t.tap(find.text('حذف').last);
      await settle(t);
      expect(server.lastWrite('DELETE', RegExp(r'/periods/1$')), isNotNull);
      expect(find.text('سجّل أوّل شحن للرصيد'), findsOneWidget);
      await done(t);
    });

    testWidgets('الأخطاء: نصّ الخادم وزرّ الإعادة (لا أرقام)، ومطفأة', (t) async {
      use(BalanceServer.ownerExample()..listFail = 'big');
      await open(t);
      expect(find.textContaining('حركات هذا الحساب أكثر ممّا يحسبه التقرير الآن'), findsOneWidget);
      expect(k('bal-hero'), findsNothing);
      server.listFail = null;
      await tap(t, k('bal-retry'));
      expect(k('bal-hero'), findsOneWidget);
      await done(t);
      use(BalanceServer.ownerExample()..enabled = false);
      await open(t);
      expect(find.text('تقارير الأرصدة غير مفعّلة لحسابك بعد'), findsOneWidget);
      expect(k('bal-new'), findsNothing);
      await done(t);
    });

    testWidgets('الشكل: أضيق هاتف وخطٌّ ×1.2 وأرقامٌ بعشر خانات وأسماءٌ طويلة — لا فيض في الصفحة ولا التفاصيل ولا الأوراق', (t) async {
      for (final width in [320.0, 390.0, 480.0]) {
        final s = BalanceServer.three(long: true, big: true);
        final p = s.periods.first;
        p['amount'] = 2000000000;
        p['cash_now'] = 1450000000;
        p['paid_in'] = 300000000;
        p['debts_created'] = 900000000;
        p['debts_open'] = 600000000;
        p['income_in_window'] = 400000000;
        p['note'] = 'ملاحظة طويلة على الشحنة حتى نرى التفافها في أضيق هاتف';
        p['transfers'] = {'count': 12, 'sum': 1500000000};
        p['adjustments'] = [
          {'id': 91, 'amount': 125000000, 'source': 'other', 'note': 'ملاحظة طويلة عن مصدر مبلغ التسوية حتى نرى كيف تلتفّ بلا أن تخرج من الكرت', 'created_at_ms': balanceStart(3)},
        ];
        s.totals = {'old_paid': 1365000000, 'manual_paid': 40000000, 'other_paid': 25000000, 'advance': 15000000};
        s.balance = 1000;
        use(s);
        await open(t, width: width, textScale: 1.2);
        expect(t.takeException(), isNull, reason: 'الصفحة @$width');
        await tap(t, k('bal-detail-1'));
        await tap(t, k('bal-moves-more'));
        expect(t.takeException(), isNull, reason: 'التفاصيل @$width');
        statusesWhole(t, 'حالات الحركات @$width');
        await tap(t, k('bal-adjust-1'));
        expect(t.takeException(), isNull, reason: 'ورقة التسوية @$width');
        await done(t);
      }
    });
  });

  group('كرت التقارير', () {
    Future<void> hub(WidgetTester t) async {
      phone(t);
      await t.pumpWidget(app(const ReportsHubScreen()));
      await settle(t);
    }

    testWidgets('المدير والميزة مفتوحة: الكرت ظاهرٌ ويفتح الصفحة؛ مطفأة: لا كرت', (t) async {
      use(BalanceServer.ownerExample());
      PermissionsService.debugSet(isEmployee: false);
      await hub(t);
      expect(k('report-balances'), findsOneWidget);
      expect(find.text('تقارير الأرصدة'), findsOneWidget);
      await tap(t, k('report-balances'));
      expect(k('bal-hero'), findsOneWidget);
      await done(t);
      use(BalanceServer.ownerExample()..enabled = false);
      await hub(t);
      expect(k('report-balances'), findsNothing);
      await done(t);
    });

    testWidgets('الفتح الثاني: الكرت من أوّل إطار (لا يقفز ما تحته)، والخادم يُسأل ثانيةً — وعثرة الشبكة لا تُخفيه', (t) async {
      use(BalanceServer.ownerExample());
      PermissionsService.debugSet(isEmployee: false);
      phone(t);
      await t.pumpWidget(app(const ReportsHubScreen()));
      await t.pump();
      expect(k('report-balances'), findsNothing, reason: 'أوّل فتحٍ في الجلسة: لا جواب بعد');
      await settle(t);
      expect(k('report-balances'), findsOneWidget);
      await done(t);
      // فتحٌ ثانٍ والخادم يتعثّر: الكرت حاضرٌ من الإطار الأوّل ويبقى بعد فشل السؤال
      server.meFail = true;
      await t.pumpWidget(app(const ReportsHubScreen()));
      await t.pump();
      expect(k('report-balances'), findsOneWidget, reason: 'من آخر جوابٍ لهذه الجلسة');
      await settle(t);
      expect(server.meReads, greaterThan(1), reason: 'يُسأل الخادم مع كلّ فتح (وطلب القراءة الفاشل قد يُعاد مرّة)');
      expect(k('report-balances'), findsOneWidget, reason: 'عثرة شبكة لا تُخفي الكرت');
      await done(t);
      // أُطفئت الميزة عند الخادم: الجواب الجديد يُخفيه
      server
        ..meFail = false
        ..enabled = false;
      await t.pumpWidget(app(const ReportsHubScreen()));
      await settle(t);
      expect(k('report-balances'), findsNothing);
      await done(t);
    });

    testWidgets('الجلسة تبدّلت: المحفوظ يُمسح فلا كرت لصفحةٍ أخرى، وجوابٌ وصل بعد التبدّل يُهمل', (t) async {
      use(BalanceServer.ownerExample());
      PermissionsService.debugSet(isEmployee: false);
      await hub(t);
      expect(k('report-balances'), findsOneWidget);
      await done(t);
      expect(BalanceReportsState.last?.featureEnabled, isTrue);
      BalanceReportsState.reset(); // ما يفعله SessionManager عند الخروج/تبديل الشركة
      expect(BalanceReportsState.last, isNull);
      use(BalanceServer.ownerExample()..enabled = false);
      await t.pumpWidget(app(const ReportsHubScreen()));
      await t.pump();
      expect(k('report-balances'), findsNothing, reason: 'لا كرت من جلسةٍ سابقة');
      await done(t);
      // طلبٌ في الطريق والجلسة تتبدّل: جوابه (مفتوحة) لصفحةٍ أخرى فلا يُحفظ
      use(BalanceServer.ownerExample());
      final pending = BalanceReportsState.refresh();
      BalanceReportsState.reset();
      await settle(t);
      expect(await pending, isNull);
      expect(BalanceReportsState.last, isNull);
      // ومسح الجلسة يستدعيه فعلاً
      final src = File('lib/services/session_manager.dart').readAsStringSync();
      expect(src, contains("_guardSync('BalanceReportsState.reset', () => BalanceReportsState.reset());"));
    });

    testWidgets('الموظّف بلا «تقارير الأرصدة — عرض»: الكرت بمكانه مقفلاً بنصّ الصلاحيّة — لا يفتح ولا يطلب اللوحة', (t) async {
      use(BalanceServer.ownerExample()..employee = true);
      PermissionsService.debugSet(isEmployee: true, permissions: const {'reports.financial': true});
      await hub(t);
      expect(k('report-balances'), findsOneWidget);
      await tap(t, k('report-balances'));
      expect(find.text('locked.toast'.tr()), findsOneWidget);
      expect(find.text('هذا القسم لمدير الصفحة وحده'), findsNothing, reason: 'لم يعد للمدير وحده (٢٠ نوفمبر)');
      expect(find.byType(BalanceReportsScreen), findsNothing);
      expect(server.listReads, 0);
      await done(t);
    });

    testWidgets('الموظّف بمفتاح «العرض» (can_view من الخادم): الكرت مفتوحٌ ويفتح الصفحة', (t) async {
      use(BalanceServer.ownerExample()
        ..employee = true
        ..empView = true);
      PermissionsService.debugSet(isEmployee: true, permissions: const {'reports.financial': true, 'balance_reports.view': true});
      await hub(t);
      await tap(t, k('report-balances'));
      expect(find.text('locked.toast'.tr()), findsNothing);
      expect(k('bal-hero'), findsOneWidget);
      expect(server.listReads, greaterThan(0));
      await done(t);
    });
  });

  // ═══════════ ٢٠ نوفمبر: الموظّف بمفتاحَيه، والاسم العربيّ بجانب اليوزر ═══════════
  group('الموظّف (٢٠ نوفمبر)', () {
    testWidgets('«العرض» وحده: اللوحة والتفاصيل تُقرأ، سطر «للعرض» بسببه، ولا زرّ كتابة ولا طلب كتابة', (t) async {
      use(BalanceServer.three()
        ..employee = true
        ..empView = true);
      PermissionsService.debugSet(isEmployee: true, permissions: const {'balance_reports.view': true});
      await open(t);
      expect(k('bal-hero'), findsOneWidget);
      expect(t.widget<Text>(k('bal-employee-readonly')).data, BalanceReportsController.employeeReadOnlyText);
      expect(k('bal-routed-readonly'), findsNothing, reason: 'سطر «كل الشركات» ليس له');
      for (final key in ['bal-new', 'bal-amount-btn', 'bal-adjust-1', 'bal-close-1', 'bal-edit-1', 'bal-adjust-2', 'bal-close-2', 'bal-edit-2']) {
        expect(k(key), findsNothing, reason: key);
      }
      await tap(t, k('bal-detail-1'));
      expect(rows(), findsWidgets);
      expect(k('bal-adjust-1'), findsNothing);
      expect(k('bal-close-1'), findsNothing);
      expect(server.writes, isEmpty);
      await done(t);
    });

    testWidgets('«العرض» و«التسجيل»: أزرار الكتابة بلا سطر «للعرض»، والشحن يُرسل', (t) async {
      use(BalanceServer.ownerExample()
        ..employee = true
        ..empView = true
        ..empManage = true);
      PermissionsService.debugSet(isEmployee: true, permissions: const {'balance_reports.view': true, 'balance_reports.manage': true});
      await open(t);
      expect(k('bal-employee-readonly'), findsNothing);
      expect(k('bal-new'), findsOneWidget);
      expect(k('bal-adjust-1'), findsOneWidget);
      await done(t);
    });

    testWidgets('حتى يصل جواب «من أنا» لا زرّ كتابة؛ وتعذّره ⇒ للعرض بلا سطرٍ يَعِد بشيء', (t) async {
      use(BalanceServer.ownerExample()
        ..employee = true
        ..empView = true
        ..empManage = true
        ..meFail = true);
      PermissionsService.debugSet(isEmployee: true, permissions: const {'balance_reports.view': true, 'balance_reports.manage': true});
      final c = BalanceReportsController();
      expect(c.canWrite, isFalse, reason: 'الموظّف لا يكتب قبل جواب الخادم');
      c.dispose();
      await open(t);
      expect(k('bal-hero'), findsOneWidget);
      expect(k('bal-new'), findsNothing);
      expect(k('bal-adjust-1'), findsNothing);
      expect(k('bal-employee-readonly'), findsNothing);
      expect(k('bal-routed-readonly'), findsNothing);
      await done(t);
    });

    testWidgets('لا شحنات و«العرض» وحده: الشرح بسببه بلا زرّ', (t) async {
      use(BalanceServer()
        ..employee = true
        ..empView = true);
      PermissionsService.debugSet(isEmployee: true, permissions: const {'balance_reports.view': true});
      await open(t);
      expect(k('bal-empty'), findsOneWidget);
      expect(find.text(BalanceReportsController.employeeReadOnlyText), findsOneWidget);
      expect(k('bal-first'), findsNothing);
      await done(t);
    });

    test('مفتاحاه لموظّفي ايرث لنك وفايبر اكس والشركات المُضافة — خارج الأدوار الجاهزة، و«موظّف عام» الحاليّ يبقى مطابقاً', () {
      expect(ElEmployeePerms.balanceReportKeys, {'balance_reports.view', 'balance_reports.manage'});
      for (final e in {'ايرث لنك': ElEmployeePerms.earthlinkKeys, 'فايبر اكس': ElEmployeePerms.fiberxKeys, 'الشركات المُضافة': ElEmployeePerms.kitKeys}.entries) {
        expect(e.value.containsAll(ElEmployeePerms.balanceReportKeys), isTrue, reason: e.key);
      }
      for (final p in ElEmployeePerms.presets) {
        expect(p.keys.intersection(ElEmployeePerms.balanceReportKeys), isEmpty, reason: p.id);
      }
      // موظّف ايرث لنك على «موظّف عام» (قبل اليوم): يبقى مطابقاً والمفتاحان مطفأان؛ ومنح «العرض» فرادى ⇒ مخصّص (كالتذاكر)
      final general = ElEmployeePerms.presets.firstWhere((p) => p.id == 'general');
      final perms = {for (final k in ElEmployeePerms.earthlinkKeys) k: general.keys.contains(k)};
      expect(ElEmployeePerms.matching(perms)?.id, 'general');
      expect(ElEmployeePerms.matching({...perms, 'balance_reports.view': true}), isNull);
    });

    test('المدير كما كان: يكتب من أوّل لحظة بلا سؤال «من أنا»', () {
      PermissionsService.debugSet(isEmployee: false);
      final c = BalanceReportsController();
      expect([c.canWrite, c.employeeReadOnly], [true, false]);
      c.dispose();
    });
  });

  group('الاسم العربيّ بجانب اليوزر (٢٠ نوفمبر)', () {
    Subscriber sub(String u, String first, String last) => Subscriber.fromJson({'username': u, 'firstname': first, 'lastname': last});
    final subs = [
      sub('user0@net', 'علي', 'حسين'),
      sub('user1@net', 'user1@net', 'user1@net'), // الاسم = اليوزر ⇒ لا اسم
      sub('USER2@NET', 'محمد جاسم', ''), // حالة الأحرف تختلف ⇒ يطابق
      sub('user3@net', 'عبد الرحمن عبد الكريم عبد الأمير', 'الحسيني الموسوي البغدادي'),
      sub('user5@net', 'زينب', 'كاظم'), // تسديد دين
    ];
    Finder nameIn(String row) => find.descendant(of: k('bal-move-$row'), matching: k('bal-move-name'));
    String? nameOf(WidgetTester t, String row) => nameIn(row).evaluate().isEmpty ? null : t.widget<Text>(nameIn(row)).data;

    test('balanceSubName: الأوّل والأخير بلا ما يساوي اليوزر، وnull حين لا اسم غيره', () {
      expect(balanceSubName('user0@net', firstname: 'علي', lastname: 'حسين'), 'علي حسين');
      expect(balanceSubName('user1@net', firstname: 'user1@net', lastname: 'USER1@NET'), isNull);
      expect(balanceSubName('u', firstname: '  محمد   جاسم ', lastname: 'u'), 'محمد جاسم');
      expect(balanceSubName('u', firstname: null, lastname: ''), isNull);
      expect(balanceSubName('Ali', firstname: 'ali', lastname: null), isNull);
    });

    testWidgets('الحساب العاديّ: الاسم بعد اليوزر للتفعيل والتسديد، والقائمة مرّةً واحدة ولو زادت الحركات', (t) async {
      var loads = 0;
      var probes = 0;
      BalanceSubNames.probe = () async {
        probes++;
        return 0;
      };
      BalanceSubNames.loadAll = () async {
        loads++;
        return subs;
      };
      use(BalanceServer.ownerExample());
      await open(t);
      await tap(t, k('bal-detail-1'));
      expect(nameOf(t, 'a500'), 'علي حسين');
      expect(inKey('bal-move-a500', 'user0@net'), findsOneWidget, reason: 'العنوان يبقى اليوزر');
      expect(nameOf(t, 'a501'), isNull, reason: 'الاسم = اليوزر');
      expect(nameOf(t, 'a502'), 'محمد جاسم', reason: 'حالة الأحرف');
      expect(nameOf(t, 'a504'), isNull, reason: 'ليس بالقائمة');
      expect(nameOf(t, 'p905'), 'زينب كاظم', reason: 'تسديد الدين أيضاً');
      expect(nameOf(t, 'a503'), 'عبد الرحمن عبد الكريم عبد الأمير الحسيني الموسوي البغدادي');
      await tap(t, k('bal-moves-more'));
      await tap(t, k('bal-moves-more'));
      expect(rows(), findsNWidgets(47));
      expect([loads, probes], [1, 1], reason: 'القائمة المخبّأة مرّة، لا مع كلّ صفحة');
      await done(t);
    });

    testWidgets('الحساب الكبير: أسماء صفوف الصفحة وحدها من الساس (≤١٠٠، كلّ يوزرٍ مرّة) — لا القائمة الكاملة', (t) async {
      final asked = <List<String>>[];
      var loads = 0;
      BalanceSubNames.probe = () async => 89000;
      BalanceSubNames.loadAll = () async {
        loads++;
        return subs;
      };
      BalanceSubNames.lookup = (u) async {
        asked.add(List.of(u));
        final want = u.map((x) => x.toLowerCase()).toSet();
        return subs.where((s) => want.contains(s.username.toLowerCase())).toList();
      };
      use(BalanceServer.ownerExample());
      await open(t);
      await tap(t, k('bal-detail-1'));
      expect(nameOf(t, 'a500'), 'علي حسين');
      expect(nameOf(t, 'p905'), 'زينب كاظم');
      await tap(t, k('bal-moves-more'));
      await tap(t, k('bal-moves-more'));
      expect(loads, 0, reason: 'لا قائمة كاملة لحسابٍ كبير');
      final all = asked.expand((x) => x).toList();
      expect(asked.every((x) => x.length <= 100), isTrue);
      expect(all.length, all.toSet().length, reason: 'كلّ يوزرٍ يُسأل عنه مرّة');
      expect(all.toSet().length, 47);
      await done(t);
    });

    testWidgets('موظّفٌ بلا «عرض المشتركين»: لا طلب لقائمتهم ولا أسماء — اليوزر وحده', (t) async {
      var calls = 0;
      BalanceSubNames.probe = () async {
        calls++;
        return 0;
      };
      BalanceSubNames.loadAll = () async {
        calls++;
        return subs;
      };
      use(BalanceServer.ownerExample()
        ..employee = true
        ..empView = true);
      PermissionsService.debugSet(isEmployee: true, permissions: const {'balance_reports.view': true});
      await open(t);
      await tap(t, k('bal-detail-1'));
      expect(rows(), findsWidgets);
      expect(k('bal-move-name'), findsNothing);
      expect(calls, 0);
      await done(t);
      // وبالمفتاح: الأسماء تظهر له
      PermissionsService.debugSet(isEmployee: true, permissions: const {'balance_reports.view': true, 'subscribers.view': true});
      await open(t);
      await tap(t, k('bal-detail-1'));
      expect(nameOf(t, 'a500'), 'علي حسين');
      await done(t);
    });

    test('«كل الشركات» (شركةٌ مختارة): لا أسماء — قائمة التطبيق لشركة الجلسة لا المختارة', () async {
      var calls = 0;
      BalanceSubNames.probe = () async {
        calls++;
        return 0;
      };
      BalanceSubNames.loadAll = () async {
        calls++;
        return subs;
      };
      final n = BalanceSubNames(companyKey: 'speednet-iq:859');
      expect(n.enabled, isFalse);
      expect(await n.fill(['user0@net']), isFalse);
      expect([calls, n.of('user0@net')], [0, null]);
    });

    test('تعذّر القائمة: يُسأل عنها ثانيةً مع الصفحة التالية (لا تغيب الأسماء بعثرة شبكة)', () async {
      var loads = 0;
      BalanceSubNames.loadAll = () async {
        loads++;
        return loads == 1 ? null : subs;
      };
      final n = BalanceSubNames();
      expect(await n.fill(['user0@net']), isFalse);
      // اليوزرات نفسها (تحديث الصفحة نفسها) تُسأل ثانيةً — لا تبقى بلا أسماء لأنّها سُئل عنها مرّة
      expect(await n.fill(['user0@net']), isTrue);
      expect([loads, n.of('USER0@NET')], [2, 'علي حسين']);
      // القائمة عُرفت: لا طلب بعدها، والباقي منها
      expect(await n.fill(['user0@net', 'user5@net']), isFalse);
      expect([loads, n.of('user5@net')], [2, 'زينب كاظم']);
    });

    testWidgets('أضيق هاتف وخطٌّ ×1.2: الاسم الطويل كاملاً تحت اليوزر بلا قصّ، داخل سطره ولا يركب المبلغ', (t) async {
      BalanceSubNames.loadAll = () async => subs;
      for (final width in [320.0, 390.0]) {
        use(BalanceServer.ownerExample());
        await open(t, width: width, textScale: 1.2);
        await tap(t, k('bal-detail-1'));
        expect(t.takeException(), isNull, reason: '@$width');
        final name = nameIn('a503');
        expect(name, findsOneWidget);
        final w = t.widget<Text>(name);
        expect([w.maxLines, w.overflow], [null, null], reason: 'الاسم لا يُقصّ');
        final para = t.renderObject<RenderParagraph>(find.descendant(of: name, matching: find.byType(RichText)));
        expect(para.didExceedMaxLines, isFalse);
        final row = t.getRect(k('bal-move-a503'));
        final r = t.getRect(name);
        expect(r.left >= row.left - 0.5 && r.right <= row.right + 0.5, isTrue, reason: 'داخل سطره @$width: $r / $row');
        final amount = t.getRect(find.descendant(of: k('bal-move-a503'), matching: find.textContaining('د.ع')).first);
        expect(r.overlaps(amount), isFalse, reason: 'لا يركب المبلغ @$width');
        await done(t);
      }
    });
  });
}
