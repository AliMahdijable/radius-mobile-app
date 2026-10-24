import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/platform/desktop_layout.dart';
import '../../core/widgets/permission_locked.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// رأس صفحةٍ على الحاسبة بلغة الموقع: عنوانٌ كبير وسطرٌ تحته يميناً، وأزرار الصفحة يساراً.
class DeskPageHeader extends StatelessWidget {
  const DeskPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final Widget? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.title().copyWith(fontSize: 28, height: 1.2),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                subtitle!,
              ],
            ],
          ),
        ),
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: Sp.sm),
          actions[i],
        ],
      ],
    );
  }
}

/// سطرٌ خافت تحت عنوان الصفحة.
class DeskSubtitle extends StatelessWidget {
  const DeskSubtitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppType.body(color: AppColors.textMid).copyWith(fontSize: 14),
    );
  }
}

/// «الخميس · 2026/10/22» — أرقامٌ لا أسماء شهور (المالك: «تشرين١» لا يعرفها أغلب المستخدمين).
String deskToday([DateTime? now]) {
  const days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
  final d = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[d.weekday - 1]} · ${d.year}/${two(d.month)}/${two(d.day)}';
}

/// مربّع أيقونة بإطار (تحديث، اتّجاه الترتيب، فحص) — ارتفاع حقول الصفّ نفسه.
class DeskIconButton extends StatelessWidget {
  const DeskIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
            child: busy
                ? SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand),
                  )
                : Icon(icon, size: 18, color: AppColors.textHi),
          ),
        ),
      ),
    );
  }
}

/// اسم القسم ووصفه من القائمة الجانبيّة لصفحته الأولى — فرأسها يحمل وصف القسم كما في الموقع
/// دون أن تعرفه الصفحة نفسها.
class DeskPageInfo extends InheritedWidget {
  const DeskPageInfo({super.key, this.title, this.subtitle, required super.child});

  final String? title;
  final String? subtitle;

  static DeskPageInfo? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeskPageInfo>();

  @override
  bool updateShouldNotify(DeskPageInfo old) =>
      old.title != title || old.subtitle != subtitle;
}

/// شريط الصفحة: داخل غلاف الحاسبة رأسُ صفحةٍ كالموقع (عنوانٌ كبير ووصفٌ تحته، وأزرار الصفحة
/// والزرّ الأساسيّ يساراً، ورجوعٌ بإطار حين تكون مفتوحةً من غيرها)، وخارجه [mobile] كما هو حرفاً
/// — فالهاتف لا يتغيّر بشيء. العنوان: [title] ثمّ اسم القسم ثمّ نصّ عنوان [mobile].
PreferredSizeWidget deskPageBar(
  BuildContext context, {
  required AppBar mobile,
  String? title,
  String? subtitle,
  List<Widget>? actions,
  Widget? primary,
}) {
  if (!DesktopScope.of(context)) return mobile;
  final info = DeskPageInfo.of(context);
  final mobileTitle = mobile.title;
  final heading =
      title ?? info?.title ?? (mobileTitle is Text ? mobileTitle.data : null);
  if (heading == null) return mobile;
  final sub = subtitle ?? info?.subtitle;
  final canPop = ModalRoute.of(context)?.canPop ?? false;
  final rtl = Directionality.of(context) == TextDirection.rtl;
  final all = [...?(actions ?? mobile.actions), if (primary != null) primary];
  // تبويبات الصفحة (بوّابة المشترك…) تبقى تحت الرأس.
  final tabs = mobile.bottom;
  final head = Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.xl, Sp.lg, Sp.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (canPop) ...[
            DeskIconButton(
              icon: rtl ? LucideIcons.arrowRight : LucideIcons.arrowLeft,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: Sp.md),
          ],
          Expanded(
            child: DeskPageHeader(
              title: heading,
              subtitle: sub == null ? null : DeskSubtitle(sub),
              actions: all,
            ),
          ),
        ],
      ),
    );
  final headHeight = sub == null ? 92.0 : 104.0;
  return PreferredSize(
    preferredSize: Size.fromHeight(headHeight + (tabs?.preferredSize.height ?? 0)),
    child: tabs == null
        ? head
        : Column(
            children: [
              head,
              // التبويبات بعرض محتواها في بداية السطر — لا ممدودةً بعرض الصفحة كالهاتف.
              Container(
                color: AppColors.bg,
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: tabs,
                ),
              ),
            ],
          ),
  );
}

/// الزرّ الأساسيّ للصفحة (مدير جديد، إضافة صرفيّة…) — مكان زرّ الهاتف العائم على الحاسبة.
class DeskPrimaryButton extends StatelessWidget {
  const DeskPrimaryButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.locked = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SizedBox(
      height: 44,
      child: FilledButton.icon(
        onPressed: locked ? () => showNoPermission(context) : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: locked ? AppColors.surfaceSunken : AppColors.brand,
          foregroundColor: locked ? LockedStyle.title : AppColors.onBrand,
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
          textStyle: AppType.label().copyWith(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        icon: Icon(locked ? LucideIcons.lock : icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

/// بطاقاتٌ في أعمدةٍ بحسب العرض (٣ ثمّ ٢ ثمّ عمود) — بدل قائمةٍ تمتدّ بعرض الشاشة كلّه.
class DeskGrid extends StatelessWidget {
  const DeskGrid({
    super.key,
    required this.children,
    this.minTileWidth = 300,
    this.maxColumns = 3,
    this.spacing = Sp.md,
  });

  final List<Widget> children;
  final double minTileWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      var cols = ((c.maxWidth + spacing) / (minTileWidth + spacing)).floor();
      cols = cols.clamp(1, maxColumns);
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final child in children) SizedBox(width: w, child: child)],
      );
    });
  }
}

/// شريط الإجراء أسفل الصفحة: على الحاسبة زرٌّ بعرضٍ معقول في الطرف بدل زرٍّ بعرض الشاشة كلّه.
Widget deskFooter(BuildContext context, Widget bar) {
  if (!DesktopScope.of(context)) return bar;
  return Align(
    alignment: AlignmentDirectional.centerEnd,
    heightFactor: 1,
    child: SizedBox(width: 460, child: bar),
  );
}

/// مجموعة صفوفٍ مسطّحة (شريط الملخّص، صفوف القائمة): على الحاسبة بطاقةٌ بحدٍّ وزوايا داخل حشوة
/// الصفحة بدل شرائط تلتصق بحافّتَي المحتوى، وعلى الهاتف كما هي حرفاً.
class DeskSection extends StatelessWidget {
  const DeskSection({super.key, required this.children, this.gap = Sp.md, this.inset = Sp.lg});

  final List<Widget> children;

  /// حشوة الجانبين — بقدر بطاقات الصفحة التي تحتها لتصطفّ حوافّها.
  final double inset;

  /// الفراغ تحت البطاقة.
  final double gap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
    if (!DesktopScope.of(context)) return column;
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 0, inset, gap),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: column,
      ),
    );
  }
}

/// صفوف قائمةٍ في لوحة (منافذ، واجهات، عملاء، ONU): على الحاسبة جنباً إلى جنب ([maxColumns] أعمدة حين يتّسع)
/// بدل صفٍّ بعرض الصفحة كلّها نصفه فارغ؛ على الهاتف عمودٌ واحد كما هي حرفاً. كلّ سطرٍ من الأعمدة يصطفّ من الأعلى،
/// والصفوف تحتفظ بهوامشها (المسافة العموديّة منها).
class DeskRows extends StatelessWidget {
  const DeskRows({
    super.key,
    required this.children,
    this.minTileWidth = 420,
    this.maxColumns = 2,
    this.gap = Sp.sm,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final List<Widget> children;
  final double minTileWidth;
  final int maxColumns;
  final double gap;

  /// محاذاة العمود الواحد (الهاتف) — كما كانت في الـColumn الأصليّ.
  final CrossAxisAlignment crossAxisAlignment;

  /// عدد الأعمدة لعرضٍ [width] — 1 على الهاتف.
  static int columnsFor(BuildContext context, double width, {double minTileWidth = 420, int maxColumns = 2, double gap = Sp.sm}) {
    if (!DesktopScope.of(context)) return 1;
    final cols = ((width + gap) / (minTileWidth + gap)).floor();
    return cols.clamp(1, maxColumns);
  }

  @override
  Widget build(BuildContext context) {
    if (!DesktopScope.of(context) || children.length < 2) {
      return Column(crossAxisAlignment: crossAxisAlignment, children: children);
    }
    return LayoutBuilder(builder: (context, c) {
      final cols = columnsFor(context, c.maxWidth, minTileWidth: minTileWidth, maxColumns: maxColumns, gap: gap);
      if (cols == 1) return Column(crossAxisAlignment: crossAxisAlignment, children: children);
      return Column(children: [
        for (var i = 0; i < children.length; i += cols)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var k = 0; k < cols; k++) ...[
                if (k > 0) SizedBox(width: gap),
                Expanded(child: i + k < children.length ? children[i + k] : const SizedBox.shrink()),
              ],
            ],
          ),
      ]);
    });
  }
}
