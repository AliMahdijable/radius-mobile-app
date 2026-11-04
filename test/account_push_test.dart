import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/auth_api.dart';
import 'package:rad_mysvcs/models/app_notification.dart';
import 'package:rad_mysvcs/screens/account/company_open_flow.dart';
import 'package:rad_mysvcs/screens/account/company_switch_sheet.dart';
import 'package:rad_mysvcs/services/account_service.dart';
import 'package:rad_mysvcs/services/company_push.dart';
import 'package:rad_mysvcs/services/fcm_service.dart';
import 'package:rad_mysvcs/services/linked_companies.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/sas_login_flow.dart';

import 'sim_el/sim_harness.dart';

/// «إشعارات كلّ شركاتي» (٤ نوفمبر — المالك: «اي هاي ضروريه لان كل وكيل اذا عدنه اكثر من شركه كيف بهيج حاله»؛ الخادم
/// server/accountPush.js): الهاتف يسجّل توكنه للحساب أيضاً فيصله دفع كلّ شركات الحساب باسمها، ويُعاد تسجيله للشركة المفتوحة
/// بعد كلّ تبديل (كان يبقى للسابقة حتى إعادة التشغيل)، ونقرة إشعار شركةٍ غير المفتوحة تفتح ورقة «تبديل الشركة» عليها فتُفتح هي
/// ويُوجَّه الإشعار فيها.
const _v = SimVariant(390, dark: false);
const _tok = 'fcm-token:A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6';

LinkedCompany _co(String code, String user, String label, {String? adminId, String role = 'admin'}) => LinkedCompany(
      sasCode: code,
      sasUrl: 'https://$code.example.iq',
      username: user,
      label: label,
      role: role,
      adminId: adminId,
    );

AppNotification _push(String id, Map<String, String> data) =>
    AppNotification.fromFcmPayload(messageId: id, title: 'تنبيه', body: 'نصّ', data: data);

Future<void> _openAs(String adminId) => const FlutterSecureStorage().write(key: 'auth.admin_id', value: adminId);

void main() {
  late SimServer api;
  late SimServer account;

  setUpAll(simSetUpAll);

  setUp(() async {
    api = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'owner'});
    account = SimServer();
    AccountApi.dio.httpClientAdapter = account;
    AccountApi.tokenSource = ({bool force = false}) async => 'account-test';
    api.reply('POST', '/api/fcm/register', 200, {'success': true});
    account.reply('POST', '/api/account/push/register', 200, {'success': true});
    account.reply('POST', '/api/account/push/unregister', 200, {'success': true, 'removed': 1});
    FcmService.debugReset();
    FcmService.accountUid = () => 'uid-1';
    CompanyPush.debugReset();
    LinkedCompanies.reset();
    PermissionsService.debugSet(isEmployee: false);
  });

  tearDown(() {
    AccountApi.tokenSource = AccountService.idToken;
    FcmService.debugReset();
    CompanyPush.debugReset();
    LinkedCompanies.reset();
    PermissionsService.debugReset();
  });

  test('«شركاتي»: معرّف كلّ شركة (adminId) كما في دفعها؛ خادمٌ أقدم أو ربطٌ غير مُثبَت ⇒ null', () {
    expect(LinkedCompany.fromJson({'sasCode': 'ip-1', 'username': 'u', 'label': 'الشمال', 'adminId': 'ip-1:10'}).adminId, 'ip-1:10');
    expect(LinkedCompany.fromJson({'sasCode': 'supernet', 'username': 'u', 'adminId': null}).adminId, isNull);
    expect(LinkedCompany.fromJson({'sasCode': 'supernet', 'username': 'u'}).adminId, isNull);
    expect(LinkedCompany.fromJson({'sasCode': 'supernet', 'username': 'u', 'adminId': '  '}).adminId, isNull);
  });

  test('التسجيل: للشركة المفتوحة وللحساب مرّة؛ وبعد تبديل الشركة يُسجَّل لها من جديد (التوكن نفسه)، والحساب لا يتكرّر', () async {
    await FcmService.debugRegister(_tok);
    expect(api.bodies('POST', '/api/fcm/register').map((b) => b['adminId']), ['2']);
    final acct = account.calls('POST', '/api/account/push/register');
    expect(acct, hasLength(1));
    expect(acct.single.headers['x-account-token'], 'account-test');
    expect((acct.single.data as Map)['token'], _tok);
    await FcmService.debugRegister(_tok);
    expect(api.calls('POST', '/api/fcm/register'), hasLength(1), reason: 'لا شيء تغيّر');
    await _openAs('ip-1:10'); // تبديل الشركة داخل التطبيق
    await FcmService.debugRegister(_tok);
    expect(api.bodies('POST', '/api/fcm/register').map((b) => b['adminId']), ['2', 'ip-1:10'],
        reason: 'كان التكرار بالتوكن وحده فيبقى الهاتف للشركة السابقة');
    expect(account.calls('POST', '/api/account/push/register'), hasLength(1), reason: 'الحساب نفسه والتوكن نفسه');
    FcmService.accountUid = () => 'uid-2'; // حسابٌ آخر على الهاتف
    await FcmService.debugRegister(_tok);
    expect(account.calls('POST', '/api/account/push/register'), hasLength(2));
  });

  test('بلا حساب (موظّفٌ مباشر) ⇒ للشركة وحدها؛ والخروج يُلغي تسجيل الحساب ثمّ يُعاد بالدخول', () async {
    FcmService.accountUid = () => null;
    await FcmService.debugRegister(_tok);
    expect(api.calls('POST', '/api/fcm/register'), hasLength(1));
    expect(account.calls('POST', '/api/account/push/register'), isEmpty);
    FcmService.debugReset();
    FcmService.accountUid = () => 'uid-1';
    await FcmService.debugRegister(_tok);
    await FcmService.debugUnregisterAccount();
    expect(account.bodies('POST', '/api/account/push/unregister').single['token'], _tok);
    await FcmService.debugRegister(_tok);
    expect(account.calls('POST', '/api/account/push/register'), hasLength(2), reason: 'بعد الخروج يُسجَّل من جديد');
  });

  test('الحساب: لا توكن حساب ⇒ لا طلب ولا رمي؛ ردٌّ غير ناجح ⇒ false', () async {
    AccountApi.tokenSource = ({bool force = false}) async => null;
    expect(await AccountApi.registerPush(_tok, 'Android'), isFalse);
    expect(account.calls('POST', '/api/account/push/register'), isEmpty);
    AccountApi.tokenSource = ({bool force = false}) async => 'account-test';
    account.reply('POST', '/api/account/push/register', 400, {'success': false, 'error': 'BAD_TOKEN'});
    expect(await AccountApi.registerPush('x', 'Android'), isFalse);
  });

  test('شركة الإشعار: من company_admin_id؛ والاختيار مديراً لا موظّفاً', () {
    expect(CompanyPush.companyOf({'company_admin_id': ' ip-1:10 '}), 'ip-1:10');
    expect(CompanyPush.companyOf({'type': 'x'}), isNull);
    final list = [
      _co('supernet', 'owner', 'سوبرنت', adminId: '2'),
      _co('ip-1', 'north', 'الشمال', adminId: 'ip-1:10'),
      _co('ip-2', 'staff', 'الجنوب', adminId: 'ip-2:4', role: 'employee'),
    ];
    expect(CompanyPush.pick(list, 'ip-1:10')?.label, 'الشمال');
    expect(CompanyPush.pick(list, 'ip-2:4'), isNull, reason: 'ربط الموظّف لا يُفتح من هنا');
    expect(CompanyPush.pick(null, '2'), isNull);
  });

  testWidgets('النقرة: إشعارٌ لشركةٍ أخرى من شركات الحساب ⇒ ورقتها (مرّةً للإشعار)، وينتظر رئيسيّتها إن فُتحت وإلّا يسقط', (t) async {
    final nav = GlobalKey<NavigatorState>();
    await pumpSim(t, _v, navigatorKey: nav, home: (_) => const Scaffold(body: SizedBox()));
    LinkedCompanies.items.value = [
      _co('supernet', 'owner', 'سوبرنت', adminId: '2'),
      _co('ip-1', 'north', 'الشمال', adminId: 'ip-1:10'),
      _co('ip-2', 'staff', 'الجنوب', adminId: 'ip-2:4', role: 'employee'),
    ];
    final opened = <String>[];
    var switchIt = true;
    CompanyPush.openSheet = (ctx, c, label) async {
      opened.add('${c.adminId}|$label');
      if (switchIt) await _openAs(c.adminId!);
    };
    final deferred = <String>[];
    final undeferred = <String>[];
    Future<bool> go(AppNotification n) => t.runAsync(() => CompanyPush.redirect(nav.currentState!, n,
        defer: (x) => deferred.add(x.id), undefer: (x) => undeferred.add(x.id))).then((v) => v!);

    final n1 = _push('m1', {'type': 'conn_alert_pending', 'company_admin_id': 'ip-1:10', 'company_label': 'الشمال'});
    expect(await go(n1), isTrue);
    expect(opened, ['ip-1:10|الشمال']);
    expect(deferred, ['m1']);
    expect(undeferred, isEmpty, reason: 'فُتحت ⇒ يُوجَّه في رئيسيّتها');
    expect(await go(n1), isFalse, reason: 'لا تحويل ثانٍ للإشعار نفسه');

    await _openAs('2');
    switchIt = false; // أُغلقت الورقة/رُفض الدخول
    expect(await go(_push('m2', {'company_admin_id': 'ip-1:10'})), isTrue);
    expect(undeferred, ['m2']);
    expect(opened.last, 'ip-1:10|الشمال', reason: 'بلا اسمٍ في الإشعار ⇒ اسمها في «شركاتي»');

    expect(await go(_push('m3', {'company_admin_id': '2'})), isFalse, reason: 'المفتوحة نفسها');
    expect(await go(_push('m4', {'type': 'near_expiry_digest'})), isFalse, reason: 'خادمٌ أقدم بلا شركة');
    expect(await go(_push('m5', {'company_admin_id': 'ip-2:4'})), isFalse, reason: 'ربط موظّف');
    AccountApi.tokenSource = ({bool force = false}) async => null;
    expect(await go(_push('m6', {'company_admin_id': 'zz:1'})), isFalse, reason: 'ليست من شركات الحساب');
    PermissionsService.debugSet(isEmployee: true);
    expect(await go(_push('m7', {'company_admin_id': 'ip-1:10'})), isFalse, reason: 'جلسة موظّف');
    expect(opened, hasLength(2));
  });

  testWidgets('الورقة: سطر «إشعارٌ من …» ثمّ تفتح الشركة بنفسها (مسار «شركاتي» نفسه) فتُبنى رئيسيّتها', (t) async {
    final resume0 = CompanyOpenFlow.resumeSession;
    final complete0 = CompanyOpenFlow.completeSession;
    final shell0 = CompanyOpenFlow.shellBuilder;
    addTearDown(() {
      CompanyOpenFlow.resumeSession = resume0;
      CompanyOpenFlow.completeSession = complete0;
      CompanyOpenFlow.shellBuilder = shell0;
    });
    final north = _co('ip-1', 'north', 'الشمال', adminId: 'ip-1:10');
    LinkedCompanies.items.value = [_co('supernet', 'owner', 'سوبرنت', adminId: '2'), north];
    final gate = Completer<LoginResult?>();
    final resumed = <String>[];
    CompanyOpenFlow.resumeSession = (c) {
      resumed.add(c.username);
      return gate.future;
    };
    final completed = <String?>[];
    CompanyOpenFlow.completeSession = (LoginSuccess res,
        {required String username,
        required String? password,
        required String sasUrl,
        required bool remember,
        String? companyLabel,
        String? sasCode}) async {
      completed.add(companyLabel);
      return SasLoginOutcome.ok;
    };
    CompanyOpenFlow.shellBuilder = () => const Scaffold(body: Center(child: Text('SHELL')));
    await pumpSim(t, _v, home: (_) => simLauncher((c) => showCompanySwitchSheet(c, autoOpen: north, notice: 'الشمال')));
    await t.tap(find.text(simOpenLabel));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('إشعارٌ من «الشمال» — جارٍ فتح الشركة…'), findsOneWidget);
    expect(resumed, ['north'], reason: 'تُفتح بنفسها');
    gate.complete(const LoginSuccess(token: 't', adminId: 'ip-1:10', adminUsername: 'north', displayName: 'الشمال'));
    await t.pumpAndSettle();
    expect(completed, ['الشمال']);
    expect(find.text('SHELL'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
