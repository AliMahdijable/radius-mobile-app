// «المنطقة / FDT / FAT» في «تصفية القائمة» لساسات الوطني (١٩ نوفمبر — البصرة/الناصريّة؛ كالموقع): الشاشة الحقيقيّة أمام خادمٍ وهميّ.
// الصفوف تحمل ftth_zone/fdt/fat ⇒ الورقة تعرض الأقسام الثلاثة متسلسلةً بأعدادها، والاختيار يصفّي القائمة والعدّادات؛ شركةٌ بلا الحقول
// ⇒ لا أقسام ولا أثر.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/services/known_slow_list.dart';

import 'visual_perm/visual_perm_harness.dart';

Map<String, Object?> _row(int i, String? zone, String? fdt, String? fat) => {
      'idx': 700 + i,
      'username': 'sub$i.z',
      'firstname': 'مشترك$i',
      'lastname': 'تجربة',
      'profile_name': 'FIBER 35',
      'profile_id': 9,
      'remaining_days': 10,
      'expiration': '2026-12-01 00:00:00',
      'enabled': 1,
      'notes': '',
      'debt': 0,
      'hasDebt': false,
      'package_price': 35000,
      if (zone != null) 'ftth_zone': zone,
      if (fdt != null) 'ftth_fdt': fdt,
      if (fat != null) 'ftth_fat': fat,
    };

final _fiberRows = [
  _row(1, 'BSR-1', 'FDT-1', 'FAT-1'),
  _row(2, 'BSR-1', 'FDT-1', 'FAT-2'),
  _row(3, 'BSR-1', 'FDT-2', 'FAT-3'),
  _row(4, 'BSR-2', 'FDT-7', 'FAT-9'),
  _row(5, 'BSR-10', 'FDT-20', 'FAT-30'),
];
final _plainRows = [_row(1, null, null, null), _row(2, null, null, null)];

class _Sas implements HttpClientAdapter {
  _Sas(this.inner, this.rows);
  final HttpClientAdapter inner;
  final List<Map<String, Object?>> rows;

  static ResponseBody _json(Object body) => ResponseBody.fromString(jsonEncode(body), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    if (o.method.toUpperCase() == 'GET' && o.uri.path == '/api/v2/subscribers') {
      final q = o.uri.queryParameters;
      if (q.containsKey('page')) {
        return _json({'success': true, 'paged': true, 'data': rows.take(1).toList(), 'total': rows.length, 'last_page': rows.length});
      }
      return _json({'success': true, 'data': rows});
    }
    return inner.fetch(o, s, c);
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _setUp(List<Map<String, Object?>> rows) async {
  final srv = _Sas(await visualSetUp(s1bSasOwner), rows);
  KnownSlowList.adminId = () async => 'supernet:12';
  KnownSlowList.now = DateTime.now;
  ApiClient.dio.httpClientAdapter = srv;
  SubscribersApi.clearAllCaches();
  BigSubscribersApi.reset();
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _openSheet(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.tune_rounded).first);
  await _settle(t);
}

Future<void> _chip(WidgetTester t, String label) async {
  final f = find.text(label);
  await t.ensureVisible(f.last);
  await t.pump();
  await t.tap(f.last);
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(visualSetUpAll);

  testWidgets('الورقة: المنطقة ثمّ FDT ثمّ FAT متسلسلةً — والاختيار يصفّي القائمة', (t) async {
    await _setUp(_fiberRows);
    final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
    await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
    await _settle(t);
    expect(find.textContaining('sub5.z'), findsWidgets, reason: 'القائمة الكاملة ظاهرة');

    await _openSheet(t);
    expect(find.text('المنطقة'), findsOneWidget);
    expect(find.text('BSR-1 (3)'), findsOneWidget);
    expect(find.text('BSR-2 (1)'), findsOneWidget);
    expect(find.text('BSR-10 (1)'), findsOneWidget);
    // قبل اختيار منطقة: كلّ FDT
    expect(find.text('FDT-20 (1)'), findsOneWidget);

    await _chip(t, 'BSR-1 (3)');
    expect(find.text('FDT-1 (2)'), findsOneWidget);
    expect(find.text('FDT-2 (1)'), findsOneWidget);
    expect(find.text('FDT-20 (1)'), findsNothing, reason: 'FDT مقيَّدةٌ بالمنطقة');
    await _chip(t, 'FDT-1 (2)');
    expect(find.text('FAT-1 (1)'), findsOneWidget);
    expect(find.text('FAT-3 (1)'), findsNothing, reason: 'FAT مقيَّدةٌ بالـFDT');

    await t.tap(find.text('تطبيق'));
    await _settle(t);
    expect(find.textContaining('sub1.z'), findsWidgets);
    expect(find.textContaining('sub2.z'), findsWidgets);
    expect(find.textContaining('sub3.z'), findsNothing);
    expect(find.textContaining('sub5.z'), findsNothing);

    // تغيير المنطقة يمسح ما تحتها
    await _openSheet(t);
    await _chip(t, 'BSR-10 (1)');
    await t.tap(find.text('تطبيق'));
    await _settle(t);
    expect(find.textContaining('sub5.z'), findsWidgets);
    expect(find.textContaining('sub1.z'), findsNothing);

    // «إعادة تعيين» تمسح الكلّ
    await _openSheet(t);
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ResetFilterButton'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('تطبيق'));
    await _settle(t);
    expect(find.textContaining('sub1.z'), findsWidgets);
    expect(find.textContaining('sub5.z'), findsWidgets);
    expect(t.takeException(), isNull);

    await t.pumpWidget(const SizedBox());
    await _settle(t);
  });

  testWidgets('شركةٌ بلا حقول الوطني: لا أقسام في الورقة', (t) async {
    await _setUp(_plainRows);
    final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
    await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
    await _settle(t);
    expect(find.textContaining('sub1.z'), findsWidgets);
    if (find.byIcon(Icons.tune_rounded).evaluate().isNotEmpty) {
      await _openSheet(t);
      expect(find.text('المنطقة'), findsNothing);
      expect(find.text('FDT'), findsNothing);
    }
    await t.pumpWidget(const SizedBox());
    await _settle(t);
  });
}
