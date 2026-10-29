import 'package:flutter/foundation.dart';

import '../core/util/error_text.dart';
import 'api_client.dart';

/// طريقة شحن محفظة فايبر اكس (زين كاش / كي كارد …) بحدّها الأدنى والأعلى.
@immutable
class FxTopupMethod {
  const FxTopupMethod({
    required this.id,
    required this.provider,
    required this.name,
    this.walletName,
    this.minAmount,
    this.maxAmount,
  });

  final int id;
  final String provider; // zaincash | kicard | …
  final String name;
  final String? walletName;
  final int? minAmount;
  final int? maxAmount;

  bool get isZainCash => provider.toLowerCase().contains('zain');

  factory FxTopupMethod.fromJson(Map<String, dynamic> j) => FxTopupMethod(
        id: (j['id'] as num?)?.toInt() ?? 0,
        provider: (j['provider'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        walletName: j['walletName']?.toString(),
        minAmount: (j['minAmount'] as num?)?.toInt(),
        maxAmount: (j['maxAmount'] as num?)?.toInt(),
      );
}

/// ردّ `GET /topup/options`: مفعّلٌ للحساب؟ + الطرق + رصيد المحفظة.
@immutable
class FxTopupOptions {
  const FxTopupOptions({
    required this.enabled,
    required this.methods,
    this.balance,
    this.spendable,
  });

  final bool enabled;
  final List<FxTopupMethod> methods;
  final num? balance;
  final num? spendable;

  factory FxTopupOptions.fromJson(Map<String, dynamic> j) {
    final data = (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final wallet = (data['wallet'] as Map?)?.cast<String, dynamic>();
    return FxTopupOptions(
      enabled: j['enabled'] == true,
      methods: ((data['methods'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => FxTopupMethod.fromJson(m.cast<String, dynamic>()))
          .toList(),
      balance: wallet?['balance'] as num?,
      spendable: wallet?['spendable'] as num?,
    );
  }
}

/// رابط دفعٍ أُنشئ: يُفتح بمتصفّح الوكيل، ثمّ نتابع الحالة بـ[transactionId].
@immutable
class FxTopupStart {
  const FxTopupStart({
    required this.paymentUrl,
    required this.transactionId,
    required this.provider,
    required this.amount,
  });

  final String paymentUrl;
  final String? transactionId;
  final String provider;
  final int amount;
}

/// نتيجة `POST /topup`: إمّا رابطٌ ([start])، أو رسالةٌ ورمزٌ (تأكيد التكرار/خطأ)،
/// و[notSure] حين وصل الطلب ولم يصل الحكم — لا يُعاد أعمى (قد يكون أُنشئ الرابط).
typedef FxTopupInitResult = ({
  FxTopupStart? start,
  String? message,
  String? code,
  bool notSure,
});

/// حالة الدفعة من فايبر اكس (الحقيقة عندهم — هم يضيفون المبلغ للمحفظة).
@immutable
class FxTopupStatus {
  const FxTopupStatus({required this.found, this.state, this.raw});
  final bool found;
  final String? state; // success | pending | failed … (نصّ فايبر اكس)
  final Map<String, dynamic>? raw;

  bool get isSuccess {
    final s = (state ?? '').toLowerCase();
    return s.contains('success') || s.contains('paid') || s.contains('complete');
  }

  bool get isFailed {
    final s = (state ?? '').toLowerCase();
    return s.contains('fail') || s.contains('cancel') || s.contains('reject') || s.contains('expire');
  }
}

/// شحن محفظة فايبر اكس — `/api/v2/fiberx/topup/*`.
///
/// لا مال يمرّ بخادمنا: ننشئ رابط الدفع، يفتحه الوكيل بمتصفّحه، والبوّابة
/// تضيف المبلغ لمحفظته؛ ونتابع الحالة من فايبر اكس بـ[transactionId].
/// `ApiClient.dio` يقبل 4xx (`validateStatus < 500`) فنقرأ الحالة والجسم مباشرةً.
class FiberxTopupApi {
  FiberxTopupApi._();

  static const _base = '/api/v2/fiberx/topup';

  static Future<({FxTopupOptions? data, bool offline, String? message})> options() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('$_base/options');
      final body = r.data ?? const <String, dynamic>{};
      if ((r.statusCode ?? 0) >= 400) {
        return (data: null, offline: false, message: (body['message'] ?? 'تعذّر جلب طرق الشحن').toString());
      }
      return (data: FxTopupOptions.fromJson(body), offline: false, message: null);
    } catch (e) {
      return (data: null, offline: true, message: humanError(e, fallback: 'تعذّر الاتّصال بالخادم'));
    }
  }

  static Future<FxTopupInitResult> initiate({
    required int methodId,
    required int amount,
    bool confirmRepeat = false,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        _base,
        data: {
          'methodId': methodId,
          'amount': amount,
          if (confirmRepeat) 'confirmRepeat': true,
        },
      );
      final body = r.data ?? const <String, dynamic>{};
      final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      final url = (data['paymentUrl'] ?? '').toString().trim();
      if (body['success'] == true && url.isNotEmpty) {
        return (
          start: FxTopupStart(
            paymentUrl: url,
            transactionId: data['transactionId']?.toString(),
            provider: (data['provider'] ?? '').toString(),
            amount: (data['amount'] as num?)?.toInt() ?? amount,
          ),
          message: null,
          code: null,
          notSure: false,
        );
      }
      final code = body['code']?.toString();
      return (
        start: null,
        message: (body['message'] ?? 'تعذّر إنشاء رابط الدفع').toString(),
        code: code,
        // «لم نعرف هل أُنشئ الرابط — لم يُدفع» ⇒ لا يُعاد أعمى.
        notSure: code == 'FIBERX_TOPUP_UNKNOWN',
      );
    } catch (e) {
      // 5xx/انقطاع: وصل الطلب وقد يكون أُنشئ الرابط — لا نعيد أعمى.
      return (start: null, message: humanError(e, fallback: 'تعذّر الاتّصال بالخادم'), code: null, notSure: true);
    }
  }

  static Future<FxTopupStatus> status(String transactionId) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '$_base/status/${Uri.encodeComponent(transactionId)}',
      );
      final data = (r.data?['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      return FxTopupStatus(
        found: data['found'] == true,
        state: (data['state'] ?? data['status'])?.toString(),
        raw: data,
      );
    } catch (_) {
      return const FxTopupStatus(found: false);
    }
  }
}
