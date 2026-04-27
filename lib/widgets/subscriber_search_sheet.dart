import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_theme.dart';
import '../models/subscriber_model.dart';
import '../providers/device_provider.dart';
import '../providers/subscribers_provider.dart';

/// Shows a bottom sheet that searches loaded subscribers by username, name,
/// or phone. Tapping a result closes the sheet and navigates to the
/// subscriber details screen.
Future<void> showSubscriberSearchSheet(BuildContext context) async {
  // Ensure the list is loaded before showing the sheet — the search filters
  // over whatever the subscribers provider currently holds.
  final container = ProviderScope.containerOf(context, listen: false);
  final subs = container.read(subscribersProvider);
  if (subs.subscribers.isEmpty && !subs.isLoading) {
    container.read(subscribersProvider.notifier).loadSubscribers();
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _SearchSheet(),
  );
}

class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet();

  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  final TextEditingController _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<SubscriberModel> _filter(List<SubscriberModel> all) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    final matches = all.where((s) {
      if (s.username.toLowerCase().contains(q)) return true;
      if (s.fullName.toLowerCase().contains(q)) return true;
      if (digits.isNotEmpty) {
        final phoneDigits =
            s.displayPhone.replaceAll(RegExp(r'[^0-9]'), '');
        if (phoneDigits.contains(digits)) return true;
      }
      return false;
    }).toList();
    matches.sort((a, b) {
      int rank(SubscriberModel s) {
        if (s.username.toLowerCase() == q) return 0;
        if (s.username.toLowerCase().startsWith(q)) return 1;
        if (s.fullName.toLowerCase().startsWith(q)) return 2;
        return 3;
      }
      return rank(a).compareTo(rank(b));
    });
    return matches.take(40).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenH = MediaQuery.of(context).size.height;
    final subs = ref.watch(subscribersProvider);
    final results = _filter(subs.subscribers);
    final showResults = _q.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: screenH * 0.85,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
              child: Row(
                children: [
                  Icon(Icons.search_rounded,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    'بحث سريع',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  if (subs.subscribers.isNotEmpty)
                    Text(
                      showResults ? '${results.length}' : '${subs.subscribers.length}',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
              child: TextField(
                autofocus: true,
                controller: _ctrl,
                onChanged: (v) => setState(() => _q = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم أو المعرّف أو رقم الهاتف…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _ctrl.clear();
                            setState(() => _q = '');
                          },
                        ),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: subs.isLoading && subs.subscribers.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : !showResults
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              subs.subscribers.isEmpty
                                  ? 'لا توجد بيانات مشتركين بعد'
                                  : 'ابدأ الكتابة للبحث في ${subs.subscribers.length} مشترك',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.5),
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        )
                      : results.isEmpty
                          ? Center(
                              child: Text(
                                'لا توجد نتائج',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.5),
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: results.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: theme.colorScheme.outline
                                    .withOpacity(0.08),
                              ),
                              itemBuilder: (ctx, i) {
                                final s = results[i];
                                final isExpired = !s.isActive;
                                final dotColor = !s.isEnabled
                                    ? AppTheme.dangerColor
                                    : isExpired
                                        ? AppTheme.warningColor
                                        : (s.isOnline
                                            ? AppTheme.successColor
                                            : Colors.grey);
                                return ListTile(
                                  onTap: () {
                                    // Prefetch device status before
                                    // pushing — same pattern as the
                                    // main subscribers list. Warms the
                                    // 5-min cache so ConnectionStatusCard
                                    // renders instantly on the details
                                    // screen.
                                    ref
                                        .read(deviceStatusProvider(
                                          DeviceStatusArgs(
                                            subscriberUsername: s.username,
                                            fallbackIp: s.ipAddress,
                                          ),
                                        ).future)
                                        .catchError((_) => null);
                                    Navigator.of(ctx).pop();
                                    context.push(
                                      '/subscriber/${s.username}',
                                      extra: s,
                                    );
                                  },
                                  leading: Container(
                                    width: 10,
                                    height: 10,
                                    margin: const EdgeInsets.only(top: 6),
                                    decoration: BoxDecoration(
                                      color: dotColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  title: Text(
                                    s.fullName.isNotEmpty
                                        ? s.fullName
                                        : s.username,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      s.username,
                                      if (s.displayPhone.isNotEmpty)
                                        s.displayPhone,
                                    ].join(' • '),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.55),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Icon(
                                    Icons.chevron_left_rounded,
                                    color: theme.colorScheme.primary,
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
