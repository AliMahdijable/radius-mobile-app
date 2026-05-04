import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import 'reports/activity_log_tab.dart';
import 'reports/daily_activations_tab.dart';
import 'reports/activations_tab.dart';
import 'reports/financial_tab.dart';
import 'reports/sessions_tab.dart';
import 'reports/account_statement_tab.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsTabDef {
  final String label;
  final String permission;
  final Widget Function() builder;
  const _ReportsTabDef(this.label, this.permission, this.builder);
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with TickerProviderStateMixin {
  TabController? _tabCtrl;

  static final _allTabs = <_ReportsTabDef>[
    _ReportsTabDef('سجل الحركات', 'reports.activity_log', () => const ActivityLogTab()),
    _ReportsTabDef('تفعيلات اليوم', 'reports.daily_activations', () => const DailyActivationsTab()),
    _ReportsTabDef('التفعيلات', 'reports.activations', () => const ActivationsTab()),
    _ReportsTabDef('تقارير مالية', 'reports.financial', () => const FinancialTab()),
    _ReportsTabDef('الجلسات', 'reports.sessions', () => const SessionsTab()),
    _ReportsTabDef('كشف حساب', 'reports.account_statement', () => const AccountStatementTab()),
  ];

  @override
  void dispose() {
    _tabCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.watch(authProvider).user;
    // فلترة التبويبات حسب صلاحية الفاعل (أدمن = الكل).
    final visibleTabs = _allTabs
        .where((t) => user?.hasEmployeePermission(t.permission) ?? true)
        .toList();
    if (visibleTabs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'لا توجد تقارير متاحة لصلاحياتك',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontFamily: 'Cairo'),
          ),
        ),
      );
    }
    // Re-create TabController if length changed (e.g. perms re-fetched).
    if (_tabCtrl == null || _tabCtrl!.length != visibleTabs.length) {
      _tabCtrl?.dispose();
      _tabCtrl = TabController(length: visibleTabs.length, vsync: this);
    }

    return Column(
      children: [
        Container(
          color: theme.appBarTheme.backgroundColor ?? Colors.white,
          child: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppTheme.primary,
            unselectedLabelColor:
                theme.colorScheme.onSurface.withValues(alpha: .5),
            indicatorColor: AppTheme.primary,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo'),
            unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                fontFamily: 'Cairo'),
            dividerColor: isDark ? Colors.white10 : Colors.grey.shade200,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tabs: visibleTabs.map((t) => Tab(text: t.label)).toList(),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: visibleTabs.map((t) => t.builder()).toList(),
          ),
        ),
      ],
    );
  }
}
