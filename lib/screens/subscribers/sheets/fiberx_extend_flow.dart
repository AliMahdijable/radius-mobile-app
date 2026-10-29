import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscribers_api.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';

/// «تمديد» عند فايبر اكس = رسالة واتساب **منهم** للمشترك ليمدّد اشتراكه من تطبيقهم — لا مال ولا تغيير على الاشتراك. كزرّ
/// موقعهم وموقعنا (`FiberxExtend` في FiberxSubscriberSection.tsx): تأكيدٌ قبل الإرسال، والتكرار خلال دقيقتين بتأكيدٍ صريح
/// (`RECENT_DUPLICATE`)، و«لا نعرف هل وصلت» (`FIBERX_EXTEND_UNKNOWN`) تُقال كما هي لا «فشل» — فلا يعيدها على مشتركٍ وصلته.
Future<void> showFiberxExtendFlow(BuildContext context, Subscriber sub) async {
  final idx = sub.idx;
  if (idx == null) return;
  final go = await showConfirmSheet(
    context,
    title: 'تمديد — رسالة واتساب للمشترك',
    message:
        'سيُرسل فايبر اكس للمشترك رسالة واتساب ليمدّد اشتراكه من تطبيقهم. متابعة؟',
    confirmLabel: 'أرسل رسالة التمديد',
    icon: LucideIcons.messageCircle,
  );
  if (go != true || !context.mounted) return;
  var r = await SubscribersApi.fiberxExtendNotice(idx: idx);
  if (!context.mounted) return;
  if (r.code == 'RECENT_DUPLICATE') {
    final again = await showConfirmSheet(
      context,
      title: 'أُرسلت قبل قليل',
      message:
          '${r.message ?? 'أُرسلت رسالة التمديد لهذا المشترك قبل قليل'}\n\nإرسالها ثانيةً؟',
      confirmLabel: 'أرسلها ثانيةً',
      icon: LucideIcons.messageCircle,
      tone: AppTone.warning,
    );
    if (again != true || !context.mounted) return;
    r = await SubscribersApi.fiberxExtendNotice(idx: idx, confirmRepeat: true);
    if (!context.mounted) return;
  }
  if (r.ok) {
    await showSheetSnack(
      context,
      r.delivered
          ? 'وصلت رسالة التمديد للمشترك على واتساب'
          : 'قُبل الإرسال — تصل الرسالة للمشترك خلال لحظات',
    );
    return;
  }
  if (r.code == 'FIBERX_EXTEND_UNKNOWN') {
    await showSheetSnack(
      context,
      r.message ?? 'لم نعرف هل وصلت الرسالة — تحقّق من المشترك قبل الإعادة',
      duration: const Duration(seconds: 6),
      autoExplain: false,
    );
    return;
  }
  await showSheetSnack(
    context,
    r.message ?? 'تعذّر إرسال رسالة التمديد',
    isError: true,
  );
}
