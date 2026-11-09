import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/employee_limits_api.dart';
import '../../core/util/amount_input.dart';
import '../../core/util/format.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/employee_limits_card.dart';

/// حساب الموظّف مع مديره (٩ نوفمبر — «حدود الموظّف»): أرقام فترته، حدوده، المحجوز غير المؤكَّد، «تسوية مع الموظف»، وسجلّ تسوياته.
/// للمدير وحده (الخادم يرفض غيره بـMANAGER_ONLY).
class EmployeeAccountScreen extends StatefulWidget {
  const EmployeeAccountScreen({super.key, required this.employeeId, required this.title});
  final int employeeId;
  final String title;

  @override
  State<EmployeeAccountScreen> createState() => _EmployeeAccountScreenState();
}

class _EmployeeAccountScreenState extends State<EmployeeAccountScreen> {
  EmployeeLimitStatus? _s;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _s == null;
      _error = null;
    });
    final r = await EmployeeLimitsApi.get(widget.employeeId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _s = r.data ?? _s;
      _error = r.data == null ? (r.message ?? 'تعذّر التحميل') : null;
    });
  }

  Future<void> _editLimits() async {
    final s = _s;
    if (s == null) return;
    final saved = await showEmployeeLimitsSheet(context, employeeId: widget.employeeId, initial: s.limits, name: s.displayName);
    if (saved == true) _load();
  }

  Future<void> _settle() async {
    final done = await showEmployeeSettleSheet(context, employeeId: widget.employeeId, name: _s?.displayName ?? widget.title);
    if (done != null) {
      if (mounted) showSheetSnack(context, 'سُوّي حساب الموظف — بدأت فترةٌ جديدة', isError: false);
      _load();
    }
  }

  Future<void> _releaseHold(EmployeeLimitHold h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('تحرير المبلغ المحجوز', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        content: Text(
          'عمليّة «${h.opLabel}» (${h.statusLabel}) محجوزةٌ في سقف الموظف. حرّرها فقط إن تأكّدت أنّها لم تُنفَّذ أو أنّها ظهرت في السجلّ.',
          style: AppType.body(color: AppColors.textMid),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('تحرير')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await EmployeeLimitsApi.releaseHold(widget.employeeId, h.id, reason: 'حرّره المدير');
    if (!mounted) return;
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'تعذّر التحرير', isError: true);
      return;
    }
    _load();
  }

  Future<void> _voidLatest(EmployeeSettlement st) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('إلغاء التسوية ${st.number ?? ''}', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تعود أرقام فترتها إلى الحساب الحاليّ.', style: AppType.body(color: AppColors.textMid)),
            const SizedBox(height: Sp.md),
            TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'سبب الإلغاء')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('تراجع')),
          TextButton(onPressed: () => Navigator.of(c).pop(ctrl.text.trim()), child: const Text('إلغاء التسوية')),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || reason.length < 3) return;
    final r = await EmployeeLimitsApi.voidSettlement(widget.employeeId, st.id, reason);
    if (!mounted) return;
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'تعذّر الإلغاء', isError: true);
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = _s;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('حساب ${widget.title}', style: AppType.title(color: AppColors.textHi)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : s == null
              ? Center(child: Text(_error ?? 'تعذّر التحميل', style: AppType.body(color: AppColors.textMid)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge * 2),
                    children: [
                      if (!s.started)
                        _Note(text: s.limits.isEmpty
                            ? 'لم تُضبط حدودٌ لهذا الموظف بعد — اضبط سقفاً أو ربحاً ليبدأ العدّ من الآن.'
                            : 'يبدأ العدّ من لحظة ضبط الحدود.')
                      else
                        EmployeeLimitsPanel(status: s, title: 'الفترة الحاليّة'),
                      const SizedBox(height: Sp.md),
                      _LimitsSummary(limits: s.limits, onEdit: _editLimits),
                      if (s.holds.isNotEmpty) ...[
                        const SizedBox(height: Sp.lg),
                        Text('مبالغ محجوزة (غير مؤكَّدة)', style: AppType.bodyBold(color: AppColors.textHi)),
                        const SizedBox(height: Sp.sm),
                        for (final h in s.holds)
                          _HoldTile(hold: h, onRelease: () => _releaseHold(h)),
                      ],
                      if (s.started) ...[
                        const SizedBox(height: Sp.lg),
                        FilledButton.icon(
                          key: const ValueKey('emp-settle-open'),
                          onPressed: _settle,
                          icon: const Icon(LucideIcons.handCoins, size: 18),
                          label: const Text('تسوية مع الموظف'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.brand,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.button)),
                          ),
                        ),
                      ],
                      if (s.settlements.isNotEmpty) ...[
                        const SizedBox(height: Sp.lg),
                        Text('التسويات السابقة', style: AppType.bodyBold(color: AppColors.textHi)),
                        const SizedBox(height: Sp.sm),
                        for (final st in s.settlements)
                          _SettlementTile(
                            st: st,
                            onVoid: !st.voided && st.id == s.settlements.firstWhere((x) => !x.voided, orElse: () => st).id
                                ? () => _voidLatest(st)
                                : null,
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.md)),
        child: Text(text, style: AppType.body(color: AppColors.textMid)),
      );
}

class _LimitsSummary extends StatelessWidget {
  const _LimitsSummary({required this.limits, required this.onEdit});
  final EmployeeLimits limits;
  final VoidCallback onEdit;

  String _v(double? v, {String none = 'بلا حدّ'}) => v == null || v == 0 ? none : '${formatIQD(v)} د.ع';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.sm, Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('سقف الديون: ${_v(limits.debtCap)}', style: AppType.body(color: AppColors.textHi)),
                Text('سقف الإيرادات النقديّة: ${_v(limits.cashCap)}', style: AppType.body(color: AppColors.textHi)),
                Text('ربح الموظف لكلّ عمليّة: ${_v(limits.profitPerOp, none: 'لا ربح')}', style: AppType.body(color: AppColors.textHi)),
              ],
            ),
          ),
          TextButton.icon(
            key: const ValueKey('emp-limits-edit'),
            onPressed: onEdit,
            icon: const Icon(LucideIcons.pencil, size: 15),
            label: const Text('تعديل'),
          ),
        ],
      ),
    );
  }
}

class _HoldTile extends StatelessWidget {
  const _HoldTile({required this.hold, required this.onRelease});
  final EmployeeLimitHold hold;
  final VoidCallback onRelease;
  @override
  Widget build(BuildContext context) {
    final amount = [
      if (hold.cash > 0) '${formatIQD(hold.cash)} نقداً',
      if (hold.debt > 0) '${formatIQD(hold.debt)} ديناً',
    ].join(' · ');
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: Sp.x6),
      child: ListTile(
        dense: true,
        title: Text('${hold.opLabel} — $amount', style: AppType.bodyBold(color: AppColors.textHi)),
        subtitle: Text(hold.statusLabel, style: AppType.micro(color: AppColors.warning)),
        trailing: TextButton(onPressed: onRelease, child: const Text('تحرير')),
      ),
    );
  }
}

class _SettlementTile extends StatelessWidget {
  const _SettlementTile({required this.st, this.onVoid});
  final EmployeeSettlement st;
  final VoidCallback? onVoid;
  @override
  Widget build(BuildContext context) {
    final d = st.cutAt;
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: Sp.x6),
      child: ListTile(
        dense: true,
        title: Text(
          'تسوية ${st.number ?? ''}${d != null ? ' — ${d.day}/${d.month}' : ''}${st.voided ? ' (ملغاة)' : ''}',
          style: AppType.bodyBold(color: st.voided ? AppColors.textLow : AppColors.textHi),
        ),
        subtitle: Text(
          'نقد ${formatIQD(st.cashIn)} · '
          '${st.openDebt != null ? 'ديونه المفتوحة وقتها ${formatIQD(st.openDebt!)}' : st.openDebtUnavailable ? 'ديونه المفتوحة وقتها —' : 'دين ${formatIQD(st.debtOut)}'} · '
          '${st.opsCount} عمليّة · ربح ${formatIQD(st.profit)}',
          style: AppType.micro(color: AppColors.textMid),
        ),
        trailing: onVoid == null ? null : TextButton(onPressed: onVoid, child: const Text('إلغاء')),
      ),
    );
  }
}

/// الحقول الثلاثة (المدير وحده) — في محرّر الموظف وفي شيت «تعديل الحدود». فارغ/صفر = بلا حدّ.
class EmployeeLimitsFields extends StatelessWidget {
  const EmployeeLimitsFields({
    super.key,
    required this.debtCtrl,
    required this.cashCtrl,
    required this.profitCtrl,
    required this.onChanged,
  });
  final TextEditingController debtCtrl;
  final TextEditingController cashCtrl;
  final TextEditingController profitCtrl;
  final VoidCallback onChanged;

  static EmployeeLimits read(TextEditingController d, TextEditingController c, TextEditingController p) {
    double? v(TextEditingController t) {
      final n = AmountShorthand.parse(t.text);
      return n > 0 ? n.toDouble() : null;
    }

    return EmployeeLimits(debtCap: v(d), cashCap: v(c), profitPerOp: v(p));
  }

  static String initialText(double? v) => v == null || v <= 0 ? '' : AmountShorthand.format(v.round());

  Widget _row(String label, String hint, TextEditingController ctrl, Key key) => Padding(
        padding: const EdgeInsets.only(bottom: Sp.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: Sp.x6),
            AmountTextField(key: key, controller: ctrl, compact: true, allowExact: true, hint: hint, onValue: (_) => onChanged()),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row('سقف الديون', 'بلا حدّ', debtCtrl, const ValueKey('emp-limit-debt')),
        _row('سقف الإيرادات النقديّة', 'بلا حدّ', cashCtrl, const ValueKey('emp-limit-cash')),
        _row('ربح الموظف لكلّ عمليّة', 'لا ربح', profitCtrl, const ValueKey('emp-limit-profit')),
        Text(
          'سقف الديون على ديونه المفتوحة عند المشتركين (تنقص حين يسدّدون، ولا تصفّرها التسوية): بعده لا بيع ولا تفعيل بالآجل ولا إضافة دين. '
          'وبعد سقف الإيرادات لا تفعيل نقديّ ولا بيعٌ نقداً ولا استلام دين حتى تسوّي حسابه. '
          'الربح لكلّ عمليّةٍ كاملة (تفعيلٌ نقديّ كامل، بيعٌ نقداً، تسديدٌ يصفّر الدين). فارغ = بلا حدّ.',
          style: AppType.micro(color: AppColors.textLow),
        ),
      ],
    );
  }
}

/// شيت «تعديل الحدود» للموظّف — يحفظ بنفسه ويُرجع true عند الحفظ.
Future<bool?> showEmployeeLimitsSheet(BuildContext context, {required int employeeId, required EmployeeLimits initial, required String name}) {
  return showAppSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _LimitsSheet(employeeId: employeeId, initial: initial, name: name),
  );
}

class _LimitsSheet extends StatefulWidget {
  const _LimitsSheet({required this.employeeId, required this.initial, required this.name});
  final int employeeId;
  final EmployeeLimits initial;
  final String name;
  @override
  State<_LimitsSheet> createState() => _LimitsSheetState();
}

class _LimitsSheetState extends State<_LimitsSheet> {
  late final _d = TextEditingController(text: EmployeeLimitsFields.initialText(widget.initial.debtCap));
  late final _c = TextEditingController(text: EmployeeLimitsFields.initialText(widget.initial.cashCap));
  late final _p = TextEditingController(text: EmployeeLimitsFields.initialText(widget.initial.profitPerOp));
  bool _saving = false;

  @override
  void dispose() {
    _d.dispose();
    _c.dispose();
    _p.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await EmployeeLimitsApi.put(widget.employeeId, EmployeeLimitsFields.read(_d, _c, _p));
    if (!mounted) return;
    setState(() => _saving = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'تعذّر حفظ الحدود', isError: true);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.gauge,
        title: 'حدود الموظف',
        subtitle: widget.name,
        onClose: _saving ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _saving ? 'جاري الحفظ...' : 'حفظ',
        icon: LucideIcons.save,
        busy: _saving,
        onPressed: _save,
      ),
      body: EmployeeLimitsFields(debtCtrl: _d, cashCtrl: _c, profitCtrl: _p, onChanged: () {}),
    );
  }
}

/// شيت «تسوية مع الموظف»: معاينةٌ طازجة ← تأكيد بالحدّ والأرقام نفسها. يُرجع السند المحفوظ أو null.
Future<EmployeeSettlement?> showEmployeeSettleSheet(BuildContext context, {required int employeeId, required String name}) {
  return showAppSheet<EmployeeSettlement>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => EmployeeSettleSheet(employeeId: employeeId, name: name),
  );
}

class EmployeeSettleSheet extends StatefulWidget {
  const EmployeeSettleSheet({super.key, required this.employeeId, required this.name});
  final int employeeId;
  final String name;
  @override
  State<EmployeeSettleSheet> createState() => _EmployeeSettleSheetState();
}

class _EmployeeSettleSheetState extends State<EmployeeSettleSheet> {
  SettlementPreview? _p;
  String? _error;
  bool _loading = true;
  bool _submitting = false;
  final _note = TextEditingController();
  String _key = _newKey();

  static String _newKey() => 'el${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await EmployeeLimitsApi.preview(widget.employeeId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _p = r.data;
      _error = r.data == null ? (r.message ?? 'تعذّرت المعاينة') : null;
      _key = _newKey();
    });
  }

  Future<void> _confirm() async {
    final p = _p;
    if (p == null) return;
    setState(() => _submitting = true);
    final r = await EmployeeLimitsApi.settle(widget.employeeId, p, note: _note.text, idempotencyKey: _key);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (r.ok) {
      Navigator.of(context).pop(r.data);
      return;
    }
    if (r.code == 'STALE' || r.code == 'HEAD_CHANGED') {
      showSheetSnack(context, r.message ?? 'تغيّرت الأرقام — راجعها من جديد', isError: true);
      _load();
      return;
    }
    showSheetSnack(context, r.message ?? 'تعذّرت التسوية', isError: true);
  }

  /// سطر مبلغ؛ sum = null ⇒ «—» (قراءةٌ تعذّرت لا تُعرض صفراً).
  Widget _line(String label, double? sum, int count, {bool strong = false, Key? valueKey}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(count > 0 ? '$label ($count)' : label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textMid))),
            Text(sum == null ? '—' : '${formatIQD(sum)} د.ع',
                key: valueKey, style: strong ? AppType.bodyBold(color: AppColors.textHi) : AppType.body(color: AppColors.textHi)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = _p;
    MoneyCount b(String k) => p?.breakdown[k] ?? const MoneyCount(0, 0);
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.handCoins,
        title: 'تسوية مع الموظف',
        subtitle: widget.name,
        onClose: _submitting ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: p == null
          ? null
          : SheetFooterBar(
              label: _submitting ? 'جاري التسوية...' : 'تأكيد التسوية — تصفير النقد',
              icon: LucideIcons.check,
              busy: _submitting,
              onPressed: _confirm,
            ),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(Sp.xl), child: Center(child: CircularProgressIndicator()))
          : p == null
              ? Text(_error ?? 'تعذّرت المعاينة', style: AppType.body(color: AppColors.error))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('النقد الذي يسلّمه الموظف', style: AppType.micro(color: AppColors.textLow)),
                    Text('${formatIQD(p.cashIn)} د.ع',
                        key: const ValueKey('emp-settle-cash'), style: AppType.amount(color: AppColors.textHi)),
                    const SizedBox(height: Sp.sm),
                    _line('تفعيل نقديّ', b('cash_activations').sum, b('cash_activations').count),
                    _line('تسديد ديون', b('debt_payments').sum, b('debt_payments').count),
                    _line('بيع مواد نقداً', b('sales_cash').sum, b('sales_cash').count),
                    const Divider(),
                    _line(p.openDebtApprox && p.openDebt != null ? 'ديونه المفتوحة (تقريبيّة، لا تُصفَّر)' : 'ديونه المفتوحة عند المشتركين (لا تُصفَّر)',
                        p.openDebt, 0, strong: true, valueKey: const ValueKey('emp-settle-open-debt')),
                    if (p.openDebtUnavailable)
                      Text('تعذّرت قراءة ديونه المفتوحة الآن — التسوية تشمل النقد وحده، والديون باقية عليه.',
                          key: const ValueKey('emp-settle-open-debt-unavailable'), style: AppType.micro(color: AppColors.warning)),
                    _line('ديونٌ أعطاها في الفترة', p.debtOut, 0),
                    _line('تفعيل بالآجل', b('credit_activations').sum, b('credit_activations').count),
                    _line('غير المدفوع من الجزئيّ', b('partial_unpaid').sum, b('partial_unpaid').count),
                    _line('ديون مضافة (ومنها بيعٌ بالآجل)', b('debts_added').sum, b('debts_added').count),
                    const Divider(),
                    _line('ربح الموظف (${p.opsCount} عمليّة كاملة)', p.profit, 0, strong: true),
                    Text('الربح للعرض — لا يُطرح من النقد.', style: AppType.micro(color: AppColors.textLow)),
                    if (p.holdsCount > 0) ...[
                      const SizedBox(height: Sp.sm),
                      Text(
                        'غير مؤكَّد (لا يدخل المبلغ): ${p.holdsCount} عمليّة'
                        '${p.holdsCash > 0 ? ' · ${formatIQD(p.holdsCash)} نقداً' : ''}'
                        '${p.holdsDebt > 0 ? ' · ${formatIQD(p.holdsDebt)} ديناً' : ''} — نقدها يُصفَّر بالتسوية، ودينها يبقى حتى يُحرَّر.',
                        style: AppType.micro(color: AppColors.warning),
                      ),
                    ],
                    const SizedBox(height: Sp.md),
                    TextField(
                      controller: _note,
                      decoration: const InputDecoration(hintText: 'ملاحظة (اختياريّ)'),
                    ),
                  ],
                ),
    );
  }
}
