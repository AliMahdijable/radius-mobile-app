import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/network_device.dart';
import '../../services/deep_probe_scheduler.dart';
import '../../services/device_stats_cache.dart';
import 'device_vitals.dart';
import 'widgets/device_big_card.dart';

/// البطاقة الكبيرة **الحيّة** بقائمة الأجهزة («بطاقات كبيرة» — المالك ٣١ أكتوبر: «نظرة عامه ع الاجهز نلغيها ونستبدل بدالها
/// تغير نوع العرض مثل الي بالحاسوب، نخلي عرض كارتات كبار…»).
///
/// منطق القراءة هنا هو منطق بطاقات «النظرة العامّة» حرفاً (أُلغيت الشاشة وبقي قلبها، بكلّ إصلاحاته المؤرَّخة أدناه): بذرٌ من
/// المخزن قبل أيّ جلسة، الحارس محلّيٌّ لا علَمٌ في مخزن الشاشة، الحفظ في المخزن قبل حارس `mounted`، ومجدولٌ بستّ خاناتٍ تُسحب
/// منه البطاقة حين تخرج من الشاشة. الفرق الوحيد: البطاقة الكبيرة «مفتوحة» دائماً — تجلب التفاصيل (العملاء · المنافذ) لأنّها
/// تعرضها، والعرض نفسه في [DeviceBigCard].
///
/// الحالة لكلّ جهاز ([VitalsStore]) تعيش في الشاشة لا في البطاقة: البطاقة تُهدم مع التمرير، ولو ماتت القيمة معها لأعادت كلّ
/// عودةٍ فتحَ الجلسات من الصفر.

class DeviceLiveCard extends StatefulWidget {
  const DeviceLiveCard({
    super.key,
    required this.device,
    required this.vitals,
    required this.onVitals,
    required this.medianMs,
    required this.prevSample,
    required this.onSample,
    required this.onOpen,
    this.rows = 4,
  });

  final NetworkDevice device;
  final ValueNotifier<VitalsState> vitals;
  final ValueChanged<VitalsState> onVitals;
  final int? medianMs;
  final CounterSample? Function() prevSample;
  final ValueChanged<Map<String, ({int rx, int tx})>> onSample;
  final VoidCallback onOpen;

  /// كم سطراً في قسم التفاصيل — راجع [DeviceBigCard.rows].
  final int rows;

  @override
  State<DeviceLiveCard> createState() => _DeviceLiveCardState();
}

class _DeviceLiveCardState extends State<DeviceLiveCard> {
  /// نبضة الجلب العميق للبطاقة المرئيّة.
  ///
  /// أبطأ من نبضة اللوحة المفردة (٨ث لميكروتك): الجدار يعرض ستّاً لا
  /// واحدة، والمجموع هو ما يُسخّن الهاتف.
  static const _pulse = Duration(seconds: 15);

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // ── بذرٌ من المخزن قبل أيّ جلسة ────────────────────────────
    //
    // 🐛 بلاغ المستخدم ٢٠٢٦-٠٩-٠٤: «إذا أطلع وأطبّ للتطبيق عشر مرّات
    // كلّ مرّة يرجع يفحصهن. كلّش مزعج».
    //
    // والسبب أنّ حاجز الطزاجة كان يقرأ من `VitalsStore` — وهي حقلٌ في
    // حالة الشاشة يُمسح في `dispose`. فكلّ عودةٍ تبدأ من `idle`، فيرى
    // الحاجزُ «لا قراءة» ويُرسل جلسةً بأولويّةٍ قصوى لكلّ بطاقة مرئيّة.
    //
    // والمخزن العالميّ كان يحمل الحمولة طازجةً طوال الوقت — لكنّ أحداً
    // لم يسأله. الآن نبذر منه، فتظهر الأرقام فوراً ويصمت الحاجز.
    final seed = DeviceStatsCache.instance
        .vitalsOf(widget.device.id, DeviceVitals.freshFor);
    if (seed != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onVitals(VitalsState(
          vitals: seed.vitals.cast<Vital>(),
          detail: seed.detail as DeviceDetail?,
          at: seed.at,
        ));
      });
    }

    // ── ومحوُ علَمٍ ورثناه عن بطاقةٍ ميّتة ─────────────────────
    //
    // الحارس صار محلّيّاً، فالعلَم الموروث لم يعد يجمّدنا. لكنّه يبقى
    // مرئيّاً: البطاقة تعتّم القيمة إلى ٠٫٥٥ ما دام `loading`.
    // فبطاقةٌ سليمةٌ تُعرض باهتةً بلا سبب حتّى أوّل نتيجة.
    //
    // ⚠️ ولو ارتدّ حارسُ الطزاجة (`isFresh`) لبقيت باهتةً إلى الأبد.
    final inherited = widget.vitals.value;
    if (inherited.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final cur = widget.vitals.value;
        if (!cur.loading || _inFlight) return;
        widget.onVitals(VitalsState(
          vitals: cur.vitals,
          detail: cur.detail,
          error: cur.error,
          at: cur.at,
        ));
      });
    }

    // بعد الإطار: الجلب يكتب في مُنبّهٍ يستمع إليه بناؤنا، والكتابة
    // أثناء البناء تُسقط إطاراً بخطأ setState-during-build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
    _timer = Timer.periodic(_pulse, (_) => _kick());
    DeviceStatsCache.instance.updated.addListener(_onCache);
  }

  /// قراءةٌ أحدث لهذا الجهاز كتبها غيرنا (شاشات الألياف للأولت، البرج) ⇒ نعرضها الآن بلا جلسة (المالك ٢٨ أكتوبر: «تتحدث مع
  /// تزامن تحديث الاجهزه»). كتابتنا نحن تعود بنفس الوقت تقريباً فتُترك.
  void _onCache() {
    final u = DeviceStatsCache.instance.updated.value;
    if (!mounted || u.id != widget.device.id || _inFlight) return;
    final v = DeviceStatsCache.instance.vitalsOf(widget.device.id, DeviceVitals.freshFor);
    if (v == null) return;
    final at = widget.vitals.value.at;
    if (at != null && !v.at.isAfter(at.add(const Duration(seconds: 1)))) return;
    widget.onVitals(VitalsState(vitals: v.vitals.cast<Vital>(), detail: v.detail as DeviceDetail?, at: v.at));
  }

  @override
  void didUpdateWidget(covariant DeviceLiveCard old) {
    super.didUpdateWidget(old);
    // جهاز عاد للحياة بعد مسحٍ سطحيّ: امتنعنا عن جلسته وهو معطّل،
    // فلولا هذا لبقيت خاناته فارغةً حتّى تُهدم البطاقة وتُبنى.
    if (old.device.lastStatus != widget.device.lastStatus) _kick();

  }

  @override
  void dispose() {
    _timer?.cancel();
    DeviceStatsCache.instance.updated.removeListener(_onCache);
    // ⚠️ نصف فائدة المجدول: بطاقة خرجت من الشاشة قبل دورها تُسحب من
    // الطابور فلا تُفتح لها جلسة أصلاً.
    DeepProbeScheduler.instance.cancel(this);
    super.dispose();
  }

  /// جلسةٌ لهذه البطاقة قيد التنفيذ.
  ///
  /// 🐛 بلاغ المستخدم ٢٠٢٦-٠٩-٠٤: «الدخول ع الأجهزة نظرة عامّة يجلب ٣
  /// ويوقف، أخرج وأرجع ٣ مرّات حتّى يظهرهم كلّهم».
  ///
  /// ⚠️ وهو **تكرارٌ** لبلاغ ٢٠٢٦-٠٩-٠٢ («جاب بس كم واحد وتوقّف بالكامل»)
  /// المذكور في `DeepProbeScheduler.jobTimeout`. تلك الجولة أصلحت تسريب
  /// **خانة المجدول**؛ وبقي تسريبٌ ثانٍ في **علَم الواجهة** يُنتج العرَض
  /// نفسه بآليّةٍ أخرى.
  ///
  /// ── الآليّة ────────────────────────────────────────────────────
  /// كان الحارس يقرأ `widget.vitals.value.loading` — وذلك المُنبّه يعيش
  /// في `VitalsStore` **على الشاشة** لا على البطاقة، و`of()` تُرجع
  /// المُنبّه نفسه لكلّ بطاقةٍ تُبنى لاحقاً لهذا الجهاز.
  ///
  /// و`loading: true` يُنشر **قبل** `submit`، وكلّ مسارٍ يُطفئه محروسٌ
  /// بـ`mounted` ولا واحد منها في `finally`. فبطاقةٌ تُهدَم بعد النشر
  /// تترك `true` في مُنبّهٍ بلا مالك:
  ///
  ///   • `dispose` يستدعي `cancel(this)` فتُسحب المهمّة ولا تُنشر أبداً
  ///   • أو تبدأ بعد الموت فترتدّ عند `if (!mounted) return`
  ///   • أو تنتهي بعده فترتدّ عند الحارسين ٨٢٢ و٨٣١
  ///
  /// فالبطاقة البديلة ترث `true`، ويرتدّ حارسُها فوراً، ولا `pulse` ولا
  /// `didUpdateWidget` ولا نقرةٌ تُحرّرها — لأنّ الحارس **يسبق** فحص
  /// المخزن أدناه. تجمد على «يقيس…» ما دامت الشاشة مفتوحة، والرقم
  /// موجودٌ في المخزن العالميّ لا يقرؤه أحد.
  ///
  /// والخروج يُهدم `VitalsStore` فتُمحى الأعلام كلّها، والعودة تبذر من
  /// المخزن — فيظهر من نجح سابقاً وتُنفَق الخانات الستّ على جددٍ غيرهم.
  /// ثلاث دخلاتٍ فيظهر الجميع. وهو وصف المستخدم حرفاً بحرف.
  ///
  /// ── ولماذا العلَم هنا لا هناك ──────────────────────────────────
  /// «جلسةٌ قيد التنفيذ» صفةُ **البطاقة** لا صفةُ الجهاز: مالكها هو من
  /// أطلقها، فيجب أن تموت بموته. ووضعُها في مخزنٍ يعمّر أطول منها هو
  /// الخطأ نفسه بصيغةٍ أخرى.
  ///
  /// و`loading` يبقى منشوراً في المخزن — لكن للعرض وحده (تعتيم ٠٫٥٥ في
  /// البطاقة)، لا كحارس.
  bool _inFlight = false;

  /// آخر جلسةٍ ناجحة لهذه البطاقة — راجع [_kick].
  DateTime? _ownAt;

  void _kick({bool urgent = false}) {
    if (!mounted) return;
    final st = widget.vitals.value;
    // ⚠️ الطازج يُحترم — إلّا عند الفتح بلا تفاصيل.
    //
    // القراءة المطويّة خفيفة (ثلاثة أرقام بلا عملاء ولا منافذ)، فطزاجتُها
    // لا تُغني المفتوحَ عن جلسته. ولولا هذا الاستثناء لبقي المطويّ
    // المفتوح بلا تفصيلٍ عشرين ثانية بحجّة أنّ أرقامه حديثة.
    // المخزن هو المرجع لا الحالة المعروضة: الترقية الصامتة قد تكون
    // جلبت التفاصيل بعد آخر نشرٍ لهذه البطاقة.
    // البطاقة الكبيرة «مفتوحة» دائماً (متّصلون · منافذ · PON): قراءةٌ خفيفة في المخزن (التسخين، شاشات الألياف) لا تُغنيها.
    // وجلستُها هي الحديثة تكفي ولو لم تحمل حمولةً خاماً (أولتٌ بلا بنية) — فلا تُعاد كلّ نبضة.
    final own = _ownAt != null && DateTime.now().difference(_ownAt!) < DeviceVitals.freshFor;
    final hasDetail = own || DeviceStatsCache.instance.isDetailed(widget.device.id);
    final needsDetail = !hasDetail && st.error == null;
    if (_inFlight || (st.isFresh && !needsDetail)) return;

    // ⚠️ والمخزن مرجعٌ ثانٍ — لأنّ حالة الشاشة تموت مع الشاشة.
    //
    // `st.isFresh` أعلاه يكفي ما دام المستخدم في القسم. أمّا بعد خروجٍ
    // وعودة فهي دائماً `false`، والمخزن وحده يعرف أنّ الجهاز قُرئ قبل
    // ثوانٍ. بلا هذا السطر يبقى كلّ رجوعٍ جولةَ فحصٍ كاملة.
    if (!needsDetail && !urgent) {
      final age = DeviceStatsCache.instance.ageOf(widget.device.id);
      if (age != null && age < DeviceVitals.freshFor) return;
    }

    // الامتناع الصريح أرخص من محاولةٍ تفشل: كلّ محاولة تحجز خانةً من
    // ستّ وتنتظر مهلتها كاملةً قبل أن تُحرّرها.
    final skip = DeviceVitals.skipReason(widget.device);
    if (skip != null) {
      widget.onVitals(VitalsState(error: skip, at: DateTime.now()));
      return;
    }

    // نُبقي القيم القديمة معروضةً أثناء التحديث — وميضُ فراغٍ ثمّ رقمٍ
    // كلّ خمس عشرة ثانية أسوأ من رقمٍ عمره ثانيتان.
    widget.onVitals(VitalsState(
      vitals: st.vitals,
      detail: st.detail,
      loading: true,
      at: st.at,
    ));

    // القراءة الأولى تتقدّم — راجع [DeepProbeScheduler.submit].
    _inFlight = true;
    DeepProbeScheduler.instance.submit(this, first: urgent || st.vitals == null,
        () async {
      // ⚠️ `finally` لا حارسٌ عند كلّ مخرج: المخارج أربعة، ونسيان واحدٍ
      // منها يُعيد التجمّد كاملاً. و`!mounted` داخله لا قبله للسبب نفسه.
      try {
        if (!mounted) return;
        final r = await DeviceVitals.fetch(
          widget.device,
          prev: widget.prevSample(),
          // البطاقة الكبيرة تعرض التفاصيل نفسها — راجع [DeviceVitals.fetch].
          detailed: true,
        );
        // ── الكتابة في المخزن **قبل** حارس mounted ─────────────
        //
        // 🐛 كان `if (!mounted) return;` هنا يسبق الحفظ، فجلسةٌ اكتملت
        // بعد مغادرة المستخدم تُرمى كلّيّاً: لا حمولة ولا عيّنة. وستّ
        // جلساتٍ جارية (سقف المجدول) تُهدر هكذا في كلّ خروج.
        //
        // والأسوأ أنّ `ageOf` يبقى `null` لتلك الأجهزة، فيُعيدها
        // التسخين إلى الطابور عند العودة — جولةٌ ثانية على ما دُفع
        // ثمنه فعلاً.
        //
        // المخزن عالميٌّ لا علاقة له بالويدجت، فالكتابة فيه آمنةٌ بعد
        // التخلّص. والحارس يبقى — لكن قبل النشر في الواجهة وحده.
        if (r.raw != null) {
          // الرتبة تتبع ما طلبناه فعلاً — وإلّا ظننّا الخفيفة كاملةً
          // فعرضنا تفصيلاً فارغاً ولم تُرقَّ أبداً.
          DeviceStatsCache.instance
              .putRaw(widget.device.id, r.raw!, detailed: true);
        }
        // والقراءة المعروضة تُحفظ كذلك — بها يُبذَر رجوعُ المستخدم.
        DeviceStatsCache.instance
            .putVitals(widget.device.id, r.vitals, r.detail);

        _ownAt = DateTime.now();
        if (!mounted) return;
        // العيّنة تُحفظ **قبل** النشر: الجلسة القادمة تطرح منها.
        widget.onSample(r.counters);
        widget.onVitals(VitalsState(
          vitals: r.vitals,
          detail: r.detail,
          at: DateTime.now(),
        ));
      } catch (_) {
        if (!mounted) return;
        widget.onVitals(VitalsState(
          vitals: st.vitals,
          detail: st.detail,
          error: 'تعذّر الاتّصال',
          at: DateTime.now(),
        ));
      } finally {
        _inFlight = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VitalsState>(
      valueListenable: widget.vitals,
      builder: (_, st, __) => DeviceBigCard(
        device: widget.device,
        state: st,
        medianMs: widget.medianMs,
        onOpen: widget.onOpen,
        rows: widget.rows,
      ),
    );
  }
}
