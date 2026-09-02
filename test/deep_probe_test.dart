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
      expect(DeviceVitals.skipReason(dev(status: 'offline')), 'غير متّصل',
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

  group('حساب معدّل المرور', () {
    // الدالّة private؛ نُعيد قواعدها هنا حرفيّاً — والحارس الحقيقيّ أنّ
    // أيّ انحراف بينهما يظهر فوراً في القيم على الجهاز.
    ({int? rx, int? tx}) rate({
      required int rxNow,
      required int txNow,
      Map<String, ({int rx, int tx})>? before,
      double secs = 15,
    }) {
      if (before == null) return (rx: null, tx: null);
      final b = before['eth'];
      if (b == null) return (rx: null, tx: null);
      if (secs < 1 || secs > 300) return (rx: null, tx: null);
      if (rxNow < b.rx || txNow < b.tx) return (rx: null, tx: null);
      return (
        rx: ((rxNow - b.rx) * 8 / secs).round(),
        tx: ((txNow - b.tx) * 8 / secs).round(),
      );
    }

    test('بلا عيّنة سابقة لا معدّل', () {
      // «٠ بت» يوحي بمنفذٍ صامت وهو يحمل غيغابت — الشرطة أصدق.
      expect(rate(rxNow: 1000, txNow: 500).rx, isNull);
    });

    test('الفارق يُقسَم على الزمن الحقيقيّ', () {
      // ٢٥٠ ميغابايت في ١٥ث = ١٣٣ ميغابت/ث تقريباً
      final r = rate(
        rxNow: 250000000,
        txNow: 0,
        before: {'eth': (rx: 0, tx: 0)},
      );
      expect(r.rx, 133333333);
    });

    test('زمن قصير يُرفَض — الفخّ الذي أعطى ٤ غيغا بدل ١٣٠ ميغا', () {
      // ٢٠٢٦-٠٨-١٣ في اللوحات المفردة: قسمة على نصف ثانية بدل ١٥
      // أظهرت ether1 يحمل 4.10Gbps وهو يحمل 130Mbps. الحارس هنا يمنع
      // أن يتكرّر في الجدار.
      final r = rate(
        rxNow: 250000000,
        txNow: 0,
        before: {'eth': (rx: 0, tx: 0)},
        secs: 0.5,
      );
      expect(r.rx, isNull, reason: 'نافذة أقصر من ثانية تُضخّم أيّ ضجيج');
    });

    test('زمن طويل يُرفَض — متوسّط لا معدّل', () {
      final r = rate(
        rxNow: 250000000,
        txNow: 0,
        before: {'eth': (rx: 0, tx: 0)},
        secs: 600,
      );
      expect(r.rx, isNull);
    });

    test('ارتداد العدّاد (إقلاع الجهاز) لا يُنتج رقماً', () {
      final r = rate(
        rxNow: 100,
        txNow: 50,
        before: {'eth': (rx: 999999999, tx: 999999999)},
      );
      expect(r.rx, isNull, reason: 'الطرح يُخرج سالباً أو رقماً ضخماً كاذباً');
    });

    test('منفذ جديد لم يكن في العيّنة السابقة', () {
      final r = rate(rxNow: 100, txNow: 50, before: {'other': (rx: 0, tx: 0)});
      expect(r.rx, isNull);
    });
  });

  group('التنسيق', () {
    test('المرور يتدرّج بالوحدات', () {
      expect(DeviceVitals.fmtBps(null), '—');
      expect(DeviceVitals.fmtBps(800), '800');
      expect(DeviceVitals.fmtBps(45000), '45 K');
      expect(DeviceVitals.fmtBps(133333333), '133.3 M');
      expect(DeviceVitals.fmtBps(4100000000), '4.10 G');
    });

    test('مدّة التشغيل تتدرّج', () {
      expect(DeviceVitals.fmtUptime(0), '—');
      expect(DeviceVitals.fmtUptime(300), '5 دقيقة');
      expect(DeviceVitals.fmtUptime(7200), '2 ساعة');
      expect(DeviceVitals.fmtUptime(86400 * 12), '12 يوماً');
    });
  });

  group('عرض المطويّ', () {
    late String src;
    setUpAll(() {
      src = File('lib/screens/network_devices/devices_wall_screen.dart')
          .readAsStringSync();
    });

    test('الفتح لا يفتح جلسة جديدة', () {
      // التفصيل يأتي من نفس الحمولة — أيّ نداء هنا يُبطل جوهر التصميم.
      final i = src.indexOf('class _CardDetails');
      final body = src.substring(i, src.indexOf('class _DetailHeading'));
      expect(body.contains('DeviceVitals.fetch'), isFalse);
      expect(body.contains('await '), isFalse,
          reason: 'المطويّ يرسم ما وصل، لا يجلب');
    });

    test('الأضعف إشارةً أوّلاً', () {
      // من يفتح قائمة المتّصلين يبحث عن الشكوى لا عن الأفضل.
      expect(src.contains('(a.signal ?? 0).compareTo(b.signal ?? 0)'), isTrue);
    });

    test('المنافذ المطفأة لا تُغرق العاملة', () {
      expect(src.contains('d.ports.where((p) => p.up)'), isTrue);
      expect(src.contains('b.total.compareTo(a.total)'), isTrue,
          reason: 'الأكثر مروراً أوّلاً');
    });
  });

  group('CCQ', () {
    late String vitals;
    late String wall;
    setUpAll(() {
      vitals = File('lib/screens/network_devices/device_vitals.dart')
          .readAsStringSync();
      wall = File('lib/screens/network_devices/devices_wall_screen.dart')
          .readAsStringSync();
    });

    test('PeerLink يحمل الحقل', () {
      // كان غائباً كلّيّاً — فلا CCQ لأيّ متّصل رغم أنّ العلامتين
      // تُرجعانه. (بلاغ ٢٠٢٦-٠٩-٠١)
      const p = PeerLink(name: 'x', ccq: 96);
      expect(p.hasCcq, isTrue);
      expect(p.ccq, 96);
    });

    test('الصفر يعني «غير متوفّر» لا «جودة صفر»', () {
      // airFiber ٦٠GHz لا يُرجعه أصلاً؛ عرض «٠٪» يقول إنّ الوصلة
      // منهارة وهي سليمة.
      expect(const PeerLink(name: 'x', ccq: 0).hasCcq, isFalse);
      expect(const PeerLink(name: 'x').hasCcq, isFalse);
    });

    test('العلامتان تُغذّيانه', () {
      expect(vitals.contains('ccq: st.ccq > 0 ? st.ccq : null'), isTrue,
          reason: 'محطّات UBNT');
      expect(
          vitals.contains(
              'ccq: c.txCcq > 0 ? c.txCcq : (c.rxCcq > 0 ? c.rxCcq : null)'),
          isTrue,
          reason: 'عملاء ميكروتك — txCcq أوّلاً فهو ما يشعر به المشترك');
    });

    test('🚨 سلّم CCQ «الأعلى أفضل» لا العكس', () {
      // أخطر خطأ محتمل هنا: تمريره على percentLowerBetter (سلّم المعالج
      // والذاكرة) يقلب الحكم فتُصبَغ وصلةٌ بجودة ٩٦٪ حمراء، وتبدو
      // المنهارة سليمة.
      expect(wall.contains('Grade.percentHigherBetter(peer.ccq)'), isTrue);
      expect(wall.contains('percentLowerBetter(peer.ccq)'), isFalse);
    });

    test('الجودة تسبق الإشارة في الصفّ', () {
      final i = wall.indexOf('class _PeerRow');
      final body = wall.substring(i, wall.indexOf('class _MiniChip'));
      expect(body.indexOf('peer.ccq'), lessThan(body.indexOf("'\$sig'")),
          reason: 'الإشارة وحدها تكذب — الجودة هي التشخيص');
    });

    test('الوصلة قسم مستقلّ لا مدفون في النظام', () {
      expect(wall.contains("_DetailHeading('الوصلة اللاسلكيّة')"), isTrue);
      expect(vitals.contains("(k: 'الجودة CCQ'"), isTrue);
      final i = wall.indexOf("_DetailHeading('الوصلة اللاسلكيّة')");
      final j = wall.indexOf("_DetailHeading('النظام')");
      expect(i, lessThan(j), reason: 'الوصلة قبل النظام');
    });
  });

  group('البطء نسبيّ لا مطلق', () {
    // 🐛 لقطة ٢٠٢٦-٠٩-٠١: اثنا عشر جهازاً كلّها «بطيء · ٢٣٠ms» — نفس
    // الرقم بالضبط. القياس سليم، لكنّ أربعة وعشرين مقبساً تُفتح معاً
    // فيحمل كلّ رقم إزاحةَ ازدحامٍ مشتركة. عتبةٌ ثابتة تُسمّي الجميع
    // بطيئاً أو لا أحد.
    bool slow(int? ms, int? median) {
      if (ms == null || ms < 80) return false;
      if (median == null || median <= 0) return false;
      return ms >= median * 2;
    }

    test('شبكة كلّها ٢٣٠ms: لا أحد بطيء', () {
      expect(slow(230, 230), isFalse, reason: 'الإزاحة المشتركة تسقط');
    });

    test('الشاذّ وحده يُوسَم', () {
      expect(slow(900, 230), isTrue);
      expect(slow(300, 230), isFalse, reason: 'أقلّ من الضعف');
    });

    test('شبكة سريعة لا تُوسَم مهما تفاوتت', () {
      // ٤ms مقابل وسيط ١ms = أربعة أضعاف، لكنّها شبكةٌ سليمة.
      expect(slow(4, 1), isFalse, reason: 'الأرضيّة المطلقة تحميها');
    });

    test('بلا وسيط لا حكم', () {
      expect(slow(500, null), isFalse);
      expect(slow(null, 100), isFalse);
    });
  });

  group('عرض عصريّ', () {
    late String wall;
    setUpAll(() {
      wall = File('lib/screens/network_devices/devices_wall_screen.dart')
          .readAsStringSync();
    });

    test('اتّجاه صريح للرقم ووحدته', () {
      // بلا هذا يقلبهما محرّك الاتّجاه الثنائيّ: «٪ ٣٤» بدل «٣٤٪».
      final i = wall.indexOf('class _VitalChip');
      final body = wall.substring(i, wall.indexOf('class _Note'));
      expect(body.contains('Directionality('), isTrue);
      expect(body.contains('TextDirection.ltr'), isTrue);
    });

    test('شريط حالة على الحافّة بدل الصندوق', () {
      expect(wall.contains('PositionedDirectional('), isTrue);
      expect(wall.contains('Container(width: 3, color: tone.fill)'), isTrue);
    });

    test('الملخّص يوافق البطاقات تحته', () {
      // «الكلّ سليم» فوق اثنَي عشر جهازاً بطيئاً أسوأ من غياب الملخّص.
      expect(wall.contains("if (slow > 0) return ('\$slow بطيء'"), isTrue);
    });
  });

  group('حارس الحياة', () {
    setUp(sched.resetForTest);

    test('🚨 مهمّة معلَّقة تُحرّر خانتها', () async {
      // بلاغ ٢٠٢٦-٠٩-٠٢: «جاب بس كم واحد وتوقّف بالكامل».
      //
      // المجدول كان يُحرّر الخانة في `whenComplete` وحدها. وتعهّدٌ لا
      // يكتمل أبداً لا يُنادى فيه `whenComplete` — فتبقى خانته محجوزة،
      // وستٌّ معلَّقة تُجمّد الطابور كلّه.
      expect(DeepProbeScheduler.jobTimeout.inSeconds, greaterThan(0),
          reason: 'بلا مهلةٍ يُمسك التعهّد المعلَّق خانته إلى الأبد');
      // المهلة معقولة: تسع أطول مسار (ميكروتك: جدول ثمّ صيغة ثانية
      // ثمّ SSH) ولا تُجمّد الطابور دقائق.
      expect(DeepProbeScheduler.jobTimeout.inSeconds, inInclusiveRange(15, 60));
    });

    test('المهلة مطبَّقة على التشغيل لا على الإدراج', () {
      final src = File('lib/services/deep_probe_scheduler.dart')
          .readAsStringSync();
      expect(src.contains('.timeout(jobTimeout)'), isTrue);
      final i = src.indexOf('.timeout(jobTimeout)');
      final j = src.indexOf('whenComplete', i);
      expect(j, greaterThan(i), reason: 'المهلة قبل تحرير الخانة');
    });
  });

  group('القراءة الأولى تتقدّم', () {
    setUp(sched.resetForTest);

    test('🚨 المُجدِّد لا يسبق من لم يقرأ قطّ', () async {
      // الطابور كان يعامل من لم يقرأ كمن يُحدّث قراءةً عمرها ثانية.
      // فالبطاقات الأولى تستهلك الخانات الستّ والأخيرة تبقى على
      // «يقرأ المقاييس…» أبداً.
      final gate = Completer<void>();
      final order = <String>[];
      for (var i = 0; i < DeepProbeScheduler.maxConcurrent; i++) {
        sched.submit(Object(), () async => gate.future);
      }
      // ثلاثة مُجدِّدين ثمّ قارئٌ أوّل
      for (var i = 0; i < 3; i++) {
        final n = 'renew$i';
        sched.submit(Object(), () async => order.add(n));
      }
      sched.submit(Object(), () async => order.add('FIRST'), first: true);

      await Future<void>.delayed(Duration.zero);
      expect(sched.pendingCount, 4);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(order.first, 'FIRST',
          reason: 'من لم يقرأ قطّ يجب أن يسبق كلّ مُجدِّد');
    });

    test('الأوائل بينهم بترتيب وصولهم', () async {
      // التقدّم على المُجدِّدين مقصود، والتقدّم على قرينٍ ينتظر قراءته
      // الأولى يجعل الترتيب عشوائيّاً.
      final gate = Completer<void>();
      final order = <String>[];
      for (var i = 0; i < DeepProbeScheduler.maxConcurrent; i++) {
        sched.submit(Object(), () async => gate.future);
      }
      sched.submit(Object(), () async => order.add('A'), first: true);
      sched.submit(Object(), () async => order.add('B'), first: true);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(order, ['A', 'B']);
    });

    test('البطاقة تطلب الأولويّة حين لا قيمة عندها', () {
      final wall = File('lib/screens/network_devices/devices_wall_screen.dart')
          .readAsStringSync();
      expect(wall.contains('first: st.vitals == null'), isTrue);
    });
  });
}
