import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/field_team_api.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/screens/app_modules.dart';
import 'package:rad_mysvcs/screens/field_team/field_task_screen.dart';
import 'package:rad_mysvcs/screens/field_team/field_team_screen.dart';
import 'package:rad_mysvcs/screens/field_team/field_ticket_task.dart';
import 'package:rad_mysvcs/services/fcm_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «الصيانة والمبيعات» بتطبيق المدير (٢٣ نوفمبر — الخادم server/fieldTeam، الموقع 7ccfb8e مرجع الشكل والنصوص):
///   • النموذج والنداءات: الملخّص وأكواده، القائمة ومعاملاتها، أجسام الإنشاء والإسناد والإلغاء والملاحظة والفريق والأنواع، ورسالة
///     الخادم العربيّة كما هي عند الرفض، والصورة المحذوفة.
///   • البند في «قوائم أخرى»: غائبٌ ما لم يُفتح، مقفلٌ بمكانه للموظّف، ورقم «بانتظار الإسناد» للمدير، ولا قسم لـFTTH القديم.
///   • الشاشات على ٣٢٠–٤٨٠ × ١٫٠/١٫٢ بلا قصٍّ ولا فيض، ومسارات المدير: مهمّةٌ جديدة لمشتركٍ من مشتركيه، والإسناد والإلغاء بسبب
///     والملاحظة، والحساب الميدانيّ وبيانات دخوله، والنوع التلقائيّ الذي لا يُحفظ بلا شخصه، ونوع التذكرة المأخوذ مقفلاً باسم صاحبه.

String _ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();

Map<String, dynamic> _staff7() => {
      'id': 7,
      'kind': 'own',
      'full_name': 'أحمد علي',
      'phone': '07701234567',
      'address': 'حيّ الجامعة',
      'role': 'tech',
      'role_label': 'فنّي صيانة',
      'is_active': true,
      'username': 'ahmed.tech',
      'employee_id': null,
      'last_login_at': _ago(const Duration(hours: 3)),
      'last_seen_at': _ago(const Duration(minutes: 2)),
      'active_tasks': 2,
      'created_at': '2026-11-23T05:00:00Z',
    };

Map<String, dynamic> _staff8() => {
      'id': 8,
      'kind': 'employee',
      'full_name': 'حسين كاظم',
      'phone': null,
      'address': null,
      'role': 'both',
      'role_label': 'صيانة ومبيعات',
      'is_active': false,
      'username': 'hussein',
      'employee_id': 31,
      'last_login_at': null,
      'last_seen_at': null,
      'active_tasks': 0,
      'created_at': '2026-11-23T05:10:00Z',
    };

Map<String, dynamic> _task(int id, String status, {String? staff, int? staffId, bool ticket = false, String? fail}) => {
      'id': id,
      'title': 'النت مقطوع عند المشترك — بدّل الكونكتر وافحص الإشارة',
      'details': 'المشترك يقول إنّ الراوتر يضيء أحمر منذ الصباح',
      'status': status,
      'status_label': kFieldStatusLabels[status],
      'type_id': 1,
      'type_name': 'صيانة الشبكة',
      'source': ticket ? 'ticket' : 'manual',
      'ticket_id': ticket ? 55 : null,
      'ticket_category': ticket ? 'internet' : null,
      'subscriber': {'name': 'علي كريم', 'username': 'ali.k@sn', 'phone': '07801112233'},
      'address': 'حيّ الجامعة — قرب جامع الرحمن، الشارع الثالث',
      'location': {'lat': 30.5085, 'lng': 47.7804},
      'assigned_staff_id': staffId,
      'assigned_staff_name': staff,
      'fail_reason': fail,
      'created_by': 'mahdi',
      'created_at': _ago(const Duration(hours: 2)),
      'assigned_at': staff == null ? null : _ago(const Duration(hours: 1)),
      'done_at': null,
      'updated_at': _ago(const Duration(minutes: 30)),
      'actions': switch (status) {
        'done' || 'cancelled' => ['reopen'],
        _ => ['assign', 'cancel'],
      },
    };

class _FieldServer implements HttpClientAdapter {
  _FieldServer(this.inner);
  final HttpClientAdapter inner;

  Map<String, dynamic> summary = {
    'success': true,
    'available': true,
    'can_manage': true,
    'counts': {'new': 1, 'active': 1, 'failed': 1, 'done_today': 4},
    'staff_count': 2,
  };
  List<Map<String, dynamic>> staff = [_staff7(), _staff8()];
  List<Map<String, dynamic>> types = [
    {
      'id': 1,
      'name': 'صيانة الشبكة',
      'ticket_categories': ['internet', 'device'],
      'assign_mode': 'auto',
      'default_staff_id': 7,
      'sort_order': 0,
      'is_active': true
    },
    {
      'id': 2,
      'name': 'تركيب جديد',
      'ticket_categories': <String>[],
      'assign_mode': 'manual',
      'default_staff_id': null,
      'sort_order': 1,
      'is_active': true
    },
  ];
  final categories = [
    {'key': 'internet', 'label': 'انقطاع أو بطء'},
    {'key': 'account', 'label': 'الاشتراك والدفع'},
    {'key': 'device', 'label': 'الراوتر والجهاز'},
    {'key': 'other', 'label': 'أخرى'},
  ];
  List<Map<String, dynamic>> tasks = [
    _task(101, 'new', ticket: true),
    _task(102, 'on_way', staff: 'أحمد علي', staffId: 7),
    _task(103, 'failed', staff: 'أحمد علي', staffId: 7, fail: 'المشترك غير موجود في البيت'),
  ];

  /// كلّ كتابة: (الطريقة، المسار، الجسم).
  final writes = <(String, String, Map<String, dynamic>)>[];

  /// كلّ قراءة للقائمة: معاملاتها.
  final listQueries = <Map<String, dynamic>>[];

  /// «حوّلها مهمّة»: مهامّ التذاكر (رقم التذكرة ⇒ مهمّتها)، ومعرّفات كلّ سؤال.
  Map<String, Object> ticketTasks = {};
  final ticketTaskQueries = <String>[];

  /// ردّ الكتابة القادمة: (status, body) — null ⇒ نجاح.
  (int, Object)? nextWrite;

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });

  Map<String, dynamic>? _taskById(int id) {
    for (final t in tasks) {
      if (t['id'] == id) return t;
    }
    return null;
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final m = o.method.toUpperCase();
    final p = o.path;
    if (p == '/api/v2/employees' && m == 'GET') {
      return _json(200, {
        'success': true,
        'data': [
          {'id': 31, 'username': 'hussein', 'full_name': 'حسين كاظم', 'is_active': true},
          {'id': 32, 'username': 'zaid', 'full_name': 'زيد حسن', 'is_active': true},
          {'id': 33, 'username': 'old', 'full_name': 'موظّف معطّل', 'is_active': false},
        ],
      });
    }
    if (p == '/api/subscribers/search' && m == 'GET') {
      final q = '${o.queryParameters['search'] ?? ''}';
      return _json(200, {
        'success': true,
        'data': [
          if ('علي كريم ali.k@sn'.contains(q))
            {'idx': '4411', 'username': 'ali.k@sn', 'firstname': 'علي', 'lastname': 'كريم', 'phone': null},
          if ('علياء'.contains(q)) {'idx': '4412', 'username': 'alyaa@sn', 'firstname': 'علياء', 'lastname': '', 'phone': '07709998877'},
        ],
      });
    }
    if (!p.startsWith('/api/v2/field')) return inner.fetch(o, requestStream, cancelFuture);
    if (m != 'GET') {
      writes.add((m, p, Map<String, dynamic>.from((o.data as Map?) ?? const {})));
      final r = nextWrite;
      nextWrite = null;
      if (r != null) return _json(r.$1, r.$2);
    }
    if (p == '/api/v2/field/summary') return _json(200, summary);
    if (p == '/api/v2/field/ticket-tasks') {
      ticketTaskQueries.add('${o.queryParameters['ids']}');
      return _json(200, {'success': true, 'items': ticketTasks});
    }
    if (p == '/api/v2/field/staff') {
      if (m == 'GET') return _json(200, {'success': true, 'items': staff});
      final b = writes.last.$3;
      return _json(201, {
        'success': true,
        'staff': {
          ..._staff7(),
          'id': 9,
          'full_name': b['full_name'] ?? 'زيد حسن',
          'username': b['username'] ?? 'zaid',
          'kind': b['employee_id'] == null ? 'own' : 'employee',
        },
      });
    }
    final staffMatch = RegExp(r'^/api/v2/field/staff/(\d+)$').firstMatch(p);
    if (staffMatch != null) {
      final b = writes.last.$3;
      return _json(200, {'success': true, 'staff': _staff7(), 'released_tasks': b['is_active'] == false ? 1 : 0});
    }
    if (p == '/api/v2/field/types' && m == 'GET') {
      return _json(200, {'success': true, 'items': types, 'ticket_categories': categories});
    }
    if (p.startsWith('/api/v2/field/types')) return _json(200, {'success': true, 'type': types.first});
    if (p == '/api/v2/field/tasks' && m == 'GET') {
      listQueries.add(Map<String, dynamic>.from(o.queryParameters));
      final f = '${o.queryParameters['filter']}';
      const by = {
        'new': ['new'],
        'active': ['assigned', 'on_way', 'working'],
        'failed': ['failed'],
        'closed': ['done', 'failed', 'cancelled'],
      };
      final items = f == 'all' ? tasks : tasks.where((t) => (by[f] ?? const []).contains(t['status'])).toList();
      return _json(200, {'success': true, 'filter': f, 'items': items, 'has_more': false, 'next_offset': items.length});
    }
    if (p == '/api/v2/field/tasks') return _json(201, {'success': true, 'task': _task(104, 'new')});
    final img = RegExp(r'^/api/v2/field/tasks/(\d+)/events/(\d+)/image$').firstMatch(p);
    if (img != null) return _json(410, {'success': false, 'code': 'IMAGE_EXPIRED', 'message': 'حُذفت هذه الصورة'});
    final one = RegExp(r'^/api/v2/field/tasks/(\d+)(?:/([a-z]+))?$').firstMatch(p);
    if (one != null) {
      final t = _taskById(int.parse(one.group(1)!));
      if (t == null) return _json(404, {'success': false, 'code': 'TASK_NOT_FOUND', 'message': 'لم يُعثر على هذه المهمّة'});
      if (m == 'GET') {
        return _json(200, {
          'success': true,
          'task': t,
          'events': [
            {'id': 1, 'side': 'manager', 'who': 'mahdi', 'kind': 'created', 'created_at': t['created_at']},
            if (t['assigned_staff_name'] != null) ...[
              {'id': 2, 'side': 'manager', 'who': 'mahdi', 'kind': 'assigned', 'created_at': t['assigned_at']},
              {
                'id': 3,
                'side': 'staff',
                'who': 'أحمد علي',
                'kind': 'status',
                'status_to': 'on_way',
                'status_label': 'في الطريق',
                'location': {'lat': 30.51, 'lng': 47.78},
                'created_at': _ago(const Duration(minutes: 40)),
              },
              {
                'id': 4,
                'side': 'staff',
                'who': 'أحمد علي',
                'kind': 'note',
                'note': 'وصلت قرب البيت — أنتظر المشترك يفتح الباب',
                'has_image': true,
                'created_at': _ago(const Duration(minutes: 31)),
              },
            ],
          ],
        });
      }
      return _json(200, {'success': true, 'task': t});
    }
    return _json(404, {'success': false, 'message': 'غير موجود'});
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

Future<_FieldServer> _setUp() async {
  final server = _FieldServer(await visualSetUp(s1bSasOwner));
  ApiClient.dio.httpClientAdapter = server;
  return server;
}

/// شاشةٌ بعرضٍ وتكبير — والتكبير فوق الـNavigator كما في main.dart.
/// القائمة العموديّة للصفحة (حقول النصّ لها قابل تمريرٍ أيضاً).
Finder _page() => find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

/// قابل تمرير الورقة المفتوحة (فوق الصفحة).
Finder _sheet() => find
    .descendant(
        of: find.byType(DesignSheet), matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down))
    .first;

Future<void> _pump(WidgetTester t, Widget home, {double w = 390, double s = 1.0, double h = 1400}) => pumpVisual(
      t,
      VisualDevice('', Size(w, h), 2),
      home: (_) => home,
      wrap: (child) => Builder(
        builder: (ctx) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s)), child: child),
      ),
    );

/// لا نصٌّ مقصوص بنقاطٍ أو بسطرٍ زائد في الشجرة.
void _noClippedText(WidgetTester t, String where) {
  for (final e in find.byType(RichText).evaluate()) {
    final ro = e.renderObject;
    if (ro is RenderParagraph && ro.didExceedMaxLines) {
      fail('«${ro.text.toPlainText()}» مقصوص $where');
    }
  }
}

/// آخر كتابة: الطريقة والمسار، والجسم مقارنةً عميقة (السجلّ يقارن خريطته بالهويّة).
void _expectWrite(_FieldServer s, String method, String path, Map<String, Object?> body, {String? reason}) {
  final w = s.writes.last;
  expect((w.$1, w.$2), (method, path), reason: reason);
  expect(w.$3, equals(body), reason: reason);
}

const _sizes = [(320.0, 1.0), (320.0, 1.2), (360.0, 1.2), (390.0, 1.0), (390.0, 1.2), (430.0, 1.0), (480.0, 1.2)];

void main() {
  setUpAll(visualSetUpAll);

  group('النموذج والنداءات', () {
    tearDown(() {
      FieldTeamState.debugSet(null);
      return visualTearDown();
    });

    testWidgets('الملخّص: المدير بأعداده · الموظّف مقفل · مسارٌ غائب = غير متاح · عطلٌ = مجهول', (t) async {
      final server = await _setUp();
      var s = (await t.runAsync<FieldSummary?>(FieldTeamApi.summary))!;
      expect((s.available, s.canManage, s.waiting, s.active, s.failed, s.doneToday, s.staffCount), (true, true, 1, 1, 1, 4, 2));
      server.summary = {'success': true, 'available': true, 'can_manage': false};
      s = (await t.runAsync<FieldSummary?>(FieldTeamApi.summary))!;
      expect((s.available, s.canManage, s.waiting), (true, false, 0));
      server.summary = {'success': true, 'available': false, 'can_manage': false};
      expect((await t.runAsync<FieldSummary?>(FieldTeamApi.summary))!.available, isFalse);
      // مزوّدٌ ردّه الآمن بلا available (ايرث لنك قبل تمرير المسار) ⇒ غير متاح، لا عطل
      server.summary = {'success': true, 'data': null, 'items': [], 'value': null, 'total': 0};
      expect((await t.runAsync<FieldSummary?>(FieldTeamApi.summary))!.available, isFalse);
    });

    testWidgets('القائمة: الشريحة والإزاحة والحدّ والبحث، والمهمّة كاملةً', (t) async {
      final server = await _setUp();
      final r = (await t.runAsync(() => FieldTeamApi.tasks(filter: FieldTaskFilter.waiting, query: '  علي ', offset: 0)))!;
      expect(server.listQueries.last, {'filter': 'new', 'offset': 0, 'limit': 30, 'q': 'علي'});
      final task = r.page!.items.single;
      expect((task.id, task.status, task.statusLabel, task.fromTicket, task.ticketId), (101, 'new', 'بانتظار الإسناد', true, 55));
      expect((task.subscriber?.title, task.subscriber?.phone, task.location?.lat), ('علي كريم', '07801112233', 30.5085));
      expect(task.actions, {'assign', 'cancel'});
      await t.runAsync(() => FieldTeamApi.tasks(filter: FieldTaskFilter.closed));
      expect(server.listQueries.last, {'filter': 'closed', 'offset': 0, 'limit': 30}, reason: 'بلا بحثٍ ⇒ لا q');
    });

    testWidgets('الكتابات: الإنشاء والإسناد والإلغاء والإعادة والملاحظة بأجسامها', (t) async {
      final server = await _setUp();
      final c = (await t.runAsync(() => FieldTeamApi.createTask(
            title: '  تركيب راوتر ',
            typeId: 2,
            staffId: 7,
            subscriber: const FieldSubscriber(name: 'علي كريم', username: 'ali.k@sn', phone: ''),
            address: ' حيّ الجامعة ',
            details: '',
          )))!;
      expect(c.error, isNull);
      _expectWrite(server, 'POST', '/api/v2/field/tasks', {
        'title': 'تركيب راوتر',
        'type_id': 2,
        'staff_id': 7,
        'subscriber': {'name': 'علي كريم', 'username': 'ali.k@sn'},
        'address': 'حيّ الجامعة',
      });
      await t.runAsync(() => FieldTeamApi.createTask(title: 'زيارة'));
      expect(server.writes.last.$3, {'title': 'زيارة'}, reason: 'بلا نوعٍ ولا شخصٍ ولا مشترك ⇒ لا مفاتيح فارغة');

      expect((await t.runAsync(() => FieldTeamApi.assign(101, 7)))!.ok, isTrue);
      _expectWrite(server, 'POST', '/api/v2/field/tasks/101/assign', {'staff_id': 7});
      await t.runAsync(() => FieldTeamApi.cancel(101, reason: '  أصلحه بنفسه '));
      _expectWrite(server, 'POST', '/api/v2/field/tasks/101/cancel', {'reason': 'أصلحه بنفسه'});
      await t.runAsync(() => FieldTeamApi.cancel(101));
      expect(server.writes.last.$3, isEmpty, reason: 'بلا سبب ⇒ جسمٌ فارغ');
      await t.runAsync(() => FieldTeamApi.reopen(103));
      _expectWrite(server, 'POST', '/api/v2/field/tasks/103/reopen', <String, dynamic>{});
      await t.runAsync(() => FieldTeamApi.note(102, ' المشترك ينتظرك بعد ٤ '));
      _expectWrite(server, 'POST', '/api/v2/field/tasks/102/note', {'note': 'المشترك ينتظرك بعد ٤'});

      // تغيّر الحال بين القراءة والكتابة ⇒ رسالة الخادم كما هي
      server.nextWrite = (409, {'success': false, 'code': 'TASK_STATE', 'message': 'حال المهمّة تغيّر — حدّث الصفحة'});
      final bad = (await t.runAsync(() => FieldTeamApi.assign(101, 7)))!;
      expect((bad.ok, bad.error), (false, 'حال المهمّة تغيّر — حدّث الصفحة'));
      // صفحة وسيطٍ بلا رسالة ⇒ بديلٌ عربيّ، لا نصّ HTML
      server.nextWrite = (502, '<html>Bad gateway</html>');
      final gw = (await t.runAsync(() => FieldTeamApi.note(101, 'x')))!;
      expect(gw.ok, isFalse);
      expect(gw.error, isNot(contains('<html>')));
    });

    testWidgets('الفريق: الحساب المستقلّ والموظّف الموجود والإيقاف وحدّ الموظّفين', (t) async {
      final server = await _setUp();
      final own = (await t.runAsync(() => FieldTeamApi.createOwn(
          fullName: 'زيد حسن', username: 'zaid.t', password: 'abc12345', role: 'sales', phone: '', address: 'الزبير')))!;
      expect(own.error, isNull);
      _expectWrite(server, 'POST', '/api/v2/field/staff', {
        'full_name': 'زيد حسن',
        'username': 'zaid.t',
        'password': 'abc12345',
        'role': 'sales',
        'address': 'الزبير',
      });
      await t.runAsync(() => FieldTeamApi.linkEmployee(employeeId: 31, role: 'both'));
      expect(server.writes.last.$3, {'employee_id': 31, 'role': 'both'});
      final off = (await t.runAsync(() => FieldTeamApi.updateStaff(7, {'is_active': false})))!;
      expect((off.ok, off.released), (true, 1));
      _expectWrite(server, 'PUT', '/api/v2/field/staff/7', {'is_active': false});
      server.nextWrite =
          (403, {'success': false, 'code': 'EMPLOYEE_LIMIT', 'message': 'بلغت حدّ الموظّفين في باقتك — الحساب الميدانيّ يُحسب منه'});
      final lim = (await t.runAsync(() => FieldTeamApi.createOwn(fullName: 'x', username: 'xyz', password: '123456', role: 'tech')))!;
      expect(lim.error, 'بلغت حدّ الموظّفين في باقتك — الحساب الميدانيّ يُحسب منه');
      final emps = (await t.runAsync(FieldTeamApi.employees))!;
      expect([for (final e in emps.items!) e.id], [31, 32], reason: 'المعطّل لا يُعرض');
    });

    testWidgets('الأنواع: اليدويّ بلا شخص، والتلقائيّ بشخصه، والتعديل بـPUT', (t) async {
      final server = await _setUp();
      await t.runAsync(() =>
          FieldTeamApi.saveType(name: 'تركيب', ticketCategories: const ['other'], assignMode: 'manual', defaultStaffId: 7, isActive: true));
      _expectWrite(server, 'POST', '/api/v2/field/types', {
        'name': 'تركيب',
        'ticket_categories': ['other'],
        'assign_mode': 'manual',
        'default_staff_id': null,
        'is_active': true,
      });
      await t.runAsync(() => FieldTeamApi.saveType(
          id: 1, name: 'صيانة', ticketCategories: const ['internet'], assignMode: 'auto', defaultStaffId: 7, isActive: false));
      _expectWrite(server, 'PUT', '/api/v2/field/types/1', {
        'name': 'صيانة',
        'ticket_categories': ['internet'],
        'assign_mode': 'auto',
        'default_staff_id': 7,
        'is_active': false,
      });
      final r = (await t.runAsync(FieldTeamApi.types))!;
      expect([for (final c in r.categories) c.key], ['internet', 'account', 'device', 'other']);
      expect((r.items!.first.isAuto, r.items!.first.defaultStaffId), (true, 7));
    });

    testWidgets('الصورة المحذوفة (410) تقول ذلك ولا تُعدّ عطلاً', (t) async {
      await _setUp();
      final r = (await t.runAsync(() => FieldTeamApi.eventImage(102, 4)))!;
      expect((r.bytes, r.expired), (null, true));
    });

    testWidgets('بحث «من مشتركيك»: الاسم واليوزر والهاتف', (t) async {
      await _setUp();
      final r = (await t.runAsync(() => FieldTeamApi.searchSubscribers('علي')))!;
      expect([
        for (final h in r.items!) (h.name, h.username, h.phone)
      ], [
        ('علي كريم', 'ali.k@sn', null),
        ('علياء', 'alyaa@sn', '07709998877'),
      ]);
    });
  });

  group('البند في «قوائم أخرى»', () {
    tearDown(() {
      FieldTeamState.debugSet(null);
      return visualTearDown();
    });

    AppModule? field() {
      for (final m in buildAppModules()) {
        if (m.id == 'field_team') return m;
      }
      return null;
    }

    testWidgets('غائبٌ ما لم يُفتح · المدير برقم الانتظار · الموظّف مقفلٌ بمكانه · FTTH القديم بلا قسم', (t) async {
      await _setUp();
      FieldTeamState.debugSet(null);
      expect(field(), isNull, reason: 'لم يُعرف بعد ⇒ لا يظهر');
      FieldTeamState.debugSet(const FieldSummary(available: false, canManage: false));
      expect(field(), isNull);

      FieldTeamState.debugSet(const FieldSummary(available: true, canManage: true, waiting: 3));
      var m = field()!;
      expect((m.isLocked, m.badge, m.title), (false, 3, 'الصيانة والمبيعات'));
      expect(m.subtitle, contains('3 بانتظار إسنادك'));

      FieldTeamState.debugSet(const FieldSummary(available: true, canManage: false));
      m = field()!;
      expect((m.isLocked, m.unavailable, m.badge), (true, 'لمدير الصفحة وحده الآن', null));

      ProviderService.debugSet('ftth');
      expect(field(), isNull, reason: 'FTTH القديم بلا قسم (الموقع noFtth)');
    });
  });

  group('الشاشات', () {
    tearDown(() {
      FieldTeamState.debugSet(null);
      return visualTearDown();
    });

    for (final (w, s) in _sizes) {
      testWidgets('الأقسام الثلاثة @$w ×$s: بلا فيضٍ ولا قصّ', (t) async {
        await _setUp();
        await _pump(t, const FieldTeamScreen(), w: w, s: s);
        await settle(t, seconds: 2);
        expect(find.byKey(const ValueKey('field-tabs')), findsOneWidget);
        // «بانتظار الإسناد» فيها مهمّة ⇒ تبدأ القائمة بها
        expect(find.byKey(const ValueKey('field-task-101')), findsOneWidget);
        expect(find.byKey(const ValueKey('field-stat-new')), findsOneWidget);
        _noClippedText(t, 'المهامّ @$w ×$s');
        expect(t.takeException(), isNull);

        await t.tap(find.text('الكلّ'));
        await settle(t, seconds: 1);
        expect(find.byKey(const ValueKey('field-task-103')), findsOneWidget);
        expect(find.text('المشترك غير موجود في البيت'), findsOneWidget);
        _noClippedText(t, 'الكلّ @$w ×$s');

        await t.tap(find.text('الفريق (2)'));
        await settle(t, seconds: 2);
        expect(find.byKey(const ValueKey('field-team-link')), findsOneWidget);
        await t.scrollUntilVisible(find.byKey(const ValueKey('field-staff-8')), 300, scrollable: _page());
        expect(find.text('نشِطٌ الآن'), findsOneWidget);
        expect(find.text('موقوف'), findsOneWidget);
        _noClippedText(t, 'الفريق @$w ×$s');
        expect(t.takeException(), isNull);

        await t.tap(find.text('الأنواع'));
        await settle(t, seconds: 2);
        await t.scrollUntilVisible(find.byKey(const ValueKey('field-type-2')), 300, scrollable: _page());
        expect(find.text('يدويّ — تظهر في «بانتظار الإسناد»'), findsOneWidget);
        _noClippedText(t, 'الأنواع @$w ×$s');
        expect(t.takeException(), isNull);
        await settle(t, seconds: 4); // رسالة التأكيد تختفي بعد ٣ ثوانٍ
        await t.pumpWidget(const SizedBox());
      });
    }

    testWidgets('الموظّف: القسم مقفلٌ بسببه ولا يُطلب منه شيءٌ آخر', (t) async {
      final server = await _setUp();
      server.summary = {'success': true, 'available': true, 'can_manage': false};
      await _pump(t, const FieldTeamScreen());
      await settle(t, seconds: 2);
      expect(find.byKey(const ValueKey('field-locked')), findsOneWidget);
      expect(server.listQueries, isEmpty);
      await settle(t, seconds: 4); // رسالة التأكيد تختفي بعد ٣ ثوانٍ
      await t.pumpWidget(const SizedBox());
    });

    for (final (w, s) in [(320.0, 1.2), (430.0, 1.0)]) {
      testWidgets('المهمّة @$w ×$s: المراحل والفنّي والمشترك والسجلّ، ثمّ الإسناد والملاحظة والإلغاء بسبب', (t) async {
        final server = await _setUp();
        await _pump(t, const FieldTaskScreen(taskId: 102), w: w, s: s);
        await settle(t, seconds: 2);
        expect(find.byKey(const ValueKey('field-task-title')), findsOneWidget);
        expect(find.text('في الطريق'), findsWidgets);
        expect(find.byKey(const ValueKey('field-tech-call')), findsOneWidget);
        expect(find.byKey(const ValueKey('field-sub-wa')), findsOneWidget);
        _noClippedText(t, 'المهمّة @$w ×$s');
        expect(t.takeException(), isNull);

        await t.scrollUntilVisible(find.byKey(const ValueKey('field-task-log')), 300, scrollable: _page());
        await t.scrollUntilVisible(find.byKey(const ValueKey('field-event-4')), 300, scrollable: _page());
        await settle(t, seconds: 1);
        expect(find.text('الصورة لم تعد محفوظة'), findsOneWidget);
        expect(find.text('مكان الفنّي عندها'), findsOneWidget);

        // الإسناد: الزرّ معطّلٌ حتى يُختار شخص
        await t.scrollUntilVisible(find.byKey(const ValueKey('field-assign-pick')), -300, scrollable: _page());
        await t.tap(find.byKey(const ValueKey('field-assign-pick')));
        await settle(t, seconds: 1);
        expect(find.textContaining('حسين كاظم'), findsNothing, reason: 'الموقوف لا يُسند إليه');
        await t.tap(find.textContaining('أحمد علي').last);
        await settle(t, seconds: 1);
        await t.tap(find.byKey(const ValueKey('field-assign')));
        await settle(t, seconds: 1);
        _expectWrite(server, 'POST', '/api/v2/field/tasks/102/assign', {'staff_id': 7});

        await t.scrollUntilVisible(find.byKey(const ValueKey('field-note')), 300, scrollable: _page());
        await t.enterText(
            find.descendant(of: find.byKey(const ValueKey('field-note')), matching: find.byType(TextField)), 'المشترك ينتظرك');
        await settle(t, seconds: 1);
        await t.tap(find.byKey(const ValueKey('field-note-send')));
        await settle(t, seconds: 1);
        _expectWrite(server, 'POST', '/api/v2/field/tasks/102/note', {'note': 'المشترك ينتظرك'});

        await t.scrollUntilVisible(find.byKey(const ValueKey('field-cancel')), 300, scrollable: _page());
        await t.tap(find.byKey(const ValueKey('field-cancel')));
        await settle(t, seconds: 1);
        await t.enterText(
            find.descendant(of: find.byKey(const ValueKey('field-cancel-reason')), matching: find.byType(TextField)), 'أصلحه بنفسه');
        await t.tap(find.byKey(const ValueKey('field-cancel-confirm')));
        await settle(t, seconds: 1);
        _expectWrite(server, 'POST', '/api/v2/field/tasks/102/cancel', {'reason': 'أصلحه بنفسه'});
        expect(t.takeException(), isNull);
        await settle(t, seconds: 4); // رسالة التأكيد تختفي بعد ٣ ثوانٍ
        await t.pumpWidget(const SizedBox());
      });
    }

    testWidgets('مهمّةٌ جديدة: المشترك من مشتركيه (بلا هاتف ⇒ «هاتفه للتواصل») والإسناد', (t) async {
      final server = await _setUp();
      await _pump(t, const FieldTeamScreen(), w: 360, s: 1.2);
      await settle(t, seconds: 2);
      await t.tap(find.byKey(const ValueKey('field-new-task')));
      await settle(t, seconds: 2);
      expect(find.byKey(const ValueKey('field-new-submit')), findsOneWidget);
      await t.enterText(
          find.descendant(of: find.byKey(const ValueKey('field-new-title')), matching: find.byType(TextField)), 'تركيب راوتر');
      await settle(t, seconds: 1);
      await t.tap(find.byKey(const ValueKey('field-new-staff')));
      await settle(t, seconds: 1);
      await t.tap(find.textContaining('أحمد علي').last);
      await settle(t, seconds: 1);
      await t.enterText(find.descendant(of: find.byKey(const ValueKey('field-new-search')), matching: find.byType(TextField)), 'علي');
      await settle(t, seconds: 2);
      await t.tap(find.byKey(const ValueKey('field-new-hit-ali.k@sn')));
      await settle(t, seconds: 1);
      expect(find.byKey(const ValueKey('field-new-picked')), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const ValueKey('field-new-picked-phone')), 200, scrollable: _sheet());
      await t.enterText(
          find.descendant(of: find.byKey(const ValueKey('field-new-picked-phone')), matching: find.byType(TextField)), '07801112233');
      _noClippedText(t, 'مهمّة جديدة');
      await t.tap(find.byKey(const ValueKey('field-new-submit')));
      await settle(t, seconds: 2);
      _expectWrite(server, 'POST', '/api/v2/field/tasks', {
        'title': 'تركيب راوتر',
        'staff_id': 7,
        'subscriber': {'name': 'علي كريم', 'username': 'ali.k@sn', 'phone': '07801112233'},
      });
      expect(find.byKey(const ValueKey('field-new-submit')), findsNothing, reason: 'أُغلقت بعد الإنشاء');
      expect(t.takeException(), isNull);
      await settle(t, seconds: 4); // رسالة التأكيد تختفي بعد ٣ ثوانٍ
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('حسابٌ ميدانيّ جديد ⇒ بيانات دخوله للنسخ والواتساب', (t) async {
      final server = await _setUp();
      await _pump(t, const FieldTeamScreen(), w: 320, s: 1.2);
      await settle(t, seconds: 2);
      await t.tap(find.text('الفريق (2)'));
      await settle(t, seconds: 2);
      await t.tap(find.byKey(const ValueKey('field-staff-add')));
      await settle(t, seconds: 1);
      Finder field(String k) => find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(TextField));
      await t.enterText(field('field-staff-name'), 'زيد حسن');
      await t.enterText(field('field-staff-username'), 'Zaid.T');
      await settle(t, seconds: 1);
      expect(find.text('zaid.t'), findsOneWidget, reason: 'اسم الدخول بحروفٍ صغيرة كما يحفظه الخادم');
      await t.tap(find.byKey(const ValueKey('field-suggest-password')));
      await settle(t, seconds: 1);
      final pw = t.widget<TextField>(field('field-staff-password')).controller!.text;
      expect(pw, matches(RegExp(r'^[a-hjkmnp-z2-9]{8}$')));
      await t.tap(find.byKey(const ValueKey('field-staff-save')));
      await settle(t, seconds: 2);
      _expectWrite(server, 'POST', '/api/v2/field/staff', {'full_name': 'زيد حسن', 'username': 'zaid.t', 'password': pw, 'role': 'tech'});
      expect(find.byKey(const ValueKey('field-credentials')), findsOneWidget);
      expect(find.text(pw), findsOneWidget);
      _noClippedText(t, 'بيانات الدخول');
      expect(t.takeException(), isNull);
      await settle(t, seconds: 4); // رسالة التأكيد تختفي بعد ٣ ثوانٍ
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('إيقاف شخصٍ من بطاقته: الطلب ومهامّه التي رجعت بانتظار الإسناد', (t) async {
      final server = await _setUp();
      await _pump(t, const FieldTeamScreen(), w: 390);
      await settle(t, seconds: 2);
      await t.tap(find.text('الفريق (2)'));
      await settle(t, seconds: 2);
      await t.scrollUntilVisible(find.byKey(const ValueKey('field-staff-switch-7')), 300, scrollable: _page());
      await t.tap(find.byKey(const ValueKey('field-staff-switch-7')));
      await settle(t, seconds: 1);
      _expectWrite(server, 'PUT', '/api/v2/field/staff/7', {'is_active': false});
      expect(find.textContaining('رجعت 1 مهمّة بانتظار الإسناد'), findsOneWidget);
      await settle(t, seconds: 4); // رسالة التأكيد تختفي بعد ٣ ثوانٍ
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('نوعٌ جديد: المأخوذ مقفلٌ باسم صاحبه، والتلقائيّ لا يُحفظ بلا شخصه', (t) async {
      final server = await _setUp();
      await _pump(t, const FieldTeamScreen(), w: 320, s: 1.0);
      await settle(t, seconds: 2);
      await t.tap(find.text('الأنواع'));
      await settle(t, seconds: 2);
      await t.tap(find.byKey(const ValueKey('field-type-add')));
      await settle(t, seconds: 1);
      expect(find.text('انقطاع أو بطء · صيانة الشبكة'), findsOneWidget, reason: 'مأخوذٌ بنوعٍ آخر');
      await t.enterText(find.descendant(of: find.byKey(const ValueKey('field-type-name')), matching: find.byType(TextField)), 'الحسابات');
      await t.tap(find.byKey(const ValueKey('field-type-cat-internet')));
      await t.tap(find.byKey(const ValueKey('field-type-cat-account')));
      await t.tap(find.byKey(const ValueKey('field-type-auto')));
      await settle(t, seconds: 1);
      await t.tap(find.byKey(const ValueKey('field-type-save')));
      await settle(t, seconds: 1);
      expect(server.writes, isEmpty, reason: 'تلقائيّ بلا شخص ⇒ الحفظ معطّل');
      await t.tap(find.byKey(const ValueKey('field-type-staff')));
      await settle(t, seconds: 1);
      await t.tap(find.textContaining('أحمد علي').last);
      await settle(t, seconds: 1);
      await t.tap(find.byKey(const ValueKey('field-type-save')));
      await settle(t, seconds: 2);
      _expectWrite(server, 'POST', '/api/v2/field/types', {
        'name': 'الحسابات',
        'ticket_categories': ['account'],
        'assign_mode': 'auto',
        'default_staff_id': 7,
        'is_active': true,
      });
      expect(t.takeException(), isNull);
      await settle(t, seconds: 4); // رسالة التأكيد تختفي بعد ٣ ثوانٍ
      await t.pumpWidget(const SizedBox());
    });
  });

  group('«حوّلها مهمّة»', () {
    tearDown(() {
      FieldTeamState.debugSet(null);
      return visualTearDown();
    });

    testWidgets('النداءان: مهامّ التذاكر بأرقامها، والتحويل بجسمه و«لها مهمّةٌ أصلاً»', (t) async {
      final server = await _setUp();
      server.ticketTasks = {
        '55': {'id': 101, 'status': 'assigned', 'status_label': 'مُسندة', 'assigned_staff_name': 'أحمد علي', 'type_name': 'صيانة الشبكة'},
      };
      final m = (await t.runAsync(() => FieldTeamApi.ticketTasks([55, 56, 55, 0])))!;
      expect(server.ticketTaskQueries.last, '55,56', reason: 'بلا تكرارٍ ولا صفر');
      expect((m[55]?.id, m[55]?.statusLabel, m[55]?.assignedStaffName, m[56]), (101, 'مُسندة', 'أحمد علي', null));
      expect(await t.runAsync(() => FieldTeamApi.ticketTasks(const [])), isEmpty);
      expect(server.ticketTaskQueries.length, 1, reason: 'بلا تذاكر ⇒ بلا طلب');

      final r = (await t.runAsync(() => FieldTeamApi.createFromTicket(ticketId: 57, typeId: 1, staffId: 7)))!;
      expect((r.error, r.linked), (null, false));
      _expectWrite(server, 'POST', '/api/v2/field/tasks', {'ticket_id': 57, 'type_id': 1, 'staff_id': 7});
      server.nextWrite = (409, {'success': false, 'code': 'TICKET_LINKED', 'message': 'لهذه التذكرة مهمّةٌ أصلاً'});
      final again = (await t.runAsync(() => FieldTeamApi.createFromTicket(ticketId: 57)))!;
      expect((again.error, again.linked), ('لهذه التذكرة مهمّةٌ أصلاً', true));
      _expectWrite(server, 'POST', '/api/v2/field/tasks', {'ticket_id': 57});
    });

    Widget host(Widget row) => Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: row));

    testWidgets('المدير: «حوّلها مهمّة» بالنوع المربوط وشخصه التلقائيّ افتراضاً، ثمّ «مهمّة #N» و«فتح المهمّة»', (t) async {
      final server = await _setUp();
      FieldTeamState.debugSet(const FieldSummary(available: true, canManage: true));
      await _pump(t, host(const FieldTicketTaskRow(ticketId: 57, category: 'internet')), w: 320, s: 1.2, h: 1400);
      await settle(t, seconds: 1);
      expect(find.byKey(const ValueKey('ticket-field-convert')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('ticket-field-convert')));
      await settle(t, seconds: 2);
      // «انقطاع أو بطء» مربوطٌ بـ«صيانة الشبكة» (تلقائيّ لأحمد علي) ⇒ الاثنان افتراضاً
      expect(find.textContaining('صيانة الشبكة'), findsWidgets);
      expect(find.text('مربوطٌ بنوع التذكرة «انقطاع أو بطء»'), findsOneWidget);
      expect(find.text('إسناد النوع التلقائيّ'), findsOneWidget);
      _noClippedText(t, 'حوّلها مهمّة');
      server.ticketTasks = {
        '57': {'id': 104, 'status': 'assigned', 'status_label': 'مُسندة', 'assigned_staff_name': 'أحمد علي', 'type_name': 'صيانة الشبكة'},
      };
      await t.tap(find.byKey(const ValueKey('ticket-convert-submit')));
      await settle(t, seconds: 2);
      _expectWrite(server, 'POST', '/api/v2/field/tasks', {'ticket_id': 57, 'type_id': 1, 'staff_id': 7});
      expect(find.byKey(const ValueKey('ticket-field-task')), findsOneWidget);
      expect(find.text('مهمّة #104'), findsOneWidget);
      expect(find.byKey(const ValueKey('ticket-field-open')), findsOneWidget);
      _noClippedText(t, 'مهمّة التذكرة');
      expect(t.takeException(), isNull);
      await settle(t, seconds: 4); // رسالة التأكيد تختفي بعد ٣ ثوانٍ
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('نوع تذكرةٍ غير مربوط: بلا نوعٍ ولاحقاً، وتلميحٌ يدلّ على «الأنواع»', (t) async {
      final server = await _setUp();
      FieldTeamState.debugSet(const FieldSummary(available: true, canManage: true));
      await _pump(t, host(const FieldTicketTaskRow(ticketId: 58, category: 'account')), w: 390);
      await settle(t, seconds: 1);
      await t.tap(find.byKey(const ValueKey('ticket-field-convert')));
      await settle(t, seconds: 2);
      expect(find.text('«الاشتراك والدفع» غير مربوطٍ بنوع — اربطه من «الأنواع» فتصير تذاكره مهامّاً تلقائيّاً'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('ticket-convert-submit')));
      await settle(t, seconds: 2);
      _expectWrite(server, 'POST', '/api/v2/field/tasks', {'ticket_id': 58});
      await settle(t, seconds: 4); // رسالة التأكيد تختفي بعد ٣ ثوانٍ
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('الموظّف: سطرٌ مقفلٌ بلا طلب · غير مفعّل: لا شيء', (t) async {
      final server = await _setUp();
      FieldTeamState.debugSet(const FieldSummary(available: true, canManage: false));
      await _pump(t, host(const FieldTicketTaskRow(ticketId: 55, category: 'internet')), w: 320, s: 1.2);
      await settle(t, seconds: 1);
      expect(find.byKey(const ValueKey('ticket-field-locked')), findsOneWidget);
      expect(server.ticketTaskQueries, isEmpty);
      _noClippedText(t, 'مقفل');
      await t.pumpWidget(const SizedBox());

      FieldTeamState.debugSet(const FieldSummary(available: false, canManage: false));
      await _pump(t, host(const FieldTicketTaskRow(ticketId: 55, category: 'internet')), w: 320);
      await settle(t, seconds: 1);
      expect(find.byKey(const ValueKey('ticket-field-locked')), findsNothing);
      expect(find.byKey(const ValueKey('ticket-field-convert')), findsNothing);
      expect(server.ticketTaskQueries, isEmpty);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('إشعار «أنجز الفريق مهمّة» يفتح المهمّة، وهو عاجل (صوتٌ ونافذة)', (t) async {
      await _setUp();
      expect(FcmService.urgentTypes, contains('field_task'));
      final nav = GlobalKey<NavigatorState>();
      await pumpVisual(t, const VisualDevice('', Size(390, 1200), 2), navigatorKey: nav, home: (_) => const Scaffold(body: SizedBox()));
      await settle(t, seconds: 1);
      bool? other;
      bool? bad;
      unawaited(openFieldTaskPush(nav.currentState!, const {'type': 'store_order'}).then((v) => other = v));
      unawaited(openFieldTaskPush(nav.currentState!, const {'type': 'field_task', 'task_id': 'x'}).then((v) => bad = v));
      await settle(t, seconds: 1);
      expect((other, bad), (false, false), reason: 'نوعٌ آخر أو رقمٌ غير صالح لا يُفتح');
      expect(find.byType(FieldTaskScreen), findsNothing);
      unawaited(openFieldTaskPush(nav.currentState!, const {'type': 'field_task', 'task_id': '102', 'event': 'done'}));
      await settle(t, seconds: 2);
      expect(find.byType(FieldTaskScreen), findsOneWidget);
      expect(find.text('مهمّة #102'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });

  // لقطات المراجعة (لا تعمل إلّا بـ--dart-define=VISUAL_OUT=<مجلّد>): المهامّ والفريق والأنواع والمهمّة والأوراق، فاتحاً وداكناً.
  group('اللقطات', () {
    const out = String.fromEnvironment('VISUAL_OUT');
    tearDown(() {
      FieldTeamState.debugSet(null);
      return visualTearDown();
    });

    for (final dark in [false, true]) {
      final tag = dark ? '_dark' : '';
      testWidgets('اللقطات$tag', (t) async {
        final server = await _setUp();
        final inner = server.inner as VisualServer;
        Future<void> pumpAt(Widget home, double w, double s, {double h = 900}) => pumpVisual(
              t,
              VisualDevice('', Size(w, h), 2, dark: dark),
              home: (_) => home,
              wrap: (child) => Builder(
                builder: (ctx) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s)), child: child),
              ),
            );
        Future<void> snap(String name, double w, {double h = 900}) =>
            shoot(t, s1bSasOwner, 'field_$name$tag', VisualDevice('', Size(w, h), 2, dark: dark), inner);

        await pumpAt(const FieldTeamScreen(), 390, 1.0, h: 1500);
        await settle(t, seconds: 2);
        await t.tap(find.text('الكلّ'));
        await settle(t, seconds: 1);
        await snap('tasks_390', 390, h: 1500);
        await t.tap(find.text('الفريق (2)'));
        await settle(t, seconds: 2);
        await snap('staff_390', 390, h: 1500);
        await t.tap(find.text('الأنواع'));
        await settle(t, seconds: 2);
        await snap('types_390', 390, h: 1500);
        await t.tap(find.byKey(const ValueKey('field-type-add')));
        await settle(t, seconds: 1);
        await snap('type_sheet_390', 390, h: 1500);
        await t.pumpWidget(const SizedBox());

        await pumpAt(const FieldTeamScreen(), 320, 1.2, h: 1500);
        await settle(t, seconds: 2);
        await snap('tasks_320x12', 320, h: 1500);
        await t.tap(find.byKey(const ValueKey('field-new-task')));
        await settle(t, seconds: 2);
        await snap('new_task_320x12', 320, h: 1500);
        await t.pumpWidget(const SizedBox());

        await pumpAt(const FieldTaskScreen(taskId: 102), 390, 1.0, h: 2100);
        await settle(t, seconds: 2);
        await snap('task_390', 390, h: 2100);
        await t.pumpWidget(const SizedBox());

        await pumpAt(const FieldTaskScreen(taskId: 103), 320, 1.2, h: 2100);
        await settle(t, seconds: 2);
        await snap('task_failed_320x12', 320, h: 2100);
        await t.pumpWidget(const SizedBox());
      }, skip: out.isEmpty);
    }
  });
}
