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

/// Bulk activate / renew sheet — direct port of v1's bulk_renew_sheet
/// from mobile-app/lib/screens/subscribers/bulk_renew_sheet.dart with
/// v2's design language.
///
/// Flow:
///   1. On open, fetch /api/v2/subscribers/:idx/activation-data in
///      parallel batches of 6 (matches v1's concurrency cap). Each
///      row gets package/price/discount/current-balance from the
///      response, or a load-failed flag if the call fails.
///   2. Sheet lists every selected subscriber as a card with a 3-way
///      payment method picker (دين / نقدي / جزئي), defaulting to
///      دين. Partial mode reveals an amount field with chips.
///   3. Header summary chip + a 'تعيين الكل' row (3 ghost buttons)
///      that bulk-applies a method to all renewable rows.
///   4. Submit loops activate() per row. Per-row outcome (ok/error)
///      reflects in the card's border + status icon.
///
/// Returns true when at least one row succeeds so the caller can
/// refresh + exit selection mode.
Future<bool?> showBulkActivateSheet(
  BuildContext context, {
  required List<Subscriber> subs,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _BulkActivateSheet(subs: subs),
  );
}

enum _PayMethod { debt, cash, partial }

extension _PayMethodX on _PayMethod {
  String get label => switch (this) {
        _PayMethod.debt => 'sheets.pay_debt'.tr(),
        _PayMethod.cash => 'sheets.pay_cash'.tr(),
        _PayMethod.partial => 'sheets.pay_partial'.tr(),
      };
  IconData get icon => switch (this) {
        _PayMethod.debt => LucideIcons.creditCard,
        _PayMethod.cash => LucideIcons.banknote,
        _PayMethod.partial => LucideIcons.walletCards,
      };
  Color get color => switch (this) {
        _PayMethod.debt => AppColors.error,
        _PayMethod.cash => AppColors.brand,
        _PayMethod.partial => AppColors.brandAccent,
      };

  /// Maps to the backend's expected enum on POST
  /// /api/v2/subscribers/:idx/activate.
  String get apiValue => switch (this) {
        _PayMethod.debt => 'non-cash',
        _PayMethod.cash => 'cash',
        _PayMethod.partial => 'partial-cash',
      };
}

/// Per-row state. Activation-data is cached here as `data` so the
/// submit call can echo it back verbatim (the backend enforces this —
/// see server.js comment about SAS4 session locks). The partial-amount
/// controller is owned by the row so each card stays independent.
class _RenewRow {
  _RenewRow.success({
    required this.sub,
    required this.data,
    required this.originalPrice,
    required this.discount,
    required this.effectivePrice,
    required this.currentBalance,
  })  : loadFailed = false,
        partialCtrl = TextEditingController(),
        method = _PayMethod.debt;

  _RenewRow.failed(this.sub)
      : data = null,
        originalPrice = 0,
        discount = 0,
        effectivePrice = 0,
        currentBalance = 0,
        loadFailed = true,
        partialCtrl = TextEditingController(),
        method = _PayMethod.debt;

  final Subscriber sub;
  final Map<String, dynamic>? data;
  final double originalPrice;
  final double discount;

  /// Price the admin pays — originalPrice - discount, never negative.
  final double effectivePrice;

  /// Signed balance (negative = debt, positive = credit). v1 calls
  /// this currentBalance.
  final double currentBalance;
  final bool loadFailed;
  final TextEditingController partialCtrl;

  _PayMethod method;
  int partialAmount = 0;
  bool _suppressFormat = false;
  // null = pending, true/false after submit.
  bool? ok;
  String? err;

  bool get renewable => !loadFailed;

  double get cashIn => switch (method) {
        _PayMethod.cash => effectivePrice,
        _PayMethod.partial => partialAmount.toDouble(),
        _PayMethod.debt => 0,
      };

  /// Mirrors v1's newBalance / v2's _balanceAfter:
  ///   cash    → balance unchanged
  ///   debt    → balance - price
  ///   partial → balance - price + partialAmount
  double get balanceAfter => switch (method) {
        _PayMethod.cash => currentBalance,
        _PayMethod.partial => currentBalance - effectivePrice + partialAmount,
        _PayMethod.debt => currentBalance - effectivePrice,
      };

  bool get ready {
    if (!renewable) return false;
    // Partial only requires positive amount. Excess over the package
    // price lands as a credit on the subscriber's notes — same as v1
    // (مطلب المستخدم 2026-06-07).
    if (method == _PayMethod.partial && partialAmount <= 0) return false;
    return true;
  }

  void dispose() => partialCtrl.dispose();
}

class _BulkActivateSheet extends StatefulWidget {
  const _BulkActivateSheet({required this.subs});
  final List<Subscriber> subs;

  @override
  State<_BulkActivateSheet> createState() => _BulkActivateSheetState();
}

class _BulkActivateSheetState extends State<_BulkActivateSheet> {
  bool _loading = true;
  bool _submitting = false;
  int _doneCount = 0;
  final List<_RenewRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    // Fetch activation-data in parallel batches — same concurrency cap
    // as v1 (6). Subscribers without an idx are flagged as load-failed
    // up front; without idx we can't activate them anyway.
    const concurrency = 6;
    final subs = widget.subs;
    final rows = <_RenewRow>[];
    for (var i = 0; i < subs.length; i += concurrency) {
      if (!mounted) return;
      final batch = subs.skip(i).take(concurrency).toList();
      final results = await Future.wait(batch.map((s) async {
        if (s.idx == null) return MapEntry(s, null);
        final ad = await SubscribersApi.fetchActivationData(s.idx!);
        return MapEntry(s, ad);
      }));
      for (final e in results) {
        final s = e.key;
        final ad = e.value;
        if (ad == null) {
          rows.add(_RenewRow.failed(s));
          continue;
        }
        double readD(String key) {
          final v = ad[key];
          if (v is num) return v.toDouble();
          if (v == null) return 0;
          return double.tryParse(
                  v.toString().replaceAll(RegExp(r'[^0-9.\-]'), '')) ??
              0;
        }

        final originalPrice = readD('user_price');
        final discount = readD('discount_amount');
        final effective = readD('price_after_discount');
        rows.add(
          _RenewRow.success(
            sub: s,
            data: ad,
            originalPrice: originalPrice,
            discount: discount,
            effectivePrice:
                effective > 0 ? effective : (originalPrice - discount),
            currentBalance: readD('current_balance'),
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(rows);
      });
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _setAll(_PayMethod m) {
    setState(() {
      for (final r in _rows) {
        if (r.renewable) r.method = m;
      }
    });
  }

  void _setRowMethod(_RenewRow r, _PayMethod m) {
    setState(() => r.method = m);
  }

  void _onPartialChanged(_RenewRow r) {
    if (r._suppressFormat) return;
    final digits = r.partialCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final parsed = int.tryParse(digits) ?? 0;
    final formatted = _formatThousands(parsed);
    if (formatted != r.partialCtrl.text) {
      r._suppressFormat = true;
      r.partialCtrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      r._suppressFormat = false;
    }
    if (parsed != r.partialAmount) {
      setState(() => r.partialAmount = parsed);
    }
  }

  void _addToPartial(_RenewRow r, int chip) {
    final next = r.partialAmount + chip;
    final formatted = _formatThousands(next);
    r._suppressFormat = true;
    r.partialCtrl.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    r._suppressFormat = false;
    setState(() => r.partialAmount = next);
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

  ({int debt, int cash, int partial, double cashTotal, int failed})
      get _summary {
    var d = 0, c = 0, p = 0, f = 0;
    var ct = 0.0;
    for (final r in _rows) {
      if (!r.renewable) {
        f++;
        continue;
      }
      switch (r.method) {
        case _PayMethod.debt:
          d++;
          break;
        case _PayMethod.cash:
          c++;
          ct += r.cashIn;
          break;
        case _PayMethod.partial:
          p++;
          ct += r.cashIn;
          break;
      }
    }
    return (debt: d, cash: c, partial: p, cashTotal: ct, failed: f);
  }

  bool get _canSubmit {
    if (_loading || _submitting) return false;
    final ready = _rows.where((r) => r.ready).length;
    return ready > 0;
  }

  Future<void> _confirmAndSubmit() async {
    final ready = _rows.where((r) => r.ready).toList();
    if (ready.isEmpty) return;
    final s = _summary;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'sheets.confirm_bulk_renew'.tr(namedArgs: {'n': '${ready.length}'}),
          style: AppType.label(color: AppColors.textHi)
              .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'sheets.bulk_renew_summary'.tr(namedArgs: {
            'debt': '${s.debt}',
            'cash': '${s.cash}',
            'partial': '${s.partial}',
            'total': formatIQD(s.cashTotal.round()),
            'currency': 'common.currency'.tr(),
          }),
          style: AppType.subtitle(color: AppColors.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('sheets.renew_now'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _submit();
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
      if (r.sub.idx == null || r.data == null) {
        r.ok = false;
        r.err = 'sheets.missing_data'.tr();
        if (mounted) setState(() => _doneCount++);
        continue;
      }
      final res = await SubscribersApi.activate(
        idx: r.sub.idx!,
        paymentType: r.method.apiValue,
        activationData: r.data!,
        partialAmount: r.method == _PayMethod.partial ? r.partialAmount : null,
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
            ? 'sheets.renewed_n'.tr(namedArgs: {'n': '$okCount'})
            : 'sheets.done_failed'
                .tr(namedArgs: {'ok': '$okCount', 'fail': '$failCount'}),
        isError: (failCount == 0) ? false : true);
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
        icon: LucideIcons.calendarPlus,
        title: 'sheets.bulk_renew_title'.tr(),
        subtitle: _loading
            ? 'sheets.loading_activation_data'.tr()
            : '${widget.subs.length} ${'dashboard.subscriber_singular'.tr()}'
                '${s.failed > 0 ? ' (${'sheets.load_failed_n'.tr(namedArgs: {
                        'n': '${s.failed}'
                      })})' : ''}',
        onClose: _submitting ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _submitting
            ? 'sheets.renewing_progress'.tr(namedArgs: {
                'done': '$_doneCount',
                'total': '${s.debt + s.cash + s.partial}',
              })
            : 'sheets.renew_n_subs'.tr(namedArgs: {
                  'n': '${s.debt + s.cash + s.partial}',
                }) +
                (s.cashTotal > 0
                    ? ' (${formatIQD(s.cashTotal.round())} ${'common.currency'.tr()} ${'sheets.cash_word'.tr()})'
                    : ''),
        icon: LucideIcons.calendarPlus,
        enabled: _canSubmit,
        busy: _submitting,
        onPressed: _confirmAndSubmit,
      ),
      maxHeightFactor: 0.97,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          if (!_loading) ...[
            _SummaryStrip(summary: s),
            _SetAllRow(
              onSetAll: _setAll,
              enabled: !_submitting,
            ),
          ],
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: AppColors.brand),
                  )
                : ListView.separated(
                    padding:
                        const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.md),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: Sp.sm),
                    itemBuilder: (_, i) {
                      final r = _rows[i];
                      return _RenewRowCard(
                        row: r,
                        enabled: !_submitting,
                        onMethod: (m) => _setRowMethod(r, m),
                        onPartialChanged: () => _onPartialChanged(r),
                        onPartialChip: (v) => _addToPartial(r, v),
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
  const _SummaryStrip({required this.summary});
  final ({
    int debt,
    int cash,
    int partial,
    double cashTotal,
    int failed
  }) summary;

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
          _SummaryChip(
              label: 'sheets.pay_debt'.tr(),
              count: summary.debt,
              color: AppColors.error),
          const SizedBox(width: 6),
          _SummaryChip(
              label: 'sheets.pay_cash'.tr(),
              count: summary.cash,
              color: AppColors.brand),
          const SizedBox(width: 6),
          _SummaryChip(
              label: 'sheets.pay_partial'.tr(),
              count: summary.partial,
              color: AppColors.brandAccent),
          const Spacer(),
          if (summary.cashTotal > 0)
            Text(
              '${formatIQD(summary.cashTotal.round())} ${'common.currency'.tr()}',
              style: AppType.label(color: AppColors.textHi).copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.count,
    required this.color,
  });
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label $count',
        style: AppType.muted(color: color).copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One-row "تعيين الكل" — three ghost buttons that set the same
/// method on every renewable row. Mirrors v1's quick-set row.
class _SetAllRow extends StatelessWidget {
  const _SetAllRow({required this.onSetAll, required this.enabled});
  final ValueChanged<_PayMethod> onSetAll;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.xs, Sp.lg, Sp.xs),
      child: Row(
        children: [
          Text(
            'sheets.set_all'.tr(),
            style: AppType.muted(color: AppColors.textMid).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: Sp.sm),
          for (final m in _PayMethod.values) ...[
            Expanded(
              child: _SetAllBtn(
                method: m,
                enabled: enabled,
                onTap: () => onSetAll(m),
              ),
            ),
            if (m != _PayMethod.values.last) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _SetAllBtn extends StatelessWidget {
  const _SetAllBtn({
    required this.method,
    required this.enabled,
    required this.onTap,
  });
  final _PayMethod method;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final color = method.color;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(method.icon, color: color, size: 12),
              const SizedBox(width: 3),
              Text(
                method.label,
                style: AppType.muted(color: color).copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenewRowCard extends StatelessWidget {
  const _RenewRowCard({
    required this.row,
    required this.enabled,
    required this.onMethod,
    required this.onPartialChanged,
    required this.onPartialChip,
  });
  final _RenewRow row;
  final bool enabled;
  final ValueChanged<_PayMethod> onMethod;
  final VoidCallback onPartialChanged;
  final ValueChanged<int> onPartialChip;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (row.loadFailed) {
      return _FailedRowCard(sub: row.sub);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
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
          // Header — name + price chip + status icon
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            row.sub.profileName ?? row.sub.username,
                            style: AppType.muted(color: AppColors.textLow)
                                .copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _PriceChip(row: row),
              if (row.ok != null) ...[
                const SizedBox(width: 6),
                Icon(
                  row.ok! ? LucideIcons.circleCheck : LucideIcons.circleX,
                  color: row.ok! ? AppColors.brand : AppColors.error,
                  size: 18,
                ),
              ],
            ],
          ),
          // Current balance line
          if (row.currentBalance != 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  row.currentBalance < 0
                      ? LucideIcons.creditCard
                      : LucideIcons.wallet,
                  size: 11,
                  color: row.currentBalance < 0
                      ? AppColors.error
                      : AppColors.brand,
                ),
                const SizedBox(width: 4),
                Text(
                  row.currentBalance < 0
                      ? '${'sheets.current_debt'.tr()} '
                      : '${'sheets.current_credit'.tr()} ',
                  style: AppType.muted(color: AppColors.textMid).copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${formatIQD(row.currentBalance.abs().round())} د.ع',
                  style: AppType.muted(
                    color: row.currentBalance < 0
                        ? AppColors.error
                        : AppColors.brand,
                  ).copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          // 3-way picker
          Row(
            children: [
              for (final m in _PayMethod.values) ...[
                Expanded(
                  child: _MethodTile(
                    method: m,
                    selected: row.method == m,
                    enabled: enabled,
                    onTap: () => onMethod(m),
                  ),
                ),
                if (m != _PayMethod.values.last) const SizedBox(width: 5),
              ],
            ],
          ),
          if (row.method == _PayMethod.partial) ...[
            const SizedBox(height: 8),
            _PartialField(
              row: row,
              enabled: enabled,
              onChanged: onPartialChanged,
              onChip: onPartialChip,
            ),
          ],
          // Live after-balance preview when there's something to show
          if (row.method != _PayMethod.cash || row.currentBalance != 0) ...[
            const SizedBox(height: 6),
            _AfterRow(balanceAfter: row.balanceAfter),
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
                      fontSize: 10,
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

  static Color _statusBorderColor(_RenewRow r) {
    if (r.ok == true) return AppColors.brand.withValues(alpha: 0.5);
    if (r.ok == false) return AppColors.dangerSoftBorder;
    if (r.ready) return AppColors.brandSoftBorder;
    return AppColors.border;
  }
}

class _FailedRowCard extends StatelessWidget {
  const _FailedRowCard({required this.sub});
  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.dangerSoftBorder),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.triangleAlert, color: AppColors.error, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sub.fullName,
                  style: AppType.label(color: AppColors.textHi).copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'sheets.bulk_row_fetch_failed'.tr(),
                  style: AppType.muted(color: AppColors.error).copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceChip extends StatelessWidget {
  const _PriceChip({required this.row});
  final _RenewRow row;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final hasDiscount = row.discount > 0 && row.discount < row.originalPrice;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasDiscount) ...[
            Text(
              '${formatIQD(row.originalPrice.round())}',
              style: AppType.muted(color: AppColors.textLow).copyWith(
                fontSize: 9,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const SizedBox(width: 3),
          ],
          Text(
            '${formatIQD(row.effectivePrice.round())} د.ع',
            style: AppType.muted(color: AppColors.warning).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final _PayMethod method;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final color = method.color;
    return Material(
      color: selected ? color.withValues(alpha: 0.08) : AppColors.surface,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap();
              }
            : null,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.5) : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(method.icon, color: color, size: 13),
              const SizedBox(width: 4),
              Text(
                method.label,
                style: AppType.label(color: color).copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartialField extends StatelessWidget {
  const _PartialField({
    required this.row,
    required this.enabled,
    required this.onChanged,
    required this.onChip,
  });
  final _RenewRow row;
  final bool enabled;
  final VoidCallback onChanged;
  final ValueChanged<int> onChip;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.brandAccent;
    final price = row.effectivePrice.round();
    final chips = const [5000, 10000, 15000, 25000, 35000, 50000]
        .where((c) => c < price)
        .toList();
    // Hint when the partial amount exceeds the package price — the
    // excess will be credited to the subscriber's balance (matches
    // v1's behaviour). Informational only; doesn't block submission.
    final overshoot = row.partialAmount > price;
    // Wire onChanged once via a listener — but since the parent already
    // calls onChanged via _onPartialChanged on every controller event,
    // we don't add another listener here; we just render the field.
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'sheets.paid_cash_amount'.tr(),
            style: AppType.label(color: AppColors.textHi).copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          _PartialTextField(
            controller: row.partialCtrl,
            enabled: enabled,
            onChanged: onChanged,
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 5),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final amount in chips)
                  InkWell(
                    onTap: enabled
                        ? () {
                            HapticFeedback.selectionClick();
                            onChip(amount);
                          }
                        : null,
                    borderRadius: BorderRadius.circular(R.pill),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
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
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (overshoot) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(LucideIcons.info, size: 11, color: AppColors.success),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'sheets.overpay_becomes_credit'.tr(namedArgs: {
                      'amt':
                          '${formatIQD((row.partialAmount - price).round())} ${'common.currency'.tr()}'
                    }),
                    style: AppType.muted(color: AppColors.success).copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Tiny dedicated text-field widget so the controller listener fires
/// every keystroke without re-creating the InputDecoration on each
/// parent rebuild.
class _PartialTextField extends StatefulWidget {
  const _PartialTextField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  State<_PartialTextField> createState() => _PartialTextFieldState();
}

class _PartialTextFieldState extends State<_PartialTextField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_relay);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_relay);
    super.dispose();
  }

  void _relay() => widget.onChanged();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return AmountShorthandBox(
        controller: widget.controller,
        enabled: widget.enabled,
        child: TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          style: AppType.input(color: AppColors.textHi),
          decoration: InputDecoration(
            hintText: 'sheets.amount_example_10k'.tr(),
            hintStyle: AppType.input(color: AppColors.textLow),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.sm),
              borderSide: BorderSide(color: AppColors.border),
            ),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            suffixText: 'common.currency'.tr(),
          ),
        ));
  }
}

class _AfterRow extends StatelessWidget {
  const _AfterRow({required this.balanceAfter});
  final double balanceAfter;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final isDebt = balanceAfter < 0;
    final color = isDebt ? AppColors.error : AppColors.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.arrowRight, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            'sheets.after_renewal'.tr(),
            style: AppType.label(color: AppColors.textHi).copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            isDebt
                ? '${'subscribers.debt_short'.tr()} '
                : '${'subscribers.balance_short'.tr()} ',
            style: AppType.muted(color: color).copyWith(
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '${formatIQD(balanceAfter.abs().round())} د.ع',
            style: AppType.label(color: color).copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────── shared sheet chrome (copy of activate_sheet's) ─────────
