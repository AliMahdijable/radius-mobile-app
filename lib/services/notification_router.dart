import 'package:flutter/material.dart';

import '../api/subscribers_api.dart';
import '../models/app_notification.dart';
import '../models/subscriber.dart';
import '../screens/subscribers/subscriber_detail_screen.dart';

/// يقرّر إلى أين يأخذ الإشعارُ المستخدم — **مصدرٌ واحد** يستعمله
/// النقرُ داخل صندوق الوارد والنقرُ من شاشة القفل معاً.
///
/// ── لماذا وُجد ────────────────────────────────────────────────
/// كان منطق التوجيه محبوساً داخل `InboxScreen`: ينقر المدير إشعاراً
/// **في الصندوق** فيُفتح كرت المشترك، وينقر **الإشعار نفسه** من شاشة
/// القفل فيُفتح التطبيق على آخر شاشةٍ كان فيها ولا شيء غير ذلك.
/// فـ`FcmService.onNotificationTap` كان معلَّقاً بلا مُسنِد.
///
/// والناقص لم يكن المنطق بل سلكاً يربط نقرة النظام به.
///
/// ── ولماذا صفُّ انتظار ────────────────────────────────────────
/// النقرة من **الإغلاق التامّ** تصل قبل أن يبني التطبيق أوّل شاشة
/// وقبل أن يتحقّق من الجلسة. فتنفيذها فوراً إمّا يضيع (لا Navigator
/// بعد) أو يفتح شاشةً على حسابٍ لم يُسجَّل دخوله. فتُحفَظ وتُنفَّذ
/// حين يُعلن التطبيق جاهزيّته.
class NotificationRouter {
  NotificationRouter._();

  static GlobalKey<NavigatorState>? _navKey;
  static bool _ready = false;
  static AppNotification? _pending;

  /// يُستدعى مرّةً عند بناء `MaterialApp`.
  static void attach(GlobalKey<NavigatorState> key) => _navKey = key;

  /// يُستدعى بعد اكتمال الدخول وبناء الشاشة الأولى.
  static void markReady() {
    _ready = true;
    final p = _pending;
    if (p != null) {
      _pending = null;
      handle(p);
    }
  }

  /// يُستدعى عند تسجيل الخروج — لئلّا تُفتح شاشةٌ لحسابٍ انتهى.
  static void reset() {
    _ready = false;
    _pending = null;
  }

  static Future<void> handle(AppNotification n) async {
    if (!_ready) {
      // آخر نقرةٍ هي المقصودة — لا نُكدّس طابوراً يفتح شاشاتٍ متتالية.
      _pending = n;
      return;
    }
    final nav = _navKey?.currentState;
    if (nav == null) {
      _pending = n;
      return;
    }

    // (١) حمولةٌ تحمل مشتركاً بعينه ⇒ افتح كرته. وهذا أدقّ من النوع:
    //     ملخّصٌ جماعيّ قد يحمل مشتركاً واحداً حين يكون وحده.
    final username = extractUsername(n);
    if (username != null) {
      final sub = await findSubscriber(username);
      if (sub != null) {
        await nav.push(MaterialPageRoute(
          builder: (_) => SubscriberDetailScreen(sub: sub),
          fullscreenDialog: true,
        ));
        return;
      }
    }

    // (٢) وإلّا فالنوع يقرّر. والملخّصات الجماعيّة لا تخصّ مشتركاً
    //     واحداً، فوجهتها القائمة لا الكرت.
    final dest = destinationFor(n.kind);
    if (dest != null) onDestination?.call(dest);
  }

  /// وجهةٌ عامّة يفسّرها الغلاف (التبويب + المرشِّح)، فلا يعرف هذا
  /// الملفّ شيئاً عن بنية التبويبات.
  static void Function(NotificationDestination dest)? onDestination;

  static NotificationDestination? destinationFor(NotificationKind k) =>
      switch (k) {
        NotificationKind.nearExpiryDigest =>
          NotificationDestination.subscribersNearExpiry,
        NotificationKind.expiredTodayDigest =>
          NotificationDestination.subscribersExpired,
        NotificationKind.managerDebt => NotificationDestination.managers,
        NotificationKind.managerBalance => NotificationDestination.managers,
        NotificationKind.other => null,
      };

  /// مفاتيح اسم المشترك التي يمرّرها الخادم — بنفس ترتيب أفضليّة
  /// صندوق الوارد حرفاً بحرف.
  static String? extractUsername(AppNotification n) {
    for (final k in const [
      'subscriber_username',
      'username',
      'subscriber',
      'user',
      'subscriber_id',
    ]) {
      final v = n.data[k]?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  static Future<Subscriber?> findSubscriber(String usernameOrId) async {
    final list = await SubscribersApi.loadAllWithOnline();
    if (list == null) return null;
    final needle = usernameOrId.toLowerCase();
    for (final s in list) {
      if (s.username.toLowerCase() == needle) return s;
    }
    for (final s in list) {
      if (s.idx == usernameOrId) return s;
    }
    return null;
  }
}

/// وجهةٌ مجرّدة — الغلاف يترجمها إلى تبويبٍ ومرشِّح.
enum NotificationDestination {
  subscribersNearExpiry,
  subscribersExpired,
  managers,
}
