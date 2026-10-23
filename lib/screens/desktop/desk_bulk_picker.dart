import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// عمود في جدول [DeskBulkPicker]: عرضٌ ثابت أو حصّةٌ ممّا بقي.
class DeskPickColumn {
  const DeskPickColumn(this.label, {this.width, this.flex = 1, this.align = AlignmentDirectional.centerStart});

  final String label;
  final double? width;
  final int flex;
  final AlignmentDirectional align;
}

/// صفحات «طبّق على مشتركين» على الحاسبة (الخصومات، أسعار المشتركين): جدولٌ بتحديد (البحث والفلتر
/// فوقه) ولوحةٌ جانبيّة ثابتة فيها الحقل والتطبيق والملخّص — بدل رأسٍ طويل فوق شبكة بطاقات وزرٍّ
/// أسفل الشاشة. الصفوف تُبنى عند ظهورها وحدها (الحسابات الكبيرة).
class DeskBulkPicker extends StatelessWidget {
  const DeskBulkPicker({
    super.key,
    required this.searchController,
    required this.searchHint,
    required this.columns,
    required this.rowCount,
    required this.cellsOf,
    required this.selectedOf,
    required this.onToggle,
    required this.allSelected,
    required this.onToggleAll,
    required this.footer,
    required this.panel,
    this.filters,
    this.loading = false,
    this.empty,
    this.onNearEnd,
  });

  final TextEditingController searchController;
  final String searchHint;
  final Widget? filters;
  final List<DeskPickColumn> columns;
  final int rowCount;
  final List<Widget> Function(int i) cellsOf;
  final bool Function(int i) selectedOf;

  /// null = عرضٌ بلا تحديد (لا صلاحيّة إدارة).
  final ValueChanged<int>? onToggle;
  final bool allSelected;
  final VoidCallback? onToggleAll;
  final String footer;
  final Widget panel;
  final bool loading;
  final Widget? empty;

  /// اقترب التمرير من الآخر (الحساب الكبير يجلب المزيد).
  final VoidCallback? onNearEnd;

  static const double _check = 44;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final selectable = onToggle != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.xs, Sp.lg, Sp.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _Search(controller: searchController, hint: searchHint)),
                    if (filters != null) ...[const SizedBox(width: Sp.sm), filters!],
                  ],
                ),
                const SizedBox(height: Sp.md),
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(R.lg),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        _header(selectable),
                        Expanded(child: _body(selectable)),
                        Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                          alignment: AlignmentDirectional.centerStart,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceSunken,
                            border: Border(top: BorderSide(color: AppColors.border)),
                          ),
                          child: Text(
                            footer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Sp.lg),
          SizedBox(
            width: 340,
            child: SingleChildScrollView(child: panel),
          ),
        ],
      ),
    );
  }

  Widget _header(bool selectable) {
    final style = AppType.muted(color: AppColors.textMid).copyWith(fontSize: 13, fontWeight: FontWeight.w700);
    return Container(
      height: 46,
      padding: const EdgeInsetsDirectional.only(end: Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _check,
            child: selectable && rowCount > 0
                ? DeskCheck(value: allSelected, onTap: onToggleAll)
                : null,
          ),
          for (final c in columns)
            _box(c, Align(alignment: c.align, child: Text(c.label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis))),
        ],
      ),
    );
  }

  Widget _box(DeskPickColumn c, Widget child) => c.width != null
      ? SizedBox(width: c.width, child: child)
      : Expanded(flex: c.flex, child: Padding(padding: const EdgeInsetsDirectional.only(end: Sp.sm), child: child));

  Widget _body(bool selectable) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (rowCount == 0) return empty ?? const SizedBox.shrink();
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (onNearEnd != null && n.metrics.extentAfter < 600) onNearEnd!();
        return false;
      },
      child: ListView.builder(
        itemCount: rowCount,
        itemExtent: 58,
        itemBuilder: (_, i) => _Row(
          selected: selectedOf(i),
          onTap: selectable ? () => onToggle!(i) : null,
          child: Row(
            children: [
              SizedBox(
                width: _check,
                child: selectable ? DeskCheck(value: selectedOf(i), onTap: () => onToggle!(i)) : null,
              ),
              for (final (j, cell) in cellsOf(i).indexed)
                _box(columns[j], Align(alignment: columns[j].align, child: cell)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({required this.selected, required this.onTap, required this.child});

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsetsDirectional.only(end: Sp.md),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.brandSoftBg
                : _hover
                    ? AppColors.surfaceSunken
                    : AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// مربّع تحديد الجداول على الحاسبة.
class DeskCheck extends StatelessWidget {
  const DeskCheck({super.key, required this.value, required this.onTap});

  final bool value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Center(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: H.checkbox,
            height: H.checkbox,
            decoration: BoxDecoration(
              color: value ? AppColors.brand : AppColors.surface,
              borderRadius: BorderRadius.circular(R.check),
              border: Border.all(color: value ? AppColors.brand : AppColors.borderStrong, width: 1.5),
            ),
            child: value ? const Icon(LucideIcons.check, size: 14, color: AppColors.onBrand) : null,
          ),
        ),
      ),
    );
  }
}

class _Search extends StatelessWidget {
  const _Search({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(R.md),
      borderSide: BorderSide(color: AppColors.border),
    );
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        textAlignVertical: TextAlignVertical.center,
        style: AppType.body(color: AppColors.textHi).copyWith(fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.surface,
          hintText: hint,
          hintStyle: AppType.body(color: AppColors.textLow).copyWith(fontSize: 14),
          prefixIcon: Icon(LucideIcons.search, size: 18, color: AppColors.textMid),
          contentPadding: const EdgeInsets.symmetric(horizontal: Sp.md),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(borderSide: BorderSide(color: AppColors.brand, width: 1.5)),
        ),
      ),
    );
  }
}

/// أزرارٌ متلاصقة لفلترٍ واحد (الكلّ · عليهم خصم · بلا خصم).
class DeskSegmented<T> extends StatelessWidget {
  const DeskSegmented({
    super.key,
    required this.values,
    required this.labelOf,
    required this.current,
    required this.onChanged,
  });

  final List<T> values;
  final String Function(T) labelOf;
  final T current;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in values)
            GestureDetector(
              onTap: () => onChanged(v),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == current ? AppColors.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(R.sm),
                    border: v == current ? Border.all(color: AppColors.border) : null,
                  ),
                  child: Text(
                    labelOf(v),
                    style: AppType.label(color: v == current ? AppColors.textHi : AppColors.textMid)
                        .copyWith(fontSize: 13.5, fontWeight: v == current ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// بطاقة في اللوحة الجانبيّة: عنوانٌ بأيقونة ثمّ محتواها.
class DeskPanelCard extends StatelessWidget {
  const DeskPanelCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.accent,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final c = accent ?? AppColors.brandAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.md),
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon, size: 17, color: c),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.md),
          ...children,
        ],
      ),
    );
  }
}

/// زرٌّ بعرض اللوحة (تطبيق، حذف الكلّ…).
class DeskWideButton extends StatelessWidget {
  const DeskWideButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color,
    this.busy = false,
    this.outlined = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final bool busy;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final c = color ?? AppColors.brand;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md));
    final text = AppType.label().copyWith(fontSize: 14, fontWeight: FontWeight.w700);
    final iconW = busy
        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: outlined ? c : AppColors.onBrand))
        : Icon(icon, size: 17);
    return SizedBox(
      height: 46,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: busy ? null : onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: c,
                side: BorderSide(color: onPressed == null ? AppColors.border : c.withValues(alpha: 0.5)),
                shape: shape,
                textStyle: text,
              ),
              icon: iconW,
              label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            )
          : FilledButton.icon(
              onPressed: busy ? null : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: c,
                foregroundColor: AppColors.onBrand,
                disabledBackgroundColor: AppColors.surfaceDisabled,
                disabledForegroundColor: AppColors.textHint,
                shape: shape,
                textStyle: text,
              ),
              icon: iconW,
              label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
    );
  }
}

/// رقمٌ كبير وتسميته تحته — ملخّصات اللوحة الجانبيّة.
class DeskStat extends StatelessWidget {
  const DeskStat({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppType.title().copyWith(fontSize: 22, height: 1.2)),
        const SizedBox(height: 2),
        Text(label, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
      ],
    );
  }
}
