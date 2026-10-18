import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/sheet_scaffold.dart';

/// 2026-08-26: نسخ نصّ للحافظة مع haptic خفيف + toast تأكيد.
/// helper مشترك حتى لا نكرّر الـpattern في كل tile/card.
///
/// - [text]: النصّ المنسوخ
/// - [label]: ما نُسخ، يُلصق بعد «تمّ نسخ» (مثلاً 'اسم المستخدم', 'الرقم')
/// - [message]: رسالةٌ كاملة بدل «تمّ نسخ [label]» — لنصٍّ مترجَم أو
///   تسميةٍ لا تستقيم بعد «تمّ نسخ» العربيّة.
/// - [duration]: مدّة الإشعار — ثانيتان تكفيان «تمّ نسخ الرقم»، والرسالة
///   الأطول تحتاج أكثر لتُقرأ.
/// - fire-and-forget — لا تنتظر النتيجة. تُرجع `false` إن رفضت المنصّة.
///
/// ⚠️ الإشعار على **الطبقة الجذريّة** لا على `ScaffoldMessenger`.
///
/// 🐛 كان `ScaffoldMessenger.of(context).showSnackBar(...)`، والمِرسال يرسم
/// على Scaffold الصفحة — **تحت** أيّ شيتٍ مفتوح. فالنسخ من داخل شيت (رابط
/// تلغرام، معلومات المشترك…) ينجح ولا يرى المدير ما يؤكّده. الطبقة
/// الجذريّة فوق كلّ المسارات، شيتاتٍ وصفحات، فيُرى الإشعار أينما نُسخ.
///
/// والطبقة تُلتقط **قبل** انتظار الحافظة: الودجة التي ضُغطت قد تزول أثناءه
/// (شيتٌ يُغلق)، وسياقٌ ميّت لا يُسأل عن أسلافه.
///
/// ولكلّ نسخٍ إشعارٌ واحدٌ حيّ ([_copyTag]): من ينسخ خمس معلوماتٍ تباعاً
/// يرى آخرها، لا خمسة إشعاراتٍ مكدّسة في المكان نفسه.
Future<bool> copyToClipboard(
  BuildContext context,
  String text, {
  String label = 'النصّ',
  String? message,
  Duration duration = const Duration(seconds: 2),
}) async {
  // سياقٌ زال قبل النداء (نداءٌ بعد انتظارٍ عند المستدعي) لا يُسأل عن
  // أسلافه — يُنسخ النصّ كما كان، بلا إشعار.
  final overlay =
      context.mounted ? Overlay.maybeOf(context, rootOverlay: true) : null;
  HapticFeedback.selectionClick();
  var ok = true;
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (_) {
    ok = false;
  }
  if (overlay != null && overlay.mounted) {
    showSheetSnackOn(
      overlay,
      ok ? (message ?? 'تمّ نسخ $label') : 'تعذّر النسخ — أعد المحاولة',
      isError: !ok,
      duration: duration,
      tag: _copyTag,
    );
  }
  return ok;
}

/// وسم إشعار النسخ — الجديد يُزيل سابقه (`showSheetSnackOn(tag:)`).
const _copyTag = #copyToClipboard;
