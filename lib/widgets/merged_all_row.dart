import 'package:flutter/material.dart';

import '../services/merged_mode.dart';
import '../services/merged_text.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// صفّ «كل الشركات» أعلى «تبديل الشركة» (المالك) و«كل الصفحات» أعلى «صفحاتي» (الموظّف، ٩ نوفمبر) — الصفّ نفسه بكلمة كلٍّ منهما
/// ([MergedTr.trm]): الدخول بلا تسجيل، ومفعّلاً يُعلَّم والنقر يعيد للمفتوحة. [stoppedText]: الخادم أطفأ الوضع الآن — الصفّ بمكانه
/// خافتاً بالسبب ولا يُنقر (الموظّف لا يبحث عن خيارٍ اختفى).
class MergedAllRow extends StatelessWidget {
  const MergedAllRow({super.key, required this.active, required this.busy, required this.onTap, this.stoppedText});

  final bool active;
  final bool busy;
  final VoidCallback onTap;
  final String? stoppedText;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final usable = MergedMode.usable;
    final stopped = stoppedText != null && !active;
    final row = Material(
      color: active ? AppColors.brandSoftBg : AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: busy || stopped ? null : onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: active ? AppColors.brand : AppColors.border, width: active ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.sm)),
                child: Icon(Icons.layers_rounded, size: 22, color: AppColors.brand),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('merged.all_title'.trm(), style: AppType.bodyStrong(color: AppColors.textHi)),
                    const SizedBox(height: 3),
                    Text(
                      stopped
                          ? stoppedText!
                          : busy
                              ? 'merged.entering'.trm()
                              : active
                                  ? 'merged.all_active'.trm()
                                  : 'merged.all_sub'.trm(args: ['${usable.length}']),
                      style: AppType.muted().copyWith(fontSize: 12.5, height: 1.45),
                    ),
                    if (usable.isNotEmpty && !stopped) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final c in usable)
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(color: AppColors.company(c.colorIndex), shape: BoxShape.circle),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              if (busy)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(color: AppColors.brand, strokeWidth: 2.2),
                )
              else if (stopped)
                Icon(Icons.pause_circle_outline_rounded, color: AppColors.textLow)
              else
                Icon(active ? Icons.check_circle_rounded : Icons.chevron_left_rounded,
                    color: active ? AppColors.brand : AppColors.textMid),
            ],
          ),
        ),
      ),
    );
    return stopped ? Opacity(opacity: 0.7, child: row) : row;
  }
}
