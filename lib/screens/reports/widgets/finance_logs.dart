import 'package:easy_localization/easy_localization.dart';

import '../../../api/reports_api.dart';
import '../../../core/util/format.dart';

/// حسابات حركات التقرير الماليّ من سطوره — مشتركةٌ بين الشاشة الحاليّة والتقرير الموحّد (٢٢ نوفمبر) كي لا تختلف قاعدةٌ بينهما.
/// نُقلت حرفيّاً من `FinancialReportScreen` (فلترة النوع، الأرقام من السطور، سطر الكلفة) بلا أيّ تغييرٍ في المعنى.
class FinanceLogs {
  FinanceLogs._();

  // مطلب المستخدم 2026-07-12: إشعارات الانتهاء الآلية ما تخص التقرير
  // المالي — نستثنيها قبل أي فلترة إضافية.
  static const excludedTypes = {
    'EXPIRY_NOTIFICATION',
    'NEAR_EXPIRY_NOTIFICATION',
    'AUTO_NOTIFICATION',
  };

  /// الحركات بلا الإشعارات الآليّة، ثمّ بأنواع [types] إن اختيرت (فارغ = الكلّ).
  static List<FinanceLog> filter(List<FinanceLog> logs, List<String>? types) {
    final base = logs.where((l) => !excludedTypes.contains(l.actionType.toUpperCase().trim()));
    if (types == null || types.isEmpty) return base.toList();
    return base.where((l) => types.any((t) => matchesType(l, t))).toList();
  }

  /// virtual types: SUBSCRIBER_ACTIVATE_CASH / _NON_CASH يتفكّكان بحسب
  /// description (مطابق backend FinanceReportController).
  static bool matchesType(FinanceLog l, String type) {
    final at = l.actionType.toUpperCase().trim();
    final desc = (l.actionDescription ?? '');
    final isNonCash = desc.contains('غير نقدي');
    final isCash = desc.contains('نقدي') && !isNonCash;
    switch (type) {
      case 'SUBSCRIBER_ACTIVATE_CASH':
        return (at == 'SUBSCRIBER_ACTIVATE' || (at == 'SUBSCRIBER_ADD' && desc.contains('تفعيل'))) && isCash;
      case 'SUBSCRIBER_ACTIVATE_NON_CASH':
        return (at == 'SUBSCRIBER_ACTIVATE' || (at == 'SUBSCRIBER_ADD' && desc.contains('تفعيل'))) && isNonCash;
      case 'ADMIN_EXPENSE':
        return at == 'ADMIN_EXPENSE' || at == 'EXPENSE_ADD';
      default:
        return at == type;
    }
  }

  /// نحسب KPIs من قائمة FinanceLog — يُستدعى عند تفعيل فلتر لعرض
  /// قيم مطابقة للفلتر بدلاً من فترة كاملة. عند "الكل" نستعمل قيم
  /// backend مباشرةً (أدقّ لأنها من الاستعلام الكامل بلا حد).
  /// [packageCost] كلفة السطور نفسها ([PackageCostKpis.forFilteredLogs]).
  static FinanceKPIs kpisFromLogs(List<FinanceLog> logs, {PackageCostKpis? packageCost}) {
    num activateCash = 0,
        activateNonCash = 0,
        partialUnpaid = 0,
        debtPay = 0,
        balanceDeduct = 0,
        balanceAdd = 0,
        balanceAddSales = 0,
        creditCash = 0,
        creditComp = 0,
        expenses = 0;
    int activationsCount = 0, extendCount = 0, expensesCount = 0;
    for (final l in logs) {
      final at = l.actionType.toUpperCase().trim();
      final desc = l.actionDescription ?? '';
      final isNonCash = desc.contains('غير نقدي');
      final isCash = desc.contains('نقدي') && !isNonCash;
      if (at == 'SUBSCRIBER_ACTIVATE' || (at == 'SUBSCRIBER_ADD' && desc.contains('تفعيل'))) {
        activationsCount++;
        if (isNonCash) {
          activateNonCash += l.amount;
        } else if (isCash) {
          activateCash += l.amount;
          // غير المدفوع من «نقدي جزئي» — يدخل المبيعات (صافي الربح بعد الكلفة)
          // كما يضمّه الخادم إلى «الديون الجديدة».
          partialUnpaid += l.partialUnpaid;
        }
      } else if (at == 'SUBSCRIBER_EXTEND') {
        extendCount++;
      } else if (at == 'DEBT_PAY') {
        debtPay += l.amount;
      } else if (at == 'BALANCE_DEDUCT') {
        balanceDeduct += l.amount;
      } else if (at == 'BALANCE_ADD' && l.isCredit) {
        // «إضافة رصيد» (١٧ نوفمبر — كالخادم): المقدّم نقداً نقدٌ محصَّل (داخل «تسديد الديون» كـdebt_pay_sum)، والتعويض يُطرح من
        // الصافي بعد الكلفة؛ وما قبله بلا نوع لا نقد — ولا شيء منها «إضافة دين».
        if (l.creditKind == 'cash') {
          debtPay += l.amount.abs();
          creditCash += l.amount.abs();
        } else if (l.creditKind == 'comp') {
          creditComp += l.amount.abs();
        }
      } else if (at == 'BALANCE_ADD') {
        balanceAdd += l.amount;
        // دين البيع وإنقاصه عند الإلغاء — ثمن مادّة لا «إضافة دين يدويّة» ([FinanceKPIs.manualDebtAddSum]).
        if (l.isSaleDebtLine) balanceAddSales += l.amount;
      } else if (at == 'EXPENSE_ADD' || at == 'ADMIN_EXPENSE') {
        expenses += l.amount;
        expensesCount++;
      }
    }
    return FinanceKPIs(
      activateCashSum: activateCash,
      activateNonCashSum: activateNonCash,
      debtPaySum: debtPay,
      balanceDeductSum: balanceDeduct,
      balanceAddSum: balanceAdd,
      expensesSum: expenses,
      expensesCount: expensesCount,
      activationsCount: activationsCount,
      extendCount: extendCount,
      packageCost: packageCost,
      partialUnpaidFromLogs: partialUnpaid,
      balanceAddSalesSum: balanceAddSales,
      creditCashSum: creditCash,
      creditCompSum: creditComp,
    );
  }

  /// ما دخل الصندوق نقداً من هذه الحركة — قاعدة «الإيراد النقدي» نفسها لسطرٍ واحد ([kpisFromLogs] ثمّ
  /// [FinanceKPIs.totalCashRevenue]): التفعيل النقديّ، وتسديد الدين والاستقطاع، والرصيد المقدّم نقداً. غيرها صفر.
  static num cashOf(FinanceLog l) => kpisFromLogs([l]).totalCashRevenue;

  /// سطر كلفة الباقة تحت الحركة — `null` لما لا كلفة له (تسديد، صرفية،
  /// المُزامَن من الساس، أو سطرٌ لم يرسل الخادم كلفته).
  static String? costLine(FinanceLog l) {
    final c = l.packageCost;
    if (c != null) {
      final line = 'reports.log_package_cost'.tr(namedArgs: {'amount': formatIQD(c)});
      return l.packageCostEstimated ? '$line · ${'reports.package_cost_estimated_tag'.tr()}' : line;
    }
    if (l.packageCostUnknown) return 'reports.log_package_cost_unknown'.tr();
    return null;
  }

  /// رقمٌ للتصدير بلا «.0» الزائدة (DECIMAL يصل من الخادم نصّاً كـ"20000.00").
  static String plainNumber(num v) => v == v.roundToDouble() ? v.round().toString() : v.toString();
}
