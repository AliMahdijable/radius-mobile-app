import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/services/app_version.dart';
import 'package:rad_mysvcs/services/update_gate.dart';

import 'sim_el/sim_harness.dart';

/// إجبار تحديث التطبيق (٣ نوفمبر): رقم النسخة مع كلّ طلب، والإقلاع يسأل /api/app-gate، وردّ APP_FORCE_UPDATE من أيّ طلب ⇒
/// شاشةٌ فوق كلّ شيء لا تُغلق. الخادم: server/appGate.js.
const _v = SimVariant(390, dark: false);

void main() {
  group('إجبار التحديث', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'owner'});
      AppVersion.debugSet(version: '3.0.14', build: '174');
      UpdateGate.debugReset();
    });
    tearDown(() {
      AppVersion.debugSet();
      UpdateGate.debugReset();
    });

    test('كلّ طلب يحمل x-app-build؛ والإقلاع: مفعّل والنسخة أقلّ ⇒ مطلوب، ومطفأ أو مساوية ⇒ لا', () async {
      server.reply('GET', '/api/app-gate', 200, {
        'success': true,
        'data': {'enabled': false, 'min': {'android': 175}, 'store': {}},
      });
      await UpdateGate.check();
      expect(server.calls('GET', '/api/app-gate').single.headers['x-app-build'], '174');
      expect(UpdateGate.required.value, isNull, reason: 'مطفأ');
      server.reply('GET', '/api/app-gate', 200, {
        'success': true,
        'data': {'enabled': true, 'min': {'android': 175, 'ios': 175}, 'store': {'android': 'https://play.example/x'}, 'message': 'حدّث'},
      });
      await UpdateGate.check();
      expect(UpdateGate.required.value?.storeUrl, 'https://play.example/x');
      expect(UpdateGate.required.value?.minBuild, 175);
      UpdateGate.debugReset();
      AppVersion.debugSet(version: '3.0.15', build: '175');
      await UpdateGate.check();
      expect(UpdateGate.required.value, isNull, reason: 'مساوية');
    });

    testWidgets('ردّ APP_FORCE_UPDATE من أيّ طلب ⇒ «تحديثٌ مطلوب» فوق الشاشة، وما تحتها لا يُلمس', (t) async {
      server.reply('GET', '/api/v2/anything', 409, {
        'success': false, 'code': 'APP_FORCE_UPDATE', 'message': 'حدّث التطبيق من المتجر', 'store_url': 'https://play.example/y', 'min_build': 175,
      });
      var taps = 0;
      await pumpSim(t, _v, home: (_) => UpdateGateOverlay(
            child: Scaffold(body: Center(child: TextButton(onPressed: () => taps++, child: const Text('زرّ تحت')))),
          ));
      await t.pumpAndSettle();
      expect(find.text('تحديثٌ مطلوب'), findsNothing);
      await t.runAsync(() => ApiClient.dio.get<dynamic>('/api/v2/anything'));
      await t.pumpAndSettle();
      expect(find.text('تحديثٌ مطلوب'), findsOneWidget);
      expect(find.text('حدّث التطبيق من المتجر'), findsOneWidget);
      expect(find.text('حدّث الآن'), findsOneWidget);
      expect(find.textContaining('المطلوبة: 175'), findsOneWidget);
      await t.tap(find.text('زرّ تحت'), warnIfMissed: false);
      expect(taps, 0, reason: 'ما تحت الشاشة لا يُلمس');
      await simDrain(t);
    });
  });
}
