import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';
import 'package:rad_mysvcs/models/device_health.dart';
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
/// والسلوك (٧، منذ ٢١ نوفمبر — المالك: «ابدي حبي الي تنصحه يبقى ع شركه بقي»؛ الخادم 1af5be0): صفّ شركةٍ أخرى — «تنبيه المشترك»
/// وقوالب واتساب صفحته ورمز QR — يخرج من واتساب **شركته**: قوالبها وحدودها بمعرّف مديرها، والإرسال موجَّهٌ لها بمرجع نافذته.
/// (قبله كان «للشركة وحدها»: لا يخرج منها شيء.)
const _kOpen = 'c0000000000a1';
const _kB = 'c0000000000b2';

/// مرجع نافذة مشترك JTSHOP كما يسكّه الخادم.
final _refB = 'r_${'b' * 22}';

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

  /// آخر جسمٍ ومرجع نافذةٍ لكلّ كتابة (`POST /path`).
  final bodies = <String, Object?>{};
  final refs = <String, String?>{};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    final m = o.method.toUpperCase();
    asked.add('$m $path ${key ?? '-'}');
    if (m != 'GET') {
      bodies['$m $path'] = o.data;
      refs['$m $path'] = o.headers['x-company-ref'] as String?;
    }
    final h = key == null ? const <String, List<String>>{} : {'x-company-key': [key]};
    ResponseBody j(Object body) => _json(200, body, headers: h);
    if (path == '/api/v2/subscribers' && m == 'GET') {
      if (o.queryParameters['page'] != null) return j({'success': true, 'paged': true, 'total': 1});
      return j({'success': true, 'data': const []});
    }
    if (m == 'GET' && RegExp(r'^/api/v2/subscribers/\d+$').hasMatch(path)) {
      // نافذة المشترك الموجَّهة تسكّ مرجعها (كالخادم — companyRouting mint)
      return _json(200, {'success': true, 'data': {'idx': path.split('/').last}}, headers: {
        ...h,
        if (key != null) 'x-company-ref': [key == _kB ? _refB : 'r_${'a' * 22}'],
      });
    }
    if (m == 'POST' && path.endsWith('/portal-qr-token')) {
      return j({'success': true, 'data': {'linkUrl': 'https://pro.example/mysub/q/abc', 'expiresAt': '2026-11-10T10:00:00Z'}});
    }
    // قوالب الشركة بمعرّف مديرها في نصّها — فيُعرف من أيّ شركةٍ جاء النصّ المُرسَل
    if (m == 'GET' && path.startsWith('/api/whatsapp/templates/')) {
      final admin = Uri.decodeComponent(path.split('/').last);
      return j({
        'success': true,
        'templates': [
          for (final t in ['debt_reminder', 'expiry_warning', 'subscriber_info'])
            {'template_type': t, 'is_active': 1, 'message_content': 'قالب $admin $t {subscriber_name}', 'default_channel': 'auto'},
        ],
      });
    }
    if (m == 'GET' && path == '/api/v2/connection-alerts/settings') {
      return j({'success': true, 'data': {'enabled': true, 'fiber_rx_dbm': -27, 'name_mode': 'name'}});
    }
    if (path == '/api/whatsapp/send-message') return j({'success': true, 'channel': 'whatsapp'});
    if (path == '/api/whatsapp/send-media') return j({'success': true, 'channel': 'whatsapp'});
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

    test('٧: رسالة الصفّ بغير شركته، وإرسالٌ جديد غير مراجَع، وشيت إعداد الجهاز يُبنى بلا حارسه', () {
      // ٢١ نوفمبر: رسائل الكارت بشركة الصفّ (لم تعد «للشركة وحدها») — غلافها للمفتوحة أو صفٌّ غيره يُكشف
      proves(sideVerdict,
          plant('lib/screens/subscribers/connection_alert_flow.dart',
              'final result = await MergedOps.write(\n    sub,\n    () => WhatsAppApi.sendMessage(',
              'final result = await CompanyRoute.runOpen(\n    () => WhatsAppApi.sendMessage('),
          'ليس بشركة صفّه');
      proves(sideVerdict,
          append('lib/screens/subscribers/subscriber_detail_screen.dart',
              "Future<void> _planted(Subscriber s) => WhatsAppApi.sendMessage(to: '1', message: 'x', sas4Idx: s.idx);"),
          'غير مراجَع');
      // صورةٌ لمشترك (send-media — ١٩ نوفمبر) كاتبٌ كالنصّ: موضعٌ جديد بلا مراجعة يُرفض، وحارس نافذة الرمز إن أُزيل يُكشف
      proves(sideVerdict,
          append('lib/screens/subscribers/subscriber_detail_screen.dart',
              "Future<void> _plantedMedia(Subscriber s) => WhatsAppApi.sendMedia(to: '1', bytes: Uint8List(1), filename: 'x.png', sas4Idx: s.idx);"),
          'غير مراجَع');
      proves(sideVerdict,
          plant('lib/screens/subscribers/sheets/qr_login_sheet.dart',
              'final result = await MergedOps.run(\n        widget.sub,\n        () => WhatsAppApi.sendMedia(',
              'final result = await CompanyRoute.runOpen(\n        () => WhatsAppApi.sendMedia('),
          'ليس بشركة صفّه');
      // الواجهة التي تُوجّه بنفسها (sendTemplateWithPreview) تأخذ الصفّ نفسه — لا صفّاً يُبنى ولا null
      proves(sideVerdict,
          plant('lib/screens/subscribers/subscribers_screen.dart',
              "context: context,\n        sub: s,\n        templateType: 'debt_reminder',",
              "context: context,\n        sub: Subscriber(username: 'x'),\n        templateType: 'debt_reminder',"),
          'ليس بصفّه');
      proves(sideVerdict,
          plant('lib/screens/subscribers/subscriber_detail_screen.dart',
              'context: context,\n      sub: sub,\n      templateType: templateType,',
              'context: context,\n      sub: null,\n      templateType: templateType,'),
          'ليس بصفّه');
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
      // رمز وكيل الرسالة (لا أوّل pin في الملفّ — قوالب شركة الصفّ قبله منذ ٢١ نوفمبر)
      proves(sectionVerdict,
          plant('lib/api/whatsapp_api.dart', 'final base = await CompanyRoute.pin(sub.companyKey,',
              'final base = await CompanyRoute.pin(null,'),
          'ليس بشركة صفّه');
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

  group('السلوك: رسائل كارت صفّ شركةٍ أخرى تخرج من واتسابها هي — بقالبها وحدودها ومعرّف مديرها ومرجع نافذته (البند ٧، ٢١ نوفمبر)', () {
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
      WhatsAppApi.clearCaches();
      MergedMode.reset();
      MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
      expect(await t.runAsync(() => MergedMode.enter()), isTrue);
    }

    Future<void> down(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      DeviceProbeApi.debugRunProbe = null;
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

    List<String> sends(String path) => srv.asked.where((a) => a.startsWith('POST $path ')).toList();

    /// الإرسال خرج لشركة الصفّ وحدها: موجَّهٌ بمفتاحها، بمعرّف مديرها، وبمرجع نافذة مشتركه — ولا شيء للمفتوحة.
    void sentFromB(String path, {bool subject = true}) {
      expect(sends(path), ['POST $path $_kB'], reason: 'إرسالٌ واحد موجَّه لـJTSHOP لا للمفتوحة');
      final body = srv.bodies['POST $path'] as Map;
      expect(body['adminId'], 'jt:6836', reason: 'معرّف مدير JTSHOP — لا معرّف الجلسة (supernet:12)');
      expect(body['sas4Idx'], '9');
      if (subject) expect(srv.refs['POST $path'], _refB, reason: 'مرجع نافذة المشترك (الخادم يطلبه — bodySubject sas4Idx)');
    }

    Future<void> confirmAuto(WidgetTester t) async {
      final go = find.text('إرسال تلقائي');
      expect(go, findsOneWidget, reason: 'التلقائيّ متاح لمشترك شركةٍ أخرى (لم يعد «للشركة وحدها»)');
      expect(find.byKey(const ValueKey('wa-auto-blocked')), findsNothing);
      await t.ensureVisible(go);
      await t.pump();
      await t.tap(go);
      await settleReal(t, rounds: 8);
    }

    testWidgets('«تنبيه المشترك» لصفّ JTSHOP: حدود JTSHOP وقوالبها ثمّ send-message منها بمرجع نافذته', (t) async {
      await up(t);
      try {
        DeviceProbeApi.debugRunProbe = (ip) async => DeviceHealthSnapshot(
              kind: DeviceKind.ont,
              ip: ip,
              ont: const OntOpticalInfo(
                  txPower: '2.0', rxPower: '-30.5', voltage: '3300', temperature: '48', bias: '10', sendStatus: ''),
            );
        late BuildContext ctx;
        await pumpVisual(t, phone, home: (_) => Scaffold(body: Builder(builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            })));
        await settleReal(t);
        srv.asked.clear();
        unawaited(showConnectionAlertFlow(ctx, bRow().copyWithOnline(online: true, ip: '10.9.0.9')));
        await settleReal(t, rounds: 10);
        expect(srv.asked, contains('GET /api/v2/connection-alerts/settings $_kB'), reason: 'حدود JTSHOP لا حدود المفتوحة');
        expect(srv.asked, contains('GET /api/whatsapp/templates/jt:6836 $_kB'), reason: 'قوالب JTSHOP بمعرّف مديرها');
        expect(srv.asked.where((a) => a.contains('/api/whatsapp/templates/supernet')), isEmpty, reason: 'ولا قوالب المفتوحة');
        await confirmAuto(t);
        sentFromB('/api/whatsapp/send-message');
        expect((srv.bodies['POST /api/whatsapp/send-message'] as Map)['forceChannel'], 'whatsapp');
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });

    for (final a in [SubscriberAutoAction.debtReminder, SubscriberAutoAction.expiryWarning, SubscriberAutoAction.sendInfo]) {
      testWidgets('قالب واتساب من صفحة مشترك JTSHOP (${a.name}): قالب JTSHOP نفسه ثمّ send-message منها بمرجع نافذته', (t) async {
        await up(t);
        try {
          await pumpVisual(t, phone, home: (_) => SubscriberDetailScreen(sub: bRow(), autoAction: a));
          await settleReal(t, rounds: 10);
          expect(srv.asked, contains('GET /api/whatsapp/templates/jt:6836 $_kB'), reason: 'قوالب JTSHOP بمعرّف مديرها');
          expect(srv.asked.where((x) => x.contains('/api/whatsapp/templates/supernet')), isEmpty, reason: 'ولا قوالب المفتوحة');
          await confirmAuto(t);
          sentFromB('/api/whatsapp/send-message');
          final type = switch (a) {
            SubscriberAutoAction.debtReminder => 'debt_reminder',
            SubscriberAutoAction.expiryWarning => 'expiry_warning',
            _ => 'subscriber_info',
          };
          final body = srv.bodies['POST /api/whatsapp/send-message'] as Map;
          expect(body['intent'], type);
          expect('${body['message']}', contains('قالب jt:6836 $type'), reason: 'نصّ قالب JTSHOP لا المفتوحة');
          expect(t.takeException(), isNull);
        } finally {
          await down(t);
        }
      });
    }

    testWidgets('رمز QR لمشترك JTSHOP: التلقائيّ متاحٌ، وsend-media من واتسابها بمعرّف مديرها', (t) async {
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
        await confirmAuto(t);
        await settleReal(t, rounds: 10);
        // send-media بلا مرجع نافذة (الخادم: bodyAdmin وحده) — مدير JTSHOP وموجَّهٌ لها
        sentFromB('/api/whatsapp/send-media', subject: false);
        expect(sends('/api/whatsapp/send-message'), isEmpty);
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });
  });
}
