import 'dart:async';
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
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/accounts/accounts_screen.dart';
import 'package:rad_mysvcs/screens/app_modules.dart';
import 'package:rad_mysvcs/screens/expenses/expenses_screen.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';
import 'package:rad_mysvcs/screens/managers/managers_screen.dart';
import 'package:rad_mysvcs/screens/renew/renew_widgets.dart';
import 'package:rad_mysvcs/screens/sales/sales_screen.dart';
import 'package:rad_mysvcs/screens/settlements/settlements_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/edit_subscriber_sheet.dart';
import 'package:rad_mysvcs/screens/tickets/ticket_widgets.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/notification_router.dart';

import 'visual_perm/visual_perm_harness.dart';

/// مراجعة الإصدار 179 — التحقّق العدائيّ بعد 3b145978 (route_verify_final.json): اختبارٌ لكلّ بندٍ قائم. كلٌّ منها يفشل على
/// 34d0774a/7e46e3b3 وينجح بعد الإصلاح (القاعدة: الكتابة لا تأخذ وجهة قسمٍ أبداً — شركتها صريحةٌ من لحظة فتح شيتها؛ والقراءة تتبع
/// القسم ما دام أعلى ما يُرى، وصفحات المفتوحة تغطّيه؛ ولا يتبدّل الشريط تحت ما هو مفتوح).
///   أ. (مانع) «الكلّ»/إشعارٌ بلا عنصر كان يبدّل الشريط تحت شيت صرفيّةٍ مفتوح ⇒ صرفيّة ايرث لنك تُسجَّل في مال المفتوحة.
///   ب. (مانع) شيت التسوية: تبدّل الشريط وهو مفتوح ⇒ التسوية لصندوقٍ آخر.
///   ج. (مانع) الحاسبة: إخفاء الجزء تحت نافذة صرفيّةٍ مفتوحة (ملخّص «انتهت اليوم») ⇒ الحفظ للمفتوحة.
///   د. (ثانويّ) الحاسبة: الجزء الموجَّه يُهدم ويُجلب عند كلّ عودة.
///   هـ. (مانع) المبيعات: وجهةٌ مشتركة (SalesApi.routeKey) ⇒ «بيع مادّة» لمشترك المفتوحة يذهب لشركة قسم المبيعات.
///   و. (كبير) «الصفحات» فوق قسم مدراء شركةٍ أخرى ⇒ مدراؤها صفحاتٌ للمفتوحة.
///   ز. (كبير) مشتركٌ بلا مفتاح: «تابع إلى» في نافذة تعديله مدراء قسمٍ ظاهرٍ لشركةٍ أخرى.
///   ح. (كبير) رمز الوكيل وخطر الرقم في رسالة مشترك المفتوحة من قسمٍ ظاهرٍ لشركةٍ أخرى.
///   ط. (ثانويّ) ملخّص «انتهت اليوم» يفتح تبويب المشتركين على مختارة الشريط.
///   («رجع النت» من FiberWatch: fiber_monitor_test.)
/// التحقّق الثاني (route2_verify.json — إثباتٌ أقوى، كلٌّ يفشل بإرجاع ما يحرسه): ب يفحص قراءة الشيت نفسه وحدّ التسوية المرسَل
/// ومتوقّعها، وهـ يُكمل البيع (بلا مفتاح ولا قراءة للمشترك من ايرث لنك)، و«هـ (تكملة)» تبدّل الشريط وشيت بيع ايرث لنك مفتوح.
const _kOpen = 'c0000000000a1';
const _kEl = 'c0000000000e1';
const _kJt = 'c0000000000b2';

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

/// خادمٌ بصدى المفتاح كالخادم الحقيقيّ — لكلّ شركةٍ بياناتها (رقمٌ واحد في شركتين لشيئين مختلفين: خلطٌ يُكشف)، وما سواه لخادم
/// لقطات الصلاحيّات ([fallback]) على الحاسبة.
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
    final jt = key == _kJt;
    // ── الصرفيات (ايرث لنك موجَّهة الكتابة: routed_writes) ──
    if (path == '/api/admin/expenses' && m == 'GET') {
      return j({
        'success': true,
        'expenses': [
          {'id': el ? 91 : 11, 'amount': el ? 7000 : 15000, 'note': el ? 'كهرباء ايرث' : 'إيجار', 'expense_date': '2026-11-05'},
        ],
        'total': el ? 7000 : 15000,
        if (key != null) 'routed_writes': true,
      });
    }
    if (path == '/api/admin/expenses' && m == 'POST') return j({'success': true, 'id': 501});
    if (path.startsWith('/api/v2/expenses/recurring')) return j({'success': true, 'enabled': true, 'data': [], 'pending': []});
    // ── التسويات ──
    if (path == '/api/v2/settlements/current') {
      return j({
        'success': true,
        'data': {
          'started': true,
          'head': null,
          'period': {'start_at': '2026-11-01T00:00:00Z'},
          'cut': {'head_id': el ? 7 : 3, 'activity_id': el ? 700 : 300, 'expense_id': el ? 70 : 30},
          'totals': {
            'opening_balance': 0,
            'cash_activations': {'count': el ? 2 : 5, 'amount': el ? 30000 : 125000},
            'debt_payments': {'count': 0, 'amount': 0},
            'cash_in': el ? 30000 : 125000,
            'expenses': {'count': 0, 'amount': 0},
            'new_debts': {'count': 0, 'amount': 0},
            'expected_amount': el ? 30000 : 125000,
          },
          'collectors': [],
          'can_settle': true,
          'can_void': true,
          if (key != null) 'routed_writes': true,
        },
      });
    }
    if (path == '/api/v2/settlements/movements') return j({'success': true, 'data': {'items': [], 'has_more': false}});
    if (path == '/api/v2/settlements' && m == 'GET') return j({'success': true, 'data': {'items': [], 'total': 0}});
    if (path == '/api/v2/settlements' && m == 'POST') {
      return j({'success': true, 'data': {'id': el ? 77 : 33, 'number': 4, 'expected_amount': 30000, 'received_amount': 30000}});
    }
    // ── المدراء: لكلّ شركةٍ مديرها ──
    if (path == '/api/v2/managers') {
      return j({
        'success': true,
        'data': [
          jt
              ? {'id': 92, 'username': 'jt_mgr', 'firstname': 'مدير', 'lastname': 'الجزيرة'}
              : {'id': 31, 'username': 'open_mgr', 'firstname': 'مدير', 'lastname': 'المفتوحة'},
        ],
      });
    }
    if (path == '/api/v2/managers/full') {
      return j({
        'success': true,
        'data': [
          jt
              ? {'id': 92, 'username': 'jt_sub', 'firstname': 'فرعي', 'lastname': 'الجزيرة', 'balance': 0}
              : {'id': 31, 'username': 'open_sub', 'firstname': 'فرعي', 'lastname': 'المفتوحة', 'balance': 0},
        ],
        'total': 1,
      });
    }
    // ── بوّابة المشترك: رمز وكيل كلّ شركة ──
    if (path == '/api/v2/portal/settings') return j({'success': true, 'enabled': true, 'agent_code': jt ? '999999' : '123456'});
    if (path.startsWith('/api/whatsapp/templates/')) {
      return j({
        'success': true,
        'templates': [
          {'template_type': 'debt_reminder', 'is_active': 1, 'message_content': 'رمز الوكيل {agent_code}'},
        ],
      });
    }
    if (path == '/api/v2/whatsapp/contact-risk') return j({'success': true, 'data': {}});
    // ── المبيعات: لكلّ شركةٍ موادّها ──
    if (path == '/api/v2/sales/items') {
      return j({
        'success': true,
        'enabled': true,
        'data': [
          {
            'id': el ? 7 : 1, 'name': el ? 'ONU ايرث' : 'راوتر المفتوحة', 'code': null, 'unit': 'piece', 'unit_label': 'قطعة',
            'sale_price': 45000, 'cost_avg': 32000, 'qty': 5, 'stock_value': 160000, 'margin': 13000, 'active': true,
          },
        ],
        'totals': {'count': 1, 'stock_value': 160000, 'out_of_stock': 0, 'defective_items': 0, 'defective_value': 0},
        if (key != null) 'routed_writes': true,
      });
    }
    if (path == '/api/v2/sales' && m == 'GET') {
      return j({
        'success': true, 'enabled': true, 'data': [],
        'totals': {'count': 0, 'revenue': 0, 'cost': 0, 'profit': 0, 'cash': 0, 'debt': 0},
        'unresolved': 0,
        if (key != null) 'routed_writes': true,
      });
    }
    if (path == '/api/v2/sales/debt-status') return j({'success': true, 'data': []});
    if (path == '/api/v2/sales' && m == 'POST') {
      return j({
        'success': true,
        'data': {
          'id': el ? 61 : 31, 'payment': 'debt', 'status': 'done', 'total': 45000, 'cost': 32000, 'profit': 13000,
          'customer': {'kind': 'subscriber', 'idx': '88', 'username': 'ali.open', 'name': 'علي', 'phone': null},
          'note': null, 'by': null, 'employee_id': null, 'created_at': '2026-11-09T04:05:00Z', 'voided_at': null,
          'void_reason': null,
          'lines': [
            {'item_id': el ? 7 : 1, 'name': el ? 'ONU ايرث' : 'راوتر المفتوحة', 'unit': 'piece', 'qty': 1, 'unit_price': 45000,
              'unit_cost': 32000, 'total': 45000, 'cost': 32000, 'profit': 13000},
          ],
        },
      });
    }
    // ── المشترك ──
    final sub = RegExp(r'^/api/v2/subscribers/(\d+)(/[a-z-]+)?$').firstMatch(path);
    if (sub != null && m == 'GET') {
      final tail = sub.group(2) ?? '';
      if (tail == '/activation-data') return j({'success': true, 'data': {'parent_id': 31}});
      if (tail == '/password') return j({'success': true, 'password': 'pw-open'});
      if (tail.isEmpty) return j({'success': true, 'data': {'idx': sub.group(1), 'username': 'ali.open'}});
    }
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
        // المفتوحة: مدير جلسة الحزمة (visualSetUp ⇒ supernet:12)
        {'key': _kOpen, 'code': 'supernet', 'username': 'u0', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': 'supernet:12', 'ns': 'a', 'currency': 'IQD', 'color_index': 0},
        {'key': _kEl, 'code': 'earthlink', 'provider': 'earthlink', 'username': 'u1', 'name': 'ايرث لنك', 'status': 'ok', 'admin_id': 'earthlink:77', 'ns': 'e', 'currency': 'IQD', 'color_index': 3},
        {'key': _kJt, 'code': 'jt', 'username': 'u2', 'name': 'الجزيرة', 'status': 'ok', 'admin_id': 'jt:6836', 'ns': 'j', 'currency': 'IQD', 'color_index': 1},
      ],
    };

/// مشترك الشركة المفتوحة كما يصل من إشعارٍ أو الجرس أو طلبٍ أو تذكرة (NotificationRouter.findSubscriber): بلا مفتاح شركة.
Subscriber _keyless() =>
    Subscriber(idx: '88', username: 'ali.open', firstname: 'علي', lastname: 'المفتوحة', phone: '07701234567');

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

  List<String> writes(String path) => srv.asked.where((a) => !a.startsWith('GET ') && a.split(' ')[1] == path).toList();

  Future<void> typeAmount(WidgetTester t, String amount) async {
    final field = find.descendant(of: find.byType(DesignSheet).last, matching: find.byType(TextField)).first;
    await t.enterText(field, amount);
    await t.pump();
  }

  testWidgets('أ (مانع): الجرس والإشعار بلا عنصرٍ لا يبدّلان الشريط تحت شيت صرفيّة ايرث لنك المفتوح — التسجيل لها', (t) async {
    await up(t);
    try {
      MergedMode.focus.value = _kEl;
      final nav = GlobalKey<NavigatorState>();
      await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1),
          navigatorKey: nav, home: (_) => ExpensesScreen.mergedPage());
      await settleReal(t);
      expect(srv.asked, contains('GET /api/admin/expenses $_kEl'));
      // «إضافة» من صرفيات ايرث لنك ⇒ الشيت، والمبلغ مكتوب
      await t.tap(find.byType(FloatingActionButton));
      await settleReal(t);
      await typeAmount(t, '250000');

      // إشعار طلب تجديدٍ لم يعد مفتوحاً، ثمّ إشعار تذكرةٍ بلا رقم ⇒ قائمة المفتوحة فوق الشيت — والشريط كما هو
      final f1 = openRenewRequestPush(nav.currentState!, {'type': 'renew_request', 'request_id': '99'});
      await settleReal(t);
      final focusAfterRenew = MergedMode.focus.value;
      nav.currentState!.pop();
      await settleReal(t);
      expect(await t.runAsync(() => f1), isTrue);
      final f2 = openTicketPush(nav.currentState!, {'type': 'portal_ticket', 'event': 'new'});
      await settleReal(t);
      final focusAfterTicket = MergedMode.focus.value;
      nav.currentState!.pop();
      await settleReal(t);
      expect(await t.runAsync(() => f2), isTrue);

      // الشيت كما تُرك ⇒ «تسجيل» لايرث لنك
      srv.asked.clear();
      await t.tap(find.textContaining('تسجيل 250').last);
      await settleReal(t);
      expect(writes('/api/admin/expenses'), ['POST /api/admin/expenses $_kEl'],
          reason: 'صرفيّة ايرث لنك لا تُسجَّل في مال المفتوحة: ${srv.asked}');
      expect(srv.bodies['POST /api/admin/expenses $_kEl'], containsPair('amount', 250000));
      expect(t.takeException(), isNull);
      expect([focusAfterRenew, focusAfterTicket], [_kEl, _kEl], reason: 'لا يتبدّل الشريط تحت شيتٍ مفتوح');
    } finally {
      await down(t);
    }
  });

  testWidgets('ب (مانع): شيت التسوية يبقى لصندوق ايرث لنك ولو تبدّل الشريط وهو مفتوح — المعاينة والتسوية لها', (t) async {
    await up(t);
    try {
      MergedMode.focus.value = _kEl;
      await pumpVisual(t, const VisualDevice('', Size(390, 1600), 1), home: (_) => SettlementsScreen.mergedPage());
      await settleReal(t);
      expect(srv.asked, contains('GET /api/v2/settlements/current $_kEl'));
      srv.asked.clear();
      await t.tap(find.text('settle.settle_now'.tr()));
      await settleReal(t);
      expect(find.byType(DesignSheet), findsOneWidget, reason: 'شيت التسوية مفتوح');
      // معاينة الشيت نفسه الطازجة (ما يراه المدير هو ما يُسوّى) من صندوق ايرث لنك
      expect(srv.asked.where((a) => a.startsWith('GET /api/v2/settlements/current')), ['GET /api/v2/settlements/current $_kEl'],
          reason: 'معاينة الشيت: ${srv.asked}');
      expect(find.textContaining('30,000'), findsWidgets, reason: 'المتوقّع في صندوق ايرث لنك');
      // تبدّل الشريط وهو مفتوح (أيّ مصدر: لمسٌ قبله، إشعار، رجوع موظّفٍ لصفحته…)
      MergedMode.focus.value = null;
      await settleReal(t);
      srv.asked.clear();
      await t.tap(find.textContaining('settle.confirm'.tr(namedArgs: {'amt': ''}).trim()).last);
      await settleReal(t);
      expect(t.takeException(), isNull);
      expect(writes('/api/v2/settlements'), ['POST /api/v2/settlements $_kEl'],
          reason: 'تسوية ايرث لنك لا تذهب لصندوق المفتوحة: ${srv.asked}');
      // وتُسوّى بما عوين: حدّ صندوق ايرث لنك ومتوقّعه — لا حدّ المفتوحة (3/300/30) ولا متوقّعها (125,000)
      final body = srv.bodies['POST /api/v2/settlements $_kEl']! as Map;
      expect(body['cut'], {'head_id': 7, 'activity_id': 700, 'expense_id': 70});
      expect([body['expected_amount'], body['received_amount']], [30000, 30000]);
    } finally {
      await down(t);
    }
  });

  Future<void> deskNav(WidgetTester t, String title) async {
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

  Future<String> deskOpenExpenses(WidgetTester t) async {
    await pumpVisual(t, const VisualDevice('', Size(1440, 900), 1), home: (_) => const MainShell());
    await settle(t, seconds: 3);
    MergedMode.focus.value = _kEl;
    await settleReal(t);
    final expensesTitle = buildAppModules().firstWhere((m) => m.id == 'expenses').title;
    await deskNav(t, expensesTitle);
    expect(srv.asked, contains('GET /api/admin/expenses $_kEl'));
    return expensesTitle;
  }

  testWidgets('ج (مانع): الحاسبة — ملخّص «انتهت اليوم» يخفي جزء الصرفيات تحت نافذتها المفتوحة ⇒ الحفظ لايرث لنك (شركة النافذة)',
      (t) async {
    await up(t, desktop: true);
    try {
      await deskOpenExpenses(t);
      // «إضافة» ⇒ نافذة الصرفيّة (الجذر)، ثمّ ملخّصٌ يفتح تبويب المشتركين تحتها فيُخفى الجزء
      await t.tap(find.text('common.add'.tr()).first);
      await settleReal(t);
      await typeAmount(t, '250000');
      NotificationRouter.onDestination?.call(NotificationDestination.subscribersExpired);
      await settleReal(t);
      expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), isNull, reason: 'الجزء أُخفي تحت النافذة');
      srv.asked.clear();
      await t.tap(find.textContaining('تسجيل 250').last);
      await settleReal(t);
      expect(writes('/api/admin/expenses'), ['POST /api/admin/expenses $_kEl'],
          reason: 'النافذة فُتحت لايرث لنك فتُسجَّل لها: ${srv.asked}');
      expect(t.takeException(), isNull, reason: 'لا setState بعد dispose');
    } finally {
      await down(t, seconds: 6);
    }
  });

  testWidgets('د (ثانويّ): الحاسبة — جزء الصرفيات الموجَّه يعود بحاله (الحالة نفسها) بلا جلبٍ جديد بعد تبديل الجزء', (t) async {
    await up(t, desktop: true);
    try {
      final expensesTitle = await deskOpenExpenses(t);
      final screen = t.state(find.byType(ExpensesScreen));
      await deskNav(t, 'desktop.title_dashboard'.tr());
      srv.asked.clear();
      await deskNav(t, expensesTitle);
      expect(srv.asked.where((a) => a.startsWith('GET /api/admin/expenses')), isEmpty, reason: 'لا جلب عند العودة: ${srv.asked}');
      expect(identical(t.state(find.byType(ExpensesScreen)), screen), isTrue, reason: 'حالة الجزء باقية (الفترة، التمرير)');
      expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), _kEl);
      expect(t.takeException(), isNull);
    } finally {
      await down(t, seconds: 6);
    }
  });

  testWidgets('هـ (مانع): قسم المبيعات على ايرث لنك مركّبٌ تحت صفحة مشترك المفتوحة (بلا مفتاح) ⇒ «بيع مادّة» موادّ المفتوحة وبيعها '
      'بلا مفتاح', (t) async {
    await up(t);
    try {
      final nav = GlobalKey<NavigatorState>();
      await pumpVisual(t, const VisualDevice('', Size(390, 1600), 1), navigatorKey: nav, home: (_) => const SalesScreen());
      await settleReal(t);
      await t.tap(find.byKey(const ValueKey('sales-co-$_kEl')));
      await settleReal(t);
      expect(srv.asked, contains('GET /api/v2/sales/items $_kEl'), reason: 'القسم يعرض ايرث لنك');

      // صفحةٌ فوقه (إشعار، جرس…) لمشترك المفتوحة ⇒ «بيع مادّة»
      late BuildContext ctx;
      nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: Builder(builder: (c) {
                ctx = c;
                return const SizedBox.expand();
              }))));
      await settleReal(t);
      srv.asked.clear();
      final s = _keyless();
      final f = showSellToSubscriber(ctx, idx: s.idx!, username: s.username, name: s.fullName, companyKey: s.companyKey);
      await settleReal(t);
      expect(srv.asked.where((a) => a.contains('/api/v2/sales')), ['GET /api/v2/sales/items -'],
          reason: 'موادّ المفتوحة لا ايرث لنك: ${srv.asked}');
      expect(find.byType(DesignSheet), findsOneWidget, reason: 'شيت البيع مفتوح');
      // البيع نفسه: مادّة المفتوحة على دين مشتركها (التأكيد بضغطتين) ⇒ بلا مفتاح، ولا قراءة للمشترك من ايرث لنك
      await t.tap(find.text('sales.pick_item'.tr()).last);
      await settleReal(t);
      await t.tap(find.textContaining('راوتر المفتوحة').last);
      await settleReal(t);
      await t.tap(find.textContaining('بيع على الدين').last);
      await t.pump();
      await t.tap(find.textContaining('تأكيد — دين').last);
      await settleReal(t);
      expect(await t.runAsync(() => f), isTrue, reason: 'البيع تمّ: ${srv.asked}');
      expect(writes('/api/v2/sales'), ['POST /api/v2/sales -'], reason: 'بيع مشترك المفتوحة لها: ${srv.asked}');
      final sold = srv.bodies['POST /api/v2/sales -']! as Map;
      expect((sold['customer'] as Map)['idx'], '88');
      expect(sold['payment'], 'debt');
      // (قسم ايرث لنك تحتها يحدّث قائمته بعد البيع — قراءته هو)
      expect(srv.asked.where((a) => a.endsWith(' $_kEl') && (!a.startsWith('GET ') || a.contains('/api/v2/subscribers'))), isEmpty,
          reason: 'لا كتابة لايرث لنك ولا قراءةٌ لمشترك المفتوحة منها: ${srv.asked}');
    } finally {
      await down(t);
    }
  });

  testWidgets('هـ (تكملة): «بيع جديد» من قسم ايرث لنك ثمّ تبدّل الشريط والشيت مفتوح ⇒ البيع لايرث لنك (شركة الشيت لحظة فتحه)',
      (t) async {
    await up(t);
    try {
      await pumpVisual(t, const VisualDevice('', Size(390, 1600), 1), home: (_) => const SalesScreen());
      await settleReal(t);
      await t.tap(find.byKey(const ValueKey('sales-co-$_kEl')));
      await settleReal(t);
      await t.tap(find.byType(FloatingActionButton));
      await settleReal(t);
      await t.tap(find.text('sales.pick_item'.tr()).last);
      await settleReal(t);
      await t.tap(find.textContaining('ONU ايرث').last);
      await settleReal(t);
      MergedMode.focus.value = null;
      await settleReal(t);
      srv.asked.clear();
      await t.tap(find.textContaining('بيع نقداً').last);
      await settleReal(t);
      expect(writes('/api/v2/sales'), ['POST /api/v2/sales $_kEl'], reason: 'البيع لا يتبع الشريط بعد فتح شيته: ${srv.asked}');
      expect(((srv.bodies['POST /api/v2/sales $_kEl']! as Map)['lines'] as List).single, containsPair('item_id', 7));
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('و (كبير): «الصفحات» فوق قسم مدراء الجزيرة الظاهر ⇒ مدراء المفتوحة الفرعيّون لا مدراؤها', (t) async {
    await up(t);
    try {
      await const FlutterSecureStorage().write(key: 'auth.can_access_managers', value: '1');
      MergedMode.focus.value = _kJt;
      final nav = GlobalKey<NavigatorState>();
      await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1),
          navigatorKey: nav, home: (_) => ManagersScreen.mergedPage());
      await settleReal(t);
      expect(srv.asked, contains('GET /api/v2/managers/full $_kJt'), reason: 'القسم يعرض الجزيرة');
      srv.asked.clear();
      // شريط الحاسبة يفتح «الصفحات» داخل الجزء الظاهر نفسه (DesktopShell._openPage)
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const AccountsScreen()));
      await settleReal(t);
      expect(t.takeException(), isNull);
      final full = srv.asked.where((a) => a.startsWith('GET /api/v2/managers/full')).toList();
      expect(full, ['GET /api/v2/managers/full -'], reason: 'صفحات الجلسة المفتوحة: ${srv.asked}');
      final pages = find.byType(AccountsScreen);
      expect(find.descendant(of: pages, matching: find.textContaining('open_sub')), findsWidgets);
      expect(find.descendant(of: pages, matching: find.textContaining('jt_sub')), findsNothing);
    } finally {
      await down(t);
    }
  });

  testWidgets('ز (كبير): مشتركٌ بلا مفتاح وقسم مدراء الجزيرة ظاهر ⇒ «تابع إلى» في نافذة تعديله مدراء المفتوحة', (t) async {
    await up(t);
    try {
      await const FlutterSecureStorage().write(key: 'auth.can_access_managers', value: '1');
      SubscribersApi.clearAllCaches();
      MergedMode.focus.value = _kJt;
      final nav = GlobalKey<NavigatorState>();
      await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1),
          navigatorKey: nav, home: (_) => ManagersScreen.mergedPage());
      await settleReal(t);
      expect(CompanyRoute.sectionKeyFor('/api/v2/managers'), _kJt);
      late BuildContext ctx;
      nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: Builder(builder: (c) {
                ctx = c;
                return const SizedBox.expand();
              }))));
      await settleReal(t);
      srv.asked.clear();
      unawaited(showEditSubscriberSheet(ctx, _keyless()));
      await settleReal(t);
      expect(t.takeException(), isNull);
      expect(srv.asked, contains('GET /api/v2/managers -'), reason: 'مدراء المفتوحة: ${srv.asked}');
      expect(srv.asked.where((a) => a.endsWith(' $_kJt')), isEmpty, reason: 'لا طلب من النافذة للجزيرة: ${srv.asked}');
    } finally {
      await down(t);
    }
  });

  testWidgets('ح (كبير): مشتركٌ بلا مفتاح وقسما «بوابة المشترك» و«التبليغات» للجزيرة ظاهران ⇒ رمز وكيل المفتوحة وخطر رقمها في '
      'رسالته', (t) async {
    await up(t);
    try {
      final owner = Object();
      // كجزأي «بوابة المشترك» و«التبليغات» للجزيرة ظاهرين تحت (الحاسبة) أو صفحتين تحت الإشعار (الهاتف)
      CompanyRoute.enterSection(owner, _kJt, const ['/api/v2/portal', '/api/v2/admin/branding', '/api/v2/admin/portal-packages',
          '/api/whatsapp/broadcast', '/api/v2/whatsapp']);
      addTearDown(() => CompanyRoute.leaveSection(owner));
      late BuildContext ctx;
      await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1),
          home: (_) => Scaffold(body: Builder(builder: (c) {
                ctx = c;
                return const SizedBox.expand();
              })));
      await settleReal(t);
      srv.asked.clear();
      final f = WhatsAppApi.sendTemplateWithPreview(context: ctx, sub: _keyless(), templateType: 'debt_reminder');
      await settleReal(t);
      expect(t.takeException(), isNull);
      expect(srv.asked, contains('GET /api/v2/portal/settings -'), reason: 'رمز وكيل المفتوحة: ${srv.asked}');
      expect(find.textContaining('123456', findRichText: true), findsWidgets, reason: 'المعاينة برمز المفتوحة');
      expect(find.textContaining('999999', findRichText: true), findsNothing);
      expect(srv.asked, contains('POST /api/v2/whatsapp/contact-risk -'), reason: 'خطر الرقم من واتساب المفتوحة');
      expect(srv.asked.where((a) => a.endsWith(' $_kJt')), isEmpty, reason: '${srv.asked}');
      Navigator.of(ctx).pop();
      await settleReal(t);
      await t.runAsync(() => f);
    } finally {
      await down(t);
    }
  });

  testWidgets('ط (ثانويّ) + أ: إشعار المدراء ⇒ مدراء المفتوحة مثبَّتين بلا تبديل الشريط؛ وملخّص «انتهت اليوم» ⇒ تبويب المشتركين على '
      'المفتوحة — ولا يتبدّل الشريط وفوق الغلاف شيءٌ مفتوح',
      (t) async {
    await up(t);
    try {
      MergedMode.focus.value = _kEl;
      final nav = GlobalKey<NavigatorState>();
      await pumpVisual(t, const VisualDevice('', Size(390, 900), 1), navigatorKey: nav, home: (_) => const MainShell());
      await settle(t, seconds: 3);
      // إشعار المدراء (دينٌ أو رصيدٌ في المفتوحة) ⇒ مدراء المفتوحة مثبَّتين لها، والشريط كما هو
      srv.asked.clear();
      NotificationRouter.onDestination?.call(NotificationDestination.managers);
      await settleReal(t);
      expect(MergedMode.focus.value, _kEl, reason: 'إشعار المدراء لا يبدّل الشريط');
      expect(find.byType(ManagersScreen), findsOneWidget);
      expect(srv.asked, contains('GET /api/v2/managers/full -'), reason: 'مدراء المفتوحة: ${srv.asked}');
      expect(find.textContaining('كما في الإشعارات'), findsOneWidget);
      nav.currentState!.pop();
      await settleReal(t);
      // شيءٌ مفتوحٌ فوق الغلاف ⇒ الشريط كما هو
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('page-above'))));
      await settleReal(t);
      NotificationRouter.onDestination?.call(NotificationDestination.subscribersExpired);
      await settleReal(t);
      expect(MergedMode.focus.value, _kEl, reason: 'لا يتبدّل الشريط تحت ما هو مفتوح');
      nav.currentState!.pop();
      await settleReal(t);
      // لا شيء فوقه ⇒ المفتوحة في الشريط
      NotificationRouter.onDestination?.call(NotificationDestination.subscribersExpired);
      await settleReal(t);
      expect(MergedMode.focus.value, _kOpen, reason: 'التبويب يعرض قائمة المفتوحة صاحبة الملخّص');
      expect(t.takeException(), isNull);
    } finally {
      await down(t, seconds: 6);
    }
  });
}
