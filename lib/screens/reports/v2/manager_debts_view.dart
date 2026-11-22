import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/manager_debts_api.dart';
import '../../../api/manager_movements_api.dart';
import '../../../api/managers_api.dart';
import '../../../core/util/ar_date.dart';
import '../../../core/util/server_time.dart';
import '../../../core/util/format.dart';
import 'report_kit.dart';

// «ديون المدراء» على الشكل الموحّد (٢٢ نوفمبر — «اكمل كلشي»): المنطق منقولٌ حرفاً من AllManagersDebtsScreen — أنواع الحركة الثمانية،
// «تسديد كامل» من الدين الآخر، و«إيرادات مستحصَلة» (شحن نقديّ + تسديد SAS + تسديد أخرى) تتبع كلّ الفلاتر، و«متبقّي SAS» من دين
// المدير الحاليّ عند الساس (بحث المدير وحده يحصره)، و«متبقّي أخرى» من ملخّص دفترنا، ودين مديرٍ لم يُقرأ يُسمّى ولا يُجمع.

/// نوع الحركة كما في الشاشة السابقة (مفاتيح الورقة ثابتة للحفظ).
enum MgrKind { depositCash, depositLoan, debtCreated, paymentSas, paymentCustom, withdraw, points, other }

class MgrEvent {
  const MgrEvent({required this.manager, required this.movement, this.isFullPayment = false, this.companyKey, this.loanInCustom = false});

  /// شركةٌ بلا دين ساس (ايرث لنك): «شحن آجل» دينه في «ديون أخرى» لا عند الساس.
  final bool loanInCustom;

  final Manager manager;
  final ManagerMovement movement;
  final bool isFullPayment;

  /// «كل الشركات»: شركة المدير — معرّفات المدراء الفرعيّين أرقام ساس كلّ شركة فتتكرّر بين الشركات.
  final String? companyKey;

  DateTime get date => movement.eventAt;
  double get amount => movement.amount.toDouble();
  String get managerName => manager.fullName.isEmpty ? manager.username : manager.fullName;

  MgrKind get kind {
    switch (movement.rowType) {
      case 'debt_created':
        return MgrKind.debtCreated;
      case 'debt_payment':
        return MgrKind.paymentCustom;
    }
    switch (movement.subKind) {
      case 'deposit_cash':
        return MgrKind.depositCash;
      case 'deposit_loan':
        return MgrKind.depositLoan;
      case 'withdraw':
        return MgrKind.withdraw;
      case 'sas_pay_debt':
        return MgrKind.paymentSas;
      case 'points':
        return MgrKind.points;
      default:
        return MgrKind.other;
    }
  }

  /// النصّ واللون والاتّجاه كالشاشة السابقة حرفاً (debit = على المدير).
  ({String label, RpTone tone, bool debit}) get meta => switch (kind) {
        MgrKind.debtCreated => (label: 'إضافة دين أخرى', tone: RpTone.loss, debit: true),
        MgrKind.paymentCustom => (label: isFullPayment ? 'تسديد كامل — دين أخرى' : 'تسديد جزئي — دين أخرى', tone: RpTone.money, debit: false),
        MgrKind.depositCash => (label: 'شحن نقدي', tone: RpTone.money, debit: false),
        MgrKind.depositLoan => (label: loanInCustom ? 'شحن آجل — دين أخرى' : 'شحن آجل — دين SAS', tone: RpTone.debt, debit: true),
        MgrKind.withdraw => (label: 'سحب رصيد', tone: RpTone.loss, debit: true),
        MgrKind.paymentSas => (label: 'تسديد دين SAS', tone: RpTone.money, debit: false),
        MgrKind.points => (label: 'نقاط مكافأة', tone: RpTone.info, debit: false),
        MgrKind.other => (label: movement.arabicLabel, tone: RpTone.neutral, debit: false),
      };

  /// مستحصَلٌ من المدير (شحن نقديّ، تسديد SAS، تسديد أخرى) — النقاط والآجل والسحب لا.
  bool get incoming => kind == MgrKind.depositCash || kind == MgrKind.paymentSas || kind == MgrKind.paymentCustom;
}

class ManagerDebtsView {
  ManagerDebtsView._();

  /// مفاتيح الورقة بترتيب الشاشة السابقة.
  static const kindKeys = {
    'deposit_cash': MgrKind.depositCash,
    'deposit_loan': MgrKind.depositLoan,
    'debt_created': MgrKind.debtCreated,
    'payment_sas': MgrKind.paymentSas,
    'payment_custom': MgrKind.paymentCustom,
    'withdraw': MgrKind.withdraw,
    'points': MgrKind.points,
  };

  static String kindLabel(MgrKind k) => switch (k) {
        MgrKind.depositCash => 'شحن نقدي',
        MgrKind.depositLoan => 'شحن آجل',
        MgrKind.debtCreated => 'إضافة دين',
        MgrKind.paymentSas => 'تسديد SAS',
        MgrKind.paymentCustom => 'تسديد أخرى',
        MgrKind.withdraw => 'سحب',
        MgrKind.points => 'نقاط',
        MgrKind.other => 'أخرى',
      };

  /// حركات المدراء ⇒ أحداث الفترة (والتسديد الكامل من الديون الأخرى) — [from]/[to] null = كلّ الفترات.
  ///
  /// [sasDebt] false (ايرث لنك): «شحن آجل» دينه صفٌّ في «ديون أخرى» ([ManagerMovement.debtId]) ⇒ يُسمّى «دين أخرى»، و«إضافة دين أخرى»
  /// للدين نفسه لا تُعرض ثانيةً (المال نفسه سطراً واحداً؛ المجاميع لا تمسّها: الآجل ليس مستحصَلاً، والمتبقّي من الملخّص).
  static List<MgrEvent> eventsOf(
    List<({Manager manager, List<ManagerMovement> rows})> moves,
    List<ManagerDebt> debts, {
    DateTime? from,
    DateTime? to,
    String? companyKey,
    bool sasDebt = true,
  }) {
    final debtsById = {for (final d in debts) d.id: d};
    final loanDebts = sasDebt
        ? const <int>{}
        : {
            for (final m in moves)
              for (final mv in m.rows)
                if (mv.rowType != 'debt_created' && mv.rowType != 'debt_payment' && mv.subKind == 'deposit_loan' && mv.debtId != null)
                  mv.debtId!,
          };
    final out = <MgrEvent>[];
    for (final m in moves) {
      for (final mv in m.rows) {
        if (from != null && mv.eventAt.isBefore(from)) continue;
        if (to != null && mv.eventAt.isAfter(to)) continue;
        if (mv.rowType == 'debt_created' && loanDebts.contains(mv.debtId ?? mv.relatedDebtId)) continue;
        var full = false;
        if (mv.rowType == 'debt_payment') {
          final id = mv.debtId ?? mv.relatedDebtId;
          if (id != null && debtsById[id]?.remainingAmount == 0) full = true;
        }
        out.add(MgrEvent(manager: m.manager, movement: mv, isFullPayment: full, companyKey: companyKey, loanInCustom: !sasDebt));
      }
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  static bool _managerHit(Manager m, String q) =>
      q.isEmpty || m.username.toLowerCase().contains(q) || m.fullName.toLowerCase().contains(q);

  /// الأنواع المختارة (فارغة = الكلّ) وبحث المدير.
  static List<MgrEvent> filter(List<MgrEvent> events, List<String> kinds, String query) {
    final q = query.trim().toLowerCase();
    final want = {for (final k in kinds) kindKeys[k]}..remove(null);
    return events.where((e) => (want.isEmpty || want.contains(e.kind)) && _managerHit(e.manager, q)).toList();
  }

  static double incomingOf(List<MgrEvent> events) => events.where((e) => e.incoming).fold<double>(0, (a, e) => a + e.amount);

  /// متبقّي SAS: دين المدراء المطابقين للبحث عند الساس الآن (النوع والفترة لا يمسّانه)، بلا من لم يُقرأ دينه.
  static double sasOf(List<Manager> managers, String query) {
    final q = query.trim().toLowerCase();
    return managers.where((m) => _managerHit(m, q) && !m.debtUnavailable).fold<double>(0, (a, m) => a + m.totalDebt);
  }

  /// متبقّي أخرى: ملخّص دفترنا (بالبحث إن وُجد).
  static double customOf(ManagerDebtsSummary? s, String query) {
    if (s == null) return 0;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return s.totals.totalRemaining;
    return s.perDebtor.where((d) => (d.debtorAdminUsername ?? '').toLowerCase().contains(q)).fold<double>(0, (a, d) => a + d.totalRemaining);
  }

  /// المدينون: دين SAS > 0 (مقروء) ∪ دينٌ آخر متبقٍّ — بالبحث.
  static int debtorsOf(List<Manager> managers, ManagerDebtsSummary? s, String query) {
    final q = query.trim().toLowerCase();
    final ids = <int>{
      for (final m in managers)
        if (_managerHit(m, q) && m.totalDebt > 0 && !m.debtUnavailable) m.id,
    };
    for (final row in s?.perDebtor ?? const <ManagerDebtsDebtorSummary>[]) {
      if (row.totalRemaining <= 0) continue;
      if (q.isNotEmpty && !(row.debtorAdminUsername ?? '').toLowerCase().contains(q)) continue;
      ids.add(row.debtorAdminId);
    }
    return ids.length;
  }

  static int unreadOf(List<Manager> managers, String query) {
    final q = query.trim().toLowerCase();
    return managers.where((m) => _managerHit(m, q) && m.debtUnavailable).length;
  }

  static RpRow row(MgrEvent e, {RpCompany? company}) {
    final meta = e.meta;
    final t = e.date.toLocal();
    return RpRow(
      icon: switch (e.kind) {
        MgrKind.debtCreated => LucideIcons.receipt,
        MgrKind.paymentCustom || MgrKind.paymentSas => LucideIcons.banknote,
        MgrKind.depositCash || MgrKind.depositLoan => LucideIcons.plus,
        MgrKind.withdraw => LucideIcons.circleMinus,
        MgrKind.points => LucideIcons.star,
        MgrKind.other => LucideIcons.activity,
      },
      tone: meta.tone,
      title: e.managerName,
      detail: [
        meta.label,
        if (e.manager.fullName.isNotEmpty) e.manager.username,
        if ((e.movement.note ?? '').trim().isNotEmpty) e.movement.note!.trim(),
      ].join(' · '),
      amount: e.amount == 0 ? null : e.amount.abs(),
      negative: meta.debit && e.amount != 0,
      time: clock12Ar(t),
      company: company,
    );
  }

  /// الأيّام الأحدث أوّلاً، ومجموع اليوم ما استُحصل فيه.
  static List<RpDay> days(List<MgrEvent> events, {RpCompany? Function(MgrEvent)? companyOf, int? limit}) {
    final byDay = <String, List<MgrEvent>>{};
    final order = <String>[];
    for (final e in events) {
      final key = iqDateOf(e.date.toLocal());
      if (!byDay.containsKey(key)) order.add(key);
      (byDay[key] ??= []).add(e);
    }
    final out = <RpDay>[];
    var left = limit ?? 1 << 30;
    for (final k in order) {
      if (left <= 0) break;
      final all = byDay[k]!;
      final shown = all.take(left).toList();
      left -= shown.length;
      out.add(RpDay(
        date: k,
        count: all.length,
        sum: incomingOf(all),
        rows: [for (final e in shown) row(e, company: companyOf?.call(e))],
      ));
    }
    return out;
  }

  static List<RpShare> shares(List<MgrEvent> events, String Function(MgrEvent) keyOf, {RpCompany? Function(MgrEvent)? companyOf}) {
    final acc = <String, ({String name, num amount, int count, RpCompany? co})>{};
    for (final e in events) {
      final co = companyOf?.call(e);
      final name = keyOf(e);
      final k = '${co?.key ?? ''}|$name';
      final o = acc[k];
      acc[k] = (name: name, amount: (o?.amount ?? 0) + (e.incoming ? e.amount : 0), count: (o?.count ?? 0) + 1, co: co);
    }
    final total = acc.values.fold<int>(0, (a, v) => a + v.count);
    final list = acc.values.toList()..sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : b.amount.compareTo(a.amount));
    return [
      for (final v in list) RpShare(name: v.name, amount: v.amount, count: v.count, share: total == 0 ? 0 : v.count / total, company: v.co),
    ];
  }

  static String money(num v) => '${formatIQD(v.round())} د.ع';
}
