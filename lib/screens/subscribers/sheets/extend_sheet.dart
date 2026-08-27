import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscribers_api.dart';
import '../../../core/util/format.dart';
import '../../../models/subscriber.dart';
import '../../../services/manual_wa_prefs.dart';
import '../../../services/manual_wa_sender.dart';
import '../../../services/receipt_service.dart';
import '../../../services/subscriber_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '_print_receipt_checkbox.dart';
import '../../../core/widgets/sheet_scaffold.dart';

/// Extend-subscription sheet — direct port of v1's _extendSubscription.
///   1. Fetch /api/v2/subscribers/:idx/extension-options. Spinner while
///      the round-trip is in flight.
///   2. Show current profile + manager balance + reward-points balance.
///   3. Dropdown of packages the subscriber can extend into; selecting
///      one fills in price + required points.
///   4. Method picker: balance (charges manager wallet) or points
///      (deducts reward points).
///   5. Submit → /api/v2/subscribers/:idx/extend with {profile_id,
///      method}.
Future<bool?> showExtendSheet(BuildContext context, Subscriber sub) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ExtendSheet(sub: sub),
  );
}

class _ExtendSheet extends StatefulWidget {
  const _ExtendSheet({required this.sub});
  final Subscriber sub;

  @override
  State<_ExtendSheet> createState() => _ExtendSheetState();
}

enum _Method { balance, points }

class _ExtendSheetState extends State<_ExtendSheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;

  Map<String, dynamic>? _selectedPkg;
  _Method _method = _Method.balance;
  bool _printReceiptChecked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final idx = widget.sub.idx;
    if (idx == null) {
      setState(() {
        _loading = false;
        _loadError = 'sheets.extend_no_idx'.tr();
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final data = await SubscribersApi.fetchExtensionOptions(idx);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = data;
      if (data == null) {
        _loadError = 'sheets.extend_load_failed'.tr();
      } else {
        final list = (data['packages'] as List?) ?? const [];
        if (list.isNotEmpty) {
          _selectedPkg = (list.first as Map).cast<String, dynamic>();
        }
      }
    });
  }

  num _read(Map<String, dynamic>? m, String key) {
    final v = m?[key];
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString().replaceAll(',', '')) ?? 0;
  }

  num get _managerBalance => _read(_data, 'manager_balance');
  num get _pointsBalance => _read(_data, 'reward_points_balance');
  String get _currentProfileName =>
      _data?['current_profile_name']?.toString() ?? '';

  num get _selectedPrice => _read(_selectedPkg, 'price');
  num get _selectedPoints =>
      _read(_selectedPkg, 'reward_points_required');
  String? get _selectedDuration =>
      _selectedPkg?['duration']?.toString();

  bool get _canSubmit {
    if (_loading || _submitting || _data == null || _selectedPkg == null) {
      return false;
    }
    if (_method == _Method.points) {
      return _pointsBalance >= _selectedPoints && _selectedPoints > 0;
    }
    return _selectedPrice > 0 && _managerBalance >= _selectedPrice;
  }

  String? get _disabledReason {
    if (_selectedPkg == null) return null;
    if (_method == _Method.points) {
      if (_selectedPoints <= 0) return 'sheets.no_points_support'.tr();
      if (_pointsBalance < _selectedPoints) return 'sheets.insufficient_points'.tr();
    } else {
      if (_selectedPrice <= 0) return 'sheets.no_price'.tr();
      if (_managerBalance < _selectedPrice) return 'sheets.insufficient_balance'.tr();
    }
    return null;
  }

  Future<void> _submit() async {
    final idx = widget.sub.idx;
    final pkg = _selectedPkg;
    if (idx == null || pkg == null) return;
    final profileId = pkg['id']?.toString() ?? '';
    if (profileId.isEmpty) return;
    setState(() => _submitting = true);
    // 2026-08-26 (manual WA phase 2): وضع يدوي → backend يعيد wa_preview
    // بلا إرسال، ونفتح modal بعد النجاح.
    final manualMode = ManualWaPrefs.enabled.value;
    final result = await SubscribersApi.extend(
      idx: idx,
      profileId: profileId,
      method: _method == _Method.points ? 'points' : 'balance',
      skipAutoWa: manualMode,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!result.ok) {
      showSheetSnack(context, result.message ?? 'common.error'.tr(), isError: true);
      return;
    }
    SubscriberEvents.notifyChange();
    showSheetSnack(context, 'sheets.extend_ok'.tr(), isError: false);
    // 2026-07-13: طباعة تلقائية بعد النجاح لو الـcheckbox مُفعَّل.
    if (_printReceiptChecked) {
      final price = _method == _Method.points ? 0 : _selectedPrice;
      final durationDays =
          int.tryParse(pkg['duration_days']?.toString() ?? '');
      await ReceiptService.printActivationReceipt(
        sub: widget.sub,
        packagePrice: price,
        paidAmount: price, // التجديد = دفع كامل من الرصيد
        durationDays: durationDays,
      );
    }
    if (!mounted) return;
    // 2026-08-26: preview WA بعد نجاح التمديد.
    if (manualMode) {
      if (result.waPreview != null) {
        await handleWaPreviewAfterOp(
          context: context,
          preview: result.waPreview!,
          opTitle: 'تأكيد التمديد',
          sas4Idx: widget.sub.idx,
        );
        if (!mounted) return;
      } else {
        final reason = result.wa?.reason;
        if (reason == 'no_phone') {
          showSheetSnack(context, 'لم يُبنَ preview: لا رقم هاتف للمشترك', isError: true);
        }
        // تمديد يستعمل literalMessage — بلا قالب فما نحصل no_template.
      }
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
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
                icon: LucideIcons.repeat,
                title: 'sheets.extend_subscriber'.tr(),
                subtitle: widget.sub.fullName,
                color: const Color(0xFF3B82F6),
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
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.sm),
                child: PrintReceiptCheckbox(
                  value: _printReceiptChecked,
                  onChanged: (v) =>
                      setState(() => _printReceiptChecked = v),
                ),
              ),
              _SubmitBar(
                label: _submitting
                    ? 'جاري التمديد...'
                    : (_disabledReason ?? 'تمديد الآن'),
                color: const Color(0xFF3B82F6),
                icon: LucideIcons.repeat,
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
                  child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      ];
    }
    final pkgs = (_data?['packages'] as List?) ?? const [];
    if (pkgs.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.huge),
          child: Column(
            children: [
              Icon(LucideIcons.inbox,
                  color: AppColors.textLow, size: 32),
              const SizedBox(height: Sp.sm),
              Text('لا توجد باقات متاحة للتمديد',
                  style: AppType.label(color: AppColors.textMid)),
            ],
          ),
        ),
      ];
    }
    return [
      _MetaCard(
        currentProfileName: _currentProfileName,
        managerBalance: _managerBalance,
        pointsBalance: _pointsBalance,
      ),
      const SizedBox(height: Sp.sm),
      _SectionTitle('اختر باقة التمديد'),
      const SizedBox(height: Sp.xs),
      _PackagePicker(
        packages: pkgs.cast<Map>().map((e) => e.cast<String, dynamic>()).toList(),
        selected: _selectedPkg,
        onSelect: (p) => setState(() => _selectedPkg = p),
      ),
      if (_selectedPkg != null) ...[
        const SizedBox(height: Sp.sm),
        _SelectedSummary(
          price: _selectedPrice,
          points: _selectedPoints,
          duration: _selectedDuration,
        ),
        const SizedBox(height: Sp.md),
        _SectionTitle('طريقة الدفع'),
        const SizedBox(height: Sp.xs),
        _MethodPicker(
          current: _method,
          pointsAvailable: _selectedPoints > 0,
          onSelect: (m) => setState(() => _method = m),
        ),
      ],
    ];
  }
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({
    required this.currentProfileName,
    required this.managerBalance,
    required this.pointsBalance,
  });
  final String currentProfileName;
  final num managerBalance;
  final num pointsBalance;

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
          _row(LucideIcons.package, 'الباقة الحالية',
              currentProfileName.isEmpty ? '—' : currentProfileName, null),
          _row(
            LucideIcons.wallet,
            'رصيد المدير',
            '${formatIQD(managerBalance.round())} د.ع',
            AppColors.textHi,
          ),
          if (pointsBalance > 0)
            _row(
              LucideIcons.star,
              'النقاط المتاحة',
              '${formatIQD(pointsBalance.round())}',
              const Color(0xFFCD8B00),
            ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, Color? c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMid, size: 13),
          const SizedBox(width: 6),
          Text(label,
              style: AppType.muted(color: AppColors.textMid)
                  .copyWith(fontSize: 11, fontWeight: FontWeight.w600)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: AppType.label(color: c ?? AppColors.textHi)
                  .copyWith(fontSize: 12, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
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
      child: Text(text,
          style: AppType.label(color: AppColors.textHi)
              .copyWith(fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}

class _PackagePicker extends StatelessWidget {
  const _PackagePicker({
    required this.packages,
    required this.selected,
    required this.onSelect,
  });
  final List<Map<String, dynamic>> packages;
  final Map<String, dynamic>? selected;
  final ValueChanged<Map<String, dynamic>> onSelect;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Column(
      children: [
        for (final p in packages)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _PackageRow(
              pkg: p,
              selected: selected != null && selected!['id'] == p['id'],
              onTap: () {
                HapticFeedback.selectionClick();
                onSelect(p);
              },
            ),
          ),
      ],
    );
  }
}

class _PackageRow extends StatelessWidget {
  const _PackageRow({
    required this.pkg,
    required this.selected,
    required this.onTap,
  });
  final Map<String, dynamic> pkg;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final name = pkg['name']?.toString() ?? '';
    final price = pkg['price'] is num
        ? (pkg['price'] as num).toInt()
        : int.tryParse(pkg['price']?.toString() ?? '') ?? 0;
    final points = pkg['reward_points_required'] is num
        ? (pkg['reward_points_required'] as num).toInt()
        : int.tryParse(
                pkg['reward_points_required']?.toString() ?? '') ??
            0;
    return Material(
      color: selected
          ? const Color(0xFF3B82F6).withValues(alpha: 0.08)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
              color: selected
                  ? const Color(0xFF3B82F6)
                  : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? LucideIcons.circleCheck
                    : LucideIcons.circle,
                color: selected
                    ? const Color(0xFF3B82F6)
                    : AppColors.textLow,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: AppType.label(color: AppColors.textHi).copyWith(
                      fontSize: 12, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (points > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCD8B00)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.star,
                          color: Color(0xFFCD8B00), size: 10),
                      const SizedBox(width: 3),
                      Text(
                        formatIQD(points),
                        style: AppType.muted(
                                color: const Color(0xFFCD8B00))
                            .copyWith(
                                fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                '${formatIQD(price)} د.ع',
                style: AppType.label(color: AppColors.brand)
                    .copyWith(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedSummary extends StatelessWidget {
  const _SelectedSummary({
    required this.price,
    required this.points,
    required this.duration,
  });
  final num price;
  final num points;
  final String? duration;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(
          color: const Color(0xFF3B82F6).withValues(alpha: 0.18),
        ),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Chip(
            icon: LucideIcons.tag,
            text: '${formatIQD(price.round())} د.ع',
            color: AppColors.brand,
          ),
          if (points > 0)
            _Chip(
              icon: LucideIcons.star,
              text: '${formatIQD(points.round())} نقطة',
              color: const Color(0xFFCD8B00),
            ),
          if (duration != null && duration!.isNotEmpty)
            _Chip(
              icon: LucideIcons.clock,
              text: duration!,
              color: AppColors.textMid,
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 4),
        Text(text,
            style: AppType.muted(color: color)
                .copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _MethodPicker extends StatelessWidget {
  const _MethodPicker({
    required this.current,
    required this.pointsAvailable,
    required this.onSelect,
  });
  final _Method current;
  final bool pointsAvailable;
  final ValueChanged<_Method> onSelect;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(
      children: [
        Expanded(
          child: _MethodBtn(
            label: 'برصيد المدير',
            icon: LucideIcons.wallet,
            color: AppColors.brand,
            selected: current == _Method.balance,
            enabled: true,
            onTap: () => onSelect(_Method.balance),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _MethodBtn(
            label: 'بالنقاط',
            icon: LucideIcons.star,
            color: const Color(0xFFCD8B00),
            selected: current == _Method.points,
            enabled: pointsAvailable,
            onTap: pointsAvailable
                ? () => onSelect(_Method.points)
                : null,
          ),
        ),
      ],
    );
  }
}

/// Transparent card-style picker — same visual language as the
/// operations grid on the detail screen (white surface + border +
/// soft shadow + tinted icon-box on top + colored label). Selected
/// state tints the surface and thickens the border; disabled state
/// drops opacity so the option still reads but signals it's locked.
class _MethodBtn extends StatelessWidget {
  const _MethodBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final tile = Material(
      color: selected ? color.withValues(alpha: 0.08) : AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
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
    if (enabled) return tile;
    return Opacity(opacity: 0.45, child: tile);
  }
}

// ───────── shared sheet chrome (copy of activate_sheet's) ─────────

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
