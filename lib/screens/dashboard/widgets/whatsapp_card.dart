import 'package:flutter/material.dart';

import '../../../core/mock/dashboard_data.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// WhatsApp connection status card. Green when connected, red when not
/// — and offers a "ربط" CTA so the user can recover from the home screen
/// without hunting for the WhatsApp page.
class WhatsAppCard extends StatelessWidget {
  const WhatsAppCard({super.key, required this.status});

  final WhatsAppStatus status;

  @override
  Widget build(BuildContext context) {
    final c = status.connected ? AppColors.brand : AppColors.error;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(Sp.lg),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(
              status.connected
                  ? Icons.chat_bubble_rounded
                  : Icons.cloud_off_rounded,
              color: c,
              size: 22,
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration:
                          BoxDecoration(color: c, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status.connected ? 'متصل' : 'منقطع',
                      style: AppType.label(color: c).copyWith(fontSize: 13),
                    ),
                    const SizedBox(width: Sp.sm),
                    Flexible(
                      child: Text(
                        status.phone,
                        style: AppType.subtitle(color: AppColors.textMid)
                            .copyWith(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (status.connected) ...[
                  const SizedBox(height: 6),
                  Text(
                    '✓ ${status.sentToday} رسالة اليوم • ${status.queuePending} بالطابور',
                    style: AppType.muted(color: AppColors.textLow)
                        .copyWith(fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          if (!status.connected) ...[
            const SizedBox(width: Sp.sm),
            SizedBox(
              height: 36,
              child: Material(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(R.sm),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {},
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: Sp.md),
                    child: Center(
                      child: Text(
                        'ربط',
                        style: AppType.label(color: AppColors.error)
                            .copyWith(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
