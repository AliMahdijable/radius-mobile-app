import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/deleted_debts_api.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/screens/reports/deleted_debts_screen.dart';
import 'package:rad_mysvcs/screens/reports/reports_hub_screen.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «ديون المشتركين المحذوفين» بالتطبيق (٢٣ أكتوبر) — الخادم 5ab928a والويب b412016.
///   • القائمة: العدد والمجموع، ومصدر كلّ صفّ («حذفته الشركة» · «يدويّ» · «من ملف»)، والبحث بالهاتف.
///   • مطفأةٌ للحساب ⇒ «غير مفعّلة»، وبطاقة التقارير لا تظهر؛ مفعّلة ⇒ البطاقة بعددها ومجموعها.
///   • التسديد «الكل» يرسل payAll (الخادم يسدّد رصيده المحفوظ)، والإضافة المكرّرة تُسأل ثمّ تُعاد بـconfirmRepeat.
///   • الموظّف: ما لا يملكه يبقى بمكانه مقفلاً؛ وأدوار ايرث لنك تُطابَق على ما يعرضه الكتالوج وحده.
class _DdServer implements HttpClientAdapter {
  _DdServer(this.inner);
  final HttpClientAdapter inner;

  bool enabled = true;

  /// القائمة تفشل (409 بلا بيانات) — عطلٌ عابر.
  bool failList = false;
  List<Map<String, dynamic>> rows = [
    {
      'key': 'a41',
      'origin': 'auto',
      'name': 'حسين علي',
      'username': 'hussein.a',
      'phone': '9647701234567',
      'manager_username': 'agent1',
      'debt': 35000,
      'at': '2026-10-22T09:00:00Z',
      'note': null,
    },
    {
      'key': 'm7',
      'origin': 'manual',
      'name': 'كرار جاسم',
      'username': null,
      'phone': null,
      'manager_username': null,
      'debt': 25000,
      'at': '2026-10-21T12:00:00Z',
      'note': 'باقة 35 — شهر 9',
    },
    {
      'key': 'm9',
      'origin': 'import',
      'name': 'زينب حسن',
      'username': 'zainab.h',
      'phone': '9647809876543',
      'manager_username': null,
      'debt': 15000,
      'at': '2026-10-20T08:00:00Z',
      'note': null,
    },
  ];

  /// الردّ القادم لإضافة: (status, body) — null ⇒ نجاح.
  (int, Map<String, dynamic>)? nextAdd;
  final posts = <(String, Map<String, dynamic>)>[];
  int gets = 0;

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final get = o.method.toUpperCase() == 'GET';
    if (o.path == '/api/v2/deleted-debts' && get) {
      gets += 1;
      if (failList) {
        return _json(409, {'success': false, 'code': 'DELETED_DEBTS_UNAVAILABLE', 'message': 'تعذّرت قراءة ديون المحذوفين — حاول بعد قليل'});
      }
      if (!enabled) {
        return _json(200, {'success': true, 'enabled': false, 'data': const [], 'totals': {'count': 0, 'debt': 0}});
      }
      final total = rows.fold<num>(0, (s, r) => s + (r['debt'] as num));
      return _json(200, {
        'success': true,
        'enabled': true,
        'data': rows,
        'totals': {'count': rows.length, 'debt': total},
      });
    }
    if (o.path.startsWith('/api/v2/deleted-debts') && !get) {
      final body = Map<String, dynamic>.from((o.data as Map?) ?? const {});
      posts.add((o.path, body));
      if (o.path == '/api/v2/deleted-debts') {
        final r = nextAdd;
        nextAdd = null;
        if (r != null) return _json(r.$1, r.$2);
        return _json(200, {'success': true, 'data': {'key': 'm99', 'debt': body['amount']}});
      }
      final m = RegExp(r'^/api/v2/deleted-debts/([am]\d+)/(pay|write-off)$').firstMatch(o.path);
      final row = rows.firstWhere((r) => r['key'] == m?.group(1), orElse: () => const {});
      if (m == null || row.isEmpty) return _json(404, {'success': false, 'message': 'الدين غير موجود أو ليس من ديونك'});
      final debt = (row['debt'] as num).toInt();
      if (m.group(2) == 'write-off') {
        rows = rows.where((r) => r['key'] != row['key']).toList();
        return _json(200, {'success': true, 'data': {'key': row['key'], 'written_off': debt}});
      }
      final paid = body['payAll'] == true ? debt : (body['amount'] as num).toInt();
      final left = debt - paid;
      rows = [
        for (final r in rows)
          if (r['key'] != row['key']) r else if (left > 0) {...r, 'debt': left},
      ];
      return _json(200, {
        'success': true,
        'data': {'key': row['key'], 'amount_paid': paid, 'previous_balance': -debt, 'new_balance': -left, 'remaining_debt': left},
      });
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

/// موظّف ايرث لنك يرى ديون المحذوفين ولا يملك غيرها.
const _elViewer = Scenario(
  id: 'DD_el_viewer',
  title: 'موظّف ايرث لنك — deleted_debts.view وحدها',
  actor: Actor.elEmployee,
  provider: 'earthlink',
  keys: {'deleted_debts.view': true},
);

void main() {
  setUpAll(visualSetUpAll);

  group('النموذج والـAPI', () {
    test('fromJson: المفتاح والدين شرطان، والمصدر المجهول يدويّ، والهاتف محلّيّ', () {
      final a = DeletedDebt.fromJson({'key': 'a41', 'origin': 'auto', 'name': 'حسين', 'debt': '35000', 'phone': '9647701234567'})!;
      expect(a.isAuto, isTrue);
      expect(a.debt, 35000);
      expect(a.localPhone, '07701234567');
      expect(DeletedDebt.fromJson({'key': 'x1', 'debt': 1000}), isNull, reason: 'مفتاحٌ غير m/a');
      expect(DeletedDebt.fromJson({'key': 'm1', 'debt': 0}), isNull, reason: 'بلا دين');
      final m = DeletedDebt.fromJson({'key': 'm1', 'origin': '??', 'username': 'u1', 'debt': 250})!;
      expect(m.origin, 'manual');
      expect(m.name, 'u1', reason: 'بلا اسم ⇒ اليوزر');
      expect(m.localPhone, isNull);
    });

    testWidgets('list/add/pay: ردود 4xx تصل ردّاً عاديّاً فيُقرأ رمزها ورسالتها', (t) async {
      final server = _DdServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      addTearDown(visualTearDown);

      final l = await t.runAsync(DeletedDebtsApi.list);
      expect(l!.error, isNull);
      expect(l.page!.enabled, isTrue);
      expect(l.page!.count, 3);
      expect(l.page!.total, 75000);
      expect(l.page!.rows.map((r) => r.key), ['a41', 'm7', 'm9']);

      server.nextAdd = (409, {'success': false, 'code': 'RECENT_DUPLICATE', 'message': '«كرار» بنفس المبلغ أُضيف قبل أقلّ من ٣٠ دقيقة'});
      var a = await t.runAsync(() => DeletedDebtsApi.add(name: 'كرار', amount: 25000));
      expect(a!.ok, isFalse);
      expect(a.code, 'RECENT_DUPLICATE');
      expect(a.message, contains('٣٠ دقيقة'));
      a = await t.runAsync(() => DeletedDebtsApi.add(name: 'كرار', amount: 25000, phone: '', confirmRepeat: true));
      expect(a!.ok, isTrue);
      expect(server.posts.last.$2, {'name': 'كرار', 'amount': 25000, 'confirmRepeat': true}, reason: 'الفارغ لا يُرسَل');

      final p = await t.runAsync(() => DeletedDebtsApi.pay(key: 'm7', amount: 10000));
      expect(p!.ok, isTrue);
      expect((p.paid, p.remaining), (10000.0, 15000.0));
      expect(server.posts.last.$2, {'amount': 10000});
      final all = await t.runAsync(() => DeletedDebtsApi.pay(key: 'm7', payAll: true, comment: 'نقداً'));
      expect(all!.remaining, 0);
      expect(server.posts.last.$2, {'payAll': true, 'comment': 'نقداً'}, reason: '«الكل» بلا مبلغ — الخادم يسدّد رصيده');

      final missing = await t.runAsync(() => DeletedDebtsApi.writeOff(key: 'm404', reason: 'سافر'));
      expect(missing!.ok, isFalse);
      expect(missing.message, 'الدين غير موجود أو ليس من ديونك');
    });
  });

  group('الشاشة', () {
    tearDown(visualTearDown);

    Future<_DdServer> open(WidgetTester t, Scenario s, {bool enabled = true, VisualDevice d = phone}) async {
      final server = _DdServer(await visualSetUp(s))..enabled = enabled;
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, d, home: (_) => const DeletedDebtsScreen());
      await settle(t, seconds: 2);
      return server;
    }

    testWidgets('المالك: العدد والمجموع، والمصادر الثلاثة، والبحث بالهاتف', (t) async {
      final server = await open(t, s1bSasOwner);
      expect(find.text('ديون المشتركين المحذوفين'), findsOneWidget);
      expect(find.text('مدينون محذوفون'), findsOneWidget);
      expect(find.text('75,000 د.ع'), findsOneWidget);
      expect(find.text('حذفته الشركة'), findsOneWidget);
      expect(find.text('يدويّ'), findsOneWidget);
      expect(find.text('من ملف'), findsOneWidget);
      expect(find.text('07701234567'), findsOneWidget);
      expect(find.text('باقة 35 — شهر 9'), findsOneWidget);
      expect(find.byIcon(LucideIcons.lock), findsNothing);
      await shoot(t, s1bSasOwner, 'deleted_debts', phone, server.inner as VisualServer);

      await t.enterText(find.byType(TextField).first, '٠٧٨٠٩');
      await t.pump();
      expect(find.text('زينب حسن'), findsOneWidget);
      expect(find.text('حسين علي'), findsNothing);
      await t.enterText(find.byType(TextField).first, 'لا أحد');
      await t.pump();
      expect(find.text('لا نتائج للبحث'), findsOneWidget);
    });

    testWidgets('الداكن: بلا استثناء', (t) async {
      final server = await open(t, s1bSasOwner, d: phoneDark);
      await shoot(t, s1bSasOwner, 'deleted_debts', phoneDark, server.inner as VisualServer);
    });

    testWidgets('مطفأةٌ للحساب ⇒ «غير مفعّلة» ولا زرّ إضافة', (t) async {
      await open(t, s1bSasOwner, enabled: false);
      expect(find.text('«ديون المشتركين المحذوفين» غير مفعّلة لحسابك بعد'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('ايرث لنك: الإضافة بلا سطر «ما زال بالساس» (فحصه لـSAS4 وحده)', (t) async {
      await open(t, s1Owner);
      await t.tap(find.byType(FloatingActionButton));
      await settle(t, seconds: 1);
      expect(find.text('اسم المستخدم القديم'), findsOneWidget);
      expect(find.textContaining('ما زال بالساس'), findsNothing);
    });

    testWidgets('موظّفٌ بالعرض وحده: التسديد والشطب والإضافة مقفلةٌ بمكانها، والنقر لا يفتح شيئاً', (t) async {
      final server = await open(t, _elViewer);
      // زرّان لكلّ صفٍّ من الثلاثة + زرّ الإضافة.
      expect(find.byIcon(LucideIcons.lock), findsNWidgets(7));
      await t.tap(find.text('تسديد').first);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('المبلغ المستلَم'), findsNothing);
      await t.pump(const Duration(seconds: 3));
      expect(server.posts, isEmpty);
    });

    testWidgets('تسديد «الكل»: تأكيدٌ ثمّ payAll، والقائمة تُعاد', (t) async {
      final server = await open(t, s1bSasOwner);
      final getsBefore = server.gets;
      await t.tap(find.text('تسديد').first);
      await settle(t, seconds: 1);
      expect(find.text('تسديد — حسين علي'), findsOneWidget);
      await t.tap(find.text('الكل'));
      await t.pump();
      expect(find.text('المتبقّي بعد التسديد'), findsOneWidget);
      await t.tap(find.text('تسديد').last); // زرّ الشيت (فوق أزرار الصفوف)
      await settle(t, seconds: 1);
      expect(find.text('تأكيد التسديد'), findsOneWidget);
      await t.tap(find.text('تأكيد'));
      await settle(t, seconds: 1);
      expect(server.posts.single.$1, '/api/v2/deleted-debts/a41/pay');
      expect(server.posts.single.$2, {'payAll': true});
      expect(server.gets, getsBefore + 1);
      expect(find.text('حسين علي'), findsNothing, reason: 'سُدِّد كاملاً فخرج من القائمة');
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('إضافةٌ مكرّرة: الخادم يسأل ⇒ «أضفه» ⇒ تُعاد بـconfirmRepeat', (t) async {
      final server = await open(t, s1bSasOwner);
      server.nextAdd = (409, {'success': false, 'code': 'RECENT_DUPLICATE', 'message': '«علي» بنفس المبلغ أُضيف قبل أقلّ من ٣٠ دقيقة — أكّد إن كان ديناً ثانياً'});
      await t.tap(find.byType(FloatingActionButton));
      await settle(t, seconds: 1);
      expect(find.text('إضافة دين لمشترك محذوف'), findsOneWidget);
      expect(find.textContaining('ما زال بالساس'), findsOneWidget, reason: 'SAS4 يفحص اليوزر القديم');
      final fields = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField));
      await t.enterText(fields.at(0), 'علي');
      await t.enterText(fields.at(1), '20000');
      await t.pump();
      await t.tap(find.text('إضافة دين').last);
      await settle(t, seconds: 1);
      expect(find.text('دين مكرّر؟'), findsOneWidget);
      await t.tap(find.text('أضفه'));
      await settle(t, seconds: 1);
      expect(server.posts.length, 2);
      expect(server.posts.first.$2, {'name': 'علي', 'amount': 20000});
      expect(server.posts.last.$2, {'name': 'علي', 'amount': 20000, 'confirmRepeat': true});
      expect(find.text('إضافة دين لمشترك محذوف'), findsNothing, reason: 'أُغلق الشيت بعد الحفظ');
      await t.pump(const Duration(seconds: 4));
    });
  });

  group('مركز التقارير', () {
    tearDown(visualTearDown);

    testWidgets('مفعّلة ⇒ البطاقة بعددها ومجموعها؛ مطفأة ⇒ لا بطاقة', (t) async {
      final server = _DdServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phone, home: (_) => const ReportsHubScreen());
      await settle(t, seconds: 2);
      expect(find.text('ديون المشتركين المحذوفين'), findsOneWidget);
      expect(find.text('3 مشترك — 75,000 د.ع'), findsOneWidget);
      await t.tap(find.text('ديون المشتركين المحذوفين'));
      await settle(t, seconds: 2);
      expect(find.text('مدينون محذوفون'), findsOneWidget);
    });

    testWidgets('تحديثٌ فاشل يُبقي آخر قيمة، والمطفأة تُخفيها', (t) async {
      final server = _DdServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      final first = await t.runAsync(DeletedDebtsHubSummary.fetch);
      expect(first!.count, 3);
      server.failList = true;
      expect(await t.runAsync(() => DeletedDebtsHubSummary.fetch(previous: first)), same(first));
      server
        ..failList = false
        ..enabled = false;
      expect(await t.runAsync(() => DeletedDebtsHubSummary.fetch(previous: first)), isNull);
    });

    testWidgets('مطفأة ⇒ لا بطاقة', (t) async {
      final server = _DdServer(await visualSetUp(s1bSasOwner))..enabled = false;
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, phone, home: (_) => const ReportsHubScreen());
      await settle(t, seconds: 2);
      expect(find.text('ديون المشتركين المحذوفين'), findsNothing);
      expect(server.gets, 1);
    });
  });

  group('صلاحيّات موظّف ايرث لنك', () {
    const dd = ['deleted_debts.view', 'deleted_debts.add', 'deleted_debts.pay'];

    test('العرض والإضافة والتسديد بـ«موظّف عام»، والشطب يُمنح وحده', () {
      final general = ElEmployeePerms.presets.firstWhere((p) => p.id == 'general');
      for (final k in dd) {
        expect(general.keys, contains(k));
      }
      expect(ElEmployeePerms.keys, contains('deleted_debts.write_off'));
      for (final p in ElEmployeePerms.presets) {
        expect(p.keys, isNot(contains('deleted_debts.write_off')), reason: p.id);
      }
    });

    test('كتالوجٌ بلا مفاتيحها (لم تُفتح للكلّ): «موظّف عام» القديم يبقى مطابقاً', () {
      final general = ElEmployeePerms.presets.firstWhere((p) => p.id == 'general');
      final catalog = general.keys.where((k) => !k.startsWith('deleted_debts.')).toList();
      final perms = {for (final k in catalog) k: true};
      expect(ElEmployeePerms.matching(perms, catalogKeys: catalog)?.id, 'general');
      expect(ElEmployeePerms.matching(perms), isNull, reason: 'بلا الكتالوج تُحسب كلّها');
      expect(ElEmployeePerms.offered(catalog), isNot(contains('deleted_debts.view')));
    });

    test('ما يُرسَل: مفاتيحها كما اختارها المالك حين يعرضها الكتالوج', () {
      final out = ElEmployeePerms.outgoing(
        const ['subscribers.view', 'deleted_debts.view', 'deleted_debts.write_off', 'settings.edit'],
        const {'subscribers.view': true, 'deleted_debts.view': true, 'deleted_debts.write_off': true, 'settings.edit': true},
      );
      expect(out, {'subscribers.view': true, 'deleted_debts.view': true, 'deleted_debts.write_off': true, 'settings.edit': false});
    });
  });

  test('كلّ مفاتيح الترجمة موجودة بالعربيّ والإنجليزيّ', () {
    final src = [
      File('lib/screens/reports/deleted_debts_screen.dart').readAsStringSync(),
      File('lib/screens/reports/reports_hub_screen.dart').readAsStringSync(),
    ].join('\n');
    final used = RegExp(r"'((?:dd|reports|merged)\.[a-z_0-9]+)'").allMatches(src).map((m) => m[1]!).toSet();
    for (final lang in ['ar', 'en']) {
      final d = jsonDecode(File('assets/translations/$lang.json').readAsStringSync()) as Map<String, dynamic>;
      for (final k in used) {
        final parts = k.split('.');
        final v = (d[parts[0]] as Map?)?[parts[1]];
        expect(v, isA<String>(), reason: '$lang: $k');
      }
    }
  });
}
