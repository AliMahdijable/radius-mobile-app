import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../models/dashboard.dart';
import '../../../screens/subscribers/widgets/filter_chips_bar.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Subscribers card — direct port of v1's
/// mobile-app/lib/screens/dashboard_screen.dart layout. Same shape:
///   • 130×130 dual-arc ring (active teal + expired red) on the leading
///     side, big total + 'مشترك' label inside.
///   • 5 tappable _RingStatRow on the trailing side (الفعالين, متصل الآن,
///     غير متصل, منتهي, قريب الانتهاء).
///   • Thin gradient progress bar underneath (active teal vs expired red).
///
/// stats=null → loading skeleton. onOpen wires each tap target back to
/// MainShell so the subscribers tab opens with the matching filter.
class SubscribersCard extends StatelessWidget {
  const SubscribersCard({super.key, required this.stats, this.onOpen});

  final SubscribersStats? stats;
  final ValueChanged<SubscriberFilter?>? onOpen;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (stats == null) return const _Skeleton();
    final s = stats!;
    // ⚠️ الحدّ ليس احتياطاً نظريّاً: `total` مصدره widget الـSAS4 بينما
    // `active` و`expired` محسوبان محليّاً من القائمة، فلا ضمان أنّ
    // مجموعهما ≤ الإجمالي. بلا حدّ يتجاوز مجموع الأقواس دورةً كاملة
    // فيلفّ القوس فوق نفسه ويعرض نسبةً كاذبة.
    final denom = s.total > 0 ? s.total : (s.active + s.expired);
    final rawActive = denom > 0 ? s.active / denom : 0.0;
    final rawExpired = denom > 0 ? s.expired / denom : 0.0;
    final scale =
        (rawActive + rawExpired) > 1.0 ? 1.0 / (rawActive + rawExpired) : 1.0;
    final activeRatio = rawActive * scale;
    final expiredRatio = rawExpired * scale;

    return Container(
      padding: const EdgeInsets.all(Sp.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        // حدّ محايد لا مشتقّ من البراند: `brandSoftBg` كحدٍّ يذوب في
        // السطح ليلاً ويصبغ الكارت أخضر بلا داعٍ نهاراً.
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Ring(
                total: s.total,
                activeRatio: activeRatio,
                expiredRatio: expiredRatio,
                onTap:
                    onOpen == null ? null : () => onOpen!(SubscriberFilter.all),
              ),
              const SizedBox(width: 16),
              // ⚠️ ثلاثة صفوف لا ستّة (إعادة تصميم 2026-08-30).
              //
              // الستّة كانت تجعل العمود 227px بينما الحلقة 130px، فيرتفع
              // الكارت 283px — نصف الشاشة قبل أن يُرى أيّ شيء آخر. والأهمّ
              // أنّ ستّة صفوف متطابقة الشكل لا تُنشئ تسلسلاً: العين لا
              // تعرف أيّها الأهمّ فتقرأها كلّها أو لا تقرأ شيئاً.
              //
              // الثلاثة هنا هي ما يُنظر إليه يوميّاً؛ والثلاثة الأخرى
              // (قربوا الانتهاء · غير مفعّل · بدون نت) استثناءات تُتابَع
              // عند وقوعها — فنزلت حبّاتٍ أصغر تحت. نفس الأرقام، ورتبتان
              // بصريّتان بدل رتبة واحدة مسطّحة.
              Expanded(
                child: Column(
                  children: [
                    _RingStatRow(
                      tone: AppTone.brand,
                      icon: LucideIcons.circleCheck,
                      label: 'dashboard.active'.tr(),
                      value: s.active,
                      onTap: onOpen == null
                          ? null
                          : () => onOpen!(SubscriberFilter.active),
                    ),
                    const SizedBox(height: 9),
                    _RingStatRow(
                      tone: AppTone.danger,
                      icon: LucideIcons.timerOff,
                      label: 'dashboard.expired'.tr(),
                      value: s.expired,
                      onTap: onOpen == null
                          ? null
                          : () => onOpen!(SubscriberFilter.expired),
                    ),
                    const SizedBox(height: 9),
                    _RingStatRow(
                      tone: AppTone.success,
                      icon: LucideIcons.wifi,
                      label: 'dashboard.online'.tr(),
                      value: s.online,
                      onTap: onOpen == null
                          ? null
                          : () => onOpen!(SubscriberFilter.online),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // شريط الحالات الاستثنائيّة. حلّ محلّ شريط النسبة القديم
          // (active/expired) عمداً: النسبة نفسها تقرأها الحلقة أعلاه،
          // فالشريط كان يكرّرها بلغة ثانية ويأكل الموضع الذي تحتاجه
          // هذه الثلاثة.
          // ⚠️ `IntrinsicHeight` لأنّ التسميات تختلف في عدد الأسطر
          // («قربوا الانتهاء» سطران في عرض الرُبع، و«بدون نت» سطر) —
          // وبدونه تختلف ارتفاعات الحبّات فيبدو الصفّ مكسوراً.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _StatPill(
                    tone: AppTone.warning,
                    icon: LucideIcons.triangleAlert,
                    label: 'dashboard.near_expiry'.tr(),
                    value: s.nearExpiry,
                    onTap: onOpen == null
                        ? null
                        : () => onOpen!(SubscriberFilter.nearExpiry),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatPill(
                    tone: AppTone.neutral,
                    icon: LucideIcons.userX,
                    label: 'dashboard.disabled'.tr(),
                    value: s.disabled,
                    onTap: onOpen == null
                        ? null
                        : () => onOpen!(SubscriberFilter.disabled),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatPill(
                    // «متصل بلا باقة» شذوذ لا حالة عاديّة — لونه البنفسجي
                    // نفسه في القائمة والويب، وأيقونته `wifi` لا `wifiOff`
                    // لأنّ اتّصالهم **هو** موضع الشذوذ.
                    tone: AppTone.anomaly,
                    icon: LucideIcons.wifi,
                    label: 'dashboard.online_no_plan'.tr(),
                    value: s.onlineNoPlan,
                    onTap: onOpen == null
                        ? null
                        : () => onOpen!(SubscriberFilter.onlineNoPlan),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatPill(
                    tone: AppTone.info,
                    icon: LucideIcons.wifiOff,
                    label: 'dashboard.offline'.tr(),
                    value: s.offline,
                    onTap: onOpen == null
                        ? null
                        : () => onOpen!(SubscriberFilter.offline),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading skeleton matching the card's resting height so the dashboard
/// doesn't jump when real data arrives.
class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      height: 255, // مقيس لا مُقدَّر — يحرسه dashboard_card_height_test
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        // حدّ محايد لا مشتقّ من البراند: `brandSoftBg` كحدٍّ يذوب في
        // السطح ليلاً ويصبغ الكارت أخضر بلا داعٍ نهاراً.
        border: Border.all(color: AppColors.border),
      ),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppColors.brand,
          ),
        ),
      ),
    );
  }
}

/// 130×130 dual-arc ring with the total + 'مشترك' label centered.
/// Same dimensions and behavior as v1's `Container(width:130, height:130)
/// + CustomPaint(_RingPainter)`.
class _Ring extends StatelessWidget {
  const _Ring({
    required this.total,
    required this.activeRatio,
    required this.expiredRatio,
    this.onTap,
  });

  final int total;
  final double activeRatio;
  final double expiredRatio;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 130,
        height: 130,
        child: CustomPaint(
          painter: _RingPainter(
            activeRatio: activeRatio,
            expiredRatio: expiredRatio,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$total',
                  style: AppType.title(color: AppColors.brand).copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'dashboard.subscriber_singular'.tr(),
                  style: AppType.muted(color: AppColors.textLow)
                      .copyWith(fontSize: 10.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One stat row in the trailing list. Icon-box (rounded square, 8px
/// radius) + label + value + chevron. Tappable surface highlights on
/// press; matches v1's _RingStatRow 1:1.
class _RingStatRow extends StatelessWidget {
  const _RingStatRow({
    required this.tone,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  /// نغمة دلاليّة لا لون مفرد — تحمل التعبئة والخلفيّة معاً من اللوحة
  /// بدل اشتقاق الخلفيّة بشفافيّة لا تعرف الوضع الليلي.
  final AppTone tone;
  final IconData icon;
  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: tone.softBg,
              borderRadius: BorderRadius.circular(R.icon),
            ),
            child: Icon(icon, color: tone.fill, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            // ⚠️ `maxLines: 1` ليس تجميلاً: بدونه يلتفّ النصّ فيتغيّر
            // ارتفاع الصفّ بتغيّر اللغة — التسميات الإنجليزيّة أطول
            // («Near expiry» مقابل «قربوا الانتهاء» في عرض 76px)، فترتفع
            // البطاقة كلّها وتنفصل عن ارتفاع هيكلها فتقفز الشاشة.
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label(color: AppColors.textMid)
                  .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '$value',
            style: AppType.title(color: tone.fill).copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            LucideIcons.chevronLeft,
            size: 16,
            color: AppColors.textLow,
          ),
        ],
      ),
    );
  }
}

/// Direct port of v1's _RingPainter. Background ring (teal100 tint),
/// then the active arc (teal sweep), then the expired arc (red sweep)
/// with a 0.04 rad gap between them so they read as separate segments.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.activeRatio, required this.expiredRatio});

  /// لقطة من راية الوضع الليلي وقت الإنشاء — `shouldRepaint` تقارنها.
  final bool isDark = AppColors.isDark;

  final double activeRatio;
  final double expiredRatio;

  static const _stroke = 14.0;
  static const _startAngle = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    final bgPaint = Paint()
      ..color = AppColors.brandSoftBg
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // ⚠️ لا خروج مبكّر عند activeRatio == 0.
    //
    // كان `if (activeRatio <= 0) return;` هنا، أي أنّ حساباً كلّ
    // مشتركيه منتهون يعرض حلقةً رماديّة فارغة بلا القوس الأحمر —
    // أسوأ حالة ممكنة تُرسم كأنّها لا شيء. الآن يُرسم كلّ قوس بشرطه
    // وحده.
    final rect = Rect.fromCircle(center: center, radius: radius);
    final activeSweep = 2 * math.pi * activeRatio;

    // قوس مصمت: التدرّج كان يمرّ بثلاث درجات براند فيقرأ كأنّه ثلاث
    // شرائح لا قوساً واحداً، والنسبة تُقرأ من الطول لا من اللون.
    final activePaint = Paint()
      ..color = AppColors.brandAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    if (activeRatio > 0) {
      canvas.drawArc(rect, _startAngle, activeSweep, false, activePaint);
    }

    if (expiredRatio <= 0) return;

    // الفجوة تفصل القوسين بصريّاً — لكن لا معنى لها حين لا قوس قبلها،
    // وطرحها من قوس قصير قد يجعله سالباً فلا يُرسم إطلاقاً.
    final gap = activeRatio > 0 ? 0.04 : 0.0;
    final expiredSweep = 2 * math.pi * expiredRatio;
    final expiredPaint = Paint()
      ..color = AppColors.errorFill
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      _startAngle + activeSweep + gap,
      math.max(expiredSweep - gap, 0.0),
      false,
      expiredPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.activeRatio != activeRatio ||
      old.expiredRatio != expiredRatio ||
      // الألوان تُقرأ من `AppColors` داخل `paint`، فبلا مقارنة الوضع
      // تبقى الحلقة بلوحتها القديمة بينما تنقلب الشاشة حولها.
      old.isDark != isDark;
}

/// حبّة حالة استثنائيّة أسفل البطاقة — رتبة أدنى من صفوف الحلقة.
///
/// أصغر من `_RingStatRow` عمداً: هذه حالات تُتابَع عند وقوعها لا تُقرأ
/// يوميّاً، والفرق في الحجم هو ما يجعل الصفوف الثلاثة أعلاه تُقرأ أوّلاً.
class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.tone,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final AppTone tone;
  final IconData icon;
  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      // ⚠️ بلا خلفيّة ملوّنة (طلب المستخدم 2026-08-30): الحبّات الثلاث
      // متجاورة، وثلاث خلفيّات مصمتة تجعل الصفّ كتلاً متنافسة على
      // الانتباه بدل أن يقرأها بلمحة. اللون في الأيقونة والإطار والرقم
      // يكفي للتمييز، والسطح المحايد يُبقي الصفّ هادئاً.
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            // `fill` لا `softBorder`: الأخير مُعايَر ليقع على خلفيّته
            // الناعمة، وعلى سطح محايد يُقرأ رماديّاً (1.26-1.49) فيضيع
            // التمييز الذي هو غرضه.
            border: Border.all(color: tone.fill),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 13, color: tone.fill),
                  const SizedBox(width: 5),
                  Text('$value',
                      style: AppType.cardTitleBold(color: tone.fill)),
                ],
              ),
              const SizedBox(height: 3),
              // التسمية قد تطول بالإنجليزيّة — سطر واحد بقصّ، فالحبّات
              // الثلاث متساوية العرض ولا تُزيح إحداها الأخريين.
              Text(
                label,
                // التسمية محايدة: `onSoft` مُعايَر للخلفيّة الناعمة،
                // وعلى السطح المحايد يقلّ تباينه.
                style: AppType.micro(color: AppColors.textMid),
                // سطران: أربع حبّات في صفّ تعني رُبع العرض لكلٍّ،
                // و«قربوا الانتهاء» لا تسع سطراً واحداً هناك.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
