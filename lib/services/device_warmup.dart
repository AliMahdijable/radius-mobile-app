import 'dart:async';

import '../models/network_device.dart';
import '../screens/network_devices/device_vitals.dart';
import 'deep_probe_scheduler.dart';
import 'device_stats_cache.dart';

/// تسخينٌ في الخلفيّة — يملأ [DeviceStatsCache] ما دام المدير في قسم
/// الأجهزة، فيكون فتحُ أيّ جهازٍ فوريّاً.
///
/// 🐛 طلب المستخدم ٢٠٢٦-٠٩-٠٢: «الفحص يبقى مستمرّاً بالخلفيّة عندما
/// المدير يفوت على قسم الأجهزة، والداتا جاهزة — وقت ما أفتح جهاز
/// يرجع لي الداتا، إن كانت مخزونة أو حديثة».
///
/// ── لماذا واحدٌ في كلّ مرّة ────────────────────────────────────────
/// التسخين خدمةٌ صامتة، والمستخدم لا ينتظرها. فأيّ تزاحمٍ منها على
/// خانات المجدول الستّ يُبطئ ما **ينظر إليه** الآن. جلسةٌ واحدة تعمل
/// في الفراغ ولا تُزاحم، وثمانون جهازاً تكتمل في دقائق — وهي دقائق
/// يتصفّح فيها المستخدم على أيّ حال.
///
/// ── ولماذا بأدنى أولويّة ─────────────────────────────────────────
/// `submit(first: false)` يضعها خلف كلّ بطاقةٍ تنتظر قراءتها الأولى.
/// من ينظر إليه المستخدم يسبق من قد ينظر إليه.
class DeviceWarmup {
  DeviceWarmup._();
  static final DeviceWarmup instance = DeviceWarmup._();

  /// فاصلٌ بين جهازٍ وآخر — يترك الشبكة تتنفّس بين الجلسات.
  static const gap = Duration(seconds: 3);

  bool _running = false;
  Timer? _timer;
  final List<NetworkDevice> _queue = [];
  final Set<int> _done = {};

  bool get isRunning => _running;
  int get remaining => _queue.length;

  /// يبدأ التسخين لقائمة الأجهزة الحاليّة. استدعاؤه مرّةً ثانيةً بقائمةٍ
  /// أحدث يُحدّث الطابور بلا إعادة ما سُخِّن.
  void start(List<NetworkDevice> devices) {
    _queue
      ..clear()
      ..addAll(devices.where(_worth));
    if (_running) return;
    _running = true;
    _tick();
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _queue.clear();
  }

  /// يُنسى ما سُخِّن فيُعاد من جديد — بعد تبديل حساب مثلاً.
  void reset() {
    stop();
    _done.clear();
  }

  /// هل يستحقّ هذا الجهاز جلسةً؟
  ///
  /// نمتنع بنفس أسباب البطاقة: غير المتّصل لا يردّ، وبلا بيانات دخول
  /// لا نصادق، والعلامة غير المدعومة لا مقاييس لها. ومن حمولتُه طازجةٌ
  /// في المخزن لا يحتاج جلسةً أصلاً.
  bool _worth(NetworkDevice d) {
    if (_done.contains(d.id)) return false;
    if (DeviceVitals.skipReason(d) != null) return false;
    return DeviceStatsCache.instance.ageOf(d.id) == null;
  }

  void _tick() {
    if (!_running) return;
    if (_queue.isEmpty) {
      // انتهى الطابور — نتوقّف ولا ندور فارغين.
      _running = false;
      return;
    }
    final d = _queue.removeAt(0);
    _done.add(d.id);

    DeepProbeScheduler.instance.submit(_WarmOwner(d.id), () async {
      try {
        final r = await DeviceVitals.fetch(d);
        if (r.raw != null) DeviceStatsCache.instance.putRaw(d.id, r.raw!);
        DeviceStatsCache.instance.putSample(d.id, r.counters);
      } catch (_) {
        // فشلُ تسخينٍ لا يُبلَّغ: المستخدم لم يطلبه، وسيرى الخطأ
        // الحقيقيّ حين يفتح الجهاز فعلاً.
      }
    });

    _timer = Timer(gap, _tick);
  }
}

/// مالكٌ مستقلّ لمهامّ التسخين.
///
/// ⚠️ ليس البطاقة: لو تشاركا المالك لسحب إلغاءُ إحداهما مهمّة الأخرى،
/// ولأبطل تسخينٌ متأخّر قراءةً طلبها المستخدم توّاً.
class _WarmOwner {
  const _WarmOwner(this.deviceId);
  final int deviceId;

  @override
  bool operator ==(Object other) =>
      other is _WarmOwner && other.deviceId == deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}
