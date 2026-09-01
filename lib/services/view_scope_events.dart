import 'package:flutter/foundation.dart';

/// مُنبّه تغيّر «نطاق العرض».
///
/// 🐛 بلاغ 2026-09-01: «خفّيتهن كلهن وماكو شي تغيّر». الرئيسيّة كانت
/// تقرأ الأقسام **مرّة واحدة في `initState`**، وهي تبقى مركَّبة داخل
/// `IndexedStack` طوال الجلسة — فتبديلٌ في الإعدادات لا يبلغها أبداً،
/// ولا يظهر أثره إلّا بعد إغلاق التطبيق وفتحه.
///
/// نفس صنف العطل الذي أصلحناه في شاشة المشتركين، ولنفس السبب: حالةٌ
/// تُقرأ مرّة وتُفترض ثابتة.
class ViewScopeEvents {
  ViewScopeEvents._();

  /// عدّاد يتقدّم مع كلّ حفظ ناجح — الشاشات تقارن ختمها به.
  static final ValueNotifier<int> changed = ValueNotifier<int>(0);

  static void notifyChanged() => changed.value = changed.value + 1;
}
