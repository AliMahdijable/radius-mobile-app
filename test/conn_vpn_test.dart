import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/conn_vpn_api.dart';
import 'package:rad_mysvcs/screens/whatsapp/conn_vpn_screen.dart';

import 'sim_el/sim_harness.dart';

/// «ربط VPN» بالتطبيق (٣ نوفمبر): نفق الشركة / الربط التلقائيّ بقالب سوبرنت / ملفّ الوكيل، و«فحص الاتصال» والاتصال العكسي.
const _v = SimVariant(390, dark: false);

Map<String, dynamic> _status({
  Map<String, dynamic>? company,
  Map<String, dynamic>? auto,
  Map<String, dynamic>? profile,
  bool reverse = false,
  Map<String, dynamic>? lastTest,
}) =>
    {
      'success': true,
      'data': {
        'company_tunnel': company,
        'auto_link': auto,
        'profile': profile,
        'reverse_enabled': reverse,
        'last_test': lastTest,
        'last_sweep': {'at_ms': DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch, 'online': 4, 'reachable': 3, 'readable': 2},
      },
    };

void main() {
  test('الحالة: الربط التلقائيّ لا يظهر لمن يصله نفق الشركة أو له ملفّه؛ الفحص متاحٌ بأيٍّ منها', () {
    final auto = ConnVpnStatus.fromJson(Map<String, dynamic>.from(_status(auto: {'label': 'سوبرنت الثالث', 'user': '@m'})['data'] as Map));
    expect((auto.autoLinked, auto.canTest, auto.covered), (true, true, false));
    final both = ConnVpnStatus.fromJson(Map<String, dynamic>.from(
        _status(auto: {'label': 'x', 'user': '@m'}, profile: {'saved': true, 'has_auth': true})['data'] as Map));
    expect((both.autoLinked, both.profileSaved, both.canTest), (false, true, true));
    final none = ConnVpnStatus.fromJson(Map<String, dynamic>.from(_status()['data'] as Map));
    expect(none.canTest, false);
    expect(none.sweepReachable, 3);
    final a = ConnVpnAnalysis.fromJson({'ok': true, 'errors': [], 'needs_auth': false, 'embedded_auth': true, 'needs_key_password': true, 'servers': 1});
    expect((a.needsKeyPassword, a.embeddedAuth), (true, true));
  });

  group('الشاشة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': '2957', 'auth.admin_username': 'admin@m'});
    });

    testWidgets('غير متاح (موظّف أو لم يُفتح) ⇒ رسالةٌ لا أخطاء', (t) async {
      server.reply('GET', '/api/v2/conn-vpn/status', 403, {'success': false, 'message': 'لصاحب الحساب وحده'});
      await pumpSim(t, _v, home: (_) => const ConnVpnScreen());
      await t.pumpAndSettle();
      expect(find.textContaining('غير متاحٍ لحسابك'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('سوبرنت بالقالب: «تُربط تلقائيّاً… بحسابك @m» + رفعٌ اختياريّ، و«فحص الاتصال» يستطلع حتى النتيجة', (t) async {
      server.reply('GET', '/api/v2/conn-vpn/status', 200, _status(auto: {'label': 'سوبرنت الثالث (VPN-ALL)', 'user': '@m'}));
      server.reply('POST', '/api/v2/conn-vpn/test', 200, {'success': true, 'data': {'test_id': 'abc'}});
      server.reply('GET', '/api/v2/conn-vpn/test/abc', 200, {
        'success': true,
        'data': {'state': 'done', 'result': {'connected': true, 'message': 'اتّصل ✓ — وصل 3 من 4 من مشتركيك، وقُرئ جهاز 2', 'at_ms': DateTime.now().millisecondsSinceEpoch}},
      });
      await pumpSim(t, _v, home: (_) => const ConnVpnScreen());
      await t.pumpAndSettle();
      expect(find.textContaining('تُربط تلقائيّاً عبر سوبرنت الثالث (VPN-ALL)'), findsOneWidget);
      expect(find.textContaining('@m'), findsOneWidget);
      expect(find.text('ارفع ملفّك بيوزرك (اختياريّ)'), findsOneWidget);
      expect(find.textContaining('آخر جولة'), findsOneWidget);
      await t.tap(find.text('فحص الاتصال'));
      await t.pump();
      expect(find.text('يفحص… (قد يأخذ دقيقة)'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      expect(find.textContaining('وصل 3 من 4'), findsOneWidget);
      expect(server.calls('GET', '/api/v2/conn-vpn/test/abc'), hasLength(1));
      await simDrain(t);
    });

    testWidgets('نفق الشركة: «مربوطة» بلا رفع؛ الاتصال العكسي يُرسل enabled', (t) async {
      server.reply('GET', '/api/v2/conn-vpn/status', 200, _status(company: {'label': 'ايرث لنك', 'healthy': true}));
      server.reply('PUT', '/api/v2/conn-vpn/reverse', 200, {'success': true, 'message': 'فُعّل الاتصال العكسي'});
      await pumpSim(t, _v, home: (_) => const ConnVpnScreen());
      await t.pumpAndSettle();
      expect(find.textContaining('شركتك (ايرث لنك) مربوطة'), findsOneWidget);
      expect(find.textContaining('ارفع ملفّ'), findsNothing);
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(server.bodies('PUT', '/api/v2/conn-vpn/reverse').single['enabled'], true);
      await simDrain(t);
    });
  });
}
