import 'package:flutter/foundation.dart';

import '../api/subscribers_api.dart';
import '../models/subscriber.dart';

/// عدّاد الإشعارات "الحيّة" (منتهي اليوم + قربوا الانتهاء) — reactive
/// حتى الجرس فوق الـDashboard يعكس الحالة الفعلية بدون setState يدوي.
///
/// المصدر الوحيد للحقيقة: قائمة المشتركين المُخزّنة في SubscribersApi.
/// عند كل refresh نُعيد الحساب من الـcache ونرفع ValueNotifier.
class AlertsService {
  AlertsService._();

  /// عدد المشتركين "حاليّاً في خطر" = قريب الانتهاء + انتهى اليوم.
  /// نُعرِّفه هنا حتى الجرس + InboxScreen يتّفقون على نفس الرقم.
  static final ValueNotifier<int> count = ValueNotifier<int>(0);

  /// عدد المشتركين متبقّي لهم أقل من 24 ساعة (لم ينتهوا بعد).
  static final ValueNotifier<int> nearExpiryCount = ValueNotifier<int>(0);

  /// عدد المشتركين اللي انتهى اشتراكهم اليوم فعلياً.
  static final ValueNotifier<int> expiredTodayCount = ValueNotifier<int>(0);

  /// يُعاد الحساب من قائمة SubscribersApi.loadAll — نستدعيه بعد كل
  /// refresh للـcache. آمن للاستدعاء المتكرر (idempotent).
  static Future<void> refresh() async {
    final list = await SubscribersApi.loadAll();
    if (list == null) return;
    _recompute(list);
  }

  /// يُستدعى من كود يمتلك القائمة فعلاً (يتفادى loadAll مرّة ثانية).
  static void updateFrom(List<Subscriber> list) => _recompute(list);

  static void _recompute(List<Subscriber> list) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var near = 0;
    var expToday = 0;
    for (final s in list) {
      final exp = s.parsedExpiration;
      if (exp == null) continue;
      final expDay = DateTime(exp.year, exp.month, exp.day);
      if (expDay == today && exp.isBefore(now)) {
        expToday++;
        continue;
      }
      // مطلب 2026-07-11: قربوا الانتهاء = متبقّي < 24 ساعة (حتى دقيقة/
      // ثانية) وما زال غير منتهٍ — يظهر لغاية ما ينتهي فيختفي.
      if (exp.isAfter(now) && exp.difference(now).inHours < 24) {
        near++;
      }
    }
    nearExpiryCount.value = near;
    expiredTodayCount.value = expToday;
    count.value = near + expToday;
  }

  /// نُفرغ العدّادات عند logout حتى الـadmin التالي ما يشوف رواسب.
  static void reset() {
    nearExpiryCount.value = 0;
    expiredTodayCount.value = 0;
    count.value = 0;
  }
}
