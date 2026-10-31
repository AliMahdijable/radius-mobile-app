import 'package:dio/dio.dart';

import 'api_client.dart';

/// المشروع الوطنيّ — التفعيل بالدفع بالبطاقة (تبادل/ماستر كارد، ٣١ أكتوبر؛ الخادم dd29815 server/watani/wataniCardPay.js، مفتاح
/// watani_card): activate بـ`method:'card'` ⇒ رابط دفعٍ لا تفعيل (`outcome: payment_required`)، والوكيل يدفع من صفحة الدفع، والخادم
/// يؤكّد ويحكم بالأثر ويسجّل الدين وحده. التطبيق يفتح الرابط ويتابع الطلب (GET /api/v2/ftth/card-orders/:order) حتى يُحسم.
typedef KitCardStart = ({
  bool ok,
  String? code,
  String? message,
  String? paymentUrl,
  String? orderNumber,
  num? cost,
  num? price,
  bool noReply,
});

typedef KitCardStatus = ({String status, String? paymentUrl, num? cost, num? price});

class KitCardApi {
  KitCardApi._();

  /// حالاتٌ لم تُحسم بعد (الرابط قائم، أو دُفع وينتظر أثره).
  static const live = {'creating', 'link', 'paid', 'applying'};

  /// طلب رابط الدفع. `ok` = رابطٌ جديد، أو (code `CARD_ORDER_OPEN`) رابط الطلب المفتوح نفسه لهذا المشترك — كلاهما يحمل الرابط والرقم.
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
      return (ok: false, code: null, message: null, paymentUrl: null, orderNumber: null, cost: null, price: null, noReply: false);
    }
  }

  /// ردّ activate (نجاحٌ أو رفضٌ — الرفض يصل جسماً لا استثناءً: validateStatus < 500).
  static KitCardStart parse(Map<String, dynamic> b, {required bool noReply}) {
    final url = b['payment_url']?.toString();
    final order = b['order_number']?.toString();
    final code = b['code']?.toString();
    final hasLink = url != null && url.startsWith('https://') && order != null && order.isNotEmpty;
    final ok = hasLink && ((b['success'] == true && b['outcome'] == 'payment_required') || code == 'CARD_ORDER_OPEN');
    final cost = b['cost'];
    final price = b['amount'];
    return (
      ok: ok,
      code: code,
      message: b['message']?.toString(),
      paymentUrl: hasLink ? url : null,
      orderNumber: hasLink ? order : null,
      cost: cost is num ? cost : null,
      price: price is num ? price : null,
      noReply: noReply,
    );
  }

  /// حالة الطلب لصاحبه — null عند التعذّر (المحاولة التالية).
  static Future<KitCardStatus?> status(String order) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/ftth/card-orders/${Uri.encodeComponent(order)}');
      final b = r.data;
      final d = b?['data'];
      if (b?['success'] != true || d is! Map) return null;
      final cost = d['amount'];
      final price = d['price'];
      return (
        status: d['status']?.toString() ?? 'unknown',
        paymentUrl: d['payment_url']?.toString(),
        cost: cost is num ? cost : null,
        price: price is num ? price : null,
      );
    } catch (_) {
      return null;
    }
  }
}
