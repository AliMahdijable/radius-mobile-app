import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import 'api_client.dart';
import 'company_route.dart';
import 'employee_limits_api.dart' show LimitsResult;

/// «حركات الموظف» وراتبه (١٣ نوفمبر — المالك: «نضيف عمليه ع الموظف … سلفة قرض … وراتب الموظف»).
///
/// الخادم (server/employeeLedger.js) يحسب كلّ رقم — التطبيق يعرض ويرسل فقط:
/// - دفترٌ لكلّ موظف (له/عليه): سلفة، قرض، سحب، مكافأة، خصم، تسديد — وراتبٌ بكشفٍ و«صرف».
/// - المدير، أو موظّفٌ بصلاحيّة `employees.payroll` (لا على نفسه، ولا إلغاء ولا ضبط راتب)؛ والموظف يرى حسابه قراءةً فقط (`/me`).
/// - الكشف يُصرف بما عُرض: `cut` + `expected` يعودان للخادم فيرفض إن تغيّر شيء (409 STALE / PERIOD_CHANGED).
/// - كلّ نداءٍ للشركة **المفتوحة** صراحةً ([CompanyRoute.explicit]): هذه المسارات لا تُوجَّه في «كل الشركات».
typedef LedgerResult<T> = LimitsResult<T>;

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

String? _s(Object? v) {
  final t = v?.toString().trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// أنواع الحركات التي يسجّلها المدير — بترتيب عرضها.
enum LedgerKind {
  advance('advance', 'سلفة', 'يأخذها مقدّماً — تُستقطع من أوّل كشف راتب'),
  loan('loan', 'قرض', 'يُسدَّد بقسطٍ يُستقطع مع كلّ راتب'),
  withdraw('withdraw', 'سحب', 'يأخذه من النقد الذي حصّله — يسلّم أقلّ في التسوية، ويُستقطع من راتبه'),
  bonus('bonus', 'مكافأة', 'تُضاف لكشفه القادم وتُحسب مصروفاً عند الصرف'),
  deduction('deduction', 'خصم', 'يُنقص من كشفه القادم'),
  repayment('repayment', 'تسديد', 'يرجّع نقداً — ينقص ما عليه (السلف أوّلاً ثمّ القروض)');

  const LedgerKind(this.wire, this.label, this.hint);
  final String wire;
  final String label;
  final String hint;

  /// سلفة أو قرض: يُسأل «من أين يُدفع؟» (الصندوق أو النقد الذي بيده). السحب دائماً من النقد الذي بيده.
  bool get needsSource => this == advance || this == loan;

  /// ما ينقص من حساب الموظف (يُعرض بالأحمر).
  bool get isMinus => this == advance || this == withdraw || this == loan || this == deduction;

  static LedgerKind? of(String? wire) {
    for (final k in values) {
      if (k.wire == wire) return k;
    }
    return null;
  }
}

/// حركةٌ في دفتر الموظف.
class LedgerMove {
  const LedgerMove({
    required this.id,
    required this.kind,
    required this.label,
    required this.amount,
    this.fromHand = false,
    this.note,
    this.date,
    this.voided = false,
    this.voidReason,
    this.byEmployee,
  });
  final int id;
  final String kind;
  final String label;
  final double amount;

  /// دُفعت من النقد الذي بيد الموظف (لا من الصندوق).
  final bool fromHand;
  final String? note;

  /// YYYY-MM-DD كما سجّلها الخادم (بتوقيت بغداد).
  final String? date;
  final bool voided;
  final String? voidReason;

  /// اسم الموظّف الذي سجّلها (صاحب الصلاحيّة) — null = المدير.
  final String? byEmployee;

  bool get isMinus => LedgerKind.of(kind)?.isMinus ?? false;

  static LedgerMove? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _i(raw['id']);
    if (id <= 0) return null;
    final kind = raw['kind']?.toString() ?? '';
    final by = raw['by_employee'];
    final v = raw['void'];
    return LedgerMove(
      id: id,
      kind: kind,
      label: _s(raw['label']) ?? LedgerKind.of(kind)?.label ?? kind,
      amount: _n(raw['amount']),
      fromHand: raw['source'] == 'hand',
      note: _s(raw['note']),
      date: _s(raw['date']),
      voided: raw['status'] == 'voided',
      voidReason: v is Map ? _s(v['reason']) : null,
      byEmployee: by is Map ? _s(by['username']) : null,
    );
  }
}

/// قرضٌ قائم.
class LedgerLoan {
  const LedgerLoan({required this.id, required this.principal, required this.installment, required this.remaining});
  final int id;
  final double principal;
  final double installment;
  final double remaining;
  static LedgerLoan? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return LedgerLoan(
      id: _i(raw['id']),
      principal: _n(raw['principal']),
      installment: _n(raw['installment']),
      remaining: _n(raw['remaining']),
    );
  }
}

/// ضبط راتب الموظف.
class LedgerSalary {
  const LedgerSalary({
    this.amount,
    this.weekly = false,
    this.payDay = 1,
    this.mode = 'salary',
    this.configured = false,
    this.dueCount = 0,
    this.lapsed = 0,
    this.nextLabel,
    this.nextDueDate,
    this.elsewhere,
  });

  /// الراتب (د.ع) — null = بلا راتب.
  final double? amount;
  final bool weekly;

  /// شهريّ ١–٢٨، أسبوعيّ ٠–٦ (٠ = الأحد).
  final int payDay;

  /// salary | commission | both.
  final String mode;
  final bool configured;

  /// رواتب استحقّت ولم تُصرف.
  final int dueCount;
  final int lapsed;
  final String? nextLabel;
  final String? nextDueDate;

  /// راتبه الثابت مضبوطٌ في صفحةٍ أخرى من صفحاته (موظّفٌ بأكثر من صفحة — للموظف راتبٌ واحد) — null = لا.
  final LedgerSalaryElsewhere? elsewhere;

  static const dow = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

  bool sameAs(LedgerSalary o) => amount == o.amount && weekly == o.weekly && payDay == o.payDay && mode == o.mode;

  /// «500,000 شهريّاً — يوم 28» / «100,000 أسبوعيّاً — الخميس» / «عمولة العمليّات» / null. [money] ينسّق المبلغ.
  String? describe(String Function(num) money) {
    if (!configured) return null;
    final parts = <String>[];
    final a = amount;
    if (a != null && a > 0 && mode != 'commission') {
      parts.add(weekly
          ? '${money(a)} أسبوعيّاً — ${payDay >= 0 && payDay < dow.length ? dow[payDay] : ''}'
          : '${money(a)} شهريّاً — يوم $payDay');
    }
    if (mode != 'salary') parts.add('عمولة العمليّات');
    return parts.isEmpty ? null : parts.join(' + ');
  }

  static LedgerSalary fromJson(Object? raw) {
    if (raw is! Map) return const LedgerSalary();
    final a = _n(raw['amount']);
    final next = raw['next_due'];
    final mode = raw['comp_mode']?.toString();
    return LedgerSalary(
      amount: a > 0 ? a : null,
      weekly: raw['cycle'] == 'weekly',
      payDay: _i(raw['pay_day']),
      mode: mode == 'commission' || mode == 'both' ? mode! : 'salary',
      configured: raw['configured'] == true,
      dueCount: _i(raw['due_count']),
      lapsed: _i(raw['lapsed']),
      nextLabel: next is Map ? _s(next['label']) : null,
      nextDueDate: next is Map ? _s(next['due_date']) : null,
      elsewhere: LedgerSalaryElsewhere.fromJson(raw['elsewhere']),
    );
  }
}

/// «راتبٌ واحد للموظف في كلّ صفحاته» (١٤ نوفمبر): الموظّف المربوط بأكثر من صفحة راتبه الثابت في صفحةٍ واحدة منها — صفحاته
/// الأخرى تعرضه ولا تطلبه (الخادم يرفض راتباً ثانياً SALARY_ON_OTHER_PAGE).
class LedgerSalaryElsewhere {
  const LedgerSalaryElsewhere({this.pageName, required this.salary});

  /// اسم الصفحة كما يسمّيها حسابه — null = غير معروف.
  final String? pageName;

  /// ضبطه هناك (المبلغ والدورة واليوم وطريقة الأجر).
  final LedgerSalary salary;

  /// «في صفحة «الاسم»» أو «في صفحةٍ أخرى».
  String get where {
    final n = (pageName ?? '').trim();
    return n.isEmpty ? 'في صفحةٍ أخرى' : 'في صفحة «$n»';
  }

  static LedgerSalaryElsewhere? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final s = LedgerSalary.fromJson({...raw, 'configured': true, 'elsewhere': null});
    if (s.amount == null) return null;
    return LedgerSalaryElsewhere(pageName: _s(raw['page_name']), salary: s);
  }
}

/// كشف راتبٍ مصروف (أو ملغى).
class LedgerPayslip {
  const LedgerPayslip({
    required this.id,
    required this.number,
    required this.paid,
    this.payDate,
    this.gross = 0,
    this.recoverSum = 0,
    this.installmentSum = 0,
    this.net = 0,
    this.fromHand = false,
    this.periodLabels = const [],
    this.voidReason,
  });
  final int id;
  final int number;

  /// false = ملغى.
  final bool paid;
  final String? payDate;

  /// المستحقّ — ما نزل في المصاريف.
  final double gross;
  final double recoverSum;
  final double installmentSum;

  /// ما استلمه نقداً.
  final double net;
  final bool fromHand;
  final List<String> periodLabels;
  final String? voidReason;

  double get deducted => recoverSum + installmentSum;

  static LedgerPayslip? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _i(raw['id']);
    if (id <= 0) return null;
    final periods = raw['periods'];
    final v = raw['void'];
    return LedgerPayslip(
      id: id,
      number: _i(raw['number']),
      paid: raw['status'] == 'paid',
      payDate: _s(raw['pay_date']),
      gross: _n(raw['gross']),
      recoverSum: _n(raw['recover_sum']),
      installmentSum: _n(raw['installment_sum']),
      net: _n(raw['net']),
      fromHand: raw['source'] == 'hand',
      periodLabels: periods is List
          ? periods.map((p) => p is Map ? _s(p['label'] ?? p['key']) : null).whereType<String>().toList()
          : const [],
      voidReason: v is Map ? _s(v['reason']) : null,
    );
  }
}

/// ملخّص حساب موظّف (سطر القائمة، ورأس حسابه).
class LedgerSummary {
  const LedgerSummary({
    required this.employeeId,
    this.username,
    this.name,
    this.active = true,
    this.owed = 0,
    this.loansTotal = 0,
    this.owesTotal = 0,
    this.duePending = 0,
    this.salary = const LedgerSalary(),
  });
  final int employeeId;
  final String? username;
  final String? name;
  final bool active;

  /// سلف وسحوبات لم تُستقطع بعد.
  final double owed;

  /// المتبقّي من قروضه.
  final double loansTotal;

  /// عليه = السلف والسحوبات + القروض.
  final double owesTotal;

  /// له في كشفه القادم (مكافآت − خصومات لم تُصرف) — سالب = خصومات.
  final double duePending;
  final LedgerSalary salary;

  String get displayName => (name != null && name!.trim().isNotEmpty) ? name!.trim() : (username ?? '#$employeeId');

  /// له راتبٌ استحقّ ولم يُصرف.
  bool get salaryDue => salary.dueCount > 0;

  /// عنده ما يُقال في القائمة (عليه شيء، له شيء، أو راتبٌ مستحقّ).
  bool get hasNews => owesTotal > 0 || duePending != 0 || salaryDue;

  static LedgerSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final emp = raw['employee'];
    final id = _i(emp is Map ? emp['id'] : null);
    if (id <= 0) return null;
    return LedgerSummary(
      employeeId: id,
      username: emp is Map ? _s(emp['username']) : null,
      name: emp is Map ? _s(emp['name']) : null,
      active: raw['active'] != false,
      owed: _n(raw['owed']),
      loansTotal: _n(raw['loans_total']),
      owesTotal: _n(raw['owes_total']),
      duePending: _n(raw['due_pending']),
      salary: LedgerSalary.fromJson(raw['salary']),
    );
  }
}

/// حساب موظّفٍ كاملاً: ملخّصه، قروضه، آخر حركاته وكشوفه.
class LedgerAccount {
  const LedgerAccount({
    required this.summary,
    this.loans = const [],
    this.movements = const [],
    this.movementsTotal = 0,
    this.payslips = const [],
    this.payslipsTotal = 0,
    this.featureEnabled = true,
  });
  final LedgerSummary summary;
  final List<LedgerLoan> loans;
  final List<LedgerMove> movements;
  final int movementsTotal;
  final List<LedgerPayslip> payslips;
  final int payslipsTotal;

  /// false = الميزة موقوفة لهذه الصفحة: القراءة باقية والكتابة يرفضها الخادم.
  final bool featureEnabled;

  /// آخر كشفٍ مصروف — وحده يُلغى.
  LedgerPayslip? get latestPaid {
    for (final s in payslips) {
      if (s.paid) return s;
    }
    return null;
  }

  bool get isEmpty => movements.isEmpty && payslips.isEmpty;

  static LedgerAccount? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final s = LedgerSummary.fromJson(raw);
    if (s == null) return null;
    List<T> list<T>(Object? v, T? Function(Object?) f) => v is List ? v.map(f).whereType<T>().toList() : <T>[];
    return LedgerAccount(
      summary: s,
      loans: list(raw['loans'], LedgerLoan.fromJson),
      movements: list(raw['movements'], LedgerMove.fromJson),
      movementsTotal: _i(raw['movements_total']),
      payslips: list(raw['payslips'], LedgerPayslip.fromJson),
      payslipsTotal: _i(raw['payslips_total']),
      featureEnabled: raw['feature_enabled'] != false,
    );
  }
}

/// فترة راتبٍ في معاينة الكشف.
class PayslipPeriod {
  const PayslipPeriod({required this.key, required this.label, required this.dueDate, required this.due, required this.amount, required this.selected});
  final String key;
  final String label;
  final String dueDate;

  /// استحقّت (وإلّا فهي القادمة — صرفٌ مبكّر).
  final bool due;
  final double amount;
  final bool selected;
  static PayslipPeriod? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = _s(raw['key']);
    if (key == null) return null;
    return PayslipPeriod(
      key: key,
      label: _s(raw['label']) ?? key,
      dueDate: _s(raw['due_date']) ?? '',
      due: raw['due'] == true,
      amount: _n(raw['amount']),
      selected: raw['selected'] == true,
    );
  }
}

/// معاينة «كشف الراتب» — كلّ أرقامها من الخادم، وتُعاد إليه كما هي عند «صرف».
class PayslipPreview {
  const PayslipPreview({
    required this.periods,
    required this.cut,
    this.expected,
    this.lapsed = 0,
    this.salarySum = 0,
    this.commissionEnabled = false,
    this.commissionOps = 0,
    this.commissionSum = 0,
    this.commissionUnavailable = false,
    this.bonusCount = 0,
    this.bonusSum = 0,
    this.deductionCount = 0,
    this.deductionSum = 0,
    this.owed = 0,
    this.loanTakes = const [],
    this.loansCount = 0,
    this.gross = 0,
    this.recover = 0,
    this.installmentSum = 0,
    this.net = 0,
    this.canPay = false,
    this.problem,
  });
  final List<PayslipPeriod> periods;

  /// حدّ الدفتر والعمولة الذي حُسبت عليه المعاينة — يُرسَل كما هو.
  final Map<String, dynamic> cut;

  /// {gross, net} — null حين لا يُصرف (الخصومات أكبر من المستحقّ).
  final Map<String, dynamic>? expected;
  final int lapsed;
  final double salarySum;
  final bool commissionEnabled;
  final int commissionOps;
  final double commissionSum;

  /// تعذّر حساب العمولة الآن ⇒ «—» لا صفر، وتدخل الكشف القادم.
  final bool commissionUnavailable;
  final int bonusCount;
  final double bonusSum;
  final int deductionCount;
  final double deductionSum;

  /// ما عليه من سلف وسحوبات قبل هذا الكشف.
  final double owed;

  /// أقساط القروض المستقطعة في هذا الكشف: (القسط، المتبقّي من القرض قبله).
  final List<({double take, double remaining})> loanTakes;
  final int loansCount;
  final double gross;
  final double recover;
  final double installmentSum;
  final double net;
  final bool canPay;

  /// سبب عدم الصرف (رسالة الخادم العربيّة).
  final String? problem;

  List<String> get selectedKeys => [for (final p in periods) if (p.selected) p.key];

  static PayslipPreview? fromJson(Object? raw) {
    if (raw is! Map || raw['cut'] is! Map) return null;
    final comm = raw['commission'];
    final loans = raw['loans'];
    final bonuses = raw['bonuses'];
    final deductions = raw['deductions'];
    final problem = raw['problem'];
    final periods = raw['periods'];
    final takes = <({double take, double remaining})>[];
    if (loans is List) {
      for (final l in loans) {
        if (l is Map && _n(l['take']) > 0) takes.add((take: _n(l['take']), remaining: _n(l['remaining'])));
      }
    }
    return PayslipPreview(
      periods: periods is List ? periods.map(PayslipPeriod.fromJson).whereType<PayslipPeriod>().toList() : const [],
      cut: Map<String, dynamic>.from(raw['cut'] as Map),
      expected: raw['expected'] is Map ? Map<String, dynamic>.from(raw['expected'] as Map) : null,
      lapsed: _i(raw['lapsed']),
      salarySum: _n(raw['salary_sum']),
      commissionEnabled: comm is Map && comm['enabled'] == true,
      commissionOps: comm is Map ? _i(comm['ops']) : 0,
      commissionSum: comm is Map ? _n(comm['sum']) : 0,
      commissionUnavailable: comm is Map && comm['unavailable'] == true,
      bonusCount: bonuses is List ? bonuses.length : 0,
      bonusSum: _n(raw['bonus_sum']),
      deductionCount: deductions is List ? deductions.length : 0,
      deductionSum: _n(raw['deduction_sum']),
      owed: _n(raw['owed']),
      loanTakes: takes,
      loansCount: loans is List ? loans.length : 0,
      gross: _n(raw['gross']),
      recover: _n(raw['recover']),
      installmentSum: _n(raw['installment_sum']),
      net: _n(raw['net']),
      canPay: raw['can_pay'] == true && raw['expected'] is Map,
      problem: problem is Map ? _s(problem['message']) : null,
    );
  }
}

/// من أنا في هذه الميزة.
class LedgerMe {
  const LedgerMe({required this.isEmployee, required this.featureEnabled, required this.canManage, this.account});
  final bool isEmployee;

  /// الميزة مفتوحة لهذه الصفحة.
  final bool featureEnabled;

  /// يسجّل الحركات ويصرف الكشوف: المدير، أو موظّفٌ بالصلاحيّة (لغيره).
  final bool canManage;

  /// الموظّف: حسابه هو (قراءةً فقط) — null للمدير أو حين الميزة مطفأة.
  final LedgerAccount? account;

  /// مفتوحة ويدير بها.
  bool get manages => featureEnabled && canManage;

  /// المدير نفسه (الإلغاء وضبط الراتب له وحده).
  bool get isManager => featureEnabled && !isEmployee;
}

class EmployeeLedgerApi {
  EmployeeLedgerApi._();

  static const _base = '/api/v2/employee-ledger';

  /// للشركة المفتوحة صراحةً — لا تأخذ وجهة قسمٍ موجَّه.
  static Options get _open => CompanyRoute.explicit(null);

  static final Random _rnd = Random();

  /// مفتاح منع التكرار (8–64 من `[A-Za-z0-9_-]`): ثابتٌ للنيّة الواحدة — ضغطتان أو شبكةٌ انقطعت بعد الحفظ = عمليّةٌ واحدة.
  static String newRef([String prefix = 'a']) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final tail = List.generate(8, (_) => chars[_rnd.nextInt(chars.length)]).join();
    return '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$tail';
  }

  static LedgerResult<T> _fail<T>(Object e, String fallback) {
    if (e is DioException) {
      final body = e.response?.data;
      if (body is Map) {
        return LedgerResult<T>(
          message: body['message']?.toString() ?? fallback,
          code: body['code']?.toString(),
          status: e.response?.statusCode,
        );
      }
      return LedgerResult<T>(message: fallback, status: e.response?.statusCode);
    }
    if (!kReleaseMode) debugPrint('🔴 employee-ledger: $e');
    return LedgerResult<T>(message: fallback);
  }

  static LedgerResult<T> _refused<T>(Map body, String fallback) =>
      LedgerResult<T>(message: body['message']?.toString() ?? fallback, code: body['code']?.toString());

  /// هل الميزة مفتوحة لهذه الصفحة، ومن أنا فيها؟ null = تعذّر السؤال (تُعامل مطفأة — لا أزرار ولا أخطاء).
  static Future<LedgerMe?> me() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('$_base/me', options: _open);
      final body = r.data ?? const {};
      final data = body['data'];
      if (body['success'] != true || data is! Map) return null;
      final isEmp = data['is_employee'] == true;
      final on = data['feature_enabled'] == true;
      return LedgerMe(
        isEmployee: isEmp,
        featureEnabled: on,
        canManage: data['can_manage'] == true,
        account: isEmp && on ? LedgerAccount.fromJson(data) : null,
      );
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 employee-ledger me: $e');
      return null;
    }
  }

  /// كلّ موظّفي الصفحة بملخّص حساب كلٍّ منهم. null = تعذّر أو الميزة مطفأة.
  static Future<List<LedgerSummary>?> list() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(_base, options: _open);
      final body = r.data ?? const {};
      final data = body['data'];
      if (body['success'] != true || data is! Map || data['feature_enabled'] != true) return null;
      final rows = data['employees'];
      if (rows is! List) return null;
      return rows.map(LedgerSummary.fromJson).whereType<LedgerSummary>().toList();
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 employee-ledger list: $e');
      return null;
    }
  }

  static Future<LedgerResult<LedgerAccount>> account(int id) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('$_base/$id', options: _open);
      final body = r.data ?? const {};
      final a = LedgerAccount.fromJson(body['data']);
      if (body['success'] != true || a == null) return _refused(body, 'تعذّر تحميل حساب الموظف');
      return LedgerResult(data: a);
    } catch (e) {
      return _fail(e, 'تعذّر تحميل حساب الموظف');
    }
  }

  /// تسجيل حركة. [clientRef] ثابتٌ لنافذةٍ واحدة. data = true حين سُجّلت (ولو تعذّر عرض الحساب بعدها).
  static Future<LedgerResult<bool>> addMovement(
    int id, {
    required LedgerKind kind,
    required int amount,
    bool fromHand = false,
    int? installment,
    String? note,
    required String clientRef,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/$id/movements', options: _open, data: {
        'kind': kind.wire,
        'amount': amount,
        if (kind.needsSource) 'source': fromHand ? 'hand' : 'box',
        if (kind == LedgerKind.loan) 'installment': installment,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        'client_ref': clientRef,
      });
      final body = r.data ?? const {};
      if (body['success'] != true) return _refused(body, 'تعذّر تسجيل الحركة');
      return const LedgerResult(data: true);
    } catch (e) {
      return _fail(e, 'تعذّر تسجيل الحركة');
    }
  }

  /// المدير وحده: إلغاء حركةٍ بسبب (قيدٌ معاكس — لا حذف).
  static Future<LedgerResult<bool>> voidMovement(int id, int moveId, String reason) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/$id/movements/$moveId/void', options: _open, data: {'reason': reason});
      final body = r.data ?? const {};
      if (body['success'] != true) return _refused(body, 'تعذّر الإلغاء');
      return const LedgerResult(data: true);
    } catch (e) {
      return _fail(e, 'تعذّر الإلغاء');
    }
  }

  /// المدير وحده: ضبط الراتب. amount null = بلا راتب.
  static Future<LedgerResult<bool>> setSalary(int id, LedgerSalary s) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>('$_base/$id/salary', options: _open, data: {
        'amount': s.amount?.round(),
        'cycle': s.weekly ? 'weekly' : 'monthly',
        'pay_day': s.payDay,
        'comp_mode': s.mode,
      });
      final body = r.data ?? const {};
      if (body['success'] != true) return _refused(body, 'تعذّر حفظ الراتب');
      return const LedgerResult(data: true);
    } catch (e) {
      return _fail(e, 'تعذّر حفظ الراتب');
    }
  }

  /// معاينة الكشف. [periods] null = ما يختاره الخادم (المستحقّة كلّها)؛ قائمة = المختارة بعينها (ولو فارغة).
  static Future<LedgerResult<PayslipPreview>> previewPayslip(int id, {List<String>? periods}) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '$_base/$id/payslip/preview',
        options: _open,
        queryParameters: {if (periods != null) 'periods': periods.join(',')},
      );
      final body = r.data ?? const {};
      final p = PayslipPreview.fromJson(body['data']);
      if (body['success'] != true || p == null) return _refused(body, 'تعذّر تجهيز الكشف');
      return LedgerResult(data: p);
    } catch (e) {
      return _fail(e, 'تعذّر تجهيز الكشف');
    }
  }

  /// «صرف» بما عُرض — تغيّر شيء ⇒ 409 STALE / PERIOD_CHANGED (تُعاد المعاينة).
  static Future<LedgerResult<bool>> payPayslip(int id, PayslipPreview p, {bool fromHand = false, String? note, required String clientRef}) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/$id/payslip', options: _open, data: {
        'periods': p.selectedKeys,
        'cut': p.cut,
        'expected': p.expected,
        'source': fromHand ? 'hand' : 'box',
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        'client_ref': clientRef,
      });
      final body = r.data ?? const {};
      if (body['success'] != true) return _refused(body, 'تعذّر الصرف');
      return const LedgerResult(data: true);
    } catch (e) {
      return _fail(e, 'تعذّر الصرف');
    }
  }

  /// المدير وحده: إلغاء آخر كشف (تُحذف صرفيّته وتعود استقطاعاته).
  static Future<LedgerResult<bool>> voidPayslip(int id, int payslipId, String reason) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/$id/payslips/$payslipId/void', options: _open, data: {'reason': reason});
      final body = r.data ?? const {};
      if (body['success'] != true) return _refused(body, 'تعذّر الإلغاء');
      return const LedgerResult(data: true);
    } catch (e) {
      return _fail(e, 'تعذّر الإلغاء');
    }
  }

  /// المدير وحده: تخطّي راتبٍ استحقّ بلا صرف.
  static Future<LedgerResult<bool>> skipPeriod(int id, String key) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/$id/periods/${Uri.encodeComponent(key)}/skip', options: _open, data: const {});
      final body = r.data ?? const {};
      if (body['success'] != true) return _refused(body, 'تعذّر التخطّي');
      return const LedgerResult(data: true);
    } catch (e) {
      return _fail(e, 'تعذّر التخطّي');
    }
  }
}

/// حال الميزة لهذه الجلسة — لما يُبنى بلا انتظار (بند «حركة موظف» في الإضافة السريعة). مثل `SalesState`: الاستماع يطلب الحال إن
/// كانت قديمة، ولا شيء يظهر ما لم يقل الخادم إنّها مفتوحة وإنّ المستعمل يدير بها. تبديل الجلسة يصفّرها ([reset]).
class EmployeeLedgerState {
  EmployeeLedgerState._();

  static final ValueNotifier<LedgerMe?> gate = _LedgerGate();

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static Future<void>? _inflight;

  static const ttl = Duration(minutes: 5);
  static const _cooldown = Duration(seconds: 30);

  /// الميزة مفتوحة لهذه الصفحة والمستعمل يسجّل بها (المدير أو صاحب الصلاحيّة).
  static bool get manages => gate.value?.manages ?? false;

  static Future<void> ensureFresh({bool force = false}) {
    final running = _inflight;
    if (running != null) return running;
    if (!force) {
      final now = DateTime.now();
      final at = _fetchedAt;
      if (at != null && now.difference(at) < ttl) return Future<void>.value();
      final failed = _failedAt;
      if (failed != null && now.difference(failed) < _cooldown) return Future<void>.value();
    }
    final epoch = _epoch;
    late final Future<void> run;
    run = _probe().then((m) {
      if (epoch != _epoch) return;
      if (m == null) {
        _failedAt = DateTime.now();
        return;
      }
      _fetchedAt = DateTime.now();
      _failedAt = null;
      gate.value = m;
    }).whenComplete(() {
      if (identical(_inflight, run)) _inflight = null;
    });
    _inflight = run;
    return run;
  }

  /// بلا جلسة ⇒ لا نداء.
  static Future<LedgerMe?> _probe() async {
    String? token;
    try {
      token = await AuthStorage.readToken();
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) return null;
    return EmployeeLedgerApi.me();
  }

  /// ما عرفته شاشةٌ سألت للتوّ (قسم الموظفين) — فلا يُسأل ثانيةً.
  static void note(LedgerMe? m) {
    if (m == null) return;
    _fetchedAt = DateTime.now();
    _failedAt = null;
    gate.value = m;
  }

  /// تبديل الجلسة: لا يرى المدير التالي حال سابقه.
  static void reset() {
    _epoch++;
    _fetchedAt = null;
    _failedAt = null;
    _inflight = null;
    gate.value = null;
  }

  @visibleForTesting
  static void debugSet(LedgerMe? m) {
    _epoch++;
    _inflight = null;
    _failedAt = null;
    _fetchedAt = m == null ? null : DateTime.now();
    gate.value = m;
  }
}

class _LedgerGate extends ValueNotifier<LedgerMe?> {
  _LedgerGate() : super(null);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    // بعد البناء لا أثناءه: الجلب يكتب القيمة فيُعيد بناء المستمعين.
    scheduleMicrotask(EmployeeLedgerState.ensureFresh);
  }
}
