import 'package:easy_localization/easy_localization.dart';
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

/// أنواع الحركات — مجموعة مسمّاة تخدم كل شاشة.
///
/// * `kFinancialActionTypes` — الحركات المالية فقط (لشاشة التقرير المالي).
/// * `kActivationsActionTypes` — تفعيل/تمديد (لشاشة التفعيلات والتمديدات).
/// * `kAllActionTypes` — كل الأنواع (لسجل النشاط).
class ReportActionTypeOption {
  const ReportActionTypeOption({required this.key, required this.label});
  final String key;

  /// النص المخزّن هنا هو translation key بشكل 'actions.<name>'. يمرّ
  /// عبر displayLabel لاسترجاع النص المُترجم.
  final String label;

  /// نص العرض النهائي بحسب اللغة النشطة — نستدعي .tr() على الـkey.
  String get displayLabel => label.tr();
}

/// نفس قائمة web Financial.tsx (ACTION_TYPE_OPTIONS).
/// SUBSCRIBER_ACTIVATE_CASH و_NON_CASH virtual types يفهمها الـbackend
/// (FinanceReportController.js) بحيث يفلتر SUBSCRIBER_ACTIVATE + description.
const List<ReportActionTypeOption> kFinancialActionTypes = [
  ReportActionTypeOption(key: 'BALANCE_DEDUCT', label: 'actions.debt_pay'),
  ReportActionTypeOption(
      key: 'SUBSCRIBER_ACTIVATE_CASH', label: 'actions.activate_cash'),
  ReportActionTypeOption(
      key: 'SUBSCRIBER_ACTIVATE_NON_CASH', label: 'actions.activate_non_cash'),
  ReportActionTypeOption(key: 'BALANCE_ADD', label: 'actions.debt_add'),
  ReportActionTypeOption(key: 'SUBSCRIBER_EXTEND', label: 'actions.extend_sub'),
  ReportActionTypeOption(key: 'ADMIN_EXPENSE', label: 'actions.expense'),
];

const List<ReportActionTypeOption> kActivationsActionTypes = [
  ReportActionTypeOption(key: 'SUBSCRIBER_ACTIVATE', label: 'actions.activate'),
  ReportActionTypeOption(key: 'SUBSCRIBER_EXTEND', label: 'actions.extend'),
];

/// الأنواع المسموحة في كشف حساب مشترك (مطابق backend ACCOUNT_ACTIONS
/// في server.js:15021).
const List<ReportActionTypeOption> kAccountStatementActionTypes = [
  ReportActionTypeOption(key: 'SUBSCRIBER_ACTIVATE', label: 'actions.activate'),
  ReportActionTypeOption(key: 'SUBSCRIBER_EXTEND', label: 'actions.extend'),
  ReportActionTypeOption(key: 'DEBT_PAY', label: 'actions.debt_pay'),
  ReportActionTypeOption(
      key: 'BALANCE_DEDUCT', label: 'actions.balance_deduct'),
  ReportActionTypeOption(key: 'BALANCE_ADD', label: 'actions.debt_add'),
];

const List<ReportActionTypeOption> kAllActionTypes = [
  ReportActionTypeOption(key: 'SUBSCRIBER_ACTIVATE', label: 'actions.activate'),
  ReportActionTypeOption(key: 'SUBSCRIBER_EXTEND', label: 'actions.extend'),
  ReportActionTypeOption(key: 'DEBT_PAY', label: 'actions.debt_pay'),
  ReportActionTypeOption(
      key: 'BALANCE_DEDUCT', label: 'actions.balance_deduct'),
  ReportActionTypeOption(key: 'BALANCE_ADD', label: 'actions.debt_add'),
  ReportActionTypeOption(key: 'ADMIN_EXPENSE', label: 'actions.expense'),
  ReportActionTypeOption(key: 'EXPENSE_ADD', label: 'actions.expense_manual'),
  ReportActionTypeOption(key: 'SUBSCRIBER_ADD', label: 'actions.sub_add'),
  ReportActionTypeOption(key: 'SUBSCRIBER_EDIT', label: 'actions.sub_edit'),
  ReportActionTypeOption(key: 'SUBSCRIBER_DELETE', label: 'actions.sub_delete'),
  ReportActionTypeOption(key: 'MANAGER_ADD', label: 'actions.mgr_add'),
  ReportActionTypeOption(key: 'MANAGER_EDIT', label: 'actions.mgr_edit'),
  ReportActionTypeOption(key: 'MANAGER_DELETE', label: 'actions.mgr_delete'),
  ReportActionTypeOption(key: 'PACKAGE_EDIT', label: 'actions.pkg_edit'),
  ReportActionTypeOption(key: 'DISCOUNT_SET', label: 'actions.discount_set'),
  ReportActionTypeOption(
      key: 'DISCOUNT_REMOVE', label: 'actions.discount_remove'),
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
    this.includeActionManager = true,
    this.includeUserManager = true,
    this.includeEmployee = true,
    this.actionTypeOptions = kAllActionTypes,
  });
  final ReportFilters value;
  final ValueChanged<ReportFilters> onChanged;

  /// أخفِ dropdown "كل الحركات" (مثلاً لو الشاشة عندها filter نوع خاص بها).
  final bool includeActionTypes;

  /// أخفِ dropdown "مدير الحركة" — يفيد شاشات ما تتحدد فيها الـactionManager
  /// (مثلاً Sessions اللي مصدرها SAS4 UserSessions لا activity_logs).
  final bool includeActionManager;

  /// أخفِ dropdown "مدير المستخدم" — نادراً ما نحتاج إخفاءه.
  final bool includeUserManager;

  /// أخفِ dropdown "الموظف" — يفيد شاشات ما فيها acting_employee (Sessions).
  final bool includeEmployee;

  /// قائمة أنواع الحركات المتاحة للـmulti-select. الشاشات المختلفة
  /// تُضيّق هذه القائمة حسب طبيعة التقرير (المالية → 6 أنواع فقط).
  final List<ReportActionTypeOption> actionTypeOptions;

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
      _employees = (results[1] as ({List<Employee> rows, String? error})).rows;
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
                    Icon(LucideIcons.filter, size: 14, color: AppColors.brand),
                    const SizedBox(width: 6),
                    Text('filters.title'.tr(),
                        style: AppType.label(color: AppColors.textHi).copyWith(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (!widget.value.isEmpty)
                      InkWell(
                        onTap: () => widget.onChanged(const ReportFilters()),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.x,
                                  size: 12, color: AppColors.error),
                              const SizedBox(width: 3),
                              Text('common.clear'.tr(),
                                  style: AppType.microBold(
                                      color: AppColors.error)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // grid dropdowns — نبني قائمة العناصر أولاً ثم نوزّعها 2/سطر.
                Builder(builder: (_) {
                  final items = <Widget>[
                    if (widget.includeActionTypes) _actionTypesSelect(),
                    if (widget.includeActionManager) _actionManagerSelect(),
                    if (widget.includeUserManager) _userManagerSelect(),
                    if (widget.includeEmployee) _employeeSelect(),
                  ];
                  if (items.isEmpty) return const SizedBox.shrink();
                  final rows = <Widget>[];
                  for (var i = 0; i < items.length; i += 2) {
                    final left = items[i];
                    final right = i + 1 < items.length ? items[i + 1] : null;
                    rows.add(Row(
                      children: [
                        Expanded(child: left),
                        if (right != null) ...[
                          const SizedBox(width: 6),
                          Expanded(child: right),
                        ],
                      ],
                    ));
                    if (i + 2 < items.length) {
                      rows.add(const SizedBox(height: 6));
                    }
                  }
                  return Column(children: rows);
                }),
              ],
            ),
    );
  }

  // ────────────────────────────────────────────
  // Multi-select: كل الحركات
  Widget _actionTypesSelect() {
    final selected = widget.value.actionTypes ?? const <String>[];
    final label = selected.isEmpty
        ? 'filters.all_actions'.tr()
        : selected.length == 1
            ? _labelFor(selected.first)
            : 'filters.n_types'.tr(namedArgs: {'n': '${selected.length}'});
    return _dropdownField(
      label: label,
      onTap: () async {
        final picked = await _openActionTypesDialog(context, selected);
        if (picked != null) {
          widget.onChanged(widget.value
              .copyWith(actionTypes: picked.isEmpty ? null : picked));
        }
      },
      active: selected.isNotEmpty,
    );
  }

  Future<List<String>?> _openActionTypesDialog(
      BuildContext ctx, List<String> current) async {
    final set = current.toSet();
    final options = widget.actionTypeOptions;
    return showDialog<List<String>>(
      context: ctx,
      builder: (dctx) {
        return StatefulBuilder(builder: (dctx, setLocal) {
          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(R.lg),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Icon(LucideIcons.filter,
                          size: 15, color: AppColors.brand),
                      const SizedBox(width: 6),
                      Text('filters.action_types_title'.tr(),
                          style: AppType.title(color: AppColors.textHi)
                              .copyWith(
                                  fontSize: 14, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (set.isNotEmpty)
                        TextButton(
                          onPressed: () => setLocal(set.clear),
                          style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4)),
                          child: Text('common.clear'.tr(),
                              style: AppType.pillBold(color: AppColors.error)),
                        ),
                    ],
                  ),
                ),
                Container(height: 1, color: AppColors.border),
                // Compact rows بدل CheckboxListTile
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: options.length,
                    itemBuilder: (_, i) {
                      final o = options[i];
                      final checked = set.contains(o.key);
                      return InkWell(
                        onTap: () => setLocal(() {
                          if (checked) {
                            set.remove(o.key);
                          } else {
                            set.add(o.key);
                          }
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: checked
                                      ? AppColors.brand
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(R.pill),
                                  border: Border.all(
                                    color: checked
                                        ? AppColors.brand
                                        : AppColors.border,
                                    width: 1.5,
                                  ),
                                ),
                                child: checked
                                    ? const Icon(Icons.check,
                                        size: 12, color: AppColors.onBrand)
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  o.displayLabel,
                                  style: TextStyle(
                                      fontSize: 13,
                                      height: 1.45,
                                      color: AppColors.textHi,
                                      fontWeight: checked
                                          ? FontWeight.w700
                                          : FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(height: 1, color: AppColors.border),
                // Footer
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(dctx),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: Text('common.cancel'.tr(),
                              style: TextStyle(
                                  color: AppColors.textMid,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(dctx, set.toList()),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.brand,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: Text(
                              set.isEmpty
                                  ? 'common.apply'.tr()
                                  : '${'common.apply'.tr()} (${set.length})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  height: 1.35)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  String _labelFor(String key) {
    for (final o in widget.actionTypeOptions) {
      if (o.key == key) return o.displayLabel;
    }
    return key;
  }

  // ────────────────────────────────────────────
  // Single-select: مدير الحركة
  Widget _actionManagerSelect() {
    final selected = widget.value.actionManagerId;
    final label = selected == null
        ? 'filters.action_manager'.tr()
        : _managerLabel(selected, byId: true);
    return _dropdownField(
      label: label,
      active: selected != null,
      onTap: () => _showManagerMenu(
        byId: true,
        onPick: (v) =>
            widget.onChanged(widget.value.copyWith(actionManagerId: v)),
        current: selected,
      ),
    );
  }

  // ────────────────────────────────────────────
  // Single-select: مدير المستخدم
  Widget _userManagerSelect() {
    final selected = widget.value.userManager;
    final label = selected == null
        ? 'filters.user_manager'.tr()
        : _managerLabel(selected, byId: false);
    return _dropdownField(
      label: label,
      active: selected != null,
      onTap: () => _showManagerMenu(
        byId: false,
        onPick: (v) => widget.onChanged(widget.value.copyWith(userManager: v)),
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
          title: Text(byId
              ? 'filters.pick_action_manager'.tr()
              : 'filters.pick_user_manager'.tr()),
          children: [
            _dialogTile(dctx, 'common.all'.tr(), current == null, () {
              onPick(null);
              Navigator.pop(dctx);
            }),
            for (final m in list)
              _dialogTile(
                dctx,
                byId && _currentAdminId == m.id.toString()
                    ? '${m.displayName} (${'common.me'.tr()})'
                    : m.displayName,
                byId ? current == m.id.toString() : current == m.username,
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
            Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 13, height: 1.45))),
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
    String label = 'filters.employee'.tr();
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
              title: Text('filters.pick_employee'.tr()),
              children: [
                _dialogTile(dctx, 'common.all'.tr(), selected == null, () {
                  widget.onChanged(widget.value.copyWith(employeeId: null));
                  Navigator.pop(dctx);
                }),
                for (final e in employees)
                  _dialogTile(
                    dctx,
                    e.fullName ?? e.username,
                    selected == e.id,
                    () {
                      widget.onChanged(widget.value.copyWith(employeeId: e.id));
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
          color: active ? AppColors.brandSoftBg : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(
            color: active ? AppColors.brandSoftBorder : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.labelBold(
                    color: active ? AppColors.brand : AppColors.textMid),
              ),
            ),
            Icon(LucideIcons.chevronDown, size: 13, color: AppColors.textLow),
          ],
        ),
      ),
    );
  }
}
