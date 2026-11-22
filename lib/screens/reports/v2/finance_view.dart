import 'package:easy_localization/easy_localization.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/reports_api.dart';
import '../../../core/util/ar_date.dart';
import '../../../core/util/format.dart';
import '../../../core/util/server_time.dart';
import '../widgets/action_labels.dart';
import '../widgets/finance_logs.dart';
import 'report_kit.dart';
import 'report_period.dart';

// التقرير الماليّ على الشكل الموحّد (٢٢ نوفمبر): من أرقام الخادم ([FinanceKPIs] وسطوره) إلى بطاقات الشكل — حسابٌ صرف بلا شاشة.
// القواعد نفسها حرفاً (الصافي، الربح بعد كلفة الباقات، تسديد الديون بلا المقدّم نقداً، الإضافة اليدويّة) — لا رقمٌ جديد هنا.

/// ثوابت البطاقات (حركاتها عند اللمس: [FinanceView.drill]).
class FinanceKpiIds {
  static const hero = 'hero';
  static const cash = 'cash';
  static const activateCash = 'activate_cash';
  static const debtPay = 'debt_pay';
  static const activateNonCash = 'activate_non_cash';
  static const debtAdd = 'debt_add';
  static const expenses = 'expenses';
  static const creditCash = 'credit_cash';
  static const creditComp = 'credit_comp';
  static const goodsRevenue = 'goods_revenue';
  static const goodsProfit = 'goods_profit';
  static const goodsLoss = 'goods_loss';
  static const packageCost = 'package_cost';
  static const salaries = 'salaries';
  static const empOutstanding = 'emp_outstanding';
}

class FinanceView {
  FinanceView._();

  /// البطاقة الكبرى: «صافي الربح بعد كلفة الباقات» حين يعرف الخادم الكلفة (المالك على ساسٍ بعيد/ايرث لنك)، وإلّا «الصافي»
  /// النقديّ — قاعدة الشاشة الحاليّة نفسها.
  static RpKpi hero(FinanceKPIs k, FinanceKPIs? prev) {
    final profit = k.profitAfterCost;
    final withCost = k.packageCost != null && profit != null;
    num of(FinanceKPIs x) => withCost ? (x.profitAfterCost ?? x.netCash) : x.netCash;
    final v = of(k);
    return RpKpi(
      id: FinanceKpiIds.hero,
      label: withCost ? 'صافي الربح بعد كلفة الباقات' : 'الصافي',
      value: v,
      icon: v < 0 ? LucideIcons.trendingDown : LucideIcons.trendingUp,
      tone: v < 0 ? RpTone.loss : RpTone.brand,
      delta: prev == null ? null : rpDelta(v, of(prev)),
    );
  }

  /// سطر الحساب تحت البطاقة الكبرى — الصيغة الحاليّة نفسها (مفاتيح الترجمة نفسها).
  static String heroNote(FinanceKPIs k, {bool mergedRule = false}) {
    final cost = k.packageCost;
    if (cost == null || k.profitAfterCost == null) {
      return 'الإيراد النقدي − المصاريف − إضافة الدين${k.hasGoods ? ' − كلفة المواد' : ''}';
    }
    if (mergedRule) return 'merged.finance_profit_rule'.tr();
    final base = (!k.hasGoods
            ? 'reports.profit_after_cost_formula'
            : k.goodsLossSum != 0
                ? 'reports.profit_after_cost_formula_goods_loss'
                : 'reports.profit_after_cost_formula_goods')
        .tr(namedArgs: {
      'sales': formatIQD(k.salesSum),
      'expenses': formatIQD(k.expensesSum),
      'cost': formatIQD(cost.sum),
      'goods': '${k.goodsProfitSum < 0 ? '-' : ''}${formatIQD(k.goodsProfitSum)}',
      'loss': '${k.goodsLossSum < 0 ? '-' : ''}${formatIQD(k.goodsLossSum)}',
    });
    return base + (k.creditCompSum > 0 ? ' − تعويضات ${formatIQD(k.creditCompSum)}' : '');
  }

  /// تنبيهات الكلفة (ناقصة، تقديريّة، أو لا تُحسب تحت فلتر النوع) — كالشاشة الحاليّة.
  static List<String> heroNotes(FinanceKPIs k, {bool costNeedsAllTypes = false}) {
    final cost = k.packageCost;
    return [
      if (cost != null && cost.missingRows > 0)
        'reports.package_cost_missing'.tr(namedArgs: {'missing': '${cost.missingRows}', 'rows': '${cost.rows}'}),
      if (cost != null && cost.hasEstimates)
        cost.estimatedRows > 0
            ? 'reports.package_cost_estimated'.tr(namedArgs: {'count': '${cost.estimatedRows}'})
            : 'reports.package_cost_estimated_some'.tr(),
      if (cost == null && costNeedsAllTypes) 'reports.package_cost_needs_all_types'.tr(),
    ];
  }

  /// البطاقات بعمودين — ما يُعرض اليوم نفسه بالترتيب، والمشروطة حين يوجد ما تعرضه.
  static List<RpKpi> kpis(FinanceKPIs k, FinanceKPIs? prev) {
    double? d(num Function(FinanceKPIs) f) => prev == null ? null : rpDelta(f(k), f(prev));
    RpKpi m(String id, String label, num Function(FinanceKPIs) f, dynamic icon, RpTone tone, {bool upIsGood = true}) =>
        RpKpi(id: id, label: label, value: f(k), icon: icon, tone: tone, delta: d(f), upIsGood: upIsGood);
    final cost = k.packageCost;
    return [
      m(FinanceKpiIds.cash, 'الإيراد النقدي', (x) => x.totalCashRevenue, LucideIcons.wallet, RpTone.money),
      m(FinanceKpiIds.activateCash, 'تفعيل نقدي', (x) => x.activateCashSum, LucideIcons.zap, RpTone.money),
      // المقدّم نقداً داخلٌ في «تسديد الديون» عند الخادم — يُفصل عنه بسطره (١٧ نوفمبر).
      m(FinanceKpiIds.debtPay, 'تسديد الديون', (x) => x.totalDebtPayments - x.creditCashSum, LucideIcons.banknote, RpTone.money),
      m(FinanceKpiIds.activateNonCash, 'تفعيل بالدين', (x) => x.activateNonCashSum, LucideIcons.creditCard, RpTone.debt,
          upIsGood: false),
      // اليدويّة وحدها — البيع على الدين ثمن مادّة لا منحة ([FinanceKPIs.manualDebtAddSum]).
      m(FinanceKpiIds.debtAdd, 'إضافة دين', (x) => x.manualDebtAddSum, LucideIcons.plus, RpTone.debt, upIsGood: false),
      m(FinanceKpiIds.expenses, 'المصاريف', (x) => x.expensesSum, LucideIcons.receipt, RpTone.loss, upIsGood: false),
      if (k.creditCashSum > 0) m(FinanceKpiIds.creditCash, 'رصيد مقدّم (نقداً)', (x) => x.creditCashSum, LucideIcons.coins, RpTone.money),
      if (k.creditCompSum > 0)
        m(FinanceKpiIds.creditComp, 'تعويضات بلا نقد', (x) => x.creditCompSum, LucideIcons.gift, RpTone.neutral, upIsGood: false),
      if (k.hasGoods) ...[
        m(FinanceKpiIds.goodsRevenue, 'reports.goods_revenue'.tr(), (x) => x.goodsRevenueSum, LucideIcons.shoppingCart, RpTone.money),
        m(FinanceKpiIds.goodsProfit, 'reports.goods_profit'.tr(), (x) => x.goodsProfitSum, LucideIcons.trendingUp,
            k.goodsProfitSum < 0 ? RpTone.loss : RpTone.money),
        if (k.goodsLossCount > 0)
          m(FinanceKpiIds.goodsLoss, 'reports.goods_loss'.tr(), (x) => x.goodsLossSum.abs(), LucideIcons.packageX, RpTone.loss,
              upIsGood: false),
      ],
      if (cost != null)
        m(FinanceKpiIds.packageCost, 'reports.package_cost'.tr(), (x) => x.packageCost?.sum ?? 0, LucideIcons.package, RpTone.loss,
            upIsGood: false),
      // «حركات الموظف» (١٣ نوفمبر) — للعرض: رواتبهم داخلةٌ أصلاً في المصاريف، والسلف ليست مصروفاً.
      if (k.hasEmployeeMoves && k.empSalariesSum > 0)
        m(FinanceKpiIds.salaries, 'منها رواتب ومكافآت', (x) => x.empSalariesSum, LucideIcons.users, RpTone.loss, upIsGood: false),
      if (k.showEmployeeReceivable)
        m(FinanceKpiIds.empOutstanding, 'سلف وقروض الموظفين', (x) => x.empOutstanding, LucideIcons.handCoins, RpTone.debt,
            upIsGood: false),
    ];
  }

  /// الأعداد بصفٍّ واحد.
  static List<RpKpi> counts(FinanceKPIs k) => [
        RpKpi(label: 'تفعيل', value: k.activationsCount, icon: LucideIcons.zap, tone: RpTone.brand, isCount: true),
        RpKpi(label: 'تمديد', value: k.extendCount, icon: LucideIcons.repeat, tone: RpTone.info, isCount: true),
        RpKpi(label: 'صرفيّة', value: k.expensesCount, icon: LucideIcons.receipt, tone: RpTone.loss, isCount: true),
      ];

  /// حركات بطاقةٍ لُمست — ما يصنع رقمها من السطور المعروضة.
  static bool Function(FinanceLog) drill(String id) {
    bool t(FinanceLog l, String type) => FinanceLogs.matchesType(l, type);
    String at(FinanceLog l) => l.actionType.toUpperCase().trim();
    switch (id) {
      case FinanceKpiIds.cash:
        return (l) => FinanceLogs.cashOf(l) != 0;
      case FinanceKpiIds.activateCash:
        return (l) => t(l, 'SUBSCRIBER_ACTIVATE_CASH');
      case FinanceKpiIds.debtPay:
        return (l) => const {'DEBT_PAY', 'BALANCE_DEDUCT', 'PAYMENT_ADD'}.contains(at(l));
      case FinanceKpiIds.activateNonCash:
        return (l) => t(l, 'SUBSCRIBER_ACTIVATE_NON_CASH');
      case FinanceKpiIds.debtAdd:
        return (l) => at(l) == 'BALANCE_ADD' && !l.isCredit && !l.isSaleDebtLine;
      case FinanceKpiIds.expenses:
      case FinanceKpiIds.salaries:
        return (l) => t(l, 'ADMIN_EXPENSE');
      case FinanceKpiIds.creditCash:
        return (l) => at(l) == 'BALANCE_ADD' && l.isCredit && l.creditKind == 'cash';
      case FinanceKpiIds.creditComp:
        return (l) => at(l) == 'BALANCE_ADD' && l.isCredit && l.creditKind == 'comp';
      case FinanceKpiIds.goodsRevenue:
      case FinanceKpiIds.goodsProfit:
      case FinanceKpiIds.goodsLoss:
        return (l) => l.isSale || l.isSaleDebtLine;
      case FinanceKpiIds.packageCost:
        return (l) => l.packageCost != null || l.packageCostUnknown;
      default:
        return (_) => true;
    }
  }

  static DateTime? timeOf(FinanceLog l) => parseServerUtc(l.createdAt);
  static bool _dateOnly(String s) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s.trim());

  /// سطر حركةٍ بلون عائلته وأيقونتها.
  static RpRow row(FinanceLog l, {RpCompany? company, bool showCost = false}) {
    final at = l.actionType.toUpperCase().trim();
    final desc = (l.actionDescription ?? '').trim();
    final isNonCash = desc.contains('غير نقدي');
    late final dynamic icon;
    late final RpTone tone;
    var negative = false;
    if (at == 'SUBSCRIBER_ACTIVATE' || (at == 'SUBSCRIBER_ADD' && desc.contains('تفعيل'))) {
      icon = isNonCash ? LucideIcons.creditCard : LucideIcons.zap;
      tone = isNonCash ? RpTone.debt : RpTone.money;
    } else if (at == 'SUBSCRIBER_EXTEND') {
      icon = LucideIcons.repeat;
      tone = isNonCash ? RpTone.debt : RpTone.brand;
    } else if (at == 'DEBT_PAY' || at == 'BALANCE_DEDUCT' || at == 'PAYMENT_ADD') {
      icon = LucideIcons.banknote;
      tone = RpTone.money;
    } else if (at == 'BALANCE_ADD' && l.isCredit) {
      icon = l.creditKind == 'comp' ? LucideIcons.gift : LucideIcons.coins;
      tone = l.creditKind == 'cash' ? RpTone.money : RpTone.neutral;
    } else if (at == 'BALANCE_ADD') {
      icon = LucideIcons.plus;
      tone = RpTone.debt;
    } else if (at == 'ADMIN_EXPENSE' || at == 'EXPENSE_ADD') {
      icon = LucideIcons.receipt;
      tone = RpTone.loss;
      negative = true;
    } else if (l.isSale) {
      icon = LucideIcons.shoppingCart;
      tone = RpTone.money;
    } else {
      icon = LucideIcons.activity;
      tone = RpTone.neutral;
    }
    final label = arabicActionLabel(l.actionType, desc);
    final actor = (l.actingEmployeeFullName ?? '').trim().isNotEmpty ? l.actingEmployeeFullName!.trim() : (l.adminUsername ?? '').trim();
    final detail = [
      desc.isNotEmpty ? desc : label,
      if (actor.isNotEmpty) actor,
    ].join(' · ');
    final t = timeOf(l);
    String two(int n) => n.toString().padLeft(2, '0');
    final name = [l.userFullName, l.targetName, l.userUsername].firstWhere((s) => (s ?? '').trim().isNotEmpty, orElse: () => null);
    return RpRow(
      icon: icon,
      tone: tone,
      title: name ?? label,
      detail: detail,
      amount: l.amount.abs(),
      negative: negative && l.amount != 0,
      time: t == null || _dateOnly(l.createdAt) ? '' : '${two(t.hour)}:${two(t.minute)}',
      company: company,
      cost: showCost ? FinanceLogs.costLine(l) : null,
      balanceAfter: l.balanceAfter,
    );
  }

  /// الحركات مجمّعةً باليوم (بتوقيت الجهاز = بغداد)، الأحدث أوّلاً، و[limit] سطراً أوّلاً — ومجموع كلّ يوم = ما دخل نقداً.
  static List<RpDay> days(List<FinanceLog> logs, {RpCompany? Function(FinanceLog)? companyOf, bool showCost = false, int? limit}) {
    final byDay = <String, List<FinanceLog>>{};
    final order = <String>[];
    for (final l in logs) {
      final t = timeOf(l);
      final key = t == null ? '' : iqDateOf(t);
      if (!byDay.containsKey(key)) order.add(key);
      (byDay[key] ??= []).add(l);
    }
    final out = <RpDay>[];
    var left = limit ?? 1 << 30;
    for (final k in order) {
      if (left <= 0) break;
      final all = byDay[k]!;
      final shown = all.take(left).toList();
      left -= shown.length;
      out.add(RpDay(
        date: k.isEmpty ? 'بلا تاريخ' : k,
        count: all.length,
        sum: all.fold<num>(0, (a, l) => a + FinanceLogs.cashOf(l)),
        rows: [for (final l in shown) row(l, company: companyOf?.call(l), showCost: showCost)],
      ));
    }
    return out;
  }

  /// بحث السطور: اسم المشترك أو يوزره أو الهدف أو الوصف (الأرقام بأيّ صيغة).
  static List<FinanceLog> search(List<FinanceLog> logs, String q) {
    final needle = (normalizeDigits(q) ?? '').trim().toLowerCase();
    if (needle.isEmpty) return logs;
    bool hit(String? s) => (normalizeDigits(s) ?? '').toLowerCase().contains(needle);
    return logs
        .where((l) => hit(l.userFullName) || hit(l.userUsername) || hit(l.targetName) || hit(l.actionDescription))
        .toList();
  }

  /// السطور مقطوعة عند سقف الخادم (1000) أو قال إنّ السجلّ ناقص — ما يُحسب منها لا يمثّل الفترة كلّها.
  static bool truncated(FinanceReport r) =>
      r.unavailableParts.contains('recent_logs') || r.recentLogs.length >= PackageCostKpis.recentLogsServerCap;

  /// «يوماً بيوم» من سلسلة الخادم: أيّامٌ متّصلة (اليوم بلا حركة صفر)، وما زاد عن شهرين يُجمع شهراً شهراً.
  static List<RpTrendPoint> trend(List<FinanceDayRow> series, RpRange range) {
    if (range.days < 2) return const [];
    final byDay = {for (final r in series) iqDateOf(r.day): r};
    if (range.days <= 62) {
      final out = <RpTrendPoint>[];
      for (var i = 0; i < range.days; i++) {
        final d = DateTime(range.from.year, range.from.month, range.from.day + i);
        final r = byDay[iqDateOf(d)];
        out.add(RpTrendPoint(d.day, r?.revenue ?? 0, r?.debt ?? 0));
      }
      return out;
    }
    final byMonth = <int, (num, num)>{};
    for (final r in series) {
      final k = r.day.year * 12 + r.day.month;
      final p = byMonth[k] ?? (0, 0);
      byMonth[k] = (p.$1 + r.revenue, p.$2 + (r.debt ?? 0));
    }
    final out = <RpTrendPoint>[];
    for (var k = range.from.year * 12 + range.from.month; k <= range.to.year * 12 + range.to.month; k++) {
      final m = (k - 1) % 12 + 1;
      final p = byMonth[k] ?? (0, 0);
      out.add(RpTrendPoint(m, p.$1, p.$2));
    }
    return out;
  }
}
