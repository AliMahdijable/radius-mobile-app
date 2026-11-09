import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/extend_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/pay_debt_sheet.dart';
import 'package:rad_mysvcs/services/phone_output.dart';
import 'package:rad_mysvcs/services/print_output.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';
import 'support/fake_receipt_printer.dart';

/// مراجعة 179 الثانية (٩ نوفمبر) — «الحاجز»: ورقة التفعيل/التمديد/التسديد كانت تُغلق نفسها بـ`pop(true)` فور الطباعة،
/// وورقة سبب طابعة الوصولات مفتوحةٌ فوقها لتوّها — فأغلق ذلك الـ`pop` ورقةَ السبب بـ«نعم»: الوصل المدفوع يُطبع ثانيةً بلا
/// نقرة، و«غير مؤكَّد» لا يُرى، وورقة العمليّة تبقى مفتوحة.
///
/// الأوراق الحقيقيّة أمام خادمٍ وهميّ وطابعة بلوتوث وهميّة تنقطع أثناء الوصل («غير مؤكَّد»)، بالمسار كما على الهاتف:
/// نجاح العمليّة ⇒ نافذة «اطبع على …» ⇒ الطابعة ⇒ ورقة السبب. لكلّ عمليّة:
///   ١. «غير مؤكَّد» يظهر، ولا طباعة ثانية حتى يُغلق؛ و«إغلاق» يُغلق ورقة العمليّة نفسها (true) بلا طباعة ثانية.
///   ٢. «إعادة الطباعة» بنقرة ⇒ طباعةٌ ثانية واحدة، ثمّ تُغلق ورقة العمليّة.
///   ٣. `pop(true)` من غير ورقة السبب (ما فعله الـpop القديم) لا يُفهم «إعادة الطباعة».
void main() {
  late _Server server;
  late ReceiptPrinterHarness h;
  final navKey = GlobalKey<NavigatorState>();

  setUpAll(() async {
    await loadAppFonts();
    // خطّ الوصل (PDF) يُحمَّل مرّةً هنا لا داخل الوقت المزيّف للاختبار.
    await PdfFonts.theme();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({'auth.admin_id': '1', 'auth.admin_username': 'agent1'});
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    ReceiptSettingsApi.clearCache();
    server = _Server();
    ApiClient.dio.httpClientAdapter = server;
    h = ReceiptPrinterHarness()..useBluetooth();
    // الكتابات: ١ سؤال الورق · ٢ ESC @ · ٣ الشريط الأوّل · ٤ الثاني ← ينقطع هنا (بعد شريطٍ مُرسل: «غير مؤكَّد»)
    h.bridge.dropAtWrite = 4;
    PhoneOutput.debugActive = true;
    PhoneOutput.navigatorKey = navKey;
  });

  tearDown(() {
    h.restore();
    PhoneOutput.debugActive = null;
    PhoneOutput.navigatorKey = null;
    ReceiptSettingsApi.clearCache();
  });

  final sub = Subscriber.fromJson({
    'idx': '55',
    'username': 'ali@net',
    'firstname': 'علي',
    'lastname': 'حسن',
    'profile_id': 4,
    'profile_name': 'Family',
    'notes': '-25000',
  });

  /// يفتح الورقة كما من صفحة المشترك ويعيد ما تُغلق به.
  Future<ValueNotifier<Object?>> open(WidgetTester t, Future<bool?> Function(BuildContext) show) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final closedWith = ValueNotifier<Object?>(#open);
    await t.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('ar'), Locale('en')],
      path: 'assets/translations',
      startLocale: const Locale('ar'),
      fallbackLocale: const Locale('ar'),
      saveLocale: false,
      assetLoader: const _DiskLoader(),
      child: Builder(
        builder: (ctx) => MaterialApp(
          navigatorKey: navKey,
          locale: ctx.locale,
          supportedLocales: ctx.supportedLocales,
          localizationsDelegates: ctx.localizationDelegates,
          home: Scaffold(
            body: Builder(
              builder: (c) => Center(
                child: TextButton(
                  onPressed: () async => closedWith.value = await show(c),
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
    return closedWith;
  }

  /// ما يجري خارج الوقت المزيّف (بناء PDF الوصل) — يُنتظر حقيقةً حتى يظهر [f] (أو تنقضي المهلة).
  Future<void> settleUntil(WidgetTester t, Finder f, {bool gone = false}) async {
    for (var i = 0; i < 100 && f.evaluate().isEmpty != gone; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.pumpAndSettle();
  }

  /// ينفّذ العمليّة بزرّها ويختار «اطبع على «MPT-II»» ⇒ الطابعة تنقطع أثناء الوصل.
  Future<void> runAndPrint(WidgetTester t, String submit) async {
    await t.tap(find.text(submit));
    final choice = find.byKey(const ValueKey('output-receipt-printer'));
    await settleUntil(t, choice);
    expect(choice, findsOneWidget, reason: 'نافذة «اطبع على …»');
    await t.tap(choice);
    await settleUntil(t, find.text('الطباعة غير مؤكَّدة'));
    // إشعار نجاح العمليّة (٣ ث) فوق أزرار الورقة — يمضي قبل النقر كما ينتظره الوكيل.
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
  }

  Finder problemClose() => find.widgetWithText(SheetSecondaryButton, 'إغلاق');

  /// الإشعار وتشخيص الفشل (مهلته ٦ ث) ينقضيان.
  Future<void> drain(WidgetTester t) async {
    await t.pump(const Duration(seconds: 7));
    await t.pumpAndSettle();
  }

  final flows = <(String, Future<bool?> Function(BuildContext), String, String)>[
    ('التفعيل', (c) => showActivateSheet(c, sub), 'تجديد الآن', 'activate'),
    ('التمديد', (c) => showExtendSheet(c, sub), 'تمديد الآن', 'extend'),
    ('التسديد', (c) => showPayDebtSheet(c, sub, initialAmount: 10000), 'تسديد الآن', 'pay-debt'),
  ];

  for (final (name, show, submit, op) in flows) {
    testWidgets('$name ١: «غير مؤكَّد» يظهر بلا طباعةٍ ثانية، و«إغلاق» يُغلق ورقة العمليّة (true)', (t) async {
      final closed = await open(t, show);
      await runAndPrint(t, submit);
      expect(server.ops(op), 1);
      expect(h.bridge.connects, 1);
      expect(find.text('الطباعة غير مؤكَّدة'), findsOneWidget, reason: 'السبب يُرى — لم يُغلقه pop العمليّة');
      expect(find.textContaining('قد يكون خرج جزءٌ من الوصل'), findsOneWidget);
      expect(find.text(submit), findsOneWidget, reason: 'ورقة العمليّة تحته تنتظر قرار الوكيل');
      expect(closed.value, #open);
      await t.tap(problemClose());
      await t.pumpAndSettle();
      expect(find.text('الطباعة غير مؤكَّدة'), findsNothing);
      expect(find.text(submit), findsNothing, reason: 'ورقة العمليّة أُغلقت بـpop نفسه');
      expect(closed.value, isTrue);
      expect(h.bridge.connects, 1, reason: 'لا طباعة ثانية بلا نقرة');
      expect(server.ops(op), 1, reason: 'العمليّة نفسها مرّة');
      await drain(t);
      expect(h.bridge.connects, 1);
      expect(t.takeException(), isNull);
    });

    testWidgets('$name ٢: «إعادة الطباعة» بنقرة ⇒ طباعةٌ ثانيةٌ واحدة، ثمّ تُغلق ورقة العمليّة', (t) async {
      final closed = await open(t, show);
      await runAndPrint(t, submit);
      expect(h.bridge.connects, 1);
      await t.tap(find.text('إعادة الطباعة'));
      await settleUntil(t, find.text('الطباعة غير مؤكَّدة'), gone: true);
      expect(h.bridge.connects, 2);
      expect(find.text('الطباعة غير مؤكَّدة'), findsNothing);
      expect(find.textContaining('أُرسل'), findsWidgets, reason: 'نتيجة الإعادة تُقال');
      expect(find.text(submit), findsNothing);
      expect(closed.value, isTrue);
      expect(server.ops(op), 1);
      await drain(t);
      expect(h.bridge.connects, 2);
      expect(t.takeException(), isNull);
    });

    testWidgets('$name ٣: pop(true) من غير ورقة السبب لا يُفهم «إعادة الطباعة»', (t) async {
      final closed = await open(t, show);
      await runAndPrint(t, submit);
      expect(find.text('الطباعة غير مؤكَّدة'), findsOneWidget);
      // ما فعله pop ورقة العمليّة القديم: «نعم» على أعلى ورقة.
      navKey.currentState!.pop(true);
      await t.pumpAndSettle();
      expect(h.bridge.connects, 1, reason: 'لا طباعة ثانية');
      expect(h.permission.opened, 0, reason: 'ولا فتح إعدادات');
      expect(find.text(submit), findsNothing);
      expect(closed.value, isTrue);
      await drain(t);
      expect(h.bridge.connects, 1);
      expect(t.takeException(), isNull);
    });
  }
}

class _DiskLoader extends AssetLoader {
  const _DiskLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => Future.value(
        jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>,
      );
}

/// خادمٌ وهميّ: بيانات التفعيل/التمديد، والعمليّات تنجح، وإعدادات الوصل «الطباعة التلقائيّة» (الخانة معلَّمة).
class _Server implements HttpClientAdapter {
  final _requests = <RequestOptions>[];

  int ops(String op) => _requests.where((r) => r.method == 'POST' && r.path == '/api/v2/subscribers/55/$op').length;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    _requests.add(options);
    final (int, Map<String, dynamic>) reply = switch (options.path) {
      '/api/v2/subscribers/55/activation-data' => (
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
            },
          }
        ),
      '/api/v2/subscribers/55/extension-options' => (
          200,
          {
            'success': true,
            'data': {
              'packages': [
                {'id': 7, 'name': 'Family', 'price': 30000, 'duration': '30'},
              ],
              'manager_balance': 100000,
              'reward_points_balance': 0,
              'current_profile_name': 'Basic',
            },
          }
        ),
      '/api/v2/subscribers/55/activate' ||
      '/api/v2/subscribers/55/extend' ||
      '/api/v2/subscribers/55/pay-debt' =>
        (200, {'success': true}),
      '/api/v2/receipt-settings' => (
          200,
          {
            'success': true,
            'data': {'auto_print': true, 'show_qr': false},
          }
        ),
      _ => (404, {'success': false}),
    };
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
