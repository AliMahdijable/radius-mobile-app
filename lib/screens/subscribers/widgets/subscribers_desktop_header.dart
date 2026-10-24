import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import 'sort_sheet.dart';
import 'subscriber_columns_menu.dart';

/// رأس قائمة المشتركين على الحاسبة بلغة الموقع (/v2): العنوان الكبير وعدده يميناً و«مشترك جديد»
/// والتحديث يساراً، ثمّ صفّ الفلاتر — البحث، المدير، الباقة، الترتيب واتّجاهه، فحص الأجهزة — كلّها
/// قوائمُ منسدلة في مكانها بدل أوراقٍ تصعد من أسفل شاشةٍ عريضة.
class SubscribersDesktopHeader extends StatelessWidget {
  const SubscribersDesktopHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.searchController,
    required this.managers,
    required this.manager,
    required this.onManager,
    required this.packages,
    required this.package,
    required this.onPackage,
    required this.sortField,
    required this.descending,
    required this.onSortField,
    required this.onToggleDirection,
    required this.refreshing,
    required this.onRefresh,
    required this.probing,
    required this.onScanDevices,
    required this.onAdd,
    required this.addLocked,
  });

  final String title;
  final Widget subtitle;
  final TextEditingController searchController;

  final List<String> managers;
  final String? manager;
  final ValueChanged<String?> onManager;

  final List<String> packages;
  final String? package;
  final ValueChanged<String?> onPackage;

  final SortField sortField;
  final bool descending;
  final ValueChanged<SortField> onSortField;
  final VoidCallback onToggleDirection;

  final bool refreshing;
  final VoidCallback onRefresh;

  final bool probing;
  final VoidCallback? onScanDevices;

  /// null = لا إضافة لهذا الحساب أصلاً (الزرّ يختفي)؛ [addLocked] = بمكانه مقفلاً.
  final VoidCallback? onAdd;
  final bool addLocked;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeskPageHeader(
          title: title,
          subtitle: subtitle,
          actions: [
            DeskIconButton(
              icon: LucideIcons.refreshCw,
              tooltip: 'desktop.refresh'.tr(),
              busy: refreshing,
              onTap: refreshing ? null : onRefresh,
            ),
            if (onAdd != null)
              DeskPrimaryButton(
                icon: LucideIcons.userPlus,
                label: 'desktop.new_subscriber'.tr(),
                locked: addLocked,
                onTap: onAdd!,
              ),
          ],
        ),
        const SizedBox(height: Sp.lg),
        // صفٌّ واحد حين يتّسع، وإلّا البحث سطرٌ والقوائم تحته بعرضه (لوحة التفاصيل مفتوحة).
        LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 1080;
          Widget fit(double width, Widget child) =>
              narrow ? Expanded(child: child) : SizedBox(width: width, child: child);
          final filters = <Widget>[
            if (managers.isNotEmpty)
              fit(
                190,
                _Dropdown<String?>(
                  icon: LucideIcons.userCog,
                  label: manager ?? 'desktop.all_managers'.tr(),
                  active: manager != null,
                  value: manager,
                  items: [
                    (null, 'desktop.all_managers'.tr()),
                    for (final m in managers) (m, m),
                  ],
                  onSelected: onManager,
                ),
              ),
            if (packages.isNotEmpty)
              fit(
                190,
                _Dropdown<String?>(
                  icon: LucideIcons.package,
                  label: package ?? 'desktop.all_packages'.tr(),
                  active: package != null,
                  value: package,
                  items: [
                    (null, 'desktop.all_packages'.tr()),
                    for (final p in packages) (p, p),
                  ],
                  onSelected: onPackage,
                ),
              ),
            fit(
              200,
              _Dropdown<SortField>(
                icon: LucideIcons.arrowUpDown,
                label: sortFieldLabel(sortField),
                active: false,
                value: sortField,
                items: [for (final f in sortFieldOptions) (f, sortFieldLabel(f))],
                onSelected: onSortField,
              ),
            ),
            DeskIconButton(
              icon: descending ? LucideIcons.arrowDown : LucideIcons.arrowUp,
              tooltip: (descending ? 'desktop.sort_desc' : 'desktop.sort_asc').tr(),
              onTap: onToggleDirection,
            ),
            DeskIconButton(
              icon: LucideIcons.radar,
              tooltip: 'desktop.scan_devices'.tr(),
              busy: probing,
              onTap: onScanDevices,
            ),
            const SubscriberColumnsButton(),
          ];
          List<Widget> spaced(List<Widget> items) => [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: Sp.sm),
                  items[i],
                ],
              ];
          final search = _SearchField(controller: searchController);
          if (!narrow) {
            return Row(children: spaced([Expanded(child: search), ...filters]));
          }
          return Column(
            children: [
              search,
              const SizedBox(height: Sp.sm),
              Row(children: spaced(filters)),
            ],
          );
        }),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(R.md),
      borderSide: BorderSide(color: AppColors.border),
    );
    return SizedBox(
      height: 44,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, v, _) => TextField(
          controller: controller,
          textAlignVertical: TextAlignVertical.center,
          style: AppType.body(color: AppColors.textHi).copyWith(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.surface,
            hintText: 'desktop.search_subscribers'.tr(),
            hintStyle: AppType.body(color: AppColors.textLow).copyWith(fontSize: 14),
            prefixIcon: Icon(LucideIcons.search, size: 18, color: AppColors.textMid),
            suffixIcon: v.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'common.clear'.tr(),
                    icon: Icon(LucideIcons.x, size: 16, color: AppColors.textMid),
                    onPressed: controller.clear,
                  ),
            contentPadding: const EdgeInsets.symmetric(horizontal: Sp.md),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: AppColors.brand, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// زرٌّ بإطار يفتح قائمةً منسدلة تحته (المدير، الباقة، الترتيب).
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.icon,
    required this.label,
    required this.active,
    required this.value,
    required this.items,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final bool active;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = active ? AppColors.brandOnSoft : AppColors.textHi;
    return SizedBox(
      height: 44,
      child: PopupMenuButton<int>(
        tooltip: '',
        position: PopupMenuPosition.under,
        offset: const Offset(0, 6),
        color: AppColors.surface,
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 320, maxHeight: 420),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
          side: BorderSide(color: AppColors.border),
        ),
        onSelected: (i) => onSelected(items[i].$1),
        itemBuilder: (_) => [
          for (var i = 0; i < items.length; i++)
            PopupMenuItem<int>(
              value: i,
              height: 40,
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: items[i].$1 == value
                        ? Icon(LucideIcons.check, size: 16, color: AppColors.brandAccent)
                        : null,
                  ),
                  Expanded(
                    child: Text(
                      items[i].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body(color: AppColors.textHi).copyWith(
                        fontSize: 14,
                        fontWeight: items[i].$1 == value ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md),
          decoration: BoxDecoration(
            color: active ? AppColors.brandSoftBg : AppColors.surface,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: active ? AppColors.brandSoftBorder : AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: active ? AppColors.brandAccent : AppColors.textMid),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body(color: fg).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              Icon(LucideIcons.chevronDown, size: 16, color: AppColors.textMid),
            ],
          ),
        ),
      ),
    );
  }
}
