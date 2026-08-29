import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/reports_api.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'widgets/report_export.dart';
import 'widgets/report_filters.dart';
import 'widgets/report_pagination.dart';
import 'widgets/report_permission_gate.dart';

/// تقرير الجلسات — الـonline حالياً + history.
/// Toggle بين "متصلون الآن" و "كل الجلسات (أحدث 200)".
class SessionsReportScreen extends StatefulWidget {
  const SessionsReportScreen({super.key});

  @override
  State<SessionsReportScreen> createState() => _SessionsReportScreenState();
}

class _SessionsReportScreenState extends State<SessionsReportScreen> {
  bool _onlineOnly = true;
  List<SessionRow> _rows = const [];
  bool _loading = true;
  String? _error;
  int _page = 0;
  int _pageSize = 25;
  final _searchCtrl = TextEditingController();
  String _searchField = 'username'; // username / ip / mac
  String _searchValue = '';

  /// فلتر مدير المستخدم — client-side (SAS4 sessions ما تستقبل هذا الـparam).
  ReportFilters _filters = const ReportFilters();

  List<SessionRow> get _visibleRows {
    final um = _filters.userManager;
    if (um == null || um.isEmpty) return _rows;
    return _rows.where((s) => s.userManager == um).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await ReportsApi.sessions(
      onlineOnly: _onlineOnly,
      limit: 2000,
      username: _searchField == 'username' ? _searchValue : null,
      ip: _searchField == 'ip' ? _searchValue : null,
      mac: _searchField == 'mac' ? _searchValue : null,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _rows = r.rows;
      _error = r.ok ? null : (r.error ?? 'common.load_failed'.tr());
      _page = 0;
    });
  }

  // الـexport يعكس الفلتر (visible فقط).
  List<List<String>> get _exportRows => _visibleRows
      .map((s) => [
            s.username ?? '',
            s.ipAddress ?? '',
            s.mac ?? '',
            s.userManager ?? '',
            _humanBytes(s.bytesIn),
            _humanBytes(s.bytesOut),
            s.startedAt ?? '',
            s.endedAt ?? '',
            s.isOnline ? 'subscribers.status_online'.tr() : 'subscribers.status_expired'.tr(),
          ])
      .toList();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final visible = _visibleRows;
    final totalPages =
        (visible.length / _pageSize).ceil().clamp(1, 99999);
    final pageStart = _page * _pageSize;
    final pageEnd = (pageStart + _pageSize).clamp(0, visible.length);
    final pageRows = visible.isEmpty
        ? const <SessionRow>[]
        : visible.sublist(pageStart, pageEnd);

    return ReportPermissionGate(
      permission: 'reports.sessions',
      title: 'reports.sessions'.tr(),
      child: Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'reports.sessions'.tr(),
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
              child: Column(
                children: [
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: true,
                        label: Text('reports.online_now'.tr()),
                        icon: const Icon(LucideIcons.wifi, size: 14),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('common.all'.tr()),
                        icon: const Icon(LucideIcons.history, size: 14),
                      ),
                    ],
                    selected: {_onlineOnly},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) {
                      HapticFeedback.selectionClick();
                      setState(() => _onlineOnly = s.first);
                      _load();
                    },
                  ),
                  const SizedBox(height: Sp.sm),
                  // شريط بحث + منتقي حقل (username / ip / mac).
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onSubmitted: (v) {
                            _searchValue = v.trim();
                            _load();
                          },
                          decoration: InputDecoration(
                            hintText: _searchField == 'username'
                                ? 'reports.search_by_username'.tr()
                                : _searchField == 'ip'
                                    ? 'reports.search_by_ip'.tr()
                                    : 'reports.search_by_mac'.tr(),
                            hintStyle: AppType.input(color: AppColors.textLow),
                            prefixIcon: Icon(LucideIcons.search,
                                size: 18, color: AppColors.textMid),
                            suffixIcon: _searchValue.isEmpty
                                ? null
                                : IconButton(
                                    icon: Icon(LucideIcons.x,
                                        size: 16,
                                        color: AppColors.textMid),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _searchValue = '';
                                      _load();
                                    },
                                  ),
                            filled: true,
                            fillColor: AppColors.surfaceInput,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(R.sm),
                              borderSide:
                                  BorderSide(color: AppColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(R.sm),
                              borderSide:
                                  BorderSide(color: AppColors.border),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _SearchFieldPicker(
                        current: _searchField,
                        onChange: (v) {
                          setState(() {
                            _searchField = v;
                            _searchCtrl.clear();
                            _searchValue = '';
                          });
                          _load();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.sm),
              child: Column(
                children: [
                  // فلتر مدير المستخدم فقط (لا actionManager/employee/actionTypes
                  // لأن مصدر الجلسات هو SAS4 UserSessions، ليس activity_logs).
                  ReportFiltersPanel(
                    value: _filters,
                    includeActionTypes: false,
                    includeActionManager: false,
                    includeEmployee: false,
                    onChanged: (v) {
                      setState(() {
                        _filters = v;
                        _page = 0;
                      });
                    },
                  ),
                  const SizedBox(height: Sp.sm),
                  Row(
                    children: [
                      Icon(LucideIcons.activity,
                          size: 14, color: AppColors.textMid),
                      const SizedBox(width: 6),
                      Text(
                        _loading
                            ? '...'
                            : '${visible.length} ${_onlineOnly ? 'reports.online_users'.tr() : 'reports.session_singular'.tr()}',
                        style: AppType.muted().copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: AppColors.brand,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? _errorState()
                        : _rows.isEmpty
                            ? _emptyState()
                            : ListView(
                                padding: const EdgeInsets.fromLTRB(
                                    Sp.lg, 0, Sp.lg, Sp.huge),
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ReportStatsBar(
                                          totalItems: visible.length,
                                          pageStart: pageStart,
                                          pageEnd: pageEnd,
                                          pageSize: _pageSize,
                                          onPageSizeChange: (s) =>
                                              setState(() {
                                            _pageSize = s;
                                            _page = 0;
                                          }),
                                        ),
                                      ),
                                      ReportExportBar(
                                        title: _onlineOnly
                                            ? 'reports.online_sessions'.tr()
                                            : 'reports.all_sessions'.tr(),
                                        subtitle:
                                            '${'reports.row_count'.tr()}: ${visible.length}',
                                        fileNameBase: _onlineOnly
                                            ? 'sessions_online'
                                            : 'sessions_all',
                                        columns: [
                                          'reports.col_username'.tr(),
                                          'IP',
                                          'MAC',
                                          'reports.col_manager'.tr(),
                                          'subscribers.label_download'.tr(),
                                          'subscribers.label_upload'.tr(),
                                          'reports.col_start'.tr(),
                                          'reports.col_end'.tr(),
                                          'subscribers.status'.tr(),
                                        ],
                                        rows: _exportRows,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: Sp.sm),
                                  for (final s in pageRows) ...[
                                    _sessionTile(s),
                                    const SizedBox(height: 6),
                                  ],
                                  if (totalPages > 1)
                                    ReportPager(
                                      page: _page,
                                      totalPages: totalPages,
                                      onPrev: () => setState(() => _page--),
                                      onNext: () => setState(() => _page++),
                                    ),
                                ],
                              ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _sessionTile(SessionRow s) {
    final online = s.isOnline;
    final dot = online ? const Color(0xFF14B8A6) : AppColors.textLow;
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: dot.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(online ? LucideIcons.wifi : LucideIcons.wifiOff,
                size: 16, color: dot),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.username ?? '—',
                  style: AppType.label(color: AppColors.textHi)
                      .copyWith(fontSize: 13, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (s.ipAddress != null && s.ipAddress!.isNotEmpty) ...[
                      Icon(LucideIcons.wifi,
                          size: 10, color: AppColors.textLow),
                      const SizedBox(width: 3),
                      Text(s.ipAddress!,
                          style: AppType.muted().copyWith(fontSize: 10)),
                      const SizedBox(width: 8),
                    ],
                    if (s.userManager != null && s.userManager!.isNotEmpty) ...[
                      Icon(LucideIcons.shield,
                          size: 10, color: AppColors.textLow),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(s.userManager!,
                            style: AppType.muted().copyWith(fontSize: 10),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ],
                ),
                if (s.mac != null && s.mac!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(LucideIcons.smartphone,
                          size: 10, color: AppColors.textLow),
                      const SizedBox(width: 3),
                      Text(
                        'MAC: ${s.mac!}',
                        style: AppType.muted().copyWith(
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
                if (s.bytesIn > 0 || s.bytesOut > 0) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(LucideIcons.arrowDown,
                          size: 10, color: AppColors.brand),
                      const SizedBox(width: 3),
                      Text(_humanBytes(s.bytesIn),
                          style: AppType.muted().copyWith(
                              fontSize: 10, color: AppColors.brand)),
                      const SizedBox(width: 10),
                      Icon(LucideIcons.arrowUp,
                          size: 10, color: const Color(0xFFE08F2D)),
                      const SizedBox(width: 3),
                      Text(_humanBytes(s.bytesOut),
                          style: AppType.muted().copyWith(
                              fontSize: 10,
                              color: const Color(0xFFE08F2D))),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _humanBytes(num b) {
    if (b < 1024) return '${b.round()} B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _emptyState() => ListView(
        children: [
          const SizedBox(height: Sp.huge * 2),
          Center(
            child: Column(
              children: [
                Icon(LucideIcons.wifiOff, size: 36, color: AppColors.textLow),
                const SizedBox(height: 10),
                Text(_onlineOnly ? 'reports.no_online'.tr() : 'reports.no_sessions'.tr(),
                    style: AppType.label(color: AppColors.textMid)),
              ],
            ),
          ),
        ],
      );

  Widget _errorState() => ListView(
        children: [
          const SizedBox(height: Sp.huge),
          Center(
            child: Column(
              children: [
                Icon(LucideIcons.triangleAlert,
                    size: 32, color: AppColors.error),
                const SizedBox(height: 8),
                Text(_error!,
                    style: AppType.subtitle(color: AppColors.textMid)),
                const SizedBox(height: Sp.md),
                ElevatedButton.icon(
                  onPressed: _load,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: Text('common.retry'.tr()),
                ),
              ],
            ),
          ),
        ],
      );
}

/// منتقي حقل البحث في الجلسات (username / IP / MAC).
class _SearchFieldPicker extends StatelessWidget {
  const _SearchFieldPicker({required this.current, required this.onChange});
  final String current;
  final ValueChanged<String> onChange;

  // ملاحظة: اسم الحقل هنا مفتاح ترجمة، نستدعي .tr() عند العرض في itemBuilder.
  static const _fields = [
    ('username', 'reports.field_name', LucideIcons.user),
    ('ip', 'IP', LucideIcons.globe),
    ('mac', 'MAC', LucideIcons.wifi),
  ];

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: 'reports.search_field'.tr(),
      onSelected: onChange,
      itemBuilder: (_) => [
        for (final f in _fields)
          PopupMenuItem(
            value: f.$1,
            child: Row(
              children: [
                Icon(f.$3, size: 14, color: AppColors.textMid),
                const SizedBox(width: 8),
                Text(f.$2.startsWith('reports.') ? f.$2.tr() : f.$2),
              ],
            ),
          ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              current == 'username'
                  ? LucideIcons.user
                  : current == 'ip'
                      ? LucideIcons.globe
                      : LucideIcons.wifi,
              size: 15,
              color: AppColors.textMid,
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown,
                size: 12, color: AppColors.textLow),
          ],
        ),
      ),
    );
  }
}

