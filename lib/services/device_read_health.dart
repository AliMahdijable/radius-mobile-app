import 'dart:async';

import 'package:flutter/foundation.dart';

/// آخر قراءةٍ حيّة لكلّ جهاز — من لوحته المفردة أو بطاقته الكبيرة أو البرج: نجحت، أو فشلت وبأيّ رسالة.
///
/// ── لماذا ─────────────────────────────────────────────────────────
/// المالك (١ نوفمبر): «اذا الجهاز حتى لو ما مضيوف صح المفروض تخلي زر فحص الجهاز بالبنك يرد ويظهر شعار الجهاز يرد بنك اتصال
/// ping تاكد من الاعدادات الجهاز». الفحص يقول «يردّ على الاتصال»، والقراءة وحدها تعرف أنّ الدخول فشل (كلمة مرور/منفذ/community)
/// — فتجمعهما شاشة الجهاز في سطرٍ واحد: «الجهاز يردّ على الاتصال (ping) — تأكّد من إعدادات الجهاز…»، لا «مفصول».
///
/// العمر عمرُ الجلسة (كـ`DeviceStatsCache`): قراءةٌ فاشلة أقدم من [freshFor] لا تُقال.
class DeviceReadHealth {
  DeviceReadHealth._();
  static final DeviceReadHealth instance = DeviceReadHealth._();

  /// كم تبقى قراءةٌ فاشلة «حديثة» — أطول من نبضة اللوحة (٣–١٥ث) والبطاقة (١٥ث).
  static const freshFor = Duration(minutes: 2);

  final Map<int, ({String? error, DateTime at})> _last = {};

  /// يتحرّك مع كلّ تغيّرٍ يستحقّ إعادة الرسم (فشلٌ جديد، أو نجاحٌ بعد فشل) — المستمع يقرأ [errorOf].
  final ValueNotifier<int> changes = ValueNotifier(0);

  /// قراءةٌ ناجحة.
  void ok(int deviceId) {
    final had = _last[deviceId]?.error != null;
    _last[deviceId] = (error: null, at: DateTime.now());
    if (had) _notify();
  }

  /// قراءةٌ فاشلة ورسالتها كما عرضتها اللوحة.
  void failed(int deviceId, String message) {
    final prev = _last[deviceId]?.error;
    _last[deviceId] = (error: message.trim().isEmpty ? 'تعذّرت القراءة' : message, at: DateTime.now());
    if (prev != message) _notify();
  }

  /// تُنسى بعد تعديل الجهاز: إعداداتٌ جديدة، وخطأ القديمة لا يعنيها.
  void forget(int deviceId) {
    if (_last.remove(deviceId)?.error != null) _notify();
  }

  /// آخر قراءةٍ فاشلة إن كانت حديثة ولم تنجح بعدها قراءة — وإلّا `null`.
  String? errorOf(int deviceId) {
    final e = _last[deviceId];
    if (e == null || e.error == null) return null;
    if (DateTime.now().difference(e.at) > freshFor) return null;
    return e.error;
  }

  void clear() {
    if (_last.isEmpty) return;
    _last.clear();
    _notify();
  }

  /// الإشعار بعد العمل الجاري لا داخله: الكاتب قد يكون في بناء (تهيئة لوحة) والمستمع شاشةٌ تُعيد رسم نفسها.
  void _notify() => scheduleMicrotask(() => changes.value++);

  @visibleForTesting
  void debugReset() => _last.clear();
}
