import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/national/national_ticket_write.dart';
import 'package:rad_mysvcs/screens/national/national_tickets_screen.dart';
import 'package:rad_mysvcs/screens/national/national_work_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// المشروع الوطنيّ — الكتابة من التطبيق (المرحلة ٢، ٣١ أكتوبر): «تذكرة جديدة» للزون أو لمشترك (الجسم كما يريده الخادم
/// server/watani/wataniPortalRoutes.js)، و«غير مؤكَّد» يعيد المرجع نفسه (لا تذكرة ثانية)، والتعليق، وإلغاء الطلب بتأكيد،
/// والأزرار حين يقول الخادم can_write/can فقط، والموظّف بلا «تعديل المشترك» يراها مقفلةً بمكانها.
const _v = SimVariant(390, dark: false);
const _uuid = '0a1b2c3d-1111-4222-8333-944455556666';
final _uuidRe = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

Map<String, Object?> _lookups({bool canWrite = true}) => {
      'success': true,
      'data': {
        'ticket_statuses': [
          {'id': 's-new', 'name': 'New'},
        ],
        'ticket_categories': [
          {'id': 'c1', 'name': 'Service request'},
          {'id': 'c3', 'name': 'Incident'},
        ],
        'request_types': [],
        'request_statuses': [],
        'zones': [
          {'id': 'FBG1', 'name': 'FBG1'},
          {'id': 'FBG2', 'name': 'FBG2'},
        ],
        'transaction_types': [],
        'can_write': canWrite,
      },
    };

const _ticketRow = {
  'id': 't1',
  'display_id': 'cc-26104567',
  'source': 'call_center',
  'title': 'ضعف إشارة',
  'summary': 'الضوء أحمر',
  'status': 'In progress',
  'customer': {'id': '7', 'name': 'مريم عبد الله'},
  'zone': {'id': 'FBG1', 'name': 'FBG1'},
  'comments': 0,
  'attachments': 0,
  'created_at': '2026-10-30 14:21:00',
};

Map<String, Object?> _detail({bool comment = true, bool schedule = false}) => {
      'success': true,
      'data': {
        'id': 't1',
        'display_id': 'cc-26104567',
        'title': 'ضعف إشارة',
        'details': 'الضوء أحمر منذ يومين',
        'status': 'In progress',
        'category': {'id': 'c3', 'name': 'Incident'},
        'issue': null,
        'zone': {'id': 'FBG1', 'name': 'FBG1'},
        'customer': {'id': '7', 'name': 'مريم عبد الله'},
        'created_at': '2026-10-30 10:00:00',
        'comments': [],
        'comments_total': 0,
        'can': {'comment': comment, 'schedule': schedule},
      },
    };

Finder _inSheet(Finder f) => find.descendant(of: find.byType(NationalNewTicketSheet), matching: f);

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet('watani', label: 'المشروع الوطني');
    server.reply('GET', '/api/v2/ftth/counts', 200, {'success': true, 'data': {'tasks_open': 1, 'requests_open': 1, 'requests_action_required': 0}});
    server.reply('GET', '/api/v2/ftth/tickets', 200, {'success': true, 'data': [_ticketRow], 'total': 1, 'page': 1, 'page_count': 1});
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  Future<void> openNew(WidgetTester t) async {
    await pumpSim(t, _v, home: (_) => const NationalTicketsScreen());
    await t.tap(find.widgetWithText(FloatingActionButton, 'تذكرة جديدة'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
  }

  testWidgets('تذكرة للزون: الزون والنوع والعنوان والوصف ⇒ جسم الخادم بمرجعٍ UUID وبلا مشترك، ثمّ ورقة التذكرة الجديدة', (t) async {
    server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups());
    server.reply('POST', '/api/v2/ftth/tickets', 200, {
      'success': true,
      'data': {'id': 't9', 'display_id': 'P-261031', 'title': 'كابينة مكسورة', 'status': 'New'},
    });
    server.reply('GET', '/api/v2/ftth/tickets/t9', 200, _detail());
    await openNew(t);
    expect(find.text('تُفتح باسم حسابك في بوّابة الوطني'), findsOneWidget);

    await t.tap(_inSheet(find.text('للزون')));
    await t.pumpAndSettle();
    await t.tap(_inSheet(find.text('FBG2')));
    await t.tap(_inSheet(find.text('عطل / انقطاع')));
    await t.pumpAndSettle();
    final fields = _inSheet(find.byType(TextField));
    await t.enterText(fields.at(0), 'كابينة مكسورة');
    await t.enterText(fields.at(1), 'الكابينة رقم ٣ مكسورة\nوالأسلاك ظاهرة');
    await t.pumpAndSettle();
    await t.tap(_inSheet(find.text('فتح التذكرة')));
    await t.pumpAndSettle();

    final body = server.bodies('POST', '/api/v2/ftth/tickets').single;
    expect(body['client_ref'], matches(_uuidRe));
    expect(body['category'], 'c3');
    expect(body['zone'], 'FBG2');
    expect(body['summary'], 'كابينة مكسورة');
    expect(body['details'], 'الكابينة رقم ٣ مكسورة\nوالأسلاك ظاهرة');
    expect(body.containsKey('customer_id'), isFalse, reason: 'تذكرة زون بلا مشترك');
    expect(server.calls('GET', '/api/v2/ftth/tickets/t9'), isNotEmpty, reason: 'تُفتح ورقة التذكرة الجديدة');
    await t.pump(const Duration(seconds: 5));
    await simDrain(t);
  });

  testWidgets('تذكرة لمشترك: البحث ⇒ اختياره ⇒ customer_id وزون اشتراكه؛ و«غير مؤكَّد» ⇒ «تحقّق» بالمرجع نفسه', (t) async {
    server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups());
    server.reply('GET', '/api/subscribers/search', 200, {
      'success': true,
      'data': [
        {'idx': 's-1', 'username': 'FBG885F15P2', 'firstname': 'مريم', 'lastname': 'عبد الله', 'watani': {'customerId': '1721001', 'zoneId': 'FBG1', 'zone': 'FBG1'}},
      ],
    });
    var n = 0;
    server.on('POST', '/api/v2/ftth/tickets', (o) {
      n += 1;
      if (n == 1) return const SimReply(202, {'success': false, 'code': 'UNCONFIRMED', 'message': 'لم يتأكّد فتح التذكرة — لا تفتحها من جديد'});
      return const SimReply(200, {'success': true, 'data': {'id': 't9', 'display_id': 'P-1', 'title': 'انقطاع', 'status': 'New'}});
    });
    server.reply('GET', '/api/v2/ftth/tickets/t9', 200, _detail());
    await openNew(t);

    await t.enterText(_inSheet(find.byType(TextField)).first, 'مريم');
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(server.calls('GET', '/api/subscribers/search').last.queryParameters['search'], 'مريم');
    await t.tap(_inSheet(find.text('مريم عبد الله')));
    await t.pumpAndSettle();
    expect(_inSheet(find.text('FBG1')), findsOneWidget, reason: 'زون اشتراكه (القيمة بخطّها اللاتينيّ وحدها)');
    await t.tap(_inSheet(find.text('طلب خدمة')));
    await t.pumpAndSettle();
    final fields = _inSheet(find.byType(TextField));
    await t.enterText(fields.at(0), 'انقطاع');
    await t.enterText(fields.at(1), 'لا إنترنت منذ الصباح');
    await t.pumpAndSettle();
    await t.tap(_inSheet(find.text('فتح التذكرة')));
    await t.pumpAndSettle();
    expect(find.text('لم يتأكّد فتح التذكرة — لا تفتحها من جديد'), findsOneWidget);
    expect(_inSheet(find.text('تحقّق')), findsOneWidget);

    await t.tap(_inSheet(find.text('تحقّق')));
    await t.pumpAndSettle();
    final bodies = server.bodies('POST', '/api/v2/ftth/tickets');
    expect(bodies, hasLength(2));
    expect(bodies[1]['client_ref'], bodies[0]['client_ref'], reason: 'المرجع نفسه ⇒ الخادم يقرأ أوّلاً ولا يفتح ثانية');
    expect([bodies[0]['customer_id'], bodies[0]['zone'], bodies[0]['subscriber'], bodies[0]['category']], ['1721001', 'FBG1', 's-1', 'c1']);
    await t.pump(const Duration(seconds: 5));
    await simDrain(t);
  });

  testWidgets('التعليق: يظهر حين can.comment ويرسل {text} ثمّ تُقرأ التذكرة ثانيةً', (t) async {
    server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups());
    server.reply('GET', '/api/v2/ftth/tickets/t1', 200, _detail());
    server.reply('POST', '/api/v2/ftth/tickets/t1/comments', 200, {'success': true});
    await pumpSim(t, _v, home: (_) => const NationalTicketsScreen());
    await t.tap(find.text('ضعف إشارة'));
    await t.pumpAndSettle();
    final box = find.byType(NationalCommentBox);
    expect(box, findsOneWidget);
    await t.enterText(find.descendant(of: box, matching: find.byType(TextField)), 'تمّ الإصلاح');
    await t.pumpAndSettle();
    final before = server.calls('GET', '/api/v2/ftth/tickets/t1').length;
    await t.tap(find.descendant(of: box, matching: find.text('إرسال')));
    await t.pumpAndSettle();
    expect(server.bodies('POST', '/api/v2/ftth/tickets/t1/comments').single, {'text': 'تمّ الإصلاح'});
    expect(server.calls('GET', '/api/v2/ftth/tickets/t1').length, before + 1);
    await t.pump(const Duration(seconds: 5));
    await simDrain(t);
  });

  testWidgets('إلغاء الطلب: بتأكيد ⇒ {confirm, type} ثمّ القائمة من جديد', (t) async {
    server.reply('GET', '/api/v2/ftth/requests', 200, {
      'success': true,
      'data': [
        {'id': _uuid, 'type': 'CustomerOnboardingRequest', 'type_label': '', 'status': 'New', 'customer': {'id': '7', 'name': 'حيدر'}, 'cancelable': true, 'created_at': '2026-10-29 11:01:00'},
      ],
      'total': 1,
      'page': 1,
      'page_count': 1,
    });
    server.reply('GET', '/api/v2/ftth/requests/$_uuid', 200, {
      'success': true,
      'data': {
        'can': {'cancel': true},
        'detail': {'status': 'New', 'cancelable': true, 'created_at': '2026-10-29 11:01:00', 'tasks': []},
        'logs': [],
        'logs_pending': false,
      },
    });
    server.reply('POST', '/api/v2/ftth/requests/$_uuid/cancel', 200, {'success': true});
    await pumpSim(t, _v, home: (_) => const NationalWorkScreen());
    await t.tap(find.text('تسجيل زبون جديد'));
    await t.pumpAndSettle();
    final lists = server.calls('GET', '/api/v2/ftth/requests').length;
    await t.ensureVisible(find.widgetWithText(OutlinedButton, 'إلغاء الطلب'));
    await t.tap(find.widgetWithText(OutlinedButton, 'إلغاء الطلب'));
    await t.pumpAndSettle();
    expect(find.textContaining('لا رجوع بعد الإلغاء'), findsOneWidget);
    await t.tap(find.text('إلغاء الطلب').last);
    await t.pumpAndSettle();
    expect(server.bodies('POST', '/api/v2/ftth/requests/$_uuid/cancel').single, {'confirm': true, 'type': 'CustomerOnboardingRequest'});
    expect(server.calls('GET', '/api/v2/ftth/requests').length, greaterThan(lists), reason: 'القائمة من جديد');
    await t.pump(const Duration(seconds: 5));
    await simDrain(t);
  });

  testWidgets('الموظّف بلا «تعديل المشترك»: «تذكرة جديدة» بمكانها مقفلة ولا ورقة، والتعليق مقفل', (t) async {
    PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
    server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups());
    server.reply('GET', '/api/v2/ftth/tickets/t1', 200, _detail());
    await openNew(t);
    expect(find.byType(NationalNewTicketSheet), findsNothing);
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    await t.tap(find.text('ضعف إشارة'));
    await t.pumpAndSettle();
    expect(find.text('التعليق — لا صلاحيّة'), findsOneWidget);
    expect(server.calls('POST', '/api/v2/ftth/tickets/t1/comments'), isEmpty);
    await t.pump(const Duration(seconds: 5));
    await simDrain(t);
  });

  testWidgets('الكتابة غير مفتوحة للحساب (can_write=false): لا زرّ «تذكرة جديدة» ولا تعليق', (t) async {
    server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups(canWrite: false));
    server.reply('GET', '/api/v2/ftth/tickets/t1', 200, _detail(comment: false));
    await pumpSim(t, _v, home: (_) => const NationalTicketsScreen());
    expect(find.byType(FloatingActionButton), findsNothing);
    await t.tap(find.text('ضعف إشارة'));
    await t.pumpAndSettle();
    expect(find.byType(NationalCommentBox), findsNothing);
    await simDrain(t);
  });
}
