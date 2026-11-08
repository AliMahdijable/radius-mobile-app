import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/cards_api.dart';
import 'package:rad_mysvcs/screens/cards/cards_screen.dart';
import 'package:rad_mysvcs/screens/expenses/expenses_screen.dart';
import 'package:rad_mysvcs/screens/telegram/telegram_screen.dart';
import 'package:rad_mysvcs/screens/settlements/settlements_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/add_subscriber_sheet.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/api/renew_requests_api.dart';
import 'package:rad_mysvcs/screens/renew/renew_requests_screen.dart';
import 'package:rad_mysvcs/widgets/merged_section.dart';
import 'package:rad_mysvcs/screens/broadcast/broadcast_screen.dart';
import 'package:rad_mysvcs/screens/discounts/discounts_screen.dart';
import 'package:rad_mysvcs/screens/employees/employees_screen.dart';
import 'package:rad_mysvcs/screens/portal_settings/portal_settings_screen.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «قوائم أخرى» بـ«كل الشركات» (٨ نوفمبر — المالك: «كل الاقسام مال قائمة المزيد لازم تخضع لهذا النظام شركتين بدقة»):
///   ١. وجهة القسم: بادئاته وحدها موجَّهة للمختارة (لا طلبات التطبيق الأخرى)، ويرفعها صاحبها وحده.
///   ٢. التسويات: «الكل» = المفتوحة بلا توجيه؛ شركةٌ أخرى ⇒ صندوقها موجَّهاً، مقفلةً حتى يقول الخادم routed_writes، ثمّ «تسوية الآن».
///   ٣. المصاريف: قائمتها موجَّهة، والقفل بسببها، وقوالب «الصرفيات الثابتة» لا تُعرض تحت اسم غير المفتوحة.
///   ٤–٥. أقسام «للعرض هنا» (تلغرام، الكارتات): قراءاتها لمدير المختارة، وحال الجلسة المفتوحة لا يتلوّث.
///   ٦. «للمفتوحة وحدها» (الشحن، الأسعار، التحويل…): لا توجيه أبداً، وغيرها ⇒ صفحة القفل بسببها.
const _kOpen = 'c0000000000a1';
const _kEl = 'c0000000000e1';

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

class _Srv implements HttpClientAdapter {
  final asked = <String>[];
  bool elWrites = false;
  bool tgConnected = false;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    asked.add('${o.method} $path ${key ?? '-'}');
    final h = key == null ? const <String, List<String>>{} : {'x-company-key': [key]};
    final el = key == _kEl;
    if (path == '/api/v2/settlements/current') {
      return _json(200, {
        'success': true,
        'data': {
          'started': true,
          'head': null,
          'period': {'start_at': '2026-11-01T00:00:00Z'},
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
          if (key != null) 'routed_writes': el && elWrites,
        },
      }, headers: h);
    }
    if (path == '/api/v2/settlements/movements') return _json(200, {'success': true, 'data': {'items': [], 'has_more': false}}, headers: h);
    if (path == '/api/v2/settlements') return _json(200, {'success': true, 'data': {'items': [], 'total': 0}}, headers: h);
    if (path == '/api/admin/expenses') {
      return _json(200, {
        'success': true,
        'expenses': [
          {'id': el ? 91 : 11, 'amount': el ? 7000 : 15000, 'note': el ? 'كهرباء ايرث' : 'إيجار', 'expense_date': '2026-11-05'},
        ],
        'total': el ? 7000 : 15000,
        if (key != null) 'routed_writes': el && elWrites,
      }, headers: h);
    }
    if (path.startsWith('/api/telegram/status/')) {
      if (tgConnected) {
        return _json(200, {
          'success': true,
          'status': {'exists': true, 'connected': true, 'botUsername': el ? 'el_bot' : 'sn_bot', 'bindings': {'total': 1, 'active': 1, 'blocked': 0}},
        }, headers: h);
      }
      return _json(200, {'success': true, 'connected': false, 'bot_username': null}, headers: h);
    }
    if (path.startsWith('/api/telegram/bindings/')) {
      return _json(200, {
        'success': true,
        'bindings': [
          {'id': 1, 'admin_id': el ? 'earthlink:77' : 'supernet:12', 'sas4_idx': '77', 'chat_id': '1', 'tg_username': 'tg77', 'is_blocked': 0},
        ],
      }, headers: h);
    }
    // قائمة المشتركين: نفس الرقم ٧٧ في الشركتين لشخصين مختلفين — فاسم المفتوحة تحت ايرث لنك خلطٌ يُكشف
    if (path == '/api/v2/subscribers') {
      return _json(200, {
        'success': true,
        'data': [
          {'idx': '77', 'username': el ? 'eluser' : 'snuser77', 'firstname': el ? 'مشترك' : 'سوبرنت', 'lastname': el ? 'ايرث' : 'خطأ'},
        ],
      }, headers: h);
    }
    if (path == '/api/discounts') {
      return _json(200, {
        'success': true,
        'data': [
          {'id': el ? 5 : 1, 'subscriber_username': el ? 'eluser' : 'snuser77', 'discount_amount': el ? 3000 : 1000, 'package_name': 'Economy'},
        ],
      }, headers: h);
    }
    if (path == '/api/v2/portal/settings') {
      return _json(200, {
        'success': true,
        'enabled': true,
        'agent_code': el ? '200301' : '100200',
        'sections': {'connection': true, 'usage': false, 'device': false},
      }, headers: h);
    }
    if (path == '/api/v2/cards/summary') {
      return _json(200, {'success': true, 'enabled': true, 'totals': {'available': el ? 7 : 40, 'used': 0}, 'series': []}, headers: h);
    }
    // «مشترك جديد» في ايرث لنك: خياراتها (رصيدٌ وكارت، باقةٌ واحدة) — فيُبنى حقل باسورد الإيداع ويُسأل حاله
    if (path == '/api/v2/el/create-options') {
      return _json(200, {
        'success': true,
        'data': {
          'user_suffix': '@najaf',
          'methods': {'deposit': true, 'card': true},
          'packages': [{'id': '11', 'name': 'Economy', 'price': 35000}],
          'deposit_balance': 100000,
        },
      }, headers: h);
    }
    // «طلبات التفعيل» (للعرض لكلّ شركة): المتاح والقائمة — طلبٌ معلّق لكلّ شركة باسمٍ يميّزها
    if (path == '/api/v2/portal/renew-settings') {
      return _json(200, {'success': true, 'available': true, 'can_use': true, 'can_edit': true, 'enabled': true}, headers: h);
    }
    if (path == '/api/v2/portal/renew-requests') {
      return _json(200, {
        'success': true,
        'items': [
          {'id': el ? 902 : 102, 'status': 'pending', 'months': 1, 'amount': 25000, 'created_at': '2026-11-08T10:00:00Z',
            'subscriber': {'idx': el ? '77' : '7', 'username': el ? 'eluser' : 'snuser', 'name': el ? 'مشترك ايرث' : 'مشترك سوبرنت'},
            'package': {'id': '5', 'name': 'Gold', 'same': true}},
        ],
        'counts': {'pending': 1, 'accepted': 0},
      }, headers: h);
    }
    if (path == '/api/v2/el/prepaid-needed') {
      return _json(200, {'success': true, 'data': {'items': const []}}, headers: h);
    }
    if (path == '/api/v2/el/deposit-password') {
      return _json(200, {'success': true, 'data': {'saved': false, 'can_manage': true}}, headers: h);
    }
    if (path.startsWith('/api/v2/expenses/recurring')) {
      return _json(200, {'success': true, 'enabled': true, 'templates': [], 'pending': []}, headers: h);
    }
    return _json(200, {'success': true, 'data': []}, headers: h);
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
      ],
    };

void main() {
  setUpAll(visualSetUpAll);
  late _Srv srv;

  Future<void> up(WidgetTester t) async {
    await visualSetUp(s1bSasOwner);
    srv = _Srv();
    ApiClient.dio.httpClientAdapter = srv;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    MergedMode.reset();
    MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
    expect(await t.runAsync(() => MergedMode.enter()), isTrue);
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
    MergedMode.reset();
    await visualTearDown();
  }

  Future<void> settleReal(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  test('١ وجهة القسم: بادئاته وحدها، ويرفعها صاحبها وحده', () {
    final a = Object(), b = Object();
    CompanyRoute.enterSection(a, _kEl, const ['/api/v2/settlements']);
    expect(CompanyRoute.sectionKeyFor('/api/v2/settlements'), _kEl);
    expect(CompanyRoute.sectionKeyFor('/api/v2/settlements/current'), _kEl);
    expect(CompanyRoute.sectionKeyFor('/api/v2/settlementsx'), isNull, reason: 'البادئة مقطعٌ كامل');
    expect(CompanyRoute.sectionKeyFor('/api/v2/subscribers'), isNull, reason: 'طلبات التطبيق الأخرى للمفتوحة');
    CompanyRoute.leaveSection(b);
    expect(CompanyRoute.sectionKey, _kEl, reason: 'قسمٌ آخر لا يرفع وجهة غيره');
    CompanyRoute.leaveSection(a);
    expect(CompanyRoute.sectionKey, isNull);
    CompanyRoute.enterSection(a, 'not-a-key', const ['/x']);
    expect(CompanyRoute.sectionKey, isNull, reason: 'مفتاحٌ غير صالح لا يُضبط');
  });

  testWidgets('٢ التسويات: «الكل» = المفتوحة بلا توجيه؛ ايرث لنك موجَّهةٌ مقفلةٌ حتى routed_writes ثمّ «تسوية الآن»', (t) async {
    await up(t);
    const screen = MergedSection(prefixes: ['/api/v2/settlements'], child: SettlementsScreen());
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1), home: (_) => screen);
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(srv.asked, contains('GET /api/v2/settlements/current -'), reason: '«الكل» = المفتوحة كما كانت');
    expect(find.textContaining('تعرض الشركة المفتوحة'), findsOneWidget);
    expect(find.text('تسوية الآن'), findsOneWidget);

    // ايرث لنك: موجَّهة، ومقفلة (routed_writes false)
    srv.asked.clear();
    MergedMode.focus.value = _kEl;
    await settleReal(t);
    expect(srv.asked.where((a) => a.contains('/api/v2/settlements')).every((a) => a.endsWith(_kEl)), isTrue, reason: '${srv.asked}');
    expect(srv.asked, contains('GET /api/v2/settlements/current $_kEl'));
    expect(find.textContaining('«ايرث لنك» للعرض هنا'), findsOneWidget);
    expect(find.text('تسوية الآن'), findsNothing, reason: 'لا تسوية لشركةٍ لم يفتح الخادم كتابتها');
    expect(CompanyRoute.sectionKey, _kEl);

    // الخادم يفتحها ⇒ «تسوية الآن» واسمها فوقها
    srv.elWrites = true;
    MergedMode.focus.value = null;
    await settleReal(t);
    expect(CompanyRoute.sectionKey, isNull, reason: '«الكل» يرفع الوجهة');
    MergedMode.focus.value = _kEl;
    await settleReal(t);
    expect(find.textContaining('«ايرث لنك» تُدار من هنا'), findsOneWidget);
    expect(find.text('تسوية الآن'), findsOneWidget);
    await down(t);
    expect(CompanyRoute.sectionKey, isNull, reason: 'إغلاق القسم يرفع وجهته');
  });

  testWidgets('٣ المصاريف: قائمتها موجَّهة والقفل بسببها، والصرفيات الثابتة لا تُعرض تحت اسم غير المفتوحة', (t) async {
    await up(t);
    const screen = MergedSection(prefixes: ['/api/admin/expenses', '/api/v2/expenses'], child: ExpensesScreen());
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1), home: (_) => screen);
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(find.textContaining('إيجار'), findsWidgets);
    expect(srv.asked.where((a) => a.startsWith('GET /api/v2/expenses/recurring')), isNotEmpty, reason: 'المفتوحة: قوالبها كما كانت');

    srv.asked.clear();
    MergedMode.focus.value = _kEl;
    await settleReal(t);
    expect(srv.asked, contains('GET /api/admin/expenses $_kEl'));
    expect(srv.asked.where((a) => a.startsWith('GET /api/v2/expenses/recurring')), isEmpty, reason: 'لا قوالب المفتوحة تحت اسم ايرث لنك');
    expect(find.textContaining('كهرباء ايرث'), findsWidgets);
    expect(find.textContaining('إيجار'), findsNothing);
    expect(find.textContaining('«ايرث لنك» للعرض هنا'), findsOneWidget);
    await down(t);
  });

  testWidgets('٤ تلغرام (قراءةٌ وحدها): حال الشركة المختارة بمعرّف مديرها لا المفتوحة، و«للعرض هنا»', (t) async {
    await up(t);
    const screen = MergedSection(readOnly: true, prefixes: ['/api/telegram'], child: TelegramScreen());
    MergedMode.focus.value = _kEl;
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1), home: (_) => screen);
    await settleReal(t);
    expect(t.takeException(), isNull);
    final st = srv.asked.where((a) => a.startsWith('GET /api/telegram/status/')).toList();
    expect(st, isNotEmpty);
    expect(st.every((a) => a.contains('earthlink') && a.endsWith(_kEl)), isTrue, reason: '$st');
    expect(find.textContaining('«ايرث لنك» للعرض هنا'), findsOneWidget);
    await down(t);
  });

  testWidgets('٥ الكارتات (قراءةٌ وحدها): ملخّص الشركة المختارة لا يُكتب فوق شارة المفتوحة، وملخّص المفتوحة لا يُرسم تحتها', (t) async {
    await up(t);
    CardsState.reset();
    const screen = MergedSection(readOnly: true, prefixes: ['/api/v2/cards'], child: CardsScreen());
    MergedMode.focus.value = _kEl;
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1), home: (_) => screen);
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(srv.asked, contains('GET /api/v2/cards/summary $_kEl'));
    expect(CardsState.lastSummary, isNull, reason: 'ملخّص ايرث لنك لا يصير «آخر ملخّص» للجلسة المفتوحة');
    await down(t);
  });

  testWidgets('٦ «للمفتوحة وحدها» (الشحن/الأسعار/التحويل): لا توجيه أبداً، غيرها ⇒ صفحة القفل بسببها، ولا إعادة جلبٍ بين «الكل» والمفتوحة', (t) async {
    await up(t);
    _OpenOnlyProbe.built = 0;
    final screen = MergedSection.openOnly(title: 'شحن رصيد الصفحة', reason: 'الشحن يُضاف لرصيد صفحة الشركة المفتوحة', child: const _OpenOnlyProbe());
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1), home: (_) => screen);
    await settleReal(t);
    expect(t.takeException(), isNull);
    // «الكل» ⇒ الشاشة نفسها للمفتوحة، والشريط يقول لمن ولماذا
    expect(find.text('probe-body'), findsOneWidget);
    expect(find.textContaining('للشركة المفتوحة «سوبرنت» وحدها'), findsOneWidget);
    expect(CompanyRoute.sectionKey, isNull);
    expect(_OpenOnlyProbe.built, 1);

    // ايرث لنك ⇒ لا شاشة ولا توجيه: بطاقة القفل باسمها و«بدّل إليها»
    MergedMode.focus.value = _kEl;
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(find.text('probe-body'), findsNothing, reason: 'لا شاشة المفتوحة تحت اسم ايرث لنك');
    expect(find.byKey(const ValueKey('merged-open-only-card')), findsOneWidget);
    expect(find.textContaining('«شحن رصيد الصفحة» لـ«ايرث لنك» من صفحتها'), findsOneWidget);
    expect(find.textContaining('بدّل إلى «ايرث لنك»'), findsOneWidget);
    expect(find.textContaining('الشحن يُضاف لرصيد صفحة الشركة المفتوحة — بدّل إليها'), findsOneWidget);
    expect(CompanyRoute.sectionKey, isNull, reason: 'القسم لا يُوجَّه أبداً');
    expect(CompanyRoute.sectionKeyFor('/api/v2/self-deposit/options'), isNull);

    // المفتوحة نفسها ⇒ الشاشة، ثمّ «الكل» ⇒ الشاشة نفسها بلا إعادة بناء (لا جلب ثانٍ)
    MergedMode.focus.value = _kOpen;
    await settleReal(t);
    expect(find.text('probe-body'), findsOneWidget);
    expect(find.textContaining('للشركة المفتوحة «سوبرنت» وحدها'), findsOneWidget);
    final afterOpen = _OpenOnlyProbe.built;
    MergedMode.focus.value = null;
    await settleReal(t);
    expect(find.text('probe-body'), findsOneWidget);
    expect(_OpenOnlyProbe.built, afterOpen, reason: '«الكل» والمفتوحة شاشةٌ واحدة');
    expect(srv.asked.where((a) => !a.endsWith(' -')), isEmpty, reason: 'لا طلب موجَّه من قسمٍ للمفتوحة وحدها: ${srv.asked}');
    await down(t);
  });

  testWidgets('٧ قسمٌ داخل قسم («تسوية الحساب ←» من الصرفيات): التسوية بغلافها لشركة الصرفيات، وإغلاقها لا يمسح وجهة الصرفيات', (t) async {
    // المكدّس وحده أوّلاً: الخارجيّ يبقى يوجّه بادئاته والداخليّ فوقه، وإغلاق الداخليّ لا يرفعه
    final outer = Object(), inner = Object();
    CompanyRoute.enterSection(outer, _kEl, const ['/api/admin/expenses']);
    CompanyRoute.enterSection(inner, _kEl, const ['/api/v2/settlements']);
    expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), _kEl, reason: 'الخارجيّ يوجّه وهو تحت');
    expect(CompanyRoute.sectionKeyFor('/api/v2/settlements/current'), _kEl);
    CompanyRoute.leaveSection(inner);
    expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), _kEl, reason: 'إغلاق الداخليّ لا يمسح وجهة الخارجيّ');
    expect(CompanyRoute.sectionKeyFor('/api/v2/settlements'), isNull);
    CompanyRoute.leaveSection(outer);
    expect(CompanyRoute.sectionKey, isNull);

    // الشاشات: الصرفيات لايرث لنك ثمّ «تسوية الحساب» فوقها بغلافها، ثمّ الرجوع
    await up(t);
    MergedMode.focus.value = _kEl;
    final nav = GlobalKey<NavigatorState>();
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1),
        home: (_) => Navigator(
              key: nav,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const MergedSection(prefixes: ['/api/admin/expenses', '/api/v2/expenses'], child: ExpensesScreen()),
              ),
            ));
    await settleReal(t);
    srv.asked.clear();
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => SettlementsScreen.mergedPage()));
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(srv.asked, contains('GET /api/v2/settlements/current $_kEl'), reason: 'صندوق ايرث لنك لا المفتوحة');
    expect(find.descendant(of: find.byType(SettlementsScreen), matching: find.textContaining('«ايرث لنك» للعرض هنا')), findsOneWidget,
        reason: 'شريطها وسببها فوقها');
    nav.currentState!.pop();
    await settleReal(t);
    expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), _kEl, reason: 'الصرفيات تحتها ما زالت لايرث لنك');
    await down(t);
  });

  testWidgets('٨ «مشترك جديد» في شركة ايرث لنك غير المفتوحة: نموذج ايرث لنك وطلباته (الخيارات وحال باسورد الإيداع) موجَّهةٌ لها', (t) async {
    await up(t);
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1),
        home: (_) => Builder(
              builder: (ctx) => Scaffold(
                body: Center(child: TextButton(onPressed: () => showAddSubscriberSheet(ctx), child: const Text('أضف'))),
              ),
            ));
    await settleReal(t);
    await t.tap(find.text('أضف'));
    await settleReal(t);
    await t.tap(find.byKey(const ValueKey('merged-pick-$_kEl')));
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(srv.asked, contains('GET /api/v2/el/create-options $_kEl'), reason: 'خيارات الإضافة لايرث لنك المختارة');
    expect(srv.asked, contains('GET /api/v2/el/deposit-password $_kEl'), reason: 'حال باسورد إيداعها هي لا المفتوحة');
    expect(srv.asked.where((a) => a.contains('/api/v2/el/') && a.endsWith(' -')), isEmpty, reason: '${srv.asked}');
    await down(t);
  });

  testWidgets('٩ «طلبات التفعيل» لايرث لنك غير المفتوحة: قائمتها موجَّهة للعرض — لا قبول ولا رفض، وجرس المفتوحة لا يتغيّر', (t) async {
    await up(t);
    RenewRequestsState.debugSet(null);
    MergedMode.focus.value = _kEl;
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1), home: (_) => RenewRequestsScreen.mergedPage());
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(srv.asked, contains('GET /api/v2/portal/renew-requests $_kEl'));
    expect(srv.asked.where((a) => a.contains('/api/v2/portal/renew-') && a.endsWith(' -')), isEmpty,
        reason: 'لا قراءة للمفتوحة تكتب فوق جرسها: ${srv.asked}');
    expect(RenewRequestsState.gate.value, isNull, reason: 'عدّاد الجرس للمفتوحة كما كان');
    expect(find.textContaining('مشترك ايرث'), findsWidgets);
    await t.tap(find.textContaining('مشترك ايرث').first);
    await settleReal(t);
    expect(find.byKey(const ValueKey('renew-accept')), findsNothing, reason: 'لا قبول لشركةٍ غير المفتوحة هنا');
    expect(find.byKey(const ValueKey('renew-reject')), findsNothing);
    expect(find.textContaining('«ايرث لنك» للعرض هنا — القبول والرفض'), findsOneWidget);
    await down(t);
  });

  testWidgets('١٠ «الكارتات المطلوبة» (ايرث لنك وحدها): شركة الساس «غير متاح» بلا طلب، وايرث لنك قراءتها موجَّهة', (t) async {
    await up(t);
    final screen = MergedSection(
      readOnly: true,
      prefixes: const ['/api/v2/el/prepaid-needed'],
      serves: (c) => c.provider == MergedProvider.earthlink,
      servesNote: 'هذا القسم لشركات ايرث لنك وحدها',
      lockTitle: 'الكارتات المطلوبة',
      child: const _OpenOnlyProbe(),
    );
    MergedMode.focus.value = _kOpen;
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1), home: (_) => screen);
    await settleReal(t);
    expect(t.takeException(), isNull);
    // المفتوحة صفحتها نفسها كما تعرضها «الكل» — «غير متاح» لغير المفتوحة وحدها (صورة المالك: كارتات ايرث لنك المفتوحة
    // تحت «الكل» و«غير متاح» تحت زرّها)
    expect(find.textContaining('غير متاح'), findsNothing);
    expect(find.text('probe-body'), findsOneWidget);
    expect(CompanyRoute.sectionKey, isNull);
    MergedMode.focus.value = _kEl;
    await settleReal(t);
    expect(find.text('probe-body'), findsOneWidget);
    expect(CompanyRoute.sectionKeyFor('/api/v2/el/prepaid-needed'), _kEl);
    await down(t);
  });

  testWidgets('١١ قسمٌ للساس وحده (المدراء): ايرث لنك غير المفتوحة «غير متاح» بلا سطر «للعرض هنا» فوقه؛ والمفتوحة صفحتها', (t) async {
    await up(t);
    final screen = MergedSection(
      readOnly: true,
      prefixes: const ['/api/v2/managers'],
      serves: (c) => c.provider == MergedProvider.sas4,
      servesNote: 'هذا القسم لشركات الساس وحدها',
      lockTitle: 'المدراء',
      child: const _OpenOnlyProbe(),
    );
    MergedMode.focus.value = _kEl;
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1), home: (_) => screen);
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(find.textContaining('«المدراء» غير متاح لـ«ايرث لنك»'), findsOneWidget);
    expect(find.textContaining('للعرض هنا'), findsNothing, reason: 'لا «للعرض هنا» فوق «غير متاح» (صورة المالك: الكارتات المطلوبة)');
    expect(CompanyRoute.sectionKey, isNull, reason: 'لا طلب يُوجَّه لشركةٍ لا يخدمها القسم');
    MergedMode.focus.value = _kOpen;
    await settleReal(t);
    expect(find.text('probe-body'), findsOneWidget);
    expect(CompanyRoute.sectionKey, isNull, reason: 'المفتوحة بلا توجيه');
    await down(t);
  });

  testWidgets('١٢ الموظّفون لشركةٍ للعرض: القائمة موجَّهة بلا كتالوج ولا «تعذّر تحميل كتالوج الصلاحيات»، ولا «موظف جديد»', (t) async {
    await up(t);
    const screen = MergedSection(readOnly: true, prefixes: ['/api/v2/employees'], child: EmployeesScreen());
    MergedMode.focus.value = _kEl;
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1), home: (_) => screen);
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(srv.asked, contains('GET /api/v2/employees $_kEl'));
    expect(srv.asked.where((a) => a.contains('permissions-catalog')), isEmpty, reason: 'لا محرّر للعرض ⇒ لا كتالوج');
    expect(find.textContaining('كتالوج'), findsNothing, reason: 'صورة المالك: «تعذّر تحميل كتالوج الصلاحيات»');
    expect(find.text('موظف جديد'), findsNothing);
    // «الكل» = المفتوحة: الكتالوج يُطلب لها كما كان
    srv.asked.clear();
    MergedMode.focus.value = null;
    await settleReal(t);
    expect(srv.asked.where((a) => a.startsWith('GET /api/v2/employees/permissions-catalog -')), isNotEmpty);
    await down(t);
  });

  testWidgets('١٣ بوّابة المشترك لشركةٍ للعرض: رمزها موجَّه بلا «تغيير الرمز»؛ والمفتوحة به', (t) async {
    await up(t);
    MergedMode.focus.value = _kEl;
    await pumpVisual(t, const VisualDevice('', Size(390, 1600), 1), home: (_) => PortalSettingsScreen.mergedPage());
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(srv.asked, contains('GET /api/v2/portal/settings $_kEl'));
    expect(find.text('تغيير الرمز'), findsNothing, reason: 'صورة المالك: «تغيير الرمز» ظاهرٌ لشركةٍ للعرض');
    MergedMode.focus.value = null;
    await settleReal(t);
    expect(find.text('تغيير الرمز'), findsOneWidget);
    await down(t);
  });

  testWidgets('١٤ الخصومات لشركةٍ للعرض: خصوماتها بأسماء مشتركيها هي — لا قائمة المفتوحة ولا «تطبيق الخصم»', (t) async {
    await up(t);
    const screen = MergedSection(readOnly: true, prefixes: ['/api/discounts', '/api/v2/discounts'], child: DiscountsScreen());
    MergedMode.focus.value = _kEl;
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1), home: (_) => screen);
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(srv.asked, contains('GET /api/discounts $_kEl'));
    expect(srv.asked.where((a) => a.startsWith('GET /api/v2/subscribers ') && a.endsWith(' -')), isEmpty,
        reason: 'قائمة المفتوحة لا تُقرأ تحت ايرث لنك');
    expect(find.text('مشترك ايرث'), findsOneWidget);
    expect(find.textContaining('سوبرنت خطأ'), findsNothing);
    expect(find.text('تطبيق الخصم'), findsNothing);
    await down(t);
  });

  testWidgets('١٥ التبليغات لشركةٍ للعرض: حملاتها وحالة رسائلها — لا قائمة مشتركي المفتوحة ولا إرسال', (t) async {
    await up(t);
    const screen = MergedSection(
        readOnly: true,
        prefixes: ['/api/whatsapp/broadcast', '/api/whatsapp/broadcasts', '/api/whatsapp/send-scope', '/api/v2/whatsapp'],
        child: BroadcastScreen());
    MergedMode.focus.value = _kEl;
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1), home: (_) => screen);
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(srv.asked.where((a) => a.contains('/api/v2/subscribers')), isEmpty);
    expect(find.byKey(const ValueKey('broadcast-view-campaigns')), findsOneWidget);
    expect(find.byKey(const ValueKey('broadcast-view-logs')), findsOneWidget);
    await down(t);
  });

  testWidgets('١٦ تلغرام لشركةٍ للعرض: «المرتبطون» وحدها بأسماء مشتركيها هي (لا المفتوحة)، بلا فكّ ربطٍ ولا فصل', (t) async {
    await up(t);
    srv.tgConnected = true;
    const screen = MergedSection(readOnly: true, prefixes: ['/api/telegram'], child: TelegramScreen());
    MergedMode.focus.value = _kEl;
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1), home: (_) => screen);
    await settleReal(t);
    expect(t.takeException(), isNull);
    expect(find.text('ربط مشترك'), findsNothing);
    expect(find.text('فصل البوت'), findsNothing);
    await t.tap(find.text('المرتبطون'));
    await settleReal(t);
    expect(srv.asked.where((a) => a.startsWith('GET /api/telegram/bindings/') && a.endsWith(_kEl)), isNotEmpty);
    expect(find.textContaining('مشترك ايرث'), findsWidgets, reason: 'اسم مشترك ايرث لنك نفسه');
    expect(find.textContaining('سوبرنت خطأ'), findsNothing, reason: 'لا اسم مشترك المفتوحة بنفس الرقم');
    expect(find.byIcon(LucideIcons.unlink), findsNothing);
    await down(t);
  });
}

/// شاشةٌ وهميّة لقسم «للمفتوحة وحدها»: جسمها بـ[MergedSectionBody] كالشاشات الحقيقيّة، وتعدّ مرّات إنشائها (= مرّات جلبها).
class _OpenOnlyProbe extends StatefulWidget {
  const _OpenOnlyProbe();
  static int built = 0;

  @override
  State<_OpenOnlyProbe> createState() => _OpenOnlyProbeState();
}

class _OpenOnlyProbeState extends State<_OpenOnlyProbe> {
  @override
  void initState() {
    super.initState();
    _OpenOnlyProbe.built++;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('شحن رصيد الصفحة')),
        body: MergedSectionBody(child: ListView(children: const [Text('probe-body')])),
      );
}
