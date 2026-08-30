import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';

/// 2026-08-26: نسخ نصّ للحافظة مع haptic خفيف + toast تأكيد.
/// helper مشترك حتى لا نكرّر الـpattern في كل tile/card.
///
/// - [text]: النصّ المنسوخ
/// - [label]: عنوان التوست (مثلاً 'اسم المستخدم', 'الهاتف')
/// - fire-and-forget — لا تنتظر النتيجة.
Future<void> copyToClipboard(
  BuildContext context,
  String text, {
  String label = 'النصّ',
}) async {
  HapticFeedback.selectionClick();
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(
      'تمّ نسخ $label',
      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5, height: 1.4),
    ),
    backgroundColor: AppColors.brand,
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 2),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm)),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  ));
}
