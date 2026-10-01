import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscriber_prices_api.dart';
import '../../../api/subscribers_api.dart';
import '../../../core/util/amount_input.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../services/permissions_service.dart';
import '../../../services/subscriber_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';

/// «أسعار المشتركين» — ضبط السعر الثابت لمشتركٍ واحد أو حذفه.
///
/// الأرقام كلّها من activation-data: السعر الطبيعي (`base_price`)، وتكلفة
/// المدير (`manager_cost`)، والثابت الحاليّ، والخصم الذي سيُلغى. التطبيق
/// لا يحسب شيئاً — الخادم يقرّر ما يُسجَّل عند التفعيل.
///
/// تحذيران لا منعان (قرارات المستخدم ٢٠٢٦-١٠-٠١):
/// - سعرٌ أقلّ من تكلفة المدير **مسموح** — المدير يخسر الفرق.
/// - للمشترك خصم: الثابت يلغيه، والخصم يبقى محفوظاً ويعود إن حُذف الثابت.
Future<bool?> showSubscriberPriceSheet(
  BuildContext context, {
  required String idx,
  required String name,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SubscriberPriceSheet(idx: idx, name: name),
  );
}

class _SubscriberPriceSheet extends StatefulWidget {
  const _SubscriberPriceSheet({required this.idx, required this.name});
  final String idx;
  final String name;

  @override
  State<_SubscriberPriceSheet> createState() => _SubscriberPriceSheetState();
}

class _SubscriberPriceSheetState extends State<_SubscriberPriceSheet> {
  final _ctrl = TextEditingController();
  bool _loading = true;
  bool _failed = false;
  bool _submitting = false;
  int _amount = 0;

  num _basePrice = 0;
  num _managerCost = 0;
  num? _currentFixed;
  bool _fixedActive = false;
  bool _needsRepricing = false;
  num _discount = 0;
  String _profileName = '';

  bool get _canManage => Perms.has('subscriber_prices.manage');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await SubscribersApi.fetchActivationData(widget.idx);
    if (!mounted) return;
    if (data == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    num readNum(String key) {
      final v = data[key];
      if (v == null) return 0;
      if (v is num) return v;
      return num.tryParse(v.toString().replaceAll(',', '')) ?? 0;
    }

    final source = data['price_source']?.toString();
    _fixedActive = source == 'custom';
    _needsRepricing = data['needs_repricing'] == true;
    final custom = readNum('custom_price');
    _currentFixed = custom > 0 ? custom : null;
    // `base_price` منذ «أسعار المشتركين»؛ وخادمٌ أقدم يرسل `user_price`.
    _basePrice = readNum('base_price') > 0
        ? readNum('base_price')
        : readNum('user_price');
    _managerCost = readNum('manager_cost');
    // الخصم الذي سيُلغيه الثابت: إن كان الثابت سارياً فهو `overridden_discount`.
    _discount = _fixedActive
        ? readNum('overridden_discount')
        : readNum('discount_amount');
    _profileName = (data['profile_name'] ?? '').toString();

    final seed = _currentFixed;
    if (seed != null && !_needsRepricing) {
      _amount = seed.round();
      _ctrl.text = formatIQD(_amount);
    }
    setState(() => _loading = false);
  }

  bool get _belowCost =>
      _amount > 0 && _managerCost > 0 && _amount < _managerCost;

  bool get _canSave {
    if (_loading || _failed || _submitting || !_canManage) return false;
    if (_amount <= 0) return false;
    // نفس الثابت السارٍ = لا شيء يُحفظ. أمّا «يحتاج تسعير» فالحفظ يربطه
    // بالباقة الجديدة ولو كان الرقم نفسه.
    if (_fixedActive && _currentFixed != null && _amount == _currentFixed!.round()) {
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    setState(() => _submitting = true);
    final r = await SubscriberPricesApi.set(widget.idx, _amount);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (r.ok) SubscriberEvents.notifyChange();
    showSheetSnack(
      context,
      r.ok
          ? 'sp.saved'.tr(args: [formatIQD(_amount)])
          : (r.message ?? 'sp.save_failed'.tr()),
      isError: !r.ok,
    );
    if (r.ok) Navigator.of(context).pop(true);
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('sp.remove_title'.tr()),
        content: Text('sp.remove_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _submitting = true);
    final r = await SubscriberPricesApi.remove(widget.idx);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (r.ok) SubscriberEvents.notifyChange();
    showSheetSnack(
      context,
      r.ok ? 'sp.removed'.tr() : (r.message ?? 'sp.remove_failed'.tr()),
      isError: !r.ok,
    );
    if (r.ok) Navigator.of(context).pop(true);
  }

  String _iqd(num v) => '${formatIQD(v.round())} ${'common.currency'.tr()}';

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final hasFixed = _currentFixed != null;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.banknote,
        title: 'sp.sheet_title'.tr(),
        subtitle: widget.name,
        tint: AppColors.brandAccent,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: !_canManage
          ? null
          : SheetFooterBar(
              label: _submitting ? 'sp.saving'.tr() : 'sp.save'.tr(),
              icon: LucideIcons.check,
              color: AppColors.brandAccent,
              enabled: _canSave,
              busy: _submitting,
              onPressed: _save,
              leading: hasFixed && !_loading
                  ? SheetFooterIconButton(
                      icon: LucideIcons.trash2,
                      color: AppColors.error,
                      onTap: _submitting ? null : _remove,
                    )
                  : null,
            ),
      body: _loading
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.mega),
              child: Center(
                child: CircularProgressIndicator(
                    color: AppColors.brandAccent, strokeWidth: 2.5),
              ),
            )
          : _failed
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: Sp.xl),
                  child: SheetResultBanner(
                    icon: LucideIcons.wifiOff,
                    label: 'sp.load_failed'.tr(),
                    value: '',
                    tone: AppTone.danger,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SheetSummaryBox(
                      label: _profileName.isEmpty
                          ? 'sp.normal_price'.tr()
                          : 'sp.normal_price_of'.tr(args: [_profileName]),
                      value: _iqd(_basePrice),
                    ),
                    if (_managerCost > 0) ...[
                      const SizedBox(height: Sp.sm),
                      SheetSummaryBox(
                        label: 'sp.manager_cost'.tr(),
                        value: _iqd(_managerCost),
                        valueColor: AppColors.textMid,
                      ),
                    ],
                    if (hasFixed) ...[
                      const SizedBox(height: Sp.sm),
                      SheetSummaryBox(
                        label: 'sp.current_fixed'.tr(),
                        value: _iqd(_currentFixed!),
                        valueColor: AppColors.brandAccent,
                      ),
                    ],
                    if (_needsRepricing) ...[
                      const SizedBox(height: Sp.md),
                      SheetResultBanner(
                        icon: LucideIcons.package,
                        label: 'sp.repricing_title'.tr(),
                        value: 'sp.repricing_body'.tr(),
                        tone: AppTone.info,
                      ),
                    ],
                    const SizedBox(height: Sp.lg),
                    SheetSection(
                      label: 'sp.fixed_price'.tr(),
                      hint: 'sp.fixed_price_hint'.tr(),
                      gap: 9,
                      child: SheetBox(
                        focused: _amount > 0,
                        radius: 18,
                        padding: const EdgeInsets.symmetric(
                            horizontal: Sp.lg, vertical: 14),
                        child: AmountTextField(
                          controller: _ctrl,
                          enabled: _canManage,
                          currency: 'common.currency'.tr(),
                          onValue: (v) => setState(() => _amount = v),
                        ),
                      ),
                    ),
                    if (_belowCost) ...[
                      const SizedBox(height: Sp.md),
                      SheetResultBanner(
                        icon: LucideIcons.triangleAlert,
                        label: 'sp.below_cost'.tr(),
                        value: 'sp.below_cost_by'
                            .tr(args: [_iqd(_managerCost - _amount)]),
                        tone: AppTone.warning,
                      ),
                    ],
                    if (_discount > 0) ...[
                      const SizedBox(height: Sp.md),
                      SheetResultBanner(
                        icon: LucideIcons.tag,
                        label: 'sp.discount_cancelled'
                            .tr(args: [_iqd(_discount)]),
                        value: 'sp.discount_kept'.tr(),
                        tone: AppTone.info,
                      ),
                    ],
                  ],
                ),
    );
  }
}
