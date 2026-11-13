import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// طيّ أقسام صفحة المشترك — المالك ١٤ نوفمبر: «الاقسام خليهن توكل كلوز واحد منهن ع الاقل بشكل دائمي».
///
/// لكلّ قسمٍ معرّف (`addr` عنوان الجهاز/الاتّصال · `dev1` معلومات الجهاز · `dev2` الجهاز الثاني) وحالٌ تُحفظ على الجهاز لكلّ
/// المشتركين (لا لكلّ مشترك): ما طواه الوكيل يبقى مطويّاً حتى يفتحه. المطويّ لا يُبنى كرته أصلاً ⇒ لا فحص ولا نبض على جهازه.
class SectionFold {
  SectionFold._();

  static const _prefix = 'subscriber.fold.v1.';

  /// المطويّ افتراضاً قبل أن يختار الوكيل: «الجهاز الثاني» (ثانويٌّ بطبعه، وكرتان معاً يطوّلان الصفحة).
  static const _defaults = <String, bool>{'dev2': true};

  static final _notifiers = <String, ValueNotifier<bool>>{};
  static bool _loading = false;

  /// حال القسم (true = مطويّ) — يتحدّث حين تُقرأ المحفوظات أو يتبدّل.
  static ValueNotifier<bool> of(String id) {
    final n = _notifiers.putIfAbsent(id, () => ValueNotifier<bool>(_defaults[id] ?? false));
    if (!_loading) {
      _loading = true;
      unawaited(_load());
    }
    return n;
  }

  static Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final key in p.getKeys()) {
        if (!key.startsWith(_prefix)) continue;
        final v = p.getBool(key);
        if (v == null) continue;
        final id = key.substring(_prefix.length);
        final n = _notifiers[id];
        if (n == null) {
          _notifiers[id] = ValueNotifier<bool>(v);
        } else {
          n.value = v;
        }
      }
    } catch (_) {/* بلا محفوظات ⇒ الافتراض */}
  }

  static Future<void> set(String id, bool folded) async {
    of(id).value = folded;
    try {
      await (await SharedPreferences.getInstance()).setBool('$_prefix$id', folded);
    } catch (_) {/* يبقى للجلسة */}
  }

  @visibleForTesting
  static void debugReset() {
    _notifiers.clear();
    _loading = false;
  }
}
