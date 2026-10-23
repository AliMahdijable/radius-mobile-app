import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/recurring_expenses_api.dart';
import '../../core/util/amount_input.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// «الصرفيات الثابتة» (٢٣ أكتوبر ٢٠٢٦) — قسمٌ أعلى شاشة الصرفيات: القوالب، والمعلَّقة بانتظار التأكيد، والإنشاء
/// والتعديل والإيقاف و«دفعتها الآن» والحذف. كلّ استحقاقٍ صرفيّةٌ عاديّة تظهر بالقائمة تحته بشارة «ثابتة». يظهر حين يفتحه
/// الخادم للحساب أو حين له قوالب سابقة — وإلّا الشاشة كما كانت حرفاً ([RecurringPage.visible]).
///
/// [reloadToken] يتغيّر مع كلّ سحبٍ للتحديث في الشاشة فيُعاد الجلب، و[onExpensesChanged] بعد كلّ كتابةٍ قد تُضيف صرفيّة.
class RecurringExpensesSection extends StatefulWidget {
  const RecurringExpensesSection({super.key, required this.reloadToken, required this.onExpensesChanged});
  final int reloadToken;
  final VoidCallback onExpensesChanged;

  @override
  State<RecurringExpensesSection> createState() => _RecurringExpensesSectionState();
}

String _money(num v) => '${formatIQD(v)} ${'common.currency'.tr()}';

Future<T?> _sheet<T>(BuildContext context, Widget sheet) => showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => sheet,
    );

class _RecurringExpensesSectionState extends State<RecurringExpensesSection> {
  RecurringPage? _page;
  String? _busyKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RecurringExpensesSection old) {
    super.didUpdateWidget(old);
    if (old.reloadToken != widget.reloadToken) _load();
  }

  Future<void> _load() async {
    final r = await RecurringExpensesApi.list();
    if (!mounted) return;
    setState(() => _page = r.page ?? _page);
  }

  void _changed() {
    _load();
    widget.onExpensesChanged();
  }

  Future<void> _act(String key, Future<RecurringWrite> Function() call, String ok) async {
    setState(() => _busyKey = key);
    final r = await call();
    if (!mounted) return;
    setState(() => _busyKey = null);
    showSheetSnack(context, r.ok ? ok : (r.message ?? 'rexp.failed'.tr()), isError: !r.ok);
    _changed();
  }

  Future<void> _skip(RecurringRun r) async {
    final ok = await showConfirmSheet(
      context,
      title: 'rexp.skip_q_title'.tr(namedArgs: {'name': r.name ?? ''}),
      message: 'rexp.skip_q_body'.tr(namedArgs: {'p': recurringPeriodLabel(r.period)}),
      confirmLabel: 'rexp.skip_btn'.tr(),
      icon: LucideIcons.skipForward,
      tone: AppTone.warning,
    );
    if (ok != true || !mounted) return;
    await _act('skip${r.id}', () => RecurringExpensesApi.skip(r.id), 'rexp.skipped'.tr());
  }

  Future<void> _delete(RecurringTemplate t) async {
    final ok = await showConfirmSheet(
      context,
      title: 'rexp.delete_q_title'.tr(namedArgs: {'name': t.name}),
      message: 'rexp.delete_q_body'.tr(),
      confirmLabel: 'common.delete'.tr(),
      icon: LucideIcons.trash2,
      tone: AppTone.danger,
    );
    if (ok != true || !mounted) return;
    await _act('del${t.id}', () => RecurringExpensesApi.delete(t.id), 'rexp.deleted'.tr());
  }

  Future<void> _openTemplate(RecurringTemplate? t) async {
    final page = _page;
    if (page == null) return;
    final done = await _sheet<bool>(context, _TemplateSheet(template: t, today: page.today));
    if (done == true) _changed();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final page = _page;
    if (page == null || !page.visible) return const SizedBox.shrink();
    final enabled = page.enabled;
    final busy = _busyKey != null;
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.sm),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.sm)),
                  child: Icon(LucideIcons.repeat, size: 16, color: AppColors.brand),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('rexp.title'.tr(), style: AppType.bodyStrong(color: AppColors.textHi)),
                      Text(
                        'rexp.subtitle'.tr(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.sm),
                FilledButton.icon(
                  onPressed: enabled && !busy ? () => _openTemplate(null) : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: AppColors.onBrand,
                    padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                    minimumSize: const Size(0, 36),
                  ),
                  icon: const Icon(LucideIcons.plus, size: 15),
                  label: Text('rexp.add'.tr(), style: AppType.labelBold(color: AppColors.onBrand)),
                ),
              ],
            ),
          ),
          if (!enabled)
            Container(
              color: AppColors.warningSoftBg,
              padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
              child: Text(
                'rexp.off_note'.tr(),
                style: AppType.muted(color: AppTone.warning.onSoft).copyWith(fontSize: 12.5),
              ),
            ),
          if (page.pending.isNotEmpty)
            Container(
              color: AppColors.warningSoftBg.withValues(alpha: 0.6),
              padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.bellRing, size: 14, color: AppTone.warning.onSoft),
                      const SizedBox(width: Sp.xs),
                      Text(
                        'rexp.pending_n'.tr(namedArgs: {'n': '${page.pending.length}'}),
                        style: AppType.labelBold(color: AppTone.warning.onSoft),
                      ),
                    ],
                  ),
                  for (final r in page.pending) ...[
                    const SizedBox(height: Sp.sm),
                    _PendingTile(
                      run: r,
                      enabled: enabled && !busy,
                      busySkip: _busyKey == 'skip${r.id}',
                      onConfirm: () async {
                        final done = await _sheet<bool>(context, _ConfirmRunSheet(run: r));
                        if (done == true) _changed();
                      },
                      onSkip: () => _skip(r),
                    ),
                  ],
                ],
              ),
            ),
          if (page.templates.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.md),
              child: Text(
                'rexp.empty'.tr(),
                textAlign: TextAlign.center,
                style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
              ),
            )
          else
            for (final t in page.templates)
              _TemplateTile(
                template: t,
                enabled: enabled && !busy,
                busyKey: _busyKey,
                onEdit: () => _openTemplate(t),
                onDelete: () => _delete(t),
                onToggle: () => _act(
                  'st${t.id}',
                  () => t.isActive ? RecurringExpensesApi.pause(t.id) : RecurringExpensesApi.resume(t.id),
                  (t.isActive ? 'rexp.paused_done' : 'rexp.resumed_done').tr(),
                ),
                onPayNow: () async {
                  final done = await _sheet<bool>(context, _PayNowSheet(template: t, today: page.today));
                  if (done == true) _changed();
                },
              ),
        ],
      ),
    );
  }
}

class _PendingTile extends StatelessWidget {
  const _PendingTile({
    required this.run,
    required this.enabled,
    required this.busySkip,
    required this.onConfirm,
    required this.onSkip,
  });
  final RecurringRun run;
  final bool enabled;
  final bool busySkip;
  final VoidCallback onConfirm;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  run.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong(color: AppColors.textHi),
                ),
              ),
              Text(_money(run.amount), style: AppType.labelBold(color: AppColors.error)),
            ],
          ),
          const SizedBox(height: Sp.xxs),
          Text(
            '${recurringPeriodLabel(run.period)} · ${'rexp.due_on'.tr(namedArgs: {'d': recurringDateLabel(run.dueDate)})}',
            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5),
          ),
          const SizedBox(height: Sp.sm),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: enabled ? onConfirm : null,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: AppColors.onBrand, minimumSize: const Size(0, 36)),
                  icon: const Icon(LucideIcons.circleCheck, size: 15),
                  label: Text('rexp.confirm_btn'.tr(), style: AppType.labelBold(color: AppColors.onBrand)),
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled ? onSkip : null,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                  icon: busySkip
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(LucideIcons.skipForward, size: 15),
                  label: Text('rexp.skip_btn'.tr(), style: AppType.labelBold(color: AppColors.textBody)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.enabled,
    required this.busyKey,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onPayNow,
  });
  final RecurringTemplate template;
  final bool enabled;
  final String? busyKey;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;
  final VoidCallback onPayNow;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final t = template;
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.sm, Sp.sm),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong(color: AppColors.textHi),
                ),
              ),
              const SizedBox(width: Sp.x6),
              ToneChip(
                label: (t.isAuto ? 'rexp.mode_auto' : 'rexp.mode_confirm').tr(),
                tone: t.isAuto ? AppTone.info : AppTone.warning,
                dense: true,
              ),
              if (!t.isActive) ...[
                const SizedBox(width: Sp.x6),
                ToneChip(label: (t.isPaused ? 'rexp.paused' : 'rexp.ended').tr(), dense: true),
              ],
              const Spacer(),
              Text(_money(t.amount), style: AppType.labelBold(color: AppColors.error)),
            ],
          ),
          const SizedBox(height: Sp.xxs),
          Text(
            [
              recurringScheduleText(every: t.every, day: t.day, endPeriod: t.endPeriod),
              if (t.isActive && t.nextDueDate != null) 'rexp.next_n'.tr(namedArgs: {'d': recurringDateLabel(t.nextDueDate)}),
            ].join(' · '),
            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5),
          ),
          if (t.last != null)
            Text(
              'rexp.last_n'.tr(namedArgs: {'t': recurringLastText(t.last!)}),
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!t.isEnded)
                _Act(icon: LucideIcons.handCoins, tooltip: 'rexp.pay_now'.tr(), enabled: enabled, onTap: onPayNow),
              if (!t.isEnded)
                _Act(
                  icon: t.isActive ? LucideIcons.pause : LucideIcons.play,
                  tooltip: (t.isActive ? 'rexp.pause' : 'rexp.resume').tr(),
                  enabled: enabled,
                  busy: busyKey == 'st${t.id}',
                  onTap: onToggle,
                ),
              _Act(icon: LucideIcons.pencil, tooltip: 'rexp.edit'.tr(), enabled: enabled, onTap: onEdit),
              _Act(
                icon: LucideIcons.trash2,
                tooltip: 'common.delete'.tr(),
                enabled: enabled,
                busy: busyKey == 'del${t.id}',
                color: AppColors.error,
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Act extends StatelessWidget {
  const _Act({required this.icon, required this.tooltip, required this.enabled, required this.onTap, this.busy = false, this.color});
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final bool busy;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onTap : null,
      icon: busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 17, color: enabled ? (color ?? AppColors.textBody) : AppColors.textLow),
      visualDensity: VisualDensity.compact,
    );
  }
}

// ═══════════════════════════ الشيتات ═══════════════════════════

/// صفّ اختيارٍ يفتح قائمة (يوم الاستحقاق، التكرار، أوّل/آخر شهر).
class _PickRow extends StatelessWidget {
  const _PickRow({required this.icon, required this.value, required this.onTap, this.enabled = true});
  final IconData icon;
  final String value;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(R.lg),
      child: SheetBox(
        icon: icon,
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.input(color: enabled ? AppColors.textHi : AppColors.textLow),
              ),
            ),
            if (enabled) Icon(LucideIcons.chevronDown, size: 15, color: AppColors.textLow),
          ],
        ),
      ),
    );
  }
}

Future<T?> _pick<T>(BuildContext context, String title, List<(T, String)> options, T selected) {
  return _sheet<T>(
    context,
    DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.listChecks,
        title: title,
        subtitle: '',
        onClose: () => Navigator.of(context).pop(),
      ),
      bodyPadding: EdgeInsets.zero,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label) in options)
            ListTile(
              dense: true,
              title: Text(label, style: AppType.input(color: AppColors.textHi)),
              trailing: v == selected ? Icon(LucideIcons.check, size: 16, color: AppColors.brand) : null,
              onTap: () => Navigator.of(context).pop(v),
            ),
        ],
      ),
    ),
  );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.selected, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const tone = AppTone.brand;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(R.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? tone.softBg : null,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: selected ? tone.fill : AppColors.border, width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: selected ? tone.fill : AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon, size: 16, color: selected ? AppColors.surface : AppColors.textMid),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: Sp.xxs),
                    Text(subtitle, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.5)),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: Sp.sm),
                Icon(LucideIcons.circleCheck, size: 18, color: tone.fill),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Money extends StatelessWidget {
  const _Money({required this.controller, required this.onValue});
  final TextEditingController controller;
  final ValueChanged<int> onValue;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SheetBox(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 12),
      child: AmountTextField(controller: controller, currency: 'common.currency'.tr(), shorthand: false, onValue: onValue),
    );
  }
}

class _TemplateSheet extends StatefulWidget {
  const _TemplateSheet({required this.template, required this.today});
  final RecurringTemplate? template;
  final String today;

  @override
  State<_TemplateSheet> createState() => _TemplateSheetState();
}

class _TemplateSheetState extends State<_TemplateSheet> {
  late final _name = TextEditingController(text: widget.template?.name ?? '');
  late final _amount = TextEditingController(
      text: widget.template == null ? '' : AmountShorthand.format(widget.template!.amount.round()));
  late final _note = TextEditingController(text: widget.template?.note ?? '');
  late int _amountValue = widget.template?.amount.round() ?? 0;
  late int _day = widget.template?.day ?? 1;
  late int _every = widget.template?.every ?? 1;
  late String _start = widget.template?.startPeriod ?? _thisMonth;
  late String? _end = widget.template?.endPeriod;
  late String? _mode = widget.template?.mode;
  bool _busy = false;
  final String _ref = List.generate(24, (_) => Random.secure().nextInt(16).toRadixString(16)).join();

  bool get _isEdit => widget.template != null;
  String get _thisMonth => widget.today.length >= 7 ? widget.today.substring(0, 7) : '';

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _ok => !_busy && _name.text.trim().length >= 2 && _amountValue > 0 && _amountValue <= 50000000 && _mode != null;

  Future<void> _submit() async {
    setState(() => _busy = true);
    final name = _name.text.trim();
    final note = _note.text.trim();
    final RecurringWrite r;
    if (_isEdit) {
      r = await RecurringExpensesApi.update(widget.template!.id, {
        'name': name,
        'amount': _amountValue,
        'day': _day,
        'every': _every,
        'end_period': _end,
        'mode': _mode,
        'note': note.isEmpty ? null : note,
      });
    } else {
      r = await RecurringExpensesApi.create(
        name: name,
        amount: _amountValue,
        day: _day,
        every: _every,
        startPeriod: _start,
        endPeriod: _end,
        mode: _mode!,
        note: note,
        clientRef: _ref,
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'rexp.failed'.tr(), isError: true);
      return;
    }
    final gen = r.generated.isEmpty ? null : r.generated.first;
    final String msg;
    if (_isEdit) {
      msg = gen == null ? 'rexp.saved'.tr() : 'rexp.saved_gen_n'.tr(namedArgs: {'p': recurringPeriodLabel(gen.period)});
    } else if (gen == null) {
      msg = 'rexp.created_n'.tr(namedArgs: {'name': name, 'd': recurringDateLabel(recurringDueDate(_start, _day))});
    } else if (gen.isPending) {
      msg = 'rexp.created_pending_n'.tr(namedArgs: {'name': name, 'p': recurringPeriodLabel(gen.period)});
    } else {
      msg = 'rexp.created_gen_n'.tr(namedArgs: {'name': name, 'p': recurringPeriodLabel(gen.period)});
    }
    showSheetSnack(context, msg);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final first = recurringDueDate(_start, _day);
    final dueNow = !_isEdit && first.isNotEmpty && first.compareTo(widget.today) <= 0;
    final endBase = _isEdit ? widget.template!.startPeriod : _start;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.repeat,
        title: _isEdit ? 'rexp.sheet_edit_n'.tr(namedArgs: {'name': widget.template!.name}) : 'rexp.sheet_new'.tr(),
        subtitle: 'rexp.sheet_sub'.tr(),
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _mode == null ? 'rexp.pick_mode'.tr() : (_isEdit ? 'rexp.save_edit' : 'rexp.save').tr(),
        icon: LucideIcons.check,
        enabled: _ok,
        busy: _busy,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSection(
            label: '${'rexp.f_name'.tr()} *',
            child: SheetBox(
              icon: LucideIcons.tag,
              child: TextField(
                controller: _name,
                maxLength: 120,
                style: AppType.input(),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'rexp.f_name_hint'.tr(),
                  hintStyle: AppType.input(color: AppColors.textPlaceholder),
                ),
              ),
            ),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: '${'rexp.f_amount'.tr()} *',
            footnote: 'rexp.f_amount_hint'.tr(),
            child: _Money(controller: _amount, onValue: (v) => setState(() => _amountValue = v)),
          ),
          const SizedBox(height: Sp.lg),
          Row(
            children: [
              Expanded(
                child: SheetSection(
                  label: 'rexp.f_day'.tr(),
                  child: _PickRow(
                    icon: LucideIcons.calendarDays,
                    value: recurringDayLabel(_day),
                    onTap: () async {
                      final v = await _pick<int>(context, 'rexp.f_day'.tr(),
                          [for (var d = 1; d <= 31; d++) (d, recurringDayLabel(d))], _day);
                      if (v != null) setState(() => _day = v);
                    },
                  ),
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: SheetSection(
                  label: 'rexp.f_every'.tr(),
                  child: _PickRow(
                    icon: LucideIcons.repeat,
                    value: recurringEveryLabel(_every),
                    onTap: () async {
                      final v = await _pick<int>(context, 'rexp.f_every'.tr(),
                          [for (final e in RecurringExpensesApi.everyOptions) (e, recurringEveryLabel(e))], _every);
                      if (v != null) setState(() => _every = v);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'rexp.f_start'.tr(),
            footnote: _isEdit ? 'rexp.f_start_locked'.tr() : null,
            child: _PickRow(
              icon: LucideIcons.calendarClock,
              enabled: !_isEdit,
              value: _startLabel(_start),
              onTap: () async {
                final v = await _pick<String>(context, 'rexp.f_start'.tr(),
                    [for (var i = 0; i <= 12; i++) (recurringAddMonths(_thisMonth, i), _startLabel(recurringAddMonths(_thisMonth, i)))], _start);
                if (v != null) setState(() => _start = v);
              },
            ),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'rexp.f_end'.tr(),
            footnote: 'rexp.f_end_hint'.tr(),
            child: _PickRow(
              icon: LucideIcons.flagTriangleRight,
              value: _end == null ? 'rexp.end_none'.tr() : recurringPeriodLabel(_end),
              onTap: () async {
                final v = await _pick<String>(context, 'rexp.f_end'.tr(), [
                  ('', 'rexp.end_none'.tr()),
                  for (var i = 0; i <= 36; i++) (recurringAddMonths(endBase, i), recurringPeriodLabel(recurringAddMonths(endBase, i))),
                ], _end ?? '');
                if (v != null) setState(() => _end = v.isEmpty ? null : v);
              },
            ),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: '${'rexp.f_mode'.tr()} *',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ModeCard(
                  selected: _mode == 'auto',
                  icon: LucideIcons.zap,
                  title: 'rexp.mode_auto_title'.tr(),
                  subtitle: 'rexp.mode_auto_sub'.tr(),
                  onTap: () => setState(() => _mode = 'auto'),
                ),
                const SizedBox(height: Sp.sm),
                _ModeCard(
                  selected: _mode == 'confirm',
                  icon: LucideIcons.bellRing,
                  title: 'rexp.mode_confirm_title'.tr(),
                  subtitle: 'rexp.mode_confirm_sub'.tr(),
                  onTap: () => setState(() => _mode = 'confirm'),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'rexp.f_note'.tr(),
            child: SheetNoteField(controller: _note, hint: '', maxLength: 200),
          ),
          if (!_isEdit && first.isNotEmpty) ...[
            const SizedBox(height: Sp.lg),
            // معاينة أوّل صرفيّة قبل الحفظ — «هذا الشهر» ويومه مرّ ⇒ تُضاف الآن (يُنبَّه من سجّلها بيده).
            Container(
              padding: const EdgeInsets.all(Sp.md),
              decoration: BoxDecoration(
                color: dueNow ? AppColors.warningSoftBg : AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(R.lg),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.calendarClock, size: 16, color: dueNow ? AppTone.warning.onSoft : AppColors.brand),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'rexp.preview_first'.tr(namedArgs: {'d': recurringDateLabel(first)}),
                          style: AppType.labelBold(color: AppColors.textHi),
                        ),
                        const SizedBox(height: Sp.xxs),
                        Text(
                          dueNow
                              ? (_mode == 'confirm' ? 'rexp.preview_now_confirm' : 'rexp.preview_now_auto').tr()
                              : recurringScheduleText(every: _every, day: _day, endPeriod: _end),
                          style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_isEdit) ...[
            const SizedBox(height: Sp.md),
            Text(
              'rexp.edit_note'.tr(),
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.6),
            ),
          ],
        ],
      ),
    );
  }

  String _startLabel(String p) {
    if (p == _thisMonth) return 'rexp.start_this'.tr(namedArgs: {'p': recurringPeriodLabel(p)});
    if (p == recurringAddMonths(_thisMonth, 1)) return 'rexp.start_next'.tr(namedArgs: {'p': recurringPeriodLabel(p)});
    return recurringPeriodLabel(p);
  }
}

class _ConfirmRunSheet extends StatefulWidget {
  const _ConfirmRunSheet({required this.run});
  final RecurringRun run;

  @override
  State<_ConfirmRunSheet> createState() => _ConfirmRunSheetState();
}

class _ConfirmRunSheetState extends State<_ConfirmRunSheet> {
  late final _amount = TextEditingController(text: AmountShorthand.format(widget.run.amount.round()));
  final _note = TextEditingController();
  late int _value = widget.run.amount.round();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final r = await RecurringExpensesApi.confirm(widget.run.id, amount: _value, note: _note.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'rexp.failed'.tr(), isError: true);
      return;
    }
    showSheetSnack(context, 'rexp.confirmed_n'.tr(namedArgs: {
      'name': widget.run.name ?? '',
      'a': _money(_value),
      'p': recurringPeriodLabel(widget.run.period),
    }));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final run = widget.run;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.bellRing,
        tint: AppTone.warning.fill,
        tintBg: AppTone.warning.softBg,
        title: run.name ?? '',
        subtitle: 'rexp.confirm_sub_n'.tr(namedArgs: {'p': recurringPeriodLabel(run.period), 'd': recurringDateLabel(run.dueDate)}),
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: 'rexp.confirm_btn_n'.tr(namedArgs: {'a': _value > 0 ? _money(_value) : ''}).trim(),
        icon: LucideIcons.check,
        enabled: !_busy && _value > 0,
        busy: _busy,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSection(
            label: 'rexp.f_paid'.tr(),
            footnote: 'rexp.f_paid_hint'.tr(),
            child: _Money(controller: _amount, onValue: (v) => setState(() => _value = v)),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'rexp.f_note_opt'.tr(),
            child: SheetNoteField(controller: _note, hint: '', maxLength: 200),
          ),
        ],
      ),
    );
  }
}

class _PayNowSheet extends StatefulWidget {
  const _PayNowSheet({required this.template, required this.today});
  final RecurringTemplate template;
  final String today;

  @override
  State<_PayNowSheet> createState() => _PayNowSheetState();
}

class _PayNowSheetState extends State<_PayNowSheet> {
  late final _amount = TextEditingController(text: AmountShorthand.format(widget.template.amount.round()));
  late int _value = widget.template.amount.round();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final r = await RecurringExpensesApi.payNow(widget.template.id, amount: _value);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'rexp.failed'.tr(), isError: true);
      return;
    }
    showSheetSnack(context, 'rexp.paid_n'.tr(namedArgs: {'name': widget.template.name, 'a': _money(_value)}));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.handCoins,
        title: 'rexp.paynow_title_n'.tr(namedArgs: {'name': widget.template.name}),
        subtitle: 'rexp.paynow_sub_n'.tr(namedArgs: {'d': recurringDateLabel(widget.today)}),
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: 'rexp.paynow_btn_n'.tr(namedArgs: {'a': _value > 0 ? _money(_value) : ''}).trim(),
        icon: LucideIcons.check,
        enabled: !_busy && _value > 0,
        busy: _busy,
        onPressed: _submit,
      ),
      body: SheetSection(
        label: 'rexp.f_paid'.tr(),
        child: _Money(controller: _amount, onValue: (v) => setState(() => _value = v)),
      ),
    );
  }
}
