import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../../core/theme/app_theme.dart';
import '../../core/utils/csv_export.dart';
import '../../providers/reports_provider.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/report_controls.dart';

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
  int _pageSize = 50;

  String _advIp = '';
  String _advUsername = '';
  String _advMac = '';
  String _advFromDate = '';
  String _advToDate = '';

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

  bool get _hasAdvancedFilters =>
      _advIp.isNotEmpty ||
      _advUsername.isNotEmpty ||
      _advMac.isNotEmpty ||
      _advFromDate.isNotEmpty ||
      _advToDate.isNotEmpty;

  bool _looksLikeIp(String value) =>
      RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(value);

  bool _looksLikeMac(String value) => RegExp(
        r'^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}$',
      ).hasMatch(value);

  Map<String, String> _buildSearchFilters() {
    final query = _searchCtrl.text.trim();

    if (_advUsername.isNotEmpty || _advIp.isNotEmpty || _advMac.isNotEmpty) {
      return {
        'search': '',
        'username': _advUsername.trim(),
        'ip': _advIp.trim(),
        'mac': _advMac.trim(),
      };
    }

    if (query.isEmpty) {
      return {
        'search': '',
        'username': '',
        'ip': '',
        'mac': '',
      };
    }

    if (_looksLikeMac(query)) {
      return {
        'search': '',
        'username': '',
        'ip': '',
        'mac': query,
      };
    }

    if (_looksLikeIp(query)) {
      return {
        'search': '',
        'username': '',
        'ip': query,
        'mac': '',
      };
    }

    return {
      'search': '',
      'username': query,
      'ip': '',
      'mac': '',
    };
  }

  Future<void> _load({int page = 1}) async {
    final filters = _buildSearchFilters();
    await ref.read(reportsProvider.notifier).fetchSessions(
          page: page,
          count: _pageSize,
          search: filters['search'] ?? '',
          username: filters['username'] ?? '',
          ipAddress: filters['ip'] ?? '',
          mac: filters['mac'] ?? '',
          fromDate: _advFromDate.isNotEmpty ? _advFromDate : null,
          toDate: _advToDate.isNotEmpty ? _advToDate : null,
        );
    if (mounted) {
      setState(() {
        _loaded = true;
        _page = page;
      });
    }
  }

  String _formatBytes(dynamic octets) {
    final bytes = (octets is num)
        ? octets.toDouble()
        : (double.tryParse(octets?.toString() ?? '') ?? 0);
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

  Future<void> _exportCsv() async {
    final sessions = ref.read(reportsProvider).sessions;
    if (sessions.isEmpty) {
      AppSnackBar.warning(context, 'لا توجد بيانات للتصدير');
      return;
    }
    try {
      await CsvExport.exportAndShare(
        fileName: 'sessions-report-${intl.DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
        headers: [
          'اسم المستخدم', 'وقت البدء', 'وقت الإيقاف', 'عنوان IP',
          'عنوان NAS', 'البيانات الواردة', 'البيانات الصادرة', 'سبب الإنهاء',
        ],
        rows: sessions.map((s) => [
          s['username']?.toString() ?? '',
          _formatSessionTime(s['acctstarttime']),
          _formatSessionTime(s['acctstoptime']),
          s['framedipaddress']?.toString() ?? '',
          s['nasipaddress']?.toString() ?? '',
          _formatBytes(s['acctinputoctets']),
          _formatBytes(s['acctoutputoctets']),
          s['acctterminatecause']?.toString() ?? '',
        ]).toList(),
      );
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'فشل تصدير البيانات');
    }
  }

  void _showAdvancedSearch() {
    String ip = _advIp;
    String username = _advUsername;
    String mac = _advMac;
    String fromDate = _advFromDate;
    String toDate = _advToDate;

    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                      child: Container(
                          width: 40, height: 4,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text('البحث المتقدم',
                      style: Theme.of(ctx).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'عنوان IP',
                      prefixIcon: Icon(Icons.language, size: 18),
                      isDense: true,
                    ),
                    textDirection: TextDirection.ltr,
                    controller: TextEditingController(text: ip),
                    onChanged: (v) => ip = v,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم',
                      prefixIcon: Icon(Icons.person, size: 18),
                      isDense: true,
                    ),
                    textDirection: TextDirection.ltr,
                    controller: TextEditingController(text: username),
                    onChanged: (v) => username = v,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'عنوان MAC',
                      prefixIcon: Icon(Icons.router, size: 18),
                      isDense: true,
                    ),
                    textDirection: TextDirection.ltr,
                    controller: TextEditingController(text: mac),
                    onChanged: (v) => mac = v,
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.tryParse(fromDate) ?? DateTime.now().subtract(const Duration(days: 7)),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 1)),
                          );
                          if (d != null) {
                            setSheet(() => fromDate = intl.DateFormat('yyyy-MM-dd').format(d));
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'من تاريخ',
                            prefixIcon: Icon(Icons.calendar_today, size: 16),
                            isDense: true,
                          ),
                          child: Text(fromDate.isEmpty ? '—' : fromDate,
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.tryParse(toDate) ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 1)),
                          );
                          if (d != null) {
                            setSheet(() => toDate = intl.DateFormat('yyyy-MM-dd').format(d));
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'إلى تاريخ',
                            prefixIcon: Icon(Icons.calendar_today, size: 16),
                            isDense: true,
                          ),
                          child: Text(toDate.isEmpty ? '—' : toDate,
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setSheet(() {
                            ip = '';
                            username = '';
                            mac = '';
                            fromDate = '';
                            toDate = '';
                          });
                        },
                        child: const Text('مسح'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() {
                            _advIp = ip;
                            _advUsername = username;
                            _advMac = mac;
                            _advFromDate = fromDate;
                            _advToDate = toDate;
                            _searchCtrl.text = username.isNotEmpty
                                ? username
                                : ip.isNotEmpty
                                    ? ip
                                    : mac;
                          });
                          _load(page: 1);
                        },
                        child: const Text('بحث'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          );
        });
      },
    );
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
        // Search + action buttons
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(page: 1),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'بحث باليوزر أو IP أو MAC',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchCtrl.text.isNotEmpty || _hasAdvancedFilters)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () {
                            setState(() {
                              _searchCtrl.clear();
                              _advIp = '';
                              _advUsername = '';
                              _advMac = '';
                              _advFromDate = '';
                              _advToDate = '';
                            });
                            _load(page: 1);
                          },
                          tooltip: 'مسح البحث',
                        ),
                      IconButton(
                        icon: const Icon(Icons.manage_search_rounded, size: 20),
                        onPressed: _showAdvancedSearch,
                        tooltip: 'بحث متقدم',
                      ),
                    ],
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _SmallBtn(Icons.search_rounded, () => _load(page: 1)),
            const SizedBox(width: 4),
            _SmallBtn(Icons.download_rounded, _exportCsv),
            const SizedBox(width: 4),
            _SmallBtn(Icons.refresh_rounded, () => _load(page: _page)),
          ]),
        ),

        // Pagination
        PaginationBar(
          totalItems: state.sessionsTotal,
          currentPage: _page,
          rowsPerPage: _pageSize,
          itemLabel: 'جلسة',
          onPageChanged: (p) => _load(page: p),
          onRowsPerPageChanged: (r) {
            setState(() => _pageSize = r);
            _load(page: 1);
          },
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

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SmallBtn(this.icon, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .3),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }
}
