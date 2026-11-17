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

  Future<void> open(WidgetTester t, {double width = 390, bool? bot, String? botName}) async {
    await pumpSim(t, SimVariant(width, dark: false),
        home: (_) => Scaffold(
            body: SingleChildScrollView(child: TgAccountCard(adminId: '2', botConnected: bot, botUsername: botName))));
    await t.pumpAndSettle();
  }

  /// «المستعمَلة» داخل خيارٍ بعينه — الطريقة المحدَّدة.
  Finder usedIn(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.text('المستعمَلة'));

  void modeServer(SimServer server, {required String Function() get, required void Function(String) set, bool Function()? linked}) {
    server.on('GET', _base, (_) => SimReply(200, _st(mode: get(), linked: linked == null ? true : linked())));
    server.on('PUT', '$_base/mode', (o) {
      set((o.data as Map)['mode'] as String);
      return SimReply(200, {'success': true, 'mode': get()});
    });
  }

  testWidgets('مطفأٌ للحساب ⇒ لا بطاقة', (t) async {
    server.reply('GET', _base, 200, _st(enabled: false));
    await open(t);
    expect(find.byKey(const ValueKey('tg-account-card')), findsNothing);
    await simDrain(t);
  });

  testWidgets('مربوطٌ على «حسابي»: اسمه ويوزره وعدّاد اليوم، و«البوت» يرجع الطريقة', (t) async {
    var mode = 'account';
    modeServer(server, get: () => mode, set: (m) => mode = m);
    await open(t);
    expect(find.textContaining('علي · @ali_agent'), findsOneWidget);
    expect(find.text('اليوم 3 من 30 جديداً'), findsOneWidget);
    expect(usedIn('tg-method-account'), findsOneWidget);
    expect(usedIn('tg-method-bot'), findsNothing);
    await t.tap(find.text('البوت'));
    await t.pumpAndSettle();
    expect(server.bodies('PUT', '$_base/mode').single, {'adminId': '2', 'mode': 'bot'});
    expect(usedIn('tg-method-bot'), findsOneWidget, reason: 'البوت هو المستعمَل الآن');
    expect(usedIn('tg-method-account'), findsNothing);
    expect(find.textContaining('علي · @ali_agent'), findsOneWidget, reason: 'الحساب يبقى مربوطاً ظاهراً في خياره');
    await simDrain(t);
  });

  testWidgets('الربط برقم الهاتف: الرقم ⇒ الرمز ⇒ كلمة التحقّق ⇒ مربوط', (t) async {
    var linked = false;
    var mode = 'bot';
    modeServer(server, get: () => mode, set: (m) => mode = m, linked: () => linked);
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
    expect(find.textContaining('علي · @ali_agent'), findsOneWidget);
    expect(server.bodies('PUT', '$_base/mode').single, {'adminId': '2', 'mode': 'account'},
        reason: '١٧ نوفمبر: الحساب المربوط للتوّ يصير المستعمَل — لا يبقى «البوت» غير المربوط');
    expect(usedIn('tg-method-account'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('رمز QR (الشاشة العريضة): يظهر الرمز ويتجدّد، وحين يُمسح تُغلق الورقة مربوطاً', (t) async {
    var linked = false;
    var polls = 0;
    var mode = 'bot';
    modeServer(server, get: () => mode, set: (m) => mode = m, linked: () => linked);
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
    expect(find.textContaining('علي · @ali_agent'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('١٧ نوفمبر: خيار «البوت» يقول حاله — مربوط @البوت، أو غير مربوط «اربطه أدناه» حين هو المستعمَل', (t) async {
    var mode = 'bot';
    modeServer(server, get: () => mode, set: (m) => mode = m, linked: () => true);
    await open(t, bot: true, botName: 'mysvcs_bot');
    final botTile = find.byKey(const ValueKey('tg-method-bot'));
    expect(find.descendant(of: botTile, matching: find.text('مربوط')), findsOneWidget);
    expect(find.descendant(of: botTile, matching: find.textContaining('@mysvcs_bot')), findsOneWidget);
    expect(usedIn('tg-method-bot'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('البوت غير مربوط وهو المستعمَل ⇒ «غير مربوط» + «اربطه من «ربط البوت» أدناه»؛ والحساب غير المربوط زرّ «ربط حسابي»', (t) async {
    var mode = 'bot';
    modeServer(server, get: () => mode, set: (m) => mode = m, linked: () => false);
    await open(t, bot: false);
    final botTile = find.byKey(const ValueKey('tg-method-bot'));
    expect(find.descendant(of: botTile, matching: find.text('غير مربوط')), findsOneWidget);
    expect(find.descendant(of: botTile, matching: find.textContaining('اربطه من «ربط البوت» أدناه')), findsOneWidget);
    final accTile = find.byKey(const ValueKey('tg-method-account'));
    expect(find.descendant(of: accTile, matching: find.text('غير مربوط')), findsOneWidget);
    expect(find.descendant(of: accTile, matching: find.byKey(const ValueKey('tg-account-link'))), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('حسابٌ مربوط والطريقة «البوت» ⇒ «استعمل حسابي» يحوّلها (بلا بحثٍ عن الخيار)', (t) async {
    var mode = 'bot';
    modeServer(server, get: () => mode, set: (m) => mode = m, linked: () => true);
    await open(t, bot: false);
    await t.tap(find.byKey(const ValueKey('tg-use-account')));
    await t.pumpAndSettle();
    expect(server.bodies('PUT', '$_base/mode').single, {'adminId': '2', 'mode': 'account'});
    expect(usedIn('tg-method-account'), findsOneWidget);
    expect(find.byKey(const ValueKey('tg-use-account')), findsNothing, reason: 'المستعمَل لا يُعرض له «استعمل»');
    await simDrain(t);
  });
}
