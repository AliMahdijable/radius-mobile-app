import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/device_config_api.dart';
import '../../../api/device_probe_api.dart';
import '../../../api/ubnt_api.dart';
import '../../../core/net/huawei_ont_service.dart';
import '../../../core/net/ont_traffic.dart';
import '../../../core/net/router_ops.dart';
import '../../../core/net/router_types.dart';
import '../../../core/net/tenda_service.dart';
import '../../../core/net/tplink_classic_service.dart';
import '../../../core/net/tplink_pharos_service.dart';
import '../../../services/agent_net_presence.dart';
import '../../../services/subscriber_refresh_signal.dart';
import '../../../services/vpn_now.dart';
import '../../../widgets/vpn_now_bar.dart' show VpnTag;
import '../../../core/widgets/metric_tile.dart';
import '../../../core/util/clipboard_helper.dart';
import '../../../core/widgets/copyable.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../services/merged_mode.dart';
import '../../../services/permissions_service.dart';
import '../../../models/device_health.dart';
import '../sheets/device_config_sheet.dart';
import 'device_chip_micro.dart' show DeviceProbeBus;
import 'router_wifi_panel.dart';
import 'subscriber_traffic_chart.dart';
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
    this.slot = 1,
  });

  /// 1 = جهاز المشترك (آيبي الجلسة أو المخصّص)، 2 = «الجهاز الثاني» (نانو + راوتر — عنوانه واعتماده من إعداد المشترك).
  final int slot;

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

  /// بنگ سريع مستقلّ عن الفحص الكامل: `true` واصل · `false` غير واصل ·
  /// `null` لم يُحسم بعد (أو لا عنوان) — يملأ الحبّة فوراً قبل أن يكمل الفحص.
  bool? _reach;
  String? _notes;

  /// قائمة المتّصلين بالراوتر (آيبي/ماك/اسم) مطويّةٌ افتراضاً — تنفتح بنقر الوكيل فقط (المالك ١١ نوفمبر).
  bool _clientsExpanded = false;

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

  /// TP-Link (١٠ نوفمبر): جلسة ويب واحدة لعمر الكرت، وكلّ نبضةٍ قراءةٌ خفيفة فيها ترافيك الجهاز الآن **والإشارة والجودة
  /// والمنافذ** معاً ([PharosLiveSession]). للجهاز جلسةٌ واحدة: إن طُردنا (دخل أحدٌ صفحته) نُغلق وننتظر — الخدمة نفسها
  /// تمنع الدخول دقيقتين ثمّ عشراً — ولا نطارده.
  static const _tpRetry = Duration(seconds: 15);
  PharosLiveSession? _tpSession;
  DateTime? _tpRetryAt;

  bool get _isTplink => _snap?.kind == DeviceKind.ubiquiti && (_snap?.ubnt?.isTplink ?? false);

  /// راوتر TP-Link الكلاسيكيّ (١١ نوفمبر): مصادقة Basic بلا جلسة — كلّ نبضةٍ صفحة الحالة وحدها (~٠٫٧ث: عدّادات WAN ومدّتا
  /// التشغيل والاتّصال)، وكلّ [_tcClientsEvery] نبضاتٍ صفحة الوايرلس (المتّصلون الآن). المعدّل = فرق عيّنتين.
  bool get _isTpClassic => _snap?.kind == DeviceKind.ubiquiti && (_snap?.ubnt?.isTpClassic ?? false);
  static const _tcClientsEvery = 4;
  TpClassicLive? _tcLast;
  int _tcPulses = 0;
  DateTime? _tcRetryAt;

  /// راوتر Tenda (١٢ نوفمبر): النبضة جلسةٌ قصيرة (دخول، الحالة، خروج) — الترافيك جاهزٌ منه، والمتّصلون ومدّة الاتّصال معه.
  bool get _isTenda => _snap?.kind == DeviceKind.ubiquiti && (_snap?.ubnt?.isTenda ?? false);

  /// راوترٌ بنبضةٍ حيّة بجلسةٍ مفتوحة (MER — Archer C64/C80، ١٢ نوفمبر): دخولٌ مرّة، ثمّ كلّ نبضةٍ عدّادات WAN (المعدّل فرق عيّنتين)
  /// ومدّة الاتّصال، والمتّصلون كلّ بضع نبضات ([RouterOps.openLive]).
  bool get _isRouterLive => _snap?.kind == DeviceKind.ubiquiti && RouterOps.hasLive(_snap?.ubnt?.vendor ?? '');
  RouterLive? _rlSession;
  RouterSample? _rlPrev;
  DateTime? _rlRetryAt;

  /// عمليّة واي فاي جارية على الراوتر: النبضات تتوقّف (دخولها يُسقط جلسة العمليّة أو العكس)، وبعدها تُفتح جلسةٌ حيّة جديدة فوراً.
  bool _routerOp = false;

  void _routerOpBusy(bool busy) {
    _routerOp = busy;
    if (!busy) {
      _closeRouterLive(); // جلستها سقطت بدخول العمليّة — تُفتح غيرها في النبضة التالية بلا مهلة
      _rlRetryAt = null;
      _tcRetryAt = null;
    }
  }

  void _closeRouterLive() {
    final s = _rlSession;
    _rlSession = null;
    _rlPrev = null;
    if (s != null) unawaited(s.close());
  }
  int? _lastRx;
  int? _lastTx;
  DateTime? _lastSample;
  int? _rxBps;
  int? _txBps;
  bool _pulsing = false;
  final _trafficHistory = SubscriberTrafficHistory();
  bool _trafficPaused = false;
  bool _trafficFailed = false;
  int _trafficEpoch = 0;

  bool _trafficCurrent(int epoch) => mounted && !_trafficPaused && epoch == _trafficEpoch;

  void _recordTraffic(int down, int up) {
    setState(() {
      _rxBps = down;
      _txBps = up;
      _trafficFailed = false;
      _trafficHistory.add(DateTime.now(), down, up);
    });
  }

  void _loseTraffic() {
    if (!mounted) return;
    setState(() {
      _rxBps = null;
      _txBps = null;
      _trafficFailed = true;
      _lastRx = null;
      _lastTx = null;
      _lastSample = null;
      _trafficHistory.gap(DateTime.now());
    });
  }

  void _stopTraffic({bool clear = false}) {
    _trafficEpoch++;
    _trafficFailed = false;
    _trafficTimer?.cancel();
    _trafficTimer = null;
    _session?.close();
    _session = null;
    _closeOntTraffic();
    _ontRetryAt = null;
    _closeTplink();
    _tpRetryAt = null;
    _closeRouterLive();
    _rxBps = null;
    _txBps = null;
    _lastRx = null;
    _lastTx = null;
    _lastSample = null;
    if (clear) {
      _trafficHistory.clear();
    } else {
      _trafficHistory.gap(DateTime.now());
    }
  }

  Widget _trafficChart() => SubscriberTrafficChart(
    samples: _trafficHistory.samples, downBps: _rxBps, upBps: _txBps, unavailable: _trafficFailed,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SubscriberRefreshSignal.tick.addListener(_onPullRefresh);
    // ٦ نوفمبر: «وضع VPN» ونتائج فحصه ⇒ الكرت يعرض قراءة الـVPN بدل «غير واصل»
    VpnNow.version.addListener(_onVpn);
    VpnNow.mode.addListener(_onVpn);
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
      slot: widget.slot,
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

  @override
  void didUpdateWidget(DeviceProbeCard old) {
    super.didUpdateWidget(old);
    // وصل عنوان المشترك بعد الفتح (من جلسة الساس)، أو تبدّل ⇒ أعد البنگ.
    if (old.ip != widget.ip || old.username != widget.username || old.company != widget.company) {
      _stopTraffic(clear: true);
      _maybeStartTraffic();
      _checkReach(force: true);
    }
  }

  /// بنگ سريع — مستقلٌّ عن الفحص الكامل: يُظهر «واصل/لا» خلال ~ثانية بدل
  /// انتظار الدخول والقراءة. لا ينتظر جلسة الساس (customIp يكفي).
  Future<void> _checkReach({bool force = false}) async {
    final r = await DeviceProbeApi.reachable(
      fallbackIp: widget.ip,
      subscriberUsername: widget.username,
      slot: widget.slot,
      company: widget.company,
      force: force,
    );
    if (mounted) setState(() => _reach = r);
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
    VpnNow.version.removeListener(_onVpn);
    VpnNow.mode.removeListener(_onVpn);
    SubscriberRefreshSignal.tick.removeListener(_onPullRefresh);
    WidgetsBinding.instance.removeObserver(this);
    _stopTraffic();
    _signalTimer?.cancel();
    _agoTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ⚠️ بدون هذا يبقى المؤقّت يطرق جهاز المشترك كلّ 3 ثوانٍ والتطبيق
    // في الخلفيّة — شاشة التفاصيل كانت خالية من أيّ مراقب دورة حياة.
    if (state == AppLifecycleState.resumed) {
      setState(() => _trafficPaused = false);
      _maybeStartTraffic();
      _maybeStartSignal();
    } else {
      _trafficPaused = true;
      _stopTraffic();
      _signalTimer?.cancel();
      _signalTimer = null;
      _agoTimer?.cancel();
      _agoTimer = null;
    }
  }

  /// إعادة فحصٍ دوريّة للإشارة — لأجهزة Ubiquiti وحدها.
  ///
  /// ONT مستثناة كما في الترافيك: عميل Huawei يكشط صفحة ومهلاته ١٥
  /// ثانية، فطرقُه كلّ عشر ثوانٍ يُنتج طابوراً لا تحديثاً.
  void _maybeStartSignal() {
    if (_signalTimer != null) return;
    if (_snap?.kind != DeviceKind.ubiquiti) return;
    _signalTimer = Timer.periodic(_signalPulse, (_) {
      // TP-Link: الفحص الدوريّ يقرأ بجلسة الكرت الحيّة (طلبٌ واحد). بلاها يكون دخولاً وخروجاً كاملين كلّ عشر ثوانٍ على
      // معالج الجهاز — والنبضة الحيّة نفسها تعيد فتح الجلسة وتحدّث الإشارة، فلا حاجة له.
      if (_isTplink && !TplinkPharosService.hasLive(_snap!.ip)) return;
      // الراوتر الكلاسيكيّ وTenda: نبضتهما الحيّة تحدّث المتّصلين والمدّة — فحصٌ كاملٌ فوقها حملٌ بلا فائدة على معالجٍ صغير.
      if ((_isTpClassic || _isTenda || _isRouterLive) && _trafficTimer != null) return;
      _refreshQuietly(force: true);
    });
    // عدّاد «آخر تحديث» يتقدّم بنفسه ولو لم يصل جديد — وإلّا جمد
    // النصّ على «قبل ٣ د» بينما الوقت يمضي.
    _agoTimer ??= Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  void _maybeStartTraffic() {
    if (_trafficTimer != null || _trafficPaused) return;
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
    if (snap.ubnt?.isTplink ?? false) {
      // TP-Link: لا SSH — صفحة الجهاز نفسها تعطي معدّل الترافيك جاهزاً.
      _pulseTplink();
      _trafficTimer = Timer.periodic(_pulse, (_) => _pulseTplink());
      return;
    }
    if (snap.ubnt?.isTpClassic ?? false) {
      // الراوتر الكلاسيكيّ: لا SSH ولا معدّلٌ جاهز — عدّادات WAN من صفحة الحالة، والمعدّل فرق عيّنتين.
      _tcLast = null;
      _tcPulses = 0;
      _pulseTpClassic();
      _trafficTimer = Timer.periodic(_pulse, (_) => _pulseTpClassic());
      return;
    }
    if (snap.ubnt?.isTenda ?? false) {
      // Tenda: الترافيك جاهزٌ من صفحة الحالة (KB/s) — لا فرق عدّادات.
      _pulseTenda();
      _trafficTimer = Timer.periodic(_pulse, (_) => _pulseTenda());
      return;
    }
    if (RouterOps.hasLive(snap.ubnt?.vendor ?? '')) {
      _rlPrev = null;
      _pulseRouterLive();
      _trafficTimer = Timer.periodic(_pulse, (_) => _pulseRouterLive());
      return;
    }
    if (snap.ubnt?.isRouter ?? false) {
      // راوترٌ بلا نبضةٍ حيّة بعد: لا جلسة SSH النانو عليه (منفذٌ مقفول ودخولٌ بـubnt) — «تعذّرت قراءة الترافيك» صراحةً.
      _loseTraffic();
      return;
    }
    _pulseTraffic(); // نبضة فوريّة تزرع المرجع بلا انتظار 3 ثوانٍ
    _trafficTimer = Timer.periodic(_pulse, (_) => _pulseTraffic());
  }

  /// نبضة TP-Link: الجلسة تُفتح مرّةً (بالاعتماد الذي دخل به الفحص)، ثمّ قراءةٌ خفيفة واحدة تحدّث الترافيك والإشارة معاً.
  Future<void> _pulseTplink() async {
    if (_pulsing || !mounted || _trafficPaused) return;
    final epoch = _trafficEpoch;
    final retryAt = _tpRetryAt;
    if (_tpSession == null && retryAt != null && DateTime.now().isBefore(retryAt)) return;
    _pulsing = true;
    try {
      if (_tpSession == null) {
        final creds = await DeviceProbeApi.resolveTplinkCreds(
          fallbackIp: widget.ip,
          subscriberUsername: widget.username,
      slot: widget.slot,
          company: widget.company,
        );
        if (!_trafficCurrent(epoch)) return;
        if (creds == null) {
          _loseTraffic();
          _tpRetryAt = DateTime.now().add(_tpRetry);
          return;
        }
        final session = await PharosLiveSession.open(ip: creds.ip, user: creds.user, pass: creds.pass);
        if (!_trafficCurrent(epoch)) {
          if (session != null) unawaited(session.close());
          return;
        }
        if (session == null) {
          // مشغول/مرفوض/لا يجاوب — الخدمة تحفظ السبب ومهلته؛ نعيد السؤال بعد قليل بلا طرقٍ على الجهاز.
          _loseTraffic();
          _tpRetryAt = DateTime.now().add(_tpRetry);
          return;
        }
        _tpSession = session;
      }
      final sess = _tpSession!;
      final live = await sess.sample();
      if (!_trafficCurrent(epoch)) return;
      if (live == null) {
        // طُردنا (أحدٌ دخل صفحة الجهاز) أو تعثّرت ثلاث قراءات: نُغلق ولا يبقى رقمٌ قديم معروضاً كأنّه الآن.
        if (sess.lost || sess.misses >= 3) {
          _closeTplink();
          _tpRetryAt = DateTime.now().add(_tpRetry);
        }
        _loseTraffic();
        return;
      }
      final snap = _snap;
      final u = snap?.ubnt;
      if (snap != null && u != null && u.isTplink) {
        setState(() {
          _snap = DeviceHealthSnapshot(kind: snap.kind, ip: snap.ip, ubnt: live.applyTo(u));
          _lastAt = DateTime.now();
        });
      }
      final down = live.downBps;
      final up = live.upBps;
      if (down != null && up != null) _recordTraffic(down, up);
    } catch (_) {
      if (_trafficCurrent(epoch)) {
        _closeTplink();
        _tpRetryAt = DateTime.now().add(_tpRetry);
        _loseTraffic();
      }
    } finally {
      _pulsing = false;
    }
  }

  void _closeTplink() {
    final s = _tpSession;
    _tpSession = null;
    if (s != null) unawaited(s.close());
  }

  /// نبضة الراوتر الكلاسيكيّ: صفحة الحالة (عدّادات WAN + مدّة التشغيل + مدّة الاتّصال) كلّ نبضة، وصفحة الوايرلس كلّ
  /// [_tcClientsEvery] نبضات. بالاعتماد الذي دخل به الفحص ([DeviceProbeApi.resolveTplinkCreds]). تعثّرٌ ⇒ لا رقمٌ قديم يُعرض
  /// كأنّه الآن، ومهلة [_tpRetry] قبل السؤال ثانيةً.
  Future<void> _pulseTpClassic() async {
    if (_pulsing || !mounted || _trafficPaused || _routerOp) return;
    final epoch = _trafficEpoch;
    final retryAt = _tcRetryAt;
    if (retryAt != null && DateTime.now().isBefore(retryAt)) return;
    _pulsing = true;
    try {
      final creds = await DeviceProbeApi.resolveTplinkCreds(
        fallbackIp: widget.ip,
        subscriberUsername: widget.username,
      slot: widget.slot,
        company: widget.company,
      );
      if (!_trafficCurrent(epoch)) return;
      if (creds == null) {
        _loseTraffic();
        _tcRetryAt = DateTime.now().add(_tpRetry);
        return;
      }
      // عيّنة الحالة (+ الوايرلس كلّ [_tcClientsEvery]) — الفيرموير الأحدث بجلسةٍ واحدةٍ لكلّ نبضة (دخول، صفحة، خروج).
      final wantClients = _tcPulses % _tcClientsEvery == 0;
      final got = await TplinkClassicService.pulse(creds.ip, creds.user, creds.pass, clients: wantClients);
      if (!_trafficCurrent(epoch)) return;
      final live = got.live;
      if (live == null) {
        _tcLast = null;
        _loseTraffic();
        _tcRetryAt = DateTime.now().add(_tpRetry);
        return;
      }
      _tcRetryAt = null;
      _tcPulses++;
      final clients = got.clients;
      final snap = _snap;
      final u = snap?.ubnt;
      if (snap != null && u != null && u.isTpClassic) {
        setState(() {
          _snap = DeviceHealthSnapshot(
            kind: snap.kind,
            ip: snap.ip,
            ubnt: u.withLive(
              uptimeSeconds: live.uptimeSeconds,
              wanOnlineSeconds: live.wanOnlineSeconds,
              peerCount: clients,
            ),
          );
          _lastAt = DateTime.now();
        });
      }
      final prev = _tcLast;
      _tcLast = live;
      final rate = prev == null ? null : tpClassicRate(prev, live);
      if (rate != null) _recordTraffic(rate.down, rate.up);
    } catch (_) {
      if (_trafficCurrent(epoch)) {
        _tcLast = null;
        _tcRetryAt = DateTime.now().add(_tpRetry);
        _loseTraffic();
      }
    } finally {
      _pulsing = false;
    }
  }

  /// نبضة Tenda: دخول ⇒ صفحة الحالة ⇒ خروج (الراوتر يقبل أربع جلساتٍ معاً فلا نطرد أحداً، ولا جلسةٌ تبقى لو أُغلق التطبيق).
  /// الترافيك جاهزٌ منه (KB/s ⇒ بت/ثانية)، ومعه عدد المتّصلين ومدّة الاتّصال. تعثّرٌ ⇒ لا رقمٌ قديم، ومهلةٌ قبل السؤال ثانيةً.
  Future<void> _pulseTenda() async {
    if (_pulsing || !mounted || _trafficPaused || _routerOp) return;
    final epoch = _trafficEpoch;
    final retryAt = _tcRetryAt;
    if (retryAt != null && DateTime.now().isBefore(retryAt)) return;
    _pulsing = true;
    try {
      final creds = await DeviceProbeApi.resolveTplinkCreds(
        fallbackIp: widget.ip,
        subscriberUsername: widget.username,
      slot: widget.slot,
        company: widget.company,
      );
      if (!_trafficCurrent(epoch)) return;
      if (creds == null) {
        _loseTraffic();
        _tcRetryAt = DateTime.now().add(_tpRetry);
        return;
      }
      final live = await TendaService.sample(creds.ip, creds.pass);
      if (!_trafficCurrent(epoch)) return;
      if (live == null) {
        _loseTraffic();
        _tcRetryAt = DateTime.now().add(_tpRetry);
        return;
      }
      _tcRetryAt = null;
      final snap = _snap;
      final u = snap?.ubnt;
      if (snap != null && u != null && u.isTenda) {
        setState(() {
          _snap = DeviceHealthSnapshot(
            kind: snap.kind,
            ip: snap.ip,
            ubnt: u.withLive(wanOnlineSeconds: live.wanOnlineSeconds, peerCount: live.online),
          );
          _lastAt = DateTime.now();
        });
      }
      final down = live.downBps;
      final up = live.upBps;
      if (down != null && up != null) _recordTraffic(down, up);
    } catch (_) {
      if (_trafficCurrent(epoch)) {
        _tcRetryAt = DateTime.now().add(_tpRetry);
        _loseTraffic();
      }
    } finally {
      _pulsing = false;
    }
  }

  /// نبضة الراوتر الحيّة (MER): الجلسة تُفتح مرّةً بالاعتماد الذي دخل به الفحص، ثمّ عيّنةٌ كلّ نبضة؛ المعدّل فرق عيّنتين. تعثّرٌ
  /// مكرّر أو طردٌ ⇒ تُغلق ومهلةٌ قبل فتح غيرها — ولا رقمٌ قديم يُعرض كأنّه الآن.
  Future<void> _pulseRouterLive() async {
    if (_pulsing || _probing || !mounted || _trafficPaused || _routerOp) return;
    final epoch = _trafficEpoch;
    final retryAt = _rlRetryAt;
    if (_rlSession == null && retryAt != null && DateTime.now().isBefore(retryAt)) return;
    final vendor = _snap?.ubnt?.vendor ?? '';
    _pulsing = true;
    try {
      if (_rlSession == null) {
        final c = await _routerCreds();
        if (!_trafficCurrent(epoch)) return;
        if (c == null) {
          _loseTraffic();
          _rlRetryAt = DateTime.now().add(_tpRetry);
          return;
        }
        final s = await RouterOps.openLive(vendor, c.ip, c.user, c.pass);
        if (!_trafficCurrent(epoch)) {
          if (s != null) unawaited(s.close());
          return;
        }
        if (s == null) {
          _loseTraffic();
          _rlRetryAt = DateTime.now().add(_tpRetry);
          return;
        }
        _rlSession = s;
        _rlPrev = null;
      }
      final sess = _rlSession!;
      final x = await sess.sample();
      if (!_trafficCurrent(epoch)) return;
      if (x == null) {
        if (sess.lost) {
          _closeRouterLive();
          _rlRetryAt = DateTime.now().add(_tpRetry);
        }
        _loseTraffic();
        return;
      }
      _rlRetryAt = null;
      final snap = _snap;
      final u = snap?.ubnt;
      if (snap != null && u != null && u.vendor == vendor && (x.wanOnlineSeconds != null || x.clients != null)) {
        setState(() {
          _snap = DeviceHealthSnapshot(
            kind: snap.kind,
            ip: snap.ip,
            ubnt: u.withLive(wanOnlineSeconds: x.wanOnlineSeconds, peerCount: x.clients?.length, clients: x.clients),
          );
          _lastAt = DateTime.now();
        });
      }
      final prev = _rlPrev;
      _rlPrev = x;
      if (x.downBps != null && x.upBps != null) {
        _recordTraffic(x.downBps!, x.upBps!);
      } else if (prev != null) {
        final r = routerRate(prev, x);
        if (r != null) _recordTraffic(r.down, r.up);
      }
    } catch (_) {
      if (_trafficCurrent(epoch)) {
        _closeRouterLive();
        _rlRetryAt = DateTime.now().add(_tpRetry);
        _loseTraffic();
      }
    } finally {
      _pulsing = false;
    }
  }

  /// نبضة ترافيك الـONU: جلسةٌ تُفتح مرّةً (باعتمادات شركة المشترك وعنوانه المثبَّت — كالفحص حرفاً)، ثمّ قراءةٌ ومعدّل.
  Future<void> _pulseOntTraffic() async {
    // فحصٌ جارٍ يدخل على الجهاز نفسه — دخولنا الآن يطرده (جلسةٌ واحدة) أو يطردنا؛ ننتظر النبضة التالية
    if (_pulsing || _probing || !mounted || _trafficPaused) return;
    final epoch = _trafficEpoch;
    final retryAt = _ontRetryAt;
    if (_ontSession == null && retryAt != null && DateTime.now().isBefore(retryAt)) return;
    _pulsing = true;
    try {
      if (_ontSession == null) {
        final creds = await DeviceProbeApi.resolveOntCreds(
          fallbackIp: widget.ip,
          subscriberUsername: widget.username,
      slot: widget.slot,
          company: widget.company,
        );
        if (!_trafficCurrent(epoch)) return;
        if (creds == null) { _loseTraffic(); return; }
        final session = await OntTrafficSession.open(
          ip: creds.ip,
          user: creds.user,
          pass: creds.pass,
          // ZTE (٢٥ أكتوبر) بجلسته وصفحاته؛ وإلّا هواوي كما كان
          vendor: _snap?.ont?.vendor ?? 'huawei',
        );
        if (!_trafficCurrent(epoch)) { if (session != null) unawaited(session.close()); return; }
        _ontSession = session;
        if (_ontSession == null) {
          _loseTraffic();
          _ontRetryAt = DateTime.now().add(_ontRetry);
          return;
        }
        if (!mounted) {
          _closeOntTraffic();
          return;
        }
      }
      final counters = await _ontSession?.sample();
      if (!_trafficCurrent(epoch)) return;
      if (counters == null) {
        // طُردنا (دخولٌ آخر على الجهاز) أو انتهت الجلسة — دخولٌ جديد بعد المهلة، ولا يبقى رقمٌ قديم معروضاً كأنّه الآن
        _closeOntTraffic();
        _ontRetryAt = DateTime.now().add(_ontRetry);
        _loseTraffic();
        return;
      }
      final r = _ontMeter.add(counters, DateTime.now());
      // القراءة الأولى تزرع المرجع: الثانية بعد ٣ث لا عند النبضة التالية — أوّل رقمٍ أسرع، والمدّة كافية للدقّة
      if (r == null) Timer(const Duration(seconds: 3), _pulseOntTraffic);
      if (r != null && mounted) {
        _recordTraffic(r.downBps, r.upBps);
      }
    } catch (_) {
      if (_trafficCurrent(epoch)) {
        _closeOntTraffic();
        _ontRetryAt = DateTime.now().add(_ontRetry);
        _loseTraffic();
      }
    } finally {
      _pulsing = false;
    }
  }

  void _closeOntTraffic() {
    final s = _ontSession;
    _ontSession = null;
    _ontMeter.reset();
    if (s != null) unawaited(s.close());
  }

  Future<void> _pulseTraffic() async {
    if (_pulsing || !mounted || _trafficPaused) return;
    final epoch = _trafficEpoch;
    _pulsing = true;
    try {
      // الجلسة تُفتح مرّة وتُعاد. الأمر الوحيد في كلّ نبضة هو
      // `cat /proc/net/dev` — بضع مئات من البايتات وتفرّع عمليّة واحدة.
      if (_session == null) {
        final creds = await DeviceProbeApi.resolveUbntCreds(
          fallbackIp: widget.ip,
          subscriberUsername: widget.username,
      slot: widget.slot,
          company: widget.company,
        );
        if (!_trafficCurrent(epoch)) return;
        if (creds == null) { _loseTraffic(); return; }
        final session = await UbntTrafficSession.open(
          ip: creds.ip,
          user: creds.user,
          pass: creds.pass,
        );
        if (!_trafficCurrent(epoch)) { session?.close(); return; }
        _session = session;
      }
      final sess = _session;
      if (sess == null) { _loseTraffic(); return; }

      final read = await sess.sample();
      if (!_trafficCurrent(epoch)) return;
      if (read == null) {
        // الجلسة ماتت غالباً (انقطاع أو مهلة الجهاز) — نُغلقها ليُعاد
        // فتحها في النبضة القادمة بدل الإصرار على قناة ميّتة.
        sess.close();
        _session = null;
        _loseTraffic();
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
            _recordTraffic(r, t);
          }
        }
      }
      _lastRx = read.down;
      _lastTx = read.up;
      _lastSample = now;
    } catch (_) {
      if (_trafficCurrent(epoch)) {
        _session?.close();
        _session = null;
        _loseTraffic();
      }
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
    unawaited(_checkReach(force: force));
    if (_probing) return;
    _probing = true;
    try {
      await _refreshQuietlyInner(force: force);
    } finally {
      _probing = false;
      _afterProbe();
    }
  }

  /// هويّة الجهاز في اللقطة (النوع والمورّد) — تغيّرها (عنوانٌ آخر حُفظ، جهازٌ بُدّل) يعني نبضة ترافيكٍ أخرى.
  static String _identity(DeviceHealthSnapshot? s) => s == null ? '' : '${s.kind.name}/${s.ubnt?.vendor ?? s.ont?.vendor ?? ''}';

  /// لقطةٌ جديدة لجهازٍ غير الذي تنبض له النبضة الحاليّة ⇒ تُوقف وتبدأ نبضته هو (كانت نبضة C64 تبقى على Tenda بعد تبديل العنوان).
  void _restartTrafficIfChanged(DeviceHealthSnapshot? before, DeviceHealthSnapshot? after) {
    if (after == null || _identity(before) == _identity(after) || _identity(before).isEmpty) return;
    _stopTraffic(clear: true);
    _maybeStartTraffic();
  }

  Future<void> _refreshQuietlyInner({bool force = false}) async {
    final snap = await DeviceProbeApi.probe(
      fallbackIp: widget.ip,
      subscriberUsername: widget.username,
      slot: widget.slot,
      force: force,
      company: widget.company,
    );
    if (!mounted || snap == null) return;
    final before = _snap;
    setState(() {
      _snap = snap;
      _lastAt = DateTime.now();
    });
    _restartTrafficIfChanged(before, snap);
    // من يقرأ الكاش نفسه (بلاطة «تنبيه» فوق، وبطاقة القائمة تحت) لا يعرف
    // أنّ قراءةً جديدة وصلت إلّا بهذا.
    DeviceProbeBus.bump();
  }

  /// «حفظ وفحص» وفحصٌ آخر جارٍ: يُنفَّذ بعده لا يُسقط (كان يُتجاهل فلا محاولة ولا تشخيص — ٢٧ أكتوبر، D401).
  bool _retryPending = false;

  Future<void> _run({bool force = false, bool retryLogin = false}) async {
    unawaited(_checkReach(force: force));
    if (_probing) {
      if (retryLogin) _retryPending = true;
      return;
    }
    _probing = true;
    try {
      await _runInner(force: force, retryLogin: retryLogin);
    } finally {
      _probing = false;
      _afterProbe();
    }
  }

  void _afterProbe() {
    if (!_retryPending || !mounted) return;
    _retryPending = false;
    _run(force: true, retryLogin: true);
  }

  Future<void> _runInner({bool force = false, bool retryLogin = false}) async {
    setState(() => _loading = true);
    // Probe + notes in parallel — both go through small caches so the
    // total cost on a warm session is sub-100ms.
    final results = await Future.wait([
      DeviceProbeApi.probe(
        fallbackIp: widget.ip,
        subscriberUsername: widget.username,
      slot: widget.slot,
        force: force,
        retryLogin: retryLogin,
        company: widget.company,
      ),
      DeviceConfigApi.fetchConfig(widget.username, company: widget.company),
    ]);
    if (!mounted) return;
    final snap = results[0] as DeviceHealthSnapshot?;
    final cfg = results[1] as DeviceConfig?;
    final before = _snap;
    setState(() {
      _snap = snap;
      _notes = cfg?.notes?.trim();
      _loading = false;
      if (snap != null) _lastAt = DateTime.now();
    });
    DeviceProbeBus.bump();
    // أُعيد البنگ بعد أن عُرف الإعداد (customIp) — فيُصحَّح عنوانه إن لزم.
    unawaited(_checkReach(force: force));
    _restartTrafficIfChanged(before, snap);
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
    // الراوتر (١٢ نوفمبر — المالك: «وعمل ريبوت»): بأمر صفحته نفسها للعائلات المبنيّة ([RouterOps.canReboot])، وغيرها بلا زرّ
    // (كان سيُرسل إقلاع النانو بـSSH على منفذٍ مقفول).
    if (k == DeviceKind.ubiquiti && (_snap?.ubnt?.isRouter ?? false)) return RouterOps.canReboot(_snap!.ubnt!.vendor);
    // TP-Link (١٠ نوفمبر): بأمر صفحته نفسها ([TplinkPharosService.reboot]).
    return k == DeviceKind.ubiquiti || k == DeviceKind.ont;
  }

  Future<void> _confirmReboot() async {
    final isOnt = _snap?.kind == DeviceKind.ont;
    final u0 = _snap?.ubnt;
    final name = u0?.hostname.isNotEmpty == true
        ? u0!.hostname
        : (isOnt
            ? 'ONU المشترك'
            : (u0 != null && u0.isRouter ? (u0.model.isNotEmpty ? u0.model : 'راوتر المشترك') : 'جهاز المشترك'));
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
    final ru = _snap?.ubnt;
    if (_snap?.kind == DeviceKind.ubiquiti && ru != null && ru.isRouter) {
      final done = await _rebootRouter(ru.vendor);
      if (!mounted) return;
      setState(() => _rebooting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(done.text),
        backgroundColor: done.ok ? AppColors.success : AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ));
      return;
    }
    if (_isTplink) {
      final done = await _rebootTplink();
      if (!mounted) return;
      setState(() => _rebooting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(done.text),
        backgroundColor: done.ok ? AppColors.success : AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));
      return;
    }
    try {
      final creds = isOnt
          ? await DeviceProbeApi.resolveOntCreds(
              fallbackIp: widget.ip,
              subscriberUsername: widget.username,
      slot: widget.slot,
              company: widget.company,
            )
          : await DeviceProbeApi.resolveUbntCreds(
              fallbackIp: widget.ip,
              subscriberUsername: widget.username,
      slot: widget.slot,
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

  /// إعادة تشغيل الراوتر بأمر صفحته نفسها ([RouterOps.reboot]) — الجلسة الحيّة تُغلق ولا نطرقه وهو يقلع (~دقيقتين بالإنترنت).
  Future<({bool ok, String text})> _rebootRouter(String vendor) async {
    final c = await _routerCreds();
    if (c == null) return (ok: false, text: 'تعذّرت إعادة التشغيل: لا كلمة سرٍّ للراوتر — اكتبها من «الاعتمادات»');
    final r = await RouterOps.reboot(vendor, c.ip, c.user, c.pass);
    if (!r.ok) return (ok: false, text: 'تعذّرت إعادة التشغيل: ${routerFailText(r.fail!)}');
    _closeRouterLive();
    _rlRetryAt = DateTime.now().add(const Duration(seconds: 120));
    _tcRetryAt = DateTime.now().add(const Duration(seconds: 120));
    _loseTraffic();
    return (ok: true, text: r.value!.confirmed
        ? 'أُرسل أمر إعادة التشغيل — الراوتر يقلع الآن ويرجع الإنترنت خلال دقيقتين تقريباً'
        : 'أُرسل أمر إعادة التشغيل وانقطع الاتّصال — الراوتر يقلع غالباً، ويرجع خلال دقيقتين');
  }

  /// إعادة تشغيل TP-Link بأمر صفحته نفسها (مُجرَّب حيّاً على CPE610، ١٠ نوفمبر).
  Future<({bool ok, String text})> _rebootTplink() async {
    final creds = await DeviceProbeApi.resolveTplinkCreds(
      fallbackIp: widget.ip,
      subscriberUsername: widget.username,
      slot: widget.slot,
      company: widget.company,
    );
    if (creds == null) return (ok: false, text: 'تعذّرت إعادة التشغيل: لا يوزر وباسورد للجهاز — اكتبهن من «الاعتمادات»');
    final r = await TplinkPharosService.reboot(creds.ip, creds.user, creds.pass);
    if (r.sent) {
      // الجهاز يقلع: جلسة الترافيك ماتت معه — لا نطرقه وهو يقلع. قِيس: الجهاز يقول ٨٠ث، انطفأ بعد ١٣ث ورجع يجاوب على الشبكة
      // بعد ~دقيقتين (إقلاعٌ + ارتباط اللاسلكيّ + PPPoE) — فمهلته + نصف دقيقة قبل أوّل محاولة.
      _closeTplink();
      _tpRetryAt = DateTime.now().add(Duration(seconds: ((r.seconds ?? 80) + 30).clamp(60, 240)));
      _loseTraffic();
      return (ok: true, text: 'أُرسل أمر إعادة التشغيل — الجهاز يقلع الآن ويرجع خلال دقيقتين تقريباً');
    }
    final why = switch (r.issue) {
      PharosLoginIssue.rejected => 'الجهاز رفض اليوزر أو الباسورد',
      PharosLoginIssue.busy => 'صفحة الجهاز مفتوحة بمكانٍ ثاني',
      PharosLoginIssue.locked || PharosLoginIssue.tooManyFails => 'الجهاز قافل الدخول',
      PharosLoginIssue.needsSetup => 'الجهاز يطلب ضبط كلمة سرّه من صفحته أوّلاً',
      PharosLoginIssue.readFailed => 'الجهاز ما قبل الأمر',
      _ => 'الجهاز ما يجاوب',
    };
    return (ok: false, text: 'تعذّرت إعادة التشغيل: $why');
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
      builder: (_) => DeviceConfigSheet(username: widget.username, sessionIp: widget.ip),
    );
    if (changed == true && mounted) {
      // The sheet already invalidated per-IP cache when it saved. «حفظ وفحص» = محاولة دخولٍ جديدة حتى باعتماداتٍ رُفضت قبل
      // (الـIP قد يكون من الساس فلا يُبطله الحفظ).
      _run(force: true, retryLogin: true);
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
                child: Text(widget.slot == 2 ? 'الجهاز الثاني' : 'معلومات الجهاز',
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
    final snap = _snap;
    if (snap != null) {
      // الفحص الكامل جاهز: واصلٌ ومقروء.
      label = switch (snap.kind) {
        DeviceKind.ont => 'ONT',
        DeviceKind.ubiquiti => (snap.ubnt?.isTplink ?? false)
            ? 'TP-Link'
            : (snap.ubnt?.isRouter ?? false)
                ? 'راوتر'
                : 'UBNT',
        _ => 'متصل',
      };
      fg = AppColors.brandOnSoft;
      bg = AppColors.brandSoftBg;
      border = AppColors.brandSoftBorder;
    } else if (_reach == false) {
      // بنگ حسم: غير واصل — بلا انتظار الفحص الكامل.
      label = 'غير واصل';
      fg = AppColors.dangerOnSoft;
      bg = AppColors.dangerSoftBg;
      border = AppColors.dangerSoftBorder;
    } else if (_reach == true) {
      // واصلٌ ببنگ؛ القراءة إمّا جاريةٌ أو تعذّرت — والجسم يفصّل.
      label = 'واصل';
      fg = AppColors.successFill;
      bg = AppColors.successSoftBg;
      border = AppColors.successSoftBorder;
    } else if (_loading) {
      label = 'جارٍ الفحص';
      fg = AppColors.textMid;
      bg = AppColors.surfaceSunken;
      border = AppColors.border;
    } else {
      label = 'غير متاح';
      fg = AppColors.dangerOnSoft;
      bg = AppColors.dangerSoftBg;
      border = AppColors.dangerSoftBorder;
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

  void _onVpn() {
    if (mounted) setState(() {});
  }

  /// خارج شبكتك / «وضع VPN»: آخر قراءةٍ لهذا المشترك عبر الـVPN (٣٠ د) — null إن لم تُقرأ أو كنت على شبكتك.
  VpnSubReading? _vpnReading() {
    if (!(VpnNow.mode.value || AgentNetPresence.isOff)) return null;
    if (widget.slot != 1) return null; // قراءة الـVPN للجهاز الأوّل وحده
    return VpnNow.readingFor(widget.username, company: widget.company);
  }

  Widget _body() {
    final snap = _snap;
    // ٦ نوفمبر (المالك: «من افعل وضع vpn للمشتركين مفروض هنا هم يعرض القراءات»): لا قراءة من موبايلك ⇒ قراءة الـVPN
    if (snap == null) {
      final vr = _vpnReading();
      if (vr != null) return _vpnBody(vr);
    }
    if (_loading && _snap == null) return _scanning();
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
                    Text('يتعرّف على نوعه: Ubiquiti · TP-Link · ONT', style: AppType.muted()),
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

  /// ما يقوله الكرت حين لا قراءة — بالسبب لا «لم يُتمكّن» لكلّ شيء (المالك ٢٧ أكتوبر على ZTE MH80: «شوفلي التصحيح من
  /// السيرفر لو من التطبيق؟»): رفضٌ للاعتمادات غير جهازٍ لا يجاوب.
  ({String title, String hint}) _whyNoReading() {
    final why = DeviceProbeApi.issueFor(username: widget.username, ip: widget.ip, company: widget.company, slot: widget.slot);
    final left = why?.lockLeft;
    // TP-Link (١٠ نوفمبر): قفله عشر محاولاتٍ وساعتان (لا ثلاثٌ ودقيقة)، ولا «ضوء» فيه — فجملته بكلماته.
    if (why?.vendor == 'tplink') {
      final tp = _whyNoTplink(why!.issue, left);
      if (tp != null) return tp;
    }
    // Tenda (١٢ نوفمبر): كلمة سرٍّ وحدها، ولا قفل معروف — جملتان بكلماته.
    if (why?.vendor == 'tenda') {
      final t = switch (why!.issue) {
        ProbeIssue.needsCredentials => (
            title: 'راوتر Tenda يحتاج باسورده',
            hint: 'اكتبه بقسم «راوتر — باسورد فقط» من «الاعتمادات» بالإعدادات، أو لهذا المشترك من زرّ الإعدادات هنا',
          ),
        ProbeIssue.busy => (
            title: 'الراوتر عليه أربع جلسات مفتوحة',
            hint: 'صفحته مفتوحة بأماكن ثانية — سكّر وحدة منها وحدّث',
          ),
        ProbeIssue.readFailed => (
            title: 'دخلنا للراوتر بس ما رجعت قراءاته',
            hint: 'حدّث بعد لحظات',
          ),
        _ => null,
      };
      if (t != null) return t;
    }
    return switch (why?.issue) {
      ProbeIssue.loginRejected => (
          title: 'الجهاز رفض اليوزر أو الباسورد',
          hint: 'صحّحهن من زرّ الإعدادات — ما نعيد نفس المحاولة حتى ما ينقفل الجهاز',
        ),
      ProbeIssue.busy => (
          title: 'الجهاز رفض الدخول هسّه',
          hint: 'صفحته مفتوحة بمكانٍ ثاني (متصفّح أو هاتف) — سكّرها وحدّث',
        ),
      ProbeIssue.locked => (
          title: left == null ? 'الجهاز قافل الدخول دقيقة' : 'الجهاز قافل الدخول $left ثانية',
          hint: 'صارت ثلاث محاولات غلط عليه — جرّب بعد ما يخلص الوقت',
        ),
      ProbeIssue.readFailed => (
          title: 'دخلنا للجهاز بس ما قرينا الضوء',
          hint: 'صفحة الضوء ما رجعت — حدّث بعد لحظات',
        ),
      ProbeIssue.unknownFormat => (
          title: 'دخلنا للجهاز بس صفحة ضوئه جديدة علينا',
          hint: 'انبعث شكل صفحته (بلا أيّ قيم) حتى ينضاف هذا الطراز',
        ),
      ProbeIssue.needsCredentials => (
          title: 'جهاز ZTE يحتاج يوزر وباسورده',
          hint: 'اكتبهن من زرّ الإعدادات — الباسورد مكتوب على ظهر الجهاز',
        ),
      _ => _reach == false
          ? (
              title: 'الجهاز غير واصل',
              hint: 'ما يردّ على البنگ — تأكّد إنّه شغّال وبنفس الشبكة',
            )
          : _reach == true
              ? (
                  title: 'الجهاز واصل بس تعذّرت قراءته',
                  hint: 'البنگ يوصل — غالباً النوع أو بيانات الدخول، اضبطهن من زرّ الإعدادات',
                )
              : (
                  title: 'لم يُتمكّن من الوصول للجهاز',
                  hint: 'اضبط الـIP وبيانات الدخول من زرّ الإعدادات',
                ),
    };
  }

  /// جملة «لا قراءة» لجهاز TP-Link — null لما يكفيه النصّ العامّ (رفضٌ، مشغول، لا يجاوب).
  static ({String title, String hint})? _whyNoTplink(ProbeIssue issue, int? lockLeft) => switch (issue) {
        ProbeIssue.needsCredentials => (
            title: 'جهاز TP-Link يحتاج يوزر وباسورده',
            hint: 'اكتبهن بقسم TP-Link من «الاعتمادات» بالإعدادات، أو لهذا المشترك من زرّ الإعدادات هنا',
          ),
        ProbeIssue.locked => (
            title: lockLeft == null
                ? 'الجهاز قافل الدخول'
                : 'الجهاز قافل الدخول — باقي ${(lockLeft / 60).ceil()} دقيقة',
            hint: 'صارت عشر محاولات غلط عليه — جرّب بعد ما يخلص الوقت',
          ),
        ProbeIssue.tooManyFails => (
            title: 'محاولات دخول غلط كثيرة على الجهاز',
            hint: 'ما نحاول حتى لا ينقفل — صحّح اليوزر والباسورد واضغط «حفظ وفحص الجهاز»',
          ),
        ProbeIssue.needsSetup => (
            title: 'الجهاز يطلب ضبط كلمة سرّه من صفحته أوّلاً',
            hint: 'افتح صفحة الجهاز وأكمل ضبطه، بعدها حدّث',
          ),
        ProbeIssue.readFailed => (
            title: 'دخلنا للجهاز بس ما رجعت قراءاته',
            hint: 'حدّث بعد لحظات',
          ),
        _ => null,
      };

  /// قراءة المشترك من آخر فحصٍ عبر الـVPN: جهازه (الإشارة، CCQ، الكيبل) أو سكتره، أو الأولت (الضوء والحرارة)، أو البنگ وحده.
  Widget _vpnBody(VpnSubReading r) {
    final at = VpnNow.readingsAtFor(widget.company);
    final mins = at == null ? null : DateTime.now().difference(at).inMinutes;
    final when = mins == null ? '' : (mins < 1 ? 'الآن' : 'قبل $mins د');
    final from = switch (r.src) {
      'cpe' => 'من جهازه',
      'sector' => 'من السكتر',
      'olt' => 'من الأولت',
      'ping' => 'بنگ وحده',
      _ => '',
    };
    AppTone toneSig(int v) => v >= -65 ? AppTone.success : (v >= -75 ? AppTone.warning : AppTone.danger);
    AppTone toneCcq(int v) => v >= 75 ? AppTone.success : (v >= 50 ? AppTone.warning : AppTone.danger);
    final tiles = <Widget>[
      if (r.sig != null) MetricTile(label: 'الإشارة', value: '${r.sig} dBm', tone: toneSig(r.sig!), icon: LucideIcons.signal),
      if (r.ccq != null) MetricTile(label: 'CCQ', value: '${r.ccq}%', tone: toneCcq(r.ccq!), icon: LucideIcons.activity),
      if (r.lan != null)
        MetricTile(
          label: 'الكيبل',
          value: r.lan == 'unplugged' ? 'غير مربوط' : (r.lan == '10' ? '10M' : (r.lan == 'ok' ? 'سليم' : '${r.lan}M')),
          tone: r.lan == 'unplugged' ? AppTone.danger : (r.lan == '10' ? AppTone.warning : AppTone.success),
          icon: LucideIcons.cable,
          valueLtr: r.lan != 'unplugged' && r.lan != 'ok',
        ),
      if (r.rx != null)
        MetricTile(
          label: 'الضوء',
          value: '${r.rx!.toStringAsFixed(1)} dBm',
          tone: r.rx! >= -25 ? AppTone.success : (r.rx! >= -27 ? AppTone.warning : AppTone.danger),
          icon: LucideIcons.zap,
        ),
      if (r.temp != null)
        MetricTile(
          label: 'الحرارة',
          value: '${r.temp!.round()}°C',
          tone: r.temp! < 60 ? AppTone.success : (r.temp! < 70 ? AppTone.warning : AppTone.danger),
          icon: LucideIcons.thermometer,
        ),
      if (r.src == 'ping') MetricTile(label: 'البنگ', value: r.ms != null ? '${r.ms} ms' : 'واصل', tone: AppTone.success, icon: LucideIcons.radar),
    ];
    return Column(
      key: const ValueKey('device-card-vpn'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: Text(
              ['قراءة عبر الـVPN', if (from.isNotEmpty) from, if (when.isNotEmpty) when].join(' · '),
              style: AppType.muted(color: AppColors.textMid),
            ),
          ),
          const VpnTag(),
        ]),
        const SizedBox(height: Sp.sm),
        if (r.dead)
          Text('لا يستجيب عبر الـVPN', style: AppType.rowValue(color: AppColors.dangerOnSoft))
        else if (tiles.isEmpty)
          Text('يردّ عبر الـVPN بلا قراءة', style: AppType.muted())
        else
          Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
            for (final w in tiles) SizedBox(width: 132, child: w),
          ]),
        const SizedBox(height: Sp.xs),
        Text('القراءة الكاملة والترافك من موبايلك لمّا ترجع لشبكتك', style: AppType.micro(color: AppColors.textLow)),
      ],
    );
  }

  Widget _unreachable() {
    final why = _whyNoReading();
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
                Text(why.title,
                    style: AppType.rowValue(color: AppColors.textMid)),
                const SizedBox(height: Sp.xxs),
                Text(why.hint,
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
        _trafficChart(),
        const SizedBox(height: Sp.sm),
        Row(
          children: [
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
      // الراوتر (١١ نوفمبر — المالك: «عدد المتصلين… الوايرلس تلكاه المتصل الفعلي»): أجهزة الوايرلس المتّصلة الآن، قصيرٌ ثابت.
      // ومنسدلٌ بنقر الوكيل (المالك: «اجعلها توكل بتن… يطلعه ايبي وماك واسم الجهاز… مغلق دائما الا ينقره الوكيل»).
      if (u.isRouter && u.peerCount != null) _routerClientsTile(u),
    ];

    // الترافيك اللحظي محلّ SNR (طلب المستخدم 2026-08-30): SNR رقم
    // شبه ثابت يُنظر إليه عند التركيب، والترافيك هو ما يُسأل عنه
    // يوميّاً — «هل المشترك يسحب فعلاً؟».
    final Widget? wide = _snap?.kind == DeviceKind.ubiquiti
        ? _trafficChart()
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
        // القائمة المنسدلة للمتّصلين (تحت صفّ البلاطات مباشرةً) — تظهر فقط حين ينقر الوكيل البلاطة.
        if (u.isRouter && _clientsExpanded && u.clients.isNotEmpty) _routerClientsList(u),
        if (wide != null) ...[
          if (short.isNotEmpty) const SizedBox(height: Sp.sm),
          wide, // العرض الكامل — بلا Expanded وبلا جار
        ],
        if (short.isNotEmpty || wide != null) const SizedBox(height: 14),
        _DetailRow(field: _ubntKind(u), strong: true),
        // مدّة اتّصال الإنترنت (PPPoE) — من متغيّرات المالك الثلاثة («مده الاتصالات»)؛ صفّ كامل العرض لا بلاطة (نصٌّ عربيّ طويل).
        if (u.isRouter && u.wanOnlineSeconds != null)
          _DetailRow(field: _routerOnline(u), rtlValue: true),
        if (u.isRouter && u.wanType.isNotEmpty)
          _DetailRow(field: _routerWan(u), small: true),
        // سرعة منفذ الإنترنت (المالك ١١ نوفمبر: «سرعه المنفذ wan») — حين يصدّرها الراوتر (Tenda).
        if (u.isRouter && u.wanLinkMbps != null)
          _DetailRow(field: _routerWanLink(u), small: true),
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
        if (u.isRouter && u.dhcpCount != null)
          _DetailRow(field: _routerDhcp(u), small: true),
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
        // «كلمة سرّ الواي فاي» — عرضٌ ونسخٌ وتغيير (١٢ نوفمبر) للعائلات المبنيّة والمجرَّبة.
        if (u.isRouter && RouterOps.canWifi(u.vendor)) ...[
          const SizedBox(height: Sp.sm),
          Divider(height: 1, color: AppColors.divider),
          RouterWifiPanel(vendor: u.vendor, creds: _routerCreds, onBusy: _routerOpBusy),
        ],
      ],
    );
  }

  /// الاعتماد الذي دخل به الفحص على هذا الراوتر (أو مرشّح الوكيل) — للواي فاي والإقلاع والنبضة الحيّة.
  Future<RouterCreds?> _routerCreds() => DeviceProbeApi.resolveTplinkCreds(
        fallbackIp: widget.ip,
        subscriberUsername: widget.username,
        company: widget.company,
        slot: widget.slot,
      );

  /// بلاطة «المتّصلون الآن» — قابلةٌ للنقر لفتح/طيّ قائمة الأجهزة حين تتوفّر تفاصيلها (المالك: «توكل بتن… مغلق دائما الا ينقره الوكيل»)،
  /// وإلّا بلاطةٌ عاديّة (عدٌّ بلا تفاصيل).
  Widget _routerClientsTile(UbiquitiStatus u) {
    if (u.clients.isEmpty) {
      return _MetricTile(field: _routerClients(u), color: AppColors.textHi);
    }
    return InkWell(
      borderRadius: BorderRadius.circular(R.icon),
      onTap: () => setState(() => _clientsExpanded = !_clientsExpanded),
      child: Container(
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
                Flexible(
                  child: Text('المتّصلون الآن',
                      style: AppType.micro(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: Sp.xs),
                Icon(
                  _clientsExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 15,
                  color: AppColors.brandAccent,
                ),
              ],
            ),
            const SizedBox(height: Sp.xxs),
            Text('${u.peerCount}',
                textDirection: TextDirection.ltr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.cardTitle(color: AppColors.textHi)
                    .copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  /// القائمة المنسدلة: كلّ جهازٍ باسمه (أو رقمه) وآيبيه وماكه مرتّباً، والماك قابلٌ للنسخ؛ والسلكيّ موسوم.
  Widget _routerClientsList(UbiquitiStatus u) {
    final cs = u.clients;
    return Container(
      margin: const EdgeInsets.only(top: Sp.sm),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.icon),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < cs.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.sm),
              child: _clientRow(cs[i], i + 1),
            ),
          ],
        ],
      ),
    );
  }

  Widget _clientRow(RouterClient c, int n) {
    final name = (c.name != null && c.name!.trim().isNotEmpty)
        ? c.name!.trim()
        : 'جهاز $n';
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text('$n',
              textDirection: TextDirection.ltr,
              style: AppType.micro(color: AppColors.textLabel)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(name,
                        style: AppType.body()
                            .copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (c.wired) ...[
                    const SizedBox(width: Sp.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(R.pill),
                      ),
                      child: Text('سلكيّ',
                          style: AppType.micro(color: AppColors.textLabel)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 1),
              Text(c.mac,
                  textDirection: TextDirection.ltr,
                  style: AppType.micro(color: AppColors.textLabel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        if (c.ip != null && c.ip!.isNotEmpty) ...[
          const SizedBox(width: Sp.sm),
          Text(c.ip!,
              textDirection: TextDirection.ltr,
              style: AppType.body(color: AppColors.textHi)),
        ],
        _CopyIcon(value: c.mac, label: 'MAC'),
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
    // ٦ نوفمبر (المالك: «لازم تتحول لل V» ثمّ «ماكو ٣.35 هيج فولتيه… اقل شي ١١ او ١٢»): هذه فولتيّة موديول الضوء داخل الجهاز (٣٫٣ V
    // دائماً) لا فولتيّة الأدابتر (١٢ V — لا يقيسها الجهاز) ⇒ اسمها الصريح وبالفولت
    CopyField('فولتيّة موديول الضوء', _volts(o.voltage));

/// ملّي فولت (كما تعطيه صفحة الجهاز) ⇒ «3.35 V»؛ ما لا يُفهم يبقى كما هو.
String _volts(String mv) {
  final v = double.tryParse(mv.trim());
  if (v == null || v <= 0) return mv.trim().isEmpty ? '—' : mv;
  return '${(v / 1000).toStringAsFixed(2)} V';
}

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

/// يوبيكويتي كما كان؛ وTP-Link بطرازه كما يسمّيه الجهاز («Emad (TP-Link CPE610 v2.0)»)؛ والراوتر الكلاسيكيّ «راوتر TP-Link TL-WR741ND v4».
CopyField _ubntKind(UbiquitiStatus u) {
  final brand = u.isTplink
      ? (u.model.isEmpty ? 'TP-Link' : 'TP-Link ${u.model}')
      : u.isTenda
          ? (u.model.isEmpty ? 'راوتر Tenda' : 'راوتر Tenda ${u.model}')
          : u.isRouter
              ? (u.model.isEmpty ? 'راوتر TP-Link' : 'راوتر TP-Link ${u.model}')
              : null;
  return CopyField(
    'نوع الجهاز',
    brand != null
        ? (u.hostname.isEmpty ? brand : '${u.hostname} ($brand)')
        : (u.hostname.isEmpty ? 'Ubiquiti' : '${u.hostname} (UBNT)'),
  );
}

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

/// أجهزة الوايرلس المتّصلة الآن (صفحة Wireless Statistics) — لا إيجارات DHCP.
CopyField _routerClients(UbiquitiStatus u) => CopyField('المتّصلون الآن', '${u.peerCount}');

/// مدّة اتّصال الإنترنت (PPPoE «Online Time») — صفرٌ يعني أنّ الراوتر غير متّصل الآن.
CopyField _routerOnline(UbiquitiStatus u) => CopyField(
      'مدّة الاتصال',
      (u.wanOnlineSeconds ?? 0) <= 0 ? 'غير متّصل بالإنترنت' : _DeviceProbeCardState._uptime(u.wanOnlineSeconds!),
    );

CopyField _routerWan(UbiquitiStatus u) => CopyField('الإنترنت', u.wanType);

CopyField _routerWanLink(UbiquitiStatus u) => CopyField('منفذ الإنترنت', '${u.wanLinkMbps}Mbps');

/// إيجارات DHCP (سلكيّ + لاسلكيّ) — تبقى بعد خروج الجهاز، فاسمها «أجهزة DHCP» لا «متّصلون».
CopyField _routerDhcp(UbiquitiStatus u) => CopyField('أجهزة DHCP', '${u.dhcpCount}');

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
      if (u.isRouter && u.peerCount != null) _routerClients(u),
      if (u.isRouter && u.wanOnlineSeconds != null) _routerOnline(u),
      if (u.isRouter && u.wanType.isNotEmpty) _routerWan(u),
      if (u.isRouter && u.wanLinkMbps != null) _routerWanLink(u),
      if (u.isRouter && u.dhcpCount != null) _routerDhcp(u),
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
