import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../providers/reports_provider.dart';

/// Pagination row showing "X items | rows-per-page dropdown | < page N / M >"
class PaginationBar extends StatelessWidget {
  final int totalItems;
  final int currentPage;
  final int rowsPerPage;
  final String itemLabel;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRowsPerPageChanged;

  const PaginationBar({
    super.key,
    required this.totalItems,
    required this.currentPage,
    required this.rowsPerPage,
    required this.onPageChanged,
    required this.onRowsPerPageChanged,
    this.itemLabel = 'عنصر',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalPages = (totalItems / rowsPerPage).ceil();
    final muted = theme.colorScheme.onSurface.withValues(alpha: .5);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text('$totalItems $itemLabel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted)),
          const SizedBox(width: 8),
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.colorScheme.outline.withValues(alpha: .2)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: rowsPerPage,
                isDense: true,
                style: TextStyle(fontSize: 11, fontFamily: 'Cairo', color: theme.colorScheme.onSurface),
                items: const [
                  DropdownMenuItem(value: 10, child: Text('10')),
                  DropdownMenuItem(value: 25, child: Text('25')),
                  DropdownMenuItem(value: 50, child: Text('50')),
                  DropdownMenuItem(value: 100, child: Text('100')),
                  DropdownMenuItem(value: 250, child: Text('250')),
                  DropdownMenuItem(value: 500, child: Text('500')),
                ],
                onChanged: (v) {
                  if (v != null) onRowsPerPageChanged(v);
                },
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          Text('$currentPage / ${totalPages > 0 ? totalPages : 1}',
              style: TextStyle(fontSize: 11, color: muted)),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: currentPage < totalPages ? () => onPageChanged(currentPage + 1) : null,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

/// Manager dropdown filter
class ManagerFilter extends StatelessWidget {
  final List<ManagerOption> managers;
  final String selectedId;
  final ValueChanged<String> onChanged;

  const ManagerFilter({
    super.key,
    required this.managers,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: .2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedId,
          isDense: true,
          isExpanded: true,
          style: TextStyle(fontSize: 11, fontFamily: 'Cairo', color: theme.colorScheme.onSurface),
          icon: Icon(Icons.person_outline, size: 14, color: theme.colorScheme.primary),
          items: [
            const DropdownMenuItem(value: 'all', child: Text('جميع المدراء')),
            ...managers.map((m) => DropdownMenuItem(
                  value: m.id,
                  child: Text(m.name, overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
