import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/util/format.dart';
import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'device_chip_micro.dart';

/// Subscriber card v2 — banking-app style with a colored leading rail
/// for status, an avatar with the first initial, a hero name + handle,
/// and a prominent days-remaining badge on the right. Below that, two
/// metadata rows (package/phone, expiration) and an optional finance
/// strip with a debt/credit chip + last-payment line.
class SubscriberCardV2 extends StatefulWidget {
  const SubscriberCardV2({
    super.key,
    required this.sub,
    required this.selected,
    this.lastPayment,
    this.showLiveSession = false,
    required this.onTap,
    required this.onLongPress,
    this.onShowConsumption,
    this.onDisconnect,
    this.collapsedAll = false,
  });

  final Subscriber sub;
  final bool selected;
  final Map<String, dynamic>? lastPayment;
  /// Surfaces IP / session / DL / UL / device on the card. v1 only
  /// shows this row on the 'متصل' filter — the general list stays
  /// scannable without per-row network noise.
  final bool showLiveSession;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  /// مطلب 2026-06-11: زرّا الاستهلاك والفصل أسفل كل صف في تاب
  /// "متصل". null = الزر يختفي (مستخدم في كل التابات الأخرى).
  final VoidCallback? onShowConsumption;
  final VoidCallback? onDisconnect;
  /// مطلب 2026-06-11: زر تكويل عام في الـtoolbar فوق القائمة يطبّق
  /// حالة "مكوّل" على كل البطاقات معاً. didUpdateWidget يعيد سنكروز
  /// _expanded عند تغيّر القيمة فالكل ينطبق فوراً. الـchevron الفردي
  /// يبقى يعمل كـoverride بعد ذلك.
  final bool collapsedAll;

  @override
  State<SubscriberCardV2> createState() => _SubscriberCardV2State();
}

class _SubscriberCardV2State extends State<SubscriberCardV2> {
  /// مطلب 2026-06-11: سهم تكويل يخفي قسم الاتصال (live session +
  /// device chip + الأزرار + balance + last payment). الـheader
  /// (الاسم + الحالة + الأيام) + الـmetadata (الباقة + الهاتف +
  /// الانتهاء) يبقون مرئيين دائماً.
  late bool _expanded = !widget.collapsedAll;

  @override
  void didUpdateWidget(SubscriberCardV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Global toggle changed → resync this card. الـuser لو ضغط chevron
    // البطاقة بعد ذلك، يتجاوز الإعداد العام للبطاقة فقط.
    if (oldWidget.collapsedAll != widget.collapsedAll) {
      _expanded = !widget.collapsedAll;
    }
  }

  // Getters عشان كود البناء يبقى يقرأ `sub`/`lastPayment` مباشرة
  // (ما نحتاج نعدل كل reference لإضافة widget.).
  Subscriber get sub => widget.sub;
  bool get selected => widget.selected;
  Map<String, dynamic>? get lastPayment => widget.lastPayment;
  bool get showLiveSession => widget.showLiveSession;
  VoidCallback get onTap => widget.onTap;
  VoidCallback get onLongPress => widget.onLongPress;
  VoidCallback? get onShowConsumption => widget.onShowConsumption;
  VoidCallback? get onDisconnect => widget.onDisconnect;

  @override
  Widget build(BuildContext context) {
    final disabled = sub.isDisabled;
    final statusColor = _statusColor();
    final statusLabel = _statusLabel();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(R.lg),
        child: Opacity(
          opacity: disabled ? 0.62 : 1,
          child: Container(
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.brand.withValues(alpha: 0.05)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(
                color: selected
                    ? AppColors.brand
                    : AppColors.border,
                width: selected ? 2 : 1,
              ),
              boxShadow: selected
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status accent rail (right edge in RTL = leading)
                  Container(
                    width: 4,
                    color: statusColor,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Sp.md, Sp.md, Sp.md, Sp.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(statusColor, statusLabel, disabled),
                          const SizedBox(height: 10),
                          _buildMetadata(),
                          // مطلب 2026-06-11: قسم الاتصال (live session +
                          // balance + last payment) يطوى عند الضغط على
                          // chevron الـheader. AnimatedSize يتنعّم
                          // الانتقال 220ms بدلاً من قفز فجائي.
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            alignment: Alignment.topCenter,
                            child: (_expanded && _hasFinance)
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 10),
                                      const Divider(
                                        height: 1,
                                        color: AppColors.border,
                                      ),
                                      const SizedBox(height: 8),
                                      _buildFinance(),
                                    ],
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ───────── HEADER: status icon badge + name + handle + expiry pill ─────────
  Widget _buildHeader(Color statusColor, String statusLabel, bool disabled) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _StatusIconBadge(icon: _statusIcon(), color: statusColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                sub.fullName,
                style: AppType.label(color: AppColors.textHi).copyWith(
                  fontSize: 14, // Section title tier
                  fontWeight: FontWeight.w800,
                  decoration:
                      disabled ? TextDecoration.lineThrough : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  // Status dot
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    statusLabel,
                    style: AppType.muted(color: statusColor).copyWith(
                      fontSize: 11, // Caption tier (was 10)
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (sub.fullName != sub.username) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 2,
                      height: 10,
                      color: AppColors.border,
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
                ],
              ),
            ],
          ),
        ),
        _ExpiryBadge(
          remaining: sub.remainingDays,
          expiration: sub.parsedExpiration,
          disabled: disabled,
        ),
        // مطلب 2026-06-11: سهم تكويل بعد الـExpiryBadge — يظهر
        // فقط لو في فعلاً قسم اتصال يمكن طيّه (live/balance/lastPay)،
        // غير ذلك ميمكن نطوي شي فيختفي.
        if (_hasFinance) ...[
          const SizedBox(width: 4),
          InkResponse(
            onTap: () => setState(() => _expanded = !_expanded),
            radius: 18,
            child: AnimatedRotation(
              turns: _expanded ? 0 : 0.5,
              duration: const Duration(milliseconds: 200),
              child: const Icon(
                Icons.keyboard_arrow_up_rounded,
                color: AppColors.textMid,
                size: 22,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ───────── METADATA: package + price chip / phone, then expiry ─────────
  Widget _buildMetadata() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: package name (with price chip beside it if known) +
        // phone on the trailing side.
        Row(
          children: [
            Flexible(
              child: _PackageWithPrice(
                name: (sub.profileName?.isNotEmpty ?? false)
                    ? sub.profileName!
                    : 'بدون باقة',
                price: sub.price,
                discount: sub.discount,
              ),
            ),
            if (sub.displayPhone.isNotEmpty) ...[
              const SizedBox(width: 8),
              _MetaRow(
                icon: LucideIcons.phone,
                text: sub.displayPhone,
                color: AppColors.textMid,
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        _MetaRow(
          icon: LucideIcons.calendar,
          text: 'ينتهي ${_formatExpiration(sub.expiration)}',
          color: AppColors.textLow,
        ),
      ],
    );
  }

  // Decide if there's any content under the divider — the divider
  // shouldn't draw if we're not going to render anything.
  bool get _hasFinance =>
      (showLiveSession && sub.isOnline) ||
      sub.balanceAmount != 0 ||
      lastPayment != null;

  // ───────── FINANCE: debt/credit chip + last-payment line ─────────
  Widget _buildFinance() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Live session row (online subscribers) — IP + duration + DL/UL
        // + device vendor. Mirrors v1's
        // mobile-app/lib/widgets/subscriber_card.dart:595-647.
        if (showLiveSession && sub.isOnline) ...[
          _LiveSessionRow(sub: sub),
          // مطلب 2026-06-11: سطر معلومات الجهاز كامل تحت السطر الحي —
          // RX+حرارة للـONT، إشارة+CCQ+LAN للـUBNT — + زر تحديث 36×36
          // يحرك probe لهذا المشترك فقط. AnimatedSwitcher يضمن
          // ظهوراً ناعماً لما الـwave يكمل الفحص.
          DeviceChipMicro(
            ip: sub.ipAddress,
            username: sub.username,
          ),
          // مطلب 2026-06-11: زرّا الاستهلاك + فصل المستخدم بتصميم
          // ناعم — نص صغير + أيقونة، شبه شفاف، لا حدود قوية ولا
          // ملء ملفت. مرتب يمين السطر فما يحجب الـmetrics على شماله.
          if (onShowConsumption != null || onDisconnect != null) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                if (onShowConsumption != null)
                  _GhostAction(
                    icon: LucideIcons.chartLine,
                    label: 'الاستهلاك',
                    color: const Color(0xFF3B82F6),
                    onTap: onShowConsumption!,
                  ),
                const SizedBox(width: 4),
                if (onDisconnect != null)
                  _GhostAction(
                    icon: LucideIcons.powerOff,
                    label: 'فصل',
                    color: AppColors.error,
                    onTap: onDisconnect!,
                  ),
                const Spacer(),
              ],
            ),
          ],
          if (sub.balanceAmount != 0 || lastPayment != null)
            const SizedBox(height: 4),
        ],
        if (sub.balanceAmount != 0) _BalanceChip(sub: sub),
        if (sub.balanceAmount != 0 && lastPayment != null)
          const SizedBox(height: 4),
        if (lastPayment != null) _LastPaymentLine(payment: lastPayment!),
      ],
    );
  }

  // ───────── status visual (1:1 from v1 _resolveStatusVisual) ─────────
  // mobile-app/lib/widgets/subscriber_card.dart:478-520. 7 combinations:
  //   disabled             → ban       slate-400
  //   online + expired     → wifi      purple-500   ← 'متصل ومنتهي'
  //   online + nearExpiry  → wifi      amber-500
  //   online + active      → wifi      blue-600
  //   offline + expired    → wifiOff   red-500
  //   offline + nearExpiry → wifiOff   amber-500
  //   offline + active     → wifiOff   emerald-500
  Color _statusColor() {
    if (sub.isDisabled) return const Color(0xFF94A3B8); // slate-400
    if (sub.isOnline) {
      if (sub.isExpired) return const Color(0xFF8B5CF6); // purple-500
      if (sub.isNearExpiry) return const Color(0xFFF59E0B); // amber-500
      return const Color(0xFF2563EB); // blue-600
    }
    if (sub.isExpired) return const Color(0xFFEF4444); // red-500
    if (sub.isNearExpiry) return const Color(0xFFF59E0B); // amber-500
    return const Color(0xFF10B981); // emerald-500
  }

  String _statusLabel() {
    if (sub.isDisabled) return 'معطّل';
    if (sub.isOnline) {
      if (sub.isExpired) return 'متصل / منتهي';
      if (sub.isNearExpiry) return 'متصل / قارب';
      return 'متصل';
    }
    if (sub.isExpired) return 'منتهي';
    if (sub.isNearExpiry) return 'قارب الانتهاء';
    return 'نشط';
  }

  IconData _statusIcon() {
    if (sub.isDisabled) return LucideIcons.ban;
    return sub.isOnline ? LucideIcons.wifi : LucideIcons.wifiOff;
  }

  /// Formats SAS4's expiration string ('2026-09-30 00:00:00' or
  /// '2026-09-30') to 'YYYY/MM/DD HH:MM'. Returns '—' for null/empty.
  static String _formatExpiration(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '—';
    final s = raw.trim();
    final t = DateTime.tryParse(s) ?? DateTime.tryParse(s.split(' ').first);
    if (t == null) return s.split(' ').first;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}/${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

/// Status icon badge — the card's identity at-a-glance. The icon
/// reflects the subscriber's primary state (online/active/near-expiry/
/// expired/disabled) and the background ties to the same color as the
/// trailing badge + accent rail.
class _StatusIconBadge extends StatelessWidget {
  const _StatusIconBadge({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 20),
    );
  }
}

/// Big days-remaining badge on the trailing side. The card's main
/// urgency signal — color-coded so a red badge instantly tells you
/// there's a problem before you read anything else.
class _ExpiryBadge extends StatelessWidget {
  const _ExpiryBadge({
    required this.remaining,
    required this.expiration,
    required this.disabled,
  });
  final int? remaining;
  /// Parsed expiration timestamp. Used when [remaining]==0 so we can
  /// switch the badge from a useless 'اليوم'/'0 يوم' to the actual
  /// hours/minutes left — admins want to know if the sub expires in
  /// 5 hours or 30 minutes.
  final DateTime? expiration;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final ({Color color, String big, String small, IconData icon}) v;
    if (disabled) {
      v = (
        color: const Color(0xFF6D4C41),
        big: '—',
        small: 'معطّل',
        icon: LucideIcons.ban,
      );
    } else if (remaining == null) {
      v = (
        color: AppColors.textLow,
        big: '—',
        small: '',
        icon: LucideIcons.clock,
      );
    } else if (remaining! < 0) {
      // مطلب 2026-06-11: المنتهي يظهر 'منذ X يوم' بدل '0 منتهي'
      // (المدير يحتاج يعرف كم صار له منتهي عشان يقرر يتابعه أو يحذفه).
      v = (
        color: AppColors.error,
        big: 'منذ',
        small: '${remaining!.abs()} يوم',
        icon: LucideIcons.timerOff,
      );
    } else if (remaining! == 0) {
      // Same-day expiry. Check expiration timestamp — if past, this is
      // actually expired (SAS4 rounds to 0 for any value < 24h). Show
      // 'منذ ساعة/دقيقة' so the admin distinguishes from 'باقي ساعة'.
      final hm = _hoursMinutesUntil(expiration);
      v = (
        color: AppColors.error,
        big: hm.$1,
        small: hm.$2,
        icon: LucideIcons.triangleAlert,
      );
    } else if (remaining! <= 3) {
      v = (
        color: const Color(0xFFE08F2D),
        big: '${remaining!}',
        small: 'يوم',
        icon: LucideIcons.triangleAlert,
      );
    } else if (remaining! <= 7) {
      v = (
        color: const Color(0xFFCD8B00),
        big: '${remaining!}',
        small: 'يوم',
        icon: LucideIcons.clock,
      );
    } else {
      v = (
        color: AppColors.brand,
        big: '${remaining!}',
        small: 'يوم',
        icon: LucideIcons.clock,
      );
    }

    return Container(
      // مطلب 2026-06-11: الـbadge كان كبير جداً ع الكرت. خفّضنا
      // الـpadding من 10×6 إلى 7×4 + الـicon من 14 إلى 11 +
      // الفونت 14→11 / 9.5→8.5 فيتقلّص ~30% بدون فقدان قراءة.
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: v.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: v.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(v.icon, color: v.color, size: 11),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                v.big,
                style: AppType.title(color: v.color).copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              if (v.small.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(
                  v.small,
                  style: AppType.muted(color: v.color).copyWith(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Returns `(big, small)` strings for a same-day case.
  ///  past expiry (negative diff) → ('منذ', 'X ساعة / دقيقة')
  ///  hours >= 1               → ('5س', '30د')
  ///  hours == 0               → ('30', 'دقيقة')
  static (String, String) _hoursMinutesUntil(DateTime? exp) {
    if (exp == null) return ('0', 'اليوم');
    final now = DateTime.now();
    final diff = exp.difference(now);
    if (diff.isNegative) {
      // Already expired. مطلب 2026-06-11: لما تكون المدة أكثر من
      // 24 ساعة نحوّلها لأيام بدل 'منذ 7244 ساعة'. الـbadge ضيق
      // ولا نريد رقم كبير يكسر التصميم.
      final past = now.difference(exp);
      final pd = past.inDays;
      if (pd >= 1) return ('منذ', '$pd يوم');
      final ph = past.inHours;
      if (ph >= 1) return ('منذ', '$ph ساعة');
      final pm = past.inMinutes.clamp(1, 59);
      return ('منذ', '$pm دقيقة');
    }
    final h = diff.inHours;
    final mLeft = diff.inMinutes - h * 60;
    if (h >= 1) {
      // Two-line layout: hours on top, minutes underneath.
      return ('${h}س', '${mLeft}د');
    }
    // Less than an hour — show minutes only.
    final m = diff.inMinutes.clamp(0, 59);
    return ('$m', 'دقيقة');
  }
}

/// Package name with an inline price chip on the trailing side
/// (only rendered when the catalogue gave us a price > 0). Mirrors
/// v1 subscriber_card.dart's two-chip pattern — package chip in brand
/// teal, price chip in warning amber — just in v2's tighter inline form.
class _PackageWithPrice extends StatelessWidget {
  const _PackageWithPrice({
    required this.name,
    required this.price,
    this.discount,
  });

  final String name;
  final num? price;
  /// Active discount on the subscriber's package (set via the quick
  /// discount sheet). When >0 we render a small teal '-Xk' chip next
  /// to the amber price chip so the admin sees at-a-glance that the
  /// row has a discount applied without opening the detail screen.
  final double? discount;

  @override
  Widget build(BuildContext context) {
    final hasDiscount = (discount ?? 0) > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: _MetaRow(
            icon: LucideIcons.package,
            text: name,
            color: AppColors.textMid,
          ),
        ),
        if (price != null) ...[
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFE08F2D).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(
                color: const Color(0xFFE08F2D).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.tag,
                    size: 9, color: Color(0xFFE08F2D)),
                const SizedBox(width: 2),
                Text(
                  formatIQD(price!.round()),
                  style: AppType.muted(color: const Color(0xFFE08F2D))
                      .copyWith(fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
        if (hasDiscount) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF14B8A6).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(
                color: const Color(0xFF14B8A6).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.percent,
                    size: 9, color: Color(0xFF14B8A6)),
                const SizedBox(width: 2),
                Text(
                  '-${formatIQD(discount!.round())}',
                  style: AppType.muted(color: const Color(0xFF14B8A6))
                      .copyWith(fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: AppType.muted(color: color)
                .copyWith(fontSize: 11, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _BalanceChip extends StatelessWidget {
  const _BalanceChip({required this.sub});
  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    final isDebt = sub.hasDebt;
    final color = isDebt ? AppColors.error : AppColors.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDebt ? LucideIcons.creditCard : LucideIcons.wallet,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            isDebt ? 'دين' : 'رصيد',
            style: AppType.muted(color: color).copyWith(
              fontSize: 10, // Tiny label tier
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${formatIQD(sub.debtAbs.round())} د.ع',
            style: AppType.label(color: color).copyWith(
              fontSize: 12, // Card title tier — emphasis for the amount
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Live session info row — IP (tappable to open the device's web UI),
/// session duration, DL/UL bytes, device vendor. Mirrors v1's
/// subscriber_card online row (lines 595-647).
class _LiveSessionRow extends StatelessWidget {
  const _LiveSessionRow({required this.sub});
  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    final ip = sub.ipAddress?.trim();
    final session = sub.sessionTime;
    final dl = sub.downloadBytes;
    final ul = sub.uploadBytes;
    final device = sub.deviceVendor?.trim();
    // Wrap so the IP / duration / DL / UL / device chips flow onto a
    // second line when they don't all fit — keeps the row compact even
    // when SAS4 returns large device-vendor strings.
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (ip != null && ip.isNotEmpty)
          InkWell(
            onTap: () => launchUrl(
              Uri.parse('http://$ip'),
              mode: LaunchMode.externalApplication,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.network,
                    size: 12, color: Color(0xFF26A69A)),
                const SizedBox(width: 3),
                Text(
                  ip,
                  style: AppType.label(color: const Color(0xFF26A69A))
                      .copyWith(
                          fontSize: 11, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 2),
                const Icon(LucideIcons.externalLink,
                    size: 9, color: Color(0xFF80CBC4)),
              ],
            ),
          ),
        if (session != null && session > 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.timer,
                  size: 12, color: AppColors.textMid),
              const SizedBox(width: 3),
              Text(
                _formatDuration(session),
                style: AppType.label(color: AppColors.textMid)
                    .copyWith(fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        // Download / Upload only when SAS4 actually has byte counters.
        // Showing '0 B' for online users without traffic data is just
        // visual noise — better to omit until /api/v2/online-users
        // returns a positive count.
        if (dl != null && dl > 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.arrowDownToLine,
                  size: 12, color: Color(0xFF26A69A)),
              const SizedBox(width: 3),
              Text(
                _formatBytes(dl),
                style: AppType.label(color: const Color(0xFF26A69A))
                    .copyWith(fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        if (ul != null && ul > 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.arrowUpFromLine,
                  size: 12, color: Color(0xFF3B82F6)),
              const SizedBox(width: 3),
              Text(
                _formatBytes(ul),
                style: AppType.label(color: const Color(0xFF3B82F6))
                    .copyWith(fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        if (device != null &&
            device.isNotEmpty &&
            device.toLowerCase() != 'unknown')
          Text(
            device,
            style: AppType.muted(color: AppColors.textLow)
                .copyWith(fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

class _LastPaymentLine extends StatelessWidget {
  const _LastPaymentLine({required this.payment});
  final Map<String, dynamic> payment;

  @override
  Widget build(BuildContext context) {
    final amount = _readAmount(payment);
    final createdRaw = payment['created_at']?.toString();
    final action = (payment['action_type'] ?? payment['action'] ?? '').toString();
    final paymentType = payment['payment_type']?.toString();
    if (createdRaw == null || createdRaw.isEmpty) {
      return const SizedBox.shrink();
    }
    final created = DateTime.tryParse(createdRaw);
    if (created == null) return const SizedBox.shrink();
    final diff = DateTime.now().difference(created);
    if (diff.inDays > 30) return const SizedBox.shrink();
    final timeLabel = _humanAgo(diff);
    final actionLabel = _humanAction(action, paymentType: paymentType);
    return Row(
      children: [
        const Icon(LucideIcons.banknote,
            size: 12, color: AppColors.brand),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '$actionLabel • $timeLabel${amount != 0 ? ' • ${formatIQD(amount.abs())} د.ع' : ''}',
            style: AppType.muted(color: AppColors.brand)
                .copyWith(fontSize: 11, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  static int _readAmount(Map<String, dynamic> m) {
    final raw = m['amount'] ?? m['paid_amount'] ?? m['debt_amount'];
    if (raw == null) return 0;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString().replaceAll(',', '')) ?? 0;
  }

  static String _humanAgo(Duration d) {
    if (d.inMinutes < 1) return 'الآن';
    if (d.inHours < 1) return 'قبل ${d.inMinutes} د';
    if (d.inDays < 1) return 'قبل ${d.inHours} س';
    if (d.inDays == 1) return 'قبل يوم';
    return 'قبل ${d.inDays} أيام';
  }

  /// Mirrors v1's subscriber_card._movementLabel.
  static String _humanAction(String action, {String? paymentType}) {
    if (action.toUpperCase() == 'SUBSCRIBER_ACTIVATE') {
      return (paymentType ?? '').contains('جزئي')
          ? 'تفعيل نقدي جزئي'
          : 'تفعيل نقدي';
    }
    return 'تسديد دين';
  }
}

/// Ghost-style action button — text-link feel with a colored leading
/// dot. Used للاستهلاك + فصل تحت بطاقة المتصل. مطلب 2026-06-11
/// (تحديث ثاني): الـpills السابقة كانت "نشاز" بالتصميم. هذا أنحف،
/// مدمج مع باقي السطور النصية لكن مع نقطة لون تميّز كل إجراء.
class _GhostAction extends StatelessWidget {
  const _GhostAction({
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
