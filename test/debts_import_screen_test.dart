import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/app_modules.dart';
import 'package:rad_mysvcs/screens/debts_import/debts_import_screen.dart';
import 'package:rad_mysvcs/services/debts_import/xlsx_lite.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «استيراد / تصدير الديون» بالتطبيق (٢٣ نوفمبر — المالك: «اريد ينضاف مثل الويب للهاتف»). الخادم وهميّ: لا دين يُكتب، والطلبات
/// تُسجَّل لتُثبت ما يُرسَل حرفاً (الدفعات، الوضع، اليوزر لمطابقة الهاتف)، والقرارات كالموقع: المطابقة قواعده (debts_import_parity_test)،
/// و«الاسم مختلف» بالاختيار وحده، والدفعة المنقطعة «غير مؤكَّدة» لا تُعاد ولا يُرسل ما بعدها.
const _subsJson = [
  {'idx': '1', 'username': 'ali1', 'firstname': 'علي', 'lastname': 'حسن', 'phone': '07701110001', 'hasDebt': true, 'debt': 15000, 'profile_name': 'Economy', 'expiration': '2026-12-01 00:00:00', 'remaining_days': 8, 'enabled': 1, 'parent_username': 'mahdi'},
  {'idx': '2', 'username': 'zainab', 'firstname': 'زينب', 'lastname': 'كاظم', 'phone': '07701110002', 'hasDebt': false, 'debt': 0, 'profile_name': 'Standard', 'remaining_days': -3, 'enabled': 1},
  {'idx': '3', 'username': 'hussein', 'firstname': 'حسين', 'lastname': 'عبد الأمير', 'phone': '07701110003', 'hasDebt': true, 'debt': 40000, 'enabled': 0},
  // رقمٌ مشترك بين اثنين ⇒ «غير محسوم» إلّا إن حسمه الاسم
  {'idx': '4', 'username': 'abbas', 'firstname': 'عباس', 'lastname': 'رضا', 'phone': '07709990000', 'hasDebt': false, 'debt': 0},
  {'idx': '5', 'username': 'maryam', 'firstname': 'مريم', 'lastname': 'جاسم', 'phone': '07709990000', 'hasDebt': false, 'debt': 0},
];

class _Srv implements HttpClientAdapter {
  _Srv(this.inner, {this.big = false, this.failChunk, this.subs});
  final HttpClientAdapter inner;
  final bool big;

  /// رقم الدفعة (من ١) التي ينقطع ردّها (503).
  final int? failChunk;
  final List<Map<String, Object?>>? subs;
  final posts = <(String, Map<String, dynamic>)>[];
  int chunks = 0;

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final p = o.uri.path;
    if (o.method == 'GET' && p == '/api/v2/subscribers') {
      if (o.queryParameters['page'] != null) {
        return _json(200, big ? {'success': true, 'paged': true, 'total': 9000, 'data': const []} : {'success': true, 'data': const []});
      }
      return _json(200, {'success': true, 'data': subs ?? _subsJson});
    }
    if (o.method == 'GET' && p == '/api/v2/deleted-debts') {
      return _json(200, {'success': true, 'enabled': true, 'data': const [], 'totals': {'count': 0, 'debt': 0}});
    }
    if (o.method == 'GET' && p == '/api/v2/subscriber-contacts/all') {
      return _json(200, {
        'success': true,
        'enabled': true,
        'contacts': {
          'ali1': {'wa_phone2': '07801110001', 'tg_contact': '@ali'},
        },
      });
    }
    if (o.method == 'POST' && p == '/api/v2/debts/bulk-import') {
      final b = Map<String, dynamic>.from(o.data as Map);
      posts.add((p, b));
      chunks++;
      if (failChunk == chunks) return _json(503, {'success': false});
      final rows = (b['rows'] as List).cast<Map>();
      return _json(200, {
        'success': true,
        'data': {
          'total': rows.length,
          'applied': rows.where((r) => r['username'] != 'hussein').length,
          'not_found': const [],
          'invalid': const [],
          'failed': [
            for (final r in rows)
              if (r['username'] == 'hussein') {'username': 'hussein', 'error': 'هذا الصفّ طُبّق من ملفٍّ قبل أقلّ من ٣٠ دقيقة — لم يُطبَّق ثانيةً'},
          ],
          'details': [
            for (final r in rows)
              if (r['username'] != 'hussein') {'username': r['username'], 'idx': '1', 'previous': 0, 'new': r['amount'], 'delta': r['amount']},
          ],
        },
      });
    }
    if (o.method == 'POST' && p == '/api/v2/deleted-debts/import') {
      final b = Map<String, dynamic>.from(o.data as Map);
      posts.add((p, b));
      final rows = (b['rows'] as List).cast<Map>();
      final repeat = b['confirmRepeat'] == true;
      return _json(200, {
        'success': true,
        'data': {
          'total': rows.length,
          'added': repeat ? rows.length : rows.length - 1,
          'debt_added': 1000,
          'invalid': const [],
          'exists': const [],
          // أوّل الصفوف أُضيف قبل أقلّ من ٣٠ دقيقة (رقم الصفّ من ١)
          'repeat': repeat ? const [] : [
            {'row': 1, 'name': rows.first['name']},
          ],
          'duplicate': const [],
          'failed': const [],
        },
      });
    }
    return inner.fetch(o, rs, cf);
  }

  @override
  void close({bool force = false}) {}
}

Uint8List _file(List<List<Object?>> rows) =>
    writeXlsx(sheetName: 'Debts', headers: const ['username', 'amount', 'الاسم', 'رقم الهاتف'], rows: rows);

void main() {
  setUpAll(visualSetUpAll);

  Future<_Srv> open(WidgetTester t, {bool big = false, int? failChunk, double width = 430, double scale = 1.0, List<Map<String, Object?>>? subs}) async {
    final srv = _Srv(await visualSetUp(s1bSasOwner), big: big, failChunk: failChunk, subs: subs);
    ApiClient.dio.httpClientAdapter = srv;
    BigSubscribersApi.reset();
    SubscribersApi.clearAllCaches();
    await pumpVisual(
      t,
      VisualDevice('', Size(width, 2400), 2),
      home: (_) => const DebtsImportScreen(),
      wrap: (child) => Builder(
        builder: (ctx) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child),
      ),
    );
    await settle(t, seconds: 2);
    return srv;
  }

  Future<void> down(WidgetTester t) async {
    DebtsImportScreen.debugPick = null;
    DebtsImportScreen.debugExport = null;
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    await visualTearDown();
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(ValueKey(key));
    await t.ensureVisible(f);
    await t.tap(f);
    await settle(t, seconds: 1);
  }

  testWidgets('التصدير: المدينون، كلّ المشتركين (الحالة والمدير وأرقام التواصل)، والقالب — Excel بأعمدة الموقع نفسها', (t) async {
    await open(t);
    final got = <String, List<List<String>>>{};
    DebtsImportScreen.debugExport = (name, bytes) async => got[name.replaceAll(RegExp(r'\d{4}-\d{2}-\d{2}'), 'D')] = readXlsxRows(bytes);
    try {
      expect(find.text('المدينون الحاليون (2)'), findsOneWidget);
      expect(find.text('كلّ المشتركين (5)'), findsOneWidget);
      await tapKey(t, 'dimp-export-debtors');
      await tapKey(t, 'dimp-export-all');
      await tapKey(t, 'dimp-export-template');
      expect(got['debts-D.xlsx'], [
        ['username', 'amount', 'الاسم', 'رقم الهاتف', 'الباقة', 'تاريخ النفاذ'],
        ['ali1', '15000', 'علي حسن', '07701110001', 'Economy', '2026-12-01 00:00:00'],
        ['hussein', '40000', 'حسين عبد الأمير', '07701110003', '', ''],
      ]);
      final all = got['subscribers-D.xlsx']!;
      expect(all.first, ['username', 'amount', 'الاسم', 'رقم الهاتف', 'الباقة', 'تاريخ النفاذ', 'الحالة', 'المدير', 'واتساب ثانٍ', 'تلغرام']);
      expect(all[1], ['ali1', '15000', 'علي حسن', '07701110001', 'Economy', '2026-12-01 00:00:00', 'فعّال', 'mahdi', '07801110001', '@ali']);
      expect(all[2].sublist(0, 2), ['zainab', '0'], reason: 'بلا دين ⇒ 0 (يُرفع الملفّ كما هو)');
      expect(all[2][6], 'منتهٍ');
      expect(all[3][6], 'معطّل');
      expect(all.length, 6);
      expect(got['debts-import-template.xlsx']!.length, 4, reason: 'العناوين + أوّل ثلاثة مشتركين');
      expect(got['debts-import-template.xlsx']![1][1], '', reason: 'المبلغ فارغ بالقالب');
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('الاستيراد: المطابقة باليوزر والهاتف، «الاسم مختلف» بالاختيار وحده، والدفعات (١٥) بالوضع واليوزر الصحيح، والنتيجة بأسبابها', (t) async {
    final srv = await open(t);
    // ٢٠ صفّاً باليوزر نفسه لا تصحّ (مشتركٌ بأكثر من صفّ ⇒ لا يُحسم إلّا باليوزر — واليوزر يُطبَّق)؛ نبني ملفّاً واقعيّاً:
    final rows = <List<Object?>>[
      ['ali1', 25000, 'علي', ''], // يوزر
      ['', '٣٠,٠٠٠', 'زينب كاظم', '0770 111 0002'], // هاتف + اسمٌ يطابق
      ['', 5000, 'كرار سعدي', '9647701110003'], // هاتف واسمٌ مختلف ⇒ «راجِع»
      ['', 7000, 'مجهول', '07709990000'], // رقمٌ لاثنين بلا اسمٍ يحسم ⇒ غير محسوم
      ['nobody', 9000, 'غير موجود', ''], // غير موجود
      ['', 0, 'صفر', '07701110002'], // بلا دين
    ];
    DebtsImportScreen.debugPick = () async => (name: 'debts.xlsx', bytes: _file(rows));
    try {
      await tapKey(t, 'dimp-pick');
      expect(find.text('مطابق 2 (بالهاتف 1)'), findsOneWidget);
      expect(find.text('للمراجعة 2'), findsOneWidget);
      expect(find.text('غير موجود 1'), findsOneWidget);
      expect(find.text('غير صالح 1'), findsOneWidget);
      expect(find.text('تطبيق (2) — استبدال'), findsOneWidget, reason: 'الاستبدال افتراضاً كالموقع');
      expect(find.text('الاسم مختلف — راجِع'), findsOneWidget);
      expect(find.text('في الملف: كرار سعدي'), findsOneWidget);
      // «الاسم مختلف» بالاختيار ⇒ يدخل
      await tapKey(t, 'dimp-review');
      expect(find.text('تطبيق (3) — استبدال'), findsOneWidget);
      await tapKey(t, 'dimp-apply');
      expect(find.textContaining('تأكيد 3 عملية استبدال دين'), findsOneWidget);
      await t.tap(find.text('تطبيق 3'));
      await settle(t, seconds: 2);
      final b = srv.posts.where((x) => x.$1 == '/api/v2/debts/bulk-import').single.$2;
      expect(b['mode'], 'set');
      expect(b['rows'], [
        {'username': 'ali1', 'amount': 25000},
        {'username': 'zainab', 'amount': 30000},
        {'username': 'hussein', 'amount': 5000},
      ], reason: 'بالهاتف ⇒ يوزر المشترك المطابَق، والأرقام العربيّة والفواصل مقروءة');
      // النتيجة: مطبَّقان، وواحدٌ بسببه من الخادم
      final applied = find.descendant(of: find.byKey(const ValueKey('dimp-res-applied')), matching: find.text('2'));
      expect(applied, findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('dimp-res-failed')), matching: find.text('1')), findsOneWidget);
      await t.ensureVisible(find.text('صفوفٌ لم تُطبَّق (1)'));
      await t.tap(find.text('صفوفٌ لم تُطبَّق (1)'));
      await settle(t, seconds: 1);
      expect(find.textContaining('طُبّق من ملفٍّ قبل أقلّ من ٣٠ دقيقة'), findsOneWidget);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('الإضافة (+) بالدفعات: ٣٢ صفّاً ⇒ ١٥ + ١٥ + ٢ بالترتيب، والدين بعد التطبيق = الحالي + المبلغ', (t) async {
    final many = [
      for (var i = 0; i < 32; i++)
        {'idx': '$i', 'username': 'u$i', 'firstname': 'م', 'lastname': '$i', 'phone': '', 'hasDebt': i == 0, 'debt': i == 0 ? 1000 : 0},
    ];
    final srv = await open(t, subs: many);
    DebtsImportScreen.debugPick = () async => (name: 'add.csv', bytes: Uint8List.fromList(utf8.encode('\uFEFFusername;amount\n${[for (var i = 0; i < 32; i++) 'u$i;${i + 1}'].join('\n')}\n')));
    try {
      await tapKey(t, 'dimp-mode-add');
      await tapKey(t, 'dimp-pick');
      expect(find.text('تطبيق (32) — إضافة'), findsOneWidget);
      expect(find.text('بعده 1,001'), findsOneWidget, reason: 'u0: الحالي 1,000 + 1');
      await tapKey(t, 'dimp-apply');
      await t.tap(find.text('تطبيق 32'));
      await settle(t, seconds: 3);
      final bodies = [for (final x in srv.posts) if (x.$1 == '/api/v2/debts/bulk-import') x.$2];
      expect([for (final b in bodies) (b['rows'] as List).length], [15, 15, 2]);
      expect({for (final b in bodies) b['mode']}, {'add'});
      expect([for (final b in bodies) for (final r in b['rows'] as List) (r as Map)['username']], [for (var i = 0; i < 32; i++) 'u$i']);
      expect(find.descendant(of: find.byKey(const ValueKey('dimp-res-applied')), matching: find.text('32')), findsOneWidget);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('دفعةٌ ينقطع ردّها ⇒ صفوفها «غير مؤكَّدة» بأسمائها، لا تُعاد، ولا يُرسل ما بعدها', (t) async {
    final many = [for (var i = 0; i < 40; i++) {'idx': '$i', 'username': 'u$i', 'firstname': 'م', 'lastname': '$i', 'phone': ''}];
    final srv = await open(t, subs: many, failChunk: 2);
    DebtsImportScreen.debugPick =
        () async => (name: 'x.csv', bytes: Uint8List.fromList(utf8.encode('username,amount\n${[for (var i = 0; i < 40; i++) 'u$i,1000'].join('\n')}\n')));
    try {
      await tapKey(t, 'dimp-pick');
      await tapKey(t, 'dimp-apply');
      await t.tap(find.text('تطبيق 40'));
      await settle(t, seconds: 3);
      expect(srv.chunks, 2, reason: 'الثالثة لا تُرسل بعد انقطاع الثانية — ولا إعادةٌ تلقائيّة');
      expect(find.textContaining('غير مؤكَّد (15)'), findsOneWidget);
      expect(find.textContaining('u15'), findsWidgets);
      expect(find.textContaining('لم يُرسل 10 صفّاً'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('dimp-res-applied')), matching: find.text('15')), findsOneWidget);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('«غير موجود» ⇒ ديون المحذوفين بالاسم والهاتف والمبلغ، و«أضف المكرّرة» يعيد صفوفها وحدها بـconfirmRepeat', (t) async {
    final srv = await open(t);
    DebtsImportScreen.debugPick = () async => (
          name: 'gone.xlsx',
          bytes: _file([
            ['gone1', 12000, 'مشترك محذوف', '07800000001'],
            ['', 8000, 'محذوف ثانٍ', '07800000002'],
            ['ali1', 1000, 'علي', ''],
          ]),
        );
    try {
      await tapKey(t, 'dimp-pick');
      expect(find.textContaining('2 غير موجود بالساس'), findsOneWidget);
      await tapKey(t, 'dimp-deleted-add');
      await t.tap(find.text('أضفها').last);
      await settle(t, seconds: 2);
      final first = srv.posts.where((x) => x.$1 == '/api/v2/deleted-debts/import').single.$2;
      expect(first['rows'], [
        {'name': 'مشترك محذوف', 'amount': 12000.0, 'phone': '07800000001', 'username': 'gone1'},
        {'name': 'محذوف ثانٍ', 'amount': 8000.0, 'phone': '07800000002', 'username': ''},
      ]);
      expect(first.containsKey('confirmRepeat'), isFalse);
      expect(find.textContaining('أُضيفوا قبل أقلّ من ٣٠ دقيقة 1'), findsOneWidget);
      await tapKey(t, 'dimp-deleted-again');
      await t.tap(find.text('أضفها').last);
      await settle(t, seconds: 2);
      final again = srv.posts.where((x) => x.$1 == '/api/v2/deleted-debts/import').last.$2;
      expect(again['confirmRepeat'], isTrue);
      expect((again['rows'] as List).length, 1, reason: 'الصفّ المكرّر وحده — لا الملفّ كلّه');
      expect(((again['rows'] as List).single as Map)['username'], 'gone1');
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('ملفّ PDF أو xls ⇒ رسالةٌ واضحة ولا معاينة', (t) async {
    await open(t);
    try {
      DebtsImportScreen.debugPick = () async => (name: 'r.pdf', bytes: Uint8List.fromList(utf8.encode('%PDF-1.7 ...')));
      await tapKey(t, 'dimp-pick');
      expect(find.textContaining('تقرير PDF يُقرأ من الموقع الآن'), findsOneWidget);
      expect(find.byKey(const ValueKey('dimp-preview')), findsNothing);
      DebtsImportScreen.debugPick = () async => (name: 'old.xls', bytes: Uint8List.fromList([0xd0, 0xcf, 0x11, 0xe0, 0, 0, 0, 0]));
      await settle(t, seconds: 4);
      await tapKey(t, 'dimp-pick');
      expect(find.textContaining('صيغة Excel قديمة (xls)'), findsOneWidget);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('الحساب الكبير (≥ ٥٠٠٠) ⇒ يقول ذلك ولا يطلب القائمة ولا يعرض الاستيراد', (t) async {
    final srv = await open(t, big: true);
    try {
      expect(find.textContaining('حسابك كبير (9,000 مشترك)'), findsOneWidget);
      expect(find.byKey(const ValueKey('dimp-import')), findsNothing);
      expect(find.byKey(const ValueKey('dimp-export')), findsNothing);
      expect(srv.posts, isEmpty);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  for (final width in [320.0, 360.0, 480.0]) {
    testWidgets('الشكل @$width ×1.2: التصدير والاستيراد والمعاينة والنتيجة بلا فيض', (t) async {
      await open(t, width: width, scale: 1.2);
      DebtsImportScreen.debugPick = () async => (
            name: 'a-very-long-file-name-from-the-agents-phone-2026-11-23.xlsx',
            bytes: _file([
              ['ali1', 25000, 'علي', ''],
              ['', 5000, 'اسمٌ طويلٌ جدّاً من ملفّ نظامٍ آخر لا يشبه اسم المشترك', '07701110003'],
              ['nobody_with_a_long_username@company', 1234567890, '', ''],
            ]),
          );
      try {
        await tapKey(t, 'dimp-pick');
        expect(t.takeException(), isNull);
        await tapKey(t, 'dimp-apply');
        await t.tap(find.text('تطبيق 1'));
        await settle(t, seconds: 2);
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });
  }

  test('القائمة: «استيراد / تصدير الديون» لصاحب الحساب، لا للموظّف ولا للوطنيّ القديم (FTTH)', () {
    bool shown() => buildAppModules().any((m) => m.id == 'debts_import');
    ProviderService.debugSet(null);
    PermissionsService.debugSet(isEmployee: false);
    expect(shown(), isTrue);
    PermissionsService.debugSet(isEmployee: true, permissions: const {'reports.financial': true});
    expect(shown(), isFalse, reason: 'لا يُمنح لموظّفٍ أبداً (قرار ٢١ أكتوبر)');
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet('earthlink');
    expect(shown(), isTrue, reason: 'ايرث لنك: دفترنا');
    ProviderService.debugSet('ftth');
    expect(shown(), isFalse);
    ProviderService.debugSet(null);
  });
}
