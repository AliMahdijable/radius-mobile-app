import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';

/// Skeleton placeholder بـshimmer animation ناعم — بديل لطيف لـ
/// CircularProgressIndicator أثناء تحميل قوائم/كارتات.
///
/// الاستعمال:
///   SkeletonBox(width: 100, height: 14) — سطر نصّ
///   SkeletonBox(width: 44, height: 44, borderRadius: 22) — أفاتار دائري
///   SkeletonCard() — كارت جاهز يشبه كارت الجهاز
///
/// الحركة: linear-gradient shimmer من يمين لشمال، دورة 1.4s.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 4,
  });
  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ التباين هنا ليس ذوقاً: `surfaceInput ⇄ border` يعطي 1.18:1
    // ليلاً و1.15:1 نهاراً — أي حركة لا تكاد تُرى، فتبدو الشاشة
    // متجمّدة لا محمَّلة، والمستخدم يظنّ التطبيق معلَّقاً.
    // `borderStrong` يرفعها إلى 1.58:1 ليلاً و1.44:1 نهاراً: ظاهرة
    // بوضوح وما تزال أهدأ من أن تُشتّت.
    final base = AppColors.surfaceSunken;
    final highlight = AppColors.borderStrong;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              final progress = _ctrl.value;
              // gradient يمشي من -1 إلى +2 (0..1 = مرئي، الباقي = خارج)
              final start = progress * 3 - 1;
              return LinearGradient(
                begin: Alignment(start - 0.3, 0),
                end: Alignment(start + 0.3, 0),
                colors: [base, highlight, base],
                stops: const [0.0, 0.5, 1.0],
              ).createShader(bounds);
            },
            child: Container(
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(widget.borderRadius),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Placeholder جاهز يشبه كارت الجهاز في NetworkDevicesScreen.
/// دائرة (BrandBadge) + عمودَي نصّ. يستعمل SkeletonBox داخلياً.
class SkeletonDeviceCard extends StatelessWidget {
  const SkeletonDeviceCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      // الحشوة ونصف القطر مأخوذان من `subscriber_card_v3` حرفيّاً
      // (15×14 · R.card): أيّ فرق يجعل القائمة تقفز لحظة استبدال
      // الهيكل بالمحتوى، وهي القفزة التي يُفترض بالهيكل منعها.
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(children: [
        SkeletonBox(width: 44, height: 44, borderRadius: 22),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 140, height: 14),
              SizedBox(height: 6),
              Row(children: [
                SkeletonBox(width: 80, height: 10),
                SizedBox(width: 6),
                SkeletonBox(width: 40, height: 10),
              ]),
              SizedBox(height: 6),
              SkeletonBox(width: 100, height: 9),
            ],
          ),
        ),
        SizedBox(width: 6),
        SkeletonBox(width: 30, height: 10),
      ]),
    );
  }
}

/// قائمة N من `SkeletonDeviceCard` — يُستعمل بدل CircularProgressIndicator
/// الكبير أثناء تحميل قائمة الأجهزة أوّل مرّة.
class SkeletonDeviceList extends StatelessWidget {
  const SkeletonDeviceList({super.key, this.count = 6});
  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, __) => const SkeletonDeviceCard(),
    );
  }
}

/// كارت skeleton للـmanager region — دائرة ملوّنة + سطران.
class SkeletonRegionCard extends StatelessWidget {
  const SkeletonRegionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(children: [
        SkeletonBox(width: 40, height: 40, borderRadius: 20),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 100, height: 14),
              SizedBox(height: 4),
              SkeletonBox(width: 60, height: 10),
            ],
          ),
        ),
      ]),
    );
  }
}
