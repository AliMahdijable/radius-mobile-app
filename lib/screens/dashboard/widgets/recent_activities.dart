import 'package:flutter/material.dart';

import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Recent activity feed for home. Backend rows from
/// /api/activities/daily-activations are raw maps; the row widget reads
/// each field directly. No mock fallback — loading/empty/error states
/// are rendered by the dashboard.
class RecentActivities extends StatelessWidget {
  const RecentActivities({super.key, required this.items});

  /// Backend rows from /api/activities/daily-activations.
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _Row(item: items[i]),
            if (i < items.length - 1)
              const Divider(
                height: 1,
                indent: Sp.huge + Sp.sm,
                endIndent: Sp.lg,
                color: AppColors.border,
              ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item});
  final Map<String, dynamic> item;

  ({
    IconData icon,
    Color color,
    String title,
    String? subLabel,
    int amount,
    String timeLabel,
  }) _normalize() {
    final m = item;
    final action = (m['action'] ?? m['action_type'] ?? '').toString();
    final visual = _visualForAction(action);
    // Backend enriches each row with user_firstname / user_lastname /
    // user_username via SAS4's user directory (see
    // /api/activities/daily-activations row enrichment). The Arabic
    // full name reads at-a-glance; the username goes in parentheses
    // as a secondary identifier so admins still see "the same
    // ahmed@x" they're used to from the v1 web. Falls back to
    // username alone when no name is in SAS4.
    final firstname = (m['user_firstname'] ?? '').toString().trim();
    final lastname = (m['user_lastname'] ?? '').toString().trim();
    final username = (m['user_username'] ??
            m['target_name'] ??
            m['subscriber_username'] ??
            m['username'] ??
            '')
        .toString()
        .trim();
    final fullName =
        [firstname, lastname].where((s) => s.isNotEmpty).join(' ').trim();
    final title = fullName.isNotEmpty
        ? (username.isNotEmpty ? '$fullName ($username)' : fullName)
        : (username.isNotEmpty ? username : action);
    // Short action label below the name so the row still tells the
    // admin WHAT happened without dragging in the whole verbose
    // backend description ('تفعيل المشترك … | الباقة: … | السعر: …').
    final subLabel = _shortActionLabel(action);
    final amount = _readAmount(m);
    final created = m['created_at']?.toString();
    final timeLabel = _humanCreatedAt(created);
    return (
      icon: visual.$1,
      color: visual.$2,
      title: title,
      subLabel: subLabel,
      amount: amount,
      timeLabel: timeLabel,
    );
  }

  /// Maps backend action_type → short Arabic action label. Returns
  /// null when the action is unrecognized so the row just shows the
  /// time + amount.
  static String? _shortActionLabel(String action) {
    final lower = action.toLowerCase();
    if (lower.contains('extend')) return 'تمديد';
    // Order matters — 'subscriber_activate_cash' contains both
    // 'activate' and 'cash', and 'debt_pay' contains 'debt' before
    // 'pay'. We pick the most specific match first.
    if (lower.contains('debt_pay') ||
        lower.contains('balance_deduct') ||
        lower.contains('deduct_balance') ||
        lower.contains('pay_debt')) {
      return 'تسديد دين';
    }
    if (lower.contains('balance_add') || lower.contains('add_debt')) {
      return 'إضافة دين';
    }
    if (lower.contains('payment_add')) return 'إيراد';
    if (lower.contains('activ')) return 'تفعيل';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final n = _normalize();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.lg,
            vertical: Sp.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: n.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(n.icon, color: n.color, size: 18),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Primary line: subscriber name (username) — admin
                    // sees the readable Arabic name first and the
                    // technical username in parentheses for fast cross-
                    // reference with v1's flow. Single line keeps the
                    // row compact; the action type is conveyed by the
                    // tinted icon + the short label below.
                    Text(
                      n.title,
                      style: AppType.label(color: AppColors.textHi).copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (n.subLabel != null) ...[
                          Text(
                            n.subLabel!,
                            style: AppType.muted(color: n.color).copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: const BoxDecoration(
                              color: AppColors.textLow,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          n.timeLabel,
                          style: AppType.muted(color: AppColors.textLow)
                              .copyWith(
                                  fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                        if (n.amount != 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: const BoxDecoration(
                              color: AppColors.textLow,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${n.amount < 0 ? '-' : '+'}${formatIQD(n.amount)} د.ع',
                            style: AppType.label(
                              color: n.amount < 0
                                  ? AppColors.error
                                  : AppColors.brand,
                            ).copyWith(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Maps backend action_type strings to (icon, color).
  static (IconData, Color) _visualForAction(String action) {
    final lower = action.toLowerCase();
    if (lower.contains('activ')) return (Icons.bolt_rounded, AppColors.brand);
    if (lower.contains('extend')) {
      return (Icons.loop_rounded, const Color(0xFF3B82F6));
    }
    if (lower.contains('pay') || lower.contains('debt_pay')) {
      return (Icons.payments_rounded, AppColors.brand);
    }
    if (lower.contains('debt') || lower.contains('add_debt')) {
      return (Icons.account_balance_wallet_rounded, AppColors.error);
    }
    if (lower.contains('whatsapp') || lower.contains('message')) {
      return (Icons.chat_bubble_rounded, const Color(0xFFE08F2D));
    }
    return (Icons.history_rounded, AppColors.textMid);
  }

  static int _readAmount(Map<String, dynamic> m) {
    final raw = m['amount'] ?? m['paid_amount'] ?? m['debt_amount'];
    if (raw == null) return 0;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString()) ?? 0;
  }

  static String _humanCreatedAt(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
    final days = diff.inDays;
    if (days == 1) return 'قبل يوم';
    return 'قبل $days أيام';
  }
}
