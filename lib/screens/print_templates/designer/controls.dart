import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/permission_locked.dart';
import '../../../services/receipt_layout.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// أسماء أنواع الوصل في الشرائح.
const Map<String, String> designerKindChips = {
  'activation': 'تفعيل',
  'extension': 'تمديد',
  'payment': 'تسديد',
  'info': 'بطاقة',
  'sale': 'فاتورة',
};

/// «لا يظهر في …» بكلمات الوكيل.
const Map<String, String> designerKindPhrase = {
  'activation': 'وصل التفعيل',
  'extension': 'وصل التمديد',
  'payment': 'وصل التسديد',
  'info': 'بطاقة المعلومات',
  'sale': 'فاتورة البيع',
};

const Map<String, String> designerAlignLabels = {'right': 'يمين', 'center': 'وسط', 'left': 'يسار'};
const Map<String, String> designerRowModeLabels = {'line': 'بسطر واحد', 'stack': 'تحت بعض', 'value': 'القيمة فقط'};
const Map<String, String> designerSepLabels = {'none': 'بلا', 'dotted': 'نقاط', 'dashed': 'متقطّع', 'solid': 'متّصل'};

/// العنصر بلا صلاحيّة تعديل: يُرى كما هو، والنقر رسالة القفل ([showNoPermission]) لا تعديل.
class DesignerLockScope extends InheritedWidget {
  const DesignerLockScope({super.key, required this.locked, this.message, required super.child});

  final bool locked;

  /// نصّ القفل حين لا يكون «اطلبها من مديرك» (موظّف شركةٍ لا تُمنح صلاحيّتها: «يغيّره صاحب الحساب»).
  final String? message;

  static DesignerLockScope? _of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<DesignerLockScope>();
  static bool lockedOf(BuildContext c) => _of(c)?.locked ?? false;

  /// رسالة القفل.
  static void deny(BuildContext c) => showNoPermission(c, action: true, message: _of(c)?.message);

  @override
  bool updateShouldNotify(DesignerLockScope old) => old.locked != locked || old.message != message;
}

/// يلفّ عنصر تحكّم: مقفلاً ⇒ لا يستجيب، والنقر عليه رسالة القفل.
class DesignerGate extends StatelessWidget {
  const DesignerGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!DesignerLockScope.lockedOf(context)) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => DesignerLockScope.deny(context),
      child: IgnorePointer(child: Opacity(opacity: 0.55, child: child)),
    );
  }
}

/// عنوانٌ صغير فوق مجموعة تحكّم + المجموعة.
class DesignerField extends StatelessWidget {
  const DesignerField({super.key, required this.label, required this.child, this.trailing, this.hint});

  final String label;
  final Widget child;
  final Widget? trailing;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: AppType.label(), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (DesignerLockScope.lockedOf(context)) const PermLockIcon(size: 12) else if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: Sp.x6),
          DesignerGate(child: child),
          if (hint != null) ...[
            const SizedBox(height: Sp.xs),
            Text(hint!, style: AppType.muted()),
          ],
        ],
      ),
    );
  }
}

/// شريحةٌ صغيرة مختارة/غير مختارة.
class DesignerChip extends StatelessWidget {
  const DesignerChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.ltr = false,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool ltr;

  /// حشوةٌ أضيق (شرائح النوع فوق المعاينة).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = selected ? AppColors.brand : AppColors.textBody;
    return Material(
      color: selected ? AppColors.brandSoftBg : AppColors.surface,
      borderRadius: BorderRadius.circular(R.chip),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(R.chip),
        child: Ink(
          padding: EdgeInsets.symmetric(horizontal: dense ? Sp.sm + Sp.xxs : Sp.md, vertical: Sp.x6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.chip),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.border,
              width: selected ? BW.selected : BW.normal,
            ),
          ),
          child: Text(
            label,
            textDirection: ltr ? TextDirection.ltr : null,
            style: AppType.bodyStrong(color: fg),
          ),
        ),
      ),
    );
  }
}

/// اختيارٌ واحد من شرائح ([values] بالترتيب، و`null` = «تلقائي» إن مُرّر [autoLabel]).
class DesignerChoice<T> extends StatelessWidget {
  const DesignerChoice({
    super.key,
    required this.values,
    required this.labels,
    required this.value,
    required this.onChanged,
    this.autoLabel,
  });

  final List<T> values;
  final Map<T, String> labels;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String? autoLabel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Sp.x6,
      runSpacing: Sp.x6,
      children: [
        if (autoLabel != null) DesignerChip(label: autoLabel!, selected: value == null, onTap: () => onChanged(null)),
        for (final v in values) DesignerChip(label: labels[v] ?? '$v', selected: value == v, onTap: () => onChanged(v)),
      ],
    );
  }
}

/// زرّ − / + صغير.
class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final on = onTap != null;
    return Material(
      color: on ? AppColors.surfaceSunken : AppColors.surfaceDisabled,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        borderRadius: BorderRadius.circular(R.sm),
        child: SizedBox(
          width: H.chipSm,
          height: H.chipSm,
          child: Icon(icon, size: 16, color: on ? AppColors.textHi : AppColors.textHint),
        ),
      ),
    );
  }
}

/// قيمةٌ بين زرّين.
class DesignerStepper extends StatelessWidget {
  const DesignerStepper({super.key, required this.text, this.onMinus, this.onPlus, this.trailing});

  final String text;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(
      children: [
        _StepButton(icon: LucideIcons.minus, onTap: onMinus),
        Expanded(
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.input(),
          ),
        ),
        _StepButton(icon: LucideIcons.plus, onTap: onPlus),
        if (trailing != null) ...[const SizedBox(width: Sp.sm), trailing!],
      ],
    );
  }
}

String _num(num v) => v == v.truncateToDouble() ? '${v.toInt()}' : v.toStringAsFixed(v * 10 % 1 == 0 ? 1 : 2);

/// الحجم بالنقطة: «تلقائي · 9» (يتبع الحجم العامّ) أو مثبّتٌ «12» — سلّم PT_STEPS.
class PtStepper extends StatelessWidget {
  const PtStepper({super.key, required this.pinned, required this.autoPt, required this.onChanged});

  /// المثبّت (null = تلقائي).
  final num? pinned;
  final num autoPt;
  final ValueChanged<num?> onChanged;

  @override
  Widget build(BuildContext context) {
    const steps = receiptPtSteps;
    final cur = pinned;
    num? next(int dir) {
      if (cur == null) {
        // من التلقائيّ: أقرب درجةٍ في الاتّجاه.
        final base = autoPt;
        if (dir > 0) return steps.firstWhere((s) => s > base, orElse: () => steps.last);
        return steps.lastWhere((s) => s < base, orElse: () => steps.first);
      }
      final i = steps.indexOf(cur);
      final j = (i + dir).clamp(0, steps.length - 1);
      return steps[j];
    }

    return DesignerStepper(
      text: cur == null ? 'تلقائي · ${_num(autoPt)}' : 'مثبّت · ${_num(cur)}',
      onMinus: cur == steps.first ? null : () => onChanged(next(-1)),
      onPlus: cur == steps.last ? null : () => onChanged(next(1)),
      trailing: cur == null ? null : DesignerChip(label: 'تلقائي', selected: false, onTap: () => onChanged(null)),
    );
  }
}

/// مسافةٌ بالملّيمتر: ٠–١٠ بخطوة نصف.
class MmStepper extends StatelessWidget {
  const MmStepper({super.key, required this.value, required this.onChanged, this.min = 0, this.max = 10, this.step = 0.5});

  final num value;
  final ValueChanged<num> onChanged;
  final num min;
  final num max;
  final num step;

  @override
  Widget build(BuildContext context) {
    num clean(num v) {
      final r = (v / step).round() * step;
      final c = r.clamp(min, max);
      return c == c.truncateToDouble() ? c.toInt() : c;
    }

    return DesignerStepper(
      text: '${_num(value)} ملم',
      onMinus: value <= min ? null : () => onChanged(clean(value - step)),
      onPlus: value >= max ? null : () => onChanged(clean(value + step)),
    );
  }
}

/// «يظهر في»: الأنواع الخمسة؛ كلّها مختارة = كلّ الأنواع (null).
class KindChips extends StatelessWidget {
  const KindChips({super.key, required this.only, required this.onChanged, this.kinds = receiptKinds});

  final List<String>? only;
  final ValueChanged<List<String>?> onChanged;

  /// الأنواع التي يمكن أن يظهر فيها العنصر أصلاً.
  final List<String> kinds;

  @override
  Widget build(BuildContext context) {
    final sel = only ?? receiptKinds;
    return Wrap(
      spacing: Sp.x6,
      runSpacing: Sp.x6,
      children: [
        for (final k in kinds)
          DesignerChip(
            label: designerKindChips[k]!,
            selected: sel.contains(k),
            onTap: () {
              final next = {...sel};
              if (!next.remove(k)) next.add(k);
              // لا يُفرَّغ: آخر نوعٍ لا يُطفأ (عنصرٌ لا يظهر في شيء يُخفى بمفتاحه).
              if (next.isEmpty) return;
              onChanged(receiptOnly([for (final x in receiptKinds) if (next.contains(x)) x]));
            },
          ),
      ],
    );
  }
}

/// صفّ مفتاح: عنوانٌ ووصفٌ اختياريّ + مفتاح.
class DesignerSwitchRow extends StatelessWidget {
  const DesignerSwitchRow({super.key, required this.label, required this.value, required this.onChanged, this.hint});

  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final locked = DesignerLockScope.lockedOf(context);
    return InkWell(
      onTap: locked ? () => DesignerLockScope.deny(context) : () => onChanged(!value),
      borderRadius: BorderRadius.circular(R.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.xs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppType.bodyStrong(color: AppColors.textHi), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (hint != null) Text(hint!, style: AppType.muted(), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: Sp.sm),
            if (locked)
              const PermLockIcon(size: 14)
            else
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeTrackColor: AppColors.brand,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة مجموعة في التبويبات (حدٌّ وحشوة كبطاقات التطبيق).
class DesignerCard extends StatelessWidget {
  const DesignerCard({super.key, required this.title, required this.children, this.icon});

  final String title;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.md),
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.xs),
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
              if (icon != null) ...[Icon(icon, size: 14, color: AppColors.brand), const SizedBox(width: Sp.x6)],
              Expanded(
                child: Text(
                  title,
                  style: AppType.bodyStrong(color: AppColors.textHi).copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          ...children,
        ],
      ),
    );
  }
}
