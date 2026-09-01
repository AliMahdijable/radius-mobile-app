import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/services/deep_probe_scheduler.dart';

/// المرحلة ٢ — شعاع الجلب العميق.
void main() {
  final sched = DeepProbeScheduler.instance;

  NetworkDevice dev({
    String brand = 'ubnt',
    String status = 'online',
    bool creds = true,
  }) =>
      NetworkDevice(
        id: 1,
        adminId: '2',
        name: 'برج',
        type: 'link',
        brand: brand,
        ip: '10.0.0.1',
        port: 80,
        hasCredentials: creds,
        lastStatus: status,
        createdAt: DateTime(2026),
      );

  group('المجدول', () {
    setUp(sched.resetForTest);

    test('لا يتجاوز السقف مهما أُدرج', () async {
      var peak = 0;
      var running = 0;
      final done = <Future<void>>[];
      final gate = Completer<void>();

      for (var i = 0; i < 40; i++) {
        final c = Completer<void>();
        done.add(c.future);
        sched.submit(Object(), () async {
          running++;
          if (running > peak) peak = running;
          await gate.future;
          running--;
          c.complete();
        });
      }
      await Future<void>.delayed(Duration.zero);
      expect(peak, lessThanOrEqualTo(DeepProbeScheduler.maxConcurrent),
          reason: 'أربعون جلسة SSH معاً = تجميد الواجهة');
      expect(peak, DeepProbeScheduler.maxConcurrent, reason: 'ولا نُهدر خانات');
      gate.complete();
      await Future.wait(done);
      expect(sched.activeCount, 0);
    });

    test('الإلغاء يمنع البدء لا يوقف الجاري', () async {
      final gate = Completer<void>();
      final started = <int>[];
      // نملأ السقف بمهامّ معلّقة
      for (var i = 0; i < DeepProbeScheduler.maxConcurrent; i++) {
        sched.submit(Object(), () async {
          started.add(-1);
          await gate.future;
        });
      }
      final ghost = Object();
      sched.submit(ghost, () async => started.add(99));
      await Future<void>.delayed(Duration.zero);
      expect(sched.pendingCount, 1, reason: 'المنتظِر لم يبدأ بعد');

      sched.cancel(ghost);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(started.contains(99), isFalse,
          reason: 'بطاقة غادرت الشاشة يجب ألّا تفتح جلسة');
    });

    test('مهمّة ساقطة تُحرّر خانتها', () async {
      // بلا هذا يمتلئ السقف بجلسات ميّتة ويتوقّف الجدار كلّه.
      for (var i = 0; i < DeepProbeScheduler.maxConcurrent; i++) {
        sched.submit(Object(), () async => throw StateError('فشل'));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sched.activeCount, 0);
      var ran = false;
      sched.submit(Object(), () async => ran = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ran, isTrue, reason: 'السقف انسدّ بجلسات ساقطة');
    });

    test('إعادة الإدراج بنفس المالك لا تُكدّس', () async {
      final gate = Completer<void>();
      for (var i = 0; i < DeepProbeScheduler.maxConcurrent; i++) {
        sched.submit(Object(), () async => gate.future);
      }
      final owner = Object();
      sched.submit(owner, () async {});
      sched.submit(owner, () async {});
      sched.submit(owner, () async {});
      await Future<void>.delayed(Duration.zero);
      expect(sched.pendingCount, 1,
          reason: 'نبضة كلّ ١٥ث لنفس البطاقة تُكدّس ثلاثة طلبات للجهاز نفسه');
      gate.complete();
    });
  });

  group('الامتناع الصريح', () {
    test('المعطّل لا تُفتح له جلسة', () {
      expect(DeviceVitals.skipReason(dev(status: 'offline')), 'معطّل',
          reason: 'قراءة معالجِ جهازٍ لا يردّ تحجز خانةً وتنتظر مهلتها');
    });

    test('بلا بيانات دخول', () {
      expect(DeviceVitals.skipReason(dev(creds: false)), 'بلا بيانات دخول');
    });

    test('علامة غير مدعومة', () {
      expect(DeviceVitals.skipReason(dev(brand: 'cisco')),
          'لا مقاييس لهذه العلامة');
      expect(DeviceVitals.skipReason(dev(brand: 'other')), isNotNull);
    });

    test('الصالح لا يُمتنع عنه', () {
      for (final b in ['ubnt', 'mikrotik', 'mimosa', 'UBNT']) {
        expect(DeviceVitals.skipReason(dev(brand: b)), isNull, reason: b);
      }
    });
  });

  group('نافذة الصلاحيّة', () {
    test('الطازج لا يُعاد جلبه', () {
      final fresh = VitalsState(vitals: const [], at: DateTime.now());
      expect(fresh.isFresh, isTrue);
    });

    test('القديم يُعاد جلبه', () {
      final old = VitalsState(
        vitals: const [],
        at: DateTime.now().subtract(DeviceVitals.freshFor * 2),
      );
      expect(old.isFresh, isFalse);
    });

    test('بلا طابع زمنيّ ليس طازجاً', () {
      expect(const VitalsState().isFresh, isFalse);
    });
  });

  group('بنية الجدار', () {
    late String src;
    setUpAll(() {
      src = File('lib/screens/network_devices/devices_wall_screen.dart')
          .readAsStringSync();
    });

    test('البطاقة ابن مباشر للقائمة', () {
      // لو بقيت المجموعة عنصراً واحداً يضمّ بطاقاتها، لبُنيت منطقةٌ فيها
      // أربعون جهازاً دفعةً — ولانهار تبويب النظر كلّه.
      expect(src.contains('final _DeviceRow r => _DeviceCard('), isTrue,
          reason: 'البطاقة يجب أن تُبنى من itemBuilder مباشرةً');
      expect(src.contains('class _RegionGroup'), isFalse,
          reason: 'المجموعة الحاضنة تُبطل تنويف ListView');
    });

    test('مفتاح البطاقة بمعرّف الجهاز', () {
      expect(src.contains('key: ValueKey(r.device.id)'), isTrue,
          reason: 'بلا مفتاح تظهر مقاييس برجٍ فوق اسم برجٍ غيره عند الفرز');
    });

    test('الإلغاء عند التخلّص', () {
      expect(src.contains('DeepProbeScheduler.instance.cancel(this)'), isTrue);
    });

    test('لا جلسة عميقة للمعطّل', () {
      expect(src.contains('if (!isDown)'), isTrue,
          reason: 'الشريط يُرسَم للحيّ فقط');
    });
  });
}
