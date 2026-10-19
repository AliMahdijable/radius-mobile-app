import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/services/auth_storage.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// قدرات المدير تتحدّث عند الإقلاع لكلّ مدير — لا لايرث لنك وحده (٣.٠.٣+١٦٣).
///
/// 🐛 تدقيق المدير المقيَّد ١٨ أكتوبر (admin@hhnn، `next-gen:175`): أخرج الخادم
/// `reports.financial` من خريطة قدرات الساس (1ac4fb2)، لكنّ التطبيق يحفظ الخريطة
/// وقت الدخول ولا يحدّثها إلّا لمالك ايرث لنك — فبقي رصيده وإيراداته وتقريره الماليّ
/// «لا صلاحيّة» حتى يخرج ويدخل. الآن: ① الإقلاع يسأل `/api/auth/me` لكلّ جلسة ويطبّق
/// قدرات المدير **إذا** طابقت هويّةُ الردّ المعرّفَ المحفوظ؛ ② المفاتيح المتقاعدة
/// (`reports.financial`، `self.2fa`) تسقط من خريطة المدير المحفوظة والجديدة.
void main() {
  const vault = FlutterSecureStorage();
  late _MeServer server;

  /// ردّ `/me` لمديرٍ (لا موظّف) بهويّة [id] وخريطة [caps].
  Map<String, Object?> manager(
    String? id,
    Map<String, bool>? caps, {
    bool superAdmin = false,
    String? provider,
  }) =>
      {
        'success': true,
        if (provider != null) 'provider': provider,
        'user': {
          if (id != null) 'id': id,
          'role': superAdmin ? 'super_admin' : 'admin',
          'isEmployee': false,
          'isSuperAdmin': superAdmin,
          if (provider != null) 'provider': provider,
          'permissions': const <String>[],
          'canonicalPermissions': caps,
        },
      };

  /// خريطة الدخول القديمة لمديرٍ فرعيّ: الحذف ممنوع، والتقرير الماليّ «ممنوع»
  /// (المفتاح الذي أخرجه الخادم لاحقاً).
  const loginCaps = {
    'subscribers.view': true,
    'subscribers.delete': false,
    'reports.financial': false,
  };

  /// قدرات `/me` الطازجة: الحذف صار مسموحاً، وكلمة المرور ممنوعة — وبلا
  /// `reports.financial` (الخادم أخرجه).
  const freshCaps = {
    'subscribers.view': true,
    'subscribers.delete': true,
    'subscribers.show_password': false,
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

  Future<void> login(String token, String adminId, {bool employee = false}) =>
      AuthStorage.saveSession(
        token: token,
        adminId: adminId,
        adminUsername: 'u',
        displayName: 'u',
        autoLogin: true,
        isEmployee: employee,
      );

  /// المدير الفرعيّ كما يحفظه دخولٌ قديم: مقيَّد بـ[loginCaps].
  Future<void> restrictedLogin(String token, String adminId) async {
    await login(token, adminId);
    await PermissionsService.setManagerCapabilities(
      isSuperAdmin: false,
      canonical: loginCaps,
    );
  }

  /// الإقلاع بجلسةٍ محفوظة والتوكن صالح.
  Future<void> coldStart() =>
      ProviderService.refreshOnColdStart(Future<void>.value());

  Future<Map<String, Object?>?> storedCaps() async {
    final raw = await vault.read(key: 'perms.mgr_caps');
    return raw == null ? null : Map<String, Object?>.from(jsonDecode(raw) as Map);
  }

  /// القدرات كما حفظها الدخول (ما عدا المفتاح المتقاعد الذي سقط عند الحفظ).
  Future<void> expectLoginCaps() async {
    expect(PermissionsService.has('subscribers.delete'), isFalse);
    expect(PermissionsService.has('subscribers.show_password'), isTrue);
    expect(await storedCaps(), {
      'subscribers.view': true,
      'subscribers.delete': false,
    });
  }

  group('① الإقلاع: قدرات /me لكلّ مدير — بشرط الهويّة', () {
    test('🚨 مدير ساس الأصل (42): القدرات الطازجة تُطبَّق وتُحفظ', () async {
      await restrictedLogin('sas', '42');
      server.replies['sas'] = manager('42', freshCaps);
      await coldStart();

      expect(server.asked, ['sas']);
      expect(server.paths, ['/api/auth/me']);
      expect(PermissionsService.has('subscribers.delete'), isTrue);
      expect(PermissionsService.has('subscribers.show_password'), isFalse);
      expect(PermissionsService.has('reports.financial'), isTrue);
      expect(await vault.read(key: 'perms.mgr_restricted'), '1');
      expect(await storedCaps(), freshCaps);
      expect(ProviderService.isEarthlink, isFalse);
    });

    test('🚨 مدير ساسٍ بعيد (next-gen:175): هويّته المؤهَّلة تطابق ⇒ تُطبَّق',
        () async {
      await restrictedLogin('ng', 'next-gen:175');
      server.replies['ng'] = manager('next-gen:175', freshCaps);
      await coldStart();

      expect(PermissionsService.has('subscribers.delete'), isTrue);
      expect(PermissionsService.has('subscribers.show_password'), isFalse);
      expect(await storedCaps(), freshCaps);
    });

    test('مدير سوبر: الردّ يفكّ القيد كلّه', () async {
      await restrictedLogin('sas', '42');
      server.replies['sas'] =
          manager('42', const {'subscribers.delete': true}, superAdmin: true);
      await coldStart();

      expect(PermissionsService.has('subscribers.delete'), isTrue);
      expect(PermissionsService.has('anything.else'), isTrue);
      expect(await vault.read(key: 'perms.mgr_restricted'), isNull);
      expect(await vault.read(key: 'perms.mgr_caps'), isNull);
    });

    test('مالك ايرث لنك ما زال يتحدّث (earthlink:7)', () async {
      await restrictedLogin('el', 'earthlink:7');
      server.replies['el'] =
          manager('earthlink:7', freshCaps, provider: 'earthlink');
      await coldStart();

      expect(ProviderService.isEarthlink, isTrue);
      expect(PermissionsService.has('subscribers.delete'), isTrue);
      expect(await storedCaps(), freshCaps);
    });

    for (final c in <(String, String?)>[
      ('بلا بادئة الساس (175)', '175'),
      ('مديرٌ آخر على الساس نفسه (next-gen:176)', 'next-gen:176'),
      ('ساسٌ آخر بالرقم نفسه (jt:175)', 'jt:175'),
      ('ردٌّ بلا هويّة', null),
    ]) {
      test('🚨 هويّةٌ لا تطابق next-gen:175 — ${c.$1}: القدرات كما هي', () async {
        await restrictedLogin('ng', 'next-gen:175');
        server.replies['ng'] = manager(c.$2, freshCaps);
        await coldStart();

        expect(server.asked, ['ng'], reason: 'سُئل الخادم فعلاً');
        await expectLoginCaps();
      });
    }

    test('🚨 موظّف: ردّه (isEmployee=true) لا يمسّ صلاحيّاته', () async {
      await login('emp', '42', employee: true);
      PermissionsService.debugSet(
        isEmployee: true,
        permissions: const {'subscribers.view': true, 'reports.financial': true},
      );
      server.replies['emp'] = {
        'success': true,
        'user': {
          'id': '42',
          'role': 'employee',
          'isEmployee': true,
          'isSuperAdmin': false,
          'canonicalPermissions': null,
          'permissions': const {'subscribers.view': true},
        },
      };
      await coldStart();

      expect(server.asked, ['emp']);
      expect(PermissionsService.isEmployee, isTrue);
      expect(PermissionsService.has('subscribers.view'), isTrue);
      expect(PermissionsService.has('reports.financial'), isTrue);
      expect(PermissionsService.has('subscribers.delete'), isFalse);
      expect(await vault.read(key: 'perms.mgr_caps'), isNull);
    });

    test('🚨 ردٌّ يقول «موظّف» (ولو بخريطةٍ وبالهويّة نفسها) لا يُكتب على مدير',
        () async {
      await restrictedLogin('sas', '42');
      server.replies['sas'] = {
        'success': true,
        'user': {
          'id': '42',
          'role': 'employee',
          'isEmployee': true,
          'isSuperAdmin': false,
          'canonicalPermissions': freshCaps,
        },
      };
      await coldStart();

      expect(server.asked, ['sas']);
      await expectLoginCaps();
    });

    test('🚨 جلسةٌ موظّفةٌ محلّيّاً وردٌّ يقول «مدير» بهويّتها: يُهمَل', () async {
      await login('emp', '42', employee: true);
      PermissionsService.debugSet(
        isEmployee: true,
        permissions: const {'subscribers.view': true},
      );
      server.replies['emp'] = manager('42', freshCaps);
      await coldStart();

      expect(PermissionsService.isEmployee, isTrue);
      expect(PermissionsService.has('subscribers.delete'), isFalse,
          reason: 'لا ترقية موظّفٍ إلى قدرات أبيه');
      expect(await vault.read(key: 'perms.mgr_caps'), isNull);
    });

    test('🚨 خريطةٌ كلّها false (ساسٌ ردّ /auth بلا صلاحيّات): لا تُقفل شيئاً',
        () async {
      await restrictedLogin('sas', '42');
      server.replies['sas'] = manager('42', const {
        'subscribers.view': false,
        'subscribers.delete': false,
        'subscribers.show_password': false,
      });
      await coldStart();

      expect(PermissionsService.has('subscribers.view'), isTrue);
      await expectLoginCaps();
    });

    test('ردٌّ بلا خريطة: القدرات كما هي', () async {
      await restrictedLogin('sas', '42');
      server.replies['sas'] = manager('42', null);
      await coldStart();
      await expectLoginCaps();
    });

    test('فشل /me (توكنٌ مرفوض): القدرات كما هي', () async {
      await restrictedLogin('sas', '42');
      // لا ردّ مسجَّل ⇒ ٤٠١.
      await coldStart();
      expect(server.asked, ['sas']);
      await expectLoginCaps();
    });

    test('🚨 يُسأل بعد تجديد التوكن لا قبله — وبالتوكن الجديد', () async {
      await restrictedLogin('old', 'next-gen:175');
      server.replies['new'] = manager('next-gen:175', freshCaps);
      final renewed = Completer<void>();
      final run = ProviderService.refreshOnColdStart(renewed.future);

      // التجديد جارٍ: لا سؤال بالتوكن المنتهي (المعترض لا يعيد /api/auth/*).
      await pumpEventQueue();
      expect(server.asked, isEmpty);

      await AuthStorage.saveRefreshedToken(token: 'new');
      renewed.complete();
      await run;

      expect(server.asked, ['new']);
      expect(PermissionsService.has('subscribers.delete'), isTrue);
    });

    test('تعثّر التجديد لا يمنع السؤال بما في الخزنة', () async {
      await restrictedLogin('sas', '42');
      server.replies['sas'] = manager('42', freshCaps);
      await ProviderService.refreshOnColdStart(
          Future<void>.error(StateError('refresh failed')));

      expect(server.asked, ['sas']);
      expect(PermissionsService.has('subscribers.delete'), isTrue);
    });

    test('🚨 ردٌّ عن جلسةٍ تبدّلت أثناء السؤال لا يُطبَّق', () async {
      await restrictedLogin('ng', 'next-gen:175');
      server.replies['ng'] = manager('next-gen:175', freshCaps);
      server.hold('ng');
      final run = coldStart();
      await server.arrived('ng');

      // خروجٌ ودخول مديرٍ آخر قبل وصول الردّ.
      await Future.wait([PermissionsService.clear(), ProviderService.clear()]);
      await restrictedLogin('other', 'next-gen:176');
      server.release('ng');
      await run;

      await expectLoginCaps();
    });
  });

  // الإقلاع نفسه (SplashScreen) لا يُرسم في اختبار — يبني MainShell كاملاً وFCM
  // وFirebase. فحارسٌ على نصّه: كان النداء محجوزاً بـ`if (direct ||
  // ProviderService.isEarthlink)`، وعودة شرطٍ كهذا تُعيد العطل بلا أيّ اختبارٍ أحمر.
  test('🚨 الإقلاع يحدّث كلّ جلسة: refreshOnColdStart بلا شرط مزوّد', () {
    final lines =
        File('lib/screens/splash_screen.dart').readAsLinesSync();
    bool code(String l) {
      final t = l.trim();
      return t.isNotEmpty && !t.startsWith('//') && !t.startsWith('///');
    }

    final calls = [
      for (var i = 0; i < lines.length; i++)
        if (code(lines[i]) &&
            lines[i].contains('ProviderService.refreshOnColdStart('))
          i,
    ];
    expect(calls, hasLength(1),
        reason: 'نداءٌ واحد بعد الدخول التلقائيّ — تغيّر الملفّ؟ حدّث الحارس');
    final prev = lines.sublist(0, calls.single).lastWhere(code).trim();
    expect(prev.endsWith(';'), isTrue,
        reason: 'النداء بمستوى بقيّة نداءات الإقلاع لا داخل شرط: «$prev»');
    final src = lines.where(code).join('\n');
    expect(src.contains('ProviderService.isEarthlink'), isFalse,
        reason: 'لا حجز للتحديث بمزوّد');
    expect(src.contains('ProviderService.refreshFromBackend('), isFalse,
        reason: 'الإقلاع يمرّ بـrefreshOnColdStart (بعد تجديد التوكن)');
  });

  group('② المفاتيح المتقاعدة (reports.financial، self.2fa) تسقط من خريطة المدير',
      () {
    test('🚨 خريطةٌ محفوظة قبل التحديث: تسقط عند الإقلاع (init)', () async {
      FlutterSecureStorage.setMockInitialValues({
        'perms.mgr_restricted': '1',
        'perms.mgr_caps': jsonEncode(const {
          'reports.financial': false,
          'self.2fa': false,
          'subscribers.delete': false,
        }),
      });
      PermissionsService.debugReset();
      await PermissionsService.init();

      expect(PermissionsService.has('reports.financial'), isTrue);
      expect(PermissionsService.has('self.2fa'), isTrue);
      expect(PermissionsService.has('subscribers.delete'), isFalse,
          reason: 'بقيّة الخريطة كما هي');
      expect(
          PermissionsService.hasAll(const ['reports.financial', 'self.2fa']),
          isTrue);
    });

    test('🚨 خريطةٌ جديدة: لا تُحفظ ولا تُقرأ (setManagerCapabilities)',
        () async {
      await PermissionsService.setManagerCapabilities(
        isSuperAdmin: false,
        canonical: const {
          'reports.financial': false,
          'self.2fa': false,
          'subscribers.delete': false,
        },
      );

      expect(PermissionsService.has('reports.financial'), isTrue);
      expect(PermissionsService.has('self.2fa'), isTrue);
      expect(PermissionsService.has('subscribers.delete'), isFalse);
      expect(await storedCaps(), {'subscribers.delete': false});
    });

    test('خريطةٌ لم يبقَ فيها غير المتقاعد = فارغة ⇒ غير مقيَّد', () async {
      await PermissionsService.setManagerCapabilities(
        isSuperAdmin: false,
        canonical: const {'reports.financial': false, 'self.2fa': false},
      );

      expect(PermissionsService.has('reports.financial'), isTrue);
      expect(await vault.read(key: 'perms.mgr_restricted'), isNull);
      expect(await vault.read(key: 'perms.mgr_caps'), isNull);
    });

    test('مفتاحٌ متقاعد بقيمة true يسقط أيضاً — والنتيجة مسموح', () async {
      await PermissionsService.setManagerCapabilities(
        isSuperAdmin: false,
        canonical: const {'reports.financial': true, 'subscribers.delete': false},
      );
      expect(PermissionsService.has('reports.financial'), isTrue);
      expect(await storedCaps(), {'subscribers.delete': false});
    });

    test('🚨 الموظّف لا يُمَسّ: reports.financial من صلاحيّاته عندنا', () async {
      FlutterSecureStorage.setMockInitialValues({
        'perms.is_employee': '1',
        'perms.employee_map': jsonEncode(const {
          'reports.financial': false,
          'subscribers.view': true,
        }),
      });
      PermissionsService.debugReset();
      await PermissionsService.init();

      expect(PermissionsService.isEmployee, isTrue);
      expect(PermissionsService.has('reports.financial'), isFalse);
      expect(PermissionsService.has('subscribers.view'), isTrue);
    });

    test('🚨 ①+②: خريطة دخولٍ قديمة ثمّ إقلاع ⇒ الرصيد والتقرير مفتوحان',
        () async {
      // كما على جهاز admin@hhnn: الخريطة المحفوظة من ٣.٠.٣+١٦٢ تحمل
      // reports.financial=false.
      FlutterSecureStorage.setMockInitialValues({
        'auth.token': 'ng',
        'auth.admin_id': 'next-gen:175',
        'perms.mgr_restricted': '1',
        'perms.mgr_caps': jsonEncode(loginCaps),
      });
      PermissionsService.debugReset();
      await PermissionsService.init();
      expect(PermissionsService.has('reports.financial'), isTrue,
          reason: 'يسقط من أوّل إطار، قبل أن يردّ الخادم');

      server.replies['ng'] = manager('next-gen:175', freshCaps);
      await coldStart();
      expect(PermissionsService.has('reports.financial'), isTrue);
      expect(PermissionsService.has('subscribers.delete'), isTrue);
    });
  });
}

/// خادمٌ وهميّ لـ`/api/auth/me` يعرف الجلسة من توكنها كالخادم الحقيقيّ.
/// توكنٌ بلا ردٍّ مسجَّل ⇒ ٤٠١. وردّ توكنٍ «محبوس» ينتظر [release].
class _MeServer implements HttpClientAdapter {
  final replies = <String, Map<String, Object?>>{};

  /// توكن كلّ طلبٍ وصل، بترتيبه — ومساره.
  final asked = <String>[];
  final paths = <String>[];
  final _held = <String, Completer<void>>{};
  final _arrived = <String, Completer<void>>{};

  void hold(String token) => _held[token] = Completer<void>();
  void release(String token) => _held.remove(token)!.complete();

  Future<void> arrived(String token) =>
      _arrived.putIfAbsent(token, Completer<void>.new).future;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    final token = options.headers['x-auth-token']?.toString() ?? '';
    asked.add(token);
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
