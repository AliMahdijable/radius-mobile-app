import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_portal_api.dart';
import '../../api/national_sheet_api.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/permission_locked.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import 'national_labels.dart';
import 'national_onboard_screen.dart';
import 'national_task_sheet.dart';
import 'national_ticket_write.dart';
import 'national_widgets.dart';

/// «المهامّ والطلبات» — المشروع الوطنيّ (watani، ٣١ أكتوبر): الطلبات (تسجيل زبون، عنوان جديد، نقل ملكيّة…) بفلاترها و«بانتظار
/// إجرائي» بعدّاده، وورقة الطلب (تفاصيله حسب نوعه، المهامّ المرتبطة، سجلّه)؛ والمهامّ (توصيل، توقيع عقد، صيانة) بفلاترها وملخّصها.
/// البوّابة بطيئة هنا (الطلبات ~١٦ث، المهامّ ~٨ث، سجلّ الطلب ~١١ث) ⇒ الخادم يكاشها ويُدفئها، والجلب الأوّل «جارٍ» ثمّ يصل وحده.
class NationalWorkScreen extends StatefulWidget {
  const NationalWorkScreen({super.key, this.initialTab = 0});

  /// ٠ = الطلبات، ١ = المهامّ.
  final int initialTab;

  @override
  State<NationalWorkScreen> createState() => _NationalWorkScreenState();
}

class _NationalWorkScreenState extends State<NationalWorkScreen> {
  late int _tab = widget.initialTab;
  String _q = '';
  Map<String, String> _f = const {'type': '', 'status': '', 'zone': '', 'period': ''};
  bool _action = false;
  NationalLookups? _lk;
  NationalCounts? _counts;

  /// الأقسام التجريبيّة (١ نوفمبر): تفاصيل المهمّة وتعليقاتها، وتعليقات الطلب — حين يقول الخادم إنّها مفتوحة لهذا الحساب.
  bool _beta = false;

  /// «إضافة مشترك» (٢ نوفمبر — طلب «تسجيل زبون جديد»): زرٌّ في «الطلبات» حين يفتحه الخادم (`onboard`)، ومقفلٌ بمكانه للموظّف.
  bool _onboard = false;

  final _req = NationalPaged<NationalRequest>();
  final _tasks = NationalPaged<NationalTask>();

  bool get _alive => mounted;
  void _changed() {
    if (mounted) setState(() {});
  }

  int get _active => [
        _f['zone'],
        _f['period'],
        if (_tab == 0) ...[_f['type'], _f['status']],
      ].where((v) => v != null && v.isNotEmpty).length;

  @override
  void initState() {
    super.initState();
    _reload();
    NationalPortalApi.lookups().then((v) {
      if (mounted && v != null) setState(() => _lk = v);
    });
    NationalPortalApi.counts().then((v) {
      if (mounted && v != null) setState(() => _counts = v);
    });
    NationalSheetApi.beta().then((b) {
      if (!mounted || b == null) return;
      setState(() {
        if (b.on) _beta = true;
        _onboard = b.onboard || (Perms.isEmployee && b.refused);
      });
    });
  }

  @override
  void dispose() {
    _req.dispose();
    _tasks.dispose();
    super.dispose();
  }

  void _reload() {
    final p = _tab == 0 ? _req : _tasks;
    p.reset();
    setState(() {});
    _next();
  }

  void _next() {
    final period = nationalPeriodRange(_f['period'] ?? '');
    if (_tab == 0) {
      _req.next(
        (page) => NationalPortalApi.requests(
          page: page,
          q: _q,
          type: _f['type'],
          status: _f['status'],
          actionRequired: _action,
          zone: _f['zone'],
          from: period.from,
          to: period.to,
        ),
        onChange: _changed,
        alive: () => _alive,
      );
    } else {
      _tasks.next(
        (page) => NationalPortalApi.tasks(page: page, q: _q, zone: _f['zone'], from: period.from, to: period.to),
        onChange: _changed,
        alive: () => _alive,
      );
    }
  }

  Future<void> _openFilters() async {
    final v = await showNationalFilters(context, sections: [
      if (_tab == 0) ...[
        NationalFilterSection(
          key: 'type',
          title: 'نوع الطلب',
          value: _f['type'] ?? '',
          options: _lk?.requestTypes?.map((x) => NationalChoice(x.id, nationalRequestTypeName(x.name))).toList(),
        ),
        NationalFilterSection(
          key: 'status',
          title: 'الحالة',
          value: _f['status'] ?? '',
          options: _lk?.requestStatuses?.map((x) => NationalChoice(x.id, nationalRequestStatus(x.name).label)).toList(),
        ),
      ],
      NationalFilterSection(
        key: 'zone',
        title: 'الزون',
        value: _f['zone'] ?? '',
        options: _lk?.zones?.map((x) => NationalChoice(x.id, x.name.isEmpty ? x.id : x.name)).toList(),
      ),
      NationalFilterSection(key: 'period', title: 'الفترة', value: _f['period'] ?? '', options: nationalPeriods, allLabel: 'كلّ الأوقات'),
    ]);
    if (v == null || !mounted) return;
    setState(() => _f = {..._f, ...v});
    _reload();
  }

  /// «إضافة مشترك» للموظّف بصلاحيّة «إضافة مشترك» (٣ نوفمبر — المالك: «ضيفهن بصلاحيه الهم»؛ الخادم employeeRoutes)
  static bool get _onboardLocked => Perms.isEmployee && !Perms.has('subscribers.add');

  Future<void> _openOnboard() async {
    if (_onboardLocked) {
      showNoPermission(context);
      return;
    }
    final sent = await showNationalOnboardScreen(context);
    if (sent == true && mounted && _tab == 0) _reload();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final p = _tab == 0 ? _req : _tasks;
    final onboardLocked = _onboardLocked;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text('المهامّ والطلبات', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      floatingActionButton: _tab == 0 && _onboard
          ? FloatingActionButton.extended(
              heroTag: 'national-onboard',
              tooltip: onboardLocked ? 'إضافة مشترك — مقفل' : 'إضافة مشترك',
              onPressed: _openOnboard,
              backgroundColor: onboardLocked ? AppColors.surfaceSunken : AppColors.brand,
              foregroundColor: onboardLocked ? AppColors.textLow : AppColors.onBrand,
              icon: Icon(onboardLocked ? LucideIcons.lock : LucideIcons.userPlus, size: 18),
              label: const Text('إضافة مشترك'),
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('الطلبات'), icon: Icon(LucideIcons.fileText, size: 16)),
                  ButtonSegment(value: 1, label: Text('المهامّ'), icon: Icon(LucideIcons.listChecks, size: 16)),
                ],
                selected: {_tab},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  setState(() {
                    _tab = s.first;
                    _f = {..._f, 'type': '', 'status': ''};
                  });
                  _reload();
                },
              ),
              const SizedBox(height: Sp.md),
              Row(
                children: [
                  Expanded(
                    child: NationalSearchField(
                      hint: 'اسم المشترك',
                      initial: _q,
                      onChanged: (v) {
                        _q = v;
                        _reload();
                      },
                    ),
                  ),
                  const SizedBox(width: Sp.sm),
                  NationalFilterButton(active: _active, onTap: _openFilters),
                ],
              ),
              if (_tab == 0) ...[
                const SizedBox(height: Sp.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilterChip(
                    label: Text(_counts?.actionRequired != null ? 'بانتظار إجرائي (${_counts!.actionRequired})' : 'بانتظار إجرائي'),
                    selected: _action,
                    showCheckmark: false,
                    avatar: Icon(LucideIcons.bellRing, size: 15, color: _action ? AppColors.warningOnSoft : AppColors.textMid),
                    selectedColor: AppColors.warningSoftBg,
                    side: BorderSide(color: _action ? AppColors.warningSoftBorder : AppColors.border),
                    labelStyle: AppType.label(color: _action ? AppColors.warningOnSoft : AppColors.textHi),
                    onSelected: (v) {
                      setState(() => _action = v);
                      _reload();
                    },
                  ),
                ),
              ],
              if (_tab == 1) ..._taskSummary(),
              const SizedBox(height: Sp.md),
              ..._body(p),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _taskSummary() {
    final s = _tasks.raw['summary'];
    if (s is! Map) return const [];
    String n(dynamic v) => v == null ? '—' : '$v';
    return [
      const SizedBox(height: Sp.sm),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          ToneChip(label: 'مفتوحة ${n(s['open'])}', tone: AppTone.info),
          ToneChip(label: 'مكتملة ${n(s['completed'])}', tone: AppTone.success),
          ToneChip(label: 'مستحقّة اليوم ${n(s['due_today'])}', tone: AppTone.warning),
        ],
      ),
    ];
  }

  List<Widget> _body(NationalPaged<Object?> p) {
    if (p.rows.isEmpty) {
      if (p.error != null) return [NationalStateBox.error(text: p.error!, onRetry: _reload)];
      if (p.pending) return const [NationalStateBox.pending()];
      if (p.loading || p.page == 0) return const [NationalStateBox.loading()];
      final filtered = _q.isNotEmpty || _active > 0 || (_tab == 0 && _action);
      return [
        NationalStateBox.empty(
          text: filtered ? 'لا نتائج تطابق البحث' : (_tab == 0 ? 'لا توجد طلبات' : 'لا توجد مهامّ'),
          icon: _tab == 0 ? LucideIcons.fileText : LucideIcons.listChecks,
        ),
      ];
    }
    return [
      if (_tab == 0)
        for (final r in _req.rows) ...[
          _RequestCard(r: r, onTap: r.id == null ? null : () => _openRequest(r)),
          const SizedBox(height: Sp.sm),
        ]
      else
        for (final t in _tasks.rows) ...[
          _TaskCard(t: t, onTap: _beta && t.id != null ? () => showNationalTaskSheet(context, t) : null),
          const SizedBox(height: Sp.sm),
        ],
      if (p.hasMore)
        NationalLoadMore(loading: p.loading, onTap: _next, shown: p.rows.length, total: p.total, unit: _tab == 0 ? 'طلب' : 'مهمّة')
      else if (p.total != null)
        Padding(
          padding: const EdgeInsets.only(top: Sp.sm),
          child: Text('${p.total} ${_tab == 0 ? 'طلب' : 'مهمّة'}', textAlign: TextAlign.center, style: AppType.muted()),
        ),
    ];
  }

  Future<void> _openRequest(NationalRequest r) async {
    final changed = await showAppSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RequestSheet(row: r, comments: _beta),
    );
    // أُلغي الطلب (أو لم يتأكّد): القائمة والعدّادات من جديد
    if (changed == true && mounted) _reload();
  }
}

Widget _meta(IconData i, String text, {bool ltr = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(i, size: 13, color: AppColors.textMid),
        const SizedBox(width: 4),
        Text(text, textDirection: ltr ? TextDirection.ltr : null, style: AppType.micro(color: AppColors.textMid)),
      ],
    );

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.r, this.onTap});
  final NationalRequest r;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final st = nationalRequestStatus(r.status);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(R.lg), border: Border.all(color: AppColors.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(nationalRequestType(r.type), style: AppType.cardTitle(color: AppColors.textHi))),
                  ToneChip(label: st.label, tone: st.tone, dense: true),
                ],
              ),
              const SizedBox(height: 6),
              Text(r.customer?.name ?? '—', style: AppType.listName(color: AppColors.textHi)),
              if (r.username != null)
                Text(r.username!, textDirection: TextDirection.ltr, textAlign: TextAlign.end, style: AppType.micro(color: AppColors.textMid)),
              const SizedBox(height: Sp.sm),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _meta(LucideIcons.clock, 'أُنشئ ${nationalTime(r.createdAt)}'),
                  if (r.closedAt != null) _meta(LucideIcons.calendarCheck, 'أُغلق ${nationalTime(r.closedAt)}'),
                  if (r.zone?.name.isNotEmpty == true) _meta(LucideIcons.mapPin, r.zone!.name, ltr: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.t, this.onTap});
  final NationalTask t;

  /// تفاصيل المهمّة وتعليقاتها (الأقسام التجريبيّة) — null ⇒ الكرت للعرض وحده كما كان.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final st = nationalTaskStatus(t.status);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(R.lg), border: Border.all(color: AppColors.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(nationalTaskTitle(t.title), style: AppType.cardTitle(color: AppColors.textHi))),
                  ToneChip(label: st.label, tone: st.tone, dense: true),
                ],
              ),
              const SizedBox(height: 6),
              Text(t.customer?.name ?? '—', style: AppType.listName(color: AppColors.textHi)),
              const SizedBox(height: Sp.sm),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _meta(LucideIcons.calendarClock, 'الاستحقاق ${nationalTime(t.dueAt)}'),
                  if (t.zone?.name.isNotEmpty == true) _meta(LucideIcons.mapPin, t.zone!.name, ltr: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestSheet extends StatefulWidget {
  const _RequestSheet({required this.row, this.comments = false});
  final NationalRequest row;

  /// «التعليقات» (الأقسام التجريبيّة، ١ نوفمبر).
  final bool comments;

  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  NationalRequestDetail? _d;
  String? _error;
  bool _waiting = true;
  Timer? _poll;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await NationalPortalApi.request(widget.row.id!, widget.row.type);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _error = r.error;
        _waiting = false;
      });
      return;
    }
    setState(() {
      if (r.data != null) _d = r.data;
      _waiting = r.data == null;
      _error = null;
    });
    // التفاصيل لم تصل، أو السجلّ ما زال يُجلب بالخادم (~١١ث): اسأل ثانيةً
    final again = r.data == null || r.data!.logsPending;
    if (again && _polls++ < 15) {
      _poll?.cancel();
      _poll = Timer(const Duration(seconds: 4), _load);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final row = widget.row;
    final d = _d;
    final st = nationalRequestStatus(d?.status.isNotEmpty == true ? d!.status : row.status);
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.fileText,
        title: nationalRequestType(row.type),
        subtitle: row.customer?.name ?? '—',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: _error != null
          ? NationalStateBox.error(text: _error!, onRetry: () {
              setState(() {
                _error = null;
                _waiting = true;
              });
              _load();
            })
          : _waiting && d == null
              ? const NationalStateBox.loading()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        ToneChip(label: st.label, tone: st.tone),
                        if (d?.cancelable == true && d?.canCancel != true) ...[
                          const SizedBox(width: Sp.sm),
                          Expanded(child: Text('يمكن إلغاؤه من بوّابة المشروع الوطني', style: AppType.muted())),
                        ],
                      ],
                    ),
                    const SizedBox(height: Sp.md),
                    NationalInfoGroup(children: [
                      if (row.username != null) NationalInfoRow(icon: LucideIcons.user, label: 'اليوزر', value: row.username!, ltr: true),
                      if (row.zone?.name.isNotEmpty == true) NationalInfoRow(icon: LucideIcons.mapPin, label: 'الزون', value: row.zone!.name, ltr: true),
                      if (d?.plan != null) NationalInfoRow(icon: LucideIcons.package, label: 'الباقة', value: d!.plan!, ltr: true),
                      if (d?.address != null) NationalInfoRow(icon: LucideIcons.mapPin, label: 'العنوان', value: d!.address!),
                      NationalInfoRow(icon: LucideIcons.calendarClock, label: 'أُنشئ', value: nationalTime(d?.createdAt ?? row.createdAt), ltr: true),
                      if ((d?.closedAt ?? row.closedAt) != null)
                        NationalInfoRow(icon: LucideIcons.calendarCheck, label: 'أُغلق', value: nationalTime(d?.closedAt ?? row.closedAt), ltr: true),
                    ]),
                    if (d != null && d.tasks.isNotEmpty) ...[
                      const SizedBox(height: Sp.lg),
                      Text('المهامّ المرتبطة', style: AppType.label(color: AppColors.textLabel)),
                      const SizedBox(height: Sp.sm),
                      NationalInfoGroup(children: [
                        // المهمّة المرتبطة تُفتح بورقتها (٢ نوفمبر) — ومنها «تنصيب الجهاز» لطلب التسجيل، كرابط المهمّة في البوّابة
                        for (final t in d.tasks)
                          InkWell(
                            onTap: widget.comments && t.id != null
                                ? () => showNationalTaskSheet(
                                      context,
                                      NationalTask(id: t.id, title: t.title, status: t.status, dueAt: t.dueAt, customer: row.customer, zone: row.zone),
                                    )
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Icon(LucideIcons.clipboardList, size: 16, color: AppColors.textMid),
                                  const SizedBox(width: Sp.sm),
                                  Expanded(child: Text(nationalTaskTitle(t.title), style: AppType.body(color: AppColors.textHi))),
                                  if (t.status.isNotEmpty)
                                    ToneChip(label: nationalTaskStatus(t.status).label, tone: nationalTaskStatus(t.status).tone, dense: true),
                                  if (widget.comments && t.id != null) ...[
                                    const SizedBox(width: 4),
                                    Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textMid),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ]),
                    ],
                    const SizedBox(height: Sp.lg),
                    Text('سجلّ الطلب', style: AppType.label(color: AppColors.textLabel)),
                    const SizedBox(height: Sp.sm),
                    if (d == null || d.logsPending)
                      Text('جارٍ جلب السجلّ من البوّابة…', style: AppType.muted())
                    else if (d.logs == null)
                      Text('تعذّر جلب السجلّ الآن.', style: AppType.muted())
                    else if (d.logs!.isEmpty)
                      Text('لا أحداث.', style: AppType.muted())
                    else
                      NationalInfoGroup(children: [
                        for (final l in d.logs!)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  l.ok == false ? LucideIcons.circleX : LucideIcons.circleCheck,
                                  size: 16,
                                  color: l.ok == false ? AppColors.error : AppColors.success,
                                ),
                                const SizedBox(width: Sp.sm),
                                Expanded(
                                  child: Text(l.text.isEmpty ? '—' : l.text,
                                      maxLines: 4, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textBody)),
                                ),
                                const SizedBox(width: Sp.sm),
                                Text(nationalTime(l.at), textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textMid)),
                              ],
                            ),
                          ),
                      ]),
                    if (widget.comments && row.id != null) ...[
                      const SizedBox(height: Sp.lg),
                      NationalRequestComments(requestId: row.id!, type: row.type),
                    ],
                    if (d?.canCancel == true) ...[
                      const SizedBox(height: Sp.xl),
                      OutlinedButton.icon(
                        onPressed: _cancelling ? null : _cancel,
                        icon: Icon(nationalWriteLocked ? LucideIcons.lock : LucideIcons.circleX, size: 18),
                        label: Text(_cancelling ? 'جارٍ الإلغاء…' : 'إلغاء الطلب'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: nationalWriteLocked ? AppColors.textHint : AppColors.error,
                          side: BorderSide(color: nationalWriteLocked ? AppColors.border : AppColors.error.withValues(alpha: 0.45)),
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }

  bool _cancelling = false;

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    final changed = await nationalCancelRequest(
      context,
      id: widget.row.id!,
      type: widget.row.type,
      label: nationalRequestType(widget.row.type),
    );
    if (!mounted) return;
    setState(() => _cancelling = false);
    if (changed) Navigator.of(context).pop(true);
  }
}
