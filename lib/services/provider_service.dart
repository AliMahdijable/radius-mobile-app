import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/auth_api.dart';
import 'auth_storage.dart';
import 'permissions_service.dart';

/// مزوّد الساس الحاليّ — `earthlink` لموزِّعي EarthLink، وإلّا فارغ.
///
/// الخادم يميّز مدير EarthLink في `/api/auth/me` (و`provider: 'earthlink'`).
/// التطبيق كان يكتشفه سابقاً من كلّ ردٍّ على حدة (`activation-data`،
/// `extension-options`)؛ لكنّ حجب التبويبات/الشاشات يحتاج علامةً عامّة
/// تُقرأ **متزامنةً** عند بناء قائمة «قوائم أخرى». هذه هي.
///
/// على نسق [PermissionsService]: ذاكرةٌ جاريةٌ + خزنةٌ آمنة + `ValueNotifier`
/// فتُعاد القائمة بناءً عند تغيّر المزوّد. يُمسح عند الخروج (`SessionManager`)
/// فلا يرى المدير التالي تبويبات سابقه، ويُستعاد عند الإقلاع (`main`) فيصحّ
/// الحجب فوراً للدخول التلقائيّ قبل أن يردّ `/api/auth/me`.
class ProviderService {
  ProviderService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  static const _kProvider = 'provider.current';
  static const _kLabel = 'provider.label';

  static String? _provider;

  /// اسم الشركة كما يقوله الخادم (`providerLabel` — الشركات المُضافة وحدها ترسله).
  static String? _label;
  static bool _loaded = false;
  static final ValueNotifier<int> _version = ValueNotifier<int>(0);

  /// جيل الجلسة: يرتفع مع كلّ [clear] — وهو أوّل ما يجري في كلّ خروجٍ وكلّ
  /// دخولٍ أو تبديل (`SessionManager.clearAllSessionData`). ردٌّ سُئل عنه في
  /// جيلٍ سابق يخصّ جلسةً انتهت، فلا يُطبَّق.
  static int _generation = 0;

  /// تنبيهٌ لكلّ مستمع (قائمة «قوائم أخرى») عند تغيّر المزوّد.
  static ValueListenable<int> get changes => _version;

  static bool get isLoaded => _loaded;

  /// الساس الحاليّ EarthLink؟ المصدر الوحيد لحجب شاشات البند ٤ الخاصّة به.
  static bool get isEarthlink => _provider == 'earthlink';

  /// المشروع الوطنيّ (FTTH، admin.ftth.iq) — `provider:'ftth'` من `/api/auth/me`.
  /// ⚠️ الكلمة الحرفيّة في الردّ لا بادئة المعرّف: رمز شركته `ftth-iq`، أمّا
  /// `ftth` في دليل الشركات فساس SAS4 حقيقيّ (فايبر الجزيرة) ومدراؤه بلا provider.
  static bool get isFtth => _provider == 'ftth';

  /// فايبر اكس (OpenRadius، رمز الشركة `fiberx`) — `provider:'fiberx'` من الدخول و`/api/auth/me`. التطبيق خلف مفتاح الخادم
  /// `pro_settings.fiberx_app` (٢٩ أكتوبر): بلاه يُردّ الدخول `fiberx-web-only`. يتكلّم عقود SAS4 العامّة (القائمة، مودل
  /// التفعيل بوضع «فايبر اكس»، الديون من دفترنا)، وما لا يخدمه يُقفل بقدراته (`canonicalPermissions` false).
  static bool get isFiberx => _provider == 'fiberx';

  /// المزوّدون الذين يعرفهم التطبيق باسمهم — وكلّ ما عداهم «شركةٌ مُضافة» ([isKitName]).
  static const knownProviders = {'sas4', 'earthlink', 'ftth', 'fiberx'};

  /// «الشركات المُضافة» (providerKit بالخادم، ٣٠ أكتوبر — نبض وAccessGate أوّلها): كلّ مزوّدٍ يقوله الخادم ليس من
  /// [knownProviders] — كالموقع (`components/kit/kit.ts`) حرفاً. الخادم يخدمها بعقود SAS4 نفسها والمال من دفترنا، وما لا
  /// يخدمه مزوّدها مفتاحه false في قدراتها فلا يظهر (`providerHidesAction`)، ومودل التفعيل بوضع «المزوّد» كفايبر اكس.
  /// التطبيق خلف مفتاح الخادم `pro_settings.<name>_app`: بلاه يُردّ الدخول `<name>-web-only`. شركةٌ جديدة لا تحتاج سطراً هنا.
  static bool isKitName(String? provider) {
    final p = provider?.trim() ?? '';
    return p.isNotEmpty && !knownProviders.contains(p);
  }

  /// الجلسة لشركةٍ مُضافة ([isKitName]).
  static bool get isKit => isKitName(_provider);

  /// اسم الشركة المُضافة كما يقوله الخادم (`providerLabel`)، وإلّا رمزها — للنصوص («غير متاح لحساب نبض بعد»).
  static String get label {
    final l = _label?.trim() ?? '';
    return l.isNotEmpty ? l : (_provider ?? '');
  }

  /// للشركة بوّابة مشتركين (تطبيق MyServices)؟ وسيط البوّابة (١٨ أكتوبر،
  /// الخادم fdcc2d7) يخدم شركات SAS4 كلّها **وايرث لنك** برمز الوكيل وQR؛
  /// وFTTH وحده بلا بوّابة بعد (الخادم لا يصدر له رمز وكيل) — فإعداداتها
  /// تُحفظ ولا يقرؤها أحد (تدقيق البوّابة ٢٠٢٦-١٠-١٧ §2.7).
  static bool get hasSubscriberPortal => !isFtth;

  /// رمز QR/رابط «معلومات المشترك» من نافذة المشترك؟ SAS4 وحده بعد: بطاقة
  /// الرابط (`/api/user-info/<رمز>`) لا تقرأ ايرث لنك (الخادم يردّ رمزه «غير
  /// صالح»)، وتطبيق المشترك المنشور (2.0.3) يدخل بها. والدخول بـQR لايرث لنك
  /// يعمل من تطبيق 2.0.7 وحده (`/api/portal/qr-login`) — فيُفتح هنا معه.
  static bool get hasPortalQrCard => !isEarthlink && !isFtth;

  /// يُستعاد المزوّد المحفوظ للذاكرة — مرّةً عند الإقلاع (`main`/Splash).
  static Future<void> init() async {
    if (_loaded) return;
    try {
      final raw = await _storage.read(key: _kProvider);
      _provider = (raw == null || raw.isEmpty) ? null : raw;
      final lab = await _storage.read(key: _kLabel);
      _label = (lab == null || lab.isEmpty) ? null : lab;
    } catch (e) {
      if (kDebugMode) debugPrint('ProviderService.init failed: $e');
    } finally {
      _loaded = true;
    }
  }

  /// يُجلب المزوّد من `/api/auth/me` بعد الدخول — المصدر الموثوق.
  ///
  /// الفشل (شبكة/جلسة) **لا يمسح** آخر قيمةٍ معروفة: فقط النجاح الصريح
  /// يضبط القيمة (قد تكون `null` لمديرٍ ليس EarthLink، فتُخفى شاشاته).
  ///
  /// ⚠️ والنجاح وحده لا يكفي: يلزم أن يكون الردّ عن **الجلسة الحاليّة**.
  /// 🐛 السباق (مراجعة ٢٠٢٦-١٠-١٣): `/me` مالكِ ايرث لنك في الطريق ← يبدّل
  /// المستخدم الشركة إلى مدير ساس سوبر (`SasLoginFlow.complete`: مسحٌ ←
  /// قدرات السوبر ← تحديثه هو يردّ provider=null) ← يصل الردّ القديم فيكتب
  /// `earthlink` وقدرات ايرث لنك المقيَّدة على مدير الساس، وفي الخزنة أيضاً؛
  /// والتحديثات اللاحقة تُصلح المزوّد ولا تُصلح القدرات أبداً. فنلتقط التوكن
  /// والمعرّف وجيل الجلسة **قبل** السؤال، ونُهمل الردّ إن تغيّر أيٌّ منها.
  /// (الجيل يكشف ما لا يكشفه التوكن: ردٌّ يصل بعد المسح وقبل حفظ الجلسة
  /// الجديدة، والتوكن القديم ما زال في الخزنة.) الإهمال كالفشل: آخر قيمة تبقى.
  static Future<void> refreshFromBackend() async {
    final generation = _generation;
    final asked = await _currentSession();
    if (asked == null) return; // لا جلسة (أو تعذّرت الخزنة): لا سؤال
    final r = await AuthApi.fetchProvider();
    if (!r.ok) return;
    final now = await _currentSession();
    if (generation != _generation || now == null || now != asked) return;
    // قدرات **المدير** (لا الموظّف) محفوظةٌ من لحظة الدخول، فما يغيّره الخادم أو
    // الساس بعده لا يظهر بلا خروج ودخول: زرٌّ فعّله الخادم لايرث لنك («إضافة
    // مشترك»)، أو مفتاحٌ أخرجه من خريطة الساس (`reports.financial`، ١٨ أكتوبر —
    // كان يقفل رصيد مديرٍ فرعيّ وإيراداته). نحدّثها من `/api/auth/me` لكلّ مدير:
    // SAS4 الأصل والبعيد وايرث لنك وFTTH — بشروطٍ صريحة كلّها:
    //  • الردّ يقول isEmployee=false، والجلسة ليست موظّفاً محلّيّاً؛
    //  • هويّة الردّ (`user.id`) = المعرّف المحفوظ للجلسة حرفيّاً (`42` للأصل،
    //    `next-gen:175` للبعيد، `earthlink:<idx>`) — ردٌّ بلا هويّة أو عن غيرها
    //    لا يُكتب على هذه الجلسة؛
    //  • خريطةٌ فيها مسموحٌ واحدٌ على الأقلّ: خريطةٌ كلّها false (ساسٌ ردّ `/auth`
    //    بلا قائمة صلاحيّات) غيابُ معلومةٍ لا معلومة، ولا يُقفل بها كلّ شيء —
    //    قوائم الساس لا تُصدَّق لإضافة أقفال.
    // ما لا يستوفيها كالفشل: آخر قدراتٍ معروفة تبقى.
    //
    // ⚠️ لا `await` بين الفحص أعلاه والكتابتين: كلتاهما تبدأ في الخطوة نفسها
    // وتضبط الذاكرة قبل أوّل انتظارٍ فيها، فلا تتسلّل جلسةٌ جديدة بين القرار
    // وتطبيقه. (`Future.wait` يبدأ عناصره بالترتيب، في الخطوة نفسها.)
    final canon = r.canonical;
    await Future.wait<void>([
      _set(r.provider, label: r.providerLabel),
      if (r.isEmployee == false &&
          !PermissionsService.isEmployee &&
          r.userId != null &&
          r.userId == now.adminId &&
          canon != null &&
          canon.values.any((allowed) => allowed))
        PermissionsService.setManagerCapabilities(
          isSuperAdmin: r.isSuperAdmin,
          canonical: canon,
        ),
    ]);
  }

  /// الإقلاع بجلسةٍ محفوظة (`SplashScreen`، دخولٌ تلقائيّ): [refreshFromBackend]
  /// لكلّ جلسة — مديراً بأيّ مزوّد، أو موظّفاً — بعد [tokenReady] (تجديد التوكن
  /// إن قارب الانتهاء). `/api/auth/*` يتخطّاه معترض التجديد، فتوكنٌ انتهى قبل
  /// الإقلاع يُرفض بلا إعادة — وتحديث القدرات يضيع حتى الإقلاع التالي.
  /// والتعثّر في التجديد لا يمنع السؤال: يُسأل بما في الخزنة.
  static Future<void> refreshOnColdStart(Future<void> tokenReady) async {
    try {
      await tokenReady;
    } catch (e) {
      if (kDebugMode) debugPrint('ProviderService.refreshOnColdStart: $e');
    }
    await refreshFromBackend();
  }

  /// الجلسة كما في الخزنة الآن: توكنها ومعرّف مديرها. `null` بلا جلسة أو إن
  /// تعذّرت القراءة — فلا يُسأل الخادم، ولا يُطبَّق ردٌّ لا نعرف صاحبه.
  static Future<({String token, String? adminId})?> _currentSession() async {
    try {
      final (token, adminId) =
          await (AuthStorage.readToken(), AuthStorage.readAdminId()).wait;
      if (token == null || token.isEmpty) return null;
      return (token: token, adminId: adminId);
    } catch (e) {
      if (kDebugMode) debugPrint('ProviderService._currentSession failed: $e');
      return null;
    }
  }

  /// يُضبط المزوّد مباشرةً حين يعرفه ردّ الدخول نفسه (دخول موظّف ايرث لنك:
  /// `provider:'earthlink'`) — فلا تنتظر الواجهة نداء `/api/auth/me`.
  static Future<void> setProvider(String? provider, {String? label}) => _set(provider, label: label);

  static Future<void> _set(String? provider, {String? label}) async {
    final p = (provider == null || provider.trim().isEmpty) ? null : provider.trim();
    // الاسم للشركات المُضافة وحدها (المعروفة تُسمّى بنصوص التطبيق)؛ ويتبع المزوّد: مزوّدٌ آخر بلا اسم ⇒ لا اسم قديم.
    final l = (p != null && isKitName(p) && label != null && label.trim().isNotEmpty) ? label.trim() : null;
    if (p == _provider && l == _label) return;
    _provider = p;
    _label = l;
    _loaded = true;
    try {
      if (p == null) {
        await _storage.delete(key: _kProvider);
      } else {
        await _storage.write(key: _kProvider, value: p);
      }
      if (l == null) {
        await _storage.delete(key: _kLabel);
      } else {
        await _storage.write(key: _kLabel, value: l);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ProviderService._set failed: $e');
    }
    _version.value = _version.value + 1;
  }

  /// تُستدعى من فلو الخروج (`SessionManager`) — لا يرى الحساب التالي مزوّد سابقه.
  static Future<void> clear() async {
    _generation++; // أيّ ردٍّ في الطريق صار لجلسةٍ منتهية
    _provider = null;
    _label = null;
    try {
      await _storage.delete(key: _kProvider);
      await _storage.delete(key: _kLabel);
    } catch (e) {
      if (kDebugMode) debugPrint('ProviderService.clear failed: $e');
    }
    _version.value = _version.value + 1;
  }

  /// منفذٌ للاختبار وحده: يضبط المزوّد في الذاكرة بلا خزنةٍ آمنة
  /// (الخزنة لا تعمل في `flutter test`).
  @visibleForTesting
  static void debugSet(String? provider, {String? label}) {
    _loaded = true;
    _provider = (provider == null || provider.isEmpty) ? null : provider;
    _label = label;
    _version.value = _version.value + 1;
  }
}
