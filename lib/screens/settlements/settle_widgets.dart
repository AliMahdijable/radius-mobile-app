// `hide TextDirection`: الحزمة تصدّر نوع intl الذي يحجب نوع dart:ui
// المستعمَل في `textDirection` عبر الملفّ.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/payment_voids_api.dart';
import '../../api/settlements_api.dart';
import '../../core/util/ar_date.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/payment_void_bits.dart';

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

/// سطر «الموظفون» بالصندوق («حركات الموظف»، ١٣ نوفمبر): صافيه سالبٌ ⇒ خرج (سلف وقروض وسحوبات)، موجبٌ ⇒ عاد (تسديد
/// واستقطاع رواتب). القيمة بإشارتها كما تُحسب في المتوقَّع.
({String label, String value, bool out}) employeeBoxLine(MoneyCount m) {
  final out = m.sum < 0;
  return (
    label: (out ? 'settle.emp_out' : m.sum > 0 ? 'settle.emp_in' : 'settle.emp_zero').tr(),
    value: '${out ? '−' : '+'}${formatIQD(m.sum.abs())}',
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
                          (collectors[i].outCount > 0
                                  ? 'settle.collector_counts_spent'.tr(namedArgs: {
                                      'in': '${collectors[i].inCount}',
                                      'out': '${collectors[i].outCount}',
                                    })
                                  : 'settle.collector_counts'.tr(
                                      namedArgs: {'in': '${collectors[i].inCount}'})) +
                              // حركات الموظفين التي مرّ نقدها بيده (سلفة دفعها، تسديدٌ استلمه…) — داخلةٌ في صافيه
                              (collectors[i].employeeMoves.count > 0
                                  ? ' · ${'settle.collector_emp'.tr(namedArgs: {'n': '${collectors[i].employeeMoves.count}'})}'
                                  : ''),
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
///
/// «إلغاء تسديد» (١١ نوفمبر): حركة التسديد تحمل زرّ إلغائها ([voidAction] · [onVoid]) وشارة حالها ([voided] — «ملغى» بمبلغٍ
/// مشطوب)، وحركة الإلغاء نفسها (`debt_payment_void`) خارجةٌ بمبلغها. بلا المعاملات الثلاثة السطر كما كان حرفاً.
class MovementTile extends StatelessWidget {
  const MovementTile({
    super.key,
    required this.m,
    this.voided,
    this.voidAction = PaymentVoidAction.none,
    this.onVoid,
  });
  final BoxMovement m;

  /// حال هذا التسديد في قيد الإلغاء — أو null.
  final PaymentVoidItem? voided;
  final PaymentVoidAction voidAction;
  final VoidCallback? onVoid;

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
      'debt_payment_void' => LucideIcons.undo2,
      'emp_advance' || 'emp_withdraw' || 'emp_loan' || 'emp_repayment' || 'emp_payslip_recover' => LucideIcons.users,
      'emp_advance_void' || 'emp_withdraw_void' || 'emp_loan_void' || 'emp_repayment_void' => LucideIcons.undo2,
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
      'debt_payment_void' => 'settle.kind_debt_payment_void'.tr(),
      'emp_advance' => 'settle.kind_emp_advance'.tr(),
      'emp_withdraw' => 'settle.kind_emp_withdraw'.tr(),
      'emp_loan' => 'settle.kind_emp_loan'.tr(),
      'emp_repayment' => 'settle.kind_emp_repayment'.tr(),
      'emp_advance_void' => 'settle.kind_emp_advance_void'.tr(),
      'emp_withdraw_void' => 'settle.kind_emp_withdraw_void'.tr(),
      'emp_loan_void' => 'settle.kind_emp_loan_void'.tr(),
      'emp_repayment_void' => 'settle.kind_emp_repayment_void'.tr(),
      'emp_payslip_recover' => 'settle.kind_emp_payslip_recover'.tr(),
      _ => 'settle.kind_debt_payment'.tr(),
    };
    // بيع المواد: العنوان الزبون (أو «زبون»)، وما بيع يُقرأ من الوصف بسطر التفاصيل.
    // شراء المخزون من الصندوق: العنوان المادّة وكمّيّتها (الوصف بلا بادئته).
    final isSale = m.source == 'sale';
    final isPurchase = m.source == 'purchase';
    final buyTitle = isPurchase
        ? (m.description ?? '').replaceFirst(RegExp(r'^(?:إلغاء شراء|شراء مواد|استرجاع من المورّد|إلغاء استرجاع):\s*'), '').trim()
        : '';
    // حركة موظف: العنوان الموظّف وما قيل فيها (الوصف بلا بادئة نوعه — النوع بسطر التفاصيل).
    final isEmployee = m.source == 'employee';
    final empTitle = isEmployee
        ? (m.description ?? '').replaceFirst(RegExp(r'^[^:]{1,60}:\s*'), '').trim()
        : '';
    final title = m.kind == 'expense'
        ? (m.description ?? 'settle.kind_expense'.tr())
        : isEmployee
            ? (empTitle.isEmpty ? kindLabel : iso(empTitle))
        : isPurchase
            ? (buyTitle.isEmpty ? kindLabel : iso(buyTitle))
            : isSale
                ? (m.subscriber ?? 'sales.walkin'.tr())
                : (m.subscriber ?? '—');
    final who = m.employeeId == null
        ? 'settle.manager'.tr()
        : (m.employeeName ?? m.employeeUsername ?? 'settle.employee'.tr());
    final written = m.expenseDate ?? '';
    final v = voided;
    final voidedDone = v != null && v.isDone;
    final details = Text(
      isoJoin([
        kindLabel,
        if ((m.packageName ?? '').isNotEmpty) m.packageName!,
        // ما بيع (الوصف بلا بادئة «بيع:»/«إلغاء بيع:»).
        if (isSale && (m.description ?? '').isNotEmpty)
          m.description!.replaceFirst(RegExp(r'^(?:إلغاء بيع|بيع):\s*'), ''),
        // سطر الإلغاء منسوبٌ لمن استلم التسديد (من حصّته يخرج المبلغ) — «من حصّة فلان» فلا يُقرأ «فلان ألغى»
        m.kind == 'debt_payment_void' ? 'settle.pay_void_from_share'.tr(namedArgs: {'who': who}) : who,
        settleWhen(m.createdAt),
      ], ' · '),
      style: AppType.muted(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    // زرّ الفتح بلا معالجٍ لا يُعرض؛ والمقفل («لا صلاحيّة») لا يحتاج معالجاً.
    final action = voidAction == PaymentVoidAction.open && onVoid == null ? PaymentVoidAction.none : voidAction;
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
                // شارة الإلغاء أوّل سطر التفاصيل — لا سطر جديد ولا كرت يكبر، والاسم فوقها يبقى كاملاً بأضيق هاتف
                // (التفاصيل هي التي تُختصر).
                Row(
                  children: [
                    if (v != null) ...[
                      PaymentVoidBadge(item: v),
                      const SizedBox(width: Sp.x6),
                    ],
                    Expanded(child: details),
                  ],
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
            // الملغى: مبلغه مشطوبٌ خافت — لم يعد في الصندوق (سطر إلغائه يُخرجه)
            style: voidedDone
                ? AppType.bodyBold(color: AppColors.textLow).copyWith(
                    decoration: TextDecoration.lineThrough,
                    decorationColor: AppColors.textLow,
                  )
                : AppType.bodyBold(color: tone.fill),
          ),
          if (action != PaymentVoidAction.none) ...[
            const SizedBox(width: Sp.xxs),
            PaymentVoidRowButton(
              action: action,
              resume: v != null,
              onOpen: onVoid ?? () {},
            ),
          ],
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
