import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// مطلب 2026-06-11: مودل سريع يعرض استهلاك المشترك المتصل
/// (IP، تحميل، رفع، مدة الجلسة، الجهاز). يُفتح من زر "الاستهلاك"
/// أسفل كل بطاقة في تاب "متصل" بدون الحاجة لفتح صفحة التفاصيل.
Future<void> showConsumptionSheet(BuildContext context, Subscriber sub) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ConsumptionSheet(sub: sub),
  );
}

class _ConsumptionSheet extends StatelessWidget {
  const _ConsumptionSheet({required this.sub});
  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: Sp.md),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFF3B82F6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(R.md),
                    ),
                    child: const Icon(LucideIcons.activity,
                        size: 16, color: Color(0xFF3B82F6)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'استهلاك المشترك',
                          style: AppType.title(color: AppColors.textHi)
                              .copyWith(fontSize: 15),
                        ),
                        Text(
                          sub.fullName.isNotEmpty
                              ? sub.fullName
                              : sub.username,
                          style: AppType.muted().copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Sp.md),
              Row(
                children: [
                  Expanded(
                    child: _bigStat(
                      icon: LucideIcons.download,
                      label: 'تحميل',
                      value: _fmtBytes(sub.downloadBytes ?? 0),
                      color: AppColors.brand,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _bigStat(
                      icon: LucideIcons.upload,
                      label: 'رفع',
                      value: _fmtBytes(sub.uploadBytes ?? 0),
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Sp.md),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceInput,
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: Column(
                  children: [
                    _row(
                      icon: LucideIcons.network,
                      label: 'IP',
                      value: (sub.ipAddress?.isNotEmpty ?? false)
                          ? sub.ipAddress!
                          : '—',
                    ),
                    _divider(),
                    _row(
                      icon: LucideIcons.timer,
                      label: 'مدة الجلسة',
                      value: (sub.sessionTime != null && sub.sessionTime! > 0)
                          ? _fmtDuration(sub.sessionTime!)
                          : '—',
                    ),
                    _divider(),
                    _row(
                      icon: LucideIcons.cpu,
                      label: 'الجهاز',
                      value: (sub.deviceVendor?.isNotEmpty ?? false)
                          ? sub.deviceVendor!
                          : '—',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Sp.md),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, size: 16),
                  label: const Text('إغلاق'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMid,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(R.md),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bigStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppType.muted().copyWith(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppType.title(color: color)
                .copyWith(fontSize: 18, letterSpacing: -0.3),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textMid),
          const SizedBox(width: 7),
          Text(
            label,
            style: AppType.muted(color: AppColors.textMid)
                .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: AppType.label(color: AppColors.textHi)
                  .copyWith(fontSize: 13, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        height: 1,
        color: AppColors.border,
      );

  static String _fmtBytes(int bytes) {
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

  static String _fmtDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}س ${m}د';
    return '${m}د';
  }
}
