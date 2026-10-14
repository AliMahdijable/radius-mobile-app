import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/auth_api.dart';
import 'active_company.dart';
import 'auth_storage.dart';
import 'fcm_service.dart';
import 'permissions_service.dart';
import 'provider_service.dart';
import 'session_manager.dart';

/// Pro: جلسة «موظّفٍ مباشر» — موظّف ايرث لنك يدخل بيوزره وكلمة سرّه
/// (`/api/auth/employee-login`) بلا حساب إيميل ولا اشتراكٍ خاصّ به: يعمل تحت
/// اشتراك مديره. فلا تمرّ جلسته ببوّابة الحساب أبداً — لا عند الإقلاع ولا عند
/// الخروج/الطرد — ووجهته عند انتهائها `EmployeeLoginScreen` لا شاشة الحساب.
///
/// العلامة محفوظةٌ بخيارات خزنة [AuthStorage] نفسها (تُستعاد معها على iOS)،
/// وتُمسح مع الجلسة في [SessionManager.clearAllSessionData].
class EmployeeSession {
  EmployeeSession._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
      synchronizable: true,
      accountName: 'mysvcs_radius_auth',
    ),
  );
  static const _kDirect = 'employee.direct_session';

  /// آخر جلسةٍ على الجهاز كانت موظّفاً مباشراً — **تبقى** بعد الخروج/الطرد،
  /// فيفتح الإقلاع التالي شاشة دخول الموظّف لا شاشة حسابٍ لا يملكه. تُمسح مع
  /// أيّ دخولٍ جديد (ودخول الموظّف وحده يكتبها من جديد)، أو حين يختار المستخدم
  /// طريق الحساب بالرجوع من شاشة الموظّف ([leaveToAccount]).
  static const _kLanding = 'employee.direct_landing';

  /// النصّ الاحتياطيّ لـ`SESSION_SUPERSEDED` إن لم يُرسل الخادم رسالة.
  static const supersededMessage = 'تم الدخول بهذا الحساب من جهازٍ آخر';

  /// الجلسة القائمة موظّفٌ مباشر (ذاكرة: تُضبط عند الدخول، و[restore] عند الإقلاع).
  static bool _active = false;

  /// الجلسة التي انتهت (خروج/طرد/حظر، أو قبل الإقلاع) كانت موظّفاً مباشراً.
  ///
  /// ⚠️ مسح الخروج/الطرد لا يُرجعها `false` أبداً: موجة ٤٠١ متزامنة تستدعي
  /// المسح عدّة مرّات — الأولى تجد العلامة والتالية لا تجدها؛ لو أعادتها
  /// `false` لذهب الموظّف إلى بوّابة الحساب. تُصفَّر فقط بمسح «قبل جلسةٍ
  /// جديدة» (`clearAuth: false`) — الجلسة التالية هي التي تحدّد الوجهة.
  static bool _endedDirect = false;

  /// سبب الطرد يُعرض في شاشة دخول الموظّف (دخولٌ من جهازٍ آخر).
  static String? _kickMessage;

  static bool get isActive => _active;

  /// وجهة الخروج/الطرد: شاشة دخول الموظّف بدل بوّابة الحساب.
  static bool get routeToEmployeeLogin => _active || _endedDirect;

  /// الإقلاع: علامةٌ محفوظة **مع** توكن ⇒ جلسة موظّفٍ مباشر قائمة. وعلامةٌ
  /// بلا توكن بقايا مسحٍ متعثّر ⇒ تُحذف. وجلسةٌ مباشرة انتهت قبل الإقلاع
  /// (علامة الهبوط) ⇒ [routeToEmployeeLogin]. الفشل = ليست مباشرة.
  static Future<bool> restore() async {
    try {
      final r = await Future.wait<String?>([
        _storage.read(key: _kDirect),
        AuthStorage.readToken(),
        _storage.read(key: _kLanding),
      ]);
      final flag = r[0] == '1';
      final hasToken = (r[1] ?? '').isNotEmpty;
      _active = flag && hasToken;
      if (!_active && (flag || r[2] == '1')) _endedDirect = true;
      if (flag && !hasToken) await _storage.delete(key: _kDirect);
    } catch (e) {
      if (kDebugMode) debugPrint('EmployeeSession.restore: $e');
    }
    return _active;
  }

  /// من [SessionManager.clearAllSessionData]. [newSession] = مسحٌ قبل دخولٍ
  /// جديد (`clearAuth: false`): الوجهة تُصفَّر لتحدّدها الجلسة القادمة.
  /// وإلّا فخروجٌ/طرد: تُذكَر إن كانت الجلسة الممسوحة موظّفاً مباشراً.
  static Future<void> clear({bool newSession = false}) async {
    var was = _active;
    _active = false;
    try {
      if (!was && !newSession) was = (await _storage.read(key: _kDirect)) == '1';
      await _storage.delete(key: _kDirect);
      if (newSession) await _storage.delete(key: _kLanding);
    } catch (e) {
      if (kDebugMode) debugPrint('EmployeeSession.clear: $e');
    }
    if (newSession) {
      _endedDirect = false;
      _kickMessage = null;
    } else if (was) {
      _endedDirect = true;
    }
  }

  /// الرجوع من شاشة دخول الموظّف إلى طريق الحساب: اختيارٌ صريح، فلا تُفتح
  /// شاشة الموظّف عند الإقلاع التالي ولا يبقى سبب طردٍ معلّقاً.
  static Future<void> leaveToAccount() async {
    _endedDirect = false;
    _kickMessage = null;
    try {
      await _storage.delete(key: _kLanding);
    } catch (e) {
      if (kDebugMode) debugPrint('EmployeeSession.leaveToAccount: $e');
    }
  }

  /// من المعترض عند `401 {code:'SESSION_SUPERSEDED'}` — قبل المسح والإشارة.
  static void noteSuperseded(String? serverMessage) {
    final m = serverMessage?.trim() ?? '';
    _kickMessage = m.isNotEmpty ? m : supersededMessage;
  }

  /// سبب الطرد — يُقرأ **ولا يُستهلك**: موجة ٤٠١ متزامنة تُطلق إشارة الطرد
  /// عدّة مرّات قبل أن يُزال MainShell، فلو استُهلك في الأولى لاستبدلت
  /// التاليةُ الشاشةَ بـ«انتهت الجلسة». يُمسح مع الدخول التالي أو [leaveToAccount].
  static String? get kickMessage => _kickMessage;

  /// ما بعد `employee-login` الناجح — مسار حفظ جلسة الموظّف نفسه في
  /// `SasLoginFlow.complete` (مسح البقايا ← الجلسة ← الشركة ← الصلاحيّات ←
  /// المزوّد ← FCM)، بلا مخازن كلمات سرّ الساس («شركاتي»/مبدّل المدراء):
  /// يوزر الموظّف ليس دخول ساس، وحفظه هناك يملأ دخول شركةٍ بيوزرٍ لا يصلح لها.
  ///
  /// `false` = تعذّر جلب الصلاحيّات؛ تُمسح الجلسة كلّها (لا موظّفٌ بصلاحيّاتٍ مجهولة).
  static Future<bool> completeLogin(
    LoginSuccess s, {
    required String username,
  }) async {
    await SessionManager.clearAllSessionData(unregisterFcm: false, clearAuth: false);
    await AuthStorage.saveSession(
      token: s.token,
      adminId: s.adminId,
      adminUsername: s.adminUsername,
      displayName: s.displayName,
      autoLogin: true,
      tokenExpiry: s.expiresAt,
      canAccessManagers: s.canAccessManagers,
      canAccessPackages: s.canAccessPackages,
      isEmployee: true,
      sasUrl: '',
    );
    _active = true;
    try {
      await Future.wait([
        _storage.write(key: _kDirect, value: '1'),
        _storage.write(key: _kLanding, value: '1'),
      ]);
    } catch (e) {
      if (kDebugMode) debugPrint('EmployeeSession.write: $e');
    }
    // شريط الشركة: شركة المدير الأب (الكود من معرّفه `earthlink:<idx>`).
    await ActiveCompany.saveFromLogin(
      sasUrl: '',
      adminId: s.adminId,
      loginUsername: username,
      adminUsername: s.adminUsername,
      isEmployee: true,
    );
    // فوراً لا بعد `/api/auth/me`: «قوائم أخرى» تُبنى بشاشات ايرث لنك من أوّل إطار.
    await ProviderService.setProvider('earthlink');
    final ok = await PermissionsService.refreshFromBackend();
    // و`/me` يقول «ليس موظّفاً» ⇒ PermissionsService يفتح كلّ شيء (فرع المدير)
    // — لا يُقبل لجلسةٍ دخلت من باب الموظّف: يُعامَل فشلاً لا صلاحيّاتٍ كاملة.
    if (!ok || !PermissionsService.isEmployee) {
      await SessionManager.clearAllSessionData(unregisterFcm: false);
      return false;
    }
    unawaited(ProviderService.refreshFromBackend());
    unawaited(FcmService.initAfterLogin());
    return true;
  }
}
