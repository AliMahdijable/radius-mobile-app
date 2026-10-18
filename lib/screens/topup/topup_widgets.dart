import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/self_deposit_api.dart';
import '../../core/util/format.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

// ═════════════════════════ وصف النتيجة ═════════════════════════

/// ما تقوله بطاقة النتيجة — منطقٌ صافٍ يُختبر بلا رسم.
@immutable
class TopupResultView {
  const TopupResultView({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
    this.balanceLine,
    this.refLine,
    this.checkable = false,
  });

  final AppTone tone;
  final IconData icon;
  final String title;
  final String body;
  final String? balanceLine;
  final String? refLine;

  /// يستحقّ «تحقّق الآن».
  final bool checkable;
}

bool _arabic(String? s) => s != null && RegExp(r'[؀-ۿ]').hasMatch(s);

/// رقم العمليّة للمراجعة مع الشركة — ما أرسله الخادم، وإلّا ذيل المعرّف.
String? topupRef(SelfDepositOutcome o) {
  final ref = o.ref?.trim();
  if (ref != null && ref.isNotEmpty) return ref;
  final id = (o.psid ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (id.isEmpty) return null;
  return (id.length > 8 ? id.substring(id.length - 8) : id).toUpperCase();
}

/// نتيجة عمليّةٍ بكلامٍ يفهمه المدير.
///
/// ⚠️ **لا «فشل» إلّا بحكم:** ما لم يحسمه الخادم يُقال «قيد التحقّق» أو
/// «تعذّر التأكّد» — لا «لم يُخصم شيء» عن مالٍ لا نعرف مصيره. ورسالة
/// الخادم تُعرض إن كانت عربيّة (لا إنجليزيّ الساس الخام).
TopupResultView describeTopupOutcome(
  SelfDepositOutcome o, {
  required SelfDepositFlow flow,
  int? amount,
  String currency = 'د.ع',
  bool closedEarly = false,
}) {
  String money(num v) => '${formatIQD(v)} $currency';
  final serverText = _arabic(o.message) ? o.message!.trim() : null;
  final balanceLine =
      o.balance == null ? null : 'رصيدك الآن ${money(o.balance!)}';
  final ref = topupRef(o);
  final refLine = ref == null ? null : 'رقم العمليّة: $ref';

  if (o.offline) {
    final redirect = flow == SelfDepositFlow.redirect;
    return TopupResultView(
      tone: AppTone.warning,
      icon: LucideIcons.wifiOff,
      title: redirect ? 'لم يصل التأكيد بعد' : 'تعذّر التأكّد من النتيجة',
      body: redirect
          ? 'انقطع الاتصال بالخادم. الدفع محفوظٌ على هاتفك ويُعاد إرساله '
              'تلقائيّاً — اضغط «تحقّق الآن» حين يعود الاتصال.'
          : 'انقطع الاتصال قبل أن يصل الردّ، وقد تكون العمليّة تمّت — '
              'راجع رصيدك قبل أن تعيد المحاولة.',
      refLine: redirect ? refLine : null,
      checkable: redirect,
    );
  }

  switch (o.status) {
    case SelfDepositStatus.success:
      // المُضاف كما قاله الخادم وحده (حركة الساس، أو فرقٌ طابق المبلغ تماماً) —
      // لا المبلغ المطلوب: رسومٌ أو عمليّةٌ متزامنة قد تجعله غيره.
      final credited = o.credited;
      final String body;
      if (credited != null && credited > 0) {
        body = 'أُضيف ${money(credited)} إلى رصيد صفحتك.';
      } else {
        body = switch (flow) {
          SelfDepositFlow.pin => 'أُضيف رصيد الكارت إلى صفحتك.',
          SelfDepositFlow.redirect => 'تمّ الدفع وأُضيف الرصيد إلى صفحتك.',
          _ => 'أُضيف المبلغ إلى رصيد صفحتك.',
        };
      }
      return TopupResultView(
        tone: AppTone.success,
        icon: LucideIcons.circleCheck,
        title: 'تمّت إضافة الرصيد',
        body: body,
        balanceLine: balanceLine,
        refLine: flow == SelfDepositFlow.redirect ? refLine : null,
      );
    case SelfDepositStatus.failed:
      return TopupResultView(
        tone: AppTone.danger,
        icon: LucideIcons.circleX,
        title: 'لم تكتمل العمليّة',
        body: serverText ??
            switch (flow) {
              SelfDepositFlow.pin =>
                'رمز الكارت غير صحيح أو مستعمل — تأكّد منه وأعد المحاولة.',
              SelfDepositFlow.invoice => 'تعذّر إنشاء الفاتورة — أعد المحاولة.',
              _ => 'لم يكتمل الدفع بزين كاش. إن خُصم المبلغ من محفظتك '
                  'فراجع شركتك برقم العمليّة.',
            },
        balanceLine: balanceLine,
        refLine: flow == SelfDepositFlow.redirect ? refLine : null,
      );
    case SelfDepositStatus.pending:
    case SelfDepositStatus.awaiting:
      if (closedEarly && o.status == SelfDepositStatus.pending) {
        return TopupResultView(
          tone: AppTone.warning,
          icon: LucideIcons.hourglass,
          title: 'لم يكتمل الدفع؟',
          body: 'أغلقت صفحة الدفع قبل أن ترجع. إن لم تدفع فلم يُخصم شيء. '
              'وإن دفعت فاضغط «تحقّق الآن» بعد دقائق، وإن لم يُضَف الرصيد '
              'فراجع شركتك برقم العمليّة.',
          refLine: refLine,
          checkable: true,
        );
      }
      return TopupResultView(
        tone: AppTone.warning,
        icon: LucideIcons.hourglass,
        title: 'قيد التحقّق',
        body: serverText ??
            (o.status == SelfDepositStatus.awaiting
                ? 'ننتظر تأكيد زين كاش — يُضاف الرصيد عادةً خلال دقائق.'
                : 'لم يصل تأكيد الدفع بعد — يُضاف الرصيد حين يتأكّد.'),
        refLine: refLine,
        checkable: true,
      );
    case SelfDepositStatus.unverified:
      return TopupResultView(
        tone: AppTone.warning,
        icon: LucideIcons.triangleAlert,
        title: 'تعذّر التأكّد من النتيجة',
        body: serverText ??
            'قد تكون العمليّة تمّت — راجع رصيدك قبل أن تعيد المحاولة.',
        balanceLine: balanceLine,
        refLine: flow == SelfDepositFlow.redirect ? refLine : null,
        // «تحقّق» يقرأ سجلّ الشركة (حركة زين كاش/كوشك) — الفاتورة لا سجلّ لها.
        checkable: flow != SelfDepositFlow.invoice,
      );
    case SelfDepositStatus.expired:
      return TopupResultView(
        tone: AppTone.neutral,
        icon: LucideIcons.clock,
        title: 'انتهت مهلة العمليّة',
        body: serverText ??
            'لم يكتمل الدفع خلال المهلة. إن خُصم المبلغ من محفظتك فراجع '
                'شركتك برقم العمليّة.',
        refLine: refLine,
        // ليست نهائيّة: «تحقّق» يراجع سجلّ الشركة (دفعٌ وصل بإشعار زين كاش).
        checkable: true,
      );
    case SelfDepositStatus.invoice:
      return TopupResultView(
        tone: AppTone.info,
        icon: LucideIcons.receiptText,
        title: 'تمّ إنشاء الفاتورة',
        body: serverText ??
            'سدّدها في أقرب منفذ حسب التعليمات في الرسالة النصّيّة — '
                'يُضاف الرصيد بعد التسديد.',
        refLine: refLine,
      );
  }
}

// ═════════════════════════ الرصيد ═════════════════════════

/// رأس الشاشة: رصيد الصفحة الآن ولمن.
class TopupBalanceCard extends StatelessWidget {
  const TopupBalanceCard({
    super.key,
    required this.balance,
    required this.loading,
    required this.currency,
    this.pageLine,
    this.onRefresh,
  });

  final num? balance;
  final bool loading;
  final String currency;

  /// «ali · سوبرنت» — أيّ صفحةٍ يُشحن رصيدها (معزول الاتّجاه عند المستدعي).
  final String? pageLine;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.sm, Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(R.card),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.onBrandFill2,
              borderRadius: BorderRadius.circular(R.icon),
            ),
            child: const Icon(LucideIcons.wallet,
                color: AppColors.onBrand, size: 22),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('رصيد صفحتك',
                    style: AppType.label(color: AppColors.onBrandSecondary)),
                const SizedBox(height: Sp.xs),
                if (loading)
                  const SizedBox(
                    height: 26,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.onBrand),
                      ),
                    ),
                  )
                else
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Row(
                      textBaseline: TextBaseline.alphabetic,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      children: [
                        Text(
                          balance == null ? '—' : formatIQD(balance!),
                          textDirection: TextDirection.ltr,
                          style: AppType.amount(color: AppColors.onBrand)
                              .copyWith(fontSize: 22),
                        ),
                        const SizedBox(width: Sp.x6),
                        Text(currency,
                            style: AppType.body(
                                color: AppColors.onBrandSecondary)),
                      ],
                    ),
                  ),
                if ((pageLine ?? '').isNotEmpty) ...[
                  const SizedBox(height: Sp.xxs),
                  Text(
                    pageLine!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.muted(color: AppColors.onBrandSecondary)
                        .copyWith(fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: loading ? null : onRefresh,
            tooltip: 'تحديث',
            icon: const Icon(LucideIcons.refreshCw,
                color: AppColors.onBrandStrong, size: 18),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════ الوسائل ═════════════════════════

IconData topupMethodIcon(SelfDepositMethod m) => switch (m.internalName) {
      'zaincash' || 'zaincashv2' => LucideIcons.smartphone,
      'voucher' => LucideIcons.ticket,
      'kushok' => LucideIcons.creditCard,
      'tasdid' => LucideIcons.receiptText,
      _ => LucideIcons.externalLink,
    };

/// صفّ وسيلة دفع — المختارة بحدٍّ أخضر ونقطة، وما يعمل من لوحة الشركة
/// وحدها بسهمٍ خارجيّ لا نقطة.
class TopupMethodTile extends StatelessWidget {
  const TopupMethodTile({
    super.key,
    required this.method,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });

  final SelfDepositMethod method;
  final bool selected;
  final VoidCallback? onTap;

  /// يحلّ محلّ [SelfDepositMethod.hint] (وسيلتان بالاسم نفسه).
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final panel = !method.inApp;
    final on = selected && !panel;
    return Semantics(
      selected: on,
      button: true,
      child: Material(
        color: on ? AppColors.brandSoftBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(R.lg),
          child: Ink(
            padding:
                const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(
                color: on ? AppColors.brand : AppColors.border,
                width: on ? BW.selected : BW.normal,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: H.iconBox,
                  height: H.iconBox,
                  decoration: BoxDecoration(
                    color: on
                        ? AppColors.surface
                        : panel
                            ? AppColors.surfaceSunken
                            : AppColors.brandSoftBg,
                    borderRadius: BorderRadius.circular(R.icon),
                  ),
                  child: Icon(
                    topupMethodIcon(method),
                    size: 20,
                    color: panel ? AppColors.textLow : AppColors.brand,
                  ),
                ),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        method.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.rowLabelBold(
                            color: panel ? AppColors.textMid : AppColors.textHi),
                      ),
                      const SizedBox(height: Sp.xxs),
                      Text(
                        subtitle ?? method.hint,
                        style: AppType.muted(color: AppColors.textMid)
                            .copyWith(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.sm),
                if (panel)
                  Icon(LucideIcons.externalLink,
                      size: 16, color: AppColors.textLow)
                else
                  _Radio(on: on),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      width: H.checkbox,
      height: H.checkbox,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: on ? AppColors.brand : AppColors.borderStrong,
          width: on ? 6 : BW.selected,
        ),
      ),
    );
  }
}

// ═════════════════════════ البطاقات ═════════════════════════

/// بطاقة نتيجةٍ أو تنبيه — نغمةٌ خفيفة، عنوانٌ وسطر، وزرٌّ اختياريّ.
class TopupNoticeCard extends StatelessWidget {
  const TopupNoticeCard({
    super.key,
    required this.view,
    this.actionLabel,
    this.onAction,
    this.busy = false,
    this.onDismiss,
  });

  final TopupResultView view;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool busy;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final t = view.tone;
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.md),
      decoration: BoxDecoration(
        color: t.softBg,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: t.softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(view.icon, size: 20, color: t.fill),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(view.title,
                        style: AppType.cardTitleBold(color: t.onSoft)),
                    const SizedBox(height: Sp.xs),
                    Text(view.body,
                        style: AppType.body(color: AppColors.textBody)
                            .copyWith(height: 1.5)),
                    if (view.balanceLine != null) ...[
                      const SizedBox(height: Sp.x6),
                      Text(view.balanceLine!,
                          style: AppType.bodyStrong(color: AppColors.textHi)),
                    ],
                    if (view.refLine != null) ...[
                      const SizedBox(height: Sp.xs),
                      Text(view.refLine!,
                          style: AppType.muted(color: AppColors.textMid)),
                    ],
                  ],
                ),
              ),
              if (onDismiss != null)
                InkWell(
                  onTap: onDismiss,
                  borderRadius: BorderRadius.circular(R.pill),
                  child: Padding(
                    padding: const EdgeInsets.all(Sp.xxs),
                    child: Icon(LucideIcons.x, size: 16, color: AppColors.textMid),
                  ),
                ),
            ],
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: Sp.md),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SizedBox(
                height: H.chip,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onAction,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: t.onSoft,
                    side: BorderSide(color: t.softBorder),
                    backgroundColor: AppColors.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(R.md)),
                    padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                  ),
                  icon: busy
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: t.fill),
                        )
                      : Icon(LucideIcons.refreshCw, size: 15, color: t.fill),
                  label: Text(actionLabel!,
                      style: AppType.bodyStrong(color: t.onSoft)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// حالةٌ تملأ الشاشة (مقفلة/غير متاحة/خطأ) — إطارٌ هادئ بأيقونة وسطرين.
class TopupStateCard extends StatelessWidget {
  const TopupStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    this.action,
    this.locked = false,
  });

  final IconData icon;
  final String title;
  final String text;
  final Widget? action;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.xl, vertical: Sp.xxl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: locked ? AppColors.surfaceSunken : AppColors.brandSoftBg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon,
                size: 24, color: locked ? AppColors.textLow : AppColors.brand),
          ),
          const SizedBox(height: Sp.md),
          Text(title,
              textAlign: TextAlign.center,
              style: AppType.cardTitleBold(color: AppColors.textHi)),
          const SizedBox(height: Sp.xs),
          Text(text,
              textAlign: TextAlign.center,
              style: AppType.body(color: AppColors.textMid)
                  .copyWith(height: 1.5)),
          if (action != null) ...[
            const SizedBox(height: Sp.lg),
            action!,
          ],
        ],
      ),
    );
  }
}

/// بطاقة قسمٍ بعنوان.
class TopupSection extends StatelessWidget {
  const TopupSection({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppType.cardTitleBold(color: AppColors.textHi)),
          const SizedBox(height: Sp.md),
          ...children,
        ],
      ),
    );
  }
}

// ═════════════════════════ السجلّ ═════════════════════════

/// حال العمليّة بكلمة ونغمة — لصفّ السجلّ.
(String, AppTone) topupStatusChip(SelfDepositOutcome o) => switch (o.status) {
      SelfDepositStatus.success => ('تمّت', AppTone.success),
      SelfDepositStatus.failed => ('لم تكتمل', AppTone.danger),
      SelfDepositStatus.pending => ('قيد التحقّق', AppTone.warning),
      SelfDepositStatus.awaiting => ('بانتظار التأكيد', AppTone.warning),
      SelfDepositStatus.unverified => ('غير مؤكَّدة', AppTone.warning),
      SelfDepositStatus.expired => ('انتهت المهلة', AppTone.neutral),
      SelfDepositStatus.invoice => ('فاتورة', AppTone.info),
    };

/// صفّ عمليّةٍ في «آخر العمليّات» — الوسيلة والمبلغ، ثمّ الحال (بلونها)
/// والوقت؛ والمعلّقة تُنقر لـ«تحقّق» (سهم التحديث في طرفها).
///
/// الحال كلمةٌ ملوّنة في السطر الثاني لا حبّةٌ في الطرف: الحبّة كانت تأكل
/// عرض المبلغ فيُقصّ عند ٣٢٠ («زين كاش · 250,000 د…»).
class TopupHistoryRow extends StatelessWidget {
  const TopupHistoryRow({
    super.key,
    required this.record,
    required this.currency,
    this.onCheck,
    this.busy = false,
  });

  final SelfDepositRecord record;
  final String currency;
  final VoidCallback? onCheck;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final o = record.outcome;
    final money = o.credited ?? o.amount;
    final title = money != null && money > 0
        ? '${record.label} · ${formatIQD(money)} $currency'
        : record.label;
    final at = record.createdAt;
    final when = at == null
        ? null
        : humanMinutesAgo(DateTime.now().difference(at).inMinutes);
    final ref = topupRef(o);
    final rest = [
      if (when != null) when,
      if (ref != null && record.flow == SelfDepositFlow.redirect) 'رقم $ref',
    ].join(' · ');
    final (word, tone) = topupStatusChip(o);
    final row = Row(
      children: [
        Container(
          width: H.closeBtn,
          height: H.closeBtn,
          decoration: BoxDecoration(
            color: tone.softBg,
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Icon(
            switch (record.flow) {
              SelfDepositFlow.redirect => LucideIcons.smartphone,
              SelfDepositFlow.pin => LucideIcons.ticket,
              SelfDepositFlow.invoice => LucideIcons.receiptText,
              SelfDepositFlow.panel => LucideIcons.externalLink,
            },
            size: 16,
            color: tone.fill,
          ),
        ),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong(color: AppColors.textHi)),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: word,
                      style: AppType.pillBold(color: tone.onSoft)),
                  if (rest.isNotEmpty)
                    TextSpan(
                        text: ' · $rest',
                        style: AppType.muted(color: AppColors.textMid)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (onCheck != null) ...[
          const SizedBox(width: Sp.sm),
          if (busy)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.brandAccent),
            )
          else
            Icon(LucideIcons.refreshCw, size: 16, color: tone.fill),
        ],
      ],
    );
    if (onCheck == null) return row;
    return Semantics(
      button: true,
      label: '$title — $word — تحقّق',
      excludeSemantics: true,
      child: InkWell(
        onTap: busy ? null : onCheck,
        borderRadius: BorderRadius.circular(R.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.xxs),
          child: row,
        ),
      ),
    );
  }
}
