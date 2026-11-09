import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/expenses_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/screens/app_modules.dart';
import 'package:rad_mysvcs/screens/desktop/desktop_shell.dart';
import 'package:rad_mysvcs/screens/expenses/expenses_screen.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/add_subscriber_sheet.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/widgets/merged_section.dart';

import 'visual_perm/visual_perm_harness.dart';

/// مانع إصدار 179 (٩ نوفمبر — مراجعة merged_routing): قسمٌ من «قوائم أخرى» موجَّهٌ لشركةٍ غير المفتوحة كان يبقى يوجِّه بادئاته وهو
/// مخفيّ على الحاسبة (DesktopShell يُبقي كلّ قسمٍ فُتح مركّباً في IndexedStack) — «إضافة صرفية» للمفتوحة من الرئيسيّة (Ctrl/⌘+N)
/// سُجِّلت في مال شركة الشريط. والإجراء الذي اختار المدير له المفتوحة صراحةً لها ولو كان القسم الموجَّه ظاهراً.
///   ١. الحاسبة (MainShell عريضاً): الصرفيات لايرث لنك ثمّ الرئيسيّة ⇒ لا وجهة؛ Ctrl/⌘+N «إضافة صرفية» للمفتوحة ⇒ بلا مفتاح؛
///      والصرفيات ظاهرةٌ لايرث لنك ثمّ Ctrl/⌘+N للمفتوحة ⇒ بلا مفتاح كذلك، وقسمها يبقى لايرث لنك.
///   ٢. الجزء غير الظاهر (MergedPaneVisibility): لا توجيه، ولا يعود بتبديل الشريط وهو مخفيّ، ويعود ويُجلب لشركته حين يظهر.
///   ٣. الهاتف كما كان: صفحةٌ فوق القسم (تغطّيه) لا ترفع وجهته.
///   ٤. «مشترك جديد» للمفتوحة وقسم مدراء شركةٍ أخرى موجَّه: المدراء والباقات والإنشاء للمفتوحة.
const _kOpen = 'c0000000000a1';
const _kEl = 'c0000000000e1';
const _kJt = 'c0000000000b2';

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

/// خادمٌ صغير لما يُفحص هنا (بصدى المفتاح كالخادم)، وما سواه لخادم لقطات الصلاحيّات ([fallback]).
class _Srv implements HttpClientAdapter {
  _Srv([this.fallback]);
  final HttpClientAdapter? fallback;

  /// «METHOD path key» لكلّ طلب.
  final asked = <String>[];
  final bodies = <String, Object?>{};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    final m = o.method.toUpperCase();
    final line = '$m $path ${key ?? '-'}';
    asked.add(line);
    if (m != 'GET') bodies[line] = o.data;
    final h = key == null ? const <String, List<String>>{} : {'x-company-key': [key]};
    ResponseBody j(Object body) => _json(200, body, headers: h);
    final el = key == _kEl;
    if (path == '/api/admin/expenses' && m == 'GET') {
      return j({
        'success': true,
        'expenses': [
          {'id': el ? 91 : 11, 'amount': el ? 7000 : 15000, 'note': el ? 'كهرباء ايرث' : 'إيجار', 'expense_date': '2026-11-05'},
        ],
        'total': el ? 7000 : 15000,
        if (key != null) 'routed_writes': false,
      });
    }
    if (path == '/api/admin/expenses' && m == 'POST') return j({'success': true, 'id': 501});
    if (path.startsWith('/api/v2/expenses/recurring')) {
      return j({'success': true, 'enabled': true, 'templates': [], 'pending': []});
    }
    // المدراء: لكلّ شركةٍ مديرها — مديرُ غيرها في «تابع إلى» المفتوحة خلطٌ يُكشف
    if (path == '/api/v2/managers') {
      return j({
        'success': true,
        'data': [
          key == _kJt
              ? {'id': 92, 'username': 'jt_mgr', 'firstname': 'مدير', 'lastname': 'الجزيرة'}
              : {'id': 31, 'username': 'open_mgr', 'firstname': 'مدير', 'lastname': 'المفتوحة'},
        ],
      });
    }
    if (path == '/api/v2/packages') {
      return j({
        'success': true,
        'data': [
          {'id': 5, 'name': 'Gold', 'price': 25000},
        ],
      });
    }
    if (path == '/api/v2/subscribers' && m == 'POST') return j({'success': true, 'message': 'تمّ'});
    final f = fallback;
    if (f != null) {
      final r = await f.fetch(o, rs, cf);
      if (key == null) return r;
      return ResponseBody(r.stream, r.statusCode, headers: {...r.headers, 'x-company-key': [key]});
    }
    return j({'success': true, 'data': []});
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _companies() => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kOpen, 'code': 'supernet', 'username': 'u0', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': 'supernet:12', 'ns': 'a', 'currency': 'IQD', 'color_index': 0},
        {'key': _kEl, 'code': 'earthlink', 'provider': 'earthlink', 'username': 'u1', 'name': 'ايرث لنك', 'status': 'ok', 'admin_id': 'earthlink:77', 'ns': 'e', 'currency': 'IQD', 'color_index': 3},
        {'key': _kJt, 'code': 'jt', 'username': 'u2', 'name': 'الجزيرة', 'status': 'ok', 'admin_id': 'jt:6836', 'ns': 'j', 'currency': 'IQD', 'color_index': 1},
      ],
    };

void main() {
  setUpAll(visualSetUpAll);
  late _Srv srv;

  Future<void> up(WidgetTester t, {bool desktop = false}) async {
    if (desktop) AppPlatform.debugIsDesktop = true;
    final visual = await visualSetUp(s1bSasOwner);
    srv = _Srv(desktop ? visual : null);
    ApiClient.dio.httpClientAdapter = srv;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    MergedMode.reset();
    MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
    expect(await t.runAsync(() => MergedMode.enter()), isTrue);
  }

  Future<void> down(WidgetTester t, {int seconds = 3}) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(Duration(seconds: seconds));
    MergedMode.reset();
    await visualTearDown();
    AppPlatform.debugIsDesktop = null;
  }

  Future<void> settleReal(WidgetTester t, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  List<String> posts() => srv.asked.where((a) => a.startsWith('POST /api/admin/expenses')).toList();

  testWidgets('١ الحاسبة: الصرفيات لايرث لنك ثمّ الرئيسيّة ⇒ لا وجهة، وCtrl/⌘+N «إضافة صرفية» للمفتوحة ⇒ بلا مفتاح؛ وظاهرةً كذلك',
      (t) async {
    await up(t, desktop: true);
    try {
      await pumpVisual(t, const VisualDevice('', Size(1440, 900), 1), home: (_) => const MainShell());
      await settle(t, seconds: 3);
      expect(find.byKey(const ValueKey('desk-sidebar')), findsOneWidget, reason: 'غلاف الحاسبة');
      MergedMode.focus.value = _kEl;
      await settleReal(t);

      Future<void> nav(String title) async {
        final list = find.byKey(const ValueKey('desk-sidebar'));
        final sidebar = find.descendant(of: list, matching: find.byType(Scrollable)).first;
        final item = find.descendant(of: list, matching: find.text(title));
        await t.drag(sidebar, const Offset(0, 3000), warnIfMissed: false);
        await t.pump();
        for (var k = 0; k < 30 && item.evaluate().isEmpty; k++) {
          await t.drag(sidebar, const Offset(0, -120), warnIfMissed: false);
          await t.pump();
        }
        await t.runAsync(() => Scrollable.ensureVisible(item.evaluate().first, alignment: 0.5));
        await t.pump();
        await t.tap(item.first, warnIfMissed: false);
        await settleReal(t);
      }

      // Ctrl/⌘+N = onQuickAdd للغلاف (CallbackShortcuts) ⇒ «إضافة سريعة» نفسها من MainShell. يُنادى مباشرةً: بعد تبديل الجزء من
      // القائمة يخرج التركيز من الغلاف (IndexedStack يستثني الجزء المخفيّ من التركيز) فلا يصله المفتاح في الاختبار.
      Future<void> quickAddExpenseForOpen() async {
        t.widget<DesktopShell>(find.byType(DesktopShell)).onQuickAdd();
        await settleReal(t);
        await t.tap(find.text('dashboard.add_expense'.tr()));
        await settleReal(t);
        // «في أيّ شركة؟» ⇒ المفتوحة
        await t.tap(find.byKey(const ValueKey('merged-pick-$_kOpen')));
        await settleReal(t);
        final field = find.descendant(of: find.byType(DesignSheet).last, matching: find.byType(TextField)).first;
        await t.enterText(field, '15000');
        await t.pump();
        await t.tap(find.textContaining('تسجيل 15').last);
        await settleReal(t);
      }

      // الصرفيات لايرث لنك (موجَّهة وهي ظاهرة)
      final expensesTitle = buildAppModules().firstWhere((m) => m.id == 'expenses').title;
      await nav(expensesTitle);
      expect(srv.asked, contains('GET /api/admin/expenses $_kEl'));
      expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), _kEl);

      // الرئيسيّة: الصرفيات مخفيّةٌ ⇒ لا وجهة، ولا تعود بتبديل الشريط وهي مخفيّة
      await nav('desktop.title_dashboard'.tr());
      expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), isNull, reason: 'قسمٌ مخفيّ لا يوجِّه');
      MergedMode.focus.value = null;
      await settleReal(t);
      MergedMode.focus.value = _kEl;
      await settleReal(t);
      expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), isNull, reason: 'تبديل الشريط وهو مخفيّ لا يعيد وجهته');

      // Ctrl/⌘+N ⇒ «إضافة صرفية» ⇒ المفتوحة ⇒ بلا مفتاح
      srv.asked.clear();
      await quickAddExpenseForOpen();
      expect(t.takeException(), isNull);
      expect(posts(), ['POST /api/admin/expenses -'], reason: 'صرفيّة المفتوحة لا تُسجَّل في مال ايرث لنك: ${srv.asked}');
      expect(srv.bodies['POST /api/admin/expenses -'], containsPair('amount', 15000));

      // الصرفيات ثانيةً: تعود لوجهتها وتُجلب لايرث لنك من جديد
      srv.asked.clear();
      await nav(expensesTitle);
      expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), _kEl);
      expect(srv.asked, contains('GET /api/admin/expenses $_kEl'), reason: 'تُبنى لشركتها حين تظهر');
      expect(srv.asked.where((a) => a.startsWith('GET /api/admin/expenses') && a.endsWith(' -')), isEmpty,
          reason: 'لا جلب للمفتوحة تحت اسم ايرث لنك: ${srv.asked}');

      // وهي ظاهرةٌ لايرث لنك: Ctrl/⌘+N للمفتوحة ⇒ بلا مفتاح كذلك، والقسم باقٍ لايرث لنك
      srv.asked.clear();
      await quickAddExpenseForOpen();
      expect(t.takeException(), isNull);
      expect(posts(), ['POST /api/admin/expenses -'], reason: '${srv.asked}');
      expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), _kEl, reason: 'الصرفيات الظاهرة ما زالت لايرث لنك');
    } finally {
      await down(t, seconds: 6);
    }
  });

  testWidgets('٢ الجزء غير الظاهر: لا توجيه، وشاشته تبقى بحالها ما دامت لشركتها (لا جلب عند العودة)، وتُبنى من جديد إن اختيرت غيرها أو ذهب طلبٌ ضمنيّ من بادئاتها لغيرها',
      (t) async {
    await up(t);
    MergedMode.focus.value = _kEl;
    final visible = ValueNotifier<bool>(true);
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1),
        home: (_) => ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, v, __) => MergedPaneVisibility(visible: v, child: ExpensesScreen.mergedPage()),
            ));
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(srv.asked, contains('GET /api/admin/expenses $_kEl'));
    expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), _kEl);
    final screen = t.state(find.byType(ExpensesScreen));

    // مخفيٌّ: لا وجهة — والشاشة باقيةٌ بحالها (مراجعة 179، ثانويّة: كانت تُهدم وتُجلب عند كلّ عودة)
    visible.value = false;
    await settleReal(t);
    expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), isNull);
    expect(find.byType(ExpensesScreen, skipOffstage: false), findsOneWidget, reason: 'شاشة ايرث لنك بحالها وهي مخفيّة');
    srv.asked.clear();
    visible.value = true;
    await settleReal(t);
    expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), _kEl);
    expect(identical(t.state(find.byType(ExpensesScreen)), screen), isTrue, reason: 'الحالة نفسها (الفترة، التمرير)');
    expect(srv.asked.where((a) => a.startsWith('GET /api/admin/expenses')), isEmpty, reason: 'لا جلب عند العودة: ${srv.asked}');

    // شركةٌ أخرى اختيرت وهو مخفيّ ⇒ لا تُبنى لها مخفيّةً، ولا تبقى شاشة ايرث لنك
    visible.value = false;
    await settleReal(t);
    MergedMode.focus.value = _kJt;
    await settleReal(t);
    expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), isNull, reason: 'شركةٌ أخرى مختارة وهو مخفيّ ⇒ لا وجهة');
    expect(find.byType(ExpensesScreen, skipOffstage: false), findsNothing);
    srv.asked.clear();
    MergedMode.focus.value = _kEl;
    visible.value = true;
    await settleReal(t);
    expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), _kEl);
    expect(srv.asked, contains('GET /api/admin/expenses $_kEl'), reason: 'تُبنى لشركتها حين تظهر');
    expect(find.textContaining('كهرباء ايرث'), findsWidgets);

    // طلبٌ ضمنيّ من بادئاته وهو مخفيّ (كجلبٍ بالخلفيّة) ذهب للمفتوحة ⇒ لا تبقى الشاشة بما وصلها، وتُجلب لشركتها حين تظهر
    visible.value = false;
    await settleReal(t);
    await t.runAsync(() => ExpensesApi.list());
    await settleReal(t);
    expect(srv.asked.last, 'GET /api/admin/expenses -');
    expect(find.byType(ExpensesScreen, skipOffstage: false), findsNothing, reason: 'شاشةٌ قد تكون استلمت أرقام المفتوحة لا تبقى');
    srv.asked.clear();
    visible.value = true;
    await settleReal(t);
    expect(srv.asked, contains('GET /api/admin/expenses $_kEl'));
    expect(srv.asked.where((a) => a.startsWith('GET /api/admin/expenses') && a.endsWith(' -')), isEmpty);
    expect(t.takeException(), isNull);
    await down(t);
    expect(CompanyRoute.sectionKey, isNull);
  });

  testWidgets('٣ الهاتف كما كان: صفحةٌ فوق القسم الموجَّه (تغطّيه) لا ترفع وجهته', (t) async {
    await up(t);
    MergedMode.focus.value = _kEl;
    final navKey = GlobalKey<NavigatorState>();
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1),
        home: (_) => Navigator(
              key: navKey,
              onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => ExpensesScreen.mergedPage()),
            ));
    await settleReal(t);
    navKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('page-above'))));
    await settleReal(t);
    expect(find.text('page-above'), findsOneWidget);
    expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), _kEl, reason: 'ما يُفتح من القسم فوقه موجَّهٌ لشركته كما كان');
    navKey.currentState!.pop();
    await settleReal(t);
    expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), _kEl);
    await down(t);
  });

  testWidgets('٤ «مشترك جديد» للمفتوحة وقسم مدراء شركةٍ أخرى موجَّه: المدراء والباقات والإنشاء للمفتوحة (لا parent_id من غيرها)',
      (t) async {
    await up(t);
    await const FlutterSecureStorage().write(key: 'auth.can_access_managers', value: '1');
    SubscribersApi.clearAllCaches();
    // كقسم «المدراء» للجزيرة مفتوحٍ تحت (ظاهرٌ على الحاسبة، أو صفحةٌ تحت الإضافة)
    final owner = Object();
    CompanyRoute.enterSection(owner, _kJt, const ['/api/v2/managers', '/api/v2/acl-list', '/api/admin/managers']);
    addTearDown(() => CompanyRoute.leaveSection(owner));
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1),
        home: (_) => Builder(
              builder: (ctx) => Scaffold(
                body: Center(child: TextButton(onPressed: () => showAddSubscriberSheet(ctx), child: const Text('أضف'))),
              ),
            ));
    await settleReal(t);
    await t.tap(find.text('أضف'));
    await settleReal(t);
    await t.tap(find.byKey(const ValueKey('merged-pick-$_kOpen')));
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(srv.asked, contains('GET /api/v2/managers -'), reason: 'مدراء المفتوحة: ${srv.asked}');
    expect(srv.asked.where((a) => a.endsWith(' $_kJt')), isEmpty, reason: 'لا طلب من النافذة للجزيرة: ${srv.asked}');
    expect(srv.asked, contains('GET /api/v2/packages -'));

    await t.enterText(find.widgetWithText(TextField, 'مثال: ahmed@rezz'), 'new.user');
    await t.enterText(find.widgetWithText(TextField, '••••••••'), 'pw123456');
    final pkg = find.ancestor(of: find.text('اختر الباقة'), matching: find.byType(DropdownButton<int>));
    await t.ensureVisible(pkg);
    await t.pump();
    await t.tap(pkg);
    await settleReal(t);
    await t.tap(find.text('Gold').last);
    await settleReal(t);
    await t.tap(find.text('إضافة المشترك'));
    await settleReal(t);
    expect(t.takeException(), isNull);
    final created = srv.asked.where((a) => a.startsWith('POST /api/v2/subscribers')).toList();
    expect(created, ['POST /api/v2/subscribers -'], reason: '${srv.asked}');
    final body = srv.bodies['POST /api/v2/subscribers -'] as Map;
    expect(body['parent_id'], 12, reason: 'المدير الأب للمفتوحة (معرّف جلستها) لا مدير الجزيرة');

    // الضابط: الطلب نفسه بلا تثبيتٍ يذهب للقسم الموجَّه — فالتثبيت هو الذي أبقاها للمفتوحة
    await t.runAsync(() => SubscribersApi.loadManagers());
    expect(srv.asked.last, 'GET /api/v2/managers $_kJt');
    await down(t);
  });
}
