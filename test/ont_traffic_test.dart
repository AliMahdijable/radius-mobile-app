import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/net/huawei_ont_service.dart';
import 'package:rad_mysvcs/core/net/ont_traffic.dart';
import 'package:rad_mysvcs/models/device_health.dart';

/// ترافيك الـONU اللحظيّ (٢٢ أكتوبر، المالك: «اشتغلي على جلب ترفك onu… اختبرها اكثر من مره اهم شي الدقة»).
///
/// الصيغ هنا منقولةٌ من صفحاتٍ حقيقيّة على شبكة popq (HG8245Q2، HS8545M، HG8245C، HG8145C، HG8546M): صفحة الواي فاي تُعلن
/// مصفوفتها **فارغةً أوّلاً** ثمّ تملؤها بعد ٢٧ بايتاً — والتوقّف عند الفارغة كان يُسقط الواي فاي كلّه بصمت (أُمسك في الفحص
/// الحقيقيّ قبل أيّ نشر). والمجموع LAN + الواي فاي: المشترك يربط الاثنين معاً.

/// رأس صفحة الواي فاي كما يصل من الجهاز: الإعلان الفارغ ثمّ المملوء (domain بترميز \x2e).
const _wifiHead = r'''
var WlanChannel = '';

var PacketInfo = new Array();
PacketInfo = new Array(new stPacketInfo("InternetGatewayDevice\x2eLANDevice\x2e1\x2eWLANConfiguration\x2e1","3638888413","55004462","3386144779","24282225"),new stPacketInfo("InternetGatewayDevice\x2eLANDevice\x2e1\x2eWLANConfiguration\x2e5","1000","10","2000","20"),null);
''';

/// رأس صفحة LAN: tx (المرسَل إلى جهاز المشترك) قبل rx.
const _lanHead = '''
var userEthInfos = new Array(new LANStats("InternetGatewayDevice.X_HW_DEBUG.AMP.LANPort.1.Statistics","2","128","0","0"),new LANStats("InternetGatewayDevice.X_HW_DEBUG.AMP.LANPort.4.Statistics","1469432","1868969319","767129","110806439"),null);
''';

OntByteCounters _c(Map<String, (int, int)> v, DateTime at) =>
    OntByteCounters({for (final e in v.entries) e.key: (sent: e.value.$1, received: e.value.$2, at: at)});

void main() {
  group('التحليل', () {
    test('الواي فاي: كلّ شبكة، والمسار يُفكّ من \\x2e، والمرسَل للمشترك = تحميله', () {
      final w = OntCounterParse.wifi(_wifiHead);
      expect(w.keys, [
        'InternetGatewayDevice.LANDevice.1.WLANConfiguration.1',
        'InternetGatewayDevice.LANDevice.1.WLANConfiguration.5',
      ]);
      expect(w['InternetGatewayDevice.LANDevice.1.WLANConfiguration.1'], (sent: 3638888413, received: 3386144779));
    });

    test('LAN: كلّ منفذ، tx قبل rx — منفذٌ عليه كلّ الترافيك تقريباً (لا الواي فاي وحده)', () {
      final l = OntCounterParse.lan(_lanHead);
      expect(l.length, 2);
      expect(l['InternetGatewayDevice.X_HW_DEBUG.AMP.LANPort.4.Statistics'], (sent: 1868969319, received: 110806439));
    });

    test('🚨 نهاية المصفوفة: الإعلان الفارغ لا يوقف القراءة — المملوءة أو null وحدهما', () {
      final m = OntCounterParse.wifiEnd.firstMatch(_wifiHead);
      expect(m, isNotNull);
      expect(_wifiHead.substring(0, m!.end), contains('new stPacketInfo('),
          reason: 'التوقّف عند «new Array();» الفارغة كان يُسقط الواي فاي كلّه');
      expect(OntCounterParse.wifiEnd.hasMatch('var PacketInfo = new Array();\n'), isFalse);
      expect(OntCounterParse.wifiEnd.hasMatch('PacketInfo = new Array(null);'), isTrue, reason: 'جهازٌ بلا واي فاي مفعّل');
      expect(OntCounterParse.lanEnd.hasMatch(_lanHead), isTrue);
      expect(OntCounterParse.lanEnd.hasMatch('var userEthInfos = new Array();'), isFalse);
    });
  });

  group('المعدّل', () {
    final t0 = DateTime(2026, 10, 22, 3);

    test('الأولى تزرع المرجع، ثمّ المجموع بالبت/ث — كلّ واجهةٍ بوقت صفحتها', () {
      final m = OntTrafficMeter();
      // الواي فاي يصل أوّلاً والـLAN بعده بثانية (صفحتان بالتتابع)
      final first = OntByteCounters({
        'W1': (sent: 1000, received: 500, at: t0),
        'L4': (sent: 0, received: 0, at: t0.add(const Duration(seconds: 1))),
      });
      expect(m.add(first, t0.add(const Duration(seconds: 1))), isNull);
      final second = OntByteCounters({
        'W1': (sent: 1000 + 625000, received: 500 + 25000, at: t0.add(const Duration(seconds: 5))),
        'L4': (sent: 1250000, received: 50000, at: t0.add(const Duration(seconds: 7))),
      });
      final r = m.add(second, t0.add(const Duration(seconds: 7)))!;
      // الواي فاي: 625000 بايت / 5ث = 1 ميغابت/ث؛ LAN: 1250000 / 6ث ≈ 1.667 ميغابت/ث — لا 1250000/7 بوقتٍ واحد
      expect(r.downBps, 1000000 + 1666667);
      expect(r.upBps, 40000 + 66667);
    });

    test('التفاف عدّاد ٣٢ بت يُحسب، وإعادة الإقلاع لا تعطي رقماً كاذباً', () {
      final m = OntTrafficMeter();
      m.add(_c({'W1': (4294000000, 10)}, t0), t0);
      final r = m.add(_c({'W1': (32704, 10)}, t0.add(const Duration(seconds: 5))), t0.add(const Duration(seconds: 5)))!;
      expect(r.downBps, ((4294967296 - 4294000000 + 32704) * 8 / 5).round());
      // تصفير (إقلاع): العدّاد عاد لقيمةٍ صغيرة من منتصفه — لا التفاف
      final reset = m.add(_c({'W1': (500, 10)}, t0.add(const Duration(seconds: 10))), t0.add(const Duration(seconds: 10)));
      expect(reset, isNull);
      // والتالية تحسب على المرجع الجديد
      final after = m.add(_c({'W1': (500 + 6250, 10)}, t0.add(const Duration(seconds: 15))), t0.add(const Duration(seconds: 15)))!;
      expect(after.downBps, 10000);
    });

    test('واجهةٌ ظهرت للتوّ لا تُحسب حتى قراءتها الثانية، وقراءةٌ شاذّة فوق ٢٫٥ جيجابت تُرفض', () {
      final m = OntTrafficMeter();
      m.add(_c({'W1': (0, 0)}, t0), t0);
      final r = m.add(_c({'W1': (62500, 0), 'W5': (999999999, 0)}, t0.add(const Duration(seconds: 5))),
          t0.add(const Duration(seconds: 5)))!;
      expect(r.downBps, 100000, reason: 'W5 جديدة — لا تُطرح من صفر');
      final crazy = m.add(_c({'W1': (62500 + 2000000000, 0), 'W5': (999999999, 0)}, t0.add(const Duration(seconds: 10))),
          t0.add(const Duration(seconds: 10)));
      expect(crazy, isNull);
    });

    test('قراءتان أقرب من نصف ثانية لا تعطيان معدّلاً', () {
      final m = OntTrafficMeter();
      m.add(_c({'W1': (0, 0)}, t0), t0);
      expect(m.add(_c({'W1': (1000, 0)}, t0.add(const Duration(milliseconds: 300))), t0.add(const Duration(milliseconds: 300))),
          isNull);
    });
  });

  group('قراءة الرأس وحده', () {
    test('تتوقّف عند المصفوفة المملوءة ولا تنتظر بقيّة الصفحة (٢ م.ب في بعض الطرازات)', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final tailDone = Completer<bool>();
      server.listen((req) async {
        req.response.headers.contentType = ContentType.html;
        req.response.write('x' * 7000);
        req.response.write(_wifiHead);
        await req.response.flush();
        // بقيّة الصفحة بطيئة وضخمة — لو انتظرتها القراءة لتجاوزت المهلة
        try {
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            req.response.write('y' * 50000);
            await req.response.flush();
          }
          await req.response.close();
          if (!tailDone.isCompleted) tailDone.complete(true);
        } catch (_) {
          if (!tailDone.isCompleted) tailDone.complete(false); // قطع العميلُ الاتّصال
        }
      });
      final session = OntLoginResult(sessionCookie: 'Cookie=sid=t', baseUrl: 'http://127.0.0.1:${server.port}');
      final sw = Stopwatch()..start();
      final text = await HuaweiOntService.fetchHead(session, '/html/amp/wlaninfo/wlaninfo.asp', OntCounterParse.wifiEnd);
      sw.stop();
      expect(text, isNotNull);
      expect(OntCounterParse.wifi(text!).length, 2);
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)), reason: 'لم تنتظر ٤ث من بقيّة الصفحة');
      expect(await tailDone.future.timeout(const Duration(seconds: 6), onTimeout: () => false), isFalse,
          reason: 'الاتّصال قُطع فلم يُكمل الجهاز إرسال بقيّة الصفحة');
      await server.close(force: true);
    });

    test('صفحة دخول (جلسةٌ طُردت) ⇒ null لا عدّاداتٌ قديمة', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.headers.contentType = ContentType.html;
        req.response.write("<html><script>top.location.replace('/login.asp');</script></html>");
        await req.response.close();
      });
      final session = OntLoginResult(sessionCookie: 'Cookie=sid=t', baseUrl: 'http://127.0.0.1:${server.port}');
      expect(await HuaweiOntService.fetchHead(session, '/html/amp/wlaninfo/wlaninfo.asp', OntCounterParse.wifiEnd), isNull);
      await server.close(force: true);
    });
  });

  test('الوثيقة: الصيغة utf8 لا تُفسد بايتاً عربيّاً مقطوعاً بين قطعتين', () {
    // القراءة تُفكّ مع كلّ قطعة — حرفٌ متعدّد البايت مقطوع لا يُسقط الفكّ (allowMalformed)
    final bytes = utf8.encode('عربي $_lanHead');
    final cut = utf8.decode(bytes.sublist(0, 3), allowMalformed: true);
    expect(cut, isNotEmpty);
  });
}
