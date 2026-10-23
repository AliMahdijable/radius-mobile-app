import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/expenses_api.dart';
import 'package:rad_mysvcs/api/recurring_expenses_api.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/screens/expenses/expenses_screen.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «الصرفيات الثابتة» بالتطبيق (٢٣ أكتوبر ٢٠٢٦) — الخادم server/recurringExpenses.js والويب pages/reports/RecurringExpenses.tsx.
///   • النموذج والتواريخ (آخر الشهر، الإضافة بالأشهر) ووسم الصرفيّة المولَّدة.
///   • الحمولة: الإنشاء بمرجعه، التأكيد بمبلغه، «دفعتها الآن»، التخطّي، والتعديل.
///   • الشاشة: القسم حين يفتحه الخادم (أو له قوالب)، المعلَّقة تُؤكَّد، الإنشاء بالطريقة إجباريّة، وشارة «ثابتة».
class _RecServer implements HttpClientAdapter {
  _RecServer(this.inner);
  final HttpClientAdapter inner;
  bool enabled = true;
  bool empty = false;
  final posts = <(String, String, Map<String, dynamic>)>[];

  static Map<String, dynamic> run(int id, int tid, String period, String due, String status, {String? how, num amount = 75000, String? name}) => {
        'id': id, 'template_id': tid, 'name': name, 'period': period, 'due_date': due, 'status': status, 'how': how,
        'amount': amount, 'expense_id': status == 'created' ? 700 + id : null,
      };

  static Map<String, dynamic> tpl(int id, String name, num amount, int day, String mode, String status,
          {int every = 1, String? end, Map<String, dynamic>? last, String next = '2026-11'}) =>
      {
        'id': id, 'name': name, 'amount': amount, 'day': day, 'every': every, 'start_period': '2026-10', 'end_period': end,
        'mode': mode, 'note': null, 'status': status,
        'next_due': {'period': next, 'due_date': '$next-${day.clamp(1, 30).toString().padLeft(2, '0')}'},
        'last': last, 'runs_count': 1, 'created_by': 'admin@x',
      };

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final m = o.method.toUpperCase();
    if (o.path == '/api/admin/expenses' && m == 'GET') {
      return _json(200, {
        'success': true,
        'total': 265000,
        'expenses': [
          {'id': 741, 'amount': '250000.00', 'note': 'إيجار المحل (ثابتة 2026-10)', 'expense_date': '2026-10-01T00:00:00.000Z',
            'recurring': {'template_id': 1, 'name': 'إيجار المحل', 'period': '2026-10', 'how': 'auto'}},
          {'id': 735, 'amount': '15000.00', 'note': 'قرطاسية', 'expense_date': '2026-10-12T00:00:00.000Z'},
        ],
      });
    }
    if (o.path == '/api/v2/expenses/recurring' && m == 'GET') {
      if (empty) return _json(200, {'success': true, 'enabled': enabled, 'today': '2026-10-23', 'data': const [], 'pending': const []});
      return _json(200, {
        'success': true,
        'enabled': enabled,
        'today': '2026-10-23',
        'data': [
          tpl(1, 'إيجار المحل', 250000, 1, 'auto', 'active', last: run(11, 1, '2026-10', '2026-10-01', 'created', how: 'auto', amount: 250000)),
          tpl(2, 'المولّدة', 75000, 31, 'confirm', 'active', last: run(12, 2, '2026-10', '2026-10-31', 'pending')),
          tpl(3, 'قسط المولّد', 300000, 15, 'auto', 'paused', every: 3, end: '2027-07'),
        ],
        'pending': [run(12, 2, '2026-10', '2026-10-31', 'pending', name: 'المولّدة')],
      });
    }
    if (o.path.startsWith('/api/v2/expenses/recurring') && m != 'GET') {
      final body = Map<String, dynamic>.from((o.data as Map?) ?? const {});
      posts.add((m, o.path, body));
      if (o.path == '/api/v2/expenses/recurring') {
        return _json(200, {
          'success': true,
          'template': tpl(9, body['name'] as String, body['amount'] as num, body['day'] as int, body['mode'] as String, 'active'),
          'generated': [run(91, 9, '2026-10', '2026-10-01', 'created', how: 'auto', amount: body['amount'] as num)],
          'pending': const [],
        });
      }
      if (o.path.endsWith('/confirm')) {
        return _json(200, {'success': true, 'run': run(12, 2, '2026-10', '2026-10-31', 'created', how: 'confirm', amount: body['amount'] as num), 'pending': const []});
      }
      if (o.path.endsWith('/now')) {
        return _json(200, {'success': true, 'run': run(13, 1, '2026-11', '2026-11-01', 'created', how: 'now', amount: body['amount'] as num)});
      }
      if (o.path.endsWith('/skip')) return _json(200, {'success': true, 'run': run(12, 2, '2026-10', '2026-10-31', 'skipped', how: 'skip'), 'pending': const []});
      if (o.path.endsWith('/pause') || o.path.endsWith('/resume') || m == 'PUT' || m == 'DELETE') {
        return _json(200, {'success': true, 'pending': const []});
      }
      return _json(409, {'success': false, 'code': 'RECURRING_OFF', 'message': '«الصرفيات الثابتة» غير مفعّلة لحسابك بعد'});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

void main() {
  setUpAll(visualSetUpAll);

  group('النموذج', () {
    test('القالب والاستحقاق والوسم: الحقول، القادمة، آخرها، والصرفيّة المولَّدة', () {
      final t = RecurringTemplate.fromJson(_RecServer.tpl(2, 'المولّدة', 75000, 31, 'confirm', 'active',
          last: _RecServer.run(12, 2, '2026-10', '2026-10-31', 'pending')))!;
      expect((t.id, t.amount, t.day, t.every, t.isAuto, t.isActive, t.nextPeriod, t.last!.isPending),
          (2, 75000, 31, 1, false, true, '2026-11', true));
      expect(RecurringTemplate.fromJson(const {'name': 'x'}), isNull, reason: 'بلا معرّف');
      final r = RecurringRun.fromJson(_RecServer.run(11, 1, '2026-10', '2026-10-01', 'created', how: 'auto'))!;
      expect((r.period, r.dueDate, r.how, r.expenseId), ('2026-10', '2026-10-01', 'auto', 711));
      final e = ExpenseRow.fromJson(const {
        'id': 741, 'amount': '250000.00', 'expense_date': '2026-10-01T00:00:00.000Z',
        'recurring': {'template_id': 1, 'name': 'إيجار المحل', 'period': '2026-10'},
      })!;
      expect((e.isRecurring, e.recurringName, e.recurringPeriod), (true, 'إيجار المحل', '2026-10'));
      expect(ExpenseRow.fromJson(const {'id': 5, 'amount': 1, 'expense_date': '2026-10-01'})!.isRecurring, isFalse);
    });

    test('التواريخ كالخادم: آخر الشهر يُقصّ (٣١ ⇒ ٣٠/٢٨/٢٩) والإضافة بالأشهر عبر السنة', () {
      expect(recurringDueDate('2026-04', 31), '2026-04-30');
      expect(recurringDueDate('2027-02', 31), '2027-02-28');
      expect(recurringDueDate('2028-02', 30), '2028-02-29');
      expect(recurringDueDate('2026-10', 5), '2026-10-05');
      expect(recurringAddMonths('2026-11', 3), '2027-02');
      expect(recurringAddMonths('2026-12', 12), '2027-12');
      final p = RecurringPage(enabled: false, today: '2026-10-23', templates: const [], pending: const []);
      expect(p.visible, isFalse, reason: 'مطفأ وبلا قوالب ⇒ لا قسم');
    });
  });

  group('الحمولة', () {
    tearDown(visualTearDown);

    testWidgets('الإنشاء بمرجعه، والتأكيد بمبلغه، و«الآن» والتخطّي والتعديل بمساراتها', (t) async {
      final server = _RecServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      var w = (await t.runAsync(() => RecurringExpensesApi.create(
            name: 'إيجار', amount: 250000, day: 1, every: 1, startPeriod: '2026-10', mode: 'auto', note: 'الطابق ٢', clientRef: 'ref0000000001')))!;
      expect((w.ok, w.generated.single.period), (true, '2026-10'));
      expect(server.posts.last.$3, {
        'name': 'إيجار', 'amount': 250000, 'day': 1, 'every': 1, 'start_period': '2026-10', 'end_period': null, 'mode': 'auto',
        'note': 'الطابق ٢', 'client_ref': 'ref0000000001',
      });
      w = (await t.runAsync(() => RecurringExpensesApi.confirm(12, amount: 80000, note: 'زادت')))!;
      expect((w.ok, w.run!.how, server.posts.last.$2), (true, 'confirm', '/api/v2/expenses/recurring/runs/12/confirm'));
      expect(server.posts.last.$3, {'amount': 80000, 'note': 'زادت'});
      w = (await t.runAsync(() => RecurringExpensesApi.payNow(1, amount: 45000)))!;
      expect(w.run!.how, 'now');
      expect(server.posts.last.$3, {'amount': 45000});
      await t.runAsync(() => RecurringExpensesApi.skip(12));
      expect(server.posts.last.$2, '/api/v2/expenses/recurring/runs/12/skip');
      await t.runAsync(() => RecurringExpensesApi.update(1, {'amount': 275000, 'day': 20}));
      expect((server.posts.last.$1, server.posts.last.$2), ('PUT', '/api/v2/expenses/recurring/1'));
      expect(server.posts.last.$3, {'amount': 275000, 'day': 20});
      await t.runAsync(() => RecurringExpensesApi.pause(1));
      await t.runAsync(() => RecurringExpensesApi.delete(1));
      expect(server.posts.map((p) => '${p.$1} ${p.$2}').skip(5), ['POST /api/v2/expenses/recurring/1/pause', 'DELETE /api/v2/expenses/recurring/1']);
    });
  });

  group('الشاشة', () {
    tearDown(visualTearDown);

    testWidgets('القسم: المعلَّقة «أضفها» تُرسل التأكيد بمبلغها، والقوالب بجدولها وحالتها، وشارة «ثابتة» بالقائمة', (t) async {
      final server = _RecServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phoneTall, home: (_) => const ExpensesScreen());
      await settle(t, seconds: 2);
      expect(t.takeException(), isNull);
      expect(find.text('الصرفيات الثابتة'), findsOneWidget);
      expect(find.text('بانتظار تأكيدك (1)'), findsOneWidget);
      expect(find.text('موقوفة'), findsOneWidget);
      expect(find.textContaining('كلّ ٣ أشهر · يوم 15 · حتى تمّوز 2027'), findsOneWidget);
      expect(find.textContaining('القادمة 1 تشرين الثاني 2026'), findsOneWidget);
      expect(find.text('ثابتة'), findsOneWidget, reason: 'شارة الصرفيّة المولَّدة وحدها');
      await t.tap(find.text('أضفها'));
      await settle(t, seconds: 1);
      expect(find.textContaining('تُكتب بتاريخ استحقاقها 31 تشرين الأوّل 2026'), findsOneWidget);
      await t.tap(find.textContaining('أضفها صرفيّة'));
      await settle(t, seconds: 4);
      final post = server.posts.lastWhere((p) => p.$2.endsWith('/confirm'));
      expect((post.$2, post.$3['amount']), ('/api/v2/expenses/recurring/runs/12/confirm', 75000));
      expect(t.takeException(), isNull);
    });

    testWidgets('إنشاء قالب: الطريقة إجباريّة، ثمّ «تلقائيّاً» يُرسل هذا الشهر والمرجع', (t) async {
      final server = _RecServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phoneTall, home: (_) => const ExpensesScreen());
      await settle(t, seconds: 2);
      await t.tap(find.text('ثابتة جديدة'));
      await settle(t, seconds: 1);
      final fields = find.descendant(of: find.byType(DesignSheet), matching: find.byType(TextField));
      await t.enterText(fields.at(0), 'إيجار المخزن');
      await t.enterText(fields.at(1), '120000');
      await settle(t);
      expect(find.text('اختر: تلقائيّاً أو بتأكيد'), findsOneWidget);
      await t.tap(find.text('اختر: تلقائيّاً أو بتأكيد'));
      await settle(t);
      expect(server.posts.where((p) => p.$2 == '/api/v2/expenses/recurring'), isEmpty, reason: 'بلا طريقة لا يُرسل');
      expect(find.textContaining('أوّل صرفيّة: 1 تشرين الأوّل 2026'), findsOneWidget);
      await t.ensureVisible(find.text('تلقائيّاً يوم الاستحقاق'));
      await t.tap(find.text('تلقائيّاً يوم الاستحقاق'));
      await settle(t);
      expect(find.textContaining('يومها مرّ: تُضاف الآن'), findsOneWidget);
      await t.tap(find.text('حفظ'));
      await settle(t, seconds: 4);
      final post = server.posts.lastWhere((p) => p.$2 == '/api/v2/expenses/recurring');
      expect((post.$3['name'], post.$3['amount'], post.$3['day'], post.$3['every'], post.$3['start_period'], post.$3['mode']),
          ('إيجار المخزن', 120000, 1, 1, '2026-10', 'auto'));
      expect((post.$3['client_ref'] as String).length, 24);
      expect(t.takeException(), isNull);
    });

    testWidgets('مطفأ وبلا قوالب ⇒ لا قسم (الشاشة كما كانت)', (t) async {
      final server = _RecServer(await visualSetUp(s1bSasOwner))
        ..enabled = false
        ..empty = true;
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phone, home: (_) => const ExpensesScreen());
      await settle(t, seconds: 2);
      expect(find.text('الصرفيات الثابتة'), findsNothing);
      expect(find.text('قرطاسية'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('مطفأ وله قوالب ⇒ القسم للعرض: «ثابتة جديدة» معطّلة وملاحظة الإيقاف', (t) async {
      final server = _RecServer(await visualSetUp(s1bSasOwner))..enabled = false;
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phoneTall, home: (_) => const ExpensesScreen());
      await settle(t, seconds: 2);
      expect(find.textContaining('موقوفة لحسابك الآن'), findsOneWidget);
      final btn = t.widget<FilledButton>(find.ancestor(of: find.text('ثابتة جديدة'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
      expect(btn.onPressed, isNull);
      expect(t.takeException(), isNull);
    });
  });
}
