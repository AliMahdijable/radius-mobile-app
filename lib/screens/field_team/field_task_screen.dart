import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/field_team_api.dart';
import '../../core/util/bidi.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import '../tickets/ticket_image.dart';
import 'field_team_widgets.dart';
import '../../services/employee_visibility.dart';

/// المهمّة كما في الموقع (TaskSheet): الحال والنوع والتذكرة، المراحل الأربع، الفنّي باتّصالٍ وواتساب والإسناد، المشترك باتّصالٍ
/// وواتساب وخريطة، ملاحظةٌ تصل الفنّي، السجلّ الزمنيّ بصوره ومكان الفنّي، ثمّ إعادة الفتح أو الإلغاء بسببه. تُقرأ كلّ ٢٠ ثانية.
/// تُرجع true إن تغيّر شيء (القائمة والأعداد تُقرأ من جديد).
class FieldTaskScreen extends StatefulWidget {
  const FieldTaskScreen({super.key, required this.taskId});
  final int taskId;

  @override
  State<FieldTaskScreen> createState() => _FieldTaskScreenState();
}

class _FieldTaskScreenState extends State<FieldTaskScreen> {
  FieldTask? _task;
  List<FieldEvent> _events = const [];
  List<FieldStaff> _staff = const [];
  String? _error;
  bool _loading = true;
  bool _changed = false;

  /// فعلٌ جارٍ: assign · note · reopen · cancel — لا فعلان معاً.
  String? _busy;
  int? _assignTo;
  final _note = TextEditingController();
  Timer? _poll;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadStaff());
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_load(quiet: true)));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final seq = ++_seq;
    final r = await FieldTeamApi.task(widget.taskId);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (r.task != null) {
        _task = r.task;
        _events = r.events;
        _error = null;
      } else if (_task == null || !quiet) {
        _error = r.error;
      }
    });
  }

  Future<void> _loadStaff() async {
    final r = await FieldTeamApi.staff();
    if (!mounted || r.items == null) return;
    setState(() => _staff = r.items!);
  }

  Future<void> _act(String name, Future<FieldResult> Function() run, String ok) async {
    if (_busy != null) return;
    setState(() => _busy = name);
    final r = await run();
    if (!mounted) return;
    setState(() => _busy = null);
    if (!r.ok) {
      showSheetSnack(context, r.error ?? 'تعذّر الآن — أعد المحاولة', isError: true);
      unawaited(_load(quiet: true));
      return;
    }
    _changed = true;
    showSheetSnack(context, ok);
    setState(() {
      if (name == 'note') _note.clear();
      if (name == 'assign') _assignTo = null;
    });
    await _load(quiet: true);
  }

  Future<void> _pickAssignee() async {
    final t = _task;
    if (t == null) return;
    final active = _staff.where((s) => s.isActive).toList();
    final picked = await showFieldPickSheet<int>(
      context,
      title: t.assignedStaffId != null ? 'إعادة الإسناد' : 'أسندها لـ…',
      subtitle: 'يصل الفنّي إشعارها فوراً',
      icon: LucideIcons.userCheck,
      selected: _assignTo,
      empty: 'لا أحد في الفريق بعد — أضفه من «الفريق»',
      options: [
        for (final s in active)
          FieldPickOption<int>(
            value: s.id,
            label: s.fullName,
            sub: s.activeTasks > 0 ? '${s.roleLabel} · عنده ${s.activeTasks} جارية' : s.roleLabel,
            icon: LucideIcons.hardHat,
          ),
      ],
    );
    if (picked != null && mounted) setState(() => _assignTo = picked.value);
  }

  Future<void> _cancel() async {
    final reason = await showFieldSheet<String>(context, const _CancelSheet());
    if (reason == null || !mounted) return;
    await _act('cancel', () => FieldTeamApi.cancel(widget.taskId, reason: reason), 'أُلغيت المهمّة');
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final t = _task;
    final title = t == null ? 'المهمّة' : 'مهمّة #${t.id}';
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            iconTheme: IconThemeData(color: AppColors.textHi),
            leading: IconButton(
              tooltip: 'رجوع',
              icon: const BackButtonIcon(),
              onPressed: () => Navigator.of(context).pop(_changed),
            ),
            title: Text(title, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          ),
          title: title,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () => Future.wait([_load(), _loadStaff()]),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
                  children: t == null
                      ? [
                          FieldCenterState(
                            key: const ValueKey('field-task-error'),
                            icon: LucideIcons.circleX,
                            tone: AppTone.danger,
                            title: 'تعذّر جلب المهمّة',
                            sub: _error ?? 'اسحب للأسفل لإعادة المحاولة',
                          ),
                        ]
                      : _content(t),
                ),
              ),
      ),
    );
  }

  List<Widget> _content(FieldTask t) {
    final now = DateTime.now();
    final sub = t.subscriber;
    final who = sub?.title;
    final maps = fieldMapsUrl(t.location, t.address);
    FieldStaff? tech;
    for (final s in _staff) {
      if (s.id == t.assignedStaffId) tech = s;
    }
    return [
      // الرأس: الحال والنوع والتذكرة، العنوان، التفاصيل، ومن أنشأها
      Wrap(spacing: Sp.x6, runSpacing: 4, children: [
        FieldStatusPill(status: t.status, label: t.statusLabel),
        if ((t.typeName ?? '').isNotEmpty) FieldPill(label: t.typeName!, tone: AppTone.brand),
        if (t.fromTicket)
          FieldPill(label: t.ticketId != null ? 'من تذكرة المشترك #${t.ticketId}' : 'من تذكرة المشترك', icon: LucideIcons.ticket),
      ]),
      const SizedBox(height: Sp.sm),
      Text(iso(t.title),
          key: const ValueKey('field-task-title'), style: AppType.cardTitleBold(color: AppColors.textHi).copyWith(height: 1.55)),
      if ((t.details ?? '').isNotEmpty) ...[
        const SizedBox(height: Sp.xs),
        Text(t.details!, style: AppType.body(color: AppColors.textBody).copyWith(height: 1.6)),
      ],
      const SizedBox(height: Sp.xs),
      Text(
        [if ((t.createdBy ?? '').isNotEmpty) 'أنشأها ${t.createdBy}', fieldAgo(t.createdAt)].where((x) => x.isNotEmpty).join(' · '),
        style: AppType.micro(color: AppColors.textLow),
      ),
      const SizedBox(height: Sp.md),

      // الحال: تعذّرت / ملغاة / المراحل
      if (t.status == 'failed')
        FieldNote(
          key: const ValueKey('field-task-failed'),
          icon: LucideIcons.circleX,
          tone: AppTone.danger,
          title: 'تعذّرت المهمّة',
          text: [if ((t.failReason ?? '').isNotEmpty) t.failReason!, 'أعد فتحها لتُسندها من جديد، أو ألغها.'].join('\n'),
        )
      else if (t.status == 'cancelled')
        const FieldNote(icon: LucideIcons.ban, tone: AppTone.neutral, title: 'أُلغيت المهمّة', text: '')
      else
        FieldCard(
          child: Column(children: [
            _Stepper(status: t.status),
            if (t.status == 'new') ...[
              const SizedBox(height: Sp.md),
              Text('بانتظار إسنادك — اختر الفنّي أدناه',
                  textAlign: TextAlign.center, style: AppType.label(color: AppColors.warningOnSoft).copyWith(fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      const SizedBox(height: Sp.md),

      // الفنّي والإسناد
      FieldCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FieldSectionHead(
            icon: LucideIcons.hardHat,
            title: 'الفنّي',
            desc: t.assignedAt != null && (t.assignedStaffName ?? '').isNotEmpty ? 'أُسندت ${fieldAgo(t.assignedAt)}' : null,
          ),
          const SizedBox(height: Sp.md),
          if ((t.assignedStaffName ?? '').isNotEmpty)
            Row(children: [
              FieldAvatar(name: t.assignedStaffName!, size: 44, live: tech?.liveAt(now)),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(iso(t.assignedStaffName!), style: AppType.bodyBold(color: AppColors.textHi)),
                  if (tech != null)
                    Text(isoJoin([tech.roleLabel, if ((tech.phone ?? '').isNotEmpty) tech.phone!], ' · '),
                        style: AppType.micro(color: AppColors.textMid)),
                ]),
              ),
              if ((tech?.phone ?? '').isNotEmpty) ...[
                const SizedBox(width: Sp.sm),
                FieldIconButton(
                  key: const ValueKey('field-tech-call'),
                  icon: LucideIcons.phone,
                  tooltip: 'اتّصل بـ${tech!.fullName}',
                  onTap: () => unawaited(fieldCall(context, tech!.phone!)),
                ),
                const SizedBox(width: Sp.x6),
                FieldIconButton(
                  key: const ValueKey('field-tech-wa'),
                  icon: LucideIcons.messageCircle,
                  tone: AppTone.success,
                  tooltip: 'واتساب ${tech.fullName}',
                  onTap: () => unawaited(fieldWhatsApp(context, tech!.phone)),
                ),
              ],
            ])
          else
            Text('لم تُسند لأحدٍ بعد', style: AppType.body(color: AppColors.textMid)),
          if (t.actions.contains('assign')) ...[
            const SizedBox(height: Sp.md),
            Divider(height: 1, color: AppColors.border),
            const SizedBox(height: Sp.md),
            FieldPickerBox(
              key: const ValueKey('field-assign-pick'),
              icon: LucideIcons.userCheck,
              text: _staff.where((s) => s.id == _assignTo).map((s) => s.fullName).firstOrNull,
              placeholder: t.assignedStaffId != null ? 'إعادة الإسناد لـ…' : 'أسندها لـ…',
              onTap: _busy != null ? null : _pickAssignee,
            ),
            const SizedBox(height: Sp.sm),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FieldFilledButton(
                key: const ValueKey('field-assign'),
                icon: LucideIcons.userCheck,
                label: 'إسناد',
                busy: _busy == 'assign',
                onTap: _assignTo == null || _busy != null
                    ? null
                    : () => unawaited(_act('assign', () => FieldTeamApi.assign(t.id, _assignTo!), 'أُسندت — وصل الفنّي إشعارها')),
              ),
            ),
          ],
        ]),
      ),

      // المشترك والموقع
      if ((who ?? '').isNotEmpty || (t.address ?? '').isNotEmpty || maps != null) ...[
        const SizedBox(height: Sp.md),
        FieldCard(
          key: const ValueKey('field-task-subscriber'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if ((who ?? '').isNotEmpty)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FieldAvatar(name: who!, size: 44),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('المشترك', style: AppType.micro(color: AppColors.textMid).copyWith(fontWeight: FontWeight.w600)),
                    Text(iso(who), style: AppType.bodyBold(color: AppColors.textHi)),
                    if (Sees.usernames && (sub?.name ?? '').isNotEmpty && (sub?.username ?? '').isNotEmpty)
                      Text(iso(sub!.username!), style: AppType.micro(color: AppColors.textMid)),
                    if (Sees.phones && (sub?.phone ?? '').isNotEmpty) Text(iso(sub!.phone!), style: AppType.body(color: AppColors.textHi)),
                  ]),
                ),
              ])
            else
              const FieldSectionHead(icon: LucideIcons.mapPin, tone: AppTone.info, title: 'الموقع'),
            if ((t.address ?? '').isNotEmpty) ...[
              const SizedBox(height: Sp.md),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + 2),
                decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 3), child: Icon(LucideIcons.mapPin, size: 16, color: AppColors.brand)),
                  const SizedBox(width: Sp.sm),
                  Expanded(child: Text(iso(t.address!), style: AppType.body(color: AppColors.textHi).copyWith(height: 1.55))),
                ]),
              ),
            ],
            if ((sub?.phone ?? '').isNotEmpty || maps != null) ...[
              const SizedBox(height: Sp.md),
              _QuickLinks(links: [
                if ((sub?.phone ?? '').isNotEmpty) ...[
                  FieldQuickLink(
                    key: const ValueKey('field-sub-call'),
                    icon: LucideIcons.phone,
                    label: 'اتّصال',
                    tone: AppTone.brand,
                    onTap: () => unawaited(fieldCall(context, sub!.phone!)),
                  ),
                  FieldQuickLink(
                    key: const ValueKey('field-sub-wa'),
                    icon: LucideIcons.messageCircle,
                    label: 'واتساب',
                    tone: AppTone.success,
                    onTap: () => unawaited(fieldWhatsApp(context, sub!.phone)),
                  ),
                ],
                if (maps != null)
                  FieldQuickLink(
                    key: const ValueKey('field-sub-map'),
                    icon: LucideIcons.navigation,
                    label: 'الخريطة',
                    tone: AppTone.info,
                    onTap: () => unawaited(fieldOpenUrl(context, maps, failText: 'تعذّر فتح الخريطة')),
                  ),
              ]),
            ],
          ]),
        ),
      ],

      // ملاحظة للفنّي
      const SizedBox(height: Sp.md),
      FieldCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const FieldSectionHead(
            icon: LucideIcons.messageSquareText,
            tone: AppTone.info,
            title: 'ملاحظة للفنّي',
            desc: 'تصله بإشعارٍ إن كانت المهمّة عنده',
          ),
          const SizedBox(height: Sp.md),
          FieldTextBox(
            key: const ValueKey('field-note'),
            controller: _note,
            icon: LucideIcons.messageSquare,
            hint: 'مثلاً: المشترك ينتظرك بعد الساعة ٤',
            minLines: 2,
            maxLines: 5,
            maxLength: 1000,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Sp.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FieldFilledButton(
              key: const ValueKey('field-note-send'),
              icon: LucideIcons.send,
              label: 'إرسال',
              busy: _busy == 'note',
              onTap: _note.text.trim().isEmpty || _busy != null
                  ? null
                  : () => unawaited(_act('note', () => FieldTeamApi.note(t.id, _note.text), 'أُضيفت الملاحظة')),
            ),
          ),
        ]),
      ),

      // السجلّ
      const SizedBox(height: Sp.md),
      FieldCard(
        key: const ValueKey('field-task-log'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const FieldSectionHead(icon: LucideIcons.clock, tone: AppTone.neutral, title: 'سجلّ المهمّة'),
          const SizedBox(height: Sp.md),
          if (_events.isEmpty)
            Text('لا شيء بعد', style: AppType.muted(color: AppColors.textMid))
          else
            for (final (i, e) in _events.reversed.indexed) _EventRow(taskId: t.id, event: e, last: i == _events.length - 1),
        ]),
      ),

      // إعادة الفتح · الإلغاء
      if (t.actions.contains('reopen') || t.actions.contains('cancel')) ...[
        const SizedBox(height: Sp.md),
        Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
          if (t.actions.contains('reopen'))
            FieldOutlineButton(
              key: const ValueKey('field-reopen'),
              icon: LucideIcons.rotateCcw,
              label: 'إعادة فتح',
              busy: _busy == 'reopen',
              onTap:
                  _busy != null ? null : () => unawaited(_act('reopen', () => FieldTeamApi.reopen(t.id), 'أُعيد فتحها — بانتظار إسنادك')),
            ),
          if (t.actions.contains('cancel'))
            FieldOutlineButton(
              key: const ValueKey('field-cancel'),
              icon: LucideIcons.circleX,
              tone: AppTone.danger,
              label: 'إلغاء المهمّة',
              busy: _busy == 'cancel',
              onTap: _busy != null ? null : () => unawaited(_cancel()),
            ),
        ]),
      ],
    ];
  }
}

/// أزرار التواصل في سطرٍ حين يتّسع لكلٍّ منها (أيقونةٌ وكلمةٌ بخطّ الهاتف وتكبيره)، وإلّا تحت بعضها بعرض السطر — لا كلمة مقصوصة.
class _QuickLinks extends StatelessWidget {
  const _QuickLinks({required this.links});
  final List<Widget> links;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final each = (c.maxWidth - Sp.sm * (links.length - 1)) / links.length;
      if (each >= 96 * scale) {
        return Row(children: [
          for (final (i, l) in links.indexed) ...[if (i > 0) const SizedBox(width: Sp.sm), Expanded(child: l)],
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, l) in links.indexed) ...[if (i > 0) const SizedBox(height: Sp.sm), l],
      ]);
    });
  }
}

/// المراحل الأربع بدوائرها وخطوطها (الموقع Stepper).
class _Stepper extends StatelessWidget {
  const _Stepper({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final at = fieldStepAt(status) ?? -1;
    final done = status == 'done';
    final fill = done ? AppColors.success : AppColors.brandAccent;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < kFieldSteps.length; i++)
        Expanded(
          child: Column(children: [
            Row(children: [
              Expanded(child: Container(height: 2, color: i == 0 ? Colors.transparent : (i <= at ? fill : AppColors.border))),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (i < at || done || i == at) ? fill : AppColors.surfaceSunken,
                  border: i == at && !done ? Border.all(color: fill.withValues(alpha: 0.25), width: 4) : null,
                ),
                child: (i < at || done)
                    ? const Icon(LucideIcons.check, size: 15, color: AppColors.onBrand)
                    : Text('${i + 1}', style: AppType.microBold(color: i == at ? AppColors.onBrand : AppColors.textMid)),
              ),
              Expanded(
                child: Container(
                  height: 2,
                  color: i == kFieldSteps.length - 1 ? Colors.transparent : (i < at ? fill : AppColors.border),
                ),
              ),
            ]),
            const SizedBox(height: Sp.x6),
            Text(
              kFieldSteps[i].label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: (i <= at || done)
                  ? AppType.micro(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)
                  : AppType.micro(color: AppColors.textMid),
            ),
          ]),
        ),
    ]);
  }
}

({IconData icon, AppTone tone, String title}) _eventLook(FieldEvent e) {
  switch (e.kind) {
    case 'created':
      return (icon: LucideIcons.plus, tone: AppTone.neutral, title: 'أُنشئت');
    case 'assigned':
      return (icon: LucideIcons.userCheck, tone: AppTone.brand, title: 'أُسندت');
    case 'unassigned':
      return (icon: LucideIcons.userX, tone: AppTone.warning, title: 'أُلغي الإسناد');
    case 'note':
      return (icon: LucideIcons.messageSquareText, tone: AppTone.info, title: 'ملاحظة');
  }
  final label = e.statusLabel ?? 'تغيّرت الحال';
  return switch (e.statusTo) {
    'done' => (icon: LucideIcons.circleCheck, tone: AppTone.success, title: label),
    'failed' => (icon: LucideIcons.circleX, tone: AppTone.danger, title: label),
    'cancelled' => (icon: LucideIcons.ban, tone: AppTone.neutral, title: label),
    'on_way' => (icon: LucideIcons.navigation, tone: AppTone.info, title: label),
    'working' => (icon: LucideIcons.wrench, tone: AppTone.info, title: label),
    _ => (icon: LucideIcons.rotateCcw, tone: AppTone.brand, title: label),
  };
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.taskId, required this.event, required this.last});
  final int taskId;
  final FieldEvent event;
  final bool last;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final e = event;
    final look = _eventLook(e);
    final at = e.location == null ? null : fieldMapsUrl(e.location, null);
    return IntrinsicHeight(
      key: ValueKey('field-event-${e.id}'),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          FieldIconBox(icon: look.icon, tone: look.tone, size: 32, round: true),
          if (!last) Expanded(child: Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: AppColors.border)),
        ]),
        const SizedBox(width: Sp.md),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 5, bottom: last ? 0 : Sp.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: Sp.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(look.title, style: AppType.bodyStrong(color: AppColors.textHi)),
                Text(isoJoin([if (e.who.isNotEmpty) e.who, fieldAgo(e.createdAt)], ' · '), style: AppType.micro(color: AppColors.textMid)),
              ]),
              if ((e.note ?? '').isNotEmpty) ...[
                const SizedBox(height: Sp.x6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
                  decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
                  child: Text(e.note!, style: AppType.body(color: AppColors.textHi).copyWith(height: 1.6)),
                ),
              ],
              if (e.hasImage) ...[
                const SizedBox(height: Sp.sm),
                _EventImage(taskId: taskId, eventId: e.id),
              ],
              if (at != null) ...[
                const SizedBox(height: Sp.x6),
                InkWell(
                  borderRadius: BorderRadius.circular(R.sm),
                  onTap: () => unawaited(fieldOpenUrl(context, at, failText: 'تعذّر فتح الخريطة')),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(LucideIcons.mapPin, size: 14, color: AppColors.brand),
                      const SizedBox(width: 4),
                      Text('مكان الفنّي عندها', style: AppType.micro(color: AppColors.brand).copyWith(fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

/// صورةٌ من الفريق: مصغّرةٌ، وبالنقر ملء الشاشة بتكبير (عارض صور التذاكر نفسه).
class _EventImage extends StatefulWidget {
  const _EventImage({required this.taskId, required this.eventId});
  final int taskId;
  final int eventId;

  @override
  State<_EventImage> createState() => _EventImageState();
}

class _EventImageState extends State<_EventImage> {
  Uint8List? _bytes;
  bool _expired = false;
  bool _failed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final r = await FieldTeamApi.eventImage(widget.taskId, widget.eventId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _bytes = r.bytes;
      _expired = r.expired;
      _failed = r.bytes == null && !r.expired;
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final b = _bytes;
    if (_expired) {
      return Text('الصورة لم تعد محفوظة', style: AppType.micro(color: AppColors.textMid));
    }
    if (b == null) {
      return InkWell(
        borderRadius: BorderRadius.circular(R.md),
        onTap: _failed ? _fetch : null,
        child: Container(
          width: 112,
          height: 112,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(LucideIcons.imageOff, size: 20, color: AppColors.textLow),
                  const SizedBox(height: 4),
                  Text('اضغط للإعادة', style: AppType.micro(color: AppColors.textMid)),
                ]),
        ),
      );
    }
    return Semantics(
      label: 'صورة من الفريق — اضغط للتكبير',
      button: true,
      child: GestureDetector(
        key: ValueKey('field-event-image-${widget.eventId}'),
        onTap: () => Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
          opaque: false,
          barrierColor: AppColors.scrim,
          pageBuilder: (ctx, _, __) => TicketImageViewer(bytes: b),
        )),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(R.md),
          child: Image.memory(b, width: 112, height: 112, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 360),
        ),
      ),
    );
  }
}

/// إلغاء المهمّة: يصل الفنّي إشعارٌ بإلغائها، والسبب اختياريّ. تُرجع السبب ('' بلا سبب) أو null إن رجع.
class _CancelSheet extends StatefulWidget {
  const _CancelSheet();

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.circleX,
        tint: AppTone.danger.fill,
        tintBg: AppTone.danger.softBg,
        title: 'إلغاء المهمّة؟',
        subtitle: 'يصل الفنّي إشعارٌ بإلغائها',
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        key: const ValueKey('field-cancel-confirm'),
        label: 'تأكيد الإلغاء',
        icon: LucideIcons.circleX,
        color: AppColors.errorFill,
        onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
      ),
      body: SheetSection(
        label: 'سبب الإلغاء',
        footnote: 'اختياريّ — حتى ٣٠٠ حرف',
        child: FieldTextBox(
          key: const ValueKey('field-cancel-reason'),
          controller: _reason,
          icon: LucideIcons.messageSquare,
          hint: 'مثلاً: المشترك أصلح الخلل بنفسه',
          minLines: 2,
          maxLines: 4,
          maxLength: 300,
        ),
      ),
    );
  }
}
