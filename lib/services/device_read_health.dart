import 'dart:async';

import 'package:flutter/foundation.dart';

/// قراءةٌ حيّة تفشل الآن: رسالتها، ومتى بدأ فشلها (أوّل قراءةٍ فاشلة بعد نجاح)، ومتى آخر قراءةٍ فاشلة.
typedef ReadFailure = ({String error, DateTime since, DateTime at});

/// آخر قراءةٍ حيّة لكلّ جهاز — من لوحته المفردة أو بطاقته الكبيرة أو البرج: نجحت، أو فشلت وبأيّ رسالة ومنذ متى.
///
/// ── لماذا ─────────────────────────────────────────────────────────
/// المالك (١ نوفمبر): «اذا الجهاز حتى لو ما مضيوف صح المفروض تخلي زر فحص الجهاز بالبنك يرد ويظهر شعار الجهاز يرد بنك اتصال
/// ping تاكد من الاعدادات الجهاز». الفحص يقول «يردّ على الاتصال»، والقراءة وحدها تعرف أنّ الدخول فشل (كلمة مرور/منفذ/community)
/// — فتجمعهما شاشة الجهاز في سطرٍ واحد: «الجهاز يردّ على الاتصال (ping) — تأكّد من إعدادات الجهاز…»، لا «مفصول».
/// ولا تجمعهما إلّا إن كان الفحص **بعد** بدء الفشل ([ReachVerdict]): جهازٌ ينطفئ بعد آخر فحص تفشل قراءته أيضاً.
///
/// العمر عمرُ الجلسة (كـ`DeviceStatsCache`): قراءةٌ فاشلة أقدم من [freshFor] لا تُقال.
class DeviceReadHealth {
  DeviceReadHealth._();
  static final DeviceReadHealth instance = DeviceReadHealth._();

  /// كم تبقى قراءةٌ فاشلة «حديثة» — أطول من نبضة اللوحة (٣–١٥ث) والبطاقة (١٥ث) والبرج (٢٠ث).
  static const freshFor = Duration(minutes: 2);

  /// الساعة — واحدةٌ لأخطاء القراءة ولأحكام الفحص التي تُقارَن بها (شاشة الجهاز والبرج)، والاختبار يحقنها.
  static DateTime Function() clock = DateTime.now;

  final Map<int, ({String? error, DateTime at, DateTime? since})> _last = {};

  /// يتحرّك مع **كلّ** قراءةٍ فاشلة (حدثٌ جديد: شاشة الجهاز تعيد فحصها إن قدُم حكمها — [ReachVerdict.due]) ومع نجاحٍ بعد
  /// فشل. المستمع يقرأ [failureOf] لجهازه ويتجاهل غيره.
  final ValueNotifier<int> changes = ValueNotifier(0);

  /// قراءةٌ ناجحة.
  void ok(int deviceId) {
    final had = _last[deviceId]?.error != null;
    _last[deviceId] = (error: null, at: clock(), since: null);
    if (had) _notify();
  }

  /// قراءةٌ فاشلة ورسالتها كما عرضتها اللوحة.
  ///
  /// الفشل الجاري يبدأ بأوّل قراءةٍ فاشلة بعد نجاح (أو بعد أن قدُم آخرها) — وتغيّر الرسالة لا يبدّله: بعض اللوحات تضع في رسالتها
  /// تفاصيل تتغيّر مع كلّ نبضة، وبدءٌ جديد مع كلّ واحدةٍ كان سيعيد الفحص مع كلّ نبضة.
  void failed(int deviceId, String message) {
    final now = clock();
    final prev = _last[deviceId];
    final since = prev?.since;
    final continuing = prev != null && prev.error != null && since != null && now.difference(prev.at) <= freshFor;
    _last[deviceId] = (
      error: message.trim().isEmpty ? 'تعذّرت القراءة' : message,
      at: now,
      since: continuing ? since : now,
    );
    _notify();
  }

  /// تُنسى بعد تعديل الجهاز: إعداداتٌ جديدة، وخطأ القديمة لا يعنيها.
  void forget(int deviceId) {
    if (_last.remove(deviceId)?.error != null) _notify();
  }

  /// آخر قراءةٍ فاشلة إن كانت حديثة ولم تنجح بعدها قراءة — وإلّا `null`.
  String? errorOf(int deviceId) => failureOf(deviceId)?.error;

  /// الفشل الجاري إن كان حديثاً ([freshFor]) ولم تنجح بعده قراءة — وإلّا `null`.
  ReadFailure? failureOf(int deviceId) {
    final e = _last[deviceId];
    final error = e?.error;
    final since = e?.since;
    if (e == null || error == null || since == null) return null;
    if (clock().difference(e.at) > freshFor) return null;
    return (error: error, since: since, at: e.at);
  }

  void clear() {
    if (_last.isEmpty) return;
    _last.clear();
    _notify();
  }

  /// الإشعار بعد العمل الجاري لا داخله: الكاتب قد يكون في بناء (تهيئة لوحة) والمستمع شاشةٌ تُعيد رسم نفسها.
  void _notify() => scheduleMicrotask(() => changes.value++);

  @visibleForTesting
  void debugReset() {
    _last.clear();
    clock = DateTime.now;
  }
}

/// «يردّ» مع قراءةٍ تفشل لا يُقال إلّا بحكم وصولٍ حديث — مكانٌ واحد لشاشة الجهاز والبرج.
///
/// المراجعة (١ نوفمبر): الفحص لقطةٌ من لحظته، والقراءة الحيّة تفشل بعده كلّ بضع ثوانٍ. جهازٌ ينطفئ والشاشة مفتوحة تفشل قراءته،
/// وحكمه القديم «يردّ» كان يقول «تأكّد من إعدادات الجهاز» — يرسل الوكيل لفحص الإعدادات بدل الكهرباء. فالحكم يصلح لفشلٍ بدأ
/// **قبله** وحده ([covers])، ويُعاد ما دامت القراءة تفشل ([due]): مرّةً كلّ [recheckEvery] تقريباً.
class ReachVerdict {
  ReachVerdict._();

  /// يُعاد فحص الوصول لجهازٍ ما زالت قراءته تفشل مرّةً كلّ هذه المدّة تقريباً.
  static const recheckEvery = Duration(seconds: 30);

  /// أقصى عمرٍ لحكمٍ يُقال به «يردّ» مع قراءةٍ تفشل — أطول من [recheckEvery] ونبضةِ قراءةٍ فاشلة وزمنِ الفحص، فلا يرمش السطر
  /// بين فحصين؛ وإن توقّف الفحص لسببٍ ما سقط الحكم ولم يبقَ «يردّ» قديماً.
  static const validFor = Duration(seconds: 90);

  /// الحكم المأخوذ عند [checkedAt] يصلح للفشل الذي بدأ عند [since]: انتهى بعد بدئه ولم يقدُم ([validFor]).
  static bool covers({required DateTime? checkedAt, required DateTime since, required DateTime now}) =>
      checkedAt != null && !checkedAt.isBefore(since) && now.difference(checkedAt) <= validFor;

  /// يُفحص الآن؟ لا حكم، أو حكمٌ أقدم من بدء الفشل ([since])، أو مضى عليه [recheckEvery].
  static bool due({required DateTime? checkedAt, DateTime? since, required DateTime now}) =>
      checkedAt == null || (since != null && checkedAt.isBefore(since)) || now.difference(checkedAt) >= recheckEvery;
}
