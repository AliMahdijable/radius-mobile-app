import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
      return await u.getIdToken(force);
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
    final cred = await _auth
        .signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
    return cred.user;
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
