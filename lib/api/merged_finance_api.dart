import 'dart:collection';

import '../models/merged_company.dart';
import 'archive_info.dart';
import 'company_route.dart';
import 'merged_dashboard_api.dart';
import 'reports_api.dart';

/// تقرير شركةٍ واحدة في «كل الشركات» — أو سبب خروجها من المجموع.
class MergedFinancePart {
  const MergedFinancePart({required this.company, this.report, this.reason});

  final MergedCompany company;

  /// تقريرها كما وصل (null: تعذّر).
  final FinanceReport? report;

  /// سبب خروجها من المجموع (null: داخله).
  final String? reason;

  bool get included => report != null && reason == null;
}

/// التقارير ومجموعها.
class MergedFinanceResult {
  const MergedFinanceResult({required this.parts, required this.report, required this.logCompany});

  final List<MergedFinancePart> parts;

  /// التقرير المجموع (أرقامٌ مجموعة + حركات الشركات معاً + أرشيفها) — null: لم تدخل شركةٌ واحدة.
  final FinanceReport? report;

  /// شركة كلّ حركة (بهويّة الحركة نفسها).
  final Map<FinanceLog, String> logCompany;

  List<MergedFinancePart> get included => parts.where((p) => p.included).toList();

  /// «الاسم: السبب» لكلّ شركةٍ خارج المجموع.
  List<String> get excluded => [
        for (final p in parts)
          if (!p.included) '${p.company.name}: ${p.reason ?? 'تعذّر جلب تقريرها'}',
      ];

  /// شركاتٌ داخل المجموع سجلّ حركاتها ناقص (recent_logs) — الأرقام سليمة.
  List<String> get logsPartial => [
        for (final p in parts)
          if (p.included && p.report!.unavailableParts.contains('recent_logs')) p.company.name,
      ];

  /// المجموع خليطٌ من قاعدتين: شركةٌ تُطرح من صافيها كلفة الباقات وأخرى بلاها (سوبرنت).
  bool get mixedProfitRules {
    final inc = included;
    return inc.any((p) => p.report!.kpis.packageCost != null) && inc.any((p) => p.report!.kpis.packageCost == null);
  }

  MergedFinancePart? partOf(String key) {
    for (final p in parts) {
      if (p.company.key == key) return p;
    }
    return null;
  }
}

/// «كل الشركات» — التقرير الماليّ (٢١ أكتوبر، المالك: «حتى التقارير المالية»): تقريرٌ لكلّ شركة من معالجها نفسه
/// (GET /api/reports/finance موجَّهاً، user_ids = مديرها وحده كما يطلبه الوضع العاديّ لشركته — scope_helper)، يُحسب بقاعدة
/// شركته، ثمّ يُجمع كالويب (client-v2 pages/reports/financial-figures.ts sumFigures/financeMoneyGap): الدينار وحده يُجمع؛
/// تقريرٌ تعذّر أو جزءُ مالٍ تعذّر يُسمّى ولا يُجمع صفراً؛ الصافي مجموع صافي كلّ شركةٍ بقاعدتها (سوبرنت بلا كلفة الباقات)؛
/// وربطان للمدير نفسه تقريرٌ واحد (countable).
class MergedFinanceApi {
  MergedFinanceApi._();

  /// تقرير شركةٍ واحدة موجَّهاً — طلب الشاشة العاديّة نفسه لشركتها.
  static Future<({bool ok, FinanceReport? data, String? error})> one(
    MergedCompany c, {
    DateTime? from,
    DateTime? to,
    bool includeArchived = false,
  }) =>
      CompanyRoute.run(
        c.key,
        () => ReportsApi.finance(
          from: from,
          to: to,
          userIds: [c.adminId],
          recentLimit: 2000,
          includeArchived: includeArchived,
          withPackageCost: isCostBearingAdminId(c.adminId),
        ),
      );

  /// سبب خروج تقريرٍ وصل من المجموع (null: يدخل).
  static String? gapReason(MergedCompany c, FinanceReport r) {
    switch (r.moneyGap) {
      case 'reply':
        return 'تعذّر تقريرها الآن';
      case 'activations':
        return 'تعذّرت قراءة تفعيلاتها';
      case 'expenses':
        return 'تعذّرت قراءة صرفياتها';
      case 'other':
        return 'تعذّرت قراءة جزءٍ من أرقامها';
    }
    if (c.currency != 'IQD') return c.currency ?? 'عملةٌ غير معروفة';
    return null;
  }

  static Future<MergedFinanceResult> load({DateTime? from, DateTime? to, bool includeArchived = false}) async {
    final cs = MergedDashboardApi.countable();
    final res = await Future.wait([
      for (final c in cs) one(c, from: from, to: to, includeArchived: includeArchived),
    ]);
    final parts = <MergedFinancePart>[
      for (var i = 0; i < cs.length; i++)
        if (!res[i].ok || res[i].data == null)
          MergedFinancePart(company: cs[i], reason: res[i].error ?? 'تعذّر جلب تقريرها')
        else
          MergedFinancePart(company: cs[i], report: res[i].data, reason: gapReason(cs[i], res[i].data!)),
    ];
    return combine(parts);
  }

  /// المجموع من تقارير الشركات (منفصلةٌ للاختبار).
  static MergedFinanceResult combine(List<MergedFinancePart> parts) {
    final inc = parts.where((p) => p.included).toList();
    final logCompany = LinkedHashMap<FinanceLog, String>.identity();
    final tagged = <({FinanceLog log, int order, int at})>[];
    var order = 0;
    for (final p in parts) {
      // حركات الشركة الخارجة من المجموع لا تُعرض تحته (أرقامها مجهولة)
      if (!p.included) continue;
      for (final l in p.report!.recentLogs) {
        logCompany[l] = p.company.key;
        tagged.add((log: l, order: order++, at: _ms(l.createdAt)));
      }
    }
    // الأحدث أوّلاً — والتعادل بترتيب الشركات ثمّ ترتيب الخادم (فرزٌ ثابت)
    tagged.sort((a, b) => a.at != b.at ? b.at.compareTo(a.at) : a.order.compareTo(b.order));
    final report = inc.isEmpty
        ? null
        : FinanceReport(
            kpis: sumKpis([for (final p in inc) p.report!.kpis]),
            recentLogs: [for (final t in tagged) t.log],
            archive: mergeArchive([for (final p in inc) p.report!.archive]),
            unavailableParts: [
              if (inc.any((p) => p.report!.unavailableParts.contains('recent_logs'))) 'recent_logs',
            ],
          );
    return MergedFinanceResult(parts: parts, report: report, logCompany: logCompany);
  }

  static int _ms(String v) {
    final t = v.trim();
    if (t.isEmpty) return 0;
    return (DateTime.tryParse(t) ?? DateTime.tryParse(t.replaceFirst(' ', 'T')))?.millisecondsSinceEpoch ?? 0;
  }

  /// مجموع أرقام عدّة شركات: كلّ رقمٍ يُجمع كما هو؛ الكلفة كلفة من تُطرح عنده وحده؛ والصافي بعد الكلفة مجموع صافي كلّ
  /// شركةٍ بقاعدتها — من بلا كلفة صافيه النقديّ (الشاشة نفسها لشركته وحدها). قائمةٌ فارغة ⇒ أصفار.
  static FinanceKPIs sumKpis(List<FinanceKPIs> ks) {
    num n(num Function(FinanceKPIs k) f) => ks.fold<num>(0, (a, k) => a + f(k));
    int i(int Function(FinanceKPIs k) f) => ks.fold<int>(0, (a, k) => a + f(k));
    final costs = [
      for (final k in ks)
        if (k.packageCost != null) k.packageCost!,
    ];
    final cost = costs.isEmpty
        ? null
        : PackageCostKpis(
            sum: costs.fold<num>(0, (a, c) => a + c.sum),
            rows: costs.fold<int>(0, (a, c) => a + c.rows),
            knownRows: costs.fold<int>(0, (a, c) => a + c.knownRows),
            estimatedRows: costs.fold<int>(0, (a, c) => a + c.estimatedRows),
            hasEstimates: costs.any((c) => c.hasEstimates),
          );
    return FinanceKPIs(
      paymentsSum: n((k) => k.paymentsSum),
      debtPaySum: n((k) => k.debtPaySum),
      balanceDeductSum: n((k) => k.balanceDeductSum),
      activateCashSum: n((k) => k.activateCashSum),
      balanceAddSum: n((k) => k.balanceAddSum),
      activateNonCashSum: n((k) => k.activateNonCashSum),
      expensesSum: n((k) => k.expensesSum),
      expensesCount: i((k) => k.expensesCount),
      managerDebtsOutstanding: n((k) => k.managerDebtsOutstanding),
      activationsCount: i((k) => k.activationsCount),
      extendCount: i((k) => k.extendCount),
      packageCost: cost,
      partialUnpaidFromLogs: n((k) => k.partialUnpaidFromLogs),
      profitAfterCostOverride: cost == null ? null : n((k) => k.profitAfterCost ?? k.netCash),
    );
  }

  /// شريط الأرشيف لعدّة شركات — قاعدة الويب (mergeArchiveMeta): مجموع التسويات، ورقم أحدثها قطعاً.
  static ArchiveInfo? mergeArchive(List<ArchiveInfo?> metas) {
    final list = metas.whereType<ArchiveInfo>().toList();
    if (list.isEmpty) return null;
    var settlements = 0;
    DateTime? lastCut;
    int? lastNumber;
    for (final m in list) {
      settlements += m.settlements;
      final cut = m.lastCutAt;
      if (cut != null && (lastCut == null || cut.isAfter(lastCut))) {
        lastCut = cut;
        lastNumber = m.lastNumber;
      }
    }
    return ArchiveInfo(
      hidden: list.any((m) => m.hidden),
      included: list.any((m) => m.included),
      settlements: settlements,
      lastNumber: lastNumber,
      lastCutAt: lastCut,
    );
  }
}
