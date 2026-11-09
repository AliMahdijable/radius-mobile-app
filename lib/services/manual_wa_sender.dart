import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/company_route.dart';
import '../api/subscribers_api.dart';
import '../api/whatsapp_api.dart';
import '../core/widgets/sheet_scaffold.dart';
import '../models/subscriber.dart';
import '../widgets/manual_wa_chip.dart';
import 'merged_mode.dart';
import '../theme/typography.dart';

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
    if (context != null && context.mounted) {
      _snack(context, 'تعذّر فتح واتساب');
    }
    return false;
  }
}

void _snack(BuildContext? ctx, String msg) {
  if (ctx == null || !ctx.mounted) return;
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
    content: Text(msg, style: const TextStyle(fontFamily: AppType.family)),
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
/// [sub] المشترك: رقمه يمرَّر لـsendMessage حتى channelRouter يعرف يوجّه لـTG لو مربوط، وشركته تحكم «إرسال تلقائي» —
/// الإرسال يخرج من واتساب الشركة المفتوحة وتلغرامها، فلمشترك شركةٍ أخرى في «كل الشركات» لا إرسال تلقائيّ (كان يُرسل رسالته
/// من رقم المفتوحة، أو لمشتركها الذي بالرقم نفسه على تلغرام — التحقّق الثاني من 179): «افتح واتسابي» وحده وسببه.
/// يُرجع true = المدير أرسل (بأيّ وضع). false = ألغى أو فشل.
Future<bool> handleWaPreviewAfterOp({
  required BuildContext context,
  required WaPreview preview,
  required String opTitle,
  required Subscriber sub,
}) async {
  final blocked = await autoWaBlockedFor(sub);
  if (!context.mounted) return false;
  final choice = await showManualWaPreviewSheet(
    context,
    title: opTitle,
    phone: preview.phone,
    messagePreview: preview.message,
    autoBlockedReason: blocked,
  );
  if (choice == null || !choice.confirmed) return false;
  if (!choice.manualMode && blocked != null) {
    // حارسٌ ثانٍ: لا يُرسل من واتساب المفتوحة لمشترك غيرها ولو وصل الاختيار تلقائيّاً
    if (context.mounted) showSheetSnack(context, blocked, isError: true);
    return false;
  }

  if (choice.manualMode) {
    final ok = await openManualWa(
      phone: preview.phone,
      message: preview.message,
      context: context.mounted ? context : null,
    );
    if (!ok && context.mounted) {
      showSheetSnack(context, 'تعذّر فتح واتساب', isError: true);
    }
    return ok;
  }

  // auto — نرسل من السيرفر بعد اختيار المدير (الجلسة المفتوحة صراحةً: صفّها وحده يصل هنا)
  final r = await CompanyRoute.runOpen(() => WhatsAppApi.sendMessage(
        to: preview.phone,
        message: preview.message,
        intent: preview.intent,
        sas4Idx: sub.idx,
      ));
  if (!r.ok && context.mounted) {
    showSheetSnack(
      context,
      r.message ?? 'فشل إرسال الواتساب',
      isError: true,
    );
  }
  return r.ok;
}

/// «إرسال تلقائي» بعد عمليّةٍ على [sub] غير متاح؟ — السبب، أو null (متاح). يخرج من واتساب الشركة المفتوحة وتلغرامها، فلا يُرسل
/// لمشترك شركةٍ أخرى من «كل الشركات» (مفتاح صفّها ليس المفتوحة — ولو خرج المدير من الوضع والشيت مفتوح، أو لم تُعرف شركته).
Future<String?> autoWaBlockedFor(Subscriber sub) async {
  final key = sub.companyKey;
  if (key == null || await MergedMode.isOpenKey(key)) return null;
  final name = MergedMode.companyOf(key)?.name ?? '';
  final who = name.isEmpty ? '' : ' «$name»';
  return MergedMode.employeeSession
      ? 'الإرسال التلقائيّ يخرج من واتساب صفحتك الحاليّة — لمشترك$who افتح واتسابك، أو أرسله من صفحته'
      : 'الإرسال التلقائيّ يخرج من واتساب الشركة المفتوحة — لمشترك$who افتح واتسابك، أو أرسله من شركته';
}
