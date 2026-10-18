import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/auth_api.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/broadcast/broadcast_screen.dart';
import 'package:rad_mysvcs/screens/notifications_settings_screen.dart';
import 'package:rad_mysvcs/screens/print_templates/print_templates_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_card_v3.dart';
import 'package:rad_mysvcs/services/print_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/services/receipt_service.dart';
import 'package:rad_mysvcs/widgets/sas_captcha_sheet.dart';
import 'package:rad_mysvcs/widgets/two_factor_sheet.dart';

import 'sim_el/sim_harness.dart';
import 'visual_perm/visual_perm_harness.dart';

/// تدقيق ١٨ أكتوبر لدفعة ايرث لنك ① — ما وقع منه في التطبيق:
///
/// 1. **التحقّق بخطوتين عند الدخول** — مالكٌ (ساس أو ايرث لنك) فعّله من الويب
///    كان يرى «أدخل كود 2FA» خطأً ولا مكان لكتابته («شركاتي»: حلقة نموذج كلمة
///    السرّ). الآن نافذة الكود بمسار الويب نفسه (`/api/auth/2fa/verify`).
/// 2. **«قوالب الطباعة» لايرث لنك** — تعرض إعدادات وصل الويب (`receipt_settings`)
///    ويطبع بها التطبيق، بدل قوالب `print_templates` التي لا يكتبها أحد.
/// 3. **تفعيلٌ نقديّ لايرث لنك لا يُسمّى «تسديد دين»** على بطاقة المشترك.
/// 4. **لا «دين على مدير فرعي»** في إعدادات الإشعارات لايرث لنك/FTTH.
/// 5. **بثّ «قرب الانتهاء»** — العدّ بقاعدة الخادم، والحمولة كما يفهمها.

/// صورة PNG بنقطةٍ واحدة — لرمز الصورة وللشعار.
const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

const _wrongCode = 'الكود غير صحيح';
const _expiredMsg = 'انتهت صلاحية الجلسة المؤقّتة — أعد تسجيل الدخول';

Map<String, dynamic> _challenge(String tempId) => {
      'success': false,
      'requires2fa': true,
      'tempId': tempId,
      'expiresIn': 120,
      'message': 'أدخل كود 2FA من تطبيق Google Authenticator',
    };

/// ردّ `/api/auth/2fa/verify` الناجح لمالك ساس — شكل ردّ الدخول نفسه.
Map<String, dynamic> _sasSession() => {
      'success': true,
      'token': 'sas-token-2fa',
      'expiresAt': '2026-10-19T10:00:00.000Z',
      'expiresIn': 86400000,
      'user': {
        'id': '12',
        'username': 'mahdi',
        'role': 'admin',
        'authMethod': 'SAS4',
        'permissions': ['prm_managers_create'],
        'canonicalPermissions': {'subscribers.delete': false},
        'isSuperAdmin': false,
      },
      'message': 'تم تسجيل الدخول بنجاح بعد التحقّق من 2FA',
    };

/// خطواتٌ محدودة لا `pumpAndSettle`: دوّارة التحقّق وعدّاد المهلة لا يهدآن.
Future<void> _steps(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════ ١. التحقّق بخطوتين — الواجهة البرمجيّة ═══════════════════════
  group('التحقّق بخطوتين — AuthApi', () {
    late SimServer server;
    setUp(() async => server = await simSetUp());

    test('تحدّي الدخول: requires2fa + tempId ⇒ needs2fa لا فشلٌ ولا بوّابة', () async {
      server.reply('POST', '/api/auth/login', 200, _challenge('2fa_abc'));
      final r = await AuthApi.login(username: 'mahdi', password: 'pw');
      expect(r, isA<LoginFailure>());
      final f = r as LoginFailure;
      expect(f.needs2fa, isTrue);
      expect(f.code, '2fa-required');
      expect(f.twoFactor!.tempId, '2fa_abc');
      expect(f.twoFactor!.expiresIn, 120);
      expect(f.isAccountGate, isFalse, reason: 'البوّابة لا تحلّه');
      expect(f.isCancelled, isFalse);
      expect(f.needsCaptcha, isFalse);
      expect(f.rejected, isFalse);
    });

    test('TwoFactorChallenge.tryParse: بلا tempId أو requires2fa ⇒ ليس تحدّياً', () {
      expect(TwoFactorChallenge.tryParse(const {'requires2fa': true}), isNull);
      expect(
          TwoFactorChallenge.tryParse(const {'requires2fa': true, 'tempId': ' '}),
          isNull);
      expect(
          TwoFactorChallenge.tryParse(const {'requires2fa': false, 'tempId': 'x'}),
          isNull);
      final c = TwoFactorChallenge.tryParse(
          const {'requires2fa': true, 'tempId': 'x', 'expiresIn': '90'})!;
      expect(c.expiresIn, 90);
      expect(
          TwoFactorChallenge.tryParse(const {'requires2fa': true, 'tempId': 'x'})!
              .expiresIn,
          120);
    });

    test('فشلٌ عاديّ يبقى كما كان (لا تحدّي)', () async {
      server.reply('POST', '/api/auth/login', 401,
          {'success': false, 'message': 'اسم المستخدم أو كلمة المرور غير صحيحة'});
      final f = await AuthApi.login(username: 'mahdi', password: 'x') as LoginFailure;
      expect(f.needs2fa, isFalse);
      expect(f.rejected, isTrue);
      expect(f.code, isNull);
    });

    test('verify2fa ساس: الجسم {tempId, code} والجلسة كردّ الدخول', () async {
      server.reply('POST', '/api/auth/2fa/verify', 200, _sasSession());
      final r = await AuthApi.verify2fa(tempId: '2fa_abc', code: '123456');
      expect(r, isA<LoginSuccess>());
      final s = r as LoginSuccess;
      expect(s.token, 'sas-token-2fa');
      expect(s.adminId, '12');
      expect(s.adminUsername, 'mahdi');
      expect(s.expiresAt, '2026-10-19T10:00:00.000Z');
      expect(s.canAccessManagers, isTrue);
      expect(s.isEmployee, isFalse);
      expect(s.canonicalPermissions, {'subscribers.delete': false});
      expect(server.bodies('POST', '/api/auth/2fa/verify').single,
          {'tempId': '2fa_abc', 'code': '123456'});
    });

    test('verify2fa ايرث لنك: المعرّف earthlink:<idx> وصلاحيّاته المعياريّة', () async {
      server.reply('POST', '/api/auth/2fa/verify', 200, {
        'success': true,
        'token': 'el-session',
        'expiresAt': '2026-10-19T10:00:00.000Z',
        'expiresIn': 86400000,
        'user': {
          'id': 'earthlink:5',
          'username': 'mahdi.el',
          'role': 'admin',
          'authMethod': 'EARTHLINK',
          'permissions': <String>[],
          'canonicalPermissions': {'subscribers.add': true},
          'isSuperAdmin': false,
        },
      });
      final s =
          await AuthApi.verify2fa(tempId: '2fa_el', code: '654321') as LoginSuccess;
      expect(s.adminId, 'earthlink:5');
      expect(s.adminUsername, 'mahdi.el');
      expect(s.canonicalPermissions, {'subscribers.add': true});
    });

    test('verify2fa: كودٌ خاطئ ⇒ 2fa-invalid (الجلسة المعلَّقة باقية)', () async {
      server.reply('POST', '/api/auth/2fa/verify', 401,
          {'success': false, 'message': _wrongCode});
      final f = await AuthApi.verify2fa(tempId: 't', code: '000000') as LoginFailure;
      expect(f.code, '2fa-invalid');
      expect(f.message, _wrongCode);
      expect(f.isAccountGate, isFalse);
    });

    test('verify2fa: انتهت الجلسة المعلَّقة (٤٠١) أو مُسحت (٤٠٠) ⇒ 2fa-expired', () async {
      server.reply('POST', '/api/auth/2fa/verify', 401,
          {'success': false, 'message': _expiredMsg});
      final a = await AuthApi.verify2fa(tempId: 't', code: '000000') as LoginFailure;
      expect(a.code, '2fa-expired');
      server.reply('POST', '/api/auth/2fa/verify', 400,
          {'success': false, 'message': '2FA غير مفعّل لهذا الحساب'});
      final b = await AuthApi.verify2fa(tempId: 't', code: '000000') as LoginFailure;
      expect(b.code, '2fa-expired');
      expect(b.isAccountGate, isFalse);
    });

    test('verify2fa: مهلة شبكة ⇒ بلا رمز (عابر، يُعاد بالكود نفسه)', () async {
      server.on('POST', '/api/auth/2fa/verify', simTimeout);
      final f = await AuthApi.verify2fa(tempId: 't', code: '000000') as LoginFailure;
      expect(f.code, isNull);
      expect(f.message, isNotEmpty);
    });
  });

  // ═══════════════════════ ١. التحقّق بخطوتين — نافذة الكود ═══════════════════════
  group('التحقّق بخطوتين — نافذة الكود عبر SasCaptchaLogin', () {
    setUpAll(simSetUpAll);
    late SimServer server;
    late DateTime fakeNow;
    setUp(() async {
      server = await simSetUp();
      fakeNow = DateTime(2026, 10, 18, 10);
      TwoFactorSheet.clock = () => fakeNow;
    });
    tearDown(() => TwoFactorSheet.clock = DateTime.now);

    /// يفتح الدخول من صفحةٍ بزرّ، ويُرجع نتيجته حين تصل.
    Future<({LoginResult? Function() result})> open(WidgetTester t) async {
      LoginResult? result;
      await pumpSim(
        t,
        const SimVariant(390, dark: false),
        home: (_) => simLauncher((c) {
          SasCaptchaLogin.login(c, username: 'mahdi', password: 'pw')
              .then((r) => result = r);
        }),
      );
      await t.tap(find.text(simOpenLabel));
      await _steps(t);
      return (result: () => result);
    }

    Future<void> close(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    }

    testWidgets('🚨 كودٌ خاطئ ثمّ صحيح: الخطأ بمكانه والحقل يُمسح ثمّ الجلسة',
        (t) async {
      server.reply('POST', '/api/auth/login', 200, _challenge('2fa_1'));
      server.on('POST', '/api/auth/2fa/verify', (req) {
        final code = (req.data as Map)['code'];
        return code == '123456'
            ? SimReply(200, _sasSession())
            : const SimReply(401, {'success': false, 'message': _wrongCode});
      });
      final h = await open(t);

      expect(find.text('التحقّق بخطوتين'), findsOneWidget);
      expect(simText('تنتهي المهلة خلال 2:00'), findsOneWidget);
      expect(find.text('تأكيد الدخول'), findsOneWidget);

      // الرقم السادس يرسل وحده.
      await t.enterText(find.byType(TextField), '111111');
      await _steps(t);
      expect(find.text(_wrongCode), findsOneWidget);
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty,
          reason: 'يُمسح ليكتب الكود التالي');
      expect(h.result(), isNull, reason: 'النافذة باقية');

      await t.enterText(find.byType(TextField), '123456');
      await _steps(t);
      expect(server.bodies('POST', '/api/auth/2fa/verify'), [
        {'tempId': '2fa_1', 'code': '111111'},
        {'tempId': '2fa_1', 'code': '123456'},
      ]);
      final r = h.result();
      expect(r, isA<LoginSuccess>());
      expect((r as LoginSuccess).token, 'sas-token-2fa');
      expect(find.text('التحقّق بخطوتين'), findsNothing);
      expect(t.takeException(), isNull);
      await close(t);
    });

    testWidgets('🚨 انتهت المهلة ⇒ «إعادة الدخول» تعطي معرّفاً ومهلةً جديدين',
        (t) async {
      var logins = 0;
      server.on('POST', '/api/auth/login',
          (_) => SimReply(200, _challenge('2fa_${++logins}')));
      server.reply('POST', '/api/auth/2fa/verify', 200, _sasSession());
      final h = await open(t);
      expect(logins, 1);

      fakeNow = fakeNow.add(const Duration(seconds: 61));
      await t.pump(const Duration(seconds: 1));
      expect(simText('تنتهي المهلة خلال 0:59'), findsOneWidget);

      fakeNow = fakeNow.add(const Duration(seconds: 60));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('انتهت مهلة الكود — أعد الدخول لمهلةٍ جديدة'),
          findsOneWidget);
      expect(find.text('إعادة الدخول'), findsOneWidget);
      expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse,
          reason: 'لا كود يصلح بعد الانتهاء');

      await t.tap(find.text('إعادة الدخول'));
      await _steps(t);
      expect(logins, 2, reason: 'إعادة الإرسال = إعادة الدخول بكلمة السرّ نفسها');
      expect(server.bodies('POST', '/api/auth/login').last['password'], 'pw');
      expect(simText('تنتهي المهلة خلال 2:00'), findsOneWidget);

      await t.enterText(find.byType(TextField), '123456');
      await _steps(t);
      expect(server.bodies('POST', '/api/auth/2fa/verify').single['tempId'],
          '2fa_2', reason: 'المعرّف الجديد لا القديم');
      expect(h.result(), isA<LoginSuccess>());
      await close(t);
    });

    testWidgets('الخادم يقول «انتهت» قبل العدّاد ⇒ حالة الانتهاء نفسها', (t) async {
      server.reply('POST', '/api/auth/login', 200, _challenge('2fa_1'));
      server.reply('POST', '/api/auth/2fa/verify', 401,
          {'success': false, 'message': _expiredMsg});
      final h = await open(t);
      await t.enterText(find.byType(TextField), '123456');
      await _steps(t);
      expect(find.text(_expiredMsg), findsOneWidget);
      expect(find.text('إعادة الدخول'), findsOneWidget);
      expect(simText('تنتهي المهلة خلال 2:00'), findsNothing);
      expect(h.result(), isNull);
      await close(t);
    });

    testWidgets('«إلغاء» ⇒ 2fa-cancelled بلا رسالة (لا نموذج كلمة سرّ ولا خطأ)',
        (t) async {
      server.reply('POST', '/api/auth/login', 200, _challenge('2fa_1'));
      final h = await open(t);
      await t.tap(find.text('إلغاء'));
      await _steps(t);
      final r = h.result();
      expect(r, isA<LoginFailure>());
      final f = r as LoginFailure;
      expect(f.isCancelled, isTrue);
      expect(f.code, '2fa-cancelled');
      expect(f.message, isEmpty);
      expect(f.isAccountGate, isFalse);
      expect(server.calls('POST', '/api/auth/2fa/verify'), isEmpty);
      await close(t);
    });

    testWidgets('رمز صورة الساس ثمّ الكود: التحدّيان بالترتيب', (t) async {
      server.on('POST', '/api/auth/login', (req) {
        final body = req.data as Map;
        if (body['captchaId'] == null) {
          return const SimReply(200, {
            'success': false,
            'error': 'captcha-required',
            'captcha': {'id': 'c1', 'image': _png1x1},
            'message': 'اكتب الرمز',
          });
        }
        return SimReply(200, _challenge('2fa_after_captcha'));
      });
      server.reply('POST', '/api/auth/2fa/verify', 200, _sasSession());
      final h = await open(t);
      expect(find.text('رمز التحقّق'), findsOneWidget, reason: 'نافذة رمز الصورة');

      await t.enterText(find.byType(TextField), 'ab12');
      await t.tap(find.text('دخول'));
      await _steps(t, 12);
      expect(server.bodies('POST', '/api/auth/login').last['captchaText'], 'ab12');
      expect(find.text('التحقّق بخطوتين'), findsOneWidget, reason: 'ثمّ نافذة الكود');

      await t.enterText(find.byType(TextField), '123456');
      await _steps(t);
      expect(server.bodies('POST', '/api/auth/2fa/verify').single['tempId'],
          '2fa_after_captcha');
      expect(h.result(), isA<LoginSuccess>());
      await close(t);
    });

    testWidgets('إعادة الدخول ترفضها الشركة (حدّ الأجهزة) ⇒ للشاشة تقرّر', (t) async {
      var logins = 0;
      server.on('POST', '/api/auth/login', (_) {
        logins++;
        return logins == 1
            ? SimReply(200, _challenge('2fa_1'))
            : const SimReply(403, {
                'success': false,
                'error': 'device-limit',
                'message': 'بلغت حدّ الأجهزة',
              });
      });
      final h = await open(t);
      fakeNow = fakeNow.add(const Duration(minutes: 3));
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('إعادة الدخول'));
      await _steps(t);
      final f = h.result() as LoginFailure;
      expect(f.isDeviceLimit, isTrue);
      await close(t);
    });
  });

  // ═══════════════════════ ٢. وصل ايرث لنك من مصمّم الويب ═══════════════════════
  group('إعدادات وصل الويب (receipt_settings)', () {
    final pngBytes = base64Decode(_png1x1);

    test('fromJson: الحقول والأقسام والشعار (PNG/JPEG وحدهما)', () {
      final s = ReceiptSettings.fromJson({
        'shop_name': ' مكتب النجف ',
        'shop_address': 'النجف — شارع الكوفة',
        'shop_phone': '07701234567',
        'footer_text': 'شكراً لكم',
        'logo_data': 'data:image/png;base64,$_png1x1',
        'design': {'show_logo': false, 'show_shop_info': true},
      });
      expect(s.shopName, 'مكتب النجف');
      expect(s.shopAddress, 'النجف — شارع الكوفة');
      expect(s.logo, pngBytes);
      expect(s.showLogo, isFalse);
      expect(s.showShopInfo, isTrue);
      expect(s.showFooter, isTrue, reason: 'الغائب ظاهرٌ كافتراض الويب');
      expect(s.isCustomized, isTrue);

      expect(ReceiptSettings.decodeLogo('data:image/webp;base64,UklGRg=='), isNull);
      expect(ReceiptSettings.decodeLogo('data:image/png;base64,@@@'), isNull);
      expect(ReceiptSettings.decodeLogo('https://x/logo.png'), isNull);
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10]);
      expect(ReceiptSettings.decodeLogo('data:image/jpeg;base64,${base64Encode(jpeg)}'),
          jpeg);
    });

    test('صفٌّ لم يُحفظ بعد (قيمٌ فارغة) ⇒ غير مخصَّص', () {
      final s = ReceiptSettings.fromJson({
        'shop_name': null,
        'shop_address': '',
        'shop_phone': null,
        'footer_text': null,
        'show_qr': 1,
        'paper_size': 'pos',
        'logo_data': null,
        'auto_print': 0,
        'design': null,
      });
      expect(s.isCustomized, isFalse);
      expect(s.showFooter && s.showLogo && s.showShopInfo, isTrue);
    });

    test('brandingFor: اسم المحلّ أو الحساب، والأقسام المخفيّة لا تُطبع', () {
      final none = ReceiptService.brandingFor(null, displayName: ' admin@najaf ');
      expect(none.companyName, 'admin@najaf');
      expect(none.branding, isNull, reason: 'الوصل كما كان');

      final full = ReceiptService.brandingFor(
        ReceiptSettings(
          shopName: 'مكتب النجف',
          shopAddress: 'شارع الكوفة',
          shopPhone: '07701234567',
          footerText: 'نشكر ثقتكم',
          logo: pngBytes,
        ),
        displayName: 'admin@najaf',
      );
      expect(full.companyName, 'مكتب النجف');
      expect(full.branding!.address, 'شارع الكوفة');
      expect(full.branding!.phone, '07701234567');
      expect(full.branding!.footer, 'نشكر ثقتكم');
      expect(full.branding!.logo, pngBytes);

      final hidden = ReceiptService.brandingFor(
        ReceiptSettings(
          shopAddress: 'شارع الكوفة',
          shopPhone: '0770',
          footerText: 'نشكر',
          logo: pngBytes,
          showLogo: false,
          showShopInfo: false,
          showFooter: false,
        ),
        displayName: 'admin@najaf',
      );
      expect(hidden.companyName, 'admin@najaf');
      expect(hidden.branding!.address, isNull);
      expect(hidden.branding!.phone, isNull);
      expect(hidden.branding!.footer, '', reason: 'فارغ = بلا تذييل');
      expect(hidden.branding!.logo, isNull);

      final defaultFooter =
          ReceiptService.brandingFor(const ReceiptSettings(shopName: 'م'));
      expect(defaultFooter.branding!.footer, isNull,
          reason: 'null = سطر الشكر المعتاد');
    });

    test('ReceiptBranding.withoutLogo يُبقي الباقي', () {
      final b = ReceiptBranding(
          address: 'a', phone: 'p', footer: 'f', logo: Uint8List(4));
      final w = b.withoutLogo();
      expect([w.address, w.phone, w.footer, w.logo], ['a', 'p', 'f', null]);
    });

    test('fetch: مخبّأٌ بمعرّف الحساب، وforce يجلب جديداً، والفشل null', () async {
      final server = await simSetUp();
      ReceiptSettingsApi.clearCache();
      server.reply('GET', '/api/v2/receipt-settings', 200, {
        'success': true,
        'data': {'shop_name': 'مكتب النجف', 'design': null},
      });
      expect((await ReceiptSettingsApi.fetch())!.shopName, 'مكتب النجف');
      expect((await ReceiptSettingsApi.fetch())!.shopName, 'مكتب النجف');
      expect(server.calls('GET', '/api/v2/receipt-settings'), hasLength(1),
          reason: 'الطباعة لا تجلب الشعار مع كلّ وصل');
      await ReceiptSettingsApi.fetch(force: true);
      expect(server.calls('GET', '/api/v2/receipt-settings'), hasLength(2));

      // شركةٌ أخرى ⇒ لا تُطبع بهويّة سابقتها.
      await const FlutterSecureStorage()
          .write(key: 'auth.admin_id', value: 'earthlink:9');
      server.reply('GET', '/api/v2/receipt-settings', 200, {
        'success': true,
        'data': {'shop_name': 'مكتب كربلاء'},
      });
      expect((await ReceiptSettingsApi.fetch())!.shopName, 'مكتب كربلاء');

      // خادمٌ أقدم (فارغٌ ناجح بقائمة) أو فشل ⇒ null.
      ReceiptSettingsApi.clearCache();
      server.reply('GET', '/api/v2/receipt-settings', 200,
          {'success': true, 'data': <Object>[]});
      expect(await ReceiptSettingsApi.fetch(), isNull);
      server.on('GET', '/api/v2/receipt-settings', simTimeout);
      expect(await ReceiptSettingsApi.fetch(force: true), isNull);
      ReceiptSettingsApi.clearCache();
    });

    test('الجلسة تطبع بإعدادات الويب: ايرث لنك وحدها', () {
      ProviderService.debugSet('earthlink');
      expect(ReceiptService.usesWebReceiptSettings, isTrue);
      ProviderService.debugSet(null);
      expect(ReceiptService.usesWebReceiptSettings, isFalse);
    });
  });

  group('«قوالب الطباعة» — الشاشة', () {
    setUpAll(visualSetUpAll);
    tearDown(ReceiptSettingsApi.clearCache);

    Future<_Proxy> openScreen(
      WidgetTester t,
      Scenario s, {
      Map<String, dynamic>? receipt,
    }) async {
      final server = await visualSetUp(s);
      final proxy = _Proxy(server, {
        'GET /api/v2/receipt-settings': (_) =>
            receipt == null ? null : {'success': true, 'data': receipt},
      });
      ApiClient.dio.httpClientAdapter = proxy;
      await pumpVisual(t, phone, home: (_) => const PrintTemplatesScreen());
      await settle(t, seconds: 2);
      return proxy;
    }

    Future<void> drain(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      await visualTearDown();
    }

    testWidgets('🚨 مالك ايرث لنك: بيانات وصل الويب لا «لم يُنشَأ بعد»', (t) async {
      final proxy = await openScreen(t, s1Owner, receipt: {
        'shop_name': 'مكتب النجف',
        'shop_address': 'شارع الكوفة',
        'shop_phone': '07701234567',
        'footer_text': null,
        'logo_data': 'data:image/png;base64,$_png1x1',
        'design': {'show_footer': true},
      });
      expect(find.text('مكتب النجف'), findsOneWidget);
      expect(find.text('محفوظ من الويب'), findsOneWidget);
      expect(find.text('شارع الكوفة'), findsOneWidget);
      expect(simText('07701234567'), findsOneWidget);
      expect(find.text('شكراً لتعاملكم معنا'), findsOneWidget,
          reason: 'لا تذييل مكتوب ⇒ سطر الشكر المعتاد');
      expect(find.text('لم يُنشَأ بعد'), findsNothing);
      expect(find.text('التصميم من لوحة الويب'), findsOneWidget);
      expect(find.text('التحرير من الويب فقط'), findsNothing);
      expect(proxy.paths.any((p) => p.contains('/api/print-templates')), isFalse,
          reason: 'لا قوالب print_templates لايرث لنك');
      expect(t.takeException(), isNull);
      await drain(t);
    });

    testWidgets('ايرث لنك بلا تخصيص: «لم يُخصَّص بعد» وسببه', (t) async {
      await openScreen(t, s1Owner, receipt: {'shop_name': null});
      expect(find.text('لم يُخصَّص بعد'), findsOneWidget);
      expect(
          find.text('يُطبع الوصل باسم حسابك حتى تحفظ بيانات المحلّ من لوحة الويب.'),
          findsOneWidget);
      await drain(t);
    });

    testWidgets('ايرث لنك وتعذّر الجلب: «تعذّر الجلب» لا شاشة فارغة', (t) async {
      await openScreen(t, s1Owner); // الوكيل يردّ null ⇒ فشل
      expect(find.text('تعذّر الجلب'), findsOneWidget);
      expect(find.text('معاينة'), findsOneWidget, reason: 'المعاينة باسم الحساب');
      await drain(t);
    });

    testWidgets('مالك ساس: القالبان كما كانا (لا إعدادات ويب)', (t) async {
      final proxy = await openScreen(t, s1bSasOwner);
      expect(find.text('قالب A4'), findsOneWidget);
      expect(find.text('قالب POS (80mm)'), findsOneWidget);
      expect(find.text('التحرير من الويب فقط'), findsOneWidget);
      expect(proxy.paths.contains('/api/v2/receipt-settings'), isFalse);
      await drain(t);
    });
  });

  // ═══════════════════════ ٣. بطاقة المشترك — آخر حركة ماليّة ═══════════════════════
  group('آخر حركة ماليّة — الفعل', () {
    test('ايرث لنك: وسم الخادم movement_label', () {
      for (final l in ['تفعيل نقدي', 'تفعيل نقدي جزئي', 'تسديد دين']) {
        expect(lastMovementVerb({'movement_label': l}, earthlink: true), l);
      }
    });

    test('ايرث لنك وخادمٌ بلا وسم: من نوع الحركة', () {
      expect(
          lastMovementVerb(
              {'action_type': 'SUBSCRIBER_ACTIVATE', 'payment_type': 'نقدي'},
              earthlink: true),
          'تفعيل نقدي');
      expect(
          lastMovementVerb({
            'action_type': 'SUBSCRIBER_ACTIVATE',
            'payment_type': 'نقدي جزئي'
          }, earthlink: true),
          'تفعيل نقدي جزئي');
      expect(lastMovementVerb({'action_type': 'DEBT_PAY'}, earthlink: true),
          'تسديد دين');
    });

    test('الساس كما كان: «تسديد دين» دائماً', () {
      expect(
          lastMovementVerb({'movement_label': 'تفعيل نقدي'}, earthlink: false),
          'تسديد دين');
    });

    Subscriber sub() => Subscriber(
          username: 'ali1@najaf',
          firstname: 'علي',
          lastname: 'حسن',
          mobile: '07701000001',
          profileName: 'Economy',
          expiration: '2026-11-04 21:34:00',
          remainingDays: 17,
          price: 25000,
          hasDebtFlag: false,
        );

    Future<String?> barText(WidgetTester t, Map<String, dynamic> pay) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(390, 1000);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              child: SubscriberCardV3(
                sub: sub(),
                selected: false,
                lastPayment: pay,
                onTap: () {},
                onLongPress: () {},
              ),
            ),
          ),
        ),
      ));
      await t.pump();
      // نصّ الشريط الأخضر: «<الفعل> قبل 1 د».
      for (final e in find.byType(Text).evaluate()) {
        final s = (e.widget as Text).data ?? '';
        if (s.endsWith('قبل 1 د') || s.endsWith('الآن')) return s;
      }
      return null;
    }

    final row = {
      'created_at':
          DateTime.now().toUtc().subtract(const Duration(minutes: 1)).toIso8601String(),
      'amount': 25000,
      'action_type': 'SUBSCRIBER_ACTIVATE',
      'payment_type': 'نقدي',
      'movement_label': 'تفعيل نقدي',
    };

    testWidgets('🚨 ايرث لنك: تفعيلٌ نقديّ قبل دقيقة لا «تسديد دين»', (t) async {
      ProviderService.debugSet('earthlink');
      addTearDown(() => ProviderService.debugSet(null));
      final s = await barText(t, row);
      expect(s, isNotNull);
      expect(s!.startsWith('تفعيل نقدي'), isTrue, reason: s);
      expect(s.contains('تسديد دين'), isFalse);
    });

    testWidgets('الساس: النصّ نفسه كما كان', (t) async {
      ProviderService.debugSet(null);
      final s = await barText(t, row);
      expect(s!.startsWith('تسديد دين'), isTrue, reason: s);
    });
  });

  // ═══════════════════════ ٤. إعدادات الإشعارات ═══════════════════════
  group('إعدادات الإشعارات — «دين على مدير فرعي»', () {
    setUpAll(visualSetUpAll);
    const mgrDebt = 'دين على مدير فرعي';
    const nearExpiry = 'اقتراب انتهاء اشتراك';

    Future<void> show(WidgetTester t, Scenario s, {String? provider}) async {
      await visualSetUp(s);
      if (provider != null) ProviderService.debugSet(provider);
      await pumpVisual(t, phone,
          home: (_) => const NotificationsSettingsScreen());
      await settle(t, seconds: 1);
    }

    Future<void> drain(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      await visualTearDown();
    }

    testWidgets('🚨 مالك ايرث لنك: لا مدراء فرعيّين ⇒ لا تنبيه لهم', (t) async {
      await show(t, s1Owner);
      expect(find.text(nearExpiry), findsOneWidget);
      expect(find.text(mgrDebt), findsNothing);
      await drain(t);
    });

    testWidgets('المشروع الوطنيّ (FTTH): مخفيّ كذلك', (t) async {
      await show(t, s1bSasOwner, provider: 'ftth');
      expect(find.text(mgrDebt), findsNothing);
      await drain(t);
    });

    testWidgets('مالك ساس: بمكانه كما كان', (t) async {
      await show(t, s1bSasOwner);
      expect(find.text(mgrDebt), findsOneWidget);
      await drain(t);
    });
  });

  // ═══════════════════════ ٥. بثّ «قرب الانتهاء» ═══════════════════════
  group('بثّ «قرب الانتهاء» — قاعدة الخادم', () {
    // ١٠:٠٠ صباحاً ببغداد (٠٧:٠٠ UTC) يوم ١٨ أكتوبر.
    final now = DateTime.utc(2026, 10, 18, 7);
    Subscriber at(String? exp, {int? remaining}) => Subscriber.fromJson({
          'username': 'u',
          if (exp != null) 'expiration': exp,
          if (remaining != null) 'remaining_days': remaining,
        });

    test('لم ينتهِ بعد ← منتصف ليل بغداد اليوم + ثلاثة أيّام، شاملاً', () {
      expect(broadcastExpiring(at('2026-10-18 08:00:00'), now: now), isFalse,
          reason: 'انتهى صباح اليوم — الخادم يستثنيه فلا «ستنتهي بعد…»');
      expect(broadcastExpiring(at('2026-10-18 00:00:00'), now: now), isFalse,
          reason: 'انتهى منتصف الليل');
      expect(broadcastExpiring(at('2026-10-18 12:00:00'), now: now), isTrue,
          reason: 'ينتهي بعد ساعتين');
      expect(broadcastExpiring(at('2026-10-20 23:59:00'), now: now), isTrue);
      expect(broadcastExpiring(at('2026-10-21 00:00:00'), now: now), isTrue);
      expect(broadcastExpiring(at('2026-10-21 10:00:00'), now: now), isFalse,
          reason: 'بعد حدّ الأيّام الثلاثة');
      expect(broadcastExpiring(at('2026-10-17 23:00:00'), now: now), isFalse,
          reason: 'انتهى أمس');
    });

    test('بلا تاريخٍ مقروء: الأيّام الباقية 1..3', () {
      for (final d in [1, 2, 3]) {
        expect(broadcastExpiring(at(null, remaining: d), now: now), isTrue);
      }
      for (final d in [-1, 0, 4]) {
        expect(broadcastExpiring(at(null, remaining: d), now: now), isFalse);
      }
      expect(broadcastExpiring(at(null), now: now), isFalse);
    });

    test('اليوم يوم بغداد لا يوم الجهاز (٢٢:٣٠ UTC = ٠١:٣٠ بغداد غداً)', () {
      final lateUtc = DateTime.utc(2026, 10, 17, 22, 30);
      expect(broadcastExpiring(at('2026-10-17 23:00:00'), now: lateUtc), isFalse);
      expect(broadcastExpiring(at('2026-10-18 01:00:00'), now: lateUtc), isFalse,
          reason: 'انتهى ١:٠٠ والساعة ١:٣٠ ببغداد');
      expect(broadcastExpiring(at('2026-10-18 02:00:00'), now: lateUtc), isTrue);
    });
  });

  group('بثّ «قرب الانتهاء» — الحمولة', () {
    setUpAll(visualSetUpAll);

    String exp(Duration d) {
      final x = DateTime.now().add(d);
      String two(int n) => n.toString().padLeft(2, '0');
      return '${x.year}-${two(x.month)}-${two(x.day)} '
          '${two(x.hour)}:${two(x.minute)}:00';
    }

    Map<String, Object?> sub(int i, String user, Duration d) => {
          'idx': '$i',
          'username': user,
          'firstname': 'مشترك',
          'lastname': '$i',
          'phone': '0770${1000000 + i}',
          'expiration': exp(d),
          'enabled': 1,
        };

    Future<_Proxy> open(WidgetTester t) async {
      final server = await visualSetUp(s1bSasOwner);
      final proxy = _Proxy(server, {
        'GET /api/v2/subscribers': (_) => {
              'success': true,
              'data': [
                sub(1, 'near1', const Duration(days: 1)),
                sub(2, 'near2', const Duration(days: 2)),
                sub(3, 'far', const Duration(days: 20)),
                sub(4, 'gone', const Duration(days: -5)),
              ],
            },
        'POST /api/v2/whatsapp/bulk-risk': (_) =>
            {'success': true, 'total': 2, 'noInbound': 0, 'highRisk': 0},
        'POST /api/whatsapp/broadcast': (_) => {
              'success': true,
              'message': 'تمت إضافة 2 رسالة لطابور الإرسال',
              'summary': {'queued': 2, 'mode': 'expiring'},
            },
      });
      ApiClient.dio.httpClientAdapter = proxy;
      await pumpVisual(t, phoneTall, home: (_) => const BroadcastScreen());
      await settle(t, seconds: 2);
      await t.tap(find.text('قرب الانتهاء (3 أيام)'));
      await settle(t, seconds: 1);
      return proxy;
    }

    Future<void> sendAndConfirm(WidgetTester t) async {
      await t.tap(find.text('إرسال'));
      await settle(t, seconds: 1);
      expect(find.text('إرسال إلى 2 مشترك؟'), findsOneWidget,
          reason: 'حوار التأكيد بعدد الخادم نفسه');
      await t.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('إرسال')));
      await settle(t, seconds: 2);
    }

    Future<void> drain(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
      await visualTearDown();
    }

    testWidgets('🚨 «عام»: type=expiring بلا أسماء ورسالةٌ فارغة (قالب الخادم)',
        (t) async {
      final proxy = await open(t);
      expect(find.text('2 مشترك'), findsOneWidget);
      await sendAndConfirm(t);
      final body = proxy.writes['POST /api/whatsapp/broadcast'] as Map;
      expect(body['type'], 'expiring');
      expect(body['message'], '');
      expect(body.containsKey('targetUsernames'), isFalse,
          reason: 'الخادم يختار بقاعدته — فيبقى نطاق الإرسال وحماية التكرار');
      await drain(t);
    });

    testWidgets('«محدّد»: type=expiring والأسماء من القائمة نفسها', (t) async {
      final proxy = await open(t);
      await t.tap(find.text('محدّد'));
      await settle(t, seconds: 1);
      await t.tap(find.text('تحديد الكل'));
      await settle(t, seconds: 1);
      await sendAndConfirm(t);
      final body = proxy.writes['POST /api/whatsapp/broadcast'] as Map;
      expect(body['type'], 'expiring');
      expect((body['targetUsernames'] as List).toSet(), {'near1', 'near2'});
      await drain(t);
    });
  });

  // ═══════════════════════ محرّر موظّف ايرث لنك — تلميح الأجهزة ═══════════════════════
  test('تلميحات الأجهزة: العرض والمراقبة يكشفان بيانات دخول أجهزة المشتركين', () {
    expect(ElEmployeePerms.hints['devices.view'], contains('بيانات دخول أجهزة المشتركين'));
    expect(ElEmployeePerms.hints['devices.monitor'],
        contains('بيانات دخول أجهزة المشتركين'));
    expect(ElEmployeePerms.hints['devices.manage'], contains('إعادة تشغيلها'));
  });
}

/// يمرّر للخادم الوهميّ ما لم يُعرَّف هنا، ويسجّل أجسام الكتابة ومسارات كلّ طلب.
/// ردٌّ `null` من المعالج ⇒ مهلةٌ بلا ردّ (فشل جلب).
class _Proxy implements HttpClientAdapter {
  _Proxy(this.inner, this.routes);
  final HttpClientAdapter inner;
  final Map<String, Object? Function(RequestOptions)> routes;
  final writes = <String, Object?>{};
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${o.method.toUpperCase()} ${o.path}';
    paths.add(o.path);
    if (o.method.toUpperCase() != 'GET') writes[key] = o.data;
    final h = routes[key];
    if (h == null) return inner.fetch(o, requestStream, cancelFuture);
    final body = h(o);
    if (body == null) simTimeout(o);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
