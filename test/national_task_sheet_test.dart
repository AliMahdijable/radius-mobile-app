import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/national_portal_api.dart';
import 'package:rad_mysvcs/api/national_sheet_api.dart';
import 'package:rad_mysvcs/screens/national/national_task_sheet.dart';
import 'package:rad_mysvcs/screens/national/national_ticket_write.dart';
import 'package:rad_mysvcs/screens/national/national_work_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// تفاصيل المهمّة وتعليقاتها، وتعليقات الطلب، والتعليق عليهما — المشروع الوطنيّ (١ نوفمبر؛ عقد الخادم national_rest/contract.md §6):
/// نداءٌ واحد بلا إعادة، و«غير مؤكَّد» يُقال كما هو، والقفل الناجح لا يُقال «أُرسل»، وكلّه خلف المفتاح التجريبيّ (`lookups.beta`).
const _v = SimVariant(390, dark: false);
const _task = '5b2c1d0e-1111-4222-8333-944455556666';
const _req = '0a1b2c3d-1111-4222-8333-944455556666';

Map<String, Object?> _lookups({bool beta = true, Object? caps = const {}, Map<String, String?> locks = const {}, bool canWrite = true}) => {
      'success': true,
      'data': {
        'ticket_statuses': [],
        'ticket_categories': [],
        'request_types': [],
        'request_statuses': [],
        'zones': [],
        'transaction_types': [],
        'can_write': canWrite,
        'beta': beta,
        'caps': caps,
        'portal_locks': {'revenue': 'لا صلاحيّة «الإيرادات»', 'customer_wallet': null, 'sub_sessions': null, ...locks},
      },
    };

Map<String, Object?> _page(List<Map<String, Object?>> rows, {int page = 1, int pages = 1, int? total, Map<String, Object?> extra = const {}}) => {
      'success': true,
      'data': rows,
      'total': total ?? rows.length,
      'page': page,
      'size': 10,
      'page_count': pages,
      'fetched_at': '2026-11-01T07:00:00Z',
      'stale': false,
      ...extra,
    };

Map<String, Object?> _locked(String message) => {
      'success': true,
      'locked': true,
      'reason': 'no_permission',
      'title': 'لا صلاحيّة في البوّابة',
      'message': message,
      'data': null,
      'page': 1,
      'size': 10,
    };


Map<String, Object?> _taskDetail({bool comment = true, List<Map<String, Object?>>? comments = const [], bool commentsLocked = false}) => {
      'success': true,
      'data': {
        'id': _task,
        'title': 'Maintenance',
        'type': 'maintenance',
        'status': 'in progress',
        'description': 'ضعف إشارة عند المشترك',
        'created_at': '2026-10-30 10:00:00',
        'modified_at': '2026-10-31 09:00:00',
        'closed_at': null,
        'customer': {'id': '1721001', 'name': 'مريم عبد الله'},
        'zone': {'id': 'FBG1', 'name': 'FBG1'},
        'address': 'بغداد، الكرادة، محلّة 905',
        'line_of_business': 'FTTH',
        'request_id': null,
        'ticket': {'id': 't1', 'name': 'cc-26104567'},
        'comments': comments,
        'comments_total': comments?.length,
        'comments_locked': commentsLocked,
        'can': {'comment': comment},
      },
      'fetched_at': '2026-11-01T07:00:00Z',
      'stale': false,
    };

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
    NationalSheetApi.debugReset();
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet('watani', label: 'المشروع الوطني');
  });

  tearDown(() {
    NationalSheetApi.debugReset();
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  group('النماذج', () {
    test('ردّ الكتابة: القفل الناجح لا يُعدّ إرسالاً، وUNCONFIRMED «غير مؤكَّد»، وREPEATED رفضٌ برسالته', () {
      expect(NationalSheetApi.writeOf({'success': true}).ok, isTrue);
      final locked = NationalSheetApi.writeOf(_locked('لا صلاحيّة «إضافة تعليق»'));
      expect((locked.ok, locked.unconfirmed, locked.code, locked.message), (false, false, 'LOCKED', 'لا صلاحيّة «إضافة تعليق»'));
      final u = NationalSheetApi.writeOf({'success': false, 'code': 'UNCONFIRMED', 'message': 'لم يتأكّد إرسال التعليق'});
      expect((u.unconfirmed, u.message), (true, 'لم يتأكّد إرسال التعليق'));
      final rep = NationalSheetApi.writeOf({'success': false, 'code': 'REPEATED', 'message': 'أُرسل هذا التعليق للتوّ'});
      expect((rep.ok, rep.unconfirmed, rep.code, rep.message), (false, false, 'REPEATED', 'أُرسل هذا التعليق للتوّ'));
      expect(NationalSheetApi.writeOf({'success': false, 'code': 'BETA_OFF', 'message': 'تجريبيّ'}).code, 'BETA_OFF');
    });

    test('تفاصيل المهمّة: النوع اسمها، والتعليقات null حين قُفلت أو تعذّرت', () {
      final d = NationalTaskDetail.fromJson(Map<String, dynamic>.from(_taskDetail()['data'] as Map));
      expect((d.label, d.status, d.canComment, d.ticket?.name, d.modifiedAt),
          ('maintenance', 'in progress', true, 'cc-26104567', '2026-10-31 09:00:00'));
      final locked = NationalTaskDetail.fromJson(Map<String, dynamic>.from(_taskDetail(comments: null, commentsLocked: true)['data'] as Map));
      expect((locked.comments, locked.commentsLocked), (null, true));
      expect(NationalTaskDetail.fromJson({'title': 'x', 'status': 'not started'}).canComment, isFalse);
    });
  });

  group('المهمّة والطلب: التفاصيل والتعليقات', () {
    Future<void> openTask(WidgetTester t) async {
      await pumpSim(t, _v,
          home: (_) => simLauncher((c) => showNationalTaskSheet(c, const NationalTask(id: _task, title: 'Maintenance', status: ''))));
      await simOpen(t);
    }

    testWidgets('ورقة المهمّة: التفاصيل والوصف والتعليقات، والتعليق يرسل {text} مرّةً ثمّ تُقرأ ثانيةً', (t) async {
      server.reply(
          'GET',
          '/api/v2/ftth/tasks/$_task',
          200,
          _taskDetail(comments: [
            {'id': 'c1', 'text': 'الفنّي في الطريق', 'by': 'مركز الاتصال', 'by_type': 'Agent', 'at': '2026-10-31 09:00:00'},
          ]));
      server.reply('POST', '/api/v2/ftth/tasks/$_task/comments', 200, {'success': true});
      await openTask(t);
      expect(find.text('صيانة'), findsWidgets);
      expect(find.text('قيد التنفيذ'), findsOneWidget);
      expect(find.text('بغداد، الكرادة، محلّة 905'), findsOneWidget);
      expect(find.text('ضعف إشارة عند المشترك'), findsOneWidget);
      expect(find.text('cc-26104567'), findsOneWidget);
      expect(find.text('التعليقات (1)'), findsOneWidget);
      expect(find.text('الفنّي في الطريق'), findsOneWidget);
      final box = find.byType(NationalCommentBox);
      await t.ensureVisible(box);
      await t.enterText(find.descendant(of: box, matching: find.byType(TextField)), 'تمّ الإصلاح');
      await t.pumpAndSettle();
      final before = server.calls('GET', '/api/v2/ftth/tasks/$_task').length;
      await t.tap(find.descendant(of: box, matching: find.text('إرسال')));
      await t.pumpAndSettle();
      expect(server.bodies('POST', '/api/v2/ftth/tasks/$_task/comments').single, {'text': 'تمّ الإصلاح'});
      expect(server.calls('GET', '/api/v2/ftth/tasks/$_task').length, before + 1);
      await simDrain(t);
    });

    testWidgets('«غير مؤكَّد» يُقال كما هو ولا إعادة تلقائيّة', (t) async {
      server.reply('GET', '/api/v2/ftth/tasks/$_task', 200, _taskDetail());
      server.reply('POST', '/api/v2/ftth/tasks/$_task/comments', 202, {
        'success': false,
        'code': 'UNCONFIRMED',
        'message': 'لم يتأكّد إرسال التعليق — افتح المهمّة وتحقّق قبل إعادته',
      });
      await openTask(t);
      expect(find.text('لا توجد تعليقات على المهمّة حتى الآن.'), findsOneWidget);
      final box = find.byType(NationalCommentBox);
      await t.ensureVisible(box);
      await t.enterText(find.descendant(of: box, matching: find.byType(TextField)), 'تحديث');
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: box, matching: find.text('إرسال')));
      await t.pumpAndSettle();
      expect(find.text('لم يتأكّد إرسال التعليق — افتح المهمّة وتحقّق قبل إعادته'), findsOneWidget);
      expect(server.calls('POST', '/api/v2/ftth/tasks/$_task/comments'), hasLength(1), reason: 'لا إعادة تلقائيّة');
      await simDrain(t);
    });

    testWidgets('«أُرسل للتوّ» (REPEATED) رسالة الخادم نفسها؛ والقفل الناجح لا يُقال «أُرسل»', (t) async {
      server.reply('GET', '/api/v2/ftth/tasks/$_task', 200, _taskDetail());
      var n = 0;
      server.on('POST', '/api/v2/ftth/tasks/$_task/comments', (_) {
        n += 1;
        if (n == 1) return const SimReply(409, {'success': false, 'code': 'REPEATED', 'message': 'أُرسل هذا التعليق للتوّ'});
        return SimReply(200, _locked('لا صلاحيّة «إضافة تعليق على مهمّة» في البوّابة'));
      });
      await openTask(t);
      final box = find.byType(NationalCommentBox);
      await t.ensureVisible(box);
      await t.enterText(find.descendant(of: box, matching: find.byType(TextField)), 'تحديث');
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: box, matching: find.text('إرسال')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('أُرسل هذا التعليق للتوّ'), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: box, matching: find.text('إرسال')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('لا صلاحيّة «إضافة تعليق على مهمّة» في البوّابة'), findsOneWidget);
      expect(find.text('أُرسل التعليق'), findsNothing);
      await simDrain(t);
    });

    testWidgets('بلا can.comment لا صندوق؛ والتعليقات المقفلة قفلٌ بسببه لا «لا تعليقات»؛ و«إضافة تعليق» المقفلة بمكانها بسببها', (t) async {
      server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups(locks: {
        'task_comments': 'لا صلاحيّة «تعليقات المهامّ» في البوّابة',
        'task_comment_add': 'لا صلاحيّة «إضافة تعليق على مهمّة» في البوّابة',
      }));
      server.reply('GET', '/api/v2/ftth/tasks/$_task', 200, _taskDetail(comment: false, comments: null, commentsLocked: true));
      await openTask(t);
      expect(find.byType(NationalCommentBox), findsNothing);
      expect(find.text('لا صلاحيّة «تعليقات المهامّ» في البوّابة'), findsOneWidget);
      expect(find.text('لا توجد تعليقات على المهمّة حتى الآن.'), findsNothing);
      expect(find.text('إضافة تعليق'), findsOneWidget);
      expect(find.text('لا صلاحيّة «إضافة تعليق على مهمّة» في البوّابة'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('بلا can.comment ولا سبب قفل (الكتابة مطفأة للحساب) ⇒ لا صندوق ولا قفل', (t) async {
      server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups());
      server.reply('GET', '/api/v2/ftth/tasks/$_task', 200, _taskDetail(comment: false));
      await openTask(t);
      expect(find.text('التعليقات'), findsOneWidget);
      expect(find.byType(NationalCommentBox), findsNothing);
      expect(find.text('إضافة تعليق'), findsNothing);
      await simDrain(t);
    });

    testWidgets('المهمّة كلّها مقفلة (ردٌّ مقفل) ⇒ قفلٌ بسببه لا خطأ', (t) async {
      server.reply('GET', '/api/v2/ftth/tasks/$_task', 200, _locked('لا صلاحيّة «المهامّ» في البوّابة'));
      await openTask(t);
      expect(find.text('لا صلاحيّة «المهامّ» في البوّابة'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsNothing);
      await simDrain(t);
    });

    testWidgets('ورقة الطلب: تعليقاته (pending ثمّ تصل) والتعليق يرسل {text, type} مرّةً ثمّ تُقرأ ثانيةً', (t) async {
      server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups());
      server.reply('GET', '/api/v2/ftth/counts', 200, {
        'success': true,
        'data': {'tasks_open': 1, 'requests_open': 1, 'beta': true}
      });
      server.reply(
          'GET',
          '/api/v2/ftth/requests',
          200,
          _page([
            {
              'id': _req,
              'type': 'NewAddressRequest',
              'type_label': '',
              'status': 'New',
              'customer': {'id': '7', 'name': 'حيدر'},
              'created_at': '2026-10-29 11:01:00'
            },
          ]));
      server.reply('GET', '/api/v2/ftth/requests/$_req', 200, {
        'success': true,
        'data': {
          'can': {'cancel': false},
          'detail': {'status': 'New', 'created_at': '2026-10-29 11:01:00', 'tasks': []},
          'logs': [],
          'logs_pending': false,
        },
      });
      var n = 0;
      server.on('GET', '/api/v2/ftth/requests/$_req/comments', (_) {
        n += 1;
        if (n == 1) return const SimReply(200, {'success': true, 'pending': true, 'page': 1, 'size': 10});
        return SimReply(
            200,
            _page(
              [
                {'id': 'c1', 'text': 'بانتظار توقيع المشترك', 'by': 'الدعم', 'by_type': 'Agent', 'at': '2026-10-30 10:00:00'},
              ],
              extra: {
                'can': {'comment': true},
              },
            ));
      });
      server.reply('POST', '/api/v2/ftth/requests/$_req/comments', 200, {'success': true});
      await pumpSim(t, _v, home: (_) => const NationalWorkScreen());
      await t.tap(find.text('عنوان جديد'));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('جارٍ جلب التعليقات من البوّابة…'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      expect(find.text('بانتظار توقيع المشترك'), findsOneWidget);
      final box = find.byType(NationalCommentBox);
      await t.ensureVisible(box);
      await t.enterText(find.descendant(of: box, matching: find.byType(TextField)), 'وقّع اليوم');
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: box, matching: find.text('إرسال')));
      await t.pumpAndSettle();
      expect(server.bodies('POST', '/api/v2/ftth/requests/$_req/comments').single, {'text': 'وقّع اليوم', 'type': 'NewAddressRequest'});
      expect(server.calls('GET', '/api/v2/ftth/requests/$_req/comments'), hasLength(3), reason: 'تُقرأ ثانيةً بعد الإرسال');
      await simDrain(t);
    });

    testWidgets('قائمة المهامّ: الكرت يفتح ورقة المهمّة حين التجريبيّ مفتوح', (t) async {
      server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups());
      server.reply('GET', '/api/v2/ftth/counts', 200, {
        'success': true,
        'data': {'tasks_open': 1, 'requests_open': 0, 'beta': true}
      });
      server.reply(
          'GET',
          '/api/v2/ftth/tasks',
          200,
          _page([
            {
              'id': _task,
              'title': 'Maintenance',
              'status': 'Open',
              'due_at': '2026-11-02 12:00:00',
              'customer': {'id': '1', 'name': 'مريم'}
            },
          ]));
      server.reply('GET', '/api/v2/ftth/tasks/$_task', 200, _taskDetail());
      await pumpSim(t, _v, home: (_) => const NationalWorkScreen(initialTab: 1));
      await t.tap(find.text('صيانة'));
      await t.pumpAndSettle();
      expect(find.byType(NationalTaskSheet), findsOneWidget);
      expect(find.text('بغداد، الكرادة، محلّة 905'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('المفتاح التجريبيّ مطفأ: لا ورقة للمهمّة ولا تعليقات في ورقة الطلب', (t) async {
      server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups(beta: false));
      server.reply('GET', '/api/v2/ftth/counts', 200, {
        'success': true,
        'data': {'tasks_open': 1, 'requests_open': 0, 'beta': false}
      });
      server.reply(
          'GET',
          '/api/v2/ftth/tasks',
          200,
          _page([
            {
              'id': _task,
              'title': 'Maintenance',
              'status': 'Open',
              'due_at': '2026-11-02 12:00:00',
              'customer': {'id': '1', 'name': 'مريم'}
            },
          ]));
      server.reply('GET', '/api/v2/ftth/requests', 200, _page([
        {'id': _req, 'type': 'NewAddressRequest', 'type_label': '', 'status': 'New', 'customer': {'id': '7', 'name': 'حيدر'}, 'created_at': '2026-10-29 11:01:00'},
      ]));
      server.reply('GET', '/api/v2/ftth/requests/$_req', 200, {
        'success': true,
        'data': {
          'can': {'cancel': false},
          'detail': {'status': 'New', 'created_at': '2026-10-29 11:01:00', 'tasks': []},
          'logs': [],
          'logs_pending': false,
        },
      });
      await pumpSim(t, _v, home: (_) => const NationalWorkScreen(initialTab: 1));
      await t.tap(find.text('صيانة'));
      await t.pumpAndSettle();
      expect(find.byType(NationalTaskSheet), findsNothing);
      expect(server.calls('GET', '/api/v2/ftth/tasks/$_task'), isEmpty);

      await t.tap(find.text('الطلبات'));
      await t.pumpAndSettle();
      await t.tap(find.text('عنوان جديد'));
      await t.pumpAndSettle();
      expect(find.text('سجلّ الطلب'), findsOneWidget);
      expect(find.byType(NationalRequestComments), findsNothing);
      expect(server.calls('GET', '/api/v2/ftth/requests/$_req/comments'), isEmpty);
      await simDrain(t);
    });
  });
}
