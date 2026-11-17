import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/pay_debt_sheet.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «هل أُرسلت رسالة العمليّة؟» في «كل الشركات» (١٧ نوفمبر): السؤال يذهب لشركة صفّ المشترك نفسها — بمفتاحها هي، كالتسديد
/// الذي سبقه — لا للمفتوحة ولا بلا مفتاح (كان سيقرأ حركة مشتركٍ آخر بالرقم نفسه في شركةٍ أخرى، أو لا يجد شيئاً).
/// الخادم: مدخل القراءة `op-wa` في companyRoutingAllow (ساس، ايرث لنك، الشركات المُضافة).
const _kOpen = 'c0000000000a1';
const _kB = 'c0000000000b2';

ResponseBody _json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

/// خادمٌ بصدى المفتاح: يسجّل كلّ طلبٍ بمفتاح شركته، وما سواه لخادم لقطات الصلاحيّات.
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
    if (m == 'GET' && RegExp(r'^/api/v2/subscribers/\d+$').hasMatch(path)) {
      return j({'success': true, 'data': {'idx': path.split('/').last}});
    }
    if (m == 'POST' && path.endsWith('/pay-debt')) return j({'success': true, 'message': 'تم', 'data': {'new_balance': 0}});
    if (m == 'GET' && path.endsWith('/op-wa')) {
      return j({'success': true, 'data': {'state': 'sent', 'reason': null}});
    }
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
  setUpAll(() async {
    await visualSetUpAll();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  late _Srv srv;

  Future<void> up(WidgetTester t, {required bool merged}) async {
    final visual = await visualSetUp(s1bSasOwner);
    srv = _Srv(visual);
    ApiClient.dio.httpClientAdapter = srv;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    ReceiptSettingsApi.clearCache();
    MergedMode.reset();
    if (merged) {
      MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
      expect(await t.runAsync(() => MergedMode.enter()), isTrue);
    }
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    MergedMode.reset();
    await visualTearDown();
  }

  /// وقتٌ حقيقيّ للطلبات (الموجَّهة تمرّ بمعترضٍ غير متزامن) + وقتٌ وهميّ للمؤقّتات.
  Future<void> settleReal(WidgetTester t, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Subscriber row(String? key) => Subscriber(
      idx: '9', username: 'b.nine', firstname: 'باء', lastname: 'تسعة', phone: '07701234567', notes: '-2500', companyKey: key);

  /// يفتح ورقة التسديد لـ[sub] ويسدّد كامل دينه وينتظر السؤال عن الرسالة.
  Future<void> payAll(WidgetTester t, Subscriber sub) async {
    late BuildContext ctx;
    await pumpVisual(t, phone, home: (_) => Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.expand();
        })));
    await settleReal(t);
    srv.asked.clear();
    unawaited(showPayDebtSheet(ctx, sub));
    await settleReal(t);
    await t.ensureVisible(find.text('كامل الدين'));
    await t.pump();
    await t.tap(find.text('كامل الدين'));
    await t.pump();
    await t.ensureVisible(find.text('تسديد الآن'));
    await t.pump();
    await t.tap(find.text('تسديد الآن'));
    await settleReal(t, rounds: 20); // ≥ ٢ث وهميّة: النجاح ثمّ السؤال الأوّل (٠٫٩ث) وجوابه
  }

  List<String> of(String needle) => srv.asked.where((a) => a.contains(needle)).toList();

  testWidgets('صفّ شركةٍ أخرى (JTSHOP): التسديد والسؤال عن رسالته كلاهما بمفتاحها', (t) async {
    await up(t, merged: true);
    try {
      await payAll(t, row(_kB));
      expect(of('/pay-debt'), ['POST /api/v2/subscribers/9/pay-debt $_kB']);
      expect(of('/op-wa'), ['GET /api/v2/subscribers/9/op-wa $_kB'], reason: 'السؤال لشركة الصفّ — لا للمفتوحة ولا بلا مفتاح');
      expect(srv.asked.indexOf('POST /api/v2/subscribers/9/pay-debt $_kB'), lessThan(srv.asked.indexOf('GET /api/v2/subscribers/9/op-wa $_kB')));
      expect(find.textContaining('وأُرسلت الرسالة للمشترك'), findsOneWidget, reason: 'النتيجة تُقال');
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('صفّ الشركة المفتوحة في «كل الشركات»: بمفتاحها هي', (t) async {
    await up(t, merged: true);
    try {
      await payAll(t, row(_kOpen));
      expect(of('/pay-debt'), ['POST /api/v2/subscribers/9/pay-debt $_kOpen']);
      expect(of('/op-wa'), ['GET /api/v2/subscribers/9/op-wa $_kOpen']);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('الوضع العاديّ: بلا مفتاح شركة — الطلبان كما هما', (t) async {
    await up(t, merged: false);
    try {
      await payAll(t, row(null));
      expect(of('/pay-debt'), ['POST /api/v2/subscribers/9/pay-debt -']);
      expect(of('/op-wa'), ['GET /api/v2/subscribers/9/op-wa -']);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });
}
