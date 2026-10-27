import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/platform/desktop_layout.dart';
import '../../../core/util/bidi.dart';
import '../../../services/fiber/fiber_band.dart';
import '../../../services/fiber/fiber_light.dart';
import '../../../services/fiber/fiber_monitor.dart';
import '../../../services/fiber/fiber_onu.dart';
import '../../../services/fiber/fiber_text.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// عرض محتوى شاشات الألياف: الهاتف كامل العرض، والحاسبة بعمودٍ مقروء في الوسط.
class FiberPage extends StatelessWidget {
  const FiberPage({super.key, required this.children, this.onRefresh, this.maxWidth = 1080});

  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    // العمود بعرضٍ ثابت والهامشان يأخذان الباقي — فالشبكات (منافذ PON) تملأ العمود من بدايته لا تتوسّط بعرض محتواها.
    Widget list = LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth > maxWidth ? (c.maxWidth - maxWidth) / 2 : 0.0;
      return ListView(
        padding: EdgeInsets.only(left: side, right: side, bottom: Inset.route(context) + Sp.lg),
        children: children,
      );
    });
    if (onRefresh != null) list = RefreshIndicator(onRefresh: onRefresh!, child: list);
    return list;
  }
}

bool fiberWide(BuildContext context) => DesktopScope.of(context) || MediaQuery.sizeOf(context).width >= 720;

/// بطاقةٌ بسطح التطبيق وحدّه؛ [tone] يلوّن الحدّ (عطل/تنبيه).
class FiberCard extends StatelessWidget {
  const FiberCard({super.key, required this.child, this.tone, this.padding = const EdgeInsets.all(Sp.md), this.onTap, this.dashed = false});

  final Widget child;
  final AppTone? tone;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final border = tone == null ? AppColors.border : tone!.softBorder;
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: dashed ? AppColors.borderStrong : border, width: tone == null ? BW.normal : BW.selected),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(R.lg), onTap: onTap, child: box),
    );
  }
}

/// حبّةٌ بنغمة: «عطل» · «سليم» · «4 ضعيفة».
class FiberPill extends StatelessWidget {
  const FiberPill(this.text, {super.key, required this.tone, this.dot = false});

  final String text;
  final AppTone tone;
  final bool dot;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
        decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: tone.fill, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          Text(iso(text), style: AppType.pillBold(color: tone.onSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );
}

/// عنوان قسمٍ مع ما يقابله على الطرف الآخر.
class FiberSection extends StatelessWidget {
  const FiberSection(this.title, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.sm)});

  final String title;
  final String? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(child: Text(title, style: AppType.cardTitleBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (trailing != null)
            Flexible(
              child: Text(iso(trailing!),
                  style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
            ),
        ]),
      );
}

/// بلاطة رقمٍ صغيرة: التسمية · القيمة · السطر الصغير.
class FiberStat extends StatelessWidget {
  const FiberStat({super.key, required this.label, required this.value, this.foot, this.valueColor, this.onTap, this.accent});

  final String label, value;
  final String? foot;
  final Color? valueColor;
  final VoidCallback? onTap;

  /// شريطٌ ملوّن أعلى البلاطة (رتب الضوء).
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (accent != null) Container(height: 4, color: accent),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(iso(value), style: AppType.statValue(color: valueColor ?? AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (foot != null)
              Text(iso(foot!), style: AppType.micro(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
    if (onTap == null) return body;
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: BorderRadius.circular(R.md), onTap: onTap, child: body),
      ),
    );
  }
}

/// مربّعات منافذ الصندوق: شغّال · مفصول · فارغ · مقترح.
enum FiberSlot { up, down, free, suggested }

class FiberSlots extends StatelessWidget {
  const FiberSlots({super.key, required this.slots, this.size = 13});

  final List<FiberSlot> slots;
  final double size;

  @override
  Widget build(BuildContext context) {
    final up = slots.where((s) => s == FiberSlot.up).length;
    final down = slots.where((s) => s == FiberSlot.down).length;
    final free = slots.where((s) => s == FiberSlot.free).length;
    final sug = slots.where((s) => s == FiberSlot.suggested).length;
    final label = [
      'منافذ الصندوق ${slots.length}',
      if (up > 0) '$up شغّالة',
      if (down > 0) '$down مفصولة',
      if (sug > 0) '$sug مقترحة',
      if (free > 0) '$free فارغة',
    ].join('، ');
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Wrap(spacing: 4, runSpacing: 4, children: [
        for (final s in slots)
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: switch (s) {
                FiberSlot.up => AppColors.successFill,
                FiberSlot.down => AppColors.errorFill,
                FiberSlot.free => Colors.transparent,
                FiberSlot.suggested => AppColors.infoSoftBg,
              },
              borderRadius: BorderRadius.circular(R.check - 2),
              border: s == FiberSlot.free
                  ? Border.all(color: AppColors.borderStrong, width: BW.selected)
                  : s == FiberSlot.suggested
                      ? Border.all(color: AppColors.info, width: BW.selected)
                      : null,
            ),
          ),
      ]),
    );
  }
}

/// نقطة حالة الجهاز: أخضر متّصل، وأحمر مفصول، وكهرمانيّ لانطفاء الكهرباء.
Color fiberOnuDot(FiberOnuLive o) {
  if (o.online) return AppColors.successDot;
  return o.reason == FiberDropReason.power ? AppColors.warningFill : AppColors.errorFill;
}

/// قيمة الضوء بلونه: «‎-21.4».
class FiberRx extends StatelessWidget {
  const FiberRx(this.rx, {super.key, this.style, this.unit = false});

  final double? rx;
  final TextStyle? style;
  final bool unit;

  @override
  Widget build(BuildContext context) {
    final v = rx;
    final tone = FiberBands.tone(v);
    final text = v == null ? '—' : '${v.toStringAsFixed(1)}${unit ? ' dBm' : ''}';
    return Text(
      iso(text),
      style: (style ?? AppType.rowValue()).copyWith(color: v == null ? AppColors.textMid : (tone == AppTone.success ? AppColors.textHi : tone.fill)),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// رسمٌ صغير لمتوسّطات الأيّام (الأقدم يساراً — زمنٌ لاتينيّ الاتّجاه كبقيّة الرسوم).
class FiberSpark extends StatelessWidget {
  const FiberSpark({super.key, required this.days, this.width = 72, this.height = 26, this.semantics});

  final List<RxDay> days;
  final double width, height;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    final vals = days.map((d) => d.avg).toList();
    final last = vals.isEmpty ? null : vals.last;
    final color = FiberBands.tone(last) == AppTone.success ? AppColors.chartLine : FiberBands.tone(last).fill;
    return Semantics(
      label: semantics ?? (vals.isEmpty ? 'لا تاريخ' : 'الضوء آخر ${vals.length} أيّام'),
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: height,
        child: vals.length < 2
            ? Center(child: Text('—', style: AppType.micro(color: AppColors.textLow)))
            : CustomPaint(painter: _SparkPainter(vals, color)),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.vals, this.color);
  final List<double> vals;
  final Color color;

  @override
  void paint(Canvas c, Size s) {
    var lo = vals.reduce((a, b) => a < b ? a : b);
    var hi = vals.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 2) {
      final mid = (hi + lo) / 2;
      lo = mid - 1;
      hi = mid + 1;
    }
    final p = Path();
    for (var i = 0; i < vals.length; i++) {
      final x = 2 + (s.width - 4) * i / (vals.length - 1);
      final y = 2 + (s.height - 4) * (1 - (vals[i] - lo) / (hi - lo));
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    c.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.vals != vals || o.color != color;
}

/// سطر «تعذّر/تنبيه» داخل الشاشة مع زرّ إعادة.
class FiberNotice extends StatelessWidget {
  const FiberNotice({super.key, required this.text, this.tone = AppTone.warning, this.onRetry, this.icon});

  final String text;
  final AppTone tone;
  final VoidCallback? onRetry;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
          decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.md), border: Border.all(color: tone.softBorder)),
          child: Row(children: [
            Icon(icon ?? LucideIcons.info, size: 18, color: tone.onSoft),
            const SizedBox(width: Sp.sm),
            Expanded(child: Text(iso(text), style: AppType.body(color: tone.onSoft), maxLines: 4, overflow: TextOverflow.ellipsis)),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: Text('إعادة', style: AppType.bodyStrong(color: tone.onSoft))),
          ]),
        ),
      );
}

/// مربّع أيقونةٍ بخلفيّةٍ ناعمة (رأس البطاقات والأدوات).
class FiberIconBox extends StatelessWidget {
  const FiberIconBox(this.icon, {super.key, this.tone = AppTone.brand, this.size = 36});

  final IconData icon;
  final AppTone tone;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.sm)),
        child: Icon(icon, size: size * 0.5, color: tone == AppTone.brand ? AppColors.brandOnSoft : tone.fill),
      );
}

/// «قراءة محفوظة من …» — المعروض لقطة الفتحة السابقة حتى تصل قراءة الأولت الحيّة (ثوانٍ على أولتٍ كبير بعيد).
class FiberStaleNotice extends StatelessWidget {
  const FiberStaleNotice({super.key, required this.monitor});

  final FiberMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final at = monitor.lastOkAt;
    if (!monitor.stale || at == null) return const SizedBox.shrink();
    return FiberNotice(
      text: 'قراءة محفوظة من ${FiberText.when(at)} — نقرأ الأولت الآن…',
      tone: AppTone.info,
      icon: LucideIcons.history,
    );
  }
}
