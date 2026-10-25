import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/auth_api.dart';
import 'package:rad_mysvcs/services/auth_storage.dart';
import 'package:rad_mysvcs/services/company_creds_store.dart';
import 'package:rad_mysvcs/services/sas_login_flow.dart';
import 'package:rad_mysvcs/services/saved_profiles_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «عدم حفظ الجلسة» يعني ما يقول (٢٥ أكتوبر — المالك: «من ما يعلّم حفظ الجلسة لازم من يدخل يطلب معلومات من جديد»،
/// والتوكن يبقى عند الخادم للواتساب).
///
/// الحرّاس: الاختيار يصل الخادم صريحاً (`remember`)؛ إثبات الجلسة (`x-session-proof`) يُلتقط ويُحفظ على هذا الجهاز ويُرسَل مع
/// التجديد ويتجدّد منه؛ و«عدم حفظ الجلسة» لا يُبقي كلمة السرّ على الهاتف (ولا ما حُفظ قبلها لهذه الشركة) — فلا يفتحها «شركاتي»
/// بضغطة. الخادم يرفض الاستئناف والتجديد بلا إثبات (server/linkResume.js).
void main() {
  late _FakeAdapter adapter;

  Map<String, dynamic> loginOk() => {
        'success': true,
        'token': 'tok-1',
        'expiresAt': '2026-10-26T10:00:00Z',
        'user': {'id': 'jt:6836', 'username': 'admin@jt', 'name': 'مدير', 'role': 'admin'},
      };

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    adapter = _FakeAdapter();
    ApiClient.dio.httpClientAdapter = adapter;
    AuthApi.refreshAdapterForTest = null;
    AuthApi.accountTokenForTest = null;
    SasLoginFlow.fcmInit = () async {};
  });

  group('AuthApi.login — الاختيار والإثبات', () {
    test('remember يصل صريحاً (true/false)، ولا يُرسَل من مستدعٍ قديم (null)', () async {
      adapter.reply = (200, loginOk(), const <String, String>{});
      await AuthApi.login(username: 'admin@jt', password: 'pw', remember: false);
      expect(adapter.lastBody['remember'], isFalse);
      await AuthApi.login(username: 'admin@jt', password: 'pw', remember: true);
      expect(adapter.lastBody['remember'], isTrue);
      await AuthApi.login(username: 'admin@jt', password: 'pw');
      expect(adapter.lastBody.containsKey('remember'), isFalse);
    });

    test('إثبات الجلسة من الترويسة يُلتقط في LoginSuccess، وغيابه null', () async {
      adapter.reply = (200, loginOk(), const {'x-session-proof': 'v1.1761400000.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'});
      final r = await AuthApi.login(username: 'admin@jt', password: 'pw', remember: false);
      expect(r, isA<LoginSuccess>());
      expect((r as LoginSuccess).sessionProof, 'v1.1761400000.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
      expect(r.token, 'tok-1');
      adapter.reply = (200, loginOk(), const <String, String>{});
      final r2 = await AuthApi.login(username: 'admin@jt', password: 'pw');
      expect((r2 as LoginSuccess).sessionProof, isNull);
    });
  });

  group('AuthApi.refreshTokenDetailed — الإثبات', () {
    late _FakeAdapter refresh;
    setUp(() async {
      refresh = _FakeAdapter();
      AuthApi.refreshAdapterForTest = refresh;
      AuthApi.accountTokenForTest = () async => 'acct-token';
      await AuthStorage.saveSession(
        token: 'old', adminId: 'jt:6836', adminUsername: 'admin@jt', displayName: 'مدير', autoLogin: false);
    });

    test('يُرسَل الإثبات المحفوظ ويُستبدل بالجديد من الردّ', () async {
      await AuthStorage.saveSessionProof('v1.1.OLD');
      refresh.reply = (200, {'success': true, 'token': 'new', 'expiresAt': '2026-10-26T11:00:00Z'}, const {'x-session-proof': 'v1.2.NEW'});
      final out = await AuthApi.refreshTokenDetailed();
      expect(out, RefreshOutcome.ok);
      expect(refresh.lastHeaders['x-session-proof'], 'v1.1.OLD');
      expect(refresh.lastHeaders['x-account-token'], 'acct-token');
      expect(await AuthStorage.readSessionProof(), 'v1.2.NEW');
      expect(await AuthStorage.readToken(), 'new');
    });

    test('بلا إثبات لا ترويسة (ربطٌ محفوظٌ يجدّد كما كان)؛ ورفض الخادم (٤٠٣ password-required) ⇒ serverRejected بلا مسّ', () async {
      refresh.reply = (200, {'success': true, 'token': 'new2'}, const <String, String>{});
      expect(await AuthApi.refreshTokenDetailed(), RefreshOutcome.ok);
      expect(refresh.lastHeaders.containsKey('x-session-proof'), isFalse);
      expect(await AuthStorage.readSessionProof(), isNull);
      await AuthStorage.saveSessionProof('v1.1.KEEP');
      refresh.reply = (403, {'success': false, 'error': 'password-required', 'message': 'سجّل الدخول'}, const <String, String>{});
      expect(await AuthApi.refreshTokenDetailed(), RefreshOutcome.serverRejected);
      expect(await AuthStorage.readToken(), 'new2');
    });

    test('الخروج يمحو الإثبات مع الجلسة', () async {
      await AuthStorage.saveSessionProof('v1.1.X');
      await AuthStorage.clear();
      expect(await AuthStorage.readSessionProof(), isNull);
    });
  });

  group('SasLoginFlow.complete — كلمة السرّ على الهاتف', () {
    LoginSuccess ok({String? proof}) => LoginSuccess(
          token: 'tok',
          adminId: 'jt:6836',
          adminUsername: 'admin@jt',
          displayName: 'مدير',
          sessionProof: proof,
        );

    test('🚨 «عدم حفظ الجلسة»: لا تُحفظ، وما حُفظ قبلها لهذه الشركة يُمحى — والإثبات يُحفظ', () async {
      adapter.reply = (200, {'success': true, 'provider': 'sas4'}, const <String, String>{});
      await CompanyCredsStore.upsert(sasUrl: 'https://sas.jt.iq', username: 'admin@jt', password: 'old-pw');
      await SavedProfilesStore.upsert(username: 'admin@jt', plainPassword: 'old-pw', displayName: 'مدير');
      final out = await SasLoginFlow.complete(ok(proof: 'v1.9.P'),
          username: 'admin@jt', password: 'pw', sasUrl: 'https://sas.jt.iq', remember: false);
      expect(out, SasLoginOutcome.ok);
      await Future<void>.delayed(const Duration(milliseconds: 50)); // الكتابات غير المنتظَرة
      expect(await CompanyCredsStore.passwordFor('https://sas.jt.iq', 'admin@jt'), isNull);
      expect((await SavedProfilesStore.list()).where((p) => p.username == 'admin@jt'), isEmpty);
      expect(await AuthStorage.readSessionProof(), 'v1.9.P');
    });

    test('«حفظ الجلسة»: تُحفظ كما كانت', () async {
      adapter.reply = (200, {'success': true, 'provider': 'sas4'}, const <String, String>{});
      await SasLoginFlow.complete(ok(), username: 'admin@jt', password: 'pw', sasUrl: 'https://sas.jt.iq', remember: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await CompanyCredsStore.passwordFor('https://sas.jt.iq', 'admin@jt'), 'pw');
      expect(await AuthStorage.readSessionProof(), isNull, reason: 'دخولٌ بلا إثبات يمسح إثبات سابقه');
    });
  });
}

/// خادمٌ وهميّ لـDio — يردّ بما في [reply] (الحالة، الجسم، الترويسات) ويحفظ آخر طلب.
class _FakeAdapter implements HttpClientAdapter {
  (int, Map<String, dynamic>, Map<String, String>) reply = (200, {'success': true}, const {});
  RequestOptions? _last;

  Map<String, dynamic> get lastBody => Map<String, dynamic>.from(_last!.data as Map);
  Map<String, dynamic> get lastHeaders => _last!.headers;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    _last = options;
    final (status, body, headers) = reply;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        for (final e in headers.entries) e.key: [e.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
