import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/telegram_api.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// telegramBroadcastSheet — إرسال رسالة عبر تلغرام لكل المرتبطين.
/// Dry-run (يعرض عدد المستقبلين) ثم Send.
Future<void> showTelegramBroadcastSheet(
  BuildContext context, {
  required String adminId,
}) {
  return showModalBottomSheet(
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

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
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
      scrollable: false,
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
          if (_preview != null) ...[
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
              Expanded(
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
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: (_sending ||
                            _preview == null ||
                            _preview!.eligible == 0)
                        ? null
                        : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: AppColors.onBrand))
                        : const Icon(LucideIcons.send, size: 16),
                    label: const Text('إرسال',
                        style: TextStyle(
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
