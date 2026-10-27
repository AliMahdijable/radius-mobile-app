import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/broadcast_api.dart';
import 'package:rad_mysvcs/screens/broadcast/broadcast_campaigns_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// حملات البثّ (٢٧ أكتوبر): القائمة تعرض كلّ حملة، والنشطة فيها إيقاف+حذف، والموقوفة فيها استئناف، والنقر يستدعي
/// المسار الصحيح بالمعرّف. خادمٌ وهميّ يرجع حملتين ويسجّل عمليّات التحكّم.
class _Api implements HttpClientAdapter {
  _Api(this.campaigns);
  final List<Map<String, dynamic>> campaigns;
  final List<String> calls = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    calls.add('${o.method} ${o.uri.path}');
    Object data = {'success': true};
    if (o.uri.path.endsWith('/api/whatsapp/broadcasts/5') && o.method == 'GET') {
      data = {'success': true, 'campaigns': campaigns};
    }
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _c({
  required String id,
  int pending = 0,
  int sent = 0,
  int processing = 0,
  bool paused = false,
  String sample = 'رسالة تجريبيّة',
}) =>
    {
      'batch_id': id,
      'sample': sample,
      'total': pending + sent + processing,
      'sent': sent,
      'pending': pending,
      'processing': processing,
      'failed': 0,
      'cancelled': 0,
      'paused': paused,
      'telegram': 0,
      'created_at': '2026-10-27 12:00:00',
    };

void main() {
  late _Api api;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth.token': 't', 'auth.admin_id': '5'});
    SharedPreferences.setMockInitialValues({});
    api = _Api([
      _c(id: 'bc_live', pending: 8, sent: 2),
      _c(id: 'bc_paused', pending: 5, sent: 5, paused: true),
      _c(id: 'bc_done', sent: 10),
    ]);
    ApiClient.dio.httpClientAdapter = api;
    final interceptors = List<Interceptor>.of(ApiClient.dio.interceptors);
    ApiClient.dio.interceptors.clear();
    addTearDown(() => ApiClient.dio.interceptors
      ..clear()
      ..addAll(interceptors));
  });

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('ar')],
      path: 'assets/translations',
      startLocale: const Locale('ar'),
      fallbackLocale: const Locale('ar'),
      saveLocale: false,
      child: const MaterialApp(
        locale: Locale('ar'),
        home: Directionality(textDirection: TextDirection.rtl, child: BroadcastCampaignsScreen()),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 40));
    }
  }

  testWidgets('النشطة فيها «إيقاف»+«حذف»، والموقوفة «استئناف»، والمنتهية بلا أزرار', (t) async {
    await EasyLocalization.ensureInitialized();
    await pump(t);
    expect(find.text('إيقاف'), findsOneWidget, reason: 'bc_live نشطة');
    expect(find.text('استئناف'), findsOneWidget, reason: 'bc_paused موقوفة');
    expect(find.text('حذف'), findsNWidgets(2), reason: 'النشطة والموقوفة لهما حذف، المنتهية لا');
    expect(find.text('موقوفة'), findsOneWidget);
    expect(find.text('انتهت'), findsOneWidget);
  });

  testWidgets('زرّ الإيقاف يستدعي المسار بالمعرّف الصحيح', (t) async {
    await EasyLocalization.ensureInitialized();
    await pump(t);
    await t.tap(find.text('إيقاف'));
    await t.pump(const Duration(milliseconds: 60));
    expect(api.calls.any((c) => c == 'POST /api/whatsapp/broadcast/bc_live/pause'), isTrue);
  });

  test('نموذج الحملة: active حين فيها معلّقٌ أو قيد معالجة فقط', () {
    expect(BroadcastCampaign.fromJson(_c(id: 'a', pending: 1))!.active, isTrue);
    expect(BroadcastCampaign.fromJson(_c(id: 'b', processing: 1))!.active, isTrue);
    expect(BroadcastCampaign.fromJson(_c(id: 'c', sent: 5))!.active, isFalse);
    expect(BroadcastCampaign.fromJson({'sample': 'x'}), isNull, reason: 'بلا معرّف لا حملة');
  });
}
