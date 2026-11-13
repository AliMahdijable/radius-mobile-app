import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// «حدود الموظّف» (٩ نوفمبر — المالك: «سقف الديون والإيرادات وربح الموظف»).
///
/// الخادم (server/employeeLimits.js) يضبطها ويفرضها ويحسبها — التطبيق يعرض ويرسل فقط:
/// - المدير وحده يضبط القيم الثلاث ويسوّي حساب الموظّف (`/api/v2/employee-limits/:id…`).
/// - الموظّف يقرأ حاله هو (`/api/v2/employee-limits/me`).
/// - الرفض (سقفٌ بلغه) يأتي من مسارات المال نفسها برسالته العربيّة — يُعرض كما هو (409 `EMPLOYEE_CASH_CAP` / `EMPLOYEE_DEBT_CAP`).
class EmployeeLimits {
  const EmployeeLimits({this.debtCap, this.cashCap, this.profitPerOp});

  /// سقف الديون (د.ع) — null = بلا حدّ.
  final double? debtCap;

  /// سقف الإيرادات النقديّة (د.ع) — null = بلا حدّ.
  final double? cashCap;

  /// ربح الموظّف لكلّ عمليّةٍ كاملة (د.ع) — null = لا ربح.
  final double? profitPerOp;

  bool get hasCaps => debtCap != null || cashCap != null;
  bool get isEmpty => debtCap == null && cashCap == null && (profitPerOp == null || profitPerOp == 0);

  static double? _n(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static EmployeeLimits fromJson(Object? raw) {
    if (raw is! Map) return const EmployeeLimits();
    return EmployeeLimits(
      debtCap: _n(raw['debt_cap']),
      cashCap: _n(raw['cash_cap']),
      profitPerOp: _n(raw['profit_per_op']),
    );
  }

  bool sameAs(EmployeeLimits o) => debtCap == o.debtCap && cashCap == o.cashCap && profitPerOp == o.profitPerOp;
}

/// مجموعٌ وعدد (بندٌ من تفصيل الفترة).
class MoneyCount {
  const MoneyCount(this.sum, this.count);
  final double sum;
  final int count;
  static MoneyCount fromJson(Object? raw) {
    if (raw is! Map) return const MoneyCount(0, 0);
    return MoneyCount(EmployeeLimits._n(raw['sum']) ?? 0, int.tryParse('${raw['count'] ?? 0}') ?? 0);
  }
}

/// حال الموظّف في فترته الحاليّة (منذ آخر تسوية).
class EmployeeLimitStatus {
  const EmployeeLimitStatus({
    required this.employeeId,
    this.username,
    this.name,
    required this.featureEnabled,
    required this.enforcementOff,
    required this.limits,
    required this.started,
    this.periodStart,
    this.cashIn = 0,
    this.debtOut = 0,
    this.openDebt = 0,
    this.openDebtApprox = false,
    this.holdsCount = 0,
    this.holdsCash = 0,
    this.holdsDebt = 0,
    this.cashUsed = 0,
    this.debtUsed = 0,
    this.cashRemaining,
    this.debtRemaining,
    this.cashBlocked = false,
    this.debtBlocked = false,
    this.opsCount = 0,
    this.profit = 0,
    this.breakdown = const {},
    this.holds = const [],
    this.settlements = const [],
    this.statusUnavailable = false,
    this.note,
    this.handTaken = 0,
    this.toHandOver,
  });

  final int employeeId;

  /// «حركات الموظف» (١٣ نوفمبر): ما أخذه من النقد الذي بيده في هذه الفترة (سحب، سلفة أو راتب من يده، ناقص ما سدّده) —
  /// للعرض وحده، السقف لا يتغيّر به. صفر من خادمٍ قبله أو حين لا شيء.
  final double handTaken;

  /// ما يسلّمه فعلاً = النقد الذي استلمه − [handTaken]. null = الخادم لم يرسله.
  final double? toHandOver;

  /// الخادم قرأ الحدود وتعذّرت أرقام الحال الآن (`status_unavailable`) ⇒ تُعرض [note] لا أصفار؛ الحدود تُعدَّل كالعادة.
  final bool statusUnavailable;
  final String? note;
  final String? username;
  final String? name;
  final bool featureEnabled;
  final bool enforcementOff;
  final EmployeeLimits limits;

  /// بدأ العدّ (ضُبطت قيمةٌ مرّةً على الأقلّ).
  final bool started;
  final DateTime? periodStart;
  final double cashIn;

  /// ديونٌ أعطاها في هذه الفترة (للعلم — لا يُقاس بها السقف).
  final double debtOut;

  /// «ديونه المفتوحة عند المشتركين»: ما زالوا يدينون به من ديونٍ أعطاها منذ فُتحت له الميزة — تنقص حين يسدّد المشترك،
  /// ولا تصفّرها التسوية (قرار المالك ٩ نوفمبر). سقف الديون يُقاس بها.
  final double openDebt;

  /// تقريبيّ (سوبرنت: من سجلّ النشاط — تسديدٌ خارج التطبيق لا يُرى فيبقى مفتوحاً).
  final bool openDebtApprox;
  final int holdsCount;
  final double holdsCash;
  final double holdsDebt;

  /// المعدود في السقف (السجلّ + المحجوز غير المؤكَّد؛ والدين = ديونه المفتوحة + محجوزها).
  final double cashUsed;
  final double debtUsed;
  final double? cashRemaining;
  final double? debtRemaining;
  final bool cashBlocked;
  final bool debtBlocked;
  final int opsCount;
  final double profit;
  final Map<String, MoneyCount> breakdown;
  final List<EmployeeLimitHold> holds;
  final List<EmployeeSettlement> settlements;

  String get displayName => (name != null && name!.trim().isNotEmpty) ? name!.trim() : (username ?? '#$employeeId');

  static DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  static EmployeeLimitStatus? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final emp = raw['employee'];
    final id = int.tryParse('${emp is Map ? emp['id'] : raw['employee_id'] ?? ''}') ?? 0;
    final holds = raw['holds'];
    final bd = <String, MoneyCount>{};
    final rawBd = raw['breakdown'];
    if (rawBd is Map) {
      rawBd.forEach((k, v) => bd[k.toString()] = MoneyCount.fromJson(v));
    }
    final period = raw['period'];
    return EmployeeLimitStatus(
      employeeId: id,
      username: emp is Map ? emp['username']?.toString() : null,
      name: emp is Map ? emp['name']?.toString() : null,
      featureEnabled: raw['feature_enabled'] != false,
      enforcementOff: raw['enforcement_off'] == true,
      limits: EmployeeLimits.fromJson(raw['limits']),
      started: raw['started'] == true,
      periodStart: period is Map ? _d(period['start_at']) : null,
      cashIn: EmployeeLimits._n(raw['cash_in']) ?? 0,
      debtOut: EmployeeLimits._n(raw['debt_out']) ?? 0,
      openDebt: EmployeeLimits._n(raw['open_debt']) ?? EmployeeLimits._n(raw['debt_used']) ?? 0,
      openDebtApprox: raw['open_debt_approx'] == true,
      holdsCount: holds is Map ? int.tryParse('${holds['count'] ?? 0}') ?? 0 : 0,
      holdsCash: holds is Map ? EmployeeLimits._n(holds['cash']) ?? 0 : 0,
      holdsDebt: holds is Map ? EmployeeLimits._n(holds['debt']) ?? 0 : 0,
      cashUsed: EmployeeLimits._n(raw['cash_used']) ?? 0,
      debtUsed: EmployeeLimits._n(raw['debt_used']) ?? 0,
      cashRemaining: EmployeeLimits._n(raw['cash_remaining']),
      debtRemaining: EmployeeLimits._n(raw['debt_remaining']),
      cashBlocked: raw['cash_blocked'] == true,
      debtBlocked: raw['debt_blocked'] == true,
      opsCount: int.tryParse('${raw['ops_count'] ?? 0}') ?? 0,
      profit: EmployeeLimits._n(raw['profit']) ?? 0,
      breakdown: bd,
      holds: (raw['holds_list'] is List)
          ? (raw['holds_list'] as List).map(EmployeeLimitHold.fromJson).whereType<EmployeeLimitHold>().toList()
          : const [],
      settlements: (raw['settlements'] is List)
          ? (raw['settlements'] as List).map(EmployeeSettlement.fromJson).whereType<EmployeeSettlement>().toList()
          : const [],
      statusUnavailable: raw['status_unavailable'] == true,
      note: raw['note']?.toString(),
      handTaken: EmployeeLimits._n(raw['hand_taken']) ?? 0,
      toHandOver: EmployeeLimits._n(raw['to_hand_over']),
    );
  }
}

/// مبلغ عمليّةٍ لم يثبت سطرها (نتيجتها مجهولة أو جارية) — يُعدّ في السقف حتى التسوية أو يحرّره المدير.
class EmployeeLimitHold {
  const EmployeeLimitHold({required this.id, required this.op, required this.cash, required this.debt, required this.status, this.createdAt});
  final int id;
  final String op;
  final double cash;
  final double debt;
  final String status;
  final DateTime? createdAt;

  String get opLabel => switch (op) {
        'activate' || 'activate_card' => 'تفعيل',
        'pay_debt' => 'تسديد دين',
        'add_debt' => 'إضافة دين',
        'sale' => 'بيع',
        'create' => 'إضافة مشترك',
        'wallet_topup' => 'تعبئة محفظة',
        _ => op,
      };

  String get statusLabel => switch (status) {
        'unknown' => 'نتيجتها غير مؤكّدة',
        'unlogged' => 'تمّت ولم يظهر سطرها',
        'pending' => 'بانتظار الدفع',
        _ => status,
      };

  static EmployeeLimitHold? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = int.tryParse('${raw['id'] ?? ''}') ?? 0;
    if (id == 0) return null;
    return EmployeeLimitHold(
      id: id,
      op: raw['op']?.toString() ?? '',
      cash: EmployeeLimits._n(raw['cash']) ?? 0,
      debt: EmployeeLimits._n(raw['debt']) ?? 0,
      status: raw['status']?.toString() ?? '',
      createdAt: EmployeeLimitStatus._d(raw['created_at']),
    );
  }
}

/// تسويةٌ محفوظة مع الموظّف (لقطة أرقام فترتها).
class EmployeeSettlement {
  const EmployeeSettlement({
    required this.id,
    this.number,
    required this.status,
    this.periodStart,
    this.cutAt,
    this.cashIn = 0,
    this.debtOut = 0,
    this.openDebt,
    this.openDebtUnavailable = false,
    this.opsCount = 0,
    this.profit = 0,
    this.holdsCount = 0,
    this.note,
    this.voidReason,
  });
  final int id;
  final int? number;
  final String status;
  final DateTime? periodStart;
  final DateTime? cutAt;
  final double cashIn;
  final double debtOut;

  /// ديونه المفتوحة وقت التسوية (لقطةٌ للعلم — التسوية لا تصفّرها)؛ null في تسوياتٍ قبل ٩ نوفمبر.
  final double? openDebt;

  /// تعذّرت قراءة ديونه المفتوحة وقت التسوية ⇒ «—» (لا «دين الفترة» ولا صفر).
  final bool openDebtUnavailable;
  final int opsCount;
  final double profit;
  final int holdsCount;
  final String? note;
  final String? voidReason;

  bool get voided => status == 'voided';

  static EmployeeSettlement? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = int.tryParse('${raw['id'] ?? ''}') ?? 0;
    if (id == 0) return null;
    final holds = raw['holds'];
    return EmployeeSettlement(
      id: id,
      number: int.tryParse('${raw['number'] ?? ''}'),
      status: raw['status']?.toString() ?? 'active',
      periodStart: EmployeeLimitStatus._d(raw['period_start_at']),
      cutAt: EmployeeLimitStatus._d(raw['cut_at']),
      cashIn: EmployeeLimits._n(raw['cash_in']) ?? 0,
      debtOut: EmployeeLimits._n(raw['debt_out']) ?? 0,
      openDebt: EmployeeLimits._n(raw['open_debt']),
      openDebtUnavailable: raw['open_debt_unavailable'] == true,
      opsCount: int.tryParse('${raw['ops_count'] ?? 0}') ?? 0,
      profit: EmployeeLimits._n(raw['profit']) ?? 0,
      holdsCount: holds is Map ? int.tryParse('${holds['count'] ?? 0}') ?? 0 : 0,
      note: raw['note']?.toString(),
      voidReason: raw['void_reason']?.toString(),
    );
  }
}

/// معاينة التسوية — الحدّ والأرقام التي ستُسوّى (ما تراه هو ما يُسوّى: الخادم يعيد الحساب بالحدّ نفسه).
class SettlementPreview {
  const SettlementPreview({
    required this.cut,
    required this.cashIn,
    required this.debtOut,
    required this.opsCount,
    required this.profit,
    required this.holdsCount,
    required this.holdsCash,
    required this.holdsDebt,
    this.openDebt,
    this.openDebtApprox = false,
    this.openDebtUnavailable = false,
    this.periodStart,
    this.breakdown = const {},
    this.handTaken,
    this.toHandOver,
  });
  final Map<String, dynamic> cut;

  /// «حركات الموظف»: ما أخذه من النقد الذي بيده — يُعاد للخادم مع التأكيد فيرفض التسوية إن تغيّر منذ المعاينة.
  /// null = الخادم لم يرسله (ميزةٌ مطفأة أو خادمٌ قبلها) ⇒ لا يُرسل ولا يُعرض.
  final double? handTaken;

  /// ما يسلّمه فعلاً = [cashIn] − [handTaken]. null ⇒ [cashIn].
  final double? toHandOver;
  final double cashIn;
  final double debtOut;

  /// ديونه المفتوحة عند المشتركين الآن — للعلم، التسوية لا تصفّرها. null = غير معروفة ⇒ «—» (لا صفر، مراجعة المال ٦).
  final double? openDebt;

  /// تقريبيّة (سوبرنت: من سجلّ النشاط) — أو تعذّرت.
  final bool openDebtApprox;

  /// الخادم قالها صراحةً: تعذّرت قراءتها الآن، والتسوية تمضي بالنقد وحده (لا يُستنتج من غيابها — خادمٌ أقدم لا يرسلها).
  final bool openDebtUnavailable;
  final int opsCount;
  final double profit;
  final int holdsCount;
  final double holdsCash;
  final double holdsDebt;
  final DateTime? periodStart;
  final Map<String, MoneyCount> breakdown;

  static SettlementPreview? fromJson(Object? raw) {
    if (raw is! Map || raw['cut'] is! Map) return null;
    final holds = raw['holds'];
    final bd = <String, MoneyCount>{};
    final rawBd = raw['breakdown'];
    if (rawBd is Map) rawBd.forEach((k, v) => bd[k.toString()] = MoneyCount.fromJson(v));
    final period = raw['period'];
    return SettlementPreview(
      cut: Map<String, dynamic>.from(raw['cut'] as Map),
      cashIn: EmployeeLimits._n(raw['cash_in']) ?? 0,
      debtOut: EmployeeLimits._n(raw['debt_out']) ?? 0,
      opsCount: int.tryParse('${raw['ops_count'] ?? 0}') ?? 0,
      profit: EmployeeLimits._n(raw['profit']) ?? 0,
      holdsCount: holds is Map ? int.tryParse('${holds['count'] ?? 0}') ?? 0 : 0,
      holdsCash: holds is Map ? EmployeeLimits._n(holds['cash']) ?? 0 : 0,
      holdsDebt: holds is Map ? EmployeeLimits._n(holds['debt']) ?? 0 : 0,
      // null/غائب أو open_debt_unavailable ⇒ null (لا ?? 0 — قراءةٌ تعذّرت لا تُعرض صفراً)
      openDebt: raw['open_debt_unavailable'] == true ? null : EmployeeLimits._n(raw['open_debt']),
      openDebtApprox: raw['open_debt_approx'] == true,
      openDebtUnavailable: raw['open_debt_unavailable'] == true,
      periodStart: period is Map ? EmployeeLimitStatus._d(period['start_at']) : null,
      breakdown: bd,
      handTaken: EmployeeLimits._n(raw['hand_taken']),
      toHandOver: EmployeeLimits._n(raw['to_hand_over']),
    );
  }
}

/// نتيجة نداء: data أو رسالة الخادم كما هي (عربيّة) + رمزها.
class LimitsResult<T> {
  const LimitsResult({this.data, this.message, this.code, this.status});
  final T? data;
  final String? message;
  final String? code;
  final int? status;
  bool get ok => data != null && message == null;
}

class EmployeeLimitsApi {
  EmployeeLimitsApi._();

  static const _base = '/api/v2/employee-limits';

  static LimitsResult<T> _fail<T>(Object e, String fallback) {
    if (e is DioException) {
      final body = e.response?.data;
      if (body is Map) {
        return LimitsResult<T>(
          message: body['message']?.toString() ?? fallback,
          code: body['code']?.toString(),
          status: e.response?.statusCode,
        );
      }
      return LimitsResult<T>(message: fallback, status: e.response?.statusCode);
    }
    if (!kReleaseMode) debugPrint('🔴 employee-limits: $e');
    return LimitsResult<T>(message: fallback);
  }

  /// المدير: هل الميزة مفتوحة لحسابه (لإظهار الحقول)؟ الموظّف: حاله هو.
  static Future<({bool isEmployee, bool featureEnabled, EmployeeLimitStatus? status})?> me() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('$_base/me');
      final body = r.data ?? const {};
      final data = body['data'];
      if (body['success'] != true || data is! Map) return null;
      final isEmp = data['is_employee'] == true;
      return (
        isEmployee: isEmp,
        featureEnabled: data['feature_enabled'] == true,
        status: isEmp ? EmployeeLimitStatus.fromJson(data) : null,
      );
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 employee-limits me: $e');
      return null;
    }
  }

  /// المدير: موظّفٌ واحد — حدوده وحاله وحجوزاته وآخر تسوياته.
  static Future<LimitsResult<EmployeeLimitStatus>> get(int id) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('$_base/$id');
      final body = r.data ?? const {};
      final s = EmployeeLimitStatus.fromJson(body['data']);
      if (body['success'] != true || s == null) {
        return LimitsResult(message: body['message']?.toString() ?? 'تعذّر التحميل', code: body['code']?.toString());
      }
      return LimitsResult(data: s);
    } catch (e) {
      return _fail(e, 'تعذّر التحميل');
    }
  }

  /// المدير: ضبط القيم الثلاث (null = بلا حدّ / بلا ربح). data = true حين حُفظت — ولو تعذّر عرض الحال بعدها
  /// (`status_unavailable`: الخادم حفظها ثمّ لم يقرأ الحال ⇒ نجاحٌ لا «تعذّر الحفظ»، مراجعة المال ٦).
  static Future<LimitsResult<bool>> put(int id, EmployeeLimits l) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>('$_base/$id', data: {
        'debt_cap': l.debtCap,
        'cash_cap': l.cashCap,
        'profit_per_op': l.profitPerOp,
      });
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return LimitsResult(message: body['message']?.toString() ?? 'تعذّر حفظ الحدود', code: body['code']?.toString());
      }
      if (body['status_unavailable'] == true || EmployeeLimitStatus.fromJson(body['data']) != null) {
        return const LimitsResult(data: true);
      }
      return LimitsResult(message: body['message']?.toString() ?? 'تعذّر حفظ الحدود', code: body['code']?.toString());
    } catch (e) {
      return _fail(e, 'تعذّر حفظ الحدود');
    }
  }

  static Future<LimitsResult<SettlementPreview>> preview(int id) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('$_base/$id/settlement/preview');
      final body = r.data ?? const {};
      final p = SettlementPreview.fromJson(body['data']);
      if (body['success'] != true || p == null) {
        return LimitsResult(message: body['message']?.toString() ?? 'تعذّرت المعاينة', code: body['code']?.toString());
      }
      return LimitsResult(data: p);
    } catch (e) {
      return _fail(e, 'تعذّرت المعاينة');
    }
  }

  /// التأكيد بالحدّ والأرقام التي رآها المدير — تغيّرت ⇒ 409 STALE (تُعاد المعاينة).
  static Future<LimitsResult<EmployeeSettlement>> settle(int id, SettlementPreview p, {String? note, required String idempotencyKey}) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/$id/settlement', data: {
        'cut': p.cut,
        'expected': {
          'cash_in': p.cashIn,
          'debt_out': p.debtOut,
          'ops_count': p.opsCount,
          'profit': p.profit,
          // ما أخذه من النقد الذي بيده يُرسَل حين عرضه الخادم — فيرفض التسوية إن تغيّر منذ المعاينة
          if (p.handTaken != null) 'hand_taken': p.handTaken,
        },
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        'idempotency_key': idempotencyKey,
      });
      final body = r.data ?? const {};
      final s = EmployeeSettlement.fromJson(body['data']);
      if (body['success'] != true || s == null) {
        return LimitsResult(message: body['message']?.toString() ?? 'تعذّرت التسوية', code: body['code']?.toString());
      }
      return LimitsResult(data: s);
    } catch (e) {
      return _fail(e, 'تعذّرت التسوية');
    }
  }

  static Future<LimitsResult<List<EmployeeSettlement>>> history(int id, {int limit = 30}) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('$_base/$id/settlements', queryParameters: {'limit': limit});
      final body = r.data ?? const {};
      final list = body['data'];
      if (body['success'] != true || list is! List) {
        return LimitsResult(message: body['message']?.toString() ?? 'تعذّر التحميل');
      }
      return LimitsResult(data: list.map(EmployeeSettlement.fromJson).whereType<EmployeeSettlement>().toList());
    } catch (e) {
      return _fail(e, 'تعذّر التحميل');
    }
  }

  static Future<LimitsResult<EmployeeSettlement>> voidSettlement(int id, int settlementId, String reason) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/$id/settlements/$settlementId/void', data: {'reason': reason});
      final body = r.data ?? const {};
      final s = EmployeeSettlement.fromJson(body['data']);
      if (body['success'] != true || s == null) {
        return LimitsResult(message: body['message']?.toString() ?? 'تعذّر الإلغاء', code: body['code']?.toString());
      }
      return LimitsResult(data: s);
    } catch (e) {
      return _fail(e, 'تعذّر الإلغاء');
    }
  }

  static Future<LimitsResult<bool>> releaseHold(int id, int holdId, {String? reason}) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/$id/holds/$holdId/release',
          data: {if (reason != null && reason.isNotEmpty) 'reason': reason});
      final body = r.data ?? const {};
      if (body['success'] != true) return LimitsResult(message: body['message']?.toString() ?? 'تعذّر التحرير');
      return const LimitsResult(data: true);
    } catch (e) {
      return _fail(e, 'تعذّر التحرير');
    }
  }
}
