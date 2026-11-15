// محاكي «سرعة الرئيسيّة ودقّتها» (١٦ نوفمبر ٢٠٢٦ — المالك: «سوي محاكاة بحيث تضمن دقه المعلومات والسرعه») — المقارنة والنتائج.
// المحرّك في dashboard_sim.dart. يعمل على أيّ فرعٍ (قبل/بعد) بلا تغيير:
//   SIM_OUT=/مسار/ملف.jsonl SIM_SEEDS=300 flutter test test/sim/dashboard_load_sim_test.dart
// والمقارنة: python3 ~/release_work/dash_timing_1116/sim/compare.py <قبل.jsonl> <بعد.jsonl>
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'dashboard_sim.dart';

void main() {
  final out = Platform.environment['SIM_OUT'];
  final seeds = int.tryParse(Platform.environment['SIM_SEEDS'] ?? '') ?? 6;
  final runs = <Run>[];
  final lat = jsonDecode(File('test/sim/latency_2026-11-15.json').readAsStringSync()) as Map<String, dynamic>;
  final qProbe = latencyQuantiles(lat, 'probe_primary'), qList = latencyQuantiles(lat, 'list_readers'), qPkg = latencyQuantiles(lat, 'packages');

  setUpAll(() async => visualSetUpAll());
  tearDownAll(() {
    if (out == null) return;
    final f = File(out)..createSync(recursive: true);
    f.writeAsStringSync('${runs.map((r) => jsonEncode(r.toJson())).join('\n')}\n');
  });

  void expectAccurate(Run r, {bool big = false}) {
    final v = violations(r, big: big);
    expect(v, isEmpty, reason: '${r.profile}#${r.seed}: ${v.join(' · ')}');
    if (!big) expect(r.checks['stats'], isNotNull, reason: 'لم تظهر أرقام المشتركين');
  }

  // ── مُعايَرة + سيناريوهات ثابتة ──
  for (final p in const [
    Profile('warm_reopen', warm), // فتح التطبيق والساس دافئ (= cold3 الحيّ)
    Profile('cold_reopen', cold), // أوّل فتحٍ صباحاً والساس بارد — الحكم محفوظ من أمس
    Profile('cold_first_open', cold, storedSmall: false), // أوّل فتحٍ على الجهاز (أو بعد ٧ أيّام) والساس بارد
    Profile('warm_first_open', warm, storedSmall: false),
  ]) {
    testWidgets('سيناريو ${p.name}', (t) async {
      final r = await simulate(t, p, 0);
      runs.add(r);
      expectAccurate(r);
    });
  }

  testWidgets('حسابٌ كبير (٨٩ ألفاً): لا قائمة كاملة أبداً، بحكمٍ محفوظ أو بلا', (t) async {
    for (final stored in [false, true]) {
      final r = await simulate(t, Profile('big_${stored ? 'stored' : 'nostore'}', warm, storedSmall: stored, bigTotal: 89177), 0);
      runs.add(r);
      expectAccurate(r, big: true);
    }
  });

  // ── توزيع الوكلاء الحقيقيّ (nginx ١٥ نوفمبر): عيّناتٌ مستقلّة لكلّ نداء، ومتلازمة (ساسٌ بطيء للنداءات كلّها) ──
  for (final coupled in [false, true]) {
    testWidgets('توزيع حقيقيّ ${coupled ? 'متلازم' : 'مستقلّ'} × $seeds', (t) async {
      final rnd = math.Random(coupled ? 777 : 1116);
      final bad = <String>[];
      for (var i = 0; i < seeds; i++) {
        final u = rnd.nextDouble();
        double draw(List<double> q) => quantileAt(q, coupled ? u : rnd.nextDouble()) + 0.15; // +الإنترنت/كلاودفلير فوق زمن nginx
        final sas = Sas(draw(qProbe), draw(qList), draw(qPkg));
        final r = await simulate(t, Profile('mix_${coupled ? 'co' : 'ind'}', sas), i);
        runs.add(r);
        for (final x in violations(r)) {
          bad.add('#$i $x');
        }
      }
      expect(bad, isEmpty, reason: 'مخالفات دقّة: ${bad.take(10).join(' | ')}');
    }, timeout: const Timeout(Duration(minutes: 30)));
  }
}
