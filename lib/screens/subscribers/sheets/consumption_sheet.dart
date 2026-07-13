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
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
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
              // مطلب 2026-06-11: إذا الـSAS4 ما رجّع بايتات بعد
              // (شائع للجلسات الجديدة)، نبيّن للمدير وضوحاً أن
              // المودل مفتوح وفيه بيانات بدل ما يحس فاضي.
              if ((sub.downloadBytes ?? 0) == 0 &&
                  (sub.uploadBytes ?? 0) == 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFFE08F2D).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(R.md),
                    border: Border.all(
                      color: const Color(0xFFE08F2D)
                          .withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.info,
                          size: 13, color: Color(0xFFE08F2D)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'لا يوجد استهلاك مسجَّل بعد — الجلسة قد تكون '
                          'حديثة أو لم يتم تحديث الـSAS بعد.',
                          style: AppType.muted(color: AppColors.textHi)
                              .copyWith(fontSize: 11.5, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // 2026-07-13: قسم "الاستهلاك اليومي" الجديد — يعرض إجمالي
              // المشترك خلال اليوم (من SAS4 daily_traffic_details).
              // يظهر فقط لو backend رجّع البيانات (لبعض الجلسات null).
              if (_hasDailyTraffic) ...[
                const SizedBox(height: Sp.md),
                _sectionLabel('الاستهلاك اليومي', LucideIcons.calendar),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _bigStat(
                        icon: LucideIcons.download,
                        label: 'تحميل اليوم',
                        value: _fmtBytes(sub.dailyDownload ?? 0),
                        color: const Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _bigStat(
                        icon: LucideIcons.upload,
                        label: 'رفع اليوم',
                        value: _fmtBytes(sub.dailyUpload ?? 0),
                        color: const Color(0xFF6366F1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(R.md),
                    border: Border.all(
                      color: AppColors.brand.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.activity,
                          size: 14, color: AppColors.brand),
                      const SizedBox(width: 6),
                      Text(
                        'إجمالي اليوم:',
                        style: AppType.muted().copyWith(fontSize: 12),
                      ),
                      const Spacer(),
                      Text(
                        _fmtBytes(sub.dailyTrafficTotal ?? 0),
                        style: AppType.title(color: AppColors.brand)
                            .copyWith(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: Sp.md),
              _sectionLabel('معلومات الجلسة الحاليّة', LucideIcons.info),
              const SizedBox(height: 6),
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
                    side: BorderSide(color: AppColors.border),
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

  /// true لو backend رجّع أي قيمة داخل daily_traffic_details.
  bool get _hasDailyTraffic =>
      (sub.dailyTrafficTotal ?? 0) > 0 ||
      (sub.dailyUpload ?? 0) > 0 ||
      (sub.dailyDownload ?? 0) > 0;

  Widget _sectionLabel(String text, IconData icon) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Row(
          children: [
            Icon(icon, size: 13, color: AppColors.brand),
            const SizedBox(width: 5),
            Text(
              text,
              style: AppType.title(color: AppColors.textHi)
                  .copyWith(fontSize: 12.5),
            ),
          ],
        ),
      );

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: AppColors.textMid),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: AppType.muted(color: AppColors.textMid)
                .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          // مطلب 2026-06-11: اسم الجهاز الطويل (مثل
          // 'Guangzhou V-SOLUTION') كان يتقطع. شيلنا maxLines=1
          // وخلّينا التفاف طبيعي حتى 3 أسطر، WordWrap حتى لو
          // النص بدون فراغات.
          Expanded(
            child: Text(
              value,
              style: AppType.label(color: AppColors.textHi)
                  .copyWith(fontSize: 13, fontWeight: FontWeight.w700),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
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
