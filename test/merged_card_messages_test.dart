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
      return ResponseBody.fromString(jsonEncode({'success': true, 'data': {}}), 200, headers: {
        ...h,
        if (key != null) 'x-company-ref': [_refB],
      });
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
}
