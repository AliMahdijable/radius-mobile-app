import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/bdcom_epon.dart';
import '../../../api/bridge_fdb.dart';
import '../../../api/network_devices_api.dart';
import '../../../api/olt_profile.dart';
import '../../../api/vsol_olt_api.dart';
import '../../../api/snmp_client.dart';
import '../../../api/vsol_gpon_details.dart';
import '../../../models/network_device.dart';
import '../../../services/device_stats_cache.dart';
import '../../../services/fiber/fiber_band.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'expandable_section.dart';
import '../../desktop/desk_widgets.dart';
import '../../../core/util/bidi.dart';
import '_grade.dart';
import 'desk_device_kit.dart';
import '../../../core/platform/desktop_layout.dart';
import '../../../core/widgets/copyable.dart';

/// لوحة مراقبة حيّة لـ**OLT** ‏(VSOL وBDCOM EPON) عبر SNMP.
///
/// المصنّع من [OltProfile]: السجلّ أوّلاً ثمّ الهويّة الحيّة. ولكلٍّ جداوله:
/// VSOL GPON جدول ماكاته (`37950`)، وBDCOM ماك الـONU وقراءات الضوء والمعالج
/// من جداوله، وأجهزة المشترك خلف الـONU من جدول الجسر — كلّها في الخلفيّة
/// على إيقاعٍ بطيء، لا في كلّ نبضة.
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

  VsolGponSnapshot? _gponDetails;
  DateTime? _gponDetailsAt;
  bool _gponDetailsLoading = false;

  /// المصنّع: من السجلّ قبل أيّ قراءة، ثمّ من هويّة الجهاز الحيّة.
  late OltProfile _profile = OltProfile.fromDevice(widget.device);

  /// تفاصيل EPON البطيئة (ماك الـONU والضوء والمعالج لـBDCOM، وأجهزة
  /// المشترك من جدول الجسر) — تُدمج فوق كلّ لقطةٍ جديدة.
  OltEponDetails _epon = const OltEponDetails();
  bool _eponLoading = false;

  bool _onlineOnly = false;
  String _query = '';
  final _onuScroll = ScrollController();

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
    // والمصنّع من البذرة إن عرفته هويّةٌ حيّة سابقة — فلا تنتظر جداوله القراءة الأولى.
    if (_stats?.profile.identified ?? false) _profile = _stats!.profile;
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
    _onuScroll.dispose();
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
    final gap = _rates.isEmpty && _stats != null && !_loading && _error == null
        ? Duration.zero
        : _interval;
    // Await the read before rearming, including while the first rate is pending.
    _timer = Timer(gap, () async {
      await _fetch();
      if (mounted) _arm();
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
      var s = wantFull
          ? await VsolOltApi.fetchStats(
              host: d.ip,
              port: d.apiPort ?? 161,
              community: community,
              structureOnly: structureOnly,
              // العدّادات من الطبقتين الخفيفتين — أرخص وأحدث.
              withCounters: structureOnly,
              withGponDetails: false,
              profile: _profile,
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
                if (partial.profile.identified) _profile = partial.profile;
                if (!VsolOltStats.richer(_stats, partial)) return;
                setState(() => _stats = _withDetails(partial));
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
      if (s.profile.identified) _profile = s.profile;
      s = _withDetails(s);
      final cost = clock.elapsed;
      final at = DateTime.now();
      // كلّ طبقةٍ تُقارَن بلقطتها، والنتيجة تُدمَج فوق السابقة: فصفوف
      // المشتركين تُبقي آخر معدّلٍ معروفٍ لها بدل أن تُصفَّر كلّ نبضة.
      // ⚠️ لقطةٌ بلا عدّادات ليست عيّنة. مسحة البنية تُرجع أصفاراً،
      // والطرح منها يُنتج العدّاد كلّه منذ الإقلاع — قفزةٌ كاذبة.
      final ref = wantAll ? _prevAll : _prevHot;
      final refAt = wantAll ? _prevAllAt : _prevHotAt;
      final rates = Map<String, VsolTraffic>.from(_rates);
      if (ref != null && refAt != null && ref.hasCounters && s.hasCounters) {
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
        _samplePon(s, fresh, at);
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
      unawaited(_refreshGponDetails(community));
      unawaited(_refreshEponDetails(community));
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

  /// رسم الحاسبة: مجموع منافذ PON العاملة في كلّ قراءة — والتنزيل ما يُرسله الأولت (انظر [_flow]).
  /// منفذٌ واحدٌ مجهول المعدّل ⇒ لا عيّنة: جمعُ بعضها يرسم هبوطاً لم يحدث.
  final List<({DateTime at, int down, int up})> _history = [];
  static const int _maxHistory = 60;

  void _samplePon(VsolOltStats s, Map<String, VsolTraffic> fresh, DateTime at) {
    var down = 0.0, up = 0.0, any = false;
    for (final p in s.ponPorts) {
      if (!p.up) continue;
      final t = fresh[p.label];
      if (t == null || !t.known) return;
      down += t.txBps!;
      up += t.rxBps!;
      any = true;
    }
    if (!any) return;
    _history.add((at: at, down: down.round(), up: up.round()));
    if (_history.length > _maxHistory) _history.removeAt(0);
  }

  VsolOltStats _withDetails(VsolOltStats stats) {
    final details = _gponDetails;
    final at = _gponDetailsAt;
    final g = details == null || at == null
        ? stats
        : stats.withGponDetails(details, at);
    return g.withEponDetails(_epon);
  }

  Future<void> _refreshGponDetails(String community) async {
    // ⚠️ جدول VSOL ‏(`37950`) لـVSOL وحدها — لا يُسأل عنه BDCOM GPON.
    if (_gponDetailsLoading ||
        !_foreground ||
        !_profile.readsVsolTables ||
        !(_stats?.onus.any((o) => o.technology == VsolPonTechnology.gpon) ??
            false)) {
      return;
    }
    final age = _gponDetailsAt;
    final interval = _gponDetails?.macsComplete == true
        ? const Duration(minutes: 5)
        : const Duration(seconds: 30);
    if (age != null && DateTime.now().difference(age) < interval) return;
    setState(() => _gponDetailsLoading = true);
    final d = widget.device;
    try {
      final details = await VsolGponDetails.fetch(
        SnmpV2c(host: d.ip, port: d.apiPort ?? 161, community: community),
        isCancelled: () => !mounted || !_foreground,
      );
      if (!mounted) return;
      setState(() {
        _gponDetails = details;
        _gponDetailsAt = DateTime.now();
        // Counter polling may have finished while the MAC table was loading.
        // Enrich the latest sample, never restore the one we started with.
        if (_stats != null) {
          _stats = _withDetails(_stats!);
          DeviceStatsCache.instance.putRaw(d.id, _stats!);
        }
      });
    } finally {
      if (mounted) setState(() => _gponDetailsLoading = false);
    }
  }

  // ── EPON: كلّ قارئٍ على إيقاعه ────────────────────────────────────
  //
  // ⚡ لا شيء منها في النبضة: ماك الـONU لا يتغيّر إلّا باستبدال الوحدة
  // (كلّ ٥ دقائق أو حين تظهر ONU جديدة)، والضوء كلّ دقيقة للمتّصلين،
  // والمعالج كلّ ٣٠ث، وجدول الجسر كلّ ٥ دقائق (دقيقةٌ إن جاء ناقصاً).
  static const _macsEvery = Duration(minutes: 5);
  static const _readingsEvery = Duration(seconds: 60);
  static const _chassisEvery = Duration(seconds: 30);
  static const _fdbEvery = Duration(minutes: 5);
  static const _fdbRetry = Duration(seconds: 60);

  /// جهازٌ لا يكشف جدول الجسر: لا نُعيد السؤال قبل نصف ساعة.
  static const _fdbUnsupportedRetry = Duration(minutes: 30);

  bool _due(DateTime? at, Duration every) =>
      at == null || DateTime.now().difference(at) >= every;

  Future<void> _refreshEponDetails(String community) async {
    final st = _stats;
    if (_eponLoading || !_foreground || st == null) return;
    final epon = [
      for (final o in st.onus)
        if (o.technology == VsolPonTechnology.epon) o,
    ];
    final bdcom = _profile.readsBdcomEponTables;
    // جدول الجسر قياسيّ: BDCOM (مثبت) وVSOL EPON (ما يربطه الجدول بـONU
    // بعينها وحده — وإلّا فلا شيء).
    if (epon.isEmpty || _profile.vendor == OltVendor.unknown) return;
    final known = {for (final o in epon) o.ifIndex};
    final newOnus = bdcom && known.any((i) => !_epon.onuMacs.containsKey(i)) &&
        _due(_epon.macsAt, const Duration(seconds: 45));
    final wantMacs = bdcom && (newOnus || _due(_epon.macsAt, _macsEvery));
    final wantReadings = bdcom && _due(_epon.readingsAt, _readingsEvery);
    final wantChassis = bdcom && _due(_epon.chassisAt, _chassisEvery);
    final fdbEvery = !_epon.fdb.supported && _epon.fdbAt != null
        ? _fdbUnsupportedRetry
        : (_epon.fdb.complete ? _fdbEvery : _fdbRetry);
    var wantFdb = _due(_epon.fdbAt, fdbEvery);
    if (!wantMacs && !wantReadings && !wantChassis && !wantFdb) return;
    // ⚡ **قارئٌ ثقيلٌ واحدٌ في كلّ دورة** (والمعالج الرخيص معه): وكيل SNMP
    // يعالج ~١٠٠ قيمةً في الثانية، فثلاثة قرّاءٍ معاً يُبطئون نبضة الترفك
    // التي يراها المشغّل. والدورة تتكرّر بعد كلّ نبضة (~٣ث)، فيلحق الباقي.
    // الترتيب: ماك الـONU، ثمّ الضوء، ثمّ أجهزة المشترك.
    var wantReadingsNow = wantReadings;
    if (wantMacs) {
      wantReadingsNow = false;
      wantFdb = false;
    } else if (wantReadingsNow) {
      wantFdb = false;
    }

    setState(() => _eponLoading = true);
    final d = widget.device;
    final snmp = SnmpV2c(host: d.ip, port: d.apiPort ?? 161, community: community);
    bool cancelled() => !mounted || !_foreground;
    try {
      var next = _epon;
      if (wantChassis) {
        final c = await BdcomEpon.chassis(snmp);
        next = next.copyWith(chassis: c, chassisAt: DateTime.now());
      }
      if (wantMacs && !cancelled()) {
        final macs = await BdcomEpon.onuMacs(snmp, known, isCancelled: cancelled);
        final online = [for (final o in epon) if (o.online) o.ifIndex];
        final ids = await BdcomEpon.identities(snmp, online, isCancelled: cancelled);
        // لا نمسح ما عرفناه بفراغ: دفعةٌ لم تُجب لا تمحو ماكاً قرأناه قبل دقائق.
        next = next.copyWith(
          onuMacs: {...next.onuMacs, ...macs},
          identities: {...next.identities, ...ids},
          macsAt: DateTime.now(),
        );
      }
      if (wantReadingsNow && !cancelled()) {
        final online = [for (final o in epon) if (o.online) o.ifIndex];
        final r = await BdcomEpon.readings(snmp, online, isCancelled: cancelled);
        next = next.copyWith(readings: r, readingsAt: DateTime.now());
      }
      if (wantFdb && !cancelled()) {
        final f = await BridgeFdb.fetch(snmp, targets: known, isCancelled: cancelled);
        // مسحٌ ناقص لا يمحو آخر لقطةٍ كاملة: نُبقي الكاملة ونعيد بعد دقيقة.
        final keep = !f.complete && _epon.fdb.complete && f.supported;
        next = keep
            ? next.copyWith(fdbAt: _epon.fdbAt)
            : next.copyWith(fdb: f, fdbAt: DateTime.now());
      }
      if (!mounted) return;
      setState(() {
        _epon = next;
        if (_stats != null) {
          _stats = _withDetails(_stats!);
          DeviceStatsCache.instance.putRaw(d.id, _stats!);
        }
      });
    } catch (_) {
      // تفاصيل اختياريّة — اللوحة الأساسيّة تبقى صحيحة بدونها.
    } finally {
      if (mounted) setState(() => _eponLoading = false);
    }
  }

  void _refreshManually() {
    _gponDetailsAt = null;
    _epon = OltEponDetails(
      onuMacs: _epon.onuMacs,
      identities: _epon.identities,
      fdb: _epon.fdb,
    );
    _sinceFull = _fullEvery;
    _fetch();
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

    if (s != null && DesktopScope.of(context)) return _deskBuild(s);

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
            if (s.chassis != null && !s.chassis!.isEmpty) _chassis(s.chassis!),
            const SizedBox(height: Sp.md),
          ],
        ]),
      ),
      if (s != null) ..._sections(s),
    ]);
  }

  Widget _header({EdgeInsetsGeometry padding = const EdgeInsets.all(Sp.md)}) => Padding(
        padding: padding,
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
            onPressed: _loading ? null : _refreshManually,
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

  Widget _errorBox({EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.md)}) => Container(
        margin: margin,
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
              Text(s.sysDescr ?? _profile.label,
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

  /// المعالج والحرارة والذاكرة (BDCOM) — ما قُرئ وحده. والذاكرة إجماليٌّ
  /// لا نسبة: used/free غير متوفّرين على هذه البرمجيّة.
  Widget _chassis(BdcomChassis c) {
    Widget chip(IconData icon, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: AppColors.textMid),
            const SizedBox(width: 4),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(text, style: AppType.microBold(color: AppColors.textHi)),
            ),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, 8, Sp.md, 0),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        if (c.cpuPct != null) chip(LucideIcons.cpu, 'CPU ${c.cpuPct}%'),
        if (c.boxTempC != null) chip(LucideIcons.thermometer, '${c.boxTempC}°C'),
        if (c.ramBytes != null)
          chip(LucideIcons.memoryStick, 'RAM ${(c.ramBytes! / (1024 * 1024)).round()} MB'),
      ]),
    );
  }

  List<Widget> _sections(VsolOltStats s) {
    // Keep each subscriber's position in PON/ONU order when filtering.
    final shown = s.onus.indexed.where((entry) => _match(entry.$2)).toList();
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
            child: DeskRows(children: [for (final p in s.ponPorts) _ponRow(p)]),
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
          content: DeskRows(children: [for (final u in s.uplinks) _upRow(u)]),
        ),
      ],
      // مواصفات الطراز من صفحة المصنّع — منفصلةٌ عن قراءات الجهاز عمداً.
      if (_profile.catalogSpecs != null) ...[
        const SizedBox(height: Sp.md),
        ExpandableSection(
          key: PageStorageKey('vsol-${widget.device.id}-specs'),
          header: Row(children: [
            Icon(LucideIcons.info, size: 14, color: AppColors.brand),
            const SizedBox(width: 6),
            Text('مواصفات الطراز ${_profile.model ?? ''}', style: AppType.bodyBold()),
          ]),
          content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final line in _profile.catalogSpecs!)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $line', style: AppType.micro(color: AppColors.textMid)),
              ),
            const SizedBox(height: 2),
            Text('من صفحة المصنّع — ليست قراءةً من الجهاز',
                style: AppType.micro(color: AppColors.textLow)),
          ]),
        ),
      ],
    ];
  }

  // ══════════════════════════════════════════════════════════════
  // الحاسبة — كصفحة المايكروتك: الحقائق في شريط، والأرقام كبيرةً في صفّ، ومرور PON برسمٍ بنافذةٍ ثابتة،
  // ومنافذ PON والصعود جدولين جنباً إلى جنب، والمشتركون جدولاً طويلاً تُبنى صفوفه الظاهرة وحدها
  // (المالك ٢٤ أكتوبر: «بشكل حاسبة وليس موبايل»). الهاتف كما هو.
  // ══════════════════════════════════════════════════════════════
  Widget _deskBuild(VsolOltStats s) {
    final flow = _ponTotals(s);
    final ch = s.chassis;
    final offline = s.onusTotal - s.onusOnline;
    final techs = {for (final p in s.ponPorts) p.technology.prefix, for (final o in s.onus) o.technology.prefix}.toList()..sort();
    final descr = s.sysDescr?.split('\n').first.trim();
    final interval = _history.length >= 2
        ? _history.last.at.difference(_history.first.at) ~/ (_history.length - 1)
        : _interval;
    return Column(children: [
      DeskPanelCard(children: [
        _header(padding: EdgeInsets.zero),
        if (_error != null) _errorBox(margin: EdgeInsets.zero),
        DeskFactsBanner(facts: [
          (icon: LucideIcons.server, label: 'الاسم', value: s.sysName?.isNotEmpty == true ? s.sysName! : widget.device.name),
          (icon: LucideIcons.tag, label: 'الطراز', value: _profile.model ?? widget.device.model ?? _profile.label),
          if (descr != null && descr.isNotEmpty)
            (icon: LucideIcons.package, label: 'النظام', value: descr.length > 48 ? '${descr.substring(0, 47)}…' : descr),
          if (s.uptime != null) (icon: LucideIcons.clock, label: 'يعمل منذ', value: deskUptimeAr(s.uptime!)),
          if (techs.isNotEmpty) (icon: LucideIcons.layers, label: 'التقنية', value: techs.join(' · ')),
        ]),
        DeskTilesRow(tiles: [
          DeskMetricTile(
            icon: LucideIcons.users,
            label: 'المشتركون',
            color: s.onusOnline > 0 ? AppColors.success : AppColors.textLow,
            value: DeskBigValue('${s.onusOnline}/${s.onusTotal}', '', color: s.onusOnline > 0 ? AppColors.success : null),
            footer: deskSub(offline == 0 ? 'كلّهم متّصلون' : 'غير متّصل $offline',
                color: offline > 0 ? AppColors.warningFill : null),
          ),
          DeskMetricTile(
            icon: LucideIcons.splitSquareVertical,
            label: 'منافذ PON',
            color: AppColors.brand,
            value: DeskBigValue('${s.ponUp}/${s.ponPorts.length}', '', color: AppColors.brand),
            footer: deskSub(s.ponUp == s.ponPorts.length ? 'كلّها تعمل' : 'متوقّف ${s.ponPorts.length - s.ponUp}'),
          ),
          DeskRateTile(
            down: true,
            bps: flow?.down,
            label: 'تنزيل المشتركين',
            measuring: _rates.isEmpty,
            note: flow == null ? null : (flow.partial ? 'جزئيّ — منفذٌ لم يُقرأ' : 'مجموع منافذ PON'),
          ),
          DeskRateTile(
            down: false,
            bps: flow?.up,
            label: 'رفع المشتركين',
            measuring: _rates.isEmpty,
            note: flow == null ? null : (flow.partial ? 'جزئيّ — منفذٌ لم يُقرأ' : 'مجموع منافذ PON'),
          ),
          if (ch != null && !ch.isEmpty) ...[
            DeskPercentTile(
              icon: LucideIcons.cpu,
              label: 'المعالج',
              percent: ch.cpuPct?.toDouble(),
              sub: ch.ramBytes != null ? 'الذاكرة ${iso(deskBytesShort(ch.ramBytes!))}' : null,
            ),
            DeskTempTile(celsius: ch.boxTempC, label: 'حرارة الجهاز'),
          ] else if (s.uplinks.isNotEmpty)
            DeskMetricTile(
              icon: LucideIcons.network,
              label: 'منافذ الصعود',
              color: AppColors.brand,
              value: DeskBigValue('${s.uplinks.where((u) => u.up).length}/${s.uplinks.length}', '', color: AppColors.brand),
              footer: deskSub('تعمل'),
            ),
        ]),
        DeskTrafficCard(
          samples: [for (final h in _history) (rx: h.down, tx: h.up)],
          capacity: _maxHistory,
          interval: interval,
          subtitle: 'مجموع منافذ PON',
        ),
      ]),
      const SizedBox(height: Sp.md),
      deskSideBySide(
        s.ponPorts.isEmpty
            ? null
            : ExpandableSection(
                key: PageStorageKey('vsol-${widget.device.id}-pon'),
                initiallyExpanded: true,
                header: DeskSectionHeader(
                    icon: LucideIcons.splitSquareVertical,
                    title: 'منافذ PON',
                    count: s.ponPorts.length,
                    hint: 'تعمل ${s.ponUp}'),
                content: RepaintBoundary(child: _deskPonTable(s.ponPorts)),
              ),
        s.uplinks.isEmpty
            ? null
            : ExpandableSection(
                key: PageStorageKey('vsol-${widget.device.id}-up'),
                initiallyExpanded: true,
                header: DeskSectionHeader(icon: LucideIcons.network, title: 'منافذ الصعود', count: s.uplinks.length),
                content: _deskUplinksTable(s.uplinks),
              ),
      ),
      const SizedBox(height: Sp.md),
      ExpandableSection(
        key: PageStorageKey('vsol-${widget.device.id}-onu'),
        initiallyExpanded: true,
        header: DeskSectionHeader(
          icon: LucideIcons.users,
          title: 'المشتركون',
          count: s.onus.indexed.where((e) => _match(e.$2)).length,
          hint: 'متّصلٌ الآن ${s.onusOnline}',
        ),
        content: RepaintBoundary(child: _deskOnuContent(s)),
      ),
      if (_profile.catalogSpecs != null) ...[
        const SizedBox(height: Sp.md),
        ExpandableSection(
          key: PageStorageKey('vsol-${widget.device.id}-specs'),
          initiallyExpanded: false,
          header: DeskSectionHeader(
              icon: LucideIcons.info, title: 'مواصفات الطراز ${_profile.model ?? ''}', hint: 'من صفحة المصنّع'),
          content: DeskFactsGrid(facts: [
            for (final line in _profile.catalogSpecs!)
              Text('• $line', style: AppType.body(color: AppColors.textBody)),
          ]),
        ),
      ],
    ]);
  }

  /// مجموع معدّلات منافذ PON العاملة: التنزيل (ما يُرسله الأولت) والرفع، و«جزئيّ» إن جُهل بعضها.
  ({int down, int up, bool partial})? _ponTotals(VsolOltStats s) {
    if (_rates.isEmpty) return null;
    var down = 0.0, up = 0.0;
    var known = 0, unknown = 0;
    for (final p in s.ponPorts) {
      final t = _rates[p.label];
      if (t == null || !t.known) {
        if (p.up) unknown++;
        continue;
      }
      down += t.txBps!;
      up += t.rxBps!;
      known++;
    }
    if (known == 0) return null;
    return (down: down.round(), up: up.round(), partial: unknown > 0);
  }

  Widget _deskPonTable(List<VsolPonPort> ports) {
    int maxDown = 0, maxUp = 0;
    for (final p in ports) {
      final t = _rates[p.label];
      if (t != null && t.known) {
        maxDown = math.max(maxDown, t.txBps!.round());
        maxUp = math.max(maxUp, t.rxBps!.round());
      }
    }
    return DeskTable(
      columns: const [('المنفذ', 3), ('المشتركون', 3), ('تنزيل ↓', 3), ('رفع ↑', 3)],
      rows: [
        for (final p in ports)
          () {
            final t = _rates[p.label];
            return <Widget>[
              DeskNameCell(
                name: p.label,
                sub: p.up ? 'يعمل' : 'متوقّف',
                tone: p.up ? AppTone.success : AppTone.neutral,
                dim: !p.up,
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(iso('${p.onuOnline}/${p.onuTotal}'), style: AppType.rowValue(color: AppColors.textHi)),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(R.pill),
                  child: LinearProgressIndicator(
                    value: p.onuTotal > 0 ? (p.onuOnline / p.onuTotal).clamp(0.0, 1.0) : 0,
                    minHeight: 4,
                    backgroundColor: AppColors.borderSoft,
                    valueColor: AlwaysStoppedAnimation(AppColors.success),
                  ),
                ),
              ]),
              DeskRateCell(bps: p.up ? t?.txBps?.round() : null, down: true, max: maxDown, live: p.up),
              DeskRateCell(bps: p.up ? t?.rxBps?.round() : null, down: false, max: maxUp, live: p.up),
            ];
          }(),
      ],
    );
  }

  /// منافذ الصعود من زاوية الأولت: الوارد من الشبكة والصادر إليها — لا «تنزيل/رفع» مشتركٍ هنا.
  Widget _deskUplinksTable(List<VsolUplink> rows) {
    return DeskTable(
      columns: const [('المنفذ', 3), ('السرعة', 2), ('وارد', 3), ('صادر', 3)],
      rows: [
        for (final u in rows)
          () {
            final t = _rates[u.name];
            return <Widget>[
              DeskNameCell(name: u.name, sub: u.up ? 'يعمل' : 'متوقّف', tone: u.up ? AppTone.success : AppTone.neutral, dim: !u.up),
              u.up && u.speedMbps > 0
                  ? Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: DeskPill(u.speedMbps >= 1000 ? '${u.speedMbps ~/ 1000}G' : '${u.speedMbps}M',
                          Grade.speedMbps(u.speedMbps)))
                  : deskDash(),
              DeskRateCell(bps: u.up ? t?.rxBps?.round() : null, down: true, max: 0, live: u.up),
              DeskRateCell(bps: u.up ? t?.txBps?.round() : null, down: false, max: 0, live: u.up),
            ];
          }(),
      ],
    );
  }

  Widget _deskOnuContent(VsolOltStats s) {
    final shown = s.onus.indexed.where((e) => _match(e.$2)).toList();
    final optics = s.onus.any((o) => o.reading?.rxDbm != null);
    final learned = s.onus.any((o) => o.online && _showsLearned(o));
    int maxDown = 0, maxUp = 0;
    for (final (_, o) in shown) {
      final t = _rates[o.label];
      if (t != null && t.known) {
        maxDown = math.max(maxDown, t.txBps!.round());
        maxUp = math.max(maxUp, t.rxBps!.round());
      }
    }
    final columns = <(String, int)>[
      ('#', 1),
      ('الـONU', 5),
      ('ماك الـONU / الرقم', 4),
      if (optics) ('الضوء', 3),
      ('تنزيل ↓', 3),
      ('رفع ↑', 3),
      if (learned) ('أجهزة خلفها', 2),
    ];
    final h = MediaQuery.sizeOf(context).height;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DeskPortFilterBar(
        hint: 'ابحث بالاسم أو ONU أو MAC أو SN…',
        chipLabel: 'المتّصلون فقط',
        connectedOnly: _onlineOnly,
        onQuery: (v) {
          if (_onuScroll.hasClients) _onuScroll.jumpTo(0);
          setState(() => _query = v);
        },
        onConnectedOnly: (v) {
          if (_onuScroll.hasClients) _onuScroll.jumpTo(0);
          setState(() => _onlineOnly = v);
        },
      ),
      const SizedBox(height: Sp.md),
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('لا مشتركين مطابقين', style: AppType.body(color: AppColors.textLow)),
        )
      else
        DeskVirtualTable(
          columns: columns,
          itemCount: shown.length,
          maxHeight: (h * 0.7).clamp(320, 900).toDouble(),
          controller: _onuScroll,
          storageKey: PageStorageKey('vsol-${widget.device.id}-onu-table'),
          rowKey: (i) => ValueKey(shown[i].$2.label),
          cells: (i) {
            final (position, o) = shown[i];
            final t = _rates[o.label];
            final rx = o.reading?.rxDbm;
            return [
              Text('${position + 1}', style: AppType.label(color: AppColors.textLow)),
              DeskNameCell(
                name: o.name?.isNotEmpty == true ? o.name! : o.label,
                sub: isoJoin([
                  if (o.name?.isNotEmpty == true) o.label,
                  o.online ? 'متّصل' : 'غير متّصل',
                  if (o.vendor != null) o.vendor!,
                ], ' · '),
                tone: o.online ? AppTone.success : AppTone.neutral,
                dim: !o.online,
                copy: o.name?.isNotEmpty == true,
              ),
              if (o.mac != null)
                DeskMonoCell(o.mac!, label: 'ماك الـONU')
              else if (o.serial != null)
                DeskMonoCell(o.serial!, label: 'الرقم التسلسليّ')
              else
                deskDash(),
              if (optics)
                (o.online && rx != null)
                    ? DeskDotValue(
                        value: rx.toStringAsFixed(1),
                        unit: 'dBm',
                        // سلّم الضوء نفسه في «شبكة الألياف» (FiberBands): جيّد فوق ‎-25، حدّي حتى ‎-27، ضعيف تحته.
                        color: FiberBands.tone(rx).fill)
                    : deskDash(),
              DeskRateCell(bps: o.online ? t?.txBps?.round() : null, down: true, max: maxDown, live: o.online),
              DeskRateCell(bps: o.online ? t?.rxBps?.round() : null, down: false, max: maxUp, live: o.online),
              if (learned) _deskLearnedCell(o),
            ];
          },
        ),
    ]);
  }

  /// عدد أجهزة المشترك خلف الـONU — بنقرةٍ تُفتح قائمة ماكاتها لتُنسخ.
  Widget _deskLearnedCell(VsolOnu o) {
    if (!o.online || !_showsLearned(o)) return deskDash();
    if (o.learnedMacs.isEmpty) {
      final loading = o.technology == VsolPonTechnology.epon ? _eponLoading : _gponDetailsLoading;
      return Text(o.learnedMacsReadAt == null && loading ? '…' : '—', style: AppType.body(color: AppColors.textLow));
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: InkWell(
        borderRadius: BorderRadius.circular(R.pill),
        onTap: () => showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('أجهزة خلف ${o.name?.isNotEmpty == true ? o.name! : o.label}\u200F (${o.learnedMacs.length})',
                style: AppType.cardTitleBold()),
            content: SizedBox(
              width: 360,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (o.learnedMacsReadAt != null)
                  Text(
                      'ماكات أجهزة المشترك · آخر قراءة ${_clock(o.learnedMacsReadAt!)}${o.learnedMacsComplete ? '' : ' · ناقصة'}',
                      style: AppType.muted(color: AppColors.textLow)),
                const SizedBox(height: Sp.sm),
                for (final mac in o.learnedMacs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: SelectableText(mac, textDirection: TextDirection.ltr, style: AppType.rowValue()),
                  ),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إغلاق'))],
          ),
        ),
        child: DeskPill('${o.learnedMacs.length}', AppTone.brand),
      ),
    );
  }

  bool _match(VsolOnu o) {
    if (_onlineOnly && !o.online) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '${o.label} ${o.name ?? ''} ${o.serial ?? ''} '
            '${o.mac ?? ''} ${o.vendor ?? ''} ${o.learnedMacs.join(' ')}'
        .toLowerCase()
        .contains(q);
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

  Widget _onuContent(List<(int, VsolOnu)> shown) => Column(
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
                    hintText: 'ابحث بالاسم أو ONU أو MAC أو SN…',
                    hintStyle: AppType.micro(color: AppColors.textLow),
                    prefixIcon: Icon(LucideIcons.search,
                        size: 14, color: AppColors.textLow),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.sm),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                  ),
                  onChanged: (v) {
                    if (_onuScroll.hasClients) _onuScroll.jumpTo(0);
                    setState(() => _query = v);
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: Text('المتّصلون', style: AppType.micro()),
              selected: _onlineOnly,
              onSelected: (v) {
                if (_onuScroll.hasClients) _onuScroll.jumpTo(0);
                setState(() => _onlineOnly = v);
              },
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
            // الحاسبة: أطول (٧٠٪ من النافذة) والصفوف جنباً إلى جنب — نفس القائمة الافتراضيّة (تُبنى الظاهرة وحدها).
            LayoutBuilder(builder: (context, c) {
              final desk = DesktopScope.of(context);
              final cols = DeskRows.columnsFor(context, c.maxWidth, minTileWidth: 380, maxColumns: 3);
              final h = MediaQuery.sizeOf(context).height;
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: desk ? (h * 0.7).clamp(320, 900) : (h * 0.52).clamp(240, 420),
                ),
                child: Scrollbar(
                  controller: _onuScroll,
                  thumbVisibility: true,
                  child: cols > 1
                      ? ListView.builder(
                          key: PageStorageKey('vsol-${widget.device.id}-onu-list-$cols'),
                          controller: _onuScroll,
                          primary: false,
                          shrinkWrap: true,
                          padding: const EdgeInsetsDirectional.only(end: 10),
                          itemCount: (shown.length + cols - 1) ~/ cols,
                          itemBuilder: (context, row) => Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var k = 0; k < cols; k++) ...[
                                if (k > 0) const SizedBox(width: Sp.sm),
                                Expanded(
                                  child: row * cols + k < shown.length
                                      ? _onuRow(shown[row * cols + k].$2, shown[row * cols + k].$1 + 1)
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        )
                      : ListView.builder(
                          key: PageStorageKey('vsol-${widget.device.id}-onu-list'),
                          controller: _onuScroll,
                          primary: false,
                          shrinkWrap: true,
                          padding: const EdgeInsetsDirectional.only(end: 10),
                          itemCount: shown.length,
                          findChildIndexCallback: (key) {
                            final index = shown
                                .indexWhere((entry) => ValueKey(entry.$2.label) == key);
                            return index < 0 ? null : index;
                          },
                          itemBuilder: (context, index) {
                            final (position, onu) = shown[index];
                            return _onuRow(onu, position + 1);
                          },
                        ),
                ),
              );
            }),
        ],
      );

  Widget _onuRow(VsolOnu o, int number) => Container(
        key: ValueKey(o.label),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 4,
              height: 26,
              decoration: BoxDecoration(
                color: o.online ? AppColors.success : AppColors.textLow,
                borderRadius: BorderRadius.circular(R.sm),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.brandSoftBg,
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: Text('$number',
                  semanticsLabel: 'المشترك $number',
                  style: AppType.microBold(color: AppColors.brand)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (o.name?.isNotEmpty == true)
                      Copyable(
                        label: 'اسم الـONU',
                        value: o.name,
                        child: Text(o.name!, style: AppType.rowLabelBold()),
                      ),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(o.label,
                          textAlign: TextAlign.left,
                          style: AppType.rowLabelBold()),
                    ),
                    // ماك **وحدة الـONU** — لا ماك جهاز المشترك (تلك تحته
                    // في «أجهزة خلف الـONU»). انظر `VsolOnu.mac`.
                    // العنوان العربيّ والقيمة اللاتينيّة كلٌّ في عنصره: في سطرٍ
                    // واحدٍ مختلط الاتّجاه كان يُقرأ «…01الـ MAC».
                    if (o.mac != null)
                      Row(children: [
                        Text('ماك الـONU',
                            style: AppType.micro(color: AppColors.textLow)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Copyable(
                            label: 'ماك الـONU',
                            value: o.mac,
                            child: Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(o.mac!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.micro(color: AppColors.textMid)),
                            ),
                          ),
                        ),
                      ])
                    else
                      Copyable(
                        label: 'الرقم التسلسليّ',
                        value: o.serial,
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            o.serial != null
                                ? 'SN ${o.serial}'
                                : (o.online ? '—' : 'غير متّصل'),
                            textAlign: TextAlign.left,
                            style: AppType.micro(color: AppColors.textLow),
                          ),
                        ),
                      ),
                    if (o.online && o.reading != null) _opticsLine(o),
                  ]),
            ),
            if (o.online) _flow(o.label),
          ]),
          if (o.online && _showsLearned(o)) _learnedMacs(o),
        ]),
      );

  /// هل لهذه الـONU قائمة «أجهزة خلف الـONU»؟ GPON من جدول VSOL، وEPON
  /// من جدول الجسر (حين يُقرأ لهذا المصنّع).
  bool _showsLearned(VsolOnu o) =>
      o.technology == VsolPonTechnology.gpon ||
      (_profile.vendor != OltVendor.unknown &&
          (o.learnedMacsReadAt != null || _eponLoading));

  /// «الضوء ‎-13.5 dBm · 46°C · 3.32V · HWTC» — قراءة الـONU عند لحظتها.
  Widget _opticsLine(VsolOnu o) {
    final r = o.reading!;
    final parts = <String>[
      if (r.rxDbm != null) 'RX ${r.rxDbm!.toStringAsFixed(1)} dBm',
      if (r.txDbm != null) 'TX ${r.txDbm!.toStringAsFixed(1)} dBm',
      if (r.tempC != null) '${r.tempC!.round()}°C',
      if (r.voltV != null) '${r.voltV!.toStringAsFixed(2)}V',
      if (o.vendor != null) o.vendor!,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    final rx = r.rxDbm;
    // سلّم الضوء نفسه في «شبكة الألياف» (FiberBands) — لا يقول الأولت «سليم» لما تقول عنه شاشة الألياف «حدّي».
    final band = FiberBands.tone(rx);
    final tone = rx == null
        ? AppColors.textLow
        : (band == AppTone.success ? AppColors.textMid : (band == AppTone.warning ? AppColors.warning : AppColors.error));
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Text(parts.join(' · '),
            textAlign: TextAlign.left,
            style: AppType.micro(color: tone)),
      ),
    );
  }

  Widget _learnedMacs(VsolOnu o) {
    final epon = o.technology == VsolPonTechnology.epon;
    final loading = epon ? _eponLoading : _gponDetailsLoading;
    // EPON: جهازٌ لا يكشف جدول الجسر — «غير متوفّر» لا «لا أجهزة».
    final unsupported = epon && _epon.fdbAt != null && !_epon.fdb.supported;
    // قائمةٌ قرأناها لهذه الـONU تُعرض ولو جاء المسح التالي ناقصاً.
    if (unsupported || o.learnedMacs.isEmpty || (!epon && !o.learnedMacsComplete)) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          unsupported
              ? 'أجهزة خلف الـONU: هذا الجهاز لا يكشف جدولها'
              : o.learnedMacsReadAt == null
                  ? (loading
                      ? 'جاري قراءة أجهزة خلف الـONU…'
                      : 'أجهزة خلف الـONU لم تُقرأ بعد')
                  : (!o.learnedMacsComplete
                      ? 'تعذّرت قراءة جدول الأجهزة كاملاً'
                      : 'لا أجهزة متعلَّمة خلف الـONU الآن'),
          style: AppType.micro(color: AppColors.textLow),
        ),
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: ExpansionTile(
        key: PageStorageKey('vsol-${widget.device.id}-${o.label}-macs'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 6),
        dense: true,
        visualDensity: VisualDensity.compact,
        iconColor: AppColors.textLow,
        collapsedIconColor: AppColors.textLow,
        // ⚠️ RLM ‏(U+200F) قبل القوس: بعد «ONU» اللاتينيّة يُرسم العدد في
        // الجهة الأخرى («الـ(2) ONU») لولاها.
        title: Text('أجهزة خلف الـONU\u200F (${o.learnedMacs.length})',
            style: AppType.micro(color: AppColors.textMid)),
        subtitle: Text(
            'ماكات أجهزة المشترك · آخر قراءة ${_clock(o.learnedMacsReadAt!)}'
            '${o.learnedMacsComplete ? '' : ' · ناقصة'}',
            style: AppType.micro(color: AppColors.textLow)),
        children: [
          for (final mac in o.learnedMacs)
            Align(
              alignment: AlignmentDirectional.centerStart,
              // ExpansionTile stores a bool in PageStorage. Each selectable
              // line has a scroll position and must use a separate storage key.
              child: SelectableText(mac,
                  key: PageStorageKey(
                      'vsol-${widget.device.id}-${o.label}-$mac'),
                  textDirection: TextDirection.ltr,
                  style: AppType.micro()),
            ),
        ],
      ),
    );
  }

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
