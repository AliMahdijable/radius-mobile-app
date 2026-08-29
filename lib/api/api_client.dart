import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import '../services/session_manager.dart';
import 'auth_api.dart';

/// تنبيه عام لِلوصول 401 + فشل refresh — تستمع له الـMainShell/Splash
/// لتدفع المستخدم لـLoginScreen. القيمة عداد بسيط (bump على كل
/// authentication failure)، لا تحمل معلومات.
///
/// 2026-06-14: مطلوب للموظفين خاصة — refreshToken() ترفض التجديد لهم
/// (وإلا تكتب SAS4 admin token فوق empToken). فالـinterceptor يحتاج
/// قناة لإخبار الـUI أن الجلسة انتهت ولا فائدة من المتابعة.
final ValueNotifier<int> authExpiredSignal = ValueNotifier<int>(0);

/// إشارة "هذا المدير محظور من super-admin". تُطلق حين يرد السيرفر
/// 403 مع {blocked:true, message}. الـMainShell يستمع ويطرد المستخدم
/// لـLoginScreen مع عرض `blockedMessage`.
final ValueNotifier<int> accessBlockedSignal = ValueNotifier<int>(0);
String? blockedMessage;

/// Two shared Dio instances:
///  • `dio` → backend (rad.mysvcs.net)
///  • `sas4` → SAS4 (reseller-supernet.net), direct widget endpoints
///
/// Both share the same auth interceptor that:
///   1. Attaches `Authorization: Bearer <token>` + `x-auth-token: <token>`
///      to every request (mirrors v1's AuthInterceptor.onRequest).
///   2. On 401 / 'Token has expired', calls /api/auth/refresh-token,
///      saves the new token, and retries the original request ONCE.
///      Matches v1's onError handler. The `_refreshing` future is shared
///      so 50 concurrent 401s collapse into one refresh call.
///   3. Skips auth on /api/auth/* requests themselves so login + refresh
///      don't recurse.
class ApiClient {
  ApiClient._();

  static const String baseUrl = 'https://rad.mysvcs.net';
  static const String sas4BaseUrl =
      'https://reseller-supernet.net/admin/api/index.php/api';

  static final Dio dio = _buildDio(baseUrl);
  static final Dio sas4 = _buildDio(sas4BaseUrl);

  static Dio _buildDio(String url) {
    final d = Dio(BaseOptions(
      baseUrl: url,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      validateStatus: (s) => s != null && s < 500,
    ));
    d.interceptors.add(_AuthInterceptor(d));
    return d;
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._dio);
  final Dio _dio;

  // Concurrency: many calls fire in parallel from the dashboard. When a
  // 401 hits, the first one starts a refresh; everyone else awaits the
  // same future so we don't hammer /refresh-token. Cleared on completion.
  static Future<bool>? _refreshing;

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    // /api/auth/login + /api/auth/refresh-token must NOT carry a stale
    // token — login takes none, refresh uses adminId in the body.
    final isAuthEndpoint = options.path.contains('/api/auth/');
    if (!isAuthEndpoint) {
      final token = await AuthStorage.readToken();
      if (token != null) {
        // v1 sends BOTH headers — Authorization (modern) and x-auth-token
        // (legacy backend routes still read it). Match exactly.
        options.headers['Authorization'] = 'Bearer $token';
        options.headers['x-auth-token'] = token;
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    final data = response.data;

    // 403 مع {blocked:true} → المدير محظور من super-admin. نمسح الجلسة
    // ونبعث إشارة للـUI ليطرده لـLoginScreen مع عرض السبب. نضع
    // blockedMessage قبل أن نطلق الإشارة عشان الـMainShell يقرأها.
    if (response.statusCode == 403 && data is Map && data['blocked'] == true) {
      final msg = data['message']?.toString();
      blockedMessage = (msg != null && msg.isNotEmpty)
          ? msg
          : 'تم إيقاف حسابك — تواصل مع الإدارة';
      // نمسح كل ما يتعلّق بالجلسة (token، caches). نلغي unregisterFcm
      // لأن الاتصال بالخادم قد يفشل الآن (لكن الـtoken غير نافع بأي حال).
      await SessionManager.clearAllSessionData(unregisterFcm: false);
      accessBlockedSignal.value = accessBlockedSignal.value + 1;
      return handler.next(response);
    }

    // Some endpoints return 200 OK with `{success:false, message:'Token has expired'}`
    // (SAS4 widget endpoints do exactly that — see status=401 in user logs).
    // Trigger a refresh + retry the SAME way we do for HTTP 401.
    final isExpiredEnvelope = response.statusCode == 401 ||
        (data is Map &&
            data['message'] is String &&
            (data['message'] as String).contains('expired'));
    if (!isExpiredEnvelope) {
      return handler.next(response);
    }
    final retry = await _refreshAndRetry(response.requestOptions);
    if (retry != null) {
      return handler.resolve(retry);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }
    if (err.requestOptions.path.contains('/api/auth/')) {
      return handler.next(err);
    }
    final retry = await _refreshAndRetry(err.requestOptions);
    if (retry != null) {
      return handler.resolve(retry);
    }
    handler.next(err);
  }

  /// Coordinates a single refresh + retries the failed request with the
  /// new token. Concurrent callers (5 dashboard fetches racing) all wait
  /// on the same future so refresh-token is hit at most once.
  Future<Response?> _refreshAndRetry(RequestOptions failed) async {
    final ok = await _runRefresh();
    if (!ok) {
      // 2026-07-12 fix (v1 parity): refresh فشل حقيقي (شبكة/توكن الأب
      // منتهي). نمسح ونرمي المستخدم لـlogin. سابقاً كان الموظف يمسح
      // فوراً حتى عند 401 عابر بدون refresh — تم الإصلاح بالسماح للـ
      // refresh أوّلاً في AuthApi.refreshToken.
      final isEmp = await AuthStorage.isEmployee();
      if (isEmp) {
        // 2026-07-14: نمسح كل caches الجلسة عبر SessionManager بدلاً
        // من Auth + Perms فقط — سابقاً كان الأدمن التالي يشوف رواسب
        // (subscribers list، device snapshots) من الجلسة السابقة.
        await SessionManager.clearAllSessionData(unregisterFcm: false);
        authExpiredSignal.value = authExpiredSignal.value + 1;
      }
      return null;
    }
    // Prevent infinite loops: tag the retried request and skip refresh
    // if it fails a second time.
    if (failed.extra['__retried_after_refresh'] == true) return null;
    failed.extra['__retried_after_refresh'] = true;
    // 2026-07-12 fix: الاستدعاءات الداخلية (/api/**) تستعمل token (empJWT
    // للموظف، admin token للأدمن). الاستدعاءات المباشرة على SAS4 (لو
    // موجودة) تستعمل sas4Token. حالياً كل الـclient calls تمر عبر
    // /api/ فنستعمل token — لكن نحتفظ بـsas4Token في التخزين لو تُضاف
    // استدعاءات مباشرة لاحقاً.
    final newToken = await AuthStorage.readToken();
    if (newToken == null) return null;
    failed.headers['Authorization'] = 'Bearer $newToken';
    failed.headers['x-auth-token'] = newToken;
    try {
      return await _dio.fetch(failed);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 retry after refresh failed: $e');
      return null;
    }
  }

  Future<bool> _runRefresh() async {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final f = AuthApi.refreshToken().then((r) => r != null);
    _refreshing = f;
    try {
      return await f;
    } finally {
      _refreshing = null;
    }
  }
}
