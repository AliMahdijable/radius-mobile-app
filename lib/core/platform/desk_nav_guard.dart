import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// النقرة المزدوجة لا تفتح الصفحة مرّتين (المالك ٢٤ أكتوبر: «النقر على أي شي — شعارات، أي قائمة — مرّتين يفتح مرّتين
/// الصفحة، ومن ترجع لازم ترجع خطوتين — مشكلة عامّة بالتطبيق، مال ويندوز»).
///
/// السبب: النقرة الأولى تفتح الصفحة (أو النافذة) فوراً، والثانية تصل بعدها بجزءٍ من الثانية — وكثيراً قبل أن تُرسم
/// الصفحة الجديدة أصلاً (صفحةٌ ثقيلة البناء)، فتقع على الزرّ نفسه تحتها وتفتح نسخةً ثانية. والعلاج عامٌّ لا زرّاً زرّاً:
/// منذ لحظة الفتح (أو الرجوع) تُمتصّ النقرات حتى تُرسم الصفحة الجديدة ويكتمل انتقالها — ثلث ثانيةٍ تقريباً.
///
/// - [observer] لكلّ Navigator (المراقب لا يُشارك بين اثنين).
/// - [DeskNavGuardScope] فوق الـNavigator الجذريّ: يقرأ الحالة **لحظة النقر** (لا ينتظر إعادة رسم — النقرة الثانية
///   تصل غالباً قبل الإطار التالي).
/// - المدّة مدّة انتقال الصفحة نفسها، تُعدّ بالإطارات من أوّل إطارٍ لها (انظر [_hold]).
class DeskNavGuard {
  DeskNavGuard._();

  /// انتقالٌ جارٍ الآن ⇒ النقر يُمتصّ.
  static final ValueNotifier<bool> busy = ValueNotifier<bool>(false);

  static int _active = 0;

  /// أطول امتصاصٍ مهما طال انتقال الصفحة.
  static const Duration maxHold = Duration(milliseconds: 650);

  static NavigatorObserver observer() => _GuardObserver();

  /// من لحظة الفتح/الرجوع حتى يمرّ زمن انتقال الصفحة **محسوباً بالإطارات المرسومة** من أوّل إطارٍ لها — فالبناء الثقيل
  /// (إطارٌ أوّل يتأخّر) يُطيل الامتصاص بقدره، ولا مؤقّتات تبقى معلّقة. (لا يُقرأ من حالة حركة الصفحة: فلاتر يقلبها
  /// «مكتملة» لحظةً وهو يقيس انتقال Hero فيُفلت مبكّراً.)
  static void _hold(Route<dynamic> route, {required bool forward}) {
    if (route is! TransitionRoute) return;
    var hold = forward ? route.transitionDuration : route.reverseTransitionDuration;
    if (hold == Duration.zero) return;
    if (hold > maxHold) hold = maxHold;
    _active += 1;
    busy.value = true;
    Duration? start;
    void tick(Duration ts) {
      start ??= ts;
      if (ts - start! >= hold) {
        _active = _active > 0 ? _active - 1 : 0;
        if (_active == 0) busy.value = false;
        return;
      }
      SchedulerBinding.instance.scheduleFrameCallback(tick);
    }

    SchedulerBinding.instance.scheduleFrameCallback(tick);
  }

  @visibleForTesting
  static void debugReset() {
    _active = 0;
    busy.value = false;
  }
}

class _GuardObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // أوّل صفحةٍ في Navigator (بلا سابقة) تُبنى بلا انتقالٍ يُرى — لا امتصاص.
    if (previousRoute != null) DeskNavGuard._hold(route, forward: true);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => DeskNavGuard._hold(route, forward: false);
}

/// يمتصّ النقر أثناء الانتقال — فوق الـNavigator الجذريّ (في `MaterialApp.builder`) فيشمل كلّ الأقسام والنوافذ.
/// الحالة تُقرأ وقت فحص النقرة نفسه، فيعمل من أوّل نقرةٍ بعد الفتح ولو لم يُرسم إطارٌ بعد.
class DeskNavGuardScope extends SingleChildRenderObjectWidget {
  const DeskNavGuardScope({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderNavGuard();
}

class _RenderNavGuard extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // كـAbsorbPointer: النقرة داخل الحدود «أصابت» ولا تصل لشيءٍ تحتها.
    if (DeskNavGuard.busy.value) return size.contains(position);
    return super.hitTest(result, position: position);
  }
}
