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
  final VoidCallback? onDisconnect;
  final VoidCallback? onPreview;

  const SubscriberCard({
    super.key,
    required this.subscriber,
    this.onTap,
    this.showOnlineDetails = false,
    this.lastPayment,
    this.onDisconnect,
    this.onPreview,
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
    const badgeSize = 18.0;
    const badgeGap = 10.0;
    final badgeIndent = badgeSize + badgeGap;
    final badgeStyle = _resolveBadgeStyle(
      subscriber,
      isOnlinePage: showOnlineDetails,
    );
    final hasProfile = subscriber.profileName != null &&
        subscriber.profileName!.isNotEmpty;
    final hasPhone = subscriber.displayPhone.trim().isNotEmpty;
    final hasExpiration =
        subscriber.expiration != null && subscriber.expiration!.trim().isNotEmpty;
    final hasPrice = subscriber.price != null &&
        subscriber.price!.isNotEmpty &&
        subscriber.price != '0';
    final displayName =
        subscriber.fullName.isNotEmpty ? subscriber.fullName : subscriber.username;
    final showUsernameLine =
        subscriber.username.isNotEmpty && subscriber.username != displayName;

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
                  width: badgeSize,
                  height: badgeSize,
                  child: badgeStyle.isSplit
                      ? _SplitSubscriberBadge(
                          size: badgeSize,
                          leftColor: badgeStyle.primaryColor,
                          rightColor: badgeStyle.secondaryColor!,
                          borderColor: badgeStyle.borderColor,
                          dividerColor: badgeStyle.dividerColor,
                        )
                      : Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: badgeStyle.borderColor,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: badgeStyle.borderColor.withOpacity(0.10),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (badgeStyle.secondaryColor != null)
                            Row(
                              textDirection: TextDirection.ltr,
                              children: [
                                Expanded(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: badgeStyle.primaryColor,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: badgeStyle.secondaryColor!,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    _tintColor(
                                      badgeStyle.primaryColor,
                                      0.18,
                                    ),
                                    badgeStyle.primaryColor,
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          if (badgeStyle.secondaryColor == null)
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: badgeSize * 0.45,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withOpacity(0.20),
                                      Colors.white.withOpacity(0.03),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                          ),
                          Center(
                            child: Text(
                              _badgeLabel(subscriber),
                              style: TextStyle(
                                color: badgeStyle.foregroundColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 9,
                                height: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: badgeGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
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
                      if (showUsernameLine) ...[
                        const SizedBox(height: 2),
                        Text(
                          subscriber.username,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: isDisabled
                                ? Colors.grey
                                : theme.colorScheme.onSurface.withOpacity(0.5),
                            decoration:
                                isDisabled ? TextDecoration.lineThrough : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (!showOnlineDetails) ...[
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
                              : _formatRemaining(subscriber),
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
              ],
            ),

            // Row 2: package/price chips
            Padding(
              padding: EdgeInsets.only(top: 5, right: badgeIndent),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (hasProfile) ...[
                    _metaChip(
                      theme: theme,
                      icon: Icons.wifi_rounded,
                      text: subscriber.profileName!,
                      iconColor: isDisabled ? Colors.grey : AppTheme.primary,
                      textColor: isDisabled ? Colors.grey : AppTheme.primary,
                      backgroundColor: isDisabled
                          ? Colors.grey.withOpacity(0.08)
                          : AppTheme.primary.withOpacity(0.10),
                      borderColor: isDisabled
                          ? Colors.grey.withOpacity(0.12)
                          : AppTheme.primary.withOpacity(0.18),
                    ),
                  ],
                  if (hasPrice) ...[
                    _metaChip(
                      theme: theme,
                      icon: Icons.sell_outlined,
                      text: AppHelpers.formatMoney(subscriber.price),
                      iconColor: isDisabled ? Colors.grey : AppTheme.warningColor,
                      textColor: isDisabled ? Colors.grey : AppTheme.warningColor,
                      backgroundColor: isDisabled
                          ? Colors.grey.withOpacity(0.08)
                          : AppTheme.warningColor.withOpacity(0.10),
                      borderColor: isDisabled
                          ? Colors.grey.withOpacity(0.12)
                          : AppTheme.warningColor.withOpacity(0.18),
                    ),
                  ],
                ],
              ),
            ),

            // Row 3: phone + expiration
            if (hasPhone || hasExpiration)
              Padding(
                padding: EdgeInsets.only(top: 6, right: badgeIndent),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (hasExpiration)
                      _metaChip(
                        theme: theme,
                        icon: Icons.event_outlined,
                        text: AppHelpers.formatExpiration(subscriber.expiration),
                        iconColor: isDisabled ? Colors.grey : daysColor,
                        isLtr: true,
                      ),
                    if (hasPhone)
                      _metaChip(
                        theme: theme,
                        icon: Icons.phone_outlined,
                        text: AppHelpers.formatPhone(subscriber.displayPhone),
                        iconColor: AppTheme.infoColor,
                        isLtr: true,
                      ),
                  ],
                ),
              ),

            // Row 4: debt (red) or credit (green) or balance
            if (subscriber.hasDebt)
              Padding(
                padding: EdgeInsets.only(top: 4, right: badgeIndent),
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
                  ],
                ),
              )
            else if (subscriber.hasCredit)
              Padding(
                padding: EdgeInsets.only(top: 4, right: badgeIndent),
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
              ),

            // Row 5: Last payment
            if (lastPayment != null) _LastPaymentRow(data: lastPayment!),

            // Row 6: Online details + action buttons
            if (showOnlineDetails && isOnline)
              _OnlineRow(
                subscriber: subscriber,
                onDisconnect: onDisconnect,
                onPreview: onPreview,
              ),
          ],
        ),
      ),
    ),
    );
  }

  static String _formatRemaining(SubscriberModel sub) {
    final days = sub.remainingDays ?? 0;
    if (days > 0) return '$days يوم';
    // remaining_days = 0 → نحسب الساعات/الدقائق من تاريخ الانتهاء
    if (sub.expiration != null && sub.expiration!.isNotEmpty) {
      try {
        final expStr = sub.expiration!.trim();
        DateTime? expDate;
        if (expStr.contains('T') || expStr.contains('+')) {
          expDate = DateTime.tryParse(expStr);
        } else {
          expDate = DateTime.tryParse('${expStr.replaceAll(' ', 'T')}+03:00');
        }
        if (expDate != null) {
          final diff = expDate.difference(DateTime.now());
          if (diff.isNegative) return 'منتهي';
          final hours = diff.inHours;
          final minutes = diff.inMinutes % 60;
          if (hours > 0) return '$hours س $minutes د';
          if (minutes > 0) return '$minutes دقيقة';
          return 'ينتهي الآن';
        }
      } catch (_) {}
    }
    return '0 يوم';
  }

  static String _badgeLabel(SubscriberModel sub) {
    final firstName = sub.firstname.trim();
    if (firstName.isNotEmpty) return firstName[0];
    final username = sub.username.trim();
    if (username.isNotEmpty) return username[0];
    return '?';
  }

  static _SubscriberBadgeStyle _resolveBadgeStyle(
    SubscriberModel sub, {
    required bool isOnlinePage,
  }) {
    if (isOnlinePage && sub.isExpired && sub.isOnline) {
      return const _SubscriberBadgeStyle(
        primaryColor: Color(0xFF8B5CF6),
        borderColor: Color(0xFF7C3AED),
        foregroundColor: Colors.white,
      );
    }

    if (sub.isExpired && sub.isOnline) {
      return const _SubscriberBadgeStyle(
        primaryColor: Color(0xFFF59E0B),
        secondaryColor: Color(0xFF2563EB),
        borderColor: Color(0xFFD4D9E1),
        foregroundColor: Colors.white,
        dividerColor: Color(0xFFF8FAFC),
        isSplit: true,
      );
    }

    if (sub.isExpired) {
      return const _SubscriberBadgeStyle(
        primaryColor: Color(0xFFF59E0B),
        borderColor: Color(0xFFE38906),
        foregroundColor: Colors.white,
      );
    }

    if (sub.isOnline) {
      return const _SubscriberBadgeStyle(
        primaryColor: Color(0xFF2563EB),
        borderColor: Color(0xFF1D4ED8),
        foregroundColor: Colors.white,
      );
    }

    return const _SubscriberBadgeStyle(
      primaryColor: Color(0xFF22A06B),
      borderColor: Color(0xFF19784E),
      foregroundColor: Colors.white,
    );
  }

  static Widget _metaChip({
    required ThemeData theme,
    required IconData icon,
    required String text,
    required Color iconColor,
    Color? textColor,
    Color? backgroundColor,
    Color? borderColor,
    bool isLtr = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.onSurface.withOpacity(0.035),
        borderRadius: BorderRadius.circular(8),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: iconColor),
          const SizedBox(width: 5),
          Text(
            text,
            textDirection: isLtr ? TextDirection.ltr : null,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: textColor ?? theme.colorScheme.onSurface.withOpacity(0.55),
            ),
          ),
        ],
      ),
    );
  }

  static Color _tintColor(Color color, double amount) {
    return Color.lerp(color, Colors.white, amount) ?? color;
  }
}

class _SubscriberBadgeStyle {
  final Color primaryColor;
  final Color? secondaryColor;
  final Color borderColor;
  final Color foregroundColor;
  final Color dividerColor;
  final bool isSplit;

  const _SubscriberBadgeStyle({
    required this.primaryColor,
    this.secondaryColor,
    required this.borderColor,
    required this.foregroundColor,
    this.dividerColor = const Color(0xFFF8FAFC),
    this.isSplit = false,
  });
}

class _SplitSubscriberBadge extends StatelessWidget {
  final double size;
  final Color leftColor;
  final Color rightColor;
  final Color borderColor;
  final Color dividerColor;

  const _SplitSubscriberBadge({
    required this.size,
    required this.leftColor,
    required this.rightColor,
    required this.borderColor,
    required this.dividerColor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: borderColor.withOpacity(0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Row(
              textDirection: TextDirection.ltr,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ColoredBox(
                    color: leftColor,
                  ),
                ),
                ColoredBox(
                  color: dividerColor.withOpacity(0.75),
                  child: const SizedBox(width: 1),
                ),
                Expanded(
                  child: ColoredBox(
                    color: rightColor,
                  ),
                ),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: size * 0.42,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.18),
                        Colors.white.withOpacity(0.03),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlineRow extends StatelessWidget {
  final SubscriberModel subscriber;
  final VoidCallback? onDisconnect;
  final VoidCallback? onPreview;
  const _OnlineRow({required this.subscriber, this.onDisconnect, this.onPreview});

  void _openInBrowser(String ip) {
    final uri = Uri.parse('http://$ip');
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withOpacity(0.4);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Info section (right side in RTL)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                          const Icon(Icons.lan_rounded, size: 12, color: AppTheme.teal600),
                          const SizedBox(width: 4),
                          Text(subscriber.ipAddress ?? '—',
                              style: const TextStyle(fontSize: 11,
                                  color: AppTheme.teal600, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 3),
                          const Icon(Icons.open_in_new_rounded, size: 9, color: AppTheme.teal400),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Icon(Icons.timer_outlined, size: 12, color: muted),
                    const SizedBox(width: 3),
                    Text(SubscriberCard.formatDuration(subscriber.sessionTime),
                        style: TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 5),
                // Download + Upload
                Row(
                  children: [
                    const Icon(Icons.download_rounded, size: 12, color: AppTheme.teal600),
                    const SizedBox(width: 3),
                    Text(SubscriberCard.formatBytes(subscriber.downloadBytes),
                        style: const TextStyle(fontSize: 11, color: AppTheme.teal600, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 14),
                    Icon(Icons.upload_rounded, size: 12, color: AppTheme.infoColor),
                    const SizedBox(width: 3),
                    Text(SubscriberCard.formatBytes(subscriber.uploadBytes),
                        style: TextStyle(fontSize: 11, color: AppTheme.infoColor, fontWeight: FontWeight.w600)),
                    if (subscriber.deviceVendor != null &&
                        subscriber.deviceVendor != 'unknown') ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(subscriber.deviceVendor!,
                            style: TextStyle(fontSize: 9, color: muted),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Disconnect button (left side in RTL)
          if (onDisconnect != null) ...[
            const SizedBox(width: 10),
            _ActionBtn(
              icon: Icons.power_settings_new_rounded,
              label: 'فصل',
              color: Colors.red,
              onTap: onDisconnect!,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color,
            )),
          ],
        ),
      ),
    );
  }
}

class _LastPaymentRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _LastPaymentRow({required this.data});

  String _movementLabel() {
    final explicit = data['movement_label']?.toString().trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final actionType = data['action_type']?.toString();
    final paymentType = data['payment_type']?.toString() ?? '';
    if (actionType == 'SUBSCRIBER_ACTIVATE') {
      return paymentType.contains('جزئي') ? 'تفعيل نقدي جزئي' : 'تفعيل نقدي';
    }
    return 'تسديد دين';
  }

  String _amountText() {
    final rawAmount = data['amount'];
    final amountValue = rawAmount is num
        ? rawAmount.toDouble()
        : double.tryParse(rawAmount?.toString() ?? '');
    if (amountValue != null && amountValue > 0) {
      return '${AppHelpers.formatMoney(amountValue)} IQD';
    }

    final desc = data['action_description']?.toString() ?? '';
    return RegExp(r'([\d,.-]+)\s*IQD').firstMatch(desc)?.group(0) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final createdAt = data['created_at']?.toString();
    if (createdAt == null) return const SizedBox.shrink();

    final date = DateTime.tryParse(createdAt);
    if (date == null) return const SizedBox.shrink();

    final daysAgo = DateTime.now().difference(date).inDays;
    if (daysAgo > 30) return const SizedBox.shrink();

    final timeLabel = daysAgo == 0 ? 'اليوم' : 'منذ $daysAgo يوم';
    final movementLabel = _movementLabel();
    final amountText = _amountText();

    return Padding(
      padding: const EdgeInsets.only(top: 3, right: 46),
      child: Row(
        children: [
          Icon(Icons.monetization_on_rounded, size: 10,
              color: AppTheme.teal600.withOpacity(0.7)),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              '$movementLabel | $timeLabel${amountText.isNotEmpty ? ' | $amountText' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                color: AppTheme.teal600),
            ),
          ),
        ],
      ),
    );
  }
}
