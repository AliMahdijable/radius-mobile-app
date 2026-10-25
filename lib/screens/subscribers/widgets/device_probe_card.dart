import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/device_config_api.dart';
import '../../../api/device_probe_api.dart';
import '../../../api/ubnt_api.dart';
import '../../../core/net/huawei_ont_service.dart';
import '../../../core/net/ont_traffic.dart';
import '../../../services/subscriber_refresh_signal.dart';
import '../../../core/util/clipboard_helper.dart';
import '../../../core/widgets/copyable.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../services/merged_mode.dart';
import '../../../services/permissions_service.dart';
import '../../../models/device_health.dart';
import '../sheets/device_config_sheet.dart';
import 'device_chip_micro.dart' show DeviceProbeBus;
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/app_sheet.dart';

/// كارت «معلومات الجهاز» — يفحص IP المشترك عند أوّل بناء ويعرض قياسات
/// الجهاز. الشريحة 4 من إعادة التصميم (2026-08-29).
///
/// المخطّط يبني الكارت من ثلاث طبقات ثابتة:
///   1. **رأس**: أيقونة 18 بلون الـaccent + عنوان 14/w600 + حبّة حالة
///      ملوّنة دلاليّاً + زرّا `settings` و`sync` في الطرف.
///   2. **جسم القياسات**: بلاطات غاطسة (#F7F8F5 · r14) — ثلاث بالعرض
///      لـUbiquiti (الإشارة · SNR · CCQ)، وشبكة 2×2 لـONT (RX · TX ·
///      الفولتيّة · الحرارة).
///   3. **صفوف التفاصيل**: تسمية خافتة يمين وقيمة `ltr` يسار.
///
/// حالة الفحص لها رسم خاصّ في المخطّط (سطر «جارٍ فحص الجهاز تلقائيّاً…»
/// + هياكل نابضة) بدل الدوّارة الوسطى — تُشعر المدير أنّ الكارت سيمتلئ
/// لا أنّه عالق.
///
/// ⚠️ زرّا الرأس هما المدخل الوحيد لـ`DeviceConfigSheet` وللفحص اليدوي
/// — لا يُسقطان مهما تغيّر التصميم.
class DeviceProbeCard extends StatefulWidget {
  const DeviceProbeCard({
    super.key,
    this.ip = '',
    required this.username,
    this.company,
  });

  /// IP من SAS4 (framedipaddress). قد يكون فارغاً — الـprobe() داخلياً
  /// يجرّب customIp من DeviceConfig أوّلاً، فحتى المشتركون بلا session
  /// نشط يحصلون على فحص لو المدير خزّن customIp في إعدادات الجهاز.
  final String ip;
  final String username;

  /// شركة الصفّ في «كل الشركات» (null في الوضع العاديّ): إعداد الجهاز وافتراضات المدير من شركته، والفحص من الهاتف كما هو.
  /// حفظ إعداد الجهاز للشركة وحدها (خارج جدول التوجيه).
  final String? company;

  /// ما يرسمه الكارت ذو المفتاح [key] الآن — القراءة المعروضة ووقتها
  /// وملاحظة المدير — لـ«نسخ كلّ المعلومات». `null` حين لا يكون مركَّباً
  /// (خارج الشاشة): عندها يرسم حين يُركَّب ما في مخزن الفحص.
  ///
  /// 🐛 لماذا لا يكفي المخزن ([DeviceProbeApi.peek]): الكارت يُبقي آخر
  /// قراءةٍ ناجحة معروضةً إن فشل فحصٌ صامتٌ بعدها (نبضة الإشارة كلّ عشر
  /// ثوانٍ، أو سقف الخمس عشرة ثانية على رابطٍ ضعيف)، والمخزن يحفظ ذلك
  /// الفشل `null` — فكان النسخ يُسقط قراءاتٍ ظاهرةً على الشاشة. وملاحظته
  /// هي التي رسمها من آخر جلبٍ له، لا ما بقي في مخزن الإعداد.
  static DeviceCardShown? shownBy(GlobalKey key) {
    final s = key.currentState;
    if (s is! _DeviceProbeCardState || !s.mounted) return null;
    return (snap: s._snap, at: s._lastAt, notes: s._notes);
  }

  @override
  State<DeviceProbeCard> createState() => _DeviceProbeCardState();
}

/// ما يرسمه كارت الجهاز: [snap] القراءة المعروضة (`null` = لا قراءة: جارٍ
/// الفحص أو «غير متاح»)، و[at] وقتها، و[notes] ملاحظة المدير على الجهاز.
typedef DeviceCardShown = ({
  DeviceHealthSnapshot? snap,
  DateTime? at,
  String? notes,
});

class _DeviceProbeCardState extends State<DeviceProbeCard>
    with WidgetsBindingObserver {
  bool _loading = true;
  DeviceHealthSnapshot? _snap;
  String? _notes;

  // ═══════════ الترافيك اللحظي ═══════════
  //
  // عدّادات البايت تصل أصلاً في كلّ استجابة `/status.cgi` — نفس الطلب
  // الذي يجريه الفحص. المعدّل فرق قراءتين مقسوماً على الزمن بينهما،
  // فالنبضة الأولى تزرع المرجع ولا تُنتج قيمة.
  //
  // ⚠️ **الجلسة تُفتح مرّة واحدة** ثمّ يُعاد استعمالها: تسجيل دخول كلّ
  // 3 ثوانٍ على معالج CPE ضعيف عبء لا مبرّر له، و`fetchStatus` تقبل
  // جلسة قائمة.
  static const _pulse = Duration(seconds: 3);

  /// نبضة إعادة فحص الإشارة.
  ///
  /// 🐛 بلاغ المستخدم: «اجعل إشارة النانو تتحدّث بوقت سريع مو ثابتة».
  /// وكان الكرت يفحص **مرّةً واحدة** ثمّ لا يُعيد إلّا إن تجاوزت اللقطة
  /// خمس دقائق — فالإشارة وCCQ يتجمّدان أمام الفنّيّ وهو يوجّه الطبق.
  /// عشرٌ تطابق لوحة UBNT في قسم الأجهزة (المسار المُثبَت).
  ///
  /// ⚠️ **`force: true` لا غنى عنه**: مخزن الفحص عمره خمس دقائق، ونداءٌ
  /// بلا إجبار يُعيد اللقطة نفسها فيبدو التحديث حيّاً وهو ميّت.
  static const _signalPulse = Duration(seconds: 10);
  Timer? _signalTimer;
  Timer? _agoTimer;
  Timer? _trafficTimer;

  /// وقت آخر لقطة ناجحة — لمؤشّر «آخر تحديث».
  DateTime? _lastAt;

  /// فحصٌ واحد في الطريق لا غير.
  ///
  /// 🐛 صار للكرت ثلاثة مصادر فحص: نبضة العشر ثوانٍ، والتحديث الفوريّ
  /// عند الفتح، والسحب للتحديث. وبلا حارس تتراكم ثلاث سلاسل دخولٍ
  /// على **جهاز المشترك نفسه** — وهو أضعف ما في الشبكة، ويُفحَص
  /// تحديداً لأنّه مشكوكٌ فيه. ثمّ تتسابق نتائجها فيرتدّ الكرت بين
  /// قراءةٍ جديدة وأخرى قديمة أمام عين المدير.
  bool _probing = false;
  bool _rebooting = false;
  UbntTrafficSession? _session;

  /// ترافيك الـONU (Huawei، ٢٢ أكتوبر): جلسة ويب معمَّرة تقرأ رأسَي صفحتي الواي فاي وLAN كلّ نبضة ([OntTrafficSession])،
  /// والمعدّل لكلّ واجهةٍ بوقت صفحتها ([OntTrafficMeter]).
  ///
  /// ⚠️ للمستخدم على الـONU **جلسةٌ واحدة**: دخولٌ جديد (فحص الجهاز، هاتفٌ آخر، صفحة الجهاز من متصفّح) يطرد جلستنا —
  /// قِيس على HS8545M. فقراءةٌ فارغة تعني «طُردنا»: نُغلق وننتظر [_ontRetry] ثمّ ندخل من جديد — لا كلّ نبضة، كي لا
  /// يتطاردَ هاتفان على المشترك نفسه.
  static const _ontPulse = Duration(seconds: 5);
  static const _ontRetry = Duration(seconds: 12);
  OntTrafficSession? _ontSession;
  final _ontMeter = OntTrafficMeter();
  DateTime? _ontRetryAt;
  int? _lastRx;
  int? _lastTx;
  DateTime? _lastSample;
  int? _rxBps;
  int? _txBps;
  bool _pulsing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SubscriberRefreshSignal.tick.addListener(_onPullRefresh);
    // ⚠️ اقرأ ما فحصته موجة القائمة قبل أن تفحص.
    //
    // كان الكارت يُطلق فحصاً كاملاً عند كل فتح بلا سؤال الكاش، بينما
    // شريحة القائمة تقرأه قراءةً متزامنة ولا تفحص أبداً. فالنتيجة:
    // جهاز يُفحص مرّة في القائمة ومرّة عند فتح كارته — ومعه دوّارة
    // تحميل تُوحي بأنّ شيئاً يجري وهو معروف أصلاً.
    //
    // نقرأ بالـusername أوّلاً (لا يلتبس مع تجاوز العنوان) ثمّ بالـIP.
    // النتيجة القديمة تُعرض أيضاً: الجهاز الذي فُحص مرّة لا ينبغي أن
    // يبدو مجهولاً بعدها. إن كانت قديمة نُحدّثها في الخلفيّة بلا دوّارة.
    final hit = DeviceProbeApi.peek(
      username: widget.username,
      ip: widget.ip.trim(),
      company: widget.company,
    );
    if (hit != null) {
      _snap = hit.snap;
      _lastAt = hit.at;
      _loading = false;
      _maybeStartTraffic();
      _maybeStartSignal();
      _loadNotesOnly();
      // 🐛 كان: `if (hit.stale) _refreshQuietly()` — أي لا تحديث إلّا
      // إن تجاوزت اللقطة خمس دقائق. فمن يفتح كرت المشترك يرى أرقاماً
      // عمرها أربع دقائق **وهي معروضة كأنّها الآن**، ولا شيء يقول له.
      // والمدير يفتح الكرت تحديداً ليعرف حال الجهاز هذه اللحظة.
      //
      // الآن: يُرسم المخزَّن فوراً بلا دوّارة (فلا شاشة فارغة)، ويُطلق
      // فحصٌ **مُجبَر** في الخلفيّة يُحدّثه بعد ثانية أو ثانيتين.
      _refreshQuietly(force: true);
      return;
    }
    _run();
  }

  /// الجهاز مفحوص أصلاً: نكمل بجلب الملاحظات بلا دوّارة ولا فحص.
  /// السحب للتحديث يصل هذا الكرت عبر الإشارة — لا عبر الأب.
  ///
  /// وأشدّ ما يحتاجها حالتان لا نبضة دوريّة لهما أصلاً: جهاز ONT،
  /// وجهازٌ تعذّر الوصول إليه (`_snap == null`) — وهو بالضبط ما يسحب
  /// المدير ليُعيد المحاولة عليه.
  void _onPullRefresh() {
    if (!mounted) return;
    _run(force: true);
  }

  @override
  void dispose() {
    SubscriberRefreshSignal.tick.removeListener(_onPullRefresh);
    WidgetsBinding.instance.removeObserver(this);
    _trafficTimer?.cancel();
    _signalTimer?.cancel();
    _agoTimer?.cancel();
    _session?.close();
    _closeOntTraffic();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ⚠️ بدون هذا يبقى المؤقّت يطرق جهاز المشترك كلّ 3 ثوانٍ والتطبيق
    // في الخلفيّة — شاشة التفاصيل كانت خالية من أيّ مراقب دورة حياة.
    if (state == AppLifecycleState.resumed) {
      _maybeStartTraffic();
      _maybeStartSignal();
    } else {
      _trafficTimer?.cancel();
      _trafficTimer = null;
      _signalTimer?.cancel();
      _signalTimer = null;
      _agoTimer?.cancel();
      _agoTimer = null;
      // نُغلق قناة SSH أيضاً — إبقاؤها مفتوحة والتطبيق في الخلفيّة
      // يستهلك جلسة على جهاز المشترك بلا أيّ فائدة.
      _session?.close();
      _session = null;
      // وجلسة الـONU: جلسته الوحيدة لا تبقى محجوزةً والتطبيق في الخلفيّة
      _closeOntTraffic();
    }
  }

  /// إعادة فحصٍ دوريّة للإشارة — لأجهزة Ubiquiti وحدها.
  ///
  /// ONT مستثناة كما في الترافيك: عميل Huawei يكشط صفحة ومهلاته ١٥
  /// ثانية، فطرقُه كلّ عشر ثوانٍ يُنتج طابوراً لا تحديثاً.
  void _maybeStartSignal() {
    if (_signalTimer != null) return;
    if (_snap?.kind != DeviceKind.ubiquiti) return;
    _signalTimer =
        Timer.periodic(_signalPulse, (_) => _refreshQuietly(force: true));
    // عدّاد «آخر تحديث» يتقدّم بنفسه ولو لم يصل جديد — وإلّا جمد
    // النصّ على «قبل ٣ د» بينما الوقت يمضي.
    _agoTimer ??= Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  void _maybeStartTraffic() {
    if (_trafficTimer != null) return;
    final snap = _snap;
    // ⚠️ الشرط على **نوع الجهاز** لا على وجود عدّادات في لقطة الفحص:
    // لقطة الفحص تأتي من `status.cgi` وهو لا يُصدّر عدّادات بايت على
    // airOS — لذلك كان الشرط السابق (`ubnt?.rxBytes != null`) يمنع
    // الاستطلاع من البدء إطلاقاً، فتبقى بلاطة SNR إلى الأبد.
    // العدّادات تأتي من SSH كما تفعل لوحة الأجهزة، وهو المسار المُثبَت.
    //
    // ONT (٢٢ أكتوبر): بلا عدّادٍ في صفحة البصريّات — العدّادات في صفحتي الواي فاي وLAN، تُقرأ رؤوسهما وحدها (~٠٫٧ث لكلٍّ
    // بدل ١–٤ث كاملةً) كلّ [_ontPulse].
    if (snap == null) return;
    if (snap.kind == DeviceKind.ont) {
      // بعد لحظة لا فوراً: الفحص الذي جاء بنا ما زال يحمل `_probing` حتّى يعود — والنبضة الفوريّة كانت تُتخطّى فتنتظر
      // الدورة التالية (أوّل رقمٍ بعد ~٢٥ث من فتح الصفحة).
      Timer(const Duration(milliseconds: 300), _pulseOntTraffic);
      _trafficTimer = Timer.periodic(_ontPulse, (_) => _pulseOntTraffic());
      return;
    }
    if (snap.kind != DeviceKind.ubiquiti) return;
    _pulseTraffic(); // نبضة فوريّة تزرع المرجع بلا انتظار 3 ثوانٍ
    _trafficTimer = Timer.periodic(_pulse, (_) => _pulseTraffic());
  }

  /// نبضة ترافيك الـONU: جلسةٌ تُفتح مرّةً (باعتمادات شركة المشترك وعنوانه المثبَّت — كالفحص حرفاً)، ثمّ قراءةٌ ومعدّل.
  Future<void> _pulseOntTraffic() async {
    // فحصٌ جارٍ يدخل على الجهاز نفسه — دخولنا الآن يطرده (جلسةٌ واحدة) أو يطردنا؛ ننتظر النبضة التالية
    if (_pulsing || _probing || !mounted) return;
    final retryAt = _ontRetryAt;
    if (_ontSession == null && retryAt != null && DateTime.now().isBefore(retryAt)) return;
    _pulsing = true;
    try {
      if (_ontSession == null) {
        final creds = await DeviceProbeApi.resolveOntCreds(
          fallbackIp: widget.ip,
          subscriberUsername: widget.username,
          company: widget.company,
        );
        if (creds == null || !mounted) return;
        _ontSession = await OntTrafficSession.open(
          ip: creds.ip,
          user: creds.user,
          pass: creds.pass,
          // ZTE (٢٥ أكتوبر) بجلسته وصفحاته؛ وإلّا هواوي كما كان
          vendor: _snap?.ont?.vendor ?? 'huawei',
        );
        if (_ontSession == null) {
          _ontRetryAt = DateTime.now().add(_ontRetry);
          return;
        }
        if (!mounted) {
          _closeOntTraffic();
          return;
        }
      }
      final counters = await _ontSession?.sample();
      if (counters == null) {
        // طُردنا (دخولٌ آخر على الجهاز) أو انتهت الجلسة — دخولٌ جديد بعد المهلة، ولا يبقى رقمٌ قديم معروضاً كأنّه الآن
        _closeOntTraffic();
        _ontRetryAt = DateTime.now().add(_ontRetry);
        if (mounted && _rxBps != null) {
          setState(() {
            _rxBps = null;
            _txBps = null;
          });
        }
        return;
      }
      final r = _ontMeter.add(counters, DateTime.now());
      // القراءة الأولى تزرع المرجع: الثانية بعد ٣ث لا عند النبضة التالية — أوّل رقمٍ أسرع، والمدّة كافية للدقّة
      if (r == null) Timer(const Duration(seconds: 3), _pulseOntTraffic);
      if (r != null && mounted) {
        setState(() {
          _rxBps = r.downBps;
          _txBps = r.upBps;
        });
      }
    } catch (_) {
      _closeOntTraffic();
      _ontRetryAt = DateTime.now().add(_ontRetry);
    } finally {
      _pulsing = false;
    }
  }

  /// التحميل بلون العلامة والرفع أسود كما كانا («للتمييز» — المالك ٢٢ أكتوبر). null قبل أوّل معدّل («—» بلونٍ خافت).
  List<({String text, Color color})>? _trafficParts({required bool unit}) {
    final down = _rxBps;
    if (down == null) return null;
    final up = _txBps ?? 0;
    String f(int v) => unit ? formatBpsUnit(v) : _fmtBps(v);
    return [
      (text: '↓${f(down)}', color: AppColors.brandAccent),
      (text: unit ? '   ' : ' ', color: AppColors.textLow),
      (text: '↑${f(up)}', color: AppColors.textHi),
    ];
  }

  void _closeOntTraffic() {
    final s = _ontSession;
    _ontSession = null;
    _ontMeter.reset();
    if (s != null) unawaited(s.close());
  }

  Future<void> _pulseTraffic() async {
    if (_pulsing || !mounted) return;
    _pulsing = true;
    try {
      // الجلسة تُفتح مرّة وتُعاد. الأمر الوحيد في كلّ نبضة هو
      // `cat /proc/net/dev` — بضع مئات من البايتات وتفرّع عمليّة واحدة.
      if (_session == null) {
        final creds = await DeviceProbeApi.resolveUbntCreds(
          fallbackIp: widget.ip,
          subscriberUsername: widget.username,
          company: widget.company,
        );
        if (creds == null) return;
        _session = await UbntTrafficSession.open(
          ip: creds.ip,
          user: creds.user,
          pass: creds.pass,
        );
      }
      final sess = _session;
      if (sess == null) return;

      final read = await sess.sample();
      if (read == null) {
        // الجلسة ماتت غالباً (انقطاع أو مهلة الجهاز) — نُغلقها ليُعاد
        // فتحها في النبضة القادمة بدل الإصرار على قناة ميّتة.
        sess.close();
        _session = null;
        return;
      }

      final now = DateTime.now();
      if (_lastRx != null && _lastSample != null) {
        final secs = now.difference(_lastSample!).inMilliseconds / 1000.0;
        final dDown = read.down - _lastRx!;
        final dUp = read.up - _lastTx!;
        // الفرق السالب يعني التفاف عدّاد أو إعادة إقلاع — يُتخطّى بدل
        // عرض قيمة سالبة أو قفزة كاذبة.
        if (secs > 0.5 && dDown >= 0 && dUp >= 0) {
          final r = (dDown * 8 / secs).round();
          final t = (dUp * 8 / secs).round();
          // سقف عقلانيّة: قراءة شاذّة بعد التفاف 32-bit تمرّ بلا هذا.
          const sane = 10000000000;
          if (r <= sane && t <= sane && mounted) {
            setState(() {
              _rxBps = r;
              _txBps = t;
            });
          }
        }
      }
      _lastRx = read.down;
      _lastTx = read.up;
      _lastSample = now;
    } catch (_) {
      // نبضة فاشلة: لا نمسّ المرجع، فالنبضة الناجحة التالية تحسب
      // المعدّل على كامل الفجوة — متوسّط صحيح لا قفزة.
      _session?.close();
      _session = null;
    } finally {
      _pulsing = false;
    }
  }

  Future<void> _loadNotesOnly() async {
    final cfg = await DeviceConfigApi.fetchConfig(widget.username,
        company: widget.company);
    if (!mounted) return;
    setState(() => _notes = cfg?.notes?.trim());
  }

  /// تحديث صامت لنتيجة قديمة: بلا `_loading` فلا دوّارة ولا وميض.
  /// إن فشل الفحص تبقى النتيجة القديمة معروضة — أفضل من فراغ.
  /// تحديثٌ بلا دوّارة. [force] يتجاوز مخزن الخمس دقائق — بدونه تُعيد
  /// الدالّة اللقطة المخزَّنة نفسها، فتبدو النبضة الدوريّة عاملةً
  /// والأرقام لا تتغيّر.
  Future<void> _refreshQuietly({bool force = false}) async {
    if (_probing) return;
    _probing = true;
    try {
      await _refreshQuietlyInner(force: force);
    } finally {
      _probing = false;
    }
  }

  Future<void> _refreshQuietlyInner({bool force = false}) async {
    final snap = await DeviceProbeApi.probe(
      fallbackIp: widget.ip,
      subscriberUsername: widget.username,
      force: force,
      company: widget.company,
    );
    if (!mounted || snap == null) return;
    setState(() {
      _snap = snap;
      _lastAt = DateTime.now();
    });
    // من يقرأ الكاش نفسه (بلاطة «تنبيه» فوق، وبطاقة القائمة تحت) لا يعرف
    // أنّ قراءةً جديدة وصلت إلّا بهذا.
    DeviceProbeBus.bump();
  }

  Future<void> _run({bool force = false}) async {
    if (_probing) return;
    _probing = true;
    try {
      await _runInner(force: force);
    } finally {
      _probing = false;
    }
  }

  Future<void> _runInner({bool force = false}) async {
    setState(() => _loading = true);
    // Probe + notes in parallel — both go through small caches so the
    // total cost on a warm session is sub-100ms.
    final results = await Future.wait([
      DeviceProbeApi.probe(
        fallbackIp: widget.ip,
        subscriberUsername: widget.username,
        force: force,
        company: widget.company,
      ),
      DeviceConfigApi.fetchConfig(widget.username, company: widget.company),
    ]);
    if (!mounted) return;
    final snap = results[0] as DeviceHealthSnapshot?;
    final cfg = results[1] as DeviceConfig?;
    setState(() {
      _snap = snap;
      _notes = cfg?.notes?.trim();
      _loading = false;
      if (snap != null) _lastAt = DateTime.now();
    });
    DeviceProbeBus.bump();
    _maybeStartTraffic();
    _maybeStartSignal();
  }

  /// الإقلاع متاحٌ للنانو وللـONU — ومسار كلٍّ مُستخرَجٌ من جهازٍ
  /// حقيقيّ لا مُخمَّن (انظر [HuaweiOntService.reboot]).
  bool _canReboot() {
    if (!Perms.has('devices.manage')) return false;
    final k = _snap?.kind;
    // ZTE (٢٥ أكتوبر): مسار إعادة تشغيله لم يُفحص على جهازٍ حقيقيّ — لا زرّ يَعِد بما لم يُجرَّب.
    if (k == DeviceKind.ont && (_snap?.ont?.isZte ?? false)) return false;
    return k == DeviceKind.ubiquiti || k == DeviceKind.ont;
  }

  Future<void> _confirmReboot() async {
    final isOnt = _snap?.kind == DeviceKind.ont;
    final name = _snap?.ubnt?.hostname.isNotEmpty == true
        ? _snap!.ubnt!.hostname
        : (isOnt ? 'ONU المشترك' : 'جهاز المشترك');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(LucideIcons.power, color: AppColors.warning, size: 32),
        title: const Text('إعادة تشغيل الجهاز'),
        content: Text('سيُعاد تشغيل "$name" الآن.\n'
            'ينقطع اتّصال المشترك دقيقة إلى دقيقتين.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            icon: const Icon(LucideIcons.power, size: 16),
            label: const Text('إعادة تشغيل'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _rebooting = true);
    HapticFeedback.mediumImpact();
    String text;
    Color color;
    try {
      final creds = isOnt
          ? await DeviceProbeApi.resolveOntCreds(
              fallbackIp: widget.ip,
              subscriberUsername: widget.username,
              company: widget.company,
            )
          : await DeviceProbeApi.resolveUbntCreds(
              fallbackIp: widget.ip,
              subscriberUsername: widget.username,
              company: widget.company,
            );
      if (creds == null) {
        throw Exception('لا بيانات دخول للجهاز — اضبطها من زرّ الإعدادات');
      }
      if (isOnt) {
        final session = await HuaweiOntService.login(
          creds.ip,
          creds.user,
          creds.pass,
          budget: const Duration(seconds: 25),
        );
        if (session == null) {
          throw Exception('تعذّر تسجيل الدخول إلى ONU');
        }
        final ok = await HuaweiOntService.reboot(session);
        if (!ok) throw Exception('رفض الـONU أمر إعادة التشغيل');
      } else {
        await UbntApi.rebootDevice(
          ip: creds.ip,
          user: creds.user,
          pass: creds.pass,
        );
      }
      text = 'أُرسل أمر إعادة التشغيل — الجهاز يقلع الآن';
      color = AppColors.success;
    } catch (e) {
      text = 'تعذّرت إعادة التشغيل: '
          '${e.toString().replaceFirst('Exception: ', '')}';
      color = AppColors.error;
    }
    if (!mounted) return;
    setState(() => _rebooting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _openConfig() async {
    // «كل الشركات»: الحفظ (PUT/DELETE) خارج جدول التوجيه — كان سيُحفظ تحت الشركة المفتوحة لا شركة المشترك.
    final blocked = MergedOps.unsupportedAt(widget.company);
    if (blocked != null) {
      showSheetSnack(context, blocked, isError: true);
      return;
    }
    final changed = await showAppSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (_) => DeviceConfigSheet(username: widget.username),
    );
    if (changed == true && mounted) {
      // The sheet already invalidated per-IP cache when it saved.
      _run(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 14),
          _body(),
          // مطلب 2026-06-11: سطر ملاحظة المدير من DeviceConfig.notes.
          // مخفي إذا فاضي حتى لا يضيف ارتفاع ع الكرت بدون فائدة.
          if ((_notes ?? '').isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            Copyable.field(
              deviceNoteField(_notes!),
              radius: R.icon,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Sp.md, vertical: Sp.sm),
                decoration: BoxDecoration(
                  color: AppColors.warningSoftBg,
                  borderRadius: BorderRadius.circular(R.icon),
                  border: Border.all(color: AppColors.warningSoftBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.fileText,
                        size: 13, color: AppColors.warningFill),
                    const SizedBox(width: Sp.x6),
                    Expanded(
                      child: Text(_notes!,
                          style: AppType.body(color: AppColors.warningOnSoft)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// رأس الكارت — أيقونة + عنوان + حبّة الحالة + زرّان.
  Widget _header() {
    final chip = _statusChip();
    return Row(
      children: [
        // ⚠️ `Flexible` و`Spacer` في صفّ واحد يتقاسمان الفراغ.
        //
        // كان الترتيب: … Flexible(chip) ثمّ Spacer() — ولكليهما
        // flex=1، فيقتسمان الفراغ الحرّ نصفين. والحبّة بـ`FlexFit.loose`
        // تأخذ مقاسها الطبيعي فقط، فيضيع نصيبها من الفراغ **بلا أن
        // يُعاد توزيعه** — فتظهر فجوة قبل الزرّين ولا يبلغان حافّة
        // الكارت. (بلاغ المستخدم بالصورة 2026-08-30)
        //
        // الحلّ: تجميع محتوى البداية في `Expanded` واحد يبتلع الفراغ
        // كلّه، فينزاح الزرّان إلى النهاية فعلاً.
        Expanded(
          child: Row(
            children: [
              Icon(LucideIcons.router, size: 18, color: AppColors.brandAccent),
              const SizedBox(width: Sp.sm),
              Flexible(
                child: Text('معلومات الجهاز',
                    style: AppType.cardTitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: Sp.sm),
              chip,
              // «آخر تحديث» — يقول متى قُرئت البيانات بدل أن يترك
              // المستخدم يخمّن إن كان ما يراه حيّاً أم من ساعة.
              if (_lastAt != null) ...[
                const SizedBox(width: Sp.x6),
                Flexible(
                  child: Text(
                    _ago(_lastAt!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.micro(color: AppColors.textLabel),
                  ),
                ),
              ],
            ],
          ),
        ),
        // إعادة تشغيل الجهاز — للنانو وحده اليوم (انظر `_canReboot`).
        if (_canReboot()) ...[
          _HeaderIcon(
            icon: LucideIcons.power,
            busy: _rebooting,
            color: AppColors.error,
            onTap: _rebooting ? null : _confirmReboot,
          ),
          const SizedBox(width: Sp.sm),
        ],
        _HeaderIcon(
          icon: LucideIcons.settings,
          onTap: _openConfig,
        ),
        const SizedBox(width: Sp.sm),
        _HeaderIcon(
          icon: LucideIcons.refreshCw,
          busy: _loading,
          onTap: _loading ? null : () => _run(force: true),
        ),
      ],
    );
  }

  Widget _statusChip() {
    late final String label;
    late final Color fg, bg, border;
    if (_loading && _snap == null) {
      label = 'جارٍ الفحص';
      fg = AppColors.textMid;
      bg = AppColors.surfaceSunken;
      border = AppColors.border;
    } else if (_snap == null) {
      label = 'غير متاح';
      fg = AppColors.dangerOnSoft;
      bg = AppColors.dangerSoftBg;
      border = AppColors.dangerSoftBorder;
    } else {
      label = switch (_snap!.kind) {
        DeviceKind.ont => 'ONT',
        DeviceKind.ubiquiti => 'UBNT',
        _ => 'متصل',
      };
      fg = AppColors.brandOnSoft;
      bg = AppColors.brandSoftBg;
      border = AppColors.brandSoftBorder;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.pillLabel(color: fg).copyWith(letterSpacing: 0),
      ),
    );
  }

  Widget _body() {
    if (_loading && _snap == null) return _scanning();
    final snap = _snap;
    if (snap == null) return _unreachable();
    if (snap.kind == DeviceKind.ont) return _ontBody(snap.ont!);
    if (snap.kind == DeviceKind.ubiquiti) return _ubntBody(snap.ubnt!);
    return const SizedBox.shrink();
  }

  /// حالة الفحص — سطر مطمئِن + هياكل نابضة، كما يرسمها المخطّط.
  Widget _scanning() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(R.lg),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.brandAccent,
                  backgroundColor: AppColors.border,
                ),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('جارٍ فحص الجهاز تلقائياً…',
                        style: AppType.rowValue()),
                    const SizedBox(height: Sp.xxs),
                    Text('يتم تجربة Ubiquiti ثم ONT', style: AppType.muted()),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.md),
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: Sp.sm),
              const Expanded(child: _SkeletonBox(height: 56)),
            ],
          ],
        ),
        const SizedBox(height: Sp.md),
        const _SkeletonBar(widthFactor: 0.78),
        const SizedBox(height: Sp.sm),
        const _SkeletonBar(widthFactor: 0.60),
        const SizedBox(height: Sp.sm),
        const _SkeletonBar(widthFactor: 0.68),
      ],
    );
  }

  Widget _unreachable() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.lg),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.plugZap, size: 20, color: AppColors.textHint),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('لم يُتمكّن من الوصول للجهاز',
                    style: AppType.rowValue(color: AppColors.textMid)),
                const SizedBox(height: Sp.xxs),
                Text('اضبط الـIP وبيانات الدخول من زرّ الإعدادات',
                    style: AppType.muted()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════ ONT ═══════════════

  Widget _ontBody(OntOpticalInfo o) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // شبكة 2×2 كما كانت (طلب المالك ٢٢ أكتوبر: «٤ كارتات بشكل مربّعات مثل السابق»): الترافيك أوّلاً («خلّي الترفك بالأوّل»)
        // ثمّ RX/TX بلاطةٌ واحدة، وتحتهما الفولتيّة والحرارة. RX والتحميل بلون العلامة، وTX والرفع أسود كما كانا («للتمييز»)؛ والأحمر لقيمةٍ خارج حدّها.
        // القيمة تُصغَّر لتتّسع النصف (fit) لا تُقصّ — القصّ يُسقط وحدةً أو رقماً (انظر _ubntBody).
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                icon: LucideIcons.activity,
                field: CopyField(
                  'الترافيك الآن',
                  _rxBps == null ? '—' : '↓${_fmtBps(_rxBps!)} ↑${_fmtBps(_txBps ?? 0)}',
                ),
                color: _rxBps == null ? AppColors.textLow : AppColors.brandAccent,
                fit: true,
                parts: _trafficParts(unit: false),
              ),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: _MetricTile(
                icon: LucideIcons.arrowDownUp,
                field: _ontRxTx(o),
                color: (o.rxOk && o.txOk) ? AppColors.brandAccent : AppColors.error,
                fit: true,
                parts: [
                  (text: o.rxPower, color: o.rxOk ? AppColors.brandAccent : AppColors.error),
                  (text: ' / ', color: AppColors.textLow),
                  (text: o.txPower, color: o.txOk ? AppColors.textHi : AppColors.error),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Sp.sm),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                icon: LucideIcons.zap,
                field: _ontVoltage(o),
                color: o.voltageOk ? AppColors.textHi : AppColors.warningFill,
              ),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: _MetricTile(
                icon: LucideIcons.thermometer,
                field: _ontTemp(o),
                color: o.tempOk ? AppColors.textHi : AppColors.warningFill,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _DetailRow(field: _ontKind(o), strong: true),
        if (_ontHasFiber(o)) _DetailRow(field: _ontFiber(o)),
      ],
    );
  }

  // ═══════════════ Ubiquiti ═══════════════

  Widget _ubntBody(UbiquitiStatus u) {
    // 🐛 بلاغ 2026-08-31 بصورة: «↓587K ↑3…» — رقم الرفع مقصوص.
    //
    // القياس من ملفّ الخطّ المشحون نفسه (IBMPlexSansArabic-700، upem
    // 1000) لا بالتقدير:
    //
    //   المتاح للبلاطة @414dp = (414 − 82) ÷ 3 − 24 = 86.67 نقطة
    //   «↓587K ↑3.2M» @14px    = 6.861em × 14      = 96.05 نقطة
    //
    // والسهمان وحدهما 1.800em — **26٪ من النصّ** بلا أيّ معلومة
    // رقميّة (U+2191/U+2193 عرضهما 0.900em، أوسع من الرقم بـ50٪).
    //
    // ولا يوجد هاتف يتّسع لها: 320→55.3 · 360→68.7 · 393→79.7 ·
    // 414→86.7 · 430→92.0 نقطة، وكلّها دون الـ96.05. حتّى القيمة
    // الدنيا «↓0K ↑0K» (64.8) تفيض على 320.
    //
    // والأسوأ أنّ القصّ يكذب لا يُخفي فقط: على 360 يختفي الرفع كلّه،
    // وعلى 320 تختفي وحدة القياس فيُقرأ «587» بلا معرفة أكيلو هي أم
    // ميغا، وعلى 320 مع تكبير 1.2 يصير «↓58…» — رقمٌ **خاطئ**.
    //
    // الحلّ بنيويّ لا تجميليّ: القصيرتان ثابتتا الطول تتقاسمان الصفّ،
    // والترافيك — الوحيد المتغيّر الطول — يأخذ العرض الكامل (324 نقطة
    // على 414dp = 3.4× حاجته، و226 على 320dp = 2.4×).
    final short = <Widget>[
      if (u.signalDbm != null)
        _MetricTile(
          field: _ubntSignal(u),
          color: _healthColor(u.signalHealth),
        ),
      if (u.ccqPercent != null)
        _MetricTile(
          field: _ubntCcq(u),
          color: _healthColor(u.ccqHealth),
        ),
      // SNR يبقى في الصفّ: قصيرٌ ثابت («28 dB») ولا يظهر إلّا حين لا
      // يُصدّر الإصدار عدّادات بايت، فلا يزاحم الترافيك أبداً.
      if (_snap?.kind != DeviceKind.ubiquiti && u.snrDb != null)
        _MetricTile(
          field: CopyField('SNR', '${u.snrDb} dB'),
          color: AppColors.textHi,
        ),
    ];

    // الترافيك اللحظي محلّ SNR (طلب المستخدم 2026-08-30): SNR رقم
    // شبه ثابت يُنظر إليه عند التركيب، والترافيك هو ما يُسأل عنه
    // يوميّاً — «هل المشترك يسحب فعلاً؟».
    final Widget? wide = _snap?.kind == DeviceKind.ubiquiti
        ? _MetricTile(
            field: CopyField(
              'الترافيك',
              _rxBps == null
                  ? '—'
                  : '↓${_fmtBps(_rxBps!)} ↑${_fmtBps(_txBps ?? 0)}',
            ),
            color: _rxBps == null ? AppColors.textLow : AppColors.brandAccent,
            parts: _trafficParts(unit: false),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (short.isNotEmpty)
          // ⚠️ بلا `crossAxisAlignment: CrossAxisAlignment.stretch` هنا.
          // هي الغريزة لتسوية ارتفاع البلاطات، لكنّها تُعيد المشكلة:
          // تفرض قيداً ضيّقاً على الأبناء فيُقصّ النصّ من جديد.
          Row(
            children: [
              for (var i = 0; i < short.length; i++) ...[
                if (i > 0) const SizedBox(width: Sp.sm),
                Expanded(child: short[i]),
              ],
            ],
          ),
        if (wide != null) ...[
          if (short.isNotEmpty) const SizedBox(height: Sp.sm),
          wide, // العرض الكامل — بلا Expanded وبلا جار
        ],
        if (short.isNotEmpty || wide != null) const SizedBox(height: 14),
        _DetailRow(field: _ubntKind(u), strong: true),
        if (u.firmware.isNotEmpty)
          _DetailRow(field: _ubntFirmware(u), small: true),
        if (u.ssid.isNotEmpty)
          _DetailRow(
            field: _ubntSsid(u),
            small: true,
            // اسم السكتور يُنسَخ كثيراً (بحثٌ عنه في اللوحة، إرسالٌ
            // لفنّيّ) — ونسخه يدويّاً من شاشةٍ لا تُحدَّد نصوصها متعذّر.
            trailing: _CopyIcon(
              value: u.ssid,
              label: 'SSID',
            ),
          ),
        if ((u.uptimeSeconds ?? 0) > 0)
          _DetailRow(field: _ubntUptime(u), rtlValue: true),
        // 🐛 كانتا صفّاً واحداً بتسمية «الإرسال / الاستقبال» (7.24em —
        // أطول تسمية في الكارت) فتُقصّ سرعة الاستقبال على 360dp،
        // فقُسِّمتا صفّين. والآن تعودان صفّاً واحداً **بتسمية لاتينيّة
        // قصيرة** «TX / RX» (‏≈2.6em، أقصر من «الإرسال» وحدها) ووحدةٍ
        // واحدة في آخر القيمة بدل تكرارها مرّتين — فالسبب الذي فرض
        // القسمة زال، لا أُهمل.
        if (_ubntHasRates(u)) _DetailRow(field: _ubntRates(u)),
        if (u.peerMac != null && u.peerMac!.isNotEmpty)
          _DetailRow(field: _ubntPeerMac(u), small: true),
        // مطلب 2026-06-11: عرض كل المنافذ (لا فقط primary) — كل
        // eth interface بحبّة منفصلة مع plugged/speed.
        if (u.lanPorts.isNotEmpty) _lanPortsRow(u.lanPorts),
      ],
    );
  }

  /// صفّ المنافذ — تسمية يمين وحبّات المنافذ يسار، كما في المخطّط
  /// («ETH0 · 100M» بلون البراند و«ETH1 · مفصول» رماديّة).
  Widget _lanPortsRow(List<LanPort> ports) {
    final field = _lanPortsField(ports);
    return Copyable.field(
      field,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(field.label,
                style: AppType.body(color: AppColors.textLabel)),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: Sp.x6,
                runSpacing: Sp.x6,
                children: [for (final p in ports) _lanChip(p)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lanChip(LanPort p) {
    final unplugged = !p.plugged;
    // 🐛 `displaySpeed` تُرجع «Unplugged» لمنفذٍ **موصول** لا سرعة له —
    // وairOS 5 لا يُصدّر سرعة إطلاقاً، فكان منفذ المشترك المتّصل
    // يُعرَض «LAN · Unplugged». الحقيقة أنّه متّصلٌ وسرعته مجهولة،
    // وهذا غير «مفصول» تماماً.
    final speedUnknown = p.speedUnknown;
    final speed = p.displaySpeed;
    final Color fg = unplugged
        ? AppColors.textLow
        : (speedUnknown ? AppColors.success : _speedColor(speed));
    final Color bg = unplugged ? AppColors.bg : AppColors.brandSoftBg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: Sp.xs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Text(
        _lanPortText(p),
        textDirection: speedUnknown ? TextDirection.rtl : TextDirection.ltr,
        style: AppType.pillLabel(color: fg).copyWith(letterSpacing: 0),
      ),
    );
  }

  static Color _speedColor(String speed) {
    if (speed.contains('Gbps')) return AppColors.brandAccent;
    final m = RegExp(r'(\d+)\s*Mbps').firstMatch(speed);
    final mbps = m == null ? null : int.tryParse(m.group(1)!);
    if (mbps == null) return AppColors.textMid;
    return mbps >= 100 ? AppColors.brandAccent : AppColors.warningFill;
  }

  static Color _healthColor(String h) {
    switch (h) {
      case 'good':
        return AppColors.brandAccent;
      case 'warn':
        return AppColors.warningFill;
      case 'bad':
        return AppColors.error;
      default:
        return AppColors.textHi;
    }
  }

  static String _rate(int? kbps) {
    if (kbps == null || kbps == 0) return '—';
    if (kbps >= 1000) return '${(kbps / 1000).toStringAsFixed(1)} Mbps';
    return '$kbps Kbps';
  }

  /// «39.0 / 72.2 Mbps» — الوحدة مرّةً واحدة في الآخر.
  ///
  /// تكرارها («39.0 Mbps / 72.2 Mbps») يضيف ٥ محارف بلا معلومة، وهي
  /// نفسها المحارف التي كانت تُقصّ سرعة الاستقبال على الشاشات الضيّقة.
  /// وتختلف الوحدتان؟ حينها نكتبهما كاملتين — الصدق قبل الاختصار.
  static String _ratePair(int? txKbps, int? rxKbps) {
    final tx = txKbps ?? 0;
    final rx = rxKbps ?? 0;
    bool isMb(int v) => v >= 1000;
    String num(int v) =>
        isMb(v) ? (v / 1000).toStringAsFixed(1) : v.toString();
    if (tx == 0 && rx == 0) return '—';
    if (tx == 0 || rx == 0 || isMb(tx) != isMb(rx)) {
      return '${_rate(txKbps)} / ${_rate(rxKbps)}';
    }
    return '${num(tx)} / ${num(rx)} ${isMb(tx) ? 'Mbps' : 'Kbps'}';
  }

  /// «10 أيّام و3 ساعات و25 دقيقة» — بصيغة عربيّة سليمة.
  ///
  /// 🐛 كانت «10 يوم 3 س»: مفردٌ بعد العشرة، واختصاراتٌ بلا رابط.
  /// والعربيّة تُميّز المفرد والمثنّى وجمعَي القلّة والكثرة، وتجاهلُها
  /// يجعل النصّ يبدو آليّاً في شاشةٍ عربيّةٍ بالكامل.
  static String _uptime(int seconds) {
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final parts = <String>[
      if (d > 0) _plural(d, 'يوم', 'يومان', 'أيّام', 'يوماً'),
      if (h > 0) _plural(h, 'ساعة', 'ساعتان', 'ساعات', 'ساعة'),
      if (m > 0 && d == 0) _plural(m, 'دقيقة', 'دقيقتان', 'دقائق', 'دقيقة'),
    ];
    if (parts.isEmpty) return 'أقلّ من دقيقة';
    return parts.join(' و');
  }

  /// تصريف العدد في العربيّة: الواحد والاثنان بلا رقم، ومن ثلاثةٍ إلى
  /// عشرةٍ جمعُ قلّة، وما فوقها مفردٌ منصوب (تمييز).
  static String _plural(
      int n, String one, String two, String few, String many) {
    if (n == 1) return one;
    if (n == 2) return two;
    if (n <= 10) return '$n $few';
    return '$n $many';
  }

  /// «قبل ٣ د» — عمر آخر قراءة ناجحة.
  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inSeconds < 45) return 'الآن';
    if (d.inMinutes < 60) return 'قبل ${d.inMinutes} د';
    if (d.inHours < 24) return 'قبل ${d.inHours} س';
    return 'قبل ${d.inDays} يوم';
  }
}

/// أيقونة نسخٍ صغيرة تُلصق بقيمة صفّ التفصيل.
class _CopyIcon extends StatelessWidget {
  const _CopyIcon({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      radius: 16,
      onTap: () => copyToClipboard(context, value, label: label),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(LucideIcons.copy, size: 13, color: AppColors.textLabel),
      ),
    );
  }
}

/// زرّ أيقوني في رأس الكارت — 18dp بلا خلفيّة، كما في المخطّط.
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.icon,
    this.onTap,
    this.busy = false,
    this.color,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final bool busy;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Padding(
        padding: const EdgeInsets.all(Sp.xs),
        child: SizedBox(
          width: 18,
          height: 18,
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(1.5),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.textLow),
                )
              : Icon(icon, size: 18, color: color ?? AppColors.textLow),
        ),
      ),
    );
  }
}

/// البلاطة الغاطسة للقياس — تسمية 10.5 فوق قيمة 14/w700 ملوّنة دلاليّاً.
/// تسميتها وقيمتها من [field] الذي يُنسخ بالضغط المطوّل — ما يُرى يُنسخ.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.field,
    required this.color,
    this.icon,
    this.parts,
    this.fit = false,
  });
  final CopyField field;
  final Color color;
  final IconData? icon;

  /// القيمة تُصغَّر لتتّسع (نصف بلاطة) بدل أن تُقصّ.
  final bool fit;

  /// قيمةٌ بألوان (التحميل/الرفع، RX/TX) — المالك ٢٢ أكتوبر: «خلّي الأبلود يختلف عن الداونلود للتمييز، وكذلك RX/TX».
  /// النسخ يبقى نصّ [field].
  final List<({String text, Color color})>? parts;

  String get label => field.label;
  String get value => field.value;

  @override
  Widget build(BuildContext context) {
    return Copyable.field(
      field,
      radius: R.icon,
      child: _tile(),
    );
  }

  Widget _fitted(Widget text) => fit
      ? FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: text,
        )
      : text;

  Widget _tile() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.icon),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: AppColors.textLabel),
                const SizedBox(width: Sp.xs),
              ],
              Flexible(
                child: Text(label,
                    style: AppType.micro(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: Sp.xxs),
          _fitted(parts == null
              ? Text(
                  value,
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                  overflow: fit ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: AppType.cardTitle(color: color)
                      .copyWith(fontWeight: FontWeight.w700),
                )
              : Text.rich(
                  TextSpan(children: [
                    for (final p in parts!)
                      TextSpan(
                        text: p.text,
                        style: AppType.cardTitle(color: p.color)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                  ]),
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                  overflow: fit ? TextOverflow.visible : TextOverflow.ellipsis,
                )),
        ],
      ),
    );
  }
}

/// صفّ تفصيل — تسمية خافتة يمين وقيمة `ltr` يسار. الصفّ كلّه يُنسخ
/// بالضغط المطوّل ([field]).
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.field,
    this.strong = false,
    this.small = false,
    this.trailing,
    this.rtlValue = false,
  });
  final CopyField field;

  String get label => field.label;
  String get value => field.value;

  /// ودجة تُلصق بعد القيمة (زرّ نسخ مثلاً). تأخذ مقاسها الطبيعيّ
  /// فقط، فلا تُزاحم القيمة على العرض.
  final Widget? trailing;

  /// القيم العربيّة (مدّة التشغيل) تُعرَض باتّجاه عربيّ؛ الإجبار على
  /// `ltr` يقلب ترتيب كلماتها. أمّا العناوين والأرقام فتبقى `ltr`.
  final bool rtlValue;

  /// أوّل صفّ في المجموعة (نوع الجهاز) بلون نصّ عالٍ.
  final bool strong;

  /// القيم الطويلة (firmware / SSID / MAC) بدرجة أصغر حتى لا تلتفّ.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final style = small
        ? AppType.body(color: AppColors.textBody).copyWith(fontSize: 11.5)
        : AppType.body(
            color: strong ? AppColors.textHi : AppColors.textBody,
          );
    return Copyable.field(field, child: _row(style));
  }

  Widget _row(TextStyle style) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.xs),
      child: Row(
        children: [
          // ⚠️ التسمية **بلا مرونة**، والقيمة `Expanded` تبتلع الباقي.
          //
          // 🐛 كانت التسمية `Flexible(1)` والقيمة `Expanded(1)` —
          // فيقتسمان مناصفةً، والفضفاض الذي يأخذ أقلّ لا يُعيد الباقي.
          // فـSSID طويلٌ يُقصّ عند النصف بينما «SSID» يشغل خُمس نصفه.
          //
          // والتسميات هنا ثوابتُ قصيرة («SSID» · «Peer MAC» · «نوع
          // الجهاز») لا تتجاوز عشرة محارف — فتثبيتُها آمن، والقيمة هي
          // المتغيّرة فتستحقّ كلّ ما تبقّى. البيانات أثمن من عنوانها،
          // وهذا هو تحقيق تلك النيّة لا نقضُها.
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.body(color: AppColors.textLabel),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Text(
              value,
              // الطرف الأيسر لكلّ القيم: الصفّ عربيّ فالتسمية يميناً،
              // والقيم كانت تلتصق بها وتترك فراغاً يسارها. توحيدُها
              // على الحافّة يجعل الأرقام في عمودٍ واحد تُقرأ مسحاً.
              textAlign: rtlValue ? TextAlign.end : TextAlign.left,
              textDirection:
                  rtlValue ? TextDirection.rtl : TextDirection.ltr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: Sp.x6),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// هيكل نابض — بلاطة القياس أثناء الفحص.
class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.icon),
      ),
    );
  }
}

/// هيكل نابض — سطر تفصيل أثناء الفحص.
class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.widthFactor});
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: 12,
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(R.pill),
          ),
        ),
      ),
    );
  }
}

/// صياغة معدّل بالبت/ثانية بوحدة مقروءة.
///
/// منزلة عشريّة واحدة: البلاطة ضيّقة، ومنزلتان تدفعان النصّ للقصّ في
/// «↓12.34 ↑3.45».
/// يُنسّق معدّلاً بالبت/ثانية.
///
/// 🐛 كان يفتح بـ`if (bps < 1000) return '0K';` — فمشتركٌ يسحب 400 إلى
/// 999 بت/ث يُعرَض «0K»، وهو **بصريّاً مطابق** للوصلة الميّتة. فيستنتج
/// المدير أنّ المشترك لا يسحب شيئاً وقد يقطعه. جوابٌ خاطئ بثقة، لا نقص.
///
/// و«0K» ليست أقصر ممّا يستحقّ: بعد أن أخذت بلاطة الترافيك العرض
/// الكامل (2026-08-31) صار الفارق بين «0K» و«587b» بلا أثر على التخطيط.
@visibleForTesting
String fmtBpsForTest(int bps) => _fmtBps(bps);

/// «3.4 Mbps» / «37 Kbps» — معدّلٌ بوحدةٍ صريحة لبلاطة ترافيك الـONU.
String formatBpsUnit(int bps) {
  if (bps < 1000) return '${bps < 0 ? 0 : bps} bps';
  if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(0)} Kbps';
  if (bps < 1000000000) return '${(bps / 1000000).toStringAsFixed(1)} Mbps';
  return '${(bps / 1000000000).toStringAsFixed(2)} Gbps';
}

String _fmtBps(int bps) {
  if (bps <= 0) return '0';
  if (bps < 1000) return '${bps}b'; // الصدق أهمّ من التوحيد
  if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(0)}K';
  if (bps < 1000000000) return '${(bps / 1000000).toStringAsFixed(1)}M';
  return '${(bps / 1000000000).toStringAsFixed(1)}G';
}

// ─────────────────── القراءات كما تُنسخ ───────────────────
//
// كلّ قراءةٍ في الكارت `CopyField` واحد: منه ترسم البلاطة أو الصفّ
// تسميتها وقيمتها، ومنه يُنسخ بالضغط المطوّل، ومنه يبني «نسخ كلّ
// المعلومات» في صفحة المشترك سطوره — فلا تختلف تسميةٌ ولا وحدة.

CopyField _ontRx(OntOpticalInfo o) => CopyField('RX Power', '${o.rxPower} dBm');

CopyField _ontTx(OntOpticalInfo o) => CopyField('TX Power', '${o.txPower} dBm');

CopyField _ontRxTx(OntOpticalInfo o) => CopyField('RX / TX (dBm)', '${o.rxPower} / ${o.txPower}');

CopyField _ontVoltage(OntOpticalInfo o) =>
    CopyField('الفولتية', '${o.voltage} mV');

CopyField _ontTemp(OntOpticalInfo o) =>
    CopyField('الحرارة', '${o.temperature} °C');

/// هواوي كما كان؛ وZTE بطرازه كما يسمّيه الجهاز («ZTE MH80»).
CopyField _ontKind(OntOpticalInfo o) => o.isZte
    ? CopyField('نوع الجهاز', o.model.isEmpty ? 'ZTE ONT' : 'ZTE ${o.model}')
    : const CopyField('نوع الجهاز', 'Huawei ONT');

/// «--» يرسله الـONT حين لا حالة — ليست قيمة.
bool _ontHasFiber(OntOpticalInfo o) =>
    o.sendStatus.trim().isNotEmpty && o.sendStatus.trim() != '--';

CopyField _ontFiber(OntOpticalInfo o) => CopyField('حالة الليف', o.sendStatus);

CopyField _ubntSignal(UbiquitiStatus u) =>
    CopyField('الإشارة', '${u.signalDbm} dBm');

CopyField _ubntCcq(UbiquitiStatus u) => CopyField('CCQ', '${u.ccqPercent}%');

CopyField _ubntKind(UbiquitiStatus u) => CopyField(
      'نوع الجهاز',
      u.hostname.isEmpty ? 'Ubiquiti' : '${u.hostname} (UBNT)',
    );

CopyField _ubntFirmware(UbiquitiStatus u) => CopyField('الإصدار', u.firmware);

CopyField _ubntSsid(UbiquitiStatus u) => CopyField('SSID', u.ssid);

CopyField _ubntUptime(UbiquitiStatus u) => CopyField(
      'مدّة التشغيل',
      _DeviceProbeCardState._uptime(u.uptimeSeconds ?? 0),
    );

bool _ubntHasRates(UbiquitiStatus u) =>
    (u.txRateKbps ?? 0) > 0 || (u.rxRateKbps ?? 0) > 0;

CopyField _ubntRates(UbiquitiStatus u) => CopyField(
      'TX / RX',
      _DeviceProbeCardState._ratePair(u.txRateKbps, u.rxRateKbps),
    );

CopyField _ubntPeerMac(UbiquitiStatus u) =>
    CopyField('Peer MAC', u.peerMac ?? '');

/// «ETH0 · 100 Mbps» — نصّ حبّة المنفذ كما تُرسم.
String _lanPortText(LanPort p) =>
    '${p.label} · ${p.plugged ? p.displaySpeed : 'مفصول'}';

CopyField _lanPortsField(List<LanPort> ports) => CopyField(
      'المنافذ',
      ports.map(_lanPortText).join('، '),
      noun: 'حالة المنافذ',
    );

/// ملاحظة المدير على جهاز المشترك (إعداد الجهاز) — سطر الكارت الكهرمانيّ.
CopyField deviceNoteField(String notes) =>
    CopyField('ملاحظة الجهاز', notes.trim(), noun: 'الملاحظة');

/// قراءات الجهاز بتسميات الكارت ووحداته — نوع الجهاز أوّلاً ثمّ قراءاته —
/// لـ«نسخ كلّ المعلومات».
///
/// ⚠️ بلا الترافيك اللحظيّ: معدّلُ ثانيةٍ يكذب في رسالةٍ تُقرأ بعد دقيقة.
/// (بلاطته تُنسخ وحدها بالضغط المطوّل لمن أراد اللحظة نفسها.)
///
/// و[at] وقت القراءة يُذكر معها — قراءةٌ عمرها ساعة لا تُرسَل كأنّها الآن.
List<CopyField> deviceCopyFields(DeviceHealthSnapshot snap, {DateTime? at}) {
  final fields = <CopyField>[];
  final ont = snap.ont;
  final u = snap.ubnt;
  if (snap.kind == DeviceKind.ont && ont != null) {
    fields.addAll([
      _ontKind(ont),
      _ontRx(ont),
      _ontTx(ont),
      _ontVoltage(ont),
      _ontTemp(ont),
      if (_ontHasFiber(ont)) _ontFiber(ont),
    ]);
  } else if (snap.kind == DeviceKind.ubiquiti && u != null) {
    fields.addAll([
      _ubntKind(u),
      if (u.signalDbm != null) _ubntSignal(u),
      if (u.ccqPercent != null) _ubntCcq(u),
      if (u.firmware.isNotEmpty) _ubntFirmware(u),
      if (u.ssid.isNotEmpty) _ubntSsid(u),
      if ((u.uptimeSeconds ?? 0) > 0) _ubntUptime(u),
      if (_ubntHasRates(u)) _ubntRates(u),
      if (u.peerMac != null && u.peerMac!.isNotEmpty) _ubntPeerMac(u),
      if (u.lanPorts.isNotEmpty) _lanPortsField(u.lanPorts),
    ]);
  }
  if (fields.isNotEmpty && at != null) {
    String two(int n) => n.toString().padLeft(2, '0');
    fields.add(CopyField(
      'وقت قراءة الجهاز',
      '${at.year}/${two(at.month)}/${two(at.day)} '
          '${two(at.hour)}:${two(at.minute)}',
    ));
  }
  return fields;
}
