import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/telegram_api.dart';
import '../../../theme/colors.dart';

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
    barrierColor: Colors.black.withValues(alpha: 0.55),
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
  }

  Future<void> _send() async {
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty || _preview == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('تأكيد الإرسال',
            style:
                TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
        content: Text(
            'سيتمّ إرسال الرسالة لـ${_preview!.eligible} مشترك مربوط. متأكّد؟',
            style: const TextStyle(fontFamily: 'Cairo', height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء',
                style: TextStyle(fontFamily: 'Cairo')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('أرسل',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
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
      content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor: error ? AppColors.error : AppColors.brand,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
          left: 16, right: 16, top: 12,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(LucideIcons.messageCircle,
                        color: Color(0xFF8B5CF6), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('إرسال عام عبر تلغرام',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textHi,
                            )),
                        const SizedBox(height: 2),
                        Text('رسالة لكل المشتركين المربوطين بالبوت',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMid,
                            )),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.x,
                        size: 20, color: AppColors.textMid),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 20,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Textarea
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceInput,
                  borderRadius: BorderRadius.circular(10),
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
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: AppColors.textHi,
                    height: 1.5,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintText: 'اكتب الرسالة هنا...',
                    hintStyle: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      color: AppColors.textLow,
                    ),
                    counterStyle: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      color: AppColors.textLow,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_preview != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFF14B8A6).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF14B8A6)
                            .withValues(alpha: 0.3),
                        width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.circleCheck,
                          size: 16, color: const Color(0xFF14B8A6)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '🎯 سيصل: ${_preview!.eligible} مشترك · مرتبطون: ${_preview!.totalBound} · محظورون: ${_preview!.blocked}',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textHi,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
                                width: 14, height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5))
                            : const Icon(LucideIcons.search, size: 16),
                        label: const Text('فحص مسبق',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            )),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textHi,
                          side: BorderSide(
                              color: AppColors.border, width: 1),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
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
                        onPressed: (_sending || _preview == null)
                            ? null
                            : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5, color: Colors.white))
                            : const Icon(LucideIcons.send, size: 16),
                        label: const Text('إرسال',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            )),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
