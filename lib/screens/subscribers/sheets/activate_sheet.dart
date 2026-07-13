import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscribers_api.dart';
import '../../../core/util/format.dart';
import '../../../models/subscriber.dart';
import '../../../services/receipt_service.dart';
import '../../../services/subscriber_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '_print_receipt_dialog.dart';

/// Bottom sheet for activating a subscriber's package — direct port of
/// v1's `_activateSubscriber` flow from
/// mobile-app/lib/screens/subscribers/subscriber_details_screen.dart:
///   1. Fetch /api/v2/subscribers/:idx/activation-data on open. Sheet
///      shows a spinner while the round-trip is in flight.
///   2. Display package / duration / original price / discount /
///      effective price + the subscriber's current balance + the
///      manager's wallet.
///   3. Three payment buttons: نقدي (full cash) / دين (non-cash) /
///      جزئي (partial cash). Partial mode unlocks an amount field
///      pre-populated with quick chips (5k / 10k / 15k / 25k / 35k /
///      50k, filtered to < effective price).
///   4. Live 'بعد التفعيل' preview row showing how the subscriber's
///      balance shifts.
///   5. Submit → /api/v2/subscribers/:idx/activate with the cached
///      activation-data echoed back (the backend rejects the call
///      otherwise — see server.js comment about SAS4 session locks).
///
/// Returns true on success so callers (subscribers list, detail screen)
/// can refresh their cached rows.
Future<bool?> showActivateSheet(BuildContext context, Subscriber sub) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ActivateSheet(sub: sub),
  );
}

class _ActivateSheet extends StatefulWidget {
  const _ActivateSheet({required this.sub});
  final Subscriber sub;

  @override
  State<_ActivateSheet> createState() => _ActivateSheetState();
}

enum _PayType { cash, partial, debt }

class _ActivateSheetState extends State<_ActivateSheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;

  // Default = آجل (dept/deferred). المستخدم صرّح 2026-07-11: أغلب
  // التفعيلات تكون آجلة، فنجعله الافتراضي بدل نقدي.
  _PayType _pay = _PayType.debt;
  final _partialCtrl = TextEditingController();
  int _partialAmount = 0;
  // True while the controller text is being rewritten by us (e.g. when
  // a chip is tapped). Lets the listener skip re-formatting recursion.
  bool _suppressFormat = false;

  @override
  void initState() {
    super.initState();
    _load();
    _partialCtrl.addListener(_onPartialChanged);
  }

  void _onPartialChanged() {
    if (_suppressFormat) return;
    final raw = _partialCtrl.text;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final parsed = int.tryParse(digits) ?? 0;
    final formatted = _formatThousands(parsed);
    if (formatted != raw) {
      _suppressFormat = true;
      _partialCtrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      _suppressFormat = false;
    }
    if (parsed != _partialAmount) {
      setState(() => _partialAmount = parsed);
    }
  }

  void _addToPartial(int chipAmount) {
    final next = _partialAmount + chipAmount;
    final formatted = _formatThousands(next);
    _suppressFormat = true;
    _partialCtrl.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _suppressFormat = false;
    setState(() => _partialAmount = next);
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

  @override
  void dispose() {
    _partialCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final idx = widget.sub.idx;
    if (idx == null) {
      setState(() {
        _loading = false;
        _loadError = 'sheets.activate_no_idx'.tr();
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final data = await SubscribersApi.fetchActivationData(idx);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = data;
      if (data == null) _loadError = 'sheets.activate_load_failed'.tr();
    });
  }

  num _readNum(String key) {
    final v = _data?[key];
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString().replaceAll(',', '')) ?? 0;
  }

  num get _userPrice => _readNum('user_price');
  num get _discount => _readNum('discount_amount');
  num get _effectivePrice => _readNum('price_after_discount');
  num get _currentBalance => _readNum('current_balance');
  num get _managerBalance => _readNum('manager_balance');
  num get _rewardPoints => _readNum('reward_points');
  String get _profileName =>
      (_data?['profile_name'] ?? widget.sub.profileName ?? '').toString();
  String? get _duration => _data?['profile_duration']?.toString();

  /// Mirrors v1's newNotes calculation:
  ///   cash    → balance unchanged
  ///   debt    → balance - price
  ///   partial → balance - price + partialAmount
  num get _balanceAfter {
    final price = _effectivePrice > 0 ? _effectivePrice : _userPrice;
    switch (_pay) {
      case _PayType.cash:
        return _currentBalance;
      case _PayType.debt:
        return _currentBalance - price;
      case _PayType.partial:
        return _currentBalance - price + _partialAmount;
    }
  }

  bool get _canSubmit {
    if (_loading || _submitting || _data == null) return false;
    if (_pay == _PayType.partial) {
      // Partial only requires a positive amount. v1 lets the admin
      // pay MORE than the package price and the excess lands as a
      // credit on the subscriber's notes — مطلب المستخدم 2026-06-07.
      // Don't gate on amount >= price.
      if (_partialAmount <= 0) return false;
    }
    return true;
  }

  Future<void> _submit() async {
    final idx = widget.sub.idx;
    if (idx == null || _data == null) return;
    final paymentType = switch (_pay) {
      _PayType.cash => 'cash',
      _PayType.partial => 'partial-cash',
      _PayType.debt => 'non-cash',
    };
    setState(() => _submitting = true);
    final result = await SubscribersApi.activate(
      idx: idx,
      paymentType: paymentType,
      activationData: _data!,
      partialAmount:
          _pay == _PayType.partial ? _partialAmount : null,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'common.error'.tr()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    SubscriberEvents.notifyChange();
    // 2026-07-13: dialog صريح — يعطي المدير خيار طباعة الوصل قبل الإغلاق.
    // بدل SnackBarAction الذي كان يُفوَّت أو يُستبدَل بـsnackbar آخر.
    final effPrice = _effectivePrice > 0 ? _effectivePrice : _userPrice;
    final num paidNow = switch (_pay) {
      _PayType.cash => effPrice,
      _PayType.partial => _partialAmount,
      _PayType.debt => 0,
    };
    final durationDays = int.tryParse(_duration ?? '');
    final shouldPrint = await showPrintReceiptDialog(
      context,
      title: 'sheets.renew_ok'.tr(),
      message: 'sheets.print_receipt_prompt'.tr(),
    );
    if (shouldPrint) {
      await ReceiptService.printActivationReceipt(
        sub: widget.sub,
        packagePrice: effPrice,
        paidAmount: paidNow,
        durationDays: durationDays,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(R.xl)),
          ),
          child: Column(
            children: [
              _SheetHandle(),
              _SheetHeader(
                icon: LucideIcons.zap,
                title: 'dashboard.renew_sub'.tr(),
                subtitle: widget.sub.fullName,
                color: AppColors.brand,
                onClose: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(
                      Sp.lg, Sp.sm, Sp.lg, Sp.huge),
                  children: _buildBody(),
                ),
              ),
              _SubmitBar(
                label: _submitting ? 'sheets.renewing'.tr() : 'sheets.renew_now'.tr(),
                color: AppColors.brand,
                icon: LucideIcons.zap,
                enabled: _canSubmit,
                busy: _submitting,
                onPressed: _submit,
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildBody() {
    if (_loading) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: Sp.huge),
          child: Center(
            child: CircularProgressIndicator(color: AppColors.brand),
          ),
        ),
      ];
    }
    if (_loadError != null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.huge),
          child: Column(
            children: [
              const Icon(LucideIcons.triangleAlert,
                  color: AppColors.error, size: 32),
              const SizedBox(height: Sp.sm),
              Text(_loadError!,
                  style: AppType.label(color: AppColors.error)),
              const SizedBox(height: Sp.sm),
              TextButton(
                onPressed: _load,
                child: Text('common.retry'.tr()),
              ),
            ],
          ),
        ),
      ];
    }
    final price = _effectivePrice > 0 ? _effectivePrice : _userPrice;
    return [
      _InfoCard(
        title: 'sheets.package_details'.tr(),
        rows: [
          (LucideIcons.package, 'subscribers.label_package'.tr(), _profileName.isEmpty ? '—' : _profileName, null),
          if (_duration != null && _duration!.isNotEmpty)
            (LucideIcons.clock, 'sheets.duration'.tr(), _duration!, null),
          (
            LucideIcons.tag,
            'sheets.original_price'.tr(),
            '${formatIQD(_userPrice.round())} ${'common.currency'.tr()}',
            _discount > 0 ? AppColors.textLow : null,
          ),
          if (_discount > 0)
            (
              LucideIcons.percent,
              'subscribers.label_discount'.tr(),
              '-${formatIQD(_discount.round())} ${'common.currency'.tr()}',
              const Color(0xFF14B8A6),
            ),
          if (_discount > 0)
            (
              LucideIcons.tag,
              'sheets.final_price'.tr(),
              '${formatIQD(_effectivePrice.round())} ${'common.currency'.tr()}',
              AppColors.brand,
            ),
        ],
      ),
      const SizedBox(height: Sp.sm),
      _InfoCard(
        title: 'sheets.current_state'.tr(),
        rows: [
          (
            _currentBalance < 0
                ? LucideIcons.creditCard
                : LucideIcons.wallet,
            _currentBalance < 0 ? 'sheets.current_debt'.tr() : 'sheets.current_credit'.tr(),
            '${formatIQD(_currentBalance.abs().round())} ${'common.currency'.tr()}',
            _currentBalance < 0 ? AppColors.error : AppColors.brand,
          ),
          (
            LucideIcons.wallet,
            'dashboard.manager_balance'.tr(),
            '${formatIQD(_managerBalance.round())} ${'common.currency'.tr()}',
            AppColors.textHi,
          ),
          if (_rewardPoints > 0)
            (
              LucideIcons.star,
              'sheets.points'.tr(),
              '${formatIQD(_rewardPoints.round())}',
              const Color(0xFFCD8B00),
            ),
        ],
      ),
      const SizedBox(height: Sp.md),
      _SectionTitle('sheets.payment_method'.tr()),
      const SizedBox(height: Sp.xs),
      _PayPicker(
        current: _pay,
        onSelect: (p) => setState(() => _pay = p),
      ),
      if (_pay == _PayType.partial) ...[
        const SizedBox(height: Sp.sm),
        _PartialAmountField(
          controller: _partialCtrl,
          price: price.round(),
          onChipTap: _addToPartial,
        ),
      ],
      const SizedBox(height: Sp.md),
      _AfterCard(
        balanceAfter: _balanceAfter,
      ),
    ];
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.rows});
  final String title;
  final List<(IconData, String, String, Color?)> rows;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppType.label(color: AppColors.textMid).copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 3),
          for (final (icon, label, value, color) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(icon, color: AppColors.textMid, size: 13),
                  const SizedBox(width: 6),
                  Text(label,
                      style: AppType.muted(color: AppColors.textMid)
                          .copyWith(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      value,
                      style: AppType.label(
                              color: color ?? AppColors.textHi)
                          .copyWith(
                              fontSize: 12, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        text,
        style: AppType.label(color: AppColors.textHi)
            .copyWith(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PayPicker extends StatelessWidget {
  const _PayPicker({required this.current, required this.onSelect});
  final _PayType current;
  final ValueChanged<_PayType> onSelect;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(
      children: [
        Expanded(
          child: _PayBtn(
            label: 'sheets.pay_cash'.tr(),
            icon: LucideIcons.banknote,
            color: AppColors.brand,
            selected: current == _PayType.cash,
            onTap: () => onSelect(_PayType.cash),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _PayBtn(
            label: 'sheets.pay_debt'.tr(),
            icon: LucideIcons.creditCard,
            color: AppColors.error,
            selected: current == _PayType.debt,
            onTap: () => onSelect(_PayType.debt),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _PayBtn(
            label: 'sheets.pay_partial'.tr(),
            icon: LucideIcons.walletCards,
            color: const Color(0xFF8B5CF6),
            selected: current == _PayType.partial,
            onTap: () => onSelect(_PayType.partial),
          ),
        ),
      ],
    );
  }
}

/// Transparent card-style picker — same visual language as the
/// operations grid on the detail screen (white surface + border +
/// soft shadow + tinted icon-box on top + colored label). When
/// selected, the surface gets a soft tint of the op's color and the
/// border thickens — selection reads as a glow, not a filled chip.
class _PayBtn extends StatelessWidget {
  const _PayBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: selected ? color.withValues(alpha: 0.08) : AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.5)
                  : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: selected ? 0.15 : 0.1),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: AppType.label(color: color).copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartialAmountField extends StatelessWidget {
  const _PartialAmountField({
    required this.controller,
    required this.price,
    required this.onChipTap,
  });
  final TextEditingController controller;
  final int price;
  /// Called with the chip value; the parent ADDS it to the current
  /// amount (v1 behaviour — tap 25k twice → 50k).
  final ValueChanged<int> onChipTap;

  // Dense up to 50k so the admin can dial in any common partial-cash
  // amount in one tap. Each chip is filtered out when ≥ effective
  // price (no point offering 25k on a 20k package). Chips ACCUMULATE
  // — tap 10k twice → 20k — so even denser sets stay short to render.
  static const _chips = [
    5000, 10000, 15000, 20000, 25000, 30000, 35000, 40000, 45000, 50000,
  ];

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final filtered = _chips.where((c) => c < price).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF8B5CF6).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'sheets.paid_cash_amount'.tr(),
            style: AppType.label(color: AppColors.textHi).copyWith(
                fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: AppType.input(color: AppColors.textHi),
            decoration: InputDecoration(
              hintText: 'sheets.amount_example'.tr(),
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
            ),
          ),
          if (filtered.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final amount in filtered)
                  InkWell(
                    onTap: () => onChipTap(amount),
                    borderRadius: BorderRadius.circular(R.pill),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(R.pill),
                        border: Border.all(
                          color: const Color(0xFF8B5CF6)
                              .withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        formatIQD(amount),
                        style: AppType.muted(
                                color: const Color(0xFF8B5CF6))
                            .copyWith(
                                fontSize: 11, fontWeight: FontWeight.w700),
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

class _AfterCard extends StatelessWidget {
  const _AfterCard({required this.balanceAfter});
  final num balanceAfter;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final isDebt = balanceAfter < 0;
    final color = isDebt ? AppColors.error : AppColors.brand;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.arrowRight, color: color, size: 13),
          const SizedBox(width: 6),
          Text(
            'sheets.after_activation'.tr(),
            style: AppType.label(color: AppColors.textHi).copyWith(
                fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Text(
            isDebt ? '${'subscribers.debt_short'.tr()} ' : '${'subscribers.balance_short'.tr()} ',
            style: AppType.muted(color: color)
                .copyWith(fontSize: 10, fontWeight: FontWeight.w700),
          ),
          Text(
            '${formatIQD(balanceAfter.abs().round())} د.ع',
            style: AppType.label(color: color).copyWith(
                fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

// ───────── shared sheet chrome ─────────

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
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
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 4, Sp.sm, Sp.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: AppType.label(color: AppColors.textHi).copyWith(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 1),
                Text(subtitle,
                    style: AppType.muted(color: AppColors.textMid).copyWith(
                        fontSize: 11, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            color: AppColors.textMid,
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
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
      child: Container(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: color,
              disabledBackgroundColor: color.withValues(alpha: 0.35),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(R.md),
              ),
            ),
            onPressed: enabled ? onPressed : null,
            icon: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(icon, size: 16),
            label: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ),
      ),
    );
  }
}
