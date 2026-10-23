import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/bidi.dart';
import 'api_client.dart';
import 'archive_info.dart';

/// ============================================================
/// Reports API — موحّد لكل التقارير الـ8 في v2 web:
///   • financial — /api/reports/finance
///   • activations / daily_activations — /api/activities
///   • activity_log — /api/activities (filter شامل)
///   • sessions — /api/v2/sessions
///   • account_statement — /api/reports/account-statement
///   • expenses + manager_debts — الـAPIs الموجودة أصلاً في
///     expenses_api / manager_debts_api، نُحيل لها (لا duplication).
///
/// كل دالة ترجع record مع `ok` + الـdata + رسالة خطأ ودودة. الـUI
/// يعرض إما الـdata أو الخطأ. لا exception trapping يدوي.
/// ============================================================

// ─────────── Financial ───────────

/// حسابٌ تُطرح من صافيه كلفة الباقات: معرّفٌ مؤهَّل `<code>:<id>` (شركات SAS4
/// البعيدة وايرث لنك) — لا العاري (سوبرنت، الساس الأصليّ) ولا المشروع
/// الوطنيّ `ftth-iq:` (خارج النطاق). و`ftth:` ساس SAS4 حقيقيّ فيُشمَل.
/// مطابقٌ لـ`packageCosts.isCostBearingAdminId` في الخادم.
bool isCostBearingAdminId(String? adminId) {
  final s = (adminId ?? '').trim().toLowerCase();
  final i = s.indexOf(':');
  return i > 0 && s.substring(0, i) != 'ftth-iq';
}

/// كلفة الباقات — ما يدفعه الوكيل للساس (أو لايرث لنك) عن كلّ تفعيلٍ وتمديد.
///
/// قرار المالك ٢٠٢٦-١٠-١٨: «صافي الربح» يطرحها لكلّ الساسات البعيدة
/// ولايرث لنك، وسوبرنت (الساس الأصليّ) وحدها مستثناة.
///
/// ⚠️ الخادم وحده يحسبها ويقرّر من يراها: يرسل حقولها في `kpis` لمالك
/// الحساب حين يكون التقرير جاهزاً، ولا يرسلها لسوبرنت ولا للموظّف. فغيابها
/// يعني «لا كلفة تُعرض» — **لا** «الكلفة صفر»، ولا يُخترع منها شيءٌ هنا.
@immutable
class PackageCostKpis {
  const PackageCostKpis({
    required this.sum,
    this.rows = 0,
    this.knownRows = 0,
    this.estimatedRows = 0,
    bool hasEstimates = false,
  }) : _hasEstimates = hasEstimates;

  /// مجموع الكلفة المسجّلة (د.ع).
  final num sum;

  /// عمليّات البيع في الفترة: تفعيلٌ وتمديد، بلا ما زامنّاه من الساس.
  final int rows;

  /// منها ما سُجّلت كلفته.
  final int knownRows;

  /// منها كلفةٌ تقديريّة لم تؤكّدها الشركة بعد.
  final int estimatedRows;

  final bool _hasEstimates;

  /// عمليّاتٌ بلا كلفةٍ مسجّلة — المجموع ينقصها، فالصافي الحقيقيّ أقلّ.
  int get missingRows => rows > knownRows ? rows - knownRows : 0;

  bool get hasEstimates => _hasEstimates || estimatedRows > 0;

  /// كلفة حركاتٍ بعينها من كلفة كلّ سطرٍ كما أرسلها الخادم — يحتاجها فلتر
  /// النوع، فأرقامه تُحسب من السطور لا من الخادم.
  static PackageCostKpis fromLogs(Iterable<FinanceLog> logs) {
    num sum = 0;
    var rows = 0, known = 0, estimated = 0;
    for (final l in logs) {
      if (!l.isSale || l.fromSas) continue;
      rows++;
      final c = l.packageCost;
      if (c == null) continue;
      known++;
      sum += c;
      if (l.packageCostSource == 'estimate') estimated++;
    }
    return PackageCostKpis(
      sum: sum,
      rows: rows,
      knownRows: known,
      estimatedRows: estimated,
    );
  }

  /// سقف الخادم لسطور الحركات في `recentLogs` (FinanceReportController و
  /// financeSummary لايرث لنك: `Math.min(limit_logs, 1000)`) — الصرفيات تُلحق
  /// فوقه. بلوغه يعني أنّ السطور مقطوعة: مجموعٌ منها لا يمثّل الفترة.
  static const recentLogsServerCap = 1000;

  /// الكلفة تحت فلتر النوع.
  ///
  /// [period] كلفة الفترة من الخادم (`null` = لا كلفة تُعرض أصلاً)،
  /// و[allLogs] السطور كلّها، و[filtered] ما بقي بعد الفلتر.
  ///
  /// `unavailable` = لا يصحّ جمعها من السطور، فالشاشة تقول «أزل الفلتر» بدل
  /// رقمٍ كاذب: (أ) للفترة كلفةٌ مسجّلة لكنّ ولا سطراً يحمل حقلها (خادمٌ لا
  /// يرسلها لكلّ سطر)، أو (ب) السطور بلغت سقف الخادم فهي مقطوعة — المجموع منها
  /// جزئيّ بلا علامة (مراجعة ١٨ أكتوبر).
  static ({PackageCostKpis? cost, bool unavailable}) forFilteredLogs({
    required PackageCostKpis? period,
    required List<FinanceLog> allLogs,
    required Iterable<FinanceLog> filtered,
  }) {
    if (period == null) return (cost: null, unavailable: false);
    final perRow = period.knownRows == 0 ||
        allLogs.any((l) => l.packageCostSent || l.packageCost != null);
    if (!perRow) return (cost: null, unavailable: true);
    final activityRows =
        allLogs.where((l) => l.actionType.toUpperCase().trim() != 'ADMIN_EXPENSE').length;
    if (activityRows >= recentLogsServerCap) return (cost: null, unavailable: true);
    return (cost: fromLogs(filtered), unavailable: false);
  }

  /// من `data.kpis` — `null` حين لا يرسل الخادم الكلفة، أو يرسلها برقمٍ لا
  /// يُصدَّق (سالب أو غير رقم): رقمٌ مكسور لا يُطرح من صافي المالك.
  static PackageCostKpis? fromKpis(Map<String, dynamic> j) {
    final raw = j['package_cost_sum'];
    if (raw == null) return null;
    final sum = raw is num ? raw : num.tryParse(raw.toString().trim());
    if (sum == null || !sum.isFinite || sum < 0) return null;
    int count(Object? v) {
      final n = v is num ? v : num.tryParse(v?.toString().trim() ?? '');
      return (n == null || !n.isFinite || n < 0) ? 0 : n.toInt();
    }

    return PackageCostKpis(
      sum: sum,
      rows: count(j['cost_rows']),
      knownRows: count(j['cost_known_rows']),
      estimatedRows: count(j['cost_estimated_rows']),
      hasEstimates: j['cost_has_estimates'] == true,
    );
  }
}

class FinanceKPIs {
  const FinanceKPIs({
    this.paymentsSum = 0,
    this.debtPaySum = 0,
    this.balanceDeductSum = 0,
    this.activateCashSum = 0,
    this.balanceAddSum = 0,
    this.activateNonCashSum = 0,
    this.expensesSum = 0,
    this.expensesCount = 0,
    this.managerDebtsOutstanding = 0,
    this.activationsCount = 0,
    this.extendCount = 0,
    this.packageCost,
    this.partialUnpaidFromLogs = 0,
    this.profitAfterCostOverride,
    this.goodsCashSum = 0,
    this.goodsRevenueSum = 0,
    this.goodsCostSum = 0,
    this.goodsProfitSum = 0,
    this.goodsDebtSum = 0,
    this.goodsCount = 0,
    this.balanceAddSalesSum,
    this.goodsLossSum = 0,
    this.goodsLossCount = 0,
  });
  final num paymentsSum;
  final num debtPaySum;
  final num balanceDeductSum;
  final num activateCashSum;
  final num balanceAddSum;
  final num activateNonCashSum;
  final num expensesSum;
  final int expensesCount;
  final num managerDebtsOutstanding;
  final int activationsCount;
  final int extendCount;

  /// كلفة الباقات للمالك — `null` = لا تُعرض: سوبرنت، أو موظّف، أو خادمٌ
  /// أقدم، أو التقرير مطفأ من الإعدادات. انظر [PackageCostKpis].
  final PackageCostKpis? packageCost;

  /// غير المدفوع من «نقدي جزئي» محسوباً من السطور (فلتر النوع وحده). أرقام
  /// الخادم تضمّه أصلاً في `activate_non_cash_sum`، فيبقى صفراً لها.
  final num partialUnpaidFromLogs;

  /// «بيع المواد» (قسم «المبيعات» — ٢٣ أكتوبر): يرسلها الخادم حين توجد مبيعاتٌ
  /// بالفترة وحدها (وإلّا أصفار ⇒ الشاشة كما كانت حرفيّاً). [goodsCashSum] صافي
  /// صندوقها (بيعٌ نقديّ − إرجاع)؛ والإيراد/الكلفة/الربح/الدين للمكتملة نقداً وديناً.
  final num goodsCashSum;
  final num goodsRevenueSum;
  final num goodsCostSum;
  final num goodsProfitSum;
  final num goodsDebtSum;
  final int goodsCount;

  /// جزء [balanceAddSum] الذي من قسم المبيعات: دين البيع (+) وإنقاصه عند إلغائه (−)
  /// — يحسبه الخادم من أسطر الدين الموسومة بالبيع نفسها (`balance_add_sales_sum`)
  /// فيصحّ لكلّ فترة ولو أُلغي البيع بعدها. `null` = خادمٌ أقدم ⇒ [goodsDebtSum].
  final num? balanceAddSalesSum;

  /// خسارة المواد (قرار المالك ٢٣ أكتوبر): تالف، عطلان شُطب، إرجاعٌ للمورّد بأقلّ من قيمته — وإلغاؤها
  /// سالب. كلفةُ مخزونٍ لن يُباع ⇒ تُطرح من الصافيين (الشراء لا يمسّ الربح، فلا تُعدّ مرّتين).
  final num goodsLossSum;
  final int goodsLossCount;

  bool get hasGoods => goodsCount > 0 || goodsCashSum != 0 || goodsLossCount > 0;

  /// إضافة الدين اليدويّة وحدها: البيع على الدين يكتب سطر «إضافة دين» بمسار الدين
  /// نفسه — وهو ثمن مادّة لا منحةٌ للمشترك، فلا يُطرح من الصافي (كلفته تُطرح)؛
  /// وإلغاؤه يكتب السطر نفسه بالسالب — فيُخرَجان معاً ([balanceAddSalesSum]).
  num get manualDebtAddSum {
    final v = balanceAddSum - (balanceAddSalesSum ?? goodsDebtSum);
    return v > 0 ? v : 0;
  }

  static num _n(dynamic v) =>
      v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
  static int _i(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

  /// إيراد نقدي حقيقي = activate_cash + payments + debt_pay + balance_deduct.
  /// **مطابق Financial.tsx** — كان mobile يفتقد `paymentsSum` (PAYMENT_ADD)
  /// وينتج فرق بين الويب والموبايل (bug 2026-08-10).
  num get totalCashRevenue =>
      activateCashSum + paymentsSum + debtPaySum + balanceDeductSum + goodsCashSum;

  /// تسديد ديون (debt collections) للعرض في KPI grid — يشمل paymentsSum أيضاً.
  num get totalDebtPayments => paymentsSum + debtPaySum + balanceDeductSum;

  /// الصافي = الإيراد - المصاريف - إضافة الدين اليدوي (2026-07-10).
  /// إضافة الدين اليدوي هي مبالغ منحها المدير للمشترك بلا استلام نقد
  /// (subsidy فعلي)، فتُطرَح من الصافي مثل المصاريف.
  ///
  /// بيع المواد: نقدها داخلٌ في [totalCashRevenue] فتُطرح كلفة ما بيع منها (ما بيع
  /// على الدين يدخل «النقد» حين يُسدَّد — فلا يُعدّ ربحه مرّتين)، و«إضافة الدين»
  /// اليدويّة وحدها تُطرح ([manualDebtAddSum]).
  num get netCash => totalCashRevenue - expensesSum - manualDebtAddSum - goodsCostSum - goodsLossSum;

  /// المبيعات: نقد التفعيلات + «الديون الجديدة» منها (غير النقديّ + غير
  /// المدفوع من الجزئيّ). أساس صافي الربح بعد الكلفة — كـ`sales_sum` الخادم.
  num get salesSum => activateCashSum + activateNonCashSum + partialUnpaidFromLogs;

  /// صافي الربح بعد كلفة الباقات — **على أساس المبيعات**: المبيعات − المصاريف
  /// − الكلفة المعروفة. `null` بلا كلفة (سوبرنت، الموظّف) فلا يُعرض شيء.
  ///
  /// صيغة الويب نفسها و`profit_after_cost` الخادم (والشاشة تحسبه هنا كي يصحّ
  /// تحت فلتر النوع أيضاً). ⚠️ لا من [netCash]: النقد فيه تسديد ديونٍ قديمة
  /// ويغيب عنه البيع بالدين، وكلفة البيع بالدين تُدفع للشركة يوم البيع — فطرحها
  /// من النقد كان يُظهر خسارةً لمالكٍ رابح (مراجعة ١٨ أكتوبر: ٩ من ١٦ مالكاً).
  /// [netCash] يبقى سطره كما كان (وفيه طرح إضافة الدين اليدوي بطلب المالك).
  /// + ربح المواد (البيع − كلفة المخزون، نقداً وديناً) − التالف والعطلان — صفرٌ بلا مبيعات.
  num? get profitAfterCost =>
      profitAfterCostOverride ??
      (packageCost == null ? null : salesSum - expensesSum - packageCost!.sum + goodsProfitSum - goodsLossSum);

  /// «كل الشركات»: مجموع صافي كلّ شركةٍ بقاعدتها (من بلا كلفةٍ — سوبرنت — صافيه
  /// النقديّ) — لا صيغةٌ واحدة على المجموع (قاعدة الويب sumFigures). null خارجه.
  final num? profitAfterCostOverride;

  /// [includePackageCost] قرار المستدعي بحسب من يشاهد — المالك وحده. الافتراض
  /// `false`: مستدعٍ لا يعرف المشاهد لا يكشف الكلفة لموظّف.
  static FinanceKPIs fromJson(
    Map<String, dynamic> j, {
    bool includePackageCost = false,
  }) {
    return FinanceKPIs(
      paymentsSum: _n(j['payments_sum']),
      debtPaySum: _n(j['debt_pay_sum']),
      balanceDeductSum: _n(j['balance_deduct_sum']),
      activateCashSum: _n(j['activate_cash_sum']),
      balanceAddSum: _n(j['balance_add_sum']),
      activateNonCashSum: _n(j['activate_non_cash_sum']),
      expensesSum: _n(j['expenses_sum']),
      expensesCount: _i(j['expenses_count']),
      managerDebtsOutstanding: _n(j['manager_debts_outstanding']),
      activationsCount: _i(j['activations_count']),
      extendCount: _i(j['extend_count']),
      packageCost: includePackageCost ? PackageCostKpis.fromKpis(j) : null,
      goodsCashSum: _n(j['sales_cash_sum']),
      goodsRevenueSum: _n(j['sales_revenue_sum']),
      goodsCostSum: _n(j['sales_cost_sum']),
      goodsProfitSum: _n(j['sales_profit_sum']),
      goodsDebtSum: _n(j['sales_debt_sum']),
      goodsCount: _i(j['sales_count']),
      balanceAddSalesSum: j.containsKey('balance_add_sales_sum') ? _n(j['balance_add_sales_sum']) : null,
      goodsLossSum: _n(j['sales_loss_sum']),
      goodsLossCount: _i(j['sales_loss_count']),
    );
  }
}

class FinanceLog {
  const FinanceLog({
    required this.id,
    required this.actionType,
    this.actionDescription,
    this.amount = 0,
    this.adminUsername,
    this.actingEmployeeFullName,
    this.actingEmployeeUsername,
    this.userUsername,
    this.userFirstname,
    this.userLastname,
    this.userManager,
    this.targetName,
    required this.createdAt,
    this.balanceAfter,
    this.fromSas = false,
    this.packageCost,
    this.packageCostSource,
    this.packageCostSent = false,
    this.partialUnpaid = 0,
  });
  final int id;
  final String actionType;
  final String? actionDescription;
  final num amount;
  final String? adminUsername;
  final String? actingEmployeeFullName;
  final String? actingEmployeeUsername;
  final String? userUsername;

  /// سطرٌ زامنّاه من الساس (`request_method='SYNC'`، الخادم: `from_sas`) — لا
  /// مال فيه، فلا يُعدّ عمليّة بيعٍ لها كلفة.
  final bool fromSas;

  /// كلفة باقة هذه الحركة — للمالك وحده، وحين يرسلها الخادم. `null` = غير
  /// مسجّلة أو غير مُرسَلة، لا صفر.
  final num? packageCost;

  /// مصدر الكلفة كما يسمّيه الخادم (`estimate` = تقديريّة لم تتأكّد بعد).
  final String? packageCostSource;

  /// الخادم أرسل حقل `package_cost` لهذا السطر (ولو `null` = غير معروفة بعد).
  /// غيابه لا يُفسَّر: خادمٌ قد لا يرسل إلّا المعروف.
  final bool packageCostSent;

  bool get packageCostEstimated => packageCostSource == 'estimate';

  /// غير المدفوع من «نقدي جزئي» لهذا السطر (`partial_unpaid` الخادم، بشرط
  /// النقديّ نفسه الذي يجمعه في «الديون الجديدة») — صفرٌ لغيره.
  final num partialUnpaid;

  /// عمليّة بيعٍ أرسل الخادم كلفتها `null` صراحةً — لم تُسجَّل بعد.
  bool get packageCostUnknown =>
      packageCostSent && packageCost == null && isSale && !fromSas;

  /// سطر دينٍ من قسم المبيعات — دين البيع أو إنقاصه عند إلغائه — بوصفه الذي يكتبه
  /// مسار الدين («… - بيع #N: …» · «إلغاء بيع #N — إنقاص دين …»). لحساب KPIs من
  /// السطور (فلتر النوع) وحده؛ أرقام الخادم الكاملة تأتي بـ`balance_add_sales_sum`.
  bool get isSaleDebtLine {
    if (actionType.toUpperCase().trim() != 'BALANCE_ADD') return false;
    final d = actionDescription ?? '';
    return d.startsWith('إلغاء بيع #') || d.contains('- بيع #');
  }

  /// تفعيلٌ أو تمديد — ما يُحسب له سعر باقة (تعريف `activationLike` في الخادم).
  bool get isSale {
    final at = actionType.toUpperCase().trim();
    return at == 'SUBSCRIBER_ACTIVATE' ||
        at == 'SUBSCRIBER_EXTEND' ||
        (at == 'SUBSCRIBER_ADD' && (actionDescription ?? '').contains('تفعيل'));
  }

  /// الاسم الأول (عربي) للمشترك — backend يحقنه في enrichment
  /// (fetchUserDirectory في FinanceReportController.js).
  final String? userFirstname;
  final String? userLastname;
  final String? userManager;
  final String? targetName;
  final String createdAt;

  /// الدين المتبقّي بعد الحركة — سالبٌ = دَين. `null` = لا نعرف.
  final num? balanceAfter;

  /// اسم كامل عربي مدمَج (firstname + lastname)، أو null لو أحدهما فارغ.
  String? get userFullName {
    final full = '${userFirstname ?? ''} ${userLastname ?? ''}'.trim();
    return full.isEmpty ? null : full;
  }

  /// [includePackageCost] كما في [FinanceKPIs.fromJson]: الكلفة للمالك وحده.
  static FinanceLog? fromJson(
    Map<String, dynamic> j, {
    bool includePackageCost = false,
  }) {
    // backend `/api/reports/finance` يحقن صفوف صناعية بمعرّفات نصّية
    // (id: "expense_5"، "mdebt_12"). لا نرفضها — نصنع hash id من الـstring.
    // ملاحظة: كنّا نرفضها بـint.tryParse فتختفي الصرفيات من قائمة "آخر
    // الحركات" رغم أن counters "# مصاريف" في KPIs تعمل صح (bug 2026-07-10).
    final at = j['action_type']?.toString();
    final ts = j['created_at']?.toString();
    if (at == null || ts == null) return null;
    final rawId = j['id']?.toString() ?? '';
    final id = int.tryParse(rawId) ?? rawId.hashCode.abs();
    return FinanceLog(
      id: id,
      actionType: at,
      actionDescription: j['action_description']?.toString(),
      amount: FinanceKPIs._n(j['amount']),
      adminUsername: j['admin_username']?.toString(),
      actingEmployeeFullName: j['acting_employee_full_name']?.toString(),
      actingEmployeeUsername: j['acting_employee_username']?.toString(),
      userUsername: j['user_username']?.toString(),
      userFirstname: j['user_firstname']?.toString(),
      userLastname: j['user_lastname']?.toString(),
      userManager: j['user_manager']?.toString(),
      targetName: j['target_name']?.toString(),
      createdAt: ts,
      balanceAfter:
          j['balance_after'] == null ? null : FinanceKPIs._n(j['balance_after']),
      fromSas: _truthy(j['from_sas']),
      packageCost: includePackageCost ? _cost(j['package_cost']) : null,
      packageCostSource: includePackageCost
          ? j['package_cost_source']?.toString()
          : null,
      packageCostSent: includePackageCost && j.containsKey('package_cost'),
      partialUnpaid: FinanceKPIs._n(j['partial_unpaid']),
    );
  }

  /// MySQL يُرجع `(… <=> 'SYNC')` رقماً (1/0) لا قيمةً منطقيّة.
  static bool _truthy(Object? v) =>
      v == true || v == 1 || v == '1' || v == 'true';

  /// كلفةٌ صالحة أو `null` — السالب وغير الرقم لا يُجمعان.
  static num? _cost(Object? v) {
    if (v == null) return null;
    final n = v is num ? v : num.tryParse(v.toString().trim());
    return (n == null || !n.isFinite || n < 0) ? null : n;
  }
}

class FinanceReport {
  const FinanceReport({
    required this.kpis,
    required this.recentLogs,
    this.archive,
    this.unavailable = false,
    this.unavailableParts = const [],
  });
  final FinanceKPIs kpis;
  final List<FinanceLog> recentLogs;

  /// وصف ما أخفته التسويات عن هذا التقرير — `data.archive` لا الجذر.
  /// `null` على خادمٍ قديم، وصفرُ تسوياتٍ لا يُعرض (§٤).
  final ArchiveInfo? archive;

  /// الخادم قال إنّ التقرير كلّه تعذّر (ملخّص ايرث لنك: جسمٌ أصفار ليست جواباً).
  final bool unavailable;

  /// أجزاءٌ تعذّرت فاستُبدلت بصفر: `expenses` · `activations` · `manager_debts` ·
  /// `package_cost` (أرقامٌ لا تُجمع) · `recent_logs` (السجلّ ناقص، والأرقام سليمة).
  final List<String> unavailableParts;

  /// أرقامه مجهولة (لا تُجمع في «كل الشركات»، والشركة تُسمّى): التقرير كلّه، أو
  /// جزءُ مال — وجزءٌ باسمٍ لا نعرفه احتياطاً. `recent_logs` وحده عرضٌ. null: سليمة.
  /// منقولةٌ من الويب (financial-figures.ts financeMoneyGap).
  String? get moneyGap {
    if (unavailable) return 'reply';
    final parts = unavailableParts.where((p) => p != 'recent_logs').toList();
    if (parts.isEmpty) return null;
    if (parts.contains('activations')) return 'activations';
    if (parts.contains('expenses')) return 'expenses';
    return 'other';
  }
}

// ─────────── Activities (Activations + ActivityLog) ───────────

class ActivityRow {
  const ActivityRow({
    required this.id,
    required this.actionType,
    this.actionDescription,
    this.amount = 0,
    this.adminUsername,
    this.actingEmployeeFullName,
    this.userUsername,
    this.userFirstname,
    this.userLastname,
    this.targetName,
    required this.createdAt,
    this.balanceAfter,
  });
  final int id;
  final String actionType;
  final String? actionDescription;
  final num amount;
  final String? adminUsername;
  final String? actingEmployeeFullName;
  final String? userUsername;

  /// backend يُغني `/api/activities` بـuser_firstname/lastname
  /// (server.js:7526–7557). يمكن نُقدّمها بارزة في UI و export.
  final String? userFirstname;
  final String? userLastname;
  final String? targetName;
  final String createdAt;
  /// الدين المتبقّي بعد هذه الحركة — موقَّعاً: سالبٌ = دَينٌ عليه.
  ///
  /// ⚠️ `null` ليس صفراً: حركةٌ لا تمسّ الرصيد، أو سجلٌّ قديم بلا القيمة.
  /// الواجهة تُخفي السطر حينها بدل أن تعرض «الدين: 0» — وهو رقمٌ يكذب.
  final num? balanceAfter;

  String? get userFullName {
    final full = '${userFirstname ?? ''} ${userLastname ?? ''}'.trim();
    return full.isEmpty ? null : full;
  }

  static ActivityRow? fromJson(Map<String, dynamic> j) {
    // نتقبّل معرّفات نصّية (مثل "expense_5") ونصنع hash لها. مطابق منطق
    // FinanceLog.fromJson (bug 2026-07-10: الصفوف الصناعية بمعرّف نصّي
    // كانت تُرفض).
    final at = j['action_type']?.toString();
    final ts = j['created_at']?.toString();
    if (at == null || ts == null) return null;
    final rawId = j['id']?.toString() ?? '';
    final id = int.tryParse(rawId) ?? rawId.hashCode.abs();
    return ActivityRow(
      id: id,
      actionType: at,
      actionDescription: j['action_description']?.toString(),
      amount: FinanceKPIs._n(j['amount']),
      adminUsername: j['admin_username']?.toString(),
      actingEmployeeFullName: j['acting_employee_full_name']?.toString(),
      userUsername: j['user_username']?.toString(),
      userFirstname: j['user_firstname']?.toString(),
      userLastname: j['user_lastname']?.toString(),
      targetName: j['target_name']?.toString(),
      createdAt: ts,
      balanceAfter:
          j['balance_after'] == null ? null : FinanceKPIs._n(j['balance_after']),
    );
  }
}

// ─────────── Daily Activations ───────────

class DailyActivationRow {
  const DailyActivationRow({
    required this.day,
    required this.count,
    required this.cashSum,
    required this.nonCashCount,
  });
  final String day;
  final int count;
  final num cashSum;
  final int nonCashCount;

  static DailyActivationRow? fromJson(Map<String, dynamic> j) {
    final day = j['day']?.toString();
    if (day == null) return null;
    return DailyActivationRow(
      day: day,
      count: FinanceKPIs._i(j['count']),
      cashSum: FinanceKPIs._n(j['cash_sum']),
      nonCashCount: FinanceKPIs._i(j['non_cash_count']),
    );
  }
}

// ─────────── Sessions ───────────

class SessionRow {
  const SessionRow({
    required this.id,
    this.username,
    this.userManager,
    this.ipAddress,
    this.mac,
    this.device,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.startedAt,
    this.endedAt,
    this.sessionTime,
    this.isOnlineOverride,
  });
  final int id;
  final String? username;
  final String? userManager;
  final String? ipAddress;
  final String? mac;
  final String? device;
  final num bytesIn;
  final num bytesOut;
  final String? startedAt;
  final String? endedAt;
  final num? sessionTime;
  final bool? isOnlineOverride;

  bool get isOnline =>
      isOnlineOverride ?? (endedAt == null || endedAt!.isEmpty);

  static SessionRow? fromJson(Map<String, dynamic> j) {
    // نمطان محتملان:
    //  (1) /api/v2/sessions (historical): radacctid + framedipaddress + callingstationid + acctstarttime/acctstoptime
    //  (2) /api/v2/online-users (live): بدون id، ip/mac/session_time مباشرة
    final id = int.tryParse(j['id']?.toString() ?? '') ??
        int.tryParse(j['radacctid']?.toString() ?? '');
    // لو ما ملقينا id، نصنع hash من username+mac كـfallback عشان
    // ما نرفض صف online-users. الـid يستعمل بس داخل الـUI.
    final username = j['username']?.toString();
    final ip = j['ip_address']?.toString() ??
        j['ip']?.toString() ??
        j['framedipaddress']?.toString();
    final mac = j['mac']?.toString() ?? j['callingstationid']?.toString();
    if (id == null && (username == null || username.isEmpty)) return null;
    final finalId = id ?? '$username|$mac'.hashCode.abs();
    final st = j['session_time'];
    final sessionTime =
        st is num ? st : (st != null ? num.tryParse(st.toString()) : null);
    // online-users ما فيه endedAt — نضبطها = null، والـisOnline يعتمد
    // على المصدر (لو مافيه radacctid عادة يعني /online-users).
    final endedAt = j['ended_at']?.toString() ?? j['acctstoptime']?.toString();
    final isOnlineOverride = id == null && endedAt == null ? true : null;
    return SessionRow(
      id: finalId,
      username: username,
      userManager: j['user_manager']?.toString() ??
          j['manager']?.toString() ??
          j['parent']?.toString(),
      ipAddress: ip,
      mac: (mac != null && mac.isNotEmpty) ? mac : null,
      device: j['device']?.toString() ?? j['oui']?.toString(),
      bytesIn: FinanceKPIs._n(
          j['bytes_in'] ?? j['download_bytes'] ?? j['acctinputoctets']),
      bytesOut: FinanceKPIs._n(
          j['bytes_out'] ?? j['upload_bytes'] ?? j['acctoutputoctets']),
      startedAt: j['started_at']?.toString() ?? j['acctstarttime']?.toString(),
      endedAt: endedAt,
      sessionTime: sessionTime,
      isOnlineOverride: isOnlineOverride,
    );
  }
}

/// كشف حساب مشترك — صف حركة واحدة (تفعيل/تسديد/إضافة دين/…).
class StatementRow {
  const StatementRow({
    required this.id,
    required this.createdAt,
    this.actionType,
    this.description,
    this.amount = 0,
    this.adminName,
    this.notes,
    this.balanceAfter,
  });
  final int id;
  final String createdAt;
  final String? actionType;
  final String? description;
  final num amount;
  final String? adminName;
  final String? notes;
  /// الدين المتبقّي بعد هذه الحركة — موقَّعاً: سالبٌ = دَينٌ عليه.
  ///
  /// ⚠️ `null` ليس صفراً: حركةٌ لا تمسّ الرصيد، أو سجلٌّ قديم بلا القيمة.
  /// الواجهة تُخفي السطر حينها بدل أن تعرض «الدين: 0» — وهو رقمٌ يكذب.
  final num? balanceAfter;

  static StatementRow? fromJson(Map<String, dynamic> j) {
    final rawId = j['id']?.toString() ?? '';
    final id = int.tryParse(rawId) ?? rawId.hashCode.abs();
    final ts = j['created_at']?.toString();
    if (ts == null) return null;
    return StatementRow(
      id: id,
      createdAt: ts,
      actionType: j['action_type']?.toString(),
      description: j['description']?.toString(),
      amount: FinanceKPIs._n(j['amount']),
      adminName: j['admin_name']?.toString(),
      notes: j['notes']?.toString(),
      balanceAfter:
          j['balance_after'] == null ? null : FinanceKPIs._n(j['balance_after']),
    );
  }
}

class StatementSummary {
  const StatementSummary({
    this.totalTransactions = 0,
    this.totalDebt = 0,
    this.totalPayments = 0,
    this.totalActivations = 0,
  });
  final int totalTransactions;
  final num totalDebt;
  final num totalPayments;
  final int totalActivations;

  /// الرصيد الصافي: مدفوع - دين. سالب = مدين للمدير، موجب = رصيد إضافي.
  num get balance => totalPayments - totalDebt;

  static StatementSummary fromJson(Map<String, dynamic> j) {
    return StatementSummary(
      totalTransactions: FinanceKPIs._i(j['totalTransactions']),
      totalDebt: FinanceKPIs._n(j['totalDebt']),
      totalPayments: FinanceKPIs._n(j['totalPayments']),
      totalActivations: FinanceKPIs._i(j['totalActivations']),
    );
  }
}

class SubscriberInfo {
  const SubscriberInfo({
    this.username,
    this.firstname,
    this.lastname,
    this.phone,
  });
  final String? username;
  final String? firstname;
  final String? lastname;
  final String? phone;

  String get displayName {
    final full =
        [firstname, lastname].where((s) => s != null && s.isNotEmpty).join(' ');
    return full.isNotEmpty ? full : (username ?? '');
  }

  static SubscriberInfo? fromJson(Map<String, dynamic> j) {
    return SubscriberInfo(
      username: j['username']?.toString(),
      firstname: j['firstname']?.toString(),
      lastname: j['lastname']?.toString(),
      phone: j['phone']?.toString(),
    );
  }
}

class StatementResponse {
  const StatementResponse({
    required this.rows,
    required this.summary,
    this.subscriber,
  });
  final List<StatementRow> rows;
  final StatementSummary summary;
  final SubscriberInfo? subscriber;
}

class ReportsApi {
  ReportsApi._();

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// نهاية اليوم — للـdate_to حتى يشمل كل عمليّات اليوم.
  /// كنّا نرسل YYYY-MM-DD فقط، فالـSQL يعتبرها 00:00:00 ويتخطّى كل
  /// عمليّات اليوم الحالي. يجب مطابقة web (يرسل 23:59:59).
  static String _dateEnd(DateTime d) => '${_date(d)} 23:59:59';

  /// بداية اليوم — للـdate_from (00:00:00 صريحة).
  static String _dateStart(DateTime d) => '${_date(d)} 00:00:00';

  /// التقرير المالي — KPIs + آخر السجلات.
  /// dateFrom/dateTo بصيغة YYYY-MM-DD. لو فاضي يرجع الـbackend الافتراضي.
  /// userIds — قائمة IDs المدراء المرشّحين. لو فاضي يرجع كل المدراء.
  /// actionManagerId يحل محل userIds إذا حُدّد (فلتر بمدير معيّن).
  /// userManager — filter بمدير المشترك المستهدَف (username).
  /// employeeId — فلتر بموظف مُنفِّذ.
  /// withPackageCost — يقرأ كلفة الباقات إن أرسلها الخادم. يمرّره المستدعي
  /// لمالك الحساب وحده؛ للموظّف تُسقَط الحقول هنا ولو وصلت.
  static Future<({bool ok, FinanceReport? data, String? error})> finance({
    DateTime? from,
    DateTime? to,
    int recentLimit = 50,
    List<String>? userIds,
    String? actionManagerId,
    String? userManager,
    int? employeeId,
    bool includeArchived = false,
    bool withPackageCost = false,
  }) async {
    try {
      final qp = <String, String>{
        'limit_logs': '$recentLimit',
        // ما غطّته تسويةٌ فعّالة مخفيٌّ افتراضيّاً من الخادم: الأرقام
        // والسلسلة وآخر الحركات والصرفيات معاً (§٤).
        if (includeArchived) 'include_archived': '1',
        if (from != null) 'date_from': _dateStart(from),
        if (to != null) 'date_to': _dateEnd(to),
        // priority: actionManagerId (single) > userIds (list)
        if (actionManagerId != null && actionManagerId.isNotEmpty)
          'user_id': actionManagerId
        else if (userIds != null && userIds.isNotEmpty)
          'user_ids': userIds.where((id) => id.isNotEmpty).join(','),
        if (userManager != null && userManager.isNotEmpty)
          'user_manager': userManager,
        if (employeeId != null) 'employee_id': '$employeeId',
      };
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/reports/finance',
        queryParameters: qp,
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (ok: false, data: null, error: body['message']?.toString());
      }
      final data = body['data'];
      if (data is! Map) {
        return (ok: false, data: null, error: 'تنسيق غير متوقع');
      }
      final kpisRaw = data['kpis'];
      final logsRaw = data['recentLogs'];
      final kpis = kpisRaw is Map
          ? FinanceKPIs.fromJson(
              Map<String, dynamic>.from(kpisRaw),
              includePackageCost: withPackageCost,
            )
          : const FinanceKPIs();
      final logs = (logsRaw is List)
          ? logsRaw
              .whereType<Map>()
              .map((m) => FinanceLog.fromJson(
                    Map<String, dynamic>.from(m),
                    includePackageCost: withPackageCost,
                  ))
              .whereType<FinanceLog>()
              .toList()
          : const <FinanceLog>[];
      // علما التعذّر (٢١ أكتوبر، 2621ef0/84a295f): في الجسم أو داخل data — بلا تكرار.
      final parts = <String>{
        for (final src in [body['unavailable_parts'], data['unavailable_parts']])
          if (src is List)
            for (final x in src) '$x',
      };
      return (
        ok: true,
        data: FinanceReport(
          kpis: kpis,
          recentLogs: logs,
          archive: ArchiveInfo.fromJson(data['archive']),
          unavailable: body['unavailable'] == true || data['unavailable'] == true,
          unavailableParts: parts.toList(),
        ),
        error: null,
      );
    } on DioException catch (e) {
      _log('finance', e);
      return (ok: false, data: null, error: _friendly(e));
    } catch (e) {
      _log('finance', e);
      return (ok: false, data: null, error: 'تعذّر تحميل التقرير');
    }
  }

  /// قائمة activities — يستعمل للـActivations + ActivityLog.
  /// activityType: فلتر اختياري. فاضي = الكل.
  /// userIds — قائمة IDs المدراء المرشّحين.
  /// actionManagerId (single) يحل محل userIds إذا حُدّد.
  /// userManager: username المدير الفرعي للمشترك المستهدَف.
  /// employeeId: الموظف المنفِّذ للحركة.
  static Future<({bool ok, List<ActivityRow> rows, String? error})> activities({
    DateTime? from,
    DateTime? to,
    String? activityType,
    String? search,
    List<String>? userIds,
    String? actionManagerId,
    String? userManager,
    int? employeeId,
    int limit = 200,
  }) async {
    try {
      final qp = <String, String>{
        'limit': '$limit',
        if (from != null) 'date_from': _dateStart(from),
        if (to != null) 'date_to': _dateEnd(to),
        if (activityType != null && activityType.isNotEmpty)
          'activity_type': activityType,
        if (search != null && search.isNotEmpty) 'search': search,
        if (actionManagerId != null && actionManagerId.isNotEmpty)
          'user_id': actionManagerId
        else if (userIds != null && userIds.isNotEmpty)
          'user_ids': userIds.where((id) => id.isNotEmpty).join(','),
        if (userManager != null && userManager.isNotEmpty)
          'user_manager': userManager,
        if (employeeId != null) 'employee_id': '$employeeId',
      };
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/activities',
        queryParameters: qp,
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          ok: false,
          rows: const <ActivityRow>[],
          error: body['message']?.toString(),
        );
      }
      final list = body['data'];
      if (list is! List) {
        return (ok: true, rows: const <ActivityRow>[], error: null);
      }
      return (
        ok: true,
        rows: list
            .whereType<Map>()
            .map((m) => ActivityRow.fromJson(Map<String, dynamic>.from(m)))
            .whereType<ActivityRow>()
            .toList(),
        error: null,
      );
    } on DioException catch (e) {
      _log('activities', e);
      return (ok: false, rows: const <ActivityRow>[], error: _friendly(e));
    } catch (e) {
      _log('activities', e);
      return (ok: false, rows: const <ActivityRow>[], error: 'تعذّر التحميل');
    }
  }

  /// التفعيلات اليومية — مُجمَّعة حسب اليوم عبر الفترة.
  ///
  /// backend `/api/activities/daily-activations` يرجع "اليوم فقط" (ليس
  /// مُجمَّعاً لفترة). فنستخدم `/api/activities` مع فلتر تفعيلات +
  /// نُجمّع محلياً حسب تاريخ اليوم.
  static Future<({bool ok, List<DailyActivationRow> rows, String? error})>
      dailyActivations({
    DateTime? from,
    DateTime? to,
    List<String>? userIds,
    String? actionManagerId,
    String? userManager,
    int? employeeId,
  }) async {
    try {
      final qp = <String, String>{
        'limit': '5000',
        if (from != null) 'date_from': _dateStart(from),
        if (to != null) 'date_to': _dateEnd(to),
        // priority: actionManagerId (single) > userIds (list)
        if (actionManagerId != null && actionManagerId.isNotEmpty)
          'user_id': actionManagerId
        else if (userIds != null && userIds.isNotEmpty)
          'user_ids': userIds.where((id) => id.isNotEmpty).join(','),
        if (userManager != null && userManager.isNotEmpty)
          'user_manager': userManager,
        if (employeeId != null) 'employee_id': '$employeeId',
      };
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/activities',
        queryParameters: qp,
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          ok: false,
          rows: const <DailyActivationRow>[],
          error: body['message']?.toString(),
        );
      }
      final list = body['data'];
      if (list is! List) {
        return (ok: true, rows: const <DailyActivationRow>[], error: null);
      }
      // نفلتر ونجمّع محلياً حسب اليوم.
      final byDay = <String, ({int cash, int nonCash, num cashSum})>{};
      for (final row in list) {
        if (row is! Map) continue;
        final at = (row['action_type']?.toString() ?? '').toUpperCase().trim();
        final desc =
            (row['action_description']?.toString() ?? '').toLowerCase();
        final isActivate = at == 'SUBSCRIBER_ACTIVATE' ||
            (at == 'SUBSCRIBER_ADD' && desc.contains('تفعيل'));
        if (!isActivate) continue;
        final ts = row['created_at']?.toString();
        if (ts == null || ts.length < 10) continue;
        final day = ts.substring(0, 10); // YYYY-MM-DD
        final isCash = desc.contains('نقدي') && !desc.contains('غير نقدي');
        num amount = 0;
        // نجرّب استخراج المبلغ من action_data (JSON string) → ثم من الوصف.
        final dataRaw = row['action_data'];
        if (dataRaw is String && dataRaw.isNotEmpty) {
          try {
            final map = jsonDecode(dataRaw);
            if (map is Map) {
              final v = map['final_price'] ??
                  map['partial_cash_amount'] ??
                  map['amount'] ??
                  map['price'] ??
                  map['user_price'] ??
                  0;
              amount = v is num ? v : num.tryParse(v.toString()) ?? 0;
            }
          } catch (_) {}
        } else if (dataRaw is Map) {
          final v = dataRaw['final_price'] ??
              dataRaw['partial_cash_amount'] ??
              dataRaw['amount'] ??
              dataRaw['price'] ??
              dataRaw['user_price'] ??
              0;
          amount = v is num ? v : num.tryParse(v.toString()) ?? 0;
        }
        if (amount == 0) {
          final m = RegExp(r'IQD\s*([0-9][0-9,]*)').firstMatch(desc);
          if (m != null) {
            amount = num.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0;
          }
        }
        final prev = byDay[day] ?? (cash: 0, nonCash: 0, cashSum: 0);
        byDay[day] = (
          cash: prev.cash + (isCash ? 1 : 0),
          nonCash: prev.nonCash + (isCash ? 0 : 1),
          cashSum: prev.cashSum + (isCash ? amount : 0),
        );
      }
      final rows = byDay.entries
          .map((e) => DailyActivationRow(
                day: e.key,
                count: e.value.cash,
                cashSum: e.value.cashSum,
                nonCashCount: e.value.nonCash,
              ))
          .toList()
        ..sort((a, b) => b.day.compareTo(a.day));
      return (ok: true, rows: rows, error: null);
    } on DioException catch (e) {
      _log('daily activations', e);
      return (
        ok: false,
        rows: const <DailyActivationRow>[],
        error: _friendly(e),
      );
    } catch (e) {
      _log('daily activations', e);
      return (
        ok: false,
        rows: const <DailyActivationRow>[],
        error: 'تعذّر التحميل',
      );
    }
  }

  /// الجلسات الحالية + التاريخية (filter بـonlineOnly).
  /// search: filter عام (SAS4 يفهمه). أو تعطي username/ip/mac منفردين.
  ///
  /// [note] = ملاحظة مصدر الجلسات المنتهية ([sessionsHistoryNote]) — ايرث لنك
  /// وحدها: `usersession/completed` من العقد المفكَّك (خلف فحص قدرة عند
  /// الخادم)، وسجلّ مشتركٍ بعينه من `usersession/user` (مؤكَّد حيّاً).
  static Future<({bool ok, List<SessionRow> rows, String? error, String? note})>
      sessions({
    bool onlineOnly = false,
    DateTime? from,
    DateTime? to,
    String? search,
    String? username,
    String? ip,
    String? mac,
    int limit = 200,
  }) async {
    try {
      final qp = <String, String>{
        'count': '$limit',
        'page': '1',
        if (from != null) 'from': _date(from),
        if (to != null) 'to': _date(to),
        if (search != null && search.isNotEmpty) 'search': search,
        if (username != null && username.isNotEmpty) 'username': username,
        if (ip != null && ip.isNotEmpty) 'ip': ip,
        if (mac != null && mac.isNotEmpty) 'mac': mac,
      };
      final endpoint = onlineOnly ? '/api/v2/online-users' : '/api/v2/sessions';
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        endpoint,
        queryParameters: qp,
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          ok: false,
          rows: const <SessionRow>[],
          error: body['message']?.toString(),
          note: null,
        );
      }
      final note = onlineOnly ? null : sessionsHistoryNote(body);
      final list = body['data'];
      if (list is! List) {
        return (ok: true, rows: const <SessionRow>[], error: null, note: note);
      }
      return (
        ok: true,
        rows: list
            .whereType<Map>()
            .map((m) => SessionRow.fromJson(Map<String, dynamic>.from(m)))
            .whereType<SessionRow>()
            .toList(),
        error: null,
        note: note,
      );
    } on DioException catch (e) {
      _log('sessions', e);
      return (
        ok: false,
        rows: const <SessionRow>[],
        error: _friendly(e),
        note: null,
      );
    } catch (e) {
      _log('sessions', e);
      return (
        ok: false,
        rows: const <SessionRow>[],
        error: 'تعذّر التحميل',
        note: null,
      );
    }
  }

  /// ملاحظة مصدر الجلسات المنتهية من ردّ `/api/v2/sessions` — ايرث لنك وحدها
  /// ترسل `ended:{supported, source, window, partial, range}` (المجموعة ②
  /// ١٨ أكتوبر)؛ SAS4 لا يرسله ⇒ `null` كما كان. نصوص الويب نفسها.
  ///   • `supported:false` — ايرث لنك لا تعطي سجلّ الجلسات المنتهية لهذا الحساب.
  ///   • `supported:null` — تعذّر جلبها هذه المرّة.
  ///   • `source:'subscriber'` — سجلّ مشتركٍ بعينه (البحث باسمه كاملاً) بمداه.
  ///   • `source:'completed'` + `partial` — آخر N جلسة فقط.
  @visibleForTesting
  static String? sessionsHistoryNote(Map<String, dynamic> body) {
    final e = body['ended'];
    if (e is! Map) {
      // خادمٌ يرسل علم القدرة وحده (`history_available:false` + نصّه) بلا
      // تفصيل `ended`: نصّه إن وُجد، وإلّا «الحيّة فقط».
      if (body['history_available'] != false) return null;
      final note = body['history_note']?.toString().trim() ?? '';
      return note.isNotEmpty
          ? note
          : 'ايرث لنك لا تعطي سجلّ الجلسات المنتهية لحسابك — تظهر الجلسات '
              'الحيّة فقط.';
    }
    if (e.containsKey('supported') && e['supported'] == false) {
      return 'ايرث لنك لا تعطي سجلّ الجلسات المنتهية لحسابك — تظهر الجلسات '
          'الحيّة فقط. لسجلّ مشتركٍ بعينه ابحث باسم دخوله كاملاً.';
    }
    if (e['supported'] == null) {
      return 'تعذّر جلب الجلسات المنتهية من ايرث لنك هذه المرّة — المعروض '
          'الجلسات الحيّة.';
    }
    final range = e['range'];
    if (e['source'] == 'subscriber' && range is Map) {
      // «2026/09/19» معزولاً: الشرطة تُكسر عندها الأسطر وتنقلب في نصٍّ عربيّ.
      String day(Object? v) =>
          iso((v?.toString().trim() ?? '').replaceAll('-', '/'));
      final from = day(range['startDate']);
      final to = day(range['endDate']);
      if (from.isNotEmpty && to.isNotEmpty) {
        return 'سجلّ هذا المشترك من $from إلى $to.';
      }
    }
    if (e['source'] == 'completed' && e['partial'] == true) {
      final w = e['window'];
      final n = w is num ? w.toInt() : int.tryParse('$w');
      return n == null || n <= 0
          ? 'آخر الجلسات المنتهية لدى ايرث لنك فقط — لسجلّ مشتركٍ بعينه ابحث '
              'باسم دخوله كاملاً.'
          : 'آخر $n جلسة منتهية لدى ايرث لنك — لسجلّ مشتركٍ بعينه ابحث باسم '
              'دخوله كاملاً.';
    }
    return null;
  }

  /// كشف حساب مشترك — يجلب حركاته المالية في الفترة + summary.
  /// backend: GET /api/reports/account-statement?username=X&date_from=Y&date_to=Z
  static Future<({bool ok, StatementResponse? data, String? error})>
      accountStatement({
    required String username,
    DateTime? from,
    DateTime? to,
    String? userId,
    List<String>? actionTypes,
  }) async {
    try {
      final qp = <String, String>{
        'username': username,
        if (from != null) 'date_from': _dateStart(from),
        if (to != null) 'date_to': _dateEnd(to),
        if (userId != null && userId.isNotEmpty) 'user_id': userId,
        if (actionTypes != null && actionTypes.isNotEmpty)
          'action_types': actionTypes.join(','),
      };
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/reports/account-statement',
        queryParameters: qp,
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          ok: false,
          data: null,
          error: body['message']?.toString(),
        );
      }
      final data = body['data'];
      if (data is! Map) {
        return (ok: false, data: null, error: 'تنسيق غير متوقع');
      }
      final rawRows = data['transactions'];
      final rows = rawRows is List
          ? rawRows
              .whereType<Map>()
              .map((m) => StatementRow.fromJson(Map<String, dynamic>.from(m)))
              .whereType<StatementRow>()
              .toList()
          : const <StatementRow>[];
      final summary = data['summary'] is Map
          ? StatementSummary.fromJson(
              Map<String, dynamic>.from(data['summary'] as Map))
          : const StatementSummary();
      final subscriber = data['subscriber'] is Map
          ? SubscriberInfo.fromJson(
              Map<String, dynamic>.from(data['subscriber'] as Map))
          : null;
      return (
        ok: true,
        data: StatementResponse(
          rows: rows,
          summary: summary,
          subscriber: subscriber,
        ),
        error: null,
      );
    } on DioException catch (e) {
      _log('account-statement', e);
      return (ok: false, data: null, error: _friendly(e));
    } catch (e) {
      _log('account-statement', e);
      return (ok: false, data: null, error: 'تعذّر التحميل');
    }
  }

  static String _friendly(DioException e) {
    final code = e.response?.statusCode ?? 0;
    if (code == 403) return 'لا تملك صلاحية لهذا التقرير';
    if (code == 401) return 'انتهت الجلسة';
    return 'تعذّر التحميل';
  }

  static void _log(String endpoint, Object err) {
    if (kReleaseMode) return;
    if (err is DioException) {
      debugPrint(
        '🔴 reports $endpoint: status=${err.response?.statusCode} body=${err.response?.data}',
      );
    } else {
      debugPrint('🔴 reports $endpoint: $err');
    }
  }
}
