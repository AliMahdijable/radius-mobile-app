import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/payment_voids_api.dart';
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

/// «إلغاء تسديد» (١١ نوفمبر ٢٠٢٦ — المالك: «مهمّة لأنّ هسه سبّبت لي مشاكل») — نافذة التأكيد.
///
/// تسديدٌ سُجّل خطأً يُلغى: يرجع دين المشترك وينقص المبلغ من الصندوق، من حساب من استلمه. ولصاحب الصفحة خيارٌ ثانٍ حين وُجدت
/// «إضافة دين» يدويّة بالمبلغ نفسه بعد التسديد: هي الإرجاع — فلا يتغيّر دين المشترك ويُصحَّح الصندوق وحده. ونتيجةٌ لم يؤكّدها
/// الساس تُحسم هنا بعد أن يتحقّق المدير من دين المشترك.
///
/// القواعد كلّها بالخادم (`server/paymentVoids.js`): هذه تعرض ما يقوله وترسل ما رآه المدير في قائمته — [amount] و[subscriber]
/// (يوزر المشترك) — ليطابقه الخادم بسطر التسديد [paymentId] قبل أيّ شيء. لا مبلغ يُكتب هنا.
///
/// تُرجع `true` حين تغيّر شيء (أُلغي التسديد، أو حُسم إلغاءٌ معلّق، أو صار «بانتظار حسم») لتُحدَّث القائمة التي فُتحت منها.
Future<bool?> showPaymentVoidSheet(
  BuildContext context, {
  required int paymentId,
  required num amount,
  required String subscriber,
}) {
  return showAppSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _PaymentVoidSheet(paymentId: paymentId, amount: amount, subscriber: subscriber),
  );
}

String _iqd(num n) => '${formatIQD(n)} د.ع';

String _when(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${iqDateOf(l)} · ${two(l.hour)}:${two(l.minute)}';
}

class _PaymentVoidSheet extends StatefulWidget {
  const _PaymentVoidSheet({required this.paymentId, required this.amount, required this.subscriber});
  final int paymentId;
  final num amount;
  final String subscriber;

  @override
  State<_PaymentVoidSheet> createState() => _PaymentVoidSheetState();
}

class _PaymentVoidSheetState extends State<_PaymentVoidSheet> {
  /// اختيار «إرجاع الدين الآن» — أرقام إضافات الدين (للربط) كلّها موجبة.
  static const _restore = 0;

  PaymentVoidPreview? _p;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  /// null = لم يختر بعد · [_restore] · أو رقم إضافة الدين المختارة للربط.
  int? _choice;

  /// إلغاءٌ لم تتأكّد نتيجته في هذه الجلسة (من ردّ الإلغاء) — رقم قيده.
  int? _unknownId;

  /// تغيّر شيءٌ في الخادم ولو لم يكتمل (صار «بانتظار حسم») — القائمة تُحدَّث عند الإغلاق.
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
    final r = await PaymentVoidsApi.preview(widget.paymentId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _p = r.data;
      _error = r.data == null ? (r.message ?? 'تعذّرت قراءة التسديد') : null;
      // معاينةٌ جديدة: اختيارٌ على مرشّحٍ لم يعد معروضاً لا يبقى
      final c = _choice;
      if (c != null && c != _restore && !(r.data?.candidates.any((x) => x.id == c) ?? false)) _choice = null;
    });
  }

  /// قيدٌ بانتظار حسم: من ردّ الإلغاء الآن، أو قائمٌ من قبل (المعاينة).
  int? get _resolveId {
    if (_unknownId != null) return _unknownId;
    final v = _p?.existing;
    return v != null && v.isUnknown ? v.voidId : null;
  }

  bool get _canLink {
    final p = _p;
    return p != null && p.canLink && p.candidates.isNotEmpty;
  }

  /// بلا مرشّحٍ للربط لا اختيار: الإلغاء إرجاع الدين.
  int? get _effective => _canLink ? _choice : _restore;

  num get _amount => _p?.amount ?? widget.amount;

  String get _who {
    final p = _p;
    if (p == null || p.collectorEmployeeId == null) return 'المدير';
    return p.collectorUsername ?? 'الموظّف';
  }

  bool get _showForm => !_loading && _error == null && _resolveId == null && (_p?.canVoid ?? false);

  void _close() => Navigator.of(context).pop(_dirty ? true : null);

  Future<void> _confirm() async {
    final choice = _effective;
    if (_p == null || choice == null || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final r = await PaymentVoidsApi.run(
      paymentId: widget.paymentId,
      expectAmount: widget.amount,
      expectSubscriber: widget.subscriber,
      linkAddId: choice == _restore ? null : choice,
      reason: _reason.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      // رجع الدين على المشترك ⇒ قوائمه وصفحته تُحدَّث
      SubscriberEvents.notifyChange();
      showSheetSnack(
        context,
        r.duplicate
            ? 'هذا التسديد ملغى سابقاً'
            : choice == _restore
                ? 'أُلغي التسديد — رجع الدين ${_iqd(_amount)} ونقص من الصندوق'
                : 'أُلغي التسديد — نقص ${_iqd(_amount)} من الصندوق (دين المشترك كما هو)',
      );
      Navigator.of(context).pop(true);
      return;
    }
    if (r.code == 'OUTCOME_UNKNOWN' && r.voidId != null) {
      // لا «فشل» ولا «نجح»: الساس لم يؤكّد — يُحسم بعد أن يتحقّق المدير
      setState(() {
        _unknownId = r.voidId;
        _dirty = true;
      });
      return;
    }
    showSheetSnack(context, r.message ?? 'تعذّر إلغاء التسديد', isError: true);
    // ما تغيّر تحتنا (سطرٌ لا يطابق، عمليّةٌ جارية) أو طلبٌ لا نعرف مصيره ⇒ الحال من الخادم قبل أيّ إعادة
    if (r.code == 'PAYMENT_MISMATCH' || r.code == 'IN_PROGRESS' || r.code == 'NETWORK') {
      _dirty = true;
      await _load();
    }
  }

  Future<void> _resolve(bool applied) async {
    final id = _resolveId;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    final r = await PaymentVoidsApi.resolve(id, applied: applied);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'تعذّر الحسم', isError: true);
      return;
    }
    // «ما رجع» وحركة الإرجاع مكتوبةٌ في الدفتر: الخادم يُكمل الإلغاء ويقول «صُحّح» — لا نقول «التسديد كما كان».
    final voided = applied || r.corrected;
    if (voided) SubscriberEvents.notifyChange();
    showSheetSnack(
      context,
      r.corrected
          ? 'الدين كان قد رجع فعلاً — سُجّل الإلغاء ونقص المبلغ من الصندوق'
          : applied
              ? 'سُجّل الإلغاء — نقص المبلغ من الصندوق'
              : 'أُسقط الإلغاء — التسديد كما كان',
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.undo2,
        title: 'إلغاء تسديد',
        subtitle: isoJoin([widget.subscriber, _iqd(widget.amount)], ' — '),
        tint: AppColors.error,
        tintBg: AppColors.dangerSoftBg,
        onClose: _close,
      ),
      footer: _showForm
          ? SheetFooterBar(
              label: _busy ? 'جاري الإلغاء...' : 'تأكيد الإلغاء',
              icon: LucideIcons.undo2,
              color: AppColors.errorFill,
              enabled: _effective != null,
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
          _note(_error ?? 'تعذّرت قراءة التسديد', AppTone.danger, LucideIcons.circleAlert),
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
      return _note(p.blockedMessage ?? 'هذا التسديد لا يُلغى من هنا', AppTone.neutral, LucideIcons.info);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetRowsGroup(rows: [
          SheetRowData(label: 'المبلغ', value: _iqd(_amount), strong: true),
          SheetRowData(label: 'استلمه', value: _who),
          // قيم الصفوف تُرسم LTR (للأرقام واليوزرات): التاريخ العربيّ يُعزل فلا ينقلب ترتيبه («1 21:45 · تشرين الثاني»)
          SheetRowData(label: 'التاريخ', value: iso(_when(p.at))),
        ]),
        const SizedBox(height: Sp.lg),
        if (_canLink)
          SheetSection(
            label: 'ماذا صار بدين المشترك بعد هذا التسديد؟',
            gap: 9,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ChoiceCard(
                  selected: _choice == _restore,
                  enabled: !_busy,
                  icon: LucideIcons.undo2,
                  title: 'الدين بعده ما رجع',
                  text: 'يرجع الدين ${_iqd(_amount)} على المشترك الآن، وينقص من الصندوق.',
                  onTap: () => setState(() => _choice = _restore),
                ),
                for (final c in p.candidates) ...[
                  const SizedBox(height: Sp.sm),
                  _ChoiceCard(
                    selected: _choice == c.id,
                    enabled: !_busy,
                    icon: LucideIcons.link2,
                    title: 'رجّعناه يدويّاً بإضافة دين',
                    text: '${isoJoin([
                          'إضافة دين ${_iqd(c.amount)} بتاريخ ${_when(c.at)}',
                          if ((c.by ?? '').isNotEmpty) c.by!,
                          if ((c.comment ?? '').isNotEmpty) c.comment!,
                        ], ' — ')}. دين المشترك يبقى كما هو، وينقص المبلغ من الصندوق.',
                    onTap: () => setState(() => _choice = c.id),
                  ),
                ],
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(R.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('يرجع الدين ${_iqd(_amount)} على المشترك.', style: _explain),
                const SizedBox(height: Sp.x6),
                Text('ينقص المبلغ من الصندوق — من حساب ${iso(_who)}.', style: _explain),
              ],
            ),
          ),
        if (p.settlementNumber != null) ...[
          const SizedBox(height: Sp.sm),
          Text(
            'هذا التسديد ضمن تسوية #${p.settlementNumber} — الإلغاء يُحسب في الحساب الحاليّ، والتسوية تبقى كما هي.',
            style: AppType.muted().copyWith(height: 1.55),
          ),
        ],
        const SizedBox(height: Sp.lg),
        SheetNoteField(
          controller: _reason,
          hint: 'السبب (اختياريّ)',
          maxLength: 200,
          enabled: !_busy,
        ),
      ],
    );
  }

  TextStyle get _explain => AppType.rowValue(color: AppColors.textBody).copyWith(height: 1.55, fontWeight: FontWeight.w500);

  /// إلغاءٌ لم يؤكّد الساس نتيجته: المدير يتحقّق من دين المشترك ثمّ يحسم — لا إعادة قبل الحسم.
  Widget _resolveBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _note(
          'الساس لم يؤكّد إرجاع الدين. افتح المشترك وشوف دينه: إذا زاد ${_iqd(_amount)} فالدين رجع، وإذا بقي كما هو فما رجع.',
          AppTone.warning,
          LucideIcons.triangleAlert,
        ),
        const SizedBox(height: Sp.lg),
        _WideButton(
          label: 'الدين رجع — سجّل الإلغاء',
          filled: true,
          busy: _busy,
          onTap: () => _resolve(true),
        ),
        const SizedBox(height: Sp.sm),
        _WideButton(
          label: 'ما رجع — التسديد كما كان',
          filled: false,
          busy: _busy,
          onTap: () => _resolve(false),
        ),
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
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: tone.onSoft),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              text,
              style: AppType.rowValue(color: tone.onSoft).copyWith(height: 1.6, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة اختيارٍ (راديو): المختارة بحدّ البراند وخلفيّته الخفيفة.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.enabled,
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
  });
  final bool selected;
  final bool enabled;
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.brandSoftBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(R.lg),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(
                color: selected ? AppColors.brand : AppColors.border,
                width: selected ? BW.selected : BW.normal,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.brand : AppColors.surfaceSunken,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 14, color: selected ? AppColors.onBrand : AppColors.textMid),
                ),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppType.rowValue(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: Sp.xxs),
                      Text(text, style: AppType.body(color: AppColors.textMid).copyWith(height: 1.55)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// زرّ عريض بارتفاع أزرار الشيت — المملوء للحسم «رجع الدين»، والمحدَّد لـ«ما رجع».
class _WideButton extends StatelessWidget {
  const _WideButton({required this.label, required this.filled, required this.busy, required this.onTap});
  final String label;
  final bool filled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = busy
        ? AppColors.textHint
        : filled
            ? AppColors.onBrand
            : AppColors.textBody;
    return SizedBox(
      height: H.button,
      child: Material(
        color: busy
            ? AppColors.surfaceDisabled
            : filled
                ? AppColors.errorFill
                : AppColors.surface,
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
              child: Text(
                label,
                style: AppType.button(color: fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
