// «آخر دخول المشتركين» في «بوابة المشترك»: ٥ قراءات أوّلاً ثمّ «عرض المزيد» ٥ ٥ (١٧ نوفمبر — المالك: «بوابه المشترك السجل خلي
// ٥ قراءات فقط ويكدر يحمل المزيد»). المجلوب ٢٠ (حدّ الخادم ٢٠٠ — portalBroker.listLogins): تنفد المعروضة والمجلوب ممتلئ ⇒
// «عرض المزيد» يطلب ٤٠ ويعرض ٥ أخرى؛ والمجلوب أقلّ من حدّه ⇒ لا زرّ بعد آخر صفّ.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/portal_settings/portal_settings_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

const _settings = '/api/v2/portal/settings';
const _logins = '/api/v2/portal/logins';
const _v = SimVariant(360, dark: false);

List<Map<String, dynamic>> _rows(int n) => [
      for (var i = 0; i < n; i++)
        {
          'at': DateTime.utc(2026, 11, 17, 6, 59 - i).toIso8601String(),
          'username_lc': 'u${(i + 1).toString().padLeft(2, '0')}@popq',
          'via': i.isEven ? 'pw' : 'qr',
          'result': 'ok',
        },
    ];

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': '2251'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  Finder rows() => find.byWidgetPredicate((w) => w.runtimeType.toString() == '_LoginRow');
  final more = find.byKey(const ValueKey('portal-logins-more'));

  Future<void> open(WidgetTester t) async {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    server.reply('GET', _settings, 200, {'success': true, 'enabled': true, 'agent_code': '402917'});
    await pumpSim(t, _v, home: (_) => const PortalSettingsScreen());
    t.view.physicalSize = const Size(400, 3200);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> tapMore(WidgetTester t) async {
    await t.ensureVisible(more);
    await t.tap(more);
    await t.pumpAndSettle();
  }

  testWidgets('١٢ قراءة: ٥ ثمّ ١٠ ثمّ ١٢ — والزرّ يختفي بعد آخرها (لا طلبٌ زائد)', (t) async {
    server.reply('GET', _logins, 200, {'success': true, 'data': _rows(12)});
    await open(t);
    expect(rows(), findsNWidgets(5));
    expect(find.text('عرض المزيد'), findsOneWidget);
    await tapMore(t);
    expect(rows(), findsNWidgets(10));
    await tapMore(t);
    expect(rows(), findsNWidgets(12));
    expect(more, findsNothing);
    expect(server.calls('GET', _logins), hasLength(1), reason: 'الكلّ مجلوبٌ أصلاً');
    expect(server.calls('GET', _logins).single.queryParameters, {'limit': 20});
  });

  testWidgets('المجلوب ممتلئ (٢٠): بعد ٢٠ معروضةً «عرض المزيد» يطلب ٤٠ ويعرض ٢٥', (t) async {
    server.reply('GET', _logins, 200, {'success': true, 'data': _rows(20)});
    await open(t);
    for (var i = 0; i < 3; i++) {
      await tapMore(t);
    }
    expect(rows(), findsNWidgets(20));
    expect(more, findsOneWidget, reason: 'قد يكون بالخادم أكثر');
    server.reply('GET', _logins, 200, {'success': true, 'data': _rows(27)});
    await tapMore(t);
    expect(server.calls('GET', _logins).last.queryParameters, {'limit': 40});
    expect(rows(), findsNWidgets(25));
    await tapMore(t);
    expect(rows(), findsNWidgets(27));
    expect(more, findsNothing, reason: '٢٧ < ٤٠ ⇒ لا أكثر');
  });

  testWidgets('٥ أو أقلّ: لا زرّ أصلاً', (t) async {
    server.reply('GET', _logins, 200, {'success': true, 'data': _rows(5)});
    await open(t);
    expect(rows(), findsNWidgets(5));
    expect(more, findsNothing);
  });
}
