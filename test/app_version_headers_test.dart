import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/ai_api.dart';
import 'package:rad_mysvcs/api/auth_api.dart';
import 'package:rad_mysvcs/services/app_version.dart';
import 'package:rad_mysvcs/services/auth_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// يلتقط ترويسات آخر طلب ويردّ [reply].
class _Capture implements HttpClientAdapter {
  Map<String, dynamic> headers = const {};
  String path = '';
  (int, Object) reply = (200, {'success': true});

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    headers = Map<String, dynamic>.from(o.headers);
    path = o.path;
    return ResponseBody.fromString(jsonEncode(reply.$2), reply.$1,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

/// ٥ نوفمبر («انتهاء الجلسة» بالهواتف): بوّابة التحديث تحكم برقم النسخة (x-app-build)، و3.0.15 لم يرسله من عملائه المستقلّين
/// عن ApiClient — التجديد و«استئناف الشركة» والمساعد بوضع الحساب — فرُدّت «نسخةً قديمة»: طردٌ بعد الخمول، وفتح الشركة يسقط إلى
/// كلمة السرّ. الخادم يمرّرها منذ da9dcea؛ وهنا كلّ عميلٍ يرسل رقمه فلا يحتاج استثناءً بعد اليوم.
void main() {
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'MyServices Pro',
      packageName: 'com.mysvcs.rad_mysvcs',
      version: '3.0.16',
      buildNumber: '176',
      buildSignature: '',
    );
    await AppVersion.load();
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    AuthApi.refreshAdapterForTest = null;
    AuthApi.accountTokenForTest = null;
  });

  test('تجديد الجلسة (Dio مستقلّ) يرسل رقم النسخة', () async {
    final cap = _Capture()..reply = (200, {'success': true, 'token': 'new', 'expiresAt': '2026-11-06T11:00:00Z'});
    AuthApi.refreshAdapterForTest = cap;
    AuthApi.accountTokenForTest = () async => 'acct-token';
    await AuthStorage.saveSession(
        token: 'old', adminId: 'jt:6836', adminUsername: 'admin@jt', displayName: 'مدير', autoLogin: false);
    await AuthApi.refreshTokenDetailed();
    expect(cap.path, '/api/auth/refresh-token');
    expect(cap.headers['x-app-build'], '176');
    expect(cap.headers['x-app-version'], '3.0.16');
    expect(cap.headers['x-device-label'], isNotNull);
  });

  test('«استئناف الشركة» (AccountApi) يرسل رقم النسخة مع نوع الجهاز', () async {
    final cap = _Capture()..reply = (403, {'success': false});
    final old = AccountApi.dio.httpClientAdapter;
    final oldSrc = AccountApi.tokenSource;
    AccountApi.dio.httpClientAdapter = cap;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct-token';
    addTearDown(() {
      AccountApi.dio.httpClientAdapter = old;
      AccountApi.tokenSource = oldSrc;
    });
    await AccountApi.resumeCompany(const LinkedCompany(
        sasCode: 'jt', sasUrl: 'https://example.invalid', username: 'admin@jt', label: 'الجزيرة', role: 'admin'));
    expect(cap.path, '/api/account/companies/resume');
    expect(cap.headers['x-app-build'], '176');
    expect(cap.headers['x-device-label'], isNotNull);
    expect(cap.headers['x-account-token'], 'acct-token');
  });

  test('المساعد بوضع الحساب يرسل رقم النسخة', () async {
    final cap = _Capture()..reply = (200, {'success': true, 'enabled': false});
    final old = AiApi.accountDio.httpClientAdapter;
    final oldSrc = AiApi.accountTokenSource;
    final oldHas = AiApi.hasAccount;
    AiApi.accountDio.httpClientAdapter = cap;
    AiApi.accountTokenSource = ({bool force = false}) async => 'acct-token';
    AiApi.hasAccount = () => true;
    addTearDown(() {
      AiApi.accountDio.httpClientAdapter = old;
      AiApi.accountTokenSource = oldSrc;
      AiApi.hasAccount = oldHas;
    });
    await AiApi.status();
    expect(cap.path, endsWith('/status'));
    expect(cap.headers['x-app-build'], '176');
    expect(cap.headers['x-account-token'], 'acct-token');
  });
}
