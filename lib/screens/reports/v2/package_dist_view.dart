import '../../../api/package_report_api.dart';
import '../../../core/util/format.dart';
import 'report_kit.dart';

// «توزيع الباقات» على الشكل الموحّد (٢٢ نوفمبر — «اكمل كلشي»): المجاميع منقولةٌ حرفاً من PackageDistributionScreen — المشتركون
// والتفعيلات من كلّ شركةٍ قُرئت، الإيراد بالدينار وحده، والربح مجموع ربح كلّ شركةٍ بقاعدتها (المعفاة بلا كلفة)، ومن لا يُعرف
// رقمها تُسمّى («لا يشمل: …») لا صفرٌ صامت.

/// تقرير شركةٍ قُرئ — [key] مفتاحها في «كل الشركات» (null = المفتوحة)، و[currency] عملتها.
class PkgPart {
  const PkgPart({required this.report, this.key, this.name, this.currency = 'IQD'});
  final PackageReport report;
  final String? key;
  final String? name;
  final String? currency;

  bool get iqd => currency == 'IQD';
}

/// باقةٌ بشركتها.
class PkgRow {
  const PkgRow(this.part, this.row);
  final PkgPart part;
  final PackageReportRow row;

  int get moves => row.activations + row.extensions;
}

/// ما يُعرض فوق القائمة — وكلّ رقمٍ بمن لا يشمله.
class PkgTotals {
  const PkgTotals({
    required this.subscribers,
    required this.active,
    required this.activations,
    required this.extensions,
    required this.revenue,
    required this.cost,
    required this.profit,
    required this.estimated,
    required this.subsOut,
    required this.movesOut,
    required this.revenueOut,
    required this.profitOut,
    required this.estOut,
    required this.owner,
    required this.anyExempt,
    required this.allExempt,
  });

  /// null = لم يُعرف لأيّ شركة.
  final int? subscribers;
  final int? active;
  final int activations;
  final int extensions;
  final num revenue;
  final num? cost;
  final num? profit;
  final num? estimated;
  final List<String> subsOut;
  final List<String> movesOut;
  final List<String> revenueOut;
  final List<String> profitOut;
  final List<String> estOut;

  /// صاحب الحساب في شركةٍ واحدةٍ على الأقلّ (الكلفة والربح في الردّ — قرار الخادم).
  final bool owner;
  final bool anyExempt;
  final bool allExempt;
}

enum PkgTab { subscribers, moves, revenue, profit }

class PackageDistView {
  PackageDistView._();

  static PkgTotals totals(List<PkgPart> ok, {List<String> unread = const []}) {
    int? sumOf(int? Function(PackageReport r) f) {
      final known = [for (final p in ok) if (f(p.report) != null) f(p.report)!];
      return known.isEmpty ? null : known.fold<int>(0, (a, v) => a + v);
    }

    // أسماءٌ بلا تكرار ولا فراغ (المفتوحة وحدها بلا اسم: نقصها يُقال بتنبيه أجزائها)
    List<String> names(Iterable<PkgPart> ps) => [
          ...{...unread, for (final p in ps) p.name ?? ''}.where((n) => n.isNotEmpty),
        ];
    // حركات الفترة تعذّرت ⇒ تفعيلاتها وإيرادها وربحها ليست صفراً حقيقيّاً
    bool noActivity(PkgPart p) => p.report.unavailableParts.contains('activity');
    final iqd = [for (final p in ok) if (p.iqd && !noActivity(p)) p];
    final withProfit = [for (final p in iqd) if (p.report.owner && p.report.totals.profitTotal != null) p];
    final withEst = [for (final p in iqd) if (p.report.owner && p.report.totals.profitEstimated != null) p];
    final withCost = [for (final p in iqd) if (p.report.owner && p.report.totals.cost != null) p];
    final moving = [for (final p in ok) if (!noActivity(p)) p];
    return PkgTotals(
      subscribers: sumOf((r) => r.totals.subscribersTotal),
      active: sumOf((r) => r.totals.subscribersActive),
      activations: moving.fold<int>(0, (a, p) => a + p.report.totals.activations),
      extensions: moving.fold<int>(0, (a, p) => a + p.report.totals.extensions),
      revenue: iqd.fold<num>(0, (a, p) => a + p.report.totals.revenue),
      cost: withCost.isEmpty ? null : withCost.fold<num>(0, (a, p) => a + p.report.totals.cost!),
      profit: withProfit.isEmpty ? null : withProfit.fold<num>(0, (a, p) => a + p.report.totals.profitTotal!),
      estimated: withEst.isEmpty ? null : withEst.fold<num>(0, (a, p) => a + p.report.totals.profitEstimated!),
      subsOut: names([for (final p in ok) if (p.report.totals.subscribersTotal == null) p]),
      movesOut: names([for (final p in ok) if (noActivity(p)) p]),
      revenueOut: names([for (final p in ok) if (!iqd.contains(p)) p]),
      // كالشاشة السابقة: كلّ شركةٍ قُرئت ولا يُعرف ربحها تُسمّى (موظّفٌ فيها، أو كلفتها تعذّرت، أو عملتها أخرى)
      profitOut: names([for (final p in ok) if (!withProfit.contains(p)) p]),
      estOut: names([for (final p in ok) if (!withEst.contains(p)) p]),
      owner: ok.any((p) => p.report.owner),
      anyExempt: withProfit.any((p) => p.report.costExempt),
      allExempt: withProfit.isNotEmpty && withProfit.every((p) => p.report.costExempt),
    );
  }

  /// باقات كلّ الشركات معاً.
  static List<PkgRow> rows(List<PkgPart> ok) => [
        for (final p in ok)
          for (final r in p.report.rows) PkgRow(p, r),
      ];

  /// ترتيب التبويب: الأكبر أوّلاً، ثمّ الأكثر حركة، ثمّ الاسم. الإيراد والربح لباقات الدينار وحدها (لا جمع عملتين)، والربح لصاحب
  /// الحساب وحده.
  static List<PkgRow> ordered(List<PkgRow> rows, PkgTab tab) {
    num metric(PkgRow r) => switch (tab) {
          PkgTab.subscribers => r.row.subscribersTotal ?? -1,
          PkgTab.moves => r.moves,
          PkgTab.revenue => r.row.revenue,
          PkgTab.profit => r.row.profitTotal ?? double.negativeInfinity,
        };
    final list = [
      for (final r in rows)
        if (switch (tab) {
          PkgTab.revenue => r.part.iqd,
          PkgTab.profit => r.part.iqd && r.part.report.owner && r.row.profitTotal != null,
          _ => true,
        })
          r,
    ];
    list.sort((a, b) {
      final c = metric(b).compareTo(metric(a));
      if (c != 0) return c;
      final d = b.moves.compareTo(a.moves);
      return d != 0 ? d : a.row.name.compareTo(b.row.name);
    });
    return list;
  }

  static String countText(int? v) => v == null ? '—' : formatIQD(v);

  static RpShare share(PkgRow r, PkgTab tab, num total, {RpCompany? company}) {
    final row = r.row;
    double part(num v) => total <= 0 || v <= 0 ? 0 : (v / total).clamp(0, 1).toDouble();
    return switch (tab) {
      PkgTab.subscribers => RpShare(
          name: row.name,
          amount: 0,
          count: row.subscribersTotal ?? 0,
          share: part(row.subscribersTotal ?? 0),
          company: company,
          sub: row.subscribersTotal == null ? 'العدد غير متاح' : 'فعّال ${countText(row.subscribersActive)}',
        ),
      PkgTab.moves => RpShare(
          name: row.name,
          amount: 0,
          count: r.moves,
          share: part(r.moves),
          company: company,
          sub: 'تفعيل ${formatIQD(row.activations)} · تمديد ${formatIQD(row.extensions)}',
        ),
      PkgTab.revenue => RpShare(
          name: row.name,
          amount: row.revenue,
          count: r.moves,
          share: part(row.revenue),
          company: company,
          sub: row.price == null ? null : 'سعر البيع ${formatIQD(row.price!)}',
        ),
      PkgTab.profit => RpShare(
          name: row.name,
          amount: row.profitTotal ?? 0,
          count: r.moves,
          share: part(row.profitTotal ?? 0),
          company: company,
          sub: row.cost == null ? 'الكلفة غير معروفة' : 'الكلفة ${formatIQD(row.cost!)}',
        ),
    };
  }

  /// مجموع التبويب الذي تُحسب منه الحصص (الموجب وحده للربح).
  static num totalOf(List<PkgRow> rows, PkgTab tab) => rows.fold<num>(0, (a, r) {
        final v = switch (tab) {
          PkgTab.subscribers => r.row.subscribersTotal ?? 0,
          PkgTab.moves => r.moves,
          PkgTab.revenue => r.row.revenue,
          PkgTab.profit => r.row.profitTotal ?? 0,
        };
        return v > 0 ? a + v : a;
      });
}
