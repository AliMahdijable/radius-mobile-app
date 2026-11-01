import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/national_sheet_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/national/national_subscriber_extras.dart';
import 'package:rad_mysvcs/screens/national/national_task_sheet.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «من بوّابة الوطني» في صفحة مشترك الوطنيّ (١ نوفمبر؛ عقد الخادم national_rest/contract.md §1–§3): محفظته وسجل الأخطاء وتذاكره
/// ومهامّه وجلساته — تُجلب حين تُفتح (عشرةً في المرّة، و«المزيد»)، خلف المفتاح التجريبيّ (`lookups.beta`)، و«لا صلاحيّة في البوّابة»
/// قفلٌ بمكانه بسببه (لا خطأ ولا قائمة فارغة)، والموظّف بلا مفتاح القسم يراه مقفلاً بمكانه.
const _v = SimVariant(390, dark: false);
const _idx = '13293073';
const _task = '5b2c1d0e-1111-4222-8333-944455556666';
const _base = '/api/v2/ftth/subscriptions/$_idx';

const _lockMsg =
    'المستخدم الذي دخلت به في المشروع الوطني لا يملك صلاحيّة «تذاكر المشترك» في البوّابة — اطلبها من الشركة أو ادخل بالمستخدم الرئيسيّ للشريك';

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

Subscriber _sub() => Subscriber.fromJson({
      'idx': _idx,
      'username': 'FBG885F15P1',
      'firstname': 'مريم',
      'lastname': 'عبد الله',
      'expiration': '2026-11-20 10:00:00',
      'remaining_days': 19,
    });

Map<String, Object?> _walletRow(String type, num amount, String at) => {
      'id': 'tx-$at',
      'at': at,
      'type': type,
      'amount': amount,
      'direction': amount < 0 ? 'out' : 'in',
      'owner': 'Customer',
      'balance_after': null,
      'subscription': {'id': _idx, 'name': 'BASIC', 'starts': '2026-10-21', 'ends': '2026-11-20'},
      'pay_method': 'Card',
      'by': null,
      'by_name': null,
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
    test('المفتاح التجريبيّ والأقفال: caps=null لا يقفل شيئاً، وportal_locks سببٌ جاهز', () {
      final b = NationalBeta.fromJson({
        'beta': true,
        'can_write': true,
        'caps': null,
        'portal_locks': {'revenue': 'لا صلاحيّة «الإيرادات»', 'sub_errors': null, 'customer_wallet': ''},
      });
      expect((b.on, b.canWrite, b.caps), (true, true, null));
      expect(b.lockOf('revenue'), 'لا صلاحيّة «الإيرادات»');
      expect(b.lockOf('sub_errors'), isNull);
      expect(b.lockOf('customer_wallet'), isNull, reason: 'نصٌّ فارغ لا يقفل');
      expect(NationalBeta.fromJson(const {}).on, isFalse);
    });

    test('ردٌّ مقفل ناجح ⇒ قفلٌ بعنوانه وسببه؛ وBETA_OFF قفلٌ كذلك؛ وغيره لا', () {
      final l = NationalLock.of(_locked(_lockMsg))!;
      expect((l.title, l.message), ('لا صلاحيّة في البوّابة', _lockMsg));
      expect(NationalLock.of({'success': false, 'code': 'BETA_OFF', 'message': 'تجريبيّ'})!.message, 'تجريبيّ');
      expect(NationalLock.of({'success': false, 'code': 'FTTH_FORBIDDEN', 'locked': true, 'message': 'لا'})!.message, 'لا');
      expect(NationalLock.of({'success': false, 'code': 'FTTH_BUSY', 'message': 'مشغولة'}), isNull);
      expect(NationalLock.of(_page(const [])), isNull);
    });

    test('الجلسة والخطأ والرصيد: null يبقى null (لا صفر كاذب)', () {
      final s = NationalSessionRow.fromJson(
          {'started_at': '2026-11-01 08:00:00', 'duration_s': 3725, 'down': 1073741824, 'up': null, 'status': 'Online', 'ip': '10.1.2.3'});
      expect((s.seconds, s.down, s.up, s.live, s.ip), (3725, 1073741824, null, true, '10.1.2.3'));
      expect(NationalSessionRow.fromJson({'status': 'Offline'}).live, isFalse);
      expect(nationalDuration(3725), '1:02 ساعة');
      expect(nationalDuration(600), '10 دقائق');
      expect(nationalDuration(20), 'أقلّ من دقيقة');
      expect(nationalDuration(null), '—');
      final e = NationalErrorRow.fromJson({'at': '2026-11-01 07:00:00', 'message': 'Wrong password', 'username': 'FBG885F15P1'});
      expect((e.message, e.username), ('Wrong password', 'FBG885F15P1'));
      expect(NationalCustomerBalance.fromRaw({'balance': null}).balance, isNull);
      final bal = NationalCustomerBalance.fromRaw({
        'balance': {'balance': 15000, 'credit': null, 'currency': 'IQD'},
        'balance_locked': false
      });
      expect((bal.balance, bal.credit, bal.locked), (15000, null, false));
      expect(NationalCustomerBalance.fromRaw({'balance': null, 'balance_locked': true}).locked, isTrue);
    });

    test('shownFor: الوطنيّ وحده، خارج «كل الشركات»', () {
      expect(NationalSubscriberExtras.shownFor(_sub()), isTrue);
      ProviderService.debugSet('nabd', label: 'نبض');
      expect(NationalSubscriberExtras.shownFor(_sub()), isFalse);
      ProviderService.debugSet(null);
      expect(NationalSubscriberExtras.shownFor(_sub()), isFalse);
    });
  });

  group('صفحة المشترك: «من بوّابة الوطني»', () {
    Future<void> pumpExtras(WidgetTester t) async {
      await pumpSim(
        t,
        _v,
        home: (_) => Scaffold(
          body: ListView(padding: const EdgeInsets.all(16), children: [NationalSubscriberExtras(sub: _sub())]),
        ),
      );
    }

    testWidgets('المفتاح التجريبيّ مطفأ ⇒ لا كرت ولا جلب', (t) async {
      server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups(beta: false));
      await pumpExtras(t);
      expect(find.text('من بوّابة الوطني'), findsNothing);
      expect(server.requests.where((r) => r.path.startsWith(_base)), isEmpty);
    });

    testWidgets('مطويٌّ بلا جلب؛ «المحفظة» تجلب حين تُفتح: الرصيد والحركات، و«المزيد» للصفحة التالية', (t) async {
      server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups());
      server.on('GET', '$_base/wallet', (o) {
        final page = int.parse(o.queryParameters['page'].toString());
        return SimReply(
          200,
          _page(
            [page == 1 ? _walletRow('PLAN_RENEW', -35000, '2026-10-21 10:00:00') : _walletRow('WALLET_TOPUP', 35000, '2026-10-20 09:00:00')],
            page: page,
            pages: 2,
            total: 2,
            extra: {
              'balance': {'balance': 0, 'credit': null, 'currency': 'IQD'},
              'balance_locked': false,
            },
          ),
        );
      });
      await pumpExtras(t);
      expect(find.text('من بوّابة الوطني'), findsOneWidget);
      for (final l in ['المحفظة', 'سجل الأخطاء', 'التذاكر', 'المهامّ', 'الجلسات']) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      expect(server.requests.where((r) => r.path.startsWith(_base)), isEmpty, reason: 'لا جلب قبل الفتح');

      await t.tap(find.text('المحفظة'));
      await t.pumpAndSettle();
      final q = server.calls('GET', '$_base/wallet').single.queryParameters;
      expect((q['page'], q['size']), (1, 10));
      expect(find.text('رصيد محفظة المشترك'), findsOneWidget);
      expect(find.text('0'), findsOneWidget, reason: 'رصيدٌ صفرٌ معروف يُقال صفراً');
      expect(find.text('تجديد'), findsOneWidget);
      expect(find.text('−35,000'), findsOneWidget);
      expect(find.text('1 من 2 حركة'), findsOneWidget);

      await t.tap(find.text('المزيد'));
      await t.pumpAndSettle();
      expect(server.calls('GET', '$_base/wallet').last.queryParameters['page'], 2);
      expect(find.text('شحن المحفظة'), findsOneWidget);
      expect(find.text('المزيد'), findsNothing);

      // الطيّ ثمّ الفتح: من الذاكرة بلا جلبٍ ثانٍ
      await t.tap(find.text('المحفظة'));
      await t.pumpAndSettle();
      expect(find.text('رصيد محفظة المشترك'), findsNothing);
      await t.tap(find.text('المحفظة'));
      await t.pumpAndSettle();
      expect(server.calls('GET', '$_base/wallet'), hasLength(2));
    });

    testWidgets('الرصيد وحده مقفل (balance_locked) ⇒ «لا صلاحيّة» مكان الرقم، والحركات تظهر', (t) async {
      server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups());
      server.reply('GET', '$_base/wallet', 200,
          _page([_walletRow('PLAN_RENEW', -35000, '2026-10-21 10:00:00')], extra: {'balance': null, 'balance_locked': true}));
      await pumpExtras(t);
      await t.tap(find.text('المحفظة'));
      await t.pumpAndSettle();
      expect(find.text('لا صلاحيّة'), findsOneWidget);
      expect(find.text('تجديد'), findsOneWidget);
    });

    testWidgets('قسمٌ واحد مفتوح: «الجلسات» تطوي «سجل الأخطاء»؛ الجلسة الجارية «متصل الآن»', (t) async {
      server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups());
      server.reply(
          'GET',
          '$_base/errors',
          200,
          _page([
            {'at': '2026-11-01 07:12:00', 'message': 'Authentication rejected', 'username': 'FBG885F15P1'},
            {'at': '2026-10-31 07:12:00', 'message': 'MAC address mismatch', 'username': 'FBG885F15P9'},
          ]));
      server.reply(
          'GET',
          '$_base/sessions',
          200,
          _page([
            {
              'started_at': '2026-11-01 08:00:00',
              'duration_s': 3725,
              'ip': '10.20.30.40',
              'mac': 'AA:BB',
              'status': 'Online',
              'down': 2147483648,
              'up': 104857600
            },
            {
              'started_at': '2026-10-31 20:00:00',
              'duration_s': 11400,
              'ip': null,
              'mac': null,
              'status': 'Offline',
              'down': 524288000,
              'up': 52428800
            },
          ]));
      await pumpExtras(t);
      await t.tap(find.text('سجل الأخطاء'));
      await t.pumpAndSettle();
      expect(simText('Authentication rejected'), findsOneWidget);
      expect(find.textContaining('اليوزر'), findsOneWidget, reason: 'يوزرٌ آخر غير المشترك وحده يُذكر');
      await t.tap(find.text('الجلسات'));
      await t.pumpAndSettle();
      expect(simText('Authentication rejected'), findsNothing, reason: 'قسمٌ واحد في المرّة');
      expect(find.text('متصل الآن'), findsOneWidget);
      expect(simText('المدّة 1:02 ساعة · 10.20.30.40'), findsOneWidget);
      expect(simText('↓ 2.0 GB'), findsOneWidget);
      expect(find.text('المدّة 3:10 ساعة'), findsOneWidget);
    });

    testWidgets('ردٌّ مقفل من البوّابة ⇒ قفلٌ بعنوانه وسببه لا «إعادة»؛ وportal_locks ⇒ مقفلٌ بلا جلب', (t) async {
      server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups(locks: {'sub_sessions': 'لا صلاحيّة «سجلّ الجلسات» في البوّابة'}));
      server.reply('GET', '$_base/tickets', 200, _locked(_lockMsg));
      await pumpExtras(t);
      await t.tap(find.text('التذاكر'));
      await t.pumpAndSettle();
      expect(find.text('لا صلاحيّة في البوّابة'), findsOneWidget);
      expect(find.text(_lockMsg), findsOneWidget);
      expect(find.text('إعادة'), findsNothing);
      expect(find.text('لا تذاكر لهذا المشترك'), findsNothing, reason: 'القفل ليس قائمةً فارغة');
      await t.tap(find.text('الجلسات'));
      await t.pumpAndSettle();
      expect(find.text('لا صلاحيّة «سجلّ الجلسات» في البوّابة'), findsOneWidget);
      expect(server.calls('GET', '$_base/sessions'), isEmpty);
    });

    testWidgets('خطأٌ عابر (FTTH_BUSY) ⇒ رسالته و«إعادة» تجلب من جديد', (t) async {
      server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups());
      var n = 0;
      server.on('GET', '$_base/errors', (_) {
        n += 1;
        // ApiClient يعيد GET مرّةً بعد 503 (بوّابةٌ عابرة) — الخطأ يبقى في الاثنتين
        if (n <= 2) {
          return const SimReply(503, {'success': false, 'code': 'FTTH_BUSY', 'message': 'بوّابة المشروع الوطني مشغولة الآن — أعد المحاولة بعد دقائق'});
        }
        return SimReply(200, _page(const [], total: 0));
      });
      await pumpExtras(t);
      await t.tap(find.text('سجل الأخطاء'));
      await t.pumpAndSettle();
      expect(find.text('بوّابة المشروع الوطني مشغولة الآن — أعد المحاولة بعد دقائق'), findsOneWidget);
      await t.tap(find.text('إعادة'));
      await t.pumpAndSettle();
      expect(find.text('لا توجد أخطاء — الجلسة لا تحتوي على أخطاء'), findsOneWidget);
    });

    testWidgets('الموظّف بلا «التقارير الماليّة» ولا «سجلّ الحركات»: «المحفظة» مقفلةٌ بمكانها ولا جلب؛ والمهامّ تفتح ورقتها', (t) async {
      PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
      server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups());
      server.reply(
          'GET',
          '$_base/tasks',
          200,
          _page([
            {'id': _task, 'title': 'Maintenance'},
          ]));
      server.reply('GET', '/api/v2/ftth/tasks/$_task', 200, _taskDetail());
      await pumpExtras(t);
      expect(find.text('المحفظة'), findsOneWidget, reason: 'بمكانها لا تختفي');
      await t.tap(find.text('المحفظة'));
      await t.pump();
      expect(server.calls('GET', '$_base/wallet'), isEmpty);
      await t.pump(const Duration(seconds: 3));
      await t.tap(find.text('المهامّ'));
      await t.pumpAndSettle();
      expect(find.text('صيانة'), findsOneWidget);
      await t.tap(find.text('صيانة'));
      await t.pumpAndSettle();
      expect(find.byType(NationalTaskSheet), findsOneWidget);
      expect(find.text('قيد التنفيذ'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('الموظّف بـ«سجلّ حركات المشترك» وحده يفتح «المحفظة» (أيٌّ من المفتاحين)', (t) async {
      PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true, 'subscribers.view_activity': true});
      server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups());
      server.reply(
          'GET',
          '$_base/wallet',
          200,
          _page(const [],
              total: 0,
              extra: {
                'balance': {'balance': 2500, 'currency': 'IQD'}
              }));
      await pumpExtras(t);
      await t.tap(find.text('المحفظة'));
      await t.pumpAndSettle();
      expect(server.calls('GET', '$_base/wallet'), hasLength(1));
      expect(find.text('لا حركات في محفظة المشترك'), findsOneWidget);
    });

    testWidgets('pending ⇒ «جارٍ الجلب…» ثمّ الصفوف وحدها بعد ٤ث', (t) async {
      server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups());
      var n = 0;
      server.on('GET', '$_base/tickets', (_) {
        n += 1;
        if (n == 1) return const SimReply(200, {'success': true, 'pending': true, 'page': 1, 'size': 10});
        return SimReply(
            200,
            _page([
              {'id': 't1', 'display_id': 'cc-26104567', 'title': 'ضعف إشارة', 'summary': '', 'status': 'New', 'created_at': '2026-10-30 14:21:00'},
            ]));
      });
      await pumpExtras(t);
      await t.tap(find.text('التذاكر'));
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('جارٍ الجلب من بوّابة المشروع الوطني…'), findsOneWidget);
      expect(server.calls('GET', '$_base/tickets'), hasLength(1));
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      expect(find.text('ضعف إشارة'), findsOneWidget);
      expect(find.text('جديدة'), findsOneWidget);
    });
  });
}
