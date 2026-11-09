import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/renew_requests_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/api/tickets_api.dart';
import 'package:rad_mysvcs/models/app_notification.dart';
import 'package:rad_mysvcs/screens/top_actions.dart';
import 'package:rad_mysvcs/services/alerts_service.dart';
import 'package:rad_mysvcs/services/inbox_service.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// رقم الجرس في الرأس و«طلبات التجديد» — مراجعة 3.0.18+179 (قاعدة التذاكر نفسها، 6b257733): إشعار الطلب غير المقروء في الصندوق لا
/// يُعدّ مع طلبه — طلبٌ جديد = ١ لا ٢، وطلبان = ٢ لا ٤؛ والطلب الجديد يُعدّ فوراً قبل قراءة القائمة؛ وطلبٌ قُبل من مكانٍ آخر لا يعود
/// إشعاره يُعدّ؛ وطلب شركةٍ أخرى أو والقسم مقفلٌ له يُعدّ كأيّ إشعار.
const _v = SimVariant(390, dark: false);

const _settingsPath = '/api/v2/portal/renew-settings';
const _listPath = '/api/v2/portal/renew-requests';

String _iso(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String();

Map<String, dynamic> _req(int id, String status, {String name = 'علي عباس'}) => {
      'id': id,
      'status': status,
      'months': 1,
      'package': {'id': '12', 'name': 'Fiber 50', 'same': true},
      'unit_price': 35000,
      'amount': 35000,
      'pay_method': 'zaincash',
      'created_at': _iso(const Duration(minutes: 12)),
      'decided_at': status == 'pending' ? null : _iso(const Duration(minutes: 5)),
      'done_at': null,
      'reject_reason': null,
      'company_code': 'supernet',
      'subscriber': {'idx': '$id', 'username': 'user$id', 'name': name},
      'current_package': 'Fiber 50',
      'note': null,
      'via': 'app',
      'image': {'available': false, 'expires_at': null},
      'decided_by': null,
      'done_source': null,
    };

/// خادم الطلبات بعقد server/portalRenew.js: الإعداد (الوصول) والقائمة المفتوحة بأعدادها — [world] تُقرأ عند كلّ طلب.
void _serve(SimServer server, List<Map<String, dynamic>> world, {bool canUse = true}) {
  server.reply('GET', _settingsPath, 200, {
    'success': true,
    'available': true,
    'can_use': canUse,
    'can_edit': canUse,
    if (canUse) ...{'enabled': true, 'zaincash': '07801234567', 'master': null, 'note': null},
  });
  server.on('GET', _listPath, (_) {
    final open = world.where((x) => x['status'] == 'pending' || x['status'] == 'accepted').toList();
    return SimReply(200, {
      'success': true,
      'items': open,
      'counts': {
        'pending': open.where((x) => x['status'] == 'pending').length,
        'accepted': open.where((x) => x['status'] == 'accepted').length,
      },
    });
  });
}

AppNotification _push(String id, int request, {String company = '2'}) => AppNotification.fromFcmPayload(
      messageId: id,
      title: 'طلب تجديد اشتراك',
      body: 'من المشترك علي عباس',
      data: {'type': 'renew_request', 'request_id': '$request', 'screen': 'renew_requests', 'company_admin_id': company},
    );

void main() {
  late SimServer server;
  setUpAll(simSetUpAll);
  setUp(() async {
    RenewRequestsState.reset();
    RenewRequestsState.debugResetInbox();
    TicketsState.reset();
    TicketsState.debugResetInbox();
    ProviderService.debugSet(null);
    PermissionsService.debugSet(isEmployee: false);
    server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin@m'});
  });
  tearDown(() {
    RenewRequestsState.reset();
    TicketsState.reset();
    ProviderService.debugSet(null);
    PermissionsService.debugReset();
    SubscribersApi.clearAllCaches();
    BigSubscribersApi.reset();
    AlertsService.reset();
  });

  Finder badge(String n) => find.descendant(of: find.byKey(const ValueKey('top-actions-notifications')), matching: find.text(n));
  Widget header() => Scaffold(appBar: AppBar(actions: const [TopActions()]));

  Future<void> arrive(WidgetTester t, AppNotification n) async {
    await t.runAsync(() => InboxService.add(n));
    RenewRequestsState.onInboxChanged(); // كما يربطه main.dart بالصندوق
    await t.pumpAndSettle();
  }

  testWidgets('طلبٌ جديد وإشعاره في الصندوق ⇒ ١ لا ٢؛ وطلبان ⇒ ٢ لا ٤؛ وقُبل من مكانٍ آخر ⇒ لا يعود إشعاره يُعدّ؛ وطلب شركةٍ أخرى يُعدّ',
      (t) async {
    final world = <Map<String, dynamic>>[];
    _serve(server, world);
    await t.runAsync(InboxService.clear);
    addTearDown(() => t.runAsync(InboxService.clear));
    await pumpSim(t, _v, home: (_) => header());
    expect(RenewRequestsState.on, isTrue);
    expect(find.descendant(of: find.byKey(const ValueKey('top-actions-notifications')), matching: find.byType(Text)), findsNothing);
    RenewRequestsState.onInboxChanged(); // أوّل قراءةٍ للصندوق: لا طلب فيه
    // المشترك يطلب التجديد والتطبيق مفتوح: إشعاره يُحفظ غير مقروء (اللافتة تُغلق نفسها بلا نقر)
    world.add(_req(41, 'pending'));
    await t.runAsync(() => InboxService.add(_push('r-41', 41)));
    await t.pump();
    expect(badge('1'), findsOneWidget, reason: 'الإشعار يُعدّ حتى تُقرأ القائمة — لا تأخير');
    RenewRequestsState.onInboxChanged();
    await t.pumpAndSettle();
    expect(RenewRequestsState.pending, 1);
    expect(badge('1'), findsOneWidget, reason: 'طلبٌ واحد = ١ (إشعاره لا يُعدّ معه)');
    expect(badge('2'), findsNothing);
    // طلبٌ ثانٍ
    world.add(_req(43, 'pending', name: 'مصطفى كريم'));
    await arrive(t, _push('r-43', 43));
    expect(RenewRequestsState.pending, 2);
    expect(InboxService.unreadCount, 2);
    expect(badge('2'), findsOneWidget, reason: 'طلبان = ٢ لا ٤');
    // قُبل الأوّل من الويب: لم يعد ينتظرك — وإشعاره غير المقروء لا يعود يُعدّ
    world[0] = _req(41, 'accepted');
    await t.runAsync(() => RenewRequestsState.ensureFresh(force: true));
    await t.pumpAndSettle();
    expect(RenewRequestsState.pending, 1);
    expect(badge('1'), findsOneWidget, reason: 'الثاني وحده ينتظرك');
    // «إشعارات كلّ شركاتي»: طلبٌ لشركةٍ أخرى — الجرس لطلبات المفتوحة وحدها، فإشعاره يُعدّ
    await t.runAsync(() => InboxService.add(_push('r-77', 77, company: 'jt:6836')));
    await t.pump();
    expect(badge('2'), findsOneWidget);
    // القسم مقفلٌ له (لا «طلبات التفعيل»): لا عدد طلبات ⇒ إشعاراتها كأيّ إشعار
    await t.pumpWidget(const SizedBox());
    RenewRequestsState.reset();
    _serve(server, world, canUse: false);
    await pumpSim(t, _v, home: (_) => header());
    expect(RenewRequestsState.on, isFalse);
    expect(badge('3'), findsOneWidget, reason: 'الإشعارات الثلاثة غير المقروءة');
    await simDrain(t);
  });
}
