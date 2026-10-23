import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'subscriber_columns.dart';

/// زرّ «الأعمدة» في رأس قائمة المشتركين على الحاسبة: قائمةٌ تحته يُظهَر فيها كلّ عمودٍ ويُخفى
/// بمربّع، ويُسحب من مقبضه لأعلى أو أسفل فيتغيّر مكانه في الجدول فوراً — ويُحفظ على هذا الجهاز.
class SubscriberColumnsButton extends StatelessWidget {
  const SubscriberColumnsButton({super.key, this.dropped = 0});

  /// أعمدةٌ مختارة لم يتّسع لها العرض الآن.
  final int dropped;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(Sp.sm)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
          side: BorderSide(color: AppColors.border),
        )),
      ),
      menuChildren: [SubscriberColumnsEditor(dropped: dropped)],
      builder: (context, controller, _) => ValueListenableBuilder<List<(SubCol, bool)>>(
        valueListenable: SubscriberColumnPrefs.layout,
        builder: (context, layout, _) {
          final hidden = layout.where((e) => !e.$2 && e.$1.available).length;
          return SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: () => controller.isOpen ? controller.close() : controller.open(),
              style: OutlinedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.textHi,
                side: BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
                textStyle: AppType.label().copyWith(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              icon: const Icon(LucideIcons.columns3, size: 17),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('desktop.columns'.tr()),
                  if (hidden > 0) ...[
                    const SizedBox(width: 6),
                    _Count(hidden),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.n);

  final int n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.warningSoftBg,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Text(
        '$n',
        style: AppType.micro(color: AppColors.warningOnSoft).copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// محتوى القائمة: الأعمدة بترتيبها، كلٌّ بمقبض سحبٍ ومربّع إظهار.
class SubscriberColumnsEditor extends StatelessWidget {
  const SubscriberColumnsEditor({super.key, this.dropped = 0});

  final int dropped;

  static const double _row = 42;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ValueListenableBuilder<List<(SubCol, bool)>>(
      valueListenable: SubscriberColumnPrefs.layout,
      builder: (context, layout, _) {
        final cols = layout.where((e) => e.$1.available).toList();
        return SizedBox(
          width: 290,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.xs, Sp.sm, Sp.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('desktop.columns_title'.tr(),
                        style: AppType.label(color: AppColors.textHi)
                            .copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('desktop.columns_hint'.tr(),
                        style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
                  ],
                ),
              ),
              SizedBox(
                height: cols.length * _row,
                child: ReorderableListView(
                  buildDefaultDragHandles: false,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  proxyDecorator: (child, _, __) => Material(
                    color: AppColors.surface,
                    elevation: 6,
                    shadowColor: AppColors.scrim,
                    borderRadius: BorderRadius.circular(R.sm),
                    child: child,
                  ),
                  onReorderItem: (from, to) {
                    final next = [...cols];
                    next.insert(to, next.removeAt(from));
                    // غير المتاح لهذا المزوّد يبقى في آخر القائمة المحفوظة كما هو.
                    SubscriberColumnPrefs.set([
                      ...next,
                      ...layout.where((e) => !e.$1.available),
                    ]);
                  },
                  children: [
                    for (var i = 0; i < cols.length; i++)
                      _ColumnRow(
                        key: ValueKey(cols[i].$1),
                        index: i,
                        col: cols[i].$1,
                        visible: cols[i].$2,
                        height: _row,
                        onToggle: () => SubscriberColumnPrefs.set([
                          for (final e in layout) e.$1 == cols[i].$1 ? (e.$1, !e.$2) : e,
                        ]),
                      ),
                  ],
                ),
              ),
              if (dropped > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.sm, Sp.sm, 0),
                  child: Row(
                    children: [
                      Icon(LucideIcons.info, size: 14, color: AppColors.warningOnSoft),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'desktop.columns_dropped'.tr(args: ['$dropped']),
                          style: AppType.muted(color: AppColors.warningOnSoft).copyWith(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              Divider(height: Sp.lg, color: AppColors.border),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => SubscriberColumnPrefs.set([
                      for (final e in layout) (e.$1, true),
                    ]),
                    icon: const Icon(LucideIcons.eye, size: 16),
                    label: Text('desktop.show_all'.tr()),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: SubscriberColumnPrefs.isDefault ? null : SubscriberColumnPrefs.reset,
                    icon: const Icon(LucideIcons.rotateCcw, size: 16),
                    label: Text('desktop.columns_reset'.tr()),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ColumnRow extends StatefulWidget {
  const _ColumnRow({
    super.key,
    required this.index,
    required this.col,
    required this.visible,
    required this.height,
    required this.onToggle,
  });

  final int index;
  final SubCol col;
  final bool visible;
  final double height;
  final VoidCallback onToggle;

  @override
  State<_ColumnRow> createState() => _ColumnRowState();
}

class _ColumnRowState extends State<_ColumnRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: _hover ? AppColors.surfaceSunken : Colors.transparent,
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: widget.index,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: SizedBox(
                  width: 32,
                  height: widget.height,
                  child: Icon(LucideIcons.gripVertical, size: 16, color: AppColors.textLow),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(R.sm),
                onTap: widget.onToggle,
                child: Row(
                  children: [
                    Checkbox(
                      value: widget.visible,
                      onChanged: (_) => widget.onToggle(),
                      activeColor: AppColors.brand,
                      visualDensity: VisualDensity.compact,
                    ),
                    Expanded(
                      child: Text(
                        widget.col.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.body(color: widget.visible ? AppColors.textHi : AppColors.textMid)
                            .copyWith(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
