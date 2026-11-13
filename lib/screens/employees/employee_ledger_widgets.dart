import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/employee_ledger_api.dart';
import '../../core/util/amount_input.dart';
import '../../core/util/ar_date.dart';
import '../../core/util/format.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// «حركات الموظف» وراتبه (١٣ نوفمبر): لوحة «له / عليه» داخل «حساب الموظف»، ورقتا «حركة جديدة» و«كشف الراتب»، منتقي الموظف
/// (للإضافة السريعة)، وحقول الراتب في محرّر الموظف. كلّ رقمٍ من الخادم — الواجهة لا تحسب مالاً، والكشف يُصرف بما عُرض.

String _iqd(num v) => '${formatIQD(v)} د.ع';

/// المبلغ كما سيُحفظ: اختصار الآلاف يُطبَّق ولو لم يخرج المؤشّر من الحقل بعد (٢٥ ⇒ ٢٥٬٠٠٠ — كما يقول تلميح الحقل).
int ledgerAmountOf(TextEditingController c) => AmountShorthand.expand(AmountShorthand.parse(c.text));

/// «عليه 100,000» / «له 25,000» / «خصم 10,000» / null (لا شيء).
({String text, bool owes})? ledgerBalanceText(LedgerSummary? s) {
  if (s == null) return null;
  if (s.owesTotal > 0) return (text: 'عليه ${formatIQD(s.owesTotal)}', owes: true);
  if (s.duePending > 0) return (text: 'له ${formatIQD(s.duePending)}', owes: false);
  if (s.duePending < 0) return (text: 'خصم ${formatIQD(-s.duePending)}', owes: true);
  return null;
}

/// سببٌ مكتوب (٣ أحرف فأكثر) لإلغاءٍ — أو null إن تراجع.
Future<String?> askLedgerVoidReason(BuildContext context, {required String title, required String body, required String confirm}) async {
  final reason = await showDialog<String>(
    context: context,
    builder: (_) => _VoidReasonDialog(title: title, body: body, confirm: confirm),
  );
  if (reason == null) return null;
  if (reason.length < 3) {
    if (context.mounted) showSheetSnack(context, 'اكتب سبب الإلغاء', isError: true);
    return null;
  }
  return reason;
}

/// نافذة السبب تملك حقلها (يُتلَف معها بعد انتهاء حركة الإغلاق — لا قبلها).
class _VoidReasonDialog extends StatefulWidget {
  const _VoidReasonDialog({required this.title, required this.body, required this.confirm});
  final String title;
  final String body;
  final String confirm;
  @override
  State<_VoidReasonDialog> createState() => _VoidReasonDialogState();
}

class _VoidReasonDialogState extends State<_VoidReasonDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.title, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.body, style: AppType.body(color: AppColors.textMid)),
          const SizedBox(height: Sp.md),
          TextField(
            key: const ValueKey('emp-ledger-void-reason'),
            controller: _ctrl,
            decoration: const InputDecoration(hintText: 'سبب الإلغاء'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('تراجع')),
        TextButton(
          key: const ValueKey('emp-ledger-void-confirm'),
          onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}

// ─────────────────────────── لوحة الحساب ───────────────────────────

/// لوحة «له / عليه» للموظف: الملخّص، «حركة جديدة» و«كشف الراتب»، القروض، آخر الحركات والكشوف.
/// المعالجات null ⇒ بلا أزرارها ([selfView]: الموظّف يرى حسابه قراءةً فقط؛ الإلغاء للمدير وحده).
class EmployeeLedgerPanel extends StatelessWidget {
  const EmployeeLedgerPanel({
    super.key,
    required this.account,
    this.selfView = false,
    this.onMove,
    this.onPayslip,
    this.onVoidMove,
    this.onVoidPayslip,
  });
  final LedgerAccount account;
  final bool selfView;
  final VoidCallback? onMove;
  final VoidCallback? onPayslip;
  final void Function(LedgerMove m)? onVoidMove;
  final void Function(LedgerPayslip s)? onVoidPayslip;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final a = account;
    final s = a.summary;
    final salary = s.salary.describe(formatIQD);
    final there = s.salary.elsewhere;
    final thereText = there == null ? null : '${there.where}: ${there.salary.describe(formatIQD) ?? ''}';
    final who = selfView ? 'راتبك' : 'الراتب';
    final salaryLine = thereText != null
        ? (salary != null ? '$who: $salary · والثابت $thereText' : '$who $thereText')
        : salary != null
            ? '$who: $salary'
            : (selfView ? 'بلا راتبٍ مضبوط' : 'بلا راتب — يُضبط من «تعديل» الموظف');
    final due = s.salary.dueCount;
    final latest = a.latestPaid;
    return Column(
      key: const ValueKey('emp-ledger-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Figure(
                      valueKey: const ValueKey('emp-ledger-owes'),
                      label: selfView ? 'عليك (سلف وقروض)' : 'عليه (سلف وقروض)',
                      value: _iqd(s.owesTotal),
                      color: s.owesTotal > 0 ? AppColors.error : AppColors.textHi,
                    ),
                  ),
                  const SizedBox(width: Sp.md),
                  Expanded(
                    child: _Figure(
                      valueKey: const ValueKey('emp-ledger-due'),
                      label: s.duePending < 0
                          ? (selfView ? 'خصومات لكشفك القادم' : 'خصومات لكشفه القادم')
                          : (selfView ? 'لك في كشفك القادم' : 'له في كشفه القادم'),
                      value: _iqd(s.duePending.abs()),
                      color: s.duePending > 0
                          ? AppColors.success
                          : s.duePending < 0
                              ? AppColors.error
                              : AppColors.textHi,
                    ),
                  ),
                ],
              ),
              if (s.owed > 0 && s.loansTotal > 0) ...[
                const SizedBox(height: Sp.x6),
                Text('سلف وسحوبات ${formatIQD(s.owed)} · قروض ${formatIQD(s.loansTotal)}', style: AppType.micro(color: AppColors.textLow)),
              ],
              const SizedBox(height: Sp.sm),
              Divider(height: 1, color: AppColors.border),
              const SizedBox(height: Sp.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      salaryLine,
                      key: const ValueKey('emp-ledger-salary'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.micro(color: AppColors.textMid),
                    ),
                  ),
                  if (due > 0) ...[
                    const SizedBox(width: Sp.sm),
                    ToneChip(
                      key: const ValueKey('emp-ledger-salary-due'),
                      label: due == 1 ? 'راتبٌ مستحقّ' : '$due رواتب مستحقّة',
                      tone: AppTone.warning,
                      dense: true,
                    ),
                  ],
                ],
              ),
              if (onMove != null || onPayslip != null) ...[
                const SizedBox(height: Sp.md),
                Row(
                  children: [
                    if (onMove != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('emp-ledger-move'),
                          onPressed: onMove,
                          icon: const Icon(LucideIcons.plus, size: 16),
                          label: const Text('حركة جديدة', maxLines: 1, overflow: TextOverflow.ellipsis),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.brand,
                            side: BorderSide(color: AppColors.brand),
                            minimumSize: const Size.fromHeight(46),
                            padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.button)),
                          ),
                        ),
                      ),
                    if (onMove != null && onPayslip != null) const SizedBox(width: Sp.sm),
                    if (onPayslip != null)
                      Expanded(
                        child: FilledButton.icon(
                          key: const ValueKey('emp-ledger-slip'),
                          onPressed: onPayslip,
                          icon: const Icon(LucideIcons.receiptText, size: 16),
                          label: const Text('كشف الراتب', maxLines: 1, overflow: TextOverflow.ellipsis),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.brand,
                            minimumSize: const Size.fromHeight(46),
                            padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.button)),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (a.loans.isNotEmpty) ...[
          const SizedBox(height: Sp.lg),
          Text('القروض', style: AppType.bodyBold(color: AppColors.textHi)),
          const SizedBox(height: Sp.sm),
          for (final l in a.loans)
            _Tile(
              title: 'قرض ${formatIQD(l.principal)}',
              subtitle: 'القسط ${formatIQD(l.installment)} مع كلّ راتب',
              amount: 'المتبقّي ${_iqd(l.remaining)}',
              amountColor: AppColors.textHi,
            ),
        ],
        if (a.movements.isNotEmpty) ...[
          const SizedBox(height: Sp.lg),
          Text(
            a.movementsTotal > a.movements.length ? 'الحركات (آخر ${a.movements.length} من ${a.movementsTotal})' : 'الحركات',
            style: AppType.bodyBold(color: AppColors.textHi),
          ),
          const SizedBox(height: Sp.sm),
          for (final m in a.movements)
            _Tile(
              key: ValueKey('emp-ledger-move-${m.id}'),
              title: '${m.label}${m.fromHand ? ' — من النقد الذي بيده' : ''}${m.voided ? ' (ملغاة)' : ''}',
              subtitle: [
                if (m.date != null) iqDateLabel(m.date),
                if (m.voided) (m.voidReason ?? '') else (m.note ?? ''),
                if (m.byEmployee != null) 'سجّلها ${m.byEmployee}',
              ].where((x) => x.isNotEmpty).join(' · '),
              amount: _iqd(m.amount),
              amountColor: m.voided ? AppColors.textLow : (m.isMinus ? AppColors.error : AppColors.success),
              faded: m.voided,
              onVoid: !m.voided && onVoidMove != null ? () => onVoidMove!(m) : null,
            ),
        ],
        if (a.payslips.isNotEmpty) ...[
          const SizedBox(height: Sp.lg),
          Text('كشوف الرواتب', style: AppType.bodyBold(color: AppColors.textHi)),
          const SizedBox(height: Sp.sm),
          for (final p in a.payslips)
            _Tile(
              key: ValueKey('emp-ledger-slip-${p.id}'),
              title: 'كشف ${p.number}${p.paid ? '' : ' (ملغى)'}${p.periodLabels.isEmpty ? '' : ' — ${p.periodLabels.join('، ')}'}',
              subtitle: [
                if (p.payDate != null) iqDateLabel(p.payDate),
                'المستحقّ ${formatIQD(p.gross)}',
                if (p.deducted > 0) 'استُقطع ${formatIQD(p.deducted)}',
                if (p.fromHand) 'من النقد الذي بيده',
                if (!p.paid) (p.voidReason ?? ''),
              ].where((x) => x.isNotEmpty).join(' · '),
              amount: _iqd(p.net),
              amountColor: p.paid ? AppColors.textHi : AppColors.textLow,
              faded: !p.paid,
              onVoid: onVoidPayslip != null && latest != null && latest.id == p.id ? () => onVoidPayslip!(p) : null,
            ),
        ],
        if (a.isEmpty && !selfView) ...[
          const SizedBox(height: Sp.sm),
          Text('لا حركات بعد — سلفة، قرض، سحب، مكافأة، خصم أو تسديد تُسجَّل من «حركة جديدة».', style: AppType.micro(color: AppColors.textLow)),
        ],
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.color, this.valueKey});
  final String label;
  final String value;
  final Color color;
  final Key? valueKey;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textLow)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, key: valueKey, maxLines: 1, style: AppType.rowValue(color: color).copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ],
      );
}

/// سطرٌ في قوائم اللوحة: عنوانٌ ومبلغ، وتحته التفاصيل، وزرّ «إلغاء» حين يُسمح.
class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.title, required this.subtitle, required this.amount, required this.amountColor, this.faded = false, this.onVoid});
  final String title;
  final String subtitle;
  final String amount;
  final Color amountColor;
  final bool faded;
  final VoidCallback? onVoid;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.x6),
      padding: EdgeInsetsDirectional.only(start: Sp.md, end: onVoid == null ? Sp.md : Sp.xs, top: Sp.sm, bottom: Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.bodyBold(color: faded ? AppColors.textLow : AppColors.textHi),
                      ),
                    ),
                    const SizedBox(width: Sp.sm),
                    Text(
                      amount,
                      style: AppType.bodyBold(color: amountColor).copyWith(decoration: faded ? TextDecoration.lineThrough : null),
                    ),
                  ],
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
                ],
              ],
            ),
          ),
          if (onVoid != null)
            TextButton(
              onPressed: onVoid,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                minimumSize: const Size(44, 36),
                padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('إلغاء'),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────── حركة جديدة ───────────────────────────

/// ورقة «حركة جديدة» على موظّفٍ بعينه. تُرجع نصّ النجاح («سُجّلت: سلفة 100,000 د.ع») أو null.
/// [owes] ما عليه الآن (لحدّ التسديد) إن عُرف.
Future<String?> showEmployeeMoveSheet(
  BuildContext context, {
  required int employeeId,
  required String name,
  double? owes,
  LedgerKind initialKind = LedgerKind.advance,
}) {
  return showAppSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => EmployeeMoveSheet(employeeId: employeeId, name: name, owes: owes, initialKind: initialKind),
  );
}

class EmployeeMoveSheet extends StatefulWidget {
  const EmployeeMoveSheet({super.key, required this.employeeId, required this.name, this.owes, this.initialKind = LedgerKind.advance});
  final int employeeId;
  final String name;
  final double? owes;
  final LedgerKind initialKind;
  @override
  State<EmployeeMoveSheet> createState() => _EmployeeMoveSheetState();
}

class _EmployeeMoveSheetState extends State<EmployeeMoveSheet> {
  late LedgerKind _kind = widget.initialKind;
  final _amountCtrl = TextEditingController();
  final _instCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _fromHand = false;
  bool _busy = false;

  /// مفتاحٌ واحد لهذه الورقة: إعادة الضغط أو انقطاع الشبكة لا يسجّلان الحركة مرّتين.
  final String _ref = EmployeeLedgerApi.newRef('m');

  @override
  void dispose() {
    _amountCtrl.dispose();
    _instCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  int get _amount => ledgerAmountOf(_amountCtrl);
  int get _installment => ledgerAmountOf(_instCtrl);

  /// ما يمنع التسجيل الآن — أو null.
  String? get _problem {
    final a = _amount;
    final owes = widget.owes;
    if (a <= 0) return 'اكتب المبلغ';
    if (_kind == LedgerKind.loan && _installment <= 0) return 'اكتب قسط القرض';
    if (_kind == LedgerKind.loan && _installment > a) return 'القسط أكبر من مبلغ القرض';
    if (_kind == LedgerKind.repayment && owes != null && a > owes) return 'المبلغ أكبر ممّا عليه (${_iqd(owes)})';
    return null;
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_problem != null || _busy) return;
    final amount = _amount;
    final kind = _kind;
    setState(() => _busy = true);
    final r = await EmployeeLedgerApi.addMovement(
      widget.employeeId,
      kind: kind,
      amount: amount,
      fromHand: _fromHand,
      installment: kind == LedgerKind.loan ? _installment : null,
      note: _noteCtrl.text,
      clientRef: _ref,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'تعذّر تسجيل الحركة', isError: true);
      return;
    }
    Navigator.of(context).pop('سُجّلت: ${kind.label} ${_iqd(amount)}');
  }

  Widget _kindButton(LedgerKind k) {
    final on = k == _kind;
    return Expanded(
      child: Material(
        color: on ? AppColors.brandSoftBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.icon),
        child: InkWell(
          key: ValueKey('emp-move-kind-${k.wire}'),
          onTap: _busy ? null : () => setState(() => _kind = k),
          borderRadius: BorderRadius.circular(R.icon),
          child: Ink(
            height: H.segment,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.icon),
              border: Border.all(color: on ? AppColors.brand : AppColors.border, width: on ? BW.selected : BW.normal),
            ),
            child: Center(
              child: Text(
                k.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.input(color: on ? AppColors.brand : AppColors.textBody).copyWith(fontWeight: on ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final problem = _problem;
    final a = _amount;
    const kinds = LedgerKind.values;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.banknote,
        title: 'حركة موظف',
        subtitle: widget.name,
        onClose: _busy ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        key: const ValueKey('emp-move-save'),
        label: _busy ? 'جاري التسجيل...' : (problem ?? 'تسجيل ${_kind.label} — ${_iqd(a)}'),
        icon: LucideIcons.check,
        busy: _busy,
        enabled: problem == null,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSection(
            label: 'النوع',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  _kindButton(kinds[0]),
                  const SizedBox(width: Sp.sm),
                  _kindButton(kinds[1]),
                  const SizedBox(width: Sp.sm),
                  _kindButton(kinds[2]),
                ]),
                const SizedBox(height: Sp.sm),
                Row(children: [
                  _kindButton(kinds[3]),
                  const SizedBox(width: Sp.sm),
                  _kindButton(kinds[4]),
                  const SizedBox(width: Sp.sm),
                  _kindButton(kinds[5]),
                ]),
                const SizedBox(height: Sp.x6),
                Text(_kind.hint, key: const ValueKey('emp-move-hint'), style: AppType.muted(color: AppColors.textHint)),
              ],
            ),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'المبلغ',
            child: SheetBox(
              focused: a > 0,
              child: AmountTextField(
                key: const ValueKey('emp-move-amount'),
                controller: _amountCtrl,
                enabled: !_busy,
                onValue: (_) => setState(() {}),
              ),
            ),
          ),
          if (_kind.needsSource) ...[
            const SizedBox(height: Sp.lg),
            SheetSection(
              label: 'من أين يُدفع؟',
              child: SheetSegmented(
                key: const ValueKey('emp-move-source'),
                labels: const ['من الصندوق', 'من النقد الذي بيده'],
                selectedIndex: _fromHand ? 1 : 0,
                onSelect: (i) {
                  if (!_busy) setState(() => _fromHand = i == 1);
                },
              ),
            ),
          ],
          if (_kind == LedgerKind.loan) ...[
            const SizedBox(height: Sp.lg),
            SheetSection(
              label: 'القسط (يُستقطع مع كلّ راتب)',
              child: SheetBox(
                focused: _installment > 0,
                child: AmountTextField(
                  key: const ValueKey('emp-move-installment'),
                  controller: _instCtrl,
                  enabled: !_busy,
                  compact: true,
                  onValue: (_) => setState(() {}),
                ),
              ),
            ),
          ],
          if (_kind == LedgerKind.repayment && widget.owes != null) ...[
            const SizedBox(height: Sp.sm),
            Text('عليه الآن: ${_iqd(widget.owes!)}', key: const ValueKey('emp-move-owes'), style: AppType.muted(color: AppColors.textMid)),
          ],
          const SizedBox(height: Sp.lg),
          SheetNoteField(controller: _noteCtrl, hint: 'ملاحظة (اختياريّ)', maxLength: 300, enabled: !_busy),
        ],
      ),
    );
  }
}

// ─────────────────────────── كشف الراتب ───────────────────────────

/// ورقة «كشف الراتب»: معاينةٌ طازجة من الخادم ← «صرف» بأرقامها نفسها. تُرجع نصّ النجاح أو null.
/// [canSkip]: المدير وحده يتخطّى راتباً استحقّ بلا صرف.
Future<String?> showEmployeePayslipSheet(BuildContext context, {required int employeeId, required String name, bool canSkip = false}) {
  return showAppSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => EmployeePayslipSheet(employeeId: employeeId, name: name, canSkip: canSkip),
  );
}

class EmployeePayslipSheet extends StatefulWidget {
  const EmployeePayslipSheet({super.key, required this.employeeId, required this.name, this.canSkip = false});
  final int employeeId;
  final String name;
  final bool canSkip;
  @override
  State<EmployeePayslipSheet> createState() => _EmployeePayslipSheetState();
}

class _EmployeePayslipSheetState extends State<EmployeePayslipSheet> {
  PayslipPreview? _pv;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _fromHand = false;
  final _noteCtrl = TextEditingController();

  /// مفتاح منع التكرار لهذه المعاينة: أرقامٌ جديدة ⇒ نيّةٌ جديدة، وإعادة الضغط على الأرقام نفسها ⇒ الكشف نفسه.
  String _ref = EmployeeLedgerApi.newRef('s');

  /// يُسقط ردّ معاينةٍ سبقتها أخرى (تبديلٌ سريع للفترات).
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  /// [periods] null = ما يختاره الخادم (المستحقّة كلّها).
  Future<void> _load({List<String>? periods}) async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await EmployeeLedgerApi.previewPayslip(widget.employeeId, periods: periods);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (r.data != null) {
        _pv = r.data;
        _ref = EmployeeLedgerApi.newRef('s');
      } else {
        _error = r.message ?? 'تعذّر تجهيز الكشف';
      }
    });
    if (r.data == null && _pv != null && mounted) showSheetSnack(context, _error!, isError: true);
  }

  void _toggle(PayslipPeriod p) {
    final pv = _pv;
    if (pv == null || _loading || _busy) return;
    _load(periods: [
      for (final x in pv.periods)
        if (x.key == p.key ? !x.selected : x.selected) x.key,
    ]);
  }

  Future<void> _pay() async {
    final pv = _pv;
    if (pv == null || !pv.canPay || _busy || _loading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    final r = await EmployeeLedgerApi.payPayslip(widget.employeeId, pv, fromHand: _fromHand && pv.net > 0, note: _noteCtrl.text, clientRef: _ref);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      Navigator.of(context).pop('صُرف كشف ${widget.name} — ${_iqd(pv.net)}');
      return;
    }
    showSheetSnack(context, r.message ?? 'تعذّر الصرف', isError: true);
    // تغيّرت الأرقام ⇒ معاينةٌ جديدة بالاختيار نفسه؛ تغيّرت الفترات ⇒ من جديد
    if (r.code == 'STALE') {
      _load(periods: pv.selectedKeys);
    } else if (r.code == 'PERIOD_CHANGED') {
      _load();
    }
  }

  Future<void> _skip(PayslipPeriod p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('تخطّي ${p.label}', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        content: Text('يُتخطّى هذا الراتب بلا صرف، ولن يظهر مستحقّاً بعدها.', style: AppType.body(color: AppColors.textMid)),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('تراجع')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('تخطٍّ')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await EmployeeLedgerApi.skipPeriod(widget.employeeId, p.key);
    if (!mounted) return;
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'تعذّر التخطّي', isError: true);
      return;
    }
    _load();
  }

  Widget _line(String label, String value, {bool strong = false, Color? color, Key? valueKey}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // سطران على الأكثر: تسميةٌ طويلة («عمولة العمليّات (تعذّر حسابها…)») تلتفّ ولا تزاحم المبلغ
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: strong ? AppType.bodyBold(color: AppColors.textHi) : AppType.body(color: AppColors.textMid),
              ),
            ),
            const SizedBox(width: Sp.sm),
            Text(value, key: valueKey, style: strong ? AppType.bodyBold(color: color ?? AppColors.textHi) : AppType.body(color: color ?? AppColors.textHi)),
          ],
        ),
      );

  Widget _periodRow(PayslipPeriod p) {
    final lock = _loading || _busy;
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.x6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: p.selected ? AppColors.brand : AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: ValueKey('emp-payslip-period-${p.key}'),
              borderRadius: BorderRadius.circular(R.md),
              onTap: lock ? null : () => _toggle(p),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: Sp.sm, end: Sp.md, top: Sp.sm, bottom: Sp.sm),
                child: Row(
                  children: [
                    Icon(p.selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                        size: 22, color: p.selected ? AppColors.brand : AppColors.textLow),
                    const SizedBox(width: Sp.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyBold(color: AppColors.textHi)),
                          Text(
                            p.due ? 'استحقّ ${iqDateLabel(p.dueDate)}' : 'يستحقّ ${iqDateLabel(p.dueDate)} — صرفٌ مبكّر',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.micro(color: AppColors.textMid),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Sp.sm),
                    Text(_iqd(p.amount), style: AppType.body(color: AppColors.textHi)),
                  ],
                ),
              ),
            ),
          ),
          if (widget.canSkip && p.due && !p.selected)
            TextButton(
              key: ValueKey('emp-payslip-skip-${p.key}'),
              onPressed: lock ? null : () => _skip(p),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textMid,
                minimumSize: const Size(44, 36),
                padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('تخطٍّ'),
            ),
        ],
      ),
    );
  }

  Widget _body(PayslipPreview pv) {
    return Opacity(
      opacity: _loading ? 0.55 : 1,
      child: Column(
        key: const ValueKey('emp-payslip'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pv.periods.isNotEmpty) ...[
            Text('الرواتب', style: AppType.label()),
            const SizedBox(height: Sp.x6),
            for (final p in pv.periods) _periodRow(p),
            if (pv.lapsed > 0) Text('وأقدم منها ${pv.lapsed} راتباً لم يُصرف — لا يُعرض.', style: AppType.micro(color: AppColors.textLow)),
            const SizedBox(height: Sp.md),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pv.salarySum > 0) _line('الراتب', _iqd(pv.salarySum)),
                if (pv.commissionEnabled)
                  _line(
                    pv.commissionUnavailable ? 'عمولة العمليّات (تعذّر حسابها — تدخل الكشف القادم)' : 'عمولة العمليّات (${pv.commissionOps} عمليّة كاملة)',
                    pv.commissionUnavailable ? '—' : _iqd(pv.commissionSum),
                  ),
                if (pv.bonusSum > 0) _line('مكافآت (${pv.bonusCount})', '+${_iqd(pv.bonusSum)}', color: AppColors.success),
                if (pv.deductionSum > 0) _line('خصومات (${pv.deductionCount})', '-${_iqd(pv.deductionSum)}', color: AppColors.error),
                Divider(height: Sp.md, color: AppColors.border),
                _line('المستحقّ — ينزل في المصاريف', _iqd(pv.gross < 0 ? 0 : pv.gross), strong: true, valueKey: const ValueKey('emp-payslip-gross')),
                if (pv.recover > 0) _line('استقطاع السلف والسحوبات', '-${_iqd(pv.recover)}', color: AppColors.error),
                for (final l in pv.loanTakes) _line('قسط قرض (المتبقّي ${formatIQD(l.remaining)})', '-${_iqd(l.take)}', color: AppColors.error),
                Divider(height: Sp.md, color: AppColors.border),
                _line('يستلم نقداً', _iqd(pv.net), strong: true, valueKey: const ValueKey('emp-payslip-net')),
                if (pv.owed > pv.recover)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('يبقى عليه ${_iqd(pv.owed - pv.recover)} من السلف للكشف القادم.', style: AppType.micro(color: AppColors.warning)),
                  ),
                if (pv.loansCount > 0 && pv.installmentSum == 0 && pv.salarySum == 0 && pv.commissionSum == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('قسط القرض يُستقطع مع الراتب — لا قسط في كشفٍ بلا راتب.', style: AppType.micro(color: AppColors.textLow)),
                  ),
              ],
            ),
          ),
          if (pv.canPay && pv.net > 0) ...[
            const SizedBox(height: Sp.lg),
            SheetSection(
              label: 'من أين يُدفع؟',
              child: SheetSegmented(
                key: const ValueKey('emp-payslip-source'),
                labels: const ['من الصندوق', 'من النقد الذي بيده'],
                selectedIndex: _fromHand ? 1 : 0,
                onSelect: (i) {
                  if (!_busy) setState(() => _fromHand = i == 1);
                },
              ),
            ),
          ],
          if (pv.canPay) ...[
            const SizedBox(height: Sp.lg),
            SheetNoteField(controller: _noteCtrl, hint: 'ملاحظة (اختياريّ)', maxLength: 300, enabled: !_busy),
          ],
          if (!pv.canPay && pv.problem != null) ...[
            const SizedBox(height: Sp.md),
            Container(
              padding: const EdgeInsets.all(Sp.md),
              decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.md)),
              child: Text(pv.problem!, key: const ValueKey('emp-payslip-problem'), style: AppType.body(color: AppColors.textMid)),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final pv = _pv;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.receiptText,
        title: 'كشف الراتب',
        subtitle: widget.name,
        onClose: _busy ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: pv == null
          ? null
          : SheetFooterBar(
              key: const ValueKey('emp-payslip-pay'),
              label: _busy
                  ? 'جاري الصرف...'
                  : pv.canPay
                      ? 'صرف — يستلم ${_iqd(pv.net)}'
                      : 'لا شيء يُصرف الآن',
              icon: LucideIcons.check,
              busy: _busy,
              enabled: pv.canPay && !_loading,
              onPressed: _pay,
            ),
      body: pv != null
          ? _body(pv)
          : _loading
              ? const Padding(padding: EdgeInsets.all(Sp.xl), child: Center(child: CircularProgressIndicator()))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_error ?? 'تعذّر تجهيز الكشف', style: AppType.body(color: AppColors.error)),
                    const SizedBox(height: Sp.md),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                    ),
                  ],
                ),
    );
  }
}

// ─────────────────────────── منتقي الموظف (الإضافة السريعة) ───────────────────────────

/// «على أيّ موظف؟» — قائمة موظّفي الصفحة بملخّص كلٍّ منهم. تُرجع المختار أو null.
/// [employees] null ⇒ تُجلب هنا ([loader]، افتراضاً قائمة الخادم) بدوّارةٍ ثمّ القائمة. [excludeId]: المستعمل نفسه (صاحب
/// الصلاحيّة لا يسجّل على نفسه).
Future<LedgerSummary?> showEmployeePickSheet(
  BuildContext context, {
  List<LedgerSummary>? employees,
  Future<List<LedgerSummary>?> Function()? loader,
  int? excludeId,
  String title = 'حركة موظف',
}) {
  return showAppSheet<LedgerSummary>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => EmployeePickSheet(employees: employees, loader: loader, excludeId: excludeId, title: title),
  );
}

class EmployeePickSheet extends StatefulWidget {
  const EmployeePickSheet({super.key, this.employees, this.loader, this.excludeId, this.title = 'حركة موظف'});
  final List<LedgerSummary>? employees;
  final Future<List<LedgerSummary>?> Function()? loader;
  final int? excludeId;
  final String title;
  @override
  State<EmployeePickSheet> createState() => _EmployeePickSheetState();
}

class _EmployeePickSheetState extends State<EmployeePickSheet> {
  late List<LedgerSummary>? _rows = widget.employees;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (_rows == null) _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    final rows = await (widget.loader ?? EmployeeLedgerApi.list)();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _failed = rows == null;
    });
  }

  Widget _row(LedgerSummary e) {
    final b = ledgerBalanceText(e);
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.x6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        key: ValueKey('emp-pick-${e.employeeId}'),
        borderRadius: BorderRadius.circular(R.md),
        onTap: () => Navigator.of(context).pop(e),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  e.active ? e.displayName : '${e.displayName} (معطّل)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyBold(color: e.active ? AppColors.textHi : AppColors.textLow),
                ),
              ),
              if (e.salaryDue) ...[
                const SizedBox(width: Sp.sm),
                const ToneChip(label: 'راتبٌ مستحقّ', tone: AppTone.warning, dense: true),
              ],
              if (b != null) ...[
                const SizedBox(width: Sp.sm),
                Text(b.text, style: AppType.micro(color: b.owes ? AppColors.error : AppColors.success).copyWith(fontWeight: FontWeight.w700)),
              ],
              const SizedBox(width: Sp.sm),
              Icon(Icons.arrow_back_ios_new_rounded, size: 12, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final rows = _rows?.where((e) => e.employeeId != widget.excludeId).toList();
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.users,
        title: widget.title,
        subtitle: 'اختر الموظف',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: rows == null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.lg),
              child: Center(
                child: _failed
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('تعذّر تحميل الموظفين الآن', style: AppType.body(color: AppColors.textMid)),
                          const SizedBox(height: Sp.sm),
                          OutlinedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                        ],
                      )
                    : const CircularProgressIndicator(),
              ),
            )
          : rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: Sp.lg),
                  child: Center(child: Text('لا موظفين في هذه الصفحة بعد', style: AppType.muted())),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final e in rows) _row(e)],
                ),
    );
  }
}

/// «حركة موظف» من الإضافة السريعة: «على أيّ موظف؟» ثمّ ورقة الحركة، ثمّ نصّ النجاح. [context] يبقى حيّاً بعد إغلاق الأوراق
/// (سياق الغلاف). true = سُجّلت حركة.
Future<bool> quickEmployeeMove(BuildContext context) async {
  final picked = await showEmployeePickSheet(context, excludeId: EmployeeLedgerState.gate.value?.account?.summary.employeeId);
  if (picked == null || !context.mounted) return false;
  final done = await showEmployeeMoveSheet(context, employeeId: picked.employeeId, name: picked.displayName, owes: picked.owesTotal);
  if (done == null || !context.mounted) return false;
  showSheetSnack(context, done, isError: false);
  return true;
}

// ─────────────────────────── حقول الراتب (محرّر الموظف) ───────────────────────────

/// حال حقول الراتب في محرّر الموظف (المدير وحده): تُحمَّل قيمه المحفوظة، و[save] يحفظ إن تغيّرت.
/// لم تُقرأ القيم ⇒ لا حقول ولا حفظ (لا نكتب فوق ما لم نقرأه).
class EmployeeSalaryForm {
  final amountCtrl = TextEditingController();
  bool weekly = false;
  int payDay = 1;
  String mode = 'salary';
  LedgerSalary _before = const LedgerSalary();

  /// الحقول تُعرض: الميزة مفتوحة، والمستعمل المدير، وقُرئ ضبط الموظّف (أو هو موظّفٌ جديد).
  bool shown = false;

  /// راتبه الثابت في صفحةٍ أخرى من صفحاته (ولا راتب له هنا) ⇒ سطرٌ يقول أين بدل الحقول، ولا حفظ من هنا.
  LedgerSalaryElsewhere? elsewhere;

  /// [employeeId] null = موظّفٌ جديد. يُرجع true إن صارت الحقول تُعرض.
  Future<bool> load(int? employeeId, {Future<LedgerMe?> Function()? me}) async {
    final who = await (me ?? EmployeeLedgerApi.me)();
    if (who == null || !who.isManager) return false;
    if (employeeId != null) {
      final r = await EmployeeLedgerApi.account(employeeId);
      final s = r.data?.summary.salary;
      if (s == null) return false;
      apply(s);
      elsewhere = s.configured ? null : s.elsewhere;
    }
    shown = true;
    return true;
  }

  /// يملأ الحقول من ضبطٍ محفوظ.
  void apply(LedgerSalary s) {
    _before = LedgerSalary(amount: s.amount, weekly: s.weekly, payDay: s.payDay, mode: s.mode);
    amountCtrl.text = s.amount == null || s.amount! <= 0 ? '' : AmountShorthand.format(s.amount!.round());
    weekly = s.weekly;
    payDay = _validDay(s.payDay, s.weekly);
    mode = s.mode;
  }

  static int _validDay(int d, bool weekly) => weekly ? (d >= 0 && d <= 6 ? d : 4) : (d >= 1 && d <= 28 ? d : 1);

  /// تبديل الدورة يضبط يوماً صالحاً لها (شهريّ ١–٢٨، أسبوعيّ ٠–٦).
  void setWeekly(bool w) {
    weekly = w;
    payDay = _validDay(payDay, w);
  }

  LedgerSalary read() {
    final a = ledgerAmountOf(amountCtrl);
    return LedgerSalary(amount: a > 0 ? a.toDouble() : null, weekly: weekly, payDay: payDay, mode: mode);
  }

  /// يحفظ إن تغيّر — null نجاح/لا تغيير، وإلّا رسالة الخادم.
  Future<String?> save(int? employeeId) async {
    if (!shown || employeeId == null || elsewhere != null) return null;
    final want = read();
    if (want.sameAs(_before)) return null;
    // بلا راتب وبلا عمولة ولم يكن له ضبطٌ ⇒ لا نداء
    if (want.amount == null && want.mode == 'salary' && _before.amount == null && _before.mode == 'salary') return null;
    final r = await EmployeeLedgerApi.setSalary(employeeId, want);
    if (r.ok) {
      _before = want;
      return null;
    }
    return r.message ?? 'تعذّر حفظ الراتب';
  }

  void dispose() => amountCtrl.dispose();
}

/// حقول «راتب الموظف» — تُرسم حين [EmployeeSalaryForm.shown] وحده.
class EmployeeSalaryFields extends StatelessWidget {
  const EmployeeSalaryFields({super.key, required this.form, required this.onChanged});
  final EmployeeSalaryForm form;

  /// بعد كلّ تغيير (المضيف يعيد البناء ويمسح خطأه).
  final VoidCallback onChanged;

  static const _modes = ['salary', 'commission', 'both'];

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: Sp.x6),
        child: Text(t, style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (!form.shown) return const SizedBox.shrink();
    final there = form.elsewhere;
    if (there != null) {
      // راتبه الثابت في صفحةٍ أخرى من صفحاته: أين وكم — بلا حقول (الخادم يرفض راتباً ثانياً)
      return Container(
        key: const ValueKey('emp-salary-elsewhere'),
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.icon),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${there.salary.describe(formatIQD) ?? ''} — ${there.where}',
              style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Sp.x6),
            Text(
              'للموظف راتبٌ واحد لكلّ صفحاته — يُعدَّل ويُصرف من تلك الصفحة.',
              style: AppType.micro(color: AppColors.textMid),
            ),
          ],
        ),
      );
    }
    final days = form.weekly ? [for (var i = 0; i < 7; i++) i] : [for (var i = 1; i <= 28; i++) i];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(form.weekly ? 'الراتب الأسبوعيّ' : 'الراتب الشهريّ'),
        AmountTextField(
          key: const ValueKey('emp-salary-amount'),
          controller: form.amountCtrl,
          compact: true,
          hint: 'بلا راتب',
          onValue: (_) => onChanged(),
        ),
        const SizedBox(height: Sp.md),
        _label('يوم الصرف'),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: SheetSegmented(
                key: const ValueKey('emp-salary-cycle'),
                labels: const ['شهريّ', 'أسبوعيّ'],
                selectedIndex: form.weekly ? 1 : 0,
                onSelect: (i) {
                  form.setWeekly(i == 1);
                  onChanged();
                },
              ),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              flex: 2,
              child: Container(
                height: H.segment,
                padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(R.icon),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    key: const ValueKey('emp-salary-day'),
                    value: form.payDay,
                    isExpanded: true,
                    icon: Icon(LucideIcons.chevronDown, size: 16, color: AppColors.textMid),
                    dropdownColor: AppColors.surface,
                    items: [
                      for (final d in days)
                        DropdownMenuItem<int>(
                          value: d,
                          child: Text(
                            form.weekly ? LedgerSalary.dow[d] : 'يوم $d',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.input(color: AppColors.textHi),
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      form.payDay = v;
                      onChanged();
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Sp.md),
        _label('طريقة الأجر'),
        SheetSegmented(
          key: const ValueKey('emp-salary-mode'),
          labels: const ['راتب', 'عمولة', 'الاثنان'],
          selectedIndex: _modes.indexOf(form.mode).clamp(0, 2),
          onSelect: (i) {
            form.mode = _modes[i];
            onChanged();
          },
        ),
        const SizedBox(height: Sp.sm),
        Text(
          'يوم الصرف يجهز «كشف الراتب» في حساب الموظف: الراتب + المكافآت − السلف − قسط القرض − الخصومات، وتضغط «صرف» فينزل في المصاريف. '
          'العمولة = «ربح الموظف لكلّ عمليّة» عن عمليّاته الكاملة منذ آخر كشف. لا يُصرف شيء تلقائيّاً. فارغ = بلا راتب.',
          style: AppType.micro(color: AppColors.textLow),
        ),
      ],
    );
  }
}
