import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Horizontal row of large quick-action buttons placed right under the
/// hero revenue card. The 4 most-used operations of an ISP shop:
/// activate, pay debt, new subscriber, send message.
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: _QuickButton(
            icon: Icons.bolt_rounded,
            label: 'تفعيل',
            color: AppColors.brand,
          ),
        ),
        SizedBox(width: Sp.sm),
        Expanded(
          child: _QuickButton(
            icon: Icons.payments_rounded,
            label: 'تسديد',
            color: Color(0xFF8B5CF6),
          ),
        ),
        SizedBox(width: Sp.sm),
        Expanded(
          child: _QuickButton(
            icon: Icons.person_add_rounded,
            label: 'مشترك جديد',
            color: Color(0xFF3B82F6),
          ),
        ),
        SizedBox(width: Sp.sm),
        Expanded(
          child: _QuickButton(
            icon: Icons.chat_bubble_rounded,
            label: 'رسالة',
            color: Color(0xFFE08F2D),
          ),
        ),
      ],
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          // TODO[wire-quick-action]: route to respective flow.
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: AppType.label(color: AppColors.textHi)
                    .copyWith(fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
