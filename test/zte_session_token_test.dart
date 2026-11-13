import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/core/net/ont_traffic.dart';
import 'package:rad_mysvcs/core/net/zte_ont_service.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// الراوتر الضوئيّ H.T.M HS8546V2 (EPON، XPONV4.2.1M19) — المالك ١٤ نوفمبر: «راوتر ضوئي جديد».
///
/// من عائلة ZTE/ZXIC التي ندعمها (MH80)، والفرق بالدخول وحده: سكربت صفحته يضع **رمز جلسة** في الحقل `_SESSION_TOKEN` وفي
/// كوكي `session_cookie` معاً. كان التطبيق يرسل الدخول بلا الرمز فيردّه الجهاز «User information is error» — والكرت يتّهم
/// يوزراً وباسورداً صحيحين. وجلسته بعنوان الطالب لا بكوكي، وصفحةٌ تُطلب بلا جلسة تعود «Session timeout» قصيرة لا صفحة دخول.
/// وعدّاد «Sent» لواي فايه لا يرى ما يمرّ بالمسار السريع — فالتحميل لا يُعرض رقماً ناقصاً.
///
/// جهازٌ وهميّ على 127.0.0.1 (خادم HTTP حقيقيّ) بشكل صفحات الجهاز الحيّ؛ الاعتمادات والرموز هنا وهميّة.
void main() {
  late _FakeHtm d;

  setUp(() async {
    d = _FakeHtm();
    await d.start();
  });

  tearDown(() async {
    ZteOntService.forget(d.host);
    await d.stop();
  });

  group('الدخول برمز الجلسة', () {
    test('الحقل والكوكي كما يضعهما سكربت الصفحة ⇒ جلسة، وضوء الجهاز وطرازه يُقرآن', () async {
      final s = await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1');
      expect(s, isNotNull, reason: 'كان الدخول يُرسل بلا الرمز فيُردّ كأنّ الباسورد غلط');
      final sent = Uri.splitQueryString(d.posts.single.body);
      expect(sent['_SESSION_TOKEN'], d.issuedToken);
      expect(sent['Frm_Logintoken'], '2', reason: 'رمز النموذج من الصفحة نفسها');
      expect(d.posts.single.cookie, 'session_cookie=${d.issuedToken}', reason: 'الجهاز يطابق الحقل بالكوكي');
      expect(d.posts.single.body.indexOf('_SESSION_TOKEN'), lessThan(d.posts.single.body.indexOf('username')),
          reason: 'بترتيب حقول النموذج');
      final o = await ZteOntService.fetchOptical(s!);
      expect(o?.rxPower, '-18.7');
      expect(o?.txPower, '2.6');
      expect(o?.voltage, '3166');
      expect(o?.temperature, '29');
      expect(o?.bias, '14.6');
      expect(o?.vendor, 'zte');
      expect(o?.model, 'HS8546V2');
      expect(d.nextpages, ['epon_status_link_info_t.gch'], reason: 'صفحة الضوء من قائمته مباشرةً');
      expect(ZteOntService.lastIssue(d.host), isNull);
    });

    test('الجلسة بعنوان الطالب: الخروج ينهيها، وبعده الصفحة «Session timeout» قصيرة ⇒ تُعرف نهايةً لا صيغةً جديدة', () async {
      final s = (await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'))!;
      expect(await ZteOntService.fetchOptical(s), isNotNull);
      await ZteOntService.logout(s);
      expect(d.inSession, isFalse);
      d.nextpages.clear();
      expect(await ZteOntService.page(s, 'status_wlaninfo_t.gch'), isNull, reason: 'صفحة «انتهت الجلسة» ليست محتوى');
      expect(await ZteOntService.fetchOptical(s), isNull);
      expect(ZteOntService.lastPageTrace(s), 'epon_link:200L', reason: 'يقف عند أوّل صفحة — لا بحث في قائمةٍ لا تُجاب');
      expect(ZteOntService.lastReadUnknown(s), isFalse, reason: 'جلسةٌ منتهية ليست طرازاً جديداً');
      expect(d.nextpages, ['status_wlaninfo_t.gch', 'epon_status_link_info_t.gch']);
    });

    test('باسورد غلط ⇒ «رُفض» ويُحفظ فلا يُعاد، والصحيح بعده يدخل', () async {
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'wrong'), isNull);
      expect(ZteOntService.lastIssue(d.host)?.issue, ZteLoginIssue.rejected);
      expect(ZteOntService.lastIssue(d.host)?.trace, contains('stok:fc post:200'), reason: 'الأثر يقول إنّ الرمز أُرسل');
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'wrong'), isNull);
      expect(d.posts, hasLength(1), reason: 'المرفوض لا يُعاد');
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNotNull);
      expect(Uri.splitQueryString(d.posts.last.body)['Frm_Logintoken'], '4', reason: 'الرمز يتبدّل مع كلّ صفحة — يُقرأ كلّ مرّة');
    });

    test('نموذجٌ يطلب رمزاً بصيغةٍ لا نعرفها ⇒ لا إرسال ولا اتّهام للباسورد، وشكل الصفحة أثرٌ بلا قيم', () async {
      d.oddTokenForm = true;
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNull);
      final i = ZteOntService.lastIssue(d.host)!;
      expect(i.issue, ZteLoginIssue.unknownForm);
      expect(d.posts, isEmpty, reason: 'دخولٌ بلا رمزه يُرفض ويُحسب محاولةً غلط');
      expect(i.trace, startsWith('get:200 stok:? function dosubmit'));
      expect(i.trace, isNot(contains(d.issuedToken!.substring(1))), reason: 'الأرقام مقنّعة');
      // لم يُحفظ رفضاً: برنامجٌ عُرف شكله بعدها يدخل بالاعتماد نفسه.
      d.oddTokenForm = false;
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNotNull);
    });

    test('المحلِّل: الرمز واسم الكوكي من سكربت الصفحة، وحقلٌ ملأه الخادم يُرسَل كما هو، وMH80 بلا رمز', () {
      final t = ZteOntParse.sessionToken(d.loginPage());
      expect(t?.value, d.issuedToken);
      expect(t?.cookie, 'session_cookie');
      const filled = '<form name="fLogin"><input type="hidden" value="Q7" name="_SESSION_TOKEN" id="_SESSION_TOKEN">'
          '<input name="Frm_Logintoken"></form>';
      expect(ZteOntParse.sessionToken(filled)?.value, 'Q7');
      expect(ZteOntParse.sessionToken(filled)?.cookie, isNull, reason: 'لا كوكي ما لم يضعه سكربت الصفحة');
      const mh80 = '<form name="fLogin"><input type="hidden" name="Frm_Logintoken" value=""></form>'
          '<script>getObj("Frm_Logintoken").value = "3";</script>';
      expect(ZteOntParse.wantsSessionToken(mh80), isFalse);
      expect(ZteOntParse.sessionToken(mh80), isNull);
      expect(ZteOntParse.isLoginPage(d.loginPage()), isTrue);
      expect(ZteOntParse.lockLeft(d.loginPage()), isNull);
    });

    test('المحلِّل: صفحة «انتهت الجلسة» قصيرةٌ بسكربتها، وصفحة محتوى طويلة تذكر الكلمة ليست نهاية', () {
      expect(ZteOntParse.isSessionGone(_FakeHtm.sessionGone), isTrue);
      expect(ZteOntParse.sessionEnded(_FakeHtm.sessionGone), isTrue);
      expect(_FakeHtm.sessionGone.length, inInclusiveRange(500, 800), reason: 'بحجم صفحة الجهاز الحيّ (٦٢٧ بايتاً)');
      final content = '<html>${'x' * 5000}function logout_redirect(){}</html>';
      expect(ZteOntParse.isSessionGone(content), isFalse);
      expect(ZteOntParse.sessionEnded(d.loginPage()), isTrue);
    });
  });

  group('فحص جهاز المشترك', () {
    late _FakeApi api;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      api = _FakeApi();
      final adapter = ApiClient.dio.httpClientAdapter;
      final interceptors = List<Interceptor>.of(ApiClient.dio.interceptors);
      ApiClient.dio.httpClientAdapter = api;
      ApiClient.dio.interceptors.clear();
      addTearDown(() {
        ApiClient.dio.httpClientAdapter = adapter;
        ApiClient.dio.interceptors
          ..clear(keepImplyContentTypeInterceptor: false)
          ..addAll(interceptors);
      });
      DeviceProbeApi.invalidateAdminDefaults();
    });

    test('باعتماد المدير ⇒ قراءة ONT من فرع ZTE بطرازه، ولا طلبات هواوي ولا صفحات إعدادات', () async {
      api.defaults = {'ontUsername': 'agent', 'ontPassword': 'secret-1'};
      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect(snap?.ont?.vendor, 'zte');
      expect(snap?.ont?.model, 'HS8546V2');
      expect(snap?.ont?.rxPower, '-18.7');
      expect(DeviceProbeApi.issueFor(ip: d.host), isNull);
      expect(d.paths.where((p) => p.contains('GetRandCount') || p.contains('login.cgi')), isEmpty);
      expect(d.nextpages.where((p) => p.contains('conf') || p.contains('manager')), isEmpty);
      expect(d.inSession, isFalse, reason: 'الفحص يخرج بعد القراءة');
    });

    test('بلا يوزر من الوكيل ⇒ لا دخول، «يحتاج يوزر وباسورد»', () async {
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      expect(d.posts, isEmpty);
      expect(DeviceProbeApi.issueFor(ip: d.host)?.issue, ProbeIssue.needsCredentials);
    });

    test('صفحة دخولٍ برمزٍ لا نعرفه ⇒ «صفحة الدخول جديدة علينا» لا «رُفض»، وشكلها يُبلَّغ مرّةً بلا قيم', () async {
      api.defaults = {'ontUsername': 'agent', 'ontPassword': 'secret-1'};
      d.oddTokenForm = true;
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      expect(DeviceProbeApi.issueFor(ip: d.host)?.issue, ProbeIssue.unknownLogin);
      expect(d.posts, isEmpty);
      await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final diag = api.requests.where((r) => r.uri.path == '/api/client-diag').toList();
      expect(diag, isNotEmpty, reason: 'طرازٌ يحتاج إضافة — يصل السجلّ بلا انتظار «حفظ وفحص»');
      expect(diag.where((r) => !'${(r.data as Map)['message']}'.startsWith('+')), hasLength(1), reason: 'مرّةً لكلّ عنوان');
      final all = diag.map((r) => jsonEncode(r.data)).join();
      expect(all, contains('unknownLogin'));
      expect(all, contains('stok:?'));
      expect(all, isNot(contains('secret-1')));
      expect(all, isNot(contains('agent')));
    });
  });

  group('الترافيك: هل ترى العدّادات تحميل المشترك؟', () {
    setUp(() {
      OntTrafficSession.zteCheckWindow = const Duration(milliseconds: 60);
      OntTrafficSession.zteRecheck = const Duration(seconds: 60);
      addTearDown(() {
        OntTrafficSession.zteCheckWindow = const Duration(seconds: 8);
        OntTrafficSession.zteRecheck = const Duration(seconds: 60);
      });
    });

    Future<OntTrafficSession> open() async {
      final t = await OntTrafficSession.open(ip: d.host, user: 'agent', pass: 'secret-1', vendor: 'zte');
      expect(t, isNotNull);
      addTearDown(t!.close);
      return t;
    }

    int linkReads() => d.nextpages.where((p) => p == 'epon_status_link_info_t.gch').length;

    test('الصفحات من قائمته، والعدّادات لكلّ SSID ومنفذ (بايتاتٌ: المرسَل تحميل والمستلَم رفع)', () async {
      final t = await open();
      final c = await t.sample();
      expect(c?.byIface.keys, containsAll(['wlan1', 'wlan5', 'lan:Network port1']));
      expect(c?.byIface['wlan1']?.sent, d.wlan1TxBytes);
      expect(c?.byIface['wlan1']?.received, d.wlan1RxBytes);
      expect(d.nextpages, ['status_wlaninfo_t.gch', 'status_ponlan_info_t.gch']);
      expect(t.download, OntDownload.counted);
    });

    test('جهازٌ سليم (المرسَل للعملاء يساير الداخل) ⇒ لا شبهة ولا أيّ طلبٍ زائد', () async {
      final t = await open();
      await t.sample();
      for (var i = 0; i < 4; i++) {
        d.traffic(fromClients: 900, toClients: 1900, ponIn: 2000);
        expect(await t.sample(), isNotNull);
        expect(t.download, OntDownload.counted);
      }
      expect(linkReads(), 0, reason: 'صفحة الرابط (~١٠٠ ك.ب) لا تُقرأ على جهازٍ سليم');
    });

    test('حزمٌ تدخل من الـPON ولا يعدّها الواي فاي ⇒ يُحجب الرقم أثناء التحقّق ثمّ «غير معدود»، ويُحفظ للجهاز', () async {
      final t = await open();
      await t.sample();
      d.traffic(fromClients: 900, toClients: 10, ponIn: 5000);
      await t.sample();
      expect(t.download, OntDownload.checking, reason: 'أوّل معدّلٍ على جهازٍ مشبوه لا يُعرض');
      expect(linkReads(), 1);
      d.traffic(fromClients: 300, toClients: 4, ponIn: 2000);
      await t.sample();
      expect(t.download, OntDownload.checking, reason: 'النافذة لم تنتهِ');
      expect(linkReads(), 1);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      d.traffic(fromClients: 900, toClients: 12, ponIn: 6000);
      await t.sample();
      expect(t.download, OntDownload.uncounted, reason: 'دخل ٨٠٠٠ حزمة وعُدّ ١٦ إطاراً');
      expect(linkReads(), 2);
      expect(OntTrafficSession.knownUncounted(d.host), isTrue);
      // بعد الحكم لا تحقّق آخر في هذه الجلسة.
      d.traffic(fromClients: 900, toClients: 12, ponIn: 6000);
      await t.sample();
      expect(linkReads(), 2);
      // «حفظ وفحص الجهاز» ينساه فيُعاد القياس.
      ZteOntService.forget(d.host);
      expect(OntTrafficSession.knownUncounted(d.host), isFalse);
    });

    test('شبهةٌ بلا ترافيكٍ داخل (رفعٌ بـUDP وحده) ⇒ «معدود» كما كان، ولا تحقّق ثانٍ قبل دقيقة', () async {
      final t = await open();
      await t.sample();
      d.traffic(fromClients: 900, toClients: 5, ponIn: 20);
      await t.sample();
      expect(t.download, OntDownload.checking);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      d.traffic(fromClients: 900, toClients: 5, ponIn: 30);
      await t.sample();
      expect(t.download, OntDownload.counted, reason: 'لا حزم كافية من الـPON للحكم — العدّادات صادقة');
      expect(OntTrafficSession.knownUncounted(d.host), isFalse);
      final reads = linkReads();
      for (var i = 0; i < 3; i++) {
        d.traffic(fromClients: 900, toClients: 5, ponIn: 30);
        await t.sample();
        expect(t.download, OntDownload.counted);
      }
      expect(linkReads(), reads, reason: 'كلّ تحقّقٍ قراءتان زائدتان — لا كلّ نبضة');
    });

    test('تحقّقٌ لاحق (بعد أن حُكم «معدود») يجري بالخلفيّة: الرقم لا يُحجب، وينقلب الحكم حين يثبت النقص', () async {
      OntTrafficSession.zteRecheck = const Duration(milliseconds: 1);
      final t = await open();
      await t.sample();
      d.traffic(fromClients: 900, toClients: 5, ponIn: 20);
      await t.sample(); // تحقّقٌ أوّل
      await Future<void>.delayed(const Duration(milliseconds: 80));
      d.traffic(fromClients: 900, toClients: 5, ponIn: 20);
      await t.sample(); // حُكم: معدود
      expect(t.download, OntDownload.counted);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      d.traffic(fromClients: 900, toClients: 5, ponIn: 4000);
      await t.sample(); // تحقّقٌ ثانٍ يُفتح
      expect(t.download, OntDownload.counted, reason: 'ما بعد الأوّل لا يحجب');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      d.traffic(fromClients: 900, toClients: 5, ponIn: 4000);
      await t.sample();
      expect(t.download, OntDownload.uncounted);
    });

    test('عدّادات الواي فاي صُفّرت في النافذة (إعادة تشغيل الراديو) ⇒ لا حكم', () async {
      final t = await open();
      await t.sample();
      d.traffic(fromClients: 900, toClients: 10, ponIn: 5000);
      await t.sample();
      expect(t.download, OntDownload.checking);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      d.resetWlan();
      d.traffic(fromClients: 0, toClients: 0, ponIn: 5000);
      await t.sample();
      expect(t.download, OntDownload.counted, reason: 'فرقٌ سالب ليس دليلاً');
      expect(OntTrafficSession.knownUncounted(d.host), isFalse);
    });

    test('طُردنا (دخولٌ آخر من عنوانٍ ثانٍ أنهى جلستنا) ⇒ القراءة null بطلبٍ واحد فيعيد الكرت الفتح', () async {
      final t = await open();
      expect(await t.sample(), isNotNull);
      d.inSession = false;
      d.nextpages.clear();
      expect(await t.sample(), isNull);
      expect(d.nextpages, ['status_wlaninfo_t.gch'], reason: 'صفحة «انتهت الجلسة» تُعرف من أوّل طلب');
    });

    test('المحلِّل: إطارات الواي فاي وحزم المنافذ وحزم الـPON كما في صفحات الجهاز', () {
      final f = ZteOntParse.wifiFrames(d.wlanPage());
      expect(f?.received, d.wlan1RxFrames + d.wlan5RxFrames);
      expect(f?.sent, d.wlan1TxFrames + d.wlan5TxFrames);
      expect(ZteOntParse.lanSentPackets(d.lanPage()), 4 * 33500);
      expect(ZteOntParse.ponReceivedPackets(d.linkPage()), d.ponUniRecv);
      expect(ZteOntParse.ponReceivedPackets("<script>Transfer_meaning('PacketRecv','77');</script>"), 77,
          reason: 'بلا عدّاد الأحاديّ يكفي الكلّيّ');
      expect(ZteOntParse.wifiFrames('<html></html>'), isNull);
      expect(ZteOntParse.lanSentPackets('<html></html>'), isNull);
      expect(ZteOntParse.ponReceivedPackets('<html></html>'), isNull);
    });
  });

  group('إعادة التشغيل بزرّ صفحته', () {
    setUp(() {
      ZteOntService.rebootReplyWait = const Duration(milliseconds: 300);
      addTearDown(() => ZteOntService.rebootReplyWait = const Duration(seconds: 6));
    });

    test('الفحص يعرف أنّ في قائمة الحساب صفحة إعادة التشغيل ⇒ الكرت يُظهر الزرّ، ويُحفظ مع اللقطة', () async {
      final s = (await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'))!;
      final o = (await ZteOntService.fetchOptical(s))!;
      expect(ZteOntService.canReboot(s), isTrue);
      final withIt = o.withReboot(ZteOntService.canReboot(s));
      expect(withIt.canReboot, isTrue);
      expect(OntOpticalInfo.fromJson(withIt.toJson()).canReboot, isTrue);
      expect(OntOpticalInfo.fromJson(o.toJson()).canReboot, isFalse, reason: 'المخزَّن القديم بلا الحقل ⇒ بلا زرّ');
      expect(d.nextpages, isNot(contains('manager_dev_conf_t_user.gch')), reason: 'الفحص لا يفتح صفحة الإدارة — اسمها من القائمة');
    });

    test('الأمر كما يرسله زرّ «Reboot» حرفاً، والجهاز يسكت ويقلع (كالحيّ) ⇒ «أُرسل» بلا انتظار المهلة الكاملة، ولا خروج بعده', () async {
      final sw = Stopwatch()..start();
      final r = await ZteOntService.reboot(d.host, 'agent', 'secret-1');
      expect(r.sent, isTrue);
      expect(r.trace, 'post:receiveTimeout', reason: 'سكوته بعد وصول الطلب هو قبوله');
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
      expect(d.actions.single,
          'IF_ACTION=devrestart&IF_ERRORSTR=SUCC&IF_ERRORPARAM=SUCC&IF_ERRORTYPE=-1288281336&flag=1&_SESSION_TOKEN=${d.pageToken}');
      expect(d.rebooted, isTrue);
      expect(d.factoryReset, isFalse);
      expect(d.logouts, 0, reason: 'الجلسة تموت مع الإقلاع — لا نطرقه وهو يقلع');
    });

    test('⛔ ضبط المصنع (devrestore) لا يخرج منّا بأيّ مسار', () async {
      await ZteOntService.reboot(d.host, 'agent', 'secret-1');
      d.replyMode = 'reply';
      await ZteOntService.reboot(d.host, 'agent', 'secret-1');
      expect(d.actions, hasLength(2));
      expect(d.actions.join(), isNot(contains('devrestore')));
      expect(d.factoryReset, isFalse);
      expect(ZteOntParse.rebootForm(d.mgmtPage()), isNot(contains('devrestore')));
    });

    test('برنامجٌ يردّ بالصفحة و«flag=1» ⇒ «أُرسل»؛ وصفحةٌ تعود بلا القبول ⇒ لم يُرسَل ونخرج', () async {
      d.replyMode = 'reply';
      final ok = await ZteOntService.reboot(d.host, 'agent', 'secret-1');
      expect(ok.sent, isTrue);
      expect(ok.trace, startsWith('post:200'));
      d.replyMode = 'refuse';
      final no = await ZteOntService.reboot(d.host, 'agent', 'secret-1');
      expect(no.sent, isFalse);
      expect(no.issue, isNull);
      expect(d.logouts, 1, reason: 'لم يقلع ⇒ لا تبقى جلستنا مفتوحة على عنوان الوكيل');
    });

    test('حسابٌ قائمته بلا الصفحة المجرَّبة ⇒ لا زرّ في الكرت، ولا يُرسَل شيء', () async {
      d.userAccount = false;
      final s = (await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'))!;
      await ZteOntService.fetchOptical(s);
      expect(ZteOntService.canReboot(s), isFalse, reason: 'لا زرّ يَعِد بما لم يُجرَّب');
      await ZteOntService.logout(s);
      final r = await ZteOntService.reboot(d.host, 'agent', 'secret-1');
      expect(r.sent, isFalse);
      expect(r.trace, 'no-page');
      expect(d.actions, isEmpty);
    });

    test('صفحةٌ لا تعلن أمر devrestart بنفسها، أو تطلب رمزاً لم نجده ⇒ لا إرسال', () async {
      d.declaresRestart = false;
      final r = await ZteOntService.reboot(d.host, 'agent', 'secret-1');
      expect(r.sent, isFalse);
      expect(r.trace, startsWith('no-form'));
      expect(d.actions, isEmpty);
      expect(ZteOntParse.rebootForm(d.mgmtPage().replaceAll('var session_token', 'var other_token')), isNull,
          reason: 'الصفحة تضيف رمزاً لكلّ نموذج ولم نعرفه');
    });

    test('باسورد غلط ⇒ سبب الدخول، ولا تُفتح صفحة الإدارة', () async {
      final r = await ZteOntService.reboot(d.host, 'agent', 'wrong');
      expect(r.sent, isFalse);
      expect(r.issue, ZteLoginIssue.rejected);
      expect(d.nextpages, isEmpty);
      expect(d.actions, isEmpty);
    });

    test('المحلِّل: قيم الحقول كما تملؤها الصفحة (الأخيرة تغلب، و`\\x2d` سالب)، والقبول من صفحة الردّ', () {
      final body = Uri.splitQueryString(ZteOntParse.rebootForm(d.mgmtPage())!);
      expect(body.keys.toList(), ['IF_ACTION', 'IF_ERRORSTR', 'IF_ERRORPARAM', 'IF_ERRORTYPE', 'flag', '_SESSION_TOKEN']);
      expect(body['IF_ERRORTYPE'], '-1288281336');
      expect(ZteOntParse.rebootAccepted(d.mgmtPage()), isFalse, reason: 'flag=NULL قبل الأمر');
      expect(ZteOntParse.rebootAccepted(d.mgmtPage(flag: '1')), isTrue);
      expect(ZteOntParse.rebootAccepted(_FakeHtm.sessionGone), isFalse);
      expect(ZteOntParse.rebootPage(['manager_dev_conf_t.gch', 'status_dev_info_t.gch']), isNull);
      expect(ZteOntParse.rebootPage(['manager_dev_conf_t_user.gch']), 'manager_dev_conf_t_user.gch');
    });
  });
}

/// HS8546V2 وهميّ بشكل الجهاز الحيّ (١٤ نوفمبر): دخولٌ برمز جلسة (الحقل + الكوكي معاً)، جلسةٌ بعنوان الطالب، صفحة «Session
/// timeout» لما يُطلب بلا جلسة، وقائمةٌ بصفحات الحالة والإعداد، وعدّادات واي فاي/منافذ/PON يحرّكها الاختبار.
class _FakeHtm {
  late HttpServer server;
  bool inSession = false;
  bool oddTokenForm = false;
  int _logintoken = 1;
  int _tokenSeq = 1000000000000007;
  String? issuedToken;
  String? _issuedLogintoken;
  bool _stopped = false;

  final posts = <({String body, String? cookie})>[];
  final paths = <String>[];
  final nextpages = <String>[];

  // إعادة التشغيل: حساب user (صفحته `…_user.gch`) أو حسابٌ آخر (اسمٌ لم يُجرَّب)؛ والردّ: silent (الحيّ: يسكت ويقلع) ·
  // reply (الصفحة و`flag=1`) · refuse (الصفحة كما هي).
  bool userAccount = true;
  bool declaresRestart = true;
  String replyMode = 'silent';
  final actions = <String>[];
  bool rebooted = false;
  bool factoryReset = false;
  int logouts = 0;
  final pageToken = 'A2000000000000011';
  final _held = <HttpResponse>[];

  // عدّادات كالحيّة: واي فاي ٢٫٤ (wlan1) و٥ (wlan5)، والمنافذ مفصولة، وحزم الـPON.
  int wlan1RxBytes = 2814688572, wlan1RxFrames = 14218015, wlan1TxBytes = 668949464, wlan1TxFrames = 1207663;
  int wlan5RxBytes = 589455260, wlan5RxFrames = 973985, wlan5TxBytes = 39992390, wlan5TxFrames = 73952;
  int ponUniRecv = 41868128;

  String get host => '127.0.0.1:${server.port}';

  /// ترافيك نبضةٍ واحدة: إطاراتٌ من العملاء وإليهم (على wlan1)، وحزمٌ دخلت من الـPON.
  void traffic({required int fromClients, required int toClients, required int ponIn}) {
    wlan1RxFrames += fromClients;
    wlan1RxBytes += fromClients * 200;
    wlan1TxFrames += toClients;
    wlan1TxBytes += toClients * 500;
    ponUniRecv += ponIn;
  }

  void resetWlan() {
    wlan1RxBytes = wlan1RxFrames = wlan1TxBytes = wlan1TxFrames = 0;
    wlan5RxBytes = wlan5RxFrames = wlan5TxBytes = wlan5TxFrames = 0;
  }

  List<String> get _menu => [..._statusMenu, userAccount ? 'manager_dev_conf_t_user.gch' : 'manager_dev_conf_t.gch'];

  /// صفحة «Device Management» لحساب user كما على الحيّ: نموذج `fSubmit` وسكربتا «Reboot» و«Restore» (الثاني ضبط مصنع).
  String mgmtPage({String flag = 'NULL'}) => _content(
      "<FORM NAME=fSubmit ID=fSubmit METHOD='POST' action=>\n"
      "<INPUT type='hidden' name=IF_ACTION ID=IF_ACTION value=''>\n"
      "<script language=javascript>Transfer_meaning('IF_ACTION','');</script>\n"
      "<INPUT type='hidden' name=IF_ERRORSTR ID=IF_ERRORSTR value=''>\n"
      "<script language=javascript>Transfer_meaning('IF_ERRORSTR','SUCC');</script>\n"
      "<INPUT type='hidden' name=IF_ERRORPARAM ID=IF_ERRORPARAM value=''>\n"
      "<script language=javascript>Transfer_meaning('IF_ERRORPARAM','SUCC');</script>\n"
      "<INPUT type='hidden' name=IF_ERRORTYPE ID=IF_ERRORTYPE value=''>\n"
      "<script language=javascript>Transfer_meaning('IF_ERRORTYPE','\\x2d1');</script>\n"
      "<script language=javascript>Transfer_meaning('IF_ERRORSTR','SUCC');</script>\n"
      "<script language=javascript>Transfer_meaning('IF_ERRORPARAM','SUCC');</script>\n"
      "<script language=javascript>Transfer_meaning('IF_ERRORTYPE','\\x2d1288281336');</script>\n"
      "<INPUT type='hidden' name=flag ID=flag value=''>\n"
      "<script language=javascript>Transfer_meaning('flag','$flag');</script>\n"
      '</FORM>\n<script language="javascript">\n'
      'function msgCallback()\n{\nDisableALL();\nsetValue("IF_ACTION", "${declaresRestart ? 'devrestart' : 'devsomething'}");\n'
      'setValue("flag", "1");\ngetObj("fSubmit").submit();\n}\n'
      'function msgCallback2()\n{\nDisableALL();\nif("1" == getValue("Frm_FACTORYMODE"))\n{\n'
      'setValue("IF_ACTION", "devrestoreAll");\n}\nelse\n{\nsetValue("IF_ACTION", "devrestore");\n}\n'
      'setValue("flag", "2");\ngetObj("fSubmit").submit();\n}\n</SCRIPT>\n'
      '<input id="Submit1" name="Submit1" type="button" class="button3" value="Reboot"  onClick="DevRestartSubmit();"/>\n'
      '<form name="flogout" id="flogout" method="post" action="/" target="_top">'
      '<input type="hidden" name="logout" id="logout" value="" ></form>\n'
      '<script>function addToken2AllForms(){function doAddLogic(){var session_token = "$pageToken";\n'
      'tokenInput.setAttribute("name", "_SESSION_TOKEN");}}</script>\n');

  static const _statusMenu = [
    'status_dev_info_t.gch',
    'status_wlaninfo_t.gch',
    'status_ponlan_info_t.gch',
    'epon_status_link_info_t.gch',
    'pon_status_alarm_info_t.gch',
    'net_wlan_conf_t_user.gch',
    'net_wlan_essid_t.gch',
    'net_lanmode_t.gch',
    'manager_user_conf_t.gch',
  ];

  /// صفحة الدخول كما على الجهاز الحيّ (مختصرة): الرمز في `dosubmit`، و`Frm_Logintoken` يزيد مع كلّ صفحة.
  String loginPage({String error = ''}) {
    _logintoken++;
    _tokenSeq += 7919;
    issuedToken = 'A$_tokenSeq';
    _issuedLogintoken = '$_logintoken';
    final submit = oddTokenForm
        ? 'function dosubmit()\n{\nvar k = mkSession(${_tokenSeq % 1000}, "x${_tokenSeq % 97}");\n'
            'getObj("_SESSION_TOKEN").value = k;\ngetObj("Frm_Logintoken").value = "$_logintoken";\ndocument.fLogin.submit();\n}\n'
        : 'function dosubmit()\n{\n{\nvar token = "$issuedToken";\nvar session = getObj("_SESSION_TOKEN");\n'
            'session.value = token;\ngetObj("LoginId").disabled = true;\n\n'
            'getObj("Frm_Logintoken").value = "$_logintoken";\nsetCookie("session_cookie",token);\n'
            'document.fLogin.submit();\n}\n}\n';
    return '<SCRIPT LANGUAGE="javascript" src ="./js/common.js"></SCRIPT>\n<html><head><title>HS8546V2</title>\n<script>\n'
        'function setTime()\n{\nmaxtime = Math.min(60, 0 + 60 - 85284);\n}\n</script>\n</head>\n<body>\n'
        '<form name="fLogin" id="fLogin" method="post"  onsubmit="return false;" action="">\n'
        '<input type="hidden" name="_lang" id="_lang" value="" disabled>\n'
        '<input type="hidden" name="frashnum" id="frashnum" value="">\n'
        '<input type="hidden" name="action" id="action" value="login">\n'
        '<input type="hidden" name="Frm_Logintoken" id="Frm_Logintoken" value="">\n'
        '<input type="hidden" name="_SESSION_TOKEN" id="_SESSION_TOKEN" value="">\n'
        '<input type="text" name="username" id="username" class="font_chara" />\n'
        '<input name="Password" type="password" id="password" class="font_chara" autocomplete="off"/>\n'
        '</form>\n</body>\n</html>\n<script>\n\ngetObj("username").value = "user";\nvar UserStr = "user";\n\n$error'
        'function SetDisabled()\n{\ngetObj("errmsg").innerHTML = "You have input the wrong username or password for three '
        'times. Please try again a minute later.";\n}\n$submit</script>\n';
  }

  static const _wrong = 'getObj("errmsg").innerHTML = "User information is error, please input again.";\n\n'
      'alert("User information is error, please input again.");\n\n';

  /// ما يردّه الجهاز لأيّ صفحةٍ تُطلب بلا جلسة (٦٢٧ بايتاً على الحيّ).
  static const sessionGone = '\n<html>\n<head>\n<meta http-equiv="pragma" content="no-cache">\n'
      '<meta http-equiv="cache-control" content="no-cache, must-revalidate">\n'
      '<meta http-equiv="content-type" content="text/html; charset=utf-8" />\n'
      '<script type="text/javascript" src="js/jquery-1.10.2.min.js"></script>\n<title>HS8546V2</title>\n<script>\n'
      'function logout_redirect()\n{\n\nalert("Session timeout, please login again.");\n\n'
      'var jqxhr=\$.post("setlang.gch",\n{\n"logout" : 1,\n},\nfunction(data, status) {\nif (status==false)\n{\nflag=0;\n}\n'
      'else\n{\ntop.location.href = "http://192.168.101.1";\n}\n});\n}\n</script>\n</head>\n<body>\n<script>\n'
      'logout_redirect();\n</script>\n</body>\n</html>\n';

  /// حشوة القالب: كلّ صفحة محتوى على الجهاز تحمل القالب كاملاً (~١٠٠ ك.ب) — هنا ما يكفي لتمييزها عن صفحة النهاية.
  static final _chrome = '<!-- ${'template ' * 700} -->\n';

  String _content(String body) => '<html><head><title>HS8546V2</title></head><body>\n$_chrome$body</body></html>\n';

  String _template() => _content([
        for (final n in _menu) "<a href=\"getpage.gch?pid=1002&nextpage=$n\">$n</a>\n",
        '<form name="flogout" id="flogout" method="post" action="/" target="_top">'
            '<input type="hidden" name="logout" id="logout" value="" ></form>\n',
        '<script>function addToken2AllForms(){var session_token = "A2000000000000013";}</script>\n',
      ].join());

  String linkPage() => _content(
      "<script language=javascript>Transfer_meaning('FecEnable','0');</script>\n"
      "<script language=javascript>Transfer_meaning('PacketSent','15604984');</script>\n"
      "<script language=javascript>Transfer_meaning('PacketRecv','${ponUniRecv + 114343}');</script>\n"
      "<script language=javascript>Transfer_meaning('UniPacketSent','0');</script>\n"
      "<script language=javascript>Transfer_meaning('UniPacketRecv','$ponUniRecv');</script>\n"
      '<td id="Frm_RxPower" name="Frm_RxPower" class="tdright">\n<font id="Fnt_RxPower" name="Fnt_RxPower"></font>\n</td>\n'
      '<td id="Frm_TxPower" name="Frm_TxPower" class="tdright">\n<font id="Fnt_TxPower" name="Fnt_TxPower"></font>\n</td>\n'
      '<td class="tdleft">Optical Module Supply Voltage(uV)</td>\n'
      '<td id="Frm_Volt" name="Frm_Volt" class="tdright">3166000</td>\n'
      '<td id="Frm_Current" name="Frm_Current"  class="tdright"></td>\n'
      '<td id="Frm_Temp" name="Frm_Temp" class="tdright">29</td>\n'
      '<script>\nfunction doRxTxPowerShow()\n{\nvar LosInfo = "0";\nvar RxPower = "-186600";\nvar TxPower = "26000";\n'
      'var Current =  "14600";\n\nRxPower = parseFloat(RxPower/10000).toFixed(1);\n}\n</script>\n');

  static String _row(String table, List<Object> cells) => [
        'var RowNum = 0;\n',
        for (var i = 0; i < cells.length; i++)
          'getObj("${table}_"+ RowNum +"_${i + 1}_table").innerHTML = "${cells[i]}";\n',
      ].join();

  String wlanPage() => _content('<script>\n${[
        _row('Table_wlanstat', [1, 'Home-2G', wlan1RxBytes, wlan1RxFrames, wlan1TxBytes, wlan1TxFrames]),
        _row('Table_wlanstat', [2, 'WIFI-SSID2', 0, 0, 0, 0]),
        _row('Table_wlanstat', [5, 'Home-5G', wlan5RxBytes, wlan5RxFrames, wlan5TxBytes, wlan5TxFrames]),
        _row('Table_wlanssid', [1, 'Home-2G', 'Configured', 'WPA2-PSK', 'AES']),
      ].join()}</script>\n');

  String lanPage() => _content('<script>\n${[
        for (var p = 1; p <= 4; p++)
          _row('Table_laninterface', ['Network port$p', 'Half Duplex', 'Auto', 'Equipment disconnected', 0, 0, 3278299, 33500]),
      ].join()}</script>\n');

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      paths.add('${req.method} ${req.uri.path}');
      final res = req.response;
      res.headers.set('Server', 'Mini web server 1.0 ZTE corp 2005.');
      res.headers.contentType = ContentType.html;
      void html(String body) => res.write(body);
      final path = req.uri.path;
      if (req.method == 'POST' && path == '/') {
        final body = await utf8.decoder.bind(req).join();
        final f = Uri.splitQueryString(body);
        if (f['logout'] == '1') {
          logouts++;
          inSession = false;
          res.statusCode = 302;
          res.headers.set('Location', '/');
          await res.close();
          return;
        }
        final cookie = req.headers.value('cookie');
        posts.add((body: body, cookie: cookie));
        // الحقل والكوكي معاً برمز آخر صفحة — أيٌّ منهما وحده يُردّ كباسوردٍ غلط (جُرِّب حيّاً).
        final tokenOk = issuedToken != null &&
            f['_SESSION_TOKEN'] == issuedToken &&
            (cookie ?? '').split('; ').contains('session_cookie=$issuedToken');
        final ok = tokenOk &&
            f['action'] == 'login' &&
            f['Frm_Logintoken'] == _issuedLogintoken &&
            f['username'] == 'agent' &&
            f['Password'] == 'secret-1';
        if (ok) {
          inSession = true;
          res.statusCode = 302;
          res.headers.set('Location', '/start.ghtml'); // بلا Set-Cookie: الجلسة بعنوان الطالب
        } else {
          html(loginPage(error: _wrong));
        }
        await res.close();
        return;
      }
      if (req.method == 'POST' && path == '/getpage.gch' && inSession) {
        // أمرٌ على صفحة الإدارة: يُقبل برمز الصفحة فقط، كنموذجها.
        final body = await utf8.decoder.bind(req).join();
        final f = Uri.splitQueryString(body);
        actions.add(body);
        final act = f['IF_ACTION'] ?? '';
        if (act.startsWith('devrestore')) factoryReset = true;
        final accepted = act == 'devrestart' && f['flag'] == '1' && f['_SESSION_TOKEN'] == pageToken && replyMode != 'refuse';
        if (accepted) {
          rebooted = true;
          inSession = false;
          if (replyMode == 'silent') {
            _held.add(res); // كالحيّ: لا ردّ — الجهاز يقلع
            return;
          }
        }
        html(mgmtPage(flag: accepted ? '1' : 'NULL'));
        await res.close();
        return;
      }
      if (path == '/') {
        html(loginPage());
      } else if (path == '/start.ghtml') {
        // الإطار يُخدَم بلا جلسة أيضاً — ولا قائمة فيه.
        html('<html><head><title>HS8546V2</title></head><body>'
            '<iframe src="top.gch" name="topFrame"></iframe>'
            '<iframe src="template.gch?pid=1002&nextpage=status_dev_info_t.gch" name="mainFrame"></iframe></body></html>');
      } else if (!inSession) {
        if (path == '/getpage.gch') nextpages.add(req.uri.queryParameters['nextpage'] ?? '');
        html(sessionGone);
      } else if (path == '/template.gch') {
        html(_template());
      } else if (path == '/getpage.gch') {
        final name = req.uri.queryParameters['nextpage'] ?? '';
        nextpages.add(name);
        html(switch (name) {
          'epon_status_link_info_t.gch' => linkPage(),
          'status_wlaninfo_t.gch' => wlanPage(),
          'status_ponlan_info_t.gch' => lanPage(),
          'manager_dev_conf_t_user.gch' when userAccount => mgmtPage(),
          _ => _template(),
        });
      } else {
        res.statusCode = 404;
      }
      await res.close();
    });
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await server.close(force: true);
  }
}

/// خادم التطبيق الوهميّ: افتراضات الأجهزة والتشخيص.
class _FakeApi implements HttpClientAdapter {
  Map<String, Object?> defaults = {};
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(o);
    final Object data = o.uri.path == '/api/admin/device-defaults' ? {'success': true, 'defaults': defaults} : {'success': true};
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}
