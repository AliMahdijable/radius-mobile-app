// ① (١٦ نوفمبر ٢٠٢٦ — المالك: «ابدأ بالأول والثاني وسوي محاكاة بحيث تضمن دقه المعلومات والسرعه»): الجهاز يتذكّر حكم حجم
// الحساب فلا ينتظر «هل الحساب كبير؟» من الساس قبل قائمة المشتركين — بهامشٍ واسع، ولكلّ حسابٍ ودورٍ واسم دخولٍ وحده، والكبير
// والقريب من الحدّ والمجهول والفاشل كما كانوا حرفاً.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/services/known_account_size.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// الخادم الوهميّ: فحص الحجم وحده (`?page=1&size=1`) — يُعدّ ويجيب بما يُضبط.
class _ProbeServer implements HttpClientAdapter {
  int probes = 0;
  Future<void>? hold;
  int total = 114;
  bool paged = true;
  bool success = true;
  int failStatus = 503;
  bool fail = false;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    if (o.uri.path == '/api/v2/subscribers' && o.uri.queryParameters['size'] == '1') {
      probes++;
      final h = hold;
      if (h != null) await h;
      if (fail) throw DioException.connectionError(requestOptions: o, reason: 'down');
      final body = success
          ? {'success': true, if (paged) 'paged': true, 'total': total, 'data': const []}
          : {'success': false, 'code': 'SAS_SESSION_EXPIRED', 'message': 'x'};
      return ResponseBody.fromString(jsonEncode(body), success ? 200 : failStatus, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    return ResponseBody.fromString('{"success":false}', 404, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ProbeServer server;
  var clock = DateTime(2026, 11, 16, 1, 0);

  Map<String, dynamic> stored() {
    final raw = _prefs.getString(KnownAccountSize.storeKey);
    return raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> session({String admin = '2', String name = 'admin@popq', bool employee = false, String token = 'tok-1'}) async {
    FlutterSecureStorage.setMockInitialValues({
      'auth.token': token,
      'auth.admin_id': admin,
      'auth.admin_username': name,
    });
    KnownAccountSize.isEmployee = () => employee;
    BigSubscribersApi.reset();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
    clock = DateTime(2026, 11, 16, 1, 0);
    KnownAccountSize.now = () => clock;
    server = _ProbeServer();
    ApiClient.dio.httpClientAdapter = server;
    BigSubscribersApi.backgroundRefreshDelay = const Duration(milliseconds: 20);
    await session();
  });

  tearDown(() {
    KnownAccountSize.now = DateTime.now;
    KnownAccountSize.isEmployee = () => false;
    BigSubscribersApi.backgroundRefreshDelay = const Duration(seconds: 8);
    BigSubscribersApi.reset();
  });

  test('الحدّ نفسه في الطرفين — الكبير ٥٠٠٠ والهامش دونه بألف', () {
    expect(KnownAccountSize.bigAt, BigSubscribersApi.threshold);
    expect(KnownAccountSize.smallUnder, lessThan(KnownAccountSize.bigAt));
    expect(KnownAccountSize.bigAt - KnownAccountSize.smallUnder, greaterThanOrEqualTo(1000));
  });

  test('أوّل فتح: الفحص من الشبكة كما كان، ثمّ يُحفظ الحكم', () async {
    expect(await BigSubscribersApi.probe(), 0);
    expect(server.probes, 1);
    await pumpEventQueue();
    final e = stored()['2|m|admin@popq'] as Map;
    expect(e['size'], 114);
    expect(e['paged'], isTrue);
  });

  test('الفتح التالي (جلسةٌ جديدة للحساب نفسه): بلا فحصٍ من الشبكة، والحجم معروف للشاشات', () async {
    await BigSubscribersApi.probe();
    await pumpEventQueue();
    await session(token: 'tok-2'); // إغلاق التطبيق وفتحه: الذاكرة فارغة والتوكن تجدّد
    expect(await BigSubscribersApi.probe(), 0);
    expect(server.probes, 1, reason: 'سأل الساس مع أنّ الحساب معروفٌ صغيراً');
    expect(BigSubscribersApi.knownSize, 114);
    expect(BigSubscribersApi.knownBig, isFalse);
  });

  test('الكبير لا يُختصر أبداً — يُسأل الساس في كلّ فتح كما كان', () async {
    server.total = 89177;
    expect(await BigSubscribersApi.probe(), 89177);
    await pumpEventQueue();
    await session(token: 'tok-2');
    expect(await BigSubscribersApi.probe(), 89177);
    expect(server.probes, 2);
  });

  test('القريب من الحدّ (≥ ٤٠٠٠) يُسأل قبل القائمة؛ ودونه يُختصر', () async {
    server.total = 4000;
    await BigSubscribersApi.probe();
    await pumpEventQueue();
    await session(token: 'tok-2');
    await BigSubscribersApi.probe();
    expect(server.probes, 2, reason: '٤٠٠٠ على حافّة الهامش — لا اختصار');

    server.total = 3999;
    await session(token: 'tok-3');
    await BigSubscribersApi.probe();
    await pumpEventQueue();
    await session(token: 'tok-4');
    await BigSubscribersApi.probe();
    expect(server.probes, 3, reason: '٣٩٩٩ يُختصر');
  });

  test('صغيرٌ صار كبيراً: الفحص الخلفيّ يكتب الكبير فيُسأل الساس في الفتح بعده', () async {
    await BigSubscribersApi.probe(); // 114
    await pumpEventQueue();
    clock = clock.add(const Duration(hours: 7)); // أقدم من refreshAfter
    server.total = 6000; // (غير واقعيّ — اختبار الاتّجاه)
    await session(token: 'tok-2');
    expect(await BigSubscribersApi.probe(), 0, reason: 'الحكم المحفوظ يُستعمل فوراً');
    expect(server.probes, 1);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(server.probes, 2, reason: 'لم يتجدّد الحكم القديم في الخلفيّة');
    expect(BigSubscribersApi.knownBig, isTrue, reason: 'الفحص الخلفيّ لم يُحدّث الذاكرة');
    await session(token: 'tok-3');
    expect(await BigSubscribersApi.probe(), 6000);
    expect(server.probes, 3, reason: 'المحفوظ صار كبيراً ⇒ الفحص قبل القائمة');
  });

  test('حكمٌ حديث (< ٦ ساعات) لا يُجدَّد — أقلّ طلباتٍ على الساس من قبل', () async {
    await BigSubscribersApi.probe();
    await pumpEventQueue();
    clock = clock.add(const Duration(hours: 5));
    await session(token: 'tok-2');
    await BigSubscribersApi.probe();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(server.probes, 1);
  });

  test('أقدم من ٧ أيّام ⇒ الفحص قبل القائمة كما كان', () async {
    await BigSubscribersApi.probe();
    await pumpEventQueue();
    clock = clock.add(const Duration(days: 8));
    await session(token: 'tok-2');
    await BigSubscribersApi.probe();
    expect(server.probes, 2);
  });

  test('لكلّ حسابٍ حكمه: مديرٌ آخر، وموظّفٌ على المدير نفسه، واسم دخولٍ آخر — كلٌّ يُسأل', () async {
    await BigSubscribersApi.probe(); // 2|m|admin@popq
    await pumpEventQueue();
    await session(admin: 'speednet-iq:1429', name: 'admin@popq3x', token: 'tok-b');
    await BigSubscribersApi.probe();
    expect(server.probes, 2, reason: 'استُعمل حكم حسابٍ آخر');
    await session(employee: true, name: 'ali.m', token: 'tok-e');
    await BigSubscribersApi.probe();
    expect(server.probes, 3, reason: 'استُعمل حكم المدير لموظّفه');
    await session(name: 'admin@popq2', token: 'tok-n');
    await BigSubscribersApi.probe();
    expect(server.probes, 4, reason: 'استُعمل حكم اسم دخولٍ آخر');
  });

  test('ردّ الفحص يصل بعد تبديل الشركة ⇒ يُحفظ لحسابه لا للجديد', () async {
    final gate = Completer<void>();
    server.hold = gate.future;
    final f = BigSubscribersApi.probe(); // admin@popq، الردّ معلَّق
    await pumpEventQueue();
    FlutterSecureStorage.setMockInitialValues({
      'auth.token': 'tok-x',
      'auth.admin_id': '1146',
      'auth.admin_username': 'admin@full',
    });
    gate.complete();
    await f;
    await pumpEventQueue();
    expect(stored().keys, ['2|m|admin@popq'], reason: 'حجم حسابٍ كُتب باسم غيره');
  });

  test('«كل الشركات»: الفحص الموجَّه لشركةٍ أخرى لا يُختصر بحكم الجلسة ولا يُحفظ باسمها', () async {
    await BigSubscribersApi.probe(); // الجلسة: 114 محفوظ
    await pumpEventQueue();
    await session(token: 'tok-2');
    var routed = 'supernet:1146';
    KnownAccountSize.routedKey = () => routed;
    addTearDown(() => KnownAccountSize.routedKey = () => null);
    server.total = 89177;
    expect(await BigSubscribersApi.probe(), 89177, reason: 'الموجَّه أخذ حكم الجلسة المحفوظ');
    expect(server.probes, 2);
    await pumpEventQueue();
    expect((stored()['2|m|admin@popq'] as Map)['size'], 114, reason: 'جواب شركةٍ أخرى كُتب باسم الجلسة');
    expect(stored().length, 1);
    routed = '';
    KnownAccountSize.routedKey = () => null;
  });

  test('الفحص الفاشل لا يُحفظ (لا «حسابٌ لا يرقّم» لأنّ ساسه تعطّل لحظتها)', () async {
    server.success = false; // 503 برمز الساس
    await BigSubscribersApi.probe();
    // ردٌّ مرفوضٌ بلا رمي (٤٠٣ موظّفٌ بلا subscribers.view): success=false ⇒ paged=false — لو حُفظ لصار «حساباً لا يرقّم»
    // سبعة أيّام، فإن مُنح الصلاحيّة لاحقاً على حسابٍ كبير طُلبت قائمته الكاملة
    server.failStatus = 403;
    await session(token: 'tok-403');
    expect(await BigSubscribersApi.probe(), 0);
    await pumpEventQueue();
    expect(stored(), isEmpty, reason: 'ردٌّ مرفوض حُفظ حكماً');
    server.fail = true; // الشبكة سقطت
    await session(token: 'tok-2');
    await BigSubscribersApi.probe();
    await pumpEventQueue();
    expect(stored(), isEmpty);
    server
      ..fail = false
      ..success = true;
    await session(token: 'tok-3');
    final before = server.probes;
    await BigSubscribersApi.probe();
    expect(server.probes, before + 1, reason: 'فشلٌ سابق صار اختصاراً');
  });

  test('حسابٌ لا يرقّم (ايرث لنك/FTTH): يُختصر، وحجمه للشاشات ٠ كما كان', () async {
    server.paged = false;
    server.total = 700;
    await session(admin: 'earthlink:1025', name: 'admin@najaf40');
    expect(await BigSubscribersApi.probe(), 0);
    await pumpEventQueue();
    await session(admin: 'earthlink:1025', name: 'admin@najaf40', token: 'tok-2');
    expect(await BigSubscribersApi.probe(), 0);
    expect(server.probes, 1);
    expect(BigSubscribersApi.knownSize, 0, reason: 'غير المرقَّم يبقى بلا «حجم» للشاشات كما كان');
  });

  test('القائمة الكاملة قاربت الحدّ (≥ ٤٠٠٠ صفّ) ⇒ يُنسى «صغير» فيُسأل الساس في الفتح القادم', () async {
    await BigSubscribersApi.probe();
    await pumpEventQueue();
    final key = await KnownAccountSize.currentKey();
    await KnownAccountSize.noteList(3999, key: key);
    expect(stored().containsKey('2|m|admin@popq'), isTrue);
    await KnownAccountSize.noteList(4000, key: key);
    expect(stored().containsKey('2|m|admin@popq'), isFalse);
    await session(token: 'tok-2');
    await BigSubscribersApi.probe();
    expect(server.probes, 2);
  });

  test('تخزينٌ معطوب أو بشكلٍ آخر ⇒ الفحص كما كان، بلا رمي', () async {
    SharedPreferences.setMockInitialValues({KnownAccountSize.storeKey: '{oops'});
    _prefs = await SharedPreferences.getInstance();
    await session(token: 'tok-2');
    expect(await BigSubscribersApi.probe(), 0);
    expect(server.probes, 1);
    await pumpEventQueue(); // حفظ الحكم الجاري ينتهي قبل استبدال التخزين
    SharedPreferences.setMockInitialValues({
      KnownAccountSize.storeKey: jsonEncode({
        '2|m|admin@popq': {'size': '114', 'paged': 'yes', 'at': 'x'},
      }),
    });
    _prefs = await SharedPreferences.getInstance();
    await session(token: 'tok-3');
    await BigSubscribersApi.probe();
    expect(server.probes, 2);
  });

  test('لا يتجاوز ٣٠ حساباً — الأقدم يُحذف', () async {
    for (var i = 0; i < 35; i++) {
      clock = clock.add(const Duration(minutes: 1));
      await session(admin: '${1000 + i}', token: 'tok-$i');
      await BigSubscribersApi.probe();
      await pumpEventQueue();
    }
    final all = stored();
    expect(all.length, 30);
    expect(all.containsKey('1000|m|admin@popq'), isFalse);
    expect(all.containsKey('1034|m|admin@popq'), isTrue);
  });
}

late SharedPreferences _prefs;
