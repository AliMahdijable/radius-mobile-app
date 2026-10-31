import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/national_portal_api.dart';
import 'package:rad_mysvcs/screens/app_modules.dart';
import 'package:rad_mysvcs/screens/national/national_labels.dart';
import 'package:rad_mysvcs/screens/national/national_money_screen.dart';
import 'package:rad_mysvcs/screens/national/national_tickets_screen.dart';
import 'package:rad_mysvcs/screens/national/national_widgets.dart';
import 'package:rad_mysvcs/screens/national/national_work_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// المشروع الوطنيّ بالتطبيق (٣١ أكتوبر — المالك: «الطلبات التذاكر هاي مهمه مموجوده كذلك المواضع الي متعلقة بالمالية… والفلاتر»):
/// الشاشات الثلاث على `/api/v2/ftth/*` (الخادم server/watani/wataniPortalRoutes.js): الصفوف، والفلاتر ⇒ معاملات الطلب نفسها،
/// و«جارٍ» (pending) ثمّ وصول البيانات بإعادة السؤال، وورقة الطلب بسجلّه، والأقسام للوطنيّ وحده.
const _v = SimVariant(390, dark: false);
const _uuid = '0a1b2c3d-1111-4222-8333-944455556666';

Map<String, Object?> _ticket(int n, String status) => {
      'id': 't$n',
      'display_id': 'cc-2610${n}4567',
      'source': 'call_center',
      'title': 'انقطاع خدمة $n',
      'summary': 'الضوء أحمر على الجهاز',
      'status': status,
      'customer': {'id': '7', 'name': 'مريم عبد الله'},
      'zone': {'id': 'FBG1', 'name': 'FBG1'},
      'comments': 1,
      'attachments': 0,
      'created_at': '2026-10-30 14:21:00',
    };

Map<String, Object?> _request(String status) => {
      'id': _uuid,
      'type': 'CustomerOnboardingRequest',
      'type_label': '',
      'status': status,
      'customer': {'id': '7', 'name': 'حيدر جاسم'},
      'username': 'FBG885F15P1',
      'cancelable': true,
      'zone': {'id': 'FBG1', 'name': 'FBG1'},
      'created_at': '2026-10-29 11:01:00',
    };

const _lookups = {
  'success': true,
  'data': {
    'ticket_statuses': [
      {'id': 's-new', 'name': 'New'},
      {'id': 's-closed', 'name': 'Closed'},
    ],
    'request_types': [
      {'id': 'rt-1', 'name': 'Customer Onboarding Request'},
    ],
    'request_statuses': [
      {'id': 'rs-1', 'name': 'Done'},
    ],
    'zones': [
      {'id': 'FBG1', 'name': 'FBG1'},
    ],
    'transaction_types': [
      {'id': 'PLAN_RENEW', 'name': 'PLAN_RENEW'},
    ],
  },
};

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet('watani', label: 'المشروع الوطني');
    server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups);
    server.reply('GET', '/api/v2/ftth/counts', 200, {
      'success': true,
      'data': {'tasks_open': 12, 'requests_open': 11, 'requests_action_required': 8},
    });
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  test('الأسماء العربيّة: الحالات والأنواع والحركات — ولا «تمديد» أبداً', () {
    expect(nationalTicketStatus('Contractor feedback').label, 'بانتظار ردّك');
    expect(nationalRequestType('SubscriptionTransferRequest'), 'نقل ملكيّة اشتراك');
    expect(nationalRequestTypeName('Wireless New Address Onboarding Request'), 'عنوان جديد لاسلكيّ');
    expect(nationalTaskStatus('Not started').label, 'لم تبدأ');
    expect(nationalTxType('WALLET_TOPUP_PRLN'), 'شحن المحفظة بكارت');
    expect(nationalTxType('SOMETHING_NEW'), 'حركة أخرى');
    expect(nationalTxTypes.values.any((v) => v.contains('تمديد')), isFalse);
  });

  test('الفترة الجاهزة ⇒ من/إلى بأيّام', () {
    final now = DateTime(2026, 10, 31, 15);
    expect(nationalPeriodRange('today', now: now), (from: '2026-10-31', to: '2026-10-31'));
    expect(nationalPeriodRange('7d', now: now), (from: '2026-10-25', to: '2026-10-31'));
    expect(nationalPeriodRange('month', now: now), (from: '2026-10-01', to: '2026-10-31'));
    expect(nationalPeriodRange('', now: now), (from: null, to: null));
  });

  testWidgets('التذاكر: الصفوف بحالاتها، والبحث يرسل q، و«الفلاتر» ترسل الحالة', (t) async {
    server.reply('GET', '/api/v2/ftth/tickets', 200, {
      'success': true,
      'data': [_ticket(1, 'New'), _ticket(2, 'Closed')],
      'total': 205,
      'page': 1,
      'page_count': 18,
    });
    await pumpSim(t, _v, home: (_) => const NationalTicketsScreen());
    expect(find.text('انقطاع خدمة 1'), findsOneWidget);
    expect(find.text('جديدة'), findsOneWidget);
    expect(find.text('مغلقة'), findsOneWidget);
    expect(find.text('تحميل المزيد'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'مريم');
    await t.pump(const Duration(milliseconds: 450));
    await t.pumpAndSettle();
    expect(server.calls('GET', '/api/v2/ftth/tickets').last.queryParameters['q'], 'مريم');

    await t.tap(find.text('الفلاتر'));
    await t.pumpAndSettle();
    await t.tap(find.text('جديدة').last);
    await t.pumpAndSettle();
    await t.tap(find.text('تطبيق'));
    await t.pumpAndSettle();
    final q = server.calls('GET', '/api/v2/ftth/tickets').last.queryParameters;
    expect(q['status'], 's-new');
    expect(q['q'], 'مريم', reason: 'البحث يبقى مع الفلتر');
    expect(find.text('1'), findsWidgets, reason: 'عدد الفلاتر المفعّلة على الزرّ');
    await simDrain(t);
  });

  testWidgets('الطلبات: «جارٍ» ثمّ الصفوف بإعادة السؤال، و«بانتظار إجرائي (8)» يرسل action=1', (t) async {
    var n = 0;
    server.on('GET', '/api/v2/ftth/requests', (_) {
      n += 1;
      return n == 1
          ? const SimReply(200, {'success': true, 'pending': true, 'page': 1, 'size': 25})
          : SimReply(200, {
              'success': true,
              'data': [_request('In Progress')],
              'total': 171,
              'page': 1,
              'page_count': 7,
              'summary': [],
            });
    });
    await pumpSim(t, _v, home: (_) => const NationalWorkScreen(), settle: false);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('جارٍ الجلب من بوّابة المشروع الوطني…'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    expect(n, 2);
    expect(find.text('تسجيل زبون جديد'), findsOneWidget);
    expect(find.text('قيد التنفيذ'), findsOneWidget);
    expect(find.text('بانتظار إجرائي (8)'), findsOneWidget);

    await t.tap(find.text('بانتظار إجرائي (8)'));
    await t.pumpAndSettle();
    expect(server.calls('GET', '/api/v2/ftth/requests').last.queryParameters['action'], '1');
    await simDrain(t);
  });

  testWidgets('ورقة الطلب: التفاصيل والمهامّ، والسجلّ يصل بعد «جارٍ»', (t) async {
    server.reply('GET', '/api/v2/ftth/requests', 200, {
      'success': true,
      'data': [_request('In Progress')],
      'total': 1,
      'page': 1,
      'page_count': 1,
    });
    var n = 0;
    server.on('GET', '/api/v2/ftth/requests/$_uuid', (o) {
      n += 1;
      expect(o.queryParameters['type'], 'CustomerOnboardingRequest');
      return SimReply(200, {
        'success': true,
        'data': {
          'detail': {
            'status': 'In Progress',
            'plan': 'BASIC',
            'address': 'بغداد، الكرادة',
            'cancelable': true,
            'created_at': '2026-10-29 11:01:00',
            'tasks': [
              {'title': 'Connect Customer', 'status': 'Not started', 'due_at': '2026-11-02 10:00:00'},
            ],
          },
          'logs': n == 1
              ? null
              : [
                  {'at': '2026-10-29 11:01:00', 'ok': true, 'text': 'Request created'},
                ],
          'logs_pending': n == 1,
        },
      });
    });
    await pumpSim(t, _v, home: (_) => const NationalWorkScreen());
    await t.tap(find.text('تسجيل زبون جديد'));
    await t.pumpAndSettle();
    expect(find.text('بغداد، الكرادة'), findsOneWidget);
    expect(find.text('توصيل زبون'), findsOneWidget);
    expect(find.text('لم تبدأ'), findsOneWidget);
    expect(find.text('جارٍ جلب السجلّ من البوّابة…'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    expect(find.text('Request created'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('المهامّ: الملخّص والصفوف', (t) async {
    server.reply('GET', '/api/v2/ftth/requests', 200, {'success': true, 'data': [], 'total': 0, 'page': 1, 'page_count': 1});
    server.reply('GET', '/api/v2/ftth/tasks', 200, {
      'success': true,
      'data': [
        {'id': 'k1', 'title': 'Maintenance', 'status': 'Completed', 'due_at': '2026-11-01 08:00:00', 'customer': {'id': '7', 'name': 'زبون'}},
      ],
      'total': 178,
      'page': 1,
      'page_count': 8,
      'summary': {'open': 12, 'completed': 353, 'due_today': 0},
    });
    await pumpSim(t, _v, home: (_) => const NationalWorkScreen(initialTab: 1));
    expect(find.text('صيانة'), findsOneWidget);
    expect(find.text('مكتملة'), findsOneWidget);
    expect(find.text('مفتوحة 12'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('الحركات الماليّة: المجموع للإيرادات، والرصيد للمحفظة', (t) async {
    server.reply('GET', '/api/v2/ftth/transactions', 200, {
      'success': true,
      'data': [
        {'at': '2026-10-31 11:15:00', 'type': 'PLAN_RENEW', 'amount': 35000, 'method': 'Card', 'paid_by': 'Customer', 'customer': {'id': '7', 'name': 'علي'}},
      ],
      'total': 1,
      'page': 1,
      'page_count': 1,
      'sum': 35000,
    });
    server.reply('GET', '/api/v2/ftth/wallet', 200, {
      'success': true,
      'data': [
        {'at': '2026-10-31 11:15:00', 'type': 'WALLET_TOPUP', 'amount': 500000, 'balance_after': 1250000, 'method': 'Wallet', 'customer': null},
      ],
      'total': 1,
      'page': 1,
      'page_count': 1,
      'balance': {'balance': 1250000, 'commission': 5000, 'currency': 'IQD'},
    });
    await pumpSim(t, _v, home: (_) => const NationalMoneyScreen());
    expect(find.text('تجديد'), findsOneWidget);
    expect(find.textContaining('مجموع الفترة'), findsOneWidget);
    final rq = server.calls('GET', '/api/v2/ftth/transactions').last.queryParameters;
    expect(rq['from'], isNotNull);
    expect(rq['from'], rq['to'], reason: 'اليوم افتراضاً');

    await t.tap(find.text('محفظتي'));
    await t.pumpAndSettle();
    expect(find.text('شحن المحفظة'), findsOneWidget);
    expect(find.textContaining('الرصيد الحاليّ'), findsOneWidget);
    expect(find.textContaining('1,250,000'), findsWidgets);
    await simDrain(t);
  });

  test('الأقسام بقائمة «قوائم أخرى»: للوطنيّ وحده، والموظّف بلا مفتاحها مقفلة', () {
    var ids = buildAppModules().map((m) => m.id).toSet();
    expect(ids.containsAll({'national_work', 'national_tickets', 'national_money'}), isTrue);

    ProviderService.debugSet('nabd', label: 'نبض');
    ids = buildAppModules().map((m) => m.id).toSet();
    expect(ids.intersection({'national_work', 'national_tickets', 'national_money'}), isEmpty);

    ProviderService.debugSet('watani', label: 'المشروع الوطني');
    PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
    final mods = {for (final m in buildAppModules()) m.id: m};
    expect(mods['national_tickets']?.isLocked, isFalse);
    expect(mods['national_money']?.isLocked ?? true, isTrue, reason: 'بلا reports.financial: مقفلة أو غائبة');
  });

  test('NationalPage.hasMore والردّ «جارٍ»', () {
    const p = NationalPage<int>(items: [1], page: 1, pageCount: 3);
    expect(p.hasMore, isTrue);
    const q = NationalPage<int>(items: [], pending: true, pageCount: 3);
    expect(q.hasMore, isFalse);
  });
}
