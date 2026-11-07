import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../api/manager_debts_api.dart';
import '../api/manager_movements_api.dart';
import '../api/managers_api.dart';

/// حركات أوّل هذا العدد من مدراء كلّ شركة — كالشاشة وحدها (`mgrs.take(60)`).
const int kManagerMovementsCap = 60;

/// ديون مدراء شركةٍ واحدة كما تُقرأ وحدها — للتقرير في «كل الشركات».
class CompanyManagerDebts {
  const CompanyManagerDebts({
    this.noSubAdmins = false,
    this.managers = const [],
    this.managersTotal = 0,
    this.summary,
    this.debts = const [],
    this.movements = const [],
    this.movementsFailed = 0,
  });

  /// الشركة بلا مدراء فرعيّين — لا ديون مدراء فيها أصلاً (لا «تعذّرت» ولا صفر).
  final bool noSubAdmins;

  /// قائمة المدراء الكاملة (`/api/v2/managers/full`): دين الساس لكلّ مدير، و[Manager.debtUnavailable] لمن لم يُقرأ دينه.
  final List<Manager> managers;

  /// عددهم عند الساس — أكبر من [managers] حين تجاوزوا الصفحة (٥٠٠).
  final int managersTotal;

  /// ملخّص الديون الأخرى (دفترنا) بالفترة.
  final ManagerDebtsSummary? summary;

  /// الديون الأخرى نفسها — تميّز «تسديد كامل» من «جزئي».
  final List<ManagerDebt> debts;

  /// حركات أوّل [kManagerMovementsCap] مديراً، كلٌّ بمديره (ما قُرئ وحده).
  final List<({Manager manager, List<ManagerMovement> rows})> movements;

  /// مدراء لم تُقرأ حركاتهم.
  final int movementsFailed;

  /// مدراء لم يُقرأ دين الساس عليهم (الخادم: debt_unavailable) — يُسمَّون ولا يُجمعون.
  int get unreadDebts => managers.where((m) => m.debtUnavailable).length;
}

typedef CompanyManagerDebtsResult = ({CompanyManagerDebts? data, String? error});

/// «كل الشركات» — ديون مدراء الشركة التي يوجّه لها [CompanyRoute.run] (٨ نوفمبر — المالك: «نعم لازم نسوي كلشي»): الطلبات
/// نفسها التي تطلبها الشاشة وحدها، بنتيجةٍ تفصل «تعذّر» عن «فارغ». أيّ قراءةٍ أساسيّة تتعذّر (المدراء، الملخّص، الديون) ⇒ الشركة
/// كلّها «تعذّرت» باسمها — لا أرقامٌ ناقصة تُجمع كأنّها كاملة. وحركات كلّ مديرٍ وحدها: ما تعذّر منها يُعدّ ويُسمّى. شركةٌ بلا
/// مدراء فرعيّين لا تُطلب منها البقيّة.
Future<CompanyManagerDebtsResult> loadCompanyManagerDebts({
  String? from,
  String? to,
  int movementsLimit = 100,
  int concurrency = 6,
}) async {
  final access = await _get('/api/admin/manager-debts/access');
  if (access.body == null) return (data: null, error: access.error);
  if (access.body!['hasSubAdmins'] != true) {
    return (data: const CompanyManagerDebts(noSubAdmins: true), error: null);
  }
  final core = await Future.wait([
    _get('/api/v2/managers/full', {'page': 1, 'count': 500, 'sortBy': 'username', 'direction': 'asc'}),
    _get('/api/admin/manager-debts/summary', {
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
    }),
    _get('/api/admin/manager-debts'),
  ]);
  for (final r in core) {
    if (r.body == null) return (data: null, error: r.error);
  }
  final rawManagers = core[0].body!['data'];
  final rawDebts = core[2].body!['debts'] ?? core[2].body!['data'];
  if (rawManagers is! List || rawDebts is! List) return (data: null, error: null);
  final managers = [
    for (final m in rawManagers.whereType<Map>())
      if (Manager.fromJson(Map<String, dynamic>.from(m)) case final x?) x,
  ];
  final total = int.tryParse('${core[0].body!['total']}') ?? managers.length;
  final debts = [
    for (final d in rawDebts.whereType<Map>())
      if (ManagerDebt.fromJson(Map<String, dynamic>.from(d)) case final x?) x,
  ];
  final summary = ManagerDebtsSummary.fromJson(core[1].body!);

  // حركات أوّل ٦٠ مديراً — بضعةٌ معاً لا الستّون دفعةً (والشركات تُقرأ اثنتين اثنتين)
  final targets = managers.take(kManagerMovementsCap).toList();
  final read = List<List<ManagerMovement>?>.filled(targets.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < targets.length) {
      final i = next++;
      final r = await _get('/api/admin/managers/${targets[i].id}/movements', {'limit': movementsLimit});
      final list = r.body?['movements'] ?? r.body?['data'];
      if (r.body == null || list is! List) continue;
      read[i] = [
        for (final m in list.whereType<Map>())
          if (ManagerMovement.fromJson(Map<String, dynamic>.from(m)) case final x?) x,
      ];
    }
  }

  await Future.wait([for (var w = 0; w < concurrency && w < targets.length; w++) worker()]);
  return (
    data: CompanyManagerDebts(
      managers: List.unmodifiable(managers),
      managersTotal: total < managers.length ? managers.length : total,
      summary: summary,
      debts: List.unmodifiable(debts),
      movements: [
        for (var i = 0; i < targets.length; i++)
          if (read[i] case final rows?) (manager: targets[i], rows: rows),
      ],
      movementsFailed: read.where((r) => r == null).length,
    ),
    error: null,
  );
}

/// GET بنتيجةٍ صريحة: الجسم حين success، وإلّا رسالة الخادم (409 الموجِّه وأخواته بالعربيّة) أو نصٌّ عامّ — لا تفاصيل 5xx.
Future<({Map<String, dynamic>? body, String? error})> _get(String path, [Map<String, dynamic>? query]) async {
  try {
    final r = await ApiClient.dio.get<Map<String, dynamic>>(path, queryParameters: query);
    final body = r.data;
    if (body == null || body['success'] != true) return (body: null, error: body?['message']?.toString());
    return (body: body, error: null);
  } on DioException catch (e) {
    final code = e.response?.statusCode ?? 0;
    final data = e.response?.data;
    final msg = code >= 400 && code < 500 && data is Map ? data['message']?.toString() : null;
    return (body: null, error: msg ?? (code == 401 ? 'انتهت الجلسة' : null));
  } catch (_) {
    return (body: null, error: null);
  }
}
