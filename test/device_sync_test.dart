import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/bdcom_epon.dart';
import 'package:rad_mysvcs/api/olt_profile.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/services/device_stats_cache.dart';
import 'package:rad_mysvcs/services/fiber/fiber_monitor.dart';

/// المالك ٢٨ أكتوبر: «تحديث حاله كل من وضع الابراج وضع الالياف… تتحدث مع تزامن تحديث الاجهزه لان بوضع البرج شفت جهاز يكول
/// عليه ٥ متصلين ويعرض ٣». المخزن ينبّه بكلّ قراءةٍ جديدة، وشاشات الألياف تكتب للأولت خانات بطاقة الجدار نفسها.
VsolOnu onu(int id, {bool online = true}) => VsolOnu(ifIndex: id, slot: 0, ponPort: 1, onuId: id, online: online);

void main() {
  test('المخزن: كلّ قراءةٍ معروضة تنبّه بمعرّف جهازها', () {
    final cache = DeviceStatsCache.instance;
    final got = <int>[];
    void l() => got.add(cache.updated.value.id);
    cache.updated.addListener(l);
    addTearDown(() => cache.updated.removeListener(l));
    final seq = cache.updated.value.seq;
    cache.putVitals(9001, const [], null);
    cache.putVitals(9002, const [], null);
    cache.putVitals(9001, const [], null);
    expect(got, [9001, 9002, 9001]);
    expect(cache.updated.value.seq, seq + 3, reason: 'الجهاز نفسه مرّتين ⇒ تنبيهان');
  });

  group('جسر الألياف ⇐ بطاقة الجدار', () {
    setUp(() => FiberMonitor.onLiveStats = null);
    tearDown(() => FiberMonitor.onLiveStats = null);

    test('VSOL: قراءة الألياف الحيّة تُكتب بخانات الجدار نفسها (المشتركون/المنافذ/التشغيل)', () {
      bridgeFiberVitals();
      expect(FiberMonitor.onLiveStats, isNotNull);
      final s = VsolOltStats(
        profile: const OltProfile(vendor: OltVendor.vsol, oltLikely: true),
        uptime: const Duration(days: 3),
        onus: [onu(1), onu(2), onu(3, online: false)],
      );
      FiberMonitor.onLiveStats!(9101, s);
      final v = DeviceStatsCache.instance.vitalsOf(9101, const Duration(minutes: 1));
      expect(v, isNotNull);
      final first = v!.vitals.first as Vital;
      expect([first.label, first.value, first.unit], ['المشتركون', '2', '/3']);
      expect(oltProbeResult(s).vitals.length, v.vitals.length, reason: 'الحساب نفسه');
    });

    test('BDCOM بلا معالجٍ في قراءة الألياف: يُستعار من لقطةٍ حديثة، وإلّا لا كتابة (لا تُمحى خانة المعالج)', () {
      bridgeFiberVitals();
      const bdcom = OltProfile(vendor: OltVendor.bdcom, oltLikely: true);
      final s = VsolOltStats(profile: bdcom, onus: [onu(1)]);
      FiberMonitor.onLiveStats!(9102, s);
      expect(DeviceStatsCache.instance.vitalsOf(9102, const Duration(minutes: 1)), isNull, reason: 'لا لقطة ⇒ لا كتابة');
      DeviceStatsCache.instance.putRaw(9102, VsolOltStats(profile: bdcom, onus: [onu(1)], chassis: const BdcomChassis(cpuPct: 17)));
      FiberMonitor.onLiveStats!(9102, s);
      final v = DeviceStatsCache.instance.vitalsOf(9102, const Duration(minutes: 1));
      expect(v, isNotNull);
      expect(v!.vitals.map((x) => (x as Vital).label), contains('المعالج'));
      expect(v.vitals.whereType<Vital>().firstWhere((x) => x.label == 'المعالج').value, '17');
    });
  });
}
