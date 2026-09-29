import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
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

/// عميلٌ واحدٌ مشترك: `dio` → خادمنا (rad.mysvcs.net).
///
/// ⚠️ **التطبيق لا يخاطب الساس مباشرةً، ولا يعرف عنوانه.** كان هنا
/// عميلٌ ثانٍ `sas4` مثبَّتٌ على `reseller-supernet.net` يخدم خمسة
/// widgets في الداشبورد؛ حُذفت نداءاته في 2026-08-31 (`a58acd7`) ثمّ
/// حُذف هو في 2026-09-15 مع آخر كودٍ ميّت يحمل العنوان.
///
/// ولحذفه سببٌ يتجاوز التنظيف: عنوان الساس كان **ثابتاً نصّيّاً**
/// يُبنى مرّةً عند تحميل الصنف، والمعترض يلصق `readToken()` — وهو
/// `empJWT` خادِمنا في حالة الموظّف — على كلّ طلب. فأيّ إحياءٍ لذلك
/// العميل يرسل توكن خادمنا إلى مضيفٍ ثالث، ويقصر التطبيق على ساسٍ
/// واحدٍ إلى الأبد. من احتاج رقماً من الساس فليطلبه من خادمنا: هناك
/// وحده يُعرف أيّ ساسٍ يخصّ هذا المدير. يحرسه `test/no_direct_sas_test.dart`.
///
/// والمعترض:
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

  static final Dio dio = _buildDio(baseUrl);

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
    // ⚡ إبقاء الاتّصال حيّاً 60 ثانية (تدقيق أداء 2026-08-31).
    //
    // `IOHttpClientAdapter` الافتراضيّ يضبط `idleTimeout` على **ثلاث**
    // ثوانٍ، وإيقاع التطبيق الغالب استطلاعٌ كلّ خمس — أي أنّ المقبس
    // يموت قبل الطلب التالي دائماً، فيدفع كلّ طلب مصافحة TCP + TLS
    // كاملة من جديد. على شبكة خلويّة عراقيّة هذه مئات الميلي ثانية
    // قبل أن تُرسَل بايت واحدة من الطلب.
    //
    // ستّون ثانية تغطّي كلّ الإيقاعات الدوريّة في التطبيق، والخادم
    // خلف nginx يدعمها أصلاً.
    d.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient()
        // 15 لا 60: أطول من إيقاع الاستطلاع (5ث) فيبقى المكسب،
        // وأقصر من مهلة الإبقاء على معظم الخوادم فيقلّ احتمال
        // إرسال طلب في مقبس أغلقه الطرف الآخر.
        ..idleTimeout = const Duration(seconds: 15)
        ..maxConnectionsPerHost = 8,
    );
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
  static Future<RefreshOutcome>? _refreshing;

  /// جيلُ التجديد — يرتفع مع كلّ تجديدٍ ناجح.
  ///
  /// 🐛 علامة «حاولتُ بعد التجديد» كانت مطلقة، فطلبٌ استهلك محاولته
  /// في موجةٍ سابقة يُرفض في الموجة التالية **رغم أنّ الجلسة صارت
  /// سليمة** — فتظهر بطاقةٌ واحدة «تعذّر الجلب» في شاشةٍ كلّ ما فيها
  /// يعمل. والعلامة تعني «حاولتُ بهذا التوكن» لا «حاولتُ إلى الأبد».
  static int _refreshGen = 0;

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

    // 🐛 `validateStatus: s < 500` يجعل الـ401 **نجاحاً** في نظر Dio،
    // فيُعالَج هنا لا في `onError`. و`onError` وحده كان يستثني
    // `/api/auth/` — فموظّفٌ يُخطئ كلمة سرّه على `/api/auth/login`
    // يُشغّل مسار التجديد، وقد يُمحى حسابه بسبب خطأٍ مطبعيّ.
    //
    // والاستثناء لازمٌ في **الموضعين**: وجوده في `onError` وحده هو
    // ما أخفى العطل، لأنّ الردّ لا يمرّ بـ`onError` أصلاً.
    if (response.requestOptions.path.contains('/api/auth/')) {
      return handler.next(response);
    }

    // ردٌّ 200 يحمل `{success:false, message:'Token has expired'}` يُعامَل
    // معاملة 401. كان هذا سلوك widgets الساس المباشرة؛ خادمنا لا يُصدر
    // هذا المغلّف اليوم (فُحص: صفر موضع)، فالشرط احتياطٌ لا مسارٌ حيّ —
    // أبقيناه لأنّه مجّانيّ، لا لأنّ نداءً مباشراً على الساس عاد.
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
    // ── إعادة محاولة واحدة على مقبس ميت ──
    //
    // 🐛 بلاغ 2026-08-31: «HttpException: Connection reset by peer» على
    // نداءات SAS4، وطلبات تعود بـ`status=null body=null`.
    //
    // هذا الأثر الجانبيّ المعروف لإبقاء الاتّصال حيّاً (أُضيف في
    // 4.1.0): المقبس المُعاد استعماله قد يكون الخادم أو الوسيط قد أغلقه
    // بالفعل، فيُرسَل الطلب في أنبوب ميت ويعود «reset by peer». لا
    // يكشفه العميل إلّا بالمحاولة — فالمحاولة الثانية تفتح مقبساً
    // جديداً وتنجح.
    //
    // مقصورةٌ على GET: وحدها آمنة التكرار. وعلى أخطاء النقل وحدها —
    // لا على ردٍّ وصل بحالة خطأ.
    final isTransport = err.type == DioExceptionType.connectionError ||
        (err.type == DioExceptionType.unknown && err.response == null);

    // ── وبوّابة عابرة من الوسيط ──
    //
    // 🐛 بلاغ 2026-08-31: موجة 502 من Cloudflare بجسمٍ يقول صراحةً
    // `origin_bad_gateway` و`retryable: true`. الطابع الزمنيّ طابق
    // إعادة تشغيل الخادم إلى الثانية: كلّ طلب كان في الطريق أثناء
    // نافذة الإقلاع (~ثانيتان) ارتدّ لأنّ المنفذ كان مغلقاً.
    //
    // وهذا يتكرّر مع **كلّ** نشر. ووضع cluster بنسختين — الحلّ
    // المعتاد — خطرٌ هنا: نسختان تعنيان جدولَي مهامّ ورسائل واتساب
    // مكرّرة. فالمكان الصحيح للمعالجة هو العميل.
    //
    // 502/503/504 وحدها: أخطاء وسيط عابرة. 500 مستثناة عمداً — عطل
    // تطبيقٍ حقيقي، وإعادته تُخفي الخلل وتضاعف الحمل.
    final code = err.response?.statusCode ?? 0;
    final isGatewayBlip = code == 502 || code == 503 || code == 504;

    final isIdempotent = err.requestOptions.method.toUpperCase() == 'GET';
    if ((isTransport || isGatewayBlip) &&
        isIdempotent &&
        err.requestOptions.extra['_retried'] != true) {
      err.requestOptions.extra['_retried'] = true;
      // مهلة قبل إعادة بوّابة عابرة: الخادم يحتاج ثوانيَ ليقلع، وإعادة
      // فوريّة تصطدم بالنافذة نفسها. أمّا المقبس البائت فيُعاد فوراً —
      // المقبس الجديد جاهز حالاً.
      if (isGatewayBlip) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      try {
        final res = await _dio.fetch<dynamic>(err.requestOptions);
        return handler.resolve(res);
      } catch (_) {
        // فشلت الثانية أيضاً — انقطاع حقيقي لا نافذة إقلاع.
        return handler.next(err);
      }
    }

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
    // 🐛 كان هذا الفحص **بعد** التجديد، فكلّ ٤٠١ يُطلق تجديدَين:
    // الأوّل يضع العلامة، والمحاولة المُعادة تفشل فتدخل هنا فتُجدّد
    // ثانيةً قبل أن تقرأ العلامة. تقديمه يوقف الازدواج من أصله.
    // الرفض يقع فقط إن كانت المحاولة السابقة **بهذا التوكن نفسه**.
    // ٢٠٢٦-٠٩-٢٢ — سقفٌ مطلق فوق حارس الجيل. الحارس أدناه يقارن ختماً
    // أُخذ **قبل** التجديد بعدّادٍ يزيده التجديد الناجح — فلا يتساويان
    // أبداً ما دام التجديد ينجح. وخادمٌ يمنح توكناً جديداً في كلّ مرّة
    // ثمّ يردّ ٤٠١ عليه (حسابٌ أُوقف، صلاحيّةٌ سُحبت) كان يُدخلنا دورةً
    // لا تنتهي: تجديد ← إعادة ← ٤٠١ ← تجديد… تقصف الخادم وتُجمّد الواجهة.
    final attempts = (failed.extra['__refresh_attempts'] as int?) ?? 0;
    if (attempts >= 2) return null;
    failed.extra['__refresh_attempts'] = attempts + 1;

    if (failed.extra['__retried_after_refresh'] == true &&
        failed.extra['__refresh_gen'] == _refreshGen) {
      return null;
    }
    failed.extra['__retried_after_refresh'] = true;
    failed.extra['__refresh_gen'] = _refreshGen;

    // نلتقط التوكن **قبل** التجديد لنعرف لاحقاً هل تغيّر فعلاً.
    final before = await AuthStorage.readToken();
    final outcome = await _runRefresh();
    if (outcome != RefreshOutcome.ok) {
      // 2026-07-12 fix (v1 parity): refresh فشل حقيقي (شبكة/توكن الأب
      // منتهي). نمسح ونرمي المستخدم لـlogin. سابقاً كان الموظف يمسح
      // فوراً حتى عند 401 عابر بدون refresh — تم الإصلاح بالسماح للـ
      // refresh أوّلاً في AuthApi.refreshToken.
      // الجلسة لا تُمحى إلّا بحكمٍ صريح من الخادم. انقطاعُ شبكةٍ أو
      // مهلةٌ أو حدُّ طلبات ليست دليلاً على موت الجلسة — وكانت تُخرج
      // الموظّف من حسابه وسط عمله.
      if (outcome == RefreshOutcome.networkFailure) return null;
      // 🐛 كان المسح مشروطاً بكون المستخدم موظّفاً — فمديرٌ عاديّ
      // رُفضت جلسته صراحةً لا يُمحى ولا يُطالَب بالدخول أبداً، إذ لا
      // سبيل آخر في التطبيق كلّه إلى شاشة الدخول. الرفض الصريح ينهي
      // الجلسة أيّاً كان صاحبها.
      {
        // 2026-07-14: نمسح كل caches الجلسة عبر SessionManager بدلاً
        // من Auth + Perms فقط — سابقاً كان الأدمن التالي يشوف رواسب
        // (subscribers list، device snapshots) من الجلسة السابقة.
        await SessionManager.clearAllSessionData(unregisterFcm: false);
        authExpiredSignal.value = authExpiredSignal.value + 1;
      }
      return null;
    }
    // كلّ نداءات التطبيق تمرّ على خادمنا (/api/**)، فالتوكن الصحيح هو
    // `token` دائماً — `admin token` للأدمن. والموظّف لا يصل هنا أصلاً:
    // `AuthApi.refreshToken()` تردّ null له، فيمرّ من فرع الطرد أعلاه.
    // ولا يوجد توكن ساسٍ على الجهاز: حُذف في 2026-09-15 لأنّه كان
    // يُكتب ولا يُقرأ (انظر `_kSas4TokenLegacy`).
    //
    // ⚠️ وحارس «لا تُعِد مرّتين» لم يُنقَل إلى هنا في الدمج: هو أعلى
    // في الدالّة بصيغةٍ أقوى — سقفُ محاولاتٍ مطلق فوق حارس الجيل.
    // وضعُ نسخةٍ ثانيةٍ هنا يجعل الأولى ميّتةً ويُخفي أيّهما يعمل.
    final newToken = await AuthStorage.readToken();
    if (newToken == null) return null;
    failed.headers['Authorization'] = 'Bearer $newToken';
    failed.headers['x-auth-token'] = newToken;
    Response? retried;
    try {
      retried = await _dio.fetch(failed);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 retry after refresh failed: $e');
      return null;
    }

    // ⚠️ **الجلسة الشبح.**
    //
    // تجديد الموظّف «ينجح» ولا يُجدّد شيئاً: يكتب في `auth.sas4_token`
    // بينما التوكن المُرسَل هو `auth.token` ولا يُمسّ. فلو اكتفينا بـ
    // `outcome == ok` لَما خرج الموظّف أبداً بعد موت توكنه (٢٤ ساعة)،
    // ولبقي يرى شاشاتٍ فارغة إلى الأبد بلا طلب دخولٍ ولا سبيل تعافٍ.
    //
    // والحكم القاطع: تجديدٌ **لم يغيّر التوكن** ثمّ محاولةٌ عادت ٤٠١
    // ⇒ الجلسة ميتة حقّاً. وهذا ليس تعثّر شبكة، فالخادم ردّ فعلاً.
    final unchanged = before != null && before == newToken;
    if (unchanged && retried.statusCode == 401) {
      await SessionManager.clearAllSessionData(unregisterFcm: false);
      authExpiredSignal.value = authExpiredSignal.value + 1;
      return null;
    }
    return retried;
  }

  Future<RefreshOutcome> _runRefresh() async {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final f = AuthApi.refreshTokenDetailed();
    _refreshing = f;
    try {
      final r = await f;
      // جيلٌ جديد ⇒ التوكن تغيّر ⇒ من استهلك محاولته سابقاً يستحقّ أخرى.
      if (r == RefreshOutcome.ok) _refreshGen++;
      return r;
    } finally {
      _refreshing = null;
    }
  }
}
