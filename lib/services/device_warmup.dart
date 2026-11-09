import 'dart:async';

import '../models/network_device.dart';
import '../screens/network_devices/device_vitals.dart';
import 'deep_probe_scheduler.dart';
import 'device_stats_cache.dart';
import 'device_sweep_coordinator.dart';

/// تسخينٌ في الخلفيّة — يملأ [DeviceStatsCache] ما دام المدير في قسم
/// الأجهزة، فيكون فتحُ أيّ جهازٍ فوريّاً.
///
/// 🐛 طلب المستخدم ٢٠٢٦-٠٩-٠٢: «الفحص يبقى مستمرّاً بالخلفيّة عندما
/// المدير يفوت على قسم الأجهزة، والداتا جاهزة — وقت ما أفتح جهاز
/// يرجع لي الداتا، إن كانت مخزونة أو حديثة».
///
/// ── لماذا واحدٌ في كلّ مرّة، **مُنتظَراً** ────────────────────────
/// التسخين خدمةٌ صامتة، والمستخدم لا ينتظرها. فأيّ تزاحمٍ منها على
/// خانات المجدول الستّ يُبطئ ما **ينظر إليه** الآن.
///
/// ⚠️ ولا يكفي أن تُطلَق واحدةً كلّ ثلاث ثوانٍ: جلسة ميكروتك تستغرق
/// نحو خمس عشرة، فتتراكم خمسُ مهامّ على ستّ خانات. الفجوة يجب أن تكون
/// بين **الجلستين** لا بين الإطلاقين — فننتظر اكتمال كلّ واحدة.
///
/// وثمانون جهازاً تكتمل في دقائق يتصفّح فيها المستخدم على أيّ حال.
///
/// ── ولماذا يستأذن قبل كلّ جهاز ───────────────────────────────────
/// `submit(first: false)` يضعها خلف كلّ بطاقةٍ تنتظر قراءتها الأولى —
/// لكنّ الأولويّة ترتّب **المنتظرين** ولا تُخرج من بدأ. فإن كان
/// التسخين قد شغل الخانات فعلاً، انتظرت البطاقاتُ خلفه مهما علت
/// أولويّتها.
///
/// لذلك نسأل [DeepProbeScheduler.hasFirstPending] قبل كلّ جهاز
/// ونُرجئ: المنع من البدء أنفع من الترتيب بعده.
class DeviceWarmup {
  DeviceWarmup._();
  static final DeviceWarmup instance = DeviceWarmup._();

  /// فاصلٌ بين جهازٍ وآخر — يترك الشبكة تتنفّس بين الجلسات.
  static const gap = Duration(seconds: 3);

  bool _running = false;
  Timer? _timer;
  final List<NetworkDevice> _queue = [];
  final Set<int> _done = {};

  /// جولة السلسلة الحاليّة — [stop] يرفعها، فسلسلةٌ كانت تنتظر قراءتها لا تُكمل بجانب سلسلةٍ بدأت بعد [start] جديد
  /// (المراجعة الثانية: تبديل النافذة على الحاسبة وقراءةٌ جارية كانا يتركان سلسلتين ⇒ جلستين معاً).
  int _gen = 0;

  bool get isRunning => _running;
  int get remaining => _queue.length;

  /// يبدأ التسخين لقائمة الأجهزة الحاليّة. استدعاؤه مرّةً ثانيةً بقائمةٍ
  /// أحدث يُحدّث الطابور بلا إعادة ما سُخِّن.
  void start(List<NetworkDevice> devices) {
    // ⚠️ من لا قراءة له فقط — ولا ترقيةَ جماعيّة.
    //
    // جرّبتُ ٢٠٢٦-٠٩-٠٢ أن أُرقّي كلّ حمولةٍ خفيفة إلى كاملة في
    // الخلفيّة ليجد المستخدمُ التفاصيلَ جاهزة، فأشبعتُ الشبكة بسبع
    // عشرة جلسة SSH متتالية وعاد كلّ شيء بطيئاً. راجع `_tick`.
    _queue
      ..clear()
      ..addAll(devices.where(_worth));
    if (_running) return;
    _running = true;
    _tick();
  }

  /// «القراءات الحسّاسة» (٤ نوفمبر): إعادة قراءة من شاخت قراءته أكثر من [olderThan] — خفيفةً واحداً بعد واحد كالتسخين نفسه (تتنحّى
  /// للبطاقات المرئيّة)، فتصل قراءاتها للخادم ([VitalsReporter]) كلّ ١٠ د ما دام القسم مفتوحاً.
  void refresh(List<NetworkDevice> devices, {Duration olderThan = const Duration(minutes: 10)}) {
    for (final d in devices) {
      if (DeviceVitals.skipReason(d) != null) continue;
      final age = DeviceStatsCache.instance.ageOf(d.id);
      if (age != null && age <= olderThan) continue;
      if (_queue.any((x) => x.id == d.id)) continue;
      _queue.add(d);
    }
    if (_running || _queue.isEmpty) return;
    _running = true;
    _tick();
  }

  void stop() {
    _running = false;
    _gen++;
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

  /// جولة الترقية تُعاد كلّما فتح المستخدم القسم — فما رُقّي يبقى
  /// مرقّىً، وما شاخ يُرقّى ثانيةً. لذلك لا نستعمل `_done` هنا.
  ///
  /// وهي رخيصة: `needsUpgrade` تُرجع false لمن حمولته كاملةٌ طازجة.

  Future<void> _tick() async {
    if (!_running) return;
    final gen = _gen;
    if (_queue.isEmpty) {
      // انتهى الطابور — نتوقّف ولا ندور فارغين.
      _running = false;
      return;
    }

    // ⚠️ نستأذن قبل كلّ جهاز.
    //
    // 🐛 عطلٌ أدخلتُه ٢٠٢٦-٠٩-٠٢: «جهاز واحد فقط ظهر معلومات، البقيّة
    // كلّها تكتب يقيس». والأولويّة في الطابور لا تكفي — فهي ترتّب
    // **المنتظرين** ولا تُخرج من بدأ. فإن كان التسخين قد شغل الخانات
    // فعلاً، انتظرت البطاقاتُ المرئيّة خلفه مهما علت أولويّتها.
    //
    // الاستئذان يمنع البدء أصلاً: لا نُسخّن لجهازٍ قد يُفتح غداً بينما
    // بطاقةٌ أمام العين تنتظر رقمها الأوّل.
    // و«الفحص الشامل» مفتوحٌ فوق القسم ([DeviceSweep]) ⇒ ننتظره — لا جلسةٌ صامتة تزاحمه (٩ نوفمبر)
    if (DeepProbeScheduler.instance.hasFirstPending || DeviceSweep.suspended) {
      _timer = Timer(gap, _tick);
      return;
    }

    final d = _queue.removeAt(0);
    // قراءة الفحص الشامل له جارية بعد سقفه ⇒ آخر الطابور، لا جلسة ثانية الآن (المراجعة الثانية)
    if (DeviceSweep.busy(d.id)) {
      _queue.add(d);
      _timer = Timer(gap, _tick);
      return;
    }
    _done.add(d.id);

    // ⚠️ **ننتظر اكتمالها** قبل التالي.
    //
    // كانت تُطلَق ثمّ يُجدوَل التالي بعد ثلاث ثوانٍ. وجلسة ميكروتك
    // تستغرق نحو خمس عشرة — فتتراكم خمسُ مهامّ تسخين على ستّ خانات،
    // ولا يبقى للبطاقات المرئيّة إلّا واحدة. الفجوة كانت بين
    // **الإطلاقين** لا بين الجلستين.
    final done = Completer<void>();
    DeepProbeScheduler.instance.submit(_WarmOwner(d.id), () async {
      try {
        // انتظرت دورها والفحص الشامل بدأ بعدها (أو قراءته لهذا الجهاز جارية) — تعود للطابور بلا جلسة (المراجعة)
        if (DeviceSweep.suspended || DeviceSweep.busy(d.id)) {
          _done.remove(d.id);
          _queue.insert(0, d);
          return;
        }
        // ⚠️ **خفيف** لا كامل.
        //
        // 🐛 انحدارٌ أدخلتُه ٢٠٢٦-٠٩-٠٢ ثمّ كشفه سجلّ المستخدم: جعلتُ
        // التسخين يجلب الكامل ليجد المستخدمُ التفاصيلَ جاهزة. فعاد إلى
        // الخلفيّة بالضبط ما أزلتُه من المقدّمة — جلسة SSH لكلّ جهاز
        // ميكروتك، سبع عشرة جلسة متتالية تُشبع الشبكة والمجدول.
        //
        // والحساب لا يستقيم: التفاصيل تُجلَب لثمانين جهازاً ليُفتح
        // منها واحد. الخلفيّة يجب أن تبقى **رخيصة** — والغالي يُدفع
        // عند الطلب وحده، والفتحُ يتقدّم الطابور أصلاً.
        final r = await DeviceVitals.fetch(d);
        if (r.raw != null) {
          DeviceStatsCache.instance.putRaw(d.id, r.raw!, detailed: false);
        }
        DeviceStatsCache.instance.putSample(d.id, r.counters);
      } catch (_) {
        // فشلُ تسخينٍ لا يُبلَّغ: المستخدم لم يطلبه، وسيرى الخطأ
        // الحقيقيّ حين يفتح الجهاز فعلاً.
      } finally {
        if (!done.isCompleted) done.complete();
      }
    });

    // مهلةٌ أطول من مهلة المجدول بقليل: لو أُسقطت المهمّة من الطابور
    // قبل أن تبدأ فلن يكتمل التعهّد أبداً، ولا نريد أن يقف التسخين.
    await done.future
        .timeout(DeepProbeScheduler.jobTimeout + const Duration(seconds: 5))
        .catchError((_) {});

    // أُوقف ثمّ بدأ من جديد وهي تنتظر ⇒ السلسلة الجديدة تكمل وحدها
    if (!_running || gen != _gen) return;
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
