import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/earthlink_api.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/add_subscriber_sheet.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/services/subscriber_events.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';

/// شيت «مشترك جديد» لايرث لنك — مالٌ حقيقيّ: الرصيد/الكارت يُشحنان على
/// الوكيل، ودفترنا يسجّل دين المشترك. يُرسم بالعربيّة وبخطّ التطبيق وبعرض
/// هاتف (٣٦٠) أمام خادمٍ وهميّ بعقد `POST /api/v2/subscribers`.
///
/// ما يحرسه:
///   • «ربّما أُضيف» (CREATE_UNCONFIRMED · CREATE_LATE_SUSPECTED) يُقفل الزرّ
///     ويُحدّث القائمة، ورسالة الخادم (بمبلغ الدين) باقيةٌ كاملةً فوق الزرّ
///     بعد زوال الإشعار.
///   • USERNAME_TAKEN العاديّ خطأٌ عاديّ بلا قفل.
///   • السحب للأسفل أثناء الإضافة لا يُغلق الشيت؛ وإن أُزيل الشيت بغيره
///     فالنتيجة تُعرض على الطبقة العليا والقائمة تتحدّث.
///   • الشيت يُختار بمعرّف المدير المحفوظ أوّلاً — علم المزوّد العالق لا
///     يفتح شيت ايرث لنك لمدير SAS4.
const _subtitleEl = 'إضافة مشترك على ايرث لنك';
const _subtitleSas = 'أدخل بيانات المشترك';
const _submitLabel = 'إضافة المشترك';
const _lockedLabel = 'راجع قائمة المشتركين أوّلاً';

/// رسالتان طويلتان ومبلغ الدين في آخرهما — قصّهما يُسقط المبلغ.
const _unconfirmedMsg = 'تعذّر تأكيد إنشاء المشترك ali1 — لم يصل ردٌّ من '
    'ايرث لنك ولم تحسم إعادة الفحص. راجع قائمة المشتركين قبل أيّ محاولة، '
    'وإن ظهر فيها فسجّل عليه ديناً يدويّاً بمبلغ 35,000 د.ع';
const _lateMsg = 'يبدو أنّ إضافة ali1 السابقة مرّت متأخّرة عند ايرث لنك — '
    'لا تُضِفه باسمٍ آخر. راجع قائمة المشتركين، وإن ظهر فسجّل عليه ديناً '
    'يدويّاً بمبلغ 35,000 د.ع';

void main() {
  late _Server server;
  late GlobalKey<NavigatorState> navKey;

  setUpAll(() async {
    await loadAppFonts();
    // نقرةٌ تقع على غير هدفها (الإشعار العائم فوق الزرّ مثلاً) تُنجح
    // الاختبار زوراً — فلتكن فشلاً لا تحذيراً.
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({'auth.admin_id': 'earthlink:5'});
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    ProviderService.debugSet(null);
    server = _Server();
    ApiClient.dio.httpClientAdapter = server;
    navKey = GlobalKey<NavigatorState>();
  });

  /// يفتح الشيت عبر `showAddSubscriberSheet` (اختيار الشيت + خيارات الفتح).
  Future<void> open(WidgetTester t) async {
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
          navigatorKey: navKey,
          locale: ctx.locale,
          supportedLocales: ctx.supportedLocales,
          localizationsDelegates: ctx.localizationDelegates,
          home: Scaffold(
            body: Builder(
              builder: (c) => Center(
                child: TextButton(
                  onPressed: () => showAddSubscriberSheet(c),
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

  /// يملأ ما يلزم لإضافةٍ برصيد أونلاين (الطريقة الافتراضيّة).
  Future<void> fill(WidgetTester t) async {
    await t.enterText(find.widgetWithText(TextField, 'الاسم'), 'علي');
    await t.enterText(
        find.widgetWithText(TextField, '07XX XXX XXXX'), '07701234567');
    await t.enterText(find.widgetWithText(TextField, 'ahmed'), 'ali1');
    await t.enterText(find.widgetWithText(TextField, '••••••••'), 'pw123456');
    await t.enterText(
        find.widgetWithText(TextField, 'باسورد الإيداع'), 'dep-pass');
    // فحص الاسم مؤجَّل ٥٠٠ms.
    await t.pump(const Duration(milliseconds: 600));
    await t.pumpAndSettle();
    final pickPackage = find.text('اختر الباقة');
    await t.ensureVisible(pickPackage);
    await t.pumpAndSettle();
    await t.tap(pickPackage);
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Economy').last);
    await t.pumpAndSettle();
    expect(find.text(_submitLabel), findsOneWidget);
    expect(t.takeException(), isNull);
  }

  Future<void> submit(WidgetTester t) async {
    await t.tap(find.text(_submitLabel));
    await t.pumpAndSettle();
  }

  /// يُفرغ مؤقّتات الإشعارات العائمة قبل نهاية الاختبار.
  Future<void> drainSnacks(WidgetTester t) async {
    await t.pump(const Duration(seconds: 25));
    await t.pumpAndSettle();
  }

  /// النصّ كاملاً بلا قصٍّ وبأكثر من سطر — لا يسقط مبلغ الدين.
  void expectWhole(WidgetTester t, Finder text) {
    final p = t.renderObject<RenderParagraph>(text);
    expect(p.didExceedMaxLines, isFalse, reason: 'لا قصّ');
    expect(p.size.height, greaterThan(40), reason: 'سطورٌ عدّة لا سطرٌ واحد');
  }

  group('النتيجة', () {
    testWidgets(
        '🚨 CREATE_UNCONFIRMED: قفل + تحديث القائمة، والرسالة باقيةٌ فوق '
        'الزرّ بعد زوال الإشعار', (t) async {
      server.createReply = (
        503,
        {
          'success': false,
          'code': 'CREATE_UNCONFIRMED',
          'message': _unconfirmedMsg,
        }
      );
      await open(t);
      await fill(t);
      final before = SubscriberEvents.dataChanged.value;
      await submit(t);

      expect(server.createBodies, hasLength(1));
      expect(SubscriberEvents.dataChanged.value, before + 1,
          reason: 'القائمة تُحدَّث');
      expect(find.text(_lockedLabel), findsOneWidget);
      expect(find.text(_unconfirmedMsg), findsNWidgets(2),
          reason: 'الإشعار العائم وسطر القفل');

      await t.pump(const Duration(seconds: 9));
      await t.pumpAndSettle();
      expect(find.text(_unconfirmedMsg), findsOneWidget,
          reason: 'زال الإشعار وبقي السطر');
      expectWhole(t, find.text(_unconfirmedMsg));
      expect(find.text(_subtitleEl), findsOneWidget, reason: 'لم يُغلق');

      await t.tap(find.text(_lockedLabel));
      await t.pumpAndSettle();
      expect(server.createBodies, hasLength(1), reason: 'لا ضغطة ثانية');
      expect(t.takeException(), isNull);
      await drainSnacks(t);
    });

    testWidgets('🚨 CREATE_LATE_SUSPECTED (200): كـCREATE_UNCONFIRMED تماماً',
        (t) async {
      server.createReply = (
        200,
        {
          'success': false,
          'code': 'CREATE_LATE_SUSPECTED',
          'message': _lateMsg,
        }
      );
      await open(t);
      await fill(t);
      final before = SubscriberEvents.dataChanged.value;
      await submit(t);

      expect(SubscriberEvents.dataChanged.value, before + 1);
      expect(find.text(_lockedLabel), findsOneWidget);
      await t.pump(const Duration(seconds: 9));
      await t.pumpAndSettle();
      expect(find.text(_lateMsg), findsOneWidget);
      expectWhole(t, find.text(_lateMsg));

      await t.tap(find.text(_lockedLabel));
      await t.pumpAndSettle();
      expect(server.createBodies, hasLength(1), reason: 'لا ضغطة ثانية');
      expect(t.takeException(), isNull);
      await drainSnacks(t);
    });

    testWidgets('USERNAME_TAKEN: خطأٌ عاديّ — لا قفل ولا سطر', (t) async {
      server.createReply = (
        200,
        {
          'success': false,
          'code': 'USERNAME_TAKEN',
          'message': 'اسم الدخول مستخدم — اختر اسماً آخر',
        }
      );
      await open(t);
      await fill(t);
      final before = SubscriberEvents.dataChanged.value;
      await submit(t);

      expect(find.text('اسم الدخول مستخدم — اختر اسماً آخر'), findsOneWidget);
      expect(find.text(_lockedLabel), findsNothing);
      expect(find.text(_submitLabel), findsOneWidget);
      expect(SubscriberEvents.dataChanged.value, before);
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(find.text('اسم الدخول مستخدم — اختر اسماً آخر'), findsNothing);
      expect(t.takeException(), isNull);
      await drainSnacks(t);
    });

    testWidgets('نجاحٌ وفشل الدفتر: يُغلق، ثمّ النجاح ثمّ تنبيه الدين',
        (t) async {
      server.createReply = (
        200,
        {
          'success': true,
          'data': {'username': 'ali1@el', 'idx': 9},
          'debt_write': {'ok': false, 'message': 'لم يُسجَّل دين ali1'},
        }
      );
      await open(t);
      await fill(t);
      await submit(t);
      expect(find.text(_subtitleEl), findsNothing, reason: 'أُغلق بالنجاح');
      expect(find.text('تمت إضافة المشترك'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      expect(find.text('لم يُسجَّل دين ali1'), findsOneWidget);
      expect(t.takeException(), isNull);
      await drainSnacks(t);
    });
  });

  group('أثناء الإضافة', () {
    testWidgets('🚨 السحب للأسفل لا يُغلق الشيت، والنتيجة تصل', (t) async {
      server.gate = Completer<void>();
      server.createReply = (
        503,
        {
          'success': false,
          'code': 'CREATE_UNCONFIRMED',
          'message': _unconfirmedMsg,
        }
      );
      await open(t);
      await fill(t);
      await t.tap(find.text(_submitLabel));
      await t.pump();
      expect(find.text('جاري الإضافة...'), findsOneWidget);

      await t.drag(find.text(_subtitleEl), const Offset(0, 500));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text(_subtitleEl), findsOneWidget, reason: 'لم يُغلق');

      server.gate!.complete();
      await t.pumpAndSettle();
      expect(find.text(_lockedLabel), findsOneWidget);
      await t.pump(const Duration(seconds: 9));
      await t.pumpAndSettle();
      expect(find.text(_unconfirmedMsg), findsOneWidget);
      expect(t.takeException(), isNull);
      await drainSnacks(t);
    });

    testWidgets(
        '🚨 أُزيل الشيت أثناءها: «ربّما أُضيف» على الطبقة العليا (أطول) '
        'والقائمة تتحدّث', (t) async {
      server.gate = Completer<void>();
      server.createReply = (
        503,
        {
          'success': false,
          'code': 'CREATE_UNCONFIRMED',
          'message': _unconfirmedMsg,
        }
      );
      await open(t);
      await fill(t);
      await t.tap(find.text(_submitLabel));
      await t.pump();
      // إزالةٌ برمجيّة (خروجٌ قسريّ، توجيه إشعار…) — `pop` لا يسأل PopScope.
      navKey.currentState!.pop();
      await t.pumpAndSettle();
      expect(find.text(_subtitleEl), findsNothing);

      final before = SubscriberEvents.dataChanged.value;
      server.gate!.complete();
      await t.pumpAndSettle();
      expect(SubscriberEvents.dataChanged.value, before + 1);
      expect(find.text(_unconfirmedMsg), findsOneWidget);
      await t.pump(const Duration(seconds: 12));
      await t.pumpAndSettle();
      expect(find.text(_unconfirmedMsg), findsOneWidget,
          reason: 'لا سطر قفلٍ يحملها بعد الآن — فيطول الإشعار');
      await t.pump(const Duration(seconds: 9));
      await t.pumpAndSettle();
      expect(find.text(_unconfirmedMsg), findsNothing);
      expect(t.takeException(), isNull);
      await drainSnacks(t);
    });

    testWidgets('أُزيل الشيت ثمّ نجح وفشل الدفتر: النجاح ثمّ تنبيه الدين',
        (t) async {
      server.gate = Completer<void>();
      server.createReply = (
        200,
        {
          'success': true,
          'data': {'username': 'ali1@el', 'idx': null, 'confirmed_by': 'recheck'},
          'debt_write': {'ok': false, 'message': 'لم يُسجَّل دين ali1'},
        }
      );
      await open(t);
      await fill(t);
      await t.tap(find.text(_submitLabel));
      await t.pump();
      navKey.currentState!.pop();
      await t.pumpAndSettle();

      final before = SubscriberEvents.dataChanged.value;
      server.gate!.complete();
      await t.pumpAndSettle();
      expect(SubscriberEvents.dataChanged.value, before + 1);
      expect(find.text('تمت إضافة المشترك'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      expect(find.text('لم يُسجَّل دين ali1'), findsOneWidget);
      expect(t.takeException(), isNull);
      await drainSnacks(t);
    });
  });

  group('اختيار الشيت', () {
    testWidgets('🚨 علم المزوّد العالق لا يفتح شيت ايرث لنك لمدير SAS4',
        (t) async {
      FlutterSecureStorage.setMockInitialValues({'auth.admin_id': '123'});
      ProviderService.debugSet('earthlink');
      await open(t);
      expect(find.text(_subtitleSas), findsOneWidget);
      expect(find.text(_subtitleEl), findsNothing);
      expect(server.createOptionsCalls, 0);
    });

    testWidgets('معرّف ايرث لنك يفتح شيته ولو لم يُضبط العلم', (t) async {
      await open(t);
      expect(find.text(_subtitleEl), findsOneWidget);
      expect(server.createOptionsCalls, 1);
    });

    testWidgets('بلا معرّف: العلم احتياطٌ', (t) async {
      FlutterSecureStorage.setMockInitialValues({});
      ProviderService.debugSet('earthlink');
      await open(t);
      expect(find.text(_subtitleEl), findsOneWidget);
    });

    testWidgets('بلا معرّف ولا علم: شيت SAS4', (t) async {
      FlutterSecureStorage.setMockInitialValues({});
      await open(t);
      expect(find.text(_subtitleSas), findsOneWidget);
    });
  });

  group('تحليل الردّ', () {
    test('CREATE_LATE_SUSPECTED (200) غير مؤكّد ورسالته باقية', () {
      final r = EarthlinkApi.createResultFromBody({
        'success': false,
        'code': 'CREATE_LATE_SUSPECTED',
        'message': _lateMsg,
      });
      expect(r.ok, isFalse);
      expect(r.unclear, isTrue);
      expect(r.message, _lateMsg);
    });

    test('USERNAME_TAKEN وPRICE_UNKNOWN رفضٌ مؤكّد', () {
      for (final code in ['USERNAME_TAKEN', 'PRICE_UNKNOWN']) {
        final r = EarthlinkApi.createResultFromBody(
            {'success': false, 'code': code, 'message': 'x'});
        expect(r.unclear, isFalse, reason: code);
      }
    });

    test('CREATE_LATE_SUSPECTED رميةً (5xx) غير مؤكّد ورسالته باقية', () {
      final req = RequestOptions(path: '/api/v2/subscribers');
      final r = EarthlinkApi.createResultFromError(DioException(
        requestOptions: req,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: req,
          statusCode: 503,
          data: {
            'success': false,
            'code': 'CREATE_LATE_SUSPECTED',
            'message': _lateMsg,
          },
        ),
      ));
      expect(r.unclear, isTrue);
      expect(r.message, _lateMsg);
    });

    test('EL_UNAVAILABLE فشلٌ مؤكّد تُسمح إعادته', () {
      expect(
        EarthlinkApi.createUnclear(
            status: 503, envelope: true, code: 'EL_UNAVAILABLE'),
        isFalse,
      );
    });
  });
}

/// الترجمات من القرص مباشرةً — بلا `rootBundle`، فتعمل داخل وقت الاختبار.
///
/// ⚠️ `Future.value` لا `SynchronousFuture`: المكتبة تجمع المحمّلات بـ
/// `Future.wait`، وهو يُسقط قيمة المستقبل المتزامن فتصل الترجمات فارغةً.
class _DiskLoader extends AssetLoader {
  const _DiskLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) =>
      Future.value(jsonDecode(
        File('assets/translations/${locale.languageCode}.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>);
}

/// خادمٌ وهميّ بعقد إضافة مشترك ايرث لنك. [gate] يُمسك ردّ الإضافة حتى
/// يُكمَل — لما يجري **أثناء** الانتظار.
class _Server implements HttpClientAdapter {
  (int, Map<String, dynamic>) createReply = (200, {'success': true});
  Completer<void>? gate;
  final _requests = <RequestOptions>[];

  int get createOptionsCalls =>
      _requests.where((r) => r.path == '/api/v2/el/create-options').length;

  List<Map<String, dynamic>> get createBodies => _requests
      .where((r) => r.method == 'POST' && r.path == '/api/v2/subscribers')
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
    if (options.path == '/api/v2/el/create-options') {
      reply = (
        200,
        {
          'success': true,
          'data': {
            'user_suffix': '@el',
            'packages': [
              {'id': '7', 'name': 'Economy', 'price': 35000, 'cost_price': 20000},
            ],
            'deposit_balance': 100000,
            'test_count': 0,
            'methods': {'deposit': true, 'card': true, 'test': false},
          },
        }
      );
    } else if (options.path == '/api/v2/el/check-username') {
      reply = (
        200,
        {
          'success': true,
          'data': {'available': true, 'user_id': 'ali1@el'},
        }
      );
    } else if (options.method == 'POST' &&
        options.path == '/api/v2/subscribers') {
      final g = gate;
      if (g != null) await g.future;
      reply = createReply;
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
