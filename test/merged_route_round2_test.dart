import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/cards_api.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/core/platform/desktop_layout.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';
import 'package:rad_mysvcs/screens/network_devices/fiber/fiber_subscriber_card.dart';
import 'package:rad_mysvcs/screens/sales/sales_screen.dart';
import 'package:rad_mysvcs/screens/settlements/settlements_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/bulk_activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/bulk_pay_debt_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/pay_debt_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_table_row.dart';
import 'package:rad_mysvcs/services/fiber/fiber_store.dart';
import 'package:rad_mysvcs/services/manual_wa_prefs.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/notification_router.dart';
import 'package:rad_mysvcs/services/print_output.dart';
import 'package:rad_mysvcs/services/print_prefs.dart';
import 'package:rad_mysvcs/widgets/manual_wa_chip.dart';

import 'support/fiber_fixture.dart';
import 'visual_perm/visual_perm_harness.dart';

/// مراجعة الإصدار 179 — التحقّق العدائيّ الثاني (route2_verify.json): اختبارٌ لكلّ بند، كلٌّ يفشل على 997c62de وينجح بعد الإصلاح.
/// القاعدة كما هي: كلّ كتابةٍ على مشتركٍ في «كل الشركات» بشركته صراحةً، وما يخرج باسم شركةٍ (رسالة، فاتورة، سند، جهاز، شارة)
/// يخرج باسم شركة الشيء نفسه لا الشركة المفتوحة.
///   ١. (مانع) «تحديد الكلّ» برأس جدول الحاسبة تخطّى حارس «كل الشركات» ⇒ تسديد/تجديد/تعطيل/حذف/فصل جماعيّ للمفتوحة بأرقام
///      صفوف شركاتٍ أخرى. الآن: لا خانات تحديد في الوضع، والشيتان الجماعيّان يرفضان صفوفه، والمعترض يرفض كتابةً ضمنيّة على مشترك.
///   ٢. (كبير) «إرسال تلقائي» بعد تسديد/تجديد/تمديد مشترك شركةٍ أخرى يخرج من واتساب المفتوحة ⇒ لا يُعرض لها، والسبب مكانه.
///   ٣. (كبير) فاتورة البيع المطبوعة تلقائيّاً بعد بيعٍ في شركةٍ أخرى بتصميم المفتوحة واسمها و«أصدره» مديرها.
///   ٤. (كبير) «سند التسوية» لصندوق شركةٍ أخرى باسم المفتوحة ومديرها.
///   ٥. (كبير) صفحة مشترك شركةٍ أخرى بيوزرٍ يطابق مشتركاً في شبكة ألياف المفتوحة تعرض جهاز المفتوحة.
///   ٦. (ثانويّ) تجديد مشترك شركةٍ أخرى بكارتٍ ينقص شارة كارتات المفتوحة؛ وملخّص «انتهت اليوم» خارج الوضع يربط الغلاف بحال صفحته.
/// الأسماء لاتينيّة عمداً حيث يُقرأ الـPDF المطبوع (كلماته تُفكّ بخرائط خطّه).
const _kOpen = 'c0000000000a1';
const _kB = 'c0000000000b2';

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

Map<String, Object?> _row(int i, String user, {String debt = ''}) => {
      'idx': i,
      'username': user,
      'firstname': 'مشترك',
      'lastname': '$i',
      'profile_name': 'Gold',
      'remaining_days': 10,
      'expiration': '2026-12-01 00:00:00',
      'enabled': 1,
      'online_status': 1,
      if (debt.isNotEmpty) 'notes': debt,
    };

Map<String, Object?> _sale(int id, String item) => {
      'id': id, 'payment': 'cash', 'status': 'done', 'total': 45000, 'cost': 32000, 'profit': 13000,
      'customer': {'kind': 'walkin', 'idx': null, 'username': null, 'name': 'زبون', 'phone': null},
      'note': null, 'by': null, 'employee_id': null, 'created_at': '2026-11-09T04:05:00Z', 'voided_at': null, 'void_reason': null,
      'lines': [
        {'item_id': 7, 'name': item, 'unit': 'piece', 'qty': 1, 'unit_price': 45000, 'unit_cost': 32000, 'total': 45000, 'cost': 32000,
          'profit': 13000},
      ],
    };

Map<String, Object?> _settlement(int id) => {
      'id': id, 'kind': 'settlement', 'number': 4, 'status': 'active',
      'period_start_at': '2026-11-01T00:00:00Z', 'cut_at': '2026-11-08T10:00:00Z',
      'opening_balance': 0,
      'cash_activations': {'count': 2, 'sum': 30000},
      'debt_payments': {'count': 0, 'sum': 0},
      'cash_in': 30000,
      'expenses': {'count': 0, 'sum': 0},
      'new_debts': {'count': 0, 'sum': 0},
      'expected_amount': 30000, 'received_amount': 30000, 'carried_amount': 0,
      'collectors': [],
    };

/// خادمٌ بصدى المفتاح كالخادم الحقيقيّ، لكلّ شركةٍ بياناتها؛ وما سواه لخادم لقطات الصلاحيّات.
class _Srv implements HttpClientAdapter {
  _Srv(this.fallback);
  final HttpClientAdapter fallback;

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
    final b = key == _kB;
    // ── المشتركون: idx 1 في الشركتين لمشتركين مختلفين ──
    if (path == '/api/v2/subscribers' && m == 'GET' && o.queryParameters['page'] == null) {
      return j({
        'success': true,
        'data': b
            ? [_row(1, 'b.one', debt: '-5000'), _row(9, 'b.nine', debt: '-2500')]
            : [_row(1, 'a.one'), _row(2, 'a.two', debt: '-7000')],
      });
    }
    final sub = RegExp(r'^/api/v2/subscribers/(\d+)(/[a-z-]+)?$').firstMatch(path);
    if (sub != null) {
      final tail = sub.group(2) ?? '';
      if (m == 'GET' && tail.isEmpty) return j({'success': true, 'data': {'idx': sub.group(1)}});
      if (m == 'GET' && tail == '/activation-data') {
        return j({
          'success': true,
          'data': {
            'user_price': 46000, 'price_after_discount': 46000, 'profile_name': 'Family', 'profile_duration': '30',
            'current_balance': 0, 'manager_balance': 0,
            'activation_methods': {'credit': true, 'card': true},
            'cards': {'enabled': true, 'profile_id': 4, 'profile_name': 'Family', 'available': 2},
          },
        });
      }
      if (m == 'POST' && tail == '/pay-debt') {
        return j({
          'success': true,
          'message': 'تم التسديد',
          'wa_preview': {'phone': '9647701234567', 'message': 'تم تسديد دينك', 'intent': 'debt_payment'},
        });
      }
      if (m == 'POST' && tail == '/activate') {
        return j({
          'success': true,
          'card': {'series': '2026-52224', 'serial_tail': '4821', 'profile_name': 'Family', 'remaining': 1},
        });
      }
      if (m == 'GET') return j({'success': true, 'data': {}});
      return j({'success': true, 'message': 'تم'});
    }
    if (path == '/api/whatsapp/send-message') return j({'success': true, 'message': 'أُرسلت'});
    if (path == '/api/v2/whatsapp/contact-risk') return j({'success': true, 'data': {}});
    // ── تصميم الوصل: لكلّ شركةٍ اسم محلّها ──
    if (path == '/api/v2/receipt-settings') {
      return j({'success': true, 'data': {'shop_name': b ? 'JTDESIGN' : 'OPENDESIGN'}});
    }
    // ── المبيعات ──
    if (path == '/api/v2/sales/items' && m == 'GET') {
      return j({
        'success': true,
        'enabled': true,
        'data': [
          {
            'id': 7, 'name': b ? 'ROUTERB' : 'ROUTERA', 'code': null, 'unit': 'piece', 'unit_label': 'قطعة', 'sale_price': 45000,
            'cost_avg': 32000, 'qty': 5, 'stock_value': 160000, 'margin': 13000, 'active': true,
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
    if (path == '/api/v2/sales' && m == 'POST') return j({'success': true, 'data': _sale(30, b ? 'ROUTERB' : 'ROUTERA')});
    if (path == '/api/v2/sales/debt-status') return j({'success': true, 'data': []});
    // ── التسويات: سجلّ صندوق JTSHOP ──
    if (path == '/api/v2/settlements/current') {
      return j({
        'success': true,
        'data': {
          'started': true,
          'head': {'id': 77},
          'period': {'start_at': '2026-11-08T10:00:00Z'},
          'cut': {'head_id': 77, 'activity_id': 700, 'expense_id': 70},
          'totals': {
            'opening_balance': 0,
            'cash_activations': {'count': 0, 'amount': 0},
            'debt_payments': {'count': 0, 'amount': 0},
            'cash_in': 0,
            'expenses': {'count': 0, 'amount': 0},
            'new_debts': {'count': 0, 'amount': 0},
            'expected_amount': 0,
          },
          'collectors': [],
          'can_settle': true,
          'can_void': true,
          if (key != null) 'routed_writes': true,
        },
      });
    }
    if (path == '/api/v2/settlements/movements') return j({'success': true, 'data': {'items': [], 'has_more': false}});
    if (path == '/api/v2/settlements' && m == 'GET') {
      return j({'success': true, 'data': {'items': b ? [_settlement(77)] : [], 'total': b ? 1 : 0}});
    }
    if (path == '/api/v2/settlements/77' && m == 'GET') return j({'success': true, 'data': _settlement(77)});
    final r = await fallback.fetch(o, rs, cf);
    if (key == null) return r;
    return ResponseBody(r.stream, r.statusCode, headers: {...r.headers, 'x-company-key': [key]});
  }

  @override
  void close({bool force = false}) {}
}

/// الطابعة: ما يُرسل إليها يُحفظ (نافذة الطباعة على الحاسبة — PhoneOutput خارج الهاتف).
class _Printer implements PrintBackend {
  final docs = <PrintDoc>[];

  @override
  Future<bool> layout(PrintDoc doc) async {
    docs.add(doc);
    return true;
  }

  @override
  Future<bool> direct(Printer printer, PrintDoc doc) async {
    docs.add(doc);
    return true;
  }

  @override
  Future<List<Printer>> printers() async => const [];
}

/// كلمات PDF مبنيٍّ بحزمة pdf (خطوط TTF): كلّ `[<hex>]TJ` كلمةٌ رموزها ٤ خانات تُفكّ بخريطة ToUnicode لخطّها — ولا يُعرف هنا
/// خطّ كلّ كلمة فتُفكّ بكلّ الخرائط (فكٌّ بغير خريطتها حروفٌ لا تطابق اسماً).
Set<String> _pdfWords(Uint8List bytes) {
  final raw = latin1.decode(bytes);
  final streams = <String>[];
  for (final m in RegExp('stream\r?\n').allMatches(raw)) {
    if (m.start >= 3 && raw.substring(m.start - 3, m.start) == 'end') continue;
    final at = raw.lastIndexOf('/Length ', m.start);
    if (at < 0) continue;
    final n = int.tryParse(RegExp(r'\d+').matchAsPrefix(raw, at + 8)?.group(0) ?? '');
    if (n == null || m.end + n > bytes.length) continue;
    final data = bytes.sublist(m.end, m.end + n);
    List<int> body;
    try {
      body = zlib.decode(data);
    } catch (_) {
      body = data;
    }
    streams.add(latin1.decode(body));
  }
  final maps = <Map<int, int>>[
    for (final s in streams.where((s) => s.contains('beginbfchar')))
      {
        for (final p in RegExp(r'<([0-9A-Fa-f]{4})> <([0-9A-Fa-f]+)>').allMatches(s))
          int.parse(p.group(1)!, radix: 16): int.parse(p.group(2)!, radix: 16),
      },
  ];
  final words = <String>{};
  for (final s in streams) {
    for (final w in RegExp(r'\[<([0-9A-Fa-f]*)>\]TJ').allMatches(s)) {
      final hex = w.group(1)!;
      for (final map in maps) {
        final runes = <int>[];
        for (var i = 0; i + 4 <= hex.length; i += 4) {
          final r = map[int.parse(hex.substring(i, i + 4), radix: 16)];
          if (r == null) break;
          runes.add(r);
        }
        if (runes.length * 4 == hex.length) words.add(String.fromCharCodes(runes));
      }
    }
  }
  return words;
}

Map<String, Object?> _companies() => {
      'routing': true,
      'writes': true,
      'companies': [
        // المفتوحة: مدير جلسة الحزمة (visualSetUp ⇒ supernet:12)
        {'key': _kOpen, 'code': 'supernet', 'username': 'u0', 'name': 'OPENCO', 'status': 'ok', 'admin_id': 'supernet:12', 'ns': 'a', 'currency': 'IQD', 'color_index': 0},
        {'key': _kB, 'code': 'jt', 'username': 'jtboss', 'name': 'JTSHOP', 'status': 'ok', 'admin_id': 'jt:6836', 'ns': 'j', 'currency': 'IQD', 'color_index': 1},
      ],
    };

Finder _private(String type) => find.byWidgetPredicate((w) => w.runtimeType.toString() == type);

void main() {
  setUpAll(() async {
    await visualSetUpAll();
    // نقرةٌ تقع على غير هدفها (إشعارٌ عائمٌ فوقه) تُنجح الاختبار زوراً — فلتكن فشلاً
    WidgetController.hitTestWarningShouldBeFatal = true;
    // خطّ الطباعة يُحمَّل مرّةً ويُخبّأ وعده: يُحمَّل هنا خارج زمن الاختبار الوهميّ، وإلّا علق انتظاره في الاختبار التالي
    // (وعدٌ مكتملٌ في منطقة اختبارٍ انتهى)
    await PdfFonts.theme();
  });
  late _Srv srv;

  Future<void> up(WidgetTester t, {bool merged = true}) async {
    final visual = await visualSetUp(s1bSasOwner);
    // هويّة الجلسة المفتوحة على الوصل والسند (اسم العرض ويوزر المدير) — لاتينيّةٌ لتُقرأ من الـPDF
    await const FlutterSecureStorage().write(key: 'auth.display_name', value: 'OPENSHOP');
    await const FlutterSecureStorage().write(key: 'auth.admin_username', value: 'openadmin');
    srv = _Srv(visual);
    ApiClient.dio.httpClientAdapter = srv;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    ReceiptSettingsApi.clearCache();
    MergedMode.reset();
    MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
    if (merged) expect(await t.runAsync(() => MergedMode.enter()), isTrue);
  }

  Future<void> down(WidgetTester t, {int seconds = 3}) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(Duration(seconds: seconds));
    MergedMode.reset();
    await visualTearDown();
  }

  Future<void> settleReal(WidgetTester t, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// صفحةٌ فارغة يُفتح منها الشيت (كصفحة المشترك).
  Future<BuildContext> host(WidgetTester t) async {
    late BuildContext ctx;
    await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1),
        home: (_) => Scaffold(body: Builder(builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            })));
    await settleReal(t);
    return ctx;
  }

  _Printer printer() {
    final p = _Printer();
    final before = PrintOutput.backend;
    PrintOutput.backend = p;
    addTearDown(() => PrintOutput.backend = before);
    return p;
  }

  Future<void> printed(WidgetTester t, _Printer p) async {
    for (var i = 0; i < 60 && p.docs.isEmpty; i++) {
      await settleReal(t, rounds: 1);
    }
    expect(p.docs, hasLength(1), reason: 'طُبع: ${srv.asked}');
  }

  /// الكتابات (لا GET ولا قراءةٌ بـPOST) على ما يطابق [where].
  List<String> writes(bool Function(String path) where) => srv.asked.where((a) {
        final path = a.split(' ')[1];
        return !a.startsWith('GET ') && !CompanyRoute.readsByPost.contains(path) && where(path);
      }).toList();

  testWidgets('١ (مانع): جدول الحاسبة في «كل الشركات» — لا «تحديد الكلّ» برأسه ولا خانات صفوف: لا عمليّة جماعيّة بأرقام صفوف '
      'شركتين', (t) async {
    await up(t);
    try {
      final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
      await pumpVisual(t, const VisualDevice('_desk', Size(1440, 900), 1),
          home: (_) => DesktopScope(child: SubscribersScreen(filterCmd: cmd)));
      await settle(t, seconds: 3);
      final header = find.byType(SubscriberTableHeader);
      expect(header, findsOneWidget, reason: 'جدول الحاسبة');
      expect(find.text('b.nine'), findsWidgets, reason: 'صفوف JTSHOP في الجدول');
      expect(find.text('a.two'), findsWidgets, reason: 'وصفوف المفتوحة');
      // «تحديد الكلّ» برأس الجدول ⇒ (قبل الإصلاح) تحديدٌ لصفوف الشركتين وشريط العمليّات الجماعيّة: تسديد/تجديد/تعطيل/حذف/فصل
      // تذهب كلّها للمفتوحة بأرقامها
      final selectAll = find.descendant(of: header, matching: _private('_CheckBox'));
      if (selectAll.evaluate().isNotEmpty) {
        await t.tap(selectAll.first);
        await settleReal(t);
      }
      expect(_private('_BulkActionBar'), findsNothing,
          reason: '«تحديد الكلّ» حدّد صفوف الشركتين للعمليّات الجماعيّة (أرقامها تذهب للمفتوحة)');
      expect(selectAll, findsNothing, reason: 'لا خانة «تحديد الكلّ» في «كل الشركات»');
      expect(find.descendant(of: find.byType(SubscriberTableRow), matching: _private('_CheckBox')), findsNothing,
          reason: 'ولا خانات صفوف');
      expect(writes((p) => p.startsWith('/api/v2/subscribers')), isEmpty);
      expect(t.takeException(), isNull);
    } finally {
      await down(t, seconds: 6);
    }
  });

  testWidgets('١ (مانع) — تحت الجدول: الشيت الجماعيّ يرفض صفوف «كل الشركات»، والمعترض يرفض كتابةً ضمنيّة على مشترك؛ والصريحة '
      'تمرّ بشركتها، وخارج الوضع كما كان', (t) async {
    await up(t);
    try {
      final ctx = await host(t);
      final rows = [
        Subscriber(idx: '2', username: 'a.two', firstname: 'ألف', lastname: 'اثنان', notes: '-7000', companyKey: _kOpen),
        Subscriber(idx: '9', username: 'b.nine', firstname: 'باء', lastname: 'تسعة', notes: '-2500', companyKey: _kB),
      ];
      srv.asked.clear();
      final f = showBulkPayDebtSheet(ctx, subs: rows);
      await settleReal(t);
      expect(_private('_BulkPayDebtSheet'), findsNothing, reason: 'تسديدٌ جماعيّ لصفوف شركتين يذهب للمفتوحة بأرقامها');
      expect(find.textContaining('العمليّات الجماعيّة لشركةٍ واحدة'), findsOneWidget);
      expect(await t.runAsync(() => f), isFalse);
      final g = showBulkActivateSheet(ctx, subs: rows);
      await settleReal(t);
      expect(_private('_BulkActivateSheet'), findsNothing, reason: 'تجديدٌ جماعيّ لصفوف شركتين يقرأ ويفعّل للمفتوحة بأرقامها');
      expect(await t.runAsync(() => g), isNull);

      // المعترض: كتابةٌ بلا شركةٍ صريحة على مسار مشترك في «كل الشركات» لا تصل الخادم (لا تُعرف شركة رقم الصفّ)
      final pay = await t.runAsync(() => SubscribersApi.payDebt(idx: '9', amount: 2500));
      expect(pay!.ok, isFalse);
      expect(pay.message, contains('لم يُنفَّذ شيء'));
      expect(await t.runAsync(() => SubscribersApi.toggle('9', enable: false)), isFalse);
      expect(writes((p) => p.startsWith('/api/v2/subscribers')), isEmpty, reason: '${srv.asked}');
      // والقراءات بـPOST على مسار المشترك قراءةٌ تصل (بحث الحساب الكبير، دفعة إعدادات الأجهزة)
      await t.runAsync(() => BigSubscribersApi.lookup(usernames: const ['b.nine']));
      await t.runAsync(() => ApiClient.dio.post<Object?>('/api/v2/subscribers/device-batch', data: {'usernames': const ['b.nine']}));
      expect(srv.asked, containsAll(['POST /api/v2/subscribers/lookup -', 'POST /api/v2/subscribers/device-batch -']));
      srv.asked.clear();

      // الصريحة تمرّ: صفّ JTSHOP بمفتاحه، وصفٌّ بلا مفتاح للمفتوحة صراحةً — والقراءة بـPOST (بحث الحساب الكبير) قراءة
      await t.runAsync(() => MergedOps.write(rows[1], () => SubscribersApi.payDebt(idx: '9', amount: 2500, skipAutoWa: true)));
      await t.runAsync(() => MergedOps.write(Subscriber(idx: '2', username: 'a.two', firstname: 'ألف', lastname: 'اثنان'),
          () => SubscribersApi.payDebt(idx: '2', amount: 1000, skipAutoWa: true)));
      expect(writes((p) => p.startsWith('/api/v2/subscribers')),
          ['POST /api/v2/subscribers/9/pay-debt $_kB', 'POST /api/v2/subscribers/2/pay-debt -']);

      // خارج «كل الشركات»: الكتابة الضمنيّة كما كانت
      MergedMode.reset();
      srv.asked.clear();
      expect(await t.runAsync(() => SubscribersApi.toggle('2', enable: false)), isTrue);
      expect(srv.asked, ['POST /api/v2/subscribers/2/toggle-enabled -']);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  Future<void> payWithPreview(WidgetTester t, BuildContext ctx, Subscriber sub) async {
    unawaited(showPayDebtSheet(ctx, sub));
    await settleReal(t);
    await t.tap(find.text('كامل الدين'));
    await t.pump();
    await t.tap(find.text('تسديد الآن'));
    await settleReal(t, rounds: 10);
    expect(find.text('تأكيد التسديد'), findsOneWidget, reason: 'معاينة الرسالة بعد التسديد: ${srv.asked}');
    // إشعار «تم التسديد» العائم فوق المبدِّل يذهب أوّلاً
    await t.pump(const Duration(seconds: 6));
    await settleReal(t, rounds: 2);
  }

  testWidgets('٢ (كبير): «إرسال تلقائي» بعد تسديد دين مشترك JTSHOP لا يخرج من واتساب المفتوحة — «افتح واتسابي» وحده وسببه؛ '
      'وصفّ المفتوحة نفسها كما كان', (t) async {
    await up(t);
    ManualWaPrefs.enabled.value = true;
    addTearDown(() => ManualWaPrefs.enabled.value = false);
    try {
      final ctx = await host(t);
      final b = Subscriber(
          idx: '9', username: 'b.nine', firstname: 'باء', lastname: 'تسعة', phone: '07701234567', notes: '-2500', companyKey: _kB);
      srv.asked.clear();
      await payWithPreview(t, ctx, b);
      expect(srv.asked, contains('POST /api/v2/subscribers/9/pay-debt $_kB'));
      final reason = find.byKey(const ValueKey('wa-auto-blocked'));
      final reasonShown = reason.evaluate().isNotEmpty;
      // المبدِّل إن عُرض ⇒ «تلقائي» ثمّ «إرسال تلقائي» (ما كان المدير يستطيعه)
      if (find.byType(ManualWaChip).evaluate().isNotEmpty) {
        await t.tap(find.byType(ManualWaChip));
        await t.pump();
      }
      if (find.text('إرسال تلقائي').evaluate().isNotEmpty) {
        await t.tap(find.text('إرسال تلقائي'));
        await settleReal(t);
      }
      expect(srv.asked.where((a) => a.contains('/api/whatsapp/send-message')), isEmpty,
          reason: 'رسالة مشترك JTSHOP خرجت من واتساب المفتوحة: ${srv.asked}');
      expect(reasonShown, isTrue, reason: 'السبب مكان المبدِّل');
      expect(find.textContaining('لمشترك «JTSHOP» افتح واتسابك'), findsOneWidget);
      expect(find.text('افتح واتسابي'), findsOneWidget);
      Navigator.of(t.element(find.text('افتح واتسابي'))).pop();
      await settleReal(t);

      // صفّ المفتوحة نفسها (بمفتاحها في الوضع): الإرسال التلقائيّ من واتسابها كما كان
      final a = Subscriber(
          idx: '2', username: 'a.two', firstname: 'ألف', lastname: 'اثنان', phone: '07701234567', notes: '-7000', companyKey: _kOpen);
      srv.asked.clear();
      await payWithPreview(t, ctx, a);
      expect(reason, findsNothing);
      await t.tap(find.byType(ManualWaChip));
      await t.pump();
      await t.tap(find.text('إرسال تلقائي'));
      await settleReal(t);
      expect(srv.asked, contains('POST /api/whatsapp/send-message -'));
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('٣ (كبير): فاتورة البيع المطبوعة تلقائيّاً بعد بيعٍ في JTSHOP بتصميمها و«أصدره» مديرها — لا المفتوحة', (t) async {
    await up(t);
    PrintPrefs.saleInvoice.value = true;
    addTearDown(() => PrintPrefs.saleInvoice.value = false);
    final p = printer();
    try {
      await pumpVisual(t, const VisualDevice('', Size(390, 1600), 1), home: (_) => const SalesScreen());
      await settleReal(t);
      await t.tap(find.byKey(const ValueKey('sales-co-$_kB')));
      await settleReal(t);
      expect(srv.asked, contains('GET /api/v2/sales/items $_kB'));
      await t.tap(find.byType(FloatingActionButton));
      await settleReal(t);
      await t.tap(find.text('sales.pick_item'.tr()).last);
      await settleReal(t);
      // صفّ المادّة: اسمها معزولٌ باتّجاهه (FSI…PDI)
      await t.tap(find.textContaining('ROUTERB').last);
      await settleReal(t);
      srv.asked.clear();
      await t.tap(find.textContaining('بيع نقداً').last);
      await printed(t, p);
      expect(srv.asked, contains('POST /api/v2/sales $_kB'));
      final words = _pdfWords(p.docs.single.bytes);
      expect(words, contains('ROUTERB'), reason: 'الفاتورة نفسها مقروءة: $words');
      expect(words, contains('JTDESIGN'), reason: 'تصميم وصل JTSHOP (اسم محلّها): $words');
      expect(words, isNot(contains('OPENDESIGN')));
      expect(words, contains('jtboss'), reason: '«أصدره» مدير JTSHOP');
      expect(words, isNot(contains('openadmin')));
      expect(srv.asked, contains('GET /api/v2/receipt-settings $_kB'));
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('٤ (كبير): «سند التسوية» لصندوق JTSHOP باسمها ومديرها — لا اسم المفتوحة ومديرها', (t) async {
    await up(t);
    final p = printer();
    try {
      MergedMode.focus.value = _kB;
      await pumpVisual(t, const VisualDevice('', Size(390, 2400), 1), home: (_) => SettlementsScreen.mergedPage());
      await settleReal(t);
      expect(srv.asked, contains('GET /api/v2/settlements $_kB'));
      final tile = _private('_HistoryTile');
      expect(tile, findsOneWidget);
      await t.ensureVisible(tile);
      await t.pump();
      await t.tap(tile);
      await settleReal(t);
      expect(srv.asked, contains('GET /api/v2/settlements/77 $_kB'));
      await t.tap(find.text('settle.print'.tr()).last);
      await printed(t, p);
      final words = _pdfWords(p.docs.single.bytes);
      expect(words, contains('JTSHOP'), reason: 'اسم شركة الصندوق: $words');
      expect(words, contains('jtboss'), reason: 'مديرها');
      expect(words, isNot(contains('OPENSHOP')));
      expect(words, isNot(contains('openadmin')));
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('٥ (كبير): صفحة مشترك JTSHOP بيوزرٍ يطابق مشتركاً في شبكة ألياف المفتوحة لا تعرض جهاز المفتوحة؛ وصفّ المفتوحة '
      'كما كان', (t) async {
    await up(t);
    FiberStore.debugSet(fiberTestLayout(), admin: 'supernet:12');
    FiberSubscriberCard.devices = () async => const [];
    addTearDown(() {
      FiberStore.reset();
      FiberSubscriberCard.debugReset();
    });
    try {
      var n = 0;
      Future<void> card(Subscriber s) async {
        await pumpVisual(t, const VisualDevice('', Size(390, 900), 1),
            home: (_) => Scaffold(body: ListView(children: [FiberSubscriberCard(key: ValueKey(n++), sub: s)])));
        await settleReal(t);
      }

      Subscriber sub2(String? key) =>
          Subscriber(username: 'sub2', firstname: 'حيدر', lastname: 'علي', phone: '07801112233', companyKey: key);
      await card(sub2(_kB));
      expect(find.text('جهاز الألياف'), findsNothing, reason: 'جهاز المفتوحة (حالته وضوؤه وصندوقه) لمشترك JTSHOP');
      await card(sub2(_kOpen));
      expect(find.text('جهاز الألياف'), findsOneWidget, reason: 'صفّ المفتوحة في «كل الشركات»');
      await card(sub2(null));
      expect(find.text('جهاز الألياف'), findsOneWidget, reason: 'بلا مفتاح = المفتوحة');
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('٦ (ثانويّ): تجديد مشترك JTSHOP بكارتٍ من مخزونها لا ينقص شارة كارتات المفتوحة؛ وصفّ المفتوحة ينقصها', (t) async {
    await up(t);
    try {
      final ctx = await host(t);
      Future<void> renewByCard(Subscriber s) async {
        unawaited(showActivateSheet(ctx, s));
        await settleReal(t);
        await t.tap(find.text('كارت (2)'));
        await settleReal(t);
        await t.tap(find.text('تجديد بكارت'));
        await settleReal(t, rounds: 10);
        expect(srv.asked, contains('POST /api/v2/subscribers/${s.idx}/activate ${s.companyKey}'));
        await t.pump(const Duration(seconds: 6));
        await settleReal(t);
      }

      CardsState.set(const CardsBadge(enabled: true, remaining: 3));
      await renewByCard(Subscriber(
          idx: '9', username: 'b.nine', firstname: 'باء', lastname: 'تسعة', profileId: 4, profileName: 'Family', companyKey: _kB));
      expect(CardsState.badge.value?.remaining, 3, reason: 'كارت JTSHOP من مخزونها — شارة المفتوحة كما هي');
      await renewByCard(Subscriber(
          idx: '2', username: 'a.two', firstname: 'ألف', lastname: 'اثنان', profileId: 4, profileName: 'Family', companyKey: _kOpen));
      expect(CardsState.badge.value?.remaining, 2, reason: 'كارت المفتوحة ينقص شارتها');
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('٦ (ثانويّ): ملخّص «انتهت اليوم» خارج «كل الشركات» لا يربط الغلاف بحال صفحته — لا يُعاد بناؤه مع كلّ صفحةٍ فوقه',
      (t) async {
    await up(t, merged: false);
    final nav = GlobalKey<NavigatorState>();
    try {
      await pumpVisual(t, const VisualDevice('', Size(390, 900), 1), navigatorKey: nav, home: (_) => const MainShell());
      await settle(t, seconds: 3);
      Future<int> rebuildsAroundPage() async {
        var n = 0;
        debugOnRebuildDirtyWidget = (e, _) {
          if (e.widget is MainShell) n++;
        };
        try {
          nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('page-above'))));
          await settleReal(t);
          nav.currentState!.pop();
          await settleReal(t);
        } finally {
          debugOnRebuildDirtyWidget = null;
        }
        return n;
      }

      final before = await rebuildsAroundPage();
      NotificationRouter.onDestination?.call(NotificationDestination.subscribersExpired);
      await settleReal(t);
      final after = await rebuildsAroundPage();
      expect(after, before, reason: 'الغلاف صار تابعاً لحال صفحته (ModalRoute.of) — يُعاد بناؤه مع كلّ صفحةٍ تُفتح فوقه أو تُغلق');
      expect(MergedMode.active.value, isFalse);
      expect(t.takeException(), isNull);
    } finally {
      await down(t, seconds: 6);
    }
  });
}
