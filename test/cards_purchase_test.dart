import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/cards_api.dart';
import 'package:rad_mysvcs/screens/cards/cards_screen.dart';
import 'package:rad_mysvcs/screens/cards/sheets/card_purchase_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';

/// شراء الكارتات من الرصيد (٢٩ أكتوبر) — شيت الشراء كما يراه المدير (عربيّ، خطّ التطبيق، عرض ٣٦٠) أمام خادمٍ وهميّ بعقد
/// `/api/v2/cards/purchase/{options,history}` و`POST /api/v2/cards/purchase`.
///
/// ما يحرسه: لا شراء بلا تأكيدٍ بالمجموع؛ الحمولة كما يفهمها الخادم (فئةٌ من القائمة، عددٌ ولو بأرقامٍ عربيّة)؛ معرّف الطلب
/// ثابتٌ للنيّة الواحدة (الملتبس والانقطاع يُعادان بالمعرّف نفسه، والحكم النهائيّ يجدّده)؛ «طلبتَ الشراء نفسه» يحتاج «نعم»
/// صريحاً بالمعرّف نفسه؛ بعد القبول يُتابَع السجلّ حتى «وصلت»؛ والزرّ في الكارتات يظهر حين يفتحه الخادم وحده.
void main() {
  late _Server server;

  setUpAll(() async {
    await loadAppFonts();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    server = _Server();
    final adapter = ApiClient.dio.httpClientAdapter;
    ApiClient.dio.httpClientAdapter = server;
    addTearDown(() => ApiClient.dio.httpClientAdapter = adapter);
    CardsState.reset();
  });

  Future<void> pumpApp(WidgetTester t, Widget Function(BuildContext) home) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('ar'), Locale('en')],
      path: 'assets/translations',
      startLocale: const Locale('ar'),
      fallbackLocale: const Locale('ar'),
      saveLocale: false,
      assetLoader: const _DiskLoader(),
      child: Builder(
        builder: (ctx) => MaterialApp(
          locale: ctx.locale,
          supportedLocales: ctx.supportedLocales,
          localizationsDelegates: ctx.localizationDelegates,
          home: Scaffold(body: Builder(builder: home)),
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  /// يفتح الشيت بخيارات الخادم الوهميّ، ويعدّ مرّات «اشترى».
  Future<List<int>> openSheet(WidgetTester t) async {
    final bought = <int>[];
    final options = CardPurchaseOptions.fromJson(server.options);
    await pumpApp(
      t,
      (c) => Center(
        child: TextButton(
          onPressed: () => showCardPurchaseSheet(c, options, onPurchased: () => bought.add(1)),
          child: const Text('open'),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    return bought;
  }

  /// بعد الشراء دوّارة «قيد التجهيز» تدور حتى تصل الكارتات ⇒ لا pumpAndSettle هنا، بل خطوات وقتٍ صريحة.
  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapFooter(WidgetTester t, String label) async {
    final f = find.text(label).hitTestable();
    expect(f, findsOneWidget, reason: 'زرّ «$label»');
    await t.tap(f);
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
  }

  testWidgets('الفئات والرصيد، ولا شراء بلا تأكيدٍ بالمجموع، والحمولة بأرقامٍ عربيّة، ثمّ «وصلت»', (t) async {
    final bought = await openSheet(t);
    expect(find.text('رصيدك: 177,000 د.ع'), findsOneWidget);
    expect(find.textContaining('Economy +'), findsOneWidget);
    expect(find.textContaining('VPN'), findsOneWidget);
    // بلا فئة: الزرّ معطَّل.
    await t.tap(find.text('شراء').hitTestable());
    await t.pump();
    expect(server.purchases, isEmpty);

    await t.tap(find.byKey(const ValueKey('purchase-value-20000')));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('purchase-qty')), '٣');
    await t.pump();
    expect(find.text('المجموع 60,000 د.ع'), findsOneWidget);
    expect(find.text('رصيدك بعد الشراء: 117,000 د.ع'), findsOneWidget);

    await tapFooter(t, 'شراء');
    expect(server.purchases, isEmpty, reason: 'الضغطة الأولى تأكيدٌ لا شراء');
    await tapFooter(t, 'تأكيد الشراء — 60,000 د.ع');
    await settle(t);
    expect(server.purchases, hasLength(1));
    final body = server.purchases.single;
    expect([body['card_value'], body['quantity']], [20000, 3]);
    expect(body['request_id'], matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(body.containsKey('confirm_repeat'), isFalse);
    expect(bought, [1]);
    expect(find.textContaining('طُلب شراء 3 كارتات'), findsWidgets);
    // متابعة السجلّ: pending ثمّ finished ⇒ «وصلت».
    expect(find.text('قيد التجهيز… تظهر في كارتاتك حين تجهز'), findsOneWidget);
    server.finishAll();
    await t.pump(const Duration(seconds: 3));
    await settle(t);
    expect(find.text('وصلت الكارتات ✓ — تجدها في القائمة'), findsOneWidget);
    await t.pump(const Duration(seconds: 40));
  });

  testWidgets('«طلبتَ الشراء نفسه قبل دقائق» ⇒ «نعم، اشترِ مرّةً ثانية» بالمعرّف نفسه وconfirm_repeat', (t) async {
    server.replies = [
      (409, {'success': false, 'code': 'RECENT_DUPLICATE', 'message': 'طلبتَ كارتاً واحداً بالقيمة نفسها قبل دقائق — أكّد إن كنت تريد شراءً ثانياً'}),
    ];
    await openSheet(t);
    await t.tap(find.byKey(const ValueKey('purchase-value-1000')));
    await t.pump();
    await tapFooter(t, 'شراء');
    await tapFooter(t, 'تأكيد الشراء — 1,000 د.ع');
    await settle(t);
    expect(server.purchases, hasLength(1));
    await tapFooter(t, 'نعم، اشترِ مرّةً ثانية');
    await settle(t);
    expect(server.purchases, hasLength(2));
    expect(server.purchases[1]['request_id'], server.purchases[0]['request_id'], reason: 'لم يُرسَل شيء — النيّة نفسها');
    expect(server.purchases[1]['confirm_repeat'], isTrue);
    await t.pump(const Duration(seconds: 40));
  });

  testWidgets('غير المحسوم والانقطاع يُعادان بالمعرّف نفسه، والرفض النهائيّ يجدّده', (t) async {
    server.replies = [
      (409, {'success': false, 'code': 'OUTCOME_UNKNOWN', 'message': 'لم يتأكّد الشراء — راجع «سجل الشراء» بعد دقيقة قبل أن تعيد'}),
      null, // انقطاعٌ (رمية)
      (409, {'success': false, 'code': 'CARDS_PURCHASE_REJECTED', 'message': 'رصيدك لا يكفي لهذا الشراء — لم يُشترَ شيء'}),
    ];
    await openSheet(t);
    await t.tap(find.byKey(const ValueKey('purchase-value-17000')));
    await t.pump();
    Future<void> buy() async {
      await tapFooter(t, 'شراء');
      await tapFooter(t, 'تأكيد الشراء — 17,000 د.ع');
      await settle(t);
    }

    await buy();
    expect(find.textContaining('لم يتأكّد الشراء'), findsWidgets);
    await t.pump(const Duration(seconds: 5));
    await buy();
    await t.pump(const Duration(seconds: 5));
    await buy();
    expect(find.textContaining('رصيدك لا يكفي'), findsWidgets);
    await t.pump(const Duration(seconds: 5));
    await buy();
    final ids = server.purchases.map((b) => b['request_id']).toList();
    expect(ids, hasLength(4));
    expect(ids[1], ids[0], reason: 'غير المحسوم ⇒ المعرّف نفسه');
    expect(ids[2], ids[0], reason: 'الانقطاع ⇒ المعرّف نفسه');
    expect(ids[3], isNot(ids[0]), reason: 'الرفض حكمٌ نهائيّ ⇒ نيّةٌ جديدة');
    await t.pump(const Duration(seconds: 40));
  });

  testWidgets('العدد فوق الحدّ ⇒ الزرّ معطَّل والسبب ظاهر، وطلبٌ لم يتأكّد يُعرض من السجلّ', (t) async {
    server.pending = [
      {'value': 30000, 'qty': 2, 'total': 60000, 'at': '2026-10-29T18:00:00.000Z'},
    ];
    await openSheet(t);
    expect(find.text('طلبٌ لم يتأكّد: كارتان بـ30,000 د.ع — راجع السجلّ قبل أن تعيد'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('purchase-value-1000')));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('purchase-qty')), '21');
    await t.pump();
    expect(find.text('الحدّ للطلب الواحد 20 كارتاً'), findsOneWidget);
    await t.tap(find.text('شراء').hitTestable());
    await t.pump();
    expect(find.textContaining('تأكيد الشراء'), findsNothing);
    expect(server.purchases, isEmpty);
    await t.pump(const Duration(seconds: 40));
  });

  testWidgets('الكارتات: الزرّ يظهر حين يفتحه الخادم وحده (حتى بلا كارتات)', (t) async {
    server.options = {'success': true, 'enabled': false, 'hidden': true, 'reason': 'OFF'};
    await pumpApp(t, (_) => const CardsScreen());
    expect(find.byKey(const ValueKey('cards-purchase-open')), findsNothing);
    expect(find.text('هذا الحساب ما يستعمل كارتات'), findsOneWidget);

    server.options = _Server.enabledOptions;
    await pumpApp(t, (_) => const SizedBox.shrink());
    await pumpApp(t, (_) => const CardsScreen());
    expect(find.byKey(const ValueKey('cards-purchase-open')), findsOneWidget);
    expect(find.text('شراء كارتات'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('cards-purchase-open')));
    await t.pumpAndSettle();
    expect(find.text('رصيدك: 177,000 د.ع'), findsOneWidget);
    await t.pump(const Duration(seconds: 40));
  });

  test('الخيارات: المطفأ والموظّف والغريب لا يظهر، والرصيد الغائب «لا نعرف» لا صفر', () {
    expect(CardPurchaseOptions.fromJson({'enabled': false, 'hidden': true}).enabled, isFalse);
    final locked = CardPurchaseOptions.fromJson({'enabled': false, 'locked': true, 'message': 'لصاحب الحساب'});
    expect([locked.enabled, locked.locked, locked.message], [false, true, 'لصاحب الحساب']);
    expect(CardPurchaseOptions.fromJson({'enabled': true, 'values': [], 'max_qty': 5}).enabled, isFalse);
    expect(CardPurchaseOptions.fromJson({'enabled': 'true', 'values': [{'value': 1000}], 'max_qty': 5}).enabled, isFalse);
    final o = CardPurchaseOptions.fromJson({..._Server.enabledOptions, 'balance': null, 'balance_unavailable': true});
    expect(o.enabled, isTrue);
    expect(o.balance, isNull);
    expect(o.values.map((v) => v.value), [1000, 17000, 20000]);
  });
}

class _DiskLoader extends AssetLoader {
  const _DiskLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => Future.value(
        jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>,
      );
}

/// خادمٌ وهميّ بعقد شراء الكارتات (+ ملخّصٌ فارغ لشاشة الكارتات).
class _Server implements HttpClientAdapter {
  static const enabledOptions = <String, dynamic>{
    'success': true,
    'enabled': true,
    'title': 'شراء كروت',
    'values': [
      {'value': 1000, 'label': 'IQD 1,000 VPN', 'name': 'VPN'},
      {'value': 17000, 'label': 'IQD 17,000 Economy', 'name': 'Economy'},
      {'value': 20000, 'label': 'IQD 20,000 Economy +', 'name': 'Economy +'},
    ],
    'balance': 177000,
    'currency': 'IQD',
    'max_qty': 20,
    'max_total': 1000000,
  };

  Map<String, dynamic> options = enabledOptions;
  final purchases = <Map<String, dynamic>>[];

  /// ردود POST بالترتيب: (حالة، جسم) أو null = انقطاع؛ بعدها قبولٌ يضيف صفّاً «بالانتظار».
  List<(int, Map<String, dynamic>)?> replies = const [];
  final rows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> pending = const [];
  int _next = 500;

  void finishAll() {
    for (final r in rows) {
      r['status'] = 'finished';
    }
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final (int, Map<String, dynamic>) reply;
    final p = o.path;
    if (p == '/api/v2/cards/purchase/options') {
      reply = (200, options);
    } else if (p == '/api/v2/cards/purchase/history') {
      reply = (200, {'success': true, 'rows': rows.reversed.toList(), 'unconfirmed': pending});
    } else if (p == '/api/v2/cards/purchase' && o.method == 'POST') {
      final body = Map<String, dynamic>.from(o.data as Map);
      purchases.add(body);
      final i = purchases.length - 1;
      if (i < replies.length) {
        final r = replies[i];
        if (r == null) throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
        reply = r;
      } else {
        final id = _next++;
        final value = body['card_value'] as int;
        final qty = body['quantity'] as int;
        rows.add({'id': id, 'value': value, 'qty': qty, 'total': value * qty, 'status': 'pending', 'created_at': '2026-10-29 21:00:00'});
        reply = (200, {
          'success': true,
          'status': 'applied',
          'card_value': value,
          'quantity': qty,
          'total': value * qty,
          'purchase_id': id,
          'message': 'طُلب شراء $qty كارتات بقيمة $value د.ع — تجهز خلال لحظات وتظهر في كارتاتك',
        });
      }
    } else if (p == '/api/v2/cards/summary') {
      reply = (200, {'success': true, 'enabled': true, 'totals': {'qty': 0, 'used': 0, 'remaining': 0}, 'profiles': [], 'series': []});
    } else {
      reply = (404, {'success': false});
    }
    return ResponseBody.fromString(
      jsonEncode(reply.$2),
      reply.$1,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
