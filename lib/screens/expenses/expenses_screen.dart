import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/company_route.dart';
import '../../api/expenses_api.dart';
import '../reports/v2/report_kit.dart';
import '../reports/v2/report_period.dart';
import '../reports/v2/report_prefs.dart';
import '../reports/v2/report_sheets.dart';
import '../settlements/widgets/archive_bar.dart';
import '../../api/archive_info.dart';
import '../../core/util/ar_date.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'recurring_expenses_section.dart';
import 'sheets/add_expense_sheet.dart';
import 'sheets/edit_expense_sheet.dart';
import '../desktop/desk_widgets.dart';
import '../../core/platform/desktop_layout.dart';
import '../../widgets/merged_section.dart';
import '../../core/widgets/permission_locked.dart';
import '../../services/merged_text.dart';
import '../../services/merged_mode.dart';

/// مديول "الصرفيات" — قائمة الصرفيات + فلتر نطاق التواريخ + كرت
/// إجمالي + add/edit/delete. منقول لـv2 من ضمن "قوائم أخرى".
/// مصمم بنفس قواعد بقية شاشات v2: AppBar نظيف، كروت ملوّنة، أيقونات
/// Lucide، تفاعل ناعم. الـbackend جاهز:
///   GET    /api/admin/expenses?from=&to=
///   PUT    /api/admin/expenses/:id
///   DELETE /api/admin/expenses/:id
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  /// «كل الشركات»: بغلاف قسمها (صرفيات الشركة المختارة بمكانها — expenses_routed) — من «قوائم أخرى» ومن «+ إضافة صرفية» لشركةٍ
  /// غير المفتوحة معاً.
  static Widget mergedPage() => MergedSection(
      prefixes: const ['/api/admin/expenses', '/api/v2/expenses'],
      perms: const ['reports.expenses'],
      lockTitle: 'more.expenses'.tr(),
      child: const ExpensesScreen());

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<ExpenseRow> _rows = const [];
  num _total = 0;

  /// وصف ما أخفته التسويات، و«هل نطلبه؟». الخادم يُخفي المسوّى
  /// افتراضيّاً، فقد تكون القائمة فارغةً وهي صحيحة — والشريط يشرحها.
  ArchiveInfo? _archive;
  bool _withArchive = false;
  bool _loading = true;

  /// يتغيّر مع كلّ تحديث فيُعيد قسم «الصرفيات الثابتة» جلبه.
  int _recurringToken = 0;

  /// «كل الشركات» (٨ نوفمبر): ردّ القائمة الموجَّهة — هل يقبل الخادم إضافة/تعديل/حذف صرفيات هذه الشركة من هنا (expenses_routed).
  bool? _routedWrites;

  /// شركةٌ معروضة غير المفتوحة (من [MergedSection]) — تُقرأ في build.
  MergedSectionInfo? _section;

  /// مقفلة: شركةٌ موجَّهة لم يفتح الخادم كتابتها (أو لم يصل ردّها بعد).
  /// «كل الصفحات» للموظّف (٩ نوفمبر): وصفحةٌ كتابتها مغلقةٌ له من هنا (غير صفحته الحاليّة) — ولو فتحها الخادم لمالكها.
  bool get _locked => _section != null && _section!.routed && (_routedWrites != true || MergedOps.writeLockAt(_section!.company?.key) != null);

  String get _lockText => 'merged.section_locked'.trm(args: [_section?.company?.name ?? '—']);
  // النطاق الافتراضي: أول الشهر إلى اليوم (مطابق الويب). شريط الفترة نفسه الذي في التقارير الموحّدة (٢٢ نوفمبر — بند المقترح:
  // «الصرفيّات… تبقى بـ«قوائم أخرى»، لكن بنفس شريط الفلاتر»): تسع فتراتٍ جاهزة + مخصّصة، ويتذكّر آخر فترة.
  RpRange _range = RpRange.of(RpPreset.thisMonth, now: DateTime.now());
  static const _prefsId = 'expenses';

  /// بحث القائمة (الشكل الموحّد، ٢٢ نوفمبر): في البيان والمنفّذ وصاحب كشف الراتب — بين ما جاء للفترة.
  String _q = '';

  static bool _matches(ExpenseRow r, String q) {
    final s = q.toLowerCase();
    bool has(String? v) => (v ?? '').toLowerCase().contains(s);
    return has(r.note) || has(r.actingEmployeeUsername) || has(r.payslipEmployee);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final f = await RpPrefs.load(_prefsId, now: DateTime.now());
    if (!mounted) return;
    setState(() => _range = f.range);
    await _load();
  }

  Future<void> _pickRange() async {
    final v = await showModalBottomSheet<RpFilterValue>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (ctx) => RpFilterSheet(
        subtitle: '${'more.expenses'.tr()} · ${_range.name}',
        initial: RpFilterValue(range: _range, compare: false),
        now: DateTime.now(),
        people: const [],
        showPeople: false,
        showCompare: false,
        types: const [],
      ),
    );
    if (v == null || !mounted) return;
    setState(() => _range = v.range);
    unawaited(RpPrefs.save(_prefsId, RpFilterValue(range: v.range, compare: false)));
    await _load();
  }

  String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  Future<void> _load({bool withRecurring = true}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      if (withRecurring) _recurringToken++;
    });
    // شركة القسم من شجرته صراحةً (مراجعة 179): يُعاد الجلب بعد شيتٍ أُغلق والقسم ربّما أُخفي أو غُطّي — لا يأخذ وجهة ما فوقه
    final r = await CompanyRoute.pin(
        _companyKey,
        () => ExpensesApi.list(
              from: _fmtDate(_range.from),
              to: _fmtDate(_range.to),
              includeArchived: _withArchive,
            ));
    if (!mounted) return;
    setState(() {
      _rows = r.rows;
      _total = r.total;
      _archive = r.archive;
      _routedWrites = r.routedWrites;
      _loading = false;
    });
  }

  /// «كل الشركات» (٩ نوفمبر — مراجعة 179): شركة القسم لحظة فتح الشيت أو التأكيد — تُمرَّر صراحةً فيُسجَّل لها ولو تبدّل الشريط أو
  /// أُخفي القسم أو غطّته صفحةٌ وهو مفتوح. null = المفتوحة.
  String? get _companyKey => MergedSection.routeKeyOf(context);
  String? get _companyName => MergedSection.routedCompanyOf(context)?.name;

  Future<void> _openAdd() async {
    if (_locked) {
      showNoPermission(context, action: true, message: _lockText);
      return;
    }
    final added = await showAddExpenseSheet(context, companyKey: _companyKey, companyName: _companyName);
    // القسم قد يكون أُعيد بناؤه لشركةٍ أخرى أو أُخفي وهو مفتوح — لا تحديث لشاشةٍ زالت.
    if (added == true && mounted) _load();
  }

  Future<void> _openEdit(ExpenseRow row) async {
    if (_locked) {
      showNoPermission(context, action: true, message: _lockText);
      return;
    }
    if (row.isLocked) {
      showSheetSnack(
        context,
        'exp.locked'.tr(namedArgs: {'n': '${row.settlementNumber}'}),
        isError: true,
      );
      return;
    }
    // صرفيّة كشف راتب: مبلغها من الكشف — يُلغى الكشف من حساب الموظف فتُحذف معه
    if (row.isPayslip) {
      showSheetSnack(context, 'exp.payslip_locked'.tr(), isError: true);
      return;
    }
    final changed = await showEditExpenseSheet(context, row, companyKey: _companyKey, companyName: _companyName);
    if (changed == true && mounted) _load();
  }

  Future<void> _confirmDelete(ExpenseRow row) async {
    if (_locked) {
      showNoPermission(context, action: true, message: _lockText);
      return;
    }
    final companyKey = _companyKey;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('exp.delete_title'.tr()),
        content: Text(
          'exp.delete_body'.tr(namedArgs: {'amt': '${formatIQD(row.amount)} ${'common.currency'.tr()}'}),
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
    final result = await ExpensesApi.delete(row.id, companyKey: companyKey);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.ok ? 'exp.deleted'.tr() : (result.message ?? 'subscribers.delete_failed'.tr())),
        backgroundColor: result.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (result.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.brandAccent;
    _section = MergedSection.of(context);
    final routed = _section?.routed == true;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'more.expenses'.tr(),
            style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
          ),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
        primary: DeskPrimaryButton(
          icon: LucideIcons.plus,
          label: 'common.add'.tr(),
          onTap: _openAdd,
        ),
      ),
      floatingActionButton: DesktopScope.of(context)
          ? null
          : FloatingActionButton.extended(
              backgroundColor: accent,
              foregroundColor: AppColors.onBrand,
              onPressed: _openAdd,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: Text('common.add'.tr()),
            ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: accent,
          child: ListView(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 96),
            children: [
              // «كل الشركات»: الشركات ومن تُعرض (والمقفلة بسببها)
              MergedSectionBar(lockedText: _locked && !_loading ? _lockText : null),
              // الشكل الموحّد (٢٢ نوفمبر — المالك: «بقى عندك… أقسام بعده ما كاملات، كمّلهن كلّهن»): شريط الفترة، ثمّ المجموع بطاقةً كبرى
              // (RpHeroKpi)، ثمّ المصاريف ببحثٍ وتحت أيّامها بمجموع كلّ يوم — الإضافة والتعديل والحذف كما كانت.
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // الرأس بسطرٍ واحد (المالك ٢٢ نوفمبر): الأرشيف مختصراً فوق الفترة
                    RpHeader(
                      period: RpPeriod(name: _range.name, range: _range.rangeText),
                      onPeriod: _pickRange,
                      top: !(_archive?.show ?? false)
                          ? null
                          : ArchiveBar(
                              compact: true,
                              archive: _archive,
                              includeArchived: _withArchive,
                              onChanged: (v) {
                                setState(() => _withArchive = v);
                                _load();
                              },
                            ),
                    ),
                    const SizedBox(height: Sp.md),
                    RpHeroKpi(
                      key: const ValueKey('exp-total'),
                      kpi: RpKpi(id: 'total', label: 'exp.total_expenses'.tr(), value: _total, icon: LucideIcons.receiptText, tone: RpTone.loss),
                      compareWith: '',
                      spark: const [],
                      note: '${formatIQD(_rows.length)} عملية · ${_range.name}',
                    ),
                  ],
                ),
              ),
              // «الصرفيات الثابتة» — حين يفتحها الخادم للحساب (وإلّا لا شيء هنا). شركةٌ موجَّهة: قوالبها من صفحتها (مساراتها غير
              // موجَّهة بعد) — لا تُعرض قوالب المفتوحة تحت اسمها.
              if (!routed)
                RecurringExpensesSection(
                  reloadToken: _recurringToken,
                  onExpensesChanged: () => _load(withRecurring: false),
                ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
                  child: _listCard(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// المصاريف ببطاقة التقارير الموحّدة: العنوان وعددها، البحث، ثمّ تحت كلّ يومٍ مصاريفه ومجموعه.
  Widget _listCard() {
    final q = _q.trim();
    final shown = q.isEmpty
        ? _rows
        : [
            for (final r in _rows)
              if (_matches(r, q)) r
          ];
    final groups = <({String day, List<ExpenseRow> rows})>[];
    for (final r in shown) {
      final day = r.expenseDate;
      if (groups.isEmpty || groups.last.day != day) {
        groups.add((day: day, rows: [r]));
      } else {
        groups.last.rows.add(r);
      }
    }
    return RpCard(
      key: const ValueKey('exp-list'),
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RpTitle(
            icon: LucideIcons.listOrdered,
            title: 'more.expenses'.tr(),
            tone: RpTone.neutral,
            trailing: Text('${formatIQD(_rows.length)} مصروف', style: AppType.pillBold(color: AppColors.textMid)),
          ),
          // لا مصاريف بالفترة: داخل البطاقة نفسها لا صندوقٌ كبير وحده (لقطة المالك ٢٣ نوفمبر)
          if (_rows.isEmpty) ...[
            const SizedBox(height: Sp.lg),
            Icon(LucideIcons.receiptText, size: 30, color: AppColors.textLow),
            const SizedBox(height: Sp.sm),
            Text('exp.empty_range'.tr(), textAlign: TextAlign.center, style: AppType.bodyBold(color: AppColors.textHi)),
            const SizedBox(height: Sp.xxs),
            Text('exp.empty_hint'.tr(), textAlign: TextAlign.center, style: AppType.micro(color: AppColors.textMid)),
            const SizedBox(height: Sp.md),
          ] else ...[
          const SizedBox(height: Sp.md),
          RpSearchBox(key: const ValueKey('exp-search'), query: _q, hint: 'ابحث بالبيان أو المنفّذ', onChanged: (v) => setState(() => _q = v)),
          ],
          if (_rows.isNotEmpty && shown.isEmpty) ...[
            const SizedBox(height: Sp.lg),
            Center(child: Text('لا مصروف يطابق «$q»', style: AppType.muted(color: AppColors.textMid))),
            const SizedBox(height: Sp.sm),
          ],
          for (final g in groups) ...[
            const SizedBox(height: Sp.md),
            RpDayHead(
              day: RpDay(date: iqDateLabel(g.day), count: g.rows.length, sum: g.rows.fold<num>(0, (a, r) => a + r.amount), rows: const []),
              unit: 'مصروف',
              sumLabel: 'المجموع',
            ),
            for (var i = 0; i < g.rows.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.divider),
              _ExpenseTile(
                row: g.rows[i],
                onEdit: () => _openEdit(g.rows[i]),
                onDelete: () => _confirmDelete(g.rows[i]),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// 2026-08-26 redesign: tile مسطّح مع hairline divider. لا حواف كامل
/// لكل صف. المبلغ RTL end (يسار)، الوصف/التاريخ middle، حذف على أطراف.
/// المصمم متطابق مع صفّ المشترك الجديد (rail 3dp + fixed metric column).
class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({
    required this.row,
    required this.onEdit,
    required this.onDelete,
  });
  final ExpenseRow row;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// المولَّدة من قالب: الخادم يُلحق «(ثابتة 2026-10)» — الشارة تقولها بالشهر فتُحذف من هنا.
  static String _note(ExpenseRow r) {
    final n = (r.note ?? '').trim();
    return r.isRecurring ? stripRecurringSuffix(n) : n;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final note = _note(row);
    final who = (row.actingEmployeeUsername ?? '').trim();
    // سطرٌ بشكل التقارير الموحّدة (٢٢ نوفمبر): مربّع الأيقونة، البيان، المنفّذ وشاراته، المبلغ بطرفه — واليوم في رأس مجموعته.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('exp-row-${row.id}'),
        onTap: onEdit,
        borderRadius: BorderRadius.circular(R.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.sm),
          child: Row(
            children: [
              RpIconBox(
                icon: row.isPayslip ? LucideIcons.users : (row.isRecurring ? LucideIcons.repeat : LucideIcons.receiptText),
                tone: RpTone.loss,
                size: 36,
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // المالك ٢٥ أكتوبر: «معلومات الصرفيّة ناعمة جدّاً» — البيان عنواناً بخطٍّ واضح
                    Text(note.isEmpty ? 'exp.total_expenses'.tr() : note,
                        style: AppType.bodyBold(color: AppColors.textHi), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (who.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.badge, size: 11, color: AppColors.brandAccent),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(who, style: AppType.pillBold(color: AppColors.brandAccent), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    if (row.isPayslip) ...[
                      const SizedBox(height: 3),
                      _Tag(
                        key: ValueKey('exp-payslip-${row.id}'),
                        // «كشف راتب 3 · أحمد» — صرفيّةٌ كتبها صرف الراتب
                        // «من مالي الخاص» (٢٣ نوفمبر): «· من مال المدير» — لا يُحسب على الصندوق
                        label: '${(row.payslipEmployee ?? '').isEmpty ? 'exp.payslip_chip'.tr(namedArgs: {'n': '${row.payslipNumber}'}) : '${'exp.payslip_chip'.tr(namedArgs: {'n': '${row.payslipNumber}'})} · ${row.payslipEmployee}'}'
                            '${row.payslipOwn ? ' · من مال المدير' : ''}',
                        icon: LucideIcons.users,
                        tone: AppTone.brand,
                      ),
                    ],
                    if (row.isRecurring) ...[
                      const SizedBox(height: 3),
                      _Tag(
                        // «ثابتة · 2026/10» — الشهر بالشارة لا بلاحقة الملاحظة.
                        label:
                            (row.recurringPeriod ?? '').isEmpty ? 'rexp.badge'.tr() : '${'rexp.badge'.tr()} · ${iqPeriodLabel(row.recurringPeriod)}',
                        icon: LucideIcons.repeat,
                        tone: AppTone.info,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              // المبلغ بلا «د.ع» كسطور التقارير الموحّدة (مجموع اليوم فوقه بعملته) — فيتّسع البيان وشارته على ٣٢٠
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  formatIQD(row.amount),
                  maxLines: 1,
                  style: AppType.bodyStrong(color: AppColors.error)
                      .copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              // صرفيةٌ داخل تسوية: مقفلة — شارة رقمها بدل زرّ الحذف.
              if (row.isLocked)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: Sp.x6),
                  child: ToneChip(
                    label: 'exp.locked_chip'.tr(namedArgs: {'n': '${row.settlementNumber}'}),
                    icon: LucideIcons.lock,
                    dense: true,
                  ),
                )
              else if (row.isPayslip)
                // صرفيّة كشف راتب: لا حذف من هنا (قفلٌ بمكان الزرّ)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: Sp.x6, end: Sp.xs),
                  child: Icon(LucideIcons.lock, size: 14, color: AppColors.textLow),
                )
              else
                IconButton(
                  icon: Icon(LucideIcons.trash2, size: 15, color: AppColors.error),
                  onPressed: onDelete,
                  tooltip: 'common.delete'.tr(),
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شارةٌ صغيرة بلون نغمتها نصُّها يلتفّ ولا يُختصر «…» (ToneChip يختصر — كان «ثابتة · 2026/10» يصير «ثابتة · 2…» على ٣٢٠).
class _Tag extends StatelessWidget {
  const _Tag({super.key, required this.label, required this.icon, required this.tone});
  final String label;
  final IconData icon;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: tone.softBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: tone.fill),
          const SizedBox(width: Sp.xs),
          Flexible(child: Text(label, style: AppType.pillLabel(color: tone.onSoft).copyWith(letterSpacing: 0))),
        ],
      ),
    );
  }
}
