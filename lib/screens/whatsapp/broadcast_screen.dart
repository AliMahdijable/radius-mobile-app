import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/messages_provider.dart';
import '../../providers/subscribers_provider.dart';
import '../../models/subscriber_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/helpers.dart';
import '../../widgets/app_snackbar.dart';

enum _TabType { general, specific, expiredSpecific, debtors, debtorsSpecific }

class _TabConfig {
  final String key;
  final String label;
  final String apiType;
  final bool hasCustomMessage;
  final bool hasSubscriberSelection;
  final IconData icon;

  const _TabConfig({
    required this.key,
    required this.label,
    required this.apiType,
    required this.hasCustomMessage,
    required this.hasSubscriberSelection,
    required this.icon,
  });
}

const _tabs = <_TabType, _TabConfig>{
  _TabType.general: _TabConfig(
    key: 'general',
    label: 'تبليغ عام',
    apiType: 'general',
    hasCustomMessage: true,
    hasSubscriberSelection: false,
    icon: Icons.campaign,
  ),
  _TabType.specific: _TabConfig(
    key: 'specific',
    label: 'تبليغ محدد',
    apiType: 'general',
    hasCustomMessage: true,
    hasSubscriberSelection: true,
    icon: Icons.person_search,
  ),
  _TabType.expiredSpecific: _TabConfig(
    key: 'expired_specific',
    label: 'منتهي الاشتراك',
    apiType: 'expired',
    hasCustomMessage: true,
    hasSubscriberSelection: true,
    icon: Icons.timer_off,
  ),
  _TabType.debtors: _TabConfig(
    key: 'debtors',
    label: 'تبليغ ديون عام',
    apiType: 'debtors',
    hasCustomMessage: false,
    hasSubscriberSelection: false,
    icon: Icons.credit_card,
  ),
  _TabType.debtorsSpecific: _TabConfig(
    key: 'debtors_specific',
    label: 'تبليغ ديون محدد',
    apiType: 'debtors',
    hasCustomMessage: false,
    hasSubscriberSelection: true,
    icon: Icons.credit_score,
  ),
};

class BroadcastScreen extends ConsumerStatefulWidget {
  const BroadcastScreen({super.key});

  @override
  ConsumerState<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends ConsumerState<BroadcastScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  final _messageControllers = <_TabType, TextEditingController>{};
  final _searchControllers = <_TabType, TextEditingController>{};
  final _selectedUsernames = <_TabType, Set<String>>{};
  final _searchQueries = <_TabType, String>{};
  bool _subscribersLoaded = false;

  static const _tabOrder = [
    _TabType.general,
    _TabType.specific,
    _TabType.expiredSpecific,
    _TabType.debtors,
    _TabType.debtorsSpecific,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabOrder.length, vsync: this);
    _tabController.addListener(_onTabChanged);

    for (final tab in _tabOrder) {
      final config = _tabs[tab]!;
      if (config.hasCustomMessage) {
        _messageControllers[tab] = TextEditingController();
      }
      if (config.hasSubscriberSelection) {
        _searchControllers[tab] = TextEditingController();
        _selectedUsernames[tab] = {};
        _searchQueries[tab] = '';
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    for (final c in _messageControllers.values) {
      c.dispose();
    }
    for (final c in _searchControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    final tab = _tabOrder[_tabController.index];
    final config = _tabs[tab]!;
    if (config.hasSubscriberSelection && !_subscribersLoaded) {
      _loadSubscribers();
    }
  }

  void _loadSubscribers() {
    if (_subscribersLoaded) return;
    _subscribersLoaded = true;
    final subs = ref.read(subscribersProvider).subscribers;
    if (subs.isEmpty) {
      ref.read(subscribersProvider.notifier).loadSubscribers();
    }
  }

  List<SubscriberModel> _getFilteredSubscribers(_TabType tab) {
    final subs = ref.watch(subscribersProvider).subscribers;
    List<SubscriberModel> filtered;

    switch (tab) {
      case _TabType.specific:
        filtered = subs.where((s) => s.displayPhone.isNotEmpty).toList();
        break;
      case _TabType.expiredSpecific:
        filtered = subs.where((s) => s.isExpired).toList();
        break;
      case _TabType.debtorsSpecific:
        filtered =
            subs.where((s) => s.hasDebt && s.debtAmount.abs() > 0).toList();
        break;
      default:
        filtered = subs;
    }

    final query = (_searchQueries[tab] ?? '').toLowerCase().trim();
    if (query.isNotEmpty) {
      filtered = filtered.where((s) {
        return s.username.toLowerCase().contains(query) ||
            s.fullName.toLowerCase().contains(query) ||
            s.displayPhone.contains(query) ||
            (s.profileName ?? '').toLowerCase().contains(query);
      }).toList();
    }

    return filtered;
  }

  Future<void> _startBroadcast(_TabType tab) async {
    final config = _tabs[tab]!;
    final message = _messageControllers[tab]?.text.trim() ?? '';

    if (config.hasCustomMessage && message.isEmpty) {
      AppSnackBar.warning(context, 'يرجى كتابة الرسالة');
      return;
    }

    if (config.hasSubscriberSelection) {
      final selected = _selectedUsernames[tab] ?? {};
      if (selected.isEmpty) {
        AppSnackBar.warning(context, 'يرجى تحديد مشترك واحد على الأقل');
        return;
      }
    }

    final selectedCount = config.hasSubscriberSelection
        ? (_selectedUsernames[tab]?.length ?? 0)
        : null;

    final targetLabel = config.hasSubscriberSelection
        ? '$selectedCount مشترك محدد'
        : config.label;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد البث'),
        content: Text(
          'سيتم إرسال الرسالة إلى $targetLabel. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final targetUsernames = config.hasSubscriberSelection
        ? (_selectedUsernames[tab] ?? {}).toList()
        : null;

    await ref.read(messagesProvider.notifier).startBroadcast(
          message: config.hasCustomMessage ? message : '',
          type: config.apiType,
          targetUsernames: targetUsernames,
        );
  }

  void _selectAll(_TabType tab) {
    final subs = _getFilteredSubscribers(tab);
    setState(() {
      _selectedUsernames[tab] = subs.map((s) => s.username).toSet();
    });
  }

  void _deselectAll(_TabType tab) {
    setState(() {
      _selectedUsernames[tab] = {};
    });
  }

  void _toggleSubscriber(_TabType tab, String username) {
    setState(() {
      final set = _selectedUsernames[tab] ??= {};
      if (set.contains(username)) {
        set.remove(username);
      } else {
        set.add(username);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: _tabOrder.length,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('التبليغات'),
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              indicatorColor: theme.colorScheme.primary,
              tabs: _tabOrder.map((tab) {
                final config = _tabs[tab]!;
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(config.icon, size: 18),
                      const SizedBox(width: 6),
                      Text(config.label),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children:
                _tabOrder.map((tab) => _buildTabBody(tab, theme)).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBody(_TabType tab, ThemeData theme) {
    final config = _tabs[tab]!;
    final state = ref.watch(messagesProvider);
    final broadcast = state.broadcast;
    final isActive = broadcast?.isActive ?? false;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (broadcast != null && broadcast.isActive)
          _buildProgressPanel(broadcast, theme),
        if (broadcast != null &&
            !broadcast.isActive &&
            broadcast.event == 'complete')
          _buildCompletePanel(broadcast, theme),
        if (config.hasSubscriberSelection) ...[
          _buildSubscriberSection(tab, config, theme),
          const SizedBox(height: 16),
        ],
        if (config.hasCustomMessage) ...[
          _buildMessageField(tab, theme),
          const SizedBox(height: 16),
        ],
        if (!config.hasCustomMessage) ...[
          _buildDebtInfoCard(theme),
          const SizedBox(height: 16),
        ],
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: isActive ? null : () => _startBroadcast(tab),
            icon: const Icon(Icons.campaign),
            label: const Text(
              'بدء البث',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildProgressPanel(BroadcastProgress broadcast, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.infoColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (broadcast.isPaused)
                const Icon(Icons.pause_circle, color: Colors.orange, size: 24)
              else
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const SizedBox(width: 10),
              Text(
                broadcast.isPaused
                    ? 'توقف مؤقت (${broadcast.pauseSeconds ?? 0} ثانية)'
                    : 'جاري البث...',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: broadcast.total > 0
                  ? (broadcast.sent + broadcast.failed) / broadcast.total
                  : 0,
              minHeight: 8,
              backgroundColor: Colors.grey.withOpacity(0.2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ProgressStat(
                  label: 'مرسلة', value: broadcast.sent, color: Colors.green),
              _ProgressStat(
                  label: 'فاشلة', value: broadcast.failed, color: Colors.red),
              _ProgressStat(
                  label: 'الإجمالي',
                  value: broadcast.total,
                  color: AppTheme.infoColor),
            ],
          ),
          if (broadcast.currentUser != null) ...[
            const SizedBox(height: 8),
            Text(
              'الحالي: ${broadcast.currentUser}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(messagesProvider.notifier).cancelBroadcast(),
            icon: const Icon(Icons.stop, color: Colors.red),
            label:
                const Text('إيقاف البث', style: TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletePanel(BroadcastProgress broadcast, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 40),
          const SizedBox(height: 10),
          const Text(
            'اكتمل البث',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'مرسلة: ${broadcast.sent} | فاشلة: ${broadcast.failed}',
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriberSection(
      _TabType tab, _TabConfig config, ThemeData theme) {
    final subsState = ref.watch(subscribersProvider);

    if (subsState.isLoading) {
      if (!_subscribersLoaded) _loadSubscribers();
      return Container(
        padding: const EdgeInsets.all(40),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final filteredSubs = _getFilteredSubscribers(tab);
    final selected = _selectedUsernames[tab] ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchControllers[tab],
          decoration: InputDecoration(
            hintText: 'بحث عن مشترك...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: (_searchQueries[tab] ?? '').isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchControllers[tab]!.clear();
                      setState(() => _searchQueries[tab] = '');
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          onChanged: (val) => setState(() => _searchQueries[tab] = val),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _ActionChip(
              label: 'تحديد الكل',
              icon: Icons.select_all,
              onTap: () => _selectAll(tab),
            ),
            const SizedBox(width: 8),
            _ActionChip(
              label: 'إلغاء التحديد',
              icon: Icons.deselect,
              onTap: () => _deselectAll(tab),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${selected.length} / ${filteredSubs.length}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          constraints: const BoxConstraints(maxHeight: 350),
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.5),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: filteredSubs.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'لا يوجد مشتركين',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: filteredSubs.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: theme.dividerColor.withOpacity(0.3),
                  ),
                  itemBuilder: (context, index) {
                    final sub = filteredSubs[index];
                    final isSelected = selected.contains(sub.username);
                    final isDebtTab = tab == _TabType.debtorsSpecific;
                    return _SubscriberTile(
                      subscriber: sub,
                      isSelected: isSelected,
                      showDebt: isDebtTab,
                      onToggle: () => _toggleSubscriber(tab, sub.username),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMessageField(_TabType tab, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'نص الرسالة',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _messageControllers[tab],
          maxLines: 6,
          decoration: InputDecoration(
            hintText: 'اكتب رسالة البث هنا...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDebtInfoCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.warningColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warningColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: AppTheme.warningColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'سيتم إرسال رسالة الديون باستخدام قالب تذكير الديون المحفوظ في إعدادات واتساب',
              style: TextStyle(
                color: AppTheme.warningColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.4),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _SubscriberTile extends StatelessWidget {
  final SubscriberModel subscriber;
  final bool isSelected;
  final bool showDebt;
  final VoidCallback onToggle;

  const _SubscriberTile({
    required this.subscriber,
    required this.isSelected,
    required this.showDebt,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onToggle,
      child: Container(
        color: isSelected
            ? theme.colorScheme.primary.withOpacity(0.06)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: isSelected,
                onChanged: (_) => onToggle(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subscriber.fullName.trim().isNotEmpty
                        ? subscriber.fullName
                        : subscriber.username,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        subscriber.username,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      if (subscriber.displayPhone.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.phone, size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 2),
                        Text(
                          subscriber.displayPhone,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (showDebt && subscriber.debtAmount.abs() > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.dangerColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  AppHelpers.formatMoney(subscriber.debtAmount.abs()),
                  style: const TextStyle(
                    color: AppTheme.dangerColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProgressStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _ProgressStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ],
    );
  }
}
