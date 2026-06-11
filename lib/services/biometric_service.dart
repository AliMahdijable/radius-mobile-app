import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// قفل التطبيق بالبصمة / Face ID. التفعيل اختياري — لو الجهاز ما
/// عنده biometrics مسجلة، الـtoggle يبقى معطّلاً.
///
/// التخزين: مفتاح `bio.enabled` في الـsecure storage (مستقل عن
/// auth.* عشان ما ينمسح عند تسجيل الخروج). نقفل التطبيق عند فتحه
/// لو enabled = true و canAuthenticate = true.
class BiometricService {
  BiometricService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  static const _kEnabled = 'bio.enabled';
  static final LocalAuthentication _auth = LocalAuthentication();

  /// true لو الجهاز يدعم البصمة وعنده على الأقل وحدة مسجلة.
  static Future<bool> canAuthenticate() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final available = await _auth.canCheckBiometrics;
      return available;
    } on PlatformException {
      return false;
    }
  }

  /// أنواع الـbiometrics المتاحة (Face ID / Fingerprint / Iris).
  /// نستعملها للـlabel في الـsettings.
  static Future<List<BiometricType>> available() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return const [];
    }
  }

  static Future<bool> isEnabled() async {
    final v = await _storage.read(key: _kEnabled);
    return v == '1';
  }

  /// قبل التفعيل، نطلب من المستخدم يمسح بصمته كـsanity check —
  /// لو فشل ما نفعّل (يمنع الـlockout بسبب bio ما يشتغل).
  static Future<({bool ok, String? reason})> enable() async {
    if (!await canAuthenticate()) {
      return (ok: false, reason: 'البصمة غير متاحة على هذا الجهاز');
    }
    final passed = await authenticate(
      reason: 'تأكد البصمة قبل تفعيل القفل',
    );
    if (!passed) return (ok: false, reason: 'لم يتم التحقق');
    await _storage.write(key: _kEnabled, value: '1');
    return (ok: true, reason: null);
  }

  static Future<void> disable() => _storage.delete(key: _kEnabled);

  /// يُستدعى من الـSplash عند فتح التطبيق لو الـbiometric مفعّل.
  /// يرجع true لو نجحت المصادقة أو الـbio غير مفعّل أصلاً.
  static Future<bool> guard() async {
    if (!await isEnabled()) return true; // معطّل = لا حاجة
    if (!await canAuthenticate()) return true; // مش متاح، لا نقفل
    return authenticate(reason: 'افتح التطبيق بالبصمة');
  }

  static Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
