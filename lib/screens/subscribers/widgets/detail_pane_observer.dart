import 'package:flutter/widgets.dart';

/// لوحة تفاصيل المشترك على الحاسبة: تُطوى حين **تفرغ فعلاً** — رجوعٌ إلى أوّلها (زرّ الرجوع، Esc، حذف المشترك…).
///
/// 🐛 بلاغ المالك ٢٧ أكتوبر: «من ينقر على مشترك يطلعله القائمة الجانبيه، بس ينقره مره ثانيه تختفي، واذا نقر مره
/// ثالثه ما يصير شي إلّا يخرج ويرجع لصفحة المشتركين». فتح مشتركٍ في اللوحة `pushAndRemoveUntil`: تفاصيل جديدة
/// فوق، وتُزال القديمة من تحتها. والإزالة تُبلَّغ بالسابقة = أوّل اللوحة، فكان الشرط «السابقة أوّلُ اللوحة» يقرؤها
/// إفراغاً فيطويها والمشترك الجديد مفتوح؛ ومن الثالثة يُفتح ويُطوى في الإطار نفسه فلا يُرى شيء.
/// فالحكم بما بقي في اللوحة بعد التغيير لا بالسابقة: لا رجوع ممكن ⇒ فارغة.
class DetailPaneObserver extends NavigatorObserver {
  DetailPaneObserver(this.onEmpty);

  final VoidCallback onEmpty;

  void _check() {
    // الإشعارات تصل بعد اكتمال التحديث: المُزال والمُسحوب لم يعودا «حاضرين»، فـcanPop يصف الحال الجديدة.
    final nav = navigator;
    if (nav != null && !nav.canPop()) onEmpty();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _check();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _check();
}
