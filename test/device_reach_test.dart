import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/device_reach.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_check_text.dart';
import 'package:rad_mysvcs/theme/colors.dart';

/// ١ نوفمبر — المالك: «اذا الجهاز حتى لو ما مضيوف صح المفروض تخلي زر فحص الجهاز بالبنك يرد ويظهر شعار الجهاز يرد بنك اتصال
/// ping تاكد من الاعدادات الجهاز». الفحص يثبت الوصول مستقلّاً عن السجلّ (ping أو منفذ إدارةٍ شائع)، ويفرّق «يردّ وإعداداته خطأ»
/// عن «لا يردّ». كلّ شيءٍ هنا بنتائج مزيّفة — لا شبكة.
NetworkDevice _dev({
  String brand = 'mikrotik',
  String? model,
  String? protocol = 'api',
  int port = 80,
  int? apiPort = 8729,
  String ip = '10.9.8.7',
}) =>
    NetworkDevice.fromJson({
      'id': 7,
      'admin_id': '1',
      'name': 'سكتر 1',
      'type': 'sector',
      'brand': brand,
      'model': model,
      'ip': ip,
      'port': port,
      'api_port': apiPort,
      'protocol': protocol,
      'has_credentials': 1,
      'last_status': 'unknown',
      'created_at': '2026-11-01T00:00:00Z',
    });

const ReachProbe _up = (status: 'online', responseMs: 9, packetLoss: 0.0);
const ReachProbe _down = (status: 'offline', responseMs: null, packetLoss: 100.0);

/// شبكةٌ مزيّفة: ردّ كلّ منفذ (وزمنه)، وردّ «الشاهد» على كلّ منفذ.
class _Net {
  final Map<int, (PortReply, int)> device = {};
  final Map<int, PortReply> canary = {};
  final List<int> knocked = [];
  final List<int> canaryAsked = [];

  Future<PortAnswer> connect(String host, int port, Duration timeout) async {
    if (host == DeviceReach.canaryHost) {
      canaryAsked.add(port);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return (port: port, reply: canary[port] ?? PortReply.silent, ms: null);
    }
    knocked.add(port);
    final r = device[port];
    if (r == null) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return (port: port, reply: PortReply.silent, ms: null);
    }
    await Future<void>.delayed(Duration(milliseconds: r.$2));
    return (port: port, reply: r.$1, ms: r.$2);
  }
}

void main() {
  late _Net net;

  setUp(() {
    DeviceReach.resetForTest();
    net = _Net();
    DeviceReach.debugConnect = net.connect;
  });
  tearDown(() {
    DeviceReach.resetForTest();
    NetworkDevicesApi.debugIcmpUsable = null;
    NetworkDevicesApi.debugService = null;
  });

  group('الحكم — decide', () {
    test('ping يردّ ⇒ يردّ بزمن الـping وفقدانه، والخدمة تُقال وحدها', () {
      final c = DeviceReach.decide(icmp: (status: 'online', responseMs: 4, packetLoss: 33.3), service: _down);
      expect([c.reachable, c.latencyMs, c.packetLoss, c.serviceOk, c.via, c.icmpTried], [true, 4, 33.3, false, ReachVia.ping, true]);
    });
    test('ping محجوب والخدمة تردّ ⇒ يردّ بزمن الخدمة بلا «فقدان 100%»', () {
      final c = DeviceReach.decide(icmp: _down, service: (status: 'online', responseMs: 21, packetLoss: 0.0));
      expect([c.reachable, c.latencyMs, c.packetLoss, c.serviceOk, c.via], [true, 21, null, true, ReachVia.service]);
    });
    test('🚨 لا ping ولا خدمة ومنفذٌ شائع يردّ ⇒ يردّ (الإعدادات خطأ) لا «مفصول»', () {
      final c = DeviceReach.decide(icmp: _down, service: _down, hit: (port: 8291, ms: 6, reply: PortReply.open));
      expect([c.reachable, c.latencyMs, c.packetLoss, c.serviceOk, c.via, c.port], [true, 6, null, false, ReachVia.port, 8291]);
    });
    test('لا شيء يردّ ⇒ لا يردّ — والفقدان 100% فقط إن أُرسل ping (iOS ⇒ «—»)', () {
      final android = DeviceReach.decide(icmp: _down, service: _down);
      expect([android.reachable, android.packetLoss, android.icmpTried], [false, 100.0, true]);
      final ios = DeviceReach.decide(service: _down);
      expect([ios.reachable, ios.packetLoss, ios.icmpTried, ios.latencyMs], [false, null, false, null]);
    });
  });

  group('المنافذ — portsFor', () {
    test('ميكروتك: منافذ علامته ثمّ العامّة، بلا منفذ خدمته', () {
      final ps = DeviceReach.portsFor(_dev(), exclude: {8729});
      expect(ps.take(2), [8728, 8291]);
      expect(ps, containsAll([80, 443, 22, 23, 8080]));
      expect(ps, isNot(contains(8729)));
      expect(ps.toSet().length, ps.length, reason: 'بلا تكرار');
    });
    test('الجولة الدوريّة بلا منافذ الدخول المحميّة (SSH · Telnet · FTP · Winbox)', () {
      final ps = DeviceReach.portsFor(_dev(), periodic: true);
      expect(ps.where(DeviceReach.guarded.contains), isEmpty);
      expect(ps, containsAll([8728, 80, 443]));
    });
    test('أولت (العلامة أو طرازٌ يقول HSGQ على سجلٍّ «أخرى») ⇒ الويب وTelnet أوّلاً', () {
      expect(DeviceReach.portsFor(_dev(brand: 'hsgq', protocol: 'snmp', apiPort: 444)).take(2), [80, 23]);
      expect(DeviceReach.portsFor(_dev(brand: 'other', model: 'HSGQ OLT', protocol: 'snmp')).take(2), [80, 23]);
    });
    test('علامةٌ مجهولة ⇒ العامّة وحدها', () {
      expect(DeviceReach.portsFor(_dev(brand: 'other', protocol: null)), DeviceReach.genericPorts);
    });
  });

  group('الشاهد — ردودٌ تختلقها الشبكة لا تُحسب', () {
    test('اتّصالٌ على منفذٍ ليس للويب ⇒ يُحسب بلا شاهد', () {
      expect(DeviceReach.needsCanary(8291, PortReply.open), isFalse);
      expect(DeviceReach.counts(8291, PortReply.open, null), isTrue);
    });
    test('🚨 :80 «اتّصل» والشاهد اتّصل كذلك (وسيط الموبايل) ⇒ لا يُحسب؛ الشاهد صامت ⇒ يُحسب', () {
      expect(DeviceReach.counts(80, PortReply.open, PortReply.open), isFalse);
      expect(DeviceReach.counts(80, PortReply.open, PortReply.silent), isTrue);
    });
    test('الرفض (RST) يُحسب حين يصمت الشاهد وحده — جدارٌ يرفض كلّ شيء لا يُثبت جهازاً', () {
      expect(DeviceReach.counts(23, PortReply.refused, PortReply.silent), isTrue);
      expect(DeviceReach.counts(23, PortReply.refused, PortReply.refused), isFalse);
      expect(DeviceReach.counts(23, PortReply.silent, PortReply.silent), isFalse);
    });
    test('حكم الشاهد محفوظٌ ٣٠ث ومشارَك: جولةٌ من عشرات الأجهزة = سؤالٌ واحد', () async {
      var t = DateTime(2026, 11, 1, 1);
      DeviceReach.now = () => t;
      final a = DeviceReach.canary(80);
      final b = DeviceReach.canary(80);
      expect(await a, PortReply.silent);
      expect(await b, PortReply.silent);
      expect(net.canaryAsked, [80]);
      t = t.add(const Duration(seconds: 31));
      await DeviceReach.canary(80);
      expect(net.canaryAsked, [80, 80], reason: 'انتهت النافذة — يُسأل ثانيةً (الهاتف قد انتقل من الواي فاي)');
    });
  });

  group('المسح — sweep', () {
    test('أوّل ردٍّ مُصدَّق يفوز ولا ينتظر أبطأها', () async {
      net.device[8728] = (PortReply.open, 3);
      final sw = Stopwatch()..start();
      final hit = await DeviceReach.sweep('10.9.8.7', [8728, 443, 80]);
      expect([hit?.port, hit?.ms, hit?.reply], [8728, 3, PortReply.open]);
      expect(sw.elapsedMilliseconds, lessThan(30), reason: 'المنافذ الصامتة (30ms) لم تُنتظر');
    });
    test('لا يردّ شيء ⇒ null', () async {
      expect(await DeviceReach.sweep('10.9.8.7', [80, 443, 8728]), isNull);
    });
    test('🚨 :80 عبر وسيط الموبايل (الشاهد يتّصل) لا يُثبت جهازاً — و:8728 الحقيقيّ يُثبته', () async {
      net.device[80] = (PortReply.open, 1);
      net.canary[80] = PortReply.open;
      expect(await DeviceReach.sweep('10.9.8.7', [80]), isNull);
      net.device[8728] = (PortReply.open, 8);
      expect((await DeviceReach.sweep('10.9.8.7', [80, 8728]))?.port, 8728);
    });
    test('منافذ الدخول المحميّة: لا تُطرق إن ردّ غيرها، ولا في الجولة الدوريّة أبداً', () async {
      net.device[443] = (PortReply.open, 2);
      net.device[22] = (PortReply.open, 2);
      expect((await DeviceReach.sweep('10.9.8.7', [443, 22, 23, 8291], allowGuarded: true))?.port, 443);
      expect(net.knocked, [443]);
      net.knocked.clear();
      net.device.remove(443);
      expect(await DeviceReach.sweep('10.9.8.7', [443, 22, 23, 8291]), isNull, reason: 'الدوريّ: SSH وحده يردّ لكنّه لا يُطرق');
      expect(net.knocked, [443]);
    });
    test('🚨 SSH وحده يردّ: يُطرق مرّةً كلّ دقيقتين للعنوان، وما ثبت يُعاد داخل النافذة (فحصان لا يقولان قولين)', () async {
      var t = DateTime(2026, 11, 1, 1);
      DeviceReach.now = () => t;
      net.device[22] = (PortReply.open, 4);
      final first = await DeviceReach.sweep('10.9.8.7', [80, 22], allowGuarded: true);
      expect(first?.port, 22);
      expect(net.knocked.where((p) => p == 22).length, 1);
      t = t.add(const Duration(seconds: 50));
      final again = await DeviceReach.sweep('10.9.8.7', [80, 22], allowGuarded: true);
      expect(again?.port, 22);
      expect(net.knocked.where((p) => p == 22).length, 1, reason: 'لا طرقة ثانية خلال دقيقتين — قواعد حماية التخمين');
      t = t.add(const Duration(minutes: 2));
      await DeviceReach.sweep('10.9.8.7', [80, 22], allowGuarded: true);
      expect(net.knocked.where((p) => p == 22).length, 2);
    });
  });

  group('الفحص — checkDevice / probeDevice', () {
    setUp(() {
      NetworkDevicesApi.debugService = (_) async => _down; // منفذه المسجّل خطأ.
    });

    test('🚨 iOS (لا ping) والمنفذ المسجّل خطأ وواجهة الويب تردّ (الشاهد صامت) ⇒ يردّ بزمنه، والخدمة لا', () async {
      NetworkDevicesApi.debugIcmpUsable = false;
      net.device[80] = (PortReply.open, 11);
      final c = await NetworkDevicesApi.checkDevice(_dev(brand: 'hsgq', protocol: 'snmp', apiPort: 444));
      expect([c.reachable, c.latencyMs, c.packetLoss, c.serviceOk, c.via, c.port, c.icmpTried], [true, 11, null, false, ReachVia.port, 80, false]);
    });

    test('أندرويد: ping يردّ والخدمة لا ⇒ يردّ بزمن الـping (٣ حزم)', () async {
      final pings = <int>[];
      NetworkDevicesApi.debugIcmpUsable = true;
      NetworkDevicesApi.icmpProbe = (ip, n) async {
        pings.add(n);
        return (status: 'online', responseMs: 5, packetLoss: 0.0);
      };
      final c = await NetworkDevicesApi.checkDevice(_dev());
      expect([c.reachable, c.latencyMs, c.packetLoss, c.serviceOk, c.via], [true, 5, 0.0, false, ReachVia.ping]);
      expect(pings, [3]);
    });

    test('جهازٌ يحجب ping ومنفذه خطأ وWinbox يردّ ⇒ يردّ بلا «فقدان 100%»', () async {
      NetworkDevicesApi.debugIcmpUsable = true;
      NetworkDevicesApi.icmpProbe = (ip, n) async => _down;
      net.device[8291] = (PortReply.open, 6);
      final c = await NetworkDevicesApi.checkDevice(_dev());
      expect([c.reachable, c.latencyMs, c.packetLoss, c.serviceOk, c.port], [true, 6, null, false, 8291]);
    });

    test('لا شيء يردّ ⇒ لا يردّ (والفقدان 100% مع ping)', () async {
      NetworkDevicesApi.debugIcmpUsable = true;
      NetworkDevicesApi.icmpProbe = (ip, n) async => _down;
      final c = await NetworkDevicesApi.checkDevice(_dev());
      expect([c.reachable, c.packetLoss, c.serviceOk], [false, 100.0, false]);
    });

    test('الدوريّ (القائمة) على iOS: يُسأل بلا منافذ الدخول المحميّة، و:443 يكفي ⇒ «متّصل» لا «مفصول»', () async {
      NetworkDevicesApi.debugIcmpUsable = false;
      net.device[443] = (PortReply.open, 9);
      final r = await NetworkDevicesApi.probeDevice(_dev());
      expect([r.status, r.responseMs, r.packetLoss, r.serviceOk], ['online', 9, null, false]);
      expect(net.knocked.where(DeviceReach.guarded.contains), isEmpty);
    });

    test('الدوريّ: الخدمة تردّ ⇒ لا ping ولا منافذ (أخفّ)', () async {
      NetworkDevicesApi.debugService = (_) async => _up;
      NetworkDevicesApi.debugIcmpUsable = true;
      var pinged = false;
      NetworkDevicesApi.icmpProbe = (ip, n) async {
        pinged = true;
        return _up;
      };
      final r = await NetworkDevicesApi.probeDevice(_dev());
      expect([r.status, r.serviceOk], ['online', true]);
      expect(pinged, isFalse);
      expect(net.knocked, isEmpty);
    });

    test('الدوريّ: ping يردّ ⇒ لا تُطرق المنافذ', () async {
      NetworkDevicesApi.debugIcmpUsable = true;
      NetworkDevicesApi.icmpProbe = (ip, n) async => _up;
      final r = await NetworkDevicesApi.probeDevice(_dev());
      expect([r.status, r.serviceOk], ['online', false]);
      expect(net.knocked, isEmpty);
    });

    test('الدوريّ حيث يصلح ping (أندرويد/الحاسبة): لا يردّ ⇒ مفصول بلا مسح منافذ — جهازٌ مطفأ لا يدفع مهلةً ثالثة كلّ جولة', () async {
      NetworkDevicesApi.debugIcmpUsable = true;
      NetworkDevicesApi.icmpProbe = (ip, n) async => _down;
      net.device[443] = (PortReply.open, 3);
      final r = await NetworkDevicesApi.probeDevice(_dev());
      expect(r.status, 'offline');
      expect(net.knocked, isEmpty);
      // والزرّ يمسحها: جهازٌ يحجب ping وواجهته تردّ.
      final c = await NetworkDevicesApi.checkDevice(_dev());
      expect([c.reachable, c.port], [true, 443]);
    });
  });

  group('النصّ — DeviceCheckText', () {
    test('🚨 يردّ وخدمته لا ⇒ «الجهاز يردّ على الاتصال (ping) — تأكّد من إعدادات الجهاز: اسم المستخدم وكلمة المرور والمنفذ»', () {
      final d = _dev();
      final n = DeviceCheckText.note(d, DeviceReach.decide(icmp: _up, service: _down))!;
      expect(n.tone, AppTone.warning);
      expect(n.title, 'الجهاز يردّ على الاتصال (ping)');
      expect(n.detail, startsWith('تأكّد من إعدادات الجهاز: اسم المستخدم وكلمة المرور والمنفذ'));
      expect(n.detail, contains('8729'));
      expect(n.line, isNot(contains('مفصول')));
    });
    test('يردّ وخدمته تردّ لكنّ قراءة اللوحة فشلت (كلمة المرور) ⇒ السطر نفسه بلا اسم الخدمة', () {
      final n = DeviceCheckText.note(_dev(), DeviceReach.decide(icmp: _up, service: _up), readError: 'اسم المستخدم أو كلمة المرور خاطئة')!;
      expect(n.line, 'الجهاز يردّ على الاتصال (ping) — تأكّد من إعدادات الجهاز: اسم المستخدم وكلمة المرور والمنفذ');
    });
    test('لا ping (iOS) ومنفذ خدمته يقبل والدخول يفشل ⇒ يُسمّى منفذ الخدمة لا «ping»', () {
      final n = DeviceCheckText.note(_dev(apiPort: 8728), DeviceReach.decide(service: _up), readError: 'اسم المستخدم أو كلمة المرور خاطئة')!;
      expect(n.title, 'الجهاز يردّ على الاتصال (المنفذ 8728)');
      expect(n.detail, 'تأكّد من إعدادات الجهاز: اسم المستخدم وكلمة المرور والمنفذ');
    });
    test('SNMP ⇒ الـcommunity والمنفذ؛ وثبت بمنفذٍ لا بـping ⇒ يُسمّى المنفذ', () {
      final d = _dev(brand: 'hsgq', protocol: 'snmp', apiPort: 444);
      final n = DeviceCheckText.note(d, DeviceReach.decide(service: _down, hit: (port: 80, ms: 4, reply: PortReply.open)))!;
      expect(n.title, 'الجهاز يردّ على الاتصال (المنفذ 80)');
      expect(n.detail, startsWith('تأكّد من إعدادات الجهاز: الـcommunity والمنفذ'));
    });
    test('لا يردّ ⇒ «لا يردّ على ping — تأكّد من العنوان والشبكة» (وبلا ping: «لا يردّ على الاتصال»)', () {
      final n = DeviceCheckText.note(_dev(), DeviceReach.decide(icmp: _down, service: _down))!;
      expect([n.line, n.tone], ['لا يردّ على ping — تأكّد من العنوان والشبكة', AppTone.danger]);
      expect(DeviceCheckText.note(_dev(), DeviceReach.decide(service: _down))!.title, 'لا يردّ على الاتصال');
    });
    test('يردّ وكلّ شيءٍ سليم، أو لم يُفحص بعد ⇒ لا سطر', () {
      expect(DeviceCheckText.note(_dev(), DeviceReach.decide(icmp: _up, service: _up)), isNull);
      expect(DeviceCheckText.note(_dev(), null), isNull);
    });
    test('جهاز «ICMP فقط» (بلا بروتوكول) يردّ ⇒ لا تحذير: منفذه الافتراضيّ ليس خدمةً تُراجَع', () {
      final d = _dev(protocol: null, apiPort: null);
      final c = DeviceReach.decide(icmp: _up, service: _down);
      expect(DeviceCheckText.note(d, c), isNull);
      expect(DeviceCheckText.afterSave(d, c, created: true), startsWith('تمّت إضافة الجهاز — يردّ على الاتصال'));
    });
    test('إشعار ما بعد الحفظ يقول النتيجة', () {
      final d = _dev();
      expect(DeviceCheckText.afterSave(d, DeviceReach.decide(icmp: _up, service: _down), created: true),
          allOf(startsWith('تمّت إضافة الجهاز — الجهاز يردّ على الاتصال (ping)'), contains('تأكّد من إعدادات الجهاز')));
      expect(DeviceCheckText.afterSave(d, DeviceReach.decide(icmp: _down, service: _down), created: false),
          'تمّ الحفظ — لا يردّ على ping: تأكّد من العنوان والشبكة');
      expect(DeviceCheckText.afterSave(d, DeviceReach.decide(icmp: _up, service: _up), created: true), startsWith('تمّت إضافة الجهاز — يردّ على الاتصال'));
    });
  });
}
