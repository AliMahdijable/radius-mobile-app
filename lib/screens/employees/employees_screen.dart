import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../widgets/reveal_password_sheet.dart';

import '../../api/employees_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/clipboard_helper.dart';
import '../../core/widgets/explain_action.dart';
import '../../services/active_company.dart';
import '../../services/ai_assistant_state.dart';
import '../../services/permissions_service.dart';
import '../../services/provider_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'sheets/employee_editor_sheet.dart';
import '../desktop/desk_widgets.dart';
import '../../core/platform/desktop_layout.dart';

/// شاشة الموظفين — مديرو الفرع يدخلون عبر حساب رئيسي، والموظفون
/// الفرعيون يحصلون على صلاحيات محددة. القائمة + add/edit/delete.
///
/// ايرث لنك (Pro البند ٤): المالك يدير موظّفي الشركة المفتوحة الآن بنفس
/// المسارات العامّة؛ المحرّر يُفتح بوضع ايرث لنك ([showEmployeeEditorSheet]).
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Employee> _rows = const [];
  PermissionsCatalog? _catalog;
  bool _loading = true;
  String? _error;

  /// المالك موزّع ايرث لنك؟ المصدر `ProviderService` (من `/api/auth/me`)،
  /// وكود الشركة المفتوحة احتياطٌ يُعرف لحظة الدخول قبل أن يردّ ذلك النداء
  /// (لا يُنتظر بعد الدخول) — كي لا يرى مالك ايرث لنك محرّر SAS4.
  static bool get _isEarthlink =>
      ProviderService.isEarthlink ||
      ActiveCompany.current?.sasCode == 'earthlink';

  @override
  void initState() {
    super.initState();
    ProviderService.changes.addListener(_onContextChanged);
    ActiveCompany.listenable.addListener(_onContextChanged);
    _load();
  }

  @override
  void dispose() {
    ProviderService.changes.removeListener(_onContextChanged);
    ActiveCompany.listenable.removeListener(_onContextChanged);
    super.dispose();
  }

  void _onContextChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // حالة المساعد (مفتاحه بالمحرّر) — بالخلفيّة، بلا انتظار ولا خطأ يظهر.
    unawaited(AiAssistantState.ensureFresh());
    // الـcatalog مهم للـeditor؛ نحمّله مع القائمة. لو الـcatalog فشل
    // الـeditor ما يفتح (يحتاج presets لرسم الـUI).
    final results = await Future.wait([
      EmployeesApi.list(),
      EmployeesApi.catalog(),
    ]);
    if (!mounted) return;
    final listResult = results[0] as ({List<Employee> rows, String? error});
    final cat = results[1] as PermissionsCatalog?;
    setState(() {
      _rows = listResult.rows;
      _catalog = cat;
      _error = listResult.error ??
          (cat == null ? 'تعذّر تحميل كتالوج الصلاحيات' : null);
      _loading = false;
    });
  }

  Future<void> _openEditor({Employee? employee}) async {
    final full = _catalog;
    if (full == null) return;
    // المساعد الذكي: مفتاحه لا يظهر بالمحرّر قبل أن يقول الخادم إنّه مفعّلٌ
    // لهذا الحساب (مخفيٌّ لا مقفل — الميزة نفسها مخفيّة)، ولا يُرسَل فيُبقي
    // الخادم قيمة الموظّف المحفوظة.
    final cat = AiAssistantState.status?.enabled == true
        ? full
        : full.without(const {ElEmployeePerms.assistantKey});
    // ايرث لنك: الإنشاء يُبقي الشيت مفتوحاً على لوحة بيانات الدخول، فتُحدَّث
    // القائمة لحظة الإنشاء لا عند الإغلاق (قد يُغلق بالسحب فلا يرجع true).
    var reloaded = false;
    final changed = await showEmployeeEditorSheet(
      context,
      catalog: cat,
      employee: employee,
      isEarthlink: _isEarthlink,
      onCreated: () {
        reloaded = true;
        _load();
      },
    );
    if (changed == true && !reloaded) _load();
  }

  Future<void> _confirmDelete(Employee emp) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('حذف الموظف',
            style:
                AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        content: Text(
          'حذف "${emp.fullName?.isNotEmpty == true ? emp.fullName : emp.username}"؟ '
          'لا يمكن التراجع.',
          style:
              AppType.subtitle(color: AppColors.textMid).copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await EmployeesApi.delete(emp.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      explainableSnackBar(
        context,
        r.ok ? 'تم حذف الموظف' : (r.message ?? 'تعذّر الحذف'),
        error: !r.ok,
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
      ),
    );
    if (r.ok) _load();
  }

  /// 2026-08-26: عرض كلمة سرّ الموظّف من `employees.password_encrypted`.
  Future<void> _showEmployeePassword(Employee emp) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('جارٍ الجلب...'),
      duration: Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
    ));
    final res = await EmployeesApi.fetchPassword(emp.id);
    if (!mounted) return;
    if (res.password == null) {
      ScaffoldMessenger.of(context).showSnackBar(explainableSnackBar(
        context,
        res.message ?? 'تعذّر جلب كلمة السر',
        error: true,
        backgroundColor: AppColors.errorFill,
      ));
      return;
    }
    await showRevealPasswordSheet(
      context,
      title: emp.fullName?.isNotEmpty == true ? emp.fullName! : emp.username,
      subtitle: 'كلمة سرّ الموظّف',
      password: res.password!,
      accentColor: AppColors.brandAccent,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.brandAccent;
    final isEl = _isEarthlink;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text('الموظفون',
              style:
                  AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
        primary: (_catalog == null || !Perms.has('employees.manage'))
            ? null
            : DeskPrimaryButton(
                icon: LucideIcons.userPlus,
                label: 'موظف جديد',
                onTap: () => _openEditor(),
              ),
      ),
      floatingActionButton: (DesktopScope.of(context) ||
              _catalog == null ||
              !Perms.has('employees.manage'))
          ? null
          : FloatingActionButton.extended(
              backgroundColor: accent,
              foregroundColor: AppColors.onBrand,
              onPressed: () => _openEditor(),
              icon: const Icon(LucideIcons.userPlus, size: 16),
              label: const Text('موظف جديد'),
            ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: accent,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _errorState(_error!)
                  : _rows.isEmpty
                      ? _emptyState(isEl: isEl)
                      : ListView(
                          padding: EdgeInsets.only(
                              bottom:
                                  MediaQuery.paddingOf(context).bottom + 96),
                          children: [
                            DeskSection(children: [_compactHero(accent, isEl: isEl)]),
                            // الهاتف: فسحةٌ بين الرأس وأوّل بطاقة (الحاسبة يفصلها DeskSection نفسه).
                            if (!DesktopScope.of(context)) const SizedBox(height: Sp.md),
                            DeskSection(children: [
                              for (final e in _rows)
                                _EmployeeTile(
                                  emp: e,
                                  // ايرث لنك: ما يملكه الموظف فعلاً — مفاتيح
                                  // ايرث لنك وحدها؛ لا قيد بمدير فرعي هناك.
                                  permsCount: isEl
                                      ? ElEmployeePerms.activeCount(e.permissions)
                                      : e.activePermsCount,
                                  showScope: !isEl,
                                  onTap: Perms.has('employees.manage')
                                      ? () => _openEditor(employee: e)
                                      : null,
                                  onDelete: Perms.has('employees.manage')
                                      ? () => _confirmDelete(e)
                                      : null,
                                  onShowPassword: Perms.has('employees.manage')
                                      ? () => _showEmployeePassword(e)
                                      : null,
                                ),
                            ]),
                          ],
                        ),
        ),
      ),
    );
  }

  /// 2026-08-26 redesign: header compact بلا gradient بلا حواف ثقيلة.
  /// سطر واحد ينظم العدد الكلّي + الحالة (مفعّل/معطّل) على اليمين.
  ///
  /// ايرث لنك: وسطرٌ تحته بالشركة التي تعرض القائمة موظّفيها — الموظّف يتبع
  /// الشركة المفتوحة الآن، فموظّفو شركاته الأخرى لا يظهرون هنا.
  Widget _compactHero(Color accent, {bool isEl = false}) {
    final activeCount = _rows.where((e) => e.isActive).length;
    final disabledCount = _rows.length - activeCount;
    final counts = _heroCounts(activeCount, disabledCount);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: isEl
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                counts,
                const SizedBox(height: Sp.sm),
                _elCompanyLine(),
              ],
            )
          : counts,
    );
  }

  /// ايرث لنك: «موظفو <الشركة> · <يوزر المالك>».
  Widget _elCompanyLine() {
    final w = elWorkplace(ActiveCompany.current);
    return Row(
      children: [
        Icon(LucideIcons.building2, size: 12, color: AppColors.textLow),
        const SizedBox(width: Sp.x6),
        Expanded(
          child: Text(
            'موظفو ${iso(w.company)}'
            '${w.owner.isEmpty ? '' : ' · ${iso(w.owner)}'}',
            style: AppType.muted(color: AppColors.textMid),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _heroCounts(int activeCount, int disabledCount) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'عدد الموظفين',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMid,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_rows.length}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textHi,
                  letterSpacing: -0.4,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        _statBadge(
            label: 'مفعّل', count: activeCount, color: AppColors.success),
        if (disabledCount > 0) ...[
          const SizedBox(width: 6),
          _statBadge(
              label: 'معطّل', count: disabledCount, color: AppColors.textLow),
        ],
      ],
    );
  }

  Widget _statBadge({
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12.5, height: 1.4,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppType.pillBold(color: color),
          ),
        ],
      ),
    );
  }

  Widget _errorState(String msg) {
    return ListView(
      padding: const EdgeInsets.all(Sp.huge),
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.circleAlert, size: 36, color: AppColors.error),
              const SizedBox(height: 10),
              Text(msg,
                  style: AppType.label(color: AppColors.textMid),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(LucideIcons.refreshCw, size: 14),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// ايرث لنك: الموظفون مدعومون الآن — الحالة الفارغة تقول كيف يعمل الموظف
  /// (يتبع هذه الشركة ويدخل من «دخول موظف») بدل أن توحي بأنّ القسم لا يخصّها.
  Widget _emptyState({bool isEl = false}) {
    return ListView(
      padding: const EdgeInsets.all(Sp.huge),
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.userX, size: 36, color: AppColors.textLow),
              const SizedBox(height: 10),
              Text(
                isEl ? 'لا يوجد موظفون بعد.' : 'لا يوجد موظفون.',
                style: AppType.label(color: AppColors.textMid),
              ),
              const SizedBox(height: 4),
              Text(
                isEl
                    ? 'اضغط "موظف جديد" لإضافة موظف لهذه الشركة — يدخل من '
                        'شاشة «دخول موظف» باسم المستخدم وكلمة المرور.'
                    : 'اضغط "موظف جديد" لإضافة أول موظف.',
                style: AppType.muted().copyWith(fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  const _EmployeeTile({
    required this.emp,
    required this.permsCount,
    required this.onTap,
    this.showScope = true,
    this.onDelete,
    this.onShowPassword,
  });
  final Employee emp;

  /// عدد الصلاحيّات المعروض — ايرث لنك يعدّ مفاتيحه وحدها.
  final int permsCount;

  /// شارة «مقيَّد بـ@…» — لا قيد بمدير فرعي عند ايرث لنك.
  final bool showScope;

  /// null لو الـactor ما عنده صلاحية التعديل — InkWell يصير inert
  /// (لا ripple، لا فعل) بدل ما يفتح editor فاضي.
  final VoidCallback? onTap;

  /// null لو الـactor ما عنده صلاحية الحذف — يخفي زر الحذف بدل
  /// تعطيله.
  final VoidCallback? onDelete;

  /// 2026-08-26: إظهار كلمة سرّ الموظّف الحاليّة (طلب المستخدم).
  final VoidCallback? onShowPassword;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final display =
        (emp.fullName?.isNotEmpty == true) ? emp.fullName! : emp.username;
    final accentColor = emp.isActive ? AppColors.success : AppColors.textLow;
    final desk = DesktopScope.of(context);
    final body = Padding(
      padding: const EdgeInsetsDirectional.only(
          start: 12, end: 4, top: 10, bottom: 10),
      child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 3dp rail — نفس النمط بكارت المشتركين. مفعّل = teal، معطّل = رمادي.
              Container(
                width: 3,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(R.pill),
                ),
              ),
              const SizedBox(width: 12),
              // Small avatar 36dp (بدل 40 السابق)
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.card),
                ),
                alignment: Alignment.center,
                child: Text(
                  display.characters.isEmpty ? '?' : display.characters.first,
                  style: AppType.buttonBold(color: accentColor),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            display,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textHi,
                              height: 1.15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!emp.isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.textLow.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(R.pill),
                            ),
                            child: Text(
                              'معطّل',
                              style: AppType.daysWordBold(color: AppColors.textLow),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          emp.username,
                          style: TextStyle(
                            fontSize: 11, height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMid,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text('  ·  ',
                            style: AppType.muted()),
                        Icon(LucideIcons.shield,
                            size: 10, color: AppColors.brand),
                        const SizedBox(width: 3),
                        Text(
                          '$permsCount صلاحية',
                          style: AppType.pillBold(color: AppColors.brand),
                        ),
                      ],
                    ),
                    // 2026-08-26: شارة قيد الـscope — الموظّف مقيَّد بمدير فرعي.
                    if (showScope && emp.isScoped) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(LucideIcons.userCheck,
                              size: 10, color: AppColors.brandAccent),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'مقيَّد بـ@${emp.scopeAdminUsername ?? emp.scopeAdminId}',
                              style: AppType.microBold(color: AppColors.brandAccent),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Actions — flat icon buttons، بلا حواف.
              // 2026-08-26: زر نسخ اليوزر — يتوفّر لأي حساب مصادَق (بلا
              // perm gating لأن الـusername ليس بيانات حسّاسة).
              IconButton(
                icon:
                    Icon(LucideIcons.copy, color: AppColors.textMid, size: 15),
                onPressed: () => copyToClipboard(context, emp.username,
                    label: 'اسم المستخدم'),
                tooltip: 'نسخ اسم المستخدم',
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              if (onShowPassword != null)
                IconButton(
                  icon: Icon(LucideIcons.keyRound,
                      color: AppColors.brandAccent, size: 16),
                  onPressed: onShowPassword,
                  tooltip: 'إظهار كلمة السر',
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              if (onDelete != null)
                IconButton(
                  icon: Icon(LucideIcons.trash2,
                      color: AppColors.error, size: 15),
                  onPressed: onDelete,
                  tooltip: 'حذف',
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
        );
    if (desk) {
      // الحاسبة: صفٌّ ضمن بطاقة القسم المجمّعة بفاصلٍ رفيع (كما كان).
      return Material(
        color: AppColors.surface,
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
            child: body,
          ),
        ),
      );
    }
    // الهاتف: بطاقةٌ مستقلّة لكلّ موظّفٍ كبطاقات المشتركين، مع إبقاء كثافة الصفّ.
    // (المالك ٢٧ أكتوبر — تجانس القوائم) وبهامش قائمة المشتركين نفسه (١٦ جانباً، ٦ بين البطاقات) — بلاه
    // التصقت البطاقات بحافّتي الشاشة وبالرأس (لقطة المالك ٢٨ أكتوبر: «الالتصاق… الهيدر والمحتوى»).
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.x6),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: body,
          ),
        ),
      ),
    );
  }

  @Deprecated('unused — old badge helper')
  // ignore: unused_element
  Widget _badge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return const SizedBox.shrink();
  }
}
