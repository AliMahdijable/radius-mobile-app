import 'package:dio/dio.dart';

import 'api_client.dart';
import 'el_deposit_password.dart';
import 'topup_fee_api.dart';

/// «المدراء» لموزّع ايرث لنك (٢٠ نوفمبر ٢٠٢٦ — المالك: «قسم ايرثلنك نكدر نفتحله قسم المدراء بس خاص بس ديون اخرى وشحن رصيد للمدراء
/// يعني ماكو لا نقاط ولا سحب ولا تغيير معلومات»؛ الخادم server/earthlink/elManagers.js).
///
/// المدراء = الحسابات التابعة له في ايرث لنك (affiliate/deposit/transferTargetAffiliates). ايرث لنك تسمح بالتحويل لهم وحده — لا سحب
/// ولا تعديل ولا إضافة، ولا تعرض أرصدتهم ⇒ لكلّ مديرٍ عمليّتان: «شحن رصيد» (تحويلٌ من رصيد إيداع الوكيل) و«ديون أخرى» (دفترنا).
///
///   GET  /api/v2/el/managers               ⇒ { enabled, data:{ balance, managers:[{ index, name, other_debt, last_topup:{amount, at,
///                                               as_debt}|null, wa_phone|null, wa_source: session|saved|null, has_app }], deposit_saved } }
///   POST /api/v2/el/managers/:index/topup  { amount, as_debt, notify_app, notify_whatsapp, depositPassword?, note?, idempotencyKey,
///                                            confirmRepeat? } ⇒ { success, message, balance_after, debt_recorded, notice:{app, whatsapp…} }
///        رموز الرفض: RECENT_DUPLICATE (المبلغ نفسه للمدير نفسه خلال ٥ دقائق — يُعاد بـconfirmRepeat والمفتاح نفسه) ·
///        OUTCOME_UNKNOWN (لم يتأكّد — يُعاد بالمفتاح نفسه «تحقّق»: الخادم يقرأ كشف الحساب ولا يشحن) · IN_PROGRESS · NOT_APPLIED ·
///        DEPOSIT_PASSWORD_* · KEY_REUSED · NOT_YOURS · NOT_ENABLED · NO_PERMISSION.
///   PUT  /api/v2/el/managers/:index/contact { wa_phone } — رقم واتساب المدير لإشعاره (الفارغ يحذفه).
class ElManagerRow {
  const ElManagerRow({
    required this.index,
    required this.name,
    this.otherDebt = 0,
    this.lastTopupAmount,
    this.lastTopupAt,
    this.lastTopupAsDebt = false,
    this.waPhone,
    this.waSource,
    this.hasApp = false,
  });

  final int index;
  final String name;
  final double otherDebt;
  final double? lastTopupAmount;
  final DateTime? lastTopupAt;
  final bool lastTopupAsDebt;

  /// رقم واتساب المدير للإشعار (رقم جلسته في البرو، وإلّا ما حفظه الوكيل) — null = لا رقم.
  final String? waPhone;

  /// مصدر الرقم: `session` (واتسابه المربوط بالبرو — لا يُعدَّل من هنا) أو `saved` (حفظه الوكيل) أو null.
  final String? waSource;

  /// المدير يستعمل تطبيق البرو بحسابه (له جهازٌ يستلم الإشعار).
  final bool hasApp;

  bool get waEditable => waSource != 'session';

  static ElManagerRow? fromJson(Map<String, dynamic> j) {
    final idx = int.tryParse('${j['index'] ?? ''}');
    final name = '${j['name'] ?? ''}'.trim();
    if (idx == null || name.isEmpty) return null;
    final lt = j['last_topup'] is Map ? Map<String, dynamic>.from(j['last_topup'] as Map) : null;
    final wa = '${j['wa_phone'] ?? ''}'.trim();
    final src = '${j['wa_source'] ?? ''}'.trim();
    return ElManagerRow(
      index: idx,
      name: name,
      otherDebt: double.tryParse('${j['other_debt'] ?? 0}') ?? 0,
      lastTopupAmount: lt == null ? null : double.tryParse('${lt['amount']}'),
      lastTopupAt: lt == null ? null : DateTime.tryParse('${lt['at']}')?.toLocal(),
      lastTopupAsDebt: lt != null && lt['as_debt'] == true,
      waPhone: wa.isEmpty ? null : wa,
      waSource: src.isEmpty ? null : src,
      hasApp: j['has_app'] == true,
    );
  }
}

/// القائمة كما يقولها الخادم. [enabled] false = الميزة لم تُفتح للحساب بعد (المفتاح el_managers).
class ElManagersList {
  const ElManagersList({
    this.enabled = true,
    this.balance,
    this.rows = const [],
    this.depositSaved = false,
    this.message,
  });
  final bool enabled;
  final num? balance;
  final List<ElManagerRow> rows;
  final bool depositSaved;
  final String? message;
}

/// نتيجة الشحن. [uncertain] = لم يُعرف إن تمّ (OUTCOME_UNKNOWN/IN_PROGRESS أو انقطع الردّ) — يُعاد بالمفتاح نفسه، لا بمفتاحٍ جديد.
class ElTopupResult {
  const ElTopupResult({
    required this.ok,
    this.code,
    this.message,
    this.balanceAfter,
    this.deduped = false,
    this.debtRecorded,
    this.noticeApp,
    this.noticeAppMessage,
    this.noticeWhatsapp,
    this.noticeWhatsappMessage,
    this.noResponse = false,
    this.fee,
  });
  final bool ok;
  final String? code;
  final String? message;
  final num? balanceAfter;
  final bool deduped;
  final bool? debtRecorded;
  final bool? noticeApp;
  final String? noticeAppMessage;
  final bool? noticeWhatsapp;
  final String? noticeWhatsappMessage;

  /// لا ردّ من الخادم (انقطاع/مهلة) — قد يكون الشحن تمّ.
  final bool noResponse;

  /// «الفائدة» على الآجل كما سجّلها الخادم (٢٠ نوفمبر). تعذّر دينها تقوله رسالة الخادم نفسها («⚠️ لم تُسجَّل الفائدة…»).
  final TopupFeeOutcome? fee;

  /// سطرٌ تحت رسالة النجاح: «مع فائدة 2% (2,000 د.ع) في «ديون أخرى»» (آجل) أو «مع فائدة 700 د.ع نقداً» (نقديّ).
  String? get feeLine {
    final f = fee;
    if (f == null || !f.recorded) return null;
    return 'مع ${f.label ?? 'فائدة ${f.amount}'} ${f.cash ? 'نقداً' : 'في «ديون أخرى»'}';
  }

  bool get uncertain => !ok && (noResponse || code == 'OUTCOME_UNKNOWN' || code == 'IN_PROGRESS');
  bool get repeatPrompt => !ok && code == 'RECENT_DUPLICATE';

  /// سطر الإشعار تحت رسالة النجاح: «وصله إشعارٌ بتطبيقه · ولم تُرسل رسالة الواتساب: السبب».
  String? get noticeLine {
    final parts = <String>[
      if (noticeApp == true) 'وصله إشعارٌ بتطبيقه',
      if (noticeApp == false) 'لا إشعار بالتطبيق${noticeAppMessage != null ? ': $noticeAppMessage' : ''}',
      if (noticeWhatsapp == true) 'أُرسلت رسالة الواتساب',
      if (noticeWhatsapp == false) 'لم تُرسل رسالة الواتساب${noticeWhatsappMessage != null ? ': $noticeWhatsappMessage' : ''}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static ElTopupResult fromBody(Map body) {
    final n = body['notice'] is Map ? Map<String, dynamic>.from(body['notice'] as Map) : const <String, dynamic>{};
    bool? b(dynamic v) => v is bool ? v : null;
    String? s(dynamic v) => v == null || '$v'.trim().isEmpty ? null : '$v';
    return ElTopupResult(
      ok: body['success'] == true,
      code: s(body['code']),
      message: s(body['message']),
      balanceAfter: num.tryParse('${body['balance_after'] ?? ''}'),
      deduped: body['deduped'] == true,
      debtRecorded: b(body['debt_recorded']),
      noticeApp: b(n['app']),
      noticeAppMessage: s(n['app_message']),
      noticeWhatsapp: b(n['whatsapp']),
      noticeWhatsappMessage: s(n['whatsapp_message']),
      fee: TopupFeeOutcome.fromJson(body['fee']),
    );
  }
}

class ElManagersApi {
  ElManagersApi._();

  /// أدنى مبلغ تحويل تفرضه ايرث لنك.
  static const int minTopup = 5000;

  static Future<ElManagersList> list() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/el/managers');
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return ElManagersList(message: '${body['message'] ?? 'تعذّر جلب المدراء'}');
      }
      if (body['enabled'] == false) return const ElManagersList(enabled: false);
      final data = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : const <String, dynamic>{};
      final rows = (data['managers'] is List ? data['managers'] as List : const [])
          .whereType<Map>()
          .map((m) => ElManagerRow.fromJson(Map<String, dynamic>.from(m)))
          .whereType<ElManagerRow>()
          .toList();
      return ElManagersList(
        balance: num.tryParse('${data['balance'] ?? ''}'),
        rows: rows,
        depositSaved: data['deposit_saved'] == true,
      );
    } on DioException catch (e) {
      final d = e.response?.data;
      return ElManagersList(message: d is Map && d['message'] != null ? '${d['message']}' : 'تعذّر جلب المدراء');
    } catch (_) {
      return const ElManagersList(message: 'تعذّر جلب المدراء');
    }
  }

  static Future<ElTopupResult> topup({
    required int index,
    required num amount,
    required bool asDebt,
    required String idempotencyKey,
    bool notifyApp = true,
    bool notifyWhatsapp = true,
    String? depositPassword,
    bool rememberDepositPassword = false,
    String? note,
    bool confirmRepeat = false,
    Map<String, Object>? fee,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/v2/el/managers/$index/topup', data: {
        'amount': amount,
        'as_debt': asDebt,
        'notify_app': notifyApp,
        'notify_whatsapp': notifyWhatsapp,
        'idempotencyKey': idempotencyKey,
        if (depositPassword != null && depositPassword.isNotEmpty) 'depositPassword': depositPassword,
        if (rememberDepositPassword) 'rememberDepositPassword': true,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        if (confirmRepeat) 'confirmRepeat': true,
        // الفائدة جزءٌ من الطلب: «تحقّق» بالمفتاح نفسه يعيدها كما هي (الحقول مقفلة) — الخادم يرفض المفتاح بفائدةٍ أخرى
        if (fee != null) 'fee': fee,
      });
      final body = r.data ?? const {};
      ElDepositPassword.observe(body); // حُفظت كلمة الإيداع الآن، أو مُسحت لأنّ ايرث لنك رفضتها
      return ElTopupResult.fromBody(body);
    } on DioException catch (e) {
      final d = e.response?.data;
      if (d is Map) {
        ElDepositPassword.observe(d);
        return ElTopupResult.fromBody(d);
      }
      // لا ردٌّ مفهوم (انقطاع، مهلة، صفحة وسيط): قد يكون الشحن تمّ — «تحقّق» بالمفتاح نفسه
      return const ElTopupResult(ok: false, noResponse: true, message: 'لم يصل ردّ الخادم — قد يكون الشحن تمّ. اضغط «تحقّق» قبل أيّ إعادة');
    } catch (_) {
      return const ElTopupResult(ok: false, noResponse: true, message: 'لم يصل ردّ الخادم — قد يكون الشحن تمّ. اضغط «تحقّق» قبل أيّ إعادة');
    }
  }

  /// رقم واتساب المدير (الفارغ يحذفه) ⇒ (ok, الرقم كما يُعرض، الرسالة).
  static Future<({bool ok, String? phone, String? message})> saveContact(int index, String phone) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>('/api/v2/el/managers/$index/contact', data: {'wa_phone': phone});
      final b = r.data ?? const {};
      return (ok: b['success'] == true, phone: b['wa_phone'] == null ? null : '${b['wa_phone']}', message: b['message'] == null ? null : '${b['message']}');
    } on DioException catch (e) {
      final d = e.response?.data;
      return (ok: false, phone: null, message: d is Map && d['message'] != null ? '${d['message']}' : 'تعذّر حفظ الرقم');
    } catch (_) {
      return (ok: false, phone: null, message: 'تعذّر حفظ الرقم');
    }
  }
}
