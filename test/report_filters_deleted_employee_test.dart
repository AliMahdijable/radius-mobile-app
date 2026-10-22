import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_filters.dart';

import 'visual_perm/visual_perm_harness.dart';

/// فلتر الموظّف بالتقارير (٢٣ أكتوبر، بعد بلاغ admin@cash2): حذف الموظّف يمسح صفّه وحركاته تبقى باسمه، فكان يختفي من
/// القائمة وحركاته بلا طريق. الآن الفلتر يطلب `?with_deleted=1` والمحذوف يظهر «الاسم (محذوف)»، وحين يُختار موظّف يظهر
/// سطر «يعرض ما نفّذه الموظّف وهو داخل بحسابه فقط». شاشة الموظّفين بلا العلم كما كانت. الخادم وهميّ.
const _note = 'يعرض ما نفّذه الموظّف وهو داخل بحسابه فقط — ما انعمل بحساب المدير يظهر باسم المدير.';

class _EmpServer implements HttpClientAdapter {
  _EmpServer(this.inner);
  final HttpClientAdapter inner;
  final employeeQueries = <Map<String, dynamic>>[];

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    if (o.method == 'GET' && o.path == '/api/v2/employees') {
      employeeQueries.add(Map<String, dynamic>.from(o.queryParameters));
      final withDeleted = '${o.queryParameters['with_deleted']}' == '1';
      return Future.value(_json(200, {
        'success': true,
        'data': [
          {'id': 7, 'username': 'ali.h', 'full_name': 'علي حسين', 'is_active': true, 'permissions': {}},
          if (withDeleted)
            {
              'id': 96,
              'username': 'suliman',
              'full_name': null,
              'is_active': false,
              'permissions': {},
              'deleted': true
            },
        ],
      }));
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

void main() {
  setUpAll(visualSetUpAll);

  test('Employee.fromJson: deleted من الخادم وحده، وغيابه = حاليّ', () {
    final live = Employee.fromJson({'id': 7, 'username': 'ali.h', 'is_active': true, 'permissions': {}})!;
    final gone =
        Employee.fromJson({'id': 96, 'username': 'suliman', 'is_active': false, 'permissions': {}, 'deleted': true})!;
    final odd = Employee.fromJson({'id': 5, 'username': 'x', 'deleted': 'true'})!;
    expect(live.deleted, isFalse);
    expect(gone.deleted, isTrue);
    expect(odd.deleted, isFalse, reason: 'true المنطقيّة وحدها — لا نصّ');
  });

  group('مع الخادم الوهميّ', () {
    tearDown(visualTearDown);

    testWidgets('EmployeesApi.list: العلم مع withDeleted وحده', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      final server = _EmpServer(inner);
      ApiClient.dio.httpClientAdapter = server;
      final plain = await t.runAsync(() => EmployeesApi.list());
      final withDeleted = await t.runAsync(() => EmployeesApi.list(withDeleted: true));
      expect(server.employeeQueries, [
        <String, dynamic>{},
        {'with_deleted': 1}
      ]);
      expect(plain!.rows.map((e) => e.id), [7]);
      expect(withDeleted!.rows.map((e) => '${e.id}:${e.deleted}'), ['7:false', '96:true']);
    });

    testWidgets('فلتر التقارير: المحذوف «(محذوف)» + سطر التوضيح حين يُختار موظّف', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      final server = _EmpServer(inner);
      ApiClient.dio.httpClientAdapter = server;
      var value = const ReportFilters();
      await pumpVisual(
        t,
        phone,
        home: (_) => Scaffold(
          body: SafeArea(
            // كالشاشات الحقيقيّة: اللوحة داخل قائمةٍ تمرّر (ارتفاعها بمحتواها).
            child: StatefulBuilder(
              builder: (ctx, setState) => ListView(
                padding: const EdgeInsets.all(12),
                children: [ReportFiltersPanel(value: value, onChanged: (v) => setState(() => value = v))],
              ),
            ),
          ),
        ),
      );
      await settle(t, seconds: 2);
      expect(server.employeeQueries, [
        {'with_deleted': 1}
      ]);
      expect(find.text(_note), findsNothing, reason: 'لا سطر بلا موظّفٍ مختار');

      await t.tap(find.text('الموظف'));
      await settle(t, seconds: 1);
      expect(find.text('علي حسين'), findsOneWidget);
      expect(find.text('suliman (محذوف)'), findsOneWidget);

      await t.tap(find.text('suliman (محذوف)'));
      await settle(t, seconds: 1);
      expect(value.employeeId, 96);
      expect(find.text('suliman (محذوف)'), findsOneWidget, reason: 'اسم الحقل بعد الاختيار');
      expect(find.text(_note), findsOneWidget);
      await shoot(t, s1bSasOwner, 'report_filters_deleted_employee', phone, inner);

      await t.tap(find.text('مسح'));
      await settle(t, seconds: 1);
      expect(value.employeeId, isNull);
      expect(find.text(_note), findsNothing);
    });
  });
}
