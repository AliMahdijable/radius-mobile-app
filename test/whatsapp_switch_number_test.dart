import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/screens/whatsapp/whatsapp_status_screen.dart';

import 'visual_perm/visual_perm_harness.dart';

/// واتساب (١٢ نوفمبر، بلاغ وكيل jt:6990: «فصل نهائياً ومجاي يربط»): الحساب مربوطٌ على 0788… («مركز البرق»)
/// والمدير يضغط «قطع» ثمّ «رمز الاقتران» لـ0773… — كان الخادم يعيد الربط القديم بلا رمز فتكتب الشاشة «خطأ» ١٥ مرّة،
/// ولا زرّ يفكّ رقماً شغّالاً. الآن: 409 LINKED_TO_OTHER_NUMBER ⇒ «تفكّه وتربط الجديد؟» ⇒ فكٌّ ⇒ الرمز، و«فكّ الربط»
/// زرٌّ صريح بتأكيد، والرقم نفسه ⇒ «متّصل أصلاً» لا «خطأ».
class _SwitchServer implements HttpClientAdapter {
  _SwitchServer(this.inner, {this.linked = '9647883330099', this.connected = true});
  final HttpClientAdapter inner;
  String? linked;
  bool connected;
  final calls = <String>[];

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  static String _norm(Object? v) {
    final d = '${v ?? ''}'.replaceAll(RegExp(r'\D'), '');
    return d.startsWith('07') ? '964${d.substring(1)}' : d;
  }

  Map<String, dynamic> _body(RequestOptions o) {
    final d = o.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    if (d is String && d.isNotEmpty) return Map<String, dynamic>.from(jsonDecode(d) as Map);
    return const {};
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (o.path.startsWith('/api/whatsapp/connection-status/')) {
      final on = linked != null && connected;
      return _json(200, on
          ? {'success': true, 'connected': true, 'phone': linked, 'pushname': 'مركز البرق', 'platform': 'WAHA-GOWS'}
          : {'success': true, 'connected': false});
    }
    if (o.path == '/api/whatsapp/disconnect') {
      calls.add('disconnect');
      connected = false;
      return _json(200, {'success': true, 'message': 'تم فصل الواتساب بنجاح'});
    }
    if (o.path == '/api/whatsapp/start-session-code') {
      final req = _norm(_body(o)['phone']);
      calls.add('code:$req');
      if (linked != null) {
        connected = true; // الخادم الحقيقيّ يعيد وصل الربط القديم قبل أن يحكم
        if (linked != req) {
          return _json(409, {
            'success': false,
            'code': 'LINKED_TO_OTHER_NUMBER',
            'linkedToOtherNumber': true,
            'unlinkRequired': true,
            'linkedPhone': linked,
            'pushname': 'مركز البرق',
            'requestedPhone': req,
            'message': 'واتساب هذا الحساب مربوط على الرقم 07883330099',
          });
        }
        return _json(200, {'success': true, 'alreadyConnected': true, 'phone': linked, 'message': 'متّصل أصلاً'});
      }
      return _json(200, {'success': true, 'pairCode': 'K7QX-2M9P', 'phone': req});
    }
    if (o.path == '/api/whatsapp/unlink') {
      calls.add('unlink:${_body(o)['confirm'] == true ? 'confirm' : 'none'}');
      linked = null;
      connected = false;
      return _json(200, {'success': true, 'unlinked': true, 'previousPhone': '9647883330099'});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

const _narrow = VisualDevice('_320', Size(320, 760), 3);

void main() {
  setUpAll(visualSetUpAll);
  tearDown(visualTearDown);

  Future<_SwitchServer> openScreen(WidgetTester t, {String? linked = '9647883330099', bool connected = true, VisualDevice d = phone}) async {
    final inner = await visualSetUp(s1bSasOwner);
    final server = _SwitchServer(inner, linked: linked, connected: connected);
    ApiClient.dio.httpClientAdapter = server;
    await pumpVisual(t, d, home: (_) => const WhatsAppStatusScreen());
    await settle(t, seconds: 3);
    return server;
  }

  Future<void> tapText(WidgetTester t, String text) async {
    final f = find.text(text);
    await t.ensureVisible(f.first);
    await t.pump();
    await t.tap(f.first);
    await settle(t, seconds: 2);
  }

  Future<void> requestCodeFor(WidgetTester t, String number) async {
    await tapText(t, 'رمز الاقتران');
    await t.enterText(find.byType(TextField).first, number);
    await t.pump();
    await tapText(t, 'اتصال');
  }

  testWidgets('متّصل: «قطع» و«تهيئة كاملة» و«فكّ الربط — لتبديل الرقم» — وبعرض ٣٢٠ بلا فيض', (t) async {
    final server = await openScreen(t, d: _narrow);
    expect(find.text('قطع'), findsOneWidget);
    expect(find.text('تهيئة كاملة'), findsOneWidget);
    expect(find.text('فكّ الربط — لتبديل الرقم'), findsOneWidget);
    await shoot(t, s1bSasOwner, 'wa_connected_unlink', _narrow, server.inner as VisualServer);
  });

  testWidgets('«فكّ الربط»: تأكيدٌ يذكر الرقم ⇒ unlink بتأكيد ⇒ «انفكّ ربط الرقم»', (t) async {
    final server = await openScreen(t);
    await tapText(t, 'فكّ الربط — لتبديل الرقم');
    expect(find.text('فكّ ربط الرقم'), findsOneWidget);
    expect(find.textContaining('07883330099'), findsWidgets);
    await tapText(t, 'فكّ الربط');
    expect(server.calls, ['unlink:confirm']);
    expect(find.text('انفكّ ربط الرقم — اربط الرقم الجديد هسه'), findsOneWidget);
    expect(find.text('غير متصل'), findsWidgets);
  });

  testWidgets('بعد «قطع»: رمزٌ لـ0773 ⇒ «تفكّه وتربط؟» ⇒ فكٌّ ⇒ رمز الجديد — لا «خطأ»', (t) async {
    final server = await openScreen(t, connected: false);
    await requestCodeFor(t, '07730830030');
    expect(find.text('الحساب مربوط على رقم ثاني'), findsOneWidget);
    expect(find.textContaining('07883330099'), findsWidgets);
    expect(find.textContaining('مركز البرق'), findsWidgets);
    expect(find.textContaining('07730830030'), findsWidgets);
    await shoot(t, s1bSasOwner, 'wa_switch_confirm', phone, server.inner as VisualServer);
    await tapText(t, 'فكّ وربط الجديد');
    expect(server.calls, ['code:9647730830030', 'unlink:confirm', 'code:9647730830030']);
    expect(find.text('K7QX-2M9P'), findsOneWidget);
    expect(find.text('خطأ'), findsNothing);
  });

  testWidgets('رفض التبديل ⇒ لا فكّ ولا رمز، والربط القديم باقٍ', (t) async {
    final server = await openScreen(t, connected: false);
    await requestCodeFor(t, '07730830030');
    await tapText(t, 'إلغاء');
    expect(server.calls, ['code:9647730830030']);
    expect(server.linked, '9647883330099');
    expect(find.text('K7QX-2M9P'), findsNothing);
    expect(find.text('خطأ'), findsNothing);
  });

  testWidgets('الرقم نفسه ⇒ «متّصل أصلاً» أخضر، لا «خطأ»', (t) async {
    final server = await openScreen(t, linked: '9647730830030', connected: false);
    await requestCodeFor(t, '07730830030');
    expect(server.calls, ['code:9647730830030']);
    expect(find.text('واتساب متّصل أصلاً على هذا الرقم ✅'), findsOneWidget);
    expect(find.text('خطأ'), findsNothing);
  });
}
