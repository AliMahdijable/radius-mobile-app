import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/ar_date.dart';
import '../core/util/format.dart';
import 'api_client.dart';
import 'company_route.dart';
import 'employee_limits_api.dart' show LimitsResult;

/// «تقارير الأرصدة» (١٥ نوفمبر — المالك: «في قسم التقارير نفتح قسم خاص… تقارير الأرصدة»).
///
/// فترةٌ لكلّ شحنة رصيد يسجّلها الوكيل: «هذا ربحك، هذا الإجمالي اللي طبّلك، هذا اللي معوز حتى يوصل للسقف»، «تسوية الرصيد»
/// حين ينتهي الرصيد قبل أن يكتمل المبلغ، ثمّ الإغلاق — وما يتسدّد من ديون الفترة بعد إغلاقها ربح.
///
/// الخادم (server/balanceReports.js) يحسب كلّ رقم — التطبيق يعرض ويرسل فقط:
/// - لمدير الصفحة وحده (الموظّف يُرفض MANAGER_ONLY)، وخلف مفتاحها (`/me` ⇒ feature_enabled).
/// - كلّ كتابةٍ تردّ اللوحة محدَّثةً في `data` — فلا يُعرض رقمٌ قديم ولا تُطلب قراءةٌ ثانية.
/// - كلّ نداءٍ بشركته **صراحةً** من مستدعيه ([CompanyRoute.explicit] — null = المفتوحة): «كل الشركات» (١٦ نوفمبر — المالك:
///   «اي ضيفها بالتطبيق») يعرض شركة الشريط بمكانها، فالقسم يمرّر مفتاحها لكلّ قراءةٍ وكتابة؛ والكتابة الموجَّهة بما يقوله الخادم
///   لها (`routed_writes` في ردّ `/me` ⇐ balance_routed).
/// - «الفترة التالية تُفتح عند الإغلاق» (١٦ نوفمبر مساءً — المالك: «من يسوي غلق فترة تنفتح فترة بدون سعر مفتوحة… وعليها تنبيه…
///   بمجرد ما الفترة الجديدة صار بها حركة… القديمة تنقفل نهائيا»): حين يفتح الخادم مفتاحها للصفحة يأتي `auto_next` في اللوحة؛
///   إغلاق آخر فترة يفتح فترةً بلا مبلغ (`amount_pending` — محصَّلها حقيقيّ، والمتبقّي والربح لا يُعرفان حتى يُكتب مبلغها بـPUT amount)،
///   والمغلقة التي صار في التي بعدها حركة تأتي `reopen_locked` (إلغاء إغلاقها مرفوض). والمفتاح مطفأ: الردّ كما كان بلا هذه الحقول.
typedef BalanceResult<T> = LimitsResult<T>;

double _n(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int _i(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

int? _ms(Object? v) {
  if (v == null) return null;
  final n = _i(v);
  return n > 0 ? n : null;
}

String? _s(Object? v) {
  final t = v?.toString().trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// حال الفترة.
enum BalanceState {
  running('جارية'),
  waiting('بانتظار الإغلاق'),
  closed('مغلقة');

  const BalanceState(this.label);
  final String label;
  static BalanceState of(Object? v) => switch ('$v') { 'closed' => closed, 'waiting' => waiting, _ => running };
}

/// مصدر مبلغ «تسوية الرصيد».
enum BalanceSource {
  income('income', 'من الدخل'),
  pocket('pocket', 'من مالي الخاصّ'),
  other('other', 'غير ذلك');

  const BalanceSource(this.wire, this.label);
  final String wire;
  final String label;
  static BalanceSource of(Object? v) => values.firstWhere((x) => x.wire == '$v', orElse: () => other);
}

/// طريقة دفع التفعيل كما وقعت فعلاً.
enum BalancePay {
  cash('نقدي'),
  credit('آجل'),
  partial('جزئي');

  const BalancePay(this.label);
  final String label;
  static BalancePay of(Object? v) => switch ('$v') { 'credit' => credit, 'partial' => partial, _ => cash };
}

/// فلاتر حركات الفترة — بترتيب عرضها.
enum BalanceFilter {
  all('all', 'الكل'),
  cash('cash', 'نقدي'),
  credit('credit', 'آجل'),
  partial('partial', 'جزئي'),
  open('open', 'ديون باقية'),
  paid('paid', 'كان دين وتسدّد'),
  payments('payments', 'التسديدات'),

  /// حركات المدراء الفرعيّين — يأتي عدده حين تدخل الحساب وحده (مفتاحٌ عند الخادم)، فيُعرض حين فيه حركات.
  managers('managers', 'المدراء');

  const BalanceFilter(this.wire, this.label);
  final String wire;
  final String label;
}

/// عمليّة الرصيد مع مديرٍ فرعيّ: شحنٌ نقديّ («طبّلك»)، شحنٌ آجل (دينٌ من ديون الفترة)، تسديدٌ من دينه، أو سحب رصيدٍ منه (ينقص «طبّلك»).
enum BalanceMgrOp {
  cash('شحن مدير نقدي'),
  loan('شحن مدير آجل'),
  pay('تسديد دين مدير'),
  withdraw('سحب رصيد من مدير');

  const BalanceMgrOp(this.label);
  final String label;
  static BalanceMgrOp? of(Object? v) => switch ('$v') { 'cash' => cash, 'loan' => loan, 'pay' => pay, 'withdraw' => withdraw, _ => null };
}

/// حال دين التفعيل (أو الشحن الآجل للمدير).
enum BalanceDebtState {
  none,
  open,
  partly,
  paid,
  writtenOff,
  untracked;

  static BalanceDebtState of(Object? v) => switch ('$v') {
        'open' => open,
        'partly' => partly,
        'paid' => paid,
        'written_off' => writtenOff,
        'untracked' => untracked,
        _ => none,
      };
}

/// نغمة نصٍّ للعرض (الواجهة تحوّلها للونها).
enum BalanceTone { success, warning, danger, brand, neutral }

class BalanceAdjustment {
  const BalanceAdjustment({required this.id, required this.amount, required this.source, this.note, required this.createdAtMs});
  final int id;
  final double amount;
  final BalanceSource source;
  final String? note;
  final int createdAtMs;

  static BalanceAdjustment? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = _i(j['id']);
    if (id <= 0) return null;
    return BalanceAdjustment(id: id, amount: _n(j['amount']), source: BalanceSource.of(j['source']), note: _s(j['note']), createdAtMs: _i(j['created_at_ms']));
  }
}

/// المدراء الفرعيّون في الفترة — أرقامهم **داخلة** في أرقامها: [cash] و[paidIn] في «طبّلك» و[withdrawn] ينقص منه؛ [loans] في
/// ديون الفترة و[open] في الباقي منها؛ [afterClose] في ربح ما بعد الإغلاق.
class BalanceManagers {
  const BalanceManagers({
    required this.cash,
    required this.withdrawn,
    required this.loans,
    required this.paidIn,
    required this.open,
    required this.afterClose,
    required this.count,
  });
  final double cash;
  final double withdrawn;
  final double loans;
  final double paidIn;
  final double open;
  final double afterClose;
  final int count;

  static BalanceManagers? fromJson(Object? j) {
    if (j is! Map) return null;
    return BalanceManagers(
      cash: _n(j['cash']),
      withdrawn: _n(j['withdrawn']),
      loans: _n(j['loans']),
      paidIn: _n(j['paid_in']),
      open: _n(j['open']),
      afterClose: _n(j['late']),
      count: _i(j['count']),
    );
  }
}

class BalancePeriod {
  const BalancePeriod({
    required this.id,
    required this.startedAtMs,
    this.endsAtMs,
    required this.amount,
    this.note,
    required this.state,
    this.closedAtMs,
    required this.sales,
    required this.cashNow,
    required this.paidIn,
    required this.collected,
    required this.adjustmentsSum,
    required this.remaining,
    required this.progress,
    required this.canClose,
    required this.debtsCreated,
    required this.debtsOpen,
    required this.lateProfit,
    required this.net,
    required this.profit,
    required this.pocketOutstanding,
    required this.writtenOff,
    required this.untracked,
    required this.incomeInWindow,
    required this.nCash,
    required this.nCredit,
    required this.nPartial,
    required this.nPayments,
    required this.nActivations,
    required this.adjustments,
    required this.transfersCount,
    required this.transfersSum,
    this.managers,
    this.amountPending = false,
    this.reopenLocked = false,
  });
  final int id;
  final int startedAtMs;

  /// وقت الشحنة التالية، أو null للأحدث.
  final int? endsAtMs;

  /// مبلغ الشحنة (السقف). صفرٌ مع [amountPending]: لم يُكتب بعد.
  final double amount;

  /// فترةٌ فُتحت بإغلاق سابقتها ولم يُكتب مبلغ شحنها: [remaining] و[net] و[profit] لا تُعرف (تأتي أصفاراً — تُعرض «—»)،
  /// ولا تُغلق ولا تُسوّى حتى يُكتب.
  final bool amountPending;

  /// مغلقةٌ فُتحت بإغلاقها فترةٌ صار فيها حركة: إلغاء إغلاقها مرفوضٌ نهائيّاً.
  final bool reopenLocked;
  final String? note;
  final BalanceState state;
  final int? closedAtMs;
  final double sales;
  final double cashNow;
  final double paidIn;

  /// «طبّلك» = نقد التفعيلات + ما سُدّد من ديون الفترة قبل إغلاقها.
  final double collected;
  final double adjustmentsSum;

  /// المعوز حتى يكتمل مبلغ الشحنة.
  final double remaining;
  final double progress;
  final bool canClose;
  final double debtsCreated;
  final double debtsOpen;

  /// ما دخل بعد الإغلاق (ربح).
  final double lateProfit;

  /// طبّلك + ما بعد الإغلاق − مبلغ الشحنة (سالبٌ حتى يرجع المبلغ).
  final double net;
  final double profit;

  /// ما دفعه بـ«تسوية الرصيد» ولم يرجع بعد من ديون الفترة.
  final double pocketOutstanding;
  final double writtenOff;
  final double untracked;

  /// ما دخله خلال هذه الفترة من ديونٍ أقدم.
  final double incomeInWindow;
  final int nCash;
  final int nCredit;
  final int nPartial;
  final int nPayments;
  final int nActivations;
  final List<BalanceAdjustment> adjustments;
  final int transfersCount;
  final double transfersSum;

  /// المدراء الفرعيّون حين تدخل تحويلاتهم الحساب (مفتاحٌ عند الخادم) — null: خارج الحساب، و[transfersCount] تنبيهٌ بها.
  final BalanceManagers? managers;

  bool get isClosed => state == BalanceState.closed;

  static BalancePeriod? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = _i(j['id']);
    final start = _i(j['started_at_ms']);
    if (id <= 0 || start <= 0) return null;
    final c = j['counts'] is Map ? j['counts'] as Map : const {};
    final t = j['transfers'] is Map ? j['transfers'] as Map : const {};
    final adj = j['adjustments'];
    return BalancePeriod(
      id: id,
      startedAtMs: start,
      endsAtMs: _ms(j['ends_at_ms']),
      amount: _n(j['amount']),
      note: _s(j['note']),
      state: BalanceState.of(j['state']),
      closedAtMs: _ms(j['closed_at_ms']),
      sales: _n(j['sales']),
      cashNow: _n(j['cash_now']),
      paidIn: _n(j['paid_in']),
      collected: _n(j['collected']),
      adjustmentsSum: _n(j['adjustments_sum']),
      remaining: _n(j['remaining']),
      progress: _n(j['progress']).clamp(0, 1).toDouble(),
      canClose: j['can_close'] == true,
      debtsCreated: _n(j['debts_created']),
      debtsOpen: _n(j['debts_open']),
      lateProfit: _n(j['late_profit']),
      net: _n(j['net']),
      profit: _n(j['profit']),
      pocketOutstanding: _n(j['pocket_outstanding']),
      writtenOff: _n(j['written_off']),
      untracked: _n(j['untracked']),
      incomeInWindow: _n(j['income_in_window']),
      nCash: _i(c['cash']),
      nCredit: _i(c['credit']),
      nPartial: _i(c['partial']),
      nPayments: _i(c['payments']),
      nActivations: _i(c['activations']),
      adjustments: adj is List ? adj.map(BalanceAdjustment.fromJson).whereType<BalanceAdjustment>().toList() : const [],
      transfersCount: _i(t['count']),
      transfersSum: _n(t['sum']),
      managers: BalanceManagers.fromJson(j['managers']),
      amountPending: j['amount_pending'] == true,
      reopenLocked: j['reopen_locked'] == true,
    );
  }
}

/// اللوحة كلّها: الفترات (الأحدث أوّلاً) وما دخل من خارج حساب الشحنات، وجودة البيانات.
class BalanceOverview {
  const BalanceOverview({
    required this.featureEnabled,
    required this.periods,
    this.oldPaid = 0,
    this.manualPaid = 0,
    this.otherPaid = 0,
    this.advance = 0,
    this.noPrice = 0,
    this.noAmount = 0,
    this.noSnapshot = 0,
    this.transfersUnknown = false,
    this.managersIncluded = false,
    this.managersOldPaid = 0,
    this.autoNext = false,
  });
  final bool featureEnabled;

  /// الأحدث أوّلاً.
  final List<BalancePeriod> periods;
  final double oldPaid;
  final double manualPaid;
  final double otherPaid;
  final double advance;
  final int noPrice;
  final int noAmount;
  final int noSnapshot;
  final bool transfersUnknown;

  /// تحويلات المدراء الفرعيّين داخلةٌ في أرقام الفترات.
  final bool managersIncluded;

  /// ما سدّده المدراء الفرعيّون من ديونٍ أقدم من أوّل شحنة مسجّلة (أو لا يُعرف شحنها) — خارج حساب الشحنات.
  final double managersOldPaid;

  /// إغلاق آخر فترة يفتح بعدها فترةً بلا مبلغ (مفتاح الخادم مفتوحٌ للصفحة).
  final bool autoNext;

  BalancePeriod? periodOf(int id) {
    for (final p in periods) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// الفترة المفتوحة التي تنتظر مبلغ شحنها (الشحن الجديد يُكتب عليها — لا فترة أخرى فوقها)، أو null.
  BalancePeriod? get waitingAmount {
    for (final p in periods) {
      if (p.amountPending && !p.isClosed) return p;
    }
    return null;
  }

  /// الفترة التي فُتحت بإغلاق [p]: تاليتها وتبدأ من لحظة إغلاقها نفسها — أو null.
  BalancePeriod? openedAfter(BalancePeriod p) {
    if (p.closedAtMs == null) return null;
    final i = periods.indexWhere((x) => x.id == p.id);
    if (i <= 0) return null;
    final next = periods[i - 1];
    return next.startedAtMs == p.closedAtMs ? next : null;
  }

  /// هل فُتحت [p] بإغلاق سابقتها؟ والمفتاح مفتوح ([autoNext]): لا تُحذف ولا يتغيّر تاريخها ما دامت تلك مغلقة.
  bool openedByClose(BalancePeriod p) {
    final i = periods.indexWhere((x) => x.id == p.id);
    if (i < 0 || i + 1 >= periods.length) return false;
    final prev = periods[i + 1];
    return prev.closedAtMs != null && prev.closedAtMs == p.startedAtMs;
  }

  /// [p] مثبَّتة: فُتحت بإغلاق سابقتها والمفتاح مفتوح — لا زرّ حذف، وتعديلها بلا تاريخ.
  bool pinned(BalancePeriod p) => autoNext && openedByClose(p);

  /// ما دخل من غير تفعيلات الفترات (لا يدخل مبلغ أيّ شحنة) — بتسمياته.
  List<({String label, double value, String id})> get outside => [
        if (oldPaid > 0) (label: 'تسديد ديون قديمة (قبل أوّل شحن مسجَّل)', value: oldPaid, id: 'old'),
        if (manualPaid > 0) (label: 'تسديد ديون يدويّة («إضافة دين» ومبيعات)', value: manualPaid, id: 'manual'),
        if (otherPaid > 0) (label: 'تسديد ديون عُدّلت من خارج النظام', value: otherPaid, id: 'other'),
        if (advance > 0) (label: 'دفعات مقدَّمة لم تُستعمل بعد', value: advance, id: 'advance'),
        if (managersOldPaid > 0) (label: 'تسديد ديون مدراء فرعيّين أقدم من أوّل شحن (أو لا يُعرف تاريخ شحنها)', value: managersOldPaid, id: 'managers'),
      ];

  /// أسطر جودة البيانات التي يجب أن يراها الوكيل (لا رقم ناقص بصمت).
  List<String> get qualityNotes => [
        if (noPrice > 0) '${formatIQD(noPrice)} تفعيل بلا سعرٍ مسجَّل — لم يدخل الحساب',
        if (noAmount > 0) '${formatIQD(noAmount)} حركة بلا مبلغٍ مسجَّل — لم تدخل الحساب',
        if (noSnapshot > 0) '${formatIQD(noSnapshot)} حركة بلا دين المشترك قبلها وبعدها — نسبتها للفترات تقريبيّة',
        if (transfersUnknown) 'تعذّرت قراءة تحويلات الرصيد للمدراء الفرعيّين',
      ];

  /// null: ردٌّ بغير شكله (لا يُقرأ «لا شحنات»).
  static BalanceOverview? fromJson(Object? j) {
    if (j is! Map) return null;
    final rows = j['periods'];
    if (rows is! List) return null;
    final t = j['totals'] is Map ? j['totals'] as Map : const {};
    final q = j['quality'] is Map ? j['quality'] as Map : const {};
    return BalanceOverview(
      featureEnabled: j['feature_enabled'] == true,
      periods: rows.map(BalancePeriod.fromJson).whereType<BalancePeriod>().toList(),
      oldPaid: _n(t['old_paid']),
      manualPaid: _n(t['manual_paid']),
      otherPaid: _n(t['other_paid']),
      advance: _n(t['advance']),
      noPrice: _i(q['no_price']),
      noAmount: _i(q['no_amount']),
      noSnapshot: _i(q['no_snapshot']),
      transfersUnknown: q['transfers_unknown'] == true,
      managersIncluded: j['managers_included'] == true,
      managersOldPaid: _n(t['managers_old_paid']),
      autoNext: j['auto_next'] == true,
    );
  }
}

/// حركةٌ في فترة: تفعيل (بحال دينه)، تسديد دين، حركة مديرٍ فرعيّ، أو تسوية رصيد.
sealed class BalanceMove {
  const BalanceMove({required this.key, required this.atMs});
  final String key;
  final int atMs;

  static BalanceMove? fromJson(Object? j) {
    if (j is! Map) return null;
    final key = _s(j['key']);
    if (key == null) return null;
    final at = _i(j['at_ms']);
    switch ('${j['kind']}') {
      case 'activate':
        return BalanceActMove(
          key: key,
          atMs: at,
          username: _s(j['username']) ?? '—',
          package: _s(j['package']),
          price: _n(j['price']),
          pay: BalancePay.of(j['pay']),
          cash: _n(j['cash']),
          debt: _n(j['debt']),
          remaining: _n(j['remaining']),
          debtState: BalanceDebtState.of(j['debt_state']),
          turnedProfit: '${j['turned']}' == 'profit',
          paidIn: _n(j['paid_in']),
          paidLate: _n(j['paid_late']),
          untracked: _n(j['untracked']),
          excess: _n(j['excess']),
          lastPaidAtMs: _ms(j['last_paid_at_ms']),
          afterClose: j['after_close'] == true,
          by: _s(j['by']),
        );
      case 'payment':
        return BalancePayMove(
          key: key,
          atMs: at,
          username: _s(j['username']) ?? '—',
          amount: _n(j['amount']),
          afterClose: j['after_close'] == true,
          advance: j['advance'] == true,
          by: _s(j['by']),
        );
      case 'adjust':
        return BalanceAdjustMove(key: key, atMs: at, amount: _n(j['amount']), source: BalanceSource.of(j['source']), note: _s(j['note']));
      case 'manager':
        final op = BalanceMgrOp.of(j['op']);
        if (op == null) return null;
        return BalanceMgrMove(
          key: key,
          atMs: at,
          username: _s(j['username']) ?? '—',
          op: op,
          amount: _n(j['amount']),
          remaining: _n(j['remaining']),
          debtState: BalanceDebtState.of(j['debt_state']),
          turnedProfit: '${j['turned']}' == 'profit',
          paidIn: _n(j['paid_in']),
          paidLate: _n(j['paid_late']),
          lastPaidAtMs: _ms(j['last_paid_at_ms']),
          afterClose: j['after_close'] == true,
          by: _s(j['by']),
          note: _s(j['note']),
        );
    }
    return null;
  }
}

class BalanceActMove extends BalanceMove {
  const BalanceActMove({
    required super.key,
    required super.atMs,
    required this.username,
    this.package,
    required this.price,
    required this.pay,
    required this.cash,
    required this.debt,
    required this.remaining,
    required this.debtState,
    required this.turnedProfit,
    required this.paidIn,
    required this.paidLate,
    required this.untracked,
    required this.excess,
    this.lastPaidAtMs,
    required this.afterClose,
    this.by,
  });
  final String username;
  final String? package;
  final double price;
  final BalancePay pay;
  final double cash;
  final double debt;
  final double remaining;
  final BalanceDebtState debtState;

  /// الدين تسدّد بعد إغلاق فترته ⇒ ربح (وإلّا دخل «طبّلك»).
  final bool turnedProfit;
  final double paidIn;
  final double paidLate;
  final double untracked;
  final double excess;
  final int? lastPaidAtMs;
  final bool afterClose;
  final String? by;
}

class BalancePayMove extends BalanceMove {
  const BalancePayMove({required super.key, required super.atMs, required this.username, required this.amount, required this.afterClose, required this.advance, this.by});
  final String username;
  final double amount;
  final bool afterClose;
  final bool advance;
  final String? by;
}

class BalanceAdjustMove extends BalanceMove {
  const BalanceAdjustMove({required super.key, required super.atMs, required this.amount, required this.source, this.note});
  final double amount;
  final BalanceSource source;
  final String? note;
}

/// حركة رصيدٍ مع مديرٍ فرعيّ ([username] اسمه). حقول الدين للشحن الآجل ([BalanceMgrOp.loan]) وحده.
class BalanceMgrMove extends BalanceMove {
  const BalanceMgrMove({
    required super.key,
    required super.atMs,
    required this.username,
    required this.op,
    required this.amount,
    required this.remaining,
    required this.debtState,
    required this.turnedProfit,
    required this.paidIn,
    required this.paidLate,
    this.lastPaidAtMs,
    required this.afterClose,
    this.by,
    this.note,
  });
  final String username;
  final BalanceMgrOp op;
  final double amount;
  final double remaining;
  final BalanceDebtState debtState;
  final bool turnedProfit;
  final double paidIn;
  final double paidLate;
  final int? lastPaidAtMs;
  final bool afterClose;
  final String? by;
  final String? note;
}

/// صفحةٌ من حركات فترة، مع الفترة نفسها وأعداد الفلاتر.
class BalancePeriodPage {
  const BalancePeriodPage({required this.period, required this.counts, required this.items, required this.total, required this.offset});
  final BalancePeriod period;
  final Map<BalanceFilter, int> counts;
  final List<BalanceMove> items;
  final int total;
  final int offset;

  /// null: ردٌّ بغير شكله — لا صفحة فارغة كاذبة تُنهي القائمة.
  static BalancePeriodPage? fromJson(Object? j) {
    if (j is! Map) return null;
    final p = BalancePeriod.fromJson(j['period']);
    final mv = j['movements'];
    if (p == null || mv is! Map || mv['items'] is! List) return null;
    final c = j['counts'] is Map ? j['counts'] as Map : const {};
    return BalancePeriodPage(
      period: p,
      counts: {for (final f in BalanceFilter.values) f: _i(c[f.wire])},
      items: (mv['items'] as List).map(BalanceMove.fromJson).whereType<BalanceMove>().toList(),
      total: _i(mv['total']),
      offset: _i(mv['offset']),
    );
  }
}

class BalanceMe {
  const BalanceMe({required this.featureEnabled, required this.canManage, required this.isEmployee, this.routedWrites});
  final bool featureEnabled;
  final bool canManage;
  final bool isEmployee;

  /// «كل الشركات» وحده: هل تُقبل كتابات هذه الشركة من هنا — null في الوضع العاديّ (الخادم لا يرسله).
  final bool? routedWrites;
}

// ─────────────────────────── نصوصٌ وأوقات (نقيّة) ───────────────────────────

String balanceIqd(num v) => '${formatIQD(v)} د.ع';

/// اللحظة بحقول بغداد (سنة/شهر/يوم/ساعة/دقيقة تُقرأ منها مباشرةً).
DateTime balanceBaghdad(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).add(const Duration(hours: 3));

/// تاريخٌ ووقت اختارهما الوكيل بتوقيت بغداد ⇒ لحظة.
int balanceMsFromBaghdad(int year, int month, int day, int hour, int minute) =>
    DateTime.utc(year, month, day, hour - 3, minute).millisecondsSinceEpoch;

/// «10 تشرين الأوّل» (والسنة حين ليست سنة اليوم).
String balanceDay(int ms, {int? nowMs}) =>
    iqDateOf(balanceBaghdad(ms), today: balanceBaghdad(nowMs ?? DateTime.now().millisecondsSinceEpoch));

/// «10 تشرين الأوّل · 14:30».
String balanceDayTime(int ms, {int? nowMs}) {
  final d = balanceBaghdad(ms);
  return '${balanceDay(ms, nowMs: nowMs)} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// «شحن 10 تشرين الأوّل»؛ وبلا مبلغ بعد: «فترة جديدة» (لا شحن يُسمّى باسمه بعد).
String balancePeriodTitle(BalancePeriod p, {int? nowMs}) => p.amountPending ? 'فترة جديدة' : 'شحن ${balanceDay(p.startedAtMs, nowMs: nowMs)}';

String balancePeriodRange(BalancePeriod p, {int? nowMs}) => p.endsAtMs == null
    ? 'من ${balanceDay(p.startedAtMs, nowMs: nowMs)} حتى الآن'
    : 'من ${balanceDay(p.startedAtMs, nowMs: nowMs)} إلى ${balanceDay(p.endsAtMs!, nowMs: nowMs)}';

/// حال دين التفعيل بكلامٍ يُقرأ: «كان دين وتسدّد» (نقداً قبل الإغلاق، أو ربحاً بعده) أو ما بقي منه.
({String text, BalanceTone tone})? balanceDebtNote(BalanceActMove m, {int? nowMs}) => balanceDebtNoteOf(
      state: m.debtState,
      turnedProfit: m.turnedProfit,
      paid: m.paidIn + m.paidLate,
      remaining: m.remaining,
      lastPaidAtMs: m.lastPaidAtMs,
      nowMs: nowMs,
    );

/// حال دين الشحن الآجل لمديرٍ فرعيّ — بالكلام نفسه (null لغير الآجل).
({String text, BalanceTone tone})? balanceMgrDebtNote(BalanceMgrMove m, {int? nowMs}) => m.op != BalanceMgrOp.loan
    ? null
    : balanceDebtNoteOf(state: m.debtState, turnedProfit: m.turnedProfit, paid: m.paidIn + m.paidLate, remaining: m.remaining, lastPaidAtMs: m.lastPaidAtMs, nowMs: nowMs);

/// حال دينٍ بكلامٍ يُقرأ: «كان دين وتسدّد» (نقداً قبل الإغلاق، أو ربحاً بعده) أو ما بقي منه.
({String text, BalanceTone tone})? balanceDebtNoteOf({
  required BalanceDebtState state,
  required bool turnedProfit,
  required double paid,
  required double remaining,
  int? lastPaidAtMs,
  int? nowMs,
}) {
  final when = lastPaidAtMs == null ? '' : ' — ${balanceDay(lastPaidAtMs, nowMs: nowMs)}';
  return switch (state) {
    BalanceDebtState.paid => turnedProfit
        ? (text: 'كان دين وتسدّد بعد الإغلاق — صار ربح$when', tone: BalanceTone.brand)
        : (text: 'كان دين وتسدّد$when', tone: BalanceTone.success),
    BalanceDebtState.partly => (text: 'تسدّد منه ${formatIQD(paid)} · باقي ${formatIQD(remaining)}', tone: BalanceTone.warning),
    BalanceDebtState.open => (text: 'دين باقي ${formatIQD(remaining)}', tone: BalanceTone.danger),
    BalanceDebtState.writtenOff => (text: 'نقص الدين بلا تسديد', tone: BalanceTone.neutral),
    BalanceDebtState.untracked => (text: 'الدين لم يُسجَّل على المشترك', tone: BalanceTone.neutral),
    BalanceDebtState.none => null,
  };
}

/// متى نعدّ الرصيد «خلص»: دون واحدٍ بالمئة من الشحنة أو عشرة آلاف (أقلّ من أرخص تفعيل).
double balanceLowMark(double amount) => max(10000, (amount * 0.01).roundToDouble());

enum BalanceBannerKind { done, ended, empty, amount }

/// نصّ تنبيه الفترة التي بلا مبلغ (في الكرت وفي التفاصيل).
const balanceAmountPendingText = 'هذه الفترة بلا مبلغ شحن — اكتب مبلغها ليظهر المتبقّي والربح';

/// تنبيه الفترة: بلا مبلغ شحن بعد · اكتمل المبلغ فيصحّ الإغلاق · انتهت (سُجّلت شحنةٌ بعدها) ولم تكتمل · الرصيد خلص ولم تكتمل.
/// [liveBalance]: رصيد الوكيل الآن، أو null إن لم يُعرف (فلا نقول «خلص» بلا علم).
({BalanceBannerKind kind, String text})? balanceBanner(BalancePeriod p, num? liveBalance) {
  if (p.isClosed) return null;
  // بلا مبلغ: لا «اكتمل» ولا «نفد رصيدك» (كلاهما يقيس على مبلغٍ لم يُكتب)
  if (p.amountPending) return (kind: BalanceBannerKind.amount, text: balanceAmountPendingText);
  if (p.canClose) return (kind: BalanceBannerKind.done, text: 'اكتمل مبلغ الشحن — يمكنك إغلاق الفترة');
  if (p.state == BalanceState.waiting) {
    return (kind: BalanceBannerKind.ended, text: 'انتهت هذه الفترة ولم يكتمل المبلغ — المتبقّي ${balanceIqd(p.remaining)}');
  }
  if (liveBalance != null && liveBalance <= balanceLowMark(p.amount)) {
    return (kind: BalanceBannerKind.empty, text: 'نفد رصيدك ولم يكتمل المبلغ — المتبقّي ${balanceIqd(p.remaining)}');
  }
  return null;
}

/// آخر جواب «هل فُتحت تقارير الأرصدة لصفحة الجلسة؟» — ليظهر كرتها في «التقارير» من أوّل إطار حين تُفتح ثانيةً (بلا قفزةٍ تحت
/// الإصبع)، والخادم يُسأل مع كلّ فتحٍ فيتحدّث. يُمسح مع الجلسة ([SessionManager]) فلا يُعرض لصفحةٍ أخرى، وجوابٌ وصل بعد
/// تبدّل الجلسة يُهمل.
class BalanceReportsState {
  BalanceReportsState._();

  static BalanceMe? last;
  static int _epoch = 0;

  static void reset() {
    _epoch++;
    last = null;
  }

  /// يسأل الخادم ويحفظ جوابه؛ تعذُّر السؤال يُبقي المعروف (لا يختفي الكرت بعثرة شبكة).
  static Future<BalanceMe?> refresh() async {
    final epoch = _epoch;
    final me = await BalanceReportsApi.me(companyKey: null);
    if (epoch != _epoch) return last;
    if (me != null) last = me;
    return last;
  }
}

class BalanceReportsApi {
  BalanceReportsApi._();

  static const _base = '/api/v2/balance-reports';

  /// كم حركةً في كلّ صفحةٍ من الخادم، وكم يُعرض أوّلاً وكم يزيد «عرض المزيد».
  static const pageSize = 20;
  static const firstShown = 10;
  static const showStep = 20;

  /// وجهةٌ صريحة: [companyKey] (شركة الشريط في «كل الشركات») أو null = المفتوحة — لا تأخذ وجهة قسمٍ ضمنيّاً.
  static Options _to(String? companyKey) => CompanyRoute.explicit(companyKey);

  static final Random _rnd = Random();

  /// مفتاح منع التكرار (8–64 من `[A-Za-z0-9_-]`): ثابتٌ للنيّة الواحدة — ضغطتان أو شبكةٌ انقطعت بعد الحفظ = عمليّةٌ واحدة.
  static String newRef([String prefix = 'b']) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final tail = List.generate(8, (_) => chars[_rnd.nextInt(chars.length)]).join();
    return '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$tail';
  }

  static BalanceResult<T> _fail<T>(Object e, String fallback) {
    if (e is DioException) {
      final body = e.response?.data;
      if (body is Map) {
        return BalanceResult<T>(message: body['message']?.toString() ?? fallback, code: body['code']?.toString(), status: e.response?.statusCode);
      }
      return BalanceResult<T>(message: fallback, status: e.response?.statusCode);
    }
    if (!kReleaseMode) debugPrint('🔴 balance-reports: $e');
    return BalanceResult<T>(message: fallback);
  }

  static BalanceResult<T> _refused<T>(Map body, String fallback) =>
      BalanceResult<T>(message: body['message']?.toString() ?? fallback, code: body['code']?.toString());

  /// هل القسم مفتوحٌ لهذه الصفحة، ومن أنا فيها؟ null = تعذّر السؤال (يُعامل مطفأً — لا كرت ولا أخطاء).
  static Future<BalanceMe?> me({required String? companyKey}) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('$_base/me', options: _to(companyKey));
      final body = r.data ?? const {};
      final data = body['data'];
      if (body['success'] != true || data is! Map) return null;
      final rw = data['routed_writes'];
      return BalanceMe(
        featureEnabled: data['feature_enabled'] == true,
        canManage: data['can_manage'] == true,
        isEmployee: data['is_employee'] == true,
        routedWrites: rw is bool ? rw : null,
      );
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 balance-reports me: $e');
      return null;
    }
  }

  static BalanceResult<BalanceOverview> _overviewOf(Map body, String fallback) {
    final o = BalanceOverview.fromJson(body['data']);
    if (body['success'] != true || o == null) return _refused(body, fallback);
    return BalanceResult(data: o);
  }

  static Future<BalanceResult<BalanceOverview>> overview({required String? companyKey}) async {
    const fb = 'تعذّر تحميل تقارير الأرصدة';
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(_base, options: _to(companyKey));
      return _overviewOf(r.data ?? const {}, fb);
    } catch (e) {
      return _fail(e, fb);
    }
  }

  /// صفحةٌ من حركات الفترة بعد أوّل [offset] حركة (الأحدث أوّلاً)، بفلترها وبحثها.
  static Future<BalanceResult<BalancePeriodPage>> period(int id,
      {BalanceFilter filter = BalanceFilter.all, String q = '', int offset = 0, required String? companyKey}) async {
    const fb = 'تعذّر تحميل الحركات';
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '$_base/periods/$id',
        queryParameters: {'filter': filter.wire, 'offset': offset, 'limit': pageSize, if (q.isNotEmpty) 'q': q},
        options: _to(companyKey),
      );
      final body = r.data ?? const {};
      final page = BalancePeriodPage.fromJson(body['data']);
      if (body['success'] != true || page == null) return _refused(body, fb);
      return BalanceResult(data: page);
    } catch (e) {
      return _fail(e, fb);
    }
  }

  static Future<BalanceResult<BalanceOverview>> _write(Future<Response<Map<String, dynamic>>> Function() send, String fallback) async {
    try {
      final r = await send();
      return _overviewOf(r.data ?? const {}, fallback);
    } catch (e) {
      return _fail(e, fallback);
    }
  }

  static Future<BalanceResult<BalanceOverview>> createPeriod(
          {required int amount, required int startedAtMs, String? note, required String clientRef, required String? companyKey}) =>
      _write(
        () => ApiClient.dio.post<Map<String, dynamic>>('$_base/periods',
            options: _to(companyKey), data: {'amount': amount, 'started_at_ms': startedAtMs, 'note': (note ?? '').trim(), 'client_ref': clientRef}),
        'تعذّر تسجيل الشحن',
      );

  /// [startedAtMs] يُرسل حين تغيّر وحده (وقتٌ لم يتغيّر لا يُعاد فحصه).
  static Future<BalanceResult<BalanceOverview>> updatePeriod(int id,
          {required int amount, int? startedAtMs, required String note, required String? companyKey}) =>
      _write(
        () => ApiClient.dio.put<Map<String, dynamic>>('$_base/periods/$id',
            options: _to(companyKey), data: {'amount': amount, if (startedAtMs != null) 'started_at_ms': startedAtMs, 'note': note.trim()}),
        'تعذّر حفظ التعديل',
      );

  static Future<BalanceResult<BalanceOverview>> deletePeriod(int id, {required String? companyKey}) =>
      _write(() => ApiClient.dio.delete<Map<String, dynamic>>('$_base/periods/$id', options: _to(companyKey)), 'تعذّر حذف الشحن');

  static Future<BalanceResult<BalanceOverview>> addAdjustment(int id,
          {required int amount, required BalanceSource source, String? note, required String clientRef, required String? companyKey}) =>
      _write(
        () => ApiClient.dio.post<Map<String, dynamic>>('$_base/periods/$id/adjustments', options: _to(companyKey), data: {
          'amount': amount,
          'source': source.wire,
          if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
          'client_ref': clientRef,
        }),
        'تعذّر تسجيل التسوية',
      );

  static Future<BalanceResult<BalanceOverview>> removeAdjustment(int id, int adjustmentId, {required String? companyKey}) => _write(
      () => ApiClient.dio.delete<Map<String, dynamic>>('$_base/periods/$id/adjustments/$adjustmentId', options: _to(companyKey)), 'تعذّر حذف التسوية');

  static Future<BalanceResult<BalanceOverview>> closePeriod(int id, {required String? companyKey}) => _write(
      () => ApiClient.dio.post<Map<String, dynamic>>('$_base/periods/$id/close', options: _to(companyKey), data: const {}), 'تعذّر إغلاق الفترة');

  static Future<BalanceResult<BalanceOverview>> reopenPeriod(int id, {required String? companyKey}) => _write(
      () => ApiClient.dio.post<Map<String, dynamic>>('$_base/periods/$id/reopen', options: _to(companyKey), data: const {}), 'تعذّر إلغاء الإغلاق');

  /// رصيد الوكيل الآن عند شركته (ما تعرضه الرئيسيّة) — null: مخفيّ أو تعذّرت قراءته (لا يُقرأ صفراً).
  static Future<double?> liveBalance({required String? companyKey}) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/admin-widgets', options: _to(companyKey));
      final body = r.data ?? const {};
      if (body['success'] != true || body['balanceHidden'] == true || body['balance_unavailable'] == true) return null;
      final b = body['balance'];
      return b is num && b.isFinite ? b.toDouble() : null;
    } catch (e) {
      return null;
    }
  }
}
