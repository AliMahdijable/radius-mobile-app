import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/subscribers_api.dart';
import '../api/whatsapp_api.dart';
import '../core/widgets/sheet_scaffold.dart';
import '../widgets/manual_wa_chip.dart';

/// 2026-08-26: يفتح واتساب المدير الشخصي مع رسالة جاهزة عبر deep-link
/// `wa.me/{phone}?text={message}`. المدير يضغط "إرسال" بيده فتصير
/// الرسالة organic تماماً — بلا بصمة automation على جلسة السيرفر.
///
/// Fallback: لو تعذّر فتح تطبيق واتساب (غير مثبَّت / رفضته الـsystem)،
/// يفتح `https://wa.me/...` في المتصفّح → web.whatsapp.com. حسب اختيار
/// المستخدم في السؤال، هذا الـfallback الافتراضي.
///
/// [phone] رقم دولي بلا `+` أو `00` (مثال: `9647701234567`).
/// [message] نصّ خام — نُشفّره URL-safe داخلياً.
///
/// يرجع true لو النظام قبل الـintent (لا يعني بالضرورة أن المدير أرسل).
Future<bool> openManualWa({
  required String phone,
  required String message,
  BuildContext? context,
}) async {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) {
    _snack(context, 'رقم هاتف غير صالح');
    return false;
  }
  final encoded = Uri.encodeComponent(message);
  // نجرّب whatsapp://send أوّلاً — يفتح التطبيق مباشرة إذا مثبَّت،
  // وإلا يفشل ونجرّب wa.me التي تفتح المتصفّح كـfallback.
  final appUri = Uri.parse('whatsapp://send?phone=$digits&text=$encoded');
  final webUri = Uri.parse('https://wa.me/$digits?text=$encoded');
  try {
    if (await canLaunchUrl(appUri)) {
      final ok = await launchUrl(appUri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    }
  } catch (_) {
    // ننزل للـweb fallback
  }
  try {
    return await launchUrl(webUri, mode: LaunchMode.externalApplication);
  } catch (_) {
    _snack(context, 'تعذّر فتح واتساب');
    return false;
  }
}

void _snack(BuildContext? ctx, String msg) {
  if (ctx == null || !ctx.mounted) return;
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
    content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
    behavior: SnackBarBehavior.floating,
  ));
}

/// 2026-08-26 (manual WA phase 2): يُستدعى من sheets العمليّات (تسديد/
/// تفعيل/تمديد) بعد نجاح العمليّة على backend مع wa_preview مليان.
/// يعرض modal بمحتوى الرسالة + chip auto/manual + زرّ إرسال ذكيّ:
///   - manual → openManualWa (whatsapp:// أو web.whatsapp.com)
///   - auto → WhatsAppApi.sendMessage (السيرفر يرسل)
///
/// [opTitle] يظهر في header الـsheet ("تأكيد التسديد" / "تأكيد التفعيل" / ...)
/// [sas4Idx] يمرَّر لـsendMessage حتى channelRouter يعرف يوجّه لـTG لو مربوط.
/// يُرجع true = المدير أرسل (بأيّ وضع). false = ألغى أو فشل.
Future<bool> handleWaPreviewAfterOp({
  required BuildContext context,
  required WaPreview preview,
  required String opTitle,
  String? sas4Idx,
}) async {
  final choice = await showManualWaPreviewSheet(
    context,
    title: opTitle,
    phone: preview.phone,
    messagePreview: preview.message,
  );
  if (choice == null || !choice.confirmed) return false;

  if (choice.manualMode) {
    final ok = await openManualWa(
      phone: preview.phone,
      message: preview.message,
      context: context,
    );
    if (!ok && context.mounted) {
      showSheetSnack(context, 'تعذّر فتح واتساب', isError: true);
    }
    return ok;
  }

  // auto — نرسل من السيرفر بعد اختيار المدير
  final r = await WhatsAppApi.sendMessage(
    to: preview.phone,
    message: preview.message,
    intent: preview.intent,
    sas4Idx: sas4Idx,
  );
  if (!r.ok && context.mounted) {
    showSheetSnack(
      context,
      r.message ?? 'فشل إرسال الواتساب',
      isError: true,
    );
  }
  return r.ok;
}
