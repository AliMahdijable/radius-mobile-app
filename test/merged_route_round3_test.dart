import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/login_screen.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/notification_router.dart';
import 'package:rad_mysvcs/services/print_output.dart';
import 'package:rad_mysvcs/services/receipt_service.dart';

import 'emp_merged/emp_merged_fixture.dart' as emp;
import 'visual_perm/visual_perm_harness.dart';

/// مراجعة الإصدار 179 — التحقّق الثالث (route3_verify.json): اختبارٌ لكلّ بند، كلٌّ يفشل على ea7cb569 وينجح بعد الإصلاح.
///   ١. (كبير) «كشف حساب» مشترك شركةٍ أخرى (من «المزيد» ومن الأمر الصوتيّ) كان يُطلب من الشركة المفتوحة ويُصدَّر تحت اسمه.
///   ٢. (كبير) صفحة مشتركٍ من شركةٍ كبيرة (٥٠٠٠+) في «كل الشركات» لا تتحدّث بعد تسديد ⇒ الدين القديم يدعو لدفعةٍ ثانية.
///   ٣. (ثانويّ) صفحة المشترك وشيتات ماله لا تسمّي شركته.
///   ٤. (ثانويّ) «كل الصفحات» للموظّف: «أصدره» على الوصل يوزر مدير الصفحة لا الموظّف.
///   ٥. (ثانويّ) دخول البصمة من «شركاتي» يُبقي «شركاتي» تحت الغلاف ⇒ ملخّص «انتهت اليوم» لا يختار المفتوحة في الشريط.
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
      if (debt.isNotEmpty) 'notes': debt,
    };

/// خادمٌ بصدى المفتاح كالخادم الحقيقيّ، لكلّ شركةٍ بياناتها؛ وما سواه لخادم لقطات الصلاحيّات.
class _Srv implements HttpClientAdapter {
  _Srv(this.fallback);
  final HttpClientAdapter fallback;

  /// «METHOD path key» لكلّ طلب، و`?q=` لصفحات الكبير.
  final asked = <String>[];

  /// الشركة الأخرى كبيرة (٨٩ ألفاً — لا قائمة كاملة لها).
  bool bigB = false;

  /// دين مشترك الكبير الحيّ (بعد التسديد يتغيّر).
  String bigDebt = '-30000';

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    final m = o.method.toUpperCase();
    final q = o.queryParameters['q'];
    asked.add('$m $path ${key ?? '-'}${q == null ? '' : ' q=$q'}');
    final h = key == null ? const <String, List<String>>{} : {'x-company-key': [key]};
    ResponseBody j(Object body) => _json(200, body, headers: h);
    final b = key == _kB;
    if (path == '/api/v2/subscribers' && m == 'GET') {
      if (o.queryParameters['page'] != null) {
        if (b && bigB) {
          if (q == null) return j({'success': true, 'paged': true, 'total': 89000, 'last_page': 1780, 'data': []});
          return j({'success': true, 'paged': true, 'total': 1, 'last_page': 1, 'data': [_row(9, 'b.big', debt: bigDebt)]});
        }
        return j({'success': true, 'paged': true, 'total': 2});
      }
      return j({'success': true, 'data': b ? [_row(9, 'b.nine', debt: '-2500')] : [_row(2, 'a.two', debt: '-7000')]});
    }
    final sub = RegExp(r'^/api/v2/subscribers/(\d+)(/[a-z-]+)?$').firstMatch(path);
    if (sub != null) {
      final tail = sub.group(2) ?? '';
      if (m == 'GET' && tail.isEmpty) return j({'success': true, 'data': {'idx': sub.group(1)}});
      if (m == 'POST' && tail == '/pay-debt') {
        if (b && bigB) bigDebt = '-5000';
        return j({'success': true, 'message': 'تم التسديد'});
      }
    }
    // كشف الحساب: لكلّ شركةٍ حركاتها (المفتوحة بلا حركات لهذا اليوزر — كالخادم: كشفٌ فارغ ناجح)
    if (path == '/api/reports/account-statement') {
      return j({
        'success': true,
        'data': {
          'subscriber': {'username': o.queryParameters['username']},
          'transactions': b
              ? [
                  {'id': 1, 'action_type': 'DEBT_PAY', 'amount': 2500, 'description': 'تسديد دين باء', 'admin_name': 'jtboss',
                    'created_at': '2026-11-08 10:00:00', 'balance_after': 0},
                ]
              : [],
          'summary': {'totalTransactions': b ? 1 : 0, 'totalDebt': 0, 'totalPayments': b ? 2500 : 0, 'totalActivations': 0},
        },
      });
    }
    if (path == '/api/v2/receipt-settings') return j({'success': true, 'data': {}});
    final r = await fallback.fetch(o, rs, cf);
    if (key == null) return r;
    return ResponseBody(r.stream, r.statusCode, headers: {...r.headers, 'x-company-key': [key]});
  }

  @override
  void close({bool force = false}) {}
}

/// الطابعة: ما يُرسل إليها يُحفظ.
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

/// كلمات PDF مبنيٍّ بحزمة pdf (خطوط TTF): كلّ `[<hex>]TJ` كلمةٌ تُفكّ بخرائط ToUnicode لخطوطه.
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
        // المفتوحة: مدير جلسة الحزمة (visualSetUp ⇒ supernet:12)، واسمها كاسم الجلسة («شركاتي»)
        {'key': _kOpen, 'code': 'supernet', 'username': 'u0', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': 'supernet:12', 'ns': 'a', 'currency': 'IQD', 'color_index': 0},
        {'key': _kB, 'code': 'jt', 'username': 'jtboss', 'name': 'JTSHOP', 'status': 'ok', 'admin_id': 'jt:6836', 'ns': 'j', 'currency': 'IQD', 'color_index': 1},
      ],
    };

void main() {
  setUpAll(() async {
    await visualSetUpAll();
    WidgetController.hitTestWarningShouldBeFatal = true;
    // خطّ الطباعة يُحمَّل خارج زمن الاختبار الوهميّ (وعده المخبّأ لا يعلق في اختبارٍ تالٍ)
    await PdfFonts.theme();
  });
  late _Srv srv;

  Future<void> up(WidgetTester t) async {
    final visual = await visualSetUp(s1bSasOwner);
    srv = _Srv(visual);
    ApiClient.dio.httpClientAdapter = srv;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    ReceiptSettingsApi.clearCache();
    MergedMode.reset();
    MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
    expect(await t.runAsync(() => MergedMode.enter()), isTrue);
  }

  Future<void> down(WidgetTester t, {int seconds = 6}) async {
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

  Subscriber bRow({String user = 'b.nine', String debt = '-2500'}) =>
      Subscriber(idx: '9', username: user, firstname: 'باء', lastname: 'تسعة', phone: '07701234567', notes: debt, companyKey: _kB);

  List<String> statementAsks() => srv.asked.where((a) => a.split(' ')[1] == '/api/reports/account-statement').toList();

  testWidgets('١ (كبير): «كشف حساب» مشترك JTSHOP من «المزيد» ومن الأمر الصوتيّ — كلّ طلبٍ لشركته، وحركاتها تحت اسمه', (t) async {
    await up(t);
    try {
      // «المزيد» ⇒ «كشف الحساب»
      await pumpVisual(t, phone, home: (_) => SubscriberDetailScreen(sub: bRow()));
      await settle(t, seconds: 2);
      srv.asked.clear();
      await t.tap(find.text('subscribers.more_actions'.tr()).first);
      await settleReal(t);
      final tile = find.text('subscribers.account_statement'.tr()).last;
      await t.ensureVisible(tile);
      await t.pump();
      await t.tap(tile);
      await settleReal(t);
      expect(statementAsks(), isNotEmpty, reason: 'الكشف فُتح: ${srv.asked}');
      expect(statementAsks().every((a) => a.endsWith(' $_kB')), isTrue,
          reason: 'كشف مشترك JTSHOP من الشركة المفتوحة: ${statementAsks()}');
      expect(find.textContaining('تسديد دين باء'), findsWidgets, reason: 'حركات JTSHOP تحت اسمه');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));

      // الأمر الصوتيّ «كشف حساب فلان» (فتحٌ تلقائيّ)
      srv.asked.clear();
      await pumpVisual(t, phone, home: (_) => SubscriberDetailScreen(sub: bRow(), autoAction: SubscriberAutoAction.statement));
      await settleReal(t, rounds: 10);
      expect(statementAsks(), isNotEmpty, reason: 'الكشف فُتح تلقائيّاً: ${srv.asked}');
      expect(statementAsks().every((a) => a.endsWith(' $_kB')), isTrue, reason: '${statementAsks()}');
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('٢ (كبير): صفحة مشتركٍ من شركةٍ كبيرة (٥٠٠٠+) تتحدّث بعد التسديد كالعاديّة — الدين الجديد لا القديم', (t) async {
    await up(t);
    srv.bigB = true;
    try {
      await pumpVisual(t, phone, home: (_) => SubscriberDetailScreen(sub: bRow(user: 'b.big', debt: '-30000')));
      await settle(t, seconds: 2);
      expect(find.text('30,000 د.ع'), findsWidgets, reason: 'الدين قبل التسديد');
      await t.tap(find.text('تسديد').first);
      await settleReal(t);
      await t.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).first, '25000');
      await t.pump();
      srv.asked.clear();
      await t.tap(find.text('تسديد الآن'));
      await settleReal(t, rounds: 12);
      expect(srv.asked, contains('POST /api/v2/subscribers/9/pay-debt $_kB'));
      expect(find.text('30,000 د.ع'), findsNothing, reason: 'الدين القديم باقٍ بعد التسديد — يدعو لدفعةٍ ثانية: ${srv.asked}');
      expect(find.text('5,000 د.ع'), findsWidgets, reason: 'الدين الحيّ بعد التسديد');
      expect(srv.asked, contains('GET /api/v2/subscribers $_kB q=b.big'), reason: 'صفّه من ساس شركته بيوزره: ${srv.asked}');
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('٣ (ثانويّ): صفحة مشترك JTSHOP وشيت تسديده يسمّيان شركته؛ وصفٌّ بلا مفتاح يسمّي المفتوحة', (t) async {
    await up(t);
    try {
      await pumpVisual(t, phone, home: (_) => SubscriberDetailScreen(sub: bRow()));
      await settle(t, seconds: 2);
      expect(find.text('JTSHOP'), findsWidgets, reason: 'رأس الصفحة يسمّي شركته');
      await t.tap(find.text('تسديد').first);
      await settleReal(t);
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.textContaining('«JTSHOP»')), findsOneWidget,
          reason: 'شيت التسديد يسمّي الشركة التي يُكتب لها المال');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));

      // صفٌّ بلا مفتاح (من إشعارٍ أو الجرس) ⇒ المفتوحة
      await pumpVisual(t, phone,
          home: (_) => SubscriberDetailScreen(
              sub: Subscriber(idx: '2', username: 'a.two', firstname: 'ألف', lastname: 'اثنان', notes: '-7000')));
      await settle(t, seconds: 2);
      expect(find.text('سوبرنت'), findsWidgets, reason: 'رأس الصفحة يسمّي المفتوحة');
      await t.tap(find.text('تسديد').first);
      await settleReal(t);
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.textContaining('«سوبرنت»')), findsOneWidget);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('٤ (ثانويّ): «كل الصفحات» للموظّف — «أصدره» على وصل مشتركٍ (وفاتورة البيع) هو الموظّف لا يوزر مدير الصفحة', (t) async {
    await emp.empUp();
    await const FlutterSecureStorage().write(key: 'auth.display_name', value: 'EMPNAME');
    final p = _Printer();
    final before = PrintOutput.backend;
    PrintOutput.backend = p;
    addTearDown(() => PrintOutput.backend = before);
    try {
      expect(await t.runAsync(() => MergedMode.enter()), isTrue);
      expect(MergedMode.employeeSession, isTrue);
      for (final key in [emp.kA, emp.kB]) {
        final id = await t.runAsync(() => ReceiptService.identityFor(key));
        expect(id!.issuer, 'EMPNAME', reason: '«أصدره» لفاتورة البيع في ${MergedMode.companyOf(key)?.name}');
        expect(id.shop, MergedMode.companyOf(key)!.name, reason: 'اسم الصفحة على الوصل');
      }
      final sub = Subscriber(idx: '501', username: 'pay.user', firstname: 'Pay', lastname: 'User', notes: '-5000', companyKey: emp.kA);
      final r = await t.runAsync(() => ReceiptService.printDebtPayment(sub: sub, paid: 5000));
      expect(r!.ok, isTrue, reason: '${r.outcome}');
      final words = _pdfWords(p.docs.single.bytes);
      expect(words, contains('EMPNAME'), reason: '«أصدره» الموظّف: $words');
      expect(words, isNot(contains('admin@alef')), reason: 'لا يوزر مدير الصفحة');
    } finally {
      await emp.empDown();
    }
  });

  testWidgets('٥ (ثانويّ): دخول البصمة من «شركاتي» ⇒ الغلاف وحده في الجذر — ملخّص «انتهت اليوم» يختار المفتوحة في الشريط', (t) async {
    await up(t);
    // البصمة تنجح (منصّة local_auth الافتراضيّة على قناتها)
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/local_auth'), (call) async => call.method == 'authenticate' ? true : false);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/local_auth'), null));
    final nav = GlobalKey<NavigatorState>();
    try {
      // «شركاتي» أوّل الجذر، ومنها شاشة الدخول (fromCompanies)
      await pumpVisual(t, const VisualDevice('', Size(390, 900), 1),
          navigatorKey: nav, home: (_) => const Scaffold(body: Center(child: Text('companies-root'))));
      await settleReal(t);
      unawaited(nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const LoginScreen(fromCompanies: true))));
      await settle(t, seconds: 2);
      final finger = find.byIcon(Icons.fingerprint_rounded);
      await t.ensureVisible(finger);
      await t.pump();
      await t.tap(finger);
      await settle(t, seconds: 3);
      expect(find.byType(MainShell), findsOneWidget);
      // اختار شركةً أخرى في الشريط، ثمّ إشعار «انتهت اليوم» للمفتوحة ⇒ تبويب المشتركين على المفتوحة
      MergedMode.focus.value = _kB;
      await settleReal(t);
      NotificationRouter.onDestination?.call(NotificationDestination.subscribersExpired);
      await settleReal(t);
      expect(MergedMode.focus.value, _kOpen, reason: 'ملخّص المفتوحة يعرض قائمة غيرها');
      expect(find.text('companies-root', skipOffstage: false), findsNothing, reason: '«شركاتي» بقيت تحت الغلاف');
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });
}
