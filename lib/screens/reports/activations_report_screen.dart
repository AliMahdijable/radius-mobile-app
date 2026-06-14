import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/reports_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'widgets/date_range_chip.dart';
import 'widgets/report_log_tile.dart';

/// التفعيلات — كل صفوف SUBSCRIBER_ACTIVATE في الفترة + إجمالي.
class ActivationsReportScreen extends StatefulWidget {
  const ActivationsReportScreen({super.key});

  @override
  State<ActivationsReportScreen> createState() =>
      _ActivationsReportScreenState();
}

class _ActivationsReportScreenState extends State<ActivationsReportScreen> {
  DateRange _range = DateRange.thisMonth();
  List<ActivityRow> _rows = const [];
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
    final r = await ReportsApi.activities(
      from: _range.from,
      to: _range.to,
      actionType: 'SUBSCRIBER_ACTIVATE',
      limit: 300,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _rows = r.rows;
      _error = r.ok ? null : (r.error ?? 'تعذّر التحميل');
    });
  }

  num get _totalCash {
    num s = 0;
    for (final r in _rows) {
      final isCash = (r.actionDescription ?? '').contains('نقدي') &&
          !(r.actionDescription ?? '').contains('غير نقدي');
      if (isCash) s += r.amount;
    }
    return s;
  }

  int get _cashCount => _rows.where((r) {
        final d = r.actionDescription ?? '';
        return d.contains('نقدي') && !d.contains('غير نقدي');
      }).length;
  int get _nonCashCount => _rows.where((r) {
        final d = r.actionDescription ?? '';
        return d.contains('غير نقدي');
      }).length;

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
          'التفعيلات',
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.brand,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              DateRangeChipBar(
                value: _range,
                onChanged: (r) {
                  setState(() => _range = r);
                  _load();
                },
              ),
              const SizedBox(height: Sp.md),
              _summary(),
              const SizedBox(height: Sp.md),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: Sp.huge),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _errorBlock()
              else if (_rows.isEmpty)
                _emptyBlock()
              else
                for (final r in _rows) ...[
                  ReportLogTile(
                    actionType: r.actionType,
                    description: r.actionDescription ?? '',
                    amount: r.amount,
                    adminUsername: r.adminUsername,
                    employeeFullName: r.actingEmployeeFullName,
                    targetName: r.targetName ?? r.userUsername,
                    createdAt: r.createdAt,
                  ),
                  const SizedBox(height: 4),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary() {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _stat(
              icon: LucideIcons.zap,
              label: 'إجمالي',
              value: '${_rows.length}',
              color: const Color(0xFF14B8A6),
            ),
          ),
          Container(width: 1, height: 32, color: AppColors.border),
          Expanded(
            child: _stat(
              icon: LucideIcons.banknote,
              label: 'نقدي',
              value: '$_cashCount',
              color: const Color(0xFF14B8A6),
            ),
          ),
          Container(width: 1, height: 32, color: AppColors.border),
          Expanded(
            child: _stat(
              icon: LucideIcons.creditCard,
              label: 'غير نقدي',
              value: '$_nonCashCount',
              color: const Color(0xFFE08F2D),
            ),
          ),
          Container(width: 1, height: 32, color: AppColors.border),
          Expanded(
            child: _stat(
              icon: LucideIcons.dollarSign,
              label: 'إيراد',
              value: formatIQD(_totalCash),
              color: AppColors.brand,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
              color: AppColors.textHi,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        Text(label,
            style: AppType.muted().copyWith(fontSize: 10),
            maxLines: 1),
      ],
    );
  }

  Widget _emptyBlock() => Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.huge),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.zapOff, size: 36, color: AppColors.textLow),
              const SizedBox(height: 10),
              Text('لا توجد تفعيلات في هذه الفترة',
                  style: AppType.label(color: AppColors.textMid)),
            ],
          ),
        ),
      );

  Widget _errorBlock() => Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.xl),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.triangleAlert, size: 32, color: AppColors.error),
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
      );
}
