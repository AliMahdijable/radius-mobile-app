import 'package:flutter/widgets.dart';

import '../core/widgets/permission_locked.dart';
import '../models/subscriber.dart';
import '../services/merged_mode.dart';

/// «كل الصفحات» للموظّف (٩ نوفمبر): عمليّة كتابةٍ على مشترك صفحةٍ كتابتها مغلقةٌ من هنا (غير صفحته الحاليّة) ⇒ رسالة القفل
/// بسببها («انتقل إلى الصفحة من «صفحاتي» لتنفيذها») ولا شيت ولا طلب — حارس شيتات المال نفسها، فكلّ مدخلٍ إليها (صفحة المشترك،
/// قائمة الجدول، «+»، الأوامر الصوتيّة) يُقفل قبل الإرسال. true = مُنعت. المالك والوضع العاديّ: false دائماً.
bool mergedWriteBlocked(BuildContext context, Subscriber sub) {
  final why = MergedOps.writeLock(sub);
  if (why == null) return false;
  showNoPermission(context, action: true, message: why);
  return true;
}
