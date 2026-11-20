import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/reports_api.dart';
import 'package:rad_mysvcs/api/subscriber_edits_api.dart';
import 'package:rad_mysvcs/core/util/bidi.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/recent_activities.dart';
import 'package:rad_mysvcs/screens/manager_alias_sheet.dart';
import 'package:rad_mysvcs/screens/settings_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/edits_sheet.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «سجلّ التعديلات» و«اسمك في السجلات» بالتطبيق (المالك ٢٠ نوفمبر: «من يوزر يعدلون عليه معلومات… سويها» ثمّ «اسم مستعار
/// للمدير بدل admin@»). العقد [_contract] مولَّدٌ من server/subscriberEdits.js الحيّ نفسه (list() بسطورٍ مصطنعة — بصمة الملفّ في
/// source_sha256_16): ما يقرؤه التطبيق هو ما يرسله الخادم حرفاً.
final Map<String, dynamic> _contract =
    jsonDecode(File('test/subscriber_edits/server_contract.json').readAsStringSync()) as Map<String, dynamic>;

final String _nbsp = String.fromCharCode(0xA0);

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

/// خادمٌ وهميّ بعقد المسارين: سجلّ التعديلات و«اسمك في السجلات» — وما عداهما للخادم المرئيّ.
class _Srv implements HttpClientAdapter {
  _Srv(this.inner);
  final HttpClientAdapter inner;
  final edits = <String>[];
  final puts = <Object?>[];
  int aliasGets = 0;
  Map<String, dynamic> editsBody = _contract['owner'] as Map<String, dynamic>;
  int failEdits = 0;
  bool editsThrow500 = false;
  String? alias;
  int aliasGetStatus = 200;
  ({int status, Map<String, dynamic> body})? putReply;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final path = o.uri.path;
    final key = o.headers['x-company-key'] as String?;
    final h = key == null ? const <String, List<String>>{} : {'x-company-key': [key]};
    if (RegExp(r'^/api/v2/subscribers/[^/]+/edits$').hasMatch(path)) {
      edits.add('${o.method} ${o.uri.path}?${o.uri.query}${key == null ? '' : ' @$key'}');
      if (editsThrow500) return _json(500, {'success': false, 'message': 'خطأ مؤقّت بالخادم'}, headers: h);
      if (failEdits > 0) {
        failEdits--;
        return _json(409, {'success': false, 'message': 'تعذّرت قراءة سجلّ التعديلات — أعد المحاولة'}, headers: h);
      }
      return _json(200, editsBody, headers: h);
    }
    if (path == '/api/v2/manager-alias') {
      if (o.method == 'GET') {
        aliasGets++;
        if (aliasGetStatus != 200) {
          return _json(aliasGetStatus, {'success': false, 'message': 'تعذّرت قراءة الاسم — أعد المحاولة'});
        }
        return _json(200, {'success': true, 'alias': alias, 'max': 40});
      }
      if (o.method == 'PUT') {
        final d = o.data;
        final body = d is Map ? Map<String, dynamic>.from(d) : jsonDecode('$d') as Map<String, dynamic>;
        puts.add(body['alias']);
        final r = putReply;
        if (r != null) return _json(r.status, r.body);
        final a = '${body['alias'] ?? ''}'.trim();
        alias = a.isEmpty ? null : a;
        return _json(200, {'success': true, 'alias': alias, 'message': alias != null ? 'حُفظ الاسم' : 'رجع السجلّ ليوزر الصفحة'});
      }
    }
    return inner.fetch(o, rs, cf);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

List<SubscriberEdit> _rowsOf(String part) => [
      for (final x in ((_contract[part] as Map)['data'] as List))
        if (SubscriberEdit.fromJson(x) case final e?) e,
    ];

Subscriber _sub({String? idx = '12', String username = 'u12', String first = 'علي', String last = 'حسن', String? key}) =>
    Subscriber(idx: idx, username: username, firstname: first, lastname: last, companyKey: key);

String _plain(List<InlineSpan> spans) => TextSpan(children: spans).toPlainText();

const _muted = TextStyle(fontSize: 12);
const _strong = TextStyle(fontSize: 13);

/// هاتفٌ بعرض ٣٢٠ وطولٍ يكفي النافذة — بخطّ ١٫٢ (أقصى ما يسمح به التطبيق).
const _narrow = VisualDevice('_320', Size(320, 1400), 2);

void main() {
  setUpAll(visualSetUpAll);

  group('العقد من الخادم الحقيقيّ', () {
    test('المالك: الأحدث أوّلاً، و«من → إلى»، والسرّ بلا قيمة، والباقة عند الانتهاء، والقديم بأسمائه، والنصّ البديل', () {
      final rows = _rowsOf('owner');
      expect(rows.map((r) => r.id), [902, 901, 903, 904, 905, 906]);
      final emp = rows[0];
      expect(emp.byEmployee, isTrue);
      expect(emp.byName, startsWith('محمّد عبد الأمير'));
      expect(emp.title, 'تعديل المعلومات');
      expect(emp.atMs, DateTime.utc(2026, 11, 20, 21, 10).millisecondsSinceEpoch);
      expect(emp.diff.map((e) => (e.f, e.from, e.to)), [
        ('name', '', 'عبد الرحمن محمّد عبد الكريم الحسينيّ'),
        ('lastname', 'قديم', ''),
      ]);
      final edit = rows[1];
      expect(edit.byEmployee, isFalse);
      expect(edit.byName, 'admin@demo');
      expect(edit.diff.map((e) => e.f), ['phone', 'expiration', 'password', 'profile']);
      expect((edit.diff[0].label, edit.diff[0].from, edit.diff[0].to), ('رقم الهاتف', '07701112233', '07709998877'));
      expect(edit.diff[2].secret, isTrue);
      expect((edit.diff[2].from, edit.diff[2].to), ('', ''));
      expect(edit.diff[3].atExpiry, isTrue);
      expect(rows[2].diff.map((e) => (e.f, e.hidden, e.secret)), [('device_ip', false, false), ('device_pass', false, true)]);
      expect(rows[3].diff.single.text, 'أُضيفت');
      expect(rows[4].diff, isEmpty);
      expect(rows[4].fields, ['رقم الهاتف', 'الاسم الأوّل']);
      expect(rows[5].note, 'استُثني من الرسائل');
      expect(rows[5].title, 'الاستثناء من الرسائل');
    });

    test('موظّفٌ بلا صلاحيّة الأجهزة ومديرٌ باسمٍ مستعار: إعداد الجهاز مخفيّ، والمدير «أبو علي»', () {
      final rows = _rowsOf('employee_no_device_alias');
      expect(rows[1].byName, 'أبو علي');
      expect(rows[0].byName, startsWith('محمّد'), reason: 'الموظّف باسمه — الاسم المستعار للمدير وحده');
      expect(rows[2].diff.every((e) => e.hidden), isTrue);
      expect(rows[2].diff.any((e) => e.to.contains('10.0.0')), isFalse);
    });

    test('سطرٌ ناقص لا يُسقط القائمة: بلا «by» ⇒ «المدير»، موظّفٌ بلا اسم ⇒ «موظّف»، وبنودٌ تالفة تُترك', () {
      final r = SubscriberEdit.fromJson({
        'id': '77',
        'at': '1763650000000',
        'diff': [
          'نصّ',
          {'label': 'بلا f'},
          {'f': 'phone', 'from': 1, 'to': 2},
        ],
        'fields': ['a', 3],
      })!;
      expect(r.id, 77);
      expect(r.atMs, 1763650000000);
      expect(r.byName, 'المدير');
      expect(r.title, 'تعديل');
      expect(r.diff.map((e) => (e.f, e.label, e.from, e.to)), [('phone', 'phone', '1', '2')]);
      expect(r.fields, ['a', '3']);
      expect(SubscriberEdit.fromJson({'by': {'employee': true}, 'id': 1})!.byName, 'موظّف');
      expect(SubscriberEdit.fromJson({'title': 'x'}), isNull, reason: 'بلا رقم لا سطر');
      expect(SubscriberEdit.fromJson('نصّ'), isNull);
      expect(SubscriberEdit.fromJson({'id': 2, 'note': '  '})!.note, isNull);
    });
  });

  group('القيم والوقت', () {
    test('التاريخ أرقامٌ بالشرطة المائلة ووقته معه بلا انكسار', () {
      expect(editValue('2026-12-01 00:00:00'), '2026/12/01${_nbsp}00:00');
      expect(editValue('2026-12-01T05:07'), '2026/12/01${_nbsp}05:07');
      expect(editValue('2026-12-01'), '2026/12/01');
      expect(editValue(' باقة 35 ألف '), 'باقة 35 ألف');
      expect(editValue('2026-12-01 بعد الظهر'), '2026-12-01 بعد الظهر');
      expect(editValue(''), '');
      expect(editValue(null), '');
    });

    test('وقت التعديل بتوقيت بغداد (+3) — ما بعد منتصف الليل يومٌ جديد', () {
      expect(editTime(DateTime.utc(2026, 11, 20, 21, 10).millisecondsSinceEpoch), '2026/11/21${_nbsp}00:10');
      expect(editTime(DateTime.utc(2026, 11, 20, 13, 35).millisecondsSinceEpoch), '2026/11/20${_nbsp}16:35');
      expect(editTime(DateTime.utc(2026, 12, 31, 21, 0).millisecondsSinceEpoch), '2027/01/01${_nbsp}00:00');
    });

    test('سطر الحقل: «من … إلى …» بقيمٍ معزولة، «صار» من الفارغ، «فارغ» حين يُمسح، والسرّ «تغيّرت» وحدها', () {
      final rows = _rowsOf('owner');
      final edit = rows[1];
      expect(_plain(entrySpans(edit.diff[0], _muted, _strong)),
          'رقم الهاتف: من ${iso('07701112233')} إلى ${iso('07709998877')}');
      expect(_plain(entrySpans(edit.diff[1], _muted, _strong)),
          'تاريخ الانتهاء: من ${iso('2026/12/01${_nbsp}00:00')} إلى ${iso('2027/01/01${_nbsp}00:00')}');
      expect(_plain(entrySpans(edit.diff[2], _muted, _strong)), 'كلمة المرور: تغيّرت');
      expect(_plain(entrySpans(edit.diff[3], _muted, _strong)),
          'الباقة: من ${iso('باقة 35 ألف')} إلى ${iso('باقة 50 ألف')} (عند انتهاء الاشتراك)');
      final emp = rows[0];
      expect(_plain(entrySpans(emp.diff[0], _muted, _strong)), 'الاسم: صار ${iso('عبد الرحمن محمّد عبد الكريم الحسينيّ')}');
      expect(_plain(entrySpans(emp.diff[1], _muted, _strong)), 'اسم العائلة: من ${iso('قديم')} إلى فارغ');
      expect(_plain(entrySpans(rows[3].diff.single, _muted, _strong)), 'الملاحظة الخاصّة: أُضيفت');
      final hidden = _rowsOf('employee_no_device_alias')[2].diff.first;
      expect(_plain(entrySpans(hidden, _muted, _strong)), 'عنوان الجهاز: تغيّر — يظهر لمن عنده صلاحيّة الأجهزة');
    });
  });

  group('النداء', () {
    late _Srv srv;
    setUp(() async {
      srv = _Srv(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = srv;
    });
    tearDown(visualTearDown);

    test('المسار برقم المشترك مرمَّزاً واليوزر استعلاماً', () async {
      expect(SubscriberEditsApi.path('C 3/8'), '/api/v2/subscribers/C%203%2F8/edits');
      final r = await SubscriberEditsApi.list('12', username: 'u12');
      expect(r.ok, isTrue);
      expect(r.rows.length, 6);
      expect(srv.edits, ['GET /api/v2/subscribers/12/edits?username=u12']);
      await SubscriberEditsApi.list('38A');
      expect(srv.edits.last, 'GET /api/v2/subscribers/38A/edits?');
    });

    test('رفض الخادم (409) أو عطله (500) ⇒ ok:false برسالته — لا قائمةٌ فارغة كأنّها «لا تعديلات»', () async {
      srv.failEdits = 1;
      final a = await SubscriberEditsApi.list('12', username: 'u12');
      expect((a.ok, a.message), (false, 'تعذّرت قراءة سجلّ التعديلات — أعد المحاولة'));
      expect(a.rows, isEmpty);
      srv.editsThrow500 = true;
      final b = await SubscriberEditsApi.list('12', username: 'u12');
      expect((b.ok, b.message), (false, 'خطأ مؤقّت بالخادم'));
    });

    test('«اسمك في السجلات»: القراءة، والحفظ مقصوصاً، والمسح فارغاً، ورفض 422 برسالته', () async {
      srv.alias = 'أبو علي';
      final g = await ManagerAliasApi.get();
      expect((g.ok, g.alias), (true, 'أبو علي'));
      final s = await ManagerAliasApi.save('  المكتب  ');
      expect((s.ok, s.alias), (true, 'المكتب'));
      expect(srv.puts, ['المكتب']);
      final c = await ManagerAliasApi.save('');
      expect((c.ok, c.alias), (true, null));
      expect(srv.puts.last, '');
      srv.putReply = (status: 422, body: {'success': false, 'code': 'ALIAS_INVALID', 'message': 'الاسم بلا روابط ولا @'});
      final bad = await ManagerAliasApi.save('a@b');
      expect((bad.ok, bad.message), (false, 'الاسم بلا روابط ولا @'));
      srv.aliasGetStatus = 409;
      final gf = await ManagerAliasApi.get();
      expect((gf.ok, gf.message), (false, 'تعذّرت قراءة الاسم — أعد المحاولة'));
    });
  });

  group('نافذة «سجلّ التعديلات»', () {
    late _Srv srv;

    Future<void> openSheet(WidgetTester t, {VisualDevice d = _narrow, Subscriber? sub}) async {
      srv = _Srv(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = srv;
      t.platformDispatcher.textScaleFactorTestValue = 1.2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpVisual(t, d,
          home: (c) => Scaffold(
                backgroundColor: AppColors.bg,
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showSubscriberEditsSheet(c, sub ?? _sub()),
                    child: const Text('افتح'),
                  ),
                ),
              ));
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 2);
    }

    tearDown(visualTearDown);

    testWidgets('بعرض ٣٢٠ وخطّ ١٫٢: كلّ التعديلات بلا فيضٍ ولا قصّ — الاسم الطويل يلتفّ', (t) async {
      await openSheet(t);
      expect(t.takeException(), isNull);
      expect(srv.edits, ['GET /api/v2/subscribers/12/edits?username=u12']);
      expect(find.text('سجلّ التعديلات'), findsOneWidget);
      // الأحدث أوّلاً كما أرسله الخادم
      final ids = [
        for (final e in t.widgetList(find.byWidgetPredicate((w) => w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('sub-edit-'))))
          (e.key! as ValueKey<String>).value,
      ];
      expect(ids, ['sub-edit-902', 'sub-edit-901', 'sub-edit-903', 'sub-edit-904', 'sub-edit-905', 'sub-edit-906']);
      expect(find.textContaining('من ${iso('07701112233')} إلى ${iso('07709998877')}', findRichText: true), findsOneWidget);
      expect(find.textContaining('(عند انتهاء الاشتراك)', findRichText: true), findsOneWidget);
      expect(find.textContaining('كلمة المرور: تغيّرت', findRichText: true), findsOneWidget);
      expect(find.textContaining('كلمة مرور الجهاز: تغيّرت', findRichText: true), findsOneWidget);
      // الاسم الطويل كاملاً معزولاً بعد «الموظّف:» — لا مقطوعاً
      expect(find.textContaining('الموظّف: ${iso('محمّد عبد الأمير جبّار الموسويّ — موظّف الصندوق الرئيسيّ بالفرع الثاني')}',
              findRichText: true),
          findsOneWidget);
      expect(find.textContaining('عُدّل: رقم الهاتف، الاسم الأوّل', findRichText: true), findsOneWidget);
      expect(find.text('استُثني من الرسائل'), findsOneWidget);
      // 21:10 UTC ⇒ 00:10 بغداد من اليوم التالي
      expect(find.text(iso('2026/11/21${_nbsp}00:10')), findsOneWidget);
      // لا نصّ مقصوصٌ بـ«…» ولا محدودٌ بأسطر في بطاقات التعديلات (رأس النافذة له سطره كبقيّة النوافذ)
      final cards = find.byWidgetPredicate(
          (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('sub-edit-'));
      final texts = t.widgetList<Text>(find.descendant(of: cards, matching: find.byType(Text))).toList();
      expect(texts.length, greaterThan(20));
      for (final w in texts) {
        expect(w.overflow, isNot(TextOverflow.ellipsis), reason: '${w.data ?? w.textSpan?.toPlainText()}');
        expect(w.maxLines, isNull, reason: '${w.data ?? w.textSpan?.toPlainText()}');
      }
      await shoot(t, s1bSasOwner, 'sub_edits_sheet', _narrow, srv.inner as VisualServer);
    });

    testWidgets('الوضع الداكن بعرض ٣٢٠ — بلا فيض', (t) async {
      await openSheet(t, d: const VisualDevice('_320_dark', Size(320, 1400), 2, dark: true));
      expect(t.takeException(), isNull);
      expect(find.text('سجلّ التعديلات'), findsOneWidget);
      await shoot(t, s1bSasOwner, 'sub_edits_sheet', const VisualDevice('_320_dark', Size(320, 1400), 2, dark: true),
          srv.inner as VisualServer);
    });

    testWidgets('تعذّرت القراءة ⇒ رسالة الخادم و«إعادة المحاولة» ⇒ التعديلات', (t) async {
      srv = _Srv(await visualSetUp(s1bSasOwner))..failEdits = 1;
      ApiClient.dio.httpClientAdapter = srv;
      await pumpVisual(t, _narrow,
          home: (c) => Scaffold(
                body: Center(
                  child: ElevatedButton(onPressed: () => showSubscriberEditsSheet(c, _sub()), child: const Text('افتح')),
                ),
              ));
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 2);
      expect(find.byKey(const ValueKey('sub-edits-error')), findsOneWidget);
      expect(find.text('تعذّرت قراءة سجلّ التعديلات — أعد المحاولة'), findsOneWidget);
      expect(find.byKey(const ValueKey('sub-edit-901')), findsNothing);
      await t.tap(find.text('إعادة المحاولة'));
      await settle(t, seconds: 2);
      expect(srv.edits.length, 2);
      expect(find.byKey(const ValueKey('sub-edit-901')), findsOneWidget);
      expect(find.byKey(const ValueKey('sub-edits-error')), findsNothing);
    });

    testWidgets('لا تعديلات ⇒ «لا تعديلات مسجّلة لهذا المشترك» (لا رسالة خطأ)', (t) async {
      srv = _Srv(await visualSetUp(s1bSasOwner))..editsBody = {'success': true, 'data': []};
      ApiClient.dio.httpClientAdapter = srv;
      await pumpVisual(t, _narrow,
          home: (c) => Scaffold(
                body: Center(
                  child: ElevatedButton(onPressed: () => showSubscriberEditsSheet(c, _sub()), child: const Text('افتح')),
                ),
              ));
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 2);
      expect(find.text('لا تعديلات مسجّلة لهذا المشترك'), findsOneWidget);
      expect(find.byKey(const ValueKey('sub-edits-error')), findsNothing);
    });

    testWidgets('بلا صلاحيّة الأجهزة ومديرٌ باسمٍ مستعار: «أبو علي» وإعداد الجهاز «يظهر لمن عنده صلاحيّة الأجهزة»', (t) async {
      srv = _Srv(await visualSetUp(s1bSasOwner))..editsBody = _contract['employee_no_device_alias'] as Map<String, dynamic>;
      ApiClient.dio.httpClientAdapter = srv;
      await pumpVisual(t, _narrow,
          home: (c) => Scaffold(
                body: Center(
                  child: ElevatedButton(onPressed: () => showSubscriberEditsSheet(c, _sub()), child: const Text('افتح')),
                ),
              ));
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 2);
      expect(find.textContaining('المدير: ${iso('أبو علي')}', findRichText: true), findsWidgets);
      expect(find.textContaining('admin@demo', findRichText: true), findsNothing);
      expect(find.textContaining('يظهر لمن عنده صلاحيّة الأجهزة', findRichText: true), findsNWidgets(2));
      expect(find.textContaining('10.0.0', findRichText: true), findsNothing);
    });
  });

  group('أين يظهر الزرّ', () {
    tearDown(() => ProviderService.debugSet(null));

    test('برقم المشترك وحده، وبلا FTTH القديم — وايرث لنك وفايبر اكس والمُضافة خارج «كل الشركات» نعم', () {
      ProviderService.debugSet(null);
      expect(subscriberEditsAvailable(_sub()), isTrue);
      expect(subscriberEditsAvailable(_sub(idx: null)), isFalse);
      expect(subscriberEditsAvailable(_sub(idx: '')), isFalse);
      for (final p in ['earthlink', 'fiberx', 'nabd']) {
        ProviderService.debugSet(p);
        expect(subscriberEditsAvailable(_sub()), isTrue, reason: p);
      }
      ProviderService.debugSet('ftth');
      expect(subscriberEditsAvailable(_sub()), isFalse);
    });
  });

  group('«كل الشركات»', () {
    const kOpen = 'c0000000000a1';
    const kEl = 'c0000000000e1';
    const kFx = 'c0000000000b1';
    const kFt = 'c0000000000f1';
    const kKit = 'c0000000000c1';
    late _Srv srv;

    Future<void> up(WidgetTester t) async {
      srv = _Srv(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = srv;
      AccountApi.tokenSource = ({bool force = false}) async => 'acct';
      MergedMode.reset();
      MergedMode.fetchRaw = () async => {
            'routing': true,
            'writes': true,
            'companies': [
              {'key': kOpen, 'code': 'supernet', 'username': 'u0', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': 'supernet:12', 'ns': 'a', 'currency': 'IQD', 'color_index': 0},
              {'key': kEl, 'code': 'earthlink', 'provider': 'earthlink', 'username': 'u1', 'name': 'ايرث لنك', 'status': 'ok', 'admin_id': 'earthlink:77', 'ns': 'e', 'currency': 'IQD', 'color_index': 3},
              {'key': kFx, 'code': 'fiberx', 'provider': 'fiberx', 'username': 'u2', 'name': 'فايبر اكس', 'status': 'ok', 'admin_id': 'fiberx:9', 'ns': 'x', 'currency': 'IQD', 'color_index': 2},
              {'key': kFt, 'code': 'ftth', 'provider': 'ftth', 'username': 'u3', 'name': 'المشروع الوطني', 'status': 'ok', 'admin_id': 'ftth:5', 'ns': 'f', 'currency': 'IQD', 'color_index': 5},
              {'key': kKit, 'code': 'nabd', 'provider': 'kit', 'username': 'u4', 'name': 'نبض', 'status': 'ok', 'admin_id': 'nabd:3', 'ns': 'n', 'currency': 'IQD', 'color_index': 4},
            ],
          };
      expect(await t.runAsync(() => MergedMode.enter()), isTrue);
    }

    Future<void> down(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
      MergedMode.reset();
      await visualTearDown();
    }

    testWidgets('الزرّ لشركات الساس وايرث لنك والمُضافة — لا فايبر اكس ولا FTTH (جدول التوجيه لا يمرّرهما)', (t) async {
      await up(t);
      try {
        expect(subscriberEditsAvailable(_sub(key: kOpen)), isTrue);
        expect(subscriberEditsAvailable(_sub(key: kEl)), isTrue);
        expect(subscriberEditsAvailable(_sub(key: kKit)), isTrue);
        expect(subscriberEditsAvailable(_sub(key: kFx)), isFalse);
        expect(subscriberEditsAvailable(_sub(key: kFt)), isFalse);
      } finally {
        await down(t);
      }
    });

    testWidgets('القراءة من شركة الصفّ (x-company-key) — والعنوان يحمل اسمها', (t) async {
      await up(t);
      try {
        await pumpVisual(t, _narrow,
            home: (c) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                        onPressed: () => showSubscriberEditsSheet(c,
                            _sub(key: kEl, idx: '4410', username: 'el.u', first: 'عبد الرحمن محمّد', last: 'عبد الكريم الحسينيّ')),
                        child: const Text('افتح')),
                  ),
                ));
        await settle(t, seconds: 1);
        await t.tap(find.text('افتح'));
        for (var i = 0; i < 8; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(srv.edits, ['GET /api/v2/subscribers/4410/edits?username=el.u @$kEl']);
        expect(find.byKey(const ValueKey('sub-edit-901')), findsOneWidget);
        // اسم الشركة بعد اسمٍ طويل يلتفّ لا يُقصّ
        final sub = find.textContaining('«ايرث لنك»');
        expect(sub, findsOneWidget);
        expect(t.renderObject<RenderParagraph>(sub).didExceedMaxLines, isFalse);
      } finally {
        await down(t);
      }
    });
  });

  group('«اسمك في السجلات»', () {
    late _Srv srv;

    Future<void> openAlias(WidgetTester t, {String? alias, int getStatus = 200}) async {
      srv = _Srv(await visualSetUp(s1bSasOwner))
        ..alias = alias
        ..aliasGetStatus = getStatus;
      ApiClient.dio.httpClientAdapter = srv;
      t.platformDispatcher.textScaleFactorTestValue = 1.2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpVisual(t, _narrow,
          home: (c) => Scaffold(
                body: Center(child: ElevatedButton(onPressed: () => showManagerAliasSheet(c), child: const Text('افتح'))),
              ));
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 2);
    }

    bool saveEnabled(WidgetTester t) {
      final bar = t.widget<SheetFooterBar>(find.byType(SheetFooterBar));
      return bar.enabled && !bar.busy && bar.onPressed != null;
    }

    tearDown(visualTearDown);

    testWidgets('اسمٌ محفوظ: يظهر في الحقل و«يظهر الآن»، و«حفظ» معطّلٌ حتى يتغيّر — بعرض ٣٢٠ وخطّ ١٫٢', (t) async {
      await openAlias(t, alias: 'أبو علي');
      expect(t.takeException(), isNull);
      expect(srv.aliasGets, 1);
      expect(find.text('اسمك في السجلات'), findsOneWidget);
      expect(t.widget<TextField>(find.byKey(const ValueKey('alias-field'))).controller!.text, 'أبو علي');
      expect(find.textContaining('يظهر الآن: أبو علي', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('alias-clear')), findsOneWidget);
      expect(saveEnabled(t), isFalse);
      // سطر الرأس الثاني يسعه سطرٌ بعرض ٣٢٠ وخطّ ١٫٢ — لا «…»
      expect(t.renderObject<RenderParagraph>(find.text('بدل يوزر الصفحة')).didExceedMaxLines, isFalse);
      await shoot(t, s1bSasOwner, 'manager_alias_sheet', _narrow, srv.inner as VisualServer);
      await t.enterText(find.byKey(const ValueKey('alias-field')), 'أبو علي ');
      await t.pump();
      expect(saveEnabled(t), isFalse, reason: 'المسافة وحدها ليست تغييراً');
    });

    testWidgets('بلا اسم: «يظهر الآن» يوزر الصفحة — ثمّ حفظ اسمٍ ⇒ PUT مقصوصاً وتُغلق النافذة برسالة', (t) async {
      await openAlias(t);
      expect(find.textContaining('يظهر الآن: ${iso('mahdi')}', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('alias-clear')), findsNothing);
      expect(saveEnabled(t), isFalse);
      await t.enterText(find.byKey(const ValueKey('alias-field')), '  المكتب ');
      await t.pump();
      expect(saveEnabled(t), isTrue);
      await t.tap(find.text('حفظ'));
      await settle(t, seconds: 1);
      expect(srv.puts, ['المكتب']);
      expect(find.byType(ManagerAliasSheet), findsNothing);
      expect(find.text('حُفظ — تظهر عمليّاتك باسم «المكتب»'), findsOneWidget);
      await settle(t, seconds: 4);
    });

    testWidgets('رفض الخادم (422) ⇒ رسالته تحت الحقل والنافذة باقية — والكتابة تمسحها', (t) async {
      await openAlias(t);
      srv.putReply = (status: 422, body: {'success': false, 'code': 'ALIAS_INVALID', 'message': 'الاسم بلا روابط ولا @'});
      await t.enterText(find.byKey(const ValueKey('alias-field')), 'a@b');
      await t.pump();
      await t.tap(find.text('حفظ'));
      await settle(t, seconds: 1);
      expect(srv.puts, ['a@b']);
      expect(find.byType(ManagerAliasSheet), findsOneWidget);
      expect(find.text('الاسم بلا روابط ولا @'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.enterText(find.byKey(const ValueKey('alias-field')), 'ab');
      await t.pump();
      expect(find.byKey(const ValueKey('alias-save-error')), findsNothing);
    });

    testWidgets('«مسح الاسم» ⇒ PUT فارغ ⇒ «رجعت عمليّاتك تظهر بيوزر الصفحة»', (t) async {
      await openAlias(t, alias: 'أبو علي');
      await t.tap(find.byKey(const ValueKey('alias-clear')));
      await settle(t, seconds: 1);
      expect(srv.puts, ['']);
      expect(find.byType(ManagerAliasSheet), findsNothing);
      expect(find.text('رجعت عمليّاتك تظهر بيوزر الصفحة'), findsOneWidget);
      await settle(t, seconds: 4);
    });

    testWidgets('تعذّرت القراءة ⇒ رسالة و«إعادة المحاولة» — و«حفظ» معطّل حتى تُقرأ', (t) async {
      await openAlias(t, alias: 'أبو علي', getStatus: 409);
      expect(find.byKey(const ValueKey('alias-load-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('alias-field')), findsNothing);
      expect(saveEnabled(t), isFalse);
      srv.aliasGetStatus = 200;
      await t.tap(find.text('إعادة المحاولة'));
      await settle(t, seconds: 1);
      expect(srv.aliasGets, 2);
      expect(t.widget<TextField>(find.byKey(const ValueKey('alias-field'))).controller!.text, 'أبو علي');
    });

    testWidgets('الحقل لا يقبل أكثر من ٤٠ حرفاً', (t) async {
      await openAlias(t);
      await t.enterText(find.byKey(const ValueKey('alias-field')), 'ا' * 55);
      await t.pump();
      expect(t.widget<TextField>(find.byKey(const ValueKey('alias-field'))).controller!.text.length, ManagerAliasApi.maxChars);
    });
  });

  group('صفّ الإعدادات', () {
    Future<void> openSettings(WidgetTester t) async {
      final nav = GlobalKey<NavigatorState>();
      await pumpVisual(t, phoneTall, navigatorKey: nav, home: (_) => Scaffold(backgroundColor: AppColors.bg));
      await settle(t, seconds: 1);
      await settle(t, seconds: 1);
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
      await settle(t, seconds: 2);
    }

    Future<void> drain(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 25));
    }

    testWidgets('المالك: «اسمك في السجلات» مفتوحٌ ويفتح نافذته', (t) async {
      final srv = _Srv(await visualSetUp(s1bSasOwner))..alias = 'أبو علي';
      ApiClient.dio.httpClientAdapter = srv;
      try {
        await openSettings(t);
        final row = find.byKey(const ValueKey('settings-log-name'));
        expect(row, findsOneWidget);
        expect(find.descendant(of: row, matching: find.text('اسمك في السجلات')), findsOneWidget);
        await t.ensureVisible(row);
        await t.tap(row);
        await settle(t, seconds: 2);
        expect(find.byType(ManagerAliasSheet), findsOneWidget);
        expect(srv.aliasGets, 1);
        await drain(t);
      } finally {
        await visualTearDown();
      }
    });

    testWidgets('FTTH القديم: لا صفّ (بوّابته لا تمرّر المسار)', (t) async {
      final srv = _Srv(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = srv;
      ProviderService.debugSet('ftth');
      try {
        await openSettings(t);
        expect(find.byKey(const ValueKey('settings-log-name')), findsNothing);
        await drain(t);
      } finally {
        await visualTearDown();
      }
    });
  });

  group('الاسم المستعار في السجلات', () {
    test('سجلّ العمليّات والتقرير الماليّ: admin_name قبل admin_username، وبلاه كما كان', () {
      final base = {'action_type': 'SUBSCRIBER_ACTIVATE', 'created_at': '2026-11-20T10:00:00Z', 'id': 5, 'amount': 25000};
      expect(ActivityRow.fromJson({...base, 'admin_name': 'أبو علي', 'admin_username': 'admin@demo'})!.adminUsername, 'أبو علي');
      expect(ActivityRow.fromJson({...base, 'admin_username': 'admin@demo'})!.adminUsername, 'admin@demo');
      expect(FinanceLog.fromJson({...base, 'admin_name': 'أبو علي', 'admin_username': 'admin@demo'})!.adminUsername, 'أبو علي');
      expect(FinanceLog.fromJson({...base, 'admin_username': 'admin@demo'})!.adminUsername, 'admin@demo');
    });

    testWidgets('آخر النشاطات بالرئيسيّة: «المدير: أبو علي» — والموظّف باسمه كما كان', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              height: 600,
              child: RecentActivities(items: [
                {
                  'action_type': 'SUBSCRIBER_EDIT',
                  'action_description': 'تعديل بيانات المشترك',
                  'target_name': 'x@y',
                  'admin_username': 'admin@demo',
                  'admin_name': 'أبو علي',
                  'created_at': '2026-11-20T09:00:00Z',
                },
                {
                  'action_type': 'SUBSCRIBER_EDIT',
                  'action_description': 'تعديل بيانات المشترك',
                  'target_name': 'z@y',
                  'admin_username': 'admin@demo',
                  'acting_employee_full_name': 'سارة',
                  'created_at': '2026-11-20T08:00:00Z',
                },
              ]),
            ),
          ),
        ),
      ));
      await t.pump();
      expect(find.text('المدير: أبو علي'), findsOneWidget);
      expect(find.text('الموظف: سارة'), findsOneWidget);
      expect(find.textContaining('admin@demo'), findsNothing);
    });
  });
}
