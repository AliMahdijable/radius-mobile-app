import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/format.dart';
import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Modern subscriber card — same data v1's SubscriberCard shows, cleaner
/// layout: status pill + name + handle in header, then a compact info
/// row with package + expiry, and a debt/credit footer when relevant.
class SubscriberCardV2 extends StatelessWidget {
  const SubscriberCardV2({
    super.key,
    required this.sub,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Subscriber sub;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final disabled = !sub.isEnabled;
    final statusColor = _statusColor();
    final statusLabel = _statusLabel();
    final statusIcon = _statusIcon();

    final accentBorder = selected
        ? Border.all(color: AppColors.brand, width: 2)
        : Border.all(color: AppColors.border);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(R.lg),
        child: Opacity(
          opacity: disabled ? 0.6 : 1,
          child: Container(
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.brand.withValues(alpha: 0.06)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(R.lg),
              border: accentBorder,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _StatusBadge(color: statusColor, icon: statusIcon),
                    const SizedBox(width: Sp.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sub.fullName,
                            style: AppType.label(color: AppColors.textHi)
                                .copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              decoration: disabled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (sub.fullName != sub.username) ...[
                            const SizedBox(height: 2),
                            Text(
                              sub.username,
                              style: AppType.muted(color: AppColors.textLow)
                                  .copyWith(fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    _ExpiryPill(
                      remaining: sub.remainingDays,
                      disabled: disabled,
                    ),
                  ],
                ),
                const SizedBox(height: Sp.sm),
                // Row 1: status label + package
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(R.pill),
                      ),
                      child: Text(
                        statusLabel,
                        style: AppType.muted(color: statusColor)
                            .copyWith(fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(LucideIcons.package,
                        size: 12, color: AppColors.textMid),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        (sub.profileName?.isNotEmpty ?? false)
                            ? sub.profileName!
                            : 'بدون باقة',
                        style: AppType.muted(color: AppColors.textMid)
                            .copyWith(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Row 2: phone + expiration date
                Row(
                  children: [
                    if (sub.displayPhone.isNotEmpty) ...[
                      const Icon(LucideIcons.phone,
                          size: 12, color: AppColors.textMid),
                      const SizedBox(width: 4),
                      Text(
                        sub.displayPhone,
                        style: AppType.muted(color: AppColors.textMid)
                            .copyWith(fontSize: 11),
                      ),
                      const SizedBox(width: 10),
                    ],
                    const Icon(LucideIcons.calendar,
                        size: 12, color: AppColors.textMid),
                    const SizedBox(width: 4),
                    Text(
                      _formatExpiration(sub.expiration),
                      style: AppType.muted(color: AppColors.textMid)
                          .copyWith(fontSize: 11),
                    ),
                  ],
                ),
                if (sub.balanceAmount != 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        sub.hasDebt
                            ? LucideIcons.creditCard
                            : LucideIcons.wallet,
                        size: 13,
                        color: sub.hasDebt
                            ? AppColors.error
                            : AppColors.brand,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        sub.hasDebt
                            ? 'دين: ${formatIQD(sub.debtAbs.round())} د.ع'
                            : 'رصيد: ${formatIQD(sub.debtAbs.round())} د.ع',
                        style: AppType.label(
                          color: sub.hasDebt
                              ? AppColors.error
                              : AppColors.brand,
                        ).copyWith(fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Formats SAS4's expiration string ('2026-09-30 00:00:00' or
  /// '2026-09-30') to 'YYYY/MM/DD HH:MM'. Time is included so admins
  /// can see the exact moment a subscription ends, not just the date.
  /// Returns '—' for null/empty so the row stays aligned.
  static String _formatExpiration(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '—';
    final s = raw.trim();
    final t = DateTime.tryParse(s) ?? DateTime.tryParse(s.split(' ').first);
    if (t == null) return s.split(' ').first;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}/${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  // ───────── status helpers ─────────
  Color _statusColor() {
    if (!sub.isEnabled) return const Color(0xFF6D4C41);
    if (sub.isExpired) return AppColors.error;
    if (sub.isNearExpiry) return const Color(0xFFE08F2D);
    if (sub.isOnlineFlag) return const Color(0xFF3B82F6);
    return AppColors.brand;
  }

  String _statusLabel() {
    if (!sub.isEnabled) return 'معطّل';
    if (sub.isExpired) return 'منتهي';
    if (sub.isNearExpiry) return 'قارب الانتهاء';
    if (sub.isOnlineFlag) return 'متصل';
    return 'نشط';
  }

  IconData _statusIcon() {
    if (!sub.isEnabled) return LucideIcons.ban;
    if (sub.isExpired) return LucideIcons.timerOff;
    if (sub.isNearExpiry) return LucideIcons.triangleAlert;
    if (sub.isOnlineFlag) return LucideIcons.wifi;
    return LucideIcons.circleCheck;
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.color, required this.icon});
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _ExpiryPill extends StatelessWidget {
  const _ExpiryPill({required this.remaining, required this.disabled});
  final int? remaining;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    if (disabled) return _pill('معطّل', const Color(0xFF6D4C41));
    final d = remaining;
    if (d == null) return _pill('—', AppColors.textLow);
    if (d < 0) return _pill('منتهي', AppColors.error);
    if (d == 0) return _pill('اليوم', AppColors.error);
    if (d <= 3) return _pill('$d يوم', const Color(0xFFE08F2D));
    if (d <= 7) return _pill('$d يوم', const Color(0xFFCD8B00));
    return _pill('$d يوم', AppColors.brand);
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: AppType.muted(color: color)
            .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
