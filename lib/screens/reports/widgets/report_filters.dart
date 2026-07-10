import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/employees_api.dart';
import '../../../api/managers_api.dart';
import '../../../services/auth_storage.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// حالة الفلاتر المتقدمة للتقارير (مطابق panel client-v2).
///
/// * `actionTypes` — قائمة أنواع الحركات المختارة (multi-select).
///   null أو فارغ = "كل الحركات".
/// * `actionManagerId` — مدير الحركة (`user_id`). null = الكل.
/// * `userManager` — مدير المستخدم (`user_manager` = username المدير الفرعي
///   الذي ينتمي إليه المشترك المستهدَف).
/// * `employeeId` — الموظف المنفِّذ (`employee_id`).
class ReportFilters {
  const ReportFilters({
    this.actionTypes,
    this.actionManagerId,
    this.userManager,
    this.employeeId,
  });
  final List<String>? actionTypes;
  final String? actionManagerId;
  final String? userManager;
  final int? employeeId;

  bool get isEmpty =>
      (actionTypes == null || actionTypes!.isEmpty) &&
      actionManagerId == null &&
      userManager == null &&
      employeeId == null;

  int get activeCount {
    int n = 0;
    if (actionTypes != null && actionTypes!.isNotEmpty) n++;
    if (actionManagerId != null) n++;
    if (userManager != null) n++;
    if (employeeId != null) n++;
    return n;
  }

  ReportFilters copyWith({
    Object? actionTypes = _sentinel,
    Object? actionManagerId = _sentinel,
    Object? userManager = _sentinel,
    Object? employeeId = _sentinel,
  }) {
    return ReportFilters(
      actionTypes: actionTypes == _sentinel
          ? this.actionTypes
          : actionTypes as List<String>?,
      actionManagerId: actionManagerId == _sentinel
          ? this.actionManagerId
          : actionManagerId as String?,
      userManager:
          userManager == _sentinel ? this.userManager : userManager as String?,
      employeeId:
          employeeId == _sentinel ? this.employeeId : employeeId as int?,
    );
  }

  static const _sentinel = Object();
}

/// أنواع الحركات المدعومة بالـmulti-select (كما في client-v2 _shared).
/// key = action_type الذي يُرسَل للـbackend / يُقارَن بالصفوف.
/// label = نص العرض.
const List<({String key, String label})> kReportActionTypeOptions = [
  (key: 'SUBSCRIBER_ACTIVATE', label: 'تفعيل'),
  (key: 'SUBSCRIBER_EXTEND', label: 'تمديد'),
  (key: 'DEBT_PAY', label: 'تسديد دين'),
  (key: 'BALANCE_DEDUCT', label: 'استقطاع رصيد'),
  (key: 'BALANCE_ADD', label: 'إضافة دين'),
  (key: 'ADMIN_EXPENSE', label: 'صرفية'),
  (key: 'EXPENSE_ADD', label: 'صرفية (يدوي)'),
  (key: 'SUBSCRIBER_ADD', label: 'إضافة مشترك'),
  (key: 'SUBSCRIBER_EDIT', label: 'تعديل مشترك'),
  (key: 'SUBSCRIBER_DELETE', label: 'حذف مشترك'),
  (key: 'MANAGER_ADD', label: 'إضافة مدير'),
  (key: 'MANAGER_EDIT', label: 'تعديل مدير'),
  (key: 'MANAGER_DELETE', label: 'حذف مدير'),
  (key: 'PACKAGE_EDIT', label: 'تعديل باقة'),
  (key: 'DISCOUNT_SET', label: 'تطبيق خصم'),
  (key: 'DISCOUNT_REMOVE', label: 'إزالة خصم'),
];

/// لوحة فلاتر أفقية inline — دائماً ظاهرة على أعلى الشاشة (مطابق web).
///
/// 4 dropdowns في شبكة 2×2:
///   [كل الحركات ▼ (multi)]   [مدير الحركة ▼]
///   [مدير المستخدم ▼]       [الموظف ▼]
///
/// نتائج المدراء + الموظفين تُجلَب مرة واحدة عند build وتُخزّن ضمن الـstate.
class ReportFiltersPanel extends StatefulWidget {
  const ReportFiltersPanel({
    super.key,
    required this.value,
    required this.onChanged,
    this.includeActionTypes = true,
  });
  final ReportFilters value;
  final ValueChanged<ReportFilters> onChanged;

  /// أخفِ dropdown "كل الحركات" (مثلاً لو الشاشة عندها filter نوع خاص بها).
  final bool includeActionTypes;

  @override
  State<ReportFiltersPanel> createState() => _ReportFiltersPanelState();
}

class _ReportFiltersPanelState extends State<ReportFiltersPanel> {
  List<ManagerLite>? _managers;
  List<Employee>? _employees;
  String? _currentAdminId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      ManagersApi.lite(),
      EmployeesApi.list(),
      AuthStorage.readAdminId(),
    ]);
    if (!mounted) return;
    setState(() {
      _managers = (results[0] as List<ManagerLite>?) ?? const [];
      _employees =
          (results[1] as ({List<Employee> rows, String? error})).rows;
      _currentAdminId = results[2] as String?;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.filter,
                        size: 14, color: AppColors.brand),
                    const SizedBox(width: 6),
                    Text('الفلاتر',
                        style: AppType.label(color: AppColors.textHi)
                            .copyWith(
                                fontSize: 12, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (!widget.value.isEmpty)
                      InkWell(
                        onTap: () =>
                            widget.onChanged(const ReportFilters()),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.x,
                                  size: 12, color: AppColors.error),
                              const SizedBox(width: 3),
                              Text('مسح',
                                  style: TextStyle(
                                      color: AppColors.error,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // 2×2 grid من الـdropdowns
                Row(
                  children: [
                    if (widget.includeActionTypes) ...[
                      Expanded(child: _actionTypesSelect()),
                      const SizedBox(width: 6),
                    ],
                    Expanded(child: _actionManagerSelect()),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _userManagerSelect()),
                    const SizedBox(width: 6),
                    Expanded(child: _employeeSelect()),
                  ],
                ),
              ],
            ),
    );
  }

  // ────────────────────────────────────────────
  // Multi-select: كل الحركات
  Widget _actionTypesSelect() {
    final selected = widget.value.actionTypes ?? const <String>[];
    final label = selected.isEmpty
        ? 'كل الحركات'
        : selected.length == 1
            ? _labelFor(selected.first)
            : '${selected.length} أنواع';
    return _dropdownField(
      label: label,
      onTap: () async {
        final picked = await _openActionTypesDialog(context, selected);
        if (picked != null) {
          widget.onChanged(widget.value.copyWith(
              actionTypes: picked.isEmpty ? null : picked));
        }
      },
      active: selected.isNotEmpty,
    );
  }

  Future<List<String>?> _openActionTypesDialog(
      BuildContext ctx, List<String> current) async {
    final set = current.toSet();
    return showDialog<List<String>>(
      context: ctx,
      builder: (dctx) {
        return StatefulBuilder(builder: (dctx, setLocal) {
          return AlertDialog(
            title: const Text('اختر الحركات'),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final o in kReportActionTypeOptions)
                    CheckboxListTile(
                      dense: true,
                      title: Text(o.label,
                          style: const TextStyle(fontSize: 13)),
                      value: set.contains(o.key),
                      onChanged: (v) => setLocal(() {
                        if (v == true) {
                          set.add(o.key);
                        } else {
                          set.remove(o.key);
                        }
                      }),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('إلغاء'),
              ),
              TextButton(
                onPressed: () {
                  setLocal(set.clear);
                },
                child: const Text('مسح'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dctx, set.toList()),
                child: const Text('تطبيق'),
              ),
            ],
          );
        });
      },
    );
  }

  String _labelFor(String key) {
    for (final o in kReportActionTypeOptions) {
      if (o.key == key) return o.label;
    }
    return key;
  }

  // ────────────────────────────────────────────
  // Single-select: مدير الحركة
  Widget _actionManagerSelect() {
    final selected = widget.value.actionManagerId;
    final label = selected == null
        ? 'مدير الحركة'
        : _managerLabel(selected, byId: true);
    return _dropdownField(
      label: label,
      active: selected != null,
      onTap: () => _showManagerMenu(
        byId: true,
        onPick: (v) => widget.onChanged(
            widget.value.copyWith(actionManagerId: v as String?)),
        current: selected,
      ),
    );
  }

  // ────────────────────────────────────────────
  // Single-select: مدير المستخدم
  Widget _userManagerSelect() {
    final selected = widget.value.userManager;
    final label = selected == null
        ? 'مدير المستخدم'
        : _managerLabel(selected, byId: false);
    return _dropdownField(
      label: label,
      active: selected != null,
      onTap: () => _showManagerMenu(
        byId: false,
        onPick: (v) =>
            widget.onChanged(widget.value.copyWith(userManager: v as String?)),
        current: selected,
      ),
    );
  }

  String _managerLabel(String value, {required bool byId}) {
    final list = _managers ?? const [];
    for (final m in list) {
      if (byId && m.id.toString() == value) return m.displayName;
      if (!byId && m.username == value) return m.displayName;
    }
    return value;
  }

  Future<void> _showManagerMenu({
    required bool byId,
    required String? current,
    required ValueChanged<String?> onPick,
  }) async {
    final list = _managers ?? const [];
    return showDialog<void>(
      context: context,
      builder: (dctx) {
        return SimpleDialog(
          title: Text(byId ? 'اختر مدير الحركة' : 'اختر مدير المستخدم'),
          children: [
            _dialogTile(dctx, 'الكل', current == null, () {
              onPick(null);
              Navigator.pop(dctx);
            }),
            for (final m in list)
              _dialogTile(
                dctx,
                byId && _currentAdminId == m.id.toString()
                    ? '${m.displayName} (أنا)'
                    : m.displayName,
                byId
                    ? current == m.id.toString()
                    : current == m.username,
                () {
                  onPick(byId ? m.id.toString() : m.username);
                  Navigator.pop(dctx);
                },
              ),
          ],
        );
      },
    );
  }

  Widget _dialogTile(
      BuildContext ctx, String text, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(
              selected ? LucideIcons.circleCheck : LucideIcons.circle,
              size: 16,
              color: selected ? AppColors.brand : AppColors.textLow,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────
  // Single-select: الموظف
  Widget _employeeSelect() {
    final selected = widget.value.employeeId;
    final employees = _employees ?? const [];
    String label = 'الموظف';
    if (selected != null) {
      for (final e in employees) {
        if (e.id == selected) {
          label = e.fullName ?? e.username;
          break;
        }
      }
    }
    return _dropdownField(
      label: label,
      active: selected != null,
      onTap: () async {
        await showDialog<void>(
          context: context,
          builder: (dctx) {
            return SimpleDialog(
              title: const Text('اختر الموظف'),
              children: [
                _dialogTile(dctx, 'الكل', selected == null, () {
                  widget.onChanged(
                      widget.value.copyWith(employeeId: null));
                  Navigator.pop(dctx);
                }),
                for (final e in employees)
                  _dialogTile(
                    dctx,
                    e.fullName ?? e.username,
                    selected == e.id,
                    () {
                      widget.onChanged(
                          widget.value.copyWith(employeeId: e.id));
                      Navigator.pop(dctx);
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }

  // ────────────────────────────────────────────
  // Common dropdown field UI
  Widget _dropdownField({
    required String label,
    required VoidCallback onTap,
    required bool active,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.brand.withValues(alpha: 0.10)
              : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(
            color: active
                ? AppColors.brand.withValues(alpha: 0.45)
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? AppColors.brand : AppColors.textMid,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(LucideIcons.chevronDown,
                size: 13, color: AppColors.textLow),
          ],
        ),
      ),
    );
  }
}
