import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// معرّف جهاز ثابت للحساب (ضدّ مشاركة الحساب على أكثر من جهاز). يُولَّد مرّةً
/// ويُخزَّن بأمان، ويُرسَل في `x-device-id` فيفحصه الخادم عند دخول الساس وتجديد
/// التوكن (الحدّ = شركات الباقة + ١). ثابتٌ ما بقي التثبيت.
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
  static final RegExp _re = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
  static String? _cached;

  /// يرجّع المعرّف (يولّده ويخزّنه أوّل مرّة). لا يرمي أبداً — عند تعذّر التخزين
  /// يرجّع معرّفاً للجلسة الحاليّة (يتجدّد لاحقاً).
  static Future<String> get() async {
    final c = _cached;
    if (c != null) return c;
    try {
      final existing = await _storage.read(key: _key);
      if (existing != null && _re.hasMatch(existing)) {
        _cached = existing;
        return existing;
      }
    } catch (_) {/* تخزين غير متاح */}
    final id = _generate();
    try {
      await _storage.write(key: _key, value: id);
    } catch (_) {/* تخزين غير متاح — نستعمله للجلسة */}
    _cached = id;
    return id;
  }

  static String _generate() {
    final r = Random.secure();
    const hex = '0123456789abcdef';
    return List<String>.generate(32, (_) => hex[r.nextInt(16)]).join();
  }
}
