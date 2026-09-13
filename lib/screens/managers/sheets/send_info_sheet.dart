import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/manager_debts_api.dart';
import '../../../api/managers_api.dart';
import '../../../api/whatsapp_api.dart';
import '../../../core/util/format.dart';
import '../../../services/manual_wa_sender.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../widgets/manual_wa_chip.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';

/// إرسال رسالة معلومات للمدير (وضعه المالي الحالي) بدون أي عملية.
/// مطابق v1 _sendManagerInfoMessage (managers_screen.dart:1109).
/// يُولّد قالب جاهز يحتوي على الرصيد + الدين، ويسمح للأدمن بتعديله
/// قبل الإرسال.
Future<bool?> showSendInfoSheet(BuildContext context, Manager m) {
  return showModalBottomSheet<bool>(
    barrierColor: AppColors.scrim,
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SendInfoSheet(manager: m),
  );
}

/// قناة الإرسال.
///
/// ⚠️ تلغرام **ليس بديلاً مكافئاً** لواتساب هنا: بوت تلغرام لا يستطيع
/// بدء محادثة، فلا يصل إلّا من ربط حسابه ببوته. لذلك يُعرض الخيار
/// معطّلاً لا مخفيّاً — فيعرف المدير أنّ القناة موجودة وأنّ التابع لم
/// يربطها، بدل أن يظنّها غير مدعومة.
enum _Channel { whatsapp, telegram }

class _SendInfoSheet extends StatefulWidget {
  const _SendInfoSheet({required this.manager});
  final Manager manager;

  @override
  State<_SendInfoSheet> createState() => _SendInfoSheetState();
}

class _SendInfoSheetState extends State<_SendInfoSheet> {
  late final TextEditingController _msgCtrl;
  bool _submitting = false;

  /// القناة المختارة. الافتراضيّ واتساب دائماً — هو ما يعرفه المدير
  /// ويصل ٢٠٢ مديراً، بينما تلغرام يصل من ربط حسابه فقط.
  _Channel _channel = _Channel.whatsapp;
  // مطلب 2026-06-11: الديون الخارجية (manager-debts) تُجلب عند فتح
  // الـsheet بالتوازي مع رسم القالب الافتراضي. v1 يمرّر extraDebt من
  // الأب (managers_screen) لأنه يحتفظ بـsummary cached؛ v2 لا يحتفظ
  // فيها فنجلبها هنا. عند الوصول، نُعيد بناء النص بالقيم الصحيحة.

  @override
  void initState() {
    super.initState();
    _msgCtrl = TextEditingController(text: _composeMessage(0));
    _loadExtraDebt();
  }

  Future<void> _loadExtraDebt() async {
    final summary = await ManagerDebtsApi.summary();
    if (!mounted) return;
    final extra = summary?.remainingForDebtor(widget.manager.id) ?? 0;
    setState(() {
      _msgCtrl.text = _composeMessage(extra);
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  /// مطابق v1 _sendManagerInfoMessage (managers_screen.dart:1109).
  /// الشكل ثابت — تحية + الرصيد الحالي + بريك-داون الديون الثلاث.
  /// الفاصلة العربية بعد الاسم مهمّة: السيرفر يستعملها لاستخراج
  /// `recipient_name` في سجلّ الواتساب (لو حُذفت الفاصلة، الـRegEx
  /// يأخذ بقية الرسالة كلها كاسم → سجلّ مشوّش).
  String _composeMessage(double extraDebt) {
    final m = widget.manager;
    final managerName = m.fullName.isNotEmpty ? m.fullName : m.username;
    final sas = m.debt;
    final total = sas + extraDebt;
    return [
      'عزيزي المدير $managerName، 👋',
      '',
      '💳 رصيدك الحالي: ${formatIQD(m.credit)} د.ع',
      '',
      '— الديون عليك —',
      '🧾 ديون الساس: ${formatIQD(sas)} د.ع',
      '📑 ديون أخرى: ${formatIQD(extraDebt)} د.ع',
      '📊 المجموع: ${formatIQD(total)} د.ع',
    ].join('\n');
  }

  Future<void> _send() async {
    if (_submitting) return;
    final message0 = _msgCtrl.text.trim();
    if (message0.isEmpty) return;

    // ── مسار تلغرام ──────────────────────────────────────────────
    // ⚠️ لا معاينة ولا وضعٌ يدويّ هنا: تلغرام يُرسل من الخادم مباشرةً،
    // ولا يوجد «افتح التطبيق واضغط إرسال» كما في واتساب اليدويّ.
    if (_channel == _Channel.telegram) {
      setState(() => _submitting = true);
      final r = await ManagersApi.sendTelegram(
        id: widget.manager.id,
        message: message0,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      showSheetSnack(
        context,
        r.ok ? 'أُرسلت عبر تلغرام' : (r.message ?? 'تعذّر الإرسال عبر تلغرام'),
        isError: !r.ok,
      );
      if (r.ok) Navigator.of(context).pop(true);
      return;
    }

    final phone = (widget.manager.mobile).trim();
    if (phone.isEmpty) {
      showSheetSnack(context, 'لا يوجد رقم هاتف للمدير', isError: true);
      return;
    }
    final message = _msgCtrl.text.trim();
    if (message.isEmpty) return;
    // 2026-08-26: preview + chip للـmanual mode.
    final choice = await showManualWaPreviewSheet(
      context,
      title: 'إرسال معلومات المدير',
      phone: phone,
      messagePreview: message,
    );
    if (!mounted || choice == null || !choice.confirmed) return;

    setState(() => _submitting = true);
    if (choice.manualMode) {
      final ok = await openManualWa(
        phone: phone,
        message: message,
        context: context,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      if (ok) {
        showSheetSnack(
          context,
          'افتح واتساب واضغط "إرسال" لإتمام العمليّة',
        );
        Navigator.of(context).pop(true);
      } else {
        showSheetSnack(context, 'تعذّر فتح واتساب', isError: true);
      }
      return;
    }
    final r = await WhatsAppApi.sendMessage(
      to: phone,
      message: message,
      intent: 'manager_info',
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    showSheetSnack(
      context,
      r.ok ? 'تم إرسال المعلومات' : (r.message ?? 'تعذّر الإرسال'),
      isError: !r.ok,
    );
    if (r.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final hasPhone = (widget.manager.mobile).trim().isNotEmpty;
    final tgLinked = widget.manager.telegramLinked;
    final isTg = _channel == _Channel.telegram;
    // ⚠️ كلّ قناةٍ وشرطُ إرسالها: واتساب يحتاج رقماً، وتلغرام يحتاج
    // ربطاً. وزرّ الإرسال يتبع المختارة لا الاثنتين.
    final canSend = isTg ? tgLinked : hasPhone;
    final tint = isTg ? AppColors.channelTelegram : AppColors.channelWhatsApp;
    final tintBg =
        isTg ? AppColors.channelTelegramSoftBg : AppColors.channelWhatsAppSoftBg;
    // iOS keyboard-avoidance: push the sheet up so the editable message
    // text field + send button stay visible when the keyboard opens.
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.send,
        title: 'إرسال المعلومات',
        subtitle: widget.manager.username,
        subtitleLtr: true,
        tint: tint,
        tintBg: tintBg,
        onClose: _submitting ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _submitting ? 'جارٍ الإرسال...' : 'إرسال',
        icon: LucideIcons.send,
        color: tint,
        enabled: canSend && !_submitting,
        busy: _submitting,
        onPressed: _send,
      ),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xxl),
        children: [
          _ChannelPicker(
            value: _channel,
            telegramEnabled: tgLinked,
            onChanged: _submitting
                ? null
                : (c) => setState(() => _channel = c),
          ),
          const SizedBox(height: Sp.md),
          if (!hasPhone && !isTg) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.dangerSoftBg,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: AppColors.dangerSoftBorder),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.triangleAlert,
                      size: 14, color: AppColors.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'لا يوجد رقم هاتف محفوظ — لن يُرسل واتساب',
                      style: AppType.bodyBold(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Sp.md),
          ],
          Padding(
            padding: const EdgeInsets.only(bottom: 4, right: 2),
            child: Text('الرسالة (قابلة للتعديل)',
                style: AppType.muted(color: AppColors.textMid)
                    .copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          TextField(
            controller: _msgCtrl,
            maxLines: 12,
            minLines: 8,
            style: AppType.input(color: AppColors.textHi),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.borderSoft),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.borderSoft),
              ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}


/// مبدّل القناة — قسمان متساويان.
///
/// ⚠️ تلغرام **يُعرض معطّلاً لا مخفيّاً** حين لا يكون التابع مربوطاً.
/// إخفاؤه يجعل المدير يظنّ الميّزة غير موجودة؛ وعرضُه معطّلاً برسالةٍ
/// صريحة يقول له إنّها موجودة وإنّ التابع لم يربط حسابه — وهو فرقٌ بين
/// «لا نملكها» و«افعل شيئاً لتحصل عليها».
class _ChannelPicker extends StatelessWidget {
  const _ChannelPicker({
    required this.value,
    required this.telegramEnabled,
    required this.onChanged,
  });

  final _Channel value;
  final bool telegramEnabled;
  final ValueChanged<_Channel>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _ChannelTile(
                label: 'واتساب',
                icon: LucideIcons.messageCircle,
                color: AppColors.channelWhatsApp,
                softBg: AppColors.channelWhatsAppSoftBg,
                selected: value == _Channel.whatsapp,
                enabled: onChanged != null,
                onTap: () => onChanged?.call(_Channel.whatsapp),
              ),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: _ChannelTile(
                label: 'تلغرام',
                icon: LucideIcons.send,
                color: AppColors.channelTelegram,
                softBg: AppColors.channelTelegramSoftBg,
                selected: value == _Channel.telegram,
                enabled: onChanged != null && telegramEnabled,
                onTap: () => onChanged?.call(_Channel.telegram),
              ),
            ),
          ],
        ),
        if (!telegramEnabled) ...[
          const SizedBox(height: Sp.sm),
          Row(
            children: [
              Icon(LucideIcons.info, size: 13, color: AppColors.textMid),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'تلغرام غير متاح — لم يربط هذا المدير حسابه ببوته',
                  style: AppType.muted(color: AppColors.textMid),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.softBg,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color softBg;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // المعطَّل يبقى مقروءاً: لونٌ خافت لا شفافيّةٌ تُذيب النصّ.
    final fg = !enabled
        ? AppColors.textLow
        : (selected ? color : AppColors.textMid);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(R.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected && enabled ? softBg : AppColors.surface,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(
            color: selected && enabled ? color : AppColors.borderSoft,
            width: selected && enabled ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
            // ⚠️ يلتفّ لا يُقتطع: الصفّ الضيّق يسحق النصّ صامتاً.
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppType.bodyBold(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
