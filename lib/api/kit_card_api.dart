import 'package:dio/dio.dart';

import 'api_client.dart';

/// المشروع الوطنيّ — التفعيل بالدفع بالبطاقة (تبادل/ماستر كارد، ٣١ أكتوبر؛ الخادم dd29815 server/watani/wataniCardPay.js، مفتاح
/// watani_card): activate بـ`method:'card'` ⇒ رابط دفعٍ لا تفعيل (`outcome: payment_required`)، والوكيل يدفع من صفحة الدفع، والخادم
/// يؤكّد ويحكم بالأثر ويسجّل الدين وحده. التطبيق يفتح الرابط ويتابع الطلب (GET /api/v2/ftth/card-orders/:order) حتى يُحسم.
///
/// الإصدار الثاني (١ نوفمبر — مراجعة الخادم): الطلب المفتوح (409 `CARD_ORDER_OPEN`) قد يكون **مدفوعاً بلا رابط** (`paid:true`) ⇒ لا
/// دفعٌ ثانٍ ولا صفحة دفع، يُتابَع حتى يتفعّل؛ والحالة تقول أيضاً هل رجع الدفع (`paid_seen`)، وهل انتهى بلا رجوعٍ يُثبت شيئاً
/// (`no_return` — لا «بلا دفع» كاذبة)، وحال الدين عندنا (`debt_state`: written · failed · maybe · none) وفشل كتابته
/// (`debt_write_failed`) — فلا «سُجّل عندنا» لدينٍ لم يُكتب.
typedef KitCardStart = ({
  bool ok,
  bool open,
  bool paid,
  String? code,
  String? message,
  String? paymentUrl,
  String? orderNumber,
  num? cost,
  num? price,
  bool noReply,
});

/// حال الدين عندنا لطلب: كُتب · فشلت كتابته (تفعّل ولم يُسجَّل) · ربّما (خطأٌ بعد الحسم) · لا دين (لم يُحسم بتفعيل).
enum KitCardDebt { written, failed, maybe, none }

typedef KitCardStatus = ({
  String status,
  String? paymentUrl,
  num? cost,
  num? price,
  String? paymentType,
  String? newExpiration,
  bool paidSeen,
  bool noReturn,

  /// null = خادمٌ أقدم لا يقولها.
  KitCardDebt? debt,
  bool debtWriteFailed,
});

class KitCardApi {
  KitCardApi._();

  /// حالاتٌ لم تُحسم بعد (الرابط قائم، أو دُفع وينتظر أثره).
  static const live = {'creating', 'link', 'paid', 'applying'};

  static const codeOpen = 'CARD_ORDER_OPEN';

  /// طلب رابط الدفع. `ok` = رابطٌ جديد، أو (`open`) طلبٌ مفتوحٌ لهذا المشترك يُتابَع برقمه: برابطه إن كان بانتظار الدفع، أو بلا
  /// رابط إن كان مدفوعاً (`paid`) ينتظر التفعيل.
  static Future<KitCardStart> start({
    required String idx,
    required String paymentType,
    required Map<String, dynamic> activationData,
    int? partialAmount,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/subscribers/$idx/activate',
        data: {
          'paymentType': paymentType,
          'activationData': activationData,
          if (paymentType == 'partial-cash' && partialAmount != null) 'partialAmount': partialAmount,
          'method': 'card',
        },
        options: Options(receiveTimeout: const Duration(seconds: 120)),
      );
      return parse(r.data ?? const <String, dynamic>{}, noReply: false);
    } on DioException catch (e) {
      final b = e.response?.data;
      return parse(b is Map<String, dynamic> ? b : const <String, dynamic>{}, noReply: e.response == null);
    } catch (_) {
      return (
        ok: false,
        open: false,
        paid: false,
        code: null,
        message: null,
        paymentUrl: null,
        orderNumber: null,
        cost: null,
        price: null,
        noReply: false,
      );
    }
  }

  /// رقم طلبٍ يُتابَع: لا فارغ ولا مؤقّت (`pending-…` — الخادم لا يجيب عنه).
  static String? _order(dynamic v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty || s.startsWith('pending-') ? null : s;
  }

  /// ردّ activate (نجاحٌ أو رفضٌ — الرفض يصل جسماً لا استثناءً: validateStatus < 500).
  static KitCardStart parse(Map<String, dynamic> b, {required bool noReply}) {
    final rawUrl = b['payment_url']?.toString();
    final order = _order(b['order_number']);
    final code = b['code']?.toString();
    final open = code == codeOpen;
    final paid = open && b['paid'] == true;
    // المدفوع لا رابط له أبداً (خادمٌ أقدم قد يرسل رابطه — لا يُفتح: دفعٌ ثانٍ)
    final url = !paid && rawUrl != null && rawUrl.startsWith('https://') ? rawUrl : null;
    final fresh = b['success'] == true && b['outcome'] == 'payment_required' && url != null && order != null;
    final cost = b['cost'];
    final price = b['amount'];
    return (
      ok: fresh || (open && order != null),
      open: open,
      paid: paid,
      code: code,
      message: b['message']?.toString(),
      paymentUrl: url,
      orderNumber: order,
      cost: cost is num ? cost : null,
      price: price is num ? price : null,
      noReply: noReply,
    );
  }

  static KitCardDebt? _debt(dynamic v) => switch (v?.toString()) {
        'written' => KitCardDebt.written,
        'failed' => KitCardDebt.failed,
        'maybe' => KitCardDebt.maybe,
        'none' => KitCardDebt.none,
        _ => null,
      };

  /// جسم `data` من حالة الطلب.
  static KitCardStatus parseStatus(Map d) {
    final cost = d['amount'];
    final price = d['price'];
    final url = d['payment_url']?.toString();
    final failed = d['debt_write_failed'] == true;
    final debt = _debt(d['debt_state']);
    return (
      status: d['status']?.toString() ?? 'unknown',
      paymentUrl: url != null && url.startsWith('https://') ? url : null,
      cost: cost is num ? cost : null,
      price: price is num ? price : null,
      paymentType: d['payment_type']?.toString(),
      newExpiration: d['new_expiration']?.toString(),
      paidSeen: d['paid_seen'] == true,
      noReturn: d['no_return'] == true,
      // «فشلت الكتابة» من أيّهما قالها (الخادم الأقدم يرسل debt_write_failed وحده)
      debt: failed ? KitCardDebt.failed : debt,
      debtWriteFailed: failed || debt == KitCardDebt.failed,
    );
  }

  /// حالة الطلب لصاحبه — null عند التعذّر (المحاولة التالية).
  static Future<KitCardStatus?> status(String order) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/ftth/card-orders/${Uri.encodeComponent(order)}');
      final b = r.data;
      final d = b?['data'];
      if (b?['success'] != true || d is! Map) return null;
      return parseStatus(d);
    } catch (_) {
      return null;
    }
  }
}
