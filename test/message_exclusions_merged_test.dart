import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/message_exclusions_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/message_exclusion_card.dart';
import 'package:rad_mysvcs/screens/whatsapp/message_exclusions_screen.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/widgets/company_tag.dart';

import 'sim_el/sim_harness.dart';

/// «المستثنون من الرسائل» في «كل الشركات» (١٥ نوفمبر — المالك: «نعم هم سويها»): قائمة كلّ شركةٍ بطلبها الموجَّه ومفتاحها (جرس
/// صفّها وكرت مشتركها)، وإيقاف رسائل مشترك صفٍّ والسماح بها بالمسار ذي الرقم بغلاف شركته: مرجع نافذته أوّلاً (GET المشترك) ثمّ
/// PUT/DELETE /api/v2/subscribers/:idx/message-exclusion بمفتاحها ومرجعه — ولا شيء يذهب للشركة المفتوحة ولا لشركةٍ أخرى. وصفحة
/// «المستثنون» تعرض مستثني الشركات معاً، كلٌّ باسم شركته.
const _v = SimVariant(390, dark: false);
const _kA = 'c0000000000aa';
const _kB = 'c0000000000bb';
const _kC = 'c0000000000cc';
const _all = MessageExclusionsApi.allPath;

const _groups = [
  {'key': 'all', 'label': 'كلّ الرسائل', 'hint': 'لا تصله أيّ رسالة من النظام — ولا اليدويّة'},
  {'key': 'ops', 'label': 'التفعيل والتسديد', 'hint': 'إشعار التفعيل والتمديد وتأكيد التسديد والترحيب'},
  {'key': 'reminders', 'label': 'التذكيرات', 'hint': 'قرب الانتهاء، انتهاء الاشتراك، وتذكير الدين'},
  {'key': 'broadcast', 'label': 'التبليغات', 'hint': 'التبليغ العامّ بكلّ أنواعه'},
  {'key': 'conn', 'label': 'تنبيهات الاتصال', 'hint': 'تنبيه المشترك عن اتّصاله (الإشارة، الكيبل…)'},
];
const _labels = {'all': 'كلّ الرسائل', 'ops': 'التفعيل والتسديد', 'reminders': 'التذكيرات', 'broadcast': 'التبليغات', 'conn': 'تنبيهات الاتصال'};

Map<String, Object?> _entry(List<String> groups, {String? note, String? name, String idx = '1520', String at = '2026-11-14T18:20:00.000Z'}) => {
      'idx': idx,
      'name': name ?? 'علي حسن',
      'phone': '07701234567',
      'groups': groups,
      'label': groups.map((g) => _labels[g]).join('، '),
      'note': note,
      'by': 'owner',
      'at': at,
    };

Map<String, Object?> _reply({Map<String, Object?> exclusions = const {}, bool enabled = true, bool canManage = true}) => {
      'success': true,
      'enabled': enabled,
      'can_manage': canManage,
      'groups': _groups,
      'count': exclusions.length,
      'max': 5000,
      'exclusions': exclusions,
    };

Subscriber _sub({String? companyKey, String username = 'ali.hasan', String idx = '1520', String name = 'علي حسن'}) => Subscriber.fromJson({
      'idx': idx,
      'username': username,
      'firstname': name,
      'phone': '07701234567',
      'expiration': '2026-12-01 18:00:00',
      'remaining_days': 17,
    }).withCompany(companyKey);

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

String _refOf(String key, String idx) => 'r_${key.substring(1)}x${idx.padLeft(9, '0')}';

/// خادمٌ للطلبات الموجَّهة (بـx-company-key): يصدي المفتاح، يسكّ مرجع النافذة على GET المشترك، ويحفظ قائمة مستثني كلّ شركةٍ بمفتاحها
/// — الحفظ والإزالة بلا المرجع الصحيح يُرفضان كما يرفضهما الخادم قبل المعالج. وما بلا مفتاح يمضي للخادم الوهميّ العاديّ (المفتوحة).
class _Routed implements HttpClientAdapter {
  _Routed(this.inner);
  final HttpClientAdapter inner;
  final requests = <RequestOptions>[];

  /// قائمة كلّ شركة: ردّ /all كما هو، أو رقم حالةٍ لرفضٍ موجَّه.
  final Map<String, Object> lists = {};

  /// GET المشترك لا يسكّ مرجعاً (المشترك لم يعد في الشركة…).
  bool mint = true;

  List<RequestOptions> of(String method, String pathEnd, [String? key]) => [
        for (final o in requests)
          if (o.method == method && o.uri.path.endsWith(pathEnd) && (key == null || o.headers['x-company-key'] == key)) o,
      ];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final key = o.headers['x-company-key'] as String?;
    if (key == null) return inner.fetch(o, requestStream, cancelFuture);
    requests.add(o);
    final h = <String, List<String>>{'x-company-key': [key]};
    final path = o.uri.path;
    if (o.method == 'GET' && path == _all) {
      final l = lists[key];
      if (l is int) return _json(l, {'success': false, 'code': 'COMPANY_UPSTREAM_UNAVAILABLE', 'message': 'تعذّر جلب بيانات الشركة الآن'}, headers: h);
      return _json(200, l ?? _reply(enabled: false), headers: h);
    }
    final detail = RegExp(r'^/api/v2/subscribers/(\d+)$').firstMatch(path);
    if (o.method == 'GET' && detail != null) {
      if (!mint) return _json(404, {'success': false, 'code': 'SUBSCRIBER_NOT_FOUND', 'message': 'المشترك غير موجود'}, headers: h);
      return _json(200, {'success': true, 'data': {'idx': detail.group(1), 'username': 'u'}},
          headers: {...h, 'x-company-ref': [_refOf(key, detail.group(1)!)]});
    }
    final mx = RegExp(r'^/api/v2/subscribers/(\d+)/message-exclusion$').firstMatch(path);
    if (mx != null && (o.method == 'PUT' || o.method == 'DELETE')) {
      final idx = mx.group(1)!;
      final ref = o.headers['x-company-ref'];
      if (ref == null) {
        return _json(409, {'success': false, 'code': 'COMPANY_REF_REQUIRED', 'message': 'تغيّرت بيانات النافذة — أعد فتح المشترك (لم يُنفَّذ شيء)'}, headers: h);
      }
      if (ref != _refOf(key, idx)) {
        return _json(409, {'success': false, 'code': 'COMPANY_REF_MISMATCH', 'message': 'تغيّرت بيانات النافذة — أعد فتح المشترك (لم يُنفَّذ شيء)'}, headers: h);
      }
      final l = lists[key];
      final ex = Map<String, Object?>.from(((l is Map ? l['exclusions'] : null) as Map?) ?? const {});
      if (o.method == 'DELETE') {
        final u = '${o.queryParameters['username']}';
        final had = ex.remove(u) != null;
        if (l is Map) lists[key] = {...l, 'exclusions': ex, 'count': ex.length};
        return _json(200, {'success': true, 'removed': had}, headers: h);
      }
      final b = Map<String, dynamic>.from(o.data as Map);
      final groups = [for (final g in b['groups'] as List) '$g'];
      final e = _entry(groups, note: '${b['note'] ?? ''}'.isEmpty ? null : '${b['note']}', name: b['name'] as String?, idx: idx);
      ex['${b['username']}'] = e;
      if (l is Map) lists[key] = {...l, 'exclusions': ex, 'count': ex.length};
      return _json(200, {'success': true, 'exclusion': e}, headers: h);
    }
    return _json(200, {'success': true}, headers: h);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late SimServer server;
  late _Routed srv;
  final origToken = AccountApi.tokenSource;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'myservices'});
    srv = _Routed(server);
    ApiClient.dio.httpClientAdapter = srv;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct-1';
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
    MessageExclusionsState.reset();
    MergedMode.reset();
    CompanyRoute.debugReset();
  });

  tearDown(() {
    AccountApi.tokenSource = origToken;
    PermissionsService.debugReset();
    MessageExclusionsState.reset();
    MergedMode.reset();
    CompanyRoute.debugReset();
  });

  /// يدخل «كل الشركات» بشركتين سليمتين (ألف المفتوحة وباء) وثالثةٍ تحتاج دخولاً.
  Future<void> enterMerged(WidgetTester t) async {
    MergedMode.fetchRaw = () async => {
          'routing': true,
          'writes': true,
          'companies': [
            {'key': _kA, 'code': 'supernet', 'username': 'admin@a', 'name': 'شركة ألف', 'status': 'ok', 'admin_id': '2', 'ns': 'nA'},
            {'key': _kB, 'code': 'jt', 'username': 'admin@b', 'name': 'شركة باء', 'status': 'ok', 'admin_id': 'jt:7', 'ns': 'nB'},
            {'key': _kC, 'code': 'x', 'username': 'admin@c', 'name': 'شركة جيم', 'status': 'needs_login', 'admin_id': 'x:9', 'ns': 'nC'},
          ],
        };
    await t.runAsync(() => MergedMode.load(fresh: true));
    MergedMode.active.value = true;
  }

  /// يقرأ قوائم الشركات داخل اختبار واجهة: الطلبات تُطلق ثمّ يُضخّ الوقت (لا انتظار مباشر لشبكةٍ داخل الساعة الوهميّة).
  Future<void> loadCo(WidgetTester t, List<String> keys) async {
    unawaited(MessageExclusionsState.ensureCompanies(keys, force: true));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    await t.pump();
  }

  Future<void> openSheet(WidgetTester t, {required Subscriber sub}) async {
    await pumpSim(t, _v,
        home: (_) => simLauncher((ctx) => showMessageExclusionSheet(ctx, subject: mxSubjectOf(sub), companyKey: sub.companyKey)));
    await loadCo(t, [_kA, _kB]);
    await simOpen(t);
  }

  test('قائمة كلّ شركةٍ بطلبها الموجَّه ومفتاحها: لا تختلط شركتان ولا المفتوحة، بتوكن الحساب وحده، وتُقرأ بمدّتها', () async {
    srv.lists[_kA] = _reply(exclusions: {'Ali.Hasan': _entry(['all'], note: 'طلب عدم الإزعاج')});
    srv.lists[_kB] = _reply(exclusions: {'omar': _entry(['reminders', 'broadcast'], name: 'عمر', idx: '7')}, canManage: false);
    server.reply('GET', _all, 200, _reply(exclusions: {'open.user': _entry(['conn'], name: 'مفتوح', idx: '3')}));

    await MessageExclusionsState.ensureCompanies([_kA, _kB, _kA]);
    final asked = srv.of('GET', _all);
    expect(asked.map((o) => o.headers['x-company-key']), unorderedEquals([_kA, _kB]), reason: 'طلبٌ واحد لكلّ شركة — المكرَّر مرّة');
    for (final o in asked) {
      expect(o.headers['x-account-token'], 'acct-1');
      expect(o.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')), reason: 'لا توكن شركةٍ على طلبٍ موجَّه');
    }
    expect(server.calls('GET', _all), isEmpty, reason: 'لا طلب للمفتوحة');

    // كلّ صفٍّ بقائمة شركته — اليوزر نفسه في شركةٍ أخرى ليس مستثنى
    expect(MessageExclusionsState.ofRow(_kA, 'ali.hasan')!.all, isTrue);
    expect(MessageExclusionsState.ofRow(_kB, 'ali.hasan'), isNull);
    expect(MessageExclusionsState.ofRow(_kB, 'OMAR')!.groups, ['reminders', 'broadcast']);
    expect(MessageExclusionsState.ofRow(_kA, 'omar'), isNull);
    expect(MessageExclusionsState.ofRow(null, 'ali.hasan'), isNull, reason: 'المفتوحة لم تُقرأ بعد — لا تأخذ قائمة شركةٍ بمفتاحها');
    expect([MessageExclusionsState.enabledFor(_kA), MessageExclusionsState.canManageFor(_kA)], [true, true]);
    expect([MessageExclusionsState.enabledFor(_kB), MessageExclusionsState.canManageFor(_kB)], [true, false]);
    expect([MessageExclusionsState.enabledFor(_kC), MessageExclusionsState.canManageFor(_kC)], [false, false], reason: 'لم تُقرأ');

    // المفتوحة بطلبها هي (بلا مفتاح) — ولا تمسّ قوائم الشركات
    await MessageExclusionsState.ensureFreshFor(null);
    expect(server.calls('GET', _all), hasLength(1));
    expect(MessageExclusionsState.ofRow(null, 'open.user'), isNotNull);
    expect(MessageExclusionsState.ofRow(_kA, 'open.user'), isNull);

    // ضمن المدّة لا طلب؛ و[force] يقرأ الآن
    await MessageExclusionsState.ensureCompanies([_kA, _kB]);
    expect(srv.of('GET', _all), hasLength(2));
    await MessageExclusionsState.ensureCompanies([_kA], force: true);
    expect(srv.of('GET', _all, _kA), hasLength(2));
    // مفتاحٌ غير صالح ⇒ لا طلب (وإلّا ذهب للمفتوحة باسم شركةٍ أخرى)
    await MessageExclusionsState.ensureFreshFor('not-a-key');
    expect(srv.of('GET', _all), hasLength(3));
    expect(server.calls('GET', _all), hasLength(1));

    // ما يُعرض في الإعدادات وصفحة القائمة: العاديّ ⇒ المفتوحة وحدها؛ «كل الشركات» ⇒ شركاته بترتيبها (ما قُرئ منها)
    expect(MessageExclusionsState.viewFor(null).map((v) => (v.key, v.snap.count)), [(null, 1)]);
    expect(MessageExclusionsState.viewFor([_kA, _kB, _kC]).map((v) => (v.key, v.snap.count)), [(_kA, 1), (_kB, 1)]);

    MessageExclusionsState.reset();
    expect(MessageExclusionsState.companies.value, isEmpty, reason: 'الخروج لا يُبقي قوائم شركات المدير السابق');
    expect(MessageExclusionsState.ofRow(_kA, 'ali.hasan'), isNull);
  });

  test('شركةٌ تعذّرت قراءتها: لا علامة ولا زرّ لصفوفها، ولا يُعاد الطلب فوراً؛ والميزة المطفأة لشركةٍ ⇒ لا شيء لها', () async {
    srv.lists[_kA] = 409;
    srv.lists[_kB] = _reply(exclusions: {'omar': _entry(['all'])}, enabled: false);
    await MessageExclusionsState.ensureCompanies([_kA, _kB]);
    expect(MessageExclusionsState.snapshotFor(_kA), isNull);
    expect(MessageExclusionsState.enabledFor(_kA), isFalse);
    expect(MessageExclusionsState.enabledFor(_kB), isFalse);
    expect(MessageExclusionsState.ofRow(_kB, 'omar'), isNull, reason: 'الميزة مطفأةٌ لها ⇒ لا مستثنين يُعرضون');
    await MessageExclusionsState.ensureFreshFor(_kA);
    expect(srv.of('GET', _all, _kA), hasLength(1), reason: 'مهلةٌ بعد التعذّر');
    // ثمّ نجحت: تظهر — وآخر قراءةٍ ناجحة لا يمحوها تعذّرٌ لاحق
    srv.lists[_kA] = _reply(exclusions: {'ali.hasan': _entry(['all'])});
    await MessageExclusionsState.ensureFreshFor(_kA, force: true);
    expect(MessageExclusionsState.ofRow(_kA, 'ali.hasan'), isNotNull);
    srv.lists[_kA] = 409;
    await MessageExclusionsState.ensureFreshFor(_kA, force: true);
    expect(MessageExclusionsState.ofRow(_kA, 'ali.hasan'), isNotNull);
  });

  test('المسار ذو الرقم كتابةٌ بمرجع النافذة عند المعترض، والضمنيّة على مشتركٍ في «كل الشركات» لا تُرسل', () {
    const p = '/api/v2/subscribers/1520/message-exclusion';
    for (final m in ['PUT', 'DELETE']) {
      final r = CompanyRefs.requireOf(m, p)!;
      expect((r.idx, r.kind), ('1520', CompanyRefKind.subject), reason: m);
    }
    expect(CompanyRefs.requireOf('GET', p), isNull);
    expect(CompanyRefs.requireOf('PUT', MessageExclusionsApi.path), isNull, reason: 'المسار بلا رقم للمفتوحة وحدها — لا مرجع');
    expect(CompanyRefs.mintOf('GET', p), isNull, reason: 'لا يسكّ مرجعاً');
    // المعترض: كتابةٌ ضمنيّة على مسار مشترك و«كل الشركات» فعّال ⇒ ترفض محلّيّاً؛ وبمفتاح صفّها ⇒ له
    CompanyRoute.mergedActive = () => true;
    addTearDown(() => CompanyRoute.mergedActive = null);
    expect(CompanyRoute.decide(RequestOptions(path: p, method: 'PUT')).refused, isTrue);
    expect(CompanyRoute.decide(RequestOptions(path: p, method: 'PUT', extra: const {'companyKey': _kB})).key, _kB);
    expect(MessageExclusionsApi.routedIdx(' 1520 '), '1520');
    for (final bad in [null, '', 'abc', '8f1c-2a', '1234567890123', '-5']) {
      expect(MessageExclusionsApi.routedIdx(bad), isNull, reason: '$bad');
    }
  });

  testWidgets('إيقافٌ لمشترك صفّ شركةٍ: مرجع نافذته ثمّ PUT بالمسار ذي الرقم بمفتاحها — والحال لشركته وحدها', (t) async {
    srv.lists[_kA] = _reply();
    srv.lists[_kB] = _reply();
    await enterMerged(t);
    await openSheet(t, sub: _sub(companyKey: _kB));
    expect(find.text('علي حسن · «شركة باء»'), findsOneWidget, reason: 'الشركة مسمّاةٌ في رأس الورقة قبل الحفظ');
    await t.tap(find.text('إيقاف الرسائل').last);
    await t.pumpAndSettle();

    final get = srv.of('GET', '/api/v2/subscribers/1520').single;
    final put = srv.of('PUT', '/api/v2/subscribers/1520/message-exclusion').single;
    expect(srv.requests.indexOf(get) < srv.requests.indexOf(put), isTrue, reason: 'المرجع قبل الكتابة');
    expect([get.headers['x-company-key'], put.headers['x-company-key']], [_kB, _kB]);
    expect(put.headers['x-company-ref'], _refOf(_kB, '1520'));
    expect(put.headers['x-account-token'], 'acct-1');
    expect(Map<String, dynamic>.from(put.data as Map),
        {'username': 'ali.hasan', 'idx': '1520', 'name': 'علي حسن', 'phone': '07701234567', 'groups': ['all'], 'note': ''});
    expect(server.requests.where((o) => o.method != 'GET'), isEmpty, reason: 'لا كتابة للشركة المفتوحة');
    expect(srv.of('PUT', MessageExclusionsApi.path), isEmpty, reason: 'ولا بالمسار بلا رقم');

    expect(MessageExclusionsState.ofRow(_kB, 'ali.hasan')!.all, isTrue);
    expect(MessageExclusionsState.ofRow(_kA, 'ali.hasan'), isNull, reason: 'اليوزر نفسه في شركةٍ أخرى لم يُمسّ');
    expect(MessageExclusionsState.ofRow(null, 'ali.hasan'), isNull);
    expect(find.byKey(const ValueKey('mx-all')), findsNothing, reason: 'الورقة أُغلقت');
    await simDrain(t);
  });

  testWidgets('تعديل قائم لصفّ شركة ثمّ «السماح»: PUT بأنواعه ثمّ DELETE باليوزر — كلاهما بالمسار ذي الرقم ومرجعه', (t) async {
    srv.lists[_kA] = _reply(exclusions: {'ali.hasan': _entry(['all'])});
    srv.lists[_kB] = _reply(exclusions: {'ali.hasan': _entry(['reminders'], note: 'قريب')});
    await enterMerged(t);
    await openSheet(t, sub: _sub(companyKey: _kB));
    expect(find.text('الرسائل الموقوفة'), findsOneWidget);
    expect(t.widget<Checkbox>(find.descendant(of: find.byKey(const ValueKey('mx-group-reminders')), matching: find.byType(Checkbox))).value, isTrue,
        reason: 'أنواعه من قائمة شركته (باء) لا من ألف');
    await t.tap(find.byKey(const ValueKey('mx-group-conn')));
    await t.pumpAndSettle();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    final put = srv.of('PUT', '/api/v2/subscribers/1520/message-exclusion', _kB).single;
    expect((put.data as Map)['groups'], ['reminders', 'conn']);
    expect(MessageExclusionsState.ofRow(_kB, 'ali.hasan')!.groups, ['reminders', 'conn']);
    expect(MessageExclusionsState.ofRow(_kA, 'ali.hasan')!.all, isTrue, reason: 'شركة ألف كما هي');
    expect(srv.of('GET', '/api/v2/subscribers/1520'), hasLength(1));
    await simDrain(t);

    await simOpen(t);
    await t.ensureVisible(find.byKey(const ValueKey('mx-allow')));
    await t.tap(find.byKey(const ValueKey('mx-allow')));
    await t.pumpAndSettle();
    final del = srv.of('DELETE', '/api/v2/subscribers/1520/message-exclusion', _kB).single;
    expect(del.queryParameters['username'], 'ali.hasan');
    expect(del.headers['x-company-ref'], _refOf(_kB, '1520'));
    expect(srv.of('GET', '/api/v2/subscribers/1520'), hasLength(1), reason: 'المرجع المحفوظ يكفي — لا قراءةٌ ثانية');
    expect(MessageExclusionsState.ofRow(_kB, 'ali.hasan'), isNull);
    expect(MessageExclusionsState.ofRow(_kA, 'ali.hasan'), isNotNull);
    expect(server.requests.where((o) => o.method != 'GET'), isEmpty);
    await simDrain(t);
  });

  testWidgets('بلا مرجع نافذة (المشترك لم يعد في الشركة) ⇒ رفض الخادم برسالته، والورقة باقية والحال لا تتغيّر', (t) async {
    srv.lists[_kA] = _reply();
    srv.lists[_kB] = _reply();
    srv.mint = false;
    await enterMerged(t);
    await openSheet(t, sub: _sub(companyKey: _kB));
    await t.tap(find.text('إيقاف الرسائل').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('تغيّرت بيانات النافذة — أعد فتح المشترك (لم يُنفَّذ شيء)'), findsOneWidget);
    expect(find.byKey(const ValueKey('mx-all')), findsOneWidget);
    expect(MessageExclusionsState.ofRow(_kB, 'ali.hasan'), isNull);
    await simDrain(t);
  });

  testWidgets('رقمٌ لا يُوجَّه (غير رقميّ) لصفّ شركة ⇒ لا طلب أصلاً ورسالةٌ تقول من أين', (t) async {
    srv.lists[_kA] = _reply();
    srv.lists[_kB] = _reply();
    await enterMerged(t);
    await openSheet(t, sub: _sub(companyKey: _kB, idx: '8f1c-2a7e'));
    await t.tap(find.text('إيقاف الرسائل').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(MessageExclusionsApi.noRoutedIdx), findsOneWidget);
    expect(srv.requests.where((o) => o.method != 'GET'), isEmpty);
    expect(server.requests.where((o) => o.method != 'GET'), isEmpty, reason: 'ولا للمفتوحة');
    await simDrain(t);
  });

  testWidgets('صفٌّ بلا مفتاح في «كل الشركات» (فُتح من إشعار): للصفحة المفتوحة صراحةً بالمسار بلا رقم كما كان', (t) async {
    server.reply('GET', _all, 200, _reply());
    server.on('PUT', MessageExclusionsApi.path, (o) => SimReply(200, {'success': true, 'exclusion': _entry(['all'])}));
    srv.lists[_kA] = _reply();
    await enterMerged(t);
    await pumpSim(t, _v, home: (_) => simLauncher((ctx) => showMessageExclusionSheet(ctx, subject: mxSubjectOf(_sub()))));
    unawaited(MessageExclusionsState.ensureFresh(force: true));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    await simOpen(t);
    await t.tap(find.text('إيقاف الرسائل').last);
    await t.pumpAndSettle();
    expect(server.calls('PUT', MessageExclusionsApi.path), hasLength(1));
    expect(srv.requests.where((o) => o.method != 'GET'), isEmpty, reason: 'لا طلب موجَّه');
    expect(MessageExclusionsState.ofRow(null, 'ali.hasan')!.all, isTrue);
    expect(MessageExclusionsState.ofRow(_kA, 'ali.hasan'), isNull);
    await simDrain(t);
  });

  testWidgets('كرت صفحة المشترك لصفّ شركة: من قائمة شركته هي — وصفّ شركةٍ أخرى باليوزر نفسه بلا كرت', (t) async {
    srv.lists[_kA] = _reply(exclusions: {'ali.hasan': _entry(['reminders', 'broadcast'], note: 'طلب عدم الإزعاج')});
    srv.lists[_kB] = _reply(canManage: false);
    server.reply('GET', _all, 200, _reply(exclusions: {'ali.hasan': _entry(['conn'])}));
    await enterMerged(t);
    await loadCo(t, [_kA, _kB]);
    var edits = 0;
    Widget page(Subscriber s, {bool locked = false}) =>
        Scaffold(body: ListView(children: [MessageExclusionCard(sub: s, pageLocked: locked, onEdit: () => edits++)]));
    for (final v in const [SimVariant(320, dark: false), SimVariant(480, dark: true)]) {
      t.platformDispatcher.textScaleFactorTestValue = 1.2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpSim(t, v, home: (_) => page(_sub(companyKey: _kA)));
      expect(find.byKey(const ValueKey('mx-card')), findsOneWidget);
      expect(find.textContaining('التذكيرات، التبليغات', findRichText: true), findsOneWidget, reason: 'قائمة ألف لا المفتوحة');
      expect(find.text('طلب عدم الإزعاج'), findsOneWidget);
      expect(t.takeException(), isNull, reason: 'لا خروج نصّ على ${v.tag} بخطّ ١٫٢');
    }
    await t.tap(find.text('تعديل'));
    expect(edits, 1);
    await pumpSim(t, _v, home: (_) => page(_sub(companyKey: _kB)));
    expect(find.byKey(const ValueKey('mx-card')), findsNothing, reason: 'اليوزر نفسه في شركة باء غير مستثنى');
    await pumpSim(t, _v, home: (_) => page(_sub(companyKey: _kC)));
    expect(find.byKey(const ValueKey('mx-card')), findsNothing, reason: 'قائمة شركته لم تُقرأ');
    // صفحةٌ موقوفة الكتابة («كل الصفحات» للموظّف): الكرت ظاهرٌ و«تعديل» بمكانه مقفل
    await pumpSim(t, _v, home: (_) => page(_sub(companyKey: _kA), locked: true));
    expect(t.widget<TextButton>(find.ancestor(of: find.text('تعديل'), matching: find.bySubtype<TextButton>())).onPressed, isNull);
    // حين تصل قائمة شركةٍ بعد فتح الصفحة يظهر كرتها (الكرت يسمع الحال)
    await pumpSim(t, _v, home: (_) => page(_sub(companyKey: _kB, username: 'late.one')));
    expect(find.byKey(const ValueKey('mx-card')), findsNothing);
    srv.lists[_kB] = _reply(exclusions: {'late.one': _entry(['all'])});
    await loadCo(t, [_kB]);
    expect(find.byKey(const ValueKey('mx-card')), findsOneWidget);
  });

  testWidgets('صفحة «المستثنون» في «كل الشركات»: مستثنو الشركات معاً باسم شركة كلٍّ، و«السماح» لشركة الصفّ نفسها', (t) async {
    srv.lists[_kA] = _reply(exclusions: {
      'ali.hasan': _entry(['all'], at: '2026-11-14T18:20:00.000Z'),
      'sara': _entry(['conn'], name: 'سارة', idx: '31', at: '2026-11-14T10:00:00.000Z'),
    });
    srv.lists[_kB] = _reply(exclusions: {'ali.hasan': _entry(['reminders'], name: 'علي الثاني', idx: '77', note: 'قريب', at: '2026-11-13T09:00:00.000Z')});
    server.reply('GET', _all, 200, _reply(exclusions: {'open.only': _entry(['all'], name: 'للمفتوحة', idx: '5')}));
    await enterMerged(t);
    t.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSim(t, const SimVariant(320, dark: false), home: (_) => const MessageExclusionsScreen());
    expect(srv.of('GET', _all).map((o) => o.headers['x-company-key']), unorderedEquals([_kA, _kB]), reason: 'السليمة وحدها — جيم تحتاج دخولاً');
    expect(server.calls('GET', _all), isEmpty, reason: 'قائمة المفتوحة بلا مفتاح لا تُضاف (شركتها معروضةٌ بمفتاحها)');
    expect(find.byKey(const ValueKey('mx-merged-note')), findsOneWidget);
    expect(find.text('3 مستثنى'), findsOneWidget);
    expect(find.byKey(const ValueKey('mx-row-$_kA|ali.hasan')), findsOneWidget);
    expect(find.byKey(const ValueKey('mx-row-$_kA|sara')), findsOneWidget);
    expect(find.byKey(const ValueKey('mx-row-$_kB|ali.hasan')), findsOneWidget, reason: 'اليوزر نفسه في شركتين صفّان');
    expect(find.text('للمفتوحة'), findsNothing);
    // شارة الشركة على كلّ صفّ
    final tagB = t.widget<CompanyTag>(find.byKey(const ValueKey('mx-co-$_kB|ali.hasan')));
    expect(tagB.companyKey, _kB);
    expect(find.descendant(of: find.byKey(const ValueKey('mx-row-$_kB|ali.hasan')), matching: find.text('شركة باء')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('mx-row-$_kA|sara')), matching: find.text('شركة ألف')), findsOneWidget);
    expect(t.takeException(), isNull, reason: 'لا خروج نصّ على ٣٢٠ بخطّ ١٫٢');

    await t.ensureVisible(find.byKey(const ValueKey('mx-allow-$_kB|ali.hasan')));
    await t.tap(find.byKey(const ValueKey('mx-allow-$_kB|ali.hasan')));
    await t.pumpAndSettle();
    expect(find.text('تعود رسائل النظام تصل «علي الثاني · «شركة باء»»؟'), findsOneWidget, reason: 'التأكيد يسمّي الشركة');
    await t.tap(find.byKey(const ValueKey('mx-allow-confirm')));
    await t.pumpAndSettle();
    final del = srv.of('DELETE', '/api/v2/subscribers/77/message-exclusion').single;
    expect([del.headers['x-company-key'], del.queryParameters['username'], del.headers['x-company-ref']], [_kB, 'ali.hasan', _refOf(_kB, '77')]);
    expect(srv.of('GET', '/api/v2/subscribers/77', _kB), hasLength(1), reason: 'مرجع النافذة سُكّ قبلها');
    expect(find.byKey(const ValueKey('mx-row-$_kB|ali.hasan')), findsNothing);
    expect(find.byKey(const ValueKey('mx-row-$_kA|ali.hasan')), findsOneWidget, reason: 'مستثنى ألف باليوزر نفسه باقٍ');
    expect(find.text('2 مستثنى'), findsOneWidget);
    expect(server.requests.where((o) => o.method != 'GET'), isEmpty, reason: 'لا كتابة للمفتوحة');
    await simDrain(t);
  });

  testWidgets('صفحة «المستثنون» في «كل الشركات»: البحث باسم الشركة، وشركةٌ لا يُدير فيها صفوفها بلا أزرار، وتعذّر الكلّ ⇒ «تعذّر» لا دائرة', (t) async {
    final many = <String, Object?>{
      for (var i = 0; i < 7; i++) 'a$i': _entry(['all'], name: 'ألفيّ $i', idx: '$i'),
    };
    srv.lists[_kA] = _reply(exclusions: many);
    srv.lists[_kB] = _reply(exclusions: {'b0': _entry(['ops'], name: 'بائيّ', idx: '90')}, canManage: false);
    await enterMerged(t);
    await pumpSim(t, _v, home: (_) => const MessageExclusionsScreen());
    expect(find.text('8 مستثنى'), findsOneWidget);
    expect(find.byKey(const ValueKey('mx-allow-$_kB|b0')), findsNothing, reason: 'لا يُدير في باء');
    expect(find.byKey(const ValueKey('mx-edit-$_kB|b0')), findsNothing);
    expect(find.byKey(const ValueKey('mx-allow-$_kA|a0')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('mx-search')), 'شركة باء');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('mx-row-$_kB|b0')), findsOneWidget);
    expect(find.byKey(const ValueKey('mx-row-$_kA|a0')), findsNothing);
    await simDrain(t);

    MessageExclusionsState.reset();
    srv.lists[_kA] = 409;
    srv.lists[_kB] = 409;
    await pumpSim(t, _v, home: (_) => const MessageExclusionsScreen());
    expect(find.text('تعذّر جلب القائمة الآن — اسحب للتحديث.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await simDrain(t);
  });

  test('حارس نصّ: القائمة المدموجة تقرأ قائمة كلّ شركةٍ وتعلّم الصفّ بشركته؛ وصفحة المشترك بشركة صفّه', () {
    final list = File('lib/screens/subscribers/subscribers_screen.dart').readAsStringSync();
    expect(list, contains('bool _messagesMuted(Subscriber s) => MessageExclusionsState.ofRow(s.companyKey, s.username) != null;'));
    expect(list, contains('unawaited(MessageExclusionsState.ensureCompanies(['));
    expect(list, contains('MessageExclusionsState.changes.addListener(_onMessagesMutedChanged);'));
    expect(list, contains('MessageExclusionsState.changes.removeListener(_onMessagesMutedChanged);'));
    // الجماعيّ يبقى للشركة المفتوحة (لا تحديد في «كل الشركات» أصلاً)
    expect(list, contains('onMessages: _mergedOn ? null : _openBulkMessages,'));
    final page = File('lib/screens/subscribers/subscriber_detail_screen.dart').readAsStringSync();
    expect(page, contains('unawaited(MessageExclusionsState.ensureFreshFor(sub.companyKey));'));
    expect(page, contains('showMessageExclusionSheet(context, subject: mxSubjectOf(sub), companyKey: sub.companyKey)'));
    expect(page, contains('if (MessageExclusionsState.enabledFor(sub.companyKey))'));
    expect(page, contains('locked: !MessageExclusionsState.canManageFor(sub.companyKey),'));
    // المعترض يعرف المسار كتابةَ مشتركٍ بمرجع نافذته
    expect(File('lib/api/company_route.dart').readAsStringSync(), contains("'message-exclusion',"));
  });
}
