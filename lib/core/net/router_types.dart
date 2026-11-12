// أنواعٌ مشتركة لعمليّات راوتر المشترك (١٢ نوفمبر — طلب المالك: «عرض كلمة سرّ الواي فاي وإمكانيّة تبديله وعمل ريبوت»، و«الترافيك
// ماكو» لراوترات C50/C64): كلّ عائلةٍ (Tenda · TP-Link الكلاسيكيّ · Agile · CGI · MER) تُرجع الشكل نفسه، والكرت لا يعرف إلّا هذا.

import '../../models/device_health.dart';

/// لماذا تعذّرت العمليّة — جملةٌ واحدة في الكرت ([routerFailText]).
enum RouterFail {
  /// الراوتر رفض كلمة السرّ (أو اليوزر).
  rejected,

  /// صفحة الراوتر مفتوحة بمكانٍ آخر / الجلسات ممتلئة.
  busy,

  /// الدخول مقفول (محاولاتٌ غلط كثيرة) — لا نرسل شيئاً حتى ينفكّ.
  locked,

  /// لا يجاوب.
  unreachable,

  /// جاوب لكن رفض الأمر أو جاء بما لا نفهمه.
  failed,

  /// لا شبكة واي فاي بكلمة سرٍّ شخصيّة (مفتوحة أو Enterprise) — لا شيء يُغيَّر.
  noPsk,

  /// هذه العائلة لا تدعم العمليّة بعد.
  unsupported,
}

String routerFailText(RouterFail f) => switch (f) {
      RouterFail.rejected => 'الراوتر رفض كلمة السرّ — صحّحها من «الاعتمادات» أو إعداد المشترك',
      RouterFail.busy => 'صفحة الراوتر مفتوحة بمكانٍ ثاني — سكّرها وأعد المحاولة',
      RouterFail.locked => 'الراوتر قافل الدخول مؤقّتاً من كثرة المحاولات',
      RouterFail.unreachable => 'الراوتر ما يجاوب',
      RouterFail.failed => 'الراوتر ما قبل الأمر',
      RouterFail.noPsk => 'الواي فاي بلا كلمة سرٍّ شخصيّة (مفتوح أو Enterprise)',
      RouterFail.unsupported => 'هذا النوع من الراوترات ما يدعمها بعد',
    };

class RouterResult<T> {
  const RouterResult.ok(T this.value, [this.detail]) : fail = null;
  const RouterResult.fail(RouterFail this.fail, [this.detail]) : value = null;

  final T? value;
  final RouterFail? fail;

  /// أثرٌ تقنيّ قصير للتشخيص (لا كلمات سرّ) — ومع النجاح: [needsReboot] حين تقول الصفحة إنّ التغيير لا يسري إلّا بعد الإقلاع.
  final String? detail;

  static const needsRebootTag = 'needs-reboot';
  bool get needsReboot => ok && detail == needsRebootTag;
  bool get ok => fail == null;
}

/// ما بعد أمر إعادة التشغيل: [confirmed] = الراوتر ردّ بالقبول؛ false = أُرسل وانقطع الاتّصال قبل الردّ (يقلع غالباً).
class RouterReboot {
  const RouterReboot({required this.confirmed, this.seconds});
  final bool confirmed;

  /// مهلة الإقلاع التي يقولها الراوتر نفسه إن قالها.
  final int? seconds;
}

/// عيّنة النبضة الحيّة: عدّادات بايت تراكميّة ([rxBytes]/[txBytes] — المعدّل فرق عيّنتين) أو معدّلٌ جاهز ([downBps]/[upBps])،
/// ومعها المتّصلون الآن ومدّة اتّصال الإنترنت إن قرأها.
class RouterSample {
  const RouterSample({this.rxBytes, this.txBytes, this.downBps, this.upBps, this.clients, this.wanOnlineSeconds, this.at});
  final int? rxBytes;
  final int? txBytes;
  final int? downBps;
  final int? upBps;
  final List<RouterClient>? clients;
  final int? wanOnlineSeconds;
  final DateTime? at;
}

/// معدّل الترافيك بين عيّنتي عدّادات (بت/ثانية) — null حين لا يصلح (أوّل عيّنة، رجوع العدّاد بعد إقلاع، زمنٌ قصيرٌ جدّاً).
({int down, int up})? routerRate(RouterSample prev, RouterSample cur) {
  final a = prev.at, b = cur.at;
  if (a == null || b == null) return null;
  final ms = b.difference(a).inMilliseconds;
  if (ms < 500) return null;
  final r0 = prev.rxBytes, r1 = cur.rxBytes, t0 = prev.txBytes, t1 = cur.txBytes;
  if (r0 == null || r1 == null || t0 == null || t1 == null) return null;
  if (r1 < r0 || t1 < t0) return null;
  return (down: ((r1 - r0) * 8 * 1000 / ms).round(), up: ((t1 - t0) * 8 * 1000 / ms).round());
}

/// جلسةٌ حيّة للكرت (دخولٌ مرّة، ثمّ قراءةٌ خفيفة كلّ نبضة، وخروجٌ عند الإغلاق).
abstract class RouterLive {
  Future<RouterSample?> sample();

  /// طُردنا أو انتهت الجلسة — أغلقها وافتح غيرها بعد مهلة.
  bool get lost;
  Future<void> close();
}

/// كلمة سرّ واي فاي مقبولة (WPA2/WPA3 الشخصيّ): ٨–٦٣ حرفاً من ASCII المطبوع — null = صالحة، وإلّا السبب.
String? wifiPasswordProblem(String p) {
  if (p.length < 8) return 'كلمة السرّ ٨ أحرف على الأقل';
  if (p.length > 63) return 'كلمة السرّ ٦٣ حرفاً على الأكثر';
  for (final c in p.codeUnits) {
    if (c < 0x20 || c > 0x7e) return 'أحرفٌ إنكليزيّة وأرقام ورموز فقط (لا عربي ولا إيموجي)';
  }
  return null;
}
