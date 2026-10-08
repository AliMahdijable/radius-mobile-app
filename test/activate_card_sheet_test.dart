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
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';

/// §١٢ شيت التفعيل بالكارت — يُرسم كما يراه المدير: بالعربيّة وبخطّ التطبيق
/// الحقيقيّ وبعرض هاتف (٣٦٠)، أمام خادمٍ وهميّ يردّ بعقد الكارتات.
///
/// ما يحرسه: الرصيد افتراضيّ ولا يُرسَل معه `method`؛ الكارت يُرسَل
/// `method:'card'` وحده؛ «لا كارت» يمنع الزرّ؛ «تعذّرت القراءة» لا تمنعه؛
/// ورفض الخادم لا يقلب مصدر المال إلى الرصيد بصمت.
void main() {
  late _Server server;

  setUpAll(() async {
    await loadAppFonts();
    // نقرةٌ تقع على غير هدفها (الإشعار العائم فوق الزرّ مثلاً) تُنجح
    // الاختبار زوراً — فلتكن فشلاً لا تحذيراً.
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

  Map<String, dynamic> cardsData({
    bool credit = true,
    bool card = true,
    Object? available = 3,
  }) =>
      {
        'activation_methods': {'credit': credit, 'card': card},
        'cards': {
          'enabled': card,
          'profile_id': 4,
          'profile_name': 'Family',
          'available': available,
        },
      };

  /// يفتح الشيت وينتظر activation-data.
  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final sub = Subscriber.fromJson({
      'idx': '55',
      'username': 'ali@net',
      'firstname': 'علي',
      'lastname': 'حسن',
      'profile_id': 4,
      'profile_name': 'Family',
    });
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
          home: Scaffold(
            body: Builder(
              builder: (c) => Center(
                child: TextButton(
                  onPressed: () => showActivateSheet(c, sub),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  /// زرّ الشيت السفليّ بتسميته — والتسمية وحدها تقول أيّ طريقٍ سيُدفع.
  Finder footer(String label) => find.text(label);

  Future<void> submit(WidgetTester t, String label) async {
    await t.tap(footer(label));
    await t.pumpAndSettle();
  }

  /// يُفرغ مؤقّت الإشعار العائم قبل نهاية الاختبار.
  Future<void> drainSnack(WidgetTester t) async {
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
  }

  testWidgets('🚨 خادمٌ أقدم: لا قسم للكارت، والطلب بلا method كما كان',
      (t) async {
    await open(t);
    expect(find.text('طريقة التفعيل'), findsNothing);
    expect(find.text('طريقة الدفع'), findsOneWidget);
    await submit(t, 'تجديد الآن');
    final body = server.activateBodies.single;
    expect(body.containsKey('method'), isFalse);
    expect(body['paymentType'], 'non-cash');
    expect(find.text('تم التجديد بنجاح'), findsOneWidget);
    await drainSnack(t);
  });

  testWidgets('الطريقان: الرصيد مختار، والكارت يُرسل method=card', (t) async {
    server.activationExtra = cardsData(available: 3);
    server.activateReply = (
      200,
      {
        'success': true,
        'card': {
          'series': '2026-52224',
          'serial_tail': '4821',
          'profile_name': 'Family',
          'remaining': 2,
        },
      }
    );
    CardsState.set(const CardsBadge(enabled: true, remaining: 3));
    await open(t);

    expect(find.text('طريقة التفعيل'), findsOneWidget);
    expect(find.text('رصيد'), findsOneWidget);
    expect(find.text('كارت (3)'), findsOneWidget);
    // الرصيد افتراضيّ: لا سطر كارت، والزرّ «تجديد الآن».
    expect(find.textContaining('يُسحب كارت تلقائيّاً'), findsNothing);
    expect(footer('تجديد الآن'), findsOneWidget);

    await t.tap(find.text('كارت (3)'));
    await t.pumpAndSettle();
    expect(find.textContaining('يُسحب كارت تلقائيّاً'), findsOneWidget);
    expect(find.textContaining('Family'), findsWidgets);
    expect(t.takeException(), isNull);

    await submit(t, 'تجديد بكارت');
    final body = server.activateBodies.single;
    expect(body['method'], 'card');
    expect(body['paymentType'], 'non-cash', reason: 'نوع الدفع مستقلّ');
    expect(body.containsKey('pin'), isFalse);
    expect(find.textContaining('تم التجديد بكارت'), findsOneWidget);
    expect(find.textContaining('4821'), findsOneWidget);
    expect(CardsState.badge.value?.remaining, 2);
    // الشيت أُغلق بالنجاح.
    expect(find.text('طريقة التفعيل'), findsNothing);
    await drainSnack(t);
  });

  testWidgets('لا كارت لهذه الباقة: تحذيرٌ والزرّ معطّل، والرصيد متاح',
      (t) async {
    server.activationExtra = cardsData(available: 0);
    await open(t);
    await t.tap(find.text('كارت (0)'));
    await t.pumpAndSettle();
    expect(find.textContaining('ما عندك كارت لباقة'), findsOneWidget);
    expect(footer('ما عندك كارت لهالباقة'), findsOneWidget);
    await t.tap(footer('ما عندك كارت لهالباقة'));
    await t.pumpAndSettle();
    expect(server.activateBodies, isEmpty, reason: 'الزرّ معطّل');

    await t.tap(find.text('رصيد'));
    await t.pumpAndSettle();
    expect(footer('تجديد الآن'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('الكارت وحده: مختارٌ بلا بلاطات', (t) async {
    server.activationExtra = cardsData(credit: false, available: 2);
    await open(t);
    expect(find.text('طريقة التفعيل'), findsOneWidget);
    expect(find.text('رصيد'), findsNothing);
    expect(find.textContaining('يُسحب كارت تلقائيّاً'), findsOneWidget);
    expect(footer('تجديد بكارت'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('🚨 تعذّرت القراءة: ليست صفراً — مسموح، و«جرّب مجدّداً» يعيد',
      (t) async {
    server.activationExtra = cardsData(available: null);
    await open(t);
    await t.tap(find.text('كارت'));
    await t.pumpAndSettle();
    expect(find.text('تعذّر قراءة الكارتات — جرّب مجدّداً'), findsOneWidget);
    expect(footer('تجديد بكارت'), findsOneWidget, reason: 'غير ممنوع');

    server.activationExtra = cardsData(available: 5);
    await t.tap(find.text('تعذّر قراءة الكارتات — جرّب مجدّداً'));
    await t.pumpAndSettle();
    expect(server.activationDataCalls, 2);
    expect(find.textContaining('يُسحب كارت تلقائيّاً'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('رفض NO_CARDS: رسالة، والشيت يصير «لا كارت» ويبقى مفتوحاً',
      (t) async {
    server.activationExtra = cardsData(available: 3);
    server.activateReply = (
      409,
      {
        'success': false,
        'code': 'NO_CARDS',
        'message': 'ما عندك كارت متاح لباقة «Family»',
      }
    );
    await open(t);
    await t.tap(find.text('كارت (3)'));
    await t.pumpAndSettle();
    await submit(t, 'تجديد بكارت');
    expect(find.textContaining('ما عندك كارت متاح لباقة'), findsOneWidget);
    expect(find.textContaining('ما عندك كارت لباقة'), findsOneWidget);
    expect(footer('ما عندك كارت لهالباقة'), findsOneWidget);
    expect(find.text('طريقة التفعيل'), findsOneWidget, reason: 'لم يُغلق');
    await drainSnack(t);
    await t.tap(footer('ما عندك كارت لهالباقة'));
    await t.pumpAndSettle();
    expect(server.activateBodies, hasLength(1), reason: 'لا ضغطة ثانية');
  });

  testWidgets('🚨 رفض CARD_NOT_ALLOWED لا يقلب إلى الرصيد بصمت', (t) async {
    server.activationExtra = cardsData(available: 3);
    server.activateReply = (
      403,
      {
        'success': false,
        'code': 'CARD_NOT_ALLOWED',
        'message': 'حسابك في الساس لا يملك صلاحيّة التفعيل بالكارت',
      }
    );
    await open(t);
    await t.tap(find.text('كارت (3)'));
    await t.pumpAndSettle();
    await submit(t, 'تجديد بكارت');
    expect(
      find.text('حسابك في الساس لا يملك صلاحيّة التفعيل بالكارت'),
      findsNWidgets(2),
      reason: 'الإشعار العائم وسطر الكارت',
    );
    expect(footer('حسابك ما يسمح بالكارت'), findsOneWidget);
    await drainSnack(t);
    await t.tap(footer('حسابك ما يسمح بالكارت'));
    await t.pumpAndSettle();
    expect(server.activateBodies, hasLength(1), reason: 'لا ضغطة ثانية');

    // المدير يختار الرصيد بنفسه — ولا شيء قبل ذلك يغيّر المصدر.
    await t.tap(find.text('رصيد'));
    await t.pumpAndSettle();
    expect(footer('تجديد الآن'), findsOneWidget);
    await submit(t, 'تجديد الآن');
    expect(server.activateBodies.last.containsKey('method'), isFalse);
    await drainSnack(t);
  });
}

/// الترجمات من القرص مباشرةً — بلا `rootBundle`، فتعمل داخل وقت الاختبار.
///
/// ⚠️ `Future.value` لا `SynchronousFuture`: المكتبة تجمع المحمّلات بـ
/// `Future.wait`، وهو يُسقط قيمة المستقبل المتزامن (يُنادى قبل أن يحجز
/// خانتها) فتصل الترجمات فارغةً وتظهر المفاتيح بدل النصوص.
class _DiskLoader extends AssetLoader {
  const _DiskLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) =>
      Future.value(jsonDecode(
        File('assets/translations/${locale.languageCode}.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>);
}

/// خادمٌ وهميّ: activation-data وactivate بعقد الكارتات.
class _Server implements HttpClientAdapter {
  Map<String, dynamic> activationExtra = const {};
  (int, Map<String, dynamic>) activateReply = (200, {'success': true});
  final _requests = <RequestOptions>[];

  int get activationDataCalls =>
      _requests.where((r) => r.path.endsWith('/activation-data')).length;

  List<Map<String, dynamic>> get activateBodies => _requests
      .where((r) => r.path.endsWith('/activate'))
      .map((r) => Map<String, dynamic>.from(r.data as Map))
      .toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _requests.add(options);
    final (int, Map<String, dynamic>) reply;
    if (options.path == '/api/v2/subscribers/55/activation-data') {
      reply = (
        200,
        {
          'success': true,
          'data': {
            'user_price': 46000,
            'price_after_discount': 46000,
            'profile_name': 'Family',
            'profile_duration': '30',
            'current_balance': 0,
            'manager_balance': 0,
            ...activationExtra,
          },
        }
      );
    } else if (options.path == '/api/v2/subscribers/55/activate') {
      reply = activateReply;
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
