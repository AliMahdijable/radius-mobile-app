import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/merged_finance_api.dart';
import 'package:rad_mysvcs/api/reports_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/recent_activities.dart';
import 'package:rad_mysvcs/screens/reports/widgets/action_labels.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_log_tile.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/add_credit_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/movements_sheet.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «إضافة رصيد» نقداً أو تعويضاً بالتطبيق (١٧ نوفمبر — الخادم d23c25b + d5b537c، الويب e8cd323).
/// المالك: «اضمنها ضمن التقارير المالية وتقارير الارصده ايضا والحركه جاي تطلع اضافة دين وليس اضافة رصيد» + «الي تشوفه افضل سوي».
///   • النافذة: «نوع الرصيد» بلا اختيارٍ مسبق — الزرّ لا يرسل شيئاً حتى يُختار؛ ويُرسل credit_kind (cash|comp)؛ بلا قصٍّ على ٣٢٠
///     بخطٍّ مكبَّر ١٫٢.
///   • الأرقام: المقدّم نقداً داخلٌ أصلاً في debt_pay_sum (الخادم) ⇒ النقد كما يرسله؛ التعويض يُطرح من الصافي بعد الكلفة وحده؛ بلا
///     حقول الرصيد كلّ رقمٍ كما كان. «كل الشركات» تجمعها. فلتر النوع يحسبها من السطور كالخادم.
///   • الأسماء: «إضافة رصيد» / «(تعويض)» في سطر التقارير والتصدير و«سجل الحركات» (فلترٌ جديد) و«آخر النشاطات» — والباقي كما كان.
class _CkServer implements HttpClientAdapter {
  _CkServer(this.inner);
  final HttpClientAdapter inner;

  final posts = <(String, Map<String, dynamic>)>[];
  List<Map<String, dynamic>> statement = const [];

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final get = o.method.toUpperCase() == 'GET';
    final p = o.path;
    final ac = RegExp(r'^/api/v2/subscribers/(\w+)/add-credit$').firstMatch(p);
    if (!get && ac != null) {
      final body = o.data is Map ? Map<String, dynamic>.from(o.data as Map) : <String, dynamic>{};
      posts.add((p, body));
      return _json(200, {'success': true, 'data': {'new_balance': 10000, 'credit': true}});
    }
    if (get && p == '/api/reports/account-statement') {
      return _json(200, {'success': true, 'data': {'subscriber': {'username': 'ali.kareem'}, 'transactions': statement}});
    }
    if (get && p == '/api/v2/payment-voids/status') {
      return _json(200, {'success': true, 'enabled': false, 'items': []});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

/// أضيق هاتف بخطٍّ مكبَّر (قاعدة المالك: «لا نصّ يخرج ولا رقم يُقصّ» ٣٢٠–٤٨٠ × ١٫٢).
const _narrow = VisualDevice('_320', Size(320, 720), 2);

final _sub = Subscriber.fromJson({
  'idx': '132076',
  'username': 'ali.kareem',
  'firstname': 'علي',
  'lastname': 'كريم',
  'notes': '-15000',
});

/// نصوصٌ قُصّت (ellipsis/maxLines) داخل الشاشة — يجب ألّا يكون منها شيء ممّا أضافه هذا التغيير.
/// ⚠️ سطر المعاينة «الرصيد بعد الإضافة (دائن)» (SheetResultBanner المشترك، سطرٌ واحد) يُقصّ على ٣٢٠ بخطّ ١٫٢ **من قبل** (186
/// أيضاً) — خارج هذا التغيير، معروضٌ على المالك؛ فيُستثنى هنا باسمه وحده.
const _preexistingClip = {'الرصيد بعد الإضافة (دائن)', 'الدين بعد الإضافة'};
List<String> _clipped(WidgetTester t) {
  final out = <String>[];
  for (final e in find.byType(RichText).evaluate()) {
    final r = e.renderObject;
    if (r is RenderParagraph && r.didExceedMaxLines) out.add(r.text.toPlainText());
  }
  return out.where((x) => !_preexistingClip.contains(x)).toList();
}

void main() {
  setUpAll(visualSetUpAll);

  group('الأرقام', () {
    Map<String, dynamic> kpis({bool credit = false}) => {
          'payments_sum': 0,
          'debt_pay_sum': credit ? 85000 : 60000, // الخادم: المقدّم نقداً (25,000) داخلٌ فيه
          'balance_deduct_sum': 0,
          'activate_cash_sum': 210000,
          'balance_add_sum': 15000,
          'activate_non_cash_sum': 70000,
          'expenses_sum': 40000,
          'package_cost_sum': 196000,
          'cost_rows': 9,
          'cost_known_rows': 9,
          if (credit) ...{
            'credit_cash_sum': 25000,
            'credit_cash_count': 1,
            'credit_comp_sum': '7000.00',
            'credit_comp_count': 1,
          },
        };

    test('بلا حقول الرصيد: كلّ رقمٍ كما كان (والحقلان صفر)', () {
      final k = FinanceKPIs.fromJson(kpis(), includePackageCost: true);
      expect(k.creditCashSum, 0);
      expect(k.creditCompSum, 0);
      expect(k.profitAfterCost, 210000 + 70000 - 40000 - 196000);
      expect(k.netCash, 210000 + 60000 - 40000 - 15000);
    });

    test('بالرصيد: النقد كما يرسله الخادم (المقدّم داخله)، والتعويض يُطرح من الصافي بعد الكلفة وحده', () {
      final k = FinanceKPIs.fromJson(kpis(credit: true), includePackageCost: true);
      expect(k.creditCashSum, 25000);
      expect(k.creditCompSum, 7000);
      expect(k.totalCashRevenue, 210000 + 85000);
      expect(k.netCash, 210000 + 85000 - 40000 - 15000, reason: 'التعويض ليس نقداً — لا يمسّ الصافي النقديّ');
      expect(k.profitAfterCost, 210000 + 70000 - 40000 - 196000 - 7000);
      // بلا كلفة (سوبرنت، الموظّف): لا صافي بعد الكلفة أصلاً
      expect(FinanceKPIs.fromJson(kpis(credit: true)).profitAfterCost, isNull);
    });

    test('«كل الشركات»: الحقلان يُجمعان، والصافي بعد الكلفة مجموع صافي كلّ شركةٍ بقاعدتها', () {
      final a = FinanceKPIs.fromJson(kpis(credit: true), includePackageCost: true);
      final b = FinanceKPIs.fromJson({'activate_cash_sum': 1000, 'credit_comp_sum': 300, 'credit_cash_sum': 50, 'debt_pay_sum': 50});
      final s = MergedFinanceApi.sumKpis([a, b]);
      expect(s.creditCashSum, 25050);
      expect(s.creditCompSum, 7300);
      expect(s.profitAfterCost, a.profitAfterCost! + b.netCash);
    });

    test('سطر السجلّ: is_credit من الخادم ونوعه — والوصف «إضافة رصيد …» لما قبله؛ و«إضافة دين» ليس رصيداً', () {
      FinanceLog l(Map<String, dynamic> j) => FinanceLog.fromJson({'id': 1, 'created_at': '2026-11-17T10:00:00Z', ...j})!;
      final cash = l({'action_type': 'BALANCE_ADD', 'action_description': 'إضافة رصيد 25000 د.ع (مقدّم نقداً) للمشترك u5', 'amount': -25000, 'is_credit': true, 'credit_kind': 'cash'});
      expect((cash.isCredit, cash.creditKind), (true, 'cash'));
      final old = l({'action_type': 'BALANCE_ADD', 'action_description': 'إضافة رصيد 3000 د.ع للمشترك u8', 'amount': -3000});
      expect((old.isCredit, old.creditKind), (true, null));
      final debt = l({'action_type': 'BALANCE_ADD', 'action_description': 'إضافة دين 5000 د.ع للمشترك u4', 'amount': 5000});
      expect(debt.isCredit, isFalse);
    });

    test('التصدير (arabicActionLabel): «إضافة رصيد» و«(تعويض)» — وكشف دفتر ايرث لنك؛ والباقي كما كان', () {
      expect(arabicActionLabel('BALANCE_ADD', 'إضافة رصيد 25000 د.ع (مقدّم نقداً) للمشترك u5'), 'إضافة رصيد');
      expect(arabicActionLabel('BALANCE_ADD', 'إضافة رصيد 7000 د.ع (تعويض) للمشترك u6'), 'إضافة رصيد (تعويض)');
      expect(arabicActionLabel('DEBT_PAY', 'إضافة رصيد (مقدّم نقداً)'), 'إضافة رصيد');
      expect(arabicActionLabel('BALANCE_ADD', 'إضافة دين 5000 د.ع للمشترك u4'), 'إضافة دين');
      expect(arabicActionLabel('BALANCE_ADD', 'إلغاء بيع #12 — إنقاص دين 4000 د.ع'), 'إنقاص دين (إلغاء بيع)');
      expect(arabicActionLabel('DEBT_PAY', 'تسديد دين'), 'تسديد دين');
    });
  });

  group('نافذة «إضافة رصيد»', () {
    tearDown(visualTearDown);

    Future<_CkServer> open(WidgetTester t, {VisualDevice d = _narrow}) async {
      final server = _CkServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      t.platformDispatcher.textScaleFactorTestValue = 1.2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpVisual(t, d,
          home: (_) => Builder(
              builder: (c) => Scaffold(
                  body: Center(child: TextButton(onPressed: () => showAddCreditSheet(c, _sub), child: const Text('افتح'))))));
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 1);
      return server;
    }

    Future<void> submit(WidgetTester t) async {
      await t.ensureVisible(find.text('إضافة رصيد').last);
      await t.tap(find.text('إضافة رصيد').last);
      await settle(t, seconds: 1);
    }

    for (final (kind, label) in [('cash', 'استلمت نقداً'), ('comp', 'تعويض بلا نقد')]) {
      testWidgets('٣٢٠ بخطّ ١٫٢: لا اختيار ⇒ لا إرسال؛ «$label» ⇒ credit_kind=$kind — بلا قصٍّ ولا فيض', (t) async {
        final server = await open(t);
        expect(find.text('نوع الرصيد'), findsOneWidget);
        expect(find.text('استلمت نقداً'), findsOneWidget);
        expect(find.text('تعويض بلا نقد'), findsOneWidget);
        expect(find.textContaining('اختر: استلمت المبلغ'), findsOneWidget);
        await t.tap(find.text('25,000'));
        await settle(t, seconds: 1);
        // بلا نوعٍ مختار: الزرّ معطّل — لا نافذة تأكيد ولا طلب
        await submit(t);
        expect(find.text('تأكيد إضافة الرصيد'), findsNothing);
        expect(server.posts, isEmpty);

        await t.ensureVisible(find.text(label));
        await t.tap(find.text(label));
        await settle(t, seconds: 1);
        expect(find.textContaining(kind == 'cash' ? 'يدخل الصندوق' : 'لا نقد:'), findsOneWidget);
        expect(_clipped(t), isEmpty, reason: 'لا نصّ مقصوص على ٣٢٠ بخطّ ١٫٢');
        expect(t.takeException(), isNull);

        await submit(t);
        expect(find.text('تأكيد إضافة الرصيد'), findsOneWidget);
        expect(find.textContaining(kind == 'cash' ? 'استلمت المبلغ نقداً' : 'تعويض بلا نقد'), findsWidgets);
        await t.tap(find.text('تأكيد'));
        await settle(t, seconds: 2);
        expect(server.posts.single.$1, '/api/v2/subscribers/132076/add-credit');
        expect(server.posts.single.$2, {'amount': 25000.0, 'credit_kind': kind});
        await settle(t, seconds: 6);
      });
    }

    testWidgets('الداكن على هاتفٍ عاديّ: بلا استثناء', (t) async {
      await open(t, d: phoneDark);
      await t.tap(find.text('تعويض بلا نقد'));
      await settle(t, seconds: 1);
      expect(_clipped(t), isEmpty);
      expect(t.takeException(), isNull);
    });
  });

  group('الأسماء', () {
    tearDown(visualTearDown);

    testWidgets('سطر التقارير: المقدّم نقداً أخضر بلا سالب، والتعويض محايد — و«إضافة دين» كما كانت', (t) async {
      await visualSetUp(s1bSasOwner);
      await pumpVisual(t, phone,
          home: (_) => const Scaffold(
                body: Column(children: [
                  ReportLogTile(
                      actionType: 'BALANCE_ADD',
                      description: 'إضافة رصيد 25000 د.ع (مقدّم نقداً) للمشترك ali.kareem',
                      amount: -25000,
                      createdAt: '2026-11-17T10:20:00Z'),
                  ReportLogTile(
                      actionType: 'BALANCE_ADD',
                      description: 'إضافة رصيد 7000 د.ع (تعويض) للمشترك sara.net - عطل',
                      amount: -7000,
                      createdAt: '2026-11-17T09:40:00Z'),
                  ReportLogTile(
                      actionType: 'BALANCE_ADD',
                      description: 'إضافة دين 15000 د.ع للمشترك omar.fiber',
                      amount: 15000,
                      createdAt: '2026-11-17T09:10:00Z'),
                ]),
              ));
      await settle(t, seconds: 1);
      expect(find.text('إضافة رصيد'), findsOneWidget);
      expect(find.text('إضافة رصيد (تعويض)'), findsOneWidget);
      expect(find.text('إضافة دين'), findsOneWidget);
      expect(find.text('25,000 د.ع'), findsOneWidget, reason: 'نقدٌ داخل — بلا «-»');
      expect(find.text('7,000 د.ع'), findsOneWidget);
      expect(find.text('-15,000 د.ع'), findsOneWidget);
      expect(find.text('إنقاص دين'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('«سجل الحركات»: «إضافة رصيد» باسمها وفلترها — ساس وايرث لنك — و«إضافة دين» لا تضمّها', (t) async {
      final server = _CkServer(await visualSetUp(s1bSasOwner));
      server.statement = [
        {'id': 6, 'created_at': '2026-11-17T10:20:00Z', 'action_type': 'BALANCE_ADD', 'description': 'إضافة رصيد 25000 د.ع (مقدّم نقداً) للمشترك ali.kareem', 'amount': -25000, 'balance_after': 10000, 'admin_name': 'mahdi'},
        {'id': 5, 'created_at': '2026-11-16T18:00:00Z', 'action_type': 'DEBT_PAY', 'description': 'إضافة رصيد (تعويض) - عطل', 'amount': 7000, 'balance_after': -15000, 'admin_name': 'mahdi', 'is_credit': true, 'credit_kind': 'comp'},
        {'id': 4, 'created_at': '2026-11-16T12:00:00Z', 'action_type': 'BALANCE_ADD', 'description': 'إضافة دين 15000 د.ع للمشترك ali.kareem', 'amount': 15000, 'balance_after': -22000, 'admin_name': 'mahdi'},
        {'id': 3, 'created_at': '2026-11-14T12:00:00Z', 'action_type': 'BALANCE_DEDUCT', 'description': 'تسديد دين 10000 د.ع للمشترك ali.kareem', 'amount': 10000, 'balance_after': -7000, 'admin_name': 'mahdi'},
      ];
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phone,
          home: (_) => Builder(
              builder: (c) => Scaffold(
                  body: Center(child: TextButton(onPressed: () => showMovementsSheet(c, _sub), child: const Text('افتح'))))));
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 2);
      expect(find.text('إضافة رصيد'), findsNWidgets(2), reason: 'الفلتر + سطر المقدّم');
      expect(find.text('إضافة رصيد (تعويض)'), findsOneWidget);
      expect(find.text('إنقاص دين'), findsNothing);
      expect(find.text('تسديد دين'), findsOneWidget, reason: 'التسديد وحده — لا سطر الرصيد من دفتر ايرث لنك');

      await t.tap(find.text('إضافة رصيد').first);
      await t.pump();
      expect(find.text('إضافة رصيد (تعويض)'), findsOneWidget);
      expect(find.text('تسديد دين'), findsNothing);
      expect(find.textContaining('إضافة دين 15000'), findsNothing);

      await t.tap(find.text('إضافة دين').first);
      await t.pump();
      expect(find.textContaining('إضافة دين 15000'), findsOneWidget);
      expect(find.text('إضافة رصيد (تعويض)'), findsNothing);
      expect(t.takeException(), isNull);
      await settle(t, seconds: 2);
    });

    testWidgets('«آخر النشاطات»: «إضافة رصيد» بمبلغها — لا «إضافة دين»', (t) async {
      await visualSetUp(s1bSasOwner);
      final now = DateTime.now().toUtc().toIso8601String();
      final items = <Map<String, dynamic>>[
        {'id': 1, 'action_type': 'BALANCE_ADD', 'created_at': now, 'action_description': 'إضافة رصيد 25000 د.ع (مقدّم نقداً) للمشترك ali.kareem', 'target_name': 'ali.kareem', 'user_username': 'ali.kareem', 'admin_username': 'mahdi'},
        {'id': 2, 'action_type': 'BALANCE_ADD', 'created_at': now, 'action_description': 'إضافة رصيد 7000 د.ع (تعويض) للمشترك sara.net', 'target_name': 'sara.net', 'user_username': 'sara.net', 'admin_username': 'mahdi'},
        {'id': 3, 'action_type': 'BALANCE_ADD', 'created_at': now, 'action_description': 'إضافة دين 15000 د.ع للمشترك omar.fiber', 'target_name': 'omar.fiber', 'user_username': 'omar.fiber', 'admin_username': 'mahdi'},
      ];
      await pumpVisual(t, phone, home: (_) => Scaffold(body: SafeArea(child: SingleChildScrollView(child: RecentActivities(items: items)))));
      await settle(t, seconds: 1);
      expect(find.text('إضافة رصيد'), findsOneWidget);
      expect(find.text('إضافة رصيد (تعويض)'), findsOneWidget);
      expect(find.text('إضافة دين'), findsOneWidget);
      expect(find.text('25,000 د.ع'), findsOneWidget);
      expect(find.text('7,000 د.ع'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
