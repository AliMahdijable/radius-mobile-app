import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/screens/reports/activity_log_report_screen.dart';

import 'visual_perm/visual_perm_harness.dart';

/// ١٥ نوفمبر (المالك: «سجل النشاط لحد هسه ع حاله» — صورةٌ بمؤشّر تحميلٍ لا ينتهي على 3.0.19+182): الشاشة بلا «كل الشركات»
/// كانت تجمع الحركات والصرفيات بـ`Future.wait` ثمّ تحوّل ردّ الصرفيات إلى سجلٍّ بثلاثة حقول — وأضاف ٨ نوفمبر (abd6a2a2) حقلاً
/// رابعاً (`routedWrites`) إلى `ExpensesApi.list` ⇒ التحويل يرمي وقت التشغيل لا وقت التحليل ⇒ مؤشّر تحميلٍ إلى الأبد في 179–182،
/// والخادم يردّ خلال ربع ثانية. الحارس: الشاشة تُكمل وتعرض السطرين (حركةٌ من /api/activities وصرفيّةٌ من /api/admin/expenses)
/// بلا استثناء — ويُكسر هنا قبل المستخدم إن عاد أيّ تحويلٍ بشكلٍ لا يطابق.
void main() {
  setUpAll(visualSetUpAll);

  testWidgets('سجلّ النشاط بلا «كل الشركات»: الحركات والصرفيات تُعرض، ولا مؤشّر تحميلٍ باقٍ ولا استثناء', (t) async {
    await visualSetUp(s1bSasOwner);
    final server = _LogServer();
    ApiClient.dio.httpClientAdapter = server;
    await pumpVisual(t, const VisualDevice('390', Size(390, 844), 2), home: (_) => const ActivityLogReportScreen());
    await settle(t, seconds: 2);
    expect(t.takeException(), isNull);
    expect(server.asked, containsAll(['/api/activities', '/api/admin/expenses']), reason: 'الطلبان معاً كما كانا');
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'التحميل انتهى');
    expect(find.textContaining('تفعيل حارس السجل'), findsOneWidget, reason: 'سطر الحركة');
    expect(find.textContaining('صرفية حارس السجل'), findsOneWidget, reason: 'سطر الصرفيّة');
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 4));
    await visualTearDown();
  });
}

class _LogServer implements HttpClientAdapter {
  final asked = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    asked.add(o.path);
    final Map<String, dynamic> body;
    if (o.path == '/api/activities') {
      body = {
        'success': true,
        'data': [
          {
            'id': 11,
            'action_type': 'SUBSCRIBER_ACTIVATE',
            'action_description': 'تفعيل حارس السجل',
            'admin_id': '2',
            'admin_username': 'fixture-owner',
            'target_name': 'sub_fixture',
            'user_username': 'sub_fixture',
            'created_at': '2026-11-14 10:00:00',
            'status': 'SUCCESS',
          },
        ],
        'pagination': {'total': 1},
      };
    } else if (o.path == '/api/admin/expenses') {
      body = {
        'success': true,
        'expenses': [
          {'id': 7, 'amount': 3000, 'note': 'صرفية حارس السجل', 'expense_date': '2026-11-14'},
        ],
        'total': 3000,
      };
    } else {
      body = {'success': true, 'data': <dynamic>[]};
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
