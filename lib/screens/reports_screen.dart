import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
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

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with TickerProviderStateMixin {
  late final TabController _tabCtrl;

  static const _tabs = [
    Tab(text: 'سجل الحركات'),
    Tab(text: 'تفعيلات اليوم'),
    Tab(text: 'التفعيلات'),
    Tab(text: 'تقارير مالية'),
    Tab(text: 'الجلسات'),
    Tab(text: 'كشف حساب'),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
            tabs: _tabs,
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: const [
              ActivityLogTab(),
              DailyActivationsTab(),
              ActivationsTab(),
              FinancialTab(),
              SessionsTab(),
              AccountStatementTab(),
            ],
          ),
        ),
      ],
    );
  }
}
