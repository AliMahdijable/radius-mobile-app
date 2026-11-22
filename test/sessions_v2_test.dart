import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/screens/reports/v2/sessions_v2_screen.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_export.dart';

import 'visual_perm/visual_perm_harness.dart';

// «الجلسات» على الشكل الموحّد (٢٢ نوفمبر): المتّصلون الآن أو السجلّ، البحث من الخادم، الأعداد والأحجام، و«ناقص» عند حدّ الساس (2000)،
// والتصدير بالفلاتر حرفاً؛ و«سجلّ الجلسات» من نافذة مشتركٍ يفتح على السجلّ مبحوثاً باسمه.

class _Server implements HttpClientAdapter {
  _Server(this.inner, {this.online = 3});
  final VisualServer inner;
  final int online;
  final asked = <(String, Map<String, dynamic>)>[];

  Map<String, Object?> _s(int i, {bool live = true}) => {
        if (!live) 'radacctid': 1000 + i,
        'username': 'u$i',
        'user_manager': i.isEven ? 'ali.h' : 'admin@sup',
        'ip_address': '10.0.0.$i',
        'mac': 'AA:BB:CC:00:00:${i.toRadixString(16).padLeft(2, '0')}',
        'bytes_in': 1024 * 1024 * (i + 1),
        'bytes_out': 1024 * (i + 1),
        'started_at': '2026-11-22 ${(8 + i % 10).toString().padLeft(2, '0')}:00:00',
        if (!live) 'ended_at': '2026-11-22 20:00:00',
      };

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final p = o.uri.path;
    if (p == '/api/v2/online-users' || p == '/api/v2/sessions') {
      final q = Map<String, dynamic>.from(o.queryParameters);
      asked.add((p, q));
      final live = p == '/api/v2/online-users';
      final n = live ? online : 4;
      final u = q['username']?.toString();
      final rows = [
        for (var i = 0; i < n; i++)
          if (u == null || 'u$i' == u || u == 'u7') _s(u == 'u7' ? 7 : i, live: live),
      ];
      return ResponseBody.fromString(jsonEncode({'success': true, 'data': rows}), 200, headers: {
        Headers.contentTypeHeader: ['application/json'],
      });
    }
    return inner.fetch(o, body, cancel);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(visualSetUpAll);

  Future<void> open(WidgetTester t, Widget screen) async {
    await pumpVisual(t, const VisualDevice('', Size(430, 2400), 2), home: (_) => screen);
    for (var i = 0; i < 10; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    ReportExportActions.debugSink = null;
    await visualTearDown();
  }

  testWidgets('المتّصلون الآن: الأعداد والأحجام، والتصدير برأسه، ثمّ السجلّ من مسارٍ آخر', (t) async {
    final server = _Server(await visualSetUp(s1bSasOwner));
    ApiClient.dio.httpClientAdapter = server;
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      await open(t, const SessionsV2Screen());
      expect(server.asked.single.$1, '/api/v2/online-users');
      expect(server.asked.single.$2['count'], '2000');
      final k = t.widget<RpKpiGrid>(find.byType(RpKpiGrid)).kpis;
      expect(k[0].value, 3);
      expect(k[1].value, 3);
      expect(k[2].text, '6.0 MB', reason: '1+2+3 ميجا');
      await t.scrollUntilVisible(find.text('Excel'), 500, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('Excel'));
      await t.pump(const Duration(milliseconds: 200));
      expect(got.single.rows.length, 3);
      expect(got.single.details.first, 'المتّصلون الآن');
      expect(got.single.details, contains('عدد الصفوف: 3'));
      expect(got.single.details.any((d) => d.startsWith('ناقص')), isFalse);
      // السجلّ
      await t.scrollUntilVisible(find.text('سجلّ الجلسات'), -500, scrollable: find.byType(Scrollable).first);
      await t.tap(find.descendant(of: find.byType(SheetSegmented), matching: find.text('سجلّ الجلسات')));
      for (var i = 0; i < 8; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(server.asked.last.$1, '/api/v2/sessions');
      expect(t.widget<RpKpiGrid>(find.byType(RpKpiGrid)).kpis.first.value, 4);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('حدّ الساس (2000) ⇒ «ناقص» على الشاشة وفي رأس الملفّ — لا كأنّه الكلّ', (t) async {
    final server = _Server(await visualSetUp(s1bSasOwner), online: 2000);
    ApiClient.dio.httpClientAdapter = server;
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      await open(t, const SessionsV2Screen());
      expect(find.textContaining('بلغ الحدّ (2000'), findsOneWidget);
      await t.scrollUntilVisible(find.text('PDF'), 800, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('PDF'));
      await t.pump(const Duration(milliseconds: 200));
      expect(got.single.details.any((d) => d.startsWith('ناقص: بلغ الحدّ')), isTrue);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('«سجلّ الجلسات» من نافذة مشترك ⇒ السجلّ مبحوثاً باسمه', (t) async {
    final server = _Server(await visualSetUp(s1bSasOwner));
    ApiClient.dio.httpClientAdapter = server;
    try {
      await open(t, const SessionsV2Screen(initialUsername: 'u7'));
      expect(server.asked.single.$1, '/api/v2/sessions');
      expect(server.asked.single.$2['username'], 'u7');
      expect(find.text('سجلّ جلسات u7'), findsOneWidget);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });
}
