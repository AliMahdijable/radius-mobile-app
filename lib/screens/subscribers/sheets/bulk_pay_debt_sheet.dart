import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscribers_api.dart';
import '../../../core/util/format.dart';
import '../../../models/subscriber.dart';
import '../../../services/subscriber_events.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/util/amount_input.dart';

/// Bulk pay-debt sheet — mirrors v1's bulk_renew_sheet per-row pattern
/// from mobile-app/lib/screens/subscribers/bulk_renew_sheet.dart. The
/// admin long-presses to select N subscribers, opens this sheet, and
/// configures a payment for EACH row independently:
///   - amount field (thousands-formatted, ACCUMULATING chips)
///   - 'كامل' toggle that locks the field to the row's current debt
///   - per-row preview: 'دين قبل → دين/رصيد بعد'
/// A header summary tallies how many rows are ready and the total cash
/// that will be moved. Submit loops payDebt() per row; failures don't
/// abort siblings — the result snackbar reports ok/fail counts.
///
/// Only subscribers with debt > 0 are included (the screen pre-filters
/// before opening — see the caller). Returns true when at least one
/// payment succeeded so the caller can refresh.
Future<bool?> showBulkPayDebtSheet(
  BuildContext context, {
  required List<Subscriber> subs,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _BulkPayDebtSheet(subs: subs),
  );
}

class _BulkPayDebtSheet extends StatefulWidget {
  const _BulkPayDebtSheet({required this.subs});
  final List<Subscriber> subs;

  @override
  State<_BulkPayDebtSheet> createState() => _BulkPayDebtSheetState();
}

/// Per-row state — its own controller + flags so each row is fully
/// independent. We mutate this inside setState so the parent rebuild
/// picks up amount changes (live preview + footer totals).
class _PayRow {
  _PayRow(this.sub)
      : controller = TextEditingController(),
        debt = sub.debtAbs;
  final Subscriber sub;
  final TextEditingController controller;
  final double debt;
  int amount = 0;
  bool payAll = false;
  // ok = succeeded, err = failed-with-message, null = still pending
  // (i.e. either not yet attempted or the bulk run hasn't started).
  bool? ok;
  String? err;
  bool _suppressFormat = false;

  double get effectiveAmount => payAll ? debt : amount.toDouble();

  bool get ready => effectiveAmount > 0 && effectiveAmount <= debt;

  void dispose() => controller.dispose();
}

class _BulkPayDebtSheetState extends State<_BulkPayDebtSheet> {
  late final List<_PayRow> _rows;
  bool _submitting = false;
  int _doneCount = 0;

  @override
  void initState() {
    super.initState();
    _rows = widget.subs.map(_PayRow.new).toList();
    for (final r in _rows) {
      r.controller.addListener(() => _onAmountChanged(r));
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _onAmountChanged(_PayRow r) {
    if (r._suppressFormat) return;
    final digits = r.controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    final parsed = int.tryParse(digits) ?? 0;
    final formatted = _formatThousands(parsed);
    if (formatted != r.controller.text) {
      r._suppressFormat = true;
      r.controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      r._suppressFormat = false;
    }
    if (parsed != r.amount) setState(() => r.amount = parsed);
  }

  void _addToAmount(_PayRow r, int chip) {
    if (r.payAll) return;
    final next = r.amount + chip;
    final capped = next > r.debt.round() ? r.debt.round() : next;
    final formatted = _formatThousands(capped);
    r._suppressFormat = true;
    r.controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    r._suppressFormat = false;
    setState(() => r.amount = capped);
  }

  void _togglePayAll(_PayRow r) {
    setState(() {
      r.payAll = !r.payAll;
      if (r.payAll) {
        final whole = r.debt.round();
        final formatted = _formatThousands(whole);
        r._suppressFormat = true;
        r.controller.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
        r._suppressFormat = false;
        r.amount = whole;
      } else {
        r._suppressFormat = true;
        r.controller.clear();
        r._suppressFormat = false;
        r.amount = 0;
      }
    });
  }

  static String _formatThousands(int v) {
    if (v == 0) return '';
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  ({int readyCount, double totalCash}) get _summary {
    var c = 0;
    var t = 0.0;
    for (final r in _rows) {
      if (r.ready) {
        c++;
        t += r.effectiveAmount;
      }
    }
    return (readyCount: c, totalCash: t);
  }

  bool get _canSubmit {
    if (_submitting) return false;
    return _summary.readyCount > 0;
  }

  Future<void> _submit() async {
    final ready = _rows.where((r) => r.ready).toList();
    if (ready.isEmpty) return;
    setState(() {
      _submitting = true;
      _doneCount = 0;
      for (final r in _rows) {
        r.ok = null;
        r.err = null;
      }
    });
    var anyOk = false;
    for (final r in ready) {
      if (r.sub.idx == null) {
        r.ok = false;
        r.err = 'sheets.no_idx'.tr();
        if (mounted) setState(() => _doneCount++);
        continue;
      }
      final res = await SubscribersApi.payDebt(
        idx: r.sub.idx!,
        amount: r.effectiveAmount,
      );
      if (!mounted) return;
      setState(() {
        r.ok = res.ok;
        r.err = res.ok ? null : res.message;
        _doneCount++;
      });
      if (res.ok) anyOk = true;
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    if (anyOk) SubscriberEvents.notifyChange();
    final okCount = _rows.where((r) => r.ok == true).length;
    final failCount = _rows.where((r) => r.ok == false).length;
    showSheetSnack(
        context,
        failCount == 0
            ? 'sheets.paid_n_subs'.tr(namedArgs: {'n': '$okCount'})
            : 'sheets.done_failed'
                .tr(namedArgs: {'ok': '$okCount', 'fail': '$failCount'}),
        isError: (failCount == 0) ? false : true);
    // Auto-close only when everything succeeded — leave the sheet open
    // on partial failure so the admin can see which rows failed.
    if (anyOk && failCount == 0 && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = _summary;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.banknote,
        title: 'sheets.bulk_pay_debt_title'.tr(),
        subtitle: '${_rows.length} مشترك',
        tint: AppColors.brandAccent,
        onClose: _submitting ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _submitting
            ? 'sheets.paying_progress'.tr(
                namedArgs: {'done': '$_doneCount', 'total': '${s.readyCount}'})
            : 'sheets.pay_n_subs'.tr(namedArgs: {
                'n': '${s.readyCount}',
                'amt':
                    '${formatIQD(s.totalCash.round())} ${'common.currency'.tr()}'
              }),
        icon: LucideIcons.banknote,
        color: AppColors.brandAccent,
        enabled: _canSubmit,
        busy: _submitting,
        onPressed: _submit,
      ),
      maxHeightFactor: 0.97,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          _SummaryStrip(
            readyCount: s.readyCount,
            totalRows: _rows.length,
            totalCash: s.totalCash,
            doneCount: _doneCount,
            submitting: _submitting,
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.md),
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: Sp.sm),
              itemBuilder: (_, i) {
                final r = _rows[i];
                return _PayRowCard(
                  row: r,
                  enabled: !_submitting,
                  onClear: () {
                    r._suppressFormat = true;
                    r.controller.clear();
                    r._suppressFormat = false;
                    setState(() => r.amount = 0);
                  },
                  onChipTap: (v) => _addToAmount(r, v),
                  onTogglePayAll: () => _togglePayAll(r),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.readyCount,
    required this.totalRows,
    required this.totalCash,
    required this.doneCount,
    required this.submitting,
  });
  final int readyCount;
  final int totalRows;
  final double totalCash;
  final int doneCount;
  final bool submitting;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.xs, Sp.lg, Sp.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(R.pill),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              'sheets.ready_of'.tr(
                  namedArgs: {'ready': '$readyCount', 'total': '$totalRows'}),
              style: AppType.muted(color: AppColors.success)
                  .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          const Spacer(),
          if (submitting)
            Text(
              'sheets.done_n'.tr(namedArgs: {'n': '$doneCount'}),
              style: AppType.muted(color: AppColors.textMid).copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Text(
              '${'sheets.total_label'.tr()}: ${formatIQD(totalCash.round())} ${'common.currency'.tr()}',
              style: AppType.label(color: AppColors.textHi).copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _PayRowCard extends StatelessWidget {
  const _PayRowCard({
    required this.row,
    required this.enabled,
    required this.onClear,
    required this.onChipTap,
    required this.onTogglePayAll,
  });
  final _PayRow row;
  final bool enabled;
  final VoidCallback onClear;
  final ValueChanged<int> onChipTap;
  final VoidCallback onTogglePayAll;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.success;
    final chips = const [5000, 10000, 15000, 25000, 50000]
        .where((c) => c < row.debt)
        .toList();
    final showPreview = row.effectiveAmount > 0;
    final balanceAfter = row.sub.balanceAmount + row.effectiveAmount;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(
          color: _statusBorderColor(row),
          width: row.ok != null ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header — name + debt chip + status icon
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.sub.fullName,
                      style: AppType.label(color: AppColors.textHi).copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      row.sub.username,
                      style: AppType.muted(color: AppColors.textLow).copyWith(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoftBg,
                  borderRadius: BorderRadius.circular(R.pill),
                  border: Border.all(
                    color: AppColors.dangerSoftBorder,
                  ),
                ),
                child: Text(
                  '${formatIQD(row.debt.round())} د.ع',
                  style: AppType.muted(color: AppColors.error).copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (row.ok != null) ...[
                const SizedBox(width: 6),
                Icon(
                  row.ok! ? LucideIcons.circleCheck : LucideIcons.circleX,
                  color: row.ok! ? AppColors.success : AppColors.error,
                  size: 18,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // Amount field
          AmountShorthandBox(
              controller: row.controller,
              enabled: enabled && !row.payAll,
              child: TextField(
                controller: row.controller,
                enabled: enabled && !row.payAll,
                keyboardType: TextInputType.number,
                style: AppType.input(color: AppColors.textHi),
                decoration: InputDecoration(
                  hintText: 'sheets.paid_amount'.tr(),
                  hintStyle: AppType.input(color: AppColors.textLow),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(R.sm),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  suffixText: 'common.currency'.tr(),
                  suffixIcon:
                      enabled && !row.payAll && row.controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(LucideIcons.x, size: 16),
                              onPressed: onClear,
                              visualDensity: VisualDensity.compact,
                            )
                          : null,
                ),
              )),
          if (chips.isNotEmpty && !row.payAll) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final amount in chips)
                  InkWell(
                    onTap: enabled
                        ? () {
                            HapticFeedback.selectionClick();
                            onChipTap(amount);
                          }
                        : null,
                    borderRadius: BorderRadius.circular(R.pill),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(R.pill),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        formatIQD(amount),
                        style: AppType.muted(color: accent).copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          InkWell(
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    onTogglePayAll();
                  }
                : null,
            borderRadius: BorderRadius.circular(R.sm),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: row.payAll
                    ? accent.withValues(alpha: 0.08)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(
                  color: row.payAll
                      ? accent.withValues(alpha: 0.3)
                      : AppColors.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    row.payAll ? LucideIcons.squareCheck : LucideIcons.square,
                    color: row.payAll ? accent : AppColors.textMid,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'sheets.full_debt'.tr(),
                    style: AppType.label(color: AppColors.textHi).copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showPreview) ...[
            const SizedBox(height: 6),
            _RowPreview(
              effectiveAmount: row.effectiveAmount,
              balanceAfter: balanceAfter,
            ),
          ],
          if (row.err != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(LucideIcons.triangleAlert,
                    size: 12, color: AppColors.error),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    row.err!,
                    style: AppType.muted(color: AppColors.error).copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Border color reflects per-row state — soft border by default,
  /// brand-tinted while configured, success/error when done.
  static Color _statusBorderColor(_PayRow r) {
    if (r.ok == true) return AppColors.success.withValues(alpha: 0.5);
    if (r.ok == false) return AppColors.dangerSoftBorder;
    if (r.ready) {
      return AppColors.success.withValues(alpha: 0.35);
    }
    return AppColors.border;
  }
}

class _RowPreview extends StatelessWidget {
  const _RowPreview({
    required this.effectiveAmount,
    required this.balanceAfter,
  });
  final double effectiveAmount;
  final double balanceAfter;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final isCredit = balanceAfter >= 0;
    final color = isCredit ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(
            isCredit ? LucideIcons.circleCheck : LucideIcons.timer,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            isCredit ? 'sheets.after_pay'.tr() : 'sheets.remaining_debt'.tr(),
            style: AppType.muted(color: AppColors.textMid).copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (isCredit)
            Text(
              '${'subscribers.balance_short'.tr()} ',
              style: AppType.muted(color: color).copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          Text(
            '${formatIQD(balanceAfter.abs().round())} د.ع',
            style: AppType.label(color: color).copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────── shared sheet chrome (copy of activate_sheet's) ─────────
