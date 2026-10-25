import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/bidi.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/copyable.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '_grade.dart';

// ══════════════════════════════════════════════════════════════
// لوحات الأجهزة على الحاسبة — قطعٌ مشتركة بين العلامات، من صفحة المايكروتك (f03dd6b8).
// المالك ٢٤ أكتوبر: «تغيير جذريّ بكلّ صفحات قسم الأجهزة… بشكل حاسبة وليس موبايل»، و٢٥ أكتوبر بصور «سكتر 1».
// صفّ أرقامٍ كبيرة بوحداتها وما يفسّرها، شريط حقائق، رأس قسمٍ بعدده، جداول كقوائم Winbox، ورسم الترفك
// بنافذةٍ ثابتة. الهاتف لا يستعمل شيئاً من هنا — مساره في كلّ لوحةٍ كما هو.
// ══════════════════════════════════════════════════════════════

/// بطاقة رقمٍ كبير: أيقونةٌ بلون الحالة وعنوانها، ثمّ القيمة، وتحتها ما يفسّرها.
class DeskMetricTile extends StatelessWidget {
  const DeskMetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.value,
    this.footer,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Widget value;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Color.alphaBlend(color.withValues(alpha: AppColors.isDark ? 0.22 : 0.14), AppColors.surface),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textMid)),
          ),
        ]),
        const SizedBox(height: 10),
        value,
        const Spacer(),
        if (footer != null) ...[const SizedBox(height: Sp.sm), footer!],
      ]),
    );
  }
}

/// الرقم الكبير بوحدته يساراً إلى يمين («5.8 Mbps»، «38 °C») فلا يتفكّك في الفقرة العربيّة. «—» = لا يُعرف.
class DeskBigValue extends StatelessWidget {
  const DeskBigValue(this.value, this.unit, {super.key, this.color});

  final String value;
  final String unit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final known = value != '—';
    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 24,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: known ? (color ?? AppColors.textHi) : AppColors.textLow,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ),
        if (known && unit.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(unit, textDirection: TextDirection.ltr, style: AppType.body(color: AppColors.textLow)),
        ],
      ],
    );
  }
}

/// مكان الرقم قبل أن يُعرف: «يُحسب…» (السرعة فرقُ قراءتين) أو «يقيس…» — لا «—» كأنّه معطّل.
class DeskPendingValue extends StatelessWidget {
  const DeskPendingValue(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.statValue(color: AppColors.textLow));
}

/// سطر التفسير تحت الرقم.
Widget deskSub(String text, {Color? color}) => Text(text,
    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted(color: color ?? AppColors.textLow));

/// كلمة الحكم بحسب الرتبة («طبيعيّة/مرتفعة/حرجة»).
String deskGradeWord(AppTone t, {required String ok, required String warn, required String bad}) => switch (t) {
      AppTone.success => ok,
      AppTone.warning => warn,
      AppTone.danger => bad,
      _ => '',
    };

/// نسبةٌ مئويّة بشريطها (المعالج، الذاكرة) — الأقلّ أفضل. null = لا يقرؤها هذا الجهاز.
class DeskPercentTile extends StatelessWidget {
  const DeskPercentTile({super.key, required this.icon, required this.label, required this.percent, this.sub});

  final IconData icon;
  final String label;
  final double? percent;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final p = percent;
    if (p == null) {
      return DeskMetricTile(
        icon: icon,
        label: label,
        color: AppColors.textLow,
        value: const DeskBigValue('—', ''),
        footer: deskSub(sub ?? 'لا يقرؤها هذا الجهاز'),
      );
    }
    final tone = Grade.percentLowerBetter(p);
    return DeskMetricTile(
      icon: icon,
      label: label,
      color: tone.fill,
      value: DeskBigValue('${p.round()}', '%'),
      footer: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(R.pill),
          child: LinearProgressIndicator(
            value: (p / 100).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(tone.fill),
          ),
        ),
        if (sub != null) ...[const SizedBox(height: 6), deskSub(sub!)],
      ]),
    );
  }
}

/// حرارة الجهاز بحكمها. null = لا يقرؤها هذا الجهاز.
class DeskTempTile extends StatelessWidget {
  const DeskTempTile({super.key, required this.celsius, this.label = 'الحرارة'});

  final num? celsius;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = celsius;
    final text = t == null || t <= 0 ? null : (t is int ? '$t' : t.toStringAsFixed(0));
    final tone = Grade.temperature(t);
    final known = text != null;
    return DeskMetricTile(
      icon: LucideIcons.thermometer,
      label: label,
      color: known ? tone.fill : AppColors.textLow,
      value: DeskBigValue(text ?? '—', '°C', color: tone.fill),
      footer: deskSub(!known ? 'لا يقرؤها هذا الجهاز' : deskGradeWord(tone, ok: 'طبيعيّة', warn: 'مرتفعة', bad: 'حرجة')),
    );
  }
}

/// أعلى تنزيل/رفع: الرقم بوحدته وتحته الواجهة التي تحمله. [measuring]: لا قراءتان بعد ⇒ «يُحسب…».
class DeskRateTile extends StatelessWidget {
  const DeskRateTile({
    super.key,
    required this.down,
    required this.bps,
    this.source,
    this.measuring = false,
    this.label,
    this.note,
  });

  final bool down;
  final int? bps;
  final String? source;
  final bool measuring;
  final String? label;

  /// سطرٌ تحت الرقم حين لا واجهة تُسمّى («مجموع منافذ PON»، «جزئيّ»).
  final String? note;

  @override
  Widget build(BuildContext context) {
    final color = down ? AppColors.chartLine : AppColors.info;
    final v = bps;
    return DeskMetricTile(
      icon: down ? LucideIcons.arrowDown : LucideIcons.arrowUp,
      label: label ?? (down ? 'أعلى تنزيل' : 'أعلى رفع'),
      color: color,
      value: v == null
          ? DeskPendingValue(measuring ? 'يُحسب…' : '—')
          : () {
              final (n, u) = deskBpsParts(v);
              return DeskBigValue(n, u, color: color);
            }(),
      footer: v == null
          ? deskSub(measuring ? 'بعد القراءة الثانية' : 'لا ترافيك')
          : (source == null || source!.isEmpty)
              ? (note == null ? null : deskSub(note!))
              : Align(alignment: AlignmentDirectional.centerStart, child: DeskPill(source!, AppTone.neutral)),
    );
  }
}

/// صفّ البطاقات: كلّها في صفٍّ واحد إن اتّسع (≥ [minTileWidth] لكلّ بطاقة) وإلّا نصفين — وكلّها بارتفاعٍ واحد.
class DeskTilesRow extends StatelessWidget {
  const DeskTilesRow({super.key, required this.tiles, this.minTileWidth = 140});

  final List<Widget> tiles;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final n = tiles.length;
      final perRow = c.maxWidth >= n * minTileWidth + (n - 1) * Sp.sm ? n : (n / 2).ceil();
      return Column(children: [
        for (var i = 0; i < n; i += perRow) ...[
          if (i > 0) const SizedBox(height: Sp.sm),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var k = i; k < i + perRow; k++) ...[
                if (k > i) const SizedBox(width: Sp.sm),
                // صفٌّ أخير ناقص يحتفظ بعرض البطاقة نفسه
                Expanded(child: k < n ? tiles[k] : const SizedBox.shrink()),
              ],
            ]),
          ),
        ],
      ]);
    });
  }
}

/// حقيقةٌ في شريط الحقائق: أيقونة وعنوان وقيمة.
typedef DeskBannerFact = ({IconData icon, String label, String value});

/// الشريط العريض تحت رأس اللوحة: الطراز والنظام و«يعمل منذ …».
class DeskFactsBanner extends StatelessWidget {
  const DeskFactsBanner({super.key, required this.facts, this.margin = EdgeInsets.zero});

  final List<DeskBannerFact> facts;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    Widget fact(DeskBannerFact f) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(f.icon, size: 15, color: AppColors.brand),
          const SizedBox(width: 6),
          Text(f.label, style: AppType.label(color: AppColors.textMid)),
          const SizedBox(width: 6),
          // معزولةٌ باتّجاهها: «15.0(2)SE11» لا تنقلب أقواسها في السطر العربيّ.
          Text(iso(f.value), style: AppType.rowValue(color: AppColors.textHi)),
        ]);
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.brandSoftBg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.brandSoftBorder),
      ),
      child: Wrap(spacing: Sp.xl, runSpacing: Sp.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final f in facts)
          if (f.value.isNotEmpty) fact(f),
      ]),
    );
  }
}

/// حبّةٌ صغيرة (اسم واجهة، حالة، عدد).
class DeskPill extends StatelessWidget {
  const DeskPill(this.text, this.tone, {super.key});

  final String text;
  final AppTone tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: tone.softBg,
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: tone.softBorder),
        ),
        child: Text(iso(text), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.pillBold(color: tone.onSoft)),
      );
}

/// خليّةٌ بلا قيمة.
Widget deskDash() => Text('—', style: AppType.body(color: AppColors.textLow));

/// رأس قسمٍ قابلٍ للطيّ: أيقونةٌ في مربّع، العنوان، العدد، وتلميحٌ اختياريّ.
class DeskSectionHeader extends StatelessWidget {
  const DeskSectionHeader({super.key, required this.icon, required this.title, this.count, this.hint});

  final IconData icon;
  final String title;
  final int? count;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.sm)),
        child: Icon(icon, size: 16, color: AppColors.brand),
      ),
      const SizedBox(width: 10),
      Text(title, style: AppType.cardTitleBold()),
      if (count != null) ...[
        const SizedBox(width: 8),
        DeskPill('$count', AppTone.neutral),
      ],
      if (hint != null) ...[
        const SizedBox(width: 10),
        Flexible(
          child: Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted(color: AppColors.textLow)),
        ),
      ],
    ]);
  }
}

/// حقيقةٌ بعنوانها فوقها. [ltr]: قيمةٌ لاتينيّة («5535 MHz») معزولةٌ فلا تنقلب؛ [copy]: تُنسخ بضغطٍ مطوّل.
class DeskFact extends StatelessWidget {
  const DeskFact(this.label, this.value, {super.key, this.ltr = false, this.copy = false, this.color});

  final String label;
  final String value;
  final bool ltr;
  final bool copy;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Text(ltr ? iso(value) : value,
        maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.rowValue(color: color ?? AppColors.textHi));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: AppType.label(color: AppColors.textMid)),
      const SizedBox(height: 3),
      copy ? Copyable(label: label, value: value, child: text) : text,
    ]);
  }
}

/// حقائق في أعمدة بحسب العرض (٣ ثمّ ٢ ثمّ عمود) — بدل صفوف «عنوان … قيمة» بعرض الصفحة.
class DeskFactsGrid extends StatelessWidget {
  const DeskFactsGrid({super.key, required this.facts, this.maxColumns = 3});

  final List<Widget> facts;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final fit = c.maxWidth >= 480 ? 3 : (c.maxWidth >= 300 ? 2 : 1);
      final cols = math.min(fit, maxColumns);
      final width = (c.maxWidth - Sp.md * (cols - 1)) / cols;
      return Wrap(spacing: Sp.md, runSpacing: Sp.md, children: [
        for (final f in facts) SizedBox(width: width, child: f),
      ]);
    });
  }
}

/// بطاقةٌ داخل قسم (لوحة لاسلكيّة، وصلة، موقع): عنوانٌ بأيقونة وحالةٍ اختياريّة ثمّ محتواها.
class DeskInfoCard extends StatelessWidget {
  const DeskInfoCard({super.key, required this.icon, required this.title, required this.child, this.trailing, this.iconColor});

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: iconColor ?? AppColors.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.cardTitleBold()),
          ),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: Sp.md),
        child,
      ]),
    );
  }
}

/// قسمان جنباً إلى جنب (العريض ثمّ الضيّق، ٣:٢) بدل قسمين بعرض الصفحة؛ الموجود وحده بعرضها.
Widget deskSideBySide(Widget? wide, Widget? narrow, {int wideFlex = 3, int narrowFlex = 2}) {
  if (wide == null && narrow == null) return const SizedBox.shrink();
  if (wide == null || narrow == null) return (wide ?? narrow)!;
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(flex: wideFlex, child: wide),
    const SizedBox(width: Sp.md),
    Expanded(flex: narrowFlex, child: narrow),
  ]);
}

/// رأس اللوحة على الحاسبة: أيقونة، «مراقبة حيّة · …»، حالة المراقبة بنقطةٍ تخفت أثناء الجلب، وزرّا التحديث والإيقاف.
class DeskLiveHeader extends StatelessWidget {
  const DeskLiveHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.monitoring,
    required this.loading,
    required this.status,
    required this.onRefresh,
    required this.onToggle,
  });

  final IconData icon;
  final String title;
  final bool monitoring;
  final bool loading;
  final String status;
  final VoidCallback? onRefresh;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.sm)),
        child: Icon(icon, size: 16, color: AppColors.brandAccent),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyBold()),
          const SizedBox(height: 2),
          Row(children: [
            AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              opacity: loading ? 0.35 : 1.0,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                    color: monitoring ? AppColors.success : AppColors.textLow, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(status,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted(color: AppColors.textMid)),
            ),
          ]),
        ]),
      ),
      IconButton(
        onPressed: onRefresh,
        icon: Icon(LucideIcons.refreshCw, size: 16, color: AppColors.brandAccent),
        tooltip: 'تحديث الآن',
      ),
      IconButton(
        onPressed: onToggle,
        icon: Icon(monitoring ? LucideIcons.pause : LucideIcons.play,
            size: 16, color: monitoring ? AppColors.error : AppColors.success),
        tooltip: monitoring ? 'إيقاف المراقبة' : 'بدء المراقبة',
      ),
    ]);
  }
}

/// تنبيهٌ داخل اللوحة (آخر تحديثٍ فشل، الوصلة غير قائمة…).
class DeskNotice extends StatelessWidget {
  const DeskNotice({super.key, required this.icon, required this.text, required this.tone});

  final IconData icon;
  final String text;
  final AppTone tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
        decoration: BoxDecoration(
          color: tone.softBg,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: tone.softBorder),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: tone.fill),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(color: tone.onSoft)),
          ),
        ]),
      );
}

/// البطاقة الرئيسيّة للّوحة على الحاسبة: الرأس والحقائق والأرقام والرسم في صندوقٍ واحد.
class DeskPanelCard extends StatelessWidget {
  const DeskPanelCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const SizedBox(height: Sp.md),
            c,
          ],
        ]),
      );
}

/// جدولٌ كقوائم Winbox: رأسٌ بأسماء الأعمدة وصفوفٌ تتلوّن تحت الفأرة. [columns]: (العنوان، الوزن).
class DeskTable extends StatelessWidget {
  const DeskTable({super.key, required this.columns, required this.rows});

  final List<(String, int)> columns;
  final List<List<Widget>> rows;

  /// خلايا صفٍّ بأوزان أعمدته.
  static Widget line(List<(String, int)> columns, List<Widget> cells) => Row(children: [
        for (var k = 0; k < columns.length; k++) ...[
          if (k > 0) const SizedBox(width: Sp.md),
          Expanded(flex: columns[k].$2, child: cells[k]),
        ],
      ]);

  /// رأس الجدول بأسماء الأعمدة.
  static Widget header(List<(String, int)> columns) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: line(columns, [
          for (final c in columns)
            Text(c.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textMid)),
        ]),
      );

  static BoxDecoration get _frame => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _frame,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header(columns),
        for (var r = 0; r < rows.length; r++) _DeskTableRow(divider: r > 0, child: line(columns, rows[r])),
      ]),
    );
  }
}

/// جدولٌ طويل (مئات الصفوف — مشتركو الأولت): الرأس ثابت والصفوف قائمةٌ افتراضيّة تُبنى الظاهرة منها وحدها،
/// بارتفاعٍ أقصى [maxHeight] وشريط تمرير.
class DeskVirtualTable extends StatelessWidget {
  const DeskVirtualTable({
    super.key,
    required this.columns,
    required this.itemCount,
    required this.cells,
    required this.maxHeight,
    this.controller,
    this.storageKey,
    this.rowKey,
  });

  final List<(String, int)> columns;
  final int itemCount;
  final List<Widget> Function(int index) cells;
  final double maxHeight;
  final ScrollController? controller;
  final Key? storageKey;

  /// مفتاح الصفّ — يُبقي حالته (التظليل) معه حين يتغيّر الترتيب أو التصفية.
  final Key Function(int index)? rowKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: DeskTable._frame,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DeskTable.header(columns),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Scrollbar(
            controller: controller,
            thumbVisibility: true,
            child: ListView.builder(
              key: storageKey,
              controller: controller,
              primary: false,
              shrinkWrap: true,
              itemCount: itemCount,
              itemBuilder: (context, i) => _DeskTableRow(
                key: rowKey?.call(i),
                divider: i > 0,
                child: DeskTable.line(columns, cells(i)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _DeskTableRow extends StatefulWidget {
  const _DeskTableRow({super.key, required this.divider, required this.child});

  final bool divider;
  final Widget child;

  @override
  State<_DeskTableRow> createState() => _DeskTableRowState();
}

class _DeskTableRowState extends State<_DeskTableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
        decoration: BoxDecoration(
          color: _hover ? AppColors.surfaceSunken : null,
          border: widget.divider ? Border(top: BorderSide(color: AppColors.borderSoft)) : null,
        ),
        child: widget.child,
      ),
    );
  }
}

/// شريط البحث فوق جدول المنافذ: حقلٌ بعرضٍ معقول (لا بعرض الصفحة) و«الموصولة فقط».
class DeskPortFilterBar extends StatelessWidget {
  const DeskPortFilterBar({
    super.key,
    required this.hint,
    required this.connectedOnly,
    required this.onQuery,
    required this.onConnectedOnly,
    this.chipLabel = 'الموصولة فقط',
  });

  final String hint;
  final String chipLabel;
  final bool connectedOnly;
  final ValueChanged<String> onQuery;
  final ValueChanged<bool> onConnectedOnly;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(
        width: 320,
        height: 36,
        child: TextField(
          style: AppType.body(),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: AppType.body(color: AppColors.textLow),
            prefixIcon: Icon(LucideIcons.search, size: 16, color: AppColors.textLow),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.sm),
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.sm),
              borderSide: BorderSide(color: AppColors.border),
            ),
          ),
          onChanged: onQuery,
        ),
      ),
      const SizedBox(width: Sp.sm),
      FilterChip(
        label: Text(chipLabel, style: AppType.body()),
        selected: connectedOnly,
        onSelected: onConnectedOnly,
      ),
    ]);
  }
}

/// «+ 12 عميلاً آخر» تحت جدولٍ مقصوص.
Widget deskMoreRows(int more, {required String one, required String two, required String few, required String many}) =>
    Padding(
      padding: const EdgeInsets.only(top: Sp.sm),
      child: Text('+ ${arCount(more, one: one, two: two, few: few, many: many)}',
          style: AppType.muted(color: AppColors.textLow)),
    );

/// خليّة الاسم بنقطة حالة وسطرٍ ثانٍ صغير (النوع · الحالة).
class DeskNameCell extends StatelessWidget {
  const DeskNameCell({super.key, required this.name, required this.sub, required this.tone, this.dim = false, this.copy = false});

  final String name;
  final String sub;
  final AppTone tone;
  final bool dim;
  final bool copy;

  @override
  Widget build(BuildContext context) {
    final color = dim ? AppColors.textLow : tone.fill;
    final title = Text(name,
        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.rowValue(color: dim ? AppColors.textLow : AppColors.textHi));
    return Row(children: [
      Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          copy ? Copyable(label: 'الاسم', value: name, child: title) : title,
          if (sub.isNotEmpty)
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted(color: color)),
        ]),
      ),
    ]);
  }
}

/// خليّة سرعة (تنزيل/رفع) بشريطٍ نسبةً لأعلاها في الجدول. null ⇒ «يُحسب…» إن كان المنفذ يعمل، وإلّا «—».
class DeskRateCell extends StatelessWidget {
  const DeskRateCell({super.key, required this.bps, required this.down, required this.max, this.live = true});

  final int? bps;
  final bool down;
  final int max;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final v = bps;
    if (v == null) {
      return Text(live ? 'يُحسب…' : '—', style: AppType.body(color: AppColors.textLow));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(iso(deskBpsFull(v)), style: AppType.rowValue(color: v > 0 ? AppColors.textHi : AppColors.textLow)),
      const SizedBox(height: 5),
      ClipRRect(
        borderRadius: BorderRadius.circular(R.pill),
        child: LinearProgressIndicator(
          value: max > 0 ? (v / max).clamp(0.0, 1.0) : 0,
          minHeight: 4,
          backgroundColor: AppColors.borderSoft,
          valueColor: AlwaysStoppedAnimation(down ? AppColors.chartLine : AppColors.info),
        ),
      ),
    ]);
  }
}

/// نصٌّ لاتينيّ في خليّة (ماك، IP) بأرقامٍ متساوية العرض، يُنسخ بضغطٍ مطوّل أو زرٍّ أيمن.
class DeskMonoCell extends StatelessWidget {
  const DeskMonoCell(this.value, {super.key, required this.label, this.copy = true});

  final String value;
  final String label;
  final bool copy;

  @override
  Widget build(BuildContext context) {
    final mono = AppType.body(color: AppColors.textMid).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final text = Text(iso(value), maxLines: 1, overflow: TextOverflow.ellipsis, style: mono);
    return copy ? Copyable(label: label, value: value, child: text) : text;
  }
}

/// سرعتا الوصلة في خليّة: «↓270 ↑300 Mbps» بسهمين ملوّنين — لا نصٌّ واحد يُقصّ.
class DeskRatePair extends StatelessWidget {
  const DeskRatePair({super.key, required this.rx, required this.tx, this.unit = 'Mbps'});

  final int rx;
  final int tx;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(LucideIcons.arrowDown, size: 12, color: AppColors.chartLine),
      const SizedBox(width: 2),
      Text('$rx', style: AppType.rowValue(color: AppColors.textHi)),
      const SizedBox(width: 8),
      Icon(LucideIcons.arrowUp, size: 12, color: AppColors.info),
      const SizedBox(width: 2),
      Text('$tx', style: AppType.rowValue(color: AppColors.textHi)),
      const SizedBox(width: 4),
      Flexible(child: Text(unit, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted(color: AppColors.textLow))),
    ]);
  }
}

/// قيمةٌ بلونٍ ونقطة (الإشارة «-56 dBm»، الضوء «-21.4 dBm»).
class DeskDotValue extends StatelessWidget {
  const DeskDotValue({super.key, required this.value, required this.unit, required this.color});

  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Flexible(
        child: Text(iso(value), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.rowValue(color: color)),
      ),
      if (unit.isNotEmpty) ...[
        const SizedBox(width: 3),
        Text(unit, style: AppType.muted(color: AppColors.textLow)),
      ],
    ]);
  }
}

// ══════════════════════════════════════════════════════════════
// رسم الترفك على الحاسبة — كرسم المايكروتك: نافذةٌ ثابتة بآخر [capacity] قراءة تمتلئ من طرف «الآن»،
// التنزيل أخضر الرسوم والرفع أزرق، أعلى المحور مستدير، محور وقت، ومكانه محجوزٌ من أوّل لحظة.
// ══════════════════════════════════════════════════════════════

/// عيّنة الرسم: تنزيلٌ ورفعٌ بالبت/ثانية.
typedef DeskTrafficSample = ({int rx, int tx});

class DeskTrafficCard extends StatelessWidget {
  const DeskTrafficCard({
    super.key,
    required this.samples,
    required this.capacity,
    required this.interval,
    this.subtitle,
    this.title = 'سير الترفك',
    this.rxLabel = 'تنزيل',
    this.txLabel = 'رفع',
  });

  /// الأقدم أوّلاً. rx = التنزيل (أو الوارد)، tx = الرفع (أو الصادر).
  final List<DeskTrafficSample> samples;

  /// عدد خانات النافذة.
  final int capacity;

  /// الفاصل بين قراءتين.
  final Duration interval;

  /// ما يقيسه الرسم («أعلى واجهةٍ في كلّ لحظة»، «الوصلة اللاسلكيّة»…).
  final String? subtitle;

  /// السويتش: «حِمل المنافذ» و«وارد/صادر» — ما يصدر من منفذٍ واردٌ على جاره، فلا «تنزيل» ولا «رفع».
  final String title;
  final String rxLabel;
  final String txLabel;

  @override
  Widget build(BuildContext context) {
    final shown = samples.length > capacity ? samples.sublist(samples.length - capacity) : samples;
    final n = shown.length;
    final first = capacity - n;
    final lastX = (capacity - 1).toDouble();
    final rxSpots = <FlSpot>[];
    final txSpots = <FlSpot>[];
    for (var i = 0; i < n; i++) {
      final x = (first + i).toDouble();
      rxSpots.add(FlSpot(x, math.max(shown[i].rx, 0).toDouble()));
      txSpots.add(FlSpot(x, math.max(shown[i].tx, 0).toDouble()));
    }
    final peak = shown.fold<int>(0, (m, s) => math.max(m, math.max(s.rx, s.tx)));
    final maxY = _niceCeil(peak * 1.15);
    final rxColor = AppColors.chartLine;
    final txColor = AppColors.info;
    final windowMin = math.max(1, (capacity * interval.inSeconds / 60).round());

    final Widget chart = n < 2
        ? Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand)),
              const SizedBox(width: 8),
              Text('تُجمع القراءات — يظهر الرسم بعد ثوانٍ', style: AppType.body(color: AppColors.textMid)),
            ]),
          )
        : RepaintBoundary(
            child: LineChart(
              duration: Duration.zero,
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (_) => FlLine(color: AppColors.borderSoft, strokeWidth: 0.5),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: lastX / 2,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        child: Text(
                          value >= lastX
                              ? 'الآن'
                              : 'قبل ${arMinutes(value <= 0 ? windowMin : math.max(1, (windowMin / 2).round()))}',
                          style: AppType.micro(color: AppColors.textLow),
                        ),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      interval: maxY / 4,
                      getTitlesWidget: (value, _) =>
                          Text(deskBpsShort(value.toInt()), style: AppType.micro(color: AppColors.textLow)),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minY: 0,
                maxY: maxY,
                minX: 0,
                maxX: lastX,
                // الرفع أوّلاً فيُرسم تحت، والتنزيل فوقه بتعبئةٍ شفّافة — التداخل يظهر بلونٍ مختلط.
                lineBarsData: [_line(txSpots, txColor, lastX), _line(rxSpots, rxColor, lastX)],
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.textHi.withValues(alpha: 0.9),
                    getTooltipItems: (spots) => spots.map((s) {
                      final isTx = s.barIndex == 0;
                      return LineTooltipItem('${isTx ? "↑" : "↓"} ${deskBpsFull(s.y.toInt())}',
                          AppType.microBold(color: isTx ? txColor : rxColor));
                    }).toList(),
                  ),
                ),
              ),
            ),
          );

    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.chartLine, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: title, style: AppType.cardTitleBold(color: AppColors.textHi)),
                TextSpan(
                    text: '   ${isoJoin([if (subtitle != null) subtitle!, 'آخر ${arMinutes(windowMin)}'], ' · ')}',
                    style: AppType.muted(color: AppColors.textLow)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          if (n >= 2) ...[
            _legend(label: rxLabel, value: shown.last.rx, color: rxColor),
            const SizedBox(width: 6),
            _legend(label: txLabel, value: shown.last.tx, color: txColor),
          ],
        ]),
        const SizedBox(height: Sp.lg),
        SizedBox(height: 210, child: chart),
      ]),
    );
  }

  static LineChartBarData _line(List<FlSpot> spots, Color color, double lastX) => LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.28,
        preventCurveOverShooting: true,
        color: color,
        barWidth: 2.5,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: true,
          checkToShowDot: (spot, _) => spot.x == lastX,
          getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
            radius: 3.5,
            color: color,
            strokeWidth: 2,
            strokeColor: AppColors.surfaceSunken,
          ),
        ),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.02)],
          ),
        ),
      );

  static Widget _legend({required String label, required int value, required Color color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: AppType.label(color: AppColors.textMid)),
          const SizedBox(width: 6),
          Text(deskBpsFull(math.max(value, 0)),
              textDirection: TextDirection.ltr, style: AppType.rowValue(color: AppColors.textHi)),
        ]),
      );
}

// ── أرقام ─────────────────────────────────────────────────────

/// السرعة رقماً ووحدةً: (5.8, Mbps).
(String, String) deskBpsParts(int bps) {
  if (bps < 1000) return ('${math.max(bps, 0)}', 'bps');
  if (bps < 1000000) return ((bps / 1e3).toStringAsFixed(1), 'Kbps');
  if (bps < 1000000000) return ((bps / 1e6).toStringAsFixed(1), 'Mbps');
  return ((bps / 1e9).toStringAsFixed(2), 'Gbps');
}

/// «5.8 Mbps».
String deskBpsFull(int bps) {
  final (v, u) = deskBpsParts(bps);
  return '$v $u';
}

/// محور الرسم مختصراً: دون العشرة بمنزلةٍ عشريّة («2.5M»، «1.2M») وما فوقها مقرَّب («48M») — كـ_formatBpsShort في اللوحات.
String deskBpsShort(int bps) {
  String t(double v) {
    if (v >= 10) return '${v.round()}';
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  if (bps <= 0) return '0';
  if (bps < 1000) return '$bps';
  if (bps < 1000000) return '${t(bps / 1000)}K';
  if (bps < 1000000000) return '${t(bps / 1000000)}M';
  return '${t(bps / 1000000000)}G';
}

/// أعلى المحور بقيمةٍ أرباعُها مستديرة (1، 1.2، 1.6، 2، 3، 4، 6، 8، 10 × 10ⁿ).
double _niceCeil(double v) {
  if (v <= 1000) return 1000;
  final p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  for (final m in const [1.0, 1.2, 1.6, 2.0, 3.0, 4.0, 6.0, 8.0, 10.0]) {
    if (m * p >= v) return m * p;
  }
  return 10 * p;
}

/// مدّةٌ بالعربيّة: «45 ث» · «12 دقيقة» · «3 ساعات» · «يومين».
String deskDurationAr(int seconds) {
  if (seconds < 60) return '$seconds ث';
  if (seconds < 3600) return arMinutes(seconds ~/ 60);
  if (seconds < 86400) return arHours(seconds ~/ 3600);
  return arDays(seconds ~/ 86400);
}

/// مدّة التشغيل: «9 أسابيع و4 أيام» · «3 أيام و5 ساعات» · «ساعتين و10 دقائق».
String deskUptimeAr(Duration d) {
  final days = d.inDays, w = days ~/ 7, dd = days % 7, h = d.inHours % 24, m = d.inMinutes % 60;
  String and(String a, int n, String Function(int) f) => n > 0 ? '$a و${f(n)}' : a;
  if (w > 0) return and(arWeeks(w), dd, arDays);
  if (days > 0) return and(arDays(days), h, arHours);
  if (h > 0) return and(arHours(h), m, arMinutes);
  if (m > 0) return arMinutes(m);
  return '${d.inSeconds} ث';
}

/// حجمٌ بالبايت: «24 MB» · «1.5 GB».
String deskBytesShort(int b) {
  const mb = 1024 * 1024;
  if (b >= 1024 * mb) return '${(b / (1024 * mb)).toStringAsFixed(1)} GB';
  return '${(b / mb).round()} MB';
}
