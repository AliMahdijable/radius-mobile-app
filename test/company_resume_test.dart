import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/auth_api.dart';
import 'package:rad_mysvcs/services/account_service.dart';

/// «استئناف الشركة» في التطبيق (٢٣ أكتوبر — تبديلٌ بلا خروجٍ ودخول): `POST /api/account/companies/resume` بتوكن
/// الحساب. ردٌّ ناجح بشكل ردّ الدخول ⇒ جلسة؛ وكلّ ما سواه ⇒ `null` بلا رميٍ ولا رسالة (يكمل الدخول المعتاد).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  LinkedCompany co({String role = 'admin', String code = 'jt', String user = 'ali.jt'}) => LinkedCompany(
      sasCode: code, sasUrl: 'https://sas.jt.iq', username: user, label: 'جي تي', role: role);

  late _Fake fake;
  setUp(() {
    fake = _Fake();
    AccountApi.dio.httpClientAdapter = fake;
    AccountApi.tokenSource = ({bool force = false}) async => 'account-test';
  });
  tearDown(() => AccountApi.tokenSource = AccountService.idToken);

  test('نجاحٌ ⇒ جلسةٌ بصلاحيّاتها كالدخول، والطلب بهدفه وترويسات التطبيق', () async {
    fake.status = 200;
    fake.body = {
      'success': true,
      'token': 'tok-resumed',
      'expiresAt': '2099-01-01T00:00:00.000Z',
      'user': {
        'id': 'jt:77',
        'username': 'ali.jt',
        'role': 'admin',
        'permissions': ['prm_managers_create'],
        'canonicalPermissions': {'subscribers.delete': false, 'subscribers.add': true},
      },
      'resumed': true,
    };
    final r = await AccountApi.resumeCompany(co());
    expect(r, isA<LoginSuccess>());
    final s = r! as LoginSuccess;
    expect(s.token, 'tok-resumed');
    expect(s.adminId, 'jt:77');
    expect(s.adminUsername, 'ali.jt');
    expect(s.expiresAt, '2099-01-01T00:00:00.000Z');
    expect(s.canAccessManagers, isTrue);
    expect(s.isEmployee, isFalse);
    expect(s.canonicalPermissions, {'subscribers.delete': false, 'subscribers.add': true});
    final o = fake.requests.single;
    expect(o.method, 'POST');
    expect(o.path, '/api/account/companies/resume');
    expect(o.data, {'sas_code': 'jt', 'username': 'ali.jt'});
    expect(o.headers['x-account-token'], 'account-test');
    expect(o.headers['x-device-label'], 'android');
    expect((o.headers['x-device-id'] ?? '').toString(), isNotEmpty);
    expect(o.headers.containsKey('Authorization'), isFalse, reason: 'لا توكن ساس على مسار الحساب');
  });

  for (final c in [
    (409, 'RESUME_SESSION_DEAD'),
    (403, 'RESUME_2FA_REQUIRED'),
    (403, 'RESUME_NOT_LINKED'),
    (403, 'device-limit'),
    (403, 'ftth-web-only'),
    (429, 'RESUME_RATE_LIMITED'),
    (402, 'subscription-ended'),
  ]) {
    test('رفض ${c.$1} ${c.$2} ⇒ null (الدخول المعتاد يقول السبب)', () async {
      fake.status = c.$1;
      fake.body = {'success': false, 'error': c.$2, 'message': 'x'};
      expect(await AccountApi.resumeCompany(co()), isNull);
      expect(fake.requests, hasLength(1));
    });
  }

  test('٥٠٣ (مفتاح الإيقاف) أو انقطاع الشبكة ⇒ null بلا رمي', () async {
    fake.status = 503;
    fake.body = {'success': false, 'error': 'RESUME_UNAVAILABLE'};
    expect(await AccountApi.resumeCompany(co()), isNull);
    fake.throwNetwork = true;
    expect(await AccountApi.resumeCompany(co()), isNull);
  });

  test('٢٠٠ بلا توكن ⇒ null', () async {
    fake.status = 200;
    fake.body = {'success': true, 'user': {'id': 'jt:77', 'username': 'ali.jt'}};
    expect(await AccountApi.resumeCompany(co()), isNull);
  });

  test('ربط موظّف أو بلا كود/يوزر ⇒ null بلا طلبٍ أصلاً (الخادم لا يستأنف الموظّف)', () async {
    expect(await AccountApi.resumeCompany(co(role: 'employee')), isNull);
    expect(await AccountApi.resumeCompany(co(code: ' ')), isNull);
    expect(await AccountApi.resumeCompany(co(user: '')), isNull);
    expect(fake.requests, isEmpty);
  });

  test('بلا حساب Pro (خرج من الحساب) ⇒ null بلا طلب', () async {
    AccountApi.tokenSource = ({bool force = false}) async => null;
    expect(await AccountApi.resumeCompany(co()), isNull);
    expect(fake.requests, isEmpty);
  });
}

class _Fake implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 404;
  Map<String, dynamic> body = const {'success': false};
  bool throwNetwork = false;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(o);
    if (throwNetwork) {
      throw DioException.connectionError(requestOptions: o, reason: 'offline');
    }
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}
