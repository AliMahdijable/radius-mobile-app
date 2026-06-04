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

/// Subscriber details — v2 visual shell over v1's structure. Layout
/// top→bottom (info → operations):
///   1. Header — avatar + status + name + username + close.
///   2. Live session card (when online) — IP / MAC / duration + DL/UL.
///   3. Subscription card — package + price + expiry + parent + phone.
///   4. Balance hero card (when non-zero).
///   5. Operations card AT THE BOTTOM — every action v1 surfaces in
///      its FAB sheet, in a single 3-column grid: تعديل / تفعيل /
///      تمديد / إضافة دين / تسديد دين / خصم سريع / سجل الحركات /
///      تذكير دين / تذكير انتهاء / توليد رابط / إرسال المعلومات /
///      حذف / تعطيل-تفعيل حساب / اتصال / واتساب / فصل المستخدم.
///
/// Info cards are intentionally tight (smaller padding, 4px row gaps)
/// so the operations grid has room to breathe without scrolling on
/// most phones.
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
                  Sp.sm,
                  Sp.lg,
                  Sp.huge,
                ),
                children: [
                  if (sub.isOnline) ...[
                    _LiveSessionCard(sub: sub),
                    const SizedBox(height: Sp.sm),
                  ],
                  _SubscriptionCard(sub: sub),
                  if (sub.balanceAmount != 0) ...[
                    const SizedBox(height: Sp.sm),
                    _BalanceCard(sub: sub),
                  ],
                  const SizedBox(height: Sp.md),
                  _OperationsCard(
                    sub: sub,
                    disconnecting: _disconnecting,
                    onDisconnect: sub.isOnline && sub.idx != null
                        ? _confirmDisconnect
                        : null,
                  ),
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
        title: Text(
          'فصل المستخدم',
          style: AppType.label(color: AppColors.textHi)
              .copyWith(fontSize: 16, fontWeight: FontWeight.w800),
        ),
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
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: statusColor.withValues(alpha: 0.3)),
                ),
                alignment: Alignment.center,
                child: Icon(_statusIcon(sub), color: statusColor, size: 22),
              ),
              if (sub.isOnline)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: AppColors.surface, width: 2),
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
                    fontSize: 16,
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
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(R.pill),
                      ),
                      child: Text(
                        statusLabel,
                        style: AppType.muted(color: statusColor).copyWith(
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
                                fontSize: 11, fontWeight: FontWeight.w500),
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
            icon: const Icon(LucideIcons.x, size: 20),
            color: AppColors.textMid,
            visualDensity: VisualDensity.compact,
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
        const SizedBox(height: 4),
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
            const SizedBox(width: 6),
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
            onTap: () =>
                Clipboard.setData(ClipboardData(text: sub.displayPhone)),
            trailing: LucideIcons.copy,
          ),
        // 'آخر اتصال' for offline subscribers. v1 fetches the precise
        // last-session timestamp from SAS4's encrypted /index/UserSessions
        // endpoint — without client-side encryption in v2, the best we
        // can do until a backend wrapper lands is fall back to the
        // expiry-derived signal. Shown only for offline rows so the
        // live session block doesn't have a redundant 'آخر اتصال'.
        if (!sub.isOnline)
          _InfoRow(
            icon: LucideIcons.history,
            label: 'آخر اتصال',
            value: _lastSeenText(sub),
            valueColor: AppColors.textMid,
          ),
      ],
    );
  }

  static String _lastSeenText(Subscriber s) {
    // Best-effort: when SAS4 isn't giving us a last-session ts, infer
    // a coarse signal from the expiration field. If the sub is expired,
    // last contact was at-or-before the expiry; otherwise we don't know
    // precisely and surface 'غير متاح'.
    if (!s.isExpired) return 'غير متاح';
    final raw = s.expiration?.trim();
    if (raw == null || raw.isEmpty) return 'غير معروف';
    final t = DateTime.tryParse(raw) ??
        DateTime.tryParse(raw.split(' ').first);
    if (t == null) return raw.split(' ').first;
    final diff = DateTime.now().difference(t);
    if (diff.inDays > 365) return 'منذ أكثر من سنة';
    if (diff.inDays > 30) return 'منذ ${(diff.inDays / 30).round()} شهر';
    if (diff.inDays > 0) return 'منذ ${diff.inDays} يوم';
    if (diff.inHours > 0) return 'منذ ${diff.inHours} س';
    return 'منذ دقائق';
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
          padding: const EdgeInsets.only(top: 2, bottom: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatIQD(sub.debtAbs.round()),
                style: AppType.title(color: color).copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'د.ع',
                style: AppType.muted(color: AppColors.textMid)
                    .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Dedicated operations card at the bottom — every action v1 surfaces
/// in its FAB sheet, rendered as a 3-column grid of small tinted
/// chips. Stubbed actions snack 'قيد التطوير' until the matching
/// sheet/dialog is built in the later phases; live actions (call,
/// WhatsApp, disconnect) are wired now.
class _OperationsCard extends StatelessWidget {
  const _OperationsCard({
    required this.sub,
    required this.disconnecting,
    required this.onDisconnect,
  });

  final Subscriber sub;
  final bool disconnecting;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final phone = sub.displayPhone;
    final ops = <_Op>[
      _Op(LucideIcons.pencil, 'تعديل', const Color(0xFF2D5F47),
          () => _todo(context, 'تعديل — قيد التطوير (مرحلة 4)')),
      _Op(LucideIcons.zap, 'تفعيل', const Color(0xFF14B8A6),
          () => _todo(context, 'تفعيل — قيد التطوير (مرحلة 3)')),
      _Op(LucideIcons.repeat, 'تمديد', const Color(0xFF3B82F6),
          () => _todo(context, 'تمديد — قيد التطوير (مرحلة 3)')),
      _Op(LucideIcons.plus, 'إضافة دين', const Color(0xFFE08F2D),
          () => _todo(context, 'إضافة دين — قيد التطوير (مرحلة 3)')),
      if (sub.hasDebt)
        _Op(LucideIcons.banknote, 'تسديد دين', Colors.green,
            () => _todo(context, 'تسديد دين — قيد التطوير (مرحلة 3)')),
      _Op(LucideIcons.tag, 'خصم سريع', const Color(0xFF14B8A6),
          () => _todo(context, 'خصم سريع — قيد التطوير (مرحلة 3)')),
      _Op(LucideIcons.history, 'سجل الحركات', const Color(0xFF26A69A),
          () => _todo(context, 'سجل الحركات — قيد التطوير')),
      if (sub.hasDebt)
        _Op(LucideIcons.bellRing, 'تذكير دين', Colors.orange,
            () => _todo(context, 'تذكير دين — قيد التطوير')),
      if (sub.isNearExpiry)
        _Op(LucideIcons.alarmClock, 'تذكير انتهاء', Colors.deepOrange,
            () => _todo(context, 'تذكير انتهاء — قيد التطوير')),
      _Op(LucideIcons.link, 'توليد رابط', Colors.indigo,
          () => _todo(context, 'توليد رابط — قيد التطوير')),
      _Op(LucideIcons.info, 'إرسال المعلومات', Colors.blueAccent,
          () => _todo(context, 'إرسال المعلومات — قيد التطوير')),
      _Op(
        sub.isDisabled ? LucideIcons.circleCheck : LucideIcons.ban,
        sub.isDisabled ? 'تفعيل حساب' : 'تعطيل',
        sub.isDisabled ? Colors.green : const Color(0xFFE08F2D),
        () => _todo(context,
            '${sub.isDisabled ? 'تفعيل' : 'تعطيل'} — قيد التطوير'),
      ),
      _Op(LucideIcons.trash2, 'حذف', AppColors.error,
          () => _todo(context, 'حذف — قيد التطوير (مرحلة 4)')),
      if (phone.isNotEmpty)
        _Op(LucideIcons.phone, 'اتصال', const Color(0xFF14B8A6),
            () => _launchUri(context, Uri.parse('tel:$phone'))),
      if (phone.isNotEmpty)
        _Op(
          LucideIcons.messageCircle,
          'واتساب',
          const Color(0xFF25D366),
          () => _launchUri(
              context, Uri.parse('https://wa.me/${_digits(phone)}')),
        ),
      if (sub.isOnline && sub.idx != null)
        _Op(LucideIcons.power, disconnecting ? 'جاري الفصل' : 'فصل المستخدم',
            AppColors.error, onDisconnect ?? () {}),
    ];

    return _SectionCard(
      icon: LucideIcons.layers,
      title: 'العمليات',
      accent: AppColors.brand,
      children: [
        // Tiles laid out as a wrap of pills. Each pill is icon + label
        // inline horizontally; sizes match the chips at the top of the
        // subscribers list filter bar (~28px tall). Much smaller than
        // the previous grid tiles — fits 16+ actions in 4-5 rows.
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final op in ops) _OpChip(op: op),
          ],
        ),
      ],
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

class _Op {
  const _Op(this.icon, this.label, this.color, this.onTap);
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// Small inline pill — icon + label on one row. Sized like the filter
/// chips on the subscribers list bar so a 16-action grid fits in 4-5
/// rows without dominating the screen.
class _OpChip extends StatelessWidget {
  const _OpChip({required this.op});
  final _Op op;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: op.color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(R.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          op.onTap();
        },
        borderRadius: BorderRadius.circular(R.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(color: op.color.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(op.icon, color: op.color, size: 13),
              const SizedBox(width: 5),
              Text(
                op.label,
                style: AppType.label(color: op.color).copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
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
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.sm),
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
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon, color: accent, size: 12),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: AppType.label(color: AppColors.textHi).copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMid, size: 13),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppType.muted(color: AppColors.textMid)
                .copyWith(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: AppType.label(
                color: valueColor ?? AppColors.textHi,
              ).copyWith(fontSize: 12, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            Icon(trailing, color: AppColors.textLow, size: 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
              Icon(icon, color: color, size: 11),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppType.muted(color: AppColors.textMid)
                    .copyWith(fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _formatBytes(bytes),
            style: AppType.title(color: color).copyWith(
              fontSize: 13,
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
