import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/core/net/tplink_pharos_service.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/device_probe_card.dart' show deviceCopyFields;
import 'package:shared_preferences/shared_preferences.dart';

/// جهاز المشترك اللاسلكيّ TP-Link Pharos (١٠ نوفمبر — المالك: «صنف جديد من النانوات tplink يحتاج نضيفه ضمن الاعتمادات…
/// يجلب نفس المعلومات مال النانوات»).
///
/// الصيغ والسلوك من CPE610 v2.0 الحيّ (PharOS 2.2.99) قراءةً فقط؛ الأسماء والعناوين والاعتمادات هنا وهميّة. الجهاز الوهميّ
/// خادم HTTP حقيقيّ على 127.0.0.1 بقواعد الحيّ: nonce واحد صالح (آخر ما طُلب)، وجلسةٌ واحدة، وعدّاد فشلٍ يقفل عند عشر.
void main() {
  group('التحليل', () {
    test('ردّ التعرّف ⇒ الطراز وحال الدخول والعدّاد؛ وما ليس Pharos ⇒ null', () {
      final h = TplinkPharosParse.hello(jsonEncode(_hello(status: -1, failed: 2, lock: 0)), base: 'http://x', cookie: 'abc');
      expect(h, isNotNull);
      expect([h!.devInfo, h.devVer, h.model, h.mode], ['CPE610', '2.0', 'CPE610 v2.0', 'apClientRouter']);
      expect([h.status, h.failedCount, h.lockMinutes, h.firstLogin, h.cookie], [-1, 2, 0, false, 'abc']);
      expect(TplinkPharosParse.hello('<html>login</html>', base: 'http://x'), isNull);
      expect(TplinkPharosParse.hello('{"success":true,"status":0}', base: 'http://x'), isNull, reason: 'JSON بلا devInfo ليس Pharos');
      expect(TplinkPharosParse.hello('{"devInfo":"CPE610"}', base: 'http://x'), isNull, reason: 'وبلا status كذلك');
    });

    test('كوكي الجلسة كما يرسله الجهاز', () {
      expect(TplinkPharosParse.cookie(['COOKIE=0000000006107906; PATH=/; MAXAGE=9999; VERSION=1']), '0000000006107906');
      expect(TplinkPharosParse.cookie(['other=1; path=/', 'cookie=zz; PATH=/']), 'zz');
      expect(TplinkPharosParse.cookie(null), isNull);
      expect(TplinkPharosParse.cookie(['SESSION=1']), isNull);
    });

    test('بصمة الدخول كما تحسبها صفحة الجهاز: MD5(MD5(pass)↑:nonce)↑', () {
      expect(TplinkPharosParse.digest('secret-1', '0000000006107906'), '963275F34CEA6765AABE9F707EA26779');
      expect(TplinkPharosParse.digest('admin', '00000000060f8f02'), '82AA968CF5A54EF55DFD5E0ED2CAF3BF');
    });

    test('HTTPS يُجرَّب فقط حين يكون خادم الردّ خادم TP-Link', () {
      expect(TplinkPharosParse.worthHttps('TP-LINK HTTPD/1.0'), isTrue);
      expect(TplinkPharosParse.worthHttps('lighttpd/1.4.39'), isFalse, reason: 'جهاز يوبيكويتي (ولو حوّل إلى HTTPS) لا يُطرق بطلبٍ ثانٍ');
      expect(TplinkPharosParse.worthHttps(null), isFalse);
    });

    test('الإشارة: الحقل المجمَّع، وإلّا مجموع قدرة السلاسل كما يحسبه الجهاز', () {
      expect(TplinkPharosParse.dbm('-41 dBm'), -41);
      expect(TplinkPharosParse.dbm('-83dBm'), -83);
      expect(TplinkPharosParse.dbm('N/A'), isNull);
      expect(TplinkPharosParse.dbm('0 dBm'), isNull, reason: 'صفرٌ ليس إشارة');
      expect(TplinkPharosParse.dbm('42dB'), isNull, reason: 'موجبٌ ليس إشارة');
      expect(TplinkPharosParse.signal('-41 dBm', '-45/-43 dBm'), -41);
      // قِيس على الحيّ: ‎-45/-43 ⇒ ‎-41 و‎-46/-45 ⇒ ‎-42
      expect(TplinkPharosParse.signal('', '-45/-43 dBm'), -41);
      expect(TplinkPharosParse.signal('N/A', '-46/-45 dBm'), -42);
      expect(TplinkPharosParse.signal('', '-60 dBm'), -60, reason: 'سلسلةٌ واحدة');
      expect(TplinkPharosParse.signal('', '-60/0 dBm'), -60, reason: 'سلسلةٌ بلا إشارة لا تدخل المجموع');
      expect(TplinkPharosParse.signal('', 'N/A'), isNull);
      expect(TplinkPharosParse.signal('', '0/0 dBm'), isNull);
    });

    test('المعدّل ومدّة التشغيل والمسافة والماك والإصدار', () {
      expect(TplinkPharosParse.kbps('78.0Mbps'), 78000);
      expect(TplinkPharosParse.kbps('6.5Mbps'), 6500);
      expect(TplinkPharosParse.kbps('N/A'), isNull);
      expect(TplinkPharosParse.uptime('4 days 14:31:49'), 4 * 86400 + 14 * 3600 + 31 * 60 + 49);
      expect(TplinkPharosParse.uptime('0 days 01:13:08'), 4388);
      expect(TplinkPharosParse.uptime('1 day 00:00:05'), 86405);
      expect(TplinkPharosParse.uptime('00:02:03'), 123);
      expect(TplinkPharosParse.uptime('N/A'), isNull);
      expect(TplinkPharosParse.meters('0.221km'), 221);
      expect(TplinkPharosParse.meters('N/A'), isNull);
      expect(TplinkPharosParse.mac('24-A4-3C-00-11-22'), '24:A4:3C:00:11:22');
      expect(TplinkPharosParse.mac('N/A'), isNull);
      expect(TplinkPharosParse.mac('00-00-00-00-00-00'), isNull);
      expect(TplinkPharosParse.firmware('2.2.99 Build 20200715 Rel. 59670 (0000)'), '2.2.99 Build 20200715');
      expect(TplinkPharosParse.firmware('2.1.14'), '2.1.14');
      expect(TplinkPharosParse.firmware('N/A'), '');
    });

    test('المنفذ: السرعة بصيغة النانو، و«لا أعرف» ليست «مفصول»', () {
      final p = TplinkPharosParse.port('lan0', '100Mbps - FD')!;
      expect([p.plugged, p.speed, p.displaySpeed, p.label], [true, '100Mbps-Full', '100 Mbps', 'LAN0']);
      expect(TplinkPharosParse.port('lan0', '10Mbps - HD')!.speed, '10Mbps-Half');
      expect(TplinkPharosParse.port('lan0', '1000Mbps - FD')!.displaySpeed, '1 Gbps');
      expect(TplinkPharosParse.port('lan0', 'Unplugged')!.plugged, isFalse);
      expect(TplinkPharosParse.port('lan0', 'N/A'), isNull);
      expect(TplinkPharosParse.port('lan0', ''), isNull);
    });

    test('طرازٌ بمنفذٍ واحد: الثاني «Unplugged» الوهميّ لا يُعرض؛ والموصول على الثاني يُعرض', () {
      expect(TplinkPharosParse.ports({'lanPort0': '100Mbps - FD', 'lanPort1': 'Unplugged'}).map((p) => p.name), ['lan0']);
      final two = TplinkPharosParse.ports({'lanPort0': 'Unplugged', 'lanPort1': '100Mbps - FD'});
      expect(two.map((p) => '${p.name}:${p.plugged}'), ['lan0:false', 'lan1:true']);
      expect(TplinkPharosParse.ports({'lanPort0': 'Unplugged', 'lanPort1': 'Unplugged'}).single.plugged, isFalse);
      expect(TplinkPharosParse.ports({}), isEmpty, reason: 'لا منافذ مقروءة = لم نعرف');
    });

    test('صفحة المعلومات ⇒ قراءة النانو نفسها (الإشارة، الجودة، المعدّلات، الكيبل، الاسم والإصدار)', () {
      final u = TplinkPharosParse.status(_info(), base: 'http://10.0.0.5', model: 'CPE610 v2.0')!;
      expect([u.vendor, u.isTplink, u.model], ['tplink', true, 'CPE610 v2.0']);
      expect([u.hostname, u.firmware, u.ssid, u.mode], ['sub-cpe', '2.2.99 Build 20200715', 'Sector-A(6)', 'sta']);
      expect([u.signalDbm, u.noiseFloorDbm, u.snrDb, u.ccqPercent], [-41, -83, 42, 92]);
      expect([u.txRateKbps, u.rxRateKbps, u.uptimeSeconds, u.distanceMeters], [6500, 78000, 397909, 221]);
      expect(u.peerMac, '24:A4:3C:00:11:22');
      expect(u.peerCount, isNull);
      expect(u.lanPorts.map((p) => '${p.label}:${p.displaySpeed}'), ['LAN0:100 Mbps']);
      expect([u.signalHealth, u.ccqHealth, u.lanHealth, u.lanUp], ['good', 'good', 'good', true]);
      expect(u.baseUrl, 'http://10.0.0.5');
      // يُحفظ ويُستعاد بمورّده وطرازه؛ ولقطةٌ قديمة بلا الحقل = يوبيكويتي كما كانت
      final back = UbiquitiStatus.fromJson(jsonDecode(jsonEncode(u.toJson())) as Map<String, dynamic>);
      expect([back.vendor, back.model, back.signalDbm, back.lanPorts.single.speed], ['tplink', 'CPE610 v2.0', -41, '100Mbps-Full']);
      final old = Map<String, dynamic>.from(u.toJson())..remove('vd')..remove('md');
      expect(UbiquitiStatus.fromJson(old).vendor, 'ubnt');
    });

    test('لا أرقام كاذبة: محطّةٌ غير مرتبطة بلا إشارةٍ ولا جودةٍ ولا معدّل', () {
      final d = _info()
        ..['rootApBssid'] = 'N/A'
        ..['rssiValue'] = '-95/-96 dBm'
        ..['rssiValueCombined'] = '-93 dBm'
        ..['transmitCcq'] = 0
        ..['clientTxRate'] = 'N/A'
        ..['clientRxRate'] = 'N/A';
      final u = TplinkPharosParse.status(d, base: 'http://x')!;
      expect([u.signalDbm, u.ccqPercent, u.txRateKbps, u.rxRateKbps, u.peerMac], [null, null, null, null, null],
          reason: 'أرضيّة الضجيج ليست إشارة وصلة');
      expect(u.lanPorts, isNotEmpty, reason: 'الكيبل يُقرأ ولو سقطت الوصلة');
      expect(u.signalHealth, 'unknown');
    });

    test('نقطة وصول: لا «إشارة وصلة»، وعدد المتّصلين من الجهاز', () {
      final d = _info()
        ..['clientEnable'] = 0
        ..['apEnable'] = true
        ..['rootApBssid'] = 'N/A'
        ..['rootApSsid'] = 'N/A'
        ..['apSsid'] = 'AP-One'
        ..['apConnectedStations'] = '7';
      final u = TplinkPharosParse.status(d, base: 'http://x')!;
      expect([u.mode, u.ssid, u.signalDbm, u.ccqPercent, u.peerCount, u.peerMac], ['ap', 'AP-One', null, null, 7, null]);
    });

    test('«نسخ كلّ المعلومات»: نوع الجهاز باسم TP-Link وطرازه، وباقي الحقول حقول النانو نفسها', () {
      final u = TplinkPharosParse.status(_info(), base: 'http://x', model: 'CPE610 v2.0')!;
      final f = deviceCopyFields(DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.0.0.5', ubnt: u));
      expect(f.first.value, 'sub-cpe (TP-Link CPE610 v2.0)');
      expect(f.map((x) => x.label), ['نوع الجهاز', 'الإشارة', 'CCQ', 'الإصدار', 'SSID', 'مدّة التشغيل', 'TX / RX', 'Peer MAC', 'المنافذ']);
      expect(f.firstWhere((x) => x.label == 'المنافذ').value, 'LAN0 · 100 Mbps');
      // بلا اسمٍ للجهاز: المورّد والطراز وحدهما؛ ويوبيكويتي كما كان
      final noName = TplinkPharosParse.status(_info()..['deviceName'] = '', base: 'http://x')!;
      expect(deviceCopyFields(DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.0.0.5', ubnt: noName)).first.value,
          'TP-Link CPE610 v2.0');
      final ub = UbiquitiStatus.fromJson(Map<String, dynamic>.from(u.toJson())..remove('vd')..remove('md'));
      expect(deviceCopyFields(DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.0.0.5', ubnt: ub)).first.value, 'sub-cpe (UBNT)');
    });

    test('شكلٌ ليس صفحة المعلومات ⇒ null', () {
      expect(TplinkPharosParse.status({'hasUnsavedConfig': true}, base: 'http://x'), isNull);
    });

    test('القراءة الحيّة: تحميل المشترك ما يستقبله الراديو من البرج، والإشارة من السلاسل', () {
      final l = TplinkPharosParse.live(_live());
      expect([l.downBps, l.upBps], [1390100, 112700]);
      expect([l.signalDbm, l.noiseFloorDbm, l.ccqPercent, l.txRateKbps, l.rxRateKbps], [-41, -84, 100, 26000, 104000]);
      expect(l.uptimeSeconds, 397957);
      expect(l.lanPorts!.single.speed, '100Mbps-Full');
      // تُطبَّق على القراءة الكاملة فيبقى الاسم والطراز والمنافذ تتحدّث
      final u = l.applyTo(TplinkPharosParse.status(_info(), base: 'http://x', model: 'CPE610 v2.0')!);
      expect([u.hostname, u.model, u.vendor, u.signalDbm, u.ccqPercent, u.rxRateKbps], ['sub-cpe', 'CPE610 v2.0', 'tplink', -41, 100, 104000]);
      // نقطة وصول: تحميل عملائها ما ترسله
      final ap = TplinkPharosParse.live(_live()
        ..['rootApBssid'] = 'N/A'
        ..['apConnectedStations'] = '3');
      expect([ap.downBps, ap.upBps, ap.signalDbm], [112700, 1390100, null]);
      // بلا ترافيك في الردّ ⇒ null لا صفر
      final none = TplinkPharosParse.live(_live()..remove('wireless'));
      expect([none.downBps, none.upBps], [null, null]);
    });
  });

  group('الجهاز', () {
    late _FakePharos d;

    setUp(() async {
      TplinkPharosService.reset();
      TplinkPharosService.clock = DateTime.now;
      d = _FakePharos();
      await d.start();
    });

    tearDown(() async {
      TplinkPharosService.clock = DateTime.now;
      await d.stop();
    });

    test('تعرّفٌ بلا دخول: الطراز والـnonce — وجهازٌ آخر ⇒ null', () async {
      final h = await TplinkPharosService.hello(d.host);
      expect([h?.model, h?.status, h?.failedCount], ['CPE610 v2.0', -1, 0]);
      expect(h!.cookie, isNotEmpty);
      expect(d.logins, isEmpty);
      d.notPharos = true;
      expect(await TplinkPharosService.hello(d.host), isNull);
    });

    test('قراءةٌ واحدة: دخولٌ ← قراءةٌ ← خروج، ولا تبقى جلسة تمنع الوكيل عن صفحة جهازه', () async {
      final u = await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1');
      expect([u?.vendor, u?.signalDbm, u?.ccqPercent, u?.model], ['tplink', -41, 92, 'CPE610 v2.0']);
      expect(d.logins, hasLength(1));
      await d.idle();
      expect(d.session, isNull, reason: 'الخروج بعد القراءة');
      expect(d.failed, 0);
      expect(TplinkPharosService.lastIssue(d.host), isNull);
    });

    test('اعتمادٌ غلط ⇒ «رُفض» ويُحفظ فلا يُعاد؛ «حفظ وفحص» يعيده مرّة', () async {
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'wrong'), isNull);
      expect(TplinkPharosService.lastIssue(d.host)?.issue, PharosLoginIssue.rejected);
      expect([d.logins.length, d.failed], [1, 1]);
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'wrong'), isNull);
      expect([d.logins.length, d.failed], [1, 1], reason: 'المرفوض لا يُعاد — عشر محاولاتٍ غلط تقفل صفحة الجهاز ساعتين');
      expect(TplinkPharosService.lastIssue(d.host)?.trace, 'remembered');
      TplinkPharosService.forget(d.host, manual: true);
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'wrong'), isNull);
      expect(d.logins, hasLength(2));
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'), isNotNull, reason: 'اعتمادٌ غيره يُجرَّب فوراً');
      expect(d.failed, 0, reason: 'الدخول الناجح يصفّر عدّاد الجهاز');
    });

    test('عدّاد الجهاز بلغ الحدّ ⇒ لا إرسال تلقائيّاً؛ والوكيل («حفظ وفحص») حتى حدّه — ولا نبلغ العاشرة', () async {
      d.failed = TplinkPharosService.autoFailLimit;
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'), isNull);
      expect(TplinkPharosService.lastIssue(d.host)?.issue, PharosLoginIssue.tooManyFails);
      expect(d.logins, isEmpty, reason: 'ولو كان الاعتماد صحيحاً — العدّاد يجمع محاولات كلّ الهواتف');
      TplinkPharosService.forget(d.host, manual: true);
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'), isNotNull, reason: 'الوكيل صحّح بيده ⇒ يُسمح');
      d.failed = TplinkPharosService.manualFailLimit;
      TplinkPharosService.forget(d.host, manual: true);
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'), isNull);
      expect(TplinkPharosService.lastIssue(d.host)?.issue, PharosLoginIssue.tooManyFails);
      expect(d.logins, hasLength(1));
      // الإذن اليدويّ لمحاولةٍ واحدة: الفحص التالي بالحدّ التلقائيّ
      d.failed = TplinkPharosService.autoFailLimit;
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'), isNull);
      expect(d.logins, hasLength(1));
    });

    test('قافلٌ ⇒ لا إرسال، والباقي من الجهاز نفسه', () async {
      d.lock = 87;
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'), isNull);
      final i = TplinkPharosService.lastIssue(d.host)!;
      expect([i.issue, i.lockLeft], [PharosLoginIssue.locked, 87 * 60]);
      expect(d.logins, isEmpty);
    });

    test('المحاولة العاشرة تقفل ⇒ «قافل» لا «رُفض»', () async {
      d.failed = 9;
      final r = await TplinkPharosService.attempt(d.host, 'agent', 'wrong', failLimit: 99);
      expect([r.issue, r.lockLeft], [PharosLoginIssue.locked, 120 * 60]);
    });

    test('جهازٌ جديد لم يُضبط ⇒ لا نرسل عليه شيئاً', () async {
      d.firstLogin = true;
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'), isNull);
      expect(TplinkPharosService.lastIssue(d.host)?.issue, PharosLoginIssue.needsSetup);
      expect(d.logins, isEmpty);
    });

    test('مستخدمٌ آخر داخل من عنوانٍ ثانٍ ⇒ «مشغول»: نلغي ولا نطرده، ولا محاولة قبل دقيقة', () async {
      d.otherLoggedIn = true;
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'), isNull);
      expect(TplinkPharosService.lastIssue(d.host)?.issue, PharosLoginIssue.busy);
      await d.idle();
      expect(d.cancels, 1);
      expect(d.confirms, 0, reason: 'الإكمال يطرد المستخدم الآخر');
      d.otherLoggedIn = false;
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'), isNull);
      expect(d.logins, hasLength(1), reason: 'مهلة الدقيقة');
      expect(TplinkPharosService.lastIssue(d.host)?.trace, 'cooldown');
      final t0 = DateTime.now();
      TplinkPharosService.clock = () => t0.add(TplinkPharosService.busyCooldown + const Duration(seconds: 1));
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'), isNotNull);
    });

    test('nonce قديم (عميلٌ آخر طلب واحداً بيننا) ⇒ يُعاد بالجديد ولا يُحسب محاولةً غلط', () async {
      final h = await TplinkPharosService.hello(d.host);
      await TplinkPharosService.hello(d.host); // هاتفٌ آخر تعرّف بيننا: nonce الأوّل بطل
      final u = await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1', hello: h);
      expect(u, isNotNull);
      expect(d.logins, hasLength(2), reason: 'إرسالٌ بالقديم ثمّ بالجديد من الردّ نفسه');
      expect(d.failed, 0);
    });

    test('دخلنا وطُردت الجلسة قبل القراءة ⇒ «ما رجعت القراءات» لا رفض', () async {
      d.kickAfterLogin = true;
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'), isNull);
      expect(TplinkPharosService.lastIssue(d.host)?.issue, PharosLoginIssue.readFailed);
      d.kickAfterLogin = false;
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'), isNotNull, reason: 'لا يُحفظ رفضاً');
    });

    test('انقطاعٌ عند الإرسال ليس رفضاً ⇒ الفحص التالي يحاول', () async {
      d.dropLogin = true;
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'), isNull);
      expect(TplinkPharosService.lastIssue(d.host)?.issue, PharosLoginIssue.unreachable);
      d.dropLogin = false;
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'), isNotNull);
    });

    test('جلسة الكرت الحيّة: دخولٌ واحد، قراءاتٌ خفيفة، والفحص يقرأ بها بلا دخولٍ ثانٍ، ثمّ خروج', () async {
      final live = await PharosLiveSession.open(ip: d.host, user: 'agent', pass: 'secret-1');
      expect(live, isNotNull);
      expect(TplinkPharosService.hasLive(d.host), isTrue);
      final a = await live!.sample();
      expect([a?.downBps, a?.upBps, a?.signalDbm], [1390100, 112700, -41]);
      final u = await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1');
      expect(u?.signalDbm, -41);
      expect(d.logins, hasLength(1), reason: 'دخولٌ ثانٍ من عنواننا يطرد جلسة الكرت');
      expect((await live.sample())?.downBps, 1390100, reason: 'الجلسة باقية بعد الفحص');
      await live.close();
      expect(d.session, isNull);
      expect(TplinkPharosService.hasLive(d.host), isFalse);
    });

    test('كرتان على الجهاز نفسه يتشاركان جلسةً واحدة، والخروج بإغلاق الأخير', () async {
      final a = await PharosLiveSession.open(ip: d.host, user: 'agent', pass: 'secret-1');
      final b = await PharosLiveSession.open(ip: d.host, user: 'agent', pass: 'secret-1');
      expect(d.logins, hasLength(1));
      await a!.close();
      expect(d.session, isNotNull);
      expect((await b!.sample())?.downBps, isNotNull);
      await b.close();
      expect(d.session, isNull);
    });

    test('طُردت الجلسة الحيّة (أحدٌ دخل صفحة الجهاز) ⇒ لا نطارده: دقيقتان، ثمّ عشرٌ إن تكرّر', () async {
      var now = DateTime.now();
      TplinkPharosService.clock = () => now;
      final live = await PharosLiveSession.open(ip: d.host, user: 'agent', pass: 'secret-1');
      d.kick();
      expect(await live!.sample(), isNull);
      expect(live.lost, isTrue);
      await live.close();
      expect(d.logouts, 0, reason: 'جلسةٌ ميّتة لا يُخرَج منها');
      expect(await PharosLiveSession.open(ip: d.host, user: 'agent', pass: 'secret-1'), isNull);
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'), isNull, reason: 'والفحص كذلك لا يدخل');
      expect(TplinkPharosService.lastIssue(d.host)?.issue, PharosLoginIssue.busy);
      expect(d.logins, hasLength(1));
      now = now.add(TplinkPharosService.kickCooldown + const Duration(seconds: 1));
      final again = await PharosLiveSession.open(ip: d.host, user: 'agent', pass: 'secret-1');
      expect(again, isNotNull);
      d.kick();
      expect(await again!.sample(), isNull);
      await again.close();
      now = now.add(TplinkPharosService.kickCooldown + const Duration(seconds: 1));
      expect(await PharosLiveSession.open(ip: d.host, user: 'agent', pass: 'secret-1'), isNull,
          reason: 'طردٌ ثانٍ قريب = أحدٌ يعمل على صفحة الجهاز ⇒ انتظارٌ أطول');
      now = now.add(TplinkPharosService.kickCooldownLong);
      expect(await PharosLiveSession.open(ip: d.host, user: 'agent', pass: 'secret-1'), isNotNull);
    });

    test('الفحص يكتشف طرد الجلسة الحيّة ⇒ يسجّله مرّةً واحدة (لا يُعدّ طردين)', () async {
      var now = DateTime.now();
      TplinkPharosService.clock = () => now;
      final live = await PharosLiveSession.open(ip: d.host, user: 'agent', pass: 'secret-1');
      d.kick();
      expect(await TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'), isNull);
      expect(live!.lost, isTrue);
      await live.close();
      now = now.add(TplinkPharosService.kickCooldown + const Duration(seconds: 1));
      expect(await PharosLiveSession.open(ip: d.host, user: 'agent', pass: 'secret-1'), isNotNull,
          reason: 'طردٌ واحد ⇒ دقيقتان لا عشر');
    });

    test('تعثّرٌ عابر في القراءة الحيّة ليس طرداً: الجلسة تبقى', () async {
      final live = await PharosLiveSession.open(ip: d.host, user: 'agent', pass: 'secret-1');
      d.dropLive = true;
      expect(await live!.sample(), isNull);
      expect([live.lost, live.misses], [false, 1]);
      d.dropLive = false;
      expect(await live.sample(), isNotNull);
      expect(live.misses, 0);
      await live.close();
      expect(d.logouts, 1);
    });

    test('دخولان متزامنان من التطبيق نفسه يتسلسلان (لا يطرد أحدهما الآخر قبل قراءته)', () async {
      final r = await Future.wait([
        TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'),
        TplinkPharosService.readOnce(d.host, 'agent', 'secret-1'),
      ]);
      expect(r.map((u) => u?.signalDbm), [-41, -41]);
    });
  });

  group('فحص جهاز المشترك', () {
    late _FakePharos d;
    late _FakeApi api;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DeviceProbeApi.clearAllCaches();
      TplinkPharosService.clock = DateTime.now;
      d = _FakePharos();
      await d.start();
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

    tearDown(() => d.stop());

    test('جهاز TP-Link ⇒ قراءة النانو من فرعه، ودخول يوبيكويتي لا يُرسل عليه', () async {
      api.defaults = {'tplinkUsername': 'agent', 'tplinkPassword': 'secret-1', 'ubntUsername': 'ub', 'ubntPassword': 'ub-p'};
      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect(snap?.kind, DeviceKind.ubiquiti, reason: 'نفس نوع النانو ⇒ نفس البطاقات والتنبيهات');
      expect([snap?.ubnt?.vendor, snap?.ubnt?.signalDbm, snap?.ubnt?.ccqPercent], ['tplink', -41, 92]);
      expect(snap?.ubnt?.lanPorts.single.displaySpeed, '100 Mbps');
      expect(d.paths.where((p) => p.contains('login.cgi') || p.contains('/api/auth')), isEmpty);
      expect(DeviceProbeApi.issueFor(ip: d.host), isNull);
      final creds = await DeviceProbeApi.resolveTplinkCreds(fallbackIp: d.host);
      expect([creds?.user, creds?.pass], ['agent', 'secret-1']);
    });

    test('الفحص التالي يذهب لفرع TP-Link وحده — لا طلبات هواوي ولا يوبيكويتي على الجهاز', () async {
      api.defaults = {'tplinkUsername': 'agent', 'tplinkPassword': 'secret-1'};
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNotNull);
      await d.settle(); // فروع السباق الأخرى تنتهي
      d.paths.clear();
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNotNull);
      await d.settle();
      expect(d.paths.where((p) => !p.contains('/data/')), isEmpty);
    });

    test('بلا اعتماد من الوكيل ⇒ لا دخول بافتراضٍ من عندنا، والسبب «يحتاج يوزر وباسورد» باسم المورّد', () async {
      api.defaults = {'ubntUsername': 'ub', 'ubntPassword': 'ub-p', 'ontUsername': 'o', 'ontPassword': 'o-p'};
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      expect(d.logins, isEmpty, reason: 'اعتماد يوبيكويتي والـONT لا يُجرَّبان على TP-Link');
      final why = DeviceProbeApi.issueFor(ip: d.host);
      expect([why?.issue, why?.vendor], [ProbeIssue.needsCredentials, 'tplink']);
    });

    test('الأوّل مرفوض والإضافيّ صحيح ⇒ يدخل بالإضافيّ ويُحفظ فائزاً، والمرفوض لا يُعاد', () async {
      api.defaults = {
        'tplinkUsername': 'agent',
        'tplinkPassword': 'wrong-1',
        'tplinkExtra': [
          {'username': 'agent', 'password': 'secret-1'},
        ],
      };
      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect(snap?.ubnt?.vendor, 'tplink');
      expect(d.logins, hasLength(2));
      expect(DeviceProbeApi.issueFor(ip: d.host), isNull, reason: 'الرفض الأوّل لا يبقى سبباً بعد دخول الإضافيّ');
      expect((await DeviceProbeApi.resolveTplinkCreds(fallbackIp: d.host))?.pass, 'secret-1');
      await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect(d.logins, hasLength(3), reason: 'يبدأ بالفائز — المرفوض لا يُرسل ثانيةً');
      expect(d.failed, 0);
    });

    test('اعتمادٌ مرفوض ⇒ السبب «رُفض»، والتحديث العاديّ لا يعيده، و«حفظ وفحص» يعيده مرّة', () async {
      api.defaults = {'tplinkUsername': 'agent', 'tplinkPassword': 'wrong'};
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      expect(DeviceProbeApi.issueFor(ip: d.host)?.issue, ProbeIssue.loginRejected);
      await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect(d.logins, hasLength(1));
      await DeviceProbeApi.probe(fallbackIp: d.host, force: true, retryLogin: true);
      expect(d.logins, hasLength(2));
      expect(d.failed, 2);
    });

    test('مشغولٌ وقافل ⇒ سببهما يصل الكرت بمورّده (جملته غير جملة ZTE)', () async {
      api.defaults = {'tplinkUsername': 'agent', 'tplinkPassword': 'secret-1'};
      d.lock = 30;
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      var why = DeviceProbeApi.issueFor(ip: d.host);
      expect([why?.issue, why?.vendor], [ProbeIssue.locked, 'tplink']);
      expect(why!.lockLeft, inInclusiveRange(30 * 60 - 5, 30 * 60));
      d.lock = 0;
      d.otherLoggedIn = true;
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      why = DeviceProbeApi.issueFor(ip: d.host);
      expect([why?.issue, why?.vendor], [ProbeIssue.busy, 'tplink']);
    });

    test('جلسة الكرت الحيّة قائمة ⇒ الفحص طلبٌ واحد: لا تعرّف ولا دخول', () async {
      api.defaults = {'tplinkUsername': 'agent', 'tplinkPassword': 'secret-1'};
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNotNull);
      final live = await PharosLiveSession.open(ip: d.host, user: 'agent', pass: 'secret-1');
      await d.settle();
      d.paths.clear();
      final logins = d.logins.length;
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNotNull);
      expect(d.logins, hasLength(logins));
      expect(d.paths, ['GET /data/info.json']);
      await live!.close();
    });

    test('مرشّحو TP-Link: اعتماد المشترك وحده، وإلّا خانة المدير ثمّ إضافيّاه — بلا افتراض مصنّع أبداً', () {
      const e1 = DeviceCred('x-1', 'x-1-p');
      const e2 = DeviceCred('x-2', 'x-2-p');
      const d0 = AdminDeviceDefaults(tplinkUsername: 'tp', tplinkPassword: 'tp-p', tplinkExtra: [e1, e2, e1]);
      expect(DeviceProbeApi.candidatesFor(null, d0).tplink, [const DeviceCred('tp', 'tp-p'), e1, e2]);
      expect(DeviceProbeApi.candidatesFor(null, AdminDeviceDefaults.empty).tplink, isEmpty);
      expect(DeviceProbeApi.candidatesFor(null, const AdminDeviceDefaults(tplinkExtra: [e1])).tplink, [e1]);
      final own = DeviceProbeApi.candidatesFor(const DeviceConfig(username: 'sub-u', password: 'sub-p'), d0);
      expect(own.tplink, [const DeviceCred('sub-u', 'sub-p')], reason: '«تلقائي» + اعتماد المشترك ⇒ هو وحده');
      final pinnedRadio = DeviceProbeApi.candidatesFor(
          const DeviceConfig(deviceType: DeviceKind.ubiquiti, username: 'sub-u', password: 'sub-p'), d0);
      expect(pinnedRadio.tplink, [const DeviceCred('sub-u', 'sub-p')]);
      final pinnedOnt =
          DeviceProbeApi.candidatesFor(const DeviceConfig(deviceType: DeviceKind.ont, username: 'sub-u', password: 'sub-p'), d0);
      expect(pinnedOnt.tplink, [const DeviceCred('tp', 'tp-p'), e1, e2], reason: 'اعتماد ONT لا يُجرَّب على TP-Link');
    });

    test('اعتمادات المدير من الخادم وإليه: TP-Link يُقرأ ويُرسل دائماً، وكلمة السرّ لا تُقصّ', () {
      final a = AdminDeviceDefaults.fromJson({
        'tplinkUsername': ' tp ',
        'tplinkPassword': ' p w ',
        'tplinkExtra': [
          {'username': 'x-1', 'password': 'x-1-p'},
        ],
      });
      expect([a.tplinkUsername, a.tplinkPassword], ['tp', ' p w ']);
      expect(a.tplinkExtra, [const DeviceCred('x-1', 'x-1-p')]);
      final j = a.toJson();
      expect([j['tplinkUsername'], j['tplinkPassword']], ['tp', ' p w ']);
      expect(j['tplinkExtra'], [
        {'username': 'x-1', 'password': 'x-1-p'},
      ]);
      final old = AdminDeviceDefaults.fromJson({'ubntUsername': 'u'});
      expect([old.tplinkUsername, old.tplinkPassword, old.tplinkExtra], [null, null, isEmpty], reason: 'خادمٌ أقدم بلا الحقل');
      expect(old.toJson().containsKey('tplinkExtra'), isTrue, reason: 'القائمة تُرسل ولو فارغة');
    });
  });
}

// ── عيّنات بشكل الجهاز الحيّ (القيم وهميّة) ───────────────────────────────────

Map<String, dynamic> _hello({required int status, int failed = 0, int lock = 0, bool firstLogin = false}) => {
      'success': true,
      'timeout': status != 0,
      'version': '1.00',
      'mode': 'apClientRouter',
      'status': status,
      'failedCount': failed,
      'lockTime': lock,
      'ip': '10.0.0.9',
      'username': 'agent',
      'firstLogin': firstLogin,
      'language': 0,
      'is2G': false,
      'devInfo': 'CPE610',
      'devVer': '2.0',
      'isLockCountryID': false,
      'isRemoteLogin': true,
      'isWirelessAccess': false,
      'productInfo': 'UN',
      'languageInfo': 'en',
      'lockCountry': 0,
      'countryID': 511,
    };

Map<String, dynamic> _info() => {
      'wanConnType': 'PPPoE',
      'wanMacAddr': '98-DA-C4-00-00-02',
      'wanIpAddress': '10.20.30.40',
      'wanSubnetMask': '255.255.255.255',
      'wanDefaultGateway': '10.20.0.1',
      'wanDnsServer': '10.20.0.1',
      'wanIpv6Address': 'N/A',
      'lanMacAddr': '98-DA-C4-00-00-01',
      'lanIpAddress': '192.168.0.254',
      'lanSubnetMask': '255.255.255.0',
      'lanIpv6Address': 'N/A',
      'lanPort1': 'Unplugged',
      'lanPort0': '100Mbps - FD',
      'wanPort1': '100Mbps - FD',
      'sysTime': '2026-11-10 20:13:06',
      'sysRunTime': '4 days 14:31:49',
      'memory': 70,
      'memoryValue': '70%',
      'cpu': 5,
      'cpuValue': '5%',
      'deviceName': 'sub-cpe',
      'firmVersion': '2.2.99 Build 20200715 Rel. 59670 (0000)',
      'hardVersion': 'CPE610 v2.0',
      'rssi': 67,
      'rssiValue': '-45/-43 dBm',
      'rssiValueCombined': '-41 dBm',
      'noiseStrength': 35,
      'noiseValue': '-83dBm',
      'snrProcess': 32,
      'snrValue': '42dB',
      'transmitCcq': 92,
      'transmitValue': '92',
      'tdma': 'OFF',
      'region': 511,
      'channel': '49 / 5245MHz',
      'channelWidth': '20MHz',
      'mode': 'A/N Mixed',
      'maxTxRate': '144.4Mbps',
      'antennaMode': 0,
      'txPower': '25dBm',
      'ackTimeout': '0.221km',
      'enableSSID': false,
      'apEnable': false,
      'apMacAddr': 'N/A',
      'apSsid': 'N/A',
      'apSecurity': 'N/A',
      'apConnectedStations': 'N/A',
      'clientEnable': 1,
      'clientMacAddr': '98-DA-C4-00-00-02',
      'clientSsid': 'Sector-A(6)',
      'clientSecurity': 'None',
      'clientWds': 0,
      'rootApBssid': '24-A4-3C-00-11-22',
      'rootApSsid': 'Sector-A(6)',
      'clientTxRate': '6.5Mbps',
      'clientRxRate': '78.0Mbps',
      'clientConnTime': '0 days 01:13:08',
    };

Map<String, dynamic> _live() => {
      'wired': [
        {'deviceRx': 68.8, 'deviceTx': 1348.2},
      ],
      'wireless': [
        {'deviceRx': 1390.1, 'deviceTx': 112.7},
      ],
      'sysTime': '2026-11-10 20:13:54',
      'sysRunTime': '4 days 14:32:37',
      'memory': 71,
      'memoryValue': '71%',
      'cpu': 6,
      'cpuValue': '6%',
      'rootApBssid': '24-A4-3C-00-11-22',
      'rootApSsid': 'Sector-A(6)',
      'clientTxRate': '26.0Mbps',
      'clientRxRate': '104.0Mbps',
      'clientConnTime': '0 days 01:13:56',
      'rssi': 67,
      'rssiValue': '-45/-43 dBm',
      'noiseStrength': 34,
      'noiseValue': '-84dBm',
      'snrProcess': 33,
      'snrValue': '43dB',
      'transmitCcq': 100,
      'transmitValue': '100',
      'apConnectedStations': 'N/A',
      'lanPort1': 'Unplugged',
      'lanPort0': '100Mbps - FD',
      'wanPort1': '100Mbps - FD',
    };

/// جهاز Pharos وهميّ بقواعد الحيّ المَقيسة: آخر nonce طُلب هو الصالح وحده؛ جلسةٌ واحدة (دخولٌ ثانٍ يطرد الأوّل)؛ الخروج بكوكي
/// قديم لا يمسّ الجلسة؛ القراءة GET وحده؛ والجلسة المنتهية تردّ `timeout` بلا `data`.
class _FakePharos {
  late HttpServer server;
  static const user = 'agent';
  static const pass = 'secret-1';

  int failed = 0;
  int lock = 0;
  bool firstLogin = false;
  bool otherLoggedIn = false;
  bool notPharos = false;
  bool kickAfterLogin = false;
  bool dropLogin = false;
  bool dropLive = false;

  String? session;
  String? _nonce;
  int _seq = 0x06107906;
  final logins = <String>[];
  final paths = <String>[];
  int logouts = 0;
  int cancels = 0;
  int confirms = 0;
  bool _stopped = false;

  String get host => '127.0.0.1:${server.port}';

  /// أحدٌ دخل صفحة الجهاز: جلستنا تنتهي.
  void kick() => session = 'someone-else';

  /// مهلةٌ قصيرة لما أُرسل بلا انتظار (الخروج، الإلغاء).
  Future<void> idle([Duration d = const Duration(milliseconds: 150)]) => Future<void>.delayed(d);

  /// ينتظر حتى تسكت الطلبات (فروع السباق الأخرى تنتهي بالخلفيّة) — لا طلب جديد ربع ثانية، وبحدٍّ أقصى.
  Future<void> settle() async {
    final sw = Stopwatch()..start();
    var seen = paths.length;
    var quietSince = sw.elapsedMilliseconds;
    while (sw.elapsedMilliseconds < 5000) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (paths.length != seen) {
        seen = paths.length;
        quietSince = sw.elapsedMilliseconds;
      } else if (sw.elapsedMilliseconds - quietSince >= 250) {
        return;
      }
    }
  }

  String _newNonce() => _nonce = (_seq++).toRadixString(16).padLeft(16, '0');

  String _digest(String p, String nonce) {
    String up(String s) => md5.convert(utf8.encode(s)).toString().toUpperCase();
    return up('${up(p)}:$nonce');
  }

  Future<void> _json(HttpResponse res, Map<String, dynamic> body, {String? setCookie}) async {
    res.headers.set('Server', 'TP-LINK HTTPD/1.0');
    res.headers.set('Content-Type', 'text/html');
    if (setCookie != null) res.headers.add('Set-Cookie', 'COOKIE=$setCookie; PATH=/; MAXAGE=9999; VERSION=1');
    res.write(const JsonEncoder.withIndent('\t').convert(body));
    await res.close();
  }

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      paths.add('${req.method} ${req.uri.path}');
      final res = req.response;
      final cookie = RegExp(r'COOKIE=([^;\s]+)').firstMatch(req.headers.value('cookie') ?? '')?.group(1);
      final mine = cookie != null && cookie == session;
      if (notPharos || !req.uri.path.startsWith('/data/')) {
        res.statusCode = 404;
        await res.close();
        return;
      }
      if (req.uri.path == '/data/version.json') {
        if (req.method == 'GET') {
          if (req.uri.queryParameters['option'] == 'logout') {
            if (mine) {
              session = null;
              logouts++;
            }
            return _json(res, _hello(status: -1, failed: failed, lock: lock), setCookie: _newNonce());
          }
          if (mine) return _json(res, _hello(status: 0));
          return _json(res, _hello(status: -1, failed: failed, lock: lock, firstLogin: firstLogin), setCookie: _newNonce());
        }
        final body = await utf8.decoder.bind(req).join();
        final f = Uri.splitQueryString(body);
        if (f['option'] == 'cancel') {
          cancels++;
          return _json(res, _hello(status: -1, failed: failed, lock: lock), setCookie: _newNonce());
        }
        logins.add(body);
        if (dropLogin) {
          (await res.detachSocket(writeHeaders: false)).destroy();
          return;
        }
        // nonce قديم: لا تُحسب محاولة، والردّ يحمل الجديد
        if (f['nonce'] != _nonce || cookie != _nonce) {
          return _json(res, _hello(status: -1, failed: failed, lock: lock), setCookie: _newNonce());
        }
        final nonce = _nonce!;
        if (lock > 0) return _json(res, _hello(status: 1, failed: failed, lock: lock));
        if (f['encoded'] != '$user:${_digest(pass, nonce)}') {
          failed++;
          if (failed >= 10) lock = 120;
          return _json(res, _hello(status: 1, failed: failed, lock: lock));
        }
        if (otherLoggedIn) return _json(res, _hello(status: 4));
        failed = 0;
        session = kickAfterLogin ? 'someone-else' : nonce;
        return _json(res, {..._hello(status: 0), 'failedCount': null, 'lockTime': null});
      }
      if (req.uri.path == '/data/loginConfirm.json') {
        confirms++;
        return _json(res, _hello(status: 0));
      }
      if (req.method != 'GET') {
        // الحيّ يردّ على POST لصفحات القراءة بجسمٍ فارغ
        res.headers.set('Server', 'TP-LINK HTTPD/1.0');
        await res.close();
        return;
      }
      if (!mine) return _json(res, {'success': true, 'timeout': true}, setCookie: _newNonce());
      if (req.uri.path == '/data/info.json') return _json(res, {'success': true, 'data': _info()});
      if (req.uri.path == '/data/progressBar.json') {
        if (dropLive) {
          (await res.detachSocket(writeHeaders: false)).destroy();
          return;
        }
        return _json(res, {'success': true, 'data': _live()});
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
