import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/employees_api.dart' show ElEmployeePerms;
import '../../services/permissions_service.dart';
import '../../services/provider_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// القفل الموحّد — ما يراه الموظّف مكانَ قسمٍ أو إجراءٍ لا يملك مفتاحه.
///
/// بلاغ ٢٠٢٦-١٠-١٤ (صاحب المشروع، لقطة رئيسيّة موظّف ايرث لنك): كانت
/// الأقسام المحجوبة **تختفي**، فتبقى بطاقتان ثمّ فراغٌ أبيض يبدو عطلاً.
/// والمطلوب: «القوائم تبقى بمكانها بس تظهر ما عنده صلاحيّة».
///
/// ── القواعد ──────────────────────────────────────────────────────────
/// 1. **المقفل لا يجلب**: البيانات بلا مفتاح لا تُطلب أصلاً (الخادم يردّ
///    403)، فلا «تعذّر الجلب» ولا صفرٌ ولا دوّارة — بل إطارٌ هادئ بقفل.
/// 2. **المقاس نفسه والمكان نفسه**: الحدّ والحشوة ونصف القطر كالعنصر
///    الحيّ؛ يتغيّر اللون (خافت) والطرف (قفل بدل السهم) فقط.
/// 3. **النقر لا يفتح شيئاً**: اهتزازةٌ كجيرانه ثمّ [showNoPermission].
///    النداء الأصليّ لا يُستدعى، فلا تنقّل ولا طلب شبكة.
/// 4. **المالك لا يتغيّر**: `Perms.has` صحيحٌ دائماً لغير الموظّف، فكلّ
///    `locked:` عنده false وشاشته كما هي حرفيّاً.
/// 5. ما ليس صلاحيّةً يبقى **مخفيّاً**: ميزةٌ لا يدعمها المزوّد (ايرث لنك)،
///    أو عنصرٌ لصاحب الحساب وحده، أو مفتاحٌ لا يُمنح لهذا الدور
///    ([permShown])، أو قسمٌ أخفاه المدير من «نطاق العرض».
///
/// ⚠️ في الاختبار: [showNoPermission] يضع مؤقّتاً للإخفاء، فبعد النقر على
/// عنصرٍ مقفل `await t.pump(const Duration(seconds: 3))` قبل نهاية الاختبار.

/// هل يُعرض العنصر المبوّب بـ[anyOf] أصلاً (مفتوحاً أو مقفلاً)؟
///
/// `true` إن ملك المستخدم أحد المفاتيح، **أو** أمكن أن يُمنحه — فيُعرض
/// مقفلاً بـ`locked: !Perms.hasAny(anyOf)`. و`false` = مفتاحٌ لا يُمنح لهذا
/// الدور أصلاً، فالعنصر يبقى مخفيّاً كما كان: «اطلبها من مديرك» لما لا
/// يستطيع المدير منحه وعدٌ كاذب.
///
/// موظّف ايرث لنك يُمنح [ElEmployeePerms.keys] وحدها (+ `whatsapp.send`
/// التابع لـ«إرسال واتساب»)؛ المدراء والإعدادات والبثّ والحذف… لا وجود لها
/// عنده. وغيره (موظّف ساس، مدير فرعيّ مقيَّد) يُمنح الكتالوج كلّه.
///
///   if (permShown(const ['managers.view']))
///     _ModuleCard(locked: !Perms.has('managers.view'), …)
bool permShown(Iterable<String> anyOf) {
  if (Perms.hasAny(anyOf)) return true;
  if (!(ProviderService.isEarthlink && Perms.isEmployee)) return true;
  return anyOf
      .any((k) => ElEmployeePerms.keys.contains(k) || k == 'whatsapp.send');
}

/// ألوان العنصر المقفل — من اللوحة وحدها، فتصحّ في الوضعين.
abstract final class LockedStyle {
  /// مربّع الأيقونة (بدل `tone.softBg`).
  static Color get box => AppColors.surfaceSunken;

  /// الأيقونة والقفل.
  static Color get glyph => AppColors.textLow;

  /// العنوان — يبقى مقروءاً، فهو ما يعرّف القسم.
  static Color get title => AppColors.textMid;

  /// الوصف والنصّ الثانويّ.
  static Color get subtitle => AppColors.textLow;
}

/// رسالة القفل: اهتزازةٌ خفيفة + شريطٌ طافٍ فوق كلّ المسارات.
///
/// على الطبقة الجذريّة (كـ`showSheetSnack`) فيُرى فوق الشيتات أيضاً — زرّ
/// مقفل داخل شيت «إضافة سريعة» أو «إجراءات أخرى» **لا يغلق الشيت**.
/// ولونه `brandSurface` كشريط التطبيق العامّ: ليس خطأً (لا أحمر) ولا نجاحاً.
///
/// [action] = إجراءٌ (زرّ/عمليّة) لا قسم — يغيّر الكلمة وحدها.
void showNoPermission(BuildContext context, {bool action = false}) {
  HapticFeedback.selectionClick();
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _LockedToast.show(
    overlay,
    (action ? 'locked.toast_action' : 'locked.toast').tr(),
  );
}

/// شريطٌ واحد في كلّ لحظة: النقرات المتتالية على عناصر مقفلة تستبدله
/// ولا تكدّسه فوق بعضه.
class _LockedToast {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(OverlayState overlay, String message) {
    _hide();
    final entry = OverlayEntry(builder: (c) => _build(c, message));
    _entry = entry;
    _timer = Timer(const Duration(milliseconds: 2600), _hide);
    overlay.insert(entry);
  }

  static void _hide() {
    _timer?.cancel();
    _timer = null;
    final e = _entry;
    _entry = null;
    if (e != null && e.mounted) e.remove();
  }

  static Widget _build(BuildContext context, String message) {
    return Positioned(
      left: Sp.lg,
      right: Sp.lg,
      // فوق شريط التبويبات وزرّ «+» (الإزاحة نفسها التي تأخذها القوائم)، فلا
      // يغطّي أسماء التبويبات ولا آخر صفٍّ في شيت «إضافة سريعة».
      bottom: Inset.tabBar(context) + Sp.sm,
      // منطقةٌ حيّة: قارئ الشاشة يقرأ الرسالة لحظة ظهورها — وإلّا ضاع على
      // مستخدم VoiceOver «اطلبها من مديرك» (اسم العنصر يقول «مقفل» فقط).
      child: Semantics(
        liveRegion: true,
        container: true,
        label: message,
        excludeSemantics: true,
        child: _material(message),
      ),
    );
  }

  static Widget _material(String message) {
    return Material(
      elevation: 8,
      color: AppColors.brandSurface,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: _hide,
        borderRadius: BorderRadius.circular(R.md),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
          child: Row(
            children: [
              const Icon(LucideIcons.lock, color: AppColors.onBrand, size: 18),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Text(
                  message,
                  style: AppType.bodyStrong(color: AppColors.onBrand),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// القفل الصغير — مكانَ السهم في الصفوف والبلاطات، وأمام نصّ القفل.
/// نوعٌ عامّ لتعدّه الاختبارات بـ`find.byType(PermLockIcon)`.
class PermLockIcon extends StatelessWidget {
  const PermLockIcon({super.key, this.size = 16, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Icon(
      LucideIcons.lock,
      size: size,
      color: color ?? LockedStyle.glyph,
      semanticLabel: 'locked.badge'.tr(),
    );
  }
}

/// شارة قفلٍ صغيرة على ركن أيقونة — للبلاطات العموديّة والأزرار حيث لا
/// طرفَ لسهمٍ يُستبدل (بلاطات المشترك الأربع، أزرار كارت الرصيد).
class PermLockBadge extends StatelessWidget {
  const PermLockBadge({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        PositionedDirectional(
          end: -5,
          bottom: -4,
          child: Container(
            width: 14,
            height: 14,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const PermLockIcon(size: 8),
          ),
        ),
      ],
    );
  }
}

/// نصّ القفل داخل إطار بطاقة — بلا أرقام، بلا لون خطأ.
///
/// `inline` (الافتراضي): سطران متراصّان بارتفاع رقمٍ + سطرٍ تحته، فنصف
/// شبكة الرصيد المقفل يساوي جاره الحيّ. `block`: قفلٌ كبير متوسّط فوق
/// عنوانٍ وتلميح — لمكانٍ كان يحمل قائمة (آخر النشاطات).
class LockedNotice extends StatelessWidget {
  const LockedNotice({super.key, this.message}) : block = false;
  const LockedNotice.block({super.key, this.message}) : block = true;

  /// الافتراضي `locked.short` (inline) أو `locked.view` (block).
  final String? message;
  final bool block;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (block) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: LockedStyle.box,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const PermLockIcon(size: 24),
          ),
          const SizedBox(height: Sp.sm),
          Text(
            message ?? 'locked.view'.tr(),
            textAlign: TextAlign.center,
            style: AppType.label(color: LockedStyle.title)
                .copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Sp.xs),
          Text(
            'locked.ask'.tr(),
            textAlign: TextAlign.center,
            style: AppType.muted(color: LockedStyle.subtitle)
                .copyWith(fontSize: 12.5),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const PermLockIcon(size: 14),
            const SizedBox(width: Sp.x6),
            Flexible(
              child: Text(
                message ?? 'locked.short'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(color: LockedStyle.title)
                    .copyWith(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: Sp.xs),
        Text(
          'locked.ask'.tr(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              AppType.muted(color: LockedStyle.subtitle).copyWith(fontSize: 11),
        ),
      ],
    );
  }
}

/// بطاقة لوحةٍ مقفلة — إطار البطاقة الحيّة نفسه (سطح + حدّ + نصف قطر +
/// حشوة) وعنوانها، وتحته [LockedNotice]. لا تجلب شيئاً: تُبنى **بدل**
/// البطاقة الحيّة لا حولها، لأنّ بناء الحيّة يُطلق نداءها.
///
/// [icon] = null → نقطةٌ صغيرة مكان الأيقونة (رأس كارت الإيرادات).
class LockedCard extends StatelessWidget {
  const LockedCard({
    super.key,
    required this.title,
    this.icon,
    this.block = false,
    this.message,
    this.footer,
    this.height,
    this.radius = R.lg,
    this.padding = const EdgeInsets.all(Sp.md),
  });

  final String title;
  final IconData? icon;
  final bool block;
  final String? message;

  /// سطرٌ يبقى مقروءاً تحت القفل (معلومةٌ يملكها الفاعل في البطاقة نفسها:
  /// «الكارتات N» تحت رصيدٍ مقفل). لا يُنقر وحده: النقرة للبطاقة كلّها.
  final Widget? footer;

  /// ارتفاعٌ ثابت حين يجب أن يطابق البطاقة الحيّة (وإلّا فبمحتواه).
  final double? height;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final notice = block
        ? LockedNotice.block(message: message)
        : LockedNotice(message: message);
    return Semantics(
      button: true,
      label: 'locked.a11y'.tr(args: [title]),
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showNoPermission(context),
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            height: height,
            width: double.infinity,
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (icon != null)
                      Container(
                        padding: const EdgeInsets.all(Sp.x6),
                        decoration: BoxDecoration(
                          color: LockedStyle.box,
                          borderRadius: BorderRadius.circular(R.sm),
                        ),
                        child: Icon(icon, color: LockedStyle.glyph, size: 14),
                      )
                    else
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: LockedStyle.glyph,
                          shape: BoxShape.circle,
                        ),
                      ),
                    const SizedBox(width: Sp.sm),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label(color: LockedStyle.title).copyWith(
                            fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Sp.sm),
                if (height != null)
                  Expanded(child: Center(child: notice))
                else if (block)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Sp.lg),
                    child: Center(child: notice),
                  )
                else
                  notice,
                if (footer != null) footer!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// غلافٌ احتياطيّ لعنصرٍ لا يملك نمطاً مقفلاً خاصّاً (حبّة، زرّ صغير):
/// يبقى في مكانه ومقاسه، يُعتَّم، وتُستبدل نقرته برسالة القفل.
///
/// ⚠️ الاحتياط لا القاعدة: البلاطات والصفوف والأزرار تأخذ `locked:` في
/// ودجتها (قفلٌ مكان السهم، ألوان [LockedStyle]) — أوضح من تعتيمٍ عامّ.
/// و`locked == false` يعيد [child] كما هو حرفيّاً.
class PermissionLocked extends StatelessWidget {
  const PermissionLocked({
    super.key,
    required this.locked,
    required this.child,
    this.action = true,
    this.label,
  });

  final bool locked;
  final Widget child;
  final bool action;

  /// اسم العنصر لقارئ الشاشة («تذكير» → «تذكير — مقفل»).
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;
    return Semantics(
      button: true,
      label: label == null
          ? 'locked.badge'.tr()
          : 'locked.a11y'.tr(args: [label!]),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showNoPermission(context, action: action),
        child: IgnorePointer(
          child: Opacity(opacity: 0.45, child: child),
        ),
      ),
    );
  }
}
