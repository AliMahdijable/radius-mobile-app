import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

/// موظّفٌ بلا صلاحيّة الأجهزة (٤ نوفمبر — جولة فحص الخادم: ~١٠ آلاف ردّ 403 يوميّاً على إعداد جهاز المشترك من ٣–٤ أجهزة،
/// كلّ مشتركٍ كلّ ٥ دقائق مع موجة الفحص). الثوابت: بلا الصلاحيّة لا نداء أصلاً؛ ورفض الخادم (403) يُحفظ للحساب نصف ساعة؛ ومن
/// يملكها كما كان.
class _Srv implements HttpClientAdapter {
  _Srv(this.status);
  int status;
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add(o.uri.path);
    final body = status == 403
        ? {'success': false, 'code': 'PERMISSION_DENIED', 'message': 'لا تملك صلاحيّة'}
        : o.uri.path == '/api/v2/subscribers/device-batch'
            ? {'success': true, 'configs': <String, dynamic>{}}
            : {'success': true, 'device': null};
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Srv srv;
  var t = DateTime.utc(2026, 11, 4, 16);

  setUp(() {
    srv = _Srv(200);
    ApiClient.dio.httpClientAdapter = srv;
    DeviceConfigApi.clearAllCaches();
    DeviceConfigApi.now = () => t;
    Perms.debugReset();
  });
  tearDown(() {
    DeviceConfigApi.now = DateTime.now;
    Perms.debugReset();
  });

  test('موظّفٌ بلا صلاحيّة الأجهزة ⇒ لا نداء أصلاً (فردٌ ولا دفعة)، والنتيجة «لا إعداد» لا خطأ', () async {
    Perms.debugSet(isEmployee: true, permissions: {'subscribers.view': true});
    final cfg = await DeviceConfigApi.fetchConfig('u1');
    expect(cfg, isNotNull);
    expect(await DeviceConfigApi.warmBatch(['u1', 'u2', 'u3']), isFalse, reason: 'الكاش ليس مرجعاً — والفرديّ مقفلٌ كذلك');
    for (final u in ['u1', 'u2', 'u3']) {
      await DeviceConfigApi.fetchConfig(u);
    }
    expect(srv.calls, isEmpty);
  });

  test('موظّفٌ يملك أيّ صلاحيّة أجهزة، أو المدير ⇒ كما كان', () async {
    Perms.debugSet(isEmployee: true, permissions: {'devices.monitor': true});
    await DeviceConfigApi.fetchConfig('u1');
    expect(srv.calls, ['/api/subscribers/u1/device']);
    Perms.debugSet(isEmployee: false);
    DeviceConfigApi.clearAllCaches();
    expect(await DeviceConfigApi.warmBatch(['u1', 'u2']), isTrue);
    expect(srv.calls.last, '/api/v2/subscribers/device-batch');
  });

  test('رفض الخادم (403) يُحفظ للحساب نصف ساعة: نداءٌ واحد ثمّ لا شيء لأيّ مشترك؛ بعدها يُسأل ثانيةً؛ والخروج يمسحه', () async {
    srv.status = 403; // الصلاحيّات لم تُحمَّل بعد (has = true) والخادم يرفض
    expect(await DeviceConfigApi.warmBatch(['a', 'b', 'c']), isFalse);
    expect(srv.calls, ['/api/v2/subscribers/device-batch']);
    for (final u in ['a', 'b', 'c', 'd']) {
      await DeviceConfigApi.fetchConfig(u);
    }
    expect(srv.calls.length, 1, reason: 'كان: نداءٌ لكلّ مشترك بعد رفض الدفعة');
    t = t.add(const Duration(minutes: 29));
    await DeviceConfigApi.fetchConfig('e');
    expect(srv.calls.length, 1);
    t = t.add(const Duration(minutes: 2));
    await DeviceConfigApi.fetchConfig('e');
    expect(srv.calls.length, 2, reason: 'بعد نصف ساعة يُسأل الخادم ثانيةً (قد تكون الصلاحيّة أُعطيت)');
    DeviceConfigApi.clearAllCaches();
    srv.status = 200;
    await DeviceConfigApi.fetchConfig('f');
    expect(srv.calls.length, 3, reason: 'الخروج/تبديل الحساب يمسح الرفض');
  });
}
