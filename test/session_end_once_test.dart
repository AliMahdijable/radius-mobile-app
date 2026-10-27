import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';

import 'sim_el/sim_harness.dart';

/// المالك ٢٧ أكتوبر (نسخة الماك): «اكثر من ٢٠ مرّة انتهت الجلسة يظهر خطأ بالأسفل» والشاشات متداخلة.
/// موجة طلباتٍ متوازية تُرفض معاً ⇒ كان كلّ طلبٍ يمسح الجلسة ويُطلق إشارته، فعشرون رسالة وعشرون انتقالاً
/// متراكباً، والمسح يُفرغ ذاكرة الجدول فيطلبها ثانيةً فتعود موجة. الآن: إعلانٌ واحد لكلّ جلسة.
void main() {
  late SimServer server;
  setUpAll(simSetUpAll);
  setUp(() async => server = await simSetUp());

  Future<int> wave(int n, {String prefix = 'p'}) async {
    for (var i = 0; i < n; i++) {
      server.reply('GET', '/api/$prefix$i', 401, {'success': false, 'message': 'Unauthorized'});
    }
    final before = authExpiredSignal.value;
    await Future.wait([
      for (var i = 0; i < n; i++)
        ApiClient.dio.get<Object?>('/api/$prefix$i').then<Object?>((r) => r, onError: (Object _) => null),
    ]);
    return authExpiredSignal.value - before;
  }

  test('🚨 عشرون طلباً مرفوضاً معاً ⇒ إعلانٌ واحد لا عشرون', () async {
    expect(await wave(20), 1);
  });

  test('موجةٌ ثانية بعد المسح (بلا توكن) ⇒ لا إعلان آخر — الحلقة تقف', () async {
    expect(await wave(12), 1);
    expect(await wave(12, prefix: 'q'), 0);
  });

  test('دخولٌ جديد ثمّ ماتت جلسته ⇒ تُعلَن هي أيضاً', () async {
    expect(await wave(5), 1);
    await const FlutterSecureStorage().write(key: 'auth.token', value: 'sim-token-2');
    expect(await wave(5, prefix: 'r'), 1);
  });

  test('طلبٌ مفردٌ مرفوض كما كان: إعلانٌ واحد', () async {
    server.reply('GET', '/api/one', 401, {'success': false});
    final before = authExpiredSignal.value;
    final r = await ApiClient.dio.get<Object?>('/api/one').then<Response<Object?>?>((r) => r, onError: (Object _) => null);
    expect(r?.statusCode, 401);
    expect(authExpiredSignal.value - before, 1);
  });
}
