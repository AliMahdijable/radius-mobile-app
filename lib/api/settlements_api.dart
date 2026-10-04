import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/server_time.dart';
import 'api_client.dart';

/// «تسوية الحساب» — صندوق المدير (2026-10-02).
///
/// الصندوق = المُرحَّل + الواصل نقداً − الصرفيات منذ آخر تسوية. التسوية
/// لا تحذف حركة: تحفظ سنداً مرقّماً ويبدأ الحساب الحاليّ من الصفر.
/// العقود في الخادم `server/accountSettlements.js`، والويب يقرأ الشكل
/// نفسه في `client-v2/src/lib/settlements.ts`.

num _num(Object? v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

int _int(Object? v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0);

int? _intOrNull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

String? _str(Object? v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

class MoneyCount {
  const MoneyCount(this.sum, this.count);
  final num sum;
  final int count;

  static MoneyCount fromJson(Object? raw) {
    final m = _map(raw);
    return MoneyCount(_num(m['sum']), _int(m['count']));
  }
}

/// حصّة منفّذٍ واحد: المدير نفسه (`employeeId == null`) أو موظّف.
class SettleCollector {
  const SettleCollector({
    required this.employeeId,
    required this.username,
    required this.name,
    required this.cashActivations,
    required this.debtPayments,
    required this.expenses,
    required this.net,
  });

  final int? employeeId;
  final String? username;
  final String? name;
  final MoneyCount cashActivations;
  final MoneyCount debtPayments;
  final MoneyCount expenses;
  final num net;

  bool get isManager => employeeId == null;
  int get inCount => cashActivations.count + debtPayments.count;

  static SettleCollector fromJson(Map<String, dynamic> j) => SettleCollector(
        employeeId: _intOrNull(j['employee_id']),
        username: _str(j['username']),
        name: _str(j['name']),
        cashActivations: MoneyCount.fromJson(j['cash_activations']),
        debtPayments: MoneyCount.fromJson(j['debt_payments']),
        expenses: MoneyCount.fromJson(j['expenses']),
        net: _num(j['net_amount']),
      );
}

List<SettleCollector> _collectors(Object? v) => v is List
    ? v
        .whereType<Map>()
        .map((m) => SettleCollector.fromJson(Map<String, dynamic>.from(m)))
        .toList()
    : const <SettleCollector>[];

/// سجلٌّ في سجلّ التسويات: بداية الحساب (`opening`) أو تسوية برقم سند.
class SettlementRecord {
  const SettlementRecord({
    required this.id,
    required this.kind,
    required this.number,
    required this.status,
    required this.periodStartAt,
    required this.cutAt,
    required this.openingBalance,
    required this.cashActivations,
    required this.debtPayments,
    required this.cashIn,
    required this.expenses,
    required this.newDebts,
    required this.expected,
    required this.received,
    required this.carried,
    required this.note,
    required this.actingEmployeeUsername,
    required this.voidedAt,
    required this.voidedBy,
    required this.voidReason,
    required this.collectors,
  });

  final int id;
  final String kind;
  final int? number;
  final String status;
  final DateTime? periodStartAt;
  final DateTime? cutAt;
  final num openingBalance;
  final MoneyCount cashActivations;
  final MoneyCount debtPayments;
  final num cashIn;
  final MoneyCount expenses;
  final MoneyCount newDebts;
  final num expected;
  final num received;
  final num carried;
  final String? note;
  final String? actingEmployeeUsername;
  final DateTime? voidedAt;
  final String? voidedBy;
  final String? voidReason;
  final List<SettleCollector> collectors;

  bool get isOpening => kind == 'opening';
  bool get isVoided => status == 'voided';
  int get moveCount => cashActivations.count + debtPayments.count + expenses.count;

  static SettlementRecord? fromJson(Object? raw) {
    final j = _map(raw);
    final id = _intOrNull(j['id']);
    if (id == null) return null;
    return SettlementRecord(
      id: id,
      kind: j['kind']?.toString() ?? 'settlement',
      number: _intOrNull(j['number']),
      status: j['status']?.toString() ?? 'active',
      periodStartAt: parseServerUtc(_str(j['period_start_at'])),
      cutAt: parseServerUtc(_str(j['cut_at'])),
      openingBalance: _num(j['opening_balance']),
      cashActivations: MoneyCount.fromJson(j['cash_activations']),
      debtPayments: MoneyCount.fromJson(j['debt_payments']),
      cashIn: _num(j['cash_in']),
      expenses: MoneyCount.fromJson(j['expenses']),
      newDebts: MoneyCount.fromJson(j['new_debts']),
      expected: _num(j['expected_amount']),
      received: _num(j['received_amount']),
      carried: _num(j['carried_amount']),
      note: _str(j['note']),
      actingEmployeeUsername: _str(j['acting_employee_username']),
      voidedAt: parseServerUtc(_str(j['voided_at'])),
      voidedBy: _str(j['voided_by']),
      voidReason: _str(j['void_reason']),
      collectors: _collectors(j['collectors']),
    );
  }
}

/// حدّ التسوية كما رآه المدير في المعاينة — يُعاد كما هو عند التأكيد،
/// فما رآه هو ما يُسوّى بالضبط.
class SettlementCut {
  const SettlementCut(this.headId, this.activityId, this.expenseId);
  final int headId;
  final int activityId;
  final int expenseId;

  Map<String, dynamic> toJson() => {
        'head_id': headId,
        'activity_id': activityId,
        'expense_id': expenseId,
      };

  static SettlementCut? fromJson(Object? raw) {
    final j = _map(raw);
    final h = _intOrNull(j['head_id']);
    final a = _intOrNull(j['activity_id']);
    final e = _intOrNull(j['expense_id']);
    if (h == null || a == null || e == null) return null;
    return SettlementCut(h, a, e);
  }
}

/// الحساب الحاليّ = معاينة التسوية. `started == false` حتى تُحدَّد البداية.
class CurrentAccount {
  const CurrentAccount({
    required this.started,
    required this.head,
    required this.periodStart,
    required this.cut,
    required this.openingBalance,
    required this.cashActivations,
    required this.debtPayments,
    required this.cashIn,
    required this.expenses,
    required this.newDebts,
    required this.expected,
    required this.collectors,
    required this.canSettle,
    required this.canVoid,
    required this.today,
    required this.monthStart,
  });

  final bool started;
  final SettlementRecord? head;
  final DateTime? periodStart;
  final SettlementCut? cut;
  final num openingBalance;
  final MoneyCount cashActivations;
  final MoneyCount debtPayments;
  final num cashIn;
  final MoneyCount expenses;
  final MoneyCount newDebts;
  final num expected;
  final List<SettleCollector> collectors;
  final bool canSettle;
  final bool canVoid;

  /// `YYYY-MM-DD` بتوقيت بغداد — حين لم يبدأ الحساب بعد.
  final String? today;
  final String? monthStart;

  int get moveCount => cashActivations.count + debtPayments.count + expenses.count;
  bool get hasEmployees => collectors.any((c) => !c.isManager);

  static CurrentAccount? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final t = _map(j['totals']);
    final period = _map(j['period']);
    return CurrentAccount(
      started: j['started'] == true,
      head: SettlementRecord.fromJson(j['head']),
      periodStart: parseServerUtc(_str(period['start_at'])),
      cut: SettlementCut.fromJson(j['cut']),
      openingBalance: _num(t['opening_balance']),
      cashActivations: MoneyCount.fromJson(t['cash_activations']),
      debtPayments: MoneyCount.fromJson(t['debt_payments']),
      cashIn: _num(t['cash_in']),
      expenses: MoneyCount.fromJson(t['expenses']),
      newDebts: MoneyCount.fromJson(t['new_debts']),
      expected: _num(t['expected_amount']),
      collectors: _collectors(j['collectors']),
      canSettle: j['can_settle'] == true,
      canVoid: j['can_void'] == true,
      today: _str(j['today']),
      monthStart: _str(j['month_start']),
    );
  }
}

/// معاينة البداية — `GET /api/v2/settlements/preview-start`.
///
/// قراءةٌ فقط: ترى ما سيكون في الصندوق لو بدأ الحساب من هذا التاريخ،
/// بلا إنشاء بداية.
///
/// ⚠️ [expected] هنا **بلا** الرصيد الافتتاحيّ، لأنّ الرصيد لم يُحفَظ
/// بعدُ — يكتبه المستخدم في الحقل. فالمعروض له `expected + opening`،
/// ويتحرّك مع الحقل بلا طلبٍ جديد. (`docs/settlements-prompt.md` §٣)
class StartPreview {
  const StartPreview({
    required this.start,
    required this.startAt,
    required this.cashActivations,
    required this.debtPayments,
    required this.cashIn,
    required this.expenses,
    required this.newDebts,
    required this.expected,
    required this.collectors,
  });

  /// ما أرسلناه كما ردّه الخادم: `now` أو `YYYY-MM-DD`. تُقرأ منه
  /// التسمية المعروضة، لا من حالة الشاشة — فالردّ المتأخّر لا يُسمّى
  /// باسم اختيارٍ أحدث.
  final String start;
  final DateTime? startAt;
  final MoneyCount cashActivations;
  final MoneyCount debtPayments;
  final num cashIn;
  final MoneyCount expenses;
  final MoneyCount newDebts;

  /// بلا الرصيد الافتتاحيّ — انظر تعليق الصنف.
  final num expected;
  final List<SettleCollector> collectors;

  int get moveCount =>
      cashActivations.count + debtPayments.count + expenses.count;

  static StartPreview? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final t = _map(j['totals']);
    return StartPreview(
      start: j['start']?.toString() ?? '',
      startAt: parseServerUtc(_str(j['start_at'])),
      cashActivations: MoneyCount.fromJson(t['cash_activations']),
      debtPayments: MoneyCount.fromJson(t['debt_payments']),
      cashIn: _num(t['cash_in']),
      expenses: MoneyCount.fromJson(t['expenses']),
      newDebts: MoneyCount.fromJson(t['new_debts']),
      expected: _num(t['expected_amount']),
      collectors: _collectors(j['collectors']),
    );
  }
}

/// حركةٌ في الصندوق: نقدٌ داخل (تفعيل نقديّ · تسديد دين) أو صرفية.
class BoxMovement {
  const BoxMovement({
    required this.source,
    required this.id,
    required this.kind,
    required this.isIn,
    required this.amount,
    required this.createdAt,
    required this.subscriber,
    required this.packageName,
    required this.description,
    required this.expenseDate,
    required this.backdated,
    required this.employeeId,
    required this.employeeUsername,
    required this.employeeName,
  });

  final String source;
  final int id;

  /// `cash_activation` · `debt_payment` · `expense`
  final String kind;
  final bool isIn;
  final num amount;
  final DateTime? createdAt;
  final String? subscriber;
  final String? packageName;
  final String? description;

  /// التاريخ المكتوب على الصرفية (`YYYY-MM-DD …`).
  final String? expenseDate;

  /// صرفيةٌ سُجّلت بعد بداية الفترة بتاريخٍ سابق لها.
  final bool backdated;
  final int? employeeId;
  final String? employeeUsername;
  final String? employeeName;

  static BoxMovement? fromJson(Map<String, dynamic> j) {
    final id = _intOrNull(j['id']);
    if (id == null) return null;
    return BoxMovement(
      source: j['source']?.toString() ?? 'activity',
      id: id,
      kind: j['kind']?.toString() ?? 'debt_payment',
      isIn: j['direction']?.toString() != 'out',
      amount: _num(j['amount']),
      createdAt: parseServerUtc(_str(j['created_at'])),
      subscriber: _str(j['subscriber']),
      packageName: _str(j['package_name']),
      description: _str(j['description']),
      expenseDate: _str(j['expense_date']),
      backdated: j['backdated'] == true,
      employeeId: _intOrNull(j['employee_id']),
      employeeUsername: _str(j['employee_username']),
      employeeName: _str(j['employee_name']),
    );
  }
}

class SettlementsApi {
  SettlementsApi._();

  /// مفتاح منع التكرار: ثابتٌ للنيّة الواحدة (ضغطتان أو شبكةٌ انقطعت بعد
  /// الحفظ = تسوية واحدة)، ويتجدّد مع كلّ معاينة جديدة.
  static String newIdempotencyKey() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// GET /api/v2/settlements/current
  static Future<({CurrentAccount? data, String? message, String? code})>
      current() async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/v2/settlements/current');
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          data: null,
          message: body['message']?.toString(),
          code: body['code']?.toString(),
        );
      }
      return (data: CurrentAccount.fromJson(body['data']), message: null, code: null);
    } on DioException catch (e) {
      _log('settlements/current', e);
      return (data: null, message: _message(e, 'تعذّر حساب الصندوق'), code: _code(e));
    } catch (e) {
      _log('settlements/current', e);
      return (data: null, message: 'تعذّر حساب الصندوق', code: null);
    }
  }

  /// GET /api/v2/settlements/preview-start?start=now|YYYY-MM-DD
  ///
  /// `settlements.view` تكفي، ولا تكتب شيئاً. أخطاؤها المتوقّعة
  /// `BAD_START` (تاريخٌ قادم أو قبل 2025-01-01) و`ALREADY_STARTED`،
  /// ورسالتها عربيّةٌ جاهزة للعرض.
  static Future<({StartPreview? data, String? message, String? code})>
      previewStart(String start) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/settlements/preview-start',
        queryParameters: {'start': start},
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          data: null,
          message: body['message']?.toString(),
          code: body['code']?.toString(),
        );
      }
      return (
        data: StartPreview.fromJson(body['data']),
        message: null,
        code: null,
      );
    } on DioException catch (e) {
      _log('settlements/preview-start', e);
      return (
        data: null,
        message: _message(e, 'تعذّر حساب المعاينة'),
        code: _code(e),
      );
    } catch (e) {
      _log('settlements/preview-start', e);
      return (data: null, message: 'تعذّر حساب المعاينة', code: null);
    }
  }

  /// GET /api/v2/settlements/movements?settlement=current|<id>
  static Future<({List<BoxMovement> items, bool hasMore, String? message})>
      movements({String settlement = 'current', int limit = 100}) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/settlements/movements',
        queryParameters: {'settlement': settlement, 'limit': limit},
      );
      final data = _map((r.data ?? const {})['data']);
      final list = data['items'];
      final items = list is List
          ? list
              .whereType<Map>()
              .map((m) => BoxMovement.fromJson(Map<String, dynamic>.from(m)))
              .whereType<BoxMovement>()
              .toList()
          : const <BoxMovement>[];
      return (items: items, hasMore: data['has_more'] == true, message: null);
    } on DioException catch (e) {
      _log('settlements/movements', e);
      return (
        items: const <BoxMovement>[],
        hasMore: false,
        message: _message(e, 'تعذّر جلب الحركات'),
      );
    } catch (e) {
      _log('settlements/movements', e);
      return (items: const <BoxMovement>[], hasMore: false, message: 'تعذّر جلب الحركات');
    }
  }

  /// GET /api/v2/settlements — الأحدث أوّلاً (يشمل البداية والملغاة).
  static Future<({List<SettlementRecord> items, int total})> list({
    int limit = 30,
  }) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/settlements',
        queryParameters: {'limit': limit},
      );
      final data = _map((r.data ?? const {})['data']);
      final list = data['items'];
      final items = list is List
          ? list
              .map((m) => SettlementRecord.fromJson(m))
              .whereType<SettlementRecord>()
              .toList()
          : const <SettlementRecord>[];
      return (items: items, total: _int(data['total']));
    } on DioException catch (e) {
      _log('settlements (GET)', e);
      return (items: const <SettlementRecord>[], total: 0);
    } catch (e) {
      _log('settlements (GET)', e);
      return (items: const <SettlementRecord>[], total: 0);
    }
  }

  /// GET /api/v2/settlements/:id — مع حصص المنفّذين.
  static Future<({SettlementRecord? data, String? message})> get(int id) async {
    try {
      final r =
          await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/settlements/$id');
      return (data: SettlementRecord.fromJson((r.data ?? const {})['data']), message: null);
    } on DioException catch (e) {
      _log('settlements/:id', e);
      return (data: null, message: _message(e, 'تعذّر جلب التسوية'));
    } catch (e) {
      _log('settlements/:id', e);
      return (data: null, message: 'تعذّر جلب التسوية');
    }
  }

  /// POST /api/v2/settlements/open — بداية الحساب.
  /// [start]: `now` أو `YYYY-MM-DD` بتوقيت بغداد.
  static Future<({bool ok, String? message})> open({
    required String start,
    num openingBalance = 0,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/settlements/open',
        data: {'start': start, 'opening_balance': openingBalance},
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } on DioException catch (e) {
      _log('settlements/open', e);
      return (ok: false, message: _message(e, 'تعذّر بدء الحساب'));
    } catch (e) {
      _log('settlements/open', e);
      return (ok: false, message: 'تعذّر بدء الحساب');
    }
  }

  /// POST /api/v2/settlements — التسوية.
  ///
  /// رفض `STALE` أو `HEAD_CHANGED` (409) يحمل معاينةً أحدث في [current]:
  /// تغيّرت صرفيةٌ أو سُجّلت تسويةٌ أخرى منذ فتح المعاينة.
  static Future<
      ({
        bool ok,
        SettlementRecord? settlement,
        String? message,
        String? code,
        CurrentAccount? current,
      })> settle({
    required SettlementCut cut,
    required num expected,
    required num received,
    String? note,
    required String idempotencyKey,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/settlements',
        data: {
          'cut': cut.toJson(),
          'expected_amount': expected,
          'received_amount': received,
          if (note != null && note.isNotEmpty) 'note': note,
          'idempotency_key': idempotencyKey,
        },
      );
      final body = r.data ?? const {};
      // ⚠️ **الرفض يصل هنا لا في `on DioException`.**
      //
      // 🐛 `validateStatus: s < 500` في `api_client.dart:66` يجعل الـ409
      // **نجاحاً** في نظر Dio، فالفرع أدناه لا يُدخَل إلّا على 5xx أو
      // عطل نقل. وكان هذا المسار يكتب `code: null` حرفيّاً — فمعالجة
      // `STALE` و`HEAD_CHANGED` في `settle_sheet.dart` شيفرةٌ ميّتة،
      // والشيت يبقى على أرقامٍ وحدٍّ بائتين فتُرفض كلّ ضغطةٍ تالية
      // بالرفض نفسه. (والعقد §٣ يقول: «الجسم فيه `current` جديد:
      // حدّث الشيت به واطلب تأكيداً جديداً».)
      //
      // و`current()` و`previewStart()` في هذا الملفّ تقرآن الرمز من
      // الجسم على المسار الحيّ — `settle()` وحدها شذّت.
      if (body['success'] != true) {
        return (
          ok: false,
          settlement: null,
          message: body['message']?.toString() ?? 'تعذّرت التسوية',
          code: body['code']?.toString(),
          current: CurrentAccount.fromJson(body['current']),
        );
      }
      final s = SettlementRecord.fromJson(body['data']);
      return (
        ok: s != null,
        settlement: s,
        message: body['message']?.toString(),
        code: body['code']?.toString(),
        current: null,
      );
    } on DioException catch (e) {
      // احتياطٌ لـ5xx وأعطال النقل وحدها — انظر أعلاه.
      _log('settlements (POST)', e);
      final b = _map(e.response?.data);
      return (
        ok: false,
        settlement: null,
        message: b['message']?.toString() ?? 'تعذّرت التسوية',
        code: b['code']?.toString(),
        current: CurrentAccount.fromJson(b['current']),
      );
    } catch (e) {
      _log('settlements (POST)', e);
      return (
        ok: false,
        settlement: null,
        message: 'تعذّرت التسوية',
        code: null,
        current: null,
      );
    }
  }

  /// POST /api/v2/settlements/:id/void — لآخر سجلٍّ فعّال، وللمدير وحده.
  static Future<({bool ok, String? message})> voidSettlement(
    int id,
    String reason,
  ) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/settlements/$id/void',
        data: {'reason': reason},
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } on DioException catch (e) {
      _log('settlements/void', e);
      return (ok: false, message: _message(e, 'تعذّر الإلغاء'));
    } catch (e) {
      _log('settlements/void', e);
      return (ok: false, message: 'تعذّر الإلغاء');
    }
  }

  static String _message(DioException e, String fallback) {
    final b = e.response?.data;
    final m = b is Map ? b['message']?.toString() : null;
    return (m == null || m.isEmpty) ? fallback : m;
  }

  static String? _code(DioException e) {
    final b = e.response?.data;
    return b is Map ? b['code']?.toString() : null;
  }

  static void _log(String endpoint, Object err) {
    if (kReleaseMode) return;
    if (err is DioException) {
      debugPrint(
        '🔴 $endpoint: status=${err.response?.statusCode} body=${err.response?.data}',
      );
    } else {
      debugPrint('🔴 $endpoint: $err');
    }
  }
}
