import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/format.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../models/device_region.dart';
import '../../../models/network_device.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../devices_filters.dart';
import 'brand_badge.dart' show TypeIcon;

// أعلى صفحة «الأجهزة» (المالك ١ نوفمبر: «٤ حقول فلاتر واضافات وتوزيع اجهزه ومناطق ماخذات هواي من الصفحه»).
//
// كانت أربع كتلٍ فوق القائمة: سطر البحث والأدوات، وبلاطات «الإجمالي/متّصل/مفصول»، وصفّ الأنواع، وصفّ المناطق — نحو ثلث
// شاشة الهاتف قبل أوّل جهاز. صارت سطرين: البحث وأدواته (والإضافات كلّها تحت «+»)، وشريطٌ واحدٌ رفيع يتمرّر أفقيّاً:
// «فلاتر» (ورقةٌ فيها الحالة والنوع والمناطق، وعليها عدد الفعّال) ثمّ التوزيع نفسه شرائحَ تُرشِّح بنقرةٍ واحدة كما كانت.

/// لون المنطقة من الخادم (`#RRGGBB`) — `null` لغيابه أو فساده.
Color? deviceRegionColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final s = hex.startsWith('#') ? hex.substring(1) : hex;
  final n = int.tryParse(s, radix: 16);
  if (n == null) return null;
  return Color(0xFF000000 | n);
}

/// شريحة أعلى صفحة الأجهزة — بشكل شرائح المشتركين (`FilterChipsBar`): ارتفاع [H.chipSm]، نصف قطر [R.md]، حدٌّ خفيف،
/// والمختارة بتعبئة البراند. العدد بلونٍ دلاليّ ([countColor]) يُقرأ منه التوزيع من بعيد (المتّصل أخضر والمفصول أحمر).
class DeviceFilterChip extends StatelessWidget {
  const DeviceFilterChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.dot,
    this.count,
    this.countColor,
    this.selected = false,
    this.soft = false,
    this.removable = false,
    this.badge = 0,
    this.tooltip,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  /// نقطةٌ ملوّنة مكان الأيقونة (الحالة، لون المنطقة). على تعبئة البراند تُحاط بحلقةٍ بيضاء؛ ونقطة الحالة المختارة
  /// بيضاء كلّها (`onBrand`) — أخضر «متّصل» على أخضر البراند لا يُقرأ.
  final Color? dot;
  final int? count;
  final Color? countColor;

  /// مختارة: تعبئة البراند.
  final bool selected;

  /// إبرازٌ خفيف (أخضر فاتح) — «فلاتر» وفيها مرشّحٌ فعّال: تلفت النظر ولا تتنافس مع المختارة بجانبها.
  final bool soft;

  /// «✕» في الطرف — مرشّحٌ فعّال يُزال بالنقر.
  final bool removable;

  /// عددٌ في حبّة (شريحة «فلاتر»: كم مرشّحاً فعّالاً) — يُخفى عند الصفر.
  final int badge;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final Color bg, border, fg, glyph;
    if (selected) {
      bg = AppColors.brand;
      border = AppColors.brand;
      fg = AppColors.onBrand;
      glyph = AppColors.onBrand;
    } else if (soft) {
      bg = AppColors.brandSoftBg;
      border = AppColors.brandSoftBorder;
      fg = AppColors.brandOnSoft;
      glyph = AppColors.brandOnSoft;
    } else {
      bg = AppColors.surface;
      border = AppColors.borderSoft;
      fg = AppColors.textBody;
      glyph = AppColors.textHint;
    }
    final radius = BorderRadius.circular(R.md);
    Widget chip = Material(
      color: bg,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          height: H.chipSm,
          padding: const EdgeInsets.symmetric(horizontal: Sp.md),
          decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: border)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: glyph),
                const SizedBox(width: Sp.x6),
              ] else if (dot != null) ...[
                Container(
                  width: selected ? 10 : 8,
                  height: selected ? 10 : 8,
                  decoration: BoxDecoration(
                    color: dot,
                    shape: BoxShape.circle,
                    // على تعبئة البراند: حلقةٌ بيضاء — الأخضر على الأخضر يختفي.
                    border: selected ? Border.all(color: AppColors.onBrand, width: 1.5) : null,
                  ),
                ),
                const SizedBox(width: Sp.x6),
              ],
              Text(
                label,
                maxLines: 1,
                style: AppType.body(color: fg).copyWith(
                  fontSize: 13,
                  fontWeight: selected || soft ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: Sp.x6),
                Text(
                  '$count',
                  textDirection: ui.TextDirection.ltr,
                  style: AppType.body(
                    color: selected ? AppColors.onBrandStrong : (count == 0 ? AppColors.textHint : countColor ?? AppColors.textMid),
                  ).copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
              if (badge > 0) ...[
                const SizedBox(width: Sp.x6),
                // ⚠️ ارتفاعٌ صريح: `alignment` في صفٍّ ارتفاعه محدود يمدّ الحبّة إلى ارتفاع الشريحة كلّه.
                Container(
                  height: 18,
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.onBrand : AppColors.brand,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                  child: Text(
                    '$badge',
                    textDirection: ui.TextDirection.ltr,
                    style: AppType.pillBold(color: selected ? AppColors.brand : AppColors.onBrand).copyWith(height: 1),
                  ),
                ),
              ],
              if (removable) ...[
                const SizedBox(width: Sp.x6),
                Icon(LucideIcons.x, size: 13, color: glyph),
              ],
            ],
          ),
        ),
      ),
    );
    chip = Semantics(
      button: true,
      selected: selected,
      label: [
        label,
        if (count != null) '$count',
        if (badge > 0) '($badge)',
      ].join(' '),
      excludeSemantics: true,
      onTap: onTap,
      child: chip,
    );
    if (tooltip != null) chip = Tooltip(message: tooltip!, excludeFromSemantics: true, child: chip);
    return chip;
  }
}

/// الشريط الرفيع تحت البحث — يحلّ محلّ بلاطات «الإجمالي/متّصل/مفصول» وصفّ الأنواع وصفّ المناطق (ثلاثة صفوف ⇒ صفٌّ واحد):
///
/// «فلاتر» (الورقة بكلّ المرشّحات والمناطق، وعليها عدد الفعّال) ← المنطقة المختارة (✕ يزيلها) ← «الكلّ» (يمسح المرشّحات)
/// ← المتّصل والمفصول ← الأنواع الموجودة بأعدادها. كلّ شريحةٍ تُرشِّح بنقرةٍ واحدة كما كانت الصفوف، والنقرة الثانية تُلغي.
/// والأعداد من [DevicesFacets] — ضمن المرشّحات الأخرى (المنطقة المختارة تعرض توزيعها هي).
class DevicesFilterStrip extends StatefulWidget {
  const DevicesFilterStrip({
    super.key,
    required this.filter,
    required this.facets,
    required this.onChanged,
    required this.onOpenSheet,
    this.regionName,
    this.regionColor,
    this.padding = Sp.md,
  });

  final DevicesFilter filter;
  final DevicesFacets facets;
  final ValueChanged<DevicesFilter> onChanged;
  final VoidCallback onOpenSheet;

  /// اسم المنطقة المختارة ولونها (شريحتها في الشريط) — `null` بلا فلتر منطقة.
  final String? regionName;
  final Color? regionColor;

  /// الحشوة الأفقيّة — على حافّة القائمة تحته.
  final double padding;

  @override
  State<DevicesFilterStrip> createState() => _DevicesFilterStripState();
}

class _DevicesFilterStripState extends State<DevicesFilterStrip> {
  final _scroll = ScrollController();
  final _typeKeys = <String, GlobalKey>{};

  /// في الشريط بقيّةٌ قبل البداية/بعد النهاية — الطرف يتلاشى ليقول ذلك (على الحاسبة بفأرة لا يُرى غير ذلك).
  bool _moreStart = false;
  bool _moreEnd = false;

  bool _onScroll(ScrollMetrics m) {
    final start = m.extentBefore > 0.5;
    final end = m.extentAfter > 0.5;
    if (start != _moreStart || end != _moreEnd) {
      setState(() {
        _moreStart = start;
        _moreEnd = end;
      });
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant DevicesFilterStrip old) {
    super.didUpdateWidget(old);
    // نوعٌ اختير من الورقة وشريحته خارج المرئيّ من الشريط ⇒ تُسحب إلى النظر (كشرائح المشتركين).
    final t = widget.filter.type;
    if (t != null && t != old.filter.type) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _typeKeys[t]?.currentContext;
        if (ctx == null || !mounted) return;
        Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final f = widget.filter;
    final x = widget.facets;
    const gap = SizedBox(width: Sp.sm);
    final chips = <Widget>[
      DeviceFilterChip(
        key: const ValueKey('devices-filters'),
        icon: LucideIcons.slidersHorizontal,
        label: 'فلاتر',
        soft: !f.isEmpty,
        badge: f.count,
        tooltip: 'الحالة والنوع والمناطق',
        onTap: widget.onOpenSheet,
      ),
      if (f.region != null) ...[
        gap,
        DeviceFilterChip(
          key: const ValueKey('devices-region-chip'),
          dot: widget.regionColor ?? AppColors.textMid,
          label: widget.regionName ?? 'منطقة',
          selected: true,
          removable: true,
          tooltip: 'إزالة فلتر المنطقة',
          onTap: () => widget.onChanged(f.withRegion(null)),
        ),
      ],
      gap,
      // بلا أيقونة: الشريط على ٣٩٠ يتّسع بها لطرف أوّل نوعٍ بعده — دليلٌ أنّ في الشريط بقيّة.
      DeviceFilterChip(
        key: const ValueKey('devices-clear-filters'),
        label: 'الكلّ',
        count: x.total,
        countColor: AppColors.textHi,
        selected: f.isEmpty,
        onTap: () => widget.onChanged(DevicesFilter.none),
      ),
      gap,
      DeviceFilterChip(
        key: const ValueKey('devices-status-online'),
        dot: f.status == 'online' ? AppColors.onBrand : AppColors.success,
        label: 'متّصل',
        count: x.status('online'),
        countColor: AppColors.success,
        selected: f.status == 'online',
        onTap: () => widget.onChanged(f.withStatus(f.status == 'online' ? null : 'online')),
      ),
      gap,
      DeviceFilterChip(
        key: const ValueKey('devices-status-offline'),
        dot: f.status == 'offline' ? AppColors.onBrand : AppColors.error,
        label: 'مفصول',
        count: x.status('offline'),
        countColor: AppColors.error,
        selected: f.status == 'offline',
        onTap: () => widget.onChanged(f.withStatus(f.status == 'offline' ? null : 'offline')),
      ),
      // الأنواع الموجودة وحدها (والمختار ولو صار صفراً) — «توزيع الأجهزة» بلا شرائح فارغة تملأ الشريط.
      for (final e in NetworkDeviceLabels.types.entries)
        if (x.type(e.key) > 0 || f.type == e.key) ...[
          if (e.key == NetworkDeviceLabels.types.keys.firstWhere((k) => x.type(k) > 0 || f.type == k))
            Center(
              child: Container(
                width: 1,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: Sp.sm),
                color: AppColors.border,
              ),
            )
          else
            gap,
          DeviceFilterChip(
            key: _typeKeys.putIfAbsent(e.key, GlobalKey.new),
            icon: TypeIcon.iconFor(e.key),
            label: e.value,
            count: x.type(e.key),
            selected: f.type == e.key,
            onTap: () => widget.onChanged(f.withType(f.type == e.key ? null : e.key)),
          ),
        ],
    ];
    Widget strip = NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onScroll(n.metrics),
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (n) => _onScroll(n.metrics),
        // صفٌّ يُبنى كلّه (اثنتا عشرة شريحةً على الأكثر) لا قائمةٌ كسولة: شريحة نوعٍ اختير من الورقة يجب أن تكون مبنيّةً
        // لتُسحب إلى النظر، ولا شيء في الشريط يستحقّ البناء الكسول.
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: widget.padding),
          child: Row(children: chips),
        ),
      ),
    );
    if (_moreStart || _moreEnd) {
      final rtl = Directionality.of(context) == TextDirection.rtl;
      // يسار الشاشة نهاية الشريط بالعربيّة وبدايته بالإنجليزيّة.
      final fadeLeft = rtl ? _moreEnd : _moreStart;
      final fadeRight = rtl ? _moreStart : _moreEnd;
      strip = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) {
          final f = rect.width <= 0 ? 0.0 : (28 / rect.width).clamp(0.0, 0.5);
          // القناع يأخذ الشفافيّة وحدها (dstIn) — أيّ لونٍ معتم يصلح، والشفّاف منه نفسه.
          final solid = AppColors.bg;
          final clear = solid.withValues(alpha: 0);
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [fadeLeft ? clear : solid, solid, solid, fadeRight ? clear : solid],
            stops: [0, f, 1 - f, 1],
          ).createShader(rect);
        },
        child: strip,
      );
    }
    return SizedBox(key: const ValueKey('devices-strip'), height: H.chipSm, child: strip);
  }
}

/// ورقة «فلاتر» — الحالة والنوع والمنطقة معاً، بأعدادها ضمن المرشّحات الأخرى. تُطبَّق فوراً (القائمة خلفها تتغيّر مع كلّ
/// نقرة، فلا «تطبيق» يُنسى)، وزرّها يقول كم جهازاً سيبقى. «إدارة المناطق» بجانب عنوان المناطق لمن يملك الإدارة.
Future<void> showDevicesFilterSheet(
  BuildContext context, {
  required DevicesFilter initial,
  required List<DeviceRegion> regions,
  required DevicesFacets Function(DevicesFilter f) facetsFor,
  required ValueChanged<DevicesFilter> onChanged,
  bool hasUnassigned = false,
  VoidCallback? onManageRegions,
}) {
  return showAppSheet<void>(
    context: context,
    barrierColor: AppColors.scrim,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DevicesFilterSheet(
      initial: initial,
      regions: regions,
      facetsFor: facetsFor,
      onChanged: onChanged,
      hasUnassigned: hasUnassigned,
      onManageRegions: onManageRegions,
    ),
  );
}

class DevicesFilterSheet extends StatefulWidget {
  const DevicesFilterSheet({
    super.key,
    required this.initial,
    required this.regions,
    required this.facetsFor,
    required this.onChanged,
    this.hasUnassigned = false,
    this.onManageRegions,
  });

  final DevicesFilter initial;

  /// المناطق مرتّبةً بالاسم.
  final List<DeviceRegion> regions;
  final DevicesFacets Function(DevicesFilter f) facetsFor;
  final ValueChanged<DevicesFilter> onChanged;

  /// في الحساب أجهزةٌ بلا منطقة (من كلّ الأجهزة لا من المرشّح) — شريحة «بلا منطقة» ثابتةٌ في مكانها لا تظهر وتختفي مع
  /// كلّ نقرة.
  final bool hasUnassigned;

  /// `null` لمن لا يملك إدارة الأجهزة — الرابط لا يظهر.
  final VoidCallback? onManageRegions;

  @override
  State<DevicesFilterSheet> createState() => _DevicesFilterSheetState();
}

class _DevicesFilterSheetState extends State<DevicesFilterSheet> {
  late DevicesFilter _f = widget.initial;

  void _set(DevicesFilter f) {
    if (f == _f) return;
    setState(() => _f = f);
    widget.onChanged(f);
  }

  static int _sum(Map<Object?, int> m) => m.values.fold(0, (s, n) => s + n);

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final x = widget.facetsFor(_f);
    final n = x.shown.length;
    final orphans = x.region(DevicesFacets.noRegion);
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.slidersHorizontal,
        title: 'الفلاتر',
        subtitle: _f.isEmpty && n == x.total ? 'كلّ الأجهزة · ${x.total}' : 'يعرض $n من ${x.total}',
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: n == 0 ? 'لا نتائج — غيّر الفلاتر' : 'عرض ${arCount(n, one: 'جهاز واحد', two: 'جهازين', few: 'أجهزة', many: 'جهازاً')}',
        icon: LucideIcons.check,
        onPressed: () => Navigator.of(context).pop(),
        leading: _ResetButton(enabled: !_f.isEmpty, onTap: () => _set(DevicesFilter.none)),
      ),
      body: Column(
        key: const ValueKey('devices-filter-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Group(
            label: 'الحالة',
            children: [
              DeviceFilterChip(
                icon: LucideIcons.layers,
                label: 'الكلّ',
                count: _sum(x.byStatus),
                countColor: AppColors.textHi,
                selected: _f.status == null,
                onTap: () => _set(_f.withStatus(null)),
              ),
              DeviceFilterChip(
                dot: _f.status == 'online' ? AppColors.onBrand : AppColors.success,
                label: 'متّصل',
                count: x.status('online'),
                countColor: AppColors.success,
                selected: _f.status == 'online',
                onTap: () => _set(_f.withStatus(_f.status == 'online' ? null : 'online')),
              ),
              DeviceFilterChip(
                dot: _f.status == 'offline' ? AppColors.onBrand : AppColors.error,
                label: 'مفصول',
                count: x.status('offline'),
                countColor: AppColors.error,
                selected: _f.status == 'offline',
                onTap: () => _set(_f.withStatus(_f.status == 'offline' ? null : 'offline')),
              ),
            ],
          ),
          const SizedBox(height: Sp.lg),
          _Group(
            label: 'النوع',
            children: [
              DeviceFilterChip(
                icon: LucideIcons.layoutGrid,
                label: 'كلّ الأنواع',
                count: _sum(x.byType),
                countColor: AppColors.textHi,
                selected: _f.type == null,
                onTap: () => _set(_f.withType(null)),
              ),
              for (final e in NetworkDeviceLabels.types.entries)
                DeviceFilterChip(
                  icon: TypeIcon.iconFor(e.key),
                  label: e.value,
                  count: x.type(e.key),
                  selected: _f.type == e.key,
                  onTap: () => _set(_f.withType(_f.type == e.key ? null : e.key)),
                ),
            ],
          ),
          const SizedBox(height: Sp.lg),
          _Group(
            label: 'المنطقة',
            action: widget.onManageRegions == null
                ? null
                : _LinkButton(
                    label: 'إدارة المناطق',
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onManageRegions!();
                    },
                  ),
            children: widget.regions.isEmpty
                ? [
                    Text(
                      'لا مناطق بعد — المنطقة تجمع أجهزة البرج أو الحيّ الواحد فتُرشَّح معاً.',
                      style: AppType.body(color: AppColors.textMid),
                    ),
                  ]
                : [
                    DeviceFilterChip(
                      icon: LucideIcons.mapPin,
                      label: 'كلّ المناطق',
                      count: _sum(x.byRegion),
                      countColor: AppColors.textHi,
                      selected: _f.region == null,
                      onTap: () => _set(_f.withRegion(null)),
                    ),
                    for (final r in widget.regions)
                      DeviceFilterChip(
                        dot: deviceRegionColor(r.color) ?? AppColors.brand,
                        label: r.name,
                        count: x.region(r.id),
                        selected: _f.region == r.id,
                        onTap: () => _set(_f.withRegion(_f.region == r.id ? null : r.id)),
                      ),
                    if (widget.hasUnassigned || orphans > 0 || _f.region == DevicesFacets.noRegion)
                      DeviceFilterChip(
                        dot: AppColors.textLow,
                        label: 'بلا منطقة',
                        count: orphans,
                        selected: _f.region == DevicesFacets.noRegion,
                        onTap: () => _set(_f.withRegion(
                            _f.region == DevicesFacets.noRegion ? null : DevicesFacets.noRegion)),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}

/// مجموعة شرائح في الورقة: تسميةٌ (وإجراءٌ في طرفها) فوق شرائح ملتفّة.
class _Group extends StatelessWidget {
  const _Group({required this.label, required this.children, this.action});

  final String label;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label()),
            ),
            if (action != null) action!,
          ],
        ),
        const SizedBox(height: Sp.sm),
        Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: children),
      ],
    );
  }
}

/// رابطٌ نصّيّ صغير بطرف عنوان المجموعة — «إدارة المناطق ›».
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.xs, vertical: Sp.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, maxLines: 1, style: AppType.link().copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: Sp.xxs),
            Icon(LucideIcons.chevronLeft, size: 14, color: AppColors.brandAccent),
          ],
        ),
      ),
    );
  }
}

/// «إعادة تعيين» في شريط الورقة — بشكل زرّ ورقة تصفية المشتركين (سطحٌ بحدٍّ خفيف بجانب الزرّ الأساسيّ).
class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final radius = BorderRadius.circular(R.button);
    return SizedBox(
      height: H.button,
      child: Material(
        color: AppColors.surface,
        borderRadius: radius,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: AppColors.borderSoft)),
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
            child: Center(
              child: Text(
                'إعادة تعيين',
                style: AppType.button(color: enabled ? AppColors.textBody : AppColors.textHint),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
