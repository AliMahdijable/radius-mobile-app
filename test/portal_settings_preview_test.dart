import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/screens/portal_settings/portal_settings_screen.dart';
import 'package:rad_mysvcs/screens/portal_settings/widgets/link_image_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';

/// شاشة «بوابة المشترك» — المعاينة والحفظ أمام خادمٍ وهميّ بعقد
/// `/api/v2/admin/branding` و`/api/v2/admin/portal-packages`.
///
/// 🐛 تدقيق البوّابة ٢٠٢٦-١٠-١٧ (§2.6):
///   • المعاينة كانت تتبع **أوّل** حرفٍ وحده (`_mark` لا يعيد البناء بعده).
///   • رابط صفحةٍ (ibb.co · postimg…) يُعرض بأيقونة الحقل الفارغ — صامتاً.
///   • والخادم صار يرفض رابط الصفحة برسالةٍ عربيّة، والشاشة تقول «فشل الحفظ».
const _pageLink = 'https://ibb.co/page-abc';
const _imageLink = 'https://i.ibb.co/x/logo.png';
const _refusal =
    'هذا رابط صفحة لا صورة — افتح الصورة واختر نسخ رابط الصورة المباشر';
const _notImage = 'الرابط ليس صورة';
const _saveFailed = 'فشل الحفظ — أعد المحاولة';
const _save = 'حفظ';

void main() {
  late _Server server;
  late ui.Image pixel;
  final original = LinkImagePreview.imageFor;

  setUpAll(() async {
    await loadAppFonts();
    pixel = await createTestImage(width: 4, height: 4);
    // نقرةٌ تقع على غير هدفها تُنجح الاختبار زوراً — فلتكن فشلاً.
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues(
        {'auth.token': 'sim-token', 'auth.admin_id': '2251'});
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    server = _Server();
    ApiClient.dio.httpClientAdapter = server;
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    LinkImagePreview.imageFor = (url) => _FakeImage(url, pixel);
  });

  tearDown(() => LinkImagePreview.imageFor = original);

  Future<void> open(WidgetTester t) async {
    // طويلةٌ كي تُبنى كلّ الحقول (ListView يبني الظاهر وحده).
    t.view.physicalSize = const Size(400, 2400);
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
          home: const PortalSettingsScreen(),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    // ١٨ أكتوبر: «رمز الوكيل» صار التبويب الأوّل — الهويّة في الثاني.
    await t.tap(find.text('معلومات الشركة'));
    await t.pumpAndSettle();
  }

  /// كتابةٌ ثمّ توقّف: إطارٌ يُطبّقها، ثمّ مهلة المعاينة، ثمّ الطلب وردّه.
  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(LinkImagePreview.settle);
    await t.pump();
    await t.pump();
  }

  /// الضغط على «حفظ» وانتظار الردّ ودخول الإشعار.
  Future<void> save(WidgetTester t, {Finder? within}) async {
    final button = find.text(_save);
    await t.tap(within == null
        ? button
        : find.descendant(of: within, matching: button));
    await t.pump();
    await t.pump(const Duration(milliseconds: 750));
  }

  /// يُفرغ مؤقّتات الإشعارات قبل نهاية الاختبار.
  Future<void> drain(WidgetTester t) async {
    await t.pump(const Duration(seconds: 10));
    await t.pumpAndSettle();
  }

  // الحقول بترتيبها: 0 الاسم · 1 الشعار · 4 واتساب.
  Finder field(int i) => find.byType(TextField).at(i);
  TextEditingController ctrl(WidgetTester t, int i) =>
      t.widget<TextField>(field(i)).controller!;
  final preview = find.byType(LinkImagePreview);
  Finder inPreview(Finder f) => find.descendant(of: preview, matching: f);

  group('معاينة الترويسة', () {
    testWidgets('🚨 تتبع كلّ حرف — لا الأوّل وحده', (t) async {
      server.branding = {'display_name': 'شبكة النور'};
      await open(t);
      expect(inPreview(find.text('شبكة النور')), findsOneWidget);

      await t.enterText(field(0), 'ش');
      await t.pump();
      expect(inPreview(find.text('ش')), findsOneWidget);
      await t.enterText(field(0), 'شبكة الأمل');
      await t.pump();
      expect(inPreview(find.text('شبكة الأمل')), findsOneWidget,
          reason: 'كانت تبقى على أوّل حرفٍ كُتب');
      await t.enterText(field(0), '');
      await t.pump();
      expect(inPreview(find.text('اسم الشركة سيظهر هنا')), findsOneWidget);
    });

    testWidgets('🚨 شعارٌ رابطه صفحة: «الرابط ليس صورة» — والمباشر يُعرض',
        (t) async {
      await open(t);
      await t.enterText(field(1), _pageLink);
      await settle(t);
      expect(inPreview(find.text(_notImage)), findsOneWidget);
      expect(inPreview(find.byIcon(LucideIcons.imageOff)), findsOneWidget);

      await t.enterText(field(1), _imageLink);
      await settle(t);
      expect(find.text(_notImage), findsNothing);
      expect(inPreview(find.byType(RawImage)), findsOneWidget);
    });

    testWidgets('شعارٌ محفوظ رابطه صفحة يُكشف حال فتح الشاشة', (t) async {
      server.branding = {'logo_url': _pageLink};
      await open(t);
      expect(inPreview(find.text(_notImage)), findsOneWidget);
    });
  });

  group('الحفظ', () {
    testWidgets('🚨 رفض الخادم رابط الصفحة: رسالته تظهر لا «فشل الحفظ»',
        (t) async {
      server.putBranding = (400, {'success': false, 'message': _refusal});
      await open(t);
      await t.enterText(field(1), _pageLink);
      await t.pump();
      await save(t);
      expect(find.text(_refusal), findsOneWidget);
      expect(find.text(_saveFailed), findsNothing);
      expect(find.text(_save), findsOneWidget, reason: 'لم يُحفظ — الزرّ باقٍ');
      expect(server.brandingBodies.single['logo_url'], _pageLink);
      await drain(t);
    });

    testWidgets('رسالة رفضٍ غير عربيّة لا تُعرض — «فشل الحفظ» كما كان',
        (t) async {
      server.putBranding = (400, {'success': false, 'message': 'Bad Request'});
      await open(t);
      await t.enterText(field(0), 'شبكة');
      await t.pump();
      await save(t);
      expect(find.text(_saveFailed), findsOneWidget);
      expect(find.text('Bad Request'), findsNothing);
      await drain(t);
    });

    testWidgets('الحقول تعرض ما خزّنه الخادم (صورة الصفحة · رقم 07…)',
        (t) async {
      server.putBranding = (
        200,
        {
          'success': true,
          'branding': {
            'logo_url': _imageLink,
            'whatsapp_number': '9647701234567',
          },
        }
      );
      await open(t);
      await t.enterText(field(1), _pageLink);
      await t.enterText(field(4), '07701234567');
      await t.pump();
      await save(t);
      expect(server.brandingBodies.single['whatsapp_number'], '07701234567');
      expect(ctrl(t, 1).text, _imageLink);
      expect(ctrl(t, 4).text, '9647701234567');
      expect(find.text('تم الحفظ'), findsOneWidget);
      expect(find.text(_save), findsNothing, reason: 'محفوظ');
      await settle(t);
      expect(find.text(_notImage), findsNothing,
          reason: 'المعاينة على ما خُزّن لا على رابط الصفحة');
      await drain(t);
    });

    testWidgets('ما كُتب أثناء الحفظ لا يُمحى ويبقى زرّ الحفظ', (t) async {
      server.putGate = Completer<void>();
      server.putBranding = (
        200,
        {
          'success': true,
          'branding': {'display_name': 'أ'},
        }
      );
      await open(t);
      await t.enterText(field(0), 'أ');
      await t.pump();
      await t.tap(find.text(_save));
      await t.pump();
      await t.enterText(field(0), 'أب'); // والطلب في الطريق
      await t.pump();
      server.putGate!.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 750));
      expect(ctrl(t, 0).text, 'أب');
      expect(find.text(_save), findsOneWidget, reason: '«أب» لم يُحفظ بعد');
      await drain(t);
    });
  });

  testWidgets('🚨 شيت الباقة: معاينة الصورة حيّة ورسالة رفض الخادم', (t) async {
    server.packages = [
      {'profile_id': 9, 'sas_name': 'B-Economy', 'price': 25000},
    ];
    server.putPackage = (400, {'success': false, 'message': _refusal});
    await open(t);
    await t.tap(find.text('وصف الباقات'));
    await t.pumpAndSettle();
    await t.tap(find.text('B-Economy'));
    await t.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
    final image = inSheet(find.byType(TextField)).at(2);
    expect(inSheet(find.byType(RawImage)), findsNothing, reason: 'حقلٌ فارغ');

    await t.enterText(image, _pageLink);
    await settle(t);
    expect(inSheet(find.text(_notImage)), findsOneWidget);
    await t.enterText(image, _imageLink);
    await settle(t);
    expect(inSheet(find.text(_notImage)), findsNothing);
    expect(inSheet(find.byType(RawImage)), findsOneWidget);

    await t.enterText(image, _pageLink);
    await settle(t);
    await save(t, within: sheet);
    expect(find.text(_refusal), findsOneWidget);
    expect(find.text(_saveFailed), findsNothing);
    expect(sheet, findsOneWidget, reason: 'لم يُحفظ — الشيت باقٍ');
    expect(server.packageBodies.single['image_url'], _pageLink);
    await drain(t);
  });
}

/// صورةٌ بلا شبكة: «page» في الرابط = صفحة ويب لا يفكّها المحرّك صورةً.
class _FakeImage extends ImageProvider<_FakeImage> {
  _FakeImage(this.url, this.pixel);
  final String url;
  final ui.Image pixel;

  @override
  Future<_FakeImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FakeImage>(this);

  @override
  ImageStreamCompleter loadImage(_FakeImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(url.contains('page')
          ? Future<ImageInfo>.error(const FormatException('not an image'))
          : SynchronousFuture(ImageInfo(image: pixel.clone())));

  @override
  bool operator ==(Object other) => other is _FakeImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

class _DiskLoader extends AssetLoader {
  const _DiskLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) =>
      Future.value(jsonDecode(
        File('assets/translations/${locale.languageCode}.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>);
}

/// خادمٌ وهميّ بعقد إعدادات البوّابة. [putGate] يُمسك ردّ حفظ الهويّة حتى
/// يُكمَل — لما يجري **أثناء** الحفظ.
class _Server implements HttpClientAdapter {
  Map<String, dynamic> branding = const {};
  List<Map<String, dynamic>> packages = const [];
  (int, Map<String, dynamic>) putBranding = (200, {'success': true});
  (int, Map<String, dynamic>) putPackage = (200, {'success': true});
  Completer<void>? putGate;
  final brandingBodies = <Map<String, dynamic>>[];
  final packageBodies = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final (int, Map<String, dynamic>) reply;
    final path = options.path;
    if (options.method == 'GET' && path == '/api/v2/admin/branding') {
      reply = (200, {'success': true, 'branding': branding});
    } else if (options.method == 'PUT' && path == '/api/v2/admin/branding') {
      brandingBodies.add(Map<String, dynamic>.from(options.data as Map));
      final g = putGate;
      if (g != null) await g.future;
      reply = putBranding;
    } else if (options.method == 'GET' &&
        path == '/api/v2/admin/portal-packages') {
      reply = (200, {'success': true, 'packages': packages});
    } else if (options.method == 'PUT' &&
        path.startsWith('/api/v2/admin/portal-packages/')) {
      packageBodies.add(Map<String, dynamic>.from(options.data as Map));
      reply = putPackage;
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
