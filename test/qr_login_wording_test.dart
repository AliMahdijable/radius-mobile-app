import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/qr_login_sheet.dart';
import 'package:rad_mysvcs/services/image_saver.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';

/// رمز QR دخول المشترك — **أين** يُمسح، وما يخرج من نافذته.
///
/// 🐛 تدقيق البوّابة ٢٠٢٦-١٠-١٧ (§2.3): الرمز يُمسح من ماسح تطبيق المشترك وحده — النصّ كان يقول «هذا رمز QR لتسجيل دخولك»
/// فيُمسح بالكاميرا.
///
/// ١٩ نوفمبر (المالك: «أكو رابط يتولد مال رابط معرفة الاشتراك. هذا نريد نلغيه بالتطبيق وبالويب. ونخلي إمكانية حفظ الكيو آر،
/// مو بس مشاركة»): لا رابط في النافذة ولا في أيّ نصّ — الرمز صورةٌ تُحفظ (الصور بالهاتف، «حفظ باسم» بالحاسبة)، تُشارَك، أو
/// تُرسَل للمشترك بواتساب صورةً بتعليقها (POST /api/whatsapp/send-media).
///
/// تطبيق المشترك اسمه في المتجرين «MyServices» (كان «MySub» وأبل طلبت تركه) — فلا يظهر الاسم القديم في أيّ نصّ.
const _link = 'https://pro.mysvcs.net/v2/user-info/tok123';

/// PNG وهميّ بحجمٍ معلوم (الترويسة الحقيقيّة + حشو).
Uint8List _png(int size) {
  final b = Uint8List(size);
  b.setAll(0, const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  return b;
}

void main() {
  group('نصّ الإرسال', () {
    test('🚨 مع صورة الرمز: يُمسح من داخل MyServices أو يُرفع من المعرض — وبلا أيّ رابط', () {
      final s = qrShareText(greet: 'علي');
      expect(s, contains('تطبيق MyServices'));
      expect(s, isNot(contains('MySub')), reason: 'الاسم القديم');
      // زرّا تطبيق المشترك (2.0.7 — باسم MyServices) بنصّهما: «الدخول برمز QR
      // من وكيلك» في شاشة الدخول · «رفع صورة من المعرض» في شاشة المسح. والزرّ
      // القديم («تسجيل الدخول بواسطة QR») كان في نسخته باسم MySub وحدها.
      expect(s, contains('«الدخول برمز QR من وكيلك»'));
      expect(s, isNot(contains('تسجيل الدخول بواسطة QR')), reason: 'زرّ النسخة القديمة');
      expect(s, contains('صورته من المعرض'));
      expect(s, contains('30 يوم'));
      expect(s, isNot(contains('هذا رمز QR لتسجيل دخولك')));
      // ١٩ نوفمبر: رابط «معلومات الاشتراك» أُلغي
      expect(s, isNot(contains('http')));
      expect(s, isNot(contains('الرابط')));
      expect(s, isNot(contains('معلومات اشتراكك')));
    });
  });

  group('النافذة', () {
    late _Server srv;
    final saves = <MethodCall>[];
    String saveAnswer = 'saved';
    final shares = <({int bytes, String text})>[];
    final captures = <double>[];

    setUp(() async {
      await loadAppFonts();
      FlutterSecureStorage.setMockInitialValues({'auth.token': 'sim-token', 'auth.admin_id': '2251'});
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      srv = _Server();
      ApiClient.dio.httpClientAdapter = srv;
      saves.clear();
      shares.clear();
      captures.clear();
      saveAnswer = 'saved';
      ImageSaver.debugDesktop = false;
      debugQrCapture = (ratio) async {
        captures.add(ratio);
        return _png(4000);
      };
      debugQrShare = (bytes, text) async => shares.add((bytes: bytes.length, text: text));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ImageSaver.channel, (call) async {
        saves.add(call);
        return saveAnswer;
      });
    });

    tearDown(() {
      ImageSaver.debugDesktop = null;
      debugQrCapture = null;
      debugQrShare = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ImageSaver.channel, null);
    });

    Future<void> open(WidgetTester t, {Size size = const Size(360, 800), String phone = '07701234567'}) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final sub = Subscriber.fromJson({
        'idx': '55',
        'username': 'ali1@poox',
        'firstname': 'علي',
        'lastname': 'حسن',
        'phone': phone,
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
                    onPressed: () => showQrLoginSheet(c, sub),
                    child: const Text('افتح'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('افتح'));
      await t.pumpAndSettle();
    }

    /// يغلق الشجرة ويترك مؤقّت إشعار النافذة (٣ ث) ينتهي — وإلّا «Timer is still pending».
    Future<void> finish(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 4));
    }

    /// إطاراتٌ معدودة — زرّ «إرسال بواتساب» يدور ما دامت المعاينة مفتوحة، فـpumpAndSettle لا ينتهي.
    Future<void> some(WidgetTester t) async {
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> tapKey(WidgetTester t, String key) async {
      final f = find.byKey(ValueKey(key));
      await t.ensureVisible(f);
      await t.pump();
      await t.tap(f);
      // الالتقاط ينتظر نهاية الإطار، ثمّ القناة/الخادم
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 60));
      }
    }

    testWidgets('🚨 تقول للمدير أين يُمسح الرمز — ولا رابط فيها (لا نصّه ولا نسخه ولا فتحه)', (t) async {
      await open(t);
      expect(srv.asked, contains('POST /api/v2/subscribers/55/portal-qr-token'), reason: 'الرمز وُلِّد');
      final hint = find.textContaining('من داخل تطبيق MyServices');
      expect(hint, findsOneWidget);
      expect(find.textContaining('MySub'), findsNothing, reason: 'الاسم القديم');
      expect(find.textContaining('كاميرا الهاتف'), findsOneWidget);
      // ١٩ نوفمبر: الرابط أُلغي من النافذة
      expect(find.text(_link), findsNothing);
      expect(find.textContaining('user-info'), findsNothing);
      expect(find.textContaining('http'), findsNothing);
      // ثلاثة أزرار: حفظ · مشاركة · إرسال بواتساب
      expect(find.byKey(const ValueKey('qr-save')), findsOneWidget);
      expect(find.byKey(const ValueKey('qr-share')), findsOneWidget);
      expect(find.byKey(const ValueKey('qr-send-wa')), findsOneWidget);
      expect(find.text('حفظ الصورة'), findsOneWidget);
      expect(find.text('مشاركة'), findsOneWidget);
      // الصورة تحمل اسم المشترك وما هي
      expect(find.byKey(const ValueKey('qr-image-name')), findsOneWidget);
      expect(find.text('رمز دخول تطبيق MyServices'), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
    });

    testWidgets('لا نصّ مقصوص ولا فيضان على 320–430 × الخطّ 1.0/1.2', (t) async {
      for (final w in [320.0, 360.0, 430.0]) {
        for (final scale in [1.0, 1.2]) {
          t.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          await open(t, size: Size(w, 900));
          expect(t.takeException(), isNull, reason: 'فيضان $w×$scale');
          final cut = <String>{
            for (final p in t.allRenderObjects.whereType<RenderParagraph>())
              if (p.didExceedMaxLines) p.text.toPlainText(),
          };
          expect(cut, isEmpty, reason: 'نصٌّ مقصوص $w×$scale');
          await finish(t);
        }
      }
    });

    testWidgets('«حفظ الصورة»: إلى صور الهاتف باسمٍ لاتينيّ آمن من اسم المشترك — ويُقال «حُفظت»', (t) async {
      await open(t);
      await tapKey(t, 'qr-save');
      expect(saves, hasLength(1));
      expect(saves.single.method, 'saveImage');
      final args = Map<String, Object?>.from(saves.single.arguments as Map);
      expect(args['name'], 'myservices_qr_ali1_poox');
      expect((args['bytes'] as Uint8List).length, 4000);
      expect(captures, [3.5], reason: 'بالدقّة الكاملة');
      expect(find.text('حُفظت الصورة'), findsOneWidget);
      expect(shares, isEmpty);
      expect(t.takeException(), isNull);
      await finish(t);
    });

    testWidgets('هاتفٌ بلا حفظٍ مباشر (أندرويد أقدم من 10) ⇒ نافذة المشاركة بالصورة؛ والرفض (آيفون) يُقال بسببه', (t) async {
      saveAnswer = 'unsupported';
      await open(t);
      await tapKey(t, 'qr-save');
      expect(shares, hasLength(1), reason: 'المشاركة بديل الحفظ');
      expect(shares.single.text, isNot(contains('http')));
      expect(find.textContaining('نافذة المشاركة'), findsOneWidget);
      await finish(t);

      saveAnswer = 'denied';
      shares.clear();
      await open(t);
      await tapKey(t, 'qr-save');
      expect(shares, isEmpty);
      expect(find.textContaining('اسمح للتطبيق بإضافة الصور'), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
    });

    testWidgets('«مشاركة»: الصورة ونصّها بلا رابط', (t) async {
      await open(t);
      await tapKey(t, 'qr-share');
      expect(shares, hasLength(1));
      expect(shares.single.bytes, 4000);
      expect(shares.single.text, qrShareText(greet: 'علي حسن'));
      expect(saves, isEmpty);
      expect(t.takeException(), isNull);
      await finish(t);
    });

    testWidgets('«إرسال بواتساب»: صورة الرمز بتعليقها من واتساب الصفحة (send-media) — لا رسالة نصٍّ برابط', (t) async {
      await open(t);
      await tapKey(t, 'qr-send-wa');
      await some(t);
      await t.tap(find.text('إرسال تلقائي'));
      await some(t);
      final media = srv.posts('/api/whatsapp/send-media');
      expect(media, hasLength(1));
      final body = media.single;
      expect(body['adminId'], '2251');
      expect(body['to'], '07701234567');
      expect(body['mimetype'], 'image/png');
      expect(body['filename'], 'myservices_qr_ali1_poox.png');
      expect(body['sas4Idx'], '55');
      expect(base64Decode(body['data'] as String).length, 4000);
      expect(body['caption'], qrShareText(greet: 'علي حسن'));
      expect('${body['caption']}', isNot(contains('http')));
      expect(srv.posts('/api/whatsapp/send-message'), isEmpty, reason: 'لا رابط نصّيّاً بعد الآن');
      expect(captures.last, 2.5, reason: 'صورةٌ أصغر لمسار الخادم');
      expect(find.textContaining('تم إرسال الرمز بواتساب'), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
    });

    testWidgets('صورةٌ أكبر من حدّ الخادم تُخفَّض دقّتها حتى تصغر؛ وإن لم تصغر لا يُرسَل شيء', (t) async {
      // 2.5 ⇒ 90KB (فوق الحدّ)، 1.8 ⇒ 40KB
      debugQrCapture = (ratio) async {
        captures.add(ratio);
        return _png(ratio > 2 ? 90 * 1024 : 40 * 1024);
      };
      await open(t);
      await tapKey(t, 'qr-send-wa');
      await some(t);
      await t.tap(find.text('إرسال تلقائي'));
      await some(t);
      expect(captures, [2.5, 1.8]);
      expect(base64Decode(srv.posts('/api/whatsapp/send-media').single['data'] as String).length, 40 * 1024);
      await finish(t);

      srv.requests.clear();
      captures.clear();
      debugQrCapture = (ratio) async {
        captures.add(ratio);
        return _png(200 * 1024);
      };
      await open(t);
      await tapKey(t, 'qr-send-wa');
      await some(t);
      await t.tap(find.text('إرسال تلقائي'));
      await some(t);
      expect(captures, [2.5, 1.8, 1.3]);
      expect(srv.posts('/api/whatsapp/send-media'), isEmpty);
      expect(find.textContaining('تعذّر التقاط صورة الرمز'), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
    });

    testWidgets('«واتسابي» (يدويّ): نافذة المشاركة بالصورة — لا طلب للخادم', (t) async {
      await open(t);
      await tapKey(t, 'qr-send-wa');
      await some(t);
      // التبديل إلى اليدويّ (شريحة «وضع تلقائي») ثمّ التأكيد
      await t.tap(find.text('وضع تلقائي'));
      await some(t);
      final go = find.text('افتح واتسابي');
      expect(go, findsOneWidget, reason: 'زرّ اليدويّ في المعاينة');
      await t.tap(go);
      await some(t);
      expect(shares, hasLength(1));
      expect(srv.posts('/api/whatsapp/send-media'), isEmpty);
      expect(t.takeException(), isNull);
      await finish(t);
    });

    testWidgets('مشتركٌ بلا رقم: «إرسال بواتساب» يقول السبب ولا يطلب شيئاً — والحفظ والمشاركة يعملان', (t) async {
      await open(t, phone: '');
      await tapKey(t, 'qr-send-wa');
      expect(srv.posts('/api/whatsapp/send-media'), isEmpty);
      await tapKey(t, 'qr-save');
      expect(saves, hasLength(1));
      expect(t.takeException(), isNull);
      await finish(t);
    });
  });

  group('حفظ الصورة (ImageSaver)', () {
    tearDown(() {
      ImageSaver.debugDesktop = null;
      ImageSaver.pickPath = (_) async => null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ImageSaver.channel, null);
    });

    test('اسم الملفّ: لاتينيّ وأرقام و_ و- وحدها، ≤ 80، وغير فارغ', () {
      expect(ImageSaver.safeName('ali1@poox'), 'ali1_poox');
      expect(ImageSaver.safeName('  علي حسن  '), 'image');
      expect(ImageSaver.safeName('a/b\\c:d*e?f"g<h>i|j'), 'a_b_c_d_e_f_g_h_i_j');
      expect(ImageSaver.safeName('../../etc/passwd'), 'etc_passwd');
      expect(ImageSaver.safeName('x' * 200).length, 80);
    });

    testWidgets('الحاسبة: «حفظ باسم» يكتب الملفّ حيث اختار (ويضيف .png إن غاب)؛ الإغلاق بلا اختيار لا يكتب شيئاً', (t) async {
      await t.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('qr_save_test');
        try {
          ImageSaver.debugDesktop = true;
          String? asked;
          ImageSaver.pickPath = (suggested) async {
            asked = suggested;
            return '${dir.path}/chosen';
          };
          final r = await ImageSaver.savePng(_png(1234), name: 'myservices_qr_ali1_poox');
          expect(r, ImageSaveResult.saved);
          expect(asked, 'myservices_qr_ali1_poox.png');
          expect(File('${dir.path}/chosen.png').lengthSync(), 1234);

          ImageSaver.pickPath = (_) async => null;
          expect(await ImageSaver.savePng(_png(10), name: 'x'), ImageSaveResult.cancelled);
          expect(dir.listSync().length, 1);

          ImageSaver.pickPath = (_) async => '${dir.path}/no/such/dir/x.png';
          expect(await ImageSaver.savePng(_png(10), name: 'x'), ImageSaveResult.failed, reason: 'لا يرمي');
        } finally {
          await dir.delete(recursive: true);
        }
      });
    });

    testWidgets('الهاتف: ردّ القناة كما هو، ومنصّةٌ بلا قناة ⇒ «غير مدعوم» (المشاركة بديله)، وصورةٌ فارغة لا تُطلب', (t) async {
      ImageSaver.debugDesktop = false;
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final (answer, want) in [
        ('saved', ImageSaveResult.saved),
        ('denied', ImageSaveResult.denied),
        ('unsupported', ImageSaveResult.unsupported),
        ('failed', ImageSaveResult.failed),
        ('???', ImageSaveResult.failed),
      ]) {
        messenger.setMockMethodCallHandler(ImageSaver.channel, (call) async => answer);
        expect(await ImageSaver.savePng(_png(10), name: 'x'), want, reason: answer);
      }
      messenger.setMockMethodCallHandler(ImageSaver.channel, (call) async => throw MissingPluginException());
      expect(await ImageSaver.savePng(_png(10), name: 'x'), ImageSaveResult.unsupported);
      var calls = 0;
      messenger.setMockMethodCallHandler(ImageSaver.channel, (call) async {
        calls++;
        return 'saved';
      });
      expect(await ImageSaver.savePng(Uint8List(0), name: 'x'), ImageSaveResult.failed);
      expect(calls, 0);
      messenger.setMockMethodCallHandler(ImageSaver.channel, (call) async => throw PlatformException(code: 'boom'));
      expect(await ImageSaver.savePng(_png(10), name: 'x'), ImageSaveResult.failed, reason: 'لا يرمي');
    });
  });
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

/// خادمٌ وهميّ بعقد `POST /api/v2/subscribers/:idx/portal-qr-token` و`POST /api/whatsapp/send-media`.
class _Server implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  List<String> get asked => [for (final r in requests) '${r.method} ${r.path}'];

  List<Map<String, dynamic>> posts(String path) => [
        for (final r in requests)
          if (r.method == 'POST' && r.path == path) Map<String, dynamic>.from(r.data as Map),
      ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    Object body = {'success': false};
    var status = 404;
    if (options.method == 'POST' && options.path == '/api/v2/subscribers/55/portal-qr-token') {
      status = 200;
      body = {
        'success': true,
        'data': {
          'linkUrl': _link,
          'expiresAt': DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
        },
      };
    } else if (options.method == 'POST' && options.path == '/api/whatsapp/send-media') {
      status = 200;
      body = {'success': true, 'message': 'تم إرسال الملف بنجاح', 'channel': 'whatsapp'};
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
