import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/op_voids_api.dart';
import '../../../core/util/ar_date.dart';
import '../../../core/util/bidi.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../services/subscriber_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// «إلغاء إضافة دين/رصيد» (١٧ نوفمبر ٢٠٢٦ — المالك: «اضافة رصيد او دين بالخطا… لازم نخلي صلاحيه المدير يكدر يسوي هلشي») —
/// نافذة التأكيد.
///
/// الحركة الخاطئة تُلغى: يرجع رصيد المشترك كما كان قبلها، ويصحّ الصندوق (رصيدٌ نقداً — من حساب من استلمه) أو الصافي (تعويض) أو
/// «الديون الجديدة» (دين). ونتيجةٌ لم يؤكّدها الساس تُحسم هنا بعد أن يتحقّق المدير من رصيد المشترك.
///
/// القواعد كلّها بالخادم (`server/opVoids.js`): هذه تعرض ما يقوله وترسل ما رآه المدير في قائمته — [kind] و[amount] و[subscriber]
/// — ليطابقه الخادم بسطر الحركة [opId] قبل أيّ شيء. [currentBalance]: رصيد المشترك كما يعرضه السجلّ (موقَّع: سالبٌ = دين) —
/// للمعاينة «الآن ⇒ بعد الإلغاء»؛ null ⇒ الأثر وحده.
///
/// تُرجع `true` حين تغيّر شيء لتُحدَّث القائمة التي فُتحت منها.
Future<bool?> showOpVoidSheet(
  BuildContext context, {
  required int opId,
  required OpKind kind,
  String? creditKind,
  required num amount,
  required String subscriber,
  num? currentBalance,
}) {
  return showAppSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _OpVoidSheet(
      opId: opId,
      kind: kind,
      creditKind: creditKind,
      amount: amount,
      subscriber: subscriber,
      currentBalance: currentBalance,
    ),
  );
}

String _iqd(num n) => '${formatIQD(n)} د.ع';

/// رصيدٌ موقَّع كما يُقرأ: «عليه 20,000 د.ع» · «له 5,000 د.ع» · «لا دين» (formatIQD يُسقط الإشارة — فالكلمة تحملها).
String opBalanceText(num n) {
  if (n.abs() < 0.5) return 'لا دين';
  return n < 0 ? 'عليه ${_iqd(-n)}' : 'له ${_iqd(n)}';
}

String _when(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${iqDateOf(l)} · ${two(l.hour)}:${two(l.minute)}';
}

class _OpVoidSheet extends StatefulWidget {
  const _OpVoidSheet({
    required this.opId,
    required this.kind,
    required this.creditKind,
    required this.amount,
    required this.subscriber,
    required this.currentBalance,
  });
  final int opId;
  final OpKind kind;
  final String? creditKind;
  final num amount;
  final String subscriber;
  final num? currentBalance;

  @override
  State<_OpVoidSheet> createState() => _OpVoidSheetState();
}

class _OpVoidSheetState extends State<_OpVoidSheet> {
  OpVoidPreview? _p;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  int? _unknownId;
  bool _dirty = false;
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await OpVoidsApi.preview(widget.opId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _p = r.data;
      _error = r.data == null ? (r.message ?? 'تعذّرت قراءة الحركة') : null;
    });
  }

  int? get _resolveId {
    if (_unknownId != null) return _unknownId;
    final v = _p?.existing;
    return v != null && v.isUnknown ? v.voidId : null;
  }

  OpKind get _kind => _p?.kind ?? widget.kind;
  String? get _ck => _p?.creditKind ?? widget.creditKind;
  num get _amount => _p?.amount ?? widget.amount;
  num get _delta => _p?.balanceDelta ?? (_kind == OpKind.addDebt ? _amount : -_amount);
  String get _title => 'إلغاء ${opName(_kind, _ck)}';

  String get _who {
    final p = _p;
    if (p == null || p.originEmployeeId == null) return 'المدير';
    return p.originUsername ?? 'الموظّف';
  }

  bool get _showForm => !_loading && _error == null && _resolveId == null && (_p?.canVoid ?? false);

  void _close() => Navigator.of(context).pop(_dirty ? true : null);

  Future<void> _confirm() async {
    if (_p == null || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final r = await OpVoidsApi.run(
      opId: widget.opId,
      expectKind: widget.kind,
      expectAmount: widget.amount,
      expectSubscriber: widget.subscriber,
      reason: _reason.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      SubscriberEvents.notifyChange();
      final nb = r.newBalance;
      showSheetSnack(
        context,
        r.duplicate
            ? 'هذه الحركة ملغاة سابقاً'
            : 'أُلغيت ${opName(_kind, _ck)} ${_iqd(_amount)}${nb != null ? ' — رصيد المشترك الآن: ${opBalanceText(nb)}' : ''}',
      );
      Navigator.of(context).pop(true);
      return;
    }
    if (r.code == 'OUTCOME_UNKNOWN' && r.voidId != null) {
      setState(() {
        _unknownId = r.voidId;
        _dirty = true;
      });
      return;
    }
    showSheetSnack(context, r.message ?? 'تعذّر الإلغاء', isError: true);
    if (r.code == 'OP_MISMATCH' || r.code == 'IN_PROGRESS' || r.code == 'NETWORK') {
      _dirty = true;
      await _load();
    }
  }

  Future<void> _resolve(bool applied) async {
    final id = _resolveId;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    final r = await OpVoidsApi.resolve(id, applied: applied);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'تعذّر الحسم', isError: true);
      return;
    }
    if (applied || r.corrected) SubscriberEvents.notifyChange();
    showSheetSnack(
      context,
      r.corrected
          ? 'الرصيد كان قد تعدّل فعلاً — سُجّل الإلغاء'
          : applied
              ? 'سُجّل الإلغاء'
              : 'أُسقط الإلغاء — الحركة كما كانت',
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.undo2,
        title: _title,
        subtitle: isoJoin([widget.subscriber, _iqd(widget.amount)], ' — '),
        tint: AppColors.error,
        tintBg: AppColors.dangerSoftBg,
        onClose: _close,
      ),
      footer: _showForm
          ? SheetFooterBar(
              label: _busy ? 'جارٍ الإلغاء...' : 'تأكيد الإلغاء',
              icon: LucideIcons.undo2,
              color: AppColors.errorFill,
              enabled: true,
              busy: _busy,
              onPressed: _confirm,
              leading: SheetSecondaryButton(label: 'تراجع', onTap: _busy ? () {} : _close),
            )
          : null,
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Sp.huge),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final p = _p;
    if (p == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _note(_error ?? 'تعذّرت قراءة الحركة', AppTone.danger, LucideIcons.circleAlert),
          const SizedBox(height: Sp.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(LucideIcons.refreshCw, size: 14),
              label: const Text('إعادة المحاولة'),
            ),
          ),
        ],
      );
    }
    if (_resolveId != null) return _resolveBody();
    if (!p.canVoid) {
      return _note(p.blockedMessage ?? 'هذه الحركة لا تُلغى من هنا', AppTone.neutral, LucideIcons.info);
    }
    final cash = _kind == OpKind.addCredit && _ck == 'cash';
    final now = widget.currentBalance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetRowsGroup(rows: [
          SheetRowData(label: 'الحركة', value: opName(_kind, _ck)),
          SheetRowData(label: 'المبلغ', value: _iqd(_amount), strong: true),
          SheetRowData(label: cash ? 'استلمه' : 'سجّلها', value: _who),
          SheetRowData(label: 'التاريخ', value: iso(_when(p.at))),
        ]),
        if (now != null) ...[
          const SizedBox(height: Sp.md),
          _BalanceLine(now: now, after: now + _delta),
        ],
        const SizedBox(height: Sp.lg),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.lg)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_kind == OpKind.addDebt) ...[
                Text('ينقص دين المشترك ${_iqd(_amount)} (إذا كان سدّده يصير له رصيد).', style: _explain),
                const SizedBox(height: Sp.x6),
                Text('«الديون الجديدة» في التقرير تنقص ${_iqd(_amount)}.', style: _explain),
              ] else ...[
                Text('ينقص رصيد المشترك ${_iqd(_amount)} (إذا كان صرفه يرجع ديناً عليه).', style: _explain),
                if (cash) ...[
                  const SizedBox(height: Sp.x6),
                  Text('ينقص المبلغ من الصندوق — من حساب ${iso(_who)}.', style: _explain),
                ],
                if (_ck == 'comp') ...[
                  const SizedBox(height: Sp.x6),
                  Text('صافي الربح يرجع كما كان (التعويض يخرج منه).', style: _explain),
                ],
              ],
            ],
          ),
        ),
        if (p.settlementNumber != null) ...[
          const SizedBox(height: Sp.sm),
          Text(
            'هذه الحركة ضمن تسوية #${p.settlementNumber} — الإلغاء يُحسب في الحساب الحاليّ، والتسوية تبقى كما هي.',
            style: AppType.muted().copyWith(height: 1.55),
          ),
        ],
        const SizedBox(height: Sp.lg),
        SheetNoteField(controller: _reason, hint: 'السبب (اختياريّ)', maxLength: 200, enabled: !_busy),
      ],
    );
  }

  TextStyle get _explain => AppType.rowValue(color: AppColors.textBody).copyWith(height: 1.55, fontWeight: FontWeight.w500);

  Widget _resolveBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _note(
          'الساس لم يؤكّد تعديل رصيد المشترك. افتح المشترك وانظر إلى رصيده: إذا تغيّر ${_iqd(_amount)} '
          '${_kind == OpKind.addDebt ? '(نقص دينه)' : '(نقص رصيده)'} فالرصيد تعدّل، وإذا بقي كما هو فما تعدّل.',
          AppTone.warning,
          LucideIcons.triangleAlert,
        ),
        const SizedBox(height: Sp.lg),
        _WideButton(label: 'تعدّل الرصيد — سجّل الإلغاء', filled: true, busy: _busy, onTap: () => _resolve(true)),
        const SizedBox(height: Sp.sm),
        _WideButton(label: 'ما تعدّل — الحركة كما كانت', filled: false, busy: _busy, onTap: () => _resolve(false)),
      ],
    );
  }

  Widget _note(String text, AppTone tone, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: tone.softBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: tone.onSoft)),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(text, style: AppType.rowValue(color: tone.onSoft).copyWith(height: 1.6, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

/// «رصيد المشترك: الآن ← بعد الإلغاء» — «بعد» ملوّنٌ بإشارته (دينٌ أحمر، رصيدٌ أخضر). يلتفّ ولا يُقصّ على أضيق هاتف.
class _BalanceLine extends StatelessWidget {
  const _BalanceLine({required this.now, required this.after});
  final num now;
  final num after;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final afterColor = after < -0.5 ? AppColors.error : (after > 0.5 ? AppColors.success : AppColors.textMid);
    return Container(
      key: const ValueKey('op-void-balance'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: [
          Text('رصيد المشترك:', style: AppType.muted()),
          Text(opBalanceText(now), style: AppType.rowValue(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
          Icon(LucideIcons.arrowLeft, size: 14, color: AppColors.textLow),
          Text(opBalanceText(after), style: AppType.rowValue(color: afterColor).copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// زرّ عريض بارتفاع أزرار الشيت — المملوء للحسم «تعدّل الرصيد»، والمحدَّد لـ«ما تعدّل».
class _WideButton extends StatelessWidget {
  const _WideButton({required this.label, required this.filled, required this.busy, required this.onTap});
  final String label;
  final bool filled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = busy ? AppColors.textHint : (filled ? AppColors.onBrand : AppColors.textBody);
    return SizedBox(
      height: H.button,
      child: Material(
        color: busy ? AppColors.surfaceDisabled : (filled ? AppColors.errorFill : AppColors.surface),
        borderRadius: BorderRadius.circular(R.button),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(R.button),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.button),
              border: filled || busy ? null : Border.all(color: AppColors.borderSoft),
            ),
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
            child: Center(
              child: Text(label, style: AppType.button(color: fg), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      ),
    );
  }
}
