import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/fiberx_entertainment_api.dart';
import 'package:rad_mysvcs/screens/subscribers/fiberx_entertainment_view.dart';

/// «الخدمة الترفيهية» (المحتوى) — الـAPI يقرأ العقد، والواجهة تعرض الأعداد وتبحث محلّيّاً.
class _Fake implements HttpClientAdapter {
  _Fake(this.body, {this.status = 200});
  final Map<String, dynamic> body;
  final int status;
  final List<String> paths = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    paths.add(o.uri.path);
    return ResponseBody.fromString(jsonEncode(body), status,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _payload() => {
      'success': true,
      'summary': {'total': 14, 'active': 3, 'expired': 11, 'near_expiry': 0},
      'data': [
        {'username': 'ent.one', 'name': 'علي', 'phone': '07700000001', 'package': 'TOD',
         'status': 'active', 'status_label': 'نشط', 'expiry': '2026-12-01 00:00:00', 'remaining_days': 30, 'months': 1},
        {'username': 'ent.two', 'name': 'حسن', 'phone': '07700000002', 'package': 'Ultimate',
         'status': 'expired', 'status_label': 'منتهٍ', 'expiry': '2026-09-01 00:00:00', 'remaining_days': -20, 'months': 3},
      ],
    };

void main() {
  late List<Interceptor> saved;
  setUp(() {
    saved = List<Interceptor>.of(ApiClient.dio.interceptors);
    ApiClient.dio.interceptors.clear();
  });
  tearDown(() {
    ApiClient.dio.interceptors
      ..clear(keepImplyContentTypeInterceptor: false)
      ..addAll(saved);
  });

  test('الـAPI: يقرأ الملخّص والصفوف من العقد', () async {
    ApiClient.dio.httpClientAdapter = _Fake(_payload());
    final r = await FiberxEntertainmentApi.fetch();
    expect(r.error, isNull);
    expect([r.result!.summary.total, r.result!.summary.active, r.result!.summary.expired],
        [14, 3, 11]);
    expect(r.result!.rows.length, 2);
    expect(r.result!.rows.first.status, 'active');
  });

  test('الـAPI: success=false ⇒ رسالة لا رمي', () async {
    ApiClient.dio.httpClientAdapter =
        _Fake({'success': false, 'message': 'تعذّر'}, status: 200);
    final r = await FiberxEntertainmentApi.fetch();
    expect(r.result, isNull);
    expect(r.error, 'تعذّر');
  });

  testWidgets('الواجهة: الأعداد الأربعة والصفوف، والبحث يصفّي محلّيّاً', (t) async {
    ApiClient.dio.httpClientAdapter = _Fake(_payload());
    await t.pumpWidget(const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: FiberxEntertainmentView()),
      ),
    ));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    // أربع بطاقات أعداد
    expect(find.text('الإجمالي'), findsOneWidget);
    expect(find.text('نشطون'), findsOneWidget);
    expect(find.text('منتهون'), findsOneWidget);
    expect(find.text('على وشك'), findsOneWidget);
    // الصفّان
    expect(find.text('علي'), findsOneWidget);
    expect(find.text('حسن'), findsOneWidget);
    // البحث المحلّيّ
    await t.enterText(find.byType(TextField), 'ent.two');
    await t.pump(const Duration(milliseconds: 100));
    // عليّ (TOD) اختفى، وحسن (Ultimate) بقي — نتحقّق بالباقة لتفادي نصّ حقل البحث نفسه.
    expect(find.text('علي'), findsNothing);
    expect(find.text('TOD'), findsNothing);
    expect(find.text('Ultimate'), findsOneWidget);
  });
}
