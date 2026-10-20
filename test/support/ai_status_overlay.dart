import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// خادمٌ وهميّ فوق خادمٍ وهميٍّ آخر: يردّ `GET /api/v2/ai/status` بـ[status]
/// (حال المساعد الذكيّ؛ `null` = ٤٠٤ كخادمٍ أقدم بلا المسار)، ومسارات [routes]
/// كما هي (٢٠٠)، ويمرّر كلّ ما سواهما لـ[inner] — خادم لقطات الصلاحيّات عادةً
/// (`VisualServer`) بردوده المعقولة للرئيسيّة والمشتركين والأجهزة.
///
/// لا شبكة حقيقيّة: يُركَّب على `ApiClient.dio.httpClientAdapter`.
class AiStatusOverlay implements HttpClientAdapter {
  AiStatusOverlay(this.inner,
      {this.status, Map<String, Object>? routes, Set<String>? failing})
      : routes = routes ?? <String, Object>{},
        failing = failing ?? <String>{};

  static const statusPath = '/api/v2/ai/status';

  final HttpClientAdapter inner;

  /// جسم ردّ الحال — يُبدَّل أثناء الاختبار (شُغّل/أُطفئ من الخادم).
  Map<String, dynamic>? status;

  /// «METHOD path» ← جسم JSON يُردّ بـ٢٠٠ بدل [inner].
  final Map<String, Object> routes;

  /// «METHOD path» يردّ ٥٠٠ (عطلٌ في الخادم) — يُزال منها ليعود سليماً.
  final Set<String> failing;

  /// «METHOD path» يُمسك ردّه حتى يكتمل — لما يجري **أثناء** الانتظار.
  final holds = <String, Completer<void>>{};

  /// كلّ طلبٍ وصل، بترتيبه (ما مرّ لـ[inner] أيضاً).
  final requests = <RequestOptions>[];

  int get statusCalls => requests.where((r) => r.path == statusPath).length;

  /// طلبات المساعد غير سؤال الحال (explain/ask/feedback) — يجب ألّا تقع
  /// بلا نقرٍ صريح وموافقة.
  List<String> get aiCalls => [
        for (final r in requests)
          if (r.path.startsWith('/api/v2/ai/') && r.path != statusPath)
            '${r.method} ${r.path}',
      ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path == statusPath) {
      final s = status;
      return s == null
          ? _json(404, const {'success': false, 'message': 'غير موجود'})
          : _json(200, s);
    }
    final key = '${options.method.toUpperCase()} ${options.path}';
    final hold = holds[key];
    if (hold != null) await hold.future;
    if (failing.contains(key)) {
      return _json(500, const {'success': false, 'message': 'تعذّر'});
    }
    final body = routes[key];
    if (body != null) return _json(200, body);
    return inner.fetch(options, requestStream, cancelFuture);
  }

  static ResponseBody _json(int status, Object body) =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}

/// المساعد مفتوحٌ لهذا الحساب («كيف أسوّي؟» و«اشرحلي»).
const aiStatusOn = <String, dynamic>{
  'success': true,
  'enabled': true,
  'can_use': true,
  'explain': true,
  'ask': true,
  'quota': {'left': 7, 'limit': 10},
  'suggestions': ['شلون أفعّل مشترك بالكارت؟'],
};

/// موظّفٌ بلا صلاحيّة «المساعد الذكي» — مقفلٌ بمكانه.
const aiStatusLocked = <String, dynamic>{
  'success': true,
  'enabled': true,
  'can_use': false,
  'reason': 'no_permission',
  'locked_text': 'ما عندك صلاحيّة المساعد — اطلبها من مديرك',
};

/// مطفأٌ لهذا الحساب (الافتراضيّ في الإنتاج).
const aiStatusOff = <String, dynamic>{'success': true, 'enabled': false};
