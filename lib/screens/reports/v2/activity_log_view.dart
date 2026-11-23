import 'package:easy_localization/easy_localization.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/reports_api.dart';
import '../../../core/util/ar_date.dart';
import '../../../core/util/format.dart';
import '../../../core/util/server_time.dart';
import '../widgets/action_labels.dart';
import '../widgets/report_filters.dart';
import 'report_kit.dart';
import 'report_period.dart';

// «سجلّ الحركات» على الشكل الموحّد (٢٢ نوفمبر): كلّ حركات الفترة صفحةً صفحة بلا الإشعارات الآليّة (الخادم 9bfabd2 يستثنيها، فلا
// تملأ السقف فتنقص الحركات بصمت)، والصرفيّات من قائمتها كما كانت. سجلّ تدقيق: أعدادٌ لا أرباح — المال يُعرض على سطره وحده.

class LogKpiIds {
  static const all = 'all';
  static const subs = 'subs';
  static const debts = 'debts';
  static const expenses = 'expenses';
}

class ActivityLogView {
  ActivityLogView._();

  /// إشعاراتٌ آليّة لا تخصّ السجلّ (مطلب ٢٠٢٦-٠٧-١٢) — تُستثنى من الخادم.
  static const excluded = ['EXPIRY_NOTIFICATION', 'NEAR_EXPIRY_NOTIFICATION', 'AUTO_NOTIFICATION'];

  /// أنواع الصرفيّة (من قائمة الصرفيّات لا من السجلّ).
  static const expenseTypes = {'ADMIN_EXPENSE', 'EXPENSE_ADD'};

  static const _subs = {'SUBSCRIBER_ACTIVATE', 'SUBSCRIBER_EXTEND', 'SUBSCRIBER_ADD'};
  static const _debts = {'DEBT_PAY', 'BALANCE_DEDUCT', 'BALANCE_ADD', 'PAYMENT_ADD'};

  static String at(ActivityRow r) => r.actionType.toUpperCase().trim();

  static List<(String, String)> get typeOptions => [for (final t in kAllActionTypes) (t.key, t.displayLabel)];

  static String typeLabel(String key) {
    for (final t in kAllActionTypes) {
      if (t.key == key) return t.displayLabel;
    }
    return key;
  }

  static List<ActivityRow> filter(List<ActivityRow> rows, List<String> types) {
    final base = rows.where((r) => !excluded.contains(at(r)));
    if (types.isEmpty) return base.toList();
    final want = types.toSet();
    return base.where((r) => want.contains(at(r))).toList();
  }

  /// مال السطر كما يُعرض: الصرفيّة مبلغها، وحركات المال `money_amount` الخادم (قاعدة التقرير الماليّ)؛ غيرها بلا رقم.
  static num? moneyOf(ActivityRow r) {
    final t = at(r);
    if (expenseTypes.contains(t)) return r.amount;
    if (_debts.contains(t) || t == 'SUBSCRIBER_ACTIVATE' || t == 'SUBSCRIBER_ADD') {
      final m = r.moneyAmount;
      return m == null || m == 0 ? null : m.abs();
    }
    return null;
  }

  static List<RpKpi> kpis(List<ActivityRow> rows) {
    var subs = 0, debts = 0, exp = 0;
    for (final r in rows) {
      final t = at(r);
      if (_subs.contains(t)) subs++;
      if (_debts.contains(t)) debts++;
      if (expenseTypes.contains(t)) exp++;
    }
    return [
      RpKpi(id: LogKpiIds.all, label: 'الحركات', value: rows.length, unit: 'حركة', isCount: true, icon: LucideIcons.history, tone: RpTone.brand),
      RpKpi(id: LogKpiIds.subs, label: 'تفعيل وتمديد', value: subs, isCount: true, icon: LucideIcons.zap, tone: RpTone.money),
      RpKpi(id: LogKpiIds.debts, label: 'تسديد وديون', value: debts, isCount: true, icon: LucideIcons.banknote, tone: RpTone.debt),
      RpKpi(id: LogKpiIds.expenses, label: 'صرفيّات', value: exp, isCount: true, icon: LucideIcons.receipt, tone: RpTone.loss),
    ];
  }

  static bool Function(ActivityRow) drill(String id) => switch (id) {
        LogKpiIds.subs => (r) => _subs.contains(at(r)),
        LogKpiIds.debts => (r) => _debts.contains(at(r)),
        LogKpiIds.expenses => (r) => expenseTypes.contains(at(r)),
        _ => (_) => true,
      };

  static DateTime? timeOf(ActivityRow r) => parseServerUtc(r.createdAt);
  static bool _dateOnly(String s) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s.trim());

  static String actorOf(ActivityRow r) =>
      (r.actingEmployeeFullName ?? '').trim().isNotEmpty ? r.actingEmployeeFullName!.trim() : (r.adminUsername ?? '').trim();

  static RpRow row(ActivityRow r, {RpCompany? company}) {
    final t = at(r);
    final desc = (r.actionDescription ?? '').trim();
    final label = arabicActionLabel(r.actionType, desc);
    final (icon, tone) = switch (t) {
      'SUBSCRIBER_ACTIVATE' || 'SUBSCRIBER_ADD' => desc.contains('غير نقدي') ? (LucideIcons.creditCard, RpTone.debt) : (LucideIcons.zap, RpTone.money),
      'SUBSCRIBER_EXTEND' => (LucideIcons.repeat, RpTone.info),
      'DEBT_PAY' || 'BALANCE_DEDUCT' || 'PAYMENT_ADD' => (LucideIcons.banknote, RpTone.money),
      'BALANCE_ADD' => (LucideIcons.plus, RpTone.debt),
      'ADMIN_EXPENSE' || 'EXPENSE_ADD' => (LucideIcons.receipt, RpTone.loss),
      'SUBSCRIBER_DELETE' || 'MANAGER_DELETE' || 'DISCOUNT_REMOVE' => (LucideIcons.trash2, RpTone.loss),
      _ => (LucideIcons.pencil, RpTone.neutral),
    };
    final tm = timeOf(r);
    // التعديل بما تغيّر «من … إلى …» (المالك ٢٢ نوفمبر) — لا «تعديل المشترك — phone»
    final title = rpSubjectTitle(fullName: r.userFullName, target: r.targetName, username: r.userUsername, fallback: label);
    final head = rpHideUser(r.editSummary ?? (desc.isNotEmpty ? desc : label), r.userUsername ?? r.targetName);
    // «العربي ومن ثم اليوزر» (٢٣ نوفمبر): اليوزر بعد الاسم ما لم يحمله الوصف أصلاً
    final user = rpUserAfterName(title: title, username: r.userUsername ?? r.targetName, detail: head);
    final detail = [
      head,
      if (user != null) user,
      if (actorOf(r).isNotEmpty) actorOf(r),
    ].join(' · ');
    return RpRow(
      icon: icon,
      tone: tone,
      title: title,
      detail: detail,
      amount: moneyOf(r),
      negative: expenseTypes.contains(t) && (moneyOf(r) ?? 0) != 0,
      time: tm == null || _dateOnly(r.createdAt) ? '' : clock12Ar(tm),
      company: company,
      balanceAfter: r.balanceAfter,
    );
  }

  /// الأيّام الأحدث أوّلاً — ومجموع اليوم: ما دخل نقداً (تفعيلٌ نقديّ، تسديد) — صرفيّات اليوم لا تُطرح هنا (سجلٌّ لا صندوق).
  static List<RpDay> days(List<ActivityRow> rows, {RpCompany? Function(ActivityRow)? companyOf, int? limit}) {
    final byDay = <String, List<ActivityRow>>{};
    final order = <String>[];
    for (final r in rows) {
      final t = timeOf(r);
      final key = t == null ? (r.createdAt.length >= 10 ? r.createdAt.substring(0, 10).replaceAll('-', '/') : '') : iqDateOf(t);
      if (!byDay.containsKey(key)) order.add(key);
      (byDay[key] ??= []).add(r);
    }
    num cashOf(ActivityRow r) {
      final t = at(r);
      final d = r.actionDescription ?? '';
      if ((t == 'SUBSCRIBER_ACTIVATE' || t == 'SUBSCRIBER_ADD') && !r.fromSas && !d.contains('غير نقدي')) return r.moneyAmount ?? 0;
      if (t == 'DEBT_PAY' || t == 'BALANCE_DEDUCT' || t == 'PAYMENT_ADD') return r.moneyAmount ?? 0;
      return 0;
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
        sum: all.fold<num>(0, (a, r) => a + cashOf(r)),
        rows: [for (final r in shown) row(r, company: companyOf?.call(r))],
      ));
    }
    return out;
  }

  static List<ActivityRow> search(List<ActivityRow> rows, String q) {
    final needle = (normalizeDigits(q) ?? '').trim().toLowerCase();
    if (needle.isEmpty) return rows;
    bool hit(String? s) => (normalizeDigits(s) ?? '').toLowerCase().contains(needle);
    return rows
        .where((r) => hit(r.userFullName) || hit(r.userUsername) || hit(r.targetName) || hit(r.actionDescription) || hit(actorOf(r)))
        .toList();
  }

  /// عدد الحركات يوماً بيوم (أو شهراً بشهر).
  static List<RpTrendPoint> trend(List<ActivityRow> rows, RpRange range) {
    if (range.days < 2) return const [];
    final monthly = range.days > 62;
    final n = <int, int>{};
    int keyOf(DateTime t) => monthly ? t.year * 12 + t.month : DateTime.utc(t.year, t.month, t.day).millisecondsSinceEpoch ~/ 86400000;
    for (final r in rows) {
      final t = timeOf(r);
      if (t == null) continue;
      n[keyOf(t)] = (n[keyOf(t)] ?? 0) + 1;
    }
    if (!monthly) {
      return [
        for (var i = 0; i < range.days; i++)
          (() {
            final d = DateTime(range.from.year, range.from.month, range.from.day + i);
            return RpTrendPoint(d.day, n[keyOf(d)] ?? 0, 0);
          })(),
      ];
    }
    return [
      for (var k = range.from.year * 12 + range.from.month; k <= range.to.year * 12 + range.to.month; k++)
        RpTrendPoint((k - 1) % 12 + 1, n[k] ?? 0, 0),
    ];
  }

  static List<RpShare> shares(List<ActivityRow> rows, String Function(ActivityRow) keyOf, {RpCompany? Function(ActivityRow)? companyOf}) {
    final acc = <String, ({String name, num amount, int count, RpCompany? co})>{};
    for (final r in rows) {
      final co = companyOf?.call(r);
      final name = keyOf(r);
      final k = '${co?.key ?? ''}|$name';
      final o = acc[k];
      acc[k] = (name: name, amount: (o?.amount ?? 0) + (moneyOf(r) ?? 0), count: (o?.count ?? 0) + 1, co: co);
    }
    final total = acc.values.fold<int>(0, (a, v) => a + v.count);
    final list = acc.values.toList()..sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : b.amount.compareTo(a.amount));
    return [
      for (final v in list) RpShare(name: v.name, amount: v.amount, count: v.count, share: total == 0 ? 0 : v.count / total, company: v.co),
    ];
  }

  /// صرفيّةٌ بشكل سطرٍ من السجلّ (كالشاشة السابقة): معرّفٌ بعيد كي لا يصطدم بالسجلّ.
  static ActivityRow expenseRow({required int id, required num amount, required String date, String? note, String? actor}) => ActivityRow(
        id: 900000000 + id,
        actionType: 'EXPENSE_ADD',
        actionDescription: (note ?? '').trim().isEmpty ? 'actions.expense'.tr() : note,
        amount: amount,
        actingEmployeeFullName: actor,
        createdAt: date,
      );
}
