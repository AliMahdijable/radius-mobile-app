import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/core/net/zte_ont_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// دخول جهاز المشترك ZTE MH80 (٢٧ أكتوبر، المالك: «خليت يوزر وباسورد وميجلب شي… شوفلي التصحيح من السيرفر لو من
/// التطبيق؟»): الجهاز يصل والتعرّف يعمل، والعطب كان بالتطبيق — كلّ فشلٍ (حتى انقطاع) يُحفظ «اعتماداتٍ مرفوضة» فلا تُعاد،
/// و«حفظ وفحص الجهاز» لا يمسح الرفض حين الـIP من الساس، والكرت يقول «لم يُتمكّن من الوصول» لكلّ سبب.
///
/// جهازٌ وهميّ على 127.0.0.1 (خادم HTTP حقيقيّ) بنفس شكل صفحة الجهاز الحيّ؛ الاعتمادات هنا وهميّة.
void main() {
  late _FakeMh80 d;

  setUp(() async {
    d = _FakeMh80();
    await d.start();
  });

  tearDown(() => d.stop());

  group('الدخول', () {
    test('اعتماداتٌ صحيحة ⇒ جلسة، والكوكي يصل صفحة الضوء', () async {
      final s = await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1');
      expect(s, isNotNull);
      final o = await ZteOntService.fetchOptical(s!);
      expect(o?.rxPower, '-18.6');
      expect(o?.vendor, 'zte');
      expect(d.pageCookie, 'SID=s1');
      expect(ZteOntService.lastIssue(d.host), isNull);
    });

    test('دخولٌ بلا كوكي (جلسةٌ بالعنوان) ⇒ ناجح، وصفحة الضوء بلا ترويسة كوكي فارغة', () async {
      d.setCookie = false;
      final s = await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1');
      expect(s, isNotNull, reason: 'التحويل إلى start.ghtml هو النجاح — الكوكي ليس شرطاً');
      expect(await ZteOntService.fetchOptical(s!), isNotNull);
      expect(d.pageCookie, isNull);
    });

    test('اعتمادٌ غلط ⇒ «رُفض» ويُحفظ فلا يُعاد؛ النسيان («حفظ وفحص») يعيده مرّة', () async {
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'wrong'), isNull);
      expect(ZteOntService.lastIssue(d.host)?.issue, ZteLoginIssue.rejected);
      expect(d.posts, hasLength(1));
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'wrong'), isNull);
      expect(d.posts, hasLength(1), reason: 'المرفوض لا يُعاد — ثلاث محاولاتٍ غلط تقفل الجهاز دقيقة');
      ZteOntService.forget(d.host);
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'wrong'), isNull);
      expect(d.posts, hasLength(2));
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNotNull, reason: 'اعتماداتٌ غيرها تُجرَّب فوراً');
    });

    test('انقطاع الاتّصال عند الإرسال ليس رفضاً ⇒ الفحص التالي يحاول', () async {
      d.dropPost = true;
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNull);
      expect(ZteOntService.lastIssue(d.host)?.issue, ZteLoginIssue.unreachable);
      d.dropPost = false;
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNotNull,
          reason: 'كان يُحفظ مرفوضاً فلا يُعاد طول الجلسة');
    });

    test('قافلٌ ⇒ لا إرسال، والباقي من عدّاد الصفحة نفسها', () async {
      d.lockAt = 402900; // 402900 + 60 - 402930 = 30
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNull);
      final i = ZteOntService.lastIssue(d.host)!;
      expect(i.issue, ZteLoginIssue.locked);
      expect(i.lockLeft, 30);
      expect(d.posts, isEmpty, reason: 'كلّ محاولةٍ على جهازٍ قافل تُحسب عليه');
    });

    test('اعتماداتٌ دخلت قبل ورُفضت الآن ⇒ «مشغول» لا «رُفض»، ولا تُحفظ', () async {
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNotNull);
      d.sessionOpen = true;
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNull);
      expect(ZteOntService.lastIssue(d.host)?.issue, ZteLoginIssue.busy);
      d.sessionOpen = false;
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNull,
          reason: 'مرّةٌ بالدقيقة على الأكثر — جلسة الترافيك تعيد كلّ ١٢ ثانية وكلّ رفضٍ قد يُحسب على القفل');
      expect(d.posts, hasLength(2));
      expect(ZteOntService.lastIssue(d.host)?.trace, 'cooldown');
      ZteOntService.forget(d.host); // «حفظ وفحص» أو انقضاء الدقيقة
      expect(await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1'), isNotNull,
          reason: 'جلسةٌ مفتوحة لا تقفل الوكيل عن جهازه باعتماداتٍ صحيحة');
    });

    test('D401: صفحة EPON غائبة ⇒ تُجرَّب التالية، والضوء بصيغة Transfer_meaning بالـdBm نفسه', () async {
      d.pages['epon_status_link_info_t.gch'] = (404, 'Not Found');
      d.pages['gpon_status_link_info_t.gch'] = (404, 'Not Found');
      d.pages['pon_status_link_info_t.gch'] = (
        200,
        "<html><head><title>D401</title></head><body><script>Transfer_meaning('RxPower','-31.20');"
            "Transfer_meaning('TxPower','2.41');</script></body></html>"
      );
      final s = await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1');
      final o = await ZteOntService.fetchOptical(s!);
      expect(o?.rxPower, '-31.2', reason: 'كان أوّل اسمٍ غائب يوقف البحث');
      expect(o?.txPower, '2.4');
      expect(o?.model, 'D401');
    });

    test('صفحة الدخول بدل الضوء (الجلسة انتهت) ⇒ يتوقّف، والأثر يقول ما جُرِّب بلا قيم', () async {
      d.pages['epon_status_link_info_t.gch'] = (404, 'Not Found');
      d.pages['gpon_status_link_info_t.gch'] =
          (200, '<html><form name="fLogin"><input name="Frm_Logintoken"></form></html>');
      final s = await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1');
      expect(await ZteOntService.fetchOptical(s!), isNull);
      final trace = ZteOntService.lastPageTrace(s)!;
      expect(trace, startsWith('st:404 '), reason: 'start.ghtml أوّلاً كما يفتحها المتصفّح');
      expect(trace, contains('epon_link:404'));
      expect(trace, contains('gpon_link:200L'));
      expect(trace.split(' '), hasLength(3), reason: 'لا محاولة بعد انتهاء الجلسة');
      expect(ZteOntService.lastReadUnknown(s), isFalse, reason: 'صفحةٌ لم ترجع ليست صيغةً جديدة');
    });

    test('شكل قيمة الضوء للتشخيص بلا القيمة', () {
      expect(ZteOntParse.rxForm('var RxPower = "-186300";'), 'var:-999999');
      expect(ZteOntParse.rxForm("Transfer_meaning('RxPower','-31.20');"), 'tm:-99.99');
      expect(ZteOntParse.rxForm('<td id="Frm_RxPower">-21.5</td>'), 'frm:-99.9');
      expect(ZteOntParse.rxForm('<b>RxPower</b>'), 'rx?</b>');
      expect(ZteOntParse.rxForm('<td>RxPower:</td><td>-21.50 dBm</td>'), 'rx?:</td><td>-99.99_dBm</td',
          reason: 'شكل الصيغة بأرقامٍ مقنّعة');
      expect(ZteOntParse.rxForm('<html></html>'), '-');
    });

    test('صيغٌ قريبة من MH80 تُقرأ: تنصيصٌ مفرد، وحالة أحرف، وخليّةٌ تتبعها dBm', () {
      expect(ZteOntParse.optical("var rxpower = '-215000'; var txpower = '23000';")?.rxPower, '-21.5');
      expect(ZteOntParse.optical('<td id="Frm_RxPower">-21.50 dBm</td><td id="Frm_TxPower">2.3 dBm</td>')?.txPower, '2.3');
      expect(ZteOntParse.optical('<td id="Frm_RxPowerMax">-8</td>'), isNull, reason: 'اسمٌ أطول ليس قدرة الاستقبال');
    });

    test('صفحة الضوء باسمٍ آخر ⇒ تُكتشف من أسماء صفحات الجهاز، ولا تُفتح صفحة إعدادات', () async {
      const template = '<html><head><title>D401</title></head><body><script>'
          "menu('getpage.gch?pid=1002&nextpage=status_dev_info_t.gch');"
          "menu('getpage.gch?pid=1002&nextpage=pon_conf_t.gch');"
          "menu('getpage.gch?pid=1002&nextpage=pon_optical_info_t.gch');"
          '</script></body></html>';
      for (final p in ['epon_status_link_info_t.gch', 'gpon_status_link_info_t.gch', 'pon_status_link_info_t.gch']) {
        d.pages[p] = (200, template);
      }
      d.pages['pon_optical_info_t.gch'] =
          (200, '<html><title>D401</title><td id="Frm_RxPower">-24.10 dBm</td><td id="Frm_TxPower">2.20 dBm</td></html>');
      final s = await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1');
      final o = await ZteOntService.fetchOptical(s!);
      expect(o?.rxPower, '-24.1');
      expect(o?.model, 'D401');
      expect(d.nextpages, contains('pon_optical_info_t.gch'));
      expect(d.nextpages, isNot(contains('pon_conf_t.gch')), reason: 'صفحات الإعدادات لا تُفتح');
      expect(d.nextpages, isNot(contains('status_dev_info_t.gch')), reason: 'ليست صفحة ضوء');
    });

    test('الصفحات تُجاب ولا ضوء فيها ⇒ «صيغةٌ جديدة»، والأثر أسماءٌ بلا قيم', () async {
      d.strictPages = true;
      const template = '<html><head><title>D401</title></head><body><script>var RxOptPwr = "-21.5";'
          "menu('pon_status_optic_info_t.gch');</script><td id=\"Frm_TxOptPwr\">2.1</td></body></html>";
      for (final p in ['epon_status_link_info_t.gch', 'gpon_status_link_info_t.gch', 'pon_status_link_info_t.gch']) {
        d.pages[p] = (200, template);
      }
      final s = await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1');
      expect(await ZteOntService.fetchOptical(s!), isNull);
      expect(ZteOntService.lastReadUnknown(s), isTrue);
      final trace = ZteOntService.lastPageTrace(s)!;
      expect(trace, contains('epon_link:200/-/0.2k'));
      expect(trace, contains('pon_optic:404'), reason: 'المرشّحة من القائمة جُرِّبت');
      final info = ZteOntService.lastPageInfo(s)!;
      expect(info, contains('t=D401'));
      expect(info, contains('pg=epon_link#0.2k:v:RxOptPwr'), reason: 'حقول كلّ صفحةٍ أجابت بلا ضوء — حقلٌ سالبٌ = الضوء');
      expect(info, contains('c=pon_status_optic_info'), reason: 'المرشّحة للضوء');
      expect(info, contains('Frm_TxOptPwr'), reason: 'اسمٌ يشبه الضوء من n=');
      expect(info, contains('s=epon_status_link_info,gpon_status_link_info,pon_status_link_info'),
          reason: 'صفحات الحالة المعروفة فقط (المرشّحة في c=)');
      expect('$trace $info', isNot(contains('21')), reason: 'لا قيمة في الأثر');
    });

    test('الـpid الصحيح لكلّ صفحةٍ من روابط القائمة (D401: بـ1002 الثابت صفحة خطأ)', () {
      const menu = '<a href="getpage.gch?pid=1003&nextpage=pon_status_optic_info_t.gch">الضوء</a>'
          'getObj().src = "getpage.gch?pid=1005&amp;nextpage=status_dev_info_t.gch";';
      final links = ZteOntParse.pageLinks(menu);
      expect(links['pon_status_optic_info_t.gch'], '1003');
      expect(links['status_dev_info_t.gch'], '1005', reason: 'يفكّ &amp;');
      expect(links['missing_t.gch'], isNull);
    });

    test('صفحة الضوء بـpidها الصحيح من القائمة (غير 1002) ⇒ تُقرأ', () async {
      d.strictPages = true; // بلا تطابقٍ دقيق ⇒ 404
      d.pages['epon_status_link_info_t.gch'] = (
        200,
        '<html><title>D401</title>'
            '<a href="getpage.gch?pid=1007&nextpage=pon_status_optic_t.gch">ضوء</a></html>'
      );
      // الصفحة الصحيحة لا تُخدَم إلّا بـpid=1007.
      d.pagePid['pon_status_optic_t.gch'] = '1007';
      d.pages['pon_status_optic_t.gch'] =
          (200, '<html><title>D401</title><td id="Frm_RxPower">-23.40</td><td id="Frm_TxPower">2.10</td></html>');
      final s = await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1');
      final o = await ZteOntService.fetchOptical(s!);
      // الصفحة لا تُخدَم إلّا بـpid=1007، فنجاح القراءة دليلٌ أنّ الـpid الصحيح من القائمة استُعمل.
      expect(o?.rxPower, '-23.4');
      expect(d.nextpages, contains('pon_status_optic_t.gch'));
    });

    test('تلميحات الضوء: حقلٌ سالب ولو باسمٍ غريب، لا «‎-1» الافتراضيّة، والقيم تُترك', () {
      const page = '<html><script>var M0 = "-1"; var PonRecv = "-25.34"; var Sig = -0310;</script>'
          "<td id=\"dev_light_a\">-27.5</td><td id=\"up\">120</td>SetVal('x', '-3.14');</html>";
      final g = ZteOntParse.opticalHints(page);
      expect(g, contains('v:PonRecv'));
      expect(g, contains('c:dev_light_a'));
      expect(g, contains('f:SetVal'));
      expect(g, isNot(contains('v:M0')), reason: '«‎-1» قيمةٌ افتراضيّة لا ضوء');
      expect(g, isNot(contains('c:up')), reason: 'قيمةٌ موجبة ليست قدرة استقبال');
      expect(g.join(), isNot(contains('25')), reason: 'أسماءٌ بلا قيم');
    });

    test('مفردات الحقول الرقميّة: حقلٌ موجبٌ بغير اسم ضوءٍ يظهر، والشبكة/الإعدادات تُستبعد، بلا قيم', () {
      const page = '<html><script>var OnuRecv = "253"; var Temperature = "45"; var VlanId = "33"; var PortMode = "2";'
          "Transfer_meaning('LinkQual','7');</script><td id=\"dev_reg_status\">1</td></html>";
      final v = ZteOntParse.numericNames(page);
      expect(v, contains('v:OnuRecv'), reason: 'قيمةٌ موجبةٌ قد تكون الضوء (‎-25.3 ⇒ 253)');
      expect(v, contains('v:Temperature'));
      expect(v, contains('t:LinkQual'));
      expect(v, isNot(contains('v:VlanId')), reason: 'شبكة');
      expect(v, isNot(contains('v:PortMode')), reason: 'إعداد');
      expect(v, isNot(contains('dev_reg_status')), reason: 'status مُستبعد');
      expect(v.join(), isNot(contains('253')), reason: 'أسماءٌ بلا قيم');
    });

    test('الضوء في صفحة حالةٍ أخرى (لا اسم ضوءٍ في قائمته) ⇒ يُبحث فيها، وتُحفظ للقراءة التالية', () async {
      d.strictPages = true;
      const template = '<html><head><title>D401</title></head><body><script>'
          "menu('status_wlaninfo_t.gch');menu('status_dev_info_t.gch');menu('sys_reboot_t.gch');menu('net_wan_conf_t.gch');"
          '</script></body></html>';
      d.pages['epon_status_link_info_t.gch'] = (200, template);
      d.pages['status_wlaninfo_t.gch'] = (200, template);
      d.pages['status_dev_info_t.gch'] =
          (200, "<html><title>D401</title><script>Transfer_meaning('RxPower','-31.02');</script></html>");
      final s = await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1');
      expect((await ZteOntService.fetchOptical(s!))?.rxPower, '-31.0');
      expect(d.nextpages, isNot(contains('sys_reboot_t.gch')), reason: 'لا أوامر');
      expect(d.nextpages, isNot(contains('net_wan_conf_t.gch')), reason: 'لا إعدادات');
      expect(d.nextpages, isNot(contains('status_wlaninfo_t.gch')), reason: 'معلومات الجهاز أوّلاً والبحث يقف عند الضوء');
      d.nextpages.clear();
      expect((await ZteOntService.fetchOptical(s))?.rxPower, '-31.0');
      expect(d.nextpages, ['status_dev_info_t.gch'], reason: 'الصفحة المحفوظة أوّلاً بلا بحث');
    });

    test('بحثٌ لم يجد ⇒ لا يُعاد قبل نصف ساعة، و«حفظ وفحص» يعيده', () async {
      d.strictPages = true;
      const template = "<html><title>D401</title><script>menu('status_dev_info_t.gch');</script></html>";
      d.pages['epon_status_link_info_t.gch'] = (200, template);
      d.pages['status_dev_info_t.gch'] = (200, template);
      final s = await ZteOntService.loginConfigured(d.host, 'agent', 'secret-1');
      expect(await ZteOntService.fetchOptical(s!), isNull);
      expect(d.nextpages, contains('status_dev_info_t.gch'));
      d.nextpages.clear();
      expect(await ZteOntService.fetchOptical(s), isNull);
      expect(d.nextpages, isNot(contains('status_dev_info_t.gch')));
      expect(ZteOntService.lastPageTrace(s), endsWith('scan:later'));
      ZteOntService.forget(d.host);
      d.nextpages.clear();
      await ZteOntService.fetchOptical(s);
      expect(d.nextpages, contains('status_dev_info_t.gch'));
    });

    test('صفحات الحالة: معلومات الجهاز أوّلاً، ولا إعدادات ولا أوامر ولا ما يُجرَّب قبلها', () {
      final p = ZteOntParse.statusPages([
        'status_wlaninfo_t.gch',
        'status_dev_info_t.gch',
        'pon_status_alarm_t.gch',
        'reboot_t.gch',
        'status_user_info_t.gch',
        'net_wan_conf_t.gch',
        'epon_status_link_info_t.gch',
        'status_pon_opt_info_t.gch',
      ]);
      expect(p, ['status_dev_info_t.gch', 'status_wlaninfo_t.gch']);
    });

    test('عدّاد القفل كما على MH80 الحيّ', () {
      expect(ZteOntParse.lockLeft('maxtime = Math.min(60, 0 + 60 - 402930);'), isNull);
      expect(ZteOntParse.lockLeft('maxtime = Math.min(60, 402900 + 60 - 402930);'), 30);
      expect(ZteOntParse.lockLeft('<html>بلا عدّاد</html>'), isNull);
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
          ..clear()
          ..addAll(interceptors);
      });
      DeviceProbeApi.invalidateAdminDefaults();
    });

    test('جهاز ZTE ⇒ القراءة من فرع ZTE، وطلبات هواوي لا تطرقه', () async {
      api.defaults = {'ontUsername': 'agent', 'ontPassword': 'secret-1'};
      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect(snap?.ont?.vendor, 'zte');
      expect(snap?.ont?.rxPower, '-18.6');
      expect(d.paths.where((p) => p.contains('GetRandCount') || p.contains('login.cgi')), isEmpty);
      expect(DeviceProbeApi.issueFor(ip: d.host), isNull);
    });

    test('بلا يوزر من الوكيل ⇒ لا دخول على ZTE بافتراضٍ من عندنا، والسبب «يحتاج يوزر وباسورد»', () async {
      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect(snap, isNull);
      expect(d.posts, isEmpty);
      expect(DeviceProbeApi.issueFor(ip: d.host)?.issue, ProbeIssue.needsCredentials);
    });

    test('رفضٌ ثمّ «حفظ وفحص» بنفس الاعتمادات ⇒ يحاول مرّةً أخرى، والتشخيص يصل بلا اعتمادات', () async {
      api.defaults = {'ontUsername': 'agent', 'ontPassword': 'wrong-pass'};
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      expect(DeviceProbeApi.issueFor(ip: d.host)?.issue, ProbeIssue.loginRejected);
      await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect(d.posts, hasLength(1), reason: 'التحديث العاديّ لا يعيد المرفوض');
      await DeviceProbeApi.probe(fallbackIp: d.host, force: true, retryLogin: true);
      expect(d.posts, hasLength(2), reason: '«حفظ وفحص الجهاز» يحاول ولو بقي الـIP من الساس');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final diag = api.requests.where((r) => r.uri.path == '/api/client-diag').toList();
      expect(diag, hasLength(1), reason: 'التشخيص للمحاولة الصريحة وحدها');
      final body = diag.single.data as Map;
      expect(body['code'], 'loginRejected');
      expect('${body['message']}', contains('post:200'));
      expect(jsonEncode(body), isNot(contains('wrong-pass')));
      expect(jsonEncode(body), isNot(contains('agent')));
    });

    test('ZTE بطيء بصفحة الضوء ⇒ يُمهَل بدل أن يُقطع بلا سبب (أوّل «حفظ وفحص» على MH80)', () async {
      DeviceProbeApi.debugCaps(probe: const Duration(milliseconds: 600), zteExtra: const Duration(seconds: 3));
      addTearDown(() => DeviceProbeApi.debugCaps(probe: const Duration(seconds: 15), zteExtra: const Duration(seconds: 15)));
      api.defaults = {'ontUsername': 'agent', 'ontPassword': 'secret-1'};
      d.pageDelay = const Duration(milliseconds: 1500);
      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, force: true, retryLogin: true);
      expect(snap?.ont?.rxPower, '-18.6', reason: 'كان يُقطع عند المهلة وصفحة الضوء في الطريق');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final diag = api.requests.where((r) => r.uri.path == '/api/client-diag').single.data as Map;
      expect(diag['code'], 'ok');
    });

    test('جهازٌ لا يجاوب لا يُمهَل — موجة القائمة لا تنتظره', () async {
      DeviceProbeApi.debugCaps(probe: const Duration(milliseconds: 600), zteExtra: const Duration(seconds: 3));
      addTearDown(() => DeviceProbeApi.debugCaps(probe: const Duration(seconds: 15), zteExtra: const Duration(seconds: 15)));
      // منفذٌ يقبل الاتّصال ولا يردّ أبداً
      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final held = <Socket>[];
      silent.listen(held.add);
      addTearDown(() async {
        for (final s in held) {
          s.destroy();
        }
        await silent.close();
      });
      final sw = Stopwatch()..start();
      final snap = await DeviceProbeApi.probe(fallbackIp: '127.0.0.1:${silent.port}', force: true, retryLogin: true);
      expect(snap, isNull);
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)), reason: 'التعرّف وحده جارٍ ⇒ لا مهلة إضافيّة');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final diag = api.requests.where((r) => r.uri.path == '/api/client-diag').single.data as Map;
      expect('${diag['message']}', contains('timeout'));
      expect('${diag['message']}', contains('steps=detect+'));
    });

    test('دخلنا ولم نقرأ الضوء ⇒ الأثر يُبلَّغ مرّةً لهذا العنوان ولو بلا «حفظ وفحص»', () async {
      api.defaults = {'ontUsername': 'agent', 'ontPassword': 'secret-1'};
      d.pages['epon_status_link_info_t.gch'] = (404, 'Not Found');
      d.pages['gpon_status_link_info_t.gch'] = (404, 'Not Found');
      d.pages['pon_status_link_info_t.gch'] = (200, '<html><title>D401</title><b>RxPower</b></html>');
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      expect(DeviceProbeApi.issueFor(ip: d.host)?.issue, ProbeIssue.unknownFormat, reason: 'الصفحة أُجيبت والضوء بصيغةٍ لا نعرفها');
      await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final diag = api.requests.where((r) => r.uri.path == '/api/client-diag').toList();
      expect(diag, hasLength(1), reason: 'مرّةً لكلّ عنوان بالجلسة لا كلّ فحص');
      final msg = '${(diag.single.data as Map)['message']}';
      expect(msg, contains('epon_link:404'));
      expect(msg, contains('pon_link:200/rx?'), reason: 'الاسم موجود بصيغةٍ لا نعرفها');
      expect(msg, contains('| t=D401'));
    });

    test('أثرٌ أطول من حدّ السجلّ ⇒ يصل أجزاءً، وما بعد الأوّل يبدأ بـ«+»', () async {
      api.defaults = {'ontUsername': 'agent', 'ontPassword': 'secret-1'};
      d.strictPages = true;
      final menu = [for (var i = 0; i < 8; i++) "menu('pon_status_optical_power_long_name_number_${i}_info_t.gch');"].join();
      final template = '<html><title>D401</title><script>$menu</script></html>';
      for (final p in ['epon_status_link_info_t.gch', 'gpon_status_link_info_t.gch', 'pon_status_link_info_t.gch']) {
        d.pages[p] = (200, template);
      }
      await DeviceProbeApi.probe(fallbackIp: d.host, force: true, retryLogin: true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final parts = [
        for (final r in api.requests.where((r) => r.uri.path == '/api/client-diag')) '${(r.data as Map)['message']}',
      ];
      expect(parts.length, inInclusiveRange(2, 5));
      expect(parts.every((p) => p.length <= 291), isTrue);
      expect(parts.where((p) => p.startsWith('+')), hasLength(parts.length - 1));
      // الأثر الطويل يُقطَّع عبر الأجزاء بلا فقدٍ: اسمٌ من آخر القائمة يظهر في المجموع.
      expect(parts.join().replaceAll('+', ''), contains('pon_optical_power_long_name_number_7'));
    });

    test('جهازٌ لا يجاوب ⇒ «لم يُتمكّن من الوصول»', () async {
      final port = d.server.port;
      await d.stop();
      final snap = await DeviceProbeApi.probe(fallbackIp: '127.0.0.1:$port', force: true);
      expect(snap, isNull);
      expect(DeviceProbeApi.issueFor(ip: '127.0.0.1:$port')?.issue, ProbeIssue.unreachable);
    });
  });
}

/// ZTE MH80 وهميّ: صفحة دخولٍ بعدّاد القفل ورمز النموذج كالجهاز الحيّ، ودخولٌ بنموذجٍ إلى `/`، وصفحة ضوء.
class _FakeMh80 {
  late HttpServer server;
  bool setCookie = true;
  bool dropPost = false;
  bool sessionOpen = false;
  int lockAt = 0;
  Duration pageDelay = Duration.zero;

  /// صفحاتٌ بعينها (الاسم ⇒ الحالة والجسم) — ما سواها صفحة ضوء MH80، أو 404 مع [strictPages].
  final pages = <String, (int, String)>{};
  bool strictPages = false;

  /// صفحةٌ لا تُخدَم إلّا بهذا الـpid (D401): طلبُها بـ1002 ⇒ 404.
  final pagePid = <String, String>{};
  final posts = <String>[];
  final paths = <String>[];

  /// أسماء الصفحات المطلوبة بالترتيب.
  final nextpages = <String>[];
  String? pageCookie;
  bool _stopped = false;

  String get host => '127.0.0.1:${server.port}';

  String _loginPage() => '<html><head><title>MH80</title><script>\n'
      'maxtime = Math.min(60, $lockAt + 60 - 402930);\n'
      'getObj("Frm_Logintoken").value = "9";\n'
      '</script></head><body><form name="fLogin" id="fLogin" method="post">'
      '<input type="hidden" name="Frm_Logintoken" id="Frm_Logintoken" value=""></form></body></html>';

  static const _optical = '<html><head><title>MH80</title></head><body><script>\n'
      'var LosInfo = "0";\nvar RxPower = "-186300";\nvar TxPower = "25900";\nvar Current = "13850";\n'
      '</script><td id="Frm_Volt">3244000</td><td id="Frm_Temp">41</td></body></html>';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      paths.add('${req.method} ${req.uri.path}');
      final res = req.response;
      res.headers.set('Server', 'Mini web server 1.0 ZTE corp 2005.');
      if (req.method == 'POST' && req.uri.path == '/') {
        final body = await utf8.decoder.bind(req).join();
        if (body.contains('logout=1')) {
          res.statusCode = 302;
          res.headers.set('Location', '/');
          await res.close();
          return;
        }
        posts.add(body);
        if (dropPost) {
          (await res.detachSocket(writeHeaders: false)).destroy();
          return;
        }
        final f = Uri.splitQueryString(body);
        final ok = !sessionOpen &&
            f['action'] == 'login' &&
            f['Frm_Logintoken'] == '9' &&
            f['username'] == 'agent' &&
            f['Password'] == 'secret-1';
        if (ok) {
          res.statusCode = 302;
          res.headers.set('Location', '/start.ghtml');
          if (setCookie) res.headers.add('Set-Cookie', 'SID=s1; path=/');
        } else {
          res.headers.contentType = ContentType.html;
          res.write(_loginPage());
        }
        await res.close();
        return;
      }
      if (req.uri.path == '/getpage.gch') {
        pageCookie = req.headers.value('cookie');
        if (pageDelay > Duration.zero) await Future<void>.delayed(pageDelay);
        final name = req.uri.queryParameters['nextpage'] ?? '';
        nextpages.add(name);
        final needPid = pagePid[name];
        final custom = needPid != null && req.uri.queryParameters['pid'] != needPid
            ? (404, 'Not Found') // pid خاطئ ⇒ صفحة خطأ
            : pages[name] ?? (strictPages ? (404, 'Not Found') : null);
        res.statusCode = custom?.$1 ?? 200;
        res.headers.contentType = ContentType.html;
        res.write(custom?.$2 ?? _optical);
        await res.close();
        return;
      }
      if (req.uri.path == '/') {
        res.headers.contentType = ContentType.html;
        res.write(_loginPage());
        await res.close();
        return;
      }
      res.statusCode = 404;
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
  Map<String, String> defaults = {};
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
