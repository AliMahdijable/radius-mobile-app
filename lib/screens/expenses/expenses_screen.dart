
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/expenses_api.dart';
import '../reports/widgets/date_range_chip.dart';
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

/// مديول "الصرفيات" — قائمة الصرفيات + فلتر نطاق التواريخ + كرت
/// إجمالي + add/edit/delete. منقول لـv2 من ضمن "قوائم أخرى".
/// مصمم بنفس قواعد بقية شاشات v2: AppBar نظيف، كروت ملوّنة، أيقونات
/// Lucide، تفاعل ناعم. الـbackend جاهز:
///   GET    /api/admin/expenses?from=&to=
///   PUT    /api/admin/expenses/:id
///   DELETE /api/admin/expenses/:id
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

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
  // النطاق الافتراضي: أول الشهر إلى اليوم (مطابق الويب)، بشريط الفترات نفسه الذي في التقارير.
  DateRange _range = DateRange.thisMonth();

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  Future<void> _load({bool withRecurring = true}) async {
    setState(() {
      _loading = true;
      if (withRecurring) _recurringToken++;
    });
    final r = await ExpensesApi.list(
      from: _fmtDate(_range.from),
      to: _fmtDate(_range.to),
      includeArchived: _withArchive,
    );
    if (!mounted) return;
    setState(() {
      _rows = r.rows;
      _total = r.total;
      _archive = r.archive;
      _loading = false;
    });
  }

  Future<void> _openAdd() async {
    final added = await showAddExpenseSheet(context);
    if (added == true) _load();
  }

  Future<void> _openEdit(ExpenseRow row) async {
    if (row.isLocked) {
      showSheetSnack(
        context,
        'exp.locked'.tr(namedArgs: {'n': '${row.settlementNumber}'}),
        isError: true,
      );
      return;
    }
    final changed = await showEditExpenseSheet(context, row);
    if (changed == true) _load();
  }

  Future<void> _confirmDelete(ExpenseRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('exp.delete_title'.tr()),
        content: Text(
          'exp.delete_body'.tr(namedArgs: {
            'amt': '${formatIQD(row.amount)} ${'common.currency'.tr()}'
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final result = await ExpensesApi.delete(row.id);
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
    if (result.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.brandAccent;
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
            padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 96),
            children: [
              // 2026-08-26 redesign: header صف واحد كثيف — إجمالي + نطاق
              // + عدد. بلا gradient بلا حواف ثقيلة.
              DeskSection(children: [
                _CompactHeader(
                  total: _total,
                  count: _rows.length,
                  range: _range,
                  accent: accent,
                  onRange: (r) {
                    setState(() => _range = r);
                    _load();
                  },
                ),
              ]),
              // «الصرفيات الثابتة» — حين يفتحها الخادم للحساب (وإلّا لا شيء هنا).
              RecurringExpensesSection(
                reloadToken: _recurringToken,
                onExpensesChanged: () => _load(withRecurring: false),
              ),
              ArchiveBar(
                archive: _archive,
                includeArchived: _withArchive,
                onChanged: (v) {
                  setState(() => _withArchive = v);
                  _load();
                },
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Sp.lg),
                  child: _emptyState(),
                )
              else
                DeskSection(children: [
                  for (final row in _rows)
                    _ExpenseTile(
                      row: row,
                      onEdit: () => _openEdit(row),
                      onDelete: () => _confirmDelete(row),
                    ),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(Sp.huge),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.receiptText, size: 36, color: AppColors.textLow),
          const SizedBox(height: 10),
          Text(
            'exp.empty_range'.tr(),
            style:
                AppType.muted(color: AppColors.textHi).copyWith(fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'exp.empty_hint'.tr(),
            style: AppType.muted().copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// 2026-08-26 redesign: header مضغوط بلا gradient بلا حواف ثقيلة.
/// سطر واحد: إجمالي كبير + عدّاد. سطر ثاني: chip نطاق التاريخ.
class _CompactHeader extends StatelessWidget {
  const _CompactHeader({
    required this.total,
    required this.count,
    required this.range,
    required this.accent,
    required this.onRange,
  });
  final num total;
  final int count;
  final DateRange range;
  final Color accent;
  final ValueChanged<DateRange> onRange;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'exp.total_expenses'.tr(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMid,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatIQD(total)} د.ع',
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Text(
                  '$count عملية',
                  style: AppType.pillBold(color: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // نفس شريط الفترات في التقارير: الجاهزة + الفترة بأسماء الأشهر (المالك ٢٤ أكتوبر).
          DateRangeChipBar(value: range, onChanged: onRange),
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
    Theme.of(context);
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsetsDirectional.only(
              start: 12, end: 4, top: 10, bottom: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border, width: 0.5),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Rail — أحمر رفيع (صرفية = خرج مال)
              Container(
                width: 3,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.dangerSoftBorder,
                  borderRadius: BorderRadius.circular(R.pill),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.calendar,
                            size: 11, color: AppColors.textLow),
                        const SizedBox(width: 4),
                        Text(
                          iqDateLabel(row.expenseDate),
                          style: AppType.labelBold(color: AppColors.textHi),
                        ),
                        if ((row.actingEmployeeUsername ?? '').isNotEmpty) ...[
                          Text('  ·  ',
                              style: AppType.muted()),
                          Icon(Icons.badge,
                              size: 11, color: AppColors.brandAccent),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              row.actingEmployeeUsername!,
                              style: AppType.pillBold(color: AppColors.brandAccent),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (row.isRecurring) ...[
                      const SizedBox(height: 3),
                      ToneChip(
                        // «ثابتة · تشرين الأوّل 2026» — الشهر بالشارة لا برقمٍ بالملاحظة.
                        label: (row.recurringPeriod ?? '').isEmpty
                            ? 'rexp.badge'.tr()
                            : '${'rexp.badge'.tr()} · ${iqPeriodLabel(row.recurringPeriod)}',
                        icon: LucideIcons.repeat,
                        tone: AppTone.info,
                        dense: true,
                      ),
                    ],
                    if (_note(row).isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        _note(row),
                        style: AppType.muted(color: AppColors.textMid),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Amount — big + red (متطابق مع currency style بالكارت)
              Text(
                '${formatIQD(row.amount)} د.ع',
                style: TextStyle(
                  fontSize: 14, height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              // صرفيةٌ داخل تسوية: مقفلة — شارة رقمها بدل زرّ الحذف.
              if (row.isLocked)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: Sp.x6, end: Sp.sm),
                  child: ToneChip(
                    label: 'exp.locked_chip'
                        .tr(namedArgs: {'n': '${row.settlementNumber}'}),
                    icon: LucideIcons.lock,
                    dense: true,
                  ),
                )
              else
                IconButton(
                  icon: Icon(LucideIcons.trash2,
                      size: 15, color: AppColors.error),
                  onPressed: onDelete,
                  tooltip: 'common.delete'.tr(),
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
