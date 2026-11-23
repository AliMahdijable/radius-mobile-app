import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/field_team_api.dart';
import '../../core/util/bidi.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/merged_section.dart';
import '../desktop/desk_widgets.dart';
import 'field_new_task_sheet.dart';
import 'field_staff_tab.dart';
import 'field_task_screen.dart';
import 'field_team_widgets.dart';
import 'field_types_tab.dart';

/// «الصيانة والمبيعات» (٢٣ نوفمبر — المالك): فريقٌ ميدانيّ لكلّ مدير — حساباتٌ مستقلّة (تُحسب من حدّ الموظّفين) أو موظّفوه أنفسهم،
/// يعملون من رابط التطبيق /team. التذكرة من تطبيق المشترك تصير مهمّةً حسب نوعها (تلقائيّاً لشخصٍ، أو بانتظار إسناده)، والفنّي
/// «في الطريق/قيد العمل» ⇒ تذكرة المشترك «قيد المعالجة»، و«تمّ الإنجاز» ⇒ «تمّ الحلّ». الأقسام الثلاثة كالموقع (7ccfb8e):
/// المهامّ (بلاطات الإحصاء وشرائح الحال والبطاقات)، الفريق (رمز الرابط وحال كلّ شخص)، الأنواع والإسناد (تلقائيّ/يدويّ).
class FieldTeamScreen extends StatefulWidget {
  const FieldTeamScreen({super.key, this.openTaskId});

  /// مهمّةٌ تُفتح مباشرةً (من تذكرةٍ صارت مهمّة).
  final int? openTaskId;

  /// «كل الشركات»: فريق كلّ صفحةٍ ومهامّها لها وحدها (الموقع لا يسأل عنه في الوضع المدموج) ⇒ للمفتوحة وحدها.
  static Widget mergedPage() => const MergedSection.openOnly(
        title: kFieldTeamTitle,
        reason: 'فريق كلّ صفحةٍ ومهامّها لها وحدها',
        child: FieldTeamScreen(),
      );

  @override
  State<FieldTeamScreen> createState() => _FieldTeamScreenState();
}

const kFieldTeamTitle = 'الصيانة والمبيعات';

enum _Tab { tasks, staff, types }

class _FieldTeamScreenState extends State<FieldTeamScreen> {
  FieldSummary? _summary;
  bool _loading = true;
  _Tab _tab = _Tab.tasks;

  /// يتغيّر بسحب التحديث وبعد كلّ تعديل ⇒ التبويب يقرأ من جديد.
  int _tick = 0;
  Timer? _poll;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSummary());
    // الأعداد تتبع ما يفعله الفريق (كالموقع: كلّ دقيقة)
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => unawaited(_loadSummary(quiet: true)));
    final open = widget.openTaskId;
    if (open != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openTask(open));
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadSummary({bool quiet = false}) async {
    final seq = ++_seq;
    if (!quiet && _summary == null) setState(() => _loading = true);
    final s = await FieldTeamApi.summary();
    if (!mounted || seq != _seq) return;
    if (s != null) FieldTeamState.remember(s);
    setState(() {
      _loading = false;
      if (s != null || _summary == null) _summary = s;
    });
  }

  /// تغيّر شيءٌ (إنشاء، إسناد، إيقاف…) ⇒ الأعداد والتبويب من جديد.
  void _changed() {
    setState(() => _tick++);
    unawaited(_loadSummary(quiet: true));
  }

  Future<void> _refresh() async {
    setState(() => _tick++);
    await _loadSummary(quiet: true);
  }

  Future<void> _openTask(int id) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => FieldTaskScreen(taskId: id)),
    );
    if (mounted && changed == true) _changed();
  }

  Future<void> _newTask() async {
    final created = await showFieldSheet<bool>(context, const FieldNewTaskSheet());
    if (mounted && created == true) _changed();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppColors.textHi),
          title: Text(kFieldTeamTitle, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        ),
        title: kFieldTeamTitle,
        subtitle: 'تذاكر المشتركين ومهامّ الصيانة تصل فريقك على هواتفهم، وتتابع كلّ خطوةٍ منها هنا',
      ),
      body: MergedSectionBody(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final s = _summary;
    Widget single(Widget child) => RefreshIndicator(
          onRefresh: () => _loadSummary(),
          child: ListView(padding: const EdgeInsets.all(Sp.lg), children: [child]),
        );
    if (s == null) {
      return single(const FieldCenterState(
        key: ValueKey('field-failed'),
        icon: LucideIcons.wifiOff,
        title: 'تعذّر جلب القسم الآن',
        sub: 'اسحب للأسفل لإعادة المحاولة',
      ));
    }
    if (!s.available) {
      return single(const FieldCenterState(
        key: ValueKey('field-off'),
        icon: LucideIcons.hardHat,
        title: '«الصيانة والمبيعات» غير مفعّلة لحسابك بعد',
      ));
    }
    if (!s.canManage) {
      return single(const FieldCenterState(
        key: ValueKey('field-locked'),
        icon: LucideIcons.lock,
        tone: AppTone.warning,
        title: 'القسم لمدير الصفحة وحده الآن',
        sub: 'مدير الصفحة يدير الفريق والمهامّ — وصلاحيّات الموظّف فيه بالمرحلة القادمة',
      ));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.xs),
        child: SheetSegmented(
          key: const ValueKey('field-tabs'),
          // بلا أيقونات كالموقع — ثلاثة أقسامٍ تتّسع لـ٣٢٠ بخطٍّ مكبَّر بلا قصّ
          labels: ['المهامّ', s.staffCount > 0 ? 'الفريق (${s.staffCount})' : 'الفريق', 'الأنواع'],
          selectedIndex: _tab.index,
          onSelect: (i) => setState(() => _tab = _Tab.values[i]),
        ),
      ),
      Expanded(
        child: switch (_tab) {
          _Tab.tasks => FieldTasksTab(
              key: const ValueKey('field-tab-tasks'),
              summary: s,
              tick: _tick,
              onRefresh: _refresh,
              onOpen: _openTask,
              onNew: _newTask,
            ),
          _Tab.staff => FieldStaffTab(key: const ValueKey('field-tab-staff'), tick: _tick, onChanged: _changed, onRefresh: _refresh),
          _Tab.types => FieldTypesTab(key: const ValueKey('field-tab-types'), tick: _tick, onChanged: _changed, onRefresh: _refresh),
        },
      ),
    ]);
  }
}

// ─────────────────────────── المهامّ ───────────────────────────

class FieldTasksTab extends StatefulWidget {
  const FieldTasksTab({
    super.key,
    required this.summary,
    required this.tick,
    required this.onRefresh,
    required this.onOpen,
    required this.onNew,
  });
  final FieldSummary summary;
  final int tick;
  final Future<void> Function() onRefresh;
  final Future<void> Function(int id) onOpen;
  final Future<void> Function() onNew;

  @override
  State<FieldTasksTab> createState() => _FieldTasksTabState();
}

class _FieldTasksTabState extends State<FieldTasksTab> {
  // كالموقع: «بانتظار الإسناد» أوّلاً إن كان فيها شيء، وإلّا «الجارية»
  late FieldTaskFilter _filter = widget.summary.waiting > 0 ? FieldTaskFilter.waiting : FieldTaskFilter.active;
  final _term = TextEditingController();
  String _query = '';
  Timer? _debounce;
  Timer? _poll;
  List<FieldTask> _items = const [];
  bool _hasMore = false;
  int _next = 0;
  bool _loading = true;
  bool _more = false;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // ما يفعله الفنّي يظهر خلال نصف دقيقة (كالموقع)
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_load(quiet: true)));
  }

  @override
  void didUpdateWidget(covariant FieldTasksTab old) {
    super.didUpdateWidget(old);
    if (old.tick != widget.tick) unawaited(_load(quiet: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _poll?.cancel();
    _term.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final seq = ++_seq;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    // التحديث الهادئ يعيد الصفحات المعروضة كلّها (لا تختفي ما حُمّل بـ«عرض المزيد»)
    final want = quiet ? _items.length.clamp(FieldTeamApi.pageSize, 100) : FieldTeamApi.pageSize;
    final rows = <FieldTask>[];
    var offset = 0;
    var hasMore = false;
    String? error;
    while (true) {
      final r = await FieldTeamApi.tasks(filter: _filter, query: _query, offset: offset);
      if (!mounted || seq != _seq) return;
      final p = r.page;
      if (p == null) {
        error = r.error;
        break;
      }
      rows.addAll(p.items);
      hasMore = p.hasMore;
      offset = p.nextOffset;
      if (!p.hasMore || rows.length >= want || p.items.isEmpty) break;
    }
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (error != null) {
        if (!quiet || _items.isEmpty) _error = error;
        return;
      }
      _error = null;
      _items = rows;
      _hasMore = hasMore;
      _next = offset;
    });
  }

  Future<void> _loadMore() async {
    if (_more || !_hasMore) return;
    setState(() => _more = true);
    final seq = _seq;
    final r = await FieldTeamApi.tasks(filter: _filter, query: _query, offset: _next);
    if (!mounted || seq != _seq) return;
    setState(() {
      _more = false;
      final p = r.page;
      if (p == null) return;
      final seen = {for (final t in _items) t.id};
      _items = [..._items, ...p.items.where((t) => !seen.contains(t.id))];
      _hasMore = p.hasMore;
      _next = p.nextOffset;
    });
  }

  void _setFilter(FieldTaskFilter f) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _items = const [];
    });
    unawaited(_load());
  }

  void _onTerm(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = v.trim();
      if (q == _query) return;
      _query = q;
      unawaited(_load());
    });
  }

  Future<void> _refresh() async {
    await Future.wait([widget.onRefresh(), _load(quiet: true)]);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = widget.summary;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.huge),
        children: [
          _StatGrid(
            tiles: [
              _Stat(LucideIcons.hourglass, AppTone.warning, 'بلا إسناد', s.waiting, 'مهمّة', FieldTaskFilter.waiting),
              _Stat(LucideIcons.wrench, AppTone.info, 'الجارية', s.active, 'عند الفريق', FieldTaskFilter.active),
              _Stat(LucideIcons.triangleAlert, AppTone.danger, 'تعذّرت', s.failed, 'تحتاج قرارك', FieldTaskFilter.failed),
              _Stat(LucideIcons.circleCheck, AppTone.success, 'منجزة اليوم', s.doneToday, 'مهمّة', FieldTaskFilter.closed),
            ],
            selected: _filter,
            onTap: _setFilter,
          ),
          const SizedBox(height: Sp.md),
          FieldCard(
            padding: const EdgeInsets.all(Sp.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // البحث وزرّ «مهمّة جديدة» في سطرٍ حين يتّسع، وإلّا الزرّ تحت البحث بعرض السطر — لا تلميحٌ مقصوص على ٣٢٠ بخطٍّ مكبَّر
              LayoutBuilder(builder: (context, c) {
                final search = FieldTextBox(
                  key: const ValueKey('field-tasks-search'),
                  controller: _term,
                  icon: LucideIcons.search,
                  hint: 'ابحث في المهامّ',
                  onChanged: _onTerm,
                );
                final add = FieldFilledButton(
                  key: const ValueKey('field-new-task'),
                  icon: LucideIcons.plus,
                  label: 'مهمّة جديدة',
                  onTap: () => unawaited(widget.onNew()),
                );
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                if (c.maxWidth >= 300 * scale) {
                  return Row(children: [Expanded(child: search), const SizedBox(width: Sp.sm), add]);
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [search, const SizedBox(height: Sp.sm), add]);
              }),
              const SizedBox(height: Sp.md),
              // شرائح تلتفّ لسطرين على الشاشة الضيّقة — لا كلمة تُقصّ
              Wrap(spacing: Sp.x6, runSpacing: Sp.x6, children: [
                for (final f in FieldTaskFilter.values)
                  _FilterChip(
                    key: ValueKey('field-filter-${f.wire}'),
                    label: f.label,
                    count: s.countOf(f),
                    on: _filter == f,
                    onTap: () => _setFilter(f),
                  ),
              ]),
            ]),
          ),
          const SizedBox(height: Sp.md),
          ..._list(),
        ],
      ),
    );
  }

  List<Widget> _list() {
    if (_loading && _items.isEmpty) {
      return const [Padding(padding: EdgeInsets.only(top: Sp.huge), child: Center(child: CircularProgressIndicator()))];
    }
    if (_error != null && _items.isEmpty) {
      return [
        FieldCenterState(
          key: const ValueKey('field-tasks-error'),
          icon: LucideIcons.circleX,
          tone: AppTone.danger,
          title: 'تعذّر جلب المهامّ',
          sub: _error!,
        ),
      ];
    }
    if (_items.isEmpty) {
      return [
        FieldCenterState(
          key: const ValueKey('field-tasks-empty'),
          icon: LucideIcons.listChecks,
          title: _query.isNotEmpty ? 'لا نتائج لهذا البحث' : 'لا مهامّ هنا',
          sub: 'أنشئ مهمّةً بنفسك، أو اربط أنواع تذاكر المشتركين من «الأنواع» فتصير مهامّاً تلقائيّاً',
        ),
      ];
    }
    return [
      for (final t in _items) ...[
        FieldTaskCard(task: t, onTap: () => unawaited(widget.onOpen(t.id))),
        const SizedBox(height: Sp.sm),
      ],
      if (_hasMore)
        Center(
          child: TextButton(
            key: const ValueKey('field-tasks-more'),
            onPressed: _more ? null : _loadMore,
            child: _more
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('عرض المزيد (${FieldTeamApi.pageSize})', style: AppType.label(color: AppColors.brand)),
          ),
        ),
    ];
  }
}

class _Stat {
  const _Stat(this.icon, this.tone, this.label, this.value, this.sub, this.filter);
  final IconData icon;
  final AppTone tone;
  final String label;
  final int value;
  final String sub;
  final FieldTaskFilter filter;
}

/// بلاطات الإحصاء الأربع: عمودان على الهاتف، وأربعةٌ حين يتّسع العرض.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.tiles, required this.selected, required this.onTap});
  final List<_Stat> tiles;
  final FieldTaskFilter selected;
  final ValueChanged<FieldTaskFilter> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 640 ? 4 : 2;
      final w = (c.maxWidth - Sp.sm * (cols - 1)) / cols;
      return Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
        for (final t in tiles) SizedBox(width: w, child: _StatTile(stat: t, on: selected == t.filter, onTap: () => onTap(t.filter))),
      ]);
    });
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat, required this.on, required this.onTap});
  final _Stat stat;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final t = stat;
    return Material(
      color: on ? t.tone.softBg : AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        key: ValueKey('field-stat-${t.filter.wire}'),
        borderRadius: BorderRadius.circular(R.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: on ? t.tone.fill : AppColors.border, width: on ? BW.selected : BW.normal),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              FieldIconBox(icon: t.icon, tone: t.tone, size: 30),
              const SizedBox(width: Sp.sm),
              Expanded(
                  child: Text(t.label, maxLines: 2, style: AppType.micro(color: AppColors.textMid).copyWith(fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: Sp.sm),
            Text('${t.value}', style: AppType.statValue(color: AppColors.textHi)),
            Text(t.sub, maxLines: 1, style: AppType.micro(color: AppColors.textLow)),
          ]),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({super.key, required this.label, required this.count, required this.on, required this.onTap});
  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = on ? AppColors.onBrand : AppColors.textMid;
    return Material(
      color: on ? AppColors.brand : AppColors.surface,
      borderRadius: BorderRadius.circular(R.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.pill),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(color: on ? AppColors.brand : AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: AppType.label(color: fg).copyWith(fontWeight: FontWeight.w600)),
            if (count > 0) ...[
              const SizedBox(width: Sp.x6),
              Container(
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: on ? AppColors.onBrand.withValues(alpha: 0.22) : AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(R.pill),
                ),
                child:
                    Text('$count', textAlign: TextAlign.center, style: AppType.microBold(color: on ? AppColors.onBrand : AppColors.textHi)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// بطاقة المهمّة: شريطٌ بلون الحال على حافّتها، الحال والنوع والتذكرة، العنوان، المشترك والعنوان، سبب التعذّر، ثمّ الفنّي وشرائط المراحل.
class FieldTaskCard extends StatelessWidget {
  const FieldTaskCard({super.key, required this.task, required this.onTap});
  final FieldTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final t = task;
    final tone = fieldStatusTone(t.status);
    final who = t.subscriber?.title;
    final meta = AppType.micro(color: AppColors.textMid);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        key: ValueKey('field-task-${t.id}'),
        borderRadius: BorderRadius.circular(R.lg),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Stack(children: [
            PositionedDirectional(
              start: 0,
              top: Sp.lg,
              bottom: Sp.lg,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: t.status == 'cancelled' ? AppColors.border : tone.fill,
                  borderRadius: const BorderRadiusDirectional.horizontal(end: Radius.circular(R.pill)).resolve(Directionality.of(context)),
                ),
              ),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(Sp.lg + 2, Sp.md, Sp.md, Sp.sm),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Wrap(spacing: Sp.x6, runSpacing: 4, children: [
                        FieldStatusPill(status: t.status, label: t.statusLabel),
                        if ((t.typeName ?? '').isNotEmpty) FieldPill(label: t.typeName!, tone: AppTone.brand),
                        if (t.fromTicket) const FieldPill(label: 'تذكرة', icon: LucideIcons.ticket),
                      ]),
                    ),
                    const SizedBox(width: Sp.sm),
                    Text(fieldAgo(t.updatedAt ?? t.createdAt), style: AppType.micro(color: AppColors.textLow)),
                  ]),
                  const SizedBox(height: Sp.sm),
                  Text(iso(t.title), style: AppType.bodyBold(color: AppColors.textHi).copyWith(height: 1.55)),
                  if ((who ?? '').isNotEmpty || (t.address ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    if ((who ?? '').isNotEmpty) _line(LucideIcons.userRound, who!, meta),
                    if ((t.address ?? '').isNotEmpty) _line(LucideIcons.mapPin, t.address!, meta),
                  ],
                  if (t.status == 'failed' && (t.failReason ?? '').isNotEmpty) ...[
                    const SizedBox(height: Sp.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: Sp.sm + 2, vertical: Sp.x6),
                      decoration: BoxDecoration(color: AppColors.dangerSoftBg, borderRadius: BorderRadius.circular(R.md)),
                      child: Text(t.failReason!, style: AppType.label(color: AppColors.dangerOnSoft).copyWith(height: 1.55)),
                    ),
                  ],
                ]),
              ),
              Container(
                padding: const EdgeInsetsDirectional.fromSTEB(Sp.lg + 2, Sp.sm, Sp.md, Sp.sm),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                child: Row(children: [
                  if ((t.assignedStaffName ?? '').isNotEmpty) ...[
                    FieldAvatar(name: t.assignedStaffName!, size: 26),
                    const SizedBox(width: Sp.sm),
                    Expanded(
                        child: Text(iso(t.assignedStaffName!),
                            style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w600))),
                  ] else if (t.status == 'new') ...[
                    const FieldIconBox(icon: LucideIcons.userPlus, tone: AppTone.warning, size: 26, round: true),
                    const SizedBox(width: Sp.sm),
                    Expanded(
                      child: Text('بلا إسناد — افتحها لتسندها',
                          style: AppType.label(color: AppColors.warningOnSoft).copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ] else
                    Expanded(child: Text('بلا إسناد', style: AppType.label(color: AppColors.textMid))),
                  const SizedBox(width: Sp.sm),
                  FieldStageBars(status: t.status),
                ]),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text, TextStyle style) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 3), child: Icon(icon, size: 13, color: AppColors.textMid)),
          const SizedBox(width: Sp.x6),
          Expanded(child: Text(iso(text), style: style.copyWith(height: 1.55))),
        ]),
      );
}
