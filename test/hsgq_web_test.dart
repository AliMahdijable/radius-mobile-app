import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show md5;
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/hsgq_olt.dart';
import 'package:rad_mysvcs/api/hsgq_web.dart';
import 'package:rad_mysvcs/api/olt_profile.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';

import 'support/snmp_wire.dart';

/// ١٦ نوفمبر — المالك: «اولتي HGSC… شوفلي كيف ممكن نضيفه للنظام» ثمّ «هو بي ssh وتنلنت… سوي قارئ ويب وشوف ياطريقة سريعه
/// وتفيدنا». أولت HSGQ-E04 ببرمجيّة V3.0.18 (حساب 1674): SNMP يعرف المنافذ والضوء، وجدول الـONU «noSuchObject» — فكان التطبيق
/// يعرض أولتاً بلا مشتركين. القائمة من صفحته (`/onu_allow_list`) والضوء من SNMP كما كان.
/// الأولت هنا وهميّ على ما قِيس من الجهاز؛ الماكات اصطناعيّة (‏02:…)، والصفحة الوهميّة تدخل كما يدخل الجهاز (md5 + base64).

Varbind _int(String oid, int v) {
  final out = <int>[];
  var x = v;
  while (true) {
    out.insert(0, x & 0xff);
    final sign = x & 0x80;
    x >>= 8;
    if ((x == 0 && sign == 0) || (x == -1 && sign != 0)) break;
  }
  return Varbind(oid: oid, rawTag: 0x02, rawBytes: Uint8List.fromList(out));
}

Varbind _str(String oid, List<int> bytes) => Varbind(oid: oid, rawTag: 0x04, rawBytes: Uint8List.fromList(bytes));
Varbind _noInstance(String oid) => Varbind(oid: oid, rawTag: 0x81, rawBytes: Uint8List(0));
Varbind _noObject(String oid) => Varbind(oid: oid, rawTag: 0x80, rawBytes: Uint8List(0));

const _ifDescr = '1.3.6.1.2.1.2.2.1.2';
const _ifOper = '1.3.6.1.2.1.2.2.1.8';
const _host = 'olt-e04';

int _i(int pon, int onu) => HsgqOlt.onuIndex(pon, onu);

/// HSGQ-E04 ‏V3.0.18 كما قِيس: الهويّة والمنافذ (PON1…4، GE1…8) والضوء للمتّصلة — وجدول الـONU غائب («noSuchObject»).
/// [table] = أولتٌ أحدث فيه الجدول (الموضع الفارغ «noSuchInstance»).
class _FakeOlt {
  _FakeOlt({this.table = false});
  final bool table;
  final data = <String, Varbind>{};
  final asked = <String>[];

  Future<List<Varbind>> get(List<String> oids) async {
    asked.addAll(oids);
    return [
      for (final o in oids)
        data[o] ?? (!table && o.startsWith('${HsgqWeb.onuTable}.') ? _noObject(o) : _noInstance(o)),
    ];
  }
}

_FakeOlt _e04({bool table = false}) {
  final f = _FakeOlt(table: table);
  void put(Varbind v) => f.data[v.oid] = v;
  put(_int(HsgqOlt.ponCountOid, 4));
  put(_int(HsgqOlt.portCountOid, 12));
  put(_str(HsgqOlt.firmwareOid, [...ascii.encode('I_V3.0.18_Rel'), ...List.filled(19, 0)]));
  const names = ['PON1', 'PON2', 'PON3', 'PON4', 'GE1', 'GE2', 'GE3', 'GE4', 'GE5', 'GE6', 'GE7', 'GE8'];
  for (var k = 1; k <= 12; k++) {
    put(_str('$_ifDescr.$k', ascii.encode(names[k - 1])));
    put(_int('$_ifOper.$k', k <= 3 || k == 5 ? 1 : 2));
  }
  // الضوء للمتّصلة وحدها (`.3.3.3.1.4` بوحدة ٠٫٠١ dBm)
  for (final (pon, onu, rx) in [(1, 1, -2823), (1, 24, -2112), (3, 60, -1950), (3, 70, -2401)]) {
    put(_int(HsgqOlt.opticsOid(4, _i(pon, onu)), rx));
  }
  return f;
}

/// صفحة الأولت الوهميّة.
class _FakeWeb {
  late HttpServer server;
  final paths = <String>[];
  final tokens = <String>{};
  int logins = 0;
  String user = 'root', pass = 'admin';
  final rows = <int, List<Map<String, dynamic>>>{
    1: [
      _row(1, 1, 'ONU01/01', '02:00:00:01:01:00', 'Online'),
      _row(1, 2, 'حسين - برج ٣', '02:00:00:01:02:00', 'Initial'),
      _row(1, 24, 'ONU01/24', '02:00:00:01:18:00', 'Online'),
    ],
    2: [_row(2, 1, 'ONU02/01', '02:00:00:02:01:00', 'Offline')],
    3: [
      _row(3, 60, 'abbas-cafe', '02:00:00:03:3c:00', 'Online'),
      _row(3, 70, 'ONU03/70', '02:00:00:03:46:00', 'Online'),
    ],
    4: [],
  };

  static Map<String, dynamic> _row(int pon, int onu, String name, String mac, String status) => {
        'port_id': pon,
        'onu_id': onu,
        'onu_name': name,
        'macaddr': mac,
        'status': status,
        'auth_state': 1,
        'receive_power': '-23.10',
        'dev_type': 'HGU',
        'register_time': '2026/11/16 21:31:53',
        'last_down_time': 'None',
        'last_down_reason': '',
        'parent': '0',
      };

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
    HsgqWeb.urlFor = (h, p) => Uri.parse('http://127.0.0.1:${server.port}$p');
  }

  Future<void> _handle(HttpRequest r) async {
    paths.add('${r.method} ${r.uri}');
    Map<String, dynamic> out;
    if (r.method == 'POST' && r.uri.path == '/userlogin' && r.uri.queryParameters['form'] == 'login') {
      final body = jsonDecode(await utf8.decoder.bind(r).join()) as Map;
      final p = body['param'] as Map;
      logins++;
      final ok = p['name'] == user &&
          p['key'] == md5.convert(utf8.encode('$user:$pass')).toString() &&
          p['value'] == base64.encode(utf8.encode(pass)) &&
          p['captcha_v'] == '';
      if (ok) {
        final t = 'tok$logins';
        tokens.add(t);
        r.response.headers.set('x-token', t);
        out = {'code': 1, 'message': 'success'};
      } else {
        out = {'code': 2, 'message': 'user name or password error'};
      }
    } else if (!tokens.contains(r.headers.value('x-token'))) {
      out = {'code': 0, 'message': 'illegal login'};
    } else if (r.uri.path == '/board' && r.uri.queryParameters['info'] == 'pon') {
      out = {
        'code': 1,
        'data': [
          for (final p in rows.keys) {'port_id': p, 'status': 1, 'online': 0, 'offline': 0},
        ],
      };
    } else if (r.uri.path == '/onu_allow_list') {
      out = {'code': 1, 'data': rows[int.parse(r.uri.queryParameters['port_id']!)] ?? const []};
    } else {
      out = {'code': 2, 'message': 'not here'};
    }
    r.response.headers.contentType = ContentType.json;
    r.response.write(jsonEncode(out));
    await r.response.close();
  }

  int count(String what) => paths.where((p) => p.contains(what)).length;
}

final _profile = OltProfile.resolve(OltProfile.fromRecord(brand: 'hsgq'), sysObjectId: '1.3.6.1.4.1.50224.3.1.1', sysDescr: 'SNMP_V1.0');

void main() {
  late _FakeWeb web;
  setUp(() async {
    HsgqWeb.resetForTest();
    web = _FakeWeb();
    await web.start();
  });
  tearDown(() async {
    HsgqWeb.resetForTest();
    await web.server.close(force: true);
  });

  /// ما يفعله `SnmpV2c.get`: جوابٌ جاهز قبل الإرسال إن وُجد، وإلّا الأولت الوهميّ ثمّ الخطّاف.
  HsgqGet via(_FakeOlt olt) => (oids) async {
        final ready = await HsgqWeb.answer(_host, oids);
        if (ready != null) return ready;
        return HsgqWeb.fill(_host, await olt.get(oids));
      };

  group('E04 ‏V3.0.18: القائمة من الصفحة، والضوء من SNMP', () {
    test('🚨 كلّ ONU بحالتها وماكها واسمها المكتوب — كان «٠ مشترك»', () async {
      HsgqWeb.register(_host, 'root', 'admin');
      final olt = _e04();
      final s = await HsgqOlt.fetchStats(via(olt), profile: _profile, host: _host);
      expect(s.onus, hasLength(6));
      final on = {for (final o in s.onus) '${o.ponPort}/${o.onuId}': o.online};
      expect(on, {'1/1': true, '1/2': false, '1/24': true, '2/1': false, '3/60': true, '3/70': true},
          reason: '«Initial» و«Offline» مفصولتان، و٧٠ تظهر بمسح ما فوق الـ٦٤');
      final byKey = {for (final o in s.onus) '${o.ponPort}/${o.onuId}': o};
      expect(byKey['1/1']!.mac?.toLowerCase(), '02:00:00:01:01:00');
      expect(byKey['3/70']!.mac?.toLowerCase(), '02:00:00:03:46:00');
      expect(byKey['1/2']!.name, 'حسين - برج ٣', reason: 'الاسم المكتوب يبقى (عربيّ)');
      expect(byKey['3/60']!.name, 'abbas-cafe');
      expect(byKey['1/1']!.name, isNull, reason: 'الافتراضيّ «ONU01/01» لا يُعرض (كالأولت الأحدث)');
      final pons = {for (final p in s.ponPorts) p.port: (p.onuTotal, p.onuOnline)};
      expect(pons[1], (3, 2));
      expect(pons[2], (1, 0));
      expect(pons[3], (2, 2));
      expect(s.uplinks.map((u) => u.name), containsAll(['GE1', 'GE8']));
      // الضوء من SNMP كما كان — لا طلب للصفحة
      final pages = web.paths.length;
      final readings = await HsgqOlt.readings(via(olt), [for (final o in s.onus) if (o.online) o.ifIndex]);
      expect(readings[_i(1, 1)]?.rxDbm, closeTo(-28.23, 0.001));
      expect(readings[_i(3, 70)]?.rxDbm, closeTo(-24.01, 0.001));
      expect(web.paths.length, pages, reason: 'الضوء لا يمرّ بالصفحة');
    });

    test('⚡ قراءةٌ كاملة = دخولٌ واحد + طلبٌ لكلّ منفذ — مهما تعدّدت دفعات GET', () async {
      HsgqWeb.register(_host, 'root', 'admin');
      final olt = _e04();
      await HsgqOlt.fetchStats(via(olt), profile: _profile, host: _host);
      expect(olt.asked.where((o) => o.startsWith(HsgqWeb.onuTable)).length, 16,
          reason: 'دفعةٌ أولى تكشف أنّ الجدول غائب، والباقي (‏٣٠٠+ موضع وماك واسم) من الصفحة بلا رحلة SNMP');
      expect(web.logins, 1);
      expect(web.count('/board?info=pon'), 1);
      expect(web.count('/onu_allow_list'), 4, reason: 'منفذٌ لكلّ طلب، مرّةً واحدة');
      // تجديد الحالة ضمن النافذة نفسها ⇒ لا طلب جديد
      final asked = olt.asked.length;
      final s = await HsgqOlt.fetchStats(via(olt), profile: _profile, host: _host);
      await HsgqOlt.refreshStatus(via(olt), s);
      expect(web.count('/onu_allow_list'), 4);
      expect(olt.asked.skip(asked).where((o) => o.startsWith(HsgqWeb.onuTable)), isEmpty,
          reason: 'الجدول معروفٌ غيابه — لا سؤال للأولت عنه');
    });

    test('⛔ قراءة وحدها: لا يُطلب إلّا الدخول وقائمة المنافذ والـONU', () async {
      HsgqWeb.register(_host, 'root', 'admin');
      await HsgqOlt.fetchStats(via(_e04()), profile: _profile, host: _host);
      for (final p in web.paths) {
        expect(p, matches(RegExp(r'^(POST /userlogin\?form=login|GET /board\?info=pon|GET /onu_allow_list\?port_id=\d+)$')), reason: p);
        expect(p, isNot(matches(RegExp(r'reboot|def_config|system_save|upgrade|restore'))));
      }
    });

    test('ONU فصلت ⇒ تجديد الحالة يُظهرها مفصولة (بعد نافذة الخبء)', () async {
      HsgqWeb.register(_host, 'root', 'admin');
      final olt = _e04();
      final s = await HsgqOlt.fetchStats(via(olt), profile: _profile, host: _host);
      web.rows[1]![0] = {...web.rows[1]![0], 'status': 'Offline'};
      HsgqWeb.tableTtl = Duration.zero;
      final r = await HsgqOlt.refreshStatus(via(olt), s);
      expect(r, isNotNull);
      final o = r!.stats.onus.firstWhere((o) => o.ponPort == 1 && o.onuId == 1);
      expect(o.online, isFalse);
    });

    test('الجلسة انتهت ⇒ دخولٌ جديد واحد ثمّ القراءة', () async {
      HsgqWeb.register(_host, 'root', 'admin');
      final olt = _e04();
      await HsgqOlt.fetchStats(via(olt), profile: _profile, host: _host);
      web.tokens.clear();
      HsgqWeb.tableTtl = Duration.zero;
      final s = await HsgqOlt.fetchStats(via(olt), profile: _profile, host: _host);
      expect(s.onus, hasLength(6));
      expect(web.logins, 2);
    });
  });

  group('ما يقوله حين لا تُقرأ القائمة — لا «٠ مشترك»', () {
    test('بلا دخولٍ محفوظ ⇒ «أضف دخول صفحة الأولت»، ولا طلب للصفحة', () async {
      await expectLater(
        HsgqOlt.fetchStats(via(_e04()), profile: _profile, host: _host),
        throwsA(isA<VsolException>().having((e) => e.message, 'message', contains('أضف «دخول صفحة الأولت»'))),
      );
      expect(web.paths, isEmpty);
    });

    test('🚨 كلمة مرورٍ خطأ ⇒ رسالةٌ تقول ما يلزم، ودخولٌ واحد لا سيل (لا قفل على حساب الوكيل)', () async {
      HsgqWeb.register(_host, 'root', 'wrong-pass');
      final olt = _e04();
      Matcher says(String s) => throwsA(isA<VsolException>().having((e) => e.message, 'message', contains(s)));
      await expectLater(HsgqOlt.fetchStats(via(olt), profile: _profile, host: _host), says('غير صحيحة'));
      HsgqWeb.tableTtl = Duration.zero;
      await expectLater(HsgqOlt.fetchStats(via(olt), profile: _profile, host: _host), says('غير صحيحة'));
      expect(web.logins, 1, reason: 'المرفوضة لا تُعاد بالكلمة نفسها قبل عشر دقائق');
      // كلمةٌ جديدة ⇒ تُجرَّب فوراً
      HsgqWeb.register(_host, 'root', 'admin');
      final s = await HsgqOlt.fetchStats(via(olt), profile: _profile, host: _host);
      expect(s.onus, hasLength(6));
      expect(web.logins, 2);
    });

    test('الصفحة لا تردّ ⇒ «لا تردّ» والفشل لا يُعاد مع كلّ دفعة', () async {
      HsgqWeb.register(_host, 'root', 'admin');
      HsgqWeb.timeout = const Duration(milliseconds: 300);
      await web.server.close(force: true);
      final olt = _e04();
      await expectLater(
        HsgqOlt.fetchStats(via(olt), profile: _profile, host: _host),
        throwsA(isA<VsolException>().having((e) => e.message, 'message', contains('لا تردّ'))),
      );
      await web.start(); // تعود — والفشل القريب لا يُعاد قبل نصف دقيقة
      await expectLater(HsgqOlt.fetchStats(via(olt), profile: _profile, host: _host), throwsA(isA<VsolException>()));
      expect(web.paths, isEmpty);
    });
  });

  group('لا يمسّ غيره', () {
    test('أولت HSGQ أحدث (جدوله موجود) ⇒ لا طلب للصفحة ولو حُفظ دخولها', () async {
      HsgqWeb.register(_host, 'root', 'admin');
      final olt = _e04(table: true);
      olt.data[HsgqOlt.statusOid(_i(1, 1))] = _int(HsgqOlt.statusOid(_i(1, 1)), 1);
      final s = await HsgqOlt.fetchStats(via(olt), profile: _profile, host: _host);
      expect(s.onus, hasLength(1));
      expect(web.paths, isEmpty);
    });

    test('عنوانٌ آخر بلا دخول ⇒ الخطّاف لا يفعل شيئاً', () async {
      HsgqWeb.register(_host, 'root', 'admin');
      final vbs = [_noObject('${HsgqWeb.onuTable}.8.${_i(1, 1)}')];
      final out = await HsgqWeb.fill('10.9.9.9', vbs);
      expect(identical(out, vbs), isTrue);
      expect(web.paths, isEmpty);
    });

    test('الخطّافان يُركَّبان بالتسجيل ويُفكّان بالتصفير', () {
      expect((SnmpV2c.afterGet, SnmpV2c.beforeGet), (null, null));
      HsgqWeb.register(_host, 'root', 'admin');
      expect(SnmpV2c.afterGet, isNotNull);
      expect(SnmpV2c.beforeGet, isNotNull);
      HsgqWeb.register(_host, '', '');
      expect(HsgqWeb.has(_host), isFalse, reason: 'دخولٌ فارغ يُنسى');
      HsgqWeb.resetForTest();
      expect((SnmpV2c.afterGet, SnmpV2c.beforeGet), (null, null));
    });

    test('🚨 على السلك: عميل SnmpV2c الحقيقيّ + وكيل UDP — GET وحده، ودفعة الجدول الأولى فقط تذهب للأولت', () async {
      final olt = _e04();
      olt.data['1.3.6.1.2.1.1.1.0'] = _str('1.3.6.1.2.1.1.1.0', ascii.encode('SNMP_V1.0'));
      // sysObjectID = 1.3.6.1.4.1.50224.3.1.1 (BER)
      olt.data['1.3.6.1.2.1.1.2.0'] = Varbind(
          oid: '1.3.6.1.2.1.1.2.0',
          rawTag: 0x06,
          rawBytes: Uint8List.fromList([0x2B, 0x06, 0x01, 0x04, 0x01, 0x83, 0x88, 0x30, 0x03, 0x01, 0x01]));
      olt.data['1.3.6.1.2.1.1.5.0'] = _str('1.3.6.1.2.1.1.5.0', ascii.encode('iProc'));
      final sock = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(sock.close);
      var bulk = 0;
      sock.listen((e) async {
        if (e != RawSocketEvent.read) return;
        final dg = sock.receive();
        if (dg == null) return;
        final req = SnmpWireRequest.parse(Uint8List.fromList(dg.data));
        if (req.bulk) bulk++;
        sock.send(req.reply(await olt.get(req.oids)), dg.address, dg.port);
      });
      HsgqWeb.register('127.0.0.1', 'root', 'admin');
      final s = await VsolOltApi.fetchStats(
          host: '127.0.0.1', port: sock.port, community: 'public', profile: OltProfile.fromRecord(brand: 'hsgq'));
      expect(s.profile.vendor, OltVendor.hsgq);
      expect(s.onus, hasLength(6));
      expect(s.onus.where((o) => o.mac != null), hasLength(6));
      expect(bulk, 0, reason: 'لا مسح على HSGQ');
      expect(olt.asked.where((o) => o.startsWith(HsgqWeb.onuTable)).length, 16);
      expect(web.logins, 1);
    });
  });

  group('التحويل (نقيّ)', () {
    final rows = {
      _i(1, 1): const HsgqWebOnu(pon: 1, onu: 1, online: true, mac: '9c:28:ef:68:25:52', name: 'ONU01/01'),
      _i(1, 2): const HsgqWebOnu(pon: 1, onu: 2, online: false, mac: '00:00:00:00:00:00', name: ''),
    };
    test('الحالة 1/2، والماك ستّة بايتات، والاسم نصّاً؛ الغائب «noSuchInstance»', () {
      final st = HsgqWeb.virtualOf('${HsgqWeb.onuTable}.8.${_i(1, 1)}', rows);
      expect((st.rawTag, st.asInt), (0x02, 1));
      expect(HsgqWeb.virtualOf('${HsgqWeb.onuTable}.8.${_i(1, 2)}', rows).asInt, 2);
      expect(HsgqWeb.virtualOf('${HsgqWeb.onuTable}.7.${_i(1, 1)}', rows).asMac, '9C:28:EF:68:25:52');
      expect(HsgqWeb.virtualOf('${HsgqWeb.onuTable}.7.${_i(1, 2)}', rows).rawTag, 0x81, reason: 'ماك أصفار = لا ماك');
      expect(utf8.decode(HsgqWeb.virtualOf('${HsgqWeb.onuTable}.2.${_i(1, 1)}', rows).rawBytes), 'ONU01/01');
      expect(HsgqWeb.virtualOf('${HsgqWeb.onuTable}.2.${_i(1, 2)}', rows).rawTag, 0x81);
      expect(HsgqWeb.virtualOf('${HsgqWeb.onuTable}.25.${_i(1, 1)}', rows).rawTag, 0x81, reason: 'الصانع لا تعرفه الصفحة');
      expect(HsgqWeb.virtualOf('${HsgqWeb.onuTable}.8.${_i(2, 9)}', rows).rawTag, 0x81, reason: 'موضعٌ بلا ONU');
    });

    test('صفّ الصفحة ⇒ ONU: «Online» وحدها متّصلة', () {
      HsgqWebOnu? o(Map<String, dynamic> r) => HsgqWeb.onuFrom(r, 1);
      expect(o({'onu_id': 3, 'status': 'Online', 'macaddr': 'aa:bb:cc:dd:ee:ff'})!.online, isTrue);
      for (final st in ['Offline', 'Initial', 'LOS', '', null]) {
        expect(o({'onu_id': 3, 'status': st})!.online, isFalse, reason: '$st');
      }
      expect(o({'onu_id': 0}), isNull);
      expect(o({'onu_id': 'x'}), isNull);
      expect(o({'port_id': 2, 'onu_id': 5})!.pon, 2);
      expect(HsgqWeb.macBytes('9C-28-EF-68-25-52'), [0x9c, 0x28, 0xef, 0x68, 0x25, 0x52]);
      expect(HsgqWeb.macBytes('nope'), isNull);
    });
  });
}
