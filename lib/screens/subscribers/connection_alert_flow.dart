import 'package:flutter/material.dart';

import '../../api/device_probe_api.dart';
import '../../api/whatsapp_api.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../models/device_health.dart';
import '../../models/subscriber.dart';
import '../../services/connection_alerts.dart';
import '../../services/manual_wa_sender.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/manual_wa_chip.dart';
import 'widgets/device_chip_micro.dart';

/// «تنبيه المشترك» اليدويّ — من شريط القائمة ومن بلاطة «تنبيه» في كارت
/// المشترك. كلاهما يظهر عند المشكلة وحدها.
///
/// ١. لقطة الجهاز: من الكاش إن كانت طازجة (الخمس دقائق)، وإلّا فحصٌ لهذا
///    المشترك وحده. لا نرسل على قراءةٍ قديمة: مشتركٌ أصلح كيبله قبل
///    ساعة لا يجوز أن يُطلب منه إصلاحه.
/// ٢. الكشف بحدود المدير (`ConnectionAlerts.detect`).
/// ٣. الرسالة من قوالب المدير، والناقص بالافتراضيّ.
/// ٤. المعاينة نفسها التي تستعملها أزرار القوالب الأخرى: فيها حارس الحظر
///    ومفتاح الوضع اليدويّ/التلقائيّ، فلا نسخة ثانية منهما.
/// ٥. الإرسال عبر `/api/whatsapp/send-message` بـ`sas4Idx` — القناة
///    «تلقائي»: بوت تلغرام إن كان المشترك مربوطاً، وإلّا واتساب.
Future<void> showConnectionAlertFlow(
    BuildContext context, Subscriber sub) async {
  final phone = sub.displayPhone;
  if (phone.isEmpty) {
    showSheetSnack(context, 'لا يوجد رقم هاتف للمشترك', isError: true);
    return;
  }

  // ── ١. لقطة طازجة ─────────────────────────────────────────────
  final ip = sub.ipAddress?.trim() ?? '';
  final hit = DeviceProbeApi.peek(username: sub.username, ip: ip);
  DeviceHealthSnapshot? snap = (hit != null && !hit.stale) ? hit.snap : null;
  if (snap == null) {
    snap = await _probeWithProgress(context, sub);
    if (!context.mounted) return;
  }
  if (snap == null) {
    showSheetSnack(
      context,
      'تعذّر الوصول إلى جهاز المشترك — لا يمكن تحديد المشكلة',
      isError: true,
    );
    return;
  }

  // ── ٢. الكشف ─────────────────────────────────────────────────
  final thresholds = await ConnectionAlertSettings.ensureLoaded();
  if (!context.mounted) return;
  // الزرّ والشريط لا يظهران أصلاً والميزة متوقّفة — هذا حارسٌ لمن ضغط
  // قبل أن يُطفئها مديرٌ آخر على الحساب نفسه.
  if (!thresholds.enabled) {
    showSheetSnack(
      context,
      'تنبيه المشترك متوقّف — فعّله من الإعدادات ← واتساب ← تنبيهات الاتصال',
      isError: true,
    );
    return;
  }
  final problems = ConnectionAlerts.detect(snap, thresholds);
  if (problems.isEmpty) {
    showSheetSnack(context, 'لا توجد مشكلة في آخر فحص لجهاز المشترك ✅');
    return;
  }

  // ── ٣. الرسالة ───────────────────────────────────────────────
  final templates = await WhatsAppApi.loadTemplates();
  if (!context.mounted) return;
  WhatsTemplate? own(String type) {
    for (final t in templates ?? const <WhatsTemplate>[]) {
      if (t.templateType == type) return t;
    }
    return null;
  }

  // التفعيل في حدود المدير (`enabled`) لا في `is_active` القالب — فلا
  // نقرأ هذا هنا كي لا يحكم الميزةَ مفتاحان.
  final envelopeTpl = own(ConnectionAlertTemplates.envelopeType);
  final envelope = (envelopeTpl?.messageContent.trim().isNotEmpty ?? false)
      ? envelopeTpl!.messageContent
      : ConnectionAlertTemplates.defaultFor(
          ConnectionAlertTemplates.envelopeType);
  final lines = <String, String>{
    for (final type in ConnectionAlertTemplates.lineTypes)
      if (own(type) != null) type: own(type)!.messageContent,
  };
  final body = ConnectionAlerts.compose(
    envelope: envelope,
    lines: lines,
    problems: problems,
  );
  final message = WhatsAppApi.renderForSubscriber(body, sub);

  // ── ٤. المعاينة ──────────────────────────────────────────────
  // العنوان يحمل السبب الدقيق («LAN غير مربوط» لا «خلل الكيبل») —
  // المشترك يقرأ سطراً عامّاً، والمدير يعرف ما وراءه.
  final choice = await showManualWaPreviewSheet(
    context,
    title: 'تنبيه المشترك · ${problems.map((p) => p.label).join('، ')}',
    phone: phone,
    messagePreview: message,
  );
  if (choice == null || !choice.confirmed || !context.mounted) return;

  // ── ٥. الإرسال ───────────────────────────────────────────────
  if (choice.manualMode) {
    final ok = await openManualWa(
      phone: phone,
      message: message,
      context: context.mounted ? context : null,
    );
    if (!context.mounted) return;
    showSheetSnack(
      context,
      ok ? 'افتح واتساب واضغط "إرسال" لإتمام التنبيه' : 'تعذّر فتح واتساب',
      isError: !ok,
    );
    return;
  }
  final result = await WhatsAppApi.sendMessage(
    to: phone,
    message: message,
    intent: 'connection_alert',
    sas4Idx: sub.idx,
  );
  if (!context.mounted) return;
  final ch = result.channelArabic;
  showSheetSnack(
    context,
    result.ok
        ? (ch != null ? 'تم إرسال التنبيه · عبر $ch' : 'تم إرسال التنبيه')
        : (result.message ?? 'تعذّر إرسال التنبيه'),
    isError: !result.ok,
  );
}

/// فحصٌ لهذا المشترك وحده خلف نافذة انتظار لا تُغلق باليد: إغلاقها في
/// منتصف الفحص ثمّ `pop` بعده كان سيُغلق الشاشة التي تحتها.
Future<DeviceHealthSnapshot?> _probeWithProgress(
    BuildContext context, Subscriber sub) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    barrierColor: AppColors.scrim,
    builder: (_) => const _ProbingDialog(),
  );
  DeviceHealthSnapshot? snap;
  try {
    snap = await DeviceProbeApi.probe(
      fallbackIp: sub.ipAddress ?? '',
      subscriberUsername: sub.username,
    );
    // القائمة والكارت يقرآن الكاش نفسه — نوقظهما على القراءة الجديدة.
    DeviceProbeBus.bump();
  } finally {
    nav.pop();
  }
  return snap;
}

class _ProbingDialog extends StatelessWidget {
  const _ProbingDialog();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: AppColors.surfaceSheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.xl),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Sp.xl, vertical: Sp.xl),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(width: Sp.md),
              Flexible(
                child: Text(
                  'جاري فحص جهاز المشترك…',
                  style: AppType.body(color: AppColors.textHi),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
