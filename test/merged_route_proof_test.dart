import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/connection_alert_flow.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/qr_login_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';

import 'support/route_reviewed.dart';
import 'support/route_scan.dart';
import 'visual_perm/visual_perm_harness.dart';

/// مراجعة الإصدار 179 (للإصدار 180) — جودة الإثبات (route3_verify.json البنود ٥–١١): كلّ فحصٍ ثابتٍ جديد يفشل على نمطه السيّئ.
///
/// الأحكام نفسها التي يحكم بها test/merged_route_invariant_test.dart على lib (test/support/route_reviewed.dart بقوائمها المراجَعة)
/// تُعطى هنا نسخةً من lib بالذاكرة زُرع فيها النمط السيّئ في ملفّه الحقيقيّ — فيثبت أنّ الحكم يراه:
///   ٥. كتابة مالٍ في شاشة قسمٍ بـnull أو بالشريط، أو محلّيٌّ من الشريط، أو `_companyKey` من غير الشجرة، أو موضعٌ جديد.
///   ٦. runOpen أو pin بالشريط مكان غلاف الصفّ، وكتابةٌ في إغلاقٍ مؤجَّل (onTap:) داخل الغلاف.
///   ٧. حارس «للشركة وحدها» أُزيل، أو إرسالٌ جديد غير مراجَع، أو بوّابةٌ أُزيلت، أو شيت إعداد الجهاز بلا حارسه.
///   ٨. فصلٌ فرديّ يعود في ملفّ الجماعيّ (الاستثناء بالدالّة لا بالملفّ)، وحارسٌ أُزيل من دالّته، وشيتٌ جماعيّ يُبنى خارج دالّة عرضه.
///   ٩. «المفتوحة» بغلافٍ يتبع الشريط، و«الصفّ» بـpin(null.
///   ١١. pipe و_d وكتابةٌ بمسارٍ لا يُحلّ ودالّةٌ تمرّر مسار مشترك.
/// والسلوك (٧): صفّ شركةٍ أخرى — «تنبيه المشترك» وقوالب واتساب صفحته ورمز QR — لا يخرج منها send-message، والتلقائيّ في رمز QR
/// ممنوعٌ بسببه قبل التأكيد.
const _kOpen = 'c0000000000a1';
const _kB = 'c0000000000b2';

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

/// خادمٌ بصدى المفتاح، وما سواه لخادم لقطات الصلاحيّات.
class _Srv implements HttpClientAdapter {
  _Srv(this.fallback);
  final HttpClientAdapter fallback;
  final asked = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    final m = o.method.toUpperCase();
    asked.add('$m $path ${key ?? '-'}');
    final h = key == null ? const <String, List<String>>{} : {'x-company-key': [key]};
    ResponseBody j(Object body) => _json(200, body, headers: h);
    if (path == '/api/v2/subscribers' && m == 'GET') {
      if (o.queryParameters['page'] != null) return j({'success': true, 'paged': true, 'total': 1});
      return j({'success': true, 'data': const []});
    }
    if (m == 'GET' && RegExp(r'^/api/v2/subscribers/\d+$').hasMatch(path)) {
      return j({'success': true, 'data': {'idx': path.split('/').last}});
    }
    if (m == 'POST' && path.endsWith('/portal-qr-token')) {
      return j({'success': true, 'data': {'linkUrl': 'https://pro.example/mysub/q/abc', 'expiresAt': '2026-11-10T10:00:00Z'}});
    }
    if (path == '/api/whatsapp/send-message') return j({'success': true, 'channel': 'whatsapp'});
    if (path == '/api/v2/receipt-settings') return j({'success': true, 'data': {}});
    final r = await fallback.fetch(o, rs, cf);
    if (key == null) return r;
    return ResponseBody(r.stream, r.statusCode, headers: {...r.headers, 'x-company-key': [key]});
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _companies() => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kOpen, 'code': 'supernet', 'username': 'u0', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': 'supernet:12', 'ns': 'a', 'currency': 'IQD', 'color_index': 0},
        {'key': _kB, 'code': 'jt', 'username': 'jtboss', 'name': 'JTSHOP', 'status': 'ok', 'admin_id': 'jt:6836', 'ns': 'j', 'currency': 'IQD', 'color_index': 1},
      ],
    };

void main() {
  group('كلّ فحصٍ يفشل على نمطه مزروعاً في ملفّه الحقيقيّ (نسخةٌ بالذاكرة)', () {
    final lib = loadLib();

    /// [lib] وفي [file] [to] مكان [from] (مرّةً، ويجب أن يوجد).
    Lib plant(String file, String from, String to) {
      final s = lib[file];
      expect(s, isNotNull, reason: file);
      expect(s!.raw.contains(from), isTrue, reason: 'النمط الأصليّ غير موجود في $file — تغيّر الكود؟\n$from');
      return {...lib, file: Src(s.raw.replaceFirst(from, to))};
    }

    /// [lib] و[code] مضافاً آخر [file].
    Lib append(String file, String code) => {...lib, file: Src('${lib[file]!.raw}\n$code\n')};

    final clean = <List<String> Function(Lib), List<String>>{};
    void proves(List<String> Function(Lib) verdict, Lib planted, String hint) {
      expect(clean.putIfAbsent(verdict, () => verdict(lib)), isEmpty, reason: 'lib كما هو سليم');
      final v = verdict(planted);
      expect(v, isNotEmpty, reason: 'الحكم لم يرَ النمط المزروع ($hint)');
      expect(v.join('\n'), contains(hint));
    }

    test('٥: كتابة مالٍ في شاشة قسمٍ بـnull أو بالشريط، ومحلّيٌّ من الشريط، و`_companyKey` من غير الشجرة، وموضعٌ جديد', () {
      const st = 'lib/screens/settlements/settlements_screen.dart';
      proves(moneyKeyVerdict,
          plant(st, 'openingBalance: _opening, companyKey: _companyKey)', 'openingBalance: _opening, companyKey: null)'),
          'companyKey: null');
      proves(moneyKeyVerdict,
          plant('lib/screens/sales/sales_screen.dart', '_VoidSheet(sale: sale, companyKey: _co)',
              '_VoidSheet(sale: sale, companyKey: MergedMode.focused?.key)'),
          'من الشريط');
      proves(moneyKeyVerdict,
          plant('lib/screens/expenses/expenses_screen.dart', 'final companyKey = _companyKey;',
              'final companyKey = MergedMode.focus.value;'),
          'محلّيٌّ من');
      proves(moneyKeyVerdict,
          plant(st, 'String? get _companyKey => MergedSection.routeKeyOf(context);', 'String? get _companyKey => MergedMode.focus.value;'),
          'بتعريفٍ غير شجرة القسم');
      proves(moneyKeyVerdict,
          append('lib/screens/reports/activity_log_report_screen.dart',
              'Future<void> _planted(int id, String? companyKey) => ExpensesApi.delete(id, companyKey: companyKey);'),
          'activity_log_report_screen.dart ExpensesApi.delete');
    });

    test('٦: runOpen أو pin بالشريط مكان غلاف الصفّ، وكتابةٌ في إغلاقٍ مؤجَّل داخل الغلاف', () {
      proves(writerVerdict,
          plant('lib/screens/subscribers/sheets/quick_discount_sheet.dart', 'MergedOps.write(widget.sub, () => SubscribersApi.setDiscount(',
              'CompanyRoute.runOpen(() => SubscribersApi.setDiscount('),
          'CompanyRoute.runOpen(');
      proves(writerVerdict,
          plant('lib/screens/subscribers/sheets/add_debt_sheet.dart', 'MergedOps.write(widget.sub, () => SubscribersApi.addDebt(',
              'CompanyRoute.pin(MergedMode.focus.value, () => SubscribersApi.addDebt('),
          'CompanyRoute.pin(MergedMode.focus.value,');
      proves(writerVerdict,
          append('lib/screens/subscribers/subscriber_detail_screen.dart',
              "Future<void> _planted(BuildContext c, Subscriber s) => MergedOps.write(s, () async => showConfirmSheet(c, title: '', "
                  "message: '', confirmLabel: '', onTap: () => SubscribersApi.payDebt(idx: '9', amount: 1)));"),
          'مؤجَّل');
    });

    test('٧: حارس «للشركة وحدها» أُزيل، وإرسالٌ جديد غير مراجَع، وبوّابةٌ أُزيلت، وشيت إعداد الجهاز يُبنى بلا حارسه', () {
      proves(sideVerdict,
          plant('lib/screens/subscribers/connection_alert_flow.dart', 'final blocked = MergedOps.unsupported(sub);',
              'final String? blocked = null;'),
          'بلا حارس');
      proves(sideVerdict,
          append('lib/screens/subscribers/subscriber_detail_screen.dart',
              "Future<void> _planted(Subscriber s) => WhatsAppApi.sendMessage(to: '1', message: 'x', sas4Idx: s.idx);"),
          'غير مراجَع');
      proves(sideVerdict,
          plant('lib/screens/subscribers/subscribers_screen.dart', 'onSendDebtReminder: !_mergedOn &&', 'onSendDebtReminder: true &&'),
          'بلا البوّابة');
      proves(sideVerdict,
          append('lib/screens/subscribers/subscriber_detail_screen.dart',
              "Future<void> _planted(BuildContext c) => showAppSheet<bool>(context: c, builder: (_) => const DeviceConfigSheet(username: 'u'));"),
          'DeviceConfigSheet يُبنى بلا حارس');
    });

    test('٨: فصلٌ فرديّ في ملفّ الجماعيّ (الاستثناء بالدالّة)، وحارسٌ أُزيل من دالّته، وشيتٌ جماعيّ يُبنى خارج دالّة عرضه', () {
      const ss = 'lib/screens/subscribers/subscribers_screen.dart';
      proves(writerVerdict,
          append(ss, 'Future<void> _disconnectOne(Subscriber s) async { await SubscribersApi.disconnect(s.idx!); }'),
          'ضمنيّ');
      proves(writerVerdict, plant(ss, 'if (selectedSubs == null) return;', ''), '_bulkRowsOrRefuse');
      proves(writerVerdict,
          append('lib/screens/subscribers/sheets/bulk_pay_debt_sheet.dart',
              'Future<bool?> _planted(BuildContext c, List<Subscriber> s) => showAppSheet<bool>(context: c, builder: (_) => _BulkPayDebtSheet(subs: s));'),
          'يُبنى خارج showBulkPayDebtSheet');
    });

    test('٩: «المفتوحة» بغلافٍ يتبع الشريط، و«الصفّ» بـpin(null', () {
      proves(sectionVerdict,
          plant('lib/screens/reports/activity_log_report_screen.dart', 'CompanyRoute.runOpen(() => ExpensesApi.list(',
              'CompanyRoute.pin(MergedMode.focus.value, () => ExpensesApi.list('),
          'ليس داخل CompanyRoute.runOpen');
      proves(sectionVerdict,
          plant('lib/api/whatsapp_api.dart', 'CompanyRoute.pin(sub.companyKey,', 'CompanyRoute.pin(null,'), 'ليس بشركة صفّه');
    });

    test('١١: pipe و_d وكتابةٌ بمسارٍ لا يُحلّ ودالّةٌ تمرّر مسار مشترك', () {
      proves(dioVerdict,
          append('lib/api/tickets_api.dart', "Future<void> _planted() => ApiClient.pipe.post<Object?>('/api/v2/sales/void-all');"),
          '/api/v2/sales/void-all');
      proves(dioVerdict,
          plant('lib/core/net/vpn_pipe.dart', "await _d.post<dynamic>('/api/v2/conn-vpn/pipe/release',",
              "await _d.post<dynamic>('/api/v2/settlements/open',"),
          '/api/v2/settlements/open');
      proves(dioVerdict,
          append('lib/api/tickets_api.dart', 'Future<void> _planted(String a) => ApiClient.dio.post<Object?>(Uri.parse(a).path);'),
          'بمسارٍ لا يُحلّ');
      proves(writerVerdict,
          plant('lib/api/tickets_api.dart', "static Future<TicketWrite> reopen(int id) => _write('\$base/\$id/reopen', const {});",
              "static Future<TicketWrite> reopen(int id) => _write('/api/v2/subscribers/\$id/pay-debt', const {});"),
          'TicketsApi.reopen');
    });
  });

  group('السلوك: صفّ شركةٍ أخرى لا يُرسَل له من واتساب المفتوحة (البند ٧)', () {
    setUpAll(() async {
      await visualSetUpAll();
      WidgetController.hitTestWarningShouldBeFatal = true;
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

    Future<void> down(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      MergedMode.reset();
      await visualTearDown();
    }

    Future<void> settleReal(WidgetTester t, {int rounds = 6}) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Subscriber bRow() => Subscriber(
        idx: '9', username: 'b.nine', firstname: 'باء', lastname: 'تسعة', phone: '07701234567', notes: '-2500', companyKey: _kB);

    List<String> sends() => srv.asked.where((a) => a.startsWith('POST /api/whatsapp/send-message')).toList();
    final refusal = find.textContaining('يعمل من الشركة وحدها');

    testWidgets('«تنبيه المشترك» لصفّ JTSHOP: يُرفض بسببه ولا send-message', (t) async {
      await up(t);
      try {
        late BuildContext ctx;
        await pumpVisual(t, phone, home: (_) => Scaffold(body: Builder(builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            })));
        await settleReal(t);
        srv.asked.clear();
        unawaited(showConnectionAlertFlow(ctx, bRow()));
        await settleReal(t);
        expect(refusal, findsWidgets);
        expect(sends(), isEmpty, reason: 'رسالةٌ من واتساب المفتوحة لمشترك JTSHOP');
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });

    for (final a in [SubscriberAutoAction.debtReminder, SubscriberAutoAction.expiryWarning, SubscriberAutoAction.sendInfo]) {
      testWidgets('قالب واتساب من صفحة مشترك JTSHOP (${a.name}): يُرفض بسببه ولا send-message', (t) async {
        await up(t);
        try {
          await pumpVisual(t, phone, home: (_) => SubscriberDetailScreen(sub: bRow(), autoAction: a));
          await settleReal(t, rounds: 10);
          expect(refusal, findsWidgets);
          expect(sends(), isEmpty, reason: 'قالبٌ من واتساب المفتوحة لمشترك JTSHOP');
          expect(srv.asked.where((x) => x.contains('/api/whatsapp/templates')), isEmpty, reason: 'ولا قوالب المفتوحة');
          expect(t.takeException(), isNull);
        } finally {
          await down(t);
        }
      });
    }

    testWidgets('رمز QR لمشترك JTSHOP: معاينة الإرسال يدويّةٌ وحدها بسببها قبل التأكيد — لا «تلقائي» يُختار ثمّ يُرفض، ولا send-message',
        (t) async {
      await up(t);
      try {
        late BuildContext ctx;
        await pumpVisual(t, phone, home: (_) => Scaffold(body: Builder(builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            })));
        await settleReal(t);
        unawaited(showQrLoginSheet(ctx, bRow()));
        await settleReal(t, rounds: 10);
        expect(srv.asked, contains('POST /api/v2/subscribers/9/portal-qr-token $_kB'), reason: 'الرمز من شركته');
        srv.asked.clear();
        final send = find.text('qr_login.send_wa'.tr());
        await t.ensureVisible(send);
        await t.pump();
        await t.tap(send);
        await settleReal(t);
        expect(find.byKey(const ValueKey('wa-auto-blocked')), findsOneWidget,
            reason: 'المعاينة تعرض «تلقائي» لمشترك شركةٍ أخرى — يُختار ثمّ يُرفض بعد التأكيد');
        expect(sends(), isEmpty);
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });
  });
}
