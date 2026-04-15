import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/utils/helpers.dart';
import '../core/theme/app_theme.dart';
import '../models/subscriber_model.dart';

class SubscriberCard extends StatelessWidget {
  final SubscriberModel subscriber;
  final VoidCallback? onTap;
  final bool showOnlineDetails;
  final Map<String, dynamic>? lastPayment;

  const SubscriberCard({
    super.key,
    required this.subscriber,
    this.onTap,
    this.showOnlineDetails = false,
    this.lastPayment,
  });

  static String formatBytes(int? bytes) {
    if (bytes == null || bytes == 0) return '0';
    if (bytes >= 1073741824) return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(0)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  static String formatDuration(int? seconds) {
    if (seconds == null || seconds == 0) return '0';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 24) return '${h ~/ 24}ي ${h % 24}س';
    if (h > 0) return '${h}س ${m}د';
    return '${m}د';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = !subscriber.isEnabled;
    final daysColor = isDisabled ? Colors.grey : AppHelpers.getRemainingDaysColor(subscriber.remainingDays);
    final isOnline = subscriber.isOnline;
    final hasProfile = subscriber.profileName != null &&
        subscriber.profileName!.isNotEmpty;

    return Opacity(
      opacity: isDisabled ? 0.55 : 1.0,
      child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDisabled
              ? theme.colorScheme.onSurface.withOpacity(0.03)
              : null,
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.onSurface.withOpacity(0.06),
            ),
          ),
        ),
        child: Column(
          children: [
            // Row 1: Avatar + Name + Days
            Row(
              children: [
                SizedBox(
                  width: 36, height: 36,
                  child: Stack(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: isDisabled
                              ? Colors.grey.withOpacity(0.15)
                              : daysColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: isDisabled
                              ? const Icon(Icons.block, size: 18, color: Colors.grey)
                              : Text(
                                  subscriber.firstname.isNotEmpty
                                      ? subscriber.firstname[0] : '?',
                                  style: TextStyle(
                                    color: daysColor,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                      if (isOnline && !isDisabled)
                        Positioned(
                          bottom: -1, left: -1,
                          child: Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(
                              color: AppTheme.whatsappGreen,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.scaffoldBackgroundColor,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          subscriber.fullName,
                          style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13,
                            color: isDisabled ? Colors.grey : null,
                            decoration: isDisabled ? TextDecoration.lineThrough : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isDisabled) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4)),
                          child: const Text('معطّل', style: TextStyle(
                              fontSize: 8, fontWeight: FontWeight.w700,
                              color: Colors.red)),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: daysColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isDisabled
                        ? 'معطّل'
                        : subscriber.isExpired
                            ? 'منتهي'
                            : '${subscriber.remainingDays ?? 0} يوم',
                    style: TextStyle(
                      color: daysColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_left, size: 14,
                    color: theme.colorScheme.onSurface.withOpacity(0.15)),
              ],
            ),

            // Row 2: username · package · price · debt
            Padding(
              padding: const EdgeInsets.only(top: 5, right: 46),
              child: Row(
                children: [
                  Text(
                    subscriber.username,
                    style: TextStyle(fontSize: 10,
                        color: theme.colorScheme.onSurface.withOpacity(0.4)),
                  ),
                  if (hasProfile) ...[
                    _dot(theme),
                    Flexible(
                      child: Text(
                        subscriber.profileName!,
                        style: TextStyle(fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary.withOpacity(0.7)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  if (subscriber.price != null &&
                      subscriber.price!.isNotEmpty &&
                      subscriber.price != '0') ...[
                    _dot(theme),
                    Text(
                      AppHelpers.formatMoney(subscriber.price),
                      style: TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface.withOpacity(0.4)),
                    ),
                  ],
                ],
              ),
            ),

            // Row 3: debt (red) or credit (green) or balance
            if (subscriber.hasDebt)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 46),
                child: Row(
                  children: [
                    Icon(Icons.credit_card, size: 11, color: Colors.red.withOpacity(0.6)),
                    const SizedBox(width: 3),
                    Text(
                      'دين: ${AppHelpers.formatMoney(subscriber.debtAmount.abs())}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.red,
                      ),
                    ),
                    if (subscriber.balanceAmount > 0) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.account_balance_wallet, size: 11,
                          color: AppTheme.teal600.withOpacity(0.6)),
                      const SizedBox(width: 3),
                      Text(
                        'رصيد: ${AppHelpers.formatMoney(subscriber.balanceAmount)}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.teal600,
                        ),
                      ),
                    ],
                  ],
                ),
              )
            else if (subscriber.hasCredit)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 46),
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet, size: 11,
                        color: Colors.green.withOpacity(0.6)),
                    const SizedBox(width: 3),
                    Text(
                      'رصيد: +${AppHelpers.formatMoney(subscriber.debtAmount)}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              )
            else if (subscriber.balanceAmount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 46),
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet, size: 11,
                        color: AppTheme.teal600.withOpacity(0.6)),
                    const SizedBox(width: 3),
                    Text(
                      'رصيد: ${AppHelpers.formatMoney(subscriber.balanceAmount)}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.teal600,
                      ),
                    ),
                  ],
                ),
              ),

            // Row 4: Last payment
            if (lastPayment != null) _LastPaymentRow(data: lastPayment!),

            // Row 5: Online details
            if (showOnlineDetails && isOnline && subscriber.ipAddress != null)
              _OnlineRow(subscriber: subscriber),
          ],
        ),
      ),
    ),
    );
  }

  static Widget _dot(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5),
      width: 3, height: 3,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _OnlineRow extends StatelessWidget {
  final SubscriberModel subscriber;
  const _OnlineRow({required this.subscriber});

  void _openInBrowser(String ip) {
    final uri = Uri.parse('http://$ip');
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withOpacity(0.4);
    return Padding(
      padding: const EdgeInsets.only(top: 6, right: 46),
      child: Column(
        children: [
          // IP + Duration
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  final ip = subscriber.ipAddress;
                  if (ip != null && ip.isNotEmpty) _openInBrowser(ip);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lan_rounded, size: 11, color: AppTheme.teal600),
                    const SizedBox(width: 3),
                    Text(subscriber.ipAddress ?? '—',
                        style: const TextStyle(fontSize: 10,
                            color: AppTheme.teal600, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 2),
                    const Icon(Icons.open_in_new_rounded, size: 8, color: AppTheme.teal400),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.timer_outlined, size: 11, color: muted),
              const SizedBox(width: 2),
              Text(SubscriberCard.formatDuration(subscriber.sessionTime),
                  style: TextStyle(fontSize: 10, color: muted, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          // Download + Upload + MAC + Device
          Row(
            children: [
              const Icon(Icons.download_rounded, size: 11, color: AppTheme.teal600),
              const SizedBox(width: 2),
              Text(SubscriberCard.formatBytes(subscriber.downloadBytes),
                  style: const TextStyle(fontSize: 10, color: AppTheme.teal600, fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Icon(Icons.upload_rounded, size: 11, color: AppTheme.infoColor),
              const SizedBox(width: 2),
              Text(SubscriberCard.formatBytes(subscriber.uploadBytes),
                  style: TextStyle(fontSize: 10, color: AppTheme.infoColor, fontWeight: FontWeight.w600)),
              if (subscriber.deviceVendor != null &&
                  subscriber.deviceVendor != 'unknown') ...[
                const Spacer(),
                Text(subscriber.deviceVendor!,
                    style: TextStyle(fontSize: 9, color: muted, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LastPaymentRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _LastPaymentRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final createdAt = data['created_at']?.toString();
    if (createdAt == null) return const SizedBox.shrink();

    final date = DateTime.tryParse(createdAt);
    if (date == null) return const SizedBox.shrink();

    final daysAgo = DateTime.now().difference(date).inDays;
    if (daysAgo > 30) return const SizedBox.shrink();

    final timeLabel = daysAgo == 0 ? 'اليوم' : 'منذ $daysAgo يوم';

    final desc = data['action_description']?.toString() ?? '';
    final amountMatch = RegExp(r'([\d,.-]+)\s*IQD').firstMatch(desc);
    final amountText = amountMatch != null ? '${amountMatch.group(0)}' : '';

    return Padding(
      padding: const EdgeInsets.only(top: 3, right: 46),
      child: Row(
        children: [
          Icon(Icons.monetization_on_rounded, size: 10,
              color: AppTheme.teal600.withOpacity(0.7)),
          const SizedBox(width: 3),
          Text(
            '💰 $timeLabel',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
              color: AppTheme.teal600),
          ),
          if (amountText.isNotEmpty) ...[
            Text(' | ', style: TextStyle(fontSize: 9,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3))),
            Text(amountText, style: TextStyle(fontSize: 9,
              fontWeight: FontWeight.w600, color: AppTheme.teal600)),
          ],
        ],
      ),
    );
  }
}
