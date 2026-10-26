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
import 'package:rad_mysvcs/screens/cards/sheets/card_transfer_sheet.dart';
import 'package:rad_mysvcs/screens/cards/sheets/series_cards_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';

/// نقل الكارتات لمديرٍ فرعيّ (٢٧ أكتوبر) — شيت النقل كما يراه المدير (عربيّ، خطّ التطبيق، عرض ٣٦٠) أمام خادمٍ وهميّ
/// بعقد `/api/v2/cards/transfer-targets` و`…/range` و`…/transfer`.
///
/// ما يحرسه: لا نقل بلا تأكيد؛ الحمولة كما يفهمها الخادم (count أو to_card لا الاثنان)؛ الأرقام العربيّة تُقرأ؛ معرّف
/// الطلب ثابتٌ للنيّة الواحدة (الملتبس يُعاد بالمعرّف نفسه، والحكم النهائيّ يجدّده)؛ «لا مدراء فرعيّين» رسالةٌ لا زرّ.
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
    ApiClient.dio.httpClientAdapter = server;
    CardsState.reset();
  });

  final series = CardSeries.fromJson({
    'series': '2026-2',
    'type': 0,
    'profile_name': 'Economy',
    'value': 10000,
    'qty': 30,
    'used': 5,
    'remaining': 25,
  })!;

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

  /// يفتح شيت النقل ويحفظ نتيجته.
  Future<List<bool?>> openTransfer(WidgetTester t) async {
    final result = <bool?>[];
    await pumpApp(
      t,
      (c) => Center(
        child: TextButton(
          onPressed: () async => result.add(await showCardTransferSheet(c, series)),
          child: const Text('open'),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    return result;
  }

  Future<void> pickTarget(WidgetTester t, String name) async {
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    await t.tap(find.textContaining(name).last);
    await t.pumpAndSettle();
  }

  Future<void> drainSnack(WidgetTester t) async {
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
  }

  test('النماذج: transfer_enabled، والمستلمون الناقصون يُسقطون، والمدى الفارغ صفر، والأرقام العربيّة تُقرأ', () {
    expect(CardsSummary.fromJson({'success': true, 'enabled': true, 'transfer_enabled': true}).transferEnabled, isTrue);
    expect(CardsSummary.fromJson({'success': true, 'enabled': true}).transferEnabled, isFalse, reason: 'خادمٌ أقدم');
    expect(CardTransferTarget.fromJson({'id': '3273', 'username': 'cardtest@poox'})?.username, 'cardtest@poox');
    expect(CardTransferTarget.fromJson({'id': '', 'username': 'x'}), isNull);
    expect(CardTransferTarget.fromJson({'id': '7'}), isNull);
    final r = CardSeriesRange.fromJson({'start': 106, 'end': 130, 'length': 25});
    expect([r.start, r.end, r.length], [106, 130, 25]);
    final e = CardSeriesRange.fromJson({'start': null, 'end': null, 'length': 0});
    expect([e.start, e.end, e.length], [null, null, 0]);
    expect(CardSeriesRange.fromJson({'start': 9, 'end': 3, 'length': 4}).length, 0, reason: 'مدى مقلوب = لا شيء');
    expect(parseCardNumber('٣'), 3);
    expect(parseCardNumber(' 110 '), 110);
    expect(parseCardNumber('١٢'), 12);
    expect(parseCardNumber('x'), isNull);
    expect(parseCardNumber(''), isNull);
    expect(parseCardNumber('1.5'), isNull);
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(CardsApi.newTransferRequestId()), isTrue);
  });

  testWidgets('بالعدد: مستلمٌ + «٣» ⇒ معاينة، ثمّ «نقل» يطلب التأكيد، والتأكيد يرسل count وحده ويغلق', (t) async {
    final result = await openTransfer(t);
    expect(find.textContaining('25 كارتاً'), findsOneWidget, reason: 'المتاح من المدى الآن');
    await pickTarget(t, 'cardtest@poox');
    await t.enterText(find.byKey(const ValueKey('transfer-count')), '٣');
    await t.pumpAndSettle();
    expect(find.textContaining('سيُنقل 3 كارتات'), findsOneWidget);
    expect(find.text('لا تستطيع إرجاعها من حسابك بعد النقل.'), findsOneWidget);

    await t.tap(find.text('نقل'));
    await t.pumpAndSettle();
    expect(server.transferBodies, isEmpty, reason: 'لا نقل بلا تأكيد');
    expect(find.text('تأكيد نقل 3 كارتات'), findsOneWidget);

    await t.tap(find.text('تأكيد نقل 3 كارتات'));
    await t.pumpAndSettle();
    expect(server.transferBodies, hasLength(1));
    final b = server.transferBodies.single;
    expect(b['mode'], 'count');
    expect(b['to'], '3273');
    expect(b['count'], 3);
    expect(b.containsKey('to_card'), isFalse);
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch('${b['request_id']}'), isTrue);
    expect(result, [true], reason: 'نُقل ⇒ الشاشة تُحدَّث');
    await drainSnack(t);
  });

  testWidgets('حتى رقم كارت: من أوّل كارتٍ متبقٍّ (106) حتى 110 = خمسة، ويُرسل to_card وحده', (t) async {
    await openTransfer(t);
    await pickTarget(t, 'cardtest@poox');
    await t.tap(find.text('حتى رقم كارت'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('transfer-last')), '110');
    await t.pumpAndSettle();
    expect(find.textContaining('سيُنقل 5 كارتات'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('transfer-last')), '131');
    await t.pumpAndSettle();
    expect(find.textContaining('سيُنقل'), findsNothing, reason: 'خارج المدى ⇒ لا معاينة ولا زرّ فعّال');
    await t.enterText(find.byKey(const ValueKey('transfer-last')), '110');
    await t.pumpAndSettle();
    await t.tap(find.text('نقل'));
    await t.pumpAndSettle();
    await t.tap(find.text('تأكيد نقل 5 كارتات'));
    await t.pumpAndSettle();
    final b = server.transferBodies.single;
    expect([b['mode'], b['to_card'], b.containsKey('count')], ['range', 110, false]);
    await drainSnack(t);
  });

  testWidgets('الملتبس يُعاد بالمعرّف نفسه، والحكم النهائيّ يجدّده — لا نقل مرّتين بنيّةٍ واحدة', (t) async {
    server.transferReplies = [
      (409, {'success': false, 'code': 'OUTCOME_UNKNOWN', 'message': 'لم يتأكّد النقل — راجع كارتات المجموعة قبل أن تعيد'}),
      (400, {'success': false, 'code': 'BAD_COUNT', 'message': 'اختر عدداً من 1 إلى 25'}),
      (200, {'success': true, 'moved': 2, 'message': 'نُقل كارتان إلى cardtest@poox'}),
    ];
    await openTransfer(t);
    await pickTarget(t, 'cardtest@poox');
    await t.enterText(find.byKey(const ValueKey('transfer-count')), '2');
    await t.pumpAndSettle();
    Future<void> confirm() async {
      await t.tap(find.text('نقل'));
      await t.pumpAndSettle();
      await t.tap(find.text('تأكيد نقل كارتان'));
      await t.pumpAndSettle();
    }

    await confirm();
    expect(find.textContaining('لم يتأكّد النقل'), findsOneWidget);
    await drainSnack(t);
    await confirm();
    await drainSnack(t);
    await confirm();
    final ids = [for (final b in server.transferBodies) '${b['request_id']}'];
    expect(ids, hasLength(3));
    expect(ids[1], ids[0], reason: 'الملتبس ⇒ المعرّف نفسه');
    expect(ids[2] == ids[1], isFalse, reason: 'بعد حكمٍ نهائيّ (400) ⇒ نيّةٌ جديدة');
    await drainSnack(t);
  });

  testWidgets('لا مدراء فرعيّين: رسالةٌ بلا زرّ نقل', (t) async {
    server.targets = const [];
    await openTransfer(t);
    expect(find.text('لا مدراء فرعيّين في حسابك — تُنقل الكارتات لمدرائك الفرعيّين فقط.'), findsOneWidget);
    expect(find.text('نقل'), findsNothing);
  });

  testWidgets('شيت السلسلة: الزرّ يظهر بـcanTransfer وحده، والنقر يعيد true', (t) async {
    final result = <bool?>[];
    await pumpApp(
      t,
      (c) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(onPressed: () => showSeriesCardsSheet(c, series), child: const Text('plain')),
          TextButton(
            onPressed: () async => result.add(await showSeriesCardsSheet(c, series, canTransfer: true)),
            child: const Text('owner'),
          ),
        ],
      ),
    );
    await t.tap(find.text('plain'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('series-transfer')), findsNothing);
    await t.tapAt(const Offset(180, 20)); // خارج الشيت
    await t.pumpAndSettle();
    await t.tap(find.text('owner'));
    await t.pumpAndSettle();
    expect(find.text('نقل لمدير فرعيّ'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('series-transfer')));
    await t.pumpAndSettle();
    expect(result, [true]);
  });
}

class _DiskLoader extends AssetLoader {
  const _DiskLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => Future.value(
        jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>,
      );
}

/// خادمٌ وهميّ بعقد نقل الكارتات.
class _Server implements HttpClientAdapter {
  List<Map<String, dynamic>> targets = const [
    {'id': '3273', 'username': 'cardtest@poox'},
    {'id': '3300', 'username': 'ahmed.sub@poox'},
  ];
  List<(int, Map<String, dynamic>)> transferReplies = const [];
  final transferBodies = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final (int, Map<String, dynamic>) reply;
    final p = options.path;
    if (p == '/api/v2/cards/transfer-targets') {
      reply = (200, {'success': true, 'targets': targets});
    } else if (p == '/api/v2/cards/series/2026-2/range') {
      reply = (200, {'success': true, 'start': 106, 'end': 130, 'length': 25});
    } else if (p == '/api/v2/cards/series/2026-2' || p.startsWith('/api/v2/cards/series/2026-2?')) {
      reply = (200, {'success': true, 'cards': const [], 'total': 0, 'page': 1, 'count': 50});
    } else if (p == '/api/v2/cards/series/2026-2/transfer') {
      transferBodies.add(Map<String, dynamic>.from(options.data as Map));
      final i = transferBodies.length - 1;
      reply = i < transferReplies.length
          ? transferReplies[i]
          : (200, {'success': true, 'moved': 3, 'message': 'نُقل 3 كارتات إلى cardtest@poox'});
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
