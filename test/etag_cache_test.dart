import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/etag_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «ما تغيّر شي» (٢٤ نوفمبر): التطبيق يرسل بصمة آخر ردٍّ للقائمتين الكبيرتين، والخادم يجيب 304 حين لم يتغيّر حرف.
/// خادمٌ وهميّ كـExpress: البصمة من الجسم نفسه، و304 حين تطابق If-None-Match. الضمان المطلوب: ما يصل الشاشة هو حرفيّاً ما كان
/// سيصل بلا البصمة، نسخةٌ جديدة كلّ مرّة، والمسارات الأخرى و«كل الشركات» كما كانت.
class _Express implements HttpClientAdapter {
  final Map<String, Object> bodies = {};
  final List<({String path, String? inm, int status})> log = [];
  bool etag = true;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = jsonEncode(bodies[o.uri.path] ?? {'success': true});
    final tag = 'W/"${body.length.toRadixString(16)}-${body.hashCode}"';
    final inm = o.headers['If-None-Match']?.toString();
    final hit = etag && inm == tag;
    log.add((path: o.uri.path, inm: inm, status: hit ? 304 : 200));
    final headers = <String, List<String>>{
      Headers.contentTypeHeader: [Headers.jsonContentType],
      if (etag) 'etag': [tag],
    };
    return hit ? ResponseBody.fromString('', 304, headers: headers) : ResponseBody.fromString(body, 200, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Express server;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth.token': 'tok-A', 'auth.admin_id': '2251'});
    SharedPreferences.setMockInitialValues({});
    server = _Express();
    ApiClient.dio.httpClientAdapter = server;
    EtagCache.clear();
  });

  const subs = '/api/v2/subscribers';
  Map<String, dynamic> list(int n) => {
        'success': true,
        'data': [for (var i = 0; i < n; i++) {'username': 'u$i', 'phone': '0770$i', 'balance': -1000 * i}],
      };

  test('١ لم يتغيّر شيء ⇒ 304 من الخادم، والشاشة تستلم الجسم نفسه حرفيّاً (200) ونسخةً جديدة كلّ مرّة', () async {
    server.bodies[subs] = list(3);
    final a = await ApiClient.dio.get<Map<String, dynamic>>(subs);
    final b = await ApiClient.dio.get<Map<String, dynamic>>(subs);
    expect(server.log.map((x) => x.status), [200, 304]);
    expect(server.log[1].inm, isNotNull, reason: 'أُرسلت البصمة');
    expect(b.statusCode, 200);
    expect(jsonEncode(b.data), jsonEncode(a.data), reason: 'الجسم نفسه حرفيّاً');
    (b.data!['data'] as List).clear(); // الشاشة تعدّل ما استلمته
    final c = await ApiClient.dio.get<Map<String, dynamic>>(subs);
    expect((c.data!['data'] as List).length, 3, reason: 'تعديل الشاشة لا يمسّ المحفوظ');
    expect(EtagCache.hits, 2);
  });

  test('٢ تغيّر حرفٌ واحد ⇒ الخادم يرسل الكامل (200) والشاشة ترى الجديد، ثمّ يُحفظ الجديد', () async {
    server.bodies[subs] = list(3);
    await ApiClient.dio.get<Map<String, dynamic>>(subs);
    server.bodies[subs] = {...list(3), 'data': [...(list(3)['data'] as List).take(2), {'username': 'u2', 'phone': '07702', 'balance': -2001}]};
    final r = await ApiClient.dio.get<Map<String, dynamic>>(subs);
    expect(server.log.last.status, 200);
    expect(((r.data!['data'] as List).last as Map)['balance'], -2001);
    final again = await ApiClient.dio.get<Map<String, dynamic>>(subs);
    expect(server.log.last.status, 304);
    expect(((again.data!['data'] as List).last as Map)['balance'], -2001);
  });

  test('٣ خارج القائمتين، أو بلا بصمةٍ من الخادم، أو ردٌّ غير ناجح ⇒ كما كان (لا بصمة تُرسل)', () async {
    server.bodies['/api/v2/packages'] = {'success': true, 'data': [1]};
    await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/packages');
    await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/packages');
    expect(server.log.every((x) => x.inm == null), isTrue);
    server.log.clear();
    server.etag = false;
    server.bodies[subs] = list(2);
    await ApiClient.dio.get<Map<String, dynamic>>(subs);
    await ApiClient.dio.get<Map<String, dynamic>>(subs);
    expect(server.log.every((x) => x.inm == null), isTrue, reason: 'خادمٌ بلا بصمة');
    server.etag = true;
    server.log.clear();
    EtagCache.clear();
    server.bodies[subs] = {'success': false, 'message': 'x'};
    await ApiClient.dio.get<Map<String, dynamic>>(subs);
    await ApiClient.dio.get<Map<String, dynamic>>(subs);
    expect(server.log.every((x) => x.inm == null), isTrue, reason: 'الردّ الفاشل لا يُحفظ');
  });

  test('٤ حسابٌ آخر (توكنٌ آخر) لا يستعمل محفوظ الأوّل، ومسح الجلسة يمسحه', () async {
    server.bodies[subs] = list(4);
    await ApiClient.dio.get<Map<String, dynamic>>(subs);
    FlutterSecureStorage.setMockInitialValues({'auth.token': 'tok-B', 'auth.admin_id': '9'});
    await ApiClient.dio.get<Map<String, dynamic>>(subs);
    expect(server.log.last.inm, isNull, reason: 'مفتاحٌ آخر');
    expect(EtagCache.size, 2);
    EtagCache.clear();
    expect(EtagCache.size, 0);
  });

  test('٥ طلبٌ موجَّه («كل الشركات») خارجها: لا بصمة ولا حفظ', () async {
    server.bodies[subs] = list(2);
    final opts = Options(extra: {'_routed': 'k1'});
    await ApiClient.dio.get<Map<String, dynamic>>(subs, options: opts);
    expect(EtagCache.size, 0);
  });
}
