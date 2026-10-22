import 'dart:async';
import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import '../api/account_api.dart';
import '../core/platform/app_platform.dart';
import '../firebase_options.dart';
import 'account_user.dart';
import 'client_diag.dart';
import 'company_creds_store.dart';
import 'desktop_account_auth.dart';
import 'desktop_browser_login.dart';
import 'notification_service.dart';
import 'saved_profiles_store.dart';
import 'session_manager.dart';

/// Pro البند ٤ — طبقة الحساب (الطبقة ①): حساب إيميل عبر Firebase Auth.
///
/// قبل أيّ ساس: المستخدم يدخل بحساب Google أو إيميل+كلمة سرّ (بريدٌ مؤكَّد).
/// الخادم يتحقّق من توكن Firebase (`x-account-token`) عند دخول الساس وتجديد
/// توكنه، ومنه يعرف الاشتراك (تجربة/كود) والشركات المربوطة.
///
/// ⚠️ مفاتيح هذه الطبقة **ليست** في `auth.*` — ذاك يُمسح عند كلّ خروجٍ من
/// الساس، والحساب يجب أن يبقى. خروج الحساب نفسه يمسح كلّ شيء (الساس +
/// كلمات سرّ الشركات المحفوظة) حتى لا يرى حسابٌ آخر على الجهاز شركات الأوّل.
class AccountService {
  AccountService._();

  /// ويندوز: الحساب عبر [DesktopAccountAuth] (واجهة Firebase على الإنترنت) — متاحٌ دائماً.
  static bool get available => AppPlatform.isDesktop || NotificationService.firebaseReady;

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  /// مستخدم Firebase على الهاتف (للعمليّات التي تحتاجه بعينه). null على ويندوز.
  static User? get _firebaseUser =>
      !AppPlatform.isDesktop && NotificationService.firebaseReady ? _auth.currentUser : null;

  static AccountUser? get currentUser {
    if (AppPlatform.isDesktop) return DesktopAccountAuth.currentUser;
    final u = _firebaseUser;
    return u == null ? null : AccountUser.fromFirebase(u);
  }

  /// الحساب صالحٌ للمتابعة: موجود، وبريده مؤكَّد. (Google/Apple مؤكَّدان أصلاً.)
  static bool get isReady {
    final u = currentUser;
    return u != null && (u.emailVerified || u.isFederated);
  }

  /// توكن الحساب للخادم. [force] يجدّده (بعد تأكيد البريد مثلاً كي يحمل
  /// `email_verified`). null = لا حساب.
  static Future<String?> idToken({bool force = false}) async {
    if (AppPlatform.isDesktop) {
      try {
        return await DesktopAccountAuth.idToken(force: force)
            .timeout(const Duration(seconds: 12));
      } catch (e) {
        if (kDebugMode) debugPrint('🔴 account idToken (desktop): $e');
        return null;
      }
    }
    final u = _firebaseUser;
    if (u == null) return null;
    try {
      // بلا سقف كان زرّ الدخول يدور بلا نهاية إن تعثّر تجديد التوكن عند جوجل
      // (توكنٌ عمره ساعة ← تجديدٌ بالشبكة). شاشة الدخول تُسخّنه مسبقاً.
      return await u.getIdToken(force).timeout(const Duration(seconds: 12));
    } catch (e) {
      if (kDebugMode) debugPrint('🔴 account idToken: $e');
      return null;
    }
  }

  // ───────────── Google ─────────────

  static bool _googleReady = false;

  static Future<void> _initGoogle() async {
    if (_googleReady) return;
    await GoogleSignIn.instance.initialize(
      // أندرويد يقرأ default_web_client_id من google-services.json تلقائيّاً؛
      // iOS يحتاج معرّف عميله صراحةً.
      clientId: !kIsWeb && Platform.isIOS
          ? DefaultFirebaseOptions.ios.iosClientId
          : null,
    );
    _googleReady = true;
  }

  /// قرار ما بعد رفض نافذة Google الأصليّة (Credential Manager بأندرويد).
  ///
  /// 🐛 بلاغ ٢٠٢٦-١٠-١٦: على أجهزةٍ بعينها (تكنو/هونر…) يظهر اختيار الحساب ثمّ يُرجع
  /// Credential Manager «إلغاء» بعد النقر — لا رسالة ولا دخول. البصمة سليمة (زبائن
  /// دخلوا بـGoogle من أندرويد المتجر)، فالعطل بمسار الجهاز نفسه:
  /// • إلغاء/مقاطعة ⇒ [GoogleFailAction.cancel]: صامتٌ كما كان (قد يكون إلغاءً حقيقيّاً)،
  ///   والشاشة تعرض بعده «ادخل عبر المتصفّح».
  /// • عطلٌ آخر بأندرويد (إعداد المزوّد/غير مدعوم/مجهول) ⇒ [GoogleFailAction.browser]:
  ///   مسار المتصفّح تلقائيّاً — لا يمرّ بـCredential Manager أصلاً.
  /// • iOS: الرمي كما كان (يعمل — ٣٣ دخولاً بـGoogle من الآيفون بعشرة أيّام).
  @visibleForTesting
  static GoogleFailAction googleFailAction(GoogleSignInExceptionCode code,
      {required bool android}) {
    if (code == GoogleSignInExceptionCode.canceled ||
        code == GoogleSignInExceptionCode.interrupted) {
      return GoogleFailAction.cancel;
    }
    return android ? GoogleFailAction.browser : GoogleFailAction.rethrowError;
  }

  /// يفتح نافذة Google. يُرجع null إن ألغى المستخدم (أو أُلغيت على جهازٍ معطوب —
  /// الشاشة تعرض بعدها «عبر المتصفّح» بأندرويد).
  ///
  /// ويندوز: لا مكتبة Google له ⇒ «الدخول عبر المتصفّح» ([DesktopBrowserLogin]).
  static Future<AccountUser?> signInWithGoogle() async {
    if (AppPlatform.isDesktop) return _desktopBrowserSignIn();
    await _initGoogle();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      final android = !kIsWeb && Platform.isAndroid;
      // نصّ Credential Manager الحقيقيّ ونوع الجهاز — يصلان الخادم بلا هويّة (ClientDiag).
      if (android) {
        ClientDiag.report('google_signin', code: e.code.name, message: e.description);
      }
      switch (googleFailAction(e.code, android: android)) {
        case GoogleFailAction.cancel:
          return null;
        case GoogleFailAction.browser:
          return signInWithGoogleWeb();
        case GoogleFailAction.rethrowError:
          rethrow;
      }
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(code: 'missing-id-token');
    }
    try {
      final cred = await _auth
          .signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      return _wrap(cred.user);
    } on FirebaseAuthException catch (e) {
      // رمزٌ مخزَّن منتهٍ: خدمات Google تحكم صلاحيّته بساعة الجهاز، فساعةٌ متأخّرة (محاكي بعد نوم
      // المضيف مثلاً) تعطي رمزاً انتهى فعلاً فيرفضه Firebase بـinvalid-credential. نمسح حالة
      // الاعتماد ونطلب رمزاً جديداً مرّةً واحدة.
      if (e.code != 'invalid-credential') rethrow;
      await GoogleSignIn.instance.signOut();
      final String? fresh;
      try {
        fresh = (await GoogleSignIn.instance.authenticate()).authentication.idToken;
      } on GoogleSignInException catch (g) {
        if (g.code == GoogleSignInExceptionCode.canceled ||
            g.code == GoogleSignInExceptionCode.interrupted) {
          return null; // ألغى المستخدم نافذة الإعادة — كإلغاء الأولى
        }
        rethrow;
      }
      if (fresh == null) rethrow;
      final cred = await _auth
          .signInWithCredential(GoogleAuthProvider.credential(idToken: fresh));
      return _wrap(cred.user);
    }
  }

  static AccountUser? _wrap(User? u) => u == null ? null : AccountUser.fromFirebase(u);

  /// ويندوز: دخول المتصفّح الجاري — الشاشة تعرض «افتح الصفحة مرّةً أخرى» و«إلغاء».
  static DesktopBrowserLogin? desktopLogin;

  static Future<AccountUser?> _desktopBrowserSignIn() async {
    final login = DesktopBrowserLogin();
    desktopLogin = login;
    try {
      final token = await login.run();
      if (token == null) return null;
      return await DesktopAccountAuth.signInWithCustomToken(token);
    } finally {
      if (identical(desktopLogin, login)) desktopLogin = null;
    }
  }

  /// Google عبر المتصفّح (Firebase يفتح Custom Tab لصفحة Google ثمّ يعود) — بديلٌ لا يمرّ
  /// بـCredential Manager، فيعمل على أجهزةٍ يُلغى فيها المسار الأصليّ صامتاً. يُرجع null إن
  /// أغلق المستخدم النافذة.
  static Future<AccountUser?> signInWithGoogleWeb() async {
    if (AppPlatform.isDesktop) return _desktopBrowserSignIn();
    try {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      final cred = await _auth.signInWithProvider(provider);
      return _wrap(cred.user);
    } catch (e) {
      if (_isProviderCancel(e)) return null;
      ClientDiag.report(
        'google_signin_web',
        code: e is FirebaseAuthException ? e.code : e.runtimeType.toString(),
        message: e is FirebaseAuthException ? e.message : null,
      );
      rethrow;
    }
  }

  // ───────────── Apple ─────────────

  /// زرّ Apple يظهر على أجهزة Apple وحدها (iOS/macOS) — إرشاد App Store 4.8.
  /// أندرويد والويب يبقيان كما هما (Google + إيميل).
  static bool get appleSignInAvailable =>
      !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  static AppleAuthProvider _appleProvider() =>
      AppleAuthProvider()..addScope('email')..addScope('name');

  /// إلغاء المستخدم لنافذة Apple (ASAuthorizationError.canceled ← `canceled`) أو لنافذة
  /// المتصفّح (Google عبر المتصفّح ← `web-context-canceled`).
  static bool _isProviderCancel(Object e) {
    final code = e is FirebaseAuthException
        ? e.code
        : e is PlatformException
            ? e.code
            : null;
    return code != null &&
        const {
          'canceled',
          'cancelled',
          'web-context-canceled',
          'web-context-cancelled',
          'user-cancelled',
        }.contains(code.toLowerCase());
  }

  /// يفتح نافذة Apple الأصليّة (Firebase يولّد الـnonce ويتحقّق منه). يُرجع
  /// null إن ألغى المستخدم. ما بعد الدخول هو نفسه مسار Google: الشاشة تنتقل
  /// إلى بوّابة الحساب، وهي تستدعي `bootstrap` (إنشاء الحساب + التجربة).
  static Future<AccountUser?> signInWithApple() async {
    final UserCredential cred;
    try {
      cred = await _auth.signInWithProvider(_appleProvider());
    } catch (e) {
      if (_isProviderCancel(e)) return null;
      rethrow;
    }
    final user = cred.user;
    if (user != null) await _applyAppleName(user, cred);
    return _wrap(_auth.currentUser ?? user);
  }

  /// Apple يعطي الاسم في **أوّل** دخولٍ فقط. Firebase يمرّره للخادم غالباً،
  /// فإن بقي الملفّ بلا اسم نأخذه ممّا رجع ونكتبه. فشله لا يمنع الدخول.
  static Future<void> _applyAppleName(User user, UserCredential cred) async {
    try {
      if ((user.displayName ?? '').trim().isNotEmpty) return;
      String? name;
      for (final p in user.providerData) {
        if (p.providerId == 'apple.com' && (p.displayName ?? '').trim().isNotEmpty) {
          name = p.displayName!.trim();
          break;
        }
      }
      final profile = cred.additionalUserInfo?.profile;
      if (name == null && profile != null) {
        final raw = profile['name'] ?? profile['fullName'] ?? profile['displayName'];
        if (raw is String && raw.trim().isNotEmpty) {
          name = raw.trim();
        } else if (raw is Map) {
          final full = [raw['firstName'], raw['lastName']]
              .whereType<String>()
              .map((x) => x.trim())
              .where((x) => x.isNotEmpty)
              .join(' ');
          if (full.isNotEmpty) name = full;
        }
      }
      if (name == null) return;
      await user.updateDisplayName(name).timeout(const Duration(seconds: 8));
      await user.reload().timeout(const Duration(seconds: 8));
    } catch (e) {
      if (kDebugMode) debugPrint('🟠 apple display name: $e');
    }
  }

  // ───────────── حذف الحساب ─────────────

  /// حذف الحساب نهائيّاً من داخل التطبيق (إرشاد App Store 5.1.1(v)).
  ///
  /// ١) حساب Apple: إعادة توثيقٍ بنافذة Apple للحصول على رمز التفويض ثمّ
  ///    إبطال رموز Apple (`revokeTokenWithAuthorizationCode`) — فشله يُسجَّل
  ///    ولا يوقف الحذف؛ أمّا إلغاء المستخدم للنافذة فيوقفه (لم يؤكّد).
  /// ٢) `AccountApi.deleteAccount()` — الخادم يحذف الحساب وبياناته.
  /// ٣) خروجٌ كامل كمسار [signOut] (الساس + الشركات + المحفوظات + Google + Firebase).
  ///
  /// يرمي [AccountDeletionException] برسالةٍ جاهزةٍ للعرض عند الفشل.
  static Future<void> deleteCurrentAccount() async {
    if (AppPlatform.isDesktop) return _deleteDesktopAccount();
    final u = _firebaseUser;
    if (u == null) {
      throw AccountDeletionException('account.err_signed_out'.tr());
    }

    // ١) Apple: إبطال الرموز قبل الحذف (بعده لا مستخدم يُعاد توثيقه).
    final isApple = u.providerData.any((p) => p.providerId == 'apple.com');
    if (isApple && appleSignInAvailable) {
      String? code;
      try {
        final cred = await u.reauthenticateWithProvider(_appleProvider());
        code = cred.additionalUserInfo?.authorizationCode;
      } catch (e) {
        if (_isProviderCancel(e)) {
          throw AccountDeletionException('account.delete_cancelled'.tr(), cancelled: true);
        }
        debugPrint('account delete: apple reauth failed: '
            '${e is FirebaseAuthException ? e.code : e.runtimeType}');
      }
      if (code != null && code.isNotEmpty) {
        try {
          await _auth
              .revokeTokenWithAuthorizationCode(code)
              .timeout(const Duration(seconds: 15));
        } catch (e) {
          debugPrint('account delete: apple revoke failed: '
              '${e is FirebaseAuthException ? e.code : e.runtimeType}');
        }
      }
    }

    // ٢) الخادم.
    await _deleteOnServer();

    // احتياط: إن لم يحذف الخادم مستخدم Firebase نفسه نحذفه من هنا. «غير موجود»
    // (حذفه الخادم) أو «يتطلّب دخولاً حديثاً» لا يُفشلان الحذف — بيانات الحساب حُذفت.
    try {
      await u.delete().timeout(const Duration(seconds: 10));
    } catch (_) {/* حذفه الخادم أصلاً أو تعذّر — لا يمنع الخروج */}

    // Google: فكّ ربط التطبيق بالحساب (إن وُجد) قبل الخروج الكامل.
    if (u.providerData.any((p) => p.providerId == 'google.com')) {
      try {
        await _initGoogle();
        await GoogleSignIn.instance.disconnect().timeout(const Duration(seconds: 8));
      } catch (_) {/* لا يمنع الخروج */}
    }

    // ٣) نفس مسار الخروج: يمسح كلّ ما هو محلّيّ ثمّ Google وFirebase.
    try {
      await signOut();
    } catch (e) {
      debugPrint('account delete: local sign-out failed: ${e.runtimeType}');
      try {
        if (available) await _auth.signOut();
      } catch (_) {}
    }
  }

  static Future<void> _deleteOnServer() async {
    try {
      await AccountApi.deleteAccount();
    } on AccountApiException catch (e) {
      final m = e.message;
      throw AccountDeletionException(
          m.startsWith('account.') ? m.tr() : (m.isNotEmpty ? m : 'account.delete_failed'.tr()));
    } catch (e) {
      debugPrint('account delete: server failed: ${e.runtimeType}');
      throw AccountDeletionException('account.delete_failed'.tr());
    }
  }

  /// ويندوز: الخادم ثمّ مستخدم Firebase (واجهته على الإنترنت) ثمّ الخروج الكامل.
  static Future<void> _deleteDesktopAccount() async {
    if (DesktopAccountAuth.currentUser == null) {
      throw AccountDeletionException('account.err_signed_out'.tr());
    }
    await _deleteOnServer();
    try {
      await DesktopAccountAuth.deleteUser().timeout(const Duration(seconds: 10));
    } catch (_) {/* حذفه الخادم أصلاً أو تعذّر — لا يمنع الخروج */}
    await signOut();
  }

  // ───────────── إيميل + كلمة سرّ ─────────────

  static Future<AccountUser?> signInWithEmail(String email, String password) async {
    if (AppPlatform.isDesktop) return DesktopAccountAuth.signInWithPassword(email, password);
    final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
    return _wrap(cred.user);
  }

  static Future<AccountUser?> signUpWithEmail(String email, String password) async {
    if (AppPlatform.isDesktop) return DesktopAccountAuth.signUp(email, password);
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    await cred.user?.sendEmailVerification();
    return _wrap(cred.user);
  }

  static Future<void> resendVerification() async {
    if (AppPlatform.isDesktop) return DesktopAccountAuth.sendVerification();
    await _firebaseUser?.sendEmailVerification();
  }

  /// يعيد قراءة الحساب من Firebase (بعد ضغط رابط التأكيد) ويجدّد التوكن.
  static Future<bool> reloadVerified() async {
    if (AppPlatform.isDesktop) return DesktopAccountAuth.reloadVerified();
    final u = _firebaseUser;
    if (u == null) return false;
    await u.reload();
    final fresh = _auth.currentUser;
    if (fresh != null && fresh.emailVerified) {
      await fresh.getIdToken(true);
      return true;
    }
    return false;
  }

  static Future<void> sendPasswordReset(String email) => AppPlatform.isDesktop
      ? DesktopAccountAuth.sendPasswordReset(email)
      : _auth.sendPasswordResetEmail(email: email.trim());

  /// خروجٌ كامل: الساس + كلمات سرّ الشركات + الحسابات المحفوظة + Firebase.
  static Future<void> signOut() async {
    await SessionManager.clearAllSessionData();
    await CompanyCredsStore.clearAll();
    await SavedProfilesStore.clearAll();
    try {
      if (_googleReady) await GoogleSignIn.instance.signOut();
    } catch (_) {/* خروج Google لا يمنع خروج الحساب */}
    if (AppPlatform.isDesktop) {
      await DesktopAccountAuth.signOut();
    } else if (available) {
      await _auth.signOut();
    }
  }

  /// رسالة عربيّة لأخطاء Firebase Auth الشائعة.
  static String messageFor(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'account.err_invalid_email';
        case 'user-disabled':
          return 'account.err_user_disabled';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
        case 'INVALID_LOGIN_CREDENTIALS':
          return 'account.err_wrong_credentials';
        case 'email-already-in-use':
          return 'account.err_email_in_use';
        case 'weak-password':
          return 'account.err_weak_password';
        case 'too-many-requests':
          return 'account.err_too_many';
        case 'network-request-failed':
          return 'account.err_network';
        case 'account-exists-with-different-credential':
          return 'account.err_other_provider';
      }
    }
    if (e is GoogleSignInException) return 'account.err_google';
    if (e is DesktopLoginException) {
      return e.message.startsWith('account.') ? e.message : 'account.err_generic';
    }
    return 'account.err_generic';
  }
}

/// فشل حذف الحساب — [message] نصٌّ جاهزٌ للعرض (مترجَم، عربيّ افتراضيّاً).
/// [cancelled] = أغلق المستخدم نافذة Apple فلم يُحذف شيء (يُكفى بتنبيهٍ هادئ).
class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;

  @override
  String toString() => message;
}

/// ما يُفعل بعد رفض نافذة Google الأصليّة — [AccountService.googleFailAction].
enum GoogleFailAction { cancel, browser, rethrowError }
