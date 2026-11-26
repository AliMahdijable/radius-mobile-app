import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/employee_commissions_api.dart';
import '../../../api/reports_api.dart';
import '../../../core/util/ar_date.dart';
import '../../../core/util/format.dart';
import '../../../core/util/server_time.dart';
import '../../../services/pay_kinds.dart';
import 'report_kit.dart';
import 'report_period.dart';

// «التفعيلات» على الشكل الموحّد (٢٢ نوفمبر — المالك: «ادمج التفعيلات واليوميّة»): التقريران تقريرٌ واحد، و«اليوم» فترةٌ فيه.
// كلّ رقمٍ من سطور الفترة كاملةً (ReportsApi.activitiesAll) بقاعدة التقرير الماليّ نفسها: «نقداً» = مبالغ التفعيل غير «غير نقدي»
// وغير المزامَن (= activate_cash_sum)، و«بالدين» = «غير نقدي» + غير المدفوع من «نقدي جزئي» (= activate_non_cash_sum)، والعدّ يشمل
// المزامَن من الساس (= activations_count). المبلغ `money_amount` من الخادم — مجهولٌ ⇒ لا رقم مال (لا صفرٌ كاذب).

enum ActKind { cash, debt, sas, extend }

class ActKpiIds {
  static const activations = 'activations';
  static const extends_ = 'extends';
  static const cash = 'cash';
  static const debt = 'debt';
}

class ActivationsView {
  ActivationsView._();

  static const types = ['SUBSCRIBER_ACTIVATE', 'SUBSCRIBER_EXTEND', 'SUBSCRIBER_ADD'];

  static const noPackage = 'بلا باقة';
  static const noPackageExtend = 'تمديد (بلا باقة)';

  /// اسم الباقة كما في «قسّم حسب الباقة» وفلترها — action_data.package_name مشذّباً، وما بلا باقةٍ اسمٌ صريح يُختار أيضاً. القاعدة
  /// نفسها في فلتر الماليّ (الخادم يطابقها حرفاً: FinanceReportController PKG_NAME_SQL).
  static String packageNameOf(ActivityRow r) =>
      (r.packageName ?? '').isNotEmpty ? r.packageName! : (kindOf(r) == ActKind.extend ? noPackageExtend : noPackage);

  /// الاسم كما يطلبه الخادم في فلتر الماليّ الصارم (packages): ما بلا باقة برمزَيه (d9 ٢٢ نوفمبر — fintyped1122).
  static String serverPackage(String name) => name == noPackage ? ':none:activate' : (name == noPackageExtend ? ':none:extend' : name);

  /// تفعيلٌ (ومنه «إضافة مشترك» بتفعيل) أو تمديد — غيرهما لا يدخل التقرير.
  static bool relevant(ActivityRow r) {
    final at = r.actionType.toUpperCase().trim();
    return at == 'SUBSCRIBER_ACTIVATE' || at == 'SUBSCRIBER_EXTEND' || (at == 'SUBSCRIBER_ADD' && (r.actionDescription ?? '').contains('تفعيل'));
  }

  static ActKind kindOf(ActivityRow r) {
    if (r.actionType.toUpperCase().trim() == 'SUBSCRIBER_EXTEND') return ActKind.extend;
    if (r.fromSas) return ActKind.sas;
    return (r.actionDescription ?? '').contains('غير نقدي') ? ActKind.debt : ActKind.cash;
  }

  static String kindLabel(ActKind k) => switch (k) {
        ActKind.cash => 'تفعيل نقدي',
        ActKind.debt => 'تفعيل بالدين',
        ActKind.sas => 'تفعيل من الساس',
        ActKind.extend => 'تمديد',
      };

  /// أنواع ورقة الفلاتر (مفتاحٌ ثابت للحفظ).
  static const kindKeys = {'cash': ActKind.cash, 'debt': ActKind.debt, 'sas': ActKind.sas, 'extend': ActKind.extend};

  static List<ActivityRow> filter(List<ActivityRow> rows, List<String> kinds, {Set<String> pays = const {}}) {
    var base = rows.where(relevant);
    // «طريقة الدفع» (٢٤ نوفمبر): بطريقة السطر — يتقاطع مع النوع
    if (pays.isNotEmpty) base = base.where((r) => pays.contains(payOf(r)));
    if (kinds.isEmpty) return base.toList();
    final want = {for (final k in kinds) kindKeys[k]}..remove(null);
    return base.where((r) => want.contains(kindOf(r))).toList();
  }

  /// «طريقة الدفع» للسطر: ما كتبه الخادم (pay_kind)، وإلّا من نوعه — النقديّ كاش وغير النقديّ بالدين، وغيرهما بلا طريقة.
  static String? payOf(ActivityRow r) {
    if (r.payKind != null) return r.payKind;
    return switch (kindOf(r)) {
      ActKind.cash => 'cash',
      ActKind.debt => 'debt',
      _ => null,
    };
  }

  /// «تفعيل نقدي · ماستر» حين دُفع حوالةً — السطر والملفّ المصدَّر.
  static String kindWithVia(ActivityRow r, ActKind k) {
    final p = r.payKind;
    return (p == 'zaincash' || p == 'master' || p == 'other') ? '${kindLabel(k)} · ${PayKinds.labels[p]}' : kindLabel(k);
  }

  /// مال السطر: «نقداً» للنقديّ، و«بالدين» لغير النقديّ ولغير المدفوع من الجزئيّ. null = مجهول (خادمٌ بلا money_amount).
  static ({num? cash, num? debt}) moneyOf(ActivityRow r) {
    final m = r.moneyAmount;
    switch (kindOf(r)) {
      case ActKind.cash:
        return (cash: m, debt: m == null ? null : r.partialUnpaid);
      case ActKind.debt:
        return (cash: 0, debt: m);
      case ActKind.sas:
      case ActKind.extend:
        return (cash: 0, debt: 0);
    }
  }

  /// الأرقام — [known] false حين سطرٌ ماليّ بلا مبلغ من الخادم (لا يُعرض رقم مال).
  static ({int activations, int extends_, int cashCount, int debtCount, int sasCount, num cash, num debt, bool known}) totals(
      List<ActivityRow> rows) {
    var a = 0, e = 0, cc = 0, dc = 0, sc = 0;
    num cash = 0, debt = 0;
    var known = true;
    for (final r in rows) {
      final k = kindOf(r);
      if (k == ActKind.extend) {
        e++;
        continue;
      }
      a++;
      if (k == ActKind.cash) cc++;
      if (k == ActKind.debt) dc++;
      if (k == ActKind.sas) sc++;
      final m = moneyOf(r);
      if (m.cash == null || m.debt == null) {
        known = false;
        continue;
      }
      cash += m.cash!;
      debt += m.debt!;
    }
    return (activations: a, extends_: e, cashCount: cc, debtCount: dc, sasCount: sc, cash: cash, debt: debt, known: known);
  }

  static List<RpKpi> kpis(List<ActivityRow> rows, List<ActivityRow>? prev) {
    final t = totals(rows);
    final p = prev == null ? null : totals(prev);
    double? d(num cur, num? before) => p == null ? null : rpDelta(cur, before);
    return [
      RpKpi(
          id: ActKpiIds.activations,
          label: 'التفعيلات',
          value: t.activations,
          unit: 'تفعيل',
          isCount: true,
          icon: LucideIcons.zap,
          tone: RpTone.brand,
          delta: d(t.activations, p?.activations)),
      RpKpi(
          id: ActKpiIds.extends_,
          label: 'التمديدات',
          value: t.extends_,
          unit: 'تمديد',
          isCount: true,
          icon: LucideIcons.repeat,
          tone: RpTone.info,
          delta: d(t.extends_, p?.extends_)),
      if (t.known) ...[
        RpKpi(
            id: ActKpiIds.cash,
            label: 'نقداً',
            value: t.cash,
            icon: LucideIcons.wallet,
            tone: RpTone.money,
            delta: p == null || !p.known ? null : rpDelta(t.cash, p.cash)),
        RpKpi(
            id: ActKpiIds.debt,
            label: 'بالدين',
            value: t.debt,
            icon: LucideIcons.creditCard,
            tone: RpTone.debt,
            upIsGood: false,
            delta: p == null || !p.known ? null : rpDelta(t.debt, p.debt)),
      ],
    ];
  }

  static List<RpKpi> counts(List<ActivityRow> rows) {
    final t = totals(rows);
    return [
      RpKpi(label: 'نقداً', value: t.cashCount, icon: LucideIcons.wallet, tone: RpTone.money, isCount: true),
      RpKpi(label: 'بالدين', value: t.debtCount, icon: LucideIcons.creditCard, tone: RpTone.debt, isCount: true),
      RpKpi(label: 'من الساس', value: t.sasCount, icon: LucideIcons.refreshCw, tone: RpTone.neutral, isCount: true),
    ];
  }

  /// حركات بطاقةٍ لُمست.
  static bool Function(ActivityRow) drill(String id) => switch (id) {
        ActKpiIds.activations => (r) => kindOf(r) != ActKind.extend,
        ActKpiIds.extends_ => (r) => kindOf(r) == ActKind.extend,
        ActKpiIds.cash => (r) => kindOf(r) == ActKind.cash,
        ActKpiIds.debt => (r) => kindOf(r) == ActKind.debt || (kindOf(r) == ActKind.cash && r.partialUnpaid > 0),
        _ => (_) => true,
      };

  static DateTime? timeOf(ActivityRow r) => parseServerUtc(r.createdAt);
  static bool _dateOnly(String s) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s.trim());

  static String actorOf(ActivityRow r) =>
      (r.actingEmployeeFullName ?? '').trim().isNotEmpty ? r.actingEmployeeFullName!.trim() : (r.adminUsername ?? '').trim();

  /// [commission]: «عمولة الموظف» لهذا السطر (٢٦ نوفمبر — [EmpCommissions.of]) بعد «منها بالدين» إن وُجد — null ⇒ كما كان.
  static RpRow row(ActivityRow r, {RpCompany? company, num? commission}) {
    final k = kindOf(r);
    final m = moneyOf(r);
    final t = timeOf(r);
    final amount = k == ActKind.debt ? m.debt : m.cash;
    final title = rpSubjectTitle(fullName: r.userFullName, target: r.targetName, username: r.userUsername, fallback: kindLabel(k));
    // «العربي ومن ثم اليوزر» (٢٣ نوفمبر): اليوزر بعد النوع حين العنوان الاسم — كالتقرير الماليّ
    final user = rpUserAfterName(title: title, username: r.userUsername ?? r.targetName);
    final detail = [
      kindWithVia(r, k),
      if (user != null) user,
      if ((r.packageName ?? '').isNotEmpty) r.packageName!,
      if (actorOf(r).isNotEmpty) actorOf(r),
    ].join(' · ');
    return RpRow(
      icon: switch (k) {
        ActKind.cash => LucideIcons.zap,
        ActKind.debt => LucideIcons.creditCard,
        ActKind.sas => LucideIcons.refreshCw,
        ActKind.extend => LucideIcons.repeat,
      },
      tone: switch (k) {
        ActKind.cash => RpTone.money,
        ActKind.debt => RpTone.debt,
        ActKind.sas => RpTone.neutral,
        ActKind.extend => RpTone.info,
      },
      title: title,
      detail: detail,
      // التمديد والمزامَن من الساس بلا مال ⇒ بلا رقم؛ والمبلغ المجهول كذلك
      amount: k == ActKind.extend || k == ActKind.sas ? null : amount,
      time: t == null || _dateOnly(r.createdAt) ? '' : clock12Ar(t),
      company: company,
      cost: withEmpCommission(k == ActKind.cash && r.partialUnpaid > 0 ? 'منها بالدين ${formatIQD(r.partialUnpaid)}' : null, commission),
      balanceAfter: r.balanceAfter,
    );
  }

  /// الأيّام بتوقيت الجهاز الأحدث أوّلاً، ومجموع اليوم نقده.
  static List<RpDay> days(List<ActivityRow> rows, {RpCompany? Function(ActivityRow)? companyOf, int? limit, num? Function(ActivityRow)? commissionOf}) {
    final byDay = <String, List<ActivityRow>>{};
    final order = <String>[];
    for (final r in rows) {
      final t = timeOf(r);
      final key = t == null ? '' : iqDateOf(t);
      if (!byDay.containsKey(key)) order.add(key);
      (byDay[key] ??= []).add(r);
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
        sum: all.fold<num>(0, (a, r) => a + (moneyOf(r).cash ?? 0)),
        rows: [for (final r in shown) row(r, company: companyOf?.call(r), commission: commissionOf?.call(r))],
      ));
    }
    return out;
  }

  static List<ActivityRow> search(List<ActivityRow> rows, String q) {
    final needle = (normalizeDigits(q) ?? '').trim().toLowerCase();
    if (needle.isEmpty) return rows;
    bool hit(String? s) => (normalizeDigits(s) ?? '').toLowerCase().contains(needle);
    return rows
        .where((r) =>
            hit(r.userFullName) || hit(r.userUsername) || hit(r.targetName) || hit(r.packageName) || hit(r.actionDescription))
        .toList();
  }

  /// «العدد يوماً بيوم»: التفعيلات والتمديدات (باليوم حتى شهرين، وما زاد بالشهر).
  static List<RpTrendPoint> trend(List<ActivityRow> rows, RpRange range) {
    if (range.days < 2) return const [];
    final monthly = range.days > 62;
    final a = <int, int>{}, b = <int, int>{};
    int keyOf(DateTime t) => monthly ? t.year * 12 + t.month : DateTime.utc(t.year, t.month, t.day).millisecondsSinceEpoch ~/ 86400000;
    for (final r in rows) {
      final t = timeOf(r);
      if (t == null) continue;
      final k = keyOf(t);
      if (kindOf(r) == ActKind.extend) {
        b[k] = (b[k] ?? 0) + 1;
      } else {
        a[k] = (a[k] ?? 0) + 1;
      }
    }
    final out = <RpTrendPoint>[];
    if (!monthly) {
      for (var i = 0; i < range.days; i++) {
        final d = DateTime(range.from.year, range.from.month, range.from.day + i);
        final k = keyOf(d);
        out.add(RpTrendPoint(d.day, a[k] ?? 0, b[k] ?? 0));
      }
    } else {
      for (var k = range.from.year * 12 + range.from.month; k <= range.to.year * 12 + range.to.month; k++) {
        out.add(RpTrendPoint((k - 1) % 12 + 1, a[k] ?? 0, b[k] ?? 0));
      }
    }
    return out;
  }

  /// «قسّم حسب»: الاسم ⇒ (مال الفترة نقداً وبالدين، عدد الحركات). [keyOf] يعيد null لما لا يُعرف.
  static List<RpShare> shares(List<ActivityRow> rows, String Function(ActivityRow) keyOf,
      {RpCompany? Function(ActivityRow)? companyOf}) {
    final acc = <String, ({String name, num amount, int count, RpCompany? co})>{};
    for (final r in rows) {
      final co = companyOf?.call(r);
      final name = keyOf(r);
      final k = '${co?.key ?? ''}|$name';
      final m = moneyOf(r);
      final o = acc[k];
      acc[k] = (name: name, amount: (o?.amount ?? 0) + (m.cash ?? 0) + (m.debt ?? 0), count: (o?.count ?? 0) + 1, co: co);
    }
    final total = acc.values.fold<int>(0, (a, v) => a + v.count);
    final list = acc.values.toList()..sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : b.amount.compareTo(a.amount));
    return [
      for (final v in list) RpShare(name: v.name, amount: v.amount, count: v.count, share: total == 0 ? 0 : v.count / total, company: v.co),
    ];
  }
}
