import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// «ما تغيّر شي» (٢٤ نوفمبر — المالك: «تمام ابدأ بالأول والثاني» بعد تدقيق N+1).
///
/// أكبر قائمتين يطلبهما التطبيق مراراً — المشتركون (٢٦٫٦ ألف طلب/يوم ≈ ٣٠٧ ميغا) والمتّصلون الآن (٥٢ ألفاً ≈ ٣٦٢ ميغا) — كانتا
/// تُرسلان كاملتين وإن لم يتغيّر فيهما حرف. الخادم يضع بصمة كلّ ردّ (ETag = بصمة الجسم نفسه) ويجيب 304 «ما تغيّر شي» حين تطابق
/// البصمة التي يرسلها الطلب (If-None-Match) — والمتصفّح يفعلها من نفسه، والتطبيق لم يكن يفعلها.
///
/// الضمان: البصمة محسوبةٌ من الجسم الذي كان سيُرسَل لهذا الطلب نفسه، فـ304 تعني أنّ ما عندنا هو حرفيّاً ما كان سيصل — لا
/// رقمٌ قديم ممكن. وكلّ إعادةٍ تُفكّ من نصٍّ محفوظ (نسخةٌ جديدة، فتعديل الشاشة لها لا يمسّ المحفوظ). والمفتاح: الرابط كاملاً
/// + بصمة التوكن (حسابٌ آخر أو جلسةٌ جديدة ⇒ مفتاحٌ آخر). «كل الشركات» (الطلبات الموجَّهة) خارجها كلّيّاً.
/// الذاكرة وحدها (لا قرص)، ١٢ مدخلاً، وتُمسح مع الجلسة ([SessionManager.clearAllSessionData]).
class EtagCache {
  EtagCache._();

  /// المسارات المشمولة (GET وحده). غيرها كما كان حرفاً.
  static const paths = <String>{'/api/v2/subscribers', '/api/v2/online-users'};
  static const _maxEntries = 12;
  static const _maxBodyChars = 4 * 1024 * 1024;

  static final LinkedHashMap<String, ({String etag, String body})> _store = LinkedHashMap();
  static int hits = 0;

  static void clear() {
    _store.clear();
    hits = 0;
  }

  @visibleForTesting
  static int get size => _store.length;

  static bool _eligible(RequestOptions o) =>
      o.method.toUpperCase() == 'GET' && paths.contains(o.uri.path) && o.extra['_routed'] == null;

  static String? _keyOf(RequestOptions o) {
    final auth = o.headers['Authorization'] ?? o.headers['authorization'];
    if (auth == null) return null;
    final h = auth.toString().hashCode.toUnsigned(32).toRadixString(16);
    return '${o.uri}#$h';
  }

  static String? _etagOf(Headers h) {
    final v = h.value('etag');
    return (v == null || v.isEmpty) ? null : v;
  }
}

/// بعد معترض الجلسة: يرى التوكن وقرار التوجيه، فيضيف البصمة لطلبٍ مشمول له نسخةٌ محفوظة.
class EtagRequestInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (EtagCache._eligible(options)) {
      final key = EtagCache._keyOf(options);
      final hit = key == null ? null : EtagCache._store[key];
      if (hit != null) {
        options.headers['If-None-Match'] = hit.etag;
        options.extra['_etagKey'] = key;
        // الجسم مع الطلب نفسه: إخراجٌ من الذاكرة بين الطلب والردّ لا يترك 304 بلا جسم
        options.extra['_etagBody'] = hit.body;
      }
    }
    handler.next(options);
  }
}

/// أوّل المعترضات في الردّ: 304 لطلبٍ أرسل بصمته ⇒ ردّ 200 بالجسم المحفوظ (نسخةٌ جديدة) قبل أن يراه أيّ معترضٍ آخر — فلا يرى
/// مسار الجلسة ولا «كل الشركات» ولا بوّابة التحديث 304 أبداً. و200 مشمول ببصمةٍ وجسمٍ ناجح ⇒ يُحفظ.
class EtagResponseInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final o = response.requestOptions;
    try {
      if (response.statusCode == 304) {
        final key = o.extra['_etagKey'];
        final body = o.extra['_etagBody'];
        if (key is String && body is String) {
          final hit = EtagCache._store.remove(key); // الأحدث آخراً (LRU)
          if (hit != null) EtagCache._store[key] = hit;
          EtagCache.hits++;
          return handler.next(Response(
            requestOptions: o,
            statusCode: 200,
            statusMessage: 'OK',
            headers: response.headers,
            data: jsonDecode(body),
            extra: {...response.extra, 'etag304': true},
          ));
        }
        return handler.next(response);
      }
      if (response.statusCode == 200 && EtagCache._eligible(o)) {
        final etag = EtagCache._etagOf(response.headers);
        final key = EtagCache._keyOf(o);
        final data = response.data;
        if (etag != null && key != null && data is Map && data['success'] == true) {
          final body = jsonEncode(data);
          if (body.length <= EtagCache._maxBodyChars) {
            EtagCache._store.remove(key);
            EtagCache._store[key] = (etag: etag, body: body);
            while (EtagCache._store.length > EtagCache._maxEntries) {
              EtagCache._store.remove(EtagCache._store.keys.first);
            }
          }
        }
      }
    } catch (_) {
      // أفضل جهد: لا يغيّر الردّ أبداً بسبب البصمة
    }
    handler.next(response);
  }
}
