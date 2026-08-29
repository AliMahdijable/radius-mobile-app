import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/telegram_api.dart';
import '../../../theme/colors.dart';

/// telegramBulkLinksSheet — إرسال رابط الربط لكل مشترك عبر واتساب.
/// Dry-run أوّلاً (يعرض عدد المؤهّلين)، ثم confirm للإرسال الفعلي.
Future<void> showTelegramBulkLinksSheet(
  BuildContext context, {
  required String adminId,
  required VoidCallback onDone,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _BulkSheet(adminId: adminId, onDone: onDone),
  );
}

class _BulkSheet extends StatefulWidget {
  const _BulkSheet({required this.adminId, required this.onDone});
  final String adminId;
  final VoidCallback onDone;

  @override
  State<_BulkSheet> createState() => _BulkSheetState();
}

class _BulkSheetState extends State<_BulkSheet> {
  BroadcastLinksPreview? _preview;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() => _loading = true);
    final p = await TelegramApi.previewBroadcastLinks(widget.adminId);
    if (!mounted) return;
    setState(() {
      _preview = p;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('تأكيد الإرسال',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        content: Text(
            'سيُدرَج ${_preview!.eligible} رسالة في طابور واتساب. الإرسال يحترم حدود الإرسال.',
            style: const TextStyle(fontFamily: 'Cairo', height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('أرسل الآن',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _sending = true);
    final res = await TelegramApi.sendBroadcastLinks(widget.adminId);
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('أُدرج ${res.enqueued} رسالة في طابور واتساب',
            style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.brand,
        behavior: SnackBarBehavior.floating,
      ));
      widget.onDone();
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.message ?? 'فشل الإرسال',
            style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.errorFill,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 16,
          left: 16,
          right: 16,
          top: 12,
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
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(LucideIcons.megaphone,
                        color: AppColors.warning, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('بث روابط جماعي',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textHi,
                            )),
                        const SizedBox(height: 2),
                        Text(
                            'يُرسَل رابط ربط تلغرام لكل مشترك عنده واتساب وليس مربوطاً',
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
                    icon:
                        Icon(LucideIcons.x, size: 20, color: AppColors.textMid),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 20,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                )
              else if (_preview == null)
                Text('تعذّر جلب المعاينة',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: AppColors.error,
                    ))
              else
                _previewCard(_preview!),
              const SizedBox(height: 16),
              if (_preview != null && _preview!.eligible > 0)
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: Colors.white))
                        : const Icon(LucideIcons.send, size: 16),
                    label: Text('أرسل لـ${_preview!.eligible} مشترك',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        )),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                )
              else if (_preview != null)
                Text('لا يوجد مشتركون مؤهّلون',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: AppColors.textMid,
                      fontSize: 12,
                    )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewCard(BroadcastLinksPreview p) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('إجمالي المشتركين', p.totalSubs, AppColors.textHi),
          const SizedBox(height: 6),
          _row('مربوطون سلفاً', p.alreadyBound, AppColors.textMid),
          const SizedBox(height: 6),
          _row('بلا واتساب (QR فقط)', p.skippedNoPhone, AppColors.error),
          const Divider(height: 16),
          _row('مؤهّلون للإرسال', p.eligible, AppColors.success, bold: true),
        ],
      ),
    );
  }

  Widget _row(String label, int n, Color color, {bool bold = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: bold ? 13 : 12,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                color: AppColors.textMid,
              )),
        ),
        Text('$n',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: bold ? 15 : 13,
              fontWeight: FontWeight.w700,
              color: color,
            )),
      ],
    );
  }
}
