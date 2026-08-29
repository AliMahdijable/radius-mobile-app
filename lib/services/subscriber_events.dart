import 'package:flutter/foundation.dart';

import '../api/subscribers_api.dart';

/// Process-wide event bus for subscriber mutations. Every operation that
/// changes server-side state (activate / extend / disconnect / toggle /
/// delete / pay-debt / add-debt / discount / …) calls
/// [SubscriberEvents.notifyChange] on success. Screens that show
/// subscriber data listen to [dataChanged] and re-fetch when it ticks.
///
/// Why a ValueNotifier instead of a Stream:
///  * cheap and synchronous — fires on the same frame the operation
///    succeeds, so the UI rebuilds without a perceptible delay.
///  * no manual subscription lifecycle — addListener / removeListener
///    in initState / dispose covers everything.
///
/// The cache invalidation is bundled in [notifyChange] so callers don't
/// have to remember to call SubscribersApi.refreshAll first.
class SubscriberEvents {
  SubscriberEvents._();

  static final ValueNotifier<int> dataChanged = ValueNotifier<int>(0);

  /// Call this after any successful mutation. Bumps the notifier and
  /// drops the cached subscribers list so the next loadAll() hits the
  /// backend instead of serving stale rows.
  static void notifyChange() {
    SubscribersApi.refreshAll(); // fire-and-forget — its own future
    // resolves whenever the next listener
    // calls loadAll().
    dataChanged.value = dataChanged.value + 1;
  }
}
