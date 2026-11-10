import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/agent_alerts_api.dart';
import 'package:rad_mysvcs/screens/network_devices/agent_alerts_screen.dart';

import 'sim_el/sim_harness.dart';

/// «تنبيهات أجهزتي» (٤ نوفمبر — الخادم server/agentAlerts.js): الحال والسجلّ والإعداد و«كيف تُراقَب»، وإسكات تنبيه الموبايل المحلّيّ
/// حين يعمل الخادم، والنقر على الإشعار.
const _v = SimVariant(390, dark: false);

int _ago(Duration d) => DateTime.now().subtract(d).millisecondsSinceEpoch;

Map<String, dynamic> _status({
  bool available = true,
  bool dry = false,
  bool canUse = true,
  bool canEdit = true,
  bool enabled = true,
  Map<String, dynamic>? remote,
  List<Map<String, dynamic>> down = const [],
  List<Map<String, dynamic>>? downStale,
  List<Map<String, dynamic>> quiet = const [],
}) =>
    {
      'success': true,
      'data': available
          ? {
              'available': true, 'dry_run': dry, 'enabled': enabled, 'notify_up': true, 'can_use': canUse, 'can_edit': canEdit,
              'remote': remote,
              if (canUse) ...{
                'devices': 14, 'monitored': 14, 'down': down, 'quiet': quiet, 'network_down': false,
                if (downStale != null) 'down_stale': downStale,
                'last_app_ms': _ago(const Duration(minutes: 2)), 'last_vpn_ms': null,
              },
            }
          : {'available': false},
    };

Map<String, dynamic> _log(List<Map<String, dynamic>> items) => {'success': true, 'data': {'available': true, 'items': items}};

void main() {
  test('النماذج: الحال والفحص عن بُعد والسجلّ، والعدد بصيغته', () {
    final st = AgentAlertsStatus.fromJson(Map<String, dynamic>.from(_status(
      remote: {'on': false, 'why': 'reverse_off', 'via': 'company'},
      down: [{'id': 3, 'name': 'سكتر 2', 'type': 'sector', 'place': 'برج «النصر»', 'since_ms': 5}],
      quiet: [{'id': 4, 'name': 'لنك', 'until_ms': 9}],
    )['data'] as Map));
    expect(st.available, true);
    expect(st.down.single.place, 'برج «النصر»');
    expect(st.quiet.single.untilMs, 9);
    expect(st.downStale, isEmpty, reason: 'خادمٌ أقدم لا يرسلها');
    final stale = AgentAlertsStatus.fromJson(Map<String, dynamic>.from(_status(
      downStale: [{'id': 9, 'name': 'لنك', 'since_ms': 5, 'checked_ms': 7}, {'id': 10, 'name': 'سويج', 'since_ms': 5, 'checked_ms': null}],
    )['data'] as Map));
    expect(stale.down, isEmpty);
    expect(stale.downStale.map((d) => [d.id, d.checkedMs]), [[9, 7], [10, null]]);
    expect(st.remote!.fixableInVpn, true);
    expect(st.remote!.text, contains('«الاتصال العكسي»'));
    expect(const AgentAlertRemote(on: false, why: 'template').text, contains('يقفل دخولك أنت'));
    expect(const AgentAlertRemote(on: true, healthy: true).text, contains('كلّ دقيقة'));
    final e = AgentAlertEvent.fromJson({'id': 7, 'kind': 'tower_up', 'title': '🟢 رجع برج «النصر»', 'devices': [1, 2], 'push': 'dry', 'at_ms': 1});
    expect(e!.isUp, true);
    expect(e.devices, [1, 2]);
    expect(countDevices(1), 'جهازٌ واحد');
    expect(countDevices(2), 'جهازان');
    expect(countDevices(7), '7 أجهزة');
    expect(countDevices(14), '14 جهازاً');
  });

  test('تنبيه الموبايل المحلّيّ يسكت حين يعمل الخادم لهذه الشركة وحده — ويعود بعد تبديل الشركة', () {
    AgentAlertsApi.forget();
    expect(AgentAlertsApi.shouldFireLocalAlerts(), true, reason: 'لم يُقرأ بعد ⇒ كما كان');
    AgentAlertsApi.cached = AgentAlertsStatus.fromJson(Map<String, dynamic>.from(_status()['data'] as Map));
    expect(AgentAlertsApi.shouldFireLocalAlerts(), false);
    AgentAlertsApi.cached = AgentAlertsStatus.fromJson(Map<String, dynamic>.from(_status(enabled: false)['data'] as Map));
    expect(AgentAlertsApi.shouldFireLocalAlerts(), true, reason: 'أطفأه الوكيل ⇒ لا يُسكت تنبيه موبايله');
    AgentAlertsApi.cached = AgentAlertsStatus.off;
    expect(AgentAlertsApi.shouldFireLocalAlerts(), true);
    AgentAlertsApi.cached = AgentAlertsStatus.fromJson(Map<String, dynamic>.from(_status()['data'] as Map));
    AgentAlertsApi.forget();
    expect(AgentAlertsApi.shouldFireLocalAlerts(), true);
  });

  group('الشاشة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      AgentAlertsApi.forget();
      server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin@m'});
    });

    testWidgets('غير مفتوحةٍ لحسابه ⇒ رسالةٌ وزرّ «تنبيهات موبايلك»، بلا طلب سجلّ', (t) async {
      server.reply('GET', '/api/v2/agent-alerts/status', 200, _status(available: false));
      await pumpSim(t, _v, home: (_) => const AgentAlertsScreen());
      await t.pumpAndSettle();
      expect(find.textContaining('غير مفعّلة لحسابك بعد'), findsOneWidget);
      expect(find.text('تنبيهات موبايلك'), findsOneWidget);
      expect(server.calls('GET', '/api/v2/agent-alerts/log'), isEmpty);
      await simDrain(t);
    });

    testWidgets('موظّفٌ بلا القسم ⇒ مقفلة («لا صلاحيّة») لا مخفيّة', (t) async {
      server.reply('GET', '/api/v2/agent-alerts/status', 200, _status(canUse: false, canEdit: false));
      await pumpSim(t, _v, home: (_) => const AgentAlertsScreen());
      await t.pumpAndSettle();
      expect(find.text('لا صلاحيّة'), findsOneWidget);
      expect(find.textContaining('تنبيهات أجهزة الشبكة — القسم'), findsOneWidget);
      expect(server.calls('GET', '/api/v2/agent-alerts/log'), isEmpty);
      await simDrain(t);
    });

    testWidgets('المدير: التجربة، الطافية بمكانها ومدّتها، المتذبذب، السجلّ بوسومه، و«ربط VPN» حين يلزم؛ الإطفاء يرسل enabled:false', (t) async {
      server.reply('GET', '/api/v2/agent-alerts/status', 200, _status(
        dry: true,
        remote: {'on': false, 'why': 'reverse_off', 'via': 'company'},
        down: [
          {'id': 3, 'name': 'سكتر 2', 'place': 'برج «النصر»', 'since_ms': _ago(const Duration(minutes: 12))},
          {'id': 5, 'name': 'لنك الحيّ', 'since_ms': _ago(const Duration(minutes: 3))},
        ],
        quiet: [{'id': 6, 'name': 'سويج 1', 'until_ms': DateTime.now().add(const Duration(minutes: 40)).millisecondsSinceEpoch}],
      ));
      server.reply('GET', '/api/v2/agent-alerts/log', 200, _log([
        {'id': 9, 'kind': 'tower_down', 'title': '🔴 طفى برج «النصر»', 'detail': 'كلّ أجهزته (3) لا تستجيب منذ 3 د', 'push': 'dry', 'at_ms': _ago(const Duration(minutes: 9))},
        {'id': 8, 'kind': 'up', 'title': '🟢 رجع «لنك 1»', 'detail': 'بعد 12 د انقطاع', 'push': 'off', 'at_ms': _ago(const Duration(hours: 1))},
        {'id': 7, 'kind': 'blip', 'title': 'انقطع «كاميرا» ورجع', 'detail': 'انقطع 3 د ثمّ رجع قبل الإشعار', 'push': 'none', 'at_ms': _ago(const Duration(hours: 2))},
      ]));
      server.reply('PUT', '/api/v2/agent-alerts/settings', 200, {'success': true, 'data': {'enabled': false, 'notify_up': true}});
      await pumpSim(t, _v, home: (_) => const AgentAlertsScreen());
      await t.pumpAndSettle();
      expect(find.textContaining('تجربة: يُسجَّل ما كان سيُقال لك'), findsOneWidget);
      expect(find.text('جهازان طافيان الآن'), findsOneWidget);
      expect(find.textContaining('14 جهازاً تحت المراقبة'), findsOneWidget);
      expect(find.text('سكتر 2'), findsOneWidget);
      expect(find.text('برج «النصر»'), findsOneWidget);
      expect(find.text('منذ 12 د'), findsOneWidget);
      expect(find.text('سويج 1'), findsOneWidget);
      await t.scrollUntilVisible(find.text('طفى برج «النصر»'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('طفى برج «النصر»'), findsOneWidget, reason: 'العنوان بلا رمزه الملوّن');
      expect(find.text('تجربة'), findsOneWidget);
      expect(find.text('بلا إشعار'), findsOneWidget);
      expect(find.text('ربط VPN'), findsOneWidget, reason: 'الإجراء ظاهرٌ والقسم مطويّ');
      // «كيف تُراقَب» تنطوي (٦ نوفمبر) — تُفتح أوّلاً
      await t.scrollUntilVisible(find.byKey(const ValueKey('aa-how-head')), 300, scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const ValueKey('aa-how-head')));
      await t.pumpAndSettle();
      expect(find.textContaining('«الاتصال العكسي»'), findsWidgets);
      server.reply('GET', '/api/v2/agent-alerts/status', 200, _status(enabled: false, remote: {'on': false, 'why': 'reverse_off'}));
      await t.scrollUntilVisible(find.text('نبّهني حين يطفى جهاز'), -300, scrollable: find.byType(Scrollable).first);
      await t.tap(find.byType(Switch).first);
      await t.pumpAndSettle();
      expect(server.bodies('PUT', '/api/v2/agent-alerts/settings').single, {'enabled': false});
      expect(find.text('التنبيه مطفأ — لا يُقال لك شيء'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('١١ نوفمبر («غير دقيقه»): ما لم يُفحص منذ مدّة ليس «طافياً الآن» — بقسمه ووقت آخر فحصه؛ والشاشة تتحدّث وحدها كلّ ٢٠ث',
        (t) async {
      // حال المالك: التنبيه مطفأ، وصفّان «طافيان» منذ يومين لم يقسهما أحد — وقائمته ١٤ متّصلاً
      server.reply('GET', '/api/v2/agent-alerts/status', 200, _status(
        enabled: false,
        downStale: [
          {'id': 1514, 'name': 'سيرفر التوزيع', 'place': 'برج «برجي»', 'since_ms': _ago(const Duration(days: 2, hours: 18)), 'checked_ms': null},
          {'id': 5308, 'name': 'AirFiber 60LR', 'place': 'برج «برجي»', 'since_ms': _ago(const Duration(days: 2)), 'checked_ms': _ago(const Duration(hours: 3))},
        ],
      ));
      server.reply('GET', '/api/v2/agent-alerts/log', 200, _log([]));
      await pumpSim(t, _v, home: (_) => const AgentAlertsScreen());
      await t.pumpAndSettle();
      expect(find.text('طافية الآن'), findsNothing, reason: 'لا دعوى عن «الآن» بلا فحصٍ حديث');
      expect(find.text('كانت طافية عند آخر فحص'), findsOneWidget);
      expect(find.textContaining('افتح قسم الأجهزة وأنت على شبكتك لتُعرف حالها الآن'), findsOneWidget);
      expect(find.text('سيرفر التوزيع'), findsOneWidget);
      expect(find.textContaining('آخر فحص'), findsWidgets);
      expect(find.text('التنبيه مطفأ — لا يُقال لك شيء'), findsOneWidget);
      // مفعّلاً: لا «كلّ أجهزتك تعمل» وبعضها لم يُعرف حاله
      server.reply('GET', '/api/v2/agent-alerts/status', 200, _status(
        downStale: [{'id': 1514, 'name': 'سيرفر التوزيع', 'since_ms': _ago(const Duration(hours: 5)), 'checked_ms': _ago(const Duration(hours: 4))}],
      ));
      final before = server.calls('GET', '/api/v2/agent-alerts/status').length;
      await t.pump(AgentAlertsScreen.refreshEvery + const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(server.calls('GET', '/api/v2/agent-alerts/status').length, before + 1, reason: 'تحدّثت وحدها');
      expect(find.textContaining('لا شيء طافٍ الآن ممّا فُحص — جهازٌ واحد لم يُفحص منذ مدّة'), findsOneWidget);
      expect(find.text('كلّ أجهزتك تعمل'), findsNothing);
      // جولة قسم الأجهزة حسمته: يعمل ⇒ يختفي بلا سحب
      server.reply('GET', '/api/v2/agent-alerts/status', 200, _status(downStale: []));
      await t.pump(AgentAlertsScreen.refreshEvery + const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.text('كلّ أجهزتك تعمل'), findsOneWidget);
      expect(find.text('كانت طافية عند آخر فحص'), findsNothing);
      // تحديثٌ فاشل لا يمسح المعروض
      server.reply('GET', '/api/v2/agent-alerts/status', 500, {'success': false});
      await t.pump(AgentAlertsScreen.refreshEvery + const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.text('كلّ أجهزتك تعمل'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('بلا «إدارة الأجهزة» ⇒ المفتاحان معطّلان بسببهما؛ والخادم يفحص عن بُعد ⇒ سطره', (t) async {
      server.reply('GET', '/api/v2/agent-alerts/status', 200, _status(canEdit: false, remote: {'on': true, 'via': 'company', 'healthy': true}));
      server.reply('GET', '/api/v2/agent-alerts/log', 200, _log([]));
      await pumpSim(t, _v, home: (_) => const AgentAlertsScreen());
      await t.pumpAndSettle();
      expect(find.text('كلّ أجهزتك تعمل'), findsOneWidget);
      final sw = t.widget<Switch>(find.byType(Switch).first);
      expect(sw.onChanged, isNull);
      expect(find.textContaining('التعديل للمدير'), findsOneWidget);
      // «كيف تُراقَب» تنطوي (٦ نوفمبر) — تُفتح أوّلاً
      await t.scrollUntilVisible(find.byKey(const ValueKey('aa-how-head')), 300, scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const ValueKey('aa-how-head')));
      await t.pumpAndSettle();
      expect(find.textContaining('والخادم يفحصها عبر الـVPN كلّ دقيقة'), findsOneWidget);
      expect(find.text('ربط VPN'), findsNothing);
      expect(find.textContaining('لا شيء بعد'), findsOneWidget);
      await simDrain(t);
    });

    for (final v in simVariants) {
      testWidgets('بلا فيضٍ ولا أخطاء @${v.tag}', (t) async {
        server.reply('GET', '/api/v2/agent-alerts/status', 200, _status(
          dry: true,
          remote: {'on': false, 'why': 'template'},
          down: [{'id': 3, 'name': 'سكتر الحيّ الشرقيّ الطويل جدّاً جدّاً', 'place': 'برج «النصر الجديد الكبير»', 'since_ms': _ago(const Duration(days: 2, hours: 3))}],
          quiet: [{'id': 6, 'name': 'Sector-AP-Long-Name-01', 'until_ms': DateTime.now().add(const Duration(minutes: 40)).millisecondsSinceEpoch}],
        ));
        server.reply('GET', '/api/v2/agent-alerts/log', 200, _log([
          {'id': 2, 'kind': 'network_down', 'title': '🔴 شبكتك لا تستجيب', 'detail': 'لا نصل 10 من 12 جهازاً منذ 3 د — كهرباء أو إنترنت أو الـVPN عندك؟', 'push': 'failed', 'at_ms': _ago(const Duration(minutes: 5))},
          {'id': 1, 'kind': 'flap', 'title': '🟠 «سكتر 2» يطفي ويشتغل', 'detail': 'طفى 3 مرّات بنصف ساعة — نسكت عنه ساعة ونخبرك إن بقي طافياً', 'push': 'sent', 'at_ms': _ago(const Duration(minutes: 50))},
        ]));
        await pumpSim(t, v, home: (_) => const AgentAlertsScreen());
        await t.pumpAndSettle();
        expect(find.text('جهازٌ واحد طافٍ الآن'), findsOneWidget);
        expect(t.takeException(), isNull);
        await simDrain(t);
      });
    }

    testWidgets('النقر على الإشعار (agent_alert) يفتح «تنبيهات أجهزتي»؛ غيره لا', (t) async {
      server.reply('GET', '/api/v2/agent-alerts/status', 200, _status(available: false));
      final nav = GlobalKey<NavigatorState>();
      await pumpSim(t, _v, navigatorKey: nav, home: (_) => const Scaffold(body: SizedBox()));
      expect(await openAgentAlertPush(nav.currentState!, {'type': 'conn_alert_sent'}), false);
      final f = openAgentAlertPush(nav.currentState!, {'type': 'agent_alert', 'kind': 'down'});
      await t.pumpAndSettle();
      expect(find.byType(AgentAlertsScreen), findsOneWidget);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(await f, true);
      await simDrain(t);
    });
  });
}
