// إشعارات الحاسبة (DesktopPushService) بخادمٍ وهميّ: الربط، القراءة الأولى الصامتة، الإشعار الواحد، الدفعة الكبيرة،
// ما فات أثناء الغياب، تبديل الشركة، والخروج.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/models/app_notification.dart';
import 'package:rad_mysvcs/services/desktop_push_service.dart';
import 'package:rad_mysvcs/services/inbox_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Server implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<Map<String, dynamic>> feeds = [];
  int feedStatus = 200;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(o);
    var status = 200;
    Object data = {'success': true};
    if (o.uri.path == '/api/push/feed') {
      status = feedStatus;
      data = feeds.isEmpty ? {'success': true, 'items': [], 'cursor': o.queryParameters['after'] ?? 0, 'catchup': false} : feeds.removeAt(0);
    }
    return ResponseBody.fromString(jsonEncode(data), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}

  List<RequestOptions> to(String path) => requests.where((r) => r.uri.path == path).toList();
}

Map<String, dynamic> item(int id, {String title = 'عنوان', String body = 'نصّ', int age = 5, Map<String, String>? data}) =>
    {'id': id, 'title': title, 'body': body, 'data': data ?? {}, 'category': null, 'age_sec': age};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Server server;
  late List<List<String>> shown;
  String admin = 'speednet-iq:1429';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppPlatform.debugIsDesktop = true;
    server = _Server();
    ApiClient.dio.httpClientAdapter = server;
    shown = [];
    admin = 'speednet-iq:1429';
    DesktopPushService.reset();
    DesktopPushService.debugAdminId = () async => admin;
    DesktopPushService.debugShow = (t, b, p) async => shown.add([t, b, p]);
    await InboxService.clear();
  });

  tearDown(() {
    DesktopPushService.reset();
    DesktopPushService.debugAdminId = null;
    DesktopPushService.debugShow = null;
    AppPlatform.debugIsDesktop = null;
  });

  test('الهاتف (لا حاسبة): لا شيء', () async {
    AppPlatform.debugIsDesktop = false;
    await DesktopPushService.start();
    expect(server.requests, isEmpty);
    expect(DesktopPushService.running, isFalse);
  });

  test('الدخول: ربط الجهاز بمعرّف تثبيتٍ ثابت، ثمّ أوّل قراءةٍ بلا مؤشّر — للجرس بلا إشعارات', () async {
    server.feeds.add({'success': true, 'items': [item(40, age: 7200), item(42)], 'cursor': 42, 'catchup': true});
    await DesktopPushService.start();
    final reg = server.to('/api/push/desktop/register').single;
    final install = (reg.data as Map)['installId'] as String;
    expect(RegExp(r'^[a-f0-9]{32}$').hasMatch(install), isTrue);
    expect((reg.data as Map)['adminId'], admin);
    final feed = server.to('/api/push/feed').single;
    expect(feed.queryParameters, {'adminId': admin});
    expect(shown, isEmpty, reason: 'القراءة الأولى للجرس فقط');
    expect(InboxService.all.map((n) => n.id).toList(), ['feed-42', 'feed-40']);
    // القراءة التالية بعد المؤشّر، والمعرّف نفسه بلا إعادة ربط (≤ ١٢ ساعة)
    await DesktopPushService.tickNow();
    expect(server.to('/api/push/feed').last.queryParameters['after'], 42);
    expect(server.to('/api/push/desktop/register'), hasLength(1));
  });

  test('إشعارٌ جديد واحد ⇒ إشعار نظامٍ بعنوانه ونصّه، ومرّةً واحدة وإن عاد', () async {
    server.feeds.add({'success': true, 'items': [], 'cursor': 10, 'catchup': true});
    await DesktopPushService.start();
    server.feeds.add({
      'success': true,
      'items': [item(11, title: 'دين جديد عليك', body: 'أضاف المدير دين بقيمة 25,000 IQD', data: {'type': 'manager_debt_added'})],
      'cursor': 11,
      'catchup': false,
    });
    await DesktopPushService.tickNow();
    expect(shown, [
      ['دين جديد عليك', 'أضاف المدير دين بقيمة 25,000 IQD', 'feed-11'],
    ]);
    expect(InboxService.all.single.kind, NotificationKind.managerDebt);
    server.feeds.add({'success': true, 'items': [item(11, title: 'دين جديد عليك')], 'cursor': 11, 'catchup': false});
    await DesktopPushService.tickNow();
    expect(shown, hasLength(1), reason: 'لا تكرار');
  });

  test('أكثر من ٣ في قراءةٍ واحدة ⇒ إشعارٌ واحد بعددها يفتح الصندوق', () async {
    server.feeds.add({'success': true, 'items': [], 'cursor': 0, 'catchup': true});
    await DesktopPushService.start();
    server.feeds.add({'success': true, 'items': [for (var i = 1; i <= 5; i++) item(i)], 'cursor': 5, 'catchup': false});
    await DesktopPushService.tickNow();
    expect(shown, [
      ['إشعارات جديدة', '5 إشعارات', 'desktop-push:inbox'],
    ]);
    expect(InboxService.all, hasLength(5));
  });

  test('ما وصل والبرنامج مسكَّر (أقدم من ٣٠ دقيقة) ⇒ «وصلتك إشعارات أثناء غيابك»', () async {
    SharedPreferences.setMockInitialValues({'desktop_push_cursor_v1:speednet-iq:1429': 7});
    server.feeds.add({'success': true, 'items': [item(8, age: 3 * 3600), item(9, age: 60)], 'cursor': 9, 'catchup': false});
    await DesktopPushService.start();
    expect(server.to('/api/push/feed').single.queryParameters['after'], 7, reason: 'المؤشّر محفوظٌ لكلّ مدير');
    expect(shown, [
      ['وصلتك إشعارات أثناء غيابك', 'إشعاران', 'desktop-push:inbox'],
    ]);
  });

  test('الخادم بلا المسار بعد (404) ⇒ لا رمي، والمحاولة التالية لاحقاً', () async {
    server.feedStatus = 404;
    await DesktopPushService.start();
    expect(DesktopPushService.running, isTrue);
    expect(shown, isEmpty);
  });

  test('تبديل الشركة: ربطٌ جديد للمدير الجديد ومؤشّرٌ خاصٌّ به؛ والخروج يفكّ الربط بالمعرّف نفسه', () async {
    server.feeds.add({'success': true, 'items': [], 'cursor': 3, 'catchup': true});
    await DesktopPushService.start();
    final install = (server.to('/api/push/desktop/register').single.data as Map)['installId'];
    admin = 'earthlink:115357';
    server.feeds.add({'success': true, 'items': [], 'cursor': 90, 'catchup': true});
    await DesktopPushService.start();
    final regs = server.to('/api/push/desktop/register');
    expect(regs, hasLength(2));
    expect((regs.last.data as Map)['adminId'], 'earthlink:115357');
    expect((regs.last.data as Map)['installId'], install, reason: 'الجهاز نفسه');
    expect(server.to('/api/push/feed').last.queryParameters, {'adminId': 'earthlink:115357'});
    await DesktopPushService.stop();
    final un = server.to('/api/push/desktop/unregister').single;
    expect(un.data, {'adminId': 'earthlink:115357', 'installId': install});
    expect(DesktopPushService.running, isFalse);
  });

  test('صفّ الخادم ⇒ إشعار الصندوق نفسه الذي يبنيه FCM (النوع والوقت من العمر)', () {
    final now = DateTime(2026, 10, 25, 12);
    final n = DesktopPushService.fromFeed(
      {'id': 77, 'title': 't', 'body': 'b', 'data': {'type': 'near_expiry_digest', 'count': '3'}, 'age_sec': 90},
      now: now,
    )!;
    expect(n.id, 'feed-77');
    expect(n.kind, NotificationKind.nearExpiryDigest);
    expect(n.receivedAt, now.subtract(const Duration(seconds: 90)));
    expect(n.data['count'], '3');
    expect(DesktopPushService.fromFeed({'title': 'بلا id'}), isNull);
  });
}
