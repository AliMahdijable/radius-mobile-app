// `hide TextDirection`: الحزمة تصدّر نوع intl الذي يحجب نوع dart:ui
// المستعمَل في `textDirection` عبر الملفّ.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/settlements_api.dart';
import '../../core/util/ar_date.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// مبلغٌ بإشارته: `formatIQD` يُسقطها عمداً، والصندوق قد يكون سالباً.
String settleMoney(num n) =>
    '${n < 0 ? '−' : ''}${formatIQD(n)} ${'common.currency'.tr()}';

/// سطر «شراء مواد» بالصندوق: ما خرج لشراء المخزون ناقص ما رجّعه المورّد للصندوق عن مادّةٍ عاطلة —
/// صافيه سالبٌ ⇒ داخلٌ «استرجاع من المورّد».
({String label, String value, bool out}) goodsBoxLine(MoneyCount g) {
  final out = g.sum >= 0;
  return (
    label: (out ? 'settle.goods_purchases' : 'settle.supplier_refund').tr(),
    value: '${out ? '−' : '+'}${formatIQD(g.sum.abs())}',
    out: out,
  );
}

/// «الخميس 1 تشرين الأوّل · 21:40» بتوقيت الجهاز (الأجهزة في العراق).
String settleWhen(DateTime? d, {bool weekday = false}) {
  if (d == null) return '—';
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  // «23 تشرين الأوّل · 00:00» لا «2026-10-23 00:00» (المالك ٢٤ أكتوبر).
  final s = '${iqDateOf(l)} · ${two(l.hour)}:${two(l.minute)}';
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
                          collectors[i].outCount > 0
                              ? 'settle.collector_counts_spent'.tr(namedArgs: {
                                  'in': '${collectors[i].inCount}',
                                  'out': '${collectors[i].outCount}',
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
      'sale' => LucideIcons.shoppingCart,
      'sale_void' => LucideIcons.undo2,
      'purchase' => LucideIcons.packagePlus,
      'purchase_void' => LucideIcons.undo2,
      'supplier_refund_void' => LucideIcons.undo2,
      _ => LucideIcons.handCoins,
    };
    final kindLabel = switch (m.kind) {
      'cash_activation' => 'settle.kind_cash_activation'.tr(),
      'expense' => 'settle.kind_expense'.tr(),
      'sale' => 'settle.kind_sale'.tr(),
      'sale_void' => 'settle.kind_sale_void'.tr(),
      'purchase' => 'settle.kind_purchase'.tr(),
      'purchase_void' => 'settle.kind_purchase_void'.tr(),
      'supplier_refund' => 'settle.kind_supplier_refund'.tr(),
      'supplier_refund_void' => 'settle.kind_supplier_refund_void'.tr(),
      _ => 'settle.kind_debt_payment'.tr(),
    };
    // بيع المواد: العنوان الزبون (أو «زبون»)، وما بيع يُقرأ من الوصف بسطر التفاصيل.
    // شراء المخزون من الصندوق: العنوان المادّة وكمّيّتها (الوصف بلا بادئته).
    final isSale = m.source == 'sale';
    final isPurchase = m.source == 'purchase';
    final buyTitle = isPurchase
        ? (m.description ?? '').replaceFirst(RegExp(r'^(?:إلغاء شراء|شراء مواد|استرجاع من المورّد|إلغاء استرجاع):\s*'), '').trim()
        : '';
    final title = m.kind == 'expense'
        ? (m.description ?? 'settle.kind_expense'.tr())
        : isPurchase
            ? (buyTitle.isEmpty ? kindLabel : iso(buyTitle))
            : isSale
                ? (m.subscriber ?? 'sales.walkin'.tr())
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
                    // ما بيع (الوصف بلا بادئة «بيع:»/«إلغاء بيع:»).
                    if (isSale && (m.description ?? '').isNotEmpty)
                      m.description!.replaceFirst(RegExp(r'^(?:إلغاء بيع|بيع):\s*'), ''),
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
