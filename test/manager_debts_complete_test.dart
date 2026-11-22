import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/screens/reports/all_managers_debts_screen.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_export.dart';
import 'package:rad_mysvcs/services/merged_manager_debts.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «ديون المدراء» كاملاً (٢٢ نوفمبر — المالك: «الPDF جاي يظهر مرات مقصوص مو كامل»): كان التقرير يقرأ حركات أوّل 60 مديراً بآخر
/// 100 حركة لكلٍّ منهم فيغيب الباقي عنه وعن تصديره بصمت. الآن أوّل [kManagerMovementsCap] بأقصى ما يعطيه الخادم (500)، وما بلغ
/// السقف يُسمّى في الملخّص ورأس الملفّ؛ والقراءة الأساسيّة تتعذّر ⇒ «تعذّر» باسمه لا أصفار.
ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });

String _today(int minute) {
  final d = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} 09:${two(minute % 60)}:00';
}

class _Srv implements HttpClientAdapter {
  _Srv(this.inner, {this.managers = 70, this.busyRows = 600, this.failCore = false});
  final HttpClientAdapter inner;
  final int managers;
  final int busyRows;
  final bool failCore;
  final movementLimits = <String, String>{};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final path = o.uri.path;
    Future<ResponseBody> ok(Map<String, Object?> body) async => _json(200, {'success': true, ...body});
    if (path == '/api/admin/manager-debts/access') return ok({'hasSubAdmins': true, 'subAdmins': const []});
    if (path == '/api/v2/managers/full') {
      if (failCore) return _json(409, {'success': false, 'message': 'انتهت الجلسة — افتح الصفحة من جديد'});
      return ok({
        'data': [for (var i = 1; i <= managers; i++) {'id': i, 'username': 'm$i', 'total_debt': i == 1 ? 50000 : 0}],
        'total': managers,
      });
    }
    if (path == '/api/admin/manager-debts/summary') return ok({'totals': {'total_remaining': 0}, 'perDebtor': const []});
    if (path == '/api/admin/manager-debts') return ok({'debts': const []});
    final mv = RegExp(r'^/api/admin/managers/(\d+)/movements$').firstMatch(path);
    if (mv != null) {
      final id = mv.group(1)!;
      movementLimits[id] = '${o.queryParameters['limit']}';
      final limit = int.tryParse('${o.queryParameters['limit']}') ?? 100;
      // المدير 1 كثير الحركات (600 > سقف الخادم)، والبقيّة حركةٌ واحدة شحنٌ نقديّ
      final all = id == '1' ? busyRows : 1;
      return ok({
        'movements': [
          for (var k = 0; k < all && k < limit; k++)
            {'row_type': 'balance', 'id': int.parse(id) * 1000 + k, 'sub_kind': 'deposit_cash', 'amount': 1000, 'source': 'sas4', 'event_at': _today(k)},
        ],
      });
    }
    return inner.fetch(o, rs, cf);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(visualSetUpAll);

  Future<_Srv> up({bool failCore = false}) async {
    final srv = _Srv(await visualSetUp(s1bSasOwner), failCore: failCore);
    ApiClient.dio.httpClientAdapter = srv;
    return srv;
  }

  Future<void> open(WidgetTester t) async {
    await pumpVisual(t, const VisualDevice('', Size(430, 1600), 2), home: (_) => const AllManagersDebtsScreen());
    for (var i = 0; i < 30; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('أكثر من 60 مديراً ⇒ حركات كلّهم بأقصى الخادم (500)، ومن بلغه يُسمّى في الملخّص ورأس الملفّ', (t) async {
    final srv = await up();
    final got = <ReportExportRequest>[];
    ReportExportActions.debugSink = (r) async => got.add(r);
    try {
      await open(t);
      expect(srv.movementLimits.length, 70, reason: 'كلّ المدراء لا الستّون الأوائل');
      expect(srv.movementLimits.values.toSet(), {'$kManagerMovementsLimit'});
      expect(find.textContaining('بلغت $kManagerMovementsLimit'), findsOneWidget, reason: 'المدير كثير الحركات يُسمّى');
      // تصدير Excel من شريط الرأس
      await t.tap(find.byTooltip('تصدير Excel'));
      for (var i = 0; i < 4; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 100));
      }
      final r = got.single;
      expect(r.rows.length, 500 + 69, reason: 'كلّ الحركات المقروءة: 500 للأوّل + واحدة لكلّ الباقين');
      expect(r.details, contains('عدد الحركات: 569'));
      expect(r.details.any((d) => d.startsWith('ناقص:') && d.contains('بلغت $kManagerMovementsLimit')), isTrue);
      expect(t.takeException(), isNull);
    } finally {
      ReportExportActions.debugSink = null;
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      await visualTearDown();
    }
  });

  testWidgets('قراءةٌ أساسيّة تتعذّر ⇒ سببها باسمه لا ملخّصٌ بأصفار', (t) async {
    await up(failCore: true);
    try {
      await open(t);
      expect(find.textContaining('انتهت الجلسة'), findsOneWidget);
      expect(find.text('إيرادات مستحصَلة'), findsNothing);
      expect(t.takeException(), isNull);
    } finally {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      await visualTearDown();
    }
  });
}
