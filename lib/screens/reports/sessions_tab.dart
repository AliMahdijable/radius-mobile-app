import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../../core/theme/app_theme.dart';
import '../../providers/reports_provider.dart';

class SessionsTab extends ConsumerStatefulWidget {
  const SessionsTab({super.key});

  @override
  ConsumerState<SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends ConsumerState<SessionsTab>
    with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();
  bool _loaded = false;
  int _page = 1;
  static const _pageSize = 50;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    await ref.read(reportsProvider.notifier).fetchSessions(
          page: page,
          count: _pageSize,
          search: _searchCtrl.text.trim(),
        );
    if (mounted) {
      setState(() {
        _loaded = true;
        _page = page;
      });
    }
  }

  String _formatBytes(dynamic octets) {
    final bytes = (octets is num) ? octets.toDouble() : (double.tryParse(octets?.toString() ?? '') ?? 0);
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double val = bytes;
    while (val >= 1024 && i < units.length - 1) {
      val /= 1024;
      i++;
    }
    return '${val.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  String _formatSessionTime(dynamic time) {
    if (time == null || time.toString().isEmpty) return '—';
    final dt = DateTime.tryParse(time.toString());
    if (dt == null) return time.toString();
    return intl.DateFormat('MM/dd HH:mm').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(reportsProvider);
    final theme = Theme.of(context);

    if (state.loading && !_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalPages = (state.sessionsTotal / _pageSize).ceil();

    return Column(
      children: [
        // Search
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            onSubmitted: (_) => _load(page: 1),
            decoration: InputDecoration(
              hintText: 'بحث باسم المستخدم أو IP...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.send_rounded, size: 20),
                onPressed: () => _load(page: 1),
              ),
            ),
          ),
        ),

        // Pagination
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text('${state.sessionsTotal} جلسة',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: .5))),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: _page > 1 ? () => _load(page: _page - 1) : null,
                visualDensity: VisualDensity.compact,
              ),
              Text('$_page / ${totalPages > 0 ? totalPages : 1}',
                  style: const TextStyle(fontSize: 11)),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: _page < totalPages
                    ? () => _load(page: _page + 1)
                    : null,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),

        // Sessions list
        Expanded(
          child: state.loading
              ? const Center(child: CircularProgressIndicator())
              : state.sessions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off_rounded,
                              size: 48,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .2)),
                          const SizedBox(height: 8),
                          Text('لا توجد جلسات',
                              style: TextStyle(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .4))),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _load(page: _page),
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: state.sessions.length,
                        itemBuilder: (ctx, i) =>
                            _SessionRow(session: state.sessions[i], helpers: this),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  final Map<String, dynamic> session;
  final _SessionsTabState helpers;
  const _SessionRow({required this.session, required this.helpers});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final username = session['username']?.toString() ?? '';
    final ip = session['framedipaddress']?.toString() ?? '';
    final startTime = helpers._formatSessionTime(session['acctstarttime']);
    final stopTime = helpers._formatSessionTime(session['acctstoptime']);
    final dataIn = helpers._formatBytes(session['acctinputoctets']);
    final dataOut = helpers._formatBytes(session['acctoutputoctets']);
    final nasIp = session['nasipaddress']?.toString() ?? '';
    final terminateCause =
        session['acctterminatecause']?.toString() ?? '';

    final isOnline = stopTime == '—' || stopTime.isEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: .06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(username,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
            ),
            Text(ip,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.primary)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            _InfoChip(Icons.play_arrow_rounded, startTime, Colors.green),
            const SizedBox(width: 8),
            _InfoChip(
                Icons.stop_rounded, stopTime, isOnline ? Colors.green : Colors.red),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            _InfoChip(Icons.arrow_downward_rounded, dataIn, Colors.blue),
            const SizedBox(width: 8),
            _InfoChip(Icons.arrow_upward_rounded, dataOut, Colors.orange),
            if (nasIp.isNotEmpty) ...[
              const SizedBox(width: 8),
              _InfoChip(Icons.router_rounded, nasIp, Colors.grey),
            ],
          ]),
          if (terminateCause.isNotEmpty && terminateCause != '—')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('سبب الإنهاء: $terminateCause',
                  style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: .4))),
            ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  const _InfoChip(this.icon, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color.withValues(alpha: .6)),
        const SizedBox(width: 3),
        Text(value,
            style: TextStyle(
                fontSize: 10,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .5))),
      ],
    );
  }
}
