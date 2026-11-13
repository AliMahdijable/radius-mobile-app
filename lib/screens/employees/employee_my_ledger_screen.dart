import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/employee_ledger_api.dart';
import '../../core/util/format.dart';
import '../../services/dashboard_refresh_signal.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'employee_ledger_widgets.dart';

/// «سلفي وراتبي» — بطاقة الموظّف في الرئيسيّة («حركات الموظف»، ١٣ نوفمبر): سطرٌ واحد بما عليه أو له وراتبه، والنقر يفتح
/// حسابه قراءةً فقط.
///
/// الموظّف وحده، وحين يقول الخادم إنّ الميزة مفتوحة لصفحته **وله ما يُعرض** (سلفة، قرض، مكافأة، راتبٌ مضبوط أو حركةٌ سابقة).
/// غير ذلك ⇒ لا شيء ولا مساحة. تجلب `/api/v2/employee-ledger/me` بنفسها وتتحدّث مع سحب الرئيسيّة.
class EmployeeLedgerCard extends StatefulWidget {
  const EmployeeLedgerCard({super.key, this.loader});

  /// للاختبار: مصدرٌ بديل لـ[EmployeeLedgerApi.me].
  final Future<LedgerAccount?> Function()? loader;

  @override
  State<EmployeeLedgerCard> createState() => _EmployeeLedgerCardState();
}

class _EmployeeLedgerCardState extends State<EmployeeLedgerCard> {
  LedgerAccount? _a;

  @override
  void initState() {
    super.initState();
    DashboardRefreshSignal.tick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    DashboardRefreshSignal.tick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    LedgerAccount? a;
    if (widget.loader != null) {
      a = await widget.loader!();
    } else {
      if (!PermissionsService.isEmployee) return;
      final me = await EmployeeLedgerApi.me();
      // تعذّر السؤال ⇒ يبقى ما نعرفه (لا تختفي البطاقة لانقطاعٍ عابر)
      if (me == null) return;
      a = me.account;
    }
    if (!mounted) return;
    setState(() => _a = a);
  }

  /// له ما يُعرض؟
  static bool worthShowing(LedgerAccount a) => a.summary.hasNews || a.summary.salary.configured || !a.isEmpty;

  /// سطر البطاقة: ما عليه أو له أوّلاً، وإلّا راتبه.
  static ({String text, Color color})? headline(LedgerAccount a) {
    final s = a.summary;
    if (s.owesTotal > 0) return (text: 'عليك ${formatIQD(s.owesTotal)}', color: AppColors.error);
    if (s.duePending > 0) return (text: 'لك ${formatIQD(s.duePending)}', color: AppColors.success);
    if (s.duePending < 0) return (text: 'خصم ${formatIQD(-s.duePending)}', color: AppColors.error);
    final salary = s.salary.describe(formatIQD);
    if (salary != null) return (text: salary, color: AppColors.textMid);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final a = _a;
    if (a == null || !worthShowing(a)) return const SizedBox.shrink();
    final h = headline(a);
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.md),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('emp-ledger-card'),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EmployeeMyLedgerScreen(initial: a)));
            if (mounted) _load();
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.banknote, size: 16, color: AppColors.brand),
                const SizedBox(width: Sp.sm),
                Text('سلفي وراتبي', style: AppType.bodyBold(color: AppColors.textHi)),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: h == null
                      ? const SizedBox.shrink()
                      : Text(
                          h.text,
                          key: const ValueKey('emp-ledger-card-headline'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: AppType.micro(color: h.color).copyWith(fontWeight: FontWeight.w700),
                        ),
                ),
                const SizedBox(width: Sp.x6),
                Icon(Icons.arrow_back_ios_new_rounded, size: 12, color: AppColors.textLow),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// حساب الموظّف نفسه — قراءةً فقط: ما عليه (سلف وقروض)، ما له في كشفه القادم، راتبه، وحركاته وكشوفه.
class EmployeeMyLedgerScreen extends StatefulWidget {
  const EmployeeMyLedgerScreen({super.key, this.initial, this.loader});

  /// ما عرضته البطاقة — يُرسم فوراً ثمّ يُحدَّث.
  final LedgerAccount? initial;

  /// للاختبار: مصدرٌ بديل لـ[EmployeeLedgerApi.me].
  final Future<LedgerAccount?> Function()? loader;

  @override
  State<EmployeeMyLedgerScreen> createState() => _EmployeeMyLedgerScreenState();
}

class _EmployeeMyLedgerScreenState extends State<EmployeeMyLedgerScreen> {
  late LedgerAccount? _a = widget.initial;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = widget.loader != null ? await widget.loader!() : (await EmployeeLedgerApi.me())?.account;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _a = a ?? _a;
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final a = _a;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('سلفي وراتبي', style: AppType.title(color: AppColors.textHi)),
      ),
      body: a == null
          ? Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : Text('تعذّر تحميل حسابك الآن — حاول بعد قليل', style: AppType.body(color: AppColors.textMid)),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge * 2),
                children: [
                  EmployeeLedgerPanel(account: a, selfView: true),
                  const SizedBox(height: Sp.lg),
                  Text(
                    'السلف والسحوبات تُستقطع من أوّل كشف راتب، والقرض بقسطه مع كلّ راتب. المدير يسجّل الحركات ويصرف الكشف.',
                    style: AppType.micro(color: AppColors.textLow),
                  ),
                ],
              ),
            ),
    );
  }
}
