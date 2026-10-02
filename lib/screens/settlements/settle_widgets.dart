// `hide TextDirection`: الحزمة تصدّر نوع intl الذي يحجب نوع dart:ui
// المستعمَل في `textDirection` عبر الملفّ.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/settlements_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// مبلغٌ بإشارته: `formatIQD` يُسقطها عمداً، والصندوق قد يكون سالباً.
String settleMoney(num n) =>
    '${n < 0 ? '−' : ''}${formatIQD(n)} ${'common.currency'.tr()}';

/// «الخميس 2026-10-01 21:40» بتوقيت الجهاز (الأجهزة في العراق).
String settleWhen(DateTime? d, {bool weekday = false}) {
  if (d == null) return '—';
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final s = '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  return weekday ? '${'settle.wd${l.weekday}'.tr()} $s' : s;
}

String collectorName(SettleCollector c) {
  if (c.isManager) return 'settle.manager'.tr();
  final n = (c.name ?? '').trim();
  if (n.isNotEmpty) return n;
  return c.username ?? '#${c.employeeId}';
}

/// حصّة كلّ منفّذ: الاسم وعدد ما قبض وصرف، والصافي.
class CollectorsList extends StatelessWidget {
  const CollectorsList({super.key, required this.collectors});
  final List<SettleCollector> collectors;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < collectors.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          collectorName(collectors[i]),
                          style: AppType.bodyStrong(color: AppColors.textHi),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: Sp.xxs),
                        Text(
                          collectors[i].expenses.count > 0
                              ? 'settle.collector_counts_spent'.tr(namedArgs: {
                                  'in': '${collectors[i].inCount}',
                                  'out': '${collectors[i].expenses.count}',
                                })
                              : 'settle.collector_counts'.tr(
                                  namedArgs: {'in': '${collectors[i].inCount}'}),
                          style: AppType.muted(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Sp.sm),
                  Text(
                    settleMoney(collectors[i].net),
                    textDirection: TextDirection.ltr,
                    style: AppType.bodyBold(
                      color: collectors[i].net < 0
                          ? AppColors.error
                          : AppColors.textHi,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// حركةٌ في الصندوق: نقدٌ داخل أخضر، وصرفيةٌ خارجة حمراء.
class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.m});
  final BoxMovement m;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final tone = m.isIn ? AppTone.success : AppTone.danger;
    final icon = switch (m.kind) {
      'cash_activation' => LucideIcons.zap,
      'expense' => LucideIcons.receipt,
      _ => LucideIcons.handCoins,
    };
    final kindLabel = switch (m.kind) {
      'cash_activation' => 'settle.kind_cash_activation'.tr(),
      'expense' => 'settle.kind_expense'.tr(),
      _ => 'settle.kind_debt_payment'.tr(),
    };
    final title = m.kind == 'expense'
        ? (m.description ?? 'settle.kind_expense'.tr())
        : (m.subscriber ?? '—');
    final who = m.employeeId == null
        ? 'settle.manager'.tr()
        : (m.employeeName ?? m.employeeUsername ?? 'settle.employee'.tr());
    final written = m.expenseDate ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tone.softBg,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(icon, size: 16, color: tone.fill),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppType.bodyStrong(color: AppColors.textHi),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Sp.xxs),
                Text(
                  isoJoin([
                    kindLabel,
                    if ((m.packageName ?? '').isNotEmpty) m.packageName!,
                    who,
                    settleWhen(m.createdAt),
                  ], ' · '),
                  style: AppType.muted(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (m.backdated && written.isNotEmpty) ...[
                  const SizedBox(height: Sp.xs),
                  ToneChip(
                    label: 'settle.backdated'.tr(namedArgs: {
                      'date': written.length >= 10 ? written.substring(0, 10) : written,
                    }),
                    tone: AppTone.warning,
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Sp.sm),
          Text(
            '${m.isIn ? '+' : '−'}${formatIQD(m.amount)}',
            textDirection: TextDirection.ltr,
            style: AppType.bodyBold(color: tone.fill),
          ),
        ],
      ),
    );
  }
}

/// صفّ «المُرحَّل» في آخر قائمة الحركات — نقطة بداية الفترة.
class OpeningTile extends StatelessWidget {
  const OpeningTile({super.key, required this.label, required this.amount});
  final String label;
  final num amount;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      color: AppColors.surfaceSunken,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTone.neutral.softBg,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(LucideIcons.history, size: 16, color: AppTone.neutral.fill),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Text(
              label,
              style: AppType.body(color: AppColors.textMid),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Sp.sm),
          Text(
            settleMoney(amount),
            textDirection: TextDirection.ltr,
            style: AppType.bodyBold(color: AppColors.textHi),
          ),
        ],
      ),
    );
  }
}
