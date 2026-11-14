import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/tg_account_api.dart';
import 'package:rad_mysvcs/screens/telegram/widgets/tg_account_card.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «تلغرام بحساب الوكيل» بالتطبيق (١٤ نوفمبر — كالويب): «طريقة الإرسال بتلغرام» البوت / حسابي، وربط الحساب برقمه والرمز وكلمة
/// التحقّق بخطوتين أو برمز QR. مطفأٌ للحساب ⇒ لا بطاقة.
const _base = TgAccountApi.base;
const _png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

Map<String, dynamic> _st({bool enabled = true, String mode = 'bot', bool linked = false}) => {
      'success': true,
      'data': {
        'enabled': enabled,
        if (enabled) ...{
          'service': 'up',
          'configured': true,
          'mode': mode,
          'linked': linked,
          'status': linked ? 'connected' : 'disconnected',
          'user': linked ? {'name': 'علي', 'username': 'ali_agent', 'phone_tail': '4567'} : null,
          'daily_new_cap': 30,
          'today_new': 3,
        },
      },
    };

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'myservices'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
  });

  tearDown(PermissionsService.debugReset);

  Future<void> open(WidgetTester t, {double width = 390}) async {
    await pumpSim(t, SimVariant(width, dark: false),
        home: (_) => const Scaffold(body: SingleChildScrollView(child: TgAccountCard(adminId: '2'))));
    await t.pumpAndSettle();
  }

  testWidgets('مطفأٌ للحساب ⇒ لا بطاقة', (t) async {
    server.reply('GET', _base, 200, _st(enabled: false));
    await open(t);
    expect(find.byKey(const ValueKey('tg-account-card')), findsNothing);
    await simDrain(t);
  });

  testWidgets('مربوطٌ على «حسابي»: اسمه ويوزره وعدّاد اليوم، و«البوت» يرجع الطريقة', (t) async {
    var mode = 'account';
    server.on('GET', _base, (_) => SimReply(200, _st(mode: mode, linked: true)));
    server.on('PUT', '$_base/mode', (o) {
      mode = (o.data as Map)['mode'] as String;
      return SimReply(200, {'success': true, 'mode': mode});
    });
    await open(t);
    expect(find.text('علي · @ali_agent'), findsOneWidget);
    expect(find.text('اليوم 3 من 30 جديداً'), findsOneWidget);
    await t.tap(find.text('البوت'));
    await t.pumpAndSettle();
    expect(server.bodies('PUT', '$_base/mode').single, {'adminId': '2', 'mode': 'bot'});
    expect(find.textContaining('من البوت'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('الربط برقم الهاتف: الرقم ⇒ الرمز ⇒ كلمة التحقّق ⇒ مربوط', (t) async {
    var linked = false;
    server.on('GET', _base, (_) => SimReply(200, _st(linked: linked)));
    server.reply('POST', '$_base/login/phone', 200, {'success': true, 'login_id': 'L1', 'code_via': 'app'});
    server.reply('POST', '$_base/login/code', 200, {'success': true, 'need_password': true, 'hint': 'اسم القطّة'});
    server.on('POST', '$_base/login/password', (_) {
      linked = true;
      return const SimReply(200, {'success': true, 'done': true});
    });
    await open(t);
    await t.tap(find.byKey(const ValueKey('tg-account-link')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('tg-link-phone')), '07701234567');
    await t.tap(find.text('أرسل الرمز'));
    await t.pumpAndSettle();
    expect(server.bodies('POST', '$_base/login/phone').single, {'adminId': '2', 'phone': '07701234567'});
    await t.enterText(find.byKey(const ValueKey('tg-link-code')), '12345');
    await t.tap(find.text('دخول'));
    await t.pumpAndSettle();
    expect(find.text('تلميحها: اسم القطّة'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('tg-link-password')), 'secret');
    await t.tap(find.text('دخول'));
    await t.pumpAndSettle();
    expect(server.bodies('POST', '$_base/login/password').single, {'adminId': '2', 'login_id': 'L1', 'password': 'secret'});
    expect(find.byKey(const ValueKey('tg-link-password')), findsNothing, reason: 'الورقة أُغلقت');
    expect(find.text('علي · @ali_agent'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('رمز QR (الشاشة العريضة): يظهر الرمز ويتجدّد، وحين يُمسح تُغلق الورقة مربوطاً', (t) async {
    var linked = false;
    var polls = 0;
    server.on('GET', _base, (_) => SimReply(200, _st(linked: linked)));
    server.reply('POST', '$_base/login/qr', 200, {'success': true, 'login_id': 'Q1'});
    server.on('POST', '$_base/login/qr/poll', (_) {
      polls++;
      if (polls >= 3) {
        linked = true;
        return const SimReply(200, {'success': true, 'state': 'linked'});
      }
      return const SimReply(200, {'success': true, 'state': 'qr', 'qr_png': _png, 'qr_expires_in': 25});
    });
    await open(t, width: 900);
    await t.tap(find.byKey(const ValueKey('tg-account-link')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('tg-link-qr')), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(polls, greaterThanOrEqualTo(3));
    expect(find.byKey(const ValueKey('tg-link-qr')), findsNothing, reason: 'الورقة أُغلقت');
    expect(find.text('علي · @ali_agent'), findsOneWidget);
    await simDrain(t);
  });
}
