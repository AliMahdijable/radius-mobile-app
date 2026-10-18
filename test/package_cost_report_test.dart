import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/reports_api.dart';

/// «صافي الربح بعد كلفة الباقات» — عقد التطبيق مع `/api/reports/finance`.
///
/// قرار المالك ٢٠٢٦-١٠-١٨: «صافي الربح استثني فقط سوبرنت من سعر الباقات،
/// اما بقية الساسات لا طبّقها عليها كلّهن». الخادم يرسل الكلفة لمالك حسابٍ
/// على ساسٍ بعيد أو ايرث لنك وحده؛ والتطبيق:
///   • لا يقرؤها إلّا للمالك على حسابٍ تُطرح كلفته (حاجزٌ ثانٍ)،
///   • يُبقي صافي النقد كما كان (وفيه طرح «إضافة الدين»)،
///   • ويحسب «صافي الربح بعد كلفة الباقات» على أساس المبيعات:
///     المبيعات − المصاريف − الكلفة — صيغة الويب و`profit_after_cost` الخادم
///     (طرح كلفة كلّ البيع من النقد كان يُظهر خسارةً لمالكٍ رابح يبيع بالدين)،
///   • وبلا الحقول — سوبرنت والموظّف — أرقامه كما كانت حرفيّاً.
void main() {
  /// حمولة `data.kpis` كما يرسلها الخادم لمالك ايرث لنك (DECIMAL نصّاً).
  Map<String, dynamic> ownerKpis({Map<String, dynamic> extra = const {}}) => {
        'payments_sum': 0,
        'debt_pay_sum': '250000.00',
        'balance_add_sum': '30000.00',
        'balance_deduct_sum': 0,
        'activate_cash_sum': '1150000.00',
        'activate_non_cash_sum': 140000,
        'expenses_sum': 75000,
        'expenses_count': 3,
        'manager_debts_outstanding': 0,
        'activations_count': 42,
        'extend_count': 6,
        'package_cost_sum': '960000.00',
        // كما يرسلهما الخادم — والتطبيق يحسبهما من الأرقام نفسها (لا يقرؤهما):
        // المبيعات 1,150,000 + 140,000 = 1,290,000؛ الربح 1,290,000 − 75,000 − 960,000.
        'sales_sum': 1290000,
        'profit_after_cost': 255000,
        'cost_rows': 48,
        'cost_known_rows': 48,
        'cost_estimated_rows': 0,
        'cost_coverage': 1,
        'cost_has_estimates': false,
        ...extra,
      };

  /// الحمولة نفسها بلا حقول الكلفة — ما يصل لسوبرنت وللموظّف اليوم.
  Map<String, dynamic> plainKpis() => Map.of(ownerKpis())
    ..removeWhere((k, _) =>
        k.startsWith('cost_') ||
        k == 'package_cost_sum' ||
        k == 'sales_sum' ||
        k == 'profit_after_cost');

  group('isCostBearingAdminId — من تُطرح كلفته', () {
    test('سوبرنت (المعرّف العاري) مستثناة', () {
      expect(isCostBearingAdminId('2'), isFalse);
      expect(isCostBearingAdminId('2251'), isFalse);
    });

    test('شركات SAS4 البعيدة وايرث لنك مشمولة', () {
      expect(isCostBearingAdminId('jt:5136'), isTrue);
      expect(isCostBearingAdminId('speednet-iq:1429'), isTrue);
      expect(isCostBearingAdminId('earthlink:5'), isTrue);
      expect(isCostBearingAdminId(' JT:5136 '), isTrue);
    });

    test('ftth ساس SAS4 حقيقيّ فيُشمَل، والمشروع الوطنيّ ftth-iq خارج النطاق',
        () {
      expect(isCostBearingAdminId('ftth:12'), isTrue);
      expect(isCostBearingAdminId('ftth-iq:3'), isFalse);
      expect(isCostBearingAdminId('FTTH-IQ:3'), isFalse);
    });

    test('مجهولٌ أو مشوَّه ⇒ لا كلفة', () {
      expect(isCostBearingAdminId(null), isFalse);
      expect(isCostBearingAdminId(''), isFalse);
      expect(isCostBearingAdminId(':5'), isFalse);
    });
  });

  group('FinanceKPIs — الصافي', () {
    test('🚨 بلا حقول الكلفة (سوبرنت/الموظّف): الصافي كما كان حرفيّاً ولا ربح بعد كلفة', () {
      for (final include in [true, false]) {
        final k = FinanceKPIs.fromJson(plainKpis(), includePackageCost: include);
        expect(k.packageCost, isNull);
        // 1,400,000 − 75,000 − 30,000 (إضافة الدين ما زالت تُطرح)
        expect(k.netCash, 1295000);
        expect(k.profitAfterCost, isNull);
      }
    });

    test('المالك: صافي الربح بعد الكلفة على المبيعات، وصافي النقد كما كان', () {
      final k = FinanceKPIs.fromJson(ownerKpis(), includePackageCost: true);
      expect(k.totalCashRevenue, 1400000);
      expect(k.netCash, 1295000, reason: 'النقد − الصرفيات − إضافة الدين — لم يتغيّر');
      expect(k.packageCost!.sum, 960000);
      expect(k.salesSum, 1290000, reason: 'نقد التفعيلات + ديونها الجديدة');
      expect(k.profitAfterCost, 255000, reason: 'المبيعات − المصاريف − الكلفة');
    });

    test('🚨 لا من النقد: البيع بالدين كلّه ربحٌ بعد الكلفة لا خسارة', () {
      // مالكٌ باع 1,175,000 بالدين كلّه وحصّل 35,000 نقداً، والكلفة 781,000 (hrins، مراجعة ١٨ أكتوبر)
      final k = FinanceKPIs.fromJson({
        'activate_cash_sum': 0,
        'activate_non_cash_sum': 1175000,
        'debt_pay_sum': 35000,
        'expenses_sum': 0,
        'package_cost_sum': 781000,
      }, includePackageCost: true);
      expect(k.profitAfterCost, 394000);
      expect(k.netCash - k.packageCost!.sum, -746000, reason: 'ما كانت ستعرضه صيغة النقد');
    });

    test('🚨 الموظّف: الحقول تُسقَط ولو أرسلها الخادم خطأً', () {
      final k = FinanceKPIs.fromJson(ownerKpis(), includePackageCost: false);
      expect(k.packageCost, isNull);
      expect(k.profitAfterCost, isNull);
    });

    test('الافتراض بلا وسيط: لا كلفة (مستدعٍ لا يعرف المشاهد)', () {
      final k = FinanceKPIs.fromJson(ownerKpis());
      expect(k.packageCost, isNull);
    });

    test('الكلفة صفرٌ معروف ≠ غياب: تُعرض صفراً، والربح = المبيعات − المصاريف', () {
      final k = FinanceKPIs.fromJson(
        ownerKpis(extra: {'package_cost_sum': 0, 'cost_rows': 0, 'cost_known_rows': 0}),
        includePackageCost: true,
      );
      expect(k.packageCost, isNotNull);
      expect(k.packageCost!.sum, 0);
      expect(k.profitAfterCost, 1290000 - 75000);
    });

    test('🚨 profit_after_cost/sales_sum الخادم لا يُقرآن — الحساب من الأرقام نفسها', () {
      final k = FinanceKPIs.fromJson(
        ownerKpis(extra: {'profit_after_cost': 1, 'sales_sum': 2}),
        includePackageCost: true,
      );
      expect(k.profitAfterCost, 255000);
    });

    test('فلتر النوع: غير المدفوع من الجزئيّ (من السطور) يدخل المبيعات', () {
      const k = FinanceKPIs(
        activateCashSum: 50000, // نقد الجزئيّ
        activateNonCashSum: 35000,
        partialUnpaidFromLogs: 20000,
        expensesSum: 5000,
        packageCost: PackageCostKpis(sum: 40000, rows: 2, knownRows: 2),
      );
      expect(k.salesSum, 105000);
      expect(k.profitAfterCost, 60000);
    });

    test('رقمٌ مكسور (سالب/غير رقم/لانهائيّ) لا يُطرح من صافي المالك', () {
      for (final bad in [-5, '-5', 'abc', '', double.nan, double.infinity]) {
        final k = FinanceKPIs.fromJson(
          ownerKpis(extra: {'package_cost_sum': bad}),
          includePackageCost: true,
        );
        expect(k.packageCost, isNull, reason: 'package_cost_sum=$bad');
        expect(k.profitAfterCost, isNull);
      }
    });
  });

  group('PackageCostKpis — جودة الكلفة', () {
    test('عمليّاتٌ بلا كلفة + تقديريّة', () {
      final c = PackageCostKpis.fromKpis({
        'package_cost_sum': '2760000.00',
        'cost_rows': '150',
        'cost_known_rows': 138,
        'cost_estimated_rows': 9,
        'cost_has_estimates': true,
      })!;
      expect(c.sum, 2760000);
      expect(c.rows, 150);
      expect(c.missingRows, 12);
      expect(c.estimatedRows, 9);
      expect(c.hasEstimates, isTrue);
    });

    test('تغطيةٌ كاملة بلا تقديرات ⇒ لا تنبيه', () {
      final c = PackageCostKpis.fromKpis(ownerKpis())!;
      expect(c.missingRows, 0);
      expect(c.hasEstimates, isFalse);
    });

    test('علم التقدير من الخادم يكفي ولو غاب العدد', () {
      final c = PackageCostKpis.fromKpis(
          {'package_cost_sum': 10, 'cost_has_estimates': true})!;
      expect(c.estimatedRows, 0);
      expect(c.hasEstimates, isTrue);
    });

    test('عدّادٌ مشوَّه أو معروفٌ أكثر من الكلّ ⇒ لا «ناقص» سالب', () {
      final c = PackageCostKpis.fromKpis({
        'package_cost_sum': 10,
        'cost_rows': 3,
        'cost_known_rows': 7,
        'cost_estimated_rows': 'x',
      })!;
      expect(c.missingRows, 0);
      expect(c.estimatedRows, 0);
    });
  });

  group('FinanceLog — كلفة السطر', () {
    Map<String, dynamic> row(String type, {Map<String, dynamic> extra = const {}}) => {
          'id': 11,
          'action_type': type,
          'action_description': type == 'SUBSCRIBER_ADD' ? 'إضافة مع تفعيل' : 'وصف',
          'amount': 35000,
          'created_at': '2026-10-18T07:30:00.000Z',
          ...extra,
        };

    test('المالك: الكلفة ومصدرها', () {
      final l = FinanceLog.fromJson(
        row('SUBSCRIBER_EXTEND',
            extra: {'package_cost': '20000.00', 'package_cost_source': 'estimate'}),
        includePackageCost: true,
      )!;
      expect(l.packageCost, 20000);
      expect(l.packageCostEstimated, isTrue);
      expect(l.packageCostUnknown, isFalse);
    });

    test('🚨 الموظّف: لا كلفة ولا «غير معروفة»', () {
      final l = FinanceLog.fromJson(
        row('SUBSCRIBER_ACTIVATE', extra: {'package_cost': null}),
      )!;
      expect(l.packageCost, isNull);
      expect(l.packageCostSent, isFalse);
      expect(l.packageCostUnknown, isFalse);
    });

    test('null صريح لعمليّة بيع ⇒ غير معروفة بعد؛ والغياب لا يُفسَّر', () {
      final sent = FinanceLog.fromJson(
        row('SUBSCRIBER_ACTIVATE', extra: {'package_cost': null}),
        includePackageCost: true,
      )!;
      expect(sent.packageCostUnknown, isTrue);
      final absent =
          FinanceLog.fromJson(row('SUBSCRIBER_ACTIVATE'), includePackageCost: true)!;
      expect(absent.packageCostSent, isFalse);
      expect(absent.packageCostUnknown, isFalse);
    });

    test('لا «غير معروفة» لغير البيع ولا للسطر المُزامَن من الساس', () {
      final pay = FinanceLog.fromJson(
        row('DEBT_PAY', extra: {'package_cost': null}),
        includePackageCost: true,
      )!;
      expect(pay.isSale, isFalse);
      expect(pay.packageCostUnknown, isFalse);
      final synced = FinanceLog.fromJson(
        row('SUBSCRIBER_ACTIVATE', extra: {'package_cost': null, 'from_sas': 1}),
        includePackageCost: true,
      )!;
      expect(synced.fromSas, isTrue);
      expect(synced.packageCostUnknown, isFalse);
    });

    test('partial_unpaid يُقرأ (نصّاً أو رقماً)، وغيابه صفر', () {
      expect(FinanceLog.fromJson(row('SUBSCRIBER_ACTIVATE', extra: {'partial_unpaid': '15000.00'}))!.partialUnpaid, 15000);
      expect(FinanceLog.fromJson(row('SUBSCRIBER_ACTIVATE', extra: {'partial_unpaid': 0}))!.partialUnpaid, 0);
      expect(FinanceLog.fromJson(row('SUBSCRIBER_ACTIVATE'))!.partialUnpaid, 0);
    });

    test('from_sas كما يرسله MySQL (1/0) أو منطقيّاً', () {
      bool sas(Object? v) =>
          FinanceLog.fromJson(row('SUBSCRIBER_ACTIVATE', extra: {'from_sas': v}))!
              .fromSas;
      expect(sas(1), isTrue);
      expect(sas('1'), isTrue);
      expect(sas(true), isTrue);
      expect(sas(0), isFalse);
      expect(sas(null), isFalse);
    });

    test('«إضافة مع تفعيل» بيعٌ كتعريف activationLike في الخادم', () {
      expect(FinanceLog.fromJson(row('SUBSCRIBER_ADD'))!.isSale, isTrue);
      expect(FinanceLog.fromJson(row('SUBSCRIBER_EXTEND'))!.isSale, isTrue);
      expect(FinanceLog.fromJson(row('BALANCE_ADD'))!.isSale, isFalse);
    });

    test('كلفةٌ سالبة أو غير رقميّة لا تُقرأ', () {
      for (final bad in [-1, 'abc']) {
        final l = FinanceLog.fromJson(
          row('SUBSCRIBER_ACTIVATE', extra: {'package_cost': bad}),
          includePackageCost: true,
        )!;
        expect(l.packageCost, isNull, reason: '$bad');
      }
    });
  });

  group('فلتر النوع — الكلفة من السطور', () {
    FinanceLog log(String type,
            {Object? cost, bool sent = true, String? source, int fromSas = 0}) =>
        FinanceLog.fromJson(
          {
            'id': type.hashCode,
            'action_type': type,
            'action_description': 'وصف',
            'amount': 35000,
            'created_at': '2026-10-18T07:30:00.000Z',
            'from_sas': fromSas,
            if (sent) 'package_cost': cost,
            if (source != null) 'package_cost_source': source,
          },
          includePackageCost: true,
        )!;

    final period = PackageCostKpis.fromKpis(ownerKpis())!;

    test('بلا كلفةٍ للفترة ⇒ لا شيء (سوبرنت/الموظّف كما كانا)', () {
      final r = PackageCostKpis.forFilteredLogs(
        period: null,
        allLogs: [log('SUBSCRIBER_ACTIVATE', cost: 20000)],
        filtered: [log('SUBSCRIBER_ACTIVATE', cost: 20000)],
      );
      expect(r.cost, isNull);
      expect(r.unavailable, isFalse);
    });

    test('المجموع من سطور البيع المفلترة وحدها، والمُزامَن خارجها', () {
      final logs = [
        log('SUBSCRIBER_ACTIVATE', cost: 20000),
        log('SUBSCRIBER_EXTEND', cost: 15000, source: 'estimate'),
        log('SUBSCRIBER_ACTIVATE', cost: null),
        log('SUBSCRIBER_ACTIVATE', cost: null, fromSas: 1),
        log('DEBT_PAY', sent: false),
      ];
      final r = PackageCostKpis.forFilteredLogs(
          period: period, allLogs: logs, filtered: logs);
      expect(r.unavailable, isFalse);
      expect(r.cost!.sum, 35000);
      expect(r.cost!.rows, 3, reason: 'تفعيلان وتمديد — لا التسديد ولا المُزامَن');
      expect(r.cost!.knownRows, 2);
      expect(r.cost!.missingRows, 1);
      expect(r.cost!.estimatedRows, 1);
    });

    test('فلترٌ بلا بيع ⇒ كلفة صفر (لا شيء يُطرح)', () {
      final logs = [log('SUBSCRIBER_ACTIVATE', cost: 20000), log('DEBT_PAY', sent: false)];
      final r = PackageCostKpis.forFilteredLogs(
          period: period, allLogs: logs, filtered: [logs[1]]);
      expect(r.cost!.sum, 0);
      expect(r.cost!.rows, 0);
      expect(r.cost!.missingRows, 0);
    });

    test('🚨 خادمٌ لا يرسل كلفة السطر ⇒ «غير متاحة» لا صفرٌ كاذب', () {
      final logs = [
        log('SUBSCRIBER_ACTIVATE', sent: false),
        log('SUBSCRIBER_EXTEND', sent: false),
      ];
      final r = PackageCostKpis.forFilteredLogs(
          period: period, allLogs: logs, filtered: logs);
      expect(r.cost, isNull);
      expect(r.unavailable, isTrue);
    });

    test('🚨 السطور بلغت سقف الخادم (1000 حركة) ⇒ «غير متاحة» لا مجموعٌ جزئيّ صامت', () {
      final many = [
        for (var i = 0; i < PackageCostKpis.recentLogsServerCap; i++)
          log('SUBSCRIBER_ACTIVATE', cost: 1000),
      ];
      final expenses = [
        for (var i = 0; i < 5; i++)
          FinanceLog.fromJson({'id': 'expense_$i', 'action_type': 'ADMIN_EXPENSE', 'amount': 1, 'created_at': '2026-10-18'}, includePackageCost: true)!,
      ];
      final r = PackageCostKpis.forFilteredLogs(
          period: period, allLogs: [...many, ...expenses], filtered: many.take(3));
      expect(r.cost, isNull);
      expect(r.unavailable, isTrue);
      // دون السقف (الصرفيات لا تُعدّ) ⇒ يُجمع كالمعتاد
      final under = many.take(PackageCostKpis.recentLogsServerCap - 1).toList();
      final r2 = PackageCostKpis.forFilteredLogs(
          period: period, allLogs: [...under, ...expenses], filtered: under.take(3));
      expect(r2.unavailable, isFalse);
      expect(r2.cost!.sum, 3000);
    });

    test('فترةٌ بلا كلفةٍ معروفة أصلاً ⇒ الناقص يُعدّ (صادق)', () {
      final none = PackageCostKpis.fromKpis({
        'package_cost_sum': 0,
        'cost_rows': 2,
        'cost_known_rows': 0,
      });
      final logs = [log('SUBSCRIBER_ACTIVATE', sent: false)];
      final r = PackageCostKpis.forFilteredLogs(
          period: none, allLogs: logs, filtered: logs);
      expect(r.unavailable, isFalse);
      expect(r.cost!.missingRows, 1);
    });
  });
}
