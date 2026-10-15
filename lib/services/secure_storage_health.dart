import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// خزنة أندرويد المشفّرة التي لا تُفكّ — تشخيصها وعلاجها.
///
/// 🐛 بلاغ ٢٠٢٦-١٠-١٥ (فيديو «nonlogin»؛ admin@sk24: ٢٤٤ دخولاً ناجحاً في الخادم خلال يوم واحد، وتطبيقٌ
/// لا يتقدّم): نسخة جوجل الاحتياطيّة تُعيد ملفّ `FlutterSecureStorage` عند إعادة التثبيت أو الانتقال لهاتفٍ
/// جديد **بلا** مفتاح KeyStore الذي شفّره — مفاتيح KeyStore لا تُنسخ أبداً. ومع `resetOnError: false`
/// (مقصودٌ في [AuthStorage] كي لا يمحو عطلٌ عابر الجلسة) ترمي كلُّ قراءةٍ وكتابةٍ إلى الأبد: الدخول ينجح في
/// الخادم، وحفظ الجلسة يرمي، فلا انتقال ولا رسالة — والمدير يضغط «دخول» بلا نهاية. وإعادة التثبيت لا تُصلحه
/// (النسخة الاحتياطيّة تعود معه)؛ «مسح بيانات التطبيق» وحده كان يُصلحه.
///
/// العلاج: فحصٌ صغير (كتابة/قراءة/حذف مفتاحٍ تجريبيّ) — فشلٌ مرّتين متتاليتين ⇒ الخزنة ميّتة ⇒ تُمسح
/// بياناتها ومفتاحها ويُولَّد مفتاحٌ جديد. لا يضيع شيءٌ مقروء: ما فيها غير قابلٍ للفكّ أصلاً. والعطل العابر
/// (فشلٌ ثمّ نجاح) لا يمسح شيئاً. والوقاية في AndroidManifest: الخزنة مستثناةٌ من النسخ الاحتياطيّ.
class SecureStorageHealth {
  SecureStorageHealth._();

  static const _probeKey = 'pro.secure_storage_probe';

  /// الملفّ الافتراضيّ نفسه الذي تقرأ منه [AuthStorage] وبقيّة الخزائن، بـ`resetOnError: false` كي يظهر العطل.
  static const _probe = FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: false));

  /// للعلاج وحده: `resetOnError: true` يجعل الإضافة تمسح البيانات **والمفتاح** عند العطل ثمّ تُكمل.
  static const _reset = FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: true));

  static Future<bool>? _inFlight;

  /// مُسحت الخزنة في هذا التشغيل (يُبلَّغ Crashlytics بعد تهيئة Firebase — main.dart).
  static bool healedThisRun = false;

  /// لا يرمي أبداً. true = كانت ميّتةً فمُسحت. نداءاتٌ متزامنة تتشارك فحصاً واحداً.
  static Future<bool> healIfBroken() {
    if (kIsWeb || !Platform.isAndroid) return Future.value(false);
    return _inFlight ??= _heal().whenComplete(() => _inFlight = null);
  }

  static Future<bool> _probeOnce() async {
    try {
      await _probe.write(key: _probeKey, value: '1');
      final v = await _probe.read(key: _probeKey);
      await _probe.delete(key: _probeKey);
      return v == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _probeWithin() =>
      _probeOnce().timeout(const Duration(seconds: 3), onTimeout: () => false);

  static Future<bool> _heal() async {
    try {
      if (await _probeWithin()) return false; // سليمة
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (await _probeWithin()) return false; // عطلٌ عابر — لا مسح
      if (kDebugMode) debugPrint('🔴 [secure-storage] الخزنة لا تُفكّ — تُمسح ويُولَّد مفتاحٌ جديد');
      try {
        await _reset.deleteAll().timeout(const Duration(seconds: 3));
      } catch (_) {/* الكتابة التالية تتولّى المفتاح */}
      try {
        // كتابةٌ بـresetOnError=true: إن بقي المفتاح المغلَّف عصيّاً تمسح الإضافة البيانات والمفتاح معاً.
        await _reset.write(key: _probeKey, value: '1').timeout(const Duration(seconds: 3));
        await _reset.delete(key: _probeKey).timeout(const Duration(seconds: 3));
      } catch (_) {/* يُحكم بالفحص أدناه */}
      healedThisRun = true;
      final ok = await _probeWithin();
      if (kDebugMode) debugPrint('🟢 [secure-storage] بعد العلاج: ${ok ? 'سليمة' : 'ما زالت معطوبة'}');
      return true;
    } catch (_) {
      return false;
    }
  }
}
