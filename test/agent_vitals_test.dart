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

Map<String, dynamic> _vitals({bool available = true, bool canEdit = true, List<Map<String, dynamic>> alerts = const [], int watched = 20, bool enabled = true,
        List<Map<String, dynamic>> power = const [], int learning = 0}) => {
      'success': true,
      'data': available
          ? {
              'available': true, 'dry_run': false, 'can_use': true, 'can_edit': canEdit, 'watched': watched, 'alerts': alerts,
              'power': power, 'power_learning': learning,
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
    expect(s2.toJson(),
        {'enabled': false, 'volt_on': true, 'cpu_max': 95, 'temp_max': 80, 'volt_drop_pct': 15, 'signal_drop_db': 8, 'signal_min': -80, 'ccq_min': 50});
    // مفتاح الكهرباء (٦ نوفمبر): الغائب مفعّل (خادمٌ أقدم)، والمطفأ يُقرأ ويُرسل
    expect(AgentVitalSettings.fromJson(const {'enabled': true}).voltOn, isTrue);
    expect(AgentVitalSettings.fromJson(const {'volt_on': false}).voltOn, isFalse);
    expect(s2.copyWith(voltOn: false).toJson()['volt_on'], isFalse);
    expect(vitalValueText('volt', 19.94), '19.9V');
    expect(vitalValueText('signal', -70.4), '-70 dBm');
    final pw = AgentVitalsStatus.fromJson(Map<String, dynamic>.from(_vitals(power: [
      {'id': 1, 'name': 'راوتر البرج', 'base': 24.0, 'alert_below': 20.4, 'value': 23.9, 'state': 'ok'},
      {'id': 2, 'name': 'سويج', 'base': 48.2, 'alert_below': 41.0, 'state': 'alert'},
    ], learning: 2)['data'] as Map));
    expect(pw.power.map((p) => (p.name, p.base, p.alertBelow, p.alert)).toList().toString(), '[(راوتر البرج, 24.0, 20.4, false), (سويج, 48.2, 41.0, true)]');
    expect(pw.powerLearning, 2);
  });

  test('النسبة بالفولت: بأوّل أجهزته إن عُرفت، وإلّا بمثال 24V؛ الاسم الطويل يُختصر', () {
    String plain(String s) => s.replaceAll(RegExp('[\u2066-\u2069]'), '').replaceAll('\u00A0', ' ');
    expect(plain(voltDropHint(15, const [])), 'نزولها عن طبيعيّ الجهاز\nمثلاً: جهازٌ طبيعيّه 24.0V، التنبيه تحت 20.4V');
    const p = [AgentVitalPower(id: 1, name: 'راوتر البرج', base: 24.0, alertBelow: 20.4), AgentVitalPower(id: 2, name: 'سويج', base: 48.0, alertBelow: 40.8)];
    expect(plain(voltDropHint(20, p)), 'نزولها عن طبيعيّ الجهاز\nمثلاً: «راوتر البرج» طبيعيّه 24.0V، التنبيه تحت 19.2V');
    const long = [AgentVitalPower(id: 3, name: 'سويج البرج الرئيسيّ الطويل جدّاً', base: 48.2, alertBelow: 41.0)];
    expect(plain(voltDropHint(15, long)), 'نزولها عن طبيعيّ الجهاز\nمثلاً: «سويج البرج…» طبيعيّه 48.2V، التنبيه تحت 41.0V');
  });

  test('القراءة: ما يقيسه الجهاز فعلاً (لا صفر لما لم يُقرأ)', () {
    expect(VitalsReporter.readingOf(1, const DeviceGlance(cpu: 12, temp: 45, voltage: 24.06, signal: -61, ccq: 88)),
        {'id': 1, 'cpu': 12, 'temp': 45, 'volt': 24.1, 'signal': -61, 'ccq': 88});
    expect(VitalsReporter.readingOf(2, const DeviceGlance(voltage: 0, signal: 0, ccq: 0)), isNull);
    expect(VitalsReporter.readingOf(3, const DeviceGlance()), isNull);
  });

  test('الإشارة لوصلةٍ لا لنقطة وصول: سكتر بوضع AP لا يرسل «-96»؛ بمحطّةٍ واحدة ⇒ إشارتها؛ محطّاته لم تُقرأ ⇒ لا مفتاح', () {
    const p = PeerLink(name: 'a', signal: -63);
    const q = PeerLink(name: 'b', signal: -70);
    // الحال الحيّة (٤ نوفمبر، سكتر يوبيكويتي): وضع AP، محطّاتٌ مقروءة، و«إشارة» الجهاز -96 ⇒ null صريح (لا تنطبق)
    expect(VitalsReporter.readingOf(1, const DeviceGlance(cpu: 5, signal: -96, isAp: true, peersKnown: true), peers: const [p, q]),
        {'id': 1, 'cpu': 5, 'signal': null});
    expect(VitalsReporter.readingOf(1, const DeviceGlance(signal: -96, isAp: true, peersKnown: true)), {'id': 1, 'signal': null},
        reason: 'بلا محطّات أيضاً — والخريطة لا تُهمل: null الصريح يغلق إنذاراً قديماً');
    // نقطة وصولٍ بمحطّةٍ واحدة = وصلة PtP ⇒ إشارة المحطّة (لا إشارة الجهاز)
    expect(VitalsReporter.readingOf(2, const DeviceGlance(signal: -96, ccq: 91, isAp: true, peersKnown: true), peers: const [p]),
        {'id': 2, 'signal': -63, 'ccq': 91});
    // قراءةٌ خفيفة (محطّاتها لم تُقرأ) ⇒ لا مفتاح إشارة أصلاً
    expect(VitalsReporter.readingOf(3, const DeviceGlance(cpu: 7, signal: -60, isAp: true)), {'id': 3, 'cpu': 7});
    // المحطّة/الوصلة ⇒ إشارتها هي
    expect(VitalsReporter.readingOf(4, const DeviceGlance(signal: -58, isAp: false, peersKnown: true), peers: const [p, q]),
        {'id': 4, 'signal': -58});
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
      // سكترٌ بوضع AP بمحطّتين: إشارته «-96» لا تُرسل — null صريحٌ يصل الخادم كما هو (يغلق إنذاراً قديماً)
      VitalsReporter.instance.record(_dev(2), const DeviceGlance(voltage: 23.9, signal: -96, isAp: true, peersKnown: true),
          peers: const [PeerLink(name: 'x', signal: -60), PeerLink(name: 'y', signal: -70)]);
      expect(VitalsReporter.instance.pending.length, 2);
      server.reply('POST', '/api/v2/agent-alerts/vitals', 200, {'success': true, 'data': {'active': true, 'accepted': 3}});
      await t.runAsync(() => VitalsReporter.instance.flush());
      final body = server.bodies('POST', '/api/v2/agent-alerts/vitals').single;
      expect(body['readings'], [
        {'id': 1, 'cpu': 97, 'temp': 81},
        {'id': 2, 'volt': 23.9, 'signal': null},
      ]);
      expect((body['readings'] as List)[1].containsKey('signal'), isTrue, reason: 'null بالجسم لا مفتاحٌ محذوف');
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

    testWidgets('القسم: الإنذارات بقيمها وتحتها طبيعيّ الجهاز (19.9V · طبيعيّه 24.0V — لا سهم) والسجلّ بأيقوناته؛ «الحدود» تحفظ', (t) async {
      server.reply('GET', '/api/v2/agent-alerts/vitals', 200, _vitals(alerts: [
        {'id': 3, 'name': 'راوتر البرج', 'metric': 'volt', 'place': 'برج «النصر»', 'value': 19.9, 'base': 24.0, 'since_ms': _ago(const Duration(minutes: 6))},
        {'id': 5, 'name': 'سكتر 2', 'metric': 'temp', 'value': 82, 'since_ms': _ago(const Duration(minutes: 12))},
      ]));
      server.reply('PUT', '/api/v2/agent-alerts/vitals/settings', 200, {'success': true, 'data': {}});
      await pumpSim(t, _v, home: (_) => const AgentAlertsScreen());
      await t.pumpAndSettle();
      expect(find.text('القراءات الحسّاسة'), findsOneWidget);
      expect(find.text('الكهرباء · راوتر البرج'), findsOneWidget);
      expect(find.text('19.9V'), findsOneWidget);
      expect(find.text('طبيعيّه \u206624.0V\u2069'), findsOneWidget);
      expect(find.textContaining('←'), findsNothing, reason: 'السهم بين رقمين يُقرأ بالعكس');
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

    testWidgets('٦ نوفمبر — «يكون توكل»: مفتاحا القراءات الحسّاسة والكهرباء ظاهران؛ إطفاء الكهرباء يرسل volt_on:false ويطوي التنبيه', (t) async {
      server.reply('GET', '/api/v2/agent-alerts/vitals', 200, _vitals(power: [
        {'id': 1, 'name': 'راوتر البرج', 'base': 24.0, 'alert_below': 20.4, 'value': 23.9, 'state': 'ok'},
      ]));
      server.reply('PUT', '/api/v2/agent-alerts/vitals/settings', 200, {'success': true, 'data': {}});
      await pumpSim(t, _v, home: (_) => const AgentAlertsScreen());
      await t.pumpAndSettle();
      final vOn = find.byKey(const ValueKey('aa-switch-v_enabled'));
      final volt = find.byKey(const ValueKey('aa-switch-v_volt'));
      await t.scrollUntilVisible(volt, 300, scrollable: find.byType(Scrollable).first);
      expect(t.widget<Switch>(vOn).value, isTrue);
      expect(t.widget<Switch>(volt).value, isTrue);
      await t.tap(volt);
      await t.pumpAndSettle();
      final body = server.bodies('PUT', '/api/v2/agent-alerts/vitals/settings').single;
      expect(body['volt_on'], isFalse);
      expect(body['enabled'], isTrue, reason: 'الباقي كما هو');
    });
    testWidgets('الكهرباء بالفولت: لكلّ جهاز طبيعيّه وحدّ تنبيهه، ومن يتعلّم؛ والحدود تقولها فولتاً وتتغيّر مع ±', (t) async {
      server.reply('GET', '/api/v2/agent-alerts/vitals', 200, _vitals(power: [
        {'id': 1, 'name': 'راوتر البرج', 'base': 24.0, 'alert_below': 20.4, 'value': 23.9, 'state': 'ok'},
      ], learning: 3));
      await pumpSim(t, _v, home: (_) => const AgentAlertsScreen());
      await t.pumpAndSettle();
      expect(find.textContaining('1 جهاز · كلّها طبيعيّة · التنبيه إذا نزلت 15٪'), findsOneWidget);
      // الكهرباء تنطوي (٦ نوفمبر — «قسم الكهرباء… يكون توكل»): سطرٌ مختصر، والتفاصيل بالضغط
      await t.scrollUntilVisible(find.byKey(const ValueKey('aa-power-head')), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('20.4V'), findsNothing);
      await t.tap(find.byKey(const ValueKey('aa-power-head')));
      await t.pumpAndSettle();
      expect(find.text('راوتر البرج'), findsOneWidget);
      expect(find.text('24.0V'), findsOneWidget);
      expect(find.text('20.4V'), findsOneWidget);
      expect(find.textContaining('3 أجهزة تتعلّم فولتيّتها الطبيعيّة'), findsOneWidget);
      await t.tap(find.text('الحدود'));
      await t.pumpAndSettle();
      expect(find.textContaining('تحت\u00A0\u206620.4V'), findsOneWidget);
      await t.tap(find.byTooltip('أكثر').at(2)); // الكهرباء 15 ⇒ 20
      await t.pump();
      expect(find.textContaining('تحت\u00A0\u206619.2V'), findsOneWidget);
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
          {'id': 4, 'name': 'سويج البرج', 'metric': 'volt', 'value': 39.9, 'base': 48.2, 'since_ms': _ago(const Duration(minutes: 2))},
          {'id': 5, 'name': 'سكتر 2', 'metric': 'cpu', 'value': 97, 'since_ms': _ago(const Duration(minutes: 12))},
        ], power: [
          {'id': 4, 'name': 'سويج البرج الرئيسيّ الطويل جدّاً جدّاً', 'base': 48.2, 'alert_below': 41.0, 'value': 39.9, 'state': 'alert'},
          {'id': 6, 'name': 'راوتر', 'base': 12.1, 'alert_below': 10.3, 'value': 12.0, 'state': 'ok'},
        ], learning: 1));
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
