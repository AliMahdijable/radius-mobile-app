import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';

import 'visual_perm/visual_perm_harness.dart';

/// مراجعة الإصدار 179 (للإصدار 180): تحديث صفحة مشتركٍ في حسابٍ كبير (٥٠٠٠+، لا قائمة كاملة) — في الوضع العاديّ وفي «كل
/// الشركات» لشركةٍ كبيرة.
///
/// `BigSubscribersApi.findOne` كان يقرأ صفحةً واحدة من ٢٠ نتيجة «بحثٍ يحتوي» (اليوزر والاسم والملاحظات، و`_` يطابق أيّ حرف):
/// يوزرٌ قصيرٌ أو شائع يأتي صفّه بعد غيره ⇒ لا يُوجد ⇒ الصفحة تبقى على الدين القديم و«تسديد» فعّال (دفعةٌ ثانية تزيد على الدين).
/// الآن: صفحاتٌ من ١٠٠ حتى ٥ بعد أن تُخطئ الأولى، وما لم يُوجد ⇒ «تعذّر تحديث بيانات المشترك — الأرقام قد تكون قديمة» و«تسديد»
/// و«إضافة دين» مقفلان حتى ينجح تحديث.
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

/// ساسٌ كبير (٨٩ ألفاً) ببحثٍ «يحتوي»: نتائج `?q=ali` كثيرة، وصفّ المشترك (idx 9، «ali») في [targetAt] منها.
class _Srv implements HttpClientAdapter {
  _Srv(this.fallback);
  final HttpClientAdapter fallback;

  /// «METHOD path key [q= size= page=]» لكلّ طلب.
  final asked = <String>[];

  /// موضع صفّ المشترك بين نتائج البحث، وعددها كلّها.
  int targetAt = 20;
  int total = 45;

  /// البحث يفشل (الساس لا يردّ).
  bool searchDown = false;

  /// دين المشترك الحيّ (التسديد يغيّره).
  String debt = '-30000';

  List<Map<String, Object?>> _matches() => [
        for (var i = 0; i < total; i++)
          i == targetAt ? _row(9, 'ali', debt: debt) : _row(1000 + i, 'x${i}ali', debt: '-1000'),
      ];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    final m = o.method.toUpperCase();
    final q = o.queryParameters['q'];
    final paged = o.queryParameters['page'] != null;
    asked.add('$m $path ${key ?? '-'}'
        '${q == null ? '' : ' q=$q size=${o.queryParameters['size']} page=${o.queryParameters['page']}'}');
    final h = key == null ? const <String, List<String>>{} : {'x-company-key': [key]};
    ResponseBody j(Object body) => _json(200, body, headers: h);
    // الحساب كبير (المفتوح في الوضع العاديّ، وشركة باء في «كل الشركات»)؛ والمفتوحة في «كل الشركات» صغيرة
    final big = key == null || key == _kB;
    if (path == '/api/v2/subscribers' && m == 'GET') {
      if (paged && big) {
        if (q == null) return j({'success': true, 'paged': true, 'total': 89000, 'last_page': 89000, 'data': []});
        if (searchDown) return _json(502, {'success': false, 'message': 'الساس لا يردّ'}, headers: h);
        final size = int.parse('${o.queryParameters['size']}');
        final page = int.parse('${o.queryParameters['page']}');
        final all = _matches();
        final from = (page - 1) * size;
        return j({
          'success': true,
          'paged': true,
          'total': all.length,
          'last_page': (all.length / size).ceil(),
          'data': all.sublist(from.clamp(0, all.length), (from + size).clamp(0, all.length)),
        });
      }
      if (paged) return j({'success': true, 'paged': true, 'total': 2});
      return j({'success': true, 'data': [_row(2, 'a.two', debt: '-7000')]});
    }
    final sub = RegExp(r'^/api/v2/subscribers/(\d+)(/[a-z-]+)?$').firstMatch(path);
    if (sub != null) {
      final tail = sub.group(2) ?? '';
      if (m == 'GET' && tail.isEmpty) return j({'success': true, 'data': {'idx': sub.group(1)}});
      if (m == 'POST' && tail == '/pay-debt') {
        debt = '-5000';
        return j({'success': true, 'message': 'تم التسديد'});
      }
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
    BigSubscribersApi.reset();
    ReceiptSettingsApi.clearCache();
    MergedMode.reset();
    if (merged) {
      AccountApi.tokenSource = ({bool force = false}) async => 'acct';
      MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
      expect(await t.runAsync(() => MergedMode.enter()), isTrue);
    }
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    MergedMode.reset();
    BigSubscribersApi.reset();
    await visualTearDown();
  }

  Future<void> settleReal(WidgetTester t, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Subscriber row({String? key}) =>
      Subscriber(idx: '9', username: 'ali', firstname: 'علي', lastname: 'تسعة', phone: '07701234567', notes: '-30000', companyKey: key);

  /// «تسديد» من بطاقة الرصيد: ٢٥٬٠٠٠ من ٣٠٬٠٠٠.
  Future<void> pay(WidgetTester t) async {
    await t.tap(find.text('تسديد').first);
    await settleReal(t);
    await t.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).first, '25000');
    await t.pump();
    await t.tap(find.text('تسديد الآن'));
    await settleReal(t, rounds: 14);
  }

  List<String> searches() => srv.asked.where((a) => a.contains(' q=')).toList();

  for (final merged in [false, true]) {
    final where = merged ? '«كل الشركات» (شركة JTSHOP الكبيرة)' : 'الحساب الكبير (الوضع العاديّ)';
    final key = merged ? _kB : null;
    final k = key ?? '-';
    testWidgets('$where: صفّ المشترك بعد عشرين نتيجةً غيره ⇒ يُوجد في الصفحة التالية والدين الجديد يظهر بعد التسديد', (t) async {
      await up(t, merged: merged);
      try {
        await pumpVisual(t, phone, home: (_) => SubscriberDetailScreen(sub: row(key: key)));
        await settle(t, seconds: 2);
        expect(find.text('30,000 د.ع'), findsWidgets);
        srv.asked.clear();
        await pay(t);
        expect(srv.asked, contains('POST /api/v2/subscribers/9/pay-debt $k'));
        expect(find.text('30,000 د.ع'), findsNothing, reason: 'الدين القديم باقٍ بعد التسديد — يدعو لدفعةٍ ثانية: ${searches()}');
        expect(find.text('5,000 د.ع'), findsWidgets, reason: 'الدين الحيّ بعد التسديد');
        expect(searches(), ['GET /api/v2/subscribers $k q=ali size=20 page=1', 'GET /api/v2/subscribers $k q=ali size=100 page=1'],
            reason: 'الأولى (٢٠) أخطأته ⇒ صفحةٌ من ١٠٠ — موجَّهةً لشركته');
        expect(find.textContaining('تعذّر تحديث بيانات المشترك'), findsNothing);
        expect(t.takeException(), isNull);
      } finally {
        await down(t);
      }
    });
  }

  testWidgets('لم يُوجد ضمن خمس صفحات ⇒ «تعذّر تحديث بيانات المشترك — الأرقام قد تكون قديمة» و«تسديد»/«إضافة دين» مقفلان؛ '
      'والسحب الناجح يفتحهما بالدين الجديد', (t) async {
    await up(t, merged: false);
    srv
      ..total = 700
      ..targetAt = 650;
    try {
      await pumpVisual(t, phone, home: (_) => SubscriberDetailScreen(sub: row()));
      await settle(t, seconds: 2);
      srv.asked.clear();
      await pay(t);
      expect(searches(), [
        'GET /api/v2/subscribers - q=ali size=20 page=1',
        for (var p = 1; p <= BigSubscribersApi.findMaxPages; p++) 'GET /api/v2/subscribers - q=ali size=100 page=$p',
      ], reason: 'صفحاتٌ محدودة (٢٠ ثمّ ٥×١٠٠) لا أكثر');
      expect(find.textContaining('تعذّر تحديث بيانات المشترك — الأرقام قد تكون قديمة'), findsWidgets,
          reason: 'الأرقام القديمة تُعرض بلا تنبيه');
      // «تسديد» مقفل: لا شيت، ونقرته السبب
      await t.pump(const Duration(seconds: 4));
      await t.tap(find.text('تسديد').first);
      await settleReal(t);
      expect(find.byType(BottomSheet), findsNothing, reason: '«تسديد» فعّالٌ على دينٍ لم يتحدّث — دفعةٌ ثانية');
      expect(find.textContaining('اسحب الصفحة للتحديث'), findsWidgets);
      await t.pump(const Duration(seconds: 4));
      await t.tap(find.text('إضافة دين').first);
      await settleReal(t);
      expect(find.byType(BottomSheet), findsNothing, reason: '«إضافة دين» فعّالٌ على دينٍ لم يتحدّث');
      // ومن «المزيد»: التسديد وإضافة الدين مقفلان بالسبب نفسه
      await t.pump(const Duration(seconds: 4));
      await t.tap(find.text('subscribers.more_actions'.tr()).first);
      await settleReal(t);
      final payTile = find.text('subscribers.op_pay_debt'.tr()).last;
      await t.ensureVisible(payTile);
      await t.pump();
      await t.tap(payTile);
      await settleReal(t);
      expect(find.text('تسديد الآن'), findsNothing, reason: '«تسديد» من «المزيد» فتح الشيت');
      Navigator.of(t.element(find.byType(SubscriberDetailScreen))).popUntil((r) => r.isFirst);
      await settleReal(t);

      // الساس صار يجده (أو هدأ الضغط) ⇒ السحب للتحديث ينجح ⇒ يُفتح المال بالدين الجديد
      srv.targetAt = 3;
      final refresh = t.widget<RefreshIndicator>(find.byType(RefreshIndicator).first);
      unawaited(refresh.onRefresh());
      await settleReal(t, rounds: 10);
      expect(find.text('5,000 د.ع'), findsWidgets, reason: 'الدين الحيّ بعد تحديثٍ ناجح');
      await t.pump(const Duration(seconds: 4));
      await t.tap(find.text('تسديد').first);
      await settleReal(t);
      expect(find.text('تسديد الآن'), findsOneWidget, reason: 'تحديثٌ نجح ⇒ «تسديد» يعود');
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('البحث يتعذّر بعد عمليّة («كل الشركات») ⇒ القفل نفسه بالسبب، لا الدين القديم على أنّه حيّ', (t) async {
    await up(t, merged: true);
    try {
      await pumpVisual(t, phone, home: (_) => SubscriberDetailScreen(sub: row(key: _kB)));
      await settle(t, seconds: 2);
      srv.searchDown = true;
      await pay(t);
      expect(srv.asked, contains('POST /api/v2/subscribers/9/pay-debt $_kB'));
      expect(find.textContaining('تعذّر تحديث بيانات المشترك — الأرقام قد تكون قديمة'), findsWidgets);
      await t.pump(const Duration(seconds: 4));
      await t.tap(find.text('تسديد').first);
      await settleReal(t);
      expect(find.byType(BottomSheet), findsNothing);
      expect(t.takeException(), isNull);
    } finally {
      await down(t);
    }
  });

  testWidgets('findOne: الصفحة الأولى تكفي حين تجده (طلبٌ واحد)؛ وdeepPages: 0 (أجهزة الألياف — عشرات اليوزرات معاً) يبقى عليها '
      'كما كان', (t) async {
    await up(t, merged: false);
    try {
      srv.targetAt = 4;
      final near = await t.runAsync(() => BigSubscribersApi.findOne(idx: '9', username: 'ali'));
      expect(near?.idx, '9');
      expect(searches(), ['GET /api/v2/subscribers - q=ali size=20 page=1']);
      srv
        ..asked.clear()
        ..targetAt = 30;
      final shallow = await t.runAsync(() => BigSubscribersApi.findOne(username: 'ali', deepPages: 0));
      expect(shallow, isNull);
      expect(searches(), ['GET /api/v2/subscribers - q=ali size=20 page=1'], reason: 'لا صفحات إضافيّة لأجهزة الألياف');
      srv.asked.clear();
      final deep = await t.runAsync(() => BigSubscribersApi.findOne(username: 'ali'));
      expect(deep?.idx, '9', reason: 'بعد عشرين وأكثر ⇒ الصفحة التالية');
      // نتائج البحث كلّها في الأولى (٢٠ أو أقلّ) ولم يُوجد ⇒ لا صفحة أخرى
      srv
        ..asked.clear()
        ..total = 12
        ..targetAt = 99;
      expect(await t.runAsync(() => BigSubscribersApi.findOne(idx: '9', username: 'ali')), isNull);
      expect(searches(), hasLength(1));
    } finally {
      await down(t);
    }
  });
}
