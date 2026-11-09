import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/broadcast_api.dart' as bc;
import '../../../api/telegram_api.dart';
import '../../../core/util/amount_input.dart';
import '../../../widgets/debt_filter_panel.dart';
import '../../../widgets/list_kit.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/app_sheet.dart';

/// telegramBroadcastSheet — إرسال رسالة عبر تلغرام لكل المرتبطين.
/// Dry-run (يعرض عدد المستقبلين) ثم Send.
/// ٩ نوفمبر (المالك «نعم» لتلغرام): «تحديد المدينين» نفسه حين يعلنه الخادم (telegram) — المربوطون المدينون بعمر أقدم دينٍ لم يُسدَّد
/// و/أو مبلغه، بمعاينةٍ من الخادم بالأسماء، والإرسال يحمل بصمتها (تغيّرت القائمة ⇒ 409 بلا إرسال، فتُعاد المعاينة).
Future<void> showTelegramBroadcastSheet(
  BuildContext context, {
  required String adminId,
}) {
  return showAppSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _BroadcastSheet(adminId: adminId),
  );
}

class _BroadcastSheet extends StatefulWidget {
  const _BroadcastSheet({required this.adminId});
  final String adminId;

  @override
  State<_BroadcastSheet> createState() => _BroadcastSheetState();
}

class _BroadcastSheetState extends State<_BroadcastSheet> {
  final _msgCtrl = TextEditingController();
  BroadcastPreview? _preview;
  bool _checking = false;
  bool _sending = false;

  // «تحديد المدينين» — الخادم وحده يحسب من يطابق؛ هنا الشرائح والمعاينة
  bc.DebtFilterCapability? _cap;
  bc.DebtFilter _df = bc.DebtFilter.none;
  bc.BroadcastPreview? _dfPreview;
  String? _dfError;
  bool _dfBusy = false;
  int _dfSeq = 0;
  Timer? _dfDebounce;

  bool get _filterOn => _cap?.telegram == true && _df.active;

  @override
  void initState() {
    super.initState();
    _loadCap();
  }

  Future<void> _loadCap() async {
    final c = await bc.BroadcastApi.debtFilterCapability();
    if (!mounted) return;
    setState(() => _cap = c);
  }

  @override
  void dispose() {
    _dfDebounce?.cancel();
    _msgCtrl.dispose();
    super.dispose();
  }

  void _setFilter(bc.DebtFilter f) {
    setState(() {
      _df = f;
      _dfPreview = null;
      _dfError = null;
    });
    _dfDebounce?.cancel();
    final seq = ++_dfSeq;
    if (!_filterOn || _df.problem() != null) {
      setState(() => _dfBusy = false);
      return;
    }
    setState(() => _dfBusy = true);
    _dfDebounce = Timer(const Duration(milliseconds: 600), () => _runFilterPreview(seq));
  }

  Future<void> _runFilterPreview(int seq) async {
    final r = await bc.BroadcastApi.telegramPreview(adminId: widget.adminId, debtFilter: _df);
    if (!mounted || seq != _dfSeq) return;
    setState(() {
      _dfBusy = false;
      _dfPreview = r.preview;
      _dfError = r.preview == null ? (r.message ?? 'تعذّرت المعاينة') : null;
    });
  }

  /// الإرسال بالتحديد: معاينةٌ للطلب نفسه بالنصّ ⇒ ورقة تأكيدٍ بالأسماء ⇒ الإرسال ببصمتها.
  Future<void> _sendFiltered() async {
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty) {
      _snack('أدخل الرسالة أوّلاً', error: true);
      return;
    }
    setState(() => _checking = true);
    final pv = await bc.BroadcastApi.telegramPreview(adminId: widget.adminId, debtFilter: _df, message: msg);
    if (!mounted) return;
    setState(() => _checking = false);
    final preview = pv.preview;
    if (preview == null) {
      _snack(pv.message ?? 'تعذّرت المعاينة — لم يُرسَل شيء', error: true);
      return;
    }
    if (preview.count == 0) {
      _snack('لا أحد من المربوطين المدينين يطابق التحديد الآن', error: true);
      return;
    }
    final ok = await showAppSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TgFilteredConfirm(preview: preview, summary: _df.describe(), message: msg),
    );
    if (ok != true || !mounted) return;
    setState(() => _sending = true);
    final r = await bc.BroadcastApi.telegramSend(
      adminId: widget.adminId,
      message: msg,
      debtFilter: _df,
      audienceKey: preview.audienceKey,
      audienceCount: preview.count,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (r.ok) {
      _snack(r.message ?? 'أُدرج ${r.enqueued} رسالة للطابور');
      Navigator.of(context).pop();
    } else {
      _snack(r.message ?? 'فشل الإرسال', error: true);
      if (r.code == 'BROADCAST_AUDIENCE_CHANGED') _setFilter(_df);
    }
  }

  Future<void> _check() async {
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty) {
      _snack('أدخل الرسالة أوّلاً', error: true);
      return;
    }
    setState(() => _checking = true);
    final p = await TelegramApi.previewBroadcast(widget.adminId, msg);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _preview = p;
    });
    if (p == null) {
      _snack('تعذّر جلب المعاينة — تحقّق من الاتصال', error: true);
    }
  }

  Future<void> _send() async {
    if (_filterOn) return _sendFiltered();
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty || _preview == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('تأكيد الإرسال',
            style: TextStyle(fontFamily: AppType.family, fontWeight: FontWeight.w700)),
        content: Text(
            'سيتمّ إرسال الرسالة لـ${_preview!.eligible} مشترك مربوط. متأكّد؟',
            style: const TextStyle(fontFamily: AppType.family, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: AppType.family)),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.brandAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('أرسل',
                style: TextStyle(
                    fontFamily: AppType.family, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _sending = true);
    final res = await TelegramApi.sendBroadcast(widget.adminId, msg);
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.ok) {
      _snack('أُدرج ${res.enqueued} رسالة للطابور');
      Navigator.of(context).pop();
    } else {
      _snack(res.message ?? 'فشل الإرسال', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: AppType.family)),
      backgroundColor: error ? AppColors.error : AppColors.brand,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.send,
        title: 'إرسال عام عبر تلغرام',
        subtitle: 'رسالة لكل المشتركين المربوطين بالبوت',
        tint: AppColors.channelTelegram,
        tintBg: AppColors.channelTelegramSoftBg,
        onClose: () => Navigator.of(context).pop(),
      ),
      scrollable: _cap?.telegram == true,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          const SizedBox(height: 16),
          // Textarea
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: TextField(
              controller: _msgCtrl,
              onChanged: (_) {
                if (_preview != null) setState(() => _preview = null);
              },
              maxLines: 5,
              minLines: 4,
              maxLength: 2000,
              style: TextStyle(
                fontFamily: AppType.family,
                fontSize: 13,
                color: AppColors.textHi,
                height: 1.5,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: 'اكتب الرسالة هنا...',
                hintStyle: AppType.body(color: AppColors.textLow),
                counterStyle: TextStyle(
                  fontFamily: AppType.family,
                  fontSize: 10.5, height: 1.3,
                  color: AppColors.textLow,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_cap?.telegram == true) ...[
            DebtFilterPanel(
              cap: _cap!,
              value: _df,
              onChanged: _setFilter,
              busy: _dfBusy,
              error: _dfError,
              preview: _dfPreview,
              onRetry: () => _setFilter(_df),
              noun: 'مربوطاً مديناً',
            ),
            const SizedBox(height: 12),
          ],
          if (_preview != null && !_filterOn) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.successSoftBg,
                borderRadius: BorderRadius.circular(R.sm),
                border:
                    Border.all(color: AppColors.successSoftBorder, width: 0.5),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.circleCheck,
                      size: 16, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _preview!.outOfScope > 0
                          ? '🎯 سيصل: ${_preview!.eligible} · مرتبطون: ${_preview!.totalBound} · محظورون: ${_preview!.blocked} · خارج النطاق: ${_preview!.outOfScope}'
                          : '🎯 سيصل: ${_preview!.eligible} مشترك · مرتبطون: ${_preview!.totalBound} · محظورون: ${_preview!.blocked}',
                      style: AppType.bodyBold(),
                    ),
                  ),
                ],
              ),
            ),
            if (_preview!.eligible == 0) ...[
              const SizedBox(height: 8),
              Text(
                'لا يوجد مشتركون مربوطون — استعمل «ربط مشترك» أوّلاً',
                style: TextStyle(
                  fontFamily: AppType.family,
                  fontSize: 11.5,
                  color: AppColors.textMid,
                  height: 1.4,
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (!_filterOn) Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _checking ? null : _check,
                    icon: _checking
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.5))
                        : const Icon(LucideIcons.search, size: 16),
                    label: const Text('فحص مسبق',
                        style: TextStyle(
                          fontFamily: AppType.family,
                          fontSize: 13, height: 1.35,
                          fontWeight: FontWeight.w700,
                        )),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textHi,
                      side: BorderSide(color: AppColors.border, width: 1),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(R.md)),
                    ),
                  ),
                ),
              ),
              if (!_filterOn) const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    key: const ValueKey('tg-broadcast-send'),
                    onPressed: _sending || _checking
                        ? null
                        : _filterOn
                            ? ((_dfPreview?.count ?? 0) > 0 && _df.problem() == null ? _send : null)
                            : (_preview == null || _preview!.eligible == 0)
                                ? null
                                : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: AppColors.onBrand))
                        : const Icon(LucideIcons.send, size: 16),
                    label: Text(_filterOn && (_dfPreview?.count ?? 0) > 0 ? 'إرسال إلى ${_dfPreview!.count}' : 'إرسال',
                        style: const TextStyle(
                          fontFamily: AppType.family,
                          fontSize: 13, height: 1.35,
                          fontWeight: FontWeight.w700,
                        )),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandAccent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(R.md)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// تأكيد الإرسال بالتحديد: العدد والملاحظات (دين قديم، غير موجودين، بلا دين، حظروا البوت) والأسماء بالدين والعمر، ثمّ النصّ.
class _TgFilteredConfirm extends StatelessWidget {
  const _TgFilteredConfirm({required this.preview, required this.summary, required this.message});
  final bc.BroadcastPreview preview;
  final String summary;
  final String message;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final pv = preview;
    final notes = <String>[
      if (pv.legacy > 0) '${pv.legacy} عليهم «دين قديم» (أقدم من سجلّاتنا) — مشمولون بأيّ عمر',
      if (pv.unknownAge > 0)
        pv.ageUnsupported ? 'عمر الدين غير معروف لهذه الشركة — ${pv.unknownAge} لم يُشملوا' : '${pv.unknownAge} بلا عمر دينٍ معروف — لم يُشملوا',
      if (pv.notFound > 0) '${pv.notFound} مربوطاً لم نجدهم في قائمة الشركة — لم يُشملوا',
      if (pv.notDebtor > 0) '${pv.notDebtor} من المربوطين بلا دين — خارج التحديد',
      if (pv.blocked > 0) '${pv.blocked} حظروا البوت — لا تصلهم',
    ];
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.send,
        title: 'تأكيد الإرسال عبر تلغرام',
        subtitle: 'المربوطون المدينون — بالتحديد',
        tint: AppColors.channelTelegram,
        tintBg: AppColors.channelTelegramSoftBg,
        onClose: () => Navigator.of(context).pop(false),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(summary, style: AppType.body(color: AppColors.textBody)),
          const SizedBox(height: Sp.sm),
          Container(
            key: const ValueKey('tg-confirm-count'),
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              color: AppColors.channelTelegramSoftBg,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              const ListIconBox(icon: LucideIcons.send, tone: ListTone.info, size: 40),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${pv.count}', style: AppType.statValue(color: AppColors.textHi)),
                  Text('سيصلهم عبر تلغرام', style: AppType.micro(color: AppColors.textMid)),
                ]),
              ),
            ]),
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: Sp.sm),
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $n', style: AppType.micro(color: AppColors.textMid).copyWith(height: 1.5)),
              ),
          ],
          const SizedBox(height: Sp.sm),
          Container(
            decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(R.md)),
            child: Column(children: [
              for (var i = 0; i < pv.rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: AppColors.border),
                ListSubscriberRow(
                  key: ValueKey('tg-df-row-${pv.rows[i].username}'),
                  title: pv.rows[i].name ?? pv.rows[i].username,
                  subtitle: pv.rows[i].name == null ? '' : pv.rows[i].username,
                  subtitleLtr: true,
                  selectable: false,
                  selected: false,
                  trailing: ListAmountCell(
                    amount: AmountShorthand.format(pv.rows[i].debt.round()).isEmpty ? '0' : AmountShorthand.format(pv.rows[i].debt.round()),
                    amountColor: AppColors.warningOnSoft,
                    badge: pv.rows[i].legacy
                        ? 'دين قديم'
                        : (pv.rows[i].days == null ? null : (pv.rows[i].days == 0 ? 'اليوم' : bc.arDaysCount(pv.rows[i].days!))),
                    badgeTone: pv.rows[i].legacy ? ListTone.info : ((pv.rows[i].days ?? 0) > 30 ? ListTone.danger : ListTone.warning),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: Sp.sm),
          Container(
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
            child: Text(message, style: AppType.body(color: AppColors.textBody)),
          ),
        ],
      ),
      footer: Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('رجوع', style: AppType.button(color: AppColors.textHi)),
          ),
        ),
        const SizedBox(width: Sp.sm),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            key: const ValueKey('tg-confirm-send'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandAccent),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(LucideIcons.send, size: 16),
            label: Text('إرسال إلى ${pv.count}', style: AppType.button(color: AppColors.onBrand)),
          ),
        ),
      ]),
    );
  }
}
