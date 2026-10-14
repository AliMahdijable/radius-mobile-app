import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// معرّف جهاز ثابت للحساب (ضدّ مشاركة الحساب على أكثر من جهاز). يُولَّد مرّةً
/// ويُخزَّن بأمان، ويُرسَل في `x-device-id` فيفحصه الخادم عند دخول الساس وتجديد
/// التوكن (الحدّ = شركات الباقة + ١). ثابتٌ ما بقي التثبيت.
///
/// نسخةٌ احتياطيّة في SharedPreferences: المعرّف ليس سرّاً (هويّة تثبيت لا
/// بيانات دخول)، وتعطّل التخزين الآمن (مفتاح KeyStore مفقود بعد استعادة نسخة،
/// أو خطأ تشفير) كان يولّد معرّفاً جديداً مع **كلّ تشغيل** — فيُسجَّل جهازٌ جديد
/// كلّ مرّة حتى يمتلئ الحدّ والجهاز واحد. الترتيب: الآمن ← الاحتياطيّ ← توليد.
class DeviceId {
  DeviceId._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
      accountName: 'mysvcs_pro_device',
    ),
  );
  static const _key = 'pro.device.id';
  static const _fallbackKey = 'pro.device.id.fallback';
  static final RegExp _re = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
  static String? _cached;

  /// يرجّع المعرّف (يولّده ويخزّنه أوّل مرّة). لا يرمي أبداً — عند تعذّر
  /// التخزينين معاً يرجّع معرّفاً للجلسة الحاليّة (يتجدّد لاحقاً).
  static Future<String> get() async {
    final c = _cached;
    if (c != null) return c;
    String? secure;
    try {
      final v = await _storage.read(key: _key);
      if (v != null && _re.hasMatch(v)) secure = v;
    } catch (_) {/* تخزين آمن غير متاح */}
    String? fallback;
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_fallbackKey);
      if (v != null && _re.hasMatch(v)) fallback = v;
      // مرآةٌ للمعرّف الآمن: يبقى نفسه لو تعطّل التخزين الآمن لاحقاً.
      if (secure != null && fallback != secure) await prefs.setString(_fallbackKey, secure);
    } catch (_) {/* لا يُفشل */}
    if (secure != null) return _cached = secure;
    if (fallback != null) {
      try {
        await _storage.write(key: _key, value: fallback); // إصلاح الآمن إن عاد يعمل
      } catch (_) {}
      return _cached = fallback;
    }
    final id = _generate();
    try {
      await _storage.write(key: _key, value: id);
    } catch (_) {/* تخزين آمن غير متاح — يبقى الاحتياطيّ */}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fallbackKey, id);
    } catch (_) {/* كلاهما غير متاح — نستعمله للجلسة */}
    return _cached = id;
  }

  static String _generate() {
    final r = Random.secure();
    const hex = '0123456789abcdef';
    return List<String>.generate(32, (_) => hex[r.nextInt(16)]).join();
  }
}
