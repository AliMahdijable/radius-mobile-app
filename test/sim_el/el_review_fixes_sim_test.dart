import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/screens/print_templates/print_templates_screen.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/widgets/sas_captcha_sheet.dart';
import 'package:rad_mysvcs/widgets/two_factor_sheet.dart';

import 'sim_harness.dart';

/// محاكاة تدقيق ١٨ أكتوبر (الدفعة ①) — نافذة كود التحقّق بخطوتين عند الدخول،
/// و«قوالب الطباعة» لايرث لنك بإعدادات وصل الويب. اللقطات في `shots/el_2fa/`
/// و`shots/el_receipt/`. السلوك نفسه مفحوصٌ في `el_parity_batch1_fixes_test`؛
/// هنا الرسم: لا فيضان ولا نصّ خام بالعروض الثلاثة وبالوضعين.
const _twofa = 'el_2fa';
const _receipt = 'el_receipt';

const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

void main() {
  late SimServer server;
  late DateTime fakeNow;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp();
    fakeNow = DateTime(2026, 10, 18, 10);
    TwoFactorSheet.clock = () => fakeNow;
    ReceiptSettingsApi.clearCache();
  });

  tearDown(() {
    TwoFactorSheet.clock = DateTime.now;
    ProviderService.debugSet(null);
    ReceiptSettingsApi.clearCache();
  });

  /// خطواتٌ محدودة: عدّاد المهلة ودوّارة التحقّق لا يهدآن.
  Future<void> steps(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// يُغلق الشجرة فيُلغى مؤقّت العدّاد قبل نهاية الاختبار.
  Future<void> dispose(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  }

  Future<void> openTwoFactor(WidgetTester t, SimVariant v) async {
    server.reply('POST', '/api/auth/login', 200, {
      'success': false,
      'requires2fa': true,
      'tempId': '2fa_sim',
      'expiresIn': 120,
      'message': 'أدخل كود 2FA من تطبيق Google Authenticator',
    });
    await pumpSim(t, v,
        home: (_) => simLauncher((c) =>
            SasCaptchaLogin.login(c, username: 'mahdi.el', password: 'pw')));
    await t.tap(find.text(simOpenLabel));
    await steps(t);
    expect(find.text('التحقّق بخطوتين'), findsOneWidget);
  }

  simCase(_twofa, 'code', (t, v) async {
    await openTwoFactor(t, v);
    expect(simText('تنتهي المهلة خلال 2:00'), findsOneWidget);
    await simCheck(t, v, _twofa, 'code');
    await dispose(t);
  });

  simCase(_twofa, 'wrong_code', (t, v) async {
    server.reply('POST', '/api/auth/2fa/verify', 401,
        {'success': false, 'message': 'الكود غير صحيح'});
    await openTwoFactor(t, v);
    fakeNow = fakeNow.add(const Duration(seconds: 105));
    await t.enterText(find.byType(TextField), '111111');
    await steps(t);
    expect(find.text('الكود غير صحيح'), findsOneWidget);
    expect(simText('تنتهي المهلة خلال 0:15'), findsOneWidget,
        reason: 'الثواني الأخيرة بلون الخطر');
    await simCheck(t, v, _twofa, 'wrong_code');
    await dispose(t);
  });

  simCase(_twofa, 'expired', (t, v) async {
    await openTwoFactor(t, v);
    fakeNow = fakeNow.add(const Duration(minutes: 3));
    await t.pump(const Duration(seconds: 1));
    await steps(t, 3);
    expect(find.text('إعادة الدخول'), findsOneWidget);
    await simCheck(t, v, _twofa, 'expired');
    await dispose(t);
  });

  simCase(_receipt, 'customized', (t, v) async {
    ProviderService.debugSet('earthlink');
    server.reply('GET', '/api/v2/receipt-settings', 200, {
      'success': true,
      'data': {
        'shop_name': 'مكتب النور للإنترنت',
        'shop_address': 'النجف — حيّ الأنصار، قرب جامع الأنصار',
        'shop_phone': '07801234567',
        'footer_text': 'شكراً لثقتكم — للدعم اتّصل بنا',
        'logo_data': 'data:image/png;base64,$_png1x1',
        'design': {'show_logo': true, 'show_shop_info': true},
      },
    });
    await pumpSim(t, v, home: (_) => const PrintTemplatesScreen());
    expect(find.text('مكتب النور للإنترنت'), findsOneWidget);
    expect(find.text('محفوظ من الويب'), findsOneWidget);
    await simCheck(t, v, _receipt, 'customized');
  });

  simCase(_receipt, 'not_customized', (t, v) async {
    ProviderService.debugSet('earthlink');
    server.reply('GET', '/api/v2/receipt-settings', 200, {
      'success': true,
      'data': {'shop_name': null, 'design': null},
    });
    await pumpSim(t, v, home: (_) => const PrintTemplatesScreen());
    expect(find.text('لم يُخصَّص بعد'), findsOneWidget);
    await simCheck(t, v, _receipt, 'not_customized');
  });
}
