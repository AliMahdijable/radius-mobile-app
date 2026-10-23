import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';
import 'package:rad_mysvcs/screens/whatsapp/whatsapp_status_screen.dart';

import 'visual_perm/visual_perm_harness.dart';

/// واتساب (٢٣ أكتوبر، بلاغ وكيل بصورة): «تعذّر إنشاء الرمز» لطلبٍ لم يصل للخادم أصلاً، و«غير متصل» بلا سبب بعد أن شال
/// واتساب الربط (سجلّ WAHA: device removed بعد ٧ ثوانٍ من الربط).
///   • الطلب الذي لم يصل ⇒ «تعذّر الوصول إلى الخادم — تحقّق من الإنترنت»، ورسالة الخادم العربيّة تبقى أوّلاً.
///   • الخادم يرسل remoteLogoutAt/remoteLogoutAfterPairSec ⇒ تنبيه «واتساب فصل الربط من جهته» بدل «اربط من جديد» العامّ.
class _WaServer implements HttpClientAdapter {
  _WaServer(this.inner);
  final HttpClientAdapter inner;
  Map<String, dynamic> status = {'success': true, 'connected': false};
  Object? codeReply; // DioException تُرمى، أو (status, body)
  int codeCalls = 0;

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (o.path.startsWith('/api/whatsapp/connection-status/')) return _json(200, status);
    if (o.path == '/api/whatsapp/start-session-code') {
      codeCalls += 1;
      final r = codeReply;
      if (r is DioException) throw r.copyWith(requestOptions: o);
      if (r is (int, Map<String, dynamic>)) return _json(r.$1, r.$2);
      return _json(200, {'success': true, 'pairCode': 'ABCD-EFGH'});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

void main() {
  setUpAll(visualSetUpAll);

  test('WhatsConnectionStatus: remoteLogoutAt + بُعده عن الربط، وغيابهما null', () {
    final s = WhatsConnectionStatus.fromJson({
      'connected': false,
      'remoteLogoutAt': 1761149243,
      'remoteLogoutAfterPairSec': 7,
    });
    expect(s.remoteLogoutAt, 1761149243);
    expect(s.remoteLogoutAfterPairSec, 7);
    final none = WhatsConnectionStatus.fromJson({'connected': false});
    expect(none.remoteLogoutAt, isNull);
    expect(none.remoteLogoutAfterPairSec, isNull);
    expect(const WhatsConnectionStatus.disconnected().remoteLogoutAt, isNull);
  });

  group('مع الخادم الوهميّ', () {
    tearDown(visualTearDown);

    testWidgets('startSessionCode: لم يصل ⇒ «تحقّق من الإنترنت»، ورسالة الخادم العربيّة أوّلاً', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      final server = _WaServer(inner);
      ApiClient.dio.httpClientAdapter = server;

      server.codeReply = DioException.connectionError(
          requestOptions: RequestOptions(path: '/api/whatsapp/start-session-code'), reason: 'no route');
      var r = await t.runAsync(() => WhatsAppApi.startSessionCode(phone: '07827267556'));
      expect(r!.ok, isFalse);
      expect(r.message, 'تعذّر الوصول إلى الخادم — تحقّق من الإنترنت');

      server.codeReply = DioException.receiveTimeout(
          timeout: const Duration(seconds: 30), requestOptions: RequestOptions(path: '/api/whatsapp/start-session-code'));
      r = await t.runAsync(() => WhatsAppApi.startSessionCode(phone: '07827267556'));
      expect(r!.message, 'انتهت مهلة الاتصال — تحقّق من الشبكة وأعد المحاولة');

      server.codeReply = (423, <String, dynamic>{'success': false, 'message': 'واتساب قيّد الحساب مؤقتاً'});
      r = await t.runAsync(() => WhatsAppApi.startSessionCode(phone: '07827267556'));
      expect(r!.message, 'واتساب قيّد الحساب مؤقتاً');

      server.codeReply = null;
      r = await t.runAsync(() => WhatsAppApi.startSessionCode(phone: '07827267556'));
      expect(r!.ok, isTrue);
      expect(r.code, 'ABCD-EFGH');
      expect(server.codeCalls, 4);
    });

    Future<_WaServer> openScreen(WidgetTester t, Map<String, dynamic> status) async {
      final inner = await visualSetUp(s1bSasOwner);
      final server = _WaServer(inner)..status = status;
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phone, home: (_) => const WhatsAppStatusScreen());
      await settle(t, seconds: 3);
      return server;
    }

    testWidgets('انفصل بعد ٧ ثوانٍ من الربط ⇒ تنبيه «لا تعيد الربط هسه» بدل «اربط من جديد»', (t) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final server = await openScreen(t, {
        'success': true,
        'connected': false,
        'status': 'SCAN_QR_CODE',
        'needsPairing': true,
        'remoteLogoutAt': now - 120,
        'remoteLogoutAfterPairSec': 7,
      });
      expect(find.text('واتساب فصل الربط من جهته'), findsOneWidget);
      expect(find.textContaining('انفصل بعد 7 ثانية من الربط'), findsOneWidget);
      expect(find.textContaining('لا تعيد الربط هسه'), findsOneWidget);
      expect(find.text('جلسة واتساب تحتاج إعادة ربط'), findsNothing);
      await shoot(t, s1bSasOwner, 'wa_remote_logout_fast', phone, server.inner as VisualServer);
    });

    testWidgets('انفصالٌ بعد مدّة من الربط ⇒ «اربطه من جديد» بوقته', (t) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await openScreen(t, {
        'success': true,
        'connected': false,
        'status': 'SCAN_QR_CODE',
        'remoteLogoutAt': now - 3600,
        'remoteLogoutAfterPairSec': 7200,
      });
      expect(find.text('واتساب فصل الربط من جهته'), findsOneWidget);
      expect(find.textContaining('اربطه من جديد'), findsOneWidget);
    });

    testWidgets('أقدم من يوم، أو متصل ⇒ لا تنبيه انفصال', (t) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await openScreen(t, {
        'success': true,
        'connected': false,
        'status': 'SCAN_QR_CODE',
        'needsPairing': true,
        'remoteLogoutAt': now - 2 * 24 * 3600,
        'remoteLogoutAfterPairSec': 7,
      });
      expect(find.text('واتساب فصل الربط من جهته'), findsNothing);
      expect(find.text('جلسة واتساب تحتاج إعادة ربط'), findsOneWidget);
    });
  });
}
