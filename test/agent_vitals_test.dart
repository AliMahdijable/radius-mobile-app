import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/agent_alerts_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/agent_alerts_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/services/vitals_reporter.dart';

import 'sim_el/sim_harness.dart';

/// «القراءات الحسّاسة» (٤ نوفمبر — المرحلة ٢، الخادم server/agentVitals.js): ما يقرؤه التطبيق يُرفع، والقسم بالشاشة وحدوده.
const _v = SimVariant(390, dark: false);

int _ago(Duration d) => DateTime.now().subtract(d).millisecondsSinceEpoch;

Map<String, dynamic> _alerts() => {
      'success': true,
      'data': {
        'available': true, 'dry_run': false, 'enabled': true, 'notify_up': true, 'can_use': true, 'can_edit': true,
        'devices': 14, 'monitored': 14, 'down': <Object>[], 'quiet': <Object>[], 'network_down': false, 'last_app_ms': _ago(const Duration(minutes: 1)),
      },
    };

Map<String, dynamic> _vitals({bool available = true, bool canEdit = true, List<Map<String, dynamic>> alerts = const [], int watched = 20, bool enabled = true}) => {
      'success': true,
      'data': available
          ? {
              'available': true, 'dry_run': false, 'can_use': true, 'can_edit': canEdit, 'watched': watched, 'alerts': alerts,
              'settings': {'enabled': enabled, 'cpu_max': 90, 'temp_max': 80, 'volt_drop_pct': 15, 'signal_drop_db': 8, 'signal_min': -80, 'ccq_min': 50},
            }
          : {'available': false},
    };

NetworkDevice _dev(int id) => NetworkDevice.fromJson({'id': id, 'admin_id': '2', 'name': 'd$id', 'type': 'router', 'brand': 'mikrotik', 'ip': '10.0.0.$id'});

void main() {
  test('النماذج: الحدود والإنذارات ونسخ الإعداد', () {
    final st = AgentVitalsStatus.fromJson(Map<String, dynamic>.from(_vitals(alerts: [
      {'id': 3, 'name': 'راوتر البرج', 'metric': 'volt', 'place': 'برج «النصر»', 'value': 19.9, 'base': 24.0, 'since_ms': 5},
    ])['data'] as Map));
    expect(st.available, true);
    expect(st.settings.cpuMax, 90);
    expect(st.settings.signalMin, -80);
    expect(st.alerts.single.metric, 'volt');
    expect(st.alerts.single.base, 24.0);
    final s2 = st.settings.copyWith(cpuMax: 95, enabled: false);
    expect(s2.toJson(), {'enabled': false, 'cpu_max': 95, 'temp_max': 80, 'volt_drop_pct': 15, 'signal_drop_db': 8, 'signal_min': -80, 'ccq_min': 50});
    expect(vitalValueText('volt', 19.94), '19.9V');
    expect(vitalValueText('signal', -70.4), '-70 dBm');
  });

  test('القراءة: ما يقيسه الجهاز فعلاً (لا صفر لما لم يُقرأ)', () {
    expect(VitalsReporter.readingOf(1, const DeviceGlance(cpu: 12, temp: 45, voltage: 24.06, signal: -61, ccq: 88)),
        {'id': 1, 'cpu': 12, 'temp': 45, 'volt': 24.1, 'signal': -61, 'ccq': 88});
    expect(VitalsReporter.readingOf(2, const DeviceGlance(voltage: 0, signal: 0, ccq: 0)), isNull);
    expect(VitalsReporter.readingOf(3, const DeviceGlance()), isNull);
  });

  group('الرفع', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      AgentAlertsApi.forget();
      VitalsReporter.instance.reset();
      server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin@m'});
    });

    testWidgets('غير مفتوحةٍ للشركة ⇒ لا شيء يُجمع؛ مفتوحة ⇒ آخر قراءةٍ لكلّ جهاز دفعةً واحدة؛ active:false يوقفه', (t) async {
      VitalsReporter.instance.record(_dev(1), const DeviceGlance(cpu: 50));
      expect(VitalsReporter.instance.pending, isEmpty, reason: 'لم تُقرأ حالها بعد');
      server.reply('GET', '/api/v2/agent-alerts/vitals', 200, _vitals());
      await t.runAsync(() => AgentAlertsApi.vitalsStatus());
      VitalsReporter.instance.record(_dev(1), const DeviceGlance(cpu: 50));
      VitalsReporter.instance.record(_dev(1), const DeviceGlance(cpu: 97, temp: 81));
      VitalsReporter.instance.record(_dev(2), const DeviceGlance(voltage: 23.9));
      expect(VitalsReporter.instance.pending.length, 2);
      server.reply('POST', '/api/v2/agent-alerts/vitals', 200, {'success': true, 'data': {'active': true, 'accepted': 3}});
      await t.runAsync(() => VitalsReporter.instance.flush());
      final body = server.bodies('POST', '/api/v2/agent-alerts/vitals').single;
      expect(body['readings'], [
        {'id': 1, 'cpu': 97, 'temp': 81},
        {'id': 2, 'volt': 23.9},
      ]);
      expect(VitalsReporter.instance.pending, isEmpty);
      server.reply('POST', '/api/v2/agent-alerts/vitals', 200, {'success': true, 'data': {'active': false}});
      VitalsReporter.instance.record(_dev(3), const DeviceGlance(cpu: 10));
      await t.runAsync(() => VitalsReporter.instance.flush());
      VitalsReporter.instance.record(_dev(4), const DeviceGlance(cpu: 10));
      expect(VitalsReporter.instance.pending, isEmpty, reason: 'أُطفئت بالخادم ⇒ يتوقّف ١٠ د');
      VitalsReporter.instance.reset();
      await simDrain(t);
    });
  });

  group('الشاشة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      AgentAlertsApi.forget();
      server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin@m'});
      server.reply('GET', '/api/v2/agent-alerts/status', 200, _alerts());
      server.reply('GET', '/api/v2/agent-alerts/log', 200, {'success': true, 'data': {'available': true, 'items': [
        {'id': 4, 'kind': 'vital_power', 'title': '🔋 الكهرباء — برج «النصر»', 'detail': '3 أجهزة نزلت فولتيّتها', 'push': 'sent', 'at_ms': _ago(const Duration(minutes: 4))},
        {'id': 3, 'kind': 'vital_temp', 'title': '🌡️ حرارة «سكتر 2» 82°', 'detail': 'الحدّ 80°', 'push': 'quiet', 'at_ms': _ago(const Duration(minutes: 40))},
      ]}});
    });

    testWidgets('القسم: الإنذارات بقيمها ومعدّلها (الكهرباء 24.0V ← 19.9V) والسجلّ بأيقوناته؛ «الحدود» تحفظ', (t) async {
      server.reply('GET', '/api/v2/agent-alerts/vitals', 200, _vitals(alerts: [
        {'id': 3, 'name': 'راوتر البرج', 'metric': 'volt', 'place': 'برج «النصر»', 'value': 19.9, 'base': 24.0, 'since_ms': _ago(const Duration(minutes: 6))},
        {'id': 5, 'name': 'سكتر 2', 'metric': 'temp', 'value': 82, 'since_ms': _ago(const Duration(minutes: 12))},
      ]));
      server.reply('PUT', '/api/v2/agent-alerts/vitals/settings', 200, {'success': true, 'data': {}});
      await pumpSim(t, _v, home: (_) => const AgentAlertsScreen());
      await t.pumpAndSettle();
      expect(find.text('القراءات الحسّاسة'), findsOneWidget);
      expect(find.text('الكهرباء · راوتر البرج'), findsOneWidget);
      expect(find.text('24.0V ← 19.9V'), findsOneWidget);
      expect(find.text('الحرارة · سكتر 2'), findsOneWidget);
      expect(find.text('82°'), findsOneWidget);
      await t.tap(find.text('الحدود'));
      await t.pumpAndSettle();
      expect(find.text('حدود القراءات الحسّاسة'), findsOneWidget);
      await t.tap(find.byTooltip('أكثر').first); // المعالج 90 ⇒ 95
      await t.pump();
      expect(find.text('95%'), findsOneWidget);
      await t.tap(find.text('حفظ'));
      await t.pumpAndSettle();
      expect(server.bodies('PUT', '/api/v2/agent-alerts/vitals/settings').single['cpu_max'], 95);
      await t.scrollUntilVisible(find.text('الكهرباء — برج «النصر»'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('الكهرباء — برج «النصر»'), findsOneWidget, reason: 'العنوان بلا رمزه');
      await simDrain(t);
    });

    testWidgets('لا إنذار ⇒ «كلّها طبيعيّة»؛ بلا قراءات ⇒ «لم تصل قراءات بعد»؛ بلا «إدارة الأجهزة» لا «الحدود»؛ مطفأة للحساب ⇒ لا قسم', (t) async {
      server.reply('GET', '/api/v2/agent-alerts/vitals', 200, _vitals(canEdit: false));
      await pumpSim(t, _v, home: (_) => const AgentAlertsScreen());
      await t.pumpAndSettle();
      expect(find.text('كلّها طبيعيّة'), findsOneWidget);
      expect(find.text('الحدود'), findsNothing);
      await simDrain(t);
    });

    testWidgets('بلا قراءات بعد', (t) async {
      server.reply('GET', '/api/v2/agent-alerts/vitals', 200, _vitals(watched: 0));
      await pumpSim(t, _v, home: (_) => const AgentAlertsScreen());
      await t.pumpAndSettle();
      expect(find.text('لم تصل قراءات بعد'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('مطفأة للحساب ⇒ لا قسم', (t) async {
      server.reply('GET', '/api/v2/agent-alerts/vitals', 200, _vitals(available: false));
      await pumpSim(t, _v, home: (_) => const AgentAlertsScreen());
      await t.pumpAndSettle();
      expect(find.text('القراءات الحسّاسة'), findsNothing);
      await simDrain(t);
    });

    for (final v in simVariants) {
      testWidgets('القسم والحدود بلا فيضٍ @${v.tag}', (t) async {
        server.reply('GET', '/api/v2/agent-alerts/vitals', 200, _vitals(alerts: [
          {'id': 3, 'name': 'راوتر البرج الرئيسيّ الطويل جدّاً', 'metric': 'signal', 'place': 'برج «النصر الجديد»', 'value': -71, 'base': -58, 'since_ms': _ago(const Duration(hours: 3))},
          {'id': 5, 'name': 'سكتر 2', 'metric': 'cpu', 'value': 97, 'since_ms': _ago(const Duration(minutes: 12))},
        ]));
        await pumpSim(t, v, home: (_) => const AgentAlertsScreen());
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.tap(find.text('الحدود'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await simDrain(t);
      });
    }
  });
}
