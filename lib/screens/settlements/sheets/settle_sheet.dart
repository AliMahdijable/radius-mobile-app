import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/settlements_api.dart';
import '../../../core/util/amount_input.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../settle_widgets.dart';

/// شيت التسوية: معاينةٌ طازجة ← المبلغ المستلَم فعلاً ← تأكيد.
/// يُرجع السند المحفوظ عند النجاح، و`null` عند الإغلاق.
Future<SettlementRecord?> showSettleSheet(BuildContext context) {
  return showModalBottomSheet<SettlementRecord>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => const _SettleSheet(),
  );
}

class _SettleSheet extends StatefulWidget {
  const _SettleSheet();

  @override
  State<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends State<_SettleSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  CurrentAccount? _preview;
  bool _loading = true;
  String? _error;
  int _received = 0;
  bool _submitting = false;

  /// مفتاح منع التكرار — يتجدّد مع كلّ معاينة (انظر [_apply]).
  String _key = SettlementsApi.newIdempotencyKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// معاينة طازجة لا ما في الشاشة: ما يراه المدير هنا هو ما يُسوّى.
  Future<void> _load() async {
    final r = await SettlementsApi.current();
    if (!mounted) return;
    final d = r.data;
    if (d == null || !d.started || d.cut == null) {
      setState(() {
        _loading = false;
        _error = (d != null && !d.started)
            ? 'settle.no_start'.tr()
            : (r.message ?? 'common.load_failed'.tr());
      });
      return;
    }
    _apply(d);
  }

  int get _full => _preview == null || _preview!.expected <= 0
      ? 0
      : _preview!.expected.round();

  void _apply(CurrentAccount d) {
    setState(() {
      _preview = d;
      _loading = false;
      _error = null;
      _key = SettlementsApi.newIdempotencyKey();
    });
    _setReceived(_full);
  }

  void _setReceived(int v) {
    // المستمع في AmountTextField يقرأ النصّ ويُبلغ onValue بالقيمة.
    _amountCtrl.text = AmountShorthand.format(v);
    setState(() => _received = v);
  }

  Future<void> _submit() async {
    final p = _preview;
    final cut = p?.cut;
    if (p == null || cut == null || _submitting) return;
    setState(() => _submitting = true);
    final r = await SettlementsApi.settle(
      cut: cut,
      expected: p.expected,
      received: _received,
      note: _noteCtrl.text.trim(),
      idempotencyKey: _key,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    final saved = r.settlement;
    if (r.ok && saved != null) {
      showSheetSnack(
        context,
        r.message ?? 'settle.done'.tr(namedArgs: {'n': '${saved.number}'}),
      );
      Navigator.of(context).pop(saved);
      return;
    }
    // تغيّرت صرفيةٌ أو سُجّلت تسويةٌ أخرى منذ المعاينة: الخادم يرسل
    // الأرقام الجديدة، فتُعرض ويُعاد التأكيد عليها لا على القديمة.
    final fresh = r.current;
    if ((r.code == 'STALE' || r.code == 'HEAD_CHANGED') &&
        fresh != null &&
        fresh.cut != null) {
      _apply(fresh);
    }
    showSheetSnack(context, r.message ?? 'common.load_failed'.tr(), isError: true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final p = _preview;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.handCoins,
        title: 'settle.sheet_title'.tr(),
        subtitle: p == null
            ? 'settle.loading'.tr()
            : 'settle.sheet_from'.tr(
                namedArgs: {'when': settleWhen(p.periodStart, weekday: true)}),
        onClose: _submitting ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: p == null
            ? 'settle.confirm_plain'.tr()
            : 'settle.confirm'.tr(namedArgs: {'amt': formatIQD(_received)}),
        icon: LucideIcons.handCoins,
        enabled: p != null && !_loading,
        busy: _submitting,
        onPressed: _submit,
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: Sp.huge),
              child: Center(child: CircularProgressIndicator()),
            )
          : (p == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: Sp.xl),
                  child: Text(
                    _error ?? 'common.load_failed'.tr(),
                    style: AppType.body(color: AppColors.error),
                  ),
                )
              : _content(p)),
    );
  }

  Widget _content(CurrentAccount p) {
    final opening = p.head?.isOpening ?? true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetRowsGroup(rows: [
          if (p.openingBalance != 0)
            SheetRowData(
              label: opening
                  ? 'settle.opening_balance'.tr()
                  : 'settle.carried_balance'.tr(),
              value: settleMoney(p.openingBalance),
            ),
          SheetRowData(
            label: '${'settle.cash_activations'.tr()} · ${p.cashActivations.count}',
            value: '+${formatIQD(p.cashActivations.sum)}',
            valueColor: AppColors.success,
          ),
          SheetRowData(
            label: '${'settle.debt_payments'.tr()} · ${p.debtPayments.count}',
            value: '+${formatIQD(p.debtPayments.sum)}',
            valueColor: AppColors.success,
          ),
          SheetRowData(
            label: '${'settle.expenses'.tr()} · ${p.expenses.count}',
            value: '−${formatIQD(p.expenses.sum)}',
            valueColor: AppColors.error,
          ),
          SheetRowData(
            label: 'settle.expected'.tr(),
            value: settleMoney(p.expected),
            strong: true,
          ),
        ]),
        if (p.hasEmployees) ...[
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'settle.collectors_give'.tr(),
            child: CollectorsList(collectors: p.collectors),
          ),
        ],
        const SizedBox(height: Sp.lg),
        SheetSection(
          label: 'settle.received_label'.tr(),
          gap: 9,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetBox(
                focused: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 14),
                // ⚠️ بلا اختصار الآلاف: الحقل مملوءٌ بالمبلغ الدقيق، ومتوقَّعٌ
                // أقلّ من ألف كان سيصير ألوفاً بمجرّد لمس الحقل والخروج منه —
                // في تأكيد مال.
                child: AmountTextField(
                  controller: _amountCtrl,
                  currency: 'common.currency'.tr(),
                  shorthand: false,
                  onValue: (v) => setState(() => _received = v),
                ),
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  // بأيقونة: الشريحة بلا أيقونة تفرض LTR (مصمَّمة للأرقام).
                  SheetQuickChip(
                    label: 'settle.full_amount'.tr(),
                    icon: LucideIcons.checkCheck,
                    selected: _received == _full,
                    onTap: () => _setReceived(_full),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.md),
        _diff(p),
        const SizedBox(height: Sp.lg),
        SheetSection(
          label: 'settle.note_label'.tr(),
          child: SheetNoteField(
            controller: _noteCtrl,
            hint: 'settle.note_hint'.tr(),
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
          ),
        ),
      ],
    );
  }

  /// الفرق بين المتوقّع والمستلَم — يُرحَّل رصيداً للفترة التالية.
  Widget _diff(CurrentAccount p) {
    final carried = p.expected - _received;
    if (carried.abs() < 0.005) {
      return SheetResultBanner(
        icon: LucideIcons.circleCheck,
        label: 'settle.diff_zero'.tr(),
        value: '0',
        tone: AppTone.success,
      );
    }
    if (carried > 0) {
      return SheetResultBanner(
        icon: LucideIcons.info,
        label: 'settle.diff_left'.tr(),
        value: settleMoney(carried),
        tone: AppTone.warning,
      );
    }
    if (p.expected < 0 && _received == 0) {
      return SheetResultBanner(
        icon: LucideIcons.triangleAlert,
        label: 'settle.diff_deficit'.tr(),
        value: settleMoney(carried),
        tone: AppTone.danger,
      );
    }
    return SheetResultBanner(
      icon: LucideIcons.info,
      label: 'settle.diff_over'.tr(),
      value: settleMoney(carried),
      tone: AppTone.info,
    );
  }
}
