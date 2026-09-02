import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_sort.dart';
import 'package:rad_mysvcs/services/device_sweep_coordinator.dart';

/// جدار الأجهزة — حرّاس المنطق الذي لا يُرى في لقطة شاشة.
void main() {
  NetworkDevice dev(int id, String status, {int? ms, DateTime? since}) =>
      NetworkDevice(
        id: id,
        adminId: '2',
        name: 'جهاز $id',
        type: 'link',
        brand: 'ubnt',
        ip: '10.0.0.$id',
        port: 80,
        hasCredentials: false,
        lastStatus: status,
        lastResponseMs: ms,
        statusSince: since,
        createdAt: DateTime(2026, 1, 1),
      );

  group('منسّق المسح', () {
    setUp(() => DeviceSweep.holders.value = 0);

    test('المسح موقوف ما دام الجدار ممسكاً', () {
      expect(DeviceSweep.suspended, isFalse);
      DeviceSweep.acquire();
      expect(DeviceSweep.suspended, isTrue,
          reason: 'شاشة الأجهزة ستمسح تحت الجدار — ضِعف الشبكة وتنبيهان');
      DeviceSweep.release();
      expect(DeviceSweep.suspended, isFalse);
    });

    test('عدّاد لا علَم — مسارات متداخلة', () {
      // جدار ← تفاصيل ← جدار ثانٍ: لو كان علَماً لأطفأه أوّل خروج
      // بينما الثاني ما زال يمسح.
      DeviceSweep.acquire();
      DeviceSweep.acquire();
      DeviceSweep.release();
      expect(DeviceSweep.suspended, isTrue, reason: 'ما زال ممسِكٌ واحد');
      DeviceSweep.release();
      expect(DeviceSweep.suspended, isFalse);
    });

    test('الإفراط في الإفلات لا يهبط تحت الصفر', () {
      DeviceSweep.release();
      DeviceSweep.release();
      expect(DeviceSweep.holders.value, 0,
          reason: 'عدّاد سالب يمنع كلّ إيقاف لاحق للأبد');
    });
  });

  group('الحالة الثالثة', () {
    late String src;
    setUpAll(() {
      src = File('lib/screens/network_devices/devices_wall_screen.dart')
          .readAsStringSync();
    });

    test('البطيء له نغمة خاصّة لا نغمة الحيّ', () {
      // «حيّ» و«معطّل» لا تكفيان: البطء يسبق السقوط.
      //
      // ⚠️ تغيّر المعيار ٢٠٢٦-٠٩-٠١: كانت عتبةً مطلقة (١٥٠ms) فوسمت
      // اثنَي عشر جهازاً كلَّها بالبطء — الجولة تفحص العشرات معاً
      // فيحمل كلّ رقم إزاحةَ ازدحامٍ مشتركة. صار الحكم نسبيّاً لوسيط
      // الجولة، مع أرضيّةٍ مطلقة تحمي الشبكة السريعة.
      expect(src.contains('static const slowFloorMs = 80'), isTrue);
      expect(src.contains('static const slowFactor = 2'), isTrue);
      expect(src.contains('ms >= medianMs * slowFactor'), isTrue);
      expect(src.contains('AppTone.warning'), isTrue,
          reason: 'لا نغمة ثالثة — البطيء يبدو سليماً حتّى يسقط');
    });

    test('غير المتّصل أوّلاً ثمّ المجهول ثمّ السليم', () {
      // ⚠️ الرتبة انتقلت إلى `device_sort.dart` (٢٠٢٦-٠٩-٠٢) لتشترك
      // فيها الشاشتان — الحارس يتبعها إلى موضعها الجديد.
      expect(healthRank(dev(1, 'offline')), 0);
      expect(healthRank(dev(2, 'unknown')), 1,
          reason: 'لم يُفحص بعد — يسبق السليم لا يتبعه');
      expect(healthRank(dev(3, 'online')), 2);
    });
  });

  group('«منذ متى»', () {
    // نستعمل النسخة المصدريّة للقواعد؛ الدالّة نفسها private في الشاشة.
    String? since(DateTime? t, DateTime now) {
      if (t == null) return null;
      final d = now.difference(t);
      if (d.isNegative) return null;
      if (d.inMinutes < 1) return 'منذ لحظات';
      if (d.inMinutes < 60) return 'منذ ${d.inMinutes} دقيقة';
      if (d.inHours < 24) return 'منذ ${d.inHours} ساعة';
      return 'منذ ${d.inDays} يوماً';
    }

    final now = DateTime(2026, 9, 1, 12, 0);

    test('غياب القيمة لا يُلفَّق', () {
      expect(since(null, now), isNull,
          reason: 'جهاز بلا تاريخ يجب ألّا يدّعي «منذ لحظات»');
    });

    test('طابع في المستقبل يُهمَل', () {
      // انحراف ساعة الهاتف عن الخادم يُنتج فرقاً سالباً.
      expect(since(now.add(const Duration(hours: 3)), now), isNull,
          reason: 'ولا نعرض «منذ -3 ساعة»');
    });

    test('الوحدات تتدرّج', () {
      expect(since(now.subtract(const Duration(seconds: 20)), now), 'منذ لحظات');
      expect(since(now.subtract(const Duration(minutes: 4)), now), 'منذ 4 دقيقة');
      expect(since(now.subtract(const Duration(hours: 5)), now), 'منذ 5 ساعة');
      expect(since(now.subtract(const Duration(days: 2)), now), 'منذ 2 يوماً');
    });
  });

  group('حمولة الفحص الجماعيّ', () {
    test('حقل status_since يُقرأ من الخادم', () {
      final d = NetworkDevice.fromJson({
        'id': 1,
        'admin_id': '2',
        'name': 'x',
        'type': 'link',
        'brand': 'ubnt',
        'ip': '10.0.0.1',
        'port': 80,
        'last_status': 'offline',
        'status_since': '2026-09-01T10:00:00.000Z',
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      expect(d.statusSince, isNotNull,
          reason: '«معطّل منذ متى» يعتمد عليه كلّيّاً');
    });

    test('غيابه لا يكسر التحليل', () {
      final d = NetworkDevice.fromJson({
        'id': 1,
        'admin_id': '2',
        'name': 'x',
        'type': 'link',
        'brand': 'ubnt',
        'ip': '10.0.0.1',
        'port': 80,
        'last_status': 'online',
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      expect(d.statusSince, isNull);
    });

    test('copyWith يحفظ status_since', () {
      // ⚠️ المسح المحلّيّ يستدعي copyWith بلا تمرير statusSince عمداً —
      // الخادم يملك القيمة. فلو أسقطها copyWith لاختفى «منذ متى» بعد
      // أوّل جولة مسح.
      final t = DateTime(2026, 9, 1, 8);
      final d = dev(1, 'offline', since: t).copyWith(
        lastStatus: 'offline',
        lastResponseMs: null,
        lastProbedAt: DateTime(2026, 9, 1, 12),
      );
      expect(d.statusSince, t,
          reason: '«معطّل منذ ٤ ساعات» يختفي بعد أوّل مسح لو سقطت');
    });
  });

  group('حارس الشبكة', () {
    late String src;
    setUpAll(() {
      src = File('lib/screens/network_devices/devices_wall_screen.dart')
          .readAsStringSync();
    });

    test('يشترط فشل الكلّ لا فشل بعضهم', () {
      // جهاز واحد معطّل صدفةً يجب ألّا يُعلن «لستَ على الشبكة».
      expect(src.contains('reachable == 0 && attempted >= _offNetworkThreshold'),
          isTrue,
          reason: 'الشرط يجب أن يجمع: لا أحد وصل، والمحاولات كافية');
    });
  });
}
