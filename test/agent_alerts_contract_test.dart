import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/agent_alerts_api.dart';
import 'package:rad_mysvcs/screens/network_devices/agent_alerts_screen.dart';

import 'sim_el/sim_harness.dart';

/// عقد التطبيق مع الخادم الحقيقيّ (الفحص الأخير «من الصفر»، ٤ نوفمبر): ردودٌ حقيقيّة التُقطت من server/agentAlerts.js و
/// server/agentVitals.js على MySQL حقيقيّة مؤقّتة بخيارات حوض الإنتاج (BIGINT نصوصاً) وعبر مساراتها الحقيقيّة بـHTTP — لا JSON
/// مكتوبٌ باليد. تشمل: جهازاً طافياً، انقطاع كهرباء البرج، الكهرباء بالفولت لكلّ جهاز، الحدود المعدّلة، والسجلّ بكلّ أنواعه.
/// إن تغيّر شكل ردّ الخادم: أعد التقاطها (سكربت الفحص final_e2e.js ⇒ real_responses.json) لا تعدّلها باليد.
Map<String, dynamic> _real() {
  final raw = jsonDecode(File('test/fixtures/agent_alerts_real_responses.json').readAsStringSync()) as Map<String, dynamic>;
  // الساعة المُحاكاة متقدّمة ساعات ⇒ تُزاح الأزمنة كلّها حتى يكون أحدثها قبل دقيقة («منذ …» واقعيّة)
  var maxMs = 0;
  void scan(Object? o) {
    if (o is Map) {
      o.forEach((k, v) {
        if ('$k'.endsWith('_ms') && v is num && v > maxMs) maxMs = v.toInt();
        scan(v);
      });
    } else if (o is List) {
      o.forEach(scan);
    }
  }

  scan(raw);
  final delta = DateTime.now().millisecondsSinceEpoch - 60000 - maxMs;
  Object? shift(Object? o) {
    if (o is Map) return {for (final e in o.entries) e.key: '${e.key}'.endsWith('_ms') && e.value is num ? (e.value as num).toInt() + delta : shift(e.value)};
    if (o is List) return o.map(shift).toList();
    return o;
  }

  return Map<String, dynamic>.from(shift(raw) as Map);
}

Map<String, dynamic> _data(Object? body) => Map<String, dynamic>.from((body as Map)['data'] as Map);

void main() {
  final real = _real();

  test('النماذج تقرأ ردود الخادم الحقيقيّة كاملةً (أرقامٌ لا نصوص، لا شيء يسقط)', () {
    final st = AgentAlertsStatus.fromJson(_data(real['status_down']));
    expect(st.available, isTrue);
    expect(st.monitored, 10);
    expect(st.down.map((d) => (d.id, d.name)).toList(), [(6, 'جهاز 6')]);
    expect(st.down.single.sinceMs, isNotNull);
    expect(st.lastAppMs, isNotNull);

    final items = (_data(real['log'])['items'] as List);
    final events = items.map(AgentAlertEvent.fromJson).whereType<AgentAlertEvent>().toList();
    expect(events.length, items.length, reason: 'كلّ سطرٍ بالسجلّ يُقرأ');
    expect(events.every((e) => e.atMs != null), isTrue);
    expect(events.map((e) => e.kind).toSet(),
        containsAll(['down', 'up', 'tower_down', 'tower_up', 'flap', 'vital_power', 'vital_power_ok', 'vital_temp', 'vital_signal', 'vital_cpu']));
    expect(events.firstWhere((e) => e.kind == 'vital_cpu').push, 'dry');
    expect(events.where((e) => '${e.title}${e.detail}'.contains(RegExp('[→←]'))), isEmpty, reason: 'لا سهم بين رقمين');

    final v = AgentVitalsStatus.fromJson(_data(real['vitals_alert']));
    expect(v.available, isTrue);
    expect(v.alerts.map((a) => (a.id, a.metric, a.base, a.value)).toList(), [(1, 'volt', 24.0, 19.8), (2, 'volt', 48.2, 39.6)]);
    expect(v.power.map((p) => (p.name, p.base, p.alertBelow)).toList(), [('جهاز 1', 24.0, 20.4), ('جهاز 2', 48.2, 41.0), ('جهاز 5', 12.1, 10.3)]);
    expect(v.powerLearning, 0);

    final m = AgentVitalsStatus.fromJson(_data(real['vitals_mixed']));
    expect(m.settings.tempMax, 55);
    expect(m.settings.voltDropPct, 10);
    expect(m.alerts.map((a) => (a.id, a.metric)).toList(), [(1, 'temp')]);
    expect(m.power.first.alertBelow, 21.6, reason: 'الحدّ بالفولت يتبع نسبة المالك (10٪)');
  });

  group('الشاشة بردود الخادم الحقيقيّة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      AgentAlertsApi.forget();
      server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin@m'});
      server.reply('GET', '/api/v2/agent-alerts/status', 200, real['status_down']);
      server.reply('GET', '/api/v2/agent-alerts/log', 200, real['log']);
    });

    for (final v in [const SimVariant(390, dark: false), const SimVariant(320, dark: true)]) {
      testWidgets('طافٍ + انقطاع كهرباء البرج + الكهرباء بالفولت + السجلّ @${v.tag}', (t) async {
        server.reply('GET', '/api/v2/agent-alerts/vitals', 200, real['vitals_alert']);
        await pumpSim(t, v, home: (_) => const AgentAlertsScreen());
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.textContaining('جهاز 6'), findsWidgets);
        expect(find.text('القراءات الحسّاسة'), findsOneWidget);
        expect(find.text('الكهرباء · جهاز 1'), findsOneWidget);
        expect(find.text('19.8V'), findsOneWidget);
        expect(find.text('طبيعيّه \u206624.0V\u2069'), findsOneWidget);
        expect(find.textContaining('يُنبَّه إذا نزلت 15٪ عن طبيعيّ الجهاز'), findsOneWidget);
        expect(find.text('20.4V'), findsOneWidget);
        expect(find.textContaining('←'), findsNothing);
        await t.scrollUntilVisible(find.textContaining('يطفي ويشتغل'), 300, scrollable: find.byType(Scrollable).first);
        expect(t.takeException(), isNull);
        await simDrain(t);
      });
    }

    testWidgets('الحدود المعدّلة (الحرارة 55°، الكهرباء 10٪) تُقرأ كما حفظها الخادم، ومثال الفولت بأجهزته', (t) async {
      server.reply('GET', '/api/v2/agent-alerts/vitals', 200, real['vitals_mixed']);
      await pumpSim(t, const SimVariant(390, dark: false), home: (_) => const AgentAlertsScreen());
      await t.pumpAndSettle();
      expect(find.text('56°'), findsOneWidget);
      await t.tap(find.text('الحدود'));
      await t.pumpAndSettle();
      expect(find.text('55°'), findsOneWidget);
      expect(find.text('10%'), findsOneWidget);
      expect(find.textContaining('«جهاز 1» طبيعيّه\u00A0\u206624.0V\u2069، التنبيه\u00A0تحت\u00A0\u206621.6V'), findsOneWidget);
      await simDrain(t);
    });
  });
}
