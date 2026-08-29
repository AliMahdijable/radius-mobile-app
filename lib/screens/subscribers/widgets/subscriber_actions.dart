import 'package:flutter/material.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// صفّ الإجراءات السريعة + شيت «إجراءات أخرى» — الشريحة 4 من مخطّط
/// إعادة التصميم (2026-08-29).
///
/// المخطّط يستبدل شبكة العمليّات الضخمة (18 بلاطة دفعةً واحدة أسفل
/// الصفحة) بثلاث طبقات:
///   1. **أربع بلاطات** فوراً تحت بلوك الدين: تمديد · تعديل · تعطيل ·
///      المزيد. هذه الأربعة تغطّي ~80% من نقرات المدير اليوميّة.
///   2. **زرّ التجديد** الأساسي أسفل الصفحة (`SubscriberPrimaryAction`).
///   3. **شيت «إجراءات أخرى»** مجموعات مسمّاة تحمل الباقي كاملاً.
///
/// ⚠️ لا عمليّة تُسقَط: كلّ ما كان في الشبكة القديمة موجود إمّا كبلاطة
/// أو داخل الشيت. بوّابات `Perms` تبقى كما هي — بناء القائمة يحصل في
/// الشاشة، وهذا الملفّ يعرض ما يُسلَّم له فقط.

/// عنصر إجراء واحد — يُستعمل في البلاطة وفي صفّ الشيت معاً.
class SubAction {
  const SubAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.meta,
    this.busy = false,
  });

  final IconData icon;
  final String label;

  /// `null` → الصفّ يظهر معطّلاً (رماديّ، لا يستجيب). نستعمله حين
  /// تنقص `sub.idx` بدل إخفاء الإجراء تماماً — الاختفاء يربك المدير.
  final VoidCallback? onTap;

  /// لون الأيقونة والنصّ. الافتراضي `brandAccent` للإجراءات العاديّة؛
  /// مرّرْ `AppColors.error` لمجموعة الخطر و`warningFill` للتعطيل.
  final Color? color;

  /// نصّ خافت في طرف الصفّ — «١٨ حركة»، «-19.75 dBm»، اسم الباقة.
  final String? meta;

  /// أثناء التنفيذ: يستبدل الأيقونة بمؤشّر دائري ويقفل النقر.
  final bool busy;
}

/// مجموعة مسمّاة داخل شيت «إجراءات أخرى».
class SubActionGroup {
  const SubActionGroup(this.label, this.items);
  final String label;
  final List<SubAction> items;
}

/// ═══════════════ صفّ البلاطات الأربع ═══════════════
///
/// المخطّط: grid 4 أعمدة · gap 8 · بلاطة بيضاء r16 بحدّ 1px، حشوة
/// 12×6، عمود متمركز gap 7، أيقونة 22 ملوّنة فوق تسمية 11/w500.
///
/// نستعمل `Row`+`Expanded` لا `GridView`: العدد قد ينزل إلى ثلاثة حين
/// تنقص صلاحيّة، والشبكة الثابتة تترك فجوة بينما الصفّ يتمدّد بنظافة.
class SubscriberActionTiles extends StatelessWidget {
  const SubscriberActionTiles({super.key, required this.actions});
  final List<SubAction> actions;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (actions.isEmpty) return const SizedBox.shrink();
    final children = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      if (i > 0) children.add(const SizedBox(width: Sp.sm));
      children.add(Expanded(child: _ActionTile(action: actions[i])));
    }
    // ⚠️ `IntrinsicHeight` ليس تجميلاً: الصفّ يعيش داخل `ListView`، أي
    // ارتفاع غير محدود. و`CrossAxisAlignment.stretch` وحده يمرّر
    // `h=Infinity` للبلاطات فيرمي «BoxConstraints forces an infinite
    // height» ويترك الـRenderFlex بلا تخطيط — وحينها **يسقط تخطيط الـ
    // sliver كلّه فيختفي كلّ ما بعد الصفّ** (كارت الاتصال والجهاز وزرّ
    // التجديد). حادثة 2026-08-29.
    //
    // `IntrinsicHeight` يقيس أطول بلاطة ويقيّد الصفّ بها، فيبقى
    // `stretch` يسوّي ارتفاعات البلاطات بلا لانهاية.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});
  final SubAction action;

  @override
  Widget build(BuildContext context) {
    final enabled = action.onTap != null && !action.busy;
    final color =
        enabled ? (action.color ?? AppColors.brandAccent) : AppColors.textHint;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        onTap: enabled ? action.onTap : null,
        borderRadius: BorderRadius.circular(R.lg),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.border),
          ),
          padding:
              const EdgeInsets.symmetric(vertical: Sp.md, horizontal: Sp.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 22,
                width: 22,
                child: action.busy
                    ? Padding(
                        padding: const EdgeInsets.all(2),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    : Icon(action.icon, size: 22, color: color),
              ),
              const SizedBox(height: Sp.sm),
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppType.muted(
                  color: enabled ? AppColors.textBody : AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ═══════════════ زرّ الإجراء الأساسي أسفل الصفحة ═══════════════
///
/// المخطّط يسمّي هذا القسم «danger zone» لكنّه فعليّاً الإجراء الأهمّ:
/// زرّ ممتلئ بالبراند بارتفاع 50 و r17 — «تجديد الاشتراك».
class SubscriberPrimaryAction extends StatelessWidget {
  const SubscriberPrimaryAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final enabled = onTap != null && !busy;
    return SizedBox(
      height: H.button,
      child: Material(
        color: enabled ? AppColors.brand : AppColors.surfaceDisabled,
        borderRadius: BorderRadius.circular(R.button),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(R.button),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onBrand,
                    ),
                  )
                else
                  Icon(icon,
                      size: 20,
                      color: enabled ? AppColors.onBrand : AppColors.textHint),
                const SizedBox(width: Sp.sm),
                Text(
                  label,
                  style: AppType.button(
                    color: enabled ? AppColors.onBrand : AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ═══════════════ شيت «إجراءات أخرى» ═══════════════
///
/// المخطّط: سطح أبيض r30 أعلى · مقبض 42×4 · رأس (عنوان 16/w700 +
/// المعرّف 11.5 ltr) وزرّ إغلاق دائري 32 · ثمّ المجموعات: تسمية
/// 11/w600 خافتة فوق حاوية `surfaceSheet` r16 بحدّ خفيف تحمل الصفوف.
///
/// الشيت قابل للتمرير: المجموعات قد تتجاوز ارتفاع الشاشة حين تكون كلّ
/// الصلاحيّات مفتوحة (18 إجراءً).
Future<void> showMoreActionsSheet(
  BuildContext context, {
  required String subtitle,
  required List<SubActionGroup> groups,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (ctx) => _MoreActionsSheet(subtitle: subtitle, groups: groups),
  );
}

class _MoreActionsSheet extends StatelessWidget {
  const _MoreActionsSheet({required this.subtitle, required this.groups});
  final String subtitle;
  final List<SubActionGroup> groups;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final live = groups.where((g) => g.items.isNotEmpty).toList();
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(R.sheet)),
        boxShadow: Sh.sheet,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: Sp.md),
            Container(
              width: 42,
              height: H.grabber,
              decoration: BoxDecoration(
                color: AppColors.grabber,
                borderRadius: BorderRadius.circular(R.pill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('إجراءات أخرى',
                            style: AppType.sheetTitle().copyWith(fontSize: 16)),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          textDirection: TextDirection.ltr,
                          style: AppType.muted().copyWith(fontSize: 11.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _CloseCircle(onTap: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xxl),
                itemCount: live.length,
                separatorBuilder: (_, __) => const SizedBox(height: Sp.md),
                itemBuilder: (_, i) => _Group(group: live[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseCircle extends StatelessWidget {
  const _CloseCircle({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: H.closeBtn,
          height: H.closeBtn,
          child: Icon(Icons.close_rounded, size: 18, color: AppColors.textMid),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.group});
  final SubActionGroup group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: Sp.xs, bottom: Sp.sm),
          child: Text(group.label,
              style: AppType.pillLabel().copyWith(letterSpacing: 0)),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceSheet,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.dividerStrong),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xxs),
          child: Column(
            children: [
              for (var i = 0; i < group.items.length; i++) ...[
                if (i > 0) Divider(height: 1, color: AppColors.divider),
                _ActionRow(action: group.items[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action});
  final SubAction action;

  @override
  Widget build(BuildContext context) {
    final enabled = action.onTap != null && !action.busy;
    final color =
        enabled ? (action.color ?? AppColors.textBody) : AppColors.textHint;
    return InkWell(
      onTap: enabled
          ? () {
              // نغلق الشيت أوّلاً ثمّ ننفّذ — كلّ إجراء تقريباً يفتح شيتاً
              // آخر، وتركُ هذا مفتوحاً تحته يُنتج طبقتَي scrim.
              Navigator.of(context).pop();
              action.onTap!();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 19,
              height: 19,
              child: action.busy
                  ? Padding(
                      padding: const EdgeInsets.all(1.5),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: color),
                    )
                  : Icon(action.icon, size: 19, color: color),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.input(color: color)
                    .copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            if ((action.meta ?? '').isNotEmpty) ...[
              const SizedBox(width: Sp.sm),
              Text(
                action.meta!,
                style: AppType.muted(color: AppColors.textHint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(width: Sp.x6),
            Icon(Icons.chevron_left_rounded,
                size: 17, color: AppColors.borderStrong),
          ],
        ),
      ),
    );
  }
}
