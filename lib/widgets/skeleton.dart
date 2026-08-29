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
    // ألوان محايدة — تشتغل مع light + dark
    final base = AppColors.surfaceInput;
    final highlight = AppColors.border;

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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        const SkeletonBox(width: 44, height: 44, borderRadius: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 140, height: 14),
              const SizedBox(height: 6),
              Row(children: const [
                SkeletonBox(width: 80, height: 10),
                SizedBox(width: 6),
                SkeletonBox(width: 40, height: 10),
              ]),
              const SizedBox(height: 6),
              const SkeletonBox(width: 100, height: 9),
            ],
          ),
        ),
        const SizedBox(width: 6),
        const SkeletonBox(width: 30, height: 10),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        const SkeletonBox(width: 40, height: 40, borderRadius: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
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
