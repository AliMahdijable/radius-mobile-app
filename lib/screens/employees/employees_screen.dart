import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../widgets/reveal_password_sheet.dart';

import '../../api/employee_ledger_api.dart';
import '../../api/employee_limits_api.dart';
import '../../api/employees_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/clipboard_helper.dart';
import '../../core/widgets/explain_action.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../services/active_company.dart';
import '../../services/ai_assistant_state.dart';
import '../../services/permissions_service.dart';
import '../../services/provider_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'employee_account_screen.dart';
import 'employee_ledger_widgets.dart';
import 'sheets/employee_editor_sheet.dart';
import 'sheets/link_employee_sheet.dart';
import '../../services/auth_storage.dart';
import '../../services/linked_companies.dart';
import '../desktop/desk_widgets.dart';
import '../../core/platform/desktop_layout.dart';
import '../../widgets/merged_section.dart';
import '../../models/merged_company.dart';

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

  /// «حدود الموظّف» (٩ نوفمبر): مفتوحةٌ لصفحة هذا المدير؟ — زرّ «حساب الموظف» لكلّ موظف (المدير وحده).
  bool _limitsFeature = false;

  Future<void> _loadLimitsFeature() async {
    if (PermissionsService.isEmployee) return;
    final me = await EmployeeLimitsApi.me();
    if (!mounted) return;
    final on = me != null && !me.isEmployee && me.featureEnabled;
    if (on != _limitsFeature) setState(() => _limitsFeature = on);
  }

  /// «حركات الموظف» (١٣ نوفمبر): من أنا في الميزة (المدير، أو موظّفٌ بصلاحيّة الرواتب)، وملخّص حساب كلّ موظّف (له/عليه، راتبٌ
  /// مستحقّ) برقمه. الميزة مطفأة لهذه الصفحة أو لا أدير بها ⇒ null وخريطةٌ فارغة، والشاشة كما كانت.
  LedgerMe? _ledgerMe;
  Map<int, LedgerSummary> _ledgerRows = const {};

  bool get _ledgerOn => _ledgerMe?.manages ?? false;

  /// رقم الموظّف المستعمل نفسه (صاحب الصلاحيّة لا يسجّل على نفسه).
  int? get _selfEmployeeId => _ledgerMe?.account?.summary.employeeId;

  Future<void> _loadLedger() async {
    // شركةٌ غير المفتوحة هنا للعرض وحده: هذه المسارات للمفتوحة — لا تُسأل ولا تُعرض فوق موظّفي غيرها.
    if (MergedSection.viewOnlyNow(context)) return;
    final me = await EmployeeLedgerApi.me();
    // تعذّر السؤال (شبكة) ⇒ يبقى ما نعرفه: لا تختفي الأزرار لانقطاعٍ عابر
    if (!mounted || me == null) return;
    EmployeeLedgerState.note(me);
    if (!me.manages) {
      if (_ledgerMe != null || _ledgerRows.isNotEmpty) {
        setState(() {
          _ledgerMe = null;
          _ledgerRows = const {};
        });
      }
      return;
    }
    final rows = await EmployeeLedgerApi.list();
    if (!mounted) return;
    setState(() {
      _ledgerMe = me;
      // تعذّرت القائمة ⇒ يبقى ما نعرفه (الأزرار تعمل، والشارات تنتظر)
      if (rows != null) _ledgerRows = {for (final r in rows) r.employeeId: r};
    });
  }

  Future<void> _openAccount(Employee e) async {
    final name = (e.fullName?.isNotEmpty == true) ? e.fullName! : e.username;
    final me = _ledgerMe;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EmployeeAccountScreen(
        employeeId: e.id,
        title: name,
        limitsOn: _limitsFeature && !PermissionsService.isEmployee,
        ledger: me != null && me.manages ? (canWrite: e.id != _selfEmployeeId, canVoid: me.isManager) : null,
      ),
    ));
    // عاد من حسابه: سلفةٌ أو كشفٌ غيّر شارته
    if (mounted && _ledgerOn) unawaited(_loadLedger());
  }

  /// «حركة موظف» من رأس القسم: «على أيّ موظف؟» ثمّ ورقة الحركة.
  Future<void> _quickMove() async {
    final rows = [
      for (final e in _rows)
        if (e.id != _selfEmployeeId) _ledgerRows[e.id] ?? LedgerSummary(employeeId: e.id, username: e.username, name: e.fullName, active: e.isActive),
    ];
    final picked = await showEmployeePickSheet(context, employees: rows);
    if (picked == null || !mounted) return;
    final done = await showEmployeeMoveSheet(context, employeeId: picked.employeeId, name: picked.displayName, owes: _ledgerRows[picked.employeeId]?.owesTotal);
    if (done == null || !mounted) return;
    showSheetSnack(context, done, isError: false);
    unawaited(_loadLedger());
  }

  /// المالك موزّع ايرث لنك؟ المصدر `ProviderService` (من `/api/auth/me`)،
  /// وكود الشركة المفتوحة احتياطٌ يُعرف لحظة الدخول قبل أن يردّ ذلك النداء
  /// (لا يُنتظر بعد الدخول) — كي لا يرى مالك ايرث لنك محرّر SAS4.
  ///
  /// فايبر اكس (٣١ أكتوبر) مثله: موظّفونا لحسابه بمفاتيحه وحدها ([ElEmployeePerms.keys] تتبع الشركة المفتوحة).
  static bool get _isEarthlink =>
      ProviderService.isEarthlink ||
      ProviderService.isFiberx ||
      ProviderService.isKit ||
      ActiveCompany.current?.sasCode == 'earthlink' ||
      ActiveCompany.current?.sasCode == 'fiberx';

  @override
  void initState() {
    super.initState();
    ProviderService.changes.addListener(_onContextChanged);
    ActiveCompany.listenable.addListener(_onContextChanged);
    _load();
    _loadLimitsFeature();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadLedger();
    });
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
    // «كل الشركات» (٨ نوفمبر — صورة المالك «تعذّر تحميل كتالوج الصلاحيات»): شركةٌ غير المفتوحة هنا للعرض وحده — لا محرّر،
    // فلا كتالوج يُطلب (ليس في قائمة التوجيه) ولا يُعرض فشله خطأً فوق قائمةٍ وصلت.
    final viewOnly = MergedSection.viewOnlyNow(context);
    final results = await Future.wait([
      EmployeesApi.list(),
      viewOnly ? Future<PermissionsCatalog?>.value(null) : EmployeesApi.catalog(),
    ]);
    if (!mounted) return;
    final listResult = results[0] as ({List<Employee> rows, String? error});
    final cat = results[1] as PermissionsCatalog?;
    setState(() {
      _rows = listResult.rows;
      _catalog = cat;
      _error = listResult.error ??
          (cat == null && !viewOnly ? 'تعذّر تحميل كتالوج الصلاحيات' : null);
      _loading = false;
    });
    // السحب للتحديث يحدّث الشارات أيضاً (أوّل تحميل يسأل من initState)
    if (_ledgerMe != null) unawaited(_loadLedger());
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

  /// ٨ نوفمبر — «موظّفٌ بأكثر من صفحة»: المالك بحساب «شركاتي» فيه صفحتان فأكثر يضيف موظّفاً من صفحةٍ أخرى إلى هذه.
  bool get _canLinkFromOtherPages =>
      _catalog != null && Perms.has('employees.manage') && LinkedCompanies.switcherVisible;

  Future<void> _linkFromOtherPage() async {
    final pageId = await AuthStorage.readAdminId();
    if (!mounted || pageId == null || pageId.isEmpty) return;
    final added = await showLinkEmployeeSheet(context, pageId: pageId);
    if (!mounted || !added) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('أُضيف الموظف لهذه الصفحة — يدخل باسمه نفسه ويتنقّل من «صفحاتي»'),
      behavior: SnackBarBehavior.floating,
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.brandAccent;
    // «كل الشركات»: شركةٌ غير المفتوحة ⇒ مزوّدها هي (عدّ الصلاحيّات بمفاتيحها) وللعرض وحده (لا إضافة ولا تعديل ولا حذف ولا
    // كلمة سرّ — من صفحتها).
    final section = MergedSection.of(context);
    final routed = section?.routed ?? false;
    final viewOnly = section?.viewOnly ?? false;
    final focusedProvider = section?.company?.provider;
    final isEl = routed && focusedProvider != null
        ? (focusedProvider == MergedProvider.earthlink ||
            focusedProvider == MergedProvider.fiberx ||
            focusedProvider == MergedProvider.kit)
        : _isEarthlink;
    final canManage = Perms.has('employees.manage') && !viewOnly;
    // «حركات الموظف»: للشركة المفتوحة وحدها
    final ledgerOn = _ledgerOn && !viewOnly;
    final limitsOn = _limitsFeature && !viewOnly && !PermissionsService.isEmployee;
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
          actions: [
            if (ledgerOn && _rows.isNotEmpty)
              IconButton(
                key: const ValueKey('employees-ledger-move'),
                icon: Icon(LucideIcons.banknote, color: AppColors.textHi),
                tooltip: 'حركة موظف',
                onPressed: _quickMove,
              ),
            if (_canLinkFromOtherPages && canManage)
              IconButton(
                key: const ValueKey('employees-link-other-page'),
                icon: Icon(Icons.group_add_outlined, color: AppColors.textHi),
                tooltip: 'موظف من صفحة أخرى',
                onPressed: _linkFromOtherPage,
              ),
          ],
        ),
        actions: [
          if (ledgerOn && _rows.isNotEmpty)
            IconButton(
              icon: Icon(LucideIcons.banknote, color: AppColors.textHi),
              tooltip: 'حركة موظف',
              onPressed: _quickMove,
            ),
          if (_canLinkFromOtherPages && canManage)
            IconButton(
              icon: Icon(Icons.group_add_outlined, color: AppColors.textHi),
              tooltip: 'موظف من صفحة أخرى',
              onPressed: _linkFromOtherPage,
            ),
        ],
        primary: (_catalog == null || !canManage)
            ? null
            : DeskPrimaryButton(
                icon: LucideIcons.userPlus,
                label: 'موظف جديد',
                onTap: () => _openEditor(),
              ),
      ),
      floatingActionButton: (DesktopScope.of(context) ||
              _catalog == null ||
              !canManage)
          ? null
          : FloatingActionButton.extended(
              backgroundColor: accent,
              foregroundColor: AppColors.onBrand,
              onPressed: () => _openEditor(),
              icon: const Icon(LucideIcons.userPlus, size: 16),
              label: const Text('موظف جديد'),
            ),
      body: MergedSectionBody(child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: accent,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _errorState(_error!)
                  : _rows.isEmpty
                      ? _emptyState(isEl: isEl, viewOnly: viewOnly)
                      : ListView(
                          padding: EdgeInsets.only(
                              bottom:
                                  MediaQuery.paddingOf(context).bottom + 96),
                          children: [
                            // سطر «موظفو <الشركة المفتوحة>» لا يُرسم تحت شركةٍ أخرى (شريط القسم يسمّيها)
                            DeskSection(children: [_compactHero(accent, isEl: isEl && !routed)]),
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
                                  onTap: canManage
                                      ? () => _openEditor(employee: e)
                                      : null,
                                  onDelete: canManage
                                      ? () => _confirmDelete(e)
                                      : null,
                                  // نسخة صفحةٍ مضافة يدخل صاحبها باسمه الأصليّ — لا كلمة مرورٍ لها هنا
                                  onShowPassword: canManage && !e.isLinkedCopy
                                      ? () => _showEmployeePassword(e)
                                      : null,
                                  // حساب الموظف: حدوده وتسويته (المدير وحده) و/أو «له / عليه» (المدير أو صاحب صلاحيّة الرواتب)
                                  onAccount: limitsOn || ledgerOn ? () => _openAccount(e) : null,
                                  ledger: ledgerOn ? _ledgerRows[e.id] : null,
                                ),
                            ]),
                          ],
                        ),
        ),
      )),
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
  Widget _emptyState({bool isEl = false, bool viewOnly = false}) {
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
              if (!viewOnly)
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
    this.onAccount,
    this.ledger,
  });
  final Employee emp;

  /// ملخّص «له / عليه» (حين الميزة مفتوحة): نقطةٌ على زرّ حسابه — كهرمانيّة لراتبٍ مستحقّ، حمراء لما عليه — بلا سطرٍ جديد
  /// في البطاقة؛ والحاسبة (صفٌّ عريض) تكتبها بسطر الصلاحيّات.
  final LedgerSummary? ledger;

  /// «حساب الموظف» (حدوده وتسويته) — null يُخفي الزرّ (ليس المدير أو الميزة مطفأة).
  final VoidCallback? onAccount;

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
    // هاتفٌ ضيّق (دون ٤٠٠): أزرار الصفّ بمقاسها المرسوم (٣٢) لا بحشوة اللمس (٤٨) — أربعة أزرار كانت تترك للاسم ٥٩ نقطة بعرض ٣٦٠
    // فيفيض سطر الصلاحيّات. الأعرض كما كان.
    final tightButtons = !desk && MediaQuery.sizeOf(context).width < 400
        ? IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap)
        : null;
    // «له / عليه»: راتبٌ مستحقّ يحتاج فعلاً (كهرمانيّ) يسبق «عليه» (أحمر)
    final lg = ledger;
    final balance = ledgerBalanceText(lg);
    final ledgerParts = [
      if (lg != null && lg.salaryDue) lg.salary.dueCount == 1 ? 'راتبٌ مستحقّ' : '${lg.salary.dueCount} رواتب مستحقّة',
      if (balance != null) balance.text,
    ];
    final ledgerTip = ledgerParts.isEmpty ? null : ledgerParts.join(' · ');
    final Color? ledgerDot = lg == null
        ? null
        : lg.salaryDue
            ? AppColors.warning
            : lg.owesTotal > 0
                ? AppColors.error
                : null;
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
                        // مرنٌ: يُختصر «…» حين يضيق الصفّ (أربعة أزرار بعرض ٣٢٠) بدل أن يفيض
                        Flexible(
                          child: Text(
                            // نسخة صفحةٍ مضافة: اسم دخوله الأصليّ لا الداخليّ
                            emp.linked?.loginUsername ?? emp.username,
                            style: TextStyle(
                              fontSize: 11, height: 1.25,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMid,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
                        // الحاسبة: الصفّ عريض — تُكتب بجانب الصلاحيّات (الهاتف: نقطة زرّ الحساب)
                        if (desk && ledgerTip != null) ...[
                          Text('  ·  ', style: AppType.muted()),
                          Flexible(
                            child: Text(
                              ledgerTip,
                              key: ValueKey('employee-ledger-text-${emp.id}'),
                              style: AppType.pillBold(color: ledgerDot ?? AppColors.success),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    // ٨ نوفمبر — «موظّفٌ بأكثر من صفحة»
                    if (emp.linked != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        key: ValueKey('employee-linked-${emp.id}'),
                        children: [
                          Icon(Icons.layers_outlined, size: 11, color: AppColors.brand),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              emp.isLinkedCopy
                                  ? 'مضاف من صفحةٍ أخرى — يدخل باسمه نفسه'
                                  : 'يعمل في ${emp.linked!.pages} صفحات',
                              style: AppType.microBold(color: AppColors.brand),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
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
                  style: tightButtons,
                icon:
                    Icon(LucideIcons.copy, color: AppColors.textMid, size: 15),
                onPressed: () => copyToClipboard(context, emp.linked?.loginUsername ?? emp.username,
                    label: 'اسم المستخدم'),
                tooltip: 'نسخ اسم المستخدم',
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              if (onAccount != null)
                IconButton(
                  style: tightButtons,
                  key: ValueKey('employee-account-${emp.id}'),
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(LucideIcons.handCoins, color: AppColors.brand, size: 16),
                      if (ledgerDot != null)
                        PositionedDirectional(
                          top: -3,
                          end: -4,
                          child: Container(
                            key: ValueKey('employee-ledger-dot-${emp.id}'),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: ledgerDot,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.surface, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                  onPressed: onAccount,
                  tooltip: ledgerTip == null ? 'حساب الموظف' : 'حساب الموظف — $ledgerTip',
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              if (onShowPassword != null)
                IconButton(
                  style: tightButtons,
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
                  style: tightButtons,
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
