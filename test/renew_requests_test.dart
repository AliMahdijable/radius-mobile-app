import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/renew_requests_api.dart';
import 'package:rad_mysvcs/models/app_notification.dart';
import 'package:rad_mysvcs/screens/notifications/in_app_notification_banner.dart';
import 'package:rad_mysvcs/screens/notifications/inbox_screen.dart';
import 'package:rad_mysvcs/screens/renew/renew_requests_screen.dart';
import 'package:rad_mysvcs/screens/renew/renew_settings_card.dart';
import 'package:rad_mysvcs/screens/renew/renew_widgets.dart';
import 'package:rad_mysvcs/services/inbox_service.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/notification_router.dart';

import 'sim_el/sim_harness.dart';

/// «طلبات التفعيل» بالتطبيق (٤ نوفمبر — الخادم server/portalRenew.js): الحال للجرس والصندوق، القسم يظهر حين يوجد طلبٌ وحده،
/// النافذة السريعة (الصورة + قبول/تمّ التفعيل/رفض)، نقر الإشعار، الشاشة، وإعداد «بوابة المشترك».
const _v = SimVariant(390, dark: false);

/// صورةٌ صالحة ١×١ (PNG) — Image.memory يفكّها.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

class _BytesReply extends SimReply {
  const _BytesReply(this.bytes) : super(200);
  final Uint8List bytes;

  @override
  ResponseBody toBody() => ResponseBody(Stream.value(bytes), 200, headers: {
        Headers.contentTypeHeader: ['image/jpeg'],
      });
}

String _iso(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String();

Map<String, dynamic> _req(int id, String status,
        {String name = 'علي عباس', String user = 'ali.abbas@popq', int months = 3, int? amount = 105000, bool same = true, bool image = true}) =>
    {
      'id': id,
      'status': status,
      'months': months,
      'package': {'id': '12', 'name': 'Fiber 50', 'same': same},
      'unit_price': 35000,
      'amount': amount,
      'pay_method': 'zaincash',
      'created_at': _iso(const Duration(minutes: 12)),
      'decided_at': status == 'pending' ? null : _iso(const Duration(minutes: 5)),
      'done_at': null,
      'reject_reason': status == 'rejected' ? 'لم يصل التحويل' : null,
      'company_code': 'supernet',
      'subscriber': {'idx': '$id', 'username': user, 'name': name},
      'current_package': same ? 'Fiber 50' : 'Fiber 20',
      'note': 'رقم العمليّة 552144',
      'via': 'app',
      'image': {'available': image, 'expires_at': image ? DateTime.now().toUtc().add(const Duration(hours: 23)).toIso8601String() : null},
      'decided_by': status == 'accepted' ? 'admin@full' : null,
      'done_source': null,
    };

Map<String, dynamic> _settings({bool available = true, bool canUse = true, bool canEdit = true, bool scoped = false, bool enabled = true}) => {
      'success': true,
      'available': available,
      'can_use': canUse,
      'can_edit': canEdit,
      if (scoped) 'scoped': true,
      if (canUse || canEdit) ...{'enabled': enabled, 'zaincash': '07801234567', 'master': null, 'note': null},
    };

Map<String, dynamic> _list(List<Map<String, dynamic>> items) => {
      'success': true,
      'items': items,
      'counts': {
        'pending': items.where((x) => x['status'] == 'pending').length,
        'accepted': items.where((x) => x['status'] == 'accepted').length,
      },
    };

/// «كل الشركات»: المفتوحة (معرّف جلسة الاختبار «2») وشركةٌ أخرى مختارةٌ في الشريط.
const _kOpen = 'c0000000000a1';
const _kOther = 'c0000000000e1';

Future<void> _mergedFocusedOnOther(WidgetTester t) async {
  final prevToken = AccountApi.tokenSource;
  AccountApi.tokenSource = ({bool force = false}) async => 'acct';
  addTearDown(() => AccountApi.tokenSource = prevToken);
  MergedMode.reset();
  MergedMode.fetchRaw = () async => {
        'routing': true,
        'writes': true,
        'companies': [
          {'key': _kOpen, 'code': 'supernet', 'username': 'u0', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': '2', 'ns': 'a', 'currency': 'IQD', 'color_index': 0},
          {'key': _kOther, 'code': 'jt', 'username': 'u1', 'name': 'الجزيرة', 'status': 'ok', 'admin_id': 'jt:6836', 'ns': 'j', 'currency': 'IQD', 'color_index': 1},
        ],
      };
  addTearDown(MergedMode.reset);
  expect(await t.runAsync(MergedMode.enter), isTrue);
  MergedMode.focus.value = _kOther;
}

String? _keyOf(RequestOptions r) => r.headers['x-company-key'] as String?;

/// شجرةٌ جديدة بين سيناريوهين في اختبارٍ واحد: لا حال شاشةٍ سابقة يُعاد استعماله، ولا ورقةٌ مفتوحة فوق الزرّ، ولا إشعارٌ بالطابور.
Future<void> _fresh(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 5));
}

void main() {
  test('النماذج: الطلب بحقوله واسمه، الوصول، الترتيب، والنصوص', () {
    final r = RenewRequest.fromJson(_req(41, 'pending'))!;
    expect(r.title, 'علي عباس');
    expect(r.isPending && r.isOpen, true);
    expect(r.amount, 105000);
    expect(r.packageName, 'Fiber 50');
    expect(r.imageAvailable, true);
    expect(renewSummary(r).replaceAll(RegExp('[\u2066-\u2069]'), ''), 'Fiber 50 · 3 أشهر · 105,000 د.ع', reason: 'كلّ مقطعٍ معزول');
    expect(RenewRequest.fromJson(_req(1, 'done', name: ''))!.title, 'ali.abbas@popq', reason: 'بلا اسم ⇒ اليوزر');
    expect(RenewRequest.fromJson({'id': 1}), isNull);
    expect(renewMonthsLabel(1), 'شهر');
    expect(renewMonthsLabel(2), 'شهرين');
    expect(renewMonthsLabel(6), '6 أشهر');
    expect(renewPayLabel('master'), 'ماستر');
    final sorted = sortOpenFirst([
      RenewRequest.fromJson(_req(3, 'accepted'))!,
      RenewRequest.fromJson(_req(5, 'pending'))!,
      RenewRequest.fromJson(_req(4, 'pending'))!,
    ]);
    expect(sorted.map((x) => x.id).toList(), [5, 4, 3], reason: 'بانتظارك أوّلاً، الأحدث أوّلاً');
    final a = RenewAccess.fromJson(_settings(scoped: true, canUse: false, canEdit: false));
    expect([a.available, a.canUse, a.scoped], [true, false, true]);
  });

  group('الحال والواجهة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      RenewRequestsState.reset();
      RenewRequestsState.debugResetInbox();
      server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin@m'});
      server.on('GET', '/api/v2/portal/renew-requests/41/image', (_) => _BytesReply(_png));
      server.on('GET', '/api/v2/portal/renew-requests/40/image', (_) => _BytesReply(_png));
    });

    testWidgets('غير مفتوحةٍ لحسابه ⇒ لا قائمة ولا عدد ولا قسم', (t) async {
      server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings(available: false, canUse: false, canEdit: false));
      await pumpSim(t, _v, home: (_) => const Scaffold(body: RenewInboxSection()));
      await t.pumpAndSettle();
      expect(RenewRequestsState.on, false);
      expect(RenewRequestsState.pending, 0);
      expect(server.calls('GET', '/api/v2/portal/renew-requests'), isEmpty);
      expect(find.text('طلبات التجديد'), findsNothing);
      await simDrain(t);
    });

    testWidgets('مفتوحة: القسم يظهر حين يوجد طلبٌ وحده، والعدد بانتظارك؛ وإشعار طلبٍ جديد يقرؤها فوراً', (t) async {
      server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings());
      server.reply('GET', '/api/v2/portal/renew-requests', 200, _list([]));
      await pumpSim(t, _v, home: (_) => const Scaffold(body: SingleChildScrollView(child: RenewInboxSection())));
      await t.pumpAndSettle();
      expect(RenewRequestsState.on, true);
      expect(find.text('طلبات التجديد'), findsNothing, reason: 'لا طلب ⇒ لا قسم (المالك: «في حال اكو طلب»)');
      expect(server.calls('GET', '/api/v2/portal/renew-requests').single.queryParameters['status'], 'open');
      // طلبٌ يصل: إشعارٌ في الصندوق ⇒ القائمة من جديد
      server.reply('GET', '/api/v2/portal/renew-requests', 200, _list([_req(41, 'pending'), _req(37, 'accepted', name: 'مصطفى كريم')]));
      await t.runAsync(InboxService.clear);
      RenewRequestsState.onInboxChanged(); // أوّل قراءةٍ للصندوق: لا طلب فيه
      await t.runAsync(() => InboxService.add(AppNotification.fromFcmPayload(
            messageId: 'm-1',
            title: 'طلب تجديد اشتراك',
            body: 'من المشترك علي عباس',
            data: {'type': 'renew_request', 'request_id': '41'},
          )));
      RenewRequestsState.onInboxChanged();
      await t.pumpAndSettle();
      expect(server.calls('GET', '/api/v2/portal/renew-requests'), hasLength(2));
      expect(RenewRequestsState.pending, 1);
      expect(find.text('طلبات التجديد'), findsOneWidget);
      expect(find.text('علي عباس'), findsOneWidget);
      expect(find.text('مصطفى كريم'), findsOneWidget);
      expect(find.text('بانتظارك'), findsOneWidget);
      expect(find.text('مقبول'), findsOneWidget);
      await t.runAsync(InboxService.clear);
      await simDrain(t);
    });

    testWidgets('النافذة السريعة: الصورة والتفاصيل؛ «قبول» ⇒ accept ويبقى بحاله المقبولة؛ «تمّ التفعيل» بتأكيد ⇒ done ويُغلق', (t) async {
      server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings());
      server.reply('GET', '/api/v2/portal/renew-requests', 200, _list([_req(41, 'pending')]));
      server.reply('POST', '/api/v2/portal/renew-requests/41/accept', 200, {'success': true, 'request': _req(41, 'accepted')});
      server.reply('POST', '/api/v2/portal/renew-requests/41/done', 200, {'success': true, 'request': _req(41, 'done')});
      final r = RenewRequest.fromJson(_req(41, 'pending'))!;
      await pumpSim(t, _v, home: (_) => simLauncher((c) => showRenewRequestSheet(c, r)));
      await simOpen(t);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(find.text('طلب تجديد اشتراك'), findsOneWidget);
      expect(find.text('رقم العمليّة 552144'), findsOneWidget);
      expect(simText('Fiber 50 · 3 أشهر'), findsOneWidget);
      expect(find.text('105,000 د.ع'), findsOneWidget);
      expect(find.text('زين كاش'), findsOneWidget);
      expect(server.calls('GET', '/api/v2/portal/renew-requests/41/image'), hasLength(1));
      await t.tap(find.byKey(const ValueKey('renew-accept')));
      await t.pumpAndSettle();
      expect(server.calls('POST', '/api/v2/portal/renew-requests/41/accept'), hasLength(1));
      expect(find.text('طلب تجديد اشتراك'), findsOneWidget, reason: 'بعد القبول تبقى النافذة (التالي: صفحته للتجديد)');
      expect(find.textContaining('جدّد اشتراكه من صفحة المشترك'), findsOneWidget);
      expect(find.text('صفحة المشترك — للتجديد'), findsOneWidget);
      expect(find.byKey(const ValueKey('renew-accept')), findsNothing);
      await t.tap(find.byKey(const ValueKey('renew-done')));
      await t.pumpAndSettle();
      expect(find.textContaining('يصله «تم تفعيل اشتراكك بنجاح»'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('renew-done-confirm')));
      await t.pumpAndSettle();
      expect(server.calls('POST', '/api/v2/portal/renew-requests/41/done'), hasLength(1));
      expect(find.text('طلب تجديد اشتراك'), findsNothing, reason: 'بعد «تمّ التفعيل» تُغلق');
      await simDrain(t);
    });

    testWidgets('الرفض: سببٌ جاهز ⇒ reason بالجسم والنافذة تُغلق؛ والحالة المتغيّرة (٤٠٩) تُقال', (t) async {
      server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings());
      server.reply('GET', '/api/v2/portal/renew-requests', 200, _list([_req(41, 'pending')]));
      server.reply('POST', '/api/v2/portal/renew-requests/41/reject', 200, {'success': true, 'request': _req(41, 'rejected')});
      final r = RenewRequest.fromJson(_req(41, 'pending'))!;
      await pumpSim(t, _v, home: (_) => simLauncher((c) => showRenewRequestSheet(c, r)));
      await simOpen(t);
      await t.tap(find.byKey(const ValueKey('renew-reject')));
      await t.pumpAndSettle();
      await t.tap(find.text('لم يصل التحويل'));
      await t.pumpAndSettle();
      await t.tap(find.text('رفض الطلب'));
      await t.pumpAndSettle();
      expect(server.bodies('POST', '/api/v2/portal/renew-requests/41/reject').single, {'reason': 'لم يصل التحويل'});
      expect(find.text('طلب تجديد اشتراك'), findsNothing);
      // ٤٠٩: قرّره غيره
      await _fresh(t);
      server.reply('POST', '/api/v2/portal/renew-requests/40/accept', 409,
          {'success': false, 'code': 'RENEW_STATE', 'message': 'تغيّرت حالة الطلب — حدّث الصفحة', 'request': _req(40, 'accepted')});
      final r40 = RenewRequest.fromJson(_req(40, 'pending'))!;
      await pumpSim(t, _v, home: (_) => simLauncher((c) => showRenewRequestSheet(c, r40)));
      await simOpen(t);
      await t.tap(find.byKey(const ValueKey('renew-accept')));
      await t.pumpAndSettle();
      expect(find.text('تغيّرت حالة الطلب — حدّث الصفحة'), findsOneWidget);
      expect(find.text('مقبول'), findsOneWidget, reason: 'الحال كما قالها الخادم');
      await simDrain(t);
    });

    testWidgets('نقر الإشعار renew_request يفتح الطلب نفسه؛ رقمٌ لم يعد مفتوحاً ⇒ القائمة؛ وغيره false', (t) async {
      server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings());
      server.reply('GET', '/api/v2/portal/renew-requests', 200, _list([_req(41, 'pending')]));
      final nav = GlobalKey<NavigatorState>();
      await pumpSim(t, _v, navigatorKey: nav, home: (_) => const Scaffold(body: SizedBox()));
      expect(await openRenewRequestPush(nav.currentState!, {'type': 'agent_alert'}), false);
      final f = openRenewRequestPush(nav.currentState!, {'type': 'renew_request', 'request_id': '41'});
      await t.pumpAndSettle();
      expect(find.text('طلب تجديد اشتراك'), findsOneWidget);
      expect(find.text('علي عباس'), findsOneWidget);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(await f, true);
      final g = openRenewRequestPush(nav.currentState!, {'type': 'renew_request', 'request_id': '99'});
      await t.pumpAndSettle();
      expect(find.byType(RenewRequestsScreen), findsOneWidget);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(await g, true);
      await simDrain(t);
    });

    testWidgets('لافتة الإشعار والتطبيق مفتوح: نقرها يفتح الطلب نفسه لا صندوق الإشعارات', (t) async {
      server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings());
      server.reply('GET', '/api/v2/portal/renew-requests', 200, _list([_req(41, 'pending')]));
      await t.runAsync(InboxService.clear);
      final nav = GlobalKey<NavigatorState>();
      await pumpSim(t, _v, navigatorKey: nav, home: (_) => const Scaffold(body: SizedBox()));
      NotificationRouter.attach(nav);
      NotificationRouter.markReady();
      addTearDown(NotificationRouter.reset);
      InAppNotificationBanner.show(t.element(find.byType(Scaffold)),
          notification: AppNotification.fromFcmPayload(
            messageId: 'm-banner',
            title: 'طلب تجديد اشتراك جديد',
            body: 'من المشترك علي عباس',
            data: {'type': 'renew_request', 'request_id': '41'},
          ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400)); // انزلاق اللافتة
      await t.tap(find.text('طلب تجديد اشتراك جديد'));
      await t.pumpAndSettle();
      expect(find.text('طلب تجديد اشتراك'), findsOneWidget, reason: 'نافذة الطلب');
      expect(find.text('علي عباس'), findsOneWidget);
      expect(find.byType(InboxScreen), findsNothing);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      await simDrain(t);
    });

    testWidgets('«كل الشركات»: نافذة الطلب من الجرس والإشعار للمفتوحة (الصورة والقبول) ولو بقي تحتها قسمٌ موجَّهٌ لغيرها', (t) async {
      server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings());
      server.reply('GET', '/api/v2/portal/renew-requests', 200, _list([_req(41, 'pending'), _req(43, 'pending', name: 'مصطفى كريم')]));
      server.reply('POST', '/api/v2/portal/renew-requests/41/accept', 200, {'success': true, 'request': _req(41, 'accepted')});
      server.on('GET', '/api/v2/portal/renew-requests/43/image', (_) => _BytesReply(_png));
      await _mergedFocusedOnOther(t);
      // كقسم «بوابة المشترك» لشركةٍ أخرى مفتوحٍ تحت (الحاسبة، أو صفحةٌ تحت الإشعار) — بادئته تشمل الطلبات
      final owner = Object();
      CompanyRoute.enterSection(owner, _kOther, const ['/api/v2/portal']);
      addTearDown(() => CompanyRoute.leaveSection(owner));
      final nav = GlobalKey<NavigatorState>();
      await pumpSim(t, _v, navigatorKey: nav, home: (_) => const Scaffold(body: SingleChildScrollView(child: RenewInboxSection())));
      await t.pumpAndSettle();
      expect(server.calls('GET', '/api/v2/portal/renew-requests').map(_keyOf).toSet(), {null}, reason: 'الجرس للمفتوحة');
      await t.tap(find.text('علي عباس'));
      await t.pumpAndSettle();
      expect(find.text('طلب تجديد اشتراك'), findsOneWidget);
      expect(server.calls('GET', '/api/v2/portal/renew-requests/41/image').map(_keyOf).toList(), [null], reason: 'صورة التحويل للمفتوحة');
      await t.tap(find.byKey(const ValueKey('renew-accept')));
      await t.pumpAndSettle();
      expect(server.calls('POST', '/api/v2/portal/renew-requests/41/accept').map(_keyOf).toList(), [null], reason: 'القبول للمفتوحة');
      nav.currentState!.pop();
      await t.pumpAndSettle();
      // الإشعار ولافتته كذلك (طلبٌ آخر — الصورة تُحفظ بالذاكرة لكلّ طلب)
      final f = openRenewRequestPush(nav.currentState!, {'type': 'renew_request', 'request_id': '43'});
      await t.pumpAndSettle();
      expect(find.text('مصطفى كريم'), findsWidgets);
      expect(server.calls('GET', '/api/v2/portal/renew-requests/43/image').map(_keyOf).toList(), [null]);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(await f, true);
      // الضابط: الطلب نفسه بلا تثبيتٍ يذهب للقسم الموجَّه — فالتثبيت هو الذي أبقاها للمفتوحة
      await t.runAsync(() => RenewRequestsApi.image(44));
      expect(_keyOf(server.calls('GET', '/api/v2/portal/renew-requests/44/image').last), _kOther);
      await simDrain(t);
    });

    testWidgets('«كل الشركات»: «الكلّ» في الجرس ورقمٌ لم يعد مفتوحاً من الإشعار ⇒ قائمة المفتوحة (التي يعرضها الجرس) لا مختارة الشريط',
        (t) async {
      server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings());
      server.reply('GET', '/api/v2/portal/renew-requests', 200, _list([_req(41, 'pending')]));
      await _mergedFocusedOnOther(t);
      final nav = GlobalKey<NavigatorState>();
      await pumpSim(t, _v, navigatorKey: nav, home: (_) => const Scaffold(body: SingleChildScrollView(child: RenewInboxSection())));
      await t.pumpAndSettle();
      final before = server.requests.length;
      await t.tap(find.byKey(const ValueKey('renew-inbox-all')));
      await t.pumpAndSettle();
      expect(find.byType(RenewRequestsScreen), findsOneWidget);
      expect(MergedMode.focus.value, _kOpen, reason: 'الشريط على المفتوحة التي عرض الجرس طلباتها');
      final listAsked = server.requests.skip(before).where((r) => r.path.startsWith('/api/v2/portal/renew-')).toList();
      expect(listAsked, isNotEmpty);
      expect(listAsked.map(_keyOf).toSet(), {null}, reason: 'قائمة المفتوحة لا الجزيرة');
      nav.currentState!.pop();
      await t.pumpAndSettle();
      // رقمٌ لم يعد مفتوحاً من الإشعار ⇒ القائمة للمفتوحة كذلك
      MergedMode.focus.value = _kOther;
      await t.pumpAndSettle();
      final before2 = server.requests.length;
      final g = openRenewRequestPush(nav.currentState!, {'type': 'renew_request', 'request_id': '99'});
      await t.pumpAndSettle();
      expect(find.byType(RenewRequestsScreen), findsOneWidget);
      expect(MergedMode.focus.value, _kOpen);
      expect(server.requests.skip(before2).where((r) => r.path.startsWith('/api/v2/portal/renew-')).map(_keyOf).toSet(), {null});
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(await g, true);
      await simDrain(t);
    });

    testWidgets('الشاشة: غير مفعّلة · مقفلة للموظّف المقيَّد · القائمة وتبويب «آخر ٣٠ يوماً» ⇒ status=all', (t) async {
      server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings(available: false, canUse: false, canEdit: false));
      await pumpSim(t, _v, home: (_) => const RenewRequestsScreen());
      await t.pumpAndSettle();
      expect(find.textContaining('غير مفعّلة لحسابك بعد'), findsOneWidget);
      await _fresh(t);
      server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings(canUse: false, canEdit: false, scoped: true));
      await pumpSim(t, _v, home: (_) => const RenewRequestsScreen());
      await t.pumpAndSettle();
      expect(find.text('لا صلاحيّة'), findsOneWidget);
      expect(find.textContaining('مقيَّد بمديرٍ فرعيّ'), findsOneWidget);
      expect(server.calls('GET', '/api/v2/portal/renew-requests'), isEmpty, reason: 'مقفلةٌ ⇒ لا طلب');
      await _fresh(t);
      server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings(enabled: false));
      server.reply('GET', '/api/v2/portal/renew-requests', 200, _list([_req(37, 'accepted', name: 'مصطفى كريم'), _req(41, 'pending')]));
      await pumpSim(t, _v, home: (_) => const RenewRequestsScreen());
      await t.pumpAndSettle();
      expect(find.textContaining('مشتركوك لا يرون «طلب التجديد»'), findsOneWidget, reason: 'مفتاح الوكيل مطفأ');
      final tiles = find.byType(RenewRequestTile);
      expect(tiles, findsNWidgets(2));
      expect(t.widget<RenewRequestTile>(tiles.first).request.id, 41, reason: 'بانتظارك أوّلاً');
      await t.tap(find.text('آخر ٣٠ يوماً'));
      await t.pumpAndSettle();
      expect(server.calls('GET', '/api/v2/portal/renew-requests').last.queryParameters['status'], 'all');
      await simDrain(t);
    });

    testWidgets('إعداد «بوابة المشترك»: مخفيٌّ بلا المفتاح؛ ظاهرٌ به — التشغيل يرسل enabled والحفظ يرسل الأرقام', (t) async {
      server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings(available: false, canUse: false, canEdit: false));
      await pumpSim(t, _v, home: (_) => const Scaffold(body: SingleChildScrollView(child: RenewSettingsCard())));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('renew-settings-card')), findsNothing);
      await _fresh(t);
      server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings(enabled: false));
      server.reply('PUT', '/api/v2/portal/renew-settings', 200,
          {'success': true, 'available': true, 'enabled': true, 'zaincash': '07801234567', 'master': null, 'note': null});
      await pumpSim(t, _v, home: (_) => const Scaffold(body: SingleChildScrollView(child: RenewSettingsCard())));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('renew-settings-card')), findsOneWidget);
      expect(find.textContaining('موقوف'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('renew-enabled-switch')));
      await t.pumpAndSettle();
      expect(server.bodies('PUT', '/api/v2/portal/renew-settings').single, {'enabled': true});
      expect(find.textContaining('مشتركوك يطلبون التجديد'), findsOneWidget);
      server.reply('PUT', '/api/v2/portal/renew-settings', 200,
          {'success': true, 'available': true, 'enabled': true, 'zaincash': '07801234567', 'master': '1234567890123456', 'note': null});
      await t.enterText(find.byKey(const ValueKey('renew-master')), '1234 5678 9012 3456');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('renew-settings-save')));
      await t.pumpAndSettle();
      expect(server.bodies('PUT', '/api/v2/portal/renew-settings').last,
          {'zaincash': '07801234567', 'master': '1234 5678 9012 3456', 'note': ''});
      await simDrain(t);
    });

    for (final v in simVariants) {
      testWidgets('بلا فيضٍ ولا أخطاء @${v.tag}: القسم والنافذة والشاشة', (t) async {
        server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings());
        server.reply('GET', '/api/v2/portal/renew-requests', 200, _list([
          _req(41, 'pending', name: 'علي عباس حسين الجبوري الطويل جدّاً', user: 'very.long.username.example@popq'),
          _req(40, 'pending', same: false, amount: null, image: false),
          _req(37, 'accepted', name: 'مصطفى كريم'),
        ]));
        await pumpSim(t, v, home: (_) => const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(16), child: RenewInboxSection())));
        await t.pumpAndSettle();
        expect(find.text('طلبات التجديد'), findsOneWidget);
        expect(t.takeException(), isNull);
        await _fresh(t);
        final r = RenewRequest.fromJson(_req(41, 'pending', name: 'علي عباس حسين الجبوري الطويل جدّاً'))!;
        await pumpSim(t, v, home: (_) => simLauncher((c) => showRenewRequestSheet(c, r)));
        await simOpen(t);
        expect(t.takeException(), isNull);
        await _fresh(t);
        final r40 = RenewRequest.fromJson(_req(40, 'pending', same: false, amount: null, image: false))!;
        await pumpSim(t, v, home: (_) => simLauncher((c) => showRenewRequestSheet(c, r40)));
        await simOpen(t);
        expect(find.textContaining('حُذفت صورة التحويل'), findsOneWidget);
        expect(find.text('المبلغ غير معروف'), findsOneWidget);
        expect(find.textContaining('يريد التغيير من باقته'), findsOneWidget);
        expect(t.takeException(), isNull);
        await _fresh(t);
        await pumpSim(t, v, home: (_) => const RenewRequestsScreen());
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await simDrain(t);
      });
    }
  });
}
