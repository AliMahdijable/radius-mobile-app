import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/screens/dashboard/dashboard_screen.dart';
import 'package:rad_mysvcs/screens/whatsapp/whatsapp_status_screen.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'emp_merged/emp_merged_fixture.dart';
import 'visual_perm/visual_perm_harness.dart';

/// حبّة واتساب الرئيسيّة بـ«كل الصفحات» للموظّف (مراجعة 3.0.18+179): بلا `whatsapp.connect` (ومعه whatsapp.send) ونقرها وحال
/// الصفحات لم تصل («جارٍ التحقق…») ⇒ رسالة القفل، لا شاشة ربط واتساب. وبعد وصولها قائمة الصفحات كما كانت (فتح «صفحتي» مقفل فيها).

/// يُمسك فحص واتساب الصفحات حتى [gate] — الحبّة تبقى «جارٍ التحقق…».
class _HoldWa implements HttpClientAdapter {
  _HoldWa(this.inner);
  final HttpClientAdapter inner;
  final gate = Completer<void>();

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    if (o.uri.path.startsWith('/api/whatsapp/connection-status/')) await gate.future;
    return inner.fetch(o, rs, cf);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(visualSetUpAll);

  testWidgets('بلا whatsapp.connect: «جارٍ التحقق…» ⇒ رسالة القفل لا شاشة الربط؛ وبعد الوصول قائمة الصفحات', (t) async {
    final body = companiesBody();
    final list = [for (final e in body['companies']! as List) Map<String, Object?>.from(e as Map)];
    list[0]['permissions'] = {...permsA, 'whatsapp.connect': false};
    final srv = await empUp(companies: {...body, 'companies': list});
    PermissionsService.debugSet(isEmployee: true, permissions: {...empKeys, 'whatsapp.connect': false}, pages: empPages);
    final hold = _HoldWa(srv);
    ApiClient.dio.httpClientAdapter = hold;
    await t.runAsync(MergedMode.enter);
    await pumpVisual(t, phone, home: (_) => const DashboardScreen());
    await settle(t, seconds: 3);

    expect(find.text('جارٍ التحقق…'), findsOneWidget);
    await t.tap(find.text('جارٍ التحقق…'));
    await settle(t, seconds: 1);
    expect(find.byType(WhatsAppStatusScreen), findsNothing, reason: 'شاشة الربط تحتاج whatsapp.connect');
    expect(find.text('ليس لديك صلاحيّة لهذا القسم — اطلبها من مديرك'), findsOneWidget);

    // وصلت حال الصفحات ⇒ النقر يفتح قائمتها كما كان
    hold.gate.complete();
    await settle(t, seconds: 3);
    expect(find.text('واتساب 1/2'), findsOneWidget);
    await t.tap(find.text('واتساب 1/2'));
    await settle(t, seconds: 1);
    expect(find.byKey(const ValueKey('wa-co-$kA')), findsOneWidget);
    expect(find.byType(WhatsAppStatusScreen), findsNothing);
    Navigator.of(t.element(find.byKey(const ValueKey('wa-co-$kA')))).pop();
    await settle(t, seconds: 1);
    expect(t.takeException(), isNull);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    await empDown();
  });
}
