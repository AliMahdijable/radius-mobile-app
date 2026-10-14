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

  static String? _provider;
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

  /// يُستعاد المزوّد المحفوظ للذاكرة — مرّةً عند الإقلاع (`main`/Splash).
  static Future<void> init() async {
    if (_loaded) return;
    try {
      final raw = await _storage.read(key: _kProvider);
      _provider = (raw == null || raw.isEmpty) ? null : raw;
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
    // مدير EarthLink (لا موظّف): صلاحيّاته محفوظةٌ من لحظة الدخول، فزرٌّ يُفعّله
    // الخادم لاحقاً (مثل «إضافة مشترك») لا يظهر بلا خروج ودخول. نحدّثها من
    // `/api/auth/me` — بشرطٍ صريح: ردٌّ يقول isEmployee=false، وجلسةٌ ليست
    // موظّفاً محلّيّاً، ومعرّفها المحفوظ الآن معرّف مالك ايرث لنك. مدراء SAS4
    // لا يُمَسّون (provider ليس earthlink، ومعرّفهم بلا البادئة).
    //
    // ⚠️ لا `await` بين الفحص أعلاه والكتابتين: كلتاهما تبدأ في الخطوة نفسها
    // وتضبط الذاكرة قبل أوّل انتظارٍ فيها، فلا تتسلّل جلسةٌ جديدة بين القرار
    // وتطبيقه. (`Future.wait` يبدأ عناصره بالترتيب، في الخطوة نفسها.)
    final canon = r.canonical;
    await Future.wait<void>([
      _set(r.provider),
      if (r.provider == 'earthlink' &&
          r.isEmployee == false &&
          !PermissionsService.isEmployee &&
          (now.adminId?.startsWith('earthlink:') ?? false) &&
          canon != null &&
          canon.isNotEmpty)
        PermissionsService.setManagerCapabilities(
          isSuperAdmin: r.isSuperAdmin,
          canonical: canon,
        ),
    ]);
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
  static Future<void> setProvider(String? provider) => _set(provider);

  static Future<void> _set(String? provider) async {
    final p = (provider == null || provider.trim().isEmpty) ? null : provider.trim();
    if (p == _provider) return;
    _provider = p;
    _loaded = true;
    try {
      if (p == null) {
        await _storage.delete(key: _kProvider);
      } else {
        await _storage.write(key: _kProvider, value: p);
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
    try {
      await _storage.delete(key: _kProvider);
    } catch (e) {
      if (kDebugMode) debugPrint('ProviderService.clear failed: $e');
    }
    _version.value = _version.value + 1;
  }

  /// منفذٌ للاختبار وحده: يضبط المزوّد في الذاكرة بلا خزنةٍ آمنة
  /// (الخزنة لا تعمل في `flutter test`).
  @visibleForTesting
  static void debugSet(String? provider) {
    _loaded = true;
    _provider = (provider == null || provider.isEmpty) ? null : provider;
    _version.value = _version.value + 1;
  }
}
