import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/api/subscriber_contacts_api.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/services/connection_alerts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «كل الشركات» — رسائل كارت المشترك من **شركة الصفّ** (٢١ نوفمبر — المالك: «ابدي حبي الي تنصحه يبقى ع شركه بقي» و«اهم شي بدقة
/// تنبته»؛ الخادم 1af5be0). عقد الخادم (server/companyRoutingAllow.js، tests/company-routing ١١ب و company-routing-allow ٦ل):
///   POST /api/whatsapp/send-message   adminId الجسم = مدير الشركة الموجَّهة (bodyAdmin)، وsas4Idx الجسم بمرجع نافذته (bodySubject:
///                                     أرقامٌ ١–١٢ بعد القصّ؛ غيابه أو عطبه ⇒ MISMATCH).
///   POST /api/whatsapp/send-media     adminId الجسم وحده (bodyAdmin)، بلا مرجع.
///   GET  /api/whatsapp/templates/:adminId   adminParam.
///   POST …/:idx/add-credit · PATCH …/:idx/location   بمرجع النافذة كبقيّة كتابات المشترك.
///   GET  /api/v2/connection-alerts/settings   قراءةٌ موجَّهة (حدود «تنبيه المشترك» لشركته).
/// والسلوك الكامل بالواجهة (التنبيه، القوالب الثلاثة من صفحة المشترك، رمز QR): test/merged_route_proof_test.dart البند ٧.
const _kB = 'c0000000000b2';
final _refB = 'r_${'b' * 22}';

/// يوزر مشترك كلّ idx كما يردّه معالج نافذته (ايرث لنك بـ@، والعربيّ) — الدفعة ب.
const _users = {'9': 'ali@net', '10': 'علي.٧', '11': ' padded '};

/// خادمٌ بصدى المفتاح: يسجّل كلّ طلبٍ بمفتاحه، وجسم كلّ كتابةٍ ومرجعها.
class _Srv implements HttpClientAdapter {
  final asked = <String>[];
  final bodies = <String, Object?>{};
  final refs = <String, String?>{};
  bool failSettings = false;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final m = o.method.toUpperCase();
    final path = o.uri.path;
    asked.add('$m $path ${key ?? '-'}');
    if (m != 'GET') {
      bodies['$m $path'] = o.data;
      refs['$m $path'] = o.headers['x-company-ref'] as String?;
    }
    final h = <String, List<String>>{
      Headers.contentTypeHeader: [Headers.jsonContentType],
      if (key != null) 'x-company-key': [key],
    };
    ResponseBody j(Object b, [int s = 200]) => ResponseBody.fromString(jsonEncode(b), s, headers: h);
    if (m == 'GET' && path.startsWith('/api/whatsapp/templates/')) {
      final admin = Uri.decodeComponent(path.split('/').last);
      return j({
        'success': true,
        'templates': [
          {'template_type': 'debt_reminder', 'is_active': 1, 'message_content': 'قالب $admin', 'default_channel': 'auto'},
        ],
      });
    }
    if (m == 'GET' && path == '/api/v2/connection-alerts/settings') {
      if (failSettings) return j({'success': false, 'message': 'تعذّر'});
      return j({'success': true, 'data': {'enabled': key == _kB, 'fiber_rx_dbm': key == _kB ? -22 : -27}});
    }
    if (m == 'GET' && RegExp(r'^/api/v2/subscribers/\d+$').hasMatch(path)) {
      final idx = path.split('/').last;
      return ResponseBody.fromString(jsonEncode({'success': true, 'data': {'idx': idx, 'username': _users[idx] ?? 'sub$idx'}}), 200, headers: {
        ...h,
        if (key != null) 'x-company-ref': [_refB],
      });
    }
    if (RegExp(r'^/api/subscribers/[^/]+/device$').hasMatch(path) && (m == 'PUT' || m == 'DELETE')) {
      return j({'success': true});
    }
    if (path == '/api/v2/subscriber-contacts') {
      return m == 'GET'
          ? j({'success': true, 'enabled': true, 'contact': {'wa_phone2': '9647701112222', 'tg_contact': '@ali_b'}})
          : j({'success': true, 'contact': {'wa_phone2': '9647701112222', 'tg_contact': null}});
    }
    if (path == '/api/whatsapp/send-message' || path == '/api/whatsapp/send-media') {
      return j({'success': true, 'channel': 'whatsapp'});
    }
    return j({'success': false, 'message': 'غير معروف'}, 404);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Srv srv;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth.token': 'tok', 'auth.admin_id': 'supernet:12'});
    SharedPreferences.setMockInitialValues({});
    srv = _Srv();
    ApiClient.dio.httpClientAdapter = srv;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    CompanyRoute.adminIdOf = (k) => k == _kB ? 'jt:6836' : null;
    CompanyRefs.reset();
    WhatsAppApi.clearCaches();
    ConnectionAlertSettings.resetCompanies();
  });

  group('مرجع النافذة (CompanyRefs.requireOf) — كجدول الخادم حرفاً', () {
    ({String idx, CompanyRefKind kind})? send(Object? data, {String m = 'POST', String p = '/api/whatsapp/send-message'}) =>
        CompanyRefs.requireOf(m, p, data);
    const subject = CompanyRefKind.subject;

    test('send-message: sas4Idx الجسم (نصٌّ أو رقم، مقصوص، أرقامٌ ١–١٢) ⇒ مرجع نافذته', () {
      expect(send({'sas4Idx': '1520'}), (idx: '1520', kind: subject));
      expect(send({'sas4Idx': 1520}), (idx: '1520', kind: subject));
      expect(send({'sas4Idx': ' 77 '}), (idx: '77', kind: subject));
      expect(send({'sas4Idx': '123456789012'}), (idx: '123456789012', kind: subject));
    });

    test('send-message بلا مشتركٍ صالح ⇒ بلا مرجع (الخادم يرفض الموجَّه برسالته — لا يُرسل)', () {
      for (final bad in <Object?>[
        <String, Object?>{},
        {'sas4Idx': null},
        {'sas4Idx': ''},
        {'sas4Idx': 'abc'},
        {'sas4Idx': '12a'},
        {'sas4Idx': '1234567890123'},
        {'sas4Idx': [1]},
        'sas4Idx=1',
      ]) {
        expect(send(bad), isNull, reason: '$bad');
      }
      expect(send({'sas4Idx': '1'}, m: 'GET'), isNull);
      expect(send({'sas4Idx': '1'}, p: '/api/whatsapp/send-message/x'), isNull);
      expect(send({'sas4Idx': '1'}, p: '/api/whatsapp/send-media'), isNull, reason: 'send-media بلا مرجع (bodyAdmin وحده)');
    });

    test('«إضافة رصيد» و«الموقع» بمرجع النافذة، والبيع كما كان', () {
      expect(CompanyRefs.requireOf('POST', '/api/v2/subscribers/12/add-credit'), (idx: '12', kind: subject));
      expect(CompanyRefs.requireOf('PATCH', '/api/v2/subscribers/12/location'), (idx: '12', kind: subject));
      expect(CompanyRefs.requireOf('POST', '/api/v2/sales', {'customer': {'kind': 'subscriber', 'idx': ' 5 '}}),
          (idx: '5', kind: subject));
      expect(CompanyRefs.requireOf('POST', '/api/v2/sales', {'customer': {'kind': 'walkin', 'idx': '5'}}), isNull);
    });

    test('الإرسال لا يُسقط قائمة الشركة المخبّأة (keepsList) — عشرة تذكيراتٍ لا تعيد جلبها عشر مرّات', () {
      expect(CompanyRoute.keepsList, containsAll(['/api/whatsapp/send-message', '/api/whatsapp/send-media']));
    });
  });

  group('قوالب الواتساب لكلّ شركة', () {
    test('داخل نطاق شركة الصفّ ⇒ قوالبها بمعرّف مديرها (موجَّهة)، وخارجه قوالب الجلسة — ومخبأٌ لكلّ مدير لا يختلط', () async {
      final b = await CompanyRoute.run(_kB, () => WhatsAppApi.loadTemplates());
      final open = await WhatsAppApi.loadTemplates();
      expect(b!.single.messageContent, 'قالب jt:6836');
      expect(open!.single.messageContent, 'قالب supernet:12');
      expect(srv.asked, ['GET /api/whatsapp/templates/jt:6836 $_kB', 'GET /api/whatsapp/templates/supernet:12 -']);
      expect((await CompanyRoute.run(_kB, () => WhatsAppApi.loadTemplates()))!.single.messageContent, 'قالب jt:6836');
      expect((await WhatsAppApi.loadTemplates())!.single.messageContent, 'قالب supernet:12');
      expect(srv.asked, hasLength(2), reason: 'الثانية من المخبأ لكلٍّ بمديره');
      WhatsAppApi.clearCaches();
      await WhatsAppApi.loadTemplates();
      expect(srv.asked, hasLength(3), reason: 'clearCaches (الخروج) يمسح قوالب كلّ الشركات');
    });

    test('شركةٌ بلا معرّف مديرٍ معروف ⇒ لا قوالب ولا طلب (لا قوالب المفتوحة بدلها)', () async {
      for (final unknown in <String? Function(String)>[(_) => null, (_) => '']) {
        CompanyRoute.adminIdOf = unknown;
        expect(await CompanyRoute.run(_kB, () => WhatsAppApi.loadTemplates()), isNull);
      }
      expect(srv.asked, isEmpty);
    });
  });

  group('الإرسال بمدير شركة الصفّ', () {
    test('send-message داخل نطاق JTSHOP: مديرها + مرجع نافذة sas4Idx؛ وخارجه معرّف الجلسة بلا مفتاحٍ ولا مرجع (كما كان)', () async {
      await CompanyRoute.run(_kB, () => ApiClient.dio.get<dynamic>('/api/v2/subscribers/9')); // النافذة (MergedOps.write يفعلها)
      final r = await CompanyRoute.run(
          _kB, () => WhatsAppApi.sendMessage(to: '9647701234567', message: 'x', sas4Idx: '9', intent: 'debt_reminder'));
      expect(r.ok, isTrue);
      expect(srv.asked.last, 'POST /api/whatsapp/send-message $_kB');
      expect((srv.bodies['POST /api/whatsapp/send-message']! as Map)['adminId'], 'jt:6836');
      expect(srv.refs['POST /api/whatsapp/send-message'], _refB);

      final o = await WhatsAppApi.sendMessage(to: '9647701234567', message: 'x', sas4Idx: '9');
      expect(o.ok, isTrue);
      expect(srv.asked.last, 'POST /api/whatsapp/send-message -');
      expect((srv.bodies['POST /api/whatsapp/send-message']! as Map)['adminId'], 'supernet:12');
      expect(srv.refs['POST /api/whatsapp/send-message'], isNull);
    });

    test('send-media داخل نطاق JTSHOP: مديرها، بلا مرجع', () async {
      final r = await CompanyRoute.run(_kB,
          () => WhatsAppApi.sendMedia(to: '9647701234567', bytes: Uint8List(4), filename: 'q.png', sas4Idx: '9'));
      expect(r.ok, isTrue);
      expect(srv.asked.last, 'POST /api/whatsapp/send-media $_kB');
      expect((srv.bodies['POST /api/whatsapp/send-media']! as Map)['adminId'], 'jt:6836');
    });

    test('نطاق شركةٍ بلا مديرٍ معروف ⇒ لا إرسال أصلاً (لا معرّف الجلسة لطلبٍ يذهب لغيرها) وسببه', () async {
      CompanyRoute.adminIdOf = (_) => null;
      final r = await CompanyRoute.run(_kB, () => WhatsAppApi.sendMessage(to: '1', message: 'x', sas4Idx: '9'));
      final m = await CompanyRoute.run(_kB, () => WhatsAppApi.sendMedia(to: '1', bytes: Uint8List(4), filename: 'q.png'));
      expect(r.ok, isFalse);
      expect(m.ok, isFalse);
      expect(r.message, contains('شركة المشترك'));
      expect(srv.asked, isEmpty);
    });
  });

  group('حدود «تنبيه المشترك» لكلّ شركة', () {
    test('forRow: بلا مفتاح ⇒ حدود الجلسة كما كانت؛ وبمفتاح ⇒ null حتى تصل حدود شركته ثمّ هي (قراءةٌ موجَّهة واحدة)', () async {
      expect(identical(ConnectionAlertSettings.forRow(null), ConnectionAlertSettings.current.value), isTrue);
      var ticks = 0;
      void bump() => ticks++;
      ConnectionAlertSettings.companyTick.addListener(bump);
      addTearDown(() => ConnectionAlertSettings.companyTick.removeListener(bump));
      expect(ConnectionAlertSettings.forRow(_kB), isNull, reason: 'لم تصل ⇒ لا شريط بحدود شركةٍ أخرى');
      await ConnectionAlertSettings.loadCompany(_kB); // الطلب الجاري نفسه الذي أطلقه الرسم — لا ثانٍ
      final t = ConnectionAlertSettings.forRow(_kB)!;
      expect(t.enabled, isTrue);
      expect(t.fiberRxDbm, -22);
      expect(ticks, 1, reason: 'وصولها يعيد رسم الشريط والبلاطة');
      expect(await ConnectionAlertSettings.loadCompany(_kB), isNotNull);
      expect(srv.asked, ['GET /api/v2/connection-alerts/settings $_kB'], reason: 'المخبأ بعدها (١٠ دقائق)');
    });

    test('التعذّر ⇒ null (لا حدود غيرها)، ولا يُعاد مع كلّ رسم', () async {
      srv.failSettings = true;
      expect(await ConnectionAlertSettings.loadCompany(_kB), isNull);
      ConnectionAlertSettings.forRow(_kB);
      ConnectionAlertSettings.forRow(_kB);
      await pumpEventQueue();
      expect(srv.asked, hasLength(1));
    });

    test('طلبٌ جارٍ واحد لكلّ شركة', () async {
      final a = ConnectionAlertSettings.loadCompany(_kB);
      final b = ConnectionAlertSettings.loadCompany(_kB);
      expect(identical(a, b), isTrue);
      await Future.wait([a, b]);
      expect(srv.asked, hasLength(1));
    });

    test('مفتاحٌ غير صالح ⇒ null بلا طلب (لا يذهب للمفتوحة)', () async {
      expect(await ConnectionAlertSettings.loadCompany('not-a-key'), isNull);
      expect(srv.asked, isEmpty);
    });

    test('resetCompanies (تبديل الجلسة) ⇒ لا يرث أحدٌ حدود سابقه، وطلبٌ قديمٌ يعود بعده لا يُحفظ', () async {
      final pending = ConnectionAlertSettings.loadCompany(_kB);
      ConnectionAlertSettings.resetCompanies();
      expect(await pending, isNull);
      expect(ConnectionAlertSettings.peekCompany(_kB), isNull);
    });
  });

  group('الدفعة ب: «إعداد جهاز المشترك» و«الأرقام الإضافيّة» بيوزر مشترك النافذة (الخادم 342c96b)', () {
    ({String idx, CompanyRefKind kind})? need(String m, String p, [Object? data]) => CompanyRefs.requireOf(m, p, data);
    const subject = CompanyRefKind.subject;

    test('requireOf: الجهاز بيوزر المسار مفكوكاً (كـreq.params)، والأرقام بيوزر الجسم مقصوصاً وحدّ ١٢٨ — كالخادم حرفاً', () {
      expect(need('PUT', '/api/subscribers/ali%40net/device'), (idx: 'u:ali@net', kind: subject));
      expect(need('PUT', '/api/subscribers/ali@net/device'), (idx: 'u:ali@net', kind: subject));
      expect(need('DELETE', '/api/subscribers/${Uri.encodeComponent('علي.٧')}/device'), (idx: 'u:علي.٧', kind: subject));
      expect(need('PUT', '/api/v2/subscriber-contacts', {'username': '  ali@net ', 'wa_phone2': '1'}), (idx: 'u:ali@net', kind: subject));
      for (final bad in <(String, String, Object?)>[
        ('GET', '/api/subscribers/ali/device', null),
        ('POST', '/api/subscribers/ali/device', null),
        ('PUT', '/api/subscribers/ali/device/x', null),
        ('PUT', '/api/subscribers/%E0%A4/device', null),
        ('PUT', '/api/v2/subscriber-contacts', {'username': '   '}),
        ('PUT', '/api/v2/subscriber-contacts', {'username': ['ali']}),
        ('PUT', '/api/v2/subscriber-contacts', {'username': 'a' * 129}),
        ('PUT', '/api/v2/subscriber-contacts', 'username=ali'),
        ('GET', '/api/v2/subscriber-contacts', {'username': 'ali'}),
        ('DELETE', '/api/v2/subscriber-contacts', {'username': 'ali'}),
      ]) {
        expect(need(bad.$1, bad.$2, bad.$3), isNull, reason: '${bad.$1} ${bad.$2} ${bad.$3}');
      }
    });

    test('capture: نافذة المشترك تُحفظ بيوزره المقصوص أيضاً — وعرض السعر وردٌّ بلا يوزر لا', () async {
      await CompanyRoute.run(_kB, () => ApiClient.dio.get<dynamic>('/api/v2/subscribers/9'));
      await CompanyRoute.run(_kB, () => ApiClient.dio.get<dynamic>('/api/v2/subscribers/11'));
      expect(CompanyRefs.lookupUser(_kB, 'ali@net'), _refB);
      expect(CompanyRefs.lookupUser(_kB, 'padded'), _refB, reason: 'مقصوصاً كالخادم');
      expect(CompanyRefs.lookupUser(_kB, 'Ali@net'), isNull, reason: 'حرفاً');
      expect(CompanyRefs.lookupUser('c0000000000a1', 'ali@net'), isNull, reason: 'لكلّ شركةٍ نافذتها');
      CompanyRefs.reset();
      expect(CompanyRefs.lookupUser(_kB, 'ali@net'), isNull);
    });

    test('DeviceConfigApi: الحفظ والحذف بشركة الصفّ ومرجع نافذة مشتركه (تُفتح بـidx إن لم تُفتح)؛ وبلا مفتاح كما كان', () async {
      const cfg = DeviceConfig(deviceType: DeviceKind.ubiquiti, username: 'admin', password: 'p', customIp: '10.0.0.2');
      expect(await DeviceConfigApi.saveConfig('ali@net', cfg, company: _kB, idx: '9'), isTrue);
      expect(srv.asked, ['GET /api/v2/subscribers/9 $_kB', 'PUT /api/subscribers/ali@net/device $_kB'], reason: 'النافذة ثمّ الحفظ لشركتها');
      expect(srv.refs['PUT /api/subscribers/ali@net/device'], _refB);
      expect(await DeviceConfigApi.resetConfig('ali@net', company: _kB, idx: '9'), isTrue);
      expect(srv.asked.last, 'DELETE /api/subscribers/ali@net/device $_kB');
      expect(srv.refs['DELETE /api/subscribers/ali@net/device'], _refB);
      expect(srv.asked.where((a) => a.startsWith('GET /api/v2/subscribers/9')).length, 1, reason: 'النافذة مرّةً — المرجع محفوظ');
      srv.asked.clear();
      expect(await DeviceConfigApi.saveConfig('u7', cfg), isTrue);
      expect(srv.asked, ['PUT /api/subscribers/u7/device -'], reason: 'الوضع العاديّ: بلا نافذةٍ ولا مفتاح');
      expect(srv.refs['PUT /api/subscribers/u7/device'], isNull);
    });

    test('الأرقام الإضافيّة: القراءة والحفظ لشركة صفّ المشترك بمرجع نافذته؛ وبلا مفتاح كما كان', () async {
      final row = Subscriber(idx: '9', username: 'ali@net', firstname: 'علي', lastname: 'ب', phone: '07701234567', companyKey: _kB);
      final g = await MergedOps.run(row, () => SubscriberContactsApi.get(row.username));
      expect([g.ok, g.enabled, g.contact?.tgContact], [true, true, '@ali_b']);
      expect(srv.asked.single, 'GET /api/v2/subscriber-contacts $_kB');
      final w = await MergedOps.write(row, () => SubscriberContactsApi.save(row.username, wa: '07701112222', tg: '', phone: row.phone));
      expect(w.ok, isTrue);
      expect(srv.asked.last, 'PUT /api/v2/subscriber-contacts $_kB');
      expect(srv.refs['PUT /api/v2/subscriber-contacts'], _refB);
      expect((srv.bodies['PUT /api/v2/subscriber-contacts']! as Map)['username'], 'ali@net');
      srv.asked.clear();
      final plain = Subscriber(idx: '9', username: 'ali@net', firstname: 'علي', lastname: 'ب', phone: '07701234567');
      expect((await MergedOps.write(plain, () => SubscriberContactsApi.save(plain.username, wa: '', tg: '', phone: plain.phone))).ok, isTrue);
      expect(srv.asked, ['PUT /api/v2/subscriber-contacts -']);
    });

    test('بناء الورقة: إعداد الجهاز يُفتح من كارت الجهاز وحده بشركة الكارت ورقم مشتركه، وصفحة المشترك تمرّرهما', () {
      final libFiles = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
      final sites = <String>[];
      for (final f in libFiles) {
        final src = f.readAsStringSync();
        for (final m in RegExp(r'(?<![\w.])DeviceConfigSheet\(').allMatches(src)) {
          if (src.substring(0, m.start).trimRight().endsWith('const') && src.substring(m.start - 30 < 0 ? 0 : m.start - 30, m.start).contains('const DeviceConfigSheet')) continue;
          sites.add('${f.path}:${src.substring(m.start, (m.start + 220).clamp(0, src.length)).replaceAll(RegExp(r'\s+'), ' ')}');
        }
      }
      final builds = sites.where((x) => !x.contains('DeviceConfigSheet({super.key')).toList();
      expect(builds.length, 1, reason: builds.join('\n'));
      expect(builds.single, startsWith('lib/screens/subscribers/widgets/device_probe_card.dart:'));
      expect(builds.single, contains('companyKey: widget.company,'));
      expect(builds.single, contains('subscriberIdx: widget.subscriberIdx,'));
      final card = File('lib/screens/subscribers/widgets/device_probe_card.dart').readAsStringSync();
      final open = card.substring(card.indexOf('Future<void> _openConfig() async {'), card.indexOf('DeviceConfigSheet(\n        username: widget.username,'));
      expect(open, contains('final locked = MergedOps.writeLockAt(widget.company);'), reason: 'صفحة موظّفٍ مقفلة ⇒ لا ورقة');
      expect(open, isNot(contains('unsupportedAt')), reason: 'لم يعد «للشركة وحدها»');
      final detail = File('lib/screens/subscribers/subscriber_detail_screen.dart').readAsStringSync();
      expect(detail, contains('company: sub.companyKey,\n                          subscriberIdx: sub.idx,'));
      expect(detail, contains('SecondDeviceSlot(ip: sub.ipAddress ?? \'\', username: sub.username, company: sub.companyKey, subscriberIdx: sub.idx)'));
      final sheet = File('lib/screens/subscribers/sheets/device_config_sheet.dart').readAsStringSync();
      expect(sheet, contains('DeviceConfigApi.fetchFresh(widget.username, company: widget.companyKey)'));
      expect(RegExp(r'DeviceProbeApi\.invalidateIp\([^;]*\);').allMatches(sheet).every((m) => m.group(0)!.contains('company: widget.companyKey')), isTrue,
          reason: 'مخابئ الفحص بمفتاح شركة الصفّ');
    });
  });
}
