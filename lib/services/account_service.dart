import 'dart:async';
import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import '../api/account_api.dart';
import '../firebase_options.dart';
import 'company_creds_store.dart';
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

  static bool get available => NotificationService.firebaseReady;

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  static User? get currentUser => available ? _auth.currentUser : null;

  /// الحساب صالحٌ للمتابعة: موجود، وبريده مؤكَّد. (Google/Apple مؤكَّدان أصلاً.)
  static bool get isReady {
    final u = currentUser;
    return u != null && (u.emailVerified || _isFederated(u));
  }

  static bool _isFederated(User u) => u.providerData
      .any((p) => p.providerId == 'google.com' || p.providerId == 'apple.com');

  /// توكن الحساب للخادم. [force] يجدّده (بعد تأكيد البريد مثلاً كي يحمل
  /// `email_verified`). null = لا حساب.
  static Future<String?> idToken({bool force = false}) async {
    final u = currentUser;
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

  /// يفتح نافذة Google. يُرجع null إن ألغى المستخدم.
  static Future<User?> signInWithGoogle() async {
    await _initGoogle();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(code: 'missing-id-token');
    }
    try {
      final cred = await _auth
          .signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      return cred.user;
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
      return cred.user;
    }
  }

  // ───────────── Apple ─────────────

  /// زرّ Apple يظهر على أجهزة Apple وحدها (iOS/macOS) — إرشاد App Store 4.8.
  /// أندرويد والويب يبقيان كما هما (Google + إيميل).
  static bool get appleSignInAvailable =>
      !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  static AppleAuthProvider _appleProvider() =>
      AppleAuthProvider()..addScope('email')..addScope('name');

  /// إلغاء المستخدم لنافذة Apple (ASAuthorizationError.canceled ← `canceled`).
  static bool _isAppleCancel(Object e) {
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
  static Future<User?> signInWithApple() async {
    final UserCredential cred;
    try {
      cred = await _auth.signInWithProvider(_appleProvider());
    } catch (e) {
      if (_isAppleCancel(e)) return null;
      rethrow;
    }
    final user = cred.user;
    if (user != null) await _applyAppleName(user, cred);
    return user;
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
    final u = currentUser;
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
        if (_isAppleCancel(e)) {
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

  // ───────────── إيميل + كلمة سرّ ─────────────

  static Future<User?> signInWithEmail(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
    return cred.user;
  }

  static Future<User?> signUpWithEmail(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    await cred.user?.sendEmailVerification();
    return cred.user;
  }

  static Future<void> resendVerification() async =>
      currentUser?.sendEmailVerification();

  /// يعيد قراءة الحساب من Firebase (بعد ضغط رابط التأكيد) ويجدّد التوكن.
  static Future<bool> reloadVerified() async {
    final u = currentUser;
    if (u == null) return false;
    await u.reload();
    final fresh = _auth.currentUser;
    if (fresh != null && fresh.emailVerified) {
      await fresh.getIdToken(true);
      return true;
    }
    return false;
  }

  static Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  /// خروجٌ كامل: الساس + كلمات سرّ الشركات + الحسابات المحفوظة + Firebase.
  static Future<void> signOut() async {
    await SessionManager.clearAllSessionData();
    await CompanyCredsStore.clearAll();
    await SavedProfilesStore.clearAll();
    try {
      if (_googleReady) await GoogleSignIn.instance.signOut();
    } catch (_) {/* خروج Google لا يمنع خروج الحساب */}
    if (available) await _auth.signOut();
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
