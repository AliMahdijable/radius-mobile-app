import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/qr_login_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';

/// رمز QR دخول المشترك — **أين** يُمسح.
///
/// 🐛 تدقيق البوّابة ٢٠٢٦-١٠-١٧ (§2.3): الرمز والرابط يفتحان في المتصفّح
/// (كاميرا الهاتف، نقرة الرابط، واتساب) بطاقة معلومات من الساس وحدها — لا
/// هويّة المدير ولا أسماء باقاته. والدخول إلى البوّابة من ماسح تطبيق المشترك
/// وحده. والنصّ كان يقول «هذا رمز QR لتسجيل دخولك» فيُمسح بالكاميرا، ويظنّ
/// المدير أنّ البوّابة لا تعكس تعديلاته.
///
/// تطبيق المشترك اسمه في المتجرين «MyServices» (كان «MySub» وأبل طلبت تركه)
/// — فلا يظهر الاسم القديم في أيّ نصّ.
const _link = 'https://pro.mysvcs.net/v2/user-info/tok123';

void main() {
  group('نصّا الإرسال', () {
    test('🚨 المشاركة (مع صورة الرمز): يُمسح من داخل MyServices أو يُرفع من المعرض',
        () {
      final s = qrShareText(greet: 'علي', link: _link);
      expect(s, contains('تطبيق MyServices'));
      expect(s, isNot(contains('MySub')), reason: 'الاسم القديم');
      // زرّا تطبيق المشترك (2.0.7 — باسم MyServices) بنصّهما: «الدخول برمز QR
      // من وكيلك» في شاشة الدخول · «رفع صورة من المعرض» في شاشة المسح. والزرّ
      // القديم («تسجيل الدخول بواسطة QR») كان في نسخته باسم MySub وحدها.
      expect(s, contains('«الدخول برمز QR من وكيلك»'));
      expect(s, isNot(contains('تسجيل الدخول بواسطة QR')), reason: 'زرّ النسخة القديمة');
      expect(s, contains('صورته من المعرض'));
      expect(s, contains(_link));
      expect(s, contains('30 يوم'));
      expect(s, isNot(contains('هذا رمز QR لتسجيل دخولك')));
    });

    test('🚨 واتساب (رابطٌ بلا صورة): الرابط معلومات، والدخول من داخل التطبيق',
        () {
      final s = qrWhatsAppText(greet: 'علي', link: _link);
      expect(s, contains('معلومات اشتراكك على الرابط:\n$_link'));
      expect(s, contains('تطبيق MyServices'));
      expect(s, isNot(contains('MySub')), reason: 'الاسم القديم');
      expect(s, contains('من داخل التطبيق'));
      expect(s, contains('(«الدخول برمز QR من وكيلك»)'));
      expect(s, isNot(contains('تسجيل الدخول بواسطة QR')), reason: 'زرّ النسخة القديمة');
      expect(s, contains('لا بكاميرا الهاتف'));
      // لا صورة في رسالة واتساب — فلا تقول «هذا رمز».
      expect(s, isNot(contains('هذا رمز')));
    });
  });

  testWidgets('🚨 الشيت يقول للمدير أين يُمسح الرمز', (t) async {
    await loadAppFonts();
    FlutterSecureStorage.setMockInitialValues(
        {'auth.token': 'sim-token', 'auth.admin_id': '2251'});
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    ApiClient.dio.httpClientAdapter = _Server();
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    final sub = Subscriber.fromJson({
      'idx': '55',
      'username': 'ali1@poox',
      'firstname': 'علي',
      'lastname': 'حسن',
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

    expect(find.text(_link), findsOneWidget, reason: 'الرمز وُلِّد');
    final hint = find.textContaining('من داخل تطبيق MyServices');
    expect(hint, findsOneWidget);
    expect(find.textContaining('MySub'), findsNothing, reason: 'الاسم القديم');
    expect(find.textContaining('كاميرا الهاتف'), findsOneWidget);
    expect(t.takeException(), isNull);
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

/// خادمٌ وهميّ بعقد `POST /api/v2/subscribers/:idx/portal-qr-token`.
class _Server implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final ok = options.method == 'POST' &&
        options.path == '/api/v2/subscribers/55/portal-qr-token';
    final body = ok
        ? {
            'success': true,
            'data': {
              'linkUrl': _link,
              'expiresAt': DateTime.now()
                  .add(const Duration(days: 30))
                  .millisecondsSinceEpoch,
            },
          }
        : {'success': false};
    return ResponseBody.fromString(
      jsonEncode(body),
      ok ? 200 : 404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
