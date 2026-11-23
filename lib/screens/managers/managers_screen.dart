import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../widgets/reveal_password_sheet.dart';

import '../../api/manager_debts_api.dart';
import '../../api/managers_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/util/order_rules.dart';
import '../../core/widgets/design_sheet.dart';
import '../reports/v2/report_kit.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'custom_debts_screen.dart';
import 'movements_screen.dart';
import 'sheets/add_manager_sheet.dart';
import 'sheets/balance_op_sheet.dart';
import 'sheets/edit_manager_sheet.dart';
import 'sheets/manager_actions_sheet.dart';
import 'sheets/pay_debt_sheet.dart';
import 'sheets/send_info_sheet.dart';
import 'sheets/telegram_link_sheet.dart';
import '../../core/util/clipboard_helper.dart';
import '../../services/permissions_service.dart';
import '../../services/subscriber_events.dart';
import '../desktop/desk_widgets.dart';
import '../../core/platform/desktop_layout.dart';
import '../../api/company_route.dart';
import '../../api/balance_requests_api.dart';
import '../balance_requests/incoming_balance_requests_screen.dart';
import '../../widgets/merged_section.dart';
import '../../models/merged_company.dart';
import '../../services/merged_text.dart';

/// مديول "المدراء الفرعيون" — قائمة + بحث + add/edit/delete + عمليات
/// رصيد (شحن/سحب/نقاط). v1 web parity.
class ManagersScreen extends StatefulWidget {
  const ManagersScreen({super.key});

  /// «كل الشركات»: بغلاف قسمها (للعرض لكلّ شركة) — من «قوائم أخرى» ومن نقرة إشعار المدراء معاً. قائمة المدراء وأرصدتهم
  /// (managers/full) قراءةٌ موجَّهة للساس وحده — شركة ايرث لنك أو غيرها غير المفتوحة ⇒ «غير متاح» بسببه (لا خطأ رفض).
  /// [openCompany] (٩ نوفمبر): إشعار المدراء (دينٌ أو رصيدٌ في الشركة المفتوحة) ⇒ مدراؤها مثبَّتين لها بلا تبديل الشريط.
  static Widget mergedPage({bool openCompany = false}) => MergedSection(
      readOnly: true,
      openCompany: openCompany,
      perms: const ['managers.view'],
      prefixes: const ['/api/v2/managers', '/api/v2/acl-list', '/api/admin/manager-debts', '/api/admin/managers', '/api/admin/manager-movements'],
      serves: (c) => c.provider == MergedProvider.sas4,
      servesNote: 'merged.serves_sas'.trm(),
      lockTitle: 'mgr.title'.tr(),
      child: const ManagersScreen());

  @override
  State<ManagersScreen> createState() => _ManagersScreenState();
}

class _ManagersScreenState extends State<ManagersScreen> {
  List<Manager> _rows = const [];
  int _total = 0;
  bool _loading = true;
  String _query = '';

  /// «الترتيب بالنقر» (المرحلة ٣ — المالك ٢٣ نوفمبر): «رتّب حسب» بحقول البطاقة نفسها وكالموقع (lib/list-sorts.ts MGR_SORT) —
  /// أوّل نقرة الأنفع (الأسماء أ ← ي، الأرقام الأكبر)، الثانية تقلب، الثالثة ترجع ترتيب الساس (اليوزر) كما وصل؛ يُحفظ على الجهاز.
  static const _sortFields = [
    OrderField('username', 'المدير', OrderKind.text),
    OrderField('name', 'الاسم', OrderKind.text),
    OrderField('balance', 'الرصيد', OrderKind.number),
    OrderField('debt', 'الدين', OrderKind.number),
    OrderField('points', 'النقاط', OrderKind.number),
    OrderField('users', 'المشتركون', OrderKind.number),
    OrderField('acl', 'الصلاحية', OrderKind.text),
    OrderField('status', 'الحالة', OrderKind.number),
  ];
  OrderValue? _sort;

  /// مطلب 2026-06-11 (مطابق v1 managers_screen.dart:1167): الديون
  /// الخارجية تنضمّ إلى دين الـSAS عند عرضها في الكارت. الـmap يُملأ
  /// من /api/admin/manager-debts/summary ويُستهلَك في chip الدين +
  /// يُمرَّر للـactions sheet + pay-debt sheet.
  Map<int, double> _customDebtByManager = const {};

  @override
  void initState() {
    super.initState();
    unawaited(OrderPrefs.loadTri(OrderPrefs.listKey('managers'), _sortFields).then((v) {
      if (mounted && v != null && _sort == null) setState(() => _sort = v);
    }));
    _load();
    // أعد التحميل تلقائياً لمّا أيّ شاشة ثانية تُغيّر بيانات (إضافة
    // مدير، تسديد دين، شحن، إلخ.) — مطابق سلوك شاشة المشتركين.
    SubscriberEvents.dataChanged.addListener(_onExternalChange);
  }

  void _onExternalChange() {
    if (!mounted) return;
    _load();
  }

  @override
  void dispose() {
    SubscriberEvents.dataChanged.removeListener(_onExternalChange);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // اجلب القائمة + ملخّص الديون الخارجية بالتوازي. أيّاً منهما لو فشل
    // تُكمل الأخرى بشكل طبيعي.
    // شركة القسم من شجرته صراحةً (مراجعة 179): يُعاد الجلب بعد عمليّةٍ على مشتركٍ في أيّ مكان والقسم مخفيٌّ أو مغطّى — لا يأخذ
    // وجهة ما فوقه. والمثبَّت للمفتوحة (إشعار المدراء) لها.
    final results = await CompanyRoute.pin(
        MergedSection.routeKeyOf(context),
        () => Future.wait([
              ManagersApi.listFull(page: 1, count: 200),
              ManagerDebtsApi.summary(),
            ]));
    if (!mounted) return;
    final list = results[0] as ({List<Manager> rows, int total});
    final summary = results[1] as ManagerDebtsSummary?;
    setState(() {
      _rows = list.rows;
      _total = list.total;
      _customDebtByManager = {
        for (final d in summary?.perDebtor ?? const [])
          d.debtorAdminId: d.totalRemaining,
      };
      _loading = false;
    });
  }

  List<Manager> get _filtered {
    Iterable<Manager> it = _rows;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      it = it.where((m) {
        return m.username.toLowerCase().contains(q) ||
            m.fullName.toLowerCase().contains(q) ||
            m.mobile.contains(q);
      });
    }
    return sortOrKeep<Manager>(it.toList(), _sort, _sortFields, _sortValue);
  }

  /// قيمة المدير كما تعرضها بطاقته: الدين = الساس + «ديون أخرى» و«—» بلا دين، النقاط «—» صفراً.
  Object? _sortValue(Manager m, String k) {
    switch (k) {
      case 'username':
        return m.username;
      case 'name':
        return m.fullName;
      case 'balance':
        return m.balance;
      case 'debt':
        final d = m.debt + (_customDebtByManager[m.id] ?? 0);
        return d > 0 ? d : null;
      case 'points':
        return m.rewardPoints != 0 ? m.rewardPoints : null;
      case 'users':
        return m.usersCount;
      case 'acl':
        return m.aclName;
      case 'status':
        return m.isActive ? 1 : 0;
    }
    return null;
  }

  void _pickSort(String key) {
    for (final f in _sortFields) {
      if (f.key != key) continue;
      final next = nextTriOrder(_sort, f);
      setState(() => _sort = next);
      unawaited(OrderPrefs.saveTri(OrderPrefs.listKey('managers'), next));
      return;
    }
  }

  num get _totalBalance =>
      _rows.fold<num>(0, (acc, m) => acc + (m.balance));

  Future<void> _openAdd() async {
    final added = await showAddManagerSheet(context);
    if (added == true) _load();
  }

  Future<void> _openEdit(Manager m) async {
    final changed = await showEditManagerSheet(context, m);
    if (changed == true) _load();
  }

  Future<void> _openBalanceOp(Manager m, {BalanceOpKind? preselected}) async {
    final done = await showBalanceOpSheet(context, m, preselected: preselected, otherDebts: _customDebtByManager[m.id]);
    if (done == true) _load();
  }

  /// مطلب 2026-06-12: نقر الـtile يفتح actions sheet مطابق v1.
  /// 9 عمليات يتعامل معها بحسب القيمة المرجعة.
  Future<void> _openActions(Manager m) async {
    // 2026-08-26: نمرّر الدين التطبيقي (manager_debts) حتى الـsheet يعرض
    // زر "تسديد دين" حتى للمدراء بلا دين SAS. bug-fix: كان يختفي.
    final action = await showManagerActionsSheet(
      context,
      m,
      customDebt: _customDebtByManager[m.id] ?? 0,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case ManagerAction.edit:
        await _openEdit(m);
      case ManagerAction.deposit:
        await _openBalanceOp(m, preselected: BalanceOpKind.deposit);
      case ManagerAction.withdraw:
        await _openBalanceOp(m, preselected: BalanceOpKind.withdraw);
      case ManagerAction.addPoints:
        await _openBalanceOp(m, preselected: BalanceOpKind.addPoints);
      case ManagerAction.payDebt:
        // مرّر مجموع الديون الخارجية الحالي حتى الـsheet يعرض الكلتا
        // فوراً بدون انتظار fetch ثاني.
        final ok = await showPayDebtSheet(
          context,
          m,
          initialCustomRemaining: _customDebtByManager[m.id] ?? 0,
        );
        if (ok == true) _load();
      case ManagerAction.otherDebts:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ManagerCustomDebtsScreen(manager: m),
          ),
        );
        _load();
      case ManagerAction.movements:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ManagerMovementsScreen(manager: m),
          ),
        );
      case ManagerAction.sendInfo:
        await showSendInfoSheet(context, m);
      case ManagerAction.linkTelegram:
        // ⚠️ إعادة تحميلٍ **غير مشروطة**، وقد كانت مشروطةً فأخطأت.
        //
        // الصفيحة تُرجع `true` حين رصدت الارتباط وهي مفتوحة. لكنّ
        // **الربط يقع في تلغرام لا في التطبيق**: التابع قد يضغط START
        // بعد ساعة، أو بينما التطبيق مُغلق. فالصفيحة لا ترصد كلّ شيء،
        // واشتراطُ رصدها يترك الراية قديمةً — فيفتح المدير «شحن»
        // ويجد مفتاح تلغرام معطّلاً بينما تابعه ربط تواً. حدث فعلاً.
        //
        // وثمن إعادة التحميل نداءان بعد فعلٍ صريح من المستخدم. رخيص.
        await showTelegramLinkSheet(context, m);
        if (mounted) _load();
      case ManagerAction.showPassword:
        await _showManagerPassword(m);
      case ManagerAction.copyUsername:
        await copyToClipboard(context, m.username, label: 'اسم المدير');
      case ManagerAction.delete:
        await _confirmDelete(m);
    }
  }

  /// 2026-08-26: عرض كلمة سرّ المدير الفرعي.
  /// backend يحضرها من whatsapp_sessions.admin_password_encrypted.
  Future<void> _showManagerPassword(Manager m) async {
    final tid = _snack('جارٍ الجلب...', persistent: true);
    final res = await ManagersApi.fetchPassword(m.id);
    tid?.close();
    if (!mounted) return;
    if (res.password == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.message ?? 'تعذّر جلب كلمة المرور'),
        backgroundColor: AppColors.errorFill,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    await showRevealPasswordSheet(
      context,
      title: m.username,
      subtitle: 'كلمة مرور المدير الفرعي',
      password: res.password!,
      accentColor: AppColors.brandAccent,
    );
  }

  ScaffoldFeatureController? _snack(String msg, {bool persistent = false}) {
    if (!mounted) return null;
    return ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration:
          persistent ? const Duration(seconds: 10) : const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _confirmDelete(Manager m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('mgr.delete_title'.tr()),
        content: Text(
          'mgr.delete_body'.tr(namedArgs: {
            'name': m.fullName.isNotEmpty ? m.fullName : m.username
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final result = await ManagersApi.delete(m.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.ok
            ? 'exp.deleted'.tr()
            : (result.message ?? 'subscribers.delete_failed'.tr())),
        backgroundColor: result.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (result.ok) {
      SubscriberEvents.notifyChange();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.brandAccent;
    final filtered = _filtered;
    // «كل الشركات»: شركةٌ غير المفتوحة للعرض — القائمة وأرصدتها وديونها؛ لا إضافة ولا إجراءات (شحن/سحب/تعديل… من صفحتها)
    final viewOnly = MergedSection.viewOnlyOf(context);
    final canAdd = Perms.has('managers.add') && !viewOnly;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'mgr.title'.tr(),
            style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
          ),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
        primary: canAdd
            ? DeskPrimaryButton(
                icon: LucideIcons.userPlus,
                label: 'mgr.new'.tr(),
                onTap: _openAdd,
              )
            : null,
      ),
      floatingActionButton: !DesktopScope.of(context) && canAdd
          ? FloatingActionButton.extended(
              backgroundColor: accent,
              foregroundColor: AppColors.onBrand,
              onPressed: _openAdd,
              icon: const Icon(LucideIcons.userPlus, size: 16),
              label: Text('mgr.new'.tr()),
            )
          : null,
      body: MergedSectionBody(child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: accent,
          child: ListView(
            // الشكل الموحّد (المالك ٢٣ نوفمبر: «المدراء والخصومات والسعر الثابت كذلك»): بطاقتا أرقام، ثمّ بطاقة القائمة بعنوانها
            // وعددها، البحث والترتيب داخلها، وسطرٌ لكلّ مدير بشكل سطور التقارير — اللمسة تفتح إجراءاته كما كانت.
            padding: EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, MediaQuery.paddingOf(context).bottom + 96),
            children: [
              // «طلبات الرصيد» من مدرائك الفرعيّين (٢٤ نوفمبر): حين ينتظرك طلب — بطاقةٌ تفتح القائمة
              ValueListenableBuilder<int>(
                valueListenable: BalanceReqState.incoming,
                builder: (context, n, _) => n <= 0
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: Sp.md),
                        child: _BalanceRequestsBanner(count: n),
                      ),
              ),
              _kpis(),
              const SizedBox(height: Sp.md),
              _listCard(filtered, viewOnly),
            ],
          ),
        ),
      )),
    );
  }

  /// إجمالي الأرصدة (بإشارته: رصيدٌ سالب دَين) وعدد المدراء — بطاقتا التقارير الموحّدة بارتفاعٍ واحد.
  Widget _kpis() {
    final off = _rows.where((m) => !m.isActive).length;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: RpKpiCard(
              key: const ValueKey('mgr-kpi-balance'),
              kpi: RpKpi(
                label: 'إجمالي الأرصدة',
                value: _totalBalance,
                icon: LucideIcons.wallet,
                tone: _totalBalance < 0 ? RpTone.loss : RpTone.money,
              ),
              compareWith: '',
            ),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: RpKpiCard(
              key: const ValueKey('mgr-kpi-count'),
              kpi: RpKpi(
                label: 'mgr.title'.tr(),
                value: _total,
                isCount: true,
                unit: 'مدير',
                icon: LucideIcons.users,
                tone: RpTone.info,
                hint: off > 0 ? '${_rows.length - off} ${'mgr.active'.tr()} · $off معطّل' : null,
              ),
              compareWith: '',
            ),
          ),
        ],
      ),
    );
  }

  Widget _listCard(List<Manager> filtered, bool viewOnly) {
    return RpCard(
      key: const ValueKey('mgr-list'),
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RpTitle(
            icon: LucideIcons.listOrdered,
            title: 'mgr.title'.tr(),
            tone: RpTone.neutral,
            trailing: Text('${formatIQD(filtered.length)} مدير', style: AppType.pillBold(color: AppColors.textMid)),
          ),
          const SizedBox(height: Sp.md),
          RpSearchBox(
            key: const ValueKey('mgr-search'),
            query: _query,
            hint: 'mgr.search_hint'.tr(),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: Sp.sm),
          RpSortChips(fields: _sortFields, value: _sort, onPick: _pickSort),
          if (_loading) ...[
            const SizedBox(height: Sp.xl),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: Sp.xl),
          ] else if (filtered.isEmpty) ...[
            const SizedBox(height: Sp.lg),
            Icon(LucideIcons.userX, size: 30, color: AppColors.textLow),
            const SizedBox(height: Sp.sm),
            Text(
              _query.isEmpty ? 'mgr.empty_none'.tr() : 'subscribers.no_search_results'.tr(namedArgs: {'q': _query}),
              textAlign: TextAlign.center,
              style: AppType.muted(color: AppColors.textMid),
            ),
            const SizedBox(height: Sp.md),
          ] else ...[
            const SizedBox(height: Sp.x6),
            for (var i = 0; i < filtered.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.divider),
              _ManagerTile(
                manager: filtered[i],
                extraDebt: _customDebtByManager[filtered[i].id] ?? 0,
                onTap: viewOnly ? null : () => _openActions(filtered[i]),
              ),
            ],
          ],
        ],
      ),
    );
  }

}

class _ManagerTile extends StatelessWidget {
  const _ManagerTile({
    required this.manager,
    required this.onTap,
    this.extraDebt = 0,
  });
  final Manager manager;

  /// مطلب 2026-06-12: نقر الـtile يفتح actions sheet ضامناً 9 عمليات
  /// مطابقة v1 (تعديل / شحن / سحب / تسديد / نقاط / ديون أخرى / حركات
  /// / إرسال معلومات / حذف). الـtile نفسه ما عاد فيه أزرار.
  final VoidCallback? onTap;

  /// مطلب 2026-06-11: مجموع الديون الخارجية (manager-debts) المستحقّة
  /// على هذا المدير. تُجمع مع `manager.debt` لتعرض chip دين موحّد
  /// يطابق v1 (managers_screen.dart:1179).
  final double extraDebt;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final m = manager;
    final balance = m.balance;
    // دين الساس والديون الأخرى منفصلان (٢٠٢٦-٠٧-١٤) — سطرٌ بلون الدين تحت المدير بدل حبّتين
    final sasDebt = m.debt;
    final otherDebt = extraDebt;
    final points = m.rewardPoints;
    final hasName = m.fullName.isNotEmpty && m.fullName != m.username;
    final info = [
      if ((m.aclName ?? '').isNotEmpty) m.aclName!,
      if (m.mobile.isNotEmpty) iso(m.mobile),
      if (m.company.isNotEmpty) m.company,
    ];
    final counts = [
      '${formatIQD(m.usersCount)} مشترك',
      if (points > 0) '${'sheets.points'.tr()} ${formatIQD(points)}',
    ];
    final debts = [
      if (sasDebt > 0) '${'mgr.sas_debt'.tr()} ${rpMoney(sasDebt)}',
      if (otherDebt > 0) '${'mgr.other_debts'.tr()} ${rpMoney(otherDebt)}',
    ];
    // سطرٌ بشكل سطور التقارير الموحّدة (٢٣ نوفمبر): مربّع الحال (أخضر نشط، أحمر معطّل)، اليوزر واسمه، صلاحيّته وهاتفه، مشتركوه ونقاطه،
    // ديونه بلونها — والرصيد بإشارته بطرفه (كان «350,000» لرصيدٍ سالب).
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('mgr-row-${m.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RpIconBox(icon: m.isActive ? LucideIcons.shield : LucideIcons.shieldOff, tone: m.isActive ? RpTone.brand : RpTone.loss, size: 36),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Sp.x6,
                      runSpacing: Sp.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(m.username, style: AppType.bodyBold(color: AppColors.textHi)),
                        if (!m.isActive) const ToneChip(label: 'معطّل', tone: AppTone.danger, dense: true),
                      ],
                    ),
                    if (hasName) Text(m.fullName, style: AppType.micro(color: AppColors.textMid), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (info.isNotEmpty) Text(info.join(' · '), style: AppType.micro(color: AppColors.textLow), maxLines: 2),
                    Text(counts.join(' · '), style: AppType.micro(color: AppColors.textMid)),
                    if (debts.isNotEmpty) Text(debts.join(' · '), style: AppType.microBold(color: AppColors.warning)),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    rpNum(balance),
                    maxLines: 1,
                    style: AppType.bodyStrong(
                      color: balance < 0 ? AppColors.error : (balance > 0 ? AppColors.textHi : AppColors.textMid),
                    ),
                  ),
                  Text('dashboard.balance'.tr(), style: AppType.micro(color: AppColors.textLow)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «طلبات الرصيد» فوق قائمة المدراء — العدد وما ينتظر، والنقر يفتح القائمة.
class _BalanceRequestsBanner extends StatelessWidget {
  const _BalanceRequestsBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.warningSoftBg,
        borderRadius: BorderRadius.circular(R.card),
        child: InkWell(
          key: const ValueKey('balreq-managers-banner'),
          borderRadius: BorderRadius.circular(R.card),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IncomingBalanceRequestsScreen()));
            unawaited(BalanceReqState.refreshCount(force: true));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
            child: Row(children: [
              Icon(LucideIcons.handCoins, color: AppColors.warningOnSoft),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Text('طلبات الرصيد — $count بانتظارك', style: AppType.bodyStrong(color: AppColors.warningOnSoft)),
              ),
              Icon(LucideIcons.chevronLeft, color: AppColors.warningOnSoft),
            ]),
          ),
        ),
      );
}
