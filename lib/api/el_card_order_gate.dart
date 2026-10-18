import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import '../services/permissions_service.dart';
import '../services/provider_service.dart';
import 'api_client.dart';
import 'earthlink_api.dart';

/// «طلب الكارتات» (ايرث لنك) مفتوحٌ على الخادم؟
///
/// الطلب يخصم مالاً من رصيد الإيداع، وللخادم مفتاح إيقافٍ له (`pro_settings`
/// «el_card_order») يردّ به التقدير والطلب معاً 503 `CARD_ORDER_OFF` — ولا مسار
/// قراءةٍ يقول حاله. فيُسأل التقدير بسلّةٍ فارغة: الخادم يفحص المفتاح قبل أيّ
/// شيء، ثمّ يرفض السلّة الفارغة 400 «حدّد الباقة والعدد» — بلا نداءٍ لايرث لنك
/// ولا أثر.
///
/// بطاقة «قوائم أخرى» وزرّ «اطلب هذه الكارتات» يظهران حين يقول الخادم «مفتوح»
/// صراحةً — كـ«شحن رصيد الصفحة»: والمفتاح مطفأ لا يظهر شيء (لا نموذجٌ يُملأ ثمّ
/// يُرفض بـ«موقوف»). ويُعاد السؤال بعد [ttl]، فيظهر الباب وحده متى فُتح.
class ElCardOrderGate {
  ElCardOrderGate._();

  /// `true` مفتوح · `false` موقوف (أو لا باب لهذا الحساب) · `null` لم يُعرف.
  static final ValueNotifier<bool?> open = _LazyCardOrderGate();

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static Future<void>? _inflight;

  static const ttl = Duration(minutes: 5);
  static const _cooldown = Duration(seconds: 30);

  static const _quotePath = '/api/v2/el/card-order/quote';

  /// تُؤخذ قبل الطلب: ردٌّ يصل بعد تبديل الجلسة لا يُكتب.
  static int get epoch => _epoch;

  /// الباب يظهر؟ صاحب حساب ايرث لنك (الموظّف لا يطلب: مال صاحب الحساب)،
  /// والخادم قال «مفتوح».
  static bool get visible =>
      ProviderService.isEarthlink && !Perms.isEmployee && open.value == true;

  /// يسأل الخادم إن كانت الحال قديمة — لصاحب حساب ايرث لنك وحده (غيره لا باب
  /// له، فلا طلب). سؤالٌ واحدٌ جارٍ على الأكثر، وبعد الفشل تبريد.
  static Future<void> ensureFresh({bool force = false}) {
    if (!ProviderService.isEarthlink || Perms.isEmployee) {
      return Future<void>.value();
    }
    final running = _inflight;
    if (running != null) return running;
    if (!force) {
      final now = DateTime.now();
      final at = _fetchedAt;
      if (at != null && now.difference(at) < ttl) return Future<void>.value();
      final failed = _failedAt;
      if (failed != null && now.difference(failed) < _cooldown) {
        return Future<void>.value();
      }
    }
    final epoch = _epoch;
    late final Future<void> run;
    run = _ask(epoch).whenComplete(() {
      if (identical(_inflight, run)) _inflight = null;
    });
    _inflight = run;
    return run;
  }

  static Future<void> _ask(int epoch) async {
    // بلا جلسة لا سؤال (وهي حال الاختبارات بلا خزنة) — كـ«شحن رصيد الصفحة».
    String? token;
    try {
      token = await AuthStorage.readToken();
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) return;
    final on = await probe();
    if (epoch != _epoch) return;
    if (on == null) {
      _failedAt = DateTime.now();
      return;
    }
    apply(on, epoch: epoch);
  }

  /// حكم الخادم — من السؤال، أو من ردٍّ في شاشة الطلب نفسها (تقديرٌ نجح ⇒
  /// مفتوح، `CARD_ORDER_OFF` ⇒ موقوف).
  static void apply(bool on, {int? epoch}) {
    if (epoch != null && epoch != _epoch) return;
    _fetchedAt = DateTime.now();
    _failedAt = null;
    open.value = on;
  }

  /// السؤال نفسه: `POST /el/card-order/quote` بسلّةٍ فارغة.
  @visibleForTesting
  static Future<bool?> probe() async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        _quotePath,
        data: const {'cards': <Object>[]},
      );
      return verdict(r.statusCode, r.data);
    } on DioException catch (e) {
      return verdict(e.response?.statusCode, e.response?.data);
    } catch (_) {
      return null;
    }
  }

  /// ردّ السؤال ⇒ الحال:
  ///  • `CARD_ORDER_OFF` بأيّ حالة ⇒ موقوف.
  ///  • 400 بلا رمز (السلّة الفارغة مرفوضة بعد فحص المفتاح) أو 2xx من خادمنا
  ///    ⇒ مفتوح.
  ///  • 403 (ليس صاحب الحساب) · 404 (خادمٌ بلا المسار) ⇒ لا باب.
  ///  • ما سوى ذلك (انقطاع، 5xx بلا الرمز، 401، حدّ طلبات، 400 برمزٍ آخر، ردٌّ
  ///    غير JSON) ⇒ `null`: لم يُعرف — فيبقى ما عُرف قبله ويُعاد بعد التبريد.
  @visibleForTesting
  static bool? verdict(int? status, Object? body) {
    final code = body is Map ? body['code']?.toString() : null;
    if (code == EarthlinkApi.codeCardOrderOff) return false;
    if (status == null) return null;
    if (status == 403 || status == 404) return false;
    if (body is! Map) return null;
    if (status == 400) return code == null ? true : null;
    if (status >= 200 && status < 300) return true;
    return null;
  }

  /// من [SessionManager.clearAllSessionData] — لا يرى المدير التالي حال سابقه.
  static void reset() {
    _epoch++;
    _fetchedAt = null;
    _failedAt = null;
    _inflight = null;
    open.value = null;
  }

  @visibleForTesting
  static void debugSet(bool? on) {
    _epoch++;
    _inflight = null;
    _failedAt = null;
    _fetchedAt = on == null ? null : DateTime.now();
    open.value = on;
  }
}

/// حالةٌ تسأل عن نفسها حين يُستمع إليها — فالبطاقة والزرّ يجلبان ما يحتاجانه
/// بلا سطرٍ في شاشةٍ لا تملك حالة (كـ`SelfDepositState.gate`).
class _LazyCardOrderGate extends ValueNotifier<bool?> {
  _LazyCardOrderGate() : super(null);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    // بعد البناء لا أثناءه: الجواب يكتب القيمة فيُعيد بناء المستمعين.
    scheduleMicrotask(() {
      ElCardOrderGate.ensureFresh();
    });
  }
}
