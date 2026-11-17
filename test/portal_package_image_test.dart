import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/portal_services_api.dart' show ServiceImage;
import 'package:rad_mysvcs/api/portal_settings_api.dart';
import 'package:rad_mysvcs/screens/portal_settings/portal_settings_screen.dart';
import 'package:rad_mysvcs/screens/portal_settings/widgets/package_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';

/// صورة الباقة مرفوعةً من الهاتف (١٧ نوفمبر — المالك: «وصف الباقة يكون كتابه ورابط اريد تسوي امكانيه رفع صوره من التطبيق مالتنا بعد
/// ضغطها حتى لاتاخذ حجم») — الضغط نفسه، ونداء الحفظ، ومحرّر الباقة أمام خادمٍ وهميّ بعقد server/portalPackageImages.js (aeda6e4):
///   PUT /api/v2/admin/portal-packages/:id {…, image_data: data URL} → {success, changed, image_url: https://pro.mysvcs.net/api/portal/pkg-img/…}
const _hosted = 'https://pro.mysvcs.net/api/portal/pkg-img/7-0123456789ab.jpg';
const _hosted2 = 'https://pro.mysvcs.net/api/portal/pkg-img/7-abcdefabcdef.jpg';

Uint8List _jpg(img.Image im, {int quality = 95}) => Uint8List.fromList(img.encodeJpg(im, quality: quality));

/// صورةٌ كالصور الحقيقيّة (تدرّج + ضجيج) — أسوأ من الواقع للضغط.
img.Image _photo(int w, int h, {int seed = 1, int noise = 40}) {
  final rnd = math.Random(seed);
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    final n = rnd.nextInt(noise * 2 + 1) - noise;
    p
      ..r = (p.x * 255 ~/ w + n).clamp(0, 255)
      ..g = (p.y * 255 ~/ h + n).clamp(0, 255)
      ..b = ((p.x + p.y) * 255 ~/ (w + h) + n).clamp(0, 255);
  }
  return im;
}

bool _hasExif(Uint8List jpg) {
  // مقطع APP1 «Exif\0\0»
  for (var i = 0; i + 6 < jpg.length && i < 4096; i++) {
    if (jpg[i] == 0xFF && jpg[i + 1] == 0xE1 && jpg[i + 4] == 0x45 && jpg[i + 5] == 0x78 && jpg[i + 6] == 0x69) return true;
  }
  return false;
}

void main() {
  group('الضغط (preparePackageImage)', () {
    test('صورةٌ كبيرة من الكاميرا ⇒ JPEG أطول ضلعٍ 1280 بنسبتها، تحت 300 ك.ب، بلا EXIF', () {
      final raw = _jpg(_photo(3000, 2000));
      final r = preparePackageImage(raw);
      expect(r.image.mime, 'image/jpeg');
      expect((r.width, r.height), (1280, 853));
      expect(r.bytes, lessThanOrEqualTo(packageImageMaxBytes));
      expect(r.bytes, lessThan(raw.length ~/ 3), reason: 'أصغر بكثير من الأصل');
      expect(_hasExif(r.image.bytes), isFalse);
      final back = img.decodeJpg(r.image.bytes)!;
      expect((back.width, back.height), (1280, 853));
      expect(r.image.dataUrl, startsWith('data:image/jpeg;base64,'));
    });

    test('صورة طوليّة: الطول هو الضلع الأطول (1280) — والاتّجاه من EXIF يُطبَّق قبل حذفه', () {
      final tall = preparePackageImage(_jpg(_photo(1500, 3000)));
      expect((tall.width, tall.height), (640, 1280));
      final side = _photo(800, 400);
      side.exif.imageIfd.orientation = 6; // الهاتف مُدار ٩٠°
      final r = preparePackageImage(_jpg(side));
      expect(r.height, greaterThan(r.width), reason: 'دُوِّرت كما تُعرض في المعرض');
      expect(_hasExif(r.image.bytes), isFalse);
    });

    test('صورةٌ صغيرة لا تُكبَّر', () {
      final r = preparePackageImage(_jpg(_photo(400, 225)));
      expect((r.width, r.height), (400, 225));
    });

    test('شفافيّةٌ حقيقيّة ⇒ PNG؛ ولقطة شاشةٍ معتمة بقناةٍ رابعة ⇒ JPEG (أصغر)', () {
      final logo = img.Image(width: 600, height: 300, numChannels: 4);
      for (final p in logo) {
        p
          ..r = 20
          ..g = 120
          ..b = 90
          ..a = p.x < 300 ? 0 : 255;
      }
      final a = preparePackageImage(Uint8List.fromList(img.encodePng(logo)));
      expect(a.image.mime, 'image/png');
      expect(img.decodePng(a.image.bytes)!.getPixel(10, 10).a, 0, reason: 'الشفافيّة باقية');
      final shot = img.Image(width: 900, height: 500, numChannels: 4);
      final rnd = math.Random(3);
      for (final p in shot) {
        p
          ..r = rnd.nextInt(256)
          ..g = rnd.nextInt(256)
          ..b = 200
          ..a = 255;
      }
      final b = preparePackageImage(Uint8List.fromList(img.encodePng(shot)));
      expect(b.image.mime, 'image/jpeg');
      expect(b.bytes, lessThanOrEqualTo(packageImageMaxBytes));
    });

    test('أسوأ حالة (ضجيجٌ كامل) ⇒ جودةٌ أقلّ ثمّ ضلعٌ أصغر حتى تحت الحدّ — وإلّا «كبيرة جداً»', () {
      final noise = _photo(1600, 1600, seed: 9, noise: 127);
      final r = preparePackageImage(_jpg(noise, quality: 100));
      expect(r.bytes, lessThanOrEqualTo(packageImageMaxBytes));
      expect(r.image.mime, 'image/jpeg');
      expect(() => preparePackageImage(_jpg(noise), maxBytes: 2000),
          throwsA(isA<PackageImageError>().having((e) => e.reason, 'reason', 'too-big')));
    });

    test('بايتاتٌ ليست صورة ⇒ «تعذّر قراءة الصورة»', () {
      expect(() => preparePackageImage(Uint8List.fromList(utf8.encode('<html>not an image</html>'))),
          throwsA(isA<PackageImageError>().having((e) => e.reason, 'reason', 'decode')));
    });

    test('عنوان صورةٍ مرفوعة يُعرف كالخادم؛ والحجم مقروء', () {
      expect(isUploadedPackageImage(_hosted), isTrue);
      expect(isUploadedPackageImage(' https://rad.mysvcs.net/api/portal/pkg-img/12-0123456789ab.webp '), isTrue);
      for (final u in [null, '', 'https://i.ibb.co/x/p.png', 'http://pro.mysvcs.net/api/portal/pkg-img/7-0123456789ab.jpg',
        'https://pro.mysvcs.net/api/portal/svc-img/7-0123456789ab.jpg', 'https://evil.net/api/portal/pkg-img/7-0123456789ab.jpg']) {
        expect(isUploadedPackageImage(u), isFalse, reason: '$u');
      }
      expect(packageImageSizeLabel(87 * 1024), '87 ك.ب');
      expect(packageImageSizeLabel(300), '1 ك.ب');
      expect(packageImageSizeLabel(1258291), '1.2 م.ب');
    });
  });

  group('الحفظ والمحرّر', () {
    late _Server server;
    late Uint8List small;

    setUpAll(() async {
      await loadAppFonts();
      WidgetController.hitTestWarningShouldBeFatal = true;
      small = _jpg(_photo(64, 36), quality: 80);
    });

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({'auth.token': 'sim-token', 'auth.admin_id': '2251'});
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      server = _Server();
      ApiClient.dio.httpClientAdapter = server;
    });

    test('updatePackage: الصورة image_data (ولا image_url معها) وعنوانها من الردّ؛ وبلا صورةٍ الرابط كما كان', () async {
      server.putPackage = (200, {'success': true, 'changed': 1, 'image_url': _hosted});
      final r = await PortalSettingsApi.updatePackage(9, description: 'و', imageUrl: 'https://x.y/z.png', imageData: 'data:image/jpeg;base64,AAAA');
      expect(r.ok, isTrue);
      expect(r.imageUrl, _hosted);
      expect(server.packageBodies.single, {'description': 'و', 'image_data': 'data:image/jpeg;base64,AAAA'});
      server.putPackage = (200, {'success': true, 'changed': 1});
      final r2 = await PortalSettingsApi.updatePackage(9, imageUrl: null);
      expect((r2.ok, r2.imageUrl), (true, null));
      expect(server.packageBodies.last, {'image_url': null});
      server.putPackage = (413, {'success': false, 'code': 'IMAGE_TOO_BIG', 'field': 'image_data', 'message': 'الصورة كبيرة — اختر صورةً أصغر'});
      final r3 = await PortalSettingsApi.updatePackage(9, imageData: 'data:image/jpeg;base64,AAAA');
      expect((r3.ok, r3.message), (false, 'الصورة كبيرة — اختر صورةً أصغر'));
    });

    Future<void> open(WidgetTester t, {required PackageImagePicker picker, Size size = const Size(480, 1600), double scale = 1}) async {
      t.view.physicalSize = size;
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
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: PortalSettingsScreen(packageImagePicker: picker),
          ),
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('وصف الباقات'));
      await t.pumpAndSettle();
    }

    Future<void> openPackage(WidgetTester t, String name) async {
      await t.tap(find.text(name));
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    }

    Future<void> save(WidgetTester t) async {
      await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('حفظ')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 750));
    }

    Future<void> drain(WidgetTester t) async {
      await t.pump(const Duration(seconds: 10));
      await t.pumpAndSettle();
    }

    PreparedPackageImage prepared() => PreparedPackageImage(ServiceImage(small, 'image/jpeg'), 1280, 720);

    testWidgets('🚨 رفعٌ من الهاتف: المعاينة وحجمها بعد الضغط، والحفظ يرسل image_data وحدها، والقائمة بعنوان الخادم', (t) async {
      server.packages = [
        {'profile_id': 9, 'sas_name': 'B-Economy', 'price': 25000},
      ];
      server.putPackage = (200, {'success': true, 'changed': 1, 'image_url': _hosted});
      var picks = 0;
      await open(t, picker: () async {
        picks++;
        return prepared();
      });
      await openPackage(t, 'B-Economy');
      final sheet = find.byType(BottomSheet);
      Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
      expect(inSheet(find.text('رفع صورة من الهاتف')), findsOneWidget);
      expect(inSheet(find.text('تُضغط قبل الرفع حتى لا تأخذ حجماً')), findsOneWidget);
      expect(inSheet(find.text('أو رابط الصورة (URL)')), findsOneWidget, reason: 'الرابط باقٍ بديلاً');

      await t.tap(find.byKey(const ValueKey('pkg-image-upload')));
      await t.pumpAndSettle();
      expect(picks, 1);
      expect(find.byKey(const ValueKey('pkg-image-picked')), findsOneWidget);
      expect(inSheet(find.textContaining('بعد الضغط: ')), findsOneWidget);
      expect(inSheet(find.textContaining('ك.ب')), findsOneWidget);
      expect(inSheet(find.text('أو رابط الصورة (URL)')), findsNothing, reason: 'صورةٌ مرفوعة ⇒ لا حقل رابط');
      expect(inSheet(find.text('تغيير')), findsOneWidget);
      expect(inSheet(find.text('إزالة')), findsOneWidget);

      await save(t);
      final body = server.packageBodies.single;
      expect(body['image_data'], startsWith('data:image/jpeg;base64,'));
      expect(base64Decode((body['image_data'] as String).split(',').last), small);
      expect(body.containsKey('image_url'), isFalse);
      await t.pumpAndSettle();
      expect(sheet, findsNothing, reason: 'حُفظ وأُغلق');
      final thumb = t.widget<Image>(find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage));
      expect((thumb.image as NetworkImage).url, _hosted, reason: 'الصفّ بالعنوان الذي خزّنه الخادم');
      await drain(t);
    });

    testWidgets('صورةٌ مرفوعة سابقاً: بطاقتها بلا حقل رابط، والحفظ لا يلمسها؛ و«إزالة» ⇒ الحقل فارغاً وimage_url:null', (t) async {
      server.packages = [
        {'profile_id': 9, 'sas_name': 'B-Economy', 'price': 25000, 'image_url': _hosted, 'description': 'قديم'},
      ];
      await open(t, picker: () async => null);
      await openPackage(t, 'B-Economy');
      Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);
      expect(find.byKey(const ValueKey('pkg-image-uploaded')), findsOneWidget);
      expect(inSheet(find.text('صورةٌ مرفوعة — يراها مشتركوك كما هي')), findsOneWidget);
      expect(inSheet(find.text('أو رابط الصورة (URL)')), findsNothing);
      await save(t);
      expect(server.packageBodies.single.containsKey('image_url'), isFalse);
      expect(server.packageBodies.single.containsKey('image_data'), isFalse);
      await t.pumpAndSettle();

      await openPackage(t, 'B-Economy');
      await t.tap(find.byKey(const ValueKey('pkg-image-remove')));
      await t.pumpAndSettle();
      expect(inSheet(find.text('أو رابط الصورة (URL)')), findsOneWidget);
      expect(inSheet(find.text('رفع صورة من الهاتف')), findsOneWidget);
      final link = inSheet(find.byType(TextField)).at(2);
      expect(t.widget<TextField>(link).controller!.text, isEmpty, reason: 'عنوان خادمنا لا يظهر رابطاً');
      await save(t);
      expect(server.packageBodies.last, containsPair('image_url', null));
      await drain(t);
    });

    testWidgets('«تغيير الصورة» يرفع الجديدة؛ وإلغاء المعرض لا يغيّر شيئاً', (t) async {
      server.packages = [
        {'profile_id': 9, 'sas_name': 'B-Economy', 'price': 25000, 'image_url': _hosted},
      ];
      server.putPackage = (200, {'success': true, 'changed': 1, 'image_url': _hosted2});
      PreparedPackageImage? next;
      await open(t, picker: () async => next);
      await openPackage(t, 'B-Economy');
      await t.tap(find.byKey(const ValueKey('pkg-image-change')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pkg-image-uploaded')), findsOneWidget, reason: 'ألغى ⇒ كما هي');
      next = prepared();
      await t.tap(find.byKey(const ValueKey('pkg-image-change')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pkg-image-picked')), findsOneWidget);
      await save(t);
      expect(server.packageBodies.single.containsKey('image_data'), isTrue);
      await t.pumpAndSettle();
      final thumb = t.widget<Image>(find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage));
      expect((thumb.image as NetworkImage).url, _hosted2);
      await drain(t);
    });

    testWidgets('تعذّر الصورة ⇒ رسالتها؛ ورفض الخادم ⇒ رسالته والشيت باقٍ بالصورة', (t) async {
      server.packages = [
        {'profile_id': 9, 'sas_name': 'B-Economy', 'price': 25000},
      ];
      var fail = 'decode';
      await open(t, picker: () async => throw PackageImageError(fail));
      await openPackage(t, 'B-Economy');
      await t.tap(find.byKey(const ValueKey('pkg-image-upload')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('تعذّر قراءة الصورة — اختر صورةً أخرى'), findsOneWidget);
      await drain(t);
      fail = 'too-big';
      await t.tap(find.byKey(const ValueKey('pkg-image-upload')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('الصورة كبيرة جداً — اختر صورةً أخرى'), findsOneWidget);
      await drain(t);
      expect(server.packageBodies, isEmpty);
    });

    testWidgets('رفض الخادم للصورة (413) ⇒ رسالته، والشيت باقٍ بالمعاينة', (t) async {
      server.packages = [
        {'profile_id': 9, 'sas_name': 'B-Economy', 'price': 25000},
      ];
      server.putPackage = (413, {'success': false, 'code': 'IMAGE_TOO_BIG', 'field': 'image_data', 'message': 'الصورة كبيرة — اختر صورةً أصغر'});
      await open(t, picker: () async => prepared());
      await openPackage(t, 'B-Economy');
      await t.tap(find.byKey(const ValueKey('pkg-image-upload')));
      await t.pumpAndSettle();
      await save(t);
      expect(find.text('الصورة كبيرة — اختر صورةً أصغر'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('pkg-image-picked')), findsOneWidget);
      await drain(t);
    });

    for (final (w, scale) in const [(320.0, 1.2), (360.0, 1.0), (480.0, 1.2)]) {
      testWidgets('بلا فيضٍ ولا قصّ @ $w × خطّ $scale — زرّ الرفع والبطاقة بزرّيها', (t) async {
        server.packages = [
          {'profile_id': 9, 'sas_name': 'B-Economy', 'price': 25000},
        ];
        await open(t, picker: () async => prepared(), size: Size(w, 1400), scale: scale);
        await openPackage(t, 'B-Economy');
        expect(t.takeException(), isNull);
        void noClip(String what) {
          final sheet = find.byType(BottomSheet);
          for (final e in find.descendant(of: sheet, matching: find.byType(Text)).evaluate()) {
            final ro = e.renderObject;
            if (ro is RenderParagraph) {
              final txt = (e.widget as Text).data ?? '';
              if (txt.contains('صورة') || txt.contains('إزالة') || txt.contains('الضغط')) {
                expect(ro.didExceedMaxLines, isFalse, reason: '$what: «$txt» مقصوص');
              }
            }
          }
        }
        noClip('الرفع');
        await t.tap(find.byKey(const ValueKey('pkg-image-upload')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        noClip('البطاقة');
        await drain(t);
      });
    }
  });
}

class _DiskLoader extends AssetLoader {
  const _DiskLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => Future.value(
      jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>);
}

/// خادمٌ وهميّ بعقد «وصف الباقات» وحده.
class _Server implements HttpClientAdapter {
  List<Map<String, dynamic>> packages = const [];
  (int, Map<String, dynamic>) putPackage = (200, {'success': true, 'changed': 1});
  final packageBodies = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final (int, Map<String, dynamic>) reply;
    final path = options.path;
    if (options.method == 'GET' && path == '/api/v2/admin/portal-packages') {
      reply = (200, {'success': true, 'packages': packages});
    } else if (options.method == 'PUT' && path.startsWith('/api/v2/admin/portal-packages/')) {
      packageBodies.add(Map<String, dynamic>.from(options.data as Map));
      reply = putPackage;
    } else if (options.method == 'GET' && path == '/api/v2/admin/branding') {
      reply = (200, {'success': true, 'branding': const {}});
    } else {
      reply = (404, {'success': false});
    }
    return ResponseBody.fromString(jsonEncode(reply.$2), reply.$1, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
