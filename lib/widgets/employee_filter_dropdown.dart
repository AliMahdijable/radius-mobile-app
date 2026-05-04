import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/dio_client.dart';

/// EmployeeFilterDropdown — قائمة منسدلة لفلترة التقارير حسب الموظف.
/// تختفي تلقائياً لو الفاعل ما عنده موظفين أو الـbackend رفض (الموظف
/// نفسه ما عنده employees.view) — يصير الـwidget Sized.shrink().
///
/// الـvalue: 'all' أو معرّف الموظف (string من int).
/// الاستعمال:
///   EmployeeFilterDropdown(
///     value: _employeeId,
///     onChanged: (v) => setState(() => _employeeId = v),
///   )
class EmployeeFilterDropdown extends ConsumerStatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final EdgeInsetsGeometry? padding;

  const EmployeeFilterDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.padding,
  });

  @override
  ConsumerState<EmployeeFilterDropdown> createState() =>
      _EmployeeFilterDropdownState();
}

class _EmployeeFilterDropdownState
    extends ConsumerState<EmployeeFilterDropdown> {
  List<_EmployeeOption> _employees = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(backendDioProvider);
      final r = await dio.get('/api/v2/employees');
      final list = (r.data?['data'] as List?) ?? const [];
      _employees = list
          .map((e) => _EmployeeOption.fromJson(e as Map))
          .toList();
    } on DioException {
      _employees = [];
    } catch (_) {
      _employees = [];
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox.shrink();
    }
    if (_employees.isEmpty) {
      // الفاعل ما عنده موظفين (أو موظف بدون employees.view) → نخفي الفلتر.
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonFormField<String>(
        value: widget.value,
        isDense: true,
        decoration: InputDecoration(
          labelText: 'الموظف',
          prefixIcon: const Icon(Icons.badge_outlined, size: 18),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
        items: [
          const DropdownMenuItem(
            value: 'all',
            child: Text('الكل (مدير + موظفين)'),
          ),
          ..._employees.map(
            (e) => DropdownMenuItem(
              value: e.id.toString(),
              child: Text(
                e.fullName?.isNotEmpty == true ? e.fullName! : e.username,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        onChanged: (v) {
          if (v != null) widget.onChanged(v);
        },
      ),
    );
  }
}

class _EmployeeOption {
  final int id;
  final String username;
  final String? fullName;
  const _EmployeeOption({
    required this.id,
    required this.username,
    this.fullName,
  });
  factory _EmployeeOption.fromJson(Map j) => _EmployeeOption(
        id: int.tryParse(j['id']?.toString() ?? '') ?? 0,
        username: j['username']?.toString() ?? '',
        fullName: j['full_name']?.toString(),
      );
}
