import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/reports_api.dart';
import 'package:rad_mysvcs/api/settlements_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/reports/v2/activations_view.dart';
import 'package:rad_mysvcs/screens/reports/v2/activity_log_view.dart';
import 'package:rad_mysvcs/screens/reports/v2/finance_view.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/screens/reports/v2/sessions_v2_screen.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_export.dart';
import 'package:rad_mysvcs/screens/settlements/settle_widgets.dart';
import 'package:rad_mysvcs/services/balance_sub_names.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'visual_perm/visual_perm_harness.dart';

// «العربي ومن ثم اليوزر» بكلّ التقارير (٢٣ نوفمبر — المالك: «في تسويه الحساب ليش يظهر اسم المشترك بالاجنبي فقط ليش مو مثل
// التقارير العربي ومن ثم اليوزر؟» ثمّ «وبالتطبيق كذلك هم لازم بجميع التقارير اسم المشترك بالعربي الاولية اله»): العنوان الاسم
// العربيّ واليوزر بعده — الماليّ والتفعيلات وسجلّ الحركات (ما لم يحمله الوصف)، و«تسوية الحساب» (subscriber_name من الخادم
// 93cd0f9)، و«الجلسات» (قائمة المشتركين المخبّأة). «تقارير الأرصدة» في balance_reports_test.

const _fsi = '\u2068';
const _pdi = '\u2069';
String _plain(String s) => s.replaceAll(_fsi, '').replaceAll(_pdi, '');
int _count(String hay, String needle) => needle.allMatches(hay).length;

ActivityRow _act(Map<String, Object?> j) => ActivityRow.fromJson(Map<String, dynamic>.from(j))!;

class _Sessions implements HttpClientAdapter {
  _Sessions(this.inner);
  final VisualServer inner;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    if (o.uri.path == '/api/v2/online-users') {
      final rows = [
        for (final (i, u) in [(0, 'ali.h@net'), (1, '193@qn651'), (2, 'nobody@net')])
          {
            'username': u,
            'user_manager': 'admin@sup',
            'ip_address': '10.0.0.$i',
            'mac': 'AA:BB:CC:00:00:0$i',
            'bytes_in': 1024 * 1024,
            'bytes_out': 1024,
            'started_at': '2026-11-23 0${8 + i}:00:00',
          },
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
  group('rpUserAfterName', () {
    test('العنوان الاسم ⇒ اليوزر معزولاً؛ العنوان اليوزر أو الوصف يحمله أو بلا يوزر ⇒ لا شيء', () {
      expect(rpUserAfterName(title: 'عباس علي', username: 'abbas.ali@popq'), '${_fsi}abbas.ali@popq$_pdi');
      expect(rpUserAfterName(title: 'abbas.ali@popq', username: 'abbas.ali@popq'), isNull);
      expect(rpUserAfterName(title: 'ABBAS.ALI@popq', username: ' abbas.ali@popq '), isNull, reason: 'بلا حساسيّة أحرف');
      expect(rpUserAfterName(title: 'عباس علي', username: 'abbas.ali@popq', detail: 'تفعيل نقدي - المستخدم: Abbas.Ali@popq | السعر'), isNull);
      expect(rpUserAfterName(title: 'عباس علي', username: '  '), isNull);
      expect(rpUserAfterName(title: 'عباس علي', username: null), isNull);
    });
  });

  group('الماليّ والتفعيلات وسجلّ الحركات: الاسم عنواناً واليوزر بعده', () {
    FinanceLog fin({String? first, String? last, String desc = 'تفعيل من الساس — بكارت', String? user = 'abbas.ali@popq'}) => FinanceLog(
          id: 1,
          actionType: 'SUBSCRIBER_ACTIVATE',
          actionDescription: desc,
          amount: 30000,
          userUsername: user,
          userFirstname: first,
          userLastname: last,
          targetName: 'abbas.ali@popq',
          actingEmployeeFullName: 'حسين مهدي',
          createdAt: '2026-11-22 10:00:00',
        );

    test('الماليّ: الوصف بلا يوزر ⇒ «الوصف · اليوزر · المنفّذ»؛ الوصف يحمله ⇒ مرّةً واحدة؛ بلا اسمٍ ⇒ اليوزر عنوانٌ وحده', () {
      final r = FinanceView.row(fin(first: 'عباس', last: 'علي'));
      expect(r.title, 'عباس علي');
      expect(_plain(r.detail), 'تفعيل من الساس — بكارت · abbas.ali@popq · حسين مهدي');
      expect(r.detail, contains('${_fsi}abbas.ali@popq$_pdi'), reason: 'معزول');
      final withUser = FinanceView.row(fin(first: 'عباس', last: 'علي', desc: 'تفعيل نقدي - المستخدم: abbas.ali@popq | السعر: 30000 د.ع'));
      expect(_count(_plain(withUser.detail), 'abbas.ali@popq'), 1, reason: 'لا تكرار');
      final noName = FinanceView.row(fin());
      expect(noName.title, 'abbas.ali@popq');
      expect(_count(_plain(noName.detail), 'abbas.ali@popq'), 0);
    });

    test('التفعيلات: «النوع · اليوزر · الباقة · المنفّذ» حين العنوان الاسم', () {
      final r = ActivationsView.row(_act({
        'id': 7,
        'action_type': 'SUBSCRIBER_ACTIVATE',
        'action_description': 'تفعيل نقدي - المستخدم: 193@qn651 | السعر: 35000 د.ع',
        'user_username': '193@qn651',
        'user_firstname': 'زينب',
        'user_lastname': 'كاظم',
        'target_name': '193@qn651',
        'acting_employee_full_name': 'موسى مهدي',
        'created_at': '2026-11-21 16:34:19',
        'action_data': {'package_name': 'Economy--2'},
      }));
      expect(r.title, 'زينب كاظم');
      expect(_plain(r.detail), 'تفعيل نقدي · 193@qn651 · Economy--2 · موسى مهدي');
      final bare = ActivationsView.row(_act({
        'id': 8,
        'action_type': 'SUBSCRIBER_ACTIVATE',
        'action_description': 'تفعيل نقدي',
        'target_name': 'aloye@popq',
        'created_at': '2026-11-21 16:34:19',
      }));
      expect(bare.title, 'aloye@popq');
      expect(_count(bare.detail, 'aloye@popq'), 0, reason: 'بلا اسمٍ لا يتكرّر اليوزر');
    });

    test('سجلّ الحركات: التعديل «من … إلى …» ثمّ اليوزر', () {
      final r = ActivityLogView.row(_act({
        'id': 9,
        'action_type': 'SUBSCRIBER_EDIT',
        'action_description': 'تعديل المشترك',
        'user_username': 'must.mha@popq',
        'user_firstname': 'مصطفى',
        'target_name': 'must.mha@popq',
        'created_at': '2026-11-22 12:00:00',
        'action_data': {
          'diff': {
            'phone': {'from': '07700000000', 'to': '07800000000'},
          },
        },
      }));
      expect(r.title, 'مصطفى');
      expect(_plain(r.detail), contains('must.mha@popq'));
      expect(_plain(r.detail).indexOf('must.mha@popq'), greaterThan(0), reason: 'بعد وصف التعديل');
    });
  });

  group('تسوية الحساب', () {
    setUpAll(visualSetUpAll);

    BoxMovement move(Map<String, Object?> extra) => BoxMovement.fromJson({
          'source': 'activity',
          'id': 901,
          'kind': 'cash_activation',
          'direction': 'in',
          'amount': 35000,
          'created_at': '2026-11-22T14:46:51.000Z',
          'subscriber': 'abbas.ali@popq',
          'package_name': 'Light--1',
          'employee_id': 4,
          'employee_username': 'hussein',
          'employee_name': 'حسين مهدي',
          ...extra,
        })!;

    test('subscriber_name يُقرأ من الخادم، وغيابه null', () {
      expect(move({'subscriber_name': 'عباس علي'}).subscriberName, 'عباس علي');
      expect(move({}).subscriberName, isNull);
    });

    testWidgets('السطر: الاسم عنواناً و«النوع · اليوزر · الباقة · المنفّذ»؛ بلا اسمٍ اليوزر عنوانٌ كما كان؛ الموظّف لا يُمسّ', (t) async {
      await visualSetUp(s1bSasOwner);
      try {
        final named = move({'subscriber_name': 'عباس علي'});
        final bare = move({'id': 902, 'subscriber': 'aloye@popq'});
        final emp = BoxMovement.fromJson({
          'source': 'employee',
          'id': 11,
          'kind': 'emp_advance',
          'direction': 'out',
          'amount': 100000,
          'created_at': '2026-11-22T10:00:00.000Z',
          'subscriber': 'abbas.ali@popq',
          'subscriber_name': 'عباس علي',
          'description': 'سلفة: أحمد — عيد',
          'employee_id': null,
        })!;
        await pumpVisual(t, const VisualDevice('', Size(320, 900), 2),
            home: (_) => Scaffold(
                  body: Column(children: [
                    MovementTile(key: const ValueKey('n'), m: named, grouped: true),
                    MovementTile(key: const ValueKey('b'), m: bare, grouped: true),
                    MovementTile(key: const ValueKey('e'), m: emp, grouped: true),
                  ]),
                ));
        await t.pump(const Duration(milliseconds: 300));
        Iterable<String> texts(String key) => t
            .widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
            .map((w) => _plain(w.data ?? w.textSpan?.toPlainText() ?? ''));
        expect(texts('n').first, 'عباس علي', reason: 'العنوان الاسم العربيّ');
        expect(texts('n'), contains('تفعيل نقديّ · abbas.ali@popq · Light--1 · حسين مهدي'));
        expect(texts('b').first, 'aloye@popq', reason: 'بلا اسمٍ: اليوزر عنوان');
        expect(texts('b').where((s) => s.contains('aloye@popq')).length, 1, reason: 'لا يتكرّر في التفاصيل');
        expect(texts('e').first, 'أحمد — عيد', reason: 'حركة الموظّف بعنوانها');
        expect(texts('e').any((s) => s.contains('عباس علي')), isFalse);
        expect(texts('e').any((s) => s.contains('abbas.ali@popq')), isFalse, reason: 'حركة الموظّف بلا يوزر مشترك ولو أُرسل');
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        await visualTearDown();
      }
    });
  });

  group('الجلسات: الاسم العربيّ من قائمة المشتركين المخبّأة', () {
    setUpAll(visualSetUpAll);
    tearDown(BalanceSubNames.debugReset);

    Future<void> open(WidgetTester t) async {
      await pumpVisual(t, const VisualDevice('', Size(430, 2400), 2), home: (_) => const SessionsV2Screen());
      for (var i = 0; i < 12; i++) {
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

    final subs = [
      Subscriber.fromJson({'username': 'ALI.H@net', 'firstname': 'علي', 'lastname': 'حسين'}),
      Subscriber.fromJson({'username': '193@qn651', 'firstname': 'زينب', 'lastname': 'كاظم'}),
    ];

    testWidgets('العنوان الاسم واليوزر بسطره تحته ثمّ سطر الشبكة، والمجهول باليوزر؛ والملفّ بعمود «الاسم»', (t) async {
      ApiClient.dio.httpClientAdapter = _Sessions(await visualSetUp(s1bSasOwner));
      var loads = 0;
      BalanceSubNames.probe = () async => 0;
      BalanceSubNames.loadAll = () async {
        loads++;
        return subs;
      };
      final got = <ReportExportRequest>[];
      ReportExportActions.debugSink = (r) async => got.add(r);
      try {
        await open(t);
        expect(find.text('علي حسين'), findsOneWidget);
        expect(find.text('زينب كاظم'), findsOneWidget);
        expect(find.text('nobody@net'), findsOneWidget, reason: 'ليس بالقائمة ⇒ اليوزر عنوان');
        final details = t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').where((s) => s.contains('10.0.0.')).toList();
        expect(details, contains('${_fsi}ali.h@net$_pdi\n10.0.0.0 · AA:BB:CC:00:00:00 · admin@sup'), reason: 'اليوزر بسطره ثمّ سطر الشبكة');
        expect(details, contains('${_fsi}193@qn651$_pdi\n10.0.0.1 · AA:BB:CC:00:00:01 · admin@sup'));
        expect(details, contains('10.0.0.2 · AA:BB:CC:00:00:02 · admin@sup'), reason: 'بلا اسمٍ لا يتكرّر اليوزر');
        expect(loads, 1);
        await t.scrollUntilVisible(find.text('Excel'), 500, scrollable: find.byType(Scrollable).first);
        await t.tap(find.text('Excel'));
        await t.pump(const Duration(milliseconds: 200));
        final ex = got.single;
        final ni = ex.columns.indexOf('الاسم');
        expect(ni, greaterThanOrEqualTo(0));
        expect(ex.columns[ni + 1], 'اليوزر', reason: 'الاسم ثمّ اليوزر');
        final byUser = {for (final r in ex.rows) r[ni + 1].toString(): r[ni].toString()};
        expect(byUser['ali.h@net'], 'علي حسين');
        expect(byUser['193@qn651'], 'زينب كاظم');
        expect(byUser['nobody@net'], '');
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });

    testWidgets('موظّفٌ بلا «عرض المشتركين»: لا طلب لقائمتهم واليوزر عنوانٌ كما كان', (t) async {
      ApiClient.dio.httpClientAdapter = _Sessions(await visualSetUp(s1bSasOwner));
      var calls = 0;
      BalanceSubNames.probe = () async {
        calls++;
        return 0;
      };
      BalanceSubNames.loadAll = () async {
        calls++;
        return subs;
      };
      PermissionsService.debugSet(isEmployee: true, permissions: const {'reports.sessions': true});
      try {
        await open(t);
        expect(find.text('ali.h@net'), findsOneWidget);
        expect(find.text('علي حسين'), findsNothing);
        expect(calls, 0);
      } finally {
        await down(t);
      }
    });
  });
}
