import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/settlements_api.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../services/settlement_print.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../settle_widgets.dart';

/// سند التسوية: اللقطة، وحصص المنفّذين، والحركات، والطباعة، والإلغاء.
/// يُرجع `true` حين أُلغي السجلّ (فتعيد الشاشة الحساب).
Future<bool?> showSettlementDetailSheet(
  BuildContext context, {
  required int id,
  required int? headId,
  required bool canVoid,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _DetailSheet(id: id, headId: headId, canVoid: canVoid),
  );
}

class _DetailSheet extends StatefulWidget {
  const _DetailSheet({
    required this.id,
    required this.headId,
    required this.canVoid,
  });
  final int id;
  final int? headId;
  final bool canVoid;

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  SettlementRecord? _s;
  bool _loading = true;
  String? _error;
  bool _showMoves = false;
  bool _movesLoading = false;
  List<BoxMovement> _moves = const [];
  bool _movesMore = false;
  bool _printing = false;
  bool _voiding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await SettlementsApi.get(widget.id);
    if (!mounted) return;
    setState(() {
      _s = r.data;
      _error = r.data == null ? (r.message ?? 'common.load_failed'.tr()) : null;
      _loading = false;
    });
  }

  /// الإلغاء لآخر سجلٍّ فعّال وحده، وللمدير صاحب الحساب.
  bool get _canVoidThis {
    final s = _s;
    return s != null && widget.canVoid && !s.isVoided && s.id == widget.headId;
  }

  Future<void> _toggleMoves() async {
    if (_showMoves) {
      setState(() => _showMoves = false);
      return;
    }
    setState(() {
      _showMoves = true;
      _movesLoading = _moves.isEmpty;
    });
    if (_moves.isNotEmpty) return;
    final r = await SettlementsApi.movements(settlement: '${widget.id}', limit: 200);
    if (!mounted) return;
    setState(() {
      _moves = r.items;
      _movesMore = r.hasMore;
      _movesLoading = false;
    });
  }

  Future<void> _print() async {
    final s = _s;
    if (s == null || _printing) return;
    setState(() => _printing = true);
    final ok = await SettlementPrint.printVoucher(s);
    if (!mounted) return;
    setState(() => _printing = false);
    if (!ok) showSheetSnack(context, 'settle.print_failed'.tr(), isError: true);
  }

  Future<void> _void() async {
    final s = _s;
    if (s == null || _voiding) return;
    final reason = await _askVoidReason(context, opening: s.isOpening);
    if (reason == null || !mounted) return;
    setState(() => _voiding = true);
    final r = await SettlementsApi.voidSettlement(s.id, reason);
    if (!mounted) return;
    setState(() => _voiding = false);
    showSheetSnack(
      context,
      r.message ?? (r.ok ? 'common.success'.tr() : 'common.load_failed'.tr()),
      isError: !r.ok,
    );
    if (r.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = _s;
    final title = s == null
        ? 'settle.voucher'.tr()
        : (s.isOpening
            ? 'settle.opening_title'.tr()
            : 'settle.voucher_title'.tr(namedArgs: {'n': '${s.number}'}));
    return DesignSheet(
      header: SheetHeaderBar(
        icon: s?.isOpening == true ? LucideIcons.play : LucideIcons.receiptText,
        title: title,
        subtitle: s == null ? '' : settleWhen(s.cutAt, weekday: true),
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: 'settle.print'.tr(),
        icon: LucideIcons.printer,
        busy: _printing,
        enabled: s != null && !_voiding,
        onPressed: _print,
        leading: _canVoidThis
            ? SheetFooterIconButton(
                icon: LucideIcons.rotateCcw,
                color: AppColors.error,
                onTap: _voiding ? null : _void,
              )
            : null,
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: Sp.huge),
              child: Center(child: CircularProgressIndicator()),
            )
          : (s == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: Sp.xl),
                  child: Text(
                    _error ?? 'common.load_failed'.tr(),
                    style: AppType.body(color: AppColors.error),
                  ),
                )
              : _content(s)),
    );
  }

  Widget _content(SettlementRecord s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.isVoided) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppTone.danger.softBg,
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: AppTone.danger.softBorder),
            ),
            child: Text(
              'settle.voided_line'.tr(namedArgs: {
                'when': settleWhen(s.voidedAt),
                'who': s.voidedBy ?? '—',
                'reason': s.voidReason ?? '',
              }),
              style: AppType.body(color: AppTone.danger.onSoft),
            ),
          ),
          const SizedBox(height: Sp.lg),
        ],
        SheetRowsGroup(rows: [
          if (!s.isOpening)
            SheetRowData(label: 'settle.from'.tr(), value: settleWhen(s.periodStartAt)),
          SheetRowData(
            label: s.isOpening ? 'settle.starts_from'.tr() : 'settle.to'.tr(),
            value: settleWhen(s.cutAt),
          ),
          if ((s.actingEmployeeUsername ?? '').isNotEmpty)
            SheetRowData(label: 'settle.done_by'.tr(), value: s.actingEmployeeUsername!),
        ]),
        const SizedBox(height: Sp.lg),
        if (s.isOpening)
          SheetRowsGroup(rows: [
            SheetRowData(
              label: 'settle.opening_balance'.tr(),
              value: settleMoney(s.openingBalance),
              strong: true,
            ),
          ])
        else
          SheetRowsGroup(rows: [
            if (s.openingBalance != 0)
              SheetRowData(
                label: 'settle.carried_balance'.tr(),
                value: settleMoney(s.openingBalance),
              ),
            SheetRowData(
              label: '${'settle.cash_activations'.tr()} · ${s.cashActivations.count}',
              value: '+${formatIQD(s.cashActivations.sum)}',
              valueColor: AppColors.success,
            ),
            SheetRowData(
              label: '${'settle.debt_payments'.tr()} · ${s.debtPayments.count}',
              value: '+${formatIQD(s.debtPayments.sum)}',
              valueColor: AppColors.success,
            ),
            SheetRowData(
              label: '${'settle.expenses'.tr()} · ${s.expenses.count}',
              value: '−${formatIQD(s.expenses.sum)}',
              valueColor: AppColors.error,
            ),
            SheetRowData(
              label: 'settle.expected'.tr(),
              value: settleMoney(s.expected),
              strong: true,
            ),
            SheetRowData(
              label: 'settle.received'.tr(),
              value: settleMoney(s.received),
              strong: true,
            ),
            SheetRowData(
              label: 'settle.carried'.tr(),
              value: settleMoney(s.carried),
            ),
          ]),
        if (!s.isOpening && s.newDebts.sum > 0) ...[
          const SizedBox(height: Sp.sm),
          Text(
            'settle.new_debts_short'.tr(namedArgs: {'amt': settleMoney(s.newDebts.sum)}),
            style: AppType.muted(),
          ),
        ],
        if (s.collectors.any((c) => !c.isManager)) ...[
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'settle.collectors_share'.tr(),
            child: CollectorsList(collectors: s.collectors),
          ),
        ],
        if ((s.note ?? '').isNotEmpty) ...[
          const SizedBox(height: Sp.lg),
          SheetBox(
            icon: LucideIcons.fileText,
            alignTop: true,
            child: Text(s.note!, style: AppType.input()),
          ),
        ],
        if (!s.isOpening) ...[
          const SizedBox(height: Sp.lg),
          _movesSection(s),
        ],
      ],
    );
  }

  Widget _movesSection(SettlementRecord s) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggleMoves,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'settle.voucher_moves'.tr(namedArgs: {'n': '${s.moveCount}'}),
                      style: AppType.bodyStrong(color: AppColors.textHi),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _showMoves ? LucideIcons.chevronDown : LucideIcons.chevronLeft,
                    size: 16,
                    color: AppColors.textLow,
                  ),
                ],
              ),
            ),
          ),
          if (_showMoves) ...[
            Divider(height: 1, color: AppColors.divider),
            if (_movesLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Sp.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_moves.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Sp.lg),
                child: Text('settle.no_moves_in_voucher'.tr(), style: AppType.muted()),
              )
            else ...[
              for (final m in _moves) MovementTile(m: m),
              if (_movesMore)
                Padding(
                  padding: const EdgeInsets.all(Sp.md),
                  child: Text(
                    'settle.moves_truncated'.tr(),
                    style: AppType.muted(),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

/// سبب الإلغاء — إلزاميّ، ثلاثة أحرف على الأقلّ (كالخادم).
Future<String?> _askVoidReason(BuildContext context, {required bool opening}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _VoidReasonSheet(opening: opening),
  );
}

class _VoidReasonSheet extends StatefulWidget {
  const _VoidReasonSheet({required this.opening});
  final bool opening;

  @override
  State<_VoidReasonSheet> createState() => _VoidReasonSheetState();
}

class _VoidReasonSheetState extends State<_VoidReasonSheet> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _ctrl.removeListener(_changed);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final ok = _ctrl.text.trim().length >= 3;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.rotateCcw,
        title: widget.opening
            ? 'settle.void_opening_title'.tr()
            : 'settle.void_title'.tr(),
        subtitle: '',
        tint: AppColors.error,
        tintBg: AppColors.dangerSoftBg,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: 'settle.void_confirm'.tr(),
        icon: LucideIcons.rotateCcw,
        color: AppColors.errorFill,
        enabled: ok,
        onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.opening
                ? 'settle.void_explain_opening'.tr()
                : 'settle.void_explain'.tr(),
            style: AppType.rowValue(color: AppColors.textBody).copyWith(height: 1.6),
          ),
          const SizedBox(height: Sp.lg),
          SheetNoteField(
            controller: _ctrl,
            hint: 'settle.void_reason_hint'.tr(),
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
          ),
        ],
      ),
    );
  }
}
