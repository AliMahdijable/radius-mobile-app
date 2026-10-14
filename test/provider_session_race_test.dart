import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/services/auth_storage.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// سباق `ProviderService.refreshFromBackend`: ردّ `/api/auth/me` يصل بعد أن
/// تبدّلت الجلسة. (مراجعة ٢٠٢٦-١٠-١٣، أُعيد إنتاجه هنا قبل الإصلاح)
///
/// قبل الإصلاح: ردّ مالك ايرث لنك العالق يُكتب على مدير ساس سوبر دخل بعده —
/// المزوّد `earthlink` وقدرات ايرث لنك المقيَّدة، في الذاكرة **والخزنة**؛
/// والتحديثات اللاحقة تُصلح المزوّد ولا تُصلح القدرات أبداً.
void main() {
  const vault = FlutterSecureStorage();
  late _MeServer server;

  /// ردّ `/me` لمالك ايرث لنك: قدراتٌ معياريّة مقيَّدة (الحذف ممنوع).
  const elOwner = {
    'success': true,
    'provider': 'earthlink',
    'user': {
      'provider': 'earthlink',
      'isEmployee': false,
      'isSuperAdmin': false,
      'canonicalPermissions': {
        'subscribers.add': true,
        'subscribers.delete': false,
      },
    },
  };

  /// ردّ `/me` لمدير ساس سوبر: بلا مزوّد.
  const sasSuper = {
    'success': true,
    'user': {'isEmployee': false, 'isSuperAdmin': true},
  };

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    server = _MeServer();
    ApiClient.dio.httpClientAdapter = server;
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
  });
  tearDown(PermissionsService.debugReset);

  Future<void> login(String token, String adminId, {bool superAdmin = false}) =>
      AuthStorage.saveSession(
        token: token,
        adminId: adminId,
        adminUsername: 'u',
        displayName: 'u',
        autoLogin: true,
        isSuperAdmin: superAdmin,
      );

  /// أوّل تبديل الشركة كما في `SessionManager.clearAllSessionData`
  /// (`clearAuth:false`: التوكن والمعرّف القديمان باقيان حتى يُكتب الجديد).
  Future<void> beginSwitch() =>
      Future.wait([PermissionsService.clear(), ProviderService.clear()]);

  /// لا قيدَ على مديرٍ — لا في الذاكرة ولا في الخزنة.
  Future<void> expectUnrestricted() async {
    expect(PermissionsService.has('subscribers.delete'), isTrue);
    expect(await vault.read(key: 'perms.mgr_restricted'), isNull);
    expect(await vault.read(key: 'perms.mgr_caps'), isNull);
  }

  group('ردٌّ عن جلسةٍ سابقة لا يُطبَّق', () {
    test('🚨 مالك ايرث لنك ← مدير ساس سوبر: الردّ العالق يُهمَل', () async {
      await login('el', 'earthlink:7');
      await ProviderService.setProvider('earthlink');
      server.replies['el'] = elOwner;
      server.replies['sas'] = sasSuper;
      server.hold('el');
      final stale = ProviderService.refreshFromBackend();
      await server.arrived('el');

      // تبديل الشركة (`SasLoginFlow.complete`): مسحٌ ← حفظ الجلسة ← قدرات
      // السوبر ← تحديثه هو (provider=null).
      await beginSwitch();
      await login('sas', '42', superAdmin: true);
      await PermissionsService.setManagerCapabilities(
        isSuperAdmin: true,
        canonical: const {},
      );
      await ProviderService.refreshFromBackend();
      expect(ProviderService.isEarthlink, isFalse);

      server.release('el');
      await stale;

      expect(ProviderService.isEarthlink, isFalse);
      expect(await vault.read(key: 'provider.current'), isNull);
      await expectUnrestricted();

      // وتحديثٌ لاحقٌ للجلسة الجديدة يبقيها كما هي.
      await ProviderService.refreshFromBackend();
      expect(ProviderService.isEarthlink, isFalse);
      await expectUnrestricted();
    });

    test('🚨 ولا في النافذة بين المسح وحفظ الجلسة الجديدة', () async {
      await login('el', 'earthlink:7');
      await ProviderService.setProvider('earthlink');
      server.replies['el'] = elOwner;
      server.hold('el');
      final stale = ProviderService.refreshFromBackend();
      await server.arrived('el');

      // بدأ التبديل ولم تُكتب الجلسة الجديدة بعد: التوكن والمعرّف ما زالا
      // لمالك ايرث لنك، فلا يكشفه إلّا جيل الجلسة.
      await beginSwitch();
      server.release('el');
      await stale;

      expect(ProviderService.isEarthlink, isFalse);
      expect(await vault.read(key: 'provider.current'), isNull);
      await expectUnrestricted();
    });

    test('🚨 ولا ردٌّ سُئل عنه أثناء التبديل بالتوكن القديم', () async {
      // التحديث بدأ بعد المسح (فالجيل لا يتغيّر بعده) بتوكن ايرث لنك الباقي،
      // ووصل ردّه بعد حفظ الجلسة الجديدة: لا يكشفه إلّا التوكن والمعرّف.
      await login('el', 'earthlink:7');
      server.replies['el'] = elOwner;
      await beginSwitch();
      server.hold('el');
      final stale = ProviderService.refreshFromBackend();
      await server.arrived('el');
      await login('sas', '42', superAdmin: true);
      await PermissionsService.setManagerCapabilities(
        isSuperAdmin: true,
        canonical: const {},
      );
      server.release('el');
      await stale;

      expect(ProviderService.isEarthlink, isFalse);
      expect(await vault.read(key: 'provider.current'), isNull);
      await expectUnrestricted();
    });
  });

  group('بلا تبديل: الدلالة كما كانت', () {
    test('مالك ايرث لنك: المزوّد وقدراته الطازجة', () async {
      await login('el', 'earthlink:7');
      server.replies['el'] = elOwner;
      await ProviderService.refreshFromBackend();

      expect(ProviderService.isEarthlink, isTrue);
      expect(await vault.read(key: 'provider.current'), 'earthlink');
      expect(PermissionsService.has('subscribers.add'), isTrue);
      expect(PermissionsService.has('subscribers.delete'), isFalse);
      expect(await vault.read(key: 'perms.mgr_restricted'), '1');
    });

    test('مدير ساس: النجاح يضبط المزوّد null ولا يمسّ القدرات', () async {
      await login('sas', '42', superAdmin: true);
      await ProviderService.setProvider('earthlink');
      server.replies['sas'] = sasSuper;
      await ProviderService.refreshFromBackend();

      expect(ProviderService.isEarthlink, isFalse);
      expect(await vault.read(key: 'provider.current'), isNull);
      await expectUnrestricted();
    });

    test('الفشل لا يمسح آخر قيمةٍ معروفة', () async {
      await login('el', 'earthlink:7');
      await ProviderService.setProvider('earthlink');
      // لا ردّ مسجَّل لهذا التوكن ⇒ ٤٠١.
      await ProviderService.refreshFromBackend();

      expect(ProviderService.isEarthlink, isTrue);
      expect(await vault.read(key: 'provider.current'), 'earthlink');
    });
  });

  test('القدرات لمعرّف مالك ايرث لنك وحده (`earthlink:`)', () async {
    // ردٌّ يقول earthlink لجلسةٍ معرّفها المحفوظ ليس لمالك ايرث لنك:
    // المزوّد يُضبط (دلالته كما كانت)، والقدرات لا تُمَسّ.
    await login('el', '42');
    server.replies['el'] = elOwner;
    await ProviderService.refreshFromBackend();

    expect(ProviderService.isEarthlink, isTrue);
    await expectUnrestricted();
  });
}

/// خادمٌ وهميّ لـ`/api/auth/me` يعرف الجلسة من توكنها كالخادم الحقيقيّ.
/// توكنٌ بلا ردٍّ مسجَّل ⇒ ٤٠١. وردّ توكنٍ «محبوس» ينتظر [release] —
/// طلبٌ عالقٌ في الطريق.
class _MeServer implements HttpClientAdapter {
  final replies = <String, Map<String, dynamic>>{};
  final _held = <String, Completer<void>>{};
  final _arrived = <String, Completer<void>>{};

  void hold(String token) => _held[token] = Completer<void>();
  void release(String token) => _held.remove(token)!.complete();

  /// يكتمل حين يصل طلب هذا التوكن (أي صار في الطريق فعلاً).
  Future<void> arrived(String token) =>
      _arrived.putIfAbsent(token, Completer<void>.new).future;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final token = options.headers['x-auth-token']?.toString() ?? '';
    final came = _arrived.putIfAbsent(token, Completer<void>.new);
    if (!came.isCompleted) came.complete();
    final gate = _held[token];
    if (gate != null) await gate.future;
    final body = replies[token];
    return ResponseBody.fromString(
      jsonEncode(body ?? const {'success': false}),
      body == null ? 401 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
