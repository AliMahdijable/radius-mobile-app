import 'subscribers/widgets/filter_chips_bar.dart';

/// منفذ الغلاف للتنقّل من خارجه — «الأمر الصوتي ٢» (١٠ نوفمبر): «المشتركين المنتهين» يفتح تبويب المشتركين بفلتره، و«افتح
/// الأجهزة» تبويبها. الغلاف يسجّل نفسه ما دام حيّاً ([attach]/[detach] بمالكه — غلافٌ قديم يُنهى بعد أن يبدأ الجديد لا يفكّ
/// منفذ الجديد)، ومن لا غلاف له (اختبار، شاشةٌ قبل الدخول) يُجاب بـfalse فيقول صاحبه السبب.
class ShellNav {
  ShellNav._();

  static const tabHome = 0;
  static const tabSubscribers = 1;
  static const tabDevices = 2;
  static const tabMore = 3;

  static Object? _owner;
  static void Function(SubscriberFilter? filter)? _subscribers;
  static void Function(int tab)? _tab;

  static void attach(
    Object owner, {
    required void Function(SubscriberFilter? filter) subscribers,
    required void Function(int tab) tab,
  }) {
    _owner = owner;
    _subscribers = subscribers;
    _tab = tab;
  }

  static void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _subscribers = null;
    _tab = null;
  }

  static bool get ready => _owner != null;

  /// تبويب المشتركين بفلتره (null = بلا فلتر). false = لا غلاف.
  static bool openSubscribers(SubscriberFilter? filter) {
    final go = _subscribers;
    if (go == null) return false;
    go(filter);
    return true;
  }

  /// تبويبٌ برقمه ([tabHome]…). false = لا غلاف.
  static bool openTab(int tab) {
    final go = _tab;
    if (go == null) return false;
    go(tab);
    return true;
  }
}
