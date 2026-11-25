import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/owner_broadcast_push.dart';

/// «الإشعارات العامّة» (٢٥ نوفمبر): «شاهده» مرّةً لكلّ إشعار، ورابط «حدّث الآن» لمتاجر التطبيق وحدها، والربط بالهاتف والنقر.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(OwnerBroadcastPush.resetForTest);
  tearDown(OwnerBroadcastPush.resetForTest);

  test('«شاهده»: مرّةً لكلّ إشعار؛ غير إشعار المالك أو رقمٌ تالف ⇒ لا شيء؛ تعذّر ⇒ يُعاد بالمرّة القادمة', () async {
    final posted = <int>[];
    var fail = false;
    OwnerBroadcastPush.debugPost = (id, adminId) async {
      if (fail) throw Exception('net');
      posted.add(id);
    };
    await OwnerBroadcastPush.reportSeen({'type': 'owner_broadcast', 'broadcast_id': '7'});
    await OwnerBroadcastPush.reportSeen({'type': 'owner_broadcast', 'broadcast_id': '7'});
    expect(posted, [7]);
    await OwnerBroadcastPush.reportSeen({'type': 'conn_alert_sent', 'broadcast_id': '8'});
    await OwnerBroadcastPush.reportSeen({'type': 'owner_broadcast', 'broadcast_id': 'x'});
    await OwnerBroadcastPush.reportSeen({'type': 'owner_broadcast', 'broadcast_id': '0'});
    expect(posted, [7]);
    fail = true;
    await OwnerBroadcastPush.reportSeen({'type': 'owner_broadcast', 'broadcast_id': '9'});
    fail = false;
    await OwnerBroadcastPush.reportSeen({'type': 'owner_broadcast', 'broadcast_id': '9'});
    expect(posted, [7, 9]);
  });

  test('رابط «حدّث الآن»: https لبلاي وأبل ومايكروسوفت وحدها', () {
    Uri? u(String s) => OwnerBroadcastPush.storeUrlOf({'url': s});
    expect(u('https://play.google.com/store/apps/details?id=com.mysvcs.rad_mysvcs')?.host, 'play.google.com');
    expect(u('https://apps.apple.com/iq/app/myservices-pro/id6770731907')?.host, 'apps.apple.com');
    expect(u('https://apps.microsoft.com/detail/x')?.host, 'apps.microsoft.com');
    for (final bad in ['', 'http://play.google.com/x', 'https://evil.com/play.google.com', 'javascript:alert(1)', 'https://play.google.com.evil.com/']) {
      expect(u(bad), isNull, reason: bad);
    }
  });

  test('النقر: إشعار المالك يُعالج (شاهده + المتجر إن كان)؛ وغيره لا', () async {
    final posted = <int>[];
    final opened = <Uri>[];
    OwnerBroadcastPush.debugPost = (id, _) async => posted.add(id);
    OwnerBroadcastPush.debugLaunch = (url) async => opened.add(url);
    expect(await OwnerBroadcastPush.handleTap({'type': 'debt_reminder'}), isFalse);
    expect(await OwnerBroadcastPush.handleTap({'type': 'owner_broadcast', 'broadcast_id': '3'}), isTrue);
    expect(opened, isEmpty, reason: 'بلا رابط ⇒ لا متجر');
    expect(await OwnerBroadcastPush.handleTap({'type': 'owner_broadcast', 'broadcast_id': '4', 'url': 'https://apps.apple.com/iq/app/x/id1'}), isTrue);
    expect(opened.single.host, 'apps.apple.com');
    // «شاهده» بلا انتظار (unawaited) — يقرأ الصفحة من التخزين أوّلاً ⇒ ننتظر وصوله لا دورةً واحدة
    for (var i = 0; i < 100 && posted.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(posted, [3, 4]);
  });

  test('الربط: وصول الإشعار والتطبيق مفتوح يبلّغ «شاهده»، والنقر يمرّ به قبل «إشعارات كلّ شركاتي»', () {
    final fcm = File('lib/services/fcm_service.dart').readAsStringSync();
    final fg = fcm.indexOf('static Future<void> _handleForeground(RemoteMessage m) async {');
    expect(fg, greaterThan(0));
    final fgBody = fcm.substring(fg, fcm.indexOf('static Future<void> _handleOpenedApp', fg));
    expect(fgBody.contains('OwnerBroadcastPush.reportSeen(m.data)'), isTrue);
    final router = File('lib/services/notification_router.dart').readAsStringSync();
    final ob = router.indexOf('OwnerBroadcastPush.handleTap(n.data)');
    final company = router.indexOf('CompanyPush.redirect(nav, n');
    expect(ob, greaterThan(0));
    expect(ob < company, isTrue, reason: 'قبل توجيه الشركات');
    expect(OwnerBroadcastPush.seenPath, '/api/fcm/register/seen', reason: 'مسارٌ تقبله قوائم تمرير ايرث لنك والوطنيّ');
  });
}
