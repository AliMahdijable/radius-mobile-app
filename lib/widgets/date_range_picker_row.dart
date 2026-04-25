import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

/// Two-field "من تاريخ ... إلى تاريخ" row used across the Reports
/// filter sheets. Each tab previously only exposed quick presets
/// (today / last 7 / last 30); admins asked for explicit pickers so
/// they can drill into arbitrary ranges from inside the same sheet.
///
/// Dates are passed in/out as `yyyy-MM-dd` strings to match the
/// existing tab state which serializes to that format directly.
class DateRangePickerRow extends StatelessWidget {
  final String fromDate;
  final String toDate;
  final ValueChanged<String> onFromChanged;
  final ValueChanged<String> onToChanged;

  const DateRangePickerRow({
    super.key,
    required this.fromDate,
    required this.toDate,
    required this.onFromChanged,
    required this.onToChanged,
  });

  Future<void> _pickFrom(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          DateTime.tryParse(fromDate) ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      onFromChanged(intl.DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  Future<void> _pickTo(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(toDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      onToChanged(intl.DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _pickFrom(context),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'من تاريخ',
                prefixIcon: Icon(Icons.calendar_today, size: 16),
                isDense: true,
              ),
              child: Text(
                fromDate.isEmpty ? '—' : fromDate,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () => _pickTo(context),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'إلى تاريخ',
                prefixIcon: Icon(Icons.calendar_today, size: 16),
                isDense: true,
              ),
              child: Text(
                toDate.isEmpty ? '—' : toDate,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
