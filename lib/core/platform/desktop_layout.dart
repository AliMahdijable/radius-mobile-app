import 'package:flutter/widgets.dart';

import 'app_platform.dart';

/// تخطيط الحاسبة (ويندوز، ونسخة الماك للتجربة).
class DesktopLayout {
  DesktopLayout._();

  /// أضيق من هذا: تخطيط الهاتف (الشريط السفلي) حتى على الحاسبة — نافذةٌ مصغَّرة.
  static const double minWidth = 900;

  /// الغلاف العريض ظاهر (DesktopShell) ⇒ إطار الـ٧٢٠ في main.dart يتنحّى ويأخذ الغلاف العرض كلّه.
  static final ValueNotifier<bool> shellActive = ValueNotifier<bool>(false);

  static int _shells = 0;

  /// من initState/dispose للغلاف. التحديث بعد الإطار: تغييرٌ أثناء البناء لا يُعيد بناء الإطار
  /// (setState أثناء build)، والعدّاد يمنع خروج غلافٍ قديم من إطفاء غلافٍ جديد في الإطار نفسه.
  static void shellMounted() => _sync(++_shells);
  static void shellUnmounted() => _sync(--_shells);

  static void _sync(int _) {
    WidgetsBinding.instance.addPostFrameCallback((_) => shellActive.value = _shells > 0);
    WidgetsBinding.instance.scheduleFrame();
  }

  /// عرض النافذة الحقيقيّ (View) لا MediaQuery: إطار الـ٧٢٠ في main.dart يحصر MediaQuery قبل أن
  /// يقرّر الغلاف — فالقرار من النافذة نفسها.
  static bool wide(BuildContext context) {
    if (!AppPlatform.isDesktop) return false;
    final view = View.of(context);
    return view.physicalSize.width / view.devicePixelRatio >= minWidth;
  }
}

/// منطقة محتوى غلاف الحاسبة: ما يُبنى داخلها يرسم نسخته العريضة (رأس صفحةٍ كبير، شبكة بطاقات…)
/// فوراً من أوّل بناء — لا ينتظر [DesktopLayout.shellActive] الذي يتحدّث بعد الإطار. وما يُفتح فوق
/// الغلاف (المكدّس الجذريّ، لوحة تفاصيل المشترك) خارجها فيبقى بشكل الهاتف.
class DesktopScope extends InheritedWidget {
  const DesktopScope({super.key, this.active = true, required super.child});

  final bool active;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopScope>()?.active ?? false;

  @override
  bool updateShouldNotify(DesktopScope old) => old.active != active;
}

/// شاشات البداية داخل إطار الحاسبة (لوحة العلامة بجانبها): تُخفي شعارها الكبير — العلامة في اللوحة.
class DeskAuthScope extends InheritedWidget {
  const DeskAuthScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeskAuthScope>() != null;

  @override
  bool updateShouldNotify(DeskAuthScope old) => false;
}
