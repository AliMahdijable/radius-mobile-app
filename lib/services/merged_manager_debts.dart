import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../api/manager_debts_api.dart';
import '../api/manager_movements_api.dart';
import '../api/managers_api.dart';

/// حركات أوّل هذا العدد من مدراء كلّ شركة (٢٢ نوفمبر: 60 ⇒ 300 — المالك: «الPDF مرات مقصوص مو كامل»؛ كان كلّ ما بعد الستّين
/// يغيب عن التقرير وتصديره). ما زاد يُسمّى ([CompanyManagerDebts.managersTotal]).
const int kManagerMovementsCap = 300;

/// ايرث لنك على خادمٍ لا يعرف ديون حساباتها التابعة بعد (لا علامة `sas_debt`).
const String kElManagerDebtsNotYet = 'ديون مدراء ايرث لنك لم تُفتح بعد';

/// الخادم لم يقرأ الحسابات التابعة الآن (access `unavailable: true`).
const String kSubAdminsUnavailable = 'تعذّر جلب الحسابات التابعة الآن';

/// حركات كلّ مدير: أقصى ما يعطيه الخادم (500 — `/api/admin/managers/:id/movements`)؛ مديرٌ بلغه قد تنقص أقدم حركاته فيُسمّى.
const int kManagerMovementsLimit = 500;

/// ديون مدراء شركةٍ واحدة كما تُقرأ وحدها — للتقرير في «كل الشركات».
class CompanyManagerDebts {
  const CompanyManagerDebts({
    this.noSubAdmins = false,
    this.sasDebt = true,
    this.managers = const [],
    this.managersTotal = 0,
    this.summary,
    this.debts = const [],
    this.movements = const [],
    this.movementsFailed = 0,
    this.movementsCapped = 0,
  });

  /// الشركة بلا مدراء فرعيّين — لا ديون مدراء فيها أصلاً (لا «تعذّرت» ولا صفر).
  final bool noSubAdmins;

  /// لمدرائها دينٌ عند الساس — ايرث لنك لا تعطي أرصدة حساباتها التابعة (الخادم: `sas_debt: false` بجسم `/api/v2/managers/full`،
  /// ٢٣ نوفمبر — المالك: «ليش الايرثلنك… ما تصير بنفس الصيغة بيها ديون مدراء؟») ⇒ «متبقّي SAS» لها «—» لا صفر، وآجلها دينٌ في «ديون أخرى».
  final bool sasDebt;

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

  /// مدراء بلغت حركاتهم سقف الخادم ([kManagerMovementsLimit]) — أقدمها قد لا يكون في التقرير.
  final int movementsCapped;

  /// مدراء لم يُقرأ دين الساس عليهم (الخادم: debt_unavailable) — يُسمَّون ولا يُجمعون.
  int get unreadDebts => managers.where((m) => m.debtUnavailable).length;
}

typedef CompanyManagerDebtsResult = ({CompanyManagerDebts? data, String? error});

/// «كل الشركات» — ديون مدراء الشركة التي يوجّه لها [CompanyRoute.run] (٨ نوفمبر — المالك: «نعم لازم نسوي كلشي»): الطلبات
/// نفسها التي تطلبها الشاشة وحدها، بنتيجةٍ تفصل «تعذّر» عن «فارغ». أيّ قراءةٍ أساسيّة تتعذّر (المدراء، الملخّص، الديون) ⇒ الشركة
/// كلّها «تعذّرت» باسمها — لا أرقامٌ ناقصة تُجمع كأنّها كاملة. وحركات كلّ مديرٍ وحدها: ما تعذّر منها يُعدّ ويُسمّى. شركةٌ بلا
/// مدراء فرعيّين لا تُطلب منها البقيّة.
///
/// [earthlink]: شركة ايرث لنك — مدراؤها حساباتها التابعة ولا دين ساسٍ عليهم؛ خادمٌ لم يُحدَّث بعد يردّ قائمةً فارغة بلا علامة
/// `sas_debt` ⇒ «لم تُفتح بعد» صراحةً، لا تقريرٌ بلا حركاتٍ كأنّه كامل.
Future<CompanyManagerDebtsResult> loadCompanyManagerDebts({
  String? from,
  String? to,
  int movementsLimit = kManagerMovementsLimit,
  int concurrency = 6,
  bool earthlink = false,
}) async {
  final access = await _get('/api/admin/manager-debts/access');
  if (access.body == null) return (data: null, error: access.error);
  // ايرث لنك والمفتاح مطفأٌ لصفحتها (`enabled: false`) ⇒ «لم تُفتح بعد» لا «بلا مدراء فرعيّين» ولها حساباتٌ تابعة
  if (earthlink && access.body!['enabled'] == false) return (data: null, error: kElManagerDebtsNotYet);
  // تعذّرت قراءة الحسابات التابعة (`unavailable: true` — عقد d9 ٢٣ نوفمبر) ⇒ «تعذّرت» باسمها، لا «بلا مدراء فرعيّين»
  if (access.body!['unavailable'] == true) {
    return (data: null, error: access.body!['message']?.toString() ?? kSubAdminsUnavailable);
  }
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
  final sasDebt = core[0].body!['sas_debt'] != false;
  if (earthlink && sasDebt) return (data: null, error: kElManagerDebtsNotYet);
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

  // حركات أوّل [kManagerMovementsCap] مديراً — بضعةٌ معاً لا كلّهم دفعةً (والشركات تُقرأ اثنتين اثنتين)
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
      sasDebt: sasDebt,
      managers: List.unmodifiable(managers),
      managersTotal: total < managers.length ? managers.length : total,
      summary: summary,
      debts: List.unmodifiable(debts),
      movements: [
        for (var i = 0; i < targets.length; i++)
          if (read[i] case final rows?) (manager: targets[i], rows: rows),
      ],
      movementsFailed: read.where((r) => r == null).length,
      movementsCapped: read.where((r) => r != null && r.length >= movementsLimit).length,
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
