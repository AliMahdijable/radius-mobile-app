import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/reports_api.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await ReportsApi.sessions(onlineOnly: _onlineOnly, limit: 200);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _rows = r.rows;
      _error = r.ok ? null : (r.error ?? 'تعذّر التحميل');
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'الجلسات',
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('متصلون الآن'),
                    icon: Icon(LucideIcons.wifi, size: 14),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('الكل'),
                    icon: Icon(LucideIcons.history, size: 14),
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
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.sm),
              child: Row(
                children: [
                  Icon(LucideIcons.activity,
                      size: 14, color: AppColors.textMid),
                  const SizedBox(width: 6),
                  Text(
                    _loading
                        ? '...'
                        : '${_rows.length} ${_onlineOnly ? 'مستخدم متصل' : 'جلسة'}',
                    style: AppType.muted().copyWith(fontSize: 12),
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
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                    Sp.lg, 0, Sp.lg, Sp.huge),
                                itemCount: _rows.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (_, i) => _sessionTile(_rows[i]),
                              ),
              ),
            ),
          ],
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
                Text(_onlineOnly ? 'لا يوجد متصلون الآن' : 'لا توجد جلسات',
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
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ],
      );
}

