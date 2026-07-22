import 'package:flutter/foundation.dart';

/// Global signal bumped whenever the app returns from background to
/// foreground (OS-level lifecycle `AppLifecycleState.resumed`). Any
/// screen that displays fetched data and stays mounted for long periods
/// should listen to [tick] and re-fetch silently — mirrors v1's
/// HomeScreen didChangeAppLifecycleState behavior, adapted to v2's
/// ValueNotifier event-bus pattern (see [SubscriberEvents]).
///
/// Why not a WidgetsBindingObserver on every screen: main.dart owns the
/// single observer for the whole app and broadcasts via this signal, so
/// each screen only wires up one addListener/removeListener pair.
class AppResumedSignal {
  AppResumedSignal._();

  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static void bump() {
    tick.value = tick.value + 1;
  }
}
