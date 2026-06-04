import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/subscribers_api.dart';
import '../../core/util/format.dart';
import '../../models/subscriber.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// Subscriber details — direct port of v1's
/// mobile-app/lib/screens/subscribers/subscriber_details_screen.dart
/// in a v2 visual shell. Sections, in order:
///   1. Header — avatar + status + name + username + close button.
///   2. Top action row — تعديل / تمديد / تفعيل / حذف / اتصال / واتساب
///      (the first 4 are Phase 3+; the last 2 launch tel: / wa.me now).
///   3. Live session (when isOnline) — IP / MAC / session duration +
///      download / upload bytes as stat cards.
///   4. Subscription info — package + price + expiration + remaining
///      days + parent manager.
///   5. Disconnect button (when online + idx known) — calls SAS4 to
///      kick the user off the network. Confirmation dialog first.
class SubscriberDetailScreen extends StatefulWidget {
  const SubscriberDetailScreen({super.key, required this.sub});
  final Subscriber sub;

  @override
  State<SubscriberDetailScreen> createState() =>
      _SubscriberDetailScreenState();
}

class _SubscriberDetailScreenState extends State<SubscriberDetailScreen> {
  late Subscriber sub = widget.sub;
  bool _disconnecting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(sub: sub, onClose: () => Navigator.of(context).pop()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Sp.lg,
                  Sp.md,
                  Sp.lg,
                  Sp.huge * 2,
                ),
                children: [
                  _ActionRow(sub: sub),
                  const SizedBox(height: Sp.md),
                  if (sub.isOnline) ...[
                    _LiveSessionCard(sub: sub),
                    const SizedBox(height: Sp.md),
                  ],
                  _SubscriptionCard(sub: sub),
                  if (sub.balanceAmount != 0) ...[
                    const SizedBox(height: Sp.md),
                    _BalanceCard(sub: sub),
                  ],
                  if (sub.isOnline && sub.idx != null) ...[
                    const SizedBox(height: Sp.lg),
                    _DisconnectButton(
                      busy: _disconnecting,
                      onPressed: _confirmDisconnect,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDisconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('فصل المستخدم',
            style: AppType.label(color: AppColors.textHi)
                .copyWith(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text(
          'سيتم قطع جلسة ${sub.fullName} الحالية من الشبكة. سيحتاج '
          'لإعادة الاتصال يدوياً.',
          style: AppType.subtitle(color: AppColors.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('فصل'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _runDisconnect();
  }

  Future<void> _runDisconnect() async {
    final id = sub.idx;
    if (id == null) return;
    setState(() => _disconnecting = true);
    final success = await SubscribersApi.disconnect(id);
    if (!mounted) return;
    setState(() {
      _disconnecting = false;
      // Optimistic flip — the card list will catch up on next refresh.
      if (success) sub = sub.copyWithOnline(online: false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'تم فصل المستخدم' : 'تعذّر الفصل'),
        backgroundColor: success ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.sub, required this.onClose});
  final Subscriber sub;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(sub);
    final statusLabel = _statusLabel(sub);
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.sm, Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                alignment: Alignment.center,
                child: Icon(_statusIcon(sub), color: statusColor, size: 24),
              ),
              if (sub.isOnline)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.surface, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sub.fullName,
                  style: AppType.title(color: AppColors.textHi).copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(R.pill),
                      ),
                      child: Text(
                        statusLabel,
                        style:
                            AppType.muted(color: statusColor).copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        sub.username,
                        style: AppType.muted(color: AppColors.textLow)
                            .copyWith(
                                fontSize: 12, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x),
            color: AppColors.textMid,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }

  static Color _statusColor(Subscriber s) {
    if (s.isDisabled) return const Color(0xFF6D4C41);
    if (s.isExpired) return AppColors.error;
    if (s.isNearExpiry) return const Color(0xFFE08F2D);
    if (s.isOnline) return const Color(0xFF3B82F6);
    return AppColors.brand;
  }

  static String _statusLabel(Subscriber s) {
    if (s.isDisabled) return 'معطّل';
    if (s.isExpired) return 'منتهي';
    if (s.isNearExpiry) return 'قارب الانتهاء';
    if (s.isOnline) return 'متصل';
    return 'نشط';
  }

  static IconData _statusIcon(Subscriber s) {
    if (s.isDisabled) return LucideIcons.ban;
    if (s.isExpired) return LucideIcons.timerOff;
    if (s.isNearExpiry) return LucideIcons.triangleAlert;
    if (s.isOnline) return LucideIcons.wifi;
    return LucideIcons.circleCheck;
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.sub});
  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    final phone = sub.displayPhone;
    return SizedBox(
      height: 78,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _Action(
            icon: LucideIcons.zap,
            label: 'تفعيل',
            color: AppColors.brand,
            onTap: () => _todo(context, 'تفعيل سريع — قيد التطوير'),
          ),
          _Action(
            icon: LucideIcons.repeat,
            label: 'تمديد',
            color: const Color(0xFF3B82F6),
            onTap: () => _todo(context, 'تمديد — قيد التطوير'),
          ),
          _Action(
            icon: LucideIcons.pencil,
            label: 'تعديل',
            color: const Color(0xFF8B5CF6),
            onTap: () => _todo(context, 'تعديل — قيد التطوير'),
          ),
          _Action(
            icon: LucideIcons.trash2,
            label: 'حذف',
            color: AppColors.error,
            onTap: () => _todo(context, 'حذف — قيد التطوير'),
          ),
          if (phone.isNotEmpty) ...[
            _Action(
              icon: LucideIcons.phone,
              label: 'اتصال',
              color: const Color(0xFF14B8A6),
              onTap: () => _launchUri(context, Uri.parse('tel:$phone')),
            ),
            _Action(
              icon: LucideIcons.messageCircle,
              label: 'واتساب',
              color: const Color(0xFF25D366),
              onTap: () => _launchUri(context,
                  Uri.parse('https://wa.me/${_digits(phone)}')),
            ),
          ],
        ],
      ),
    );
  }

  static String _digits(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  static void _todo(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.textHi,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static Future<void> _launchUri(BuildContext ctx, Uri uri) async {
    final ok = await canLaunchUrl(uri);
    if (!ok) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('لا يمكن فتح الرابط')),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            width: 72,
            padding: const EdgeInsets.symmetric(vertical: Sp.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: AppType.label(color: color).copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveSessionCard extends StatelessWidget {
  const _LiveSessionCard({required this.sub});
  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: LucideIcons.wifi,
      title: 'معلومات الاتصال',
      accent: const Color(0xFF3B82F6),
      children: [
        if ((sub.ipAddress ?? '').isNotEmpty)
          _InfoRow(
            icon: LucideIcons.network,
            label: 'IP',
            value: sub.ipAddress!,
            valueColor: const Color(0xFF3B82F6),
            // Most ONT/router web UIs sit on plain HTTP.
            onTap: () => launchUrl(
              Uri.parse('http://${sub.ipAddress}'),
              mode: LaunchMode.externalApplication,
            ),
            trailing: LucideIcons.externalLink,
          ),
        if (sub.sessionTime != null && sub.sessionTime! > 0)
          _InfoRow(
            icon: LucideIcons.timer,
            label: 'مدة الجلسة',
            value: _formatDuration(sub.sessionTime!),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _BytesCard(
                icon: LucideIcons.download,
                label: 'تحميل',
                bytes: sub.downloadBytes ?? 0,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _BytesCard(
                icon: LucideIcons.upload,
                label: 'رفع',
                bytes: sub.uploadBytes ?? 0,
                color: const Color(0xFF3B82F6),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}س ${m}د';
    return '${m}د';
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.sub});
  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: LucideIcons.package,
      title: 'معلومات الاشتراك',
      accent: AppColors.brand,
      children: [
        _InfoRow(
          icon: LucideIcons.idCard,
          label: 'الباقة',
          value: (sub.profileName?.isNotEmpty ?? false)
              ? sub.profileName!
              : 'بدون باقة',
        ),
        if (sub.price != null)
          _InfoRow(
            icon: LucideIcons.tag,
            label: 'السعر',
            value: '${formatIQD(sub.price!.round())} د.ع',
            valueColor: const Color(0xFFE08F2D),
          ),
        _InfoRow(
          icon: LucideIcons.calendar,
          label: 'تاريخ الانتهاء',
          value: _expirationText(sub.expiration),
        ),
        _InfoRow(
          icon: LucideIcons.clock,
          label: 'الأيام المتبقية',
          value: sub.remainingDays == null
              ? '—'
              : sub.isExpired
                  ? 'منتهي'
                  : '${sub.remainingDays} يوم',
          valueColor: sub.isExpired
              ? AppColors.error
              : sub.isNearExpiry
                  ? const Color(0xFFE08F2D)
                  : AppColors.brand,
        ),
        if ((sub.parentUsername ?? '').isNotEmpty)
          _InfoRow(
            icon: LucideIcons.userCog,
            label: 'تابع إلى',
            value: sub.parentUsername!,
          ),
        if (sub.displayPhone.isNotEmpty)
          _InfoRow(
            icon: LucideIcons.phone,
            label: 'رقم الهاتف',
            value: sub.displayPhone,
            onTap: () => Clipboard.setData(ClipboardData(text: sub.displayPhone)),
            trailing: LucideIcons.copy,
          ),
      ],
    );
  }

  static String _expirationText(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '—';
    final s = raw.trim();
    final t = DateTime.tryParse(s) ?? DateTime.tryParse(s.split(' ').first);
    if (t == null) return s.split(' ').first;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}/${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.sub});
  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    final isDebt = sub.hasDebt;
    final color = isDebt ? AppColors.error : AppColors.brand;
    final label = isDebt ? 'دين على المشترك' : 'رصيد للمشترك';
    return _SectionCard(
      icon: isDebt ? LucideIcons.creditCard : LucideIcons.wallet,
      title: label,
      accent: color,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.sm),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  formatIQD(sub.debtAbs.round()),
                  style: AppType.title(color: color).copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'د.ع',
                  style: AppType.muted(color: AppColors.textMid)
                      .copyWith(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.accent,
    required this.children,
  });

  final IconData icon;
  final String title;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon, color: accent, size: 14),
              ),
              const SizedBox(width: Sp.sm),
              Text(
                title,
                style: AppType.label(color: AppColors.textHi).copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMid, size: 15),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppType.muted(color: AppColors.textMid)
                .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: AppType.label(
                color: valueColor ?? AppColors.textHi,
              ).copyWith(fontSize: 13, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            Icon(trailing, color: AppColors.textLow, size: 13),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.sm),
      child: row,
    );
  }
}

class _BytesCard extends StatelessWidget {
  const _BytesCard({
    required this.icon,
    required this.label,
    required this.bytes,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int bytes;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppType.muted(color: AppColors.textMid)
                    .copyWith(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formatBytes(bytes),
            style: AppType.title(color: color).copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    var v = bytes.toDouble();
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
  }
}

class _DisconnectButton extends StatelessWidget {
  const _DisconnectButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.error,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.md),
          ),
        ),
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(LucideIcons.power, size: 18),
        label: Text(busy ? 'جاري الفصل...' : 'فصل المستخدم'),
      ),
    );
  }
}
