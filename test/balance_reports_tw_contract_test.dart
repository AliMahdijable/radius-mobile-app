import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
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

/// «تقارير الأرصدة» — «بالحوالات — لم تُسحب» (٢٦ نوفمبر — المالك: «… وماينحسبن بالمال المستلم لان هنه بعدهن بالماستر الى ان
/// يسحبهن او ينقر سحب فردي او سحب الكل للصندوق يلا ينزلن خذ مثال شحن الارصده» ثمّ «نعم موافق»).
/// `balance_reports/server_contract_tw.json` **ولّده كود الخادم نفسه** (server/balanceReports.js بحزمة 1126twbal ومساراته كما هي)
/// على حركاتٍ بحوالات وسحوباتٍ للصندوق بقاعدةٍ في الذاكرة — لا يُكتب باليد (المولّد: `~/kits/balance_reports/gen_tw_contract.js
/// <شجرة الخادم>` على الخادم، ونسخته `~/release_work/balance_reports/contract/`).
/// السيناريو (٢٣–٢٥ تشرين الثاني): الفترة ١ (300,000 — بانتظار الإغلاق): ماستر 100 مسحوبٌ كلّه، زين كاش 50 سُحب منه 30، جزئيّ
/// بـ«آسيا حوالة» 30 سُحب منه 10، كاش 35، دينٌ 25 تسدّد بماستر ثمّ سُحب، دينٌ 40 تسدّد بماستر لم يُسحب، دينٌ 50 تسدّد منه 20 بزين
/// كاش لم يُسحب؛ وسحبُ زين كاش 5,000 قبل أيّ استلامٍ بها («بلا مقابل»). الفترة ٢ (100,000 — الجارية): ماستر 45 لم يُسحب، وكاش 30.
void main() {
  final tw = jsonDecode(File('test/balance_reports/server_contract_tw.json').readAsStringSync()) as Map<String, dynamic>;
  final base = jsonDecode(File('test/balance_reports/server_contract.json').readAsStringSync()) as Map<String, dynamic>;
  final overviewJson = (tw['overview'] as Map)['data'] as Map<String, dynamic>;
  Map<String, dynamic> detailJson(int id) => ((tw['details'] as Map)['$id'] as Map)['data'] as Map<String, dynamic>;
  final nowMs = tw['now_ms'] as int;

  group('النماذج تقرأ مفاتيح الحوالات من ردّ الخادم الحقيقيّ', () {
    test('الفترتان والإجماليّات: transfers_pending بمجموعه ولكلّ طريقة، totals.transfers_pending، quality.tw_unmatched — والأرقام باليد', () {
      final o = BalanceOverview.fromJson(overviewJson)!;
      expect(o.periods.map((p) => p.state).toList(), [BalanceState.running, BalanceState.waiting]);
      final p2 = o.periods.first, p1 = o.periods.last;
      // المحصَّل = الكاش + ما سُحب للصندوق وحده: 100 + 30 + 10 + 35 = 175 نقداً، و25 تسديدٌ مسحوب ⇒ 200 من 300؛ الباقي 100 كلّه ينتظر السحب
      expect([p1.amount, p1.cashNow, p1.paidIn, p1.collected, p1.remaining, p1.canClose], [300000, 175000, 25000, 200000, 100000, false]);
      expect(p1.transfersPending!.sum, 100000);
      expect([for (final v in p1.transfersPending!.byVia) (v.via, v.name, v.label, v.sum)],
          [('zaincash', null, 'زين كاش', 40000.0), ('other', 'آسيا حوالة', 'آسيا حوالة', 20000.0), ('master', null, 'ماستر', 40000.0)]);
      expect([p2.amount, p2.collected, p2.remaining, p2.transfersPending!.sum], [100000, 30000, 70000, 45000]);
      final periods = (overviewJson['periods'] as List).cast<Map<String, dynamic>>();
      for (var i = 0; i < periods.length; i++) {
        final t = periods[i]['transfers_pending'] as Map;
        expect(t.keys.toSet(), {'sum', 'by_via'});
        final p = o.periods[i].transfersPending!;
        expect(p.sum, (t['sum'] as num).toDouble());
        final bv = (t['by_via'] as List).cast<Map>();
        expect(p.byVia.length, bv.length);
        for (var k = 0; k < bv.length; k++) {
          expect(bv[k].keys.toSet().difference({'via', 'name', 'label', 'sum'}), isEmpty, reason: 'مفتاحٌ جديد لطريقةٍ بلا قرار');
          expect([p.byVia[k].via, p.byVia[k].name, p.byVia[k].label, p.byVia[k].sum], [bv[k]['via'], bv[k]['name'], bv[k]['label'], (bv[k]['sum'] as num).toDouble()]);
        }
      }
      final totals = overviewJson['totals'] as Map;
      final q = overviewJson['quality'] as Map;
      expect(o.transfersPendingTotal, (totals['transfers_pending'] as num).toDouble());
      expect(o.transfersPendingTotal, 145000, reason: '100 + 45');
      expect(o.twUnmatched, (q['tw_unmatched'] as num).toDouble());
      expect(o.twUnmatched, 5000);
      expect(o.qualityNotes, contains('سُحب 5,000 من رصيد الحوالات بلا حوالةٍ نعرفها — لم يُحسب لأيّ فترة'));
      // العقد بلا حوالات (خادمٌ أقدم أو صفحةٌ بلا حوالة): لا سطر ولا صفرٌ ظاهر
      final plain = BalanceOverview.fromJson((base['overview'] as Map)['data'])!;
      expect(plain.periods.every((p) => p.transfersPending == null && balanceTwPendingLine(p) == null), isTrue);
      expect([plain.transfersPendingTotal, plain.twUnmatched], [0, 0]);
      expect(plain.qualityNotes.any((x) => x.contains('الحوالات')), isFalse);
    });

    test('النصوص: سطر الفترة، الطرق، وتنبيه «انتهت/نفد» يذكر ما ينتظر السحب من المتبقّي', () {
      final o = BalanceOverview.fromJson(overviewJson)!;
      final p2 = o.periods.first, p1 = o.periods.last;
      expect(balanceTwPendingLine(p2), 'بالحوالات — لم تُسحب 45,000');
      expect(balanceTwPendingLine(p1), 'بالحوالات — لم تُسحب 100,000');
      expect(balanceTwPendingParts(p1.transfersPending!), 'زين كاش 40,000 · آسيا حوالة 20,000 · ماستر 40,000');
      expect(balanceBanner(p1, null)!.text, 'انتهت هذه الفترة ولم يكتمل المبلغ — المتبقّي 100,000 د.ع — منه 100,000 د.ع بالحوالات لم تُسحب');
      expect(balanceBanner(p2, 5000)!.text, 'نفد رصيدك ولم يكتمل المبلغ — المتبقّي 70,000 د.ع — منه 45,000 د.ع بالحوالات لم تُسحب');
      expect(balanceBanner(p2, 120000), isNull);
      // ما ينتظر السحب لا يتجاوز المتبقّي في التنبيه
      final big = BalancePeriod.fromJson({...(overviewJson['periods'] as List).first as Map, 'transfers_pending': {'sum': 90000, 'by_via': []}})!;
      expect(balanceBanner(big, 0)!.text, endsWith('— منه 70,000 د.ع بالحوالات لم تُسحب'));
      // بلا حوالات: التنبيه كما كان حرفاً
      final plain = BalanceOverview.fromJson((base['overview'] as Map)['data'])!;
      final waiting = plain.periods.firstWhere((p) => p.state == BalanceState.waiting);
      expect(balanceBanner(waiting, null)!.text, 'انتهت هذه الفترة ولم يكتمل المبلغ — المتبقّي ${balanceIqd(waiting.remaining)}');
    });

    test('الحركات: tw_pending / tw_at_ms / paid_tw_pending بقرّائها، وكلّ مفتاحٍ معروف', () {
      const actKnown = {
        'key', 'kind', 'at_ms', 'sub', 'username', 'package', 'price', 'pay', 'cash', 'debt', 'remaining', 'debt_state', 'turned', //
        'paid_in', 'paid_late', 'written_off', 'untracked', 'excess', 'last_paid_at_ms', 'after_close', 'by', 'via', 'via_name', //
        'tw_pending', 'tw_at_ms', 'paid_tw_pending',
      };
      const payKnown = {'key', 'kind', 'at_ms', 'sub', 'username', 'amount', 'after_close', 'advance', 'by', 'via', 'via_name', 'tw_pending', 'tw_at_ms'};
      var twActs = 0, twAt = 0, twPaid = 0, twPays = 0;
      for (final pj in (overviewJson['periods'] as List).cast<Map>()) {
        final dj = detailJson(pj['id'] as int);
        final page = BalancePeriodPage.fromJson(dj)!;
        final items = ((dj['movements'] as Map)['items'] as List).cast<Map<String, dynamic>>();
        expect(page.items.length, items.length, reason: 'لا حركة تسقط عند القراءة');
        expect(page.period.transfersPending!.sum, (pj['transfers_pending'] as Map)['sum'], reason: 'فترة التفاصيل = فترة اللوحة');
        for (var i = 0; i < items.length; i++) {
          final j = items[i];
          final m = page.items[i];
          expect(m.key, j['key']);
          switch (j['kind']) {
            case 'activate':
              m as BalanceActMove;
              expect(j.keys.toSet().difference(actKnown), isEmpty, reason: 'مفتاح تفعيلٍ جديد من الخادم بلا قرار');
              expect([m.twPending, m.twAtMs, m.paidTwPending], [(j['tw_pending'] as num? ?? 0).toDouble(), j['tw_at_ms'], (j['paid_tw_pending'] as num? ?? 0).toDouble()], reason: '${j['key']}');
              expect([m.turnedCash, m.turnedProfit], [j['turned'] == 'cash', j['turned'] == 'profit'], reason: '${j['key']}');
              expect([m.via, m.viaName], [j['via'], j['via_name']]);
              if (m.twPending > 0) twActs++;
              if (m.twAtMs != null) twAt++;
              if (m.paidTwPending > 0) twPaid++;
            case 'payment':
              m as BalancePayMove;
              expect(j.keys.toSet().difference(payKnown), isEmpty, reason: 'مفتاح تسديدٍ جديد من الخادم بلا قرار');
              expect([m.twPending, m.twAtMs], [j['tw_pending'] == true, j['tw_at_ms']], reason: '${j['key']}');
              if (m.twPending) twPays++;
              if (m.twAtMs != null) twAt++;
            default:
              fail('نوع حركةٍ غير متوقّع هنا: ${j['kind']}');
          }
        }
      }
      // زين كاش وآسيا (بعضها) وماستر الفترة ٢ لم تُسحب؛ ماستر 100 وزين كاش وآسيا (بعضها) وتسديد 25 سُحبت؛ دينان سُدّدا بحوالةٍ لم تُسحب
      expect([twActs, twAt, twPaid, twPays], [3, 4, 2, 2]);
    });

    test('علامة الدين: تسدّد بحوالةٍ لم تُسحب، وبعضه بها، والمسحوبة «كان دين وتسدّد» — وتسديدٌ عاديّ بلا الحقول كما كان', () {
      final page = BalancePeriodPage.fromJson(detailJson(1))!;
      BalanceActMove act(String key) => page.items.firstWhere((m) => m.key == key) as BalanceActMove;
      final paidTw = balanceDebtNote(act('a1003'), nowMs: nowMs)!;
      expect(paidTw.text, startsWith('كان دين وتسدّد بحوالة — لم تُسحب بعد — '));
      expect(paidTw.tone, BalanceTone.warning);
      expect(balanceDebtNote(act('a1009'), nowMs: nowMs)!.text, 'تسدّد منه 20,000 · باقي 30,000', reason: 'المعلّق داخل «تسدّد منه»');
      final withdrawn = balanceDebtNote(act('a1006'), nowMs: nowMs)!;
      expect(withdrawn.text, startsWith('كان دين وتسدّد — '));
      expect(withdrawn.tone, BalanceTone.success);
      expect(balanceDebtNote(act('a1002'), nowMs: nowMs), isNull, reason: 'تفعيلٌ نقديّ بلا دين');
      // تسدّد بعضه نقداً قبل الإغلاق وبعضه بحوالةٍ معلّقة ⇒ «كان دين وتسدّد» (دخل منه شيءٌ «المحصَّل»)
      final mixed = BalanceMove.fromJson({...detailItem(detailJson(1), 'a1003'), 'turned': 'cash', 'paid_in': 10000, 'paid_tw_pending': 30000}) as BalanceActMove;
      expect(balanceDebtNote(mixed, nowMs: nowMs)!.text, startsWith('كان دين وتسدّد — '));
    });
  });

  group('الشاشتان تعرضان الحوالات من الردّ الحقيقيّ', () {
    final server = {...base, 'overview': tw['overview'], 'details': tw['details']};
    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      PermissionsService.debugReset();
      PermissionsService.debugSet(isEmployee: false);
      BalanceReportsState.reset();
      ApiClient.dio.httpClientAdapter = BalanceContractServer(server);
    });
    tearDown(PermissionsService.debugReset);

    Widget app(Widget child) => EasyLocalization(
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
    String rich(WidgetTester t, String key) {
      final w = t.widget<Text>(k(key));
      return w.data ?? w.textSpan!.toPlainText();
    }

    Future<void> tap(WidgetTester t, Finder f) async {
      await t.ensureVisible(f);
      await t.pump();
      await t.tap(f);
      await settle(t);
    }

    for (final width in [400.0, 320.0]) {
      testWidgets('الصفحة ($width): سطر «بالحوالات — لم تُسحب» تحت المحصَّل وفي تفصيله، والمحصَّل بلا الحوالة', (t) async {
        t.view.physicalSize = Size(width, 3600);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(app(const BalanceReportsScreen()));
        await settle(t);
        expect(t.takeException(), isNull);
        expect(t.widget<Text>(k('bal-amount')).data, '100,000 د.ع');
        expect(rich(t, 'bal-tw-pending'), 'بالحوالات — لم تُسحب 45,000 — تدخل «المحصَّل» حين تسحبها للصندوق');
        expect(inKey('bal-stat-collected', '30,000 د.ع'), findsOneWidget);
        expect(inKey('bal-stat-collected', 'بالحوالات — لم تُسحب 45,000'), findsOneWidget);
        expect(inKey('bal-stat-remaining', '70,000 د.ع'), findsOneWidget);
        expect(find.textContaining('سُحب 5,000 من رصيد الحوالات بلا حوالةٍ نعرفها'), findsOneWidget);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 4));
      });

      testWidgets('تفاصيل الفترة ١ ($width): الخلاصة بما ينتظر السحب ولكلّ طريقة، والحركات بحالها', (t) async {
        t.view.physicalSize = Size(width, 4600);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(app(const BalanceReportsScreen()));
        await settle(t);
        await tap(t, find.descendant(of: k('bal-period-1'), matching: find.byType(InkWell)).first);
        expect(t.takeException(), isNull);
        expect(inKey('bal-sum-collected', '200,000 د.ع'), findsOneWidget);
        expect(inKey('bal-sum-tw-pending', '100,000 د.ع'), findsOneWidget);
        expect(inKey('bal-sum-tw-pending', 'بالحوالات — لم تُسحب (خارج المحصَّل)'), findsOneWidget);
        expect(t.widget<Text>(k('bal-sum-tw-parts')).data, 'زين كاش 40,000 · آسيا حوالة 20,000 · ماستر 40,000 — تدخل «المحصَّل» حين تسحبها للصندوق');
        expect(find.byType(BalanceMoveRow), findsNWidgets(10));
        final statuses = t.widgetList<BalanceMoveStatus>(k('bal-move-status')).map((c) => c.text).toList();
        expect(statuses.where((x) => x == 'بالحوالة — لم تُسحب بعد (خارج «المحصَّل»)').length, 3, reason: 'تسديدان معلّقان وتفعيلٌ نقديّ بزين كاش');
        expect(statuses.where((x) => x.startsWith('كان دين وتسدّد بحوالة — لم تُسحب بعد — ')).length, 1);
        expect(statuses.where((x) => x == 'تسدّد منه 20,000 · باقي 30,000').length, 1);
        expect(statuses.where((x) => x == 'أُضيف إلى «المحصَّل»').length, 1, reason: 'التسديد المسحوب');
        expect(find.textContaining('حوالة لم تُسحب 20,000'), findsNWidgets(2));
        expect(find.textContaining('سُحبت للصندوق '), findsNWidgets(4));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 4));
      });
    }
  });
}

Map<String, dynamic> detailItem(Map<String, dynamic> detail, String key) =>
    Map<String, dynamic>.from((((detail['movements'] as Map)['items'] as List).cast<Map>()).firstWhere((m) => m['key'] == key));
