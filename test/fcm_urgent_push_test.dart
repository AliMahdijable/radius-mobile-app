// إشعار التذكرة/طلب التجديد والتطبيق مفتوح (١٦ نوفمبر — المالك: «من يفتح المشترك تذكره شعار للتطبيق البرو مجاي يوصل»).
// المقيس على 3.0.20+185 بالمحاكي: الدفع يصل، لكن قناة mysvcs_fcm لم تُنشأ قطّ ⇒ «متفرّقات» بلا نافذةٍ منبثقة، والتطبيق مفتوحاً شريطٌ
// صامت ٤ ثوانٍ. الآن: القناة تُنشأ بأهميّةٍ عالية، والتذكرة/التجديد والتطبيق مفتوح ⇒ إشعار نظامٍ أيضاً (صوت + نافذة) — وغيرهما كما كان.
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/app_notification.dart';
import 'package:rad_mysvcs/services/fcm_service.dart';
import 'package:rad_mysvcs/services/inbox_service.dart';

RemoteMessage _msg(String id, String type) => RemoteMessage(
      messageId: id,
      notification: const RemoteNotification(title: 'تذكرة جديدة من مشترك', body: 'علي — الإنترنت: النت مقطوع'),
      data: {'type': type, 'ticket_id': '70', 'event': 'created', 'company_admin_id': '2'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final shown = <AppNotification>[];
  final banners = <AppNotification>[];

  setUp(() {
    shown.clear();
    banners.clear();
    FcmService.debugShowSystem = (n) async => shown.add(n);
    FcmService.onForegroundNotification = banners.add;
  });
  tearDown(() {
    FcmService.debugReset();
    FcmService.onForegroundNotification = null;
  });

  test('تذكرة والتطبيق مفتوح ⇒ إشعار نظامٍ (صوت ونافذة) مع اللافتة والصندوق', () async {
    await FcmService.debugForeground(_msg('m1', 'portal_ticket'));
    expect(banners.length, 1);
    expect(shown.length, 1);
    expect(shown.single.data['type'], 'portal_ticket');
    expect(InboxService.all.any((n) => n.data['type'] == 'portal_ticket'), isTrue);
  });

  test('طلب تجديد كذلك؛ وإشعارٌ عاديّ (قرب الانتهاء) يبقى لافتةً وحدها كما كان', () async {
    await FcmService.debugForeground(_msg('m2', 'renew_request'));
    await FcmService.debugForeground(_msg('m3', 'near_expiry'));
    expect(banners.length, 2);
    expect(shown.map((n) => n.data['type']), ['renew_request']);
  });

  test('القناة: المعرّف نفسه الذي يرسل عليه الخادم والمعلَن في المانيفست', () {
    expect(FcmService.channelId, 'mysvcs_fcm');
    expect(FcmService.urgentTypes, containsAll(['portal_ticket', 'renew_request']));
  });
}
