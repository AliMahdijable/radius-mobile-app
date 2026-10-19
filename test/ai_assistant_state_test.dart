import 'package:dio/dio.dart' show Options;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/ai_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/api_error_tap.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sim_el/sim_harness.dart' show SimReply, SimServer, simTimeout;

/// حال المساعد في الجلسة (مهلة · تبريد · جيل · نوع الجلسة) و«اشرحلي» من
/// نصّ الإشعار (ApiErrorTap ← explainFor).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const statusPath = '/api/v2/ai/status';
  const on = {
    'success': true,
    'enabled': true,
    'can_use': true,
    'explain': true,
    'ask': true,
    'quota': {'left': 7, 'limit': 10},
  };

  late SimServer server;
  late SimServer accountServer;
  var clock = DateTime(2026, 10, 18, 12);

  void company() => FlutterSecureStorage.setMockInitialValues({
        'auth.token': 'sim-token',
        'auth.admin_id': '2251',
      });

  setUp(() {
    company();
    SharedPreferences.setMockInitialValues({});
    server = SimServer();
    ApiClient.dio.httpClientAdapter = server;
    accountServer = SimServer();
    AiApi.accountDio.httpClientAdapter = accountServer;
    AiApi.hasAccount = () => false;
    AiApi.accountTokenSource = ({bool force = false}) async => null;
    clock = DateTime(2026, 10, 18, 12);
    AiAssistantState.now = () => clock;
    ApiErrorTap.now = () => clock;
    AiAssistantState.reset();
  });

  tearDown(() {
    AiAssistantState.reset();
    AiAssistantState.now = DateTime.now;
    ApiErrorTap.now = DateTime.now;
  });

  group('الحالة', () {
    test('🚨 الاستماع يطلبها مرّةً، وخلال المهلة لا طلب ثانٍ، وبعدها يُعاد',
        () async {
      server.reply('GET', statusPath, 200, on);
      void l() {}
      AiAssistantState.gate.addListener(l);
      AiAssistantState.gate.addListener(l);
      await Future<void>.delayed(Duration.zero);
      await AiAssistantState.ensureFresh();
      expect(server.calls('GET', statusPath), hasLength(1));
      expect(AiAssistantState.canExplain, isTrue);
      expect(AiAssistantState.visible, isTrue);
      clock = clock.add(const Duration(minutes: 4));
      await AiAssistantState.ensureFresh();
      expect(server.calls('GET', statusPath), hasLength(1),
          reason: 'خلال ٥ دقائق');
      clock = clock.add(const Duration(minutes: 2));
      await AiAssistantState.ensureFresh();
      expect(server.calls('GET', statusPath), hasLength(2));
      AiAssistantState.gate.removeListener(l);
      AiAssistantState.gate.removeListener(l);
    });

    test('الفشل لا يمسح ما نعرفه، وبعده تبريد ٣٠ث', () async {
      AiAssistantState.debugSet(AiStatus.fromJson(on, mode: AiMode.company));
      server.on('GET', statusPath, simTimeout);
      await AiAssistantState.ensureFresh(force: true);
      expect(AiAssistantState.canExplain, isTrue,
          reason: 'الانقطاع لا يُخفي ما قاله الخادم');
      final n = server.calls('GET', statusPath).length;
      clock = clock.add(const Duration(minutes: 6)); // المهلة انتهت…
      AiAssistantState.debugSet(null);
      server.on('GET', statusPath, simTimeout);
      await AiAssistantState.ensureFresh();
      final after = server.calls('GET', statusPath).length;
      expect(after, greaterThan(n));
      clock = clock.add(const Duration(seconds: 10));
      await AiAssistantState.ensureFresh();
      expect(server.calls('GET', statusPath).length, after,
          reason: 'تبريد بعد الفشل');
      clock = clock.add(const Duration(seconds: 31));
      await AiAssistantState.ensureFresh();
      expect(server.calls('GET', statusPath).length, greaterThan(after));
    });

    test('🚨 ردٌّ يصل بعد تبديل الجلسة لا يُكتب', () async {
      server.hold('GET', statusPath);
      server.reply('GET', statusPath, 200, on);
      final f = AiAssistantState.ensureFresh();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      AiAssistantState.reset(); // خروج/تبديل شركة
      server.release('GET', statusPath);
      await f;
      expect(AiAssistantState.gate.value, isNull);
      expect(AiAssistantState.canExplain, isFalse);
    });

    test('تبدّل نوع الجلسة (حسابٌ وحده ← شركة) يُعيد السؤال ولو خلال المهلة',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      AiApi.hasAccount = () => true;
      AiApi.accountTokenSource = ({bool force = false}) async => 'acct';
      accountServer.reply('GET', statusPath, 200,
          Map<String, dynamic>.from(on)..['ask'] = false);
      await AiAssistantState.ensureFresh();
      expect(AiAssistantState.status!.mode, AiMode.account);
      expect(AiAssistantState.canExplain, isTrue);
      expect(AiAssistantState.visible, isFalse,
          reason: '«كيف أسوّي؟» لجلسة الشركة وحدها');
      company();
      server.reply('GET', statusPath, 200, on);
      await AiAssistantState.ensureFresh();
      expect(server.calls('GET', statusPath), hasLength(1));
      expect(AiAssistantState.status!.mode, AiMode.company);
      expect(AiAssistantState.visible, isTrue);
    });

    test('بلا جلسة أصلاً ⇒ مطفأة بلا طلب', () async {
      FlutterSecureStorage.setMockInitialValues({});
      await AiAssistantState.ensureFresh();
      expect(AiAssistantState.gate.value?.enabled, isFalse);
      expect(server.requests, isEmpty);
      expect(accountServer.requests, isEmpty);
    });

    test('الحصّة تُحدَّث بعد الجواب بلا طلب، و«أُطفئت» تُخفي كلّ شيء فوراً',
        () {
      AiAssistantState.debugSet(AiStatus.fromJson(on, mode: AiMode.company));
      AiAssistantState.applyQuota(const AiQuota(left: 2, limit: 10));
      expect(AiAssistantState.status!.quota!.left, 2);
      expect(AiAssistantState.canAsk, isTrue);
      AiAssistantState.turnOff();
      expect(AiAssistantState.visible, isFalse);
      expect(AiAssistantState.canExplain, isFalse);
      AiAssistantState.applyQuota(const AiQuota(left: 9, limit: 10));
      expect(AiAssistantState.status!.enabled, isFalse,
          reason: 'الحصّة لا تُحيي المطفأ');
    });

    test('موظّفٌ بلا الصلاحيّة ⇒ البطاقة مقفلةٌ بمكانها و«اشرحلي» مخفيّ', () {
      AiAssistantState.debugSet(AiStatus.fromJson(const {
        'success': true,
        'enabled': true,
        'can_use': false,
        'reason': 'no_permission',
      }, mode: AiMode.company));
      expect(AiAssistantState.visible, isTrue);
      expect(AiAssistantState.askLocked, isTrue);
      expect(AiAssistantState.canExplain, isFalse);
      expect(AiAssistantState.canAsk, isFalse);
    });
  });

  group('ApiErrorTap — ما يُحفظ وما لا يُحفظ', () {
    Future<void> call(String method, String path, int status, Object body,
        {Object? data}) async {
      server.reply(method, path, status, body);
      try {
        await ApiClient.dio.request<Object?>(path,
            data: data, options: Options(method: method));
      } catch (_) {/* ٥xx يرمي */}
    }

    test('رفضٌ برمزٍ ورسالة يُحفظ، وما يصف العمليّة وحده من الجسم', () async {
      await call('POST', '/api/v2/subscribers/9/activate', 409, {
        'success': false,
        'code': 'CREDIT_NOT_ALLOWED',
        'message': 'حسابك ما يسمح بالتفعيل بالرصيد'
      }, data: {
        'paymentType': 'cash',
        'method': 'deposit',
        'depositPassword': 'S3cret!'
      });
      final n = ApiErrorTap.recent.single;
      expect(n.method, 'POST');
      expect(n.path, '/api/v2/subscribers/9/activate');
      expect(n.status, 409);
      expect(n.code, 'CREDIT_NOT_ALLOWED');
      expect(n.message, 'حسابك ما يسمح بالتفعيل بالرصيد');
      expect(n.payMethod, 'deposit');
      expect(n.packageChange, isFalse);
    });

    test('تعديلٌ بباقةٍ جديدة ⇒ «تغيير باقة» وتوقيته، بلا أيّ قيمة أخرى',
        () async {
      await call('PUT', '/api/v2/subscribers/9', 403, {
        'success': false,
        'code': 'PACKAGE_CHANGE_ACTIVE_FORBIDDEN',
        'message': 'لا يمكن الآن'
      }, data: {
        'profile_id': 4,
        'change_type': 'immediate',
        'password': 'p@ss',
        'phone': '07700000000'
      });
      final n = ApiErrorTap.recent.single;
      expect(n.packageChange, isTrue);
      expect(n.changeType, 'immediate');
      expect(n.payMethod, isNull);
    });

    test('٢٠٠ بـsuccess:false يُحفظ؛ والنجاح لا', () async {
      await call('POST', '/api/v2/subscribers/9/extend', 200,
          {'success': false, 'message': 'رفض الساس التمديد'});
      await call(
          'GET', '/api/v2/subscribers', 200, {'success': true, 'data': []});
      expect(ApiErrorTap.recent, hasLength(1));
      expect(ApiErrorTap.recent.single.status, 200);
    });

    test(
        'لا يُحفظ: ٤٠١ (إلّا الدخول)، ونداءات المساعد، وردٌّ ليس بكلام خادمنا، وردٌّ بلا رمزٍ ولا رسالة',
        () async {
      // (٤٠١ على /api/auth/* لا يمرّ بالتجديد — فلا تُمحى جلسة الاختبار.)
      await call('GET', '/api/auth/me', 401,
          {'success': false, 'code': 'NO_SESSION', 'message': 'انتهت الجلسة'});
      await call('POST', '/api/v2/ai/explain', 429,
          {'success': false, 'code': 'AI_RATE_LIMITED', 'message': 'كثّرت'});
      await call(
          'POST', '/api/v2/subscribers/9/extend', 400, {'success': false});
      server.on('GET', '/api/v2/cards/summary',
          (_) => const SimReply.html(200, '<html>gateway</html>'));
      try {
        await ApiClient.dio.get<Object?>('/api/v2/cards/summary');
      } catch (_) {}
      expect(ApiErrorTap.recent, isEmpty);
      await call('POST', '/api/auth/login', 401, {
        'success': false,
        'error': 'invalid-credentials',
        'message': 'اسم المستخدم أو كلمة المرور غير صحيحة'
      });
      expect(ApiErrorTap.recent.single.code, 'invalid-credentials');
    });

    test('٥xx من خادمنا (يرمي) يُحفظ، والسقف ثمانية', () async {
      await call('POST', '/api/v2/self-deposit/request', 503, {
        'success': false,
        'code': 'SAS_UNREACHABLE',
        'message': 'الشركة لا تُجيب'
      });
      expect(ApiErrorTap.recent.single.code, 'SAS_UNREACHABLE');
      for (var i = 0; i < 12; i++) {
        await call('POST', '/api/v2/subscribers/$i/extend', 409,
            {'success': false, 'code': 'C$i', 'message': 'م$i'});
      }
      expect(ApiErrorTap.recent, hasLength(8));
      expect(ApiErrorTap.recent.last.code, 'C11');
    });

    test('reset يمحوها — لا يُشرح للمدير التالي خطأ سابقه', () async {
      await call('POST', '/api/v2/subscribers/9/extend', 409,
          {'success': false, 'code': 'X_Y', 'message': 'م'});
      expect(ApiErrorTap.recent, isNotEmpty);
      AiAssistantState.reset();
      expect(ApiErrorTap.recent, isEmpty);
    });
  });

  group('explainFor — أيّ خطأٍ يعرضه الإشعار', () {
    ApiErrorNote note({
      String method = 'POST',
      String path = '/api/v2/subscribers/9/activate',
      int status = 409,
      String? code = 'CREDIT_NOT_ALLOWED',
      String? message = 'حسابك ما يسمح بالتفعيل بالرصيد',
      Duration ago = Duration.zero,
      String? payMethod,
      bool packageChange = false,
      String? changeType,
    }) =>
        ApiErrorNote(
          at: clock.subtract(ago),
          method: method,
          path: path,
          status: status,
          code: code,
          message: message,
          payMethod: payMethod,
          packageChange: packageChange,
          changeType: changeType,
        );

    test('بالنصّ: الرمز والشاشة والعمليّة والطريقة والحالة، والرسالة كما ظهرت',
        () {
      ApiErrorTap.debugNote(note(payMethod: 'credit'));
      final iso = String.fromCharCode(0x2066);
      final pdi = String.fromCharCode(0x2069);
      final r = AiAssistantState.explainFor(
          '$iso حسابك ما يسمح بالتفعيل بالرصيد$pdi')!;
      expect(r.code, 'CREDIT_NOT_ALLOWED');
      expect(r.screen, 'activate');
      expect(r.httpStatus, 409);
      expect(r.context, {'action': 'activate', 'method': 'credit'});
      expect(r.message, contains('حسابك ما يسمح'));
    });

    test('نصٌّ يحوي رسالة الخادم (سطرٌ زائد) أو جزءها بعد تنقية آيفون', () {
      ApiErrorTap.debugNote(
          note(message: 'انتهى اشتراكك — فعّل كوداً للمتابعة'));
      expect(
          AiAssistantState.explainFor(
              'انتهى اشتراكك — فعّل كوداً للمتابعة\nتأكّد من الشركة'),
          isNotNull);
      expect(AiAssistantState.explainFor('انتهى اشتراكك'), isNotNull);
    });

    test('بالوقت وحده: عمليّةٌ (غير GET) رُفضت برمزٍ قبل لحظة', () {
      ApiErrorTap.debugNote(
          note(message: null, ago: const Duration(seconds: 1)));
      expect(AiAssistantState.explainFor('تعذّر التفعيل'), isNotNull);
    });

    test('🚨 لا زرّ لرسالةٍ محلّيّة، ولا لخطأ GET بلا نصّه، ولا لخطأٍ قديم',
        () {
      expect(AiAssistantState.explainFor('أدخل المبلغ'), isNull,
          reason: 'لا خطأ خادمٍ أصلاً');
      ApiErrorTap.debugNote(note(
          method: 'GET',
          path: '/api/v2/admin-widgets',
          message: 'تعذّر',
          ago: const Duration(seconds: 1)));
      expect(AiAssistantState.explainFor('أدخل المبلغ'), isNull,
          reason: 'استطلاعٌ فشل بالخلفيّة ≠ رسالةٌ محلّيّة');
      ApiErrorTap.clear();
      ApiErrorTap.debugNote(note(ago: const Duration(seconds: 9)));
      expect(
          AiAssistantState.explainFor('حسابك ما يسمح بالتفعيل بالرصيد'), isNull,
          reason: 'أقدم من ٨ث');
      ApiErrorTap.clear();
      ApiErrorTap.debugNote(
          note(message: null, ago: const Duration(seconds: 4)));
      expect(AiAssistantState.explainFor('تعذّر التفعيل'), isNull,
          reason: 'الوقت وحده: ٢٫٥ث');
    });

    test('الأحدث أوّلاً', () {
      ApiErrorTap.debugNote(
          note(code: 'OLD_ONE', ago: const Duration(seconds: 3)));
      ApiErrorTap.debugNote(note(code: 'NEW_ONE'));
      expect(
          AiAssistantState.explainFor('حسابك ما يسمح بالتفعيل بالرصيد')!.code,
          'NEW_ONE');
    });

    test('تغيير الباقة ⇒ الشاشة والتوقيت', () {
      ApiErrorTap.debugNote(note(
        method: 'PUT',
        path: '/api/v2/subscribers/9',
        status: 403,
        code: 'PACKAGE_CHANGE_ACTIVE_FORBIDDEN',
        message: 'لا يمكن تغيير الباقة الآن',
        packageChange: true,
        changeType: 'schedule',
      ));
      final r = AiAssistantState.explainFor('لا يمكن تغيير الباقة الآن')!;
      expect(r.screen, 'package_change');
      expect(r.context,
          {'action': 'package_change', 'package_change_mode': 'at_expiry'});
    });
  });

  group('screenFor', () {
    test('المسارات المعروفة ⇒ شاشات SPEC وعمليّاتها', () {
      final cases = <(String, String, String, String?)>[
        ('POST', '/api/v2/subscribers/12/activate', 'activate', 'activate'),
        ('POST', '/api/v2/subscribers/12/extend', 'extend', 'extend'),
        ('POST', '/api/v2/subscribers/12/pay-debt', 'pay_debt', 'pay_debt'),
        ('POST', '/api/v2/subscribers/12/add-debt', 'debts', 'add_debt'),
        (
          'POST',
          '/api/v2/subscribers/12/toggle-enabled',
          'subscriber_detail',
          'toggle'
        ),
        (
          'POST',
          '/api/v2/subscribers/12/cancel-profile-change',
          'package_change',
          'package_change'
        ),
        ('PUT', '/api/v2/subscribers/12', 'edit_subscriber', 'edit'),
        ('DELETE', '/api/v2/subscribers/12', 'subscriber_detail', 'delete'),
        ('POST', '/api/v2/subscribers', 'add_subscriber', 'add'),
        ('GET', '/api/v2/subscribers', 'subscribers', null),
        ('POST', '/api/v2/self-deposit/request', 'topup', 'topup'),
        ('POST', '/api/whatsapp/send-message', 'whatsapp', 'send_whatsapp'),
        ('POST', '/api/whatsapp/broadcast', 'broadcast', 'broadcast'),
        ('POST', '/api/telegram/connect', 'telegram', null),
        ('POST', '/api/auth/login', 'login', 'login'),
        ('POST', '/api/auth/employee-login', 'employee_login', 'login'),
        ('POST', '/api/account/companies', 'companies', null),
        ('GET', '/api/reports/finance', 'finance', null),
        ('POST', '/api/v2/settlements', 'settlements', null),
        ('POST', '/api/v2/employees', 'employees', null),
        ('GET', '/api/somewhere/else', 'other', null),
      ];
      for (final (m, p, screen, action) in cases) {
        expect(AiAssistantState.screenFor(m, p), (screen, action),
            reason: '$m $p');
        expect(ExplainRequest.aiScreens, contains(screen));
        if (action != null) {
          expect(ExplainRequest.contextValues['action'], contains(action));
        }
      }
      expect(
          AiAssistantState.screenFor('PUT', '/api/v2/subscribers/12',
              packageChange: true),
          ('package_change', 'package_change'));
    });
  });
}
