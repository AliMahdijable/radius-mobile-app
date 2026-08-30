import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/manager_debts_api.dart';
import '../../../api/managers_api.dart';
import '../../../core/util/format.dart';
import '../../../services/manager_notice.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../services/subscriber_events.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/util/amount_input.dart';

/// Unified pay-debt sheet — mirrors v1
/// _PayDebtUnifiedSheet (mobile-app/lib/screens/managers_screen.dart:
/// 3249–3550). Lets the admin pay against either SAS4 debt or custom
/// "ديون أخرى" with a segmented toggle when both sources have a
/// balance, then dispatches the WA + Push notification post-success.
///
/// Custom payments use FIFO — the entered amount is split across the
/// debtor's open debts oldest-first, calling addPayment for each in
/// sequence. Mirrors v1 `_payCustomFifo`.
Future<bool?> showPayDebtSheet(
  BuildContext context,
  Manager manager, {
  /// Sum of all open custom debts on this manager. Provided by the
  /// caller (managers_screen) when it already knows the figure from
  /// the summary so the sheet doesn't have to fetch it again.
  num initialCustomRemaining = 0,
}) {
  return showModalBottomSheet<bool>(
    barrierColor: AppColors.scrim,
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PayDebtSheet(
      manager: manager,
      initialCustomRemaining: initialCustomRemaining,
    ),
  );
}

enum _PaySource { sas, custom }

class _PayDebtSheet extends StatefulWidget {
  const _PayDebtSheet({
    required this.manager,
    required this.initialCustomRemaining,
  });
  final Manager manager;
  final num initialCustomRemaining;

  @override
  State<_PayDebtSheet> createState() => _PayDebtSheetState();
}

class _PayDebtSheetState extends State<_PayDebtSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  int _amount = 0;
  bool _suppressFormat = false;
  bool _submitting = false;

  // Authoritative SAS4 figures, refreshed via /managers/:id/debt on
  // open so we don't show stale list-cached values.
  double _sasDebt = 0;
  double _sasDebtForMe = 0;
  double _sasCredit = 0;
  double _customRemaining = 0;
  bool _loading = true;

  _PaySource _source = _PaySource.sas;

  // Notification toggles — match the deposit/withdraw sheets so the
  // admin can opt out of either channel before submitting.
  bool _sendWhatsApp = true;
  bool _sendPush = true;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmount);
    _loadFresh();
  }

  Future<void> _loadFresh() async {
    // Run both fetches in parallel — the debt info comes from SAS4
    // directly, the custom-debts summary comes from our DB.
    final results = await Future.wait([
      ManagersApi.debtInfo(widget.manager.id),
      ManagerDebtsApi.summary(),
    ]);
    if (!mounted) return;
    final info = results[0] as ManagerDebtInfo?;
    final summary = results[1] as ManagerDebtsSummary?;
    setState(() {
      _sasDebt = info?.totalDebt ?? widget.manager.totalDebt;
      _sasDebtForMe = info?.debtForMe ?? widget.manager.debtForMe;
      _sasCredit = info?.balance ?? widget.manager.balance;
      _customRemaining = summary?.remainingForDebtor(widget.manager.id) ??
          widget.initialCustomRemaining.toDouble();
      // Pick a sensible default source: if SAS has debt use SAS,
      // otherwise drop to custom. If neither has debt the submit
      // button is disabled anyway.
      if (_sasDebt > 0) {
        _source = _PaySource.sas;
      } else if (_customRemaining > 0) {
        _source = _PaySource.custom;
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _onAmount() {
    if (_suppressFormat) return;
    final digits = _amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final parsed = int.tryParse(digits) ?? 0;
    final formatted = _fmt(parsed);
    if (formatted != _amountCtrl.text) {
      _suppressFormat = true;
      _amountCtrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      _suppressFormat = false;
    }
    if (parsed != _amount) setState(() => _amount = parsed);
  }

  void _setAmount(int v) {
    final formatted = _fmt(v);
    _suppressFormat = true;
    _amountCtrl.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _suppressFormat = false;
    setState(() => _amount = v);
  }

  void _addToAmount(int chip) => _setAmount(_amount + chip);

  void _fillFull() {
    final max = _maxForSource.toInt();
    _setAmount(max);
  }

  static String _fmt(int v) {
    if (v == 0) return '';
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  double get _maxForSource =>
      _source == _PaySource.sas ? _sasDebt : _customRemaining;

  bool get _canSubmit =>
      !_submitting && _amount > 0 && _amount <= _maxForSource;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    bool ok;
    String? message;
    if (_source == _PaySource.sas) {
      final r = await ManagersApi.sasPayDebt(
        id: widget.manager.id,
        amount: _amount,
        debtForMe: _sasDebtForMe,
        totalDebt: _sasDebt,
        note: note,
      );
      ok = r.ok;
      message = r.message;
    } else {
      final r = await _payCustomFifo(_amount, note);
      ok = r.ok;
      message = r.message;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() => _submitting = false);
      showSheetSnack(context, message ?? 'تعذّر تسديد الدين', isError: true);
      return;
    }

    // Fire notifications without blocking the UI — the sheet pops
    // immediately so the admin moves on, the WA/push spinner runs
    // out in the background via unawaited().
    final paidAmount = _amount.toDouble();
    final newSasDebt =
        _source == _PaySource.sas ? (_sasDebt - paidAmount) : _sasDebt;
    final newCustomDebt = _source == _PaySource.custom
        ? (_customRemaining - paidAmount).clamp(0.0, double.infinity)
        : _customRemaining;
    unawaited(ManagerNoticeService.notify(
      manager: widget.manager,
      amount: paidAmount,
      isLoan: false,
      previousCredit: _sasCredit,
      previousDebt: _sasDebt + _customRemaining,
      currentCredit: _sasCredit,
      currentDebt: newSasDebt + newCustomDebt,
      // التقسيم لـ{sas_debts} + {other_debts} في قالب v1 manager_agent.
      sasDebts: newSasDebt,
      otherDebts: newCustomDebt,
      actionKind: 'debt_payment',
      sendWhatsApp: _sendWhatsApp,
      sendPush: _sendPush,
      notes: note,
    ));

    SubscriberEvents.notifyChange();
    Navigator.of(context).pop(true);
  }

  /// FIFO custom debt payment — mirrors v1 managers_screen.dart:3364.
  /// Pulls the open debts oldest-first and consumes the amount across
  /// them. Stops at the first failure but reports back the partial
  /// success so the admin knows the state.
  Future<({bool ok, String? message})> _payCustomFifo(
    int totalAmount,
    String? note,
  ) async {
    final debts = await ManagerDebtsApi.list(debtorAdminId: widget.manager.id);
    final open = debts.where((d) => !d.isClosed).toList()
      ..sort((a, b) => a.debtDate.compareTo(b.debtDate));
    if (open.isEmpty) {
      return (ok: false, message: 'لا توجد ديون مفتوحة');
    }
    var remaining = totalAmount;
    for (final d in open) {
      if (remaining <= 0) break;
      final apply =
          remaining > d.remainingAmount ? d.remainingAmount.toInt() : remaining;
      if (apply <= 0) continue;
      final r = await ManagerDebtsApi.addPayment(
        debtId: d.id,
        amountPaid: apply,
        note: note,
      );
      if (!r.ok) {
        return (
          ok: false,
          message: r.errorMessage ?? 'فشل التسديد على دين #${d.id}'
        );
      }
      remaining -= apply;
    }
    return (ok: true, message: null);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.brandAccent; // sky blue — pay-debt
    final hasSas = _sasDebt > 0;
    final hasCustom = _customRemaining > 0;
    final showSegmented = hasSas && hasCustom;
    // iOS keyboard-avoidance: push the sheet up so amount + note +
    // submit button stay visible when the keyboard opens.
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.banknote,
        title: 'تسديد دين',
        subtitle: widget.manager.username,
        subtitleLtr: true,
        tint: AppColors.brandAccent,
        onClose: () => Navigator.of(context).pop(false),
      ),
      footer: SheetFooterBar(
        label: _submitting ? 'جارٍ التسديد...' : 'تسديد',
        icon: LucideIcons.banknote,
        color: AppColors.brandAccent,
        enabled: _canSubmit,
        busy: _submitting,
        onPressed: _submit,
      ),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                  color: AppColors.brandAccent, strokeWidth: 2.5))
          : ListView(
              padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xxl),
              children: [
                // Source badges — clickable when both sources
                // have debt, otherwise visual-only.
                Row(
                  children: [
                    Expanded(
                      child: _SourceBadge(
                        label: 'دين الساس',
                        amount: _sasDebt,
                        selected: _source == _PaySource.sas,
                        enabled: hasSas,
                        onTap: showSegmented && hasSas
                            ? () => setState(() {
                                  _source = _PaySource.sas;
                                  _amountCtrl.clear();
                                  _amount = 0;
                                })
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SourceBadge(
                        label: 'ديون أخرى',
                        amount: _customRemaining,
                        selected: _source == _PaySource.custom,
                        enabled: hasCustom,
                        onTap: showSegmented && hasCustom
                            ? () => setState(() {
                                  _source = _PaySource.custom;
                                  _amountCtrl.clear();
                                  _amount = 0;
                                })
                            : null,
                      ),
                    ),
                  ],
                ),
                if (!hasSas && !hasCustom) ...[
                  const SizedBox(height: Sp.xl),
                  Center(
                    child: Text(
                      'لا يوجد دين على هذا المدير',
                      style: AppType.label(color: AppColors.textMid),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: Sp.md),
                  // Amount input
                  AmountShorthandBox(
                      controller: _amountCtrl,
                      child: TextField(
                        controller: _amountCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: 'المبلغ',
                          suffixText: 'د.ع',
                          helperText:
                              'الحدّ الأقصى ${formatIQD(_maxForSource)}',
                        ),
                      )),
                  const SizedBox(height: Sp.sm),
                  // Quick chips + pay-full
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final v in const [
                        10000,
                        25000,
                        50000,
                        100000,
                        250000,
                        500000,
                      ])
                        _Chip(
                          label: '+${formatIQD(v)}',
                          onTap: () => _addToAmount(v),
                        ),
                      _Chip(
                        label: 'تسديد كامل',
                        emphasized: true,
                        onTap: _fillFull,
                      ),
                    ],
                  ),
                  const SizedBox(height: Sp.md),
                  TextField(
                    controller: _noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظة (اختياري)',
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                  const SizedBox(height: Sp.md),
                  _PayPreview(
                    amount: _amount.toDouble(),
                    previousDebt:
                        _source == _PaySource.sas ? _sasDebt : _customRemaining,
                  ),
                  const SizedBox(height: Sp.md),
                  _NotifyToggles(
                    sendWhatsApp: _sendWhatsApp,
                    sendPush: _sendPush,
                    waEnabled: widget.manager.mobile.trim().isNotEmpty,
                    onWa: (v) => setState(() => _sendWhatsApp = v),
                    onPush: (v) => setState(() => _sendPush = v),
                  ),
                ],
              ],
            ),
    );
  }
}

// ============================================================
// Sub-widgets
// ============================================================

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(R.pill),
          ),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onClose,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppType.title(color: AppColors.textHi)
                        .copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
                Text(subtitle,
                    style: AppType.muted(color: AppColors.textMid)
                        .copyWith(fontSize: 12.5)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 18),
            color: AppColors.textMid,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({
    required this.label,
    required this.amount,
    required this.selected,
    required this.enabled,
    this.onTap,
  });
  final String label;
  final num amount;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.brandAccent;
    final color = !enabled
        ? AppColors.textLow
        : selected
            ? accent
            : AppColors.textMid;
    return Material(
      color: selected ? accent.withValues(alpha: 0.10) : AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: 1.4,
            ),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppType.muted(color: color).copyWith(fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatIQD(amount)} د.ع',
                style: TextStyle(
                  color: color,
                  fontSize: 14,
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

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.brandAccent;
    return Material(
      color:
          emphasized ? accent.withValues(alpha: 0.10) : AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: emphasized ? accent : AppColors.textHi,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _PayPreview extends StatelessWidget {
  const _PayPreview({required this.amount, required this.previousDebt});
  final double amount;
  final double previousDebt;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final after = (previousDebt - amount).clamp(0.0, double.infinity);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.md),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'الدين بعد التسديد',
              style: AppType.label(color: AppColors.textMid)
                  .copyWith(fontSize: 12.5),
            ),
          ),
          Text(
            '${formatIQD(after)} د.ع',
            style: TextStyle(
              color: after == 0 ? AppColors.success : AppColors.textHi,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifyToggles extends StatelessWidget {
  const _NotifyToggles({
    required this.sendWhatsApp,
    required this.sendPush,
    required this.waEnabled,
    required this.onWa,
    required this.onPush,
  });
  final bool sendWhatsApp;
  final bool sendPush;
  final bool waEnabled;
  final ValueChanged<bool> onWa;
  final ValueChanged<bool> onPush;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.md),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 4),
      child: Column(
        children: [
          SwitchListTile(
            value: waEnabled && sendWhatsApp,
            onChanged: waEnabled ? onWa : null,
            dense: true,
            title: Text(
              'إشعار واتساب',
              style: AppType.label(color: AppColors.textHi)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: !waEnabled
                ? Text(
                    'لا يوجد رقم هاتف محفوظ',
                    style: AppType.muted(color: AppColors.textLow)
                        .copyWith(fontSize: 11),
                  )
                : null,
            secondary: const Icon(LucideIcons.messageCircle, size: 18),
            contentPadding: EdgeInsets.zero,
          ),
          Divider(height: 1, color: AppColors.border),
          SwitchListTile(
            value: sendPush,
            onChanged: onPush,
            dense: true,
            title: Text(
              'إشعار داخل التطبيق',
              style: AppType.label(color: AppColors.textHi)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            secondary: const Icon(LucideIcons.bell, size: 18),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.label,
    required this.color,
    required this.icon,
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });
  final String label;
  final Color color;
  final IconData icon;
  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.sm),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            onPressed: enabled ? onPressed : null,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: AppColors.onBrand,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(R.md),
              ),
            ),
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: AppColors.onBrand,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(icon, size: 16),
            label: Text(label,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
      ),
    );
  }
}
