import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/network_devices_api.dart';
import '../../../api/vsol_olt_api.dart';
import '../../../models/network_device.dart';
import '../../../services/device_stats_cache.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'expandable_section.dart';

/// لوحة مراقبة حيّة لـ**OLT من VSOL** عبر SNMP.
///
/// بنيتها من بنية اللوحات الأخرى: رأسٌ حيّ، ثمّ شريط الجهاز، ثمّ كروت
/// المقاييس، ثمّ أقسامٌ قابلة للطيّ. المستخدم ينتقل بين جهازٍ وآخر في
/// الشاشة نفسها، فاختلاف اللغة البصريّة يُقرأ عطلاً لا تنوّعاً.
///
/// وما يخصّ الـOLT وحده — منافذ PON والمشتركون — داخل القوالب نفسها.
class VsolLivePanel extends StatefulWidget {
  const VsolLivePanel({super.key, required this.device});
  final NetworkDevice device;

  @override
  State<VsolLivePanel> createState() => _VsolLivePanelState();
}

class _VsolLivePanelState extends State<VsolLivePanel>
    with WidgetsBindingObserver {
  VsolOltStats? _stats;
  String? _error;
  DateTime? _lastFetch;
  Timer? _timer;
  bool _loading = false;
  bool _monitoring = true;
  bool _foreground = true;
  int _gen = 0;

  bool _onlineOnly = false;
  String _query = '';

  /// اللقطة السابقة ولحظتُها — منهما يُحسب المعدّل.
  ///
  /// 🐛 بلاغ المستخدم ٢٠٢٦-١٠-٠١: «قيم الترفك مبالغ بيها ٣٧ كيكا».
  /// كانت البطاقة تعرض **المجموع التراكميّ** باسم «ترفك». وعلى هذا
  /// الجهاز عدّاداته ٣٢ بت تلتفّ عند ٤٫٢٩ جيجا، فالمجموع لم يكن
  /// مبالغاً فيه بل بلا معنى: موضعُ كلّ عدّادٍ في لفّته الحاليّة.
  /// والمعدّل من الفرق بين لقطتين يَسلم من ذلك — وهو المطلوب أصلاً.
  /// لقطتان سابقتان لا واحدة — واحدةٌ لكلّ إيقاع.
  ///
  /// ⚠️ الطبقة السريعة تنقل عدّادات المشتركين كما هي ولا تُجدّدها.
  /// فمقارنتها بلقطةٍ سريعةٍ أخرى تُعطي فرقاً صفريّاً لكلّ مشترك، ثمّ
  /// قفزةً حين تصل الطبقة الكاملة. فكلّ طبقةٍ تُقارَن بمثيلتها.
  VsolOltStats? _prevHot, _prevAll;
  DateTime? _prevHotAt, _prevAllAt;
  Map<String, VsolTraffic> _rates = const {};

  /// كم مسحةً خفيفةً مرّت منذ آخر مسحةٍ كاملة.
  ///
  /// الخفيفة تجلب العدّادين وحدهما (~١٠ث) والكاملة ستّة أعمدة (~٣١ث).
  /// فالترفك يتجدّد سريعاً، والبنية — حالة المشترك وظهور مشتركٍ جديد —
  /// تتجدّد كلّ خمس دورات.
  /// كلفة آخر دورةٍ خفيفة — أساس الإيقاع.
  Duration _lightCost = _minInterval;

  /// هل قرأنا البنية بأنفسنا في هذه الجلسة؟
  ///
  /// 🐛 بلاغ المستخدم ٢٠٢٦-١٠-٠١: «منافذ ومرور ما ظهر شي… أكو شي جاي
  /// يضرب على شي». كان الشرط `base == null` — والبذرة من المخزن تجعله
  /// غير فارغ، فلا تُطلَب مسحةٌ كاملة أصلاً. وبذرةٌ ناقصة (محفوظةٌ من
  /// لقطةٍ جزئيّة في تشغيلٍ سابق) تنتقل عبر الطبقة السريعة كما هي، ثمّ
  /// تُحفَظ في المخزن ثانيةً — حلقةٌ تُطعم نفسها ولا تُشفى إلّا بعد
  /// أربعٍ وعشرين دورة.
  ///
  /// **البذرة للعرض لا للبنية.** فأوّل جلبةٍ كاملةٌ دائماً.
  bool _haveStructure = false;

  /// وهل جلبنا الزينة — عناوين MAC والسرعات؟
  ///
  /// 🐛 بلاغ المستخدم ٢٠٢٦-١٠-٠١: «المشتركين مجاي يظهر الماك مالتهم».
  /// مسحة البنية تتخطّى عمود العناوين كي تصل في عشر ثوانٍ بدل أربعٍ
  /// وثلاثين، وكانت المسحة الكاملة تتأخّر أربعاً وعشرين دورة — فيبقى
  /// المشترك بلا عنوانٍ دقيقةً وأكثر.
  ///
  /// فترتيب الأولويّات: بنيةٌ ثمّ ترفك ثمّ عناوين. والعناوين تلحق بعد
  /// نبضتين لا بعد دورةٍ كاملة.
  bool _haveDetails = false;

  /// ترتيب الأولويّات بعد البنية: ترفك المنافذ، ثمّ ترفك المشتركين،
  /// ثمّ العناوين. فالتفاصيل تنتظر أربع نبضاتٍ لا نبضتين.
  static const _detailsAfter = 4;

  int _sinceFull = 0;
  int _sinceAll = 0;

  /// كلّ كم نبضةٍ نُجدّد عدّادات المشتركين، وكلّ كم نُعيد قراءة البنية.
  ///
  /// بنبضةٍ من ثلاث ثوانٍ: المشتركون كلّ ~٩ث، والبنية كلّ ~٧٢ث.
  static const _allEvery = 2;

  /// ⚠️ مسحة التفاصيل تُجمّد اللوحة ~١٩ ثانية، والعناوين والسرعات لا
  /// تتغيّر إلّا نادراً. فتُعاد كلّ خمس دقائق لا كلّ دقيقة.
  static const _fullEvery = 100;

  /// المسحة الكاملة تستغرق ~٢٫٢ ثانية على أولت فيه ٣٨ واجهة. فنبضةٌ
  /// أسرع من ذلك تُنتج طابوراً لا تحديثاً.
  static const _minInterval = Duration(seconds: 3);

  /// ⚠️ **الفاصل يتكيّف مع حجم الجهاز لا يُفرَض عليه.**
  ///
  /// 🐛 ٢٠٢٦-١٠-٠١ — أولتٌ ثانٍ فيه ٣٢٧ واجهة تستغرق مسحته ~٢٠ ثانية،
  /// فنبضةُ الاثنتي عشرة تَجِد الجلب السابق جارياً فتُلغى (`_loading`).
  /// النتيجة جلبٌ متّصل بلا انقطاع: شبكةٌ مشغولة دائماً، وبطّاريّةٌ
  /// تذوب، ولا تحديث أسرع — لأنّ الحدّ هو الجهاز لا المؤقّت.
  ///
  /// فنقيس ونُهلة: مرّةً ونصفاً من آخر مسحةٍ ناجحة، فيبقى للجهاز متنفَّس.
  Duration _interval = _minInterval;

  @override
  void initState() {
    super.initState();
    // ── بذرةٌ من المخزن ────────────────────────────────────────────
    //
    // ⚡ المسحة الكاملة على هذا الأولت ثلاثٌ وأربعون ثانية. وبلا بذرٍ
    // تُدفَع كاملةً في **كلّ** فتحةٍ للجهاز ولو أُغلق قبل ثوانٍ.
    //
    // (طلب المستخدم ٢٠٢٦-١٠-٠١: «أهمّ شي عندي سرعة الاستجابة وعرض
    // البيانات وتحديثها… وهلشي بجميع الأجهزة»)
    _stats = DeviceStatsCache.instance.seedFor<VsolOltStats>(widget.device.id);
    // وعمرُها معها: رقمٌ عمره دقيقةٌ تحت شارة «مباشر» كذبة.
    final age = DeviceStatsCache.instance.ageOf(widget.device.id);
    if (_stats != null && age != null) {
      _lastFetch = DateTime.now().subtract(age);
      // ⚡ والبذرة **لقطةٌ أولى** لا مجرّد صورةٍ تُعرَض: فأوّل دورةٍ
      // خفيفة (٧ث) تُنتج معدّلاً، بدل انتظار دورتين كاملتين.
      _prevHot = _prevAll = _stats;
      _prevHotAt = _prevAllAt = _lastFetch;
    }
    WidgetsBinding.instance.addObserver(this);
    _fetch();
    _arm();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _gen++;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    if (fg) {
      _fetch();
      _arm();
    } else {
      _timer?.cancel();
    }
  }

  void _arm() {
    _timer?.cancel();
    if (!_monitoring || !_foreground) return;
    // ⚡ ما دمنا بلا معدّلٍ بعد، فالنبضة التالية **فوريّة**: المعدّل
    // يحتاج قراءةً ثانية، وكلّ انتظارٍ هنا يُضاف إلى زمن ظهور أوّل
    // رقم. والقراءة السريعة ثانيةٌ واحدة.
    final gap = _rates.isEmpty && _stats != null ? Duration.zero : _interval;
    // مؤقّتٌ يُعيد تسليح نفسه — لأنّ الفاصل يتغيّر بعد كلّ مسحة.
    _timer = Timer(gap, () {
      _fetch();
      _arm();
    });
  }

  Future<void> _fetch() async {
    if (_loading) return;
    final d = widget.device;
    final gen = ++_gen;
    final clock = Stopwatch()..start();
    if (mounted) setState(() => _loading = true);

    try {
      final creds = await NetworkDevicesApi.getCredentials(d.id);
      if (!mounted || gen != _gen) return;
      // الـcommunity تُحفَظ تحت `community`، ويُقبل `pass` لمن أدخلها
      // في حقل كلمة المرور قبل أن يوجد الحقل المخصّص.
      final community =
          (creds['community'] ?? creds['pass'] ?? '').toString().trim();
      if (community.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'أدخل الـcommunity من إعدادات الجهاز';
        });
        return;
      }

      // ── ثلاث طبقاتٍ بحسب ما يُنظَر إليه ───────────────────────
      //
      // ⚡ الوكيل يعالج ~١٠٠ قيمةً في الثانية، فالتحديث الكامل لكلّ
      // الـ٣٢٥ واجهةً يكلّف ستّ ثوانٍ مهما فعلنا. والبطاقة ومنافذ PON
      // أربعٌ وعشرون واجهةً فقط — ثانيةٌ واحدة.
      //
      //   سريعة (كلّ نبضة)  : منافذ PON والصعود    ~١٫١ث
      //   كاملة العدّادات    : + الثلاثمئة مشترك    ~٦ث
      //   بنية (نادرة)      : أسماء وحالة وعناوين  ~٢١ث
      //
      // (بلاغ المستخدم ٢٠٢٦-١٠-٠١: «الترفك ما يتحدّث، يعني مو لحظي»)
      final base = _stats;
      final wantFull = base == null ||
          !_haveStructure ||
          (!_haveDetails && _sinceFull >= _detailsAfter) ||
          _sinceFull >= _fullEvery;
      final structureOnly = !_haveStructure;
      final wantAll = wantFull || _sinceAll >= _allEvery;
      // ⚡ أوّل مسحةٍ **بنيةٌ فقط** (‏٦ث): أسماءٌ وحالة، بلا عدّادات
      // ولا عناوين. العدّادات تأتي من الطبقة السريعة بعدها بثانية،
      // والعناوين والسرعات في المسحة الكاملة الدوريّة.
      final s = wantFull
          ? await VsolOltApi.fetchStats(
              host: d.ip,
              port: d.apiPort ?? 161,
              community: community,
              structureOnly: structureOnly,
              // العدّادات من الطبقتين الخفيفتين — أرخص وأحدث.
              withCounters: structureOnly,
              onPartialReady: (partial) {
                if (!mounted || gen != _gen) return;
                // ⚡ المسحة تبعث لقطتين: الهويّة (اسمٌ ورفع، صفر واجهات)
                // بعد ثانية، ثمّ الأسماء والحالة (‏٨ منافذ و٣٠١ مشترك)
                // بعد عشر. والعدّادات تأخذ إحدى عشرة أخرى.
                //
                // 🐛 بلاغ المستخدم ٢٠٢٦-١٠-٠١: «هيج صافن». كان الشرط
                // `_stats == null` فتملؤه لقطة الهويّة الفارغة، ثمّ
                // تُرفَض الغنيّة بعدها — فتبقى اللوحة «٠/٠» إحدى
                // وعشرين ثانيةً كاملة بلا سبب.
                //
                // والقاعدة الصحيحة: **لا نُفقر المعروض**. نقبل الأغنى
                // أيّاً كان ترتيبها — وهذا أيضاً يمنع لقطة الهويّة في
                // مسحةٍ دوريّةٍ لاحقة من محو لوحةٍ مكتملة.
                if (!VsolOltStats.richer(_stats, partial)) return;
                setState(() => _stats = partial);
                // ⚠️ ولا نتّخذها عيّنةً أولى للمعدّل.
                //
                // 🐛 جرّبتُ ذلك فأعطى `0.0 Mbps`: اللقطة والنتيجة
                // الكاملة تحملان **القراءة نفسها** (العمودان يُمسحان
                // مرّةً ثمّ يُبَثّان مرّتين)، فالفرق بينهما صفرٌ
                // بالضرورة. العيّنة الثانية لا بدّ أن تكون قراءةً
                // جديدة.
              },
            )
          : wantAll
              ? await VsolOltApi.refreshCounters(
                  host: d.ip,
                  port: d.apiPort ?? 161,
                  community: community,
                  previous: base,
                )
              : await VsolOltApi.refreshHotCounters(
                  host: d.ip,
                  port: d.apiPort ?? 161,
                  community: community,
                  previous: base,
                );
      if (!mounted || gen != _gen) return;
      final cost = clock.elapsed;
      final at = DateTime.now();
      // كلّ طبقةٍ تُقارَن بلقطتها، والنتيجة تُدمَج فوق السابقة: فصفوف
      // المشتركين تُبقي آخر معدّلٍ معروفٍ لها بدل أن تُصفَّر كلّ نبضة.
      // ⚠️ لقطةٌ بلا عدّادات ليست عيّنة. مسحة البنية تُرجع أصفاراً،
      // والطرح منها يُنتج العدّاد كلّه منذ الإقلاع — قفزةٌ كاذبة.
      final ref = wantAll ? _prevAll : _prevHot;
      final refAt = wantAll ? _prevAllAt : _prevHotAt;
      final rates = Map<String, VsolTraffic>.from(_rates);
      if (ref != null && refAt != null && ref.hasCounters) {
        final fresh = VsolTraffic.between(ref, s, at.difference(refAt));
        if (wantAll) {
          rates.addAll(fresh);
        } else {
          // 🐛 بلاغ المستخدم ٢٠٢٦-١٠-٠١: «المشتركون يظهر ترفك ويصير
          // صفر بسرعة، أمّا البونات طبيعي».
          //
          // ⚠️ الطبقة السريعة تنقل عدّادات المشتركين **كما هي**، فالفرق
          // عليها صفرٌ بالضرورة. وكنتُ أدمج ما تُرجعه كلَّه، فتمحو
          // أصفارُ المشتركين معدّلاتِهم الصحيحة كلّ ثلاث ثوانٍ — ثمّ
          // تعود مع الطبقة الكاملة، فتومض.
          //
          // فلا نكتب إلّا مفاتيح ما جُدّد فعلاً.
          for (final p in s.ponPorts) {
            final v = fresh[p.label];
            if (v != null) rates[p.label] = v;
          }
          for (final u in s.uplinks) {
            final v = fresh[u.name];
            if (v != null) rates[u.name] = v;
          }
        }
      }
      setState(() {
        _loading = false;
        _error = null;
        // لقطةٌ فارغة لا تُعرَض ولا تُحفَظ: تُبقى القراءة السابقة.
        if (!s.isEmpty || _stats == null) _stats = s;
        // ⚠️ لا نحفظ لقطةً ناقصة: بذرةٌ بلا واجهات تُعرَض «٠/٠» في
        // الفتحة التالية، وهي أسوأ من غياب البذرة.
        if (!s.isEmpty) {
          DeviceStatsCache.instance.putRaw(widget.device.id, s);
        }
        // ولا نحفظها عيّنةً للمرّة القادمة كذلك.
        if (s.hasCounters) {
          _prevHot = s;
          _prevHotAt = at;
          if (wantAll) {
            _prevAll = s;
            _prevAllAt = at;
          }
        }
        _rates = rates;
        // ولا نُعلن «عندنا بنية» على نتيجةٍ فارغة.
        if (wantFull && !s.isEmpty) {
          _haveStructure = true;
          if (!structureOnly) _haveDetails = true;
        }
        _sinceFull = wantFull ? 0 : _sinceFull + 1;
        _sinceAll = wantAll ? 0 : _sinceAll + 1;
        _lastFetch = at;
        // ⚠️ **الإيقاع من الدورة الخفيفة لا من الكاملة.**
        //
        // 🐛 بلاغ المستخدم ٢٠٢٦-١٠-٠١: «الترفك ما يتحدّث، يعني مو
        // لحظي». والسبب أنّي كنتُ أُسعّر الفاصل بكلفة **آخر** دورة؛
        // فبعد كلّ مسحةٍ كاملة (٤٣ث) يصير الفاصل ٦٤ ثانيةً فيتجمّد
        // العرض دقيقةً كاملة.
        //
        // والكاملة حدثٌ دوريّ نادر لا يصحّ أن يُملي إيقاع الشاشة،
        // فنُسعّر بالخفيفة وحدها — وهي التي تجلب الترفك أصلاً.
        // الإيقاع من الطبقة السريعة وحدها — وهي النبضة الفعليّة.
        if (!wantFull && !wantAll) _lightCost = cost;
        final paced = _lightCost * 1.5;
        _interval = paced > _minInterval ? paced : _minInterval;
      });
    } on VsolException catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _error = 'تعذّرت القراءة: $e';
      });
    }
  }

  // ══════════════════════════════════════════════════════════
  // البناء
  // ══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    if (s == null && _error == null) {
      return Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.brand),
          ),
          const SizedBox(width: 10),
          Text('جاري قراءة الـOLT…',
              style: AppType.body(color: AppColors.textMid)),
        ]),
      );
    }

    return Column(children: [
      Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          _header(),
          if (_error != null) _errorBox(),
          if (s != null) ...[
            RepaintBoundary(child: _banner(s)),
            RepaintBoundary(child: _metrics(s)),
            const SizedBox(height: Sp.md),
          ],
        ]),
      ),
      if (s != null) ..._sections(s),
    ]);
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.all(Sp.md),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.brandSoftBg,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(LucideIcons.activity, size: 16, color: AppColors.brand),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('مراقبة حيّة (OLT · SNMP)', style: AppType.bodyBold()),
              const SizedBox(height: 2),
              Row(children: [
                if (_monitoring) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: AppColors.success, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  _monitoring ? 'مباشر · كل ${_interval.inSeconds}s' : 'متوقّف',
                  style: TextStyle(
                      fontSize: 10.5, height: 1.3, color: AppColors.textMid),
                ),
                if (_lastFetch != null) ...[
                  Text(' • ',
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.3,
                          color: AppColors.textLow)),
                  Text('آخر: ${_clock(_lastFetch!)}',
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.3,
                          color: AppColors.textLow)),
                ],
              ]),
            ]),
          ),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            onPressed: _loading ? null : _fetch,
            tooltip: 'تحديث الآن',
            color: AppColors.brand,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: Icon(_monitoring ? LucideIcons.pause : LucideIcons.play,
                size: 16),
            onPressed: () {
              setState(() => _monitoring = !_monitoring);
              _arm();
              if (_monitoring) _fetch();
            },
            tooltip: _monitoring ? 'إيقاف' : 'استئناف',
            color: AppColors.textMid,
            visualDensity: VisualDensity.compact,
          ),
        ]),
      );

  Widget _errorBox() => Container(
        margin: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.md),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.dangerSoftBg,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.dangerSoftBorder),
        ),
        child: Row(children: [
          Icon(LucideIcons.triangleAlert, size: 14, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_error!, style: AppType.micro(color: AppColors.error)),
          ),
        ]),
      );

  Widget _banner(VsolOltStats s) => Container(
        margin: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.brandSoftBg,
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Row(children: [
          Icon(LucideIcons.server, size: 18, color: AppColors.brand),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                s.sysName?.isNotEmpty == true ? s.sysName! : widget.device.name,
                style: TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHi),
                overflow: TextOverflow.ellipsis,
              ),
              Text(s.sysDescr ?? 'VSOL OLT',
                  style: AppType.micro(color: AppColors.textMid),
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (s.uptime != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.brandSoftBg,
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.clock, size: 9, color: AppColors.brand),
                const SizedBox(width: 3),
                Text(_uptime(s.uptime!),
                    style: AppType.microBold(color: AppColors.brand)),
              ]),
            ),
        ]),
      );

  Widget _metrics(VsolOltStats s) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
                child: _tile(
              LucideIcons.users,
              'المشتركون',
              '${s.onusOnline}',
              '/${s.onusTotal}',
              s.onusOnline > 0 ? AppColors.success : AppColors.textLow,
            )),
            const SizedBox(width: 8),
            Expanded(
                child: _tile(
              LucideIcons.splitSquareVertical,
              'منافذ PON',
              '${s.ponUp}',
              '/${s.ponPorts.length}',
              AppColors.brand,
            )),
            const SizedBox(width: 8),
            Expanded(
                child: _tile(
              LucideIcons.arrowUpDown,
              // ⚠️ من منافذ PON لا من جمع المشتركين: ما يمرّ على ONU
              // يمرّ على منفذه، فجمعهما يعدّ البايت مرّتين.
              'مرور PON',
              _ponFlow(s),
              '',
              AppColors.brand,
            )),
          ]),
        ),
      );

  List<Widget> _sections(VsolOltStats s) {
    final shown = s.onus.where(_match).toList();
    return [
      if (s.ponPorts.isNotEmpty) ...[
        const SizedBox(height: Sp.md),
        ExpandableSection(
          key: PageStorageKey('vsol-${widget.device.id}-pon'),
          initiallyExpanded: true,
          header: Row(children: [
            Icon(LucideIcons.splitSquareVertical,
                size: 14, color: AppColors.brand),
            const SizedBox(width: 6),
            Text('منافذ PON (${s.ponUp}/${s.ponPorts.length})',
                style: AppType.bodyBold()),
          ]),
          content: RepaintBoundary(
            child: Column(children: [for (final p in s.ponPorts) _ponRow(p)]),
          ),
        ),
      ],
      const SizedBox(height: Sp.md),
      ExpandableSection(
        key: PageStorageKey('vsol-${widget.device.id}-onu'),
        initiallyExpanded: true,
        header: Row(children: [
          Icon(LucideIcons.users, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('المشتركون (${shown.length})', style: AppType.bodyBold()),
        ]),
        content: RepaintBoundary(child: _onuContent(shown)),
      ),
      if (s.uplinks.isNotEmpty) ...[
        const SizedBox(height: Sp.md),
        ExpandableSection(
          key: PageStorageKey('vsol-${widget.device.id}-up'),
          header: Row(children: [
            Icon(LucideIcons.network, size: 14, color: AppColors.brand),
            const SizedBox(width: 6),
            Text(
                'منافذ الصعود (${s.uplinks.where((u) => u.up).length}'
                '/${s.uplinks.length})',
                style: AppType.bodyBold()),
          ]),
          content: Column(children: [for (final u in s.uplinks) _upRow(u)]),
        ),
      ],
    ];
  }

  bool _match(VsolOnu o) {
    if (_onlineOnly && !o.online) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '${o.label} ${o.mac ?? ''}'.toLowerCase().contains(q);
  }

  Widget _ponRow(VsolPonPort p) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            width: 4,
            height: 26,
            decoration: BoxDecoration(
              color: p.up ? AppColors.success : AppColors.textLow,
              borderRadius: BorderRadius.circular(R.sm),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.label, style: AppType.rowLabelBold()),
              Text('${p.onuOnline}/${p.onuTotal} مشترك',
                  style: AppType.micro(color: AppColors.textMid)),
            ]),
          ),
          _flow(p.label),
        ]),
      );

  Widget _onuContent(List<VsolOnu> shown) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 34,
                child: TextField(
                  style: AppType.micro(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'ابحث برقم المشترك أو MAC…',
                    hintStyle: AppType.micro(color: AppColors.textLow),
                    prefixIcon: Icon(LucideIcons.search,
                        size: 14, color: AppColors.textLow),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.sm),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: Text('المتّصلون', style: AppType.micro()),
              selected: _onlineOnly,
              onSelected: (v) => setState(() => _onlineOnly = v),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('لا مشتركين مطابقين',
                  style: AppType.micro(color: AppColors.textLow)),
            )
          else
            for (final o in shown) _onuRow(o),
        ],
      );

  Widget _onuRow(VsolOnu o) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            width: 4,
            height: 26,
            decoration: BoxDecoration(
              color: o.online ? AppColors.success : AppColors.textLow,
              borderRadius: BorderRadius.circular(R.sm),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(o.label,
                    textAlign: TextAlign.left, style: AppType.rowLabelBold()),
              ),
              // العنوان للمتّصل وحده — انظر `VsolOnu.mac`.
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  o.mac ?? (o.online ? '—' : 'غير متّصل'),
                  textAlign: TextAlign.left,
                  style: AppType.micro(color: AppColors.textLow),
                ),
              ),
            ]),
          ),
          if (o.online) _flow(o.label),
        ]),
      );

  Widget _upRow(VsolUplink u) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: u.up ? AppColors.success : AppColors.textLow,
              borderRadius: BorderRadius.circular(R.sm),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(u.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.rowLabelBold()),
          ),
          if (u.up) ...[
            _flow(u.name),
            const SizedBox(width: 8),
          ],
          Text(u.up ? '${u.speedMbps}M' : '—',
              style: AppType.microBold(
                  color: u.up ? AppColors.textMid : AppColors.textLow)),
        ]),
      );

  Widget _tile(IconData icon, String label, String value, String unit,
          Color color) =>
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.microBold(color: AppColors.textMid)),
              ),
            ]),
            const SizedBox(height: 6),
            // اتّجاهٌ لاتينيٌّ مفروض — وإلّا رُسمت «13/26» مقلوبةً
            // في صفحةٍ عربيّة.
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            color: color)),
                  ),
                  if (unit.isNotEmpty) Text(unit, style: AppType.muted()),
                ],
              ),
            ),
          ],
        ),
      );

  // ══════════════════════════════════════════════════════════
  // تنسيق
  // ══════════════════════════════════════════════════════════

  /// «٦٨ يوماً و٢ ساعة» — تُقرأ ولا تُفكّ.
  static String _uptime(Duration d) {
    if (d.inDays > 0) {
      final h = d.inHours % 24;
      return h > 0 ? '${d.inDays}ي $hس' : '${d.inDays} يوماً';
    }
    if (d.inHours > 0) return '${d.inHours}س ${d.inMinutes % 60}د';
    return '${d.inMinutes} دقيقة';
  }

  /// معدّلٌ بالبت في الثانية ← نصّ. و`null` تُكتب «—» لا صفراً:
  /// «لا نعرف» ليست «لا مرور».
  static String _rate(double? bps) {
    if (bps == null) return '—';
    const u = ['bps', 'Kbps', 'Mbps', 'Gbps'];
    var v = bps;
    var i = 0;
    while (v >= 1000 && i < u.length - 1) {
      v /= 1000;
      i++;
    }
    return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${u[i]}';
  }

  /// مجموع معدّلات منافذ PON — المعروفُ منها وحده.
  ///
  /// إن جهلنا بعضها (عدّادٌ التفّ بين لقطتين) نقول «جزئيّ» بدل أن
  /// نجمع ما نعرف ونُقدّمه مجموعاً كاملاً.
  String _ponFlow(VsolOltStats s) {
    if (_rates.isEmpty) return '…';
    var total = 0.0;
    var unknown = 0;
    for (final p in s.ponPorts) {
      final t = _rates[p.label];
      if (t == null || !t.known) {
        unknown++;
        continue;
      }
      total += t.rxBps! + t.txBps!;
    }
    if (unknown == s.ponPorts.length) return '—';
    return unknown == 0 ? _rate(total) : '${_rate(total)} (جزئيّ)';
  }

  /// سطرا الوارد والصادر — معدّلاً إن عرفناه، وإلّا «…» حتّى اللقطة
  /// الثانية.
  Widget _flow(String key) {
    final t = _rates[key];
    // ⚠️ **الاتّجاه من زاوية المشترك لا من زاوية الأولت.**
    //
    // `ifOutOctets` هو ما يُرسله الأولت نزولاً إلى الـONU — أي
    // **تنزيل** المشترك. و`ifInOctets` ما يصعد منه — أي **رفعه**.
    // قياسٌ فعليّ ٢٠٢٦-١٠-٠١ يؤكّده: `EPON0/1` خرج ٤٥ ميجابت ودخل
    // ٣٫١ — وهي نسبة الاستهلاك المنزليّ المعروفة، معكوسةً لو قرأناها
    // بالمقلوب.
    //
    // (بلاغ المستخدم على لوحة روجي ٢٠٢٦-٠٩-٢٨: «خابط أعلى أبلود
    // وعلى داونلود وهلشي خطأ»)
    Widget line(String tag, double? bps, Color c) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tag, style: AppType.micro(color: AppColors.textLow)),
            const SizedBox(width: 3),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(t == null ? '…' : _rate(bps),
                  style: AppType.micro(color: c)),
            ),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        line('▼ تنزيل', t?.txBps, AppColors.success),
        line('▲ رفع', t?.rxBps, AppColors.brand),
      ],
    );
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}
