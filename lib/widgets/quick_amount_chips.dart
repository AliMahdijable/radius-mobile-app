import 'package:flutter/material.dart';
import '../core/utils/helpers.dart';

/// Wrap of preset-amount chips. Tapping a chip accumulates onto the existing
/// amount (so tapping 10,000 then 5,000 yields 15,000). Optionally highlights
/// a chip when [selectedAmount] exactly matches.
class QuickAmountChips extends StatelessWidget {
  final List<double> amounts;
  final double selectedAmount;
  final bool enabled;
  final ValueChanged<double> onSelected;

  const QuickAmountChips({
    super.key,
    required this.amounts,
    required this.selectedAmount,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (amounts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: amounts.map((v) {
        final isSelected = (selectedAmount - v).abs() < 0.5;
        return GestureDetector(
          onTap: enabled ? () => onSelected(v) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primary.withOpacity(0.15)
                  : theme.colorScheme.surfaceContainerHighest
                      .withOpacity(enabled ? 0.5 : 0.25),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary.withOpacity(0.4)
                    : Colors.transparent,
              ),
            ),
            child: Text(
              AppHelpers.formatMoney(v),
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
                color: !enabled
                    ? theme.colorScheme.onSurface.withOpacity(0.3)
                    : isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
