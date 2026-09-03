import 'dart:async';

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/mimosa_api.dart';
import '../../../api/network_devices_api.dart';
import '../../../models/network_device.dart';
import '../../../services/device_stats_cache.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import 'expandable_section.dart';
import '_grade.dart';
import '../../../theme/typography.dart';
import '../../../core/util/error_text.dart';

/// لوحة مراقبة حيّة لأجهزة Mimosa (B5/B5c/B11/B24/A5/C5/C5c) — SNMP v2c فقط.
///
/// **CPU/RAM غير متوفّرين** — firmware Mimosa يخفيهما بالتصميم.
/// **الأقسام**: Hero (RX/TX/SNR/Margin) → Chain table → Rates → GPS → Info.
class MimosaLivePanel extends StatefulWidget {
  final NetworkDevice device;
  const MimosaLivePanel({super.key, required this.device});

  @override
  State<MimosaLivePanel> createState() => _MimosaLivePanelState();
}

class _MimosaLivePanelState extends State<MimosaLivePanel> {
  MimosaStats? _stats;
  List<MimosaClient> _clients = const [];
  bool _loading = false;
  String? _error;
  Timer? _timer;
  bool _monitoring = false;
  DateTime? _lastFetch;

  /// آخر عدّادات أوكتِتات + لحظتها — أساس حساب المرور الفعليّ.
  ///
  /// 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «ترفك لحد هسه ماكو». وما كان يُعرض (٦٥٠/٦٥٠)
  /// سعةُ الوصلة لا حركتها.
  Map<int, ({int rx, int tx})>? _lastCounters;
  DateTime? _lastCountersAt;

  /// الواجهة المثبَّتة للرسم.
  ///
  /// 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «شو مرّة أبلود أعلى ظاهر وهو نهائيّاً ماكو
  /// هيج أبلود».
  ///
  /// كنّا ننتخب «الأنشط» في **كلّ جولة**. ونقطة الوصول لها واجهتان
  /// تحملان الحركة نفسها في اتّجاهين متعاكسين: اللاسلكيّة تستقبل ٤٦
  /// ميغا، والإيثرنت تُرسلها. ومجموع (rx+tx) متساوٍ تقريباً، فأيّ
  /// تذبذبٍ طفيف يقلب الفائز — فينقلب الخطّان ويظهر صعودٌ ٤٨ ميغا
  /// على وصلةٍ صعودها ٣.
  ///
  /// الانتخاب مرّةً والتثبيت: سلسلةٌ متماسكة من واجهةٍ واحدة.
  int? _pinnedIf;

  /// كم جولةً متتالية والمثبَّتة صامتة — بعدها نُعيد الانتخاب فلا نعلق
  /// على واجهةٍ ماتت.
  int _pinnedIdleRounds = 0;
  static const int _repinAfterIdle = 4;

  /// ٣٠ × نبضة ≈ عدّة دقائق.
  static const int _maxHistory = 30;
  final List<_TrafficSample> _history = [];

  /// نبضة الشاشة المفتوحة.
  ///
  /// 🐛 ملاحظة المستخدم ٢٠٢٦-٠٩-٠٢: «فترة التحديث تتأخّر هواي».
  ///
  /// وكانت خمس عشرة ثانية — وهي مناسبةٌ لمسحٍ جماعيّ، لا لشاشةٍ يقف
  /// أمامها المستخدم ينظر إلى **جهازٍ واحد**. الجلسة هنا لا تُزاحم
  /// أحداً: لا سقف ستّ خانات ولا ثمانون جهازاً — جهازٌ واحد وشاشةٌ
  /// مفتوحة.
  ///
  /// ⚠️ ولا نهبط إلى ثمانٍ كميكروتك: جلستُه عبر الـAPI الثنائيّ
  /// بأجزاء الثانية، وجلسة SSH/SNMP هنا أثقل — نبضةٌ أسرع من زمن
  /// الجلسة تُنتج طابوراً لا تحديثاً.
  static const _refreshInterval = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    // ── بذرةٌ من المخزن ────────────────────────────────────────────
    //
    // 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «بكلّ جهاز أنقر عليه لازم يعيد إرسال الطلب،
    // وهذا مزعج. هو كلّهن طلب واحد، مفروض يجلب كلّ المعلومات ويبقى
    // يحافظها — وقت ما أنقر على الكارت تطلع لي».
    //
    // «نظرة عامّة» فتحت جلسةً لهذا الجهاز قبل قليل وحفظت حمولتها.
    // نعرضها فوراً ثمّ نُحدّث في الخلفيّة — فالنقر يُظهر بيانات لا
    // دوّاراً، والجلسة الثانية تصحّح ما شاخ منها.
    //
    // والنوع مفحوص داخل المخزن: جهازٌ غُيّرت علامته يحمل حمولةً من
    // النوع القديم، وبذرُها هنا ترمي.
    _stats = DeviceStatsCache.instance.seedFor<MimosaStats>(widget.device.id);
    // ⚠️ وعمرُها الحقيقيّ معها.
    //
    // 🐛 تحذير المستخدم ٢٠٢٦-٠٩-٠٢: «المعلومات الحيّة ما تتغيّر، تبقى
    // ثابتة». والبذرة لقطةٌ قد يبلغ عمرها دقيقتين، وكانت تُعرض تحت
    // شارة «مباشر» كأنّها الآن.
    //
    // فنُورّث لحظتَها لا لحظتنا: الشارة تقول «قبل ٤٥ث» صادقةً، ثمّ
    // تهبط إلى «قبل ٠ث» حين يصل جلبُنا بعد جزءٍ من الثانية.
    // رقمٌ قديمٌ **معلومُ القِدَم** أمانة؛ ومعروضٌ كأنّه الآن كذبة.
    final seedAge = DeviceStatsCache.instance.ageOf(widget.device.id);
    if (_stats != null && seedAge != null) {
      _lastFetch = DateTime.now().subtract(seedAge);
    }
    _startMonitoring();
  }

  @override
  void dispose() {
    _quickSampleTimer?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _startMonitoring() async {
    setState(() => _monitoring = true);
    await _fetch();
    _timer?.cancel();
    _timer = Timer.periodic(_refreshInterval, (_) => _fetch());
  }

  void _stopMonitoring() {
    _timer?.cancel();
    setState(() => _monitoring = false);
  }

  Future<void> _fetch() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final creds = await NetworkDevicesApi.getCredentials(widget.device.id);
      // فورم الأجهزة يحفظ SNMP كـ{community: "...", version: "v2c"}
      // (راجع network_device_form_sheet.dart:103). fallback على 'pass' لو
      // في نسخ قديمة كان يحفظ في مفتاح مختلف.
      final community =
          (creds['community'] ?? creds['pass'] ?? '').toString().trim();
      // diagnostic (debug فقط — لا يُطبع في release لتفادي كشف community)
      if (kDebugMode) {
        debugPrint('🔵 Mimosa creds len=${community.length} '
            'port=${widget.device.apiPort ?? 161}');
      }
      if (community.isEmpty) {
        throw MimosaException('لم يتم إعداد SNMP community string. '
            'عدّل الجهاز وأدخل الـcommunity (عادةً "public").');
      }
      final port = widget.device.apiPort ?? 161;
      final s = await MimosaApi.fetchStats(
        host: widget.device.ip,
        port: port,
        community: community,
        // ⚡ Tier 1 partial بعد ~500ms: device name/temp/GPS/uptime
        // بدل انتظار RF details + chains (~1s إضافيّة).
        //
        // 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «من يحدّث يخفي القراءات السابقة · كارت
        // الجاينات يختفي ويظهر».
        //
        // ⚠️ **لأوّل تحميل وحده**. الجزئيّة بلا RF ولا سلاسل، فقبولها
        // في التحديث يستبدل بياناتٍ كاملةً معروضةً بأخرى ناقصة: تختفي
        // SNR والقدرتان، ويختفي كارت السلاسل كلّه، ثمّ تعود بعد ثانية.
        // وميضٌ كلّ نبضة.
        //
        // اللوحتان الأخريان (ميكروتك · UBNT) تُقيّدانها هكذا منذ
        // 2026-08-18 — وميموزا وحدها شذّت.
        onPartialReady: _stats == null
            ? (partial) {
                if (!mounted) return;
                setState(() {
                  _stats = partial;
                });
              }
            : null,
      );
      if (!mounted) return;
      setState(() {
        _computeTraffic(s.counters);
        _stats = s;
        DeviceStatsCache.instance.putRaw(widget.device.id, s);
        _lastFetch = DateTime.now();
        _maybeQuickSecondSample();
        _loading = false;
      });
      // العملاء PtMP (اختياري — للسكتورات فقط A5/A6/C5). لا يوقف الـpanel لو
      // فشل — الأجهزة PtP (B5) ترجع قائمة فارغة تلقائياً.
      _fetchClients(community, port);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is MimosaException ? e.message : humanError(e);
        _loading = false;
      });
    }
  }

  /// جلب قائمة العملاء PtMP بشكل غير متزامن — لا يوقف الـUI لو تأخّر أو فشل.
  Future<void> _fetchClients(String community, int port) async {
    try {
      final list = await MimosaApi.fetchClients(
        host: widget.device.ip,
        port: port,
        community: community,
      );
      if (mounted) setState(() => _clients = list);
    } catch (_) {
      // silent — البانل يبقى يعمل بدون قسم العملاء
    }
  }

  /// يحوّل عدّادات الأوكتِتات إلى معدّل، بفارق لقطتين.
  ///
  /// ⚠️ الزمن هو الفاصل بين **عيّنتين كاملتين**. نافذةٌ أقصر من ثانية
  /// تُضخّم أيّ ضجيج، وأطول من خمس دقائق تُعطي متوسّطاً لا معدّلاً.
  /// (نفس الحارس في جدار الأجهزة — فخّ ٢٠٢٦-٠٨-١٣ الذي أظهر ٤ غيغا
  /// مكان ١٣٠ ميغا.)
  ///
  /// وارتدادُ العدّاد (إقلاعٌ أو التفافُ ٣٢-بت) يُهمَل، فلا نُخرج رقماً
  /// سالباً أو ضخماً كاذباً.
  void _computeTraffic(List<MimosaIfCounter> counters) {
    final now = DateTime.now();
    final fresh = <int, ({int rx, int tx})>{
      for (final c in counters) c.index: (rx: c.rxOctets, tx: c.txOctets),
    };
    final prev = _lastCounters;
    final prevAt = _lastCountersAt;
    _lastCounters = fresh.isEmpty ? prev : fresh;
    if (fresh.isNotEmpty) _lastCountersAt = now;
    if (prev == null || prevAt == null || fresh.isEmpty) return;

    final secs = now.difference(prevAt).inMilliseconds / 1000.0;
    if (secs < 1 || secs > 300) return;

    // معدّل كلّ واجهة أوّلاً، ثمّ الاختيار — لا اختيارٌ أثناء الحساب.
    final rates = <int, ({int rx, int tx})>{};
    for (final c in counters) {
      final b = prev[c.index];
      if (b == null) continue;
      if (c.rxOctets < b.rx || c.txOctets < b.tx) continue; // ارتداد
      final rx = ((c.rxOctets - b.rx) * 8 / secs).round();
      final tx = ((c.txOctets - b.tx) * 8 / secs).round();
      // عشرة غيغابت سقفٌ لا تبلغه وصلةٌ لاسلكيّة — ما فوقه خللُ عدّاد.
      if (rx > 10000000000 || tx > 10000000000) continue;
      rates[c.index] = (rx: rx, tx: tx);
    }
    if (rates.isEmpty) return;

    // ⚠️ التثبيت لا الانتخاب الدوريّ — راجع [_pinnedIf].
    var pin = _pinnedIf;
    if (pin == null || !rates.containsKey(pin)) {
      pin = _electBusiest(rates);
      _pinnedIdleRounds = 0;
    } else {
      final r = rates[pin]!;
      if (r.rx + r.tx == 0) {
        _pinnedIdleRounds++;
        if (_pinnedIdleRounds >= _repinAfterIdle) {
          pin = _electBusiest(rates);
          _pinnedIdleRounds = 0;
        }
      } else {
        _pinnedIdleRounds = 0;
      }
    }
    _pinnedIf = pin;

    final chosen = rates[pin]!;
    final bestRx = chosen.rx;
    final bestTx = chosen.tx;
    // القراءة من ذيل التاريخ لا من حقولٍ موازية — مصدرٌ واحد للرقم
    // المعروض وللرسم، فلا ينحرف أحدهما عن الآخر.
    _history.add(_TrafficSample(at: now, rxBps: bestRx, txBps: bestTx));
    if (_history.length > _maxHistory) _history.removeAt(0);
  }

  Timer? _quickSampleTimer;

  /// عيّنة ثانية سريعة — لئلّا ينتظر الترفك نبضتين كاملتين.
  ///
  /// 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «الترفك الوحيد يتأخّر ٣٠ ثانية». والسبب
  /// حسابيّ لا شبكيّ: المعدّل فارقُ عيّنتين والنبضة كلّ ١٥ ثانية، أمّا
  /// بقيّة القيم فمطلقةٌ تظهر من الأولى.
  ///
  /// نأخذ الثانية بعد أربع ثوانٍ بجلبٍ مقتصر على العدّادات (ثلاث مشيات
  /// بدل عشر). وأربعٌ لا واحدة: نافذةٌ أقصر تُضخّم ضجيج العدّاد.
  void _maybeQuickSecondSample() {
    if (_history.isNotEmpty || _quickSampleTimer != null) return;
    _quickSampleTimer = Timer(const Duration(seconds: 4), () async {
      _quickSampleTimer = null;
      if (!mounted || _history.isNotEmpty) return;
      try {
        final creds = await NetworkDevicesApi.getCredentials(widget.device.id);
        final community =
            (creds['community'] ?? creds['user'] ?? 'public').toString();
        final counters = await MimosaApi.fetchCounters(
          host: widget.device.ip,
          port: widget.device.apiPort ?? 161,
          community: community,
        );
        if (!mounted || counters.isEmpty) return;
        setState(() => _computeTraffic(counters));
      } catch (_) {
        // فشلها لا يضرّ — النبضة العاديّة ستُنتج الرقم بعد قليل.
      }
    });
  }

  /// أكثر الواجهات حركةً — يُستدعى عند التثبيت الأوّل فقط.
  static int _electBusiest(Map<int, ({int rx, int tx})> rates) {
    var best = rates.keys.first;
    var bestSum = -1;
    for (final e in rates.entries) {
      final sum = e.value.rx + e.value.tx;
      if (sum > bestSum) {
        bestSum = sum;
        best = e.key;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    if (_stats == null && _loading) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator(),
      ));
    }
    if (_error != null && _stats == null) {
      return _errorCard();
    }
    if (_stats == null) return const SizedBox.shrink();

    final s = _stats!;
    return Column(children: [
      _controlBar(),
      const SizedBox(height: Sp.md),
      _heroCard(s),
      const SizedBox(height: Sp.md),
      if (s.signalMarginDb != null) ...[
        _marginCard(s),
        const SizedBox(height: Sp.md),
      ],
      if (s.chains.isNotEmpty) ...[
        _chainsSection(s),
        const SizedBox(height: Sp.md),
      ],
      // 2026-08-18: العملاء PtMP — يظهر فقط لو الجهاز سكتور (A5/A6/C5).
      if (_clients.isNotEmpty) ...[
        _clientsSection(),
        const SizedBox(height: Sp.md),
      ],
      // المرور الفعليّ **قبل** السعة: هو ما يُسأل عنه، والسعة سقفٌ
      // ثابت لا يتغيّر بين النبضات.
      _trafficGraph(),
      _ratesCard(s),
      const SizedBox(height: Sp.md),
      _systemCard(s),
      const SizedBox(height: Sp.md),
      if (s.hasGps) ...[
        _gpsCard(s),
        const SizedBox(height: Sp.md),
      ],
      _infoCard(s),
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // Header controls
  // ═══════════════════════════════════════════════════════
  Widget _controlBar() {
    final freshS = _lastFetch != null
        ? DateTime.now().difference(_lastFetch!).inSeconds
        : null;
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _monitoring ? AppColors.successSoftBg : AppColors.borderSoft,
          borderRadius: BorderRadius.circular(R.card),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // 2026-08-18: opacity pulse بدل spinner swap — يمنع مظهر
          // "فُصل ورجع" على كل fetch cycle.
          AnimatedOpacity(
            duration: const Duration(milliseconds: 400),
            opacity: _loading ? 0.35 : 1.0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _monitoring ? AppColors.success : AppColors.textLow,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _monitoring
                ? (freshS != null ? 'مباشر · قبل $freshSث' : 'مباشر')
                : 'موقوف',
            style: AppType.microBold(
                color: _monitoring ? AppColors.success : AppColors.textMid),
          ),
        ]),
      ),
      const Spacer(),
      IconButton(
        onPressed: _loading ? null : _fetch,
        icon: Icon(LucideIcons.refreshCw, size: 16, color: AppColors.textMid),
        tooltip: 'تحديث الآن',
      ),
      IconButton(
        onPressed: _monitoring ? _stopMonitoring : _startMonitoring,
        icon: Icon(_monitoring ? LucideIcons.pause : LucideIcons.play,
            size: 16, color: AppColors.textMid),
        tooltip: _monitoring ? 'إيقاف' : 'بدء',
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // 🎯 Hero — TX/RX + SNR + Temp
  // ═══════════════════════════════════════════════════════
  Widget _heroCard(MimosaStats s) {
    final rx = s.totalRxPowerDbm;
    final tx = s.totalTxPowerDbm;
    final snr = s.bestSnrDb;
    final signalColor = rx != null ? _rxColor(rx) : AppColors.textLow;
    final name = s.deviceName ?? s.sysName ?? 'Mimosa';

    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            signalColor.withValues(alpha: 0.10),
            signalColor.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: signalColor.withValues(alpha: 0.35)),
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.warningSoftBg,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: AppColors.warningSoftBorder),
            ),
            child: Center(
              child: Text('M',
                  style: TextStyle(
                      fontSize: 16,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: AppColors.warning)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: AppType.buttonBold()),
              if (s.sysDescr != null)
                Text(s.sysDescr!,
                    style: TextStyle(
                        fontSize: 9.5, height: 1.2, color: AppColors.textLow),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (s.temperatureC != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.thermometer,
                  size: 12, color: _tempColor(s.temperatureC!)),
              const SizedBox(width: 2),
              Text('${s.temperatureC!.toStringAsFixed(1)}°C',
                  textDirection: TextDirection.ltr,
                  style: AppType.pillBold(color: _tempColor(s.temperatureC!))),
            ]),
        ]),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
                child: _heroMetric(
              icon: LucideIcons.arrowDown,
              label: 'RX Power',
              value: rx != null ? rx.toStringAsFixed(1) : '—',
              unit: rx != null ? 'dBm' : '',
              color: signalColor,
            )),
            _heroDivider(),
            Expanded(
                child: _heroMetric(
              icon: LucideIcons.arrowUp,
              label: 'TX Power',
              value: tx != null ? tx.toStringAsFixed(1) : '—',
              unit: tx != null ? 'dBm' : '',
              color: AppColors.brandAccent,
            )),
            _heroDivider(),
            Expanded(
                child: _heroMetric(
              icon: LucideIcons.activity,
              label: 'SNR',
              value: snr != null ? snr.toStringAsFixed(0) : '—',
              unit: snr != null ? 'dB' : '',
              color: snr != null ? _snrColor(snr) : AppColors.textLow,
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _heroDivider() => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: AppColors.borderSoft,
      );

  Widget _heroMetric({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(height: 2),
      Text(label, style: AppType.daysWordBold(color: AppColors.textMid)),
      const SizedBox(height: 2),
      Text(value,
          textDirection: TextDirection.ltr,
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1)),
      if (unit.isNotEmpty)
        Text(unit, style: AppType.daysWord(color: AppColors.textLow)),
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // ⚖️ Margin — actual vs target
  // ═══════════════════════════════════════════════════════
  Widget _marginCard(MimosaStats s) {
    final actual = s.totalRxPowerDbm!;
    final target = s.targetRxPowerDbm!;
    final margin = s.signalMarginDb!;
    final marginColor = margin >= -3
        ? AppColors.success
        : margin >= -8
            ? AppColors.warning
            : AppColors.error;
    return _cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.gauge, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('هامش الإشارة', style: AppType.bodyBold()),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _marginTile('الفعلي', actual.toStringAsFixed(1), 'dBm',
                  AppColors.textHi)),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(LucideIcons.arrowRight,
                  size: 12, color: AppColors.textLow)),
          Expanded(
              child: _marginTile('المتوقّع', target.toStringAsFixed(1), 'dBm',
                  AppColors.textMid)),
          _heroDivider(),
          Expanded(
              child: _marginTile(
                  'الهامش',
                  margin >= 0
                      ? '+${margin.toStringAsFixed(1)}'
                      : margin.toStringAsFixed(1),
                  'dB',
                  marginColor)),
        ]),
      ]),
    );
  }

  Widget _marginTile(String label, String value, String unit, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: AppType.daysWordBold(color: AppColors.textMid)),
      const SizedBox(height: 2),
      Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1)),
            const SizedBox(width: 2),
            Text(unit,
                style: TextStyle(
                    fontSize: 9.5, height: 1.2, color: AppColors.textLow)),
          ]),
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // 📶 Chains — per-chain signal
  // ═══════════════════════════════════════════════════════
  Widget _chainsSection(MimosaStats s) {
    return ExpandableSection(
      key: PageStorageKey('mimosa-${widget.device.id}-chains'),
      initiallyExpanded: true,
      header: Row(children: [
        Icon(LucideIcons.signal, size: 14, color: AppColors.warning),
        const SizedBox(width: 6),
        Text('Chains (${s.chains.length})', style: AppType.bodyBold()),
      ]),
      content: Column(children: [
        for (final c in s.chains) _chainRow(c),
      ]),
    );
  }

  Widget _chainRow(MimosaChain c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppColors.warningSoftBg,
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Center(
            child: Text('${c.index}',
                style: AppType.bodyBold(color: AppColors.warning)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: _chainMetric(
                'RX',
                c.rxPowerDbm != null
                    ? '${c.rxPowerDbm!.toStringAsFixed(1)} dBm'
                    : '—',
                c.rxPowerDbm != null
                    ? _rxColor(c.rxPowerDbm!)
                    : AppColors.textLow)),
        Expanded(
            child: _chainMetric(
                'Noise',
                c.rxNoiseDbm != null
                    ? '${c.rxNoiseDbm!.toStringAsFixed(0)} dBm'
                    : '—',
                AppColors.textMid)),
        Expanded(
            child: _chainMetric(
                'SNR',
                c.snrDb != null ? '${c.snrDb!.toStringAsFixed(0)} dB' : '—',
                c.snrDb != null ? _snrColor(c.snrDb!) : AppColors.textLow)),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════
  // PtMP Clients section — 2026-08-18
  // العملاء المتصلون بالسكتور. لكل واحد: name/IP/RSSI/SNR/rates/uptime.
  // ═══════════════════════════════════════════════════════

  Widget _clientsSection() {
    final online = _clients.where((c) => c.online).length;
    return ExpandableSection(
      key: PageStorageKey('mimosa-${widget.device.id}-clients'),
      initiallyExpanded: true,
      header: Row(children: [
        Icon(LucideIcons.users, size: 14, color: AppColors.brandAccent),
        const SizedBox(width: 6),
        Text('العملاء المتصلون (${_clients.length})',
            style: AppType.bodyBold()),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.successSoftBg,
            borderRadius: BorderRadius.circular(R.pill),
          ),
          child: Text('$online online',
              style: AppType.daysWordBold(color: AppColors.success)),
        ),
      ]),
      content: Column(children: [
        for (final c in _clients) _clientTile(c),
      ]),
    );
  }

  Widget _clientTile(MimosaClient c) {
    final rssiColor = _rssiColor(c.rssiDbm);
    final label =
        (c.name?.trim().isNotEmpty == true) ? c.name!.trim() : (c.ip ?? c.mac);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.online ? AppColors.surface : AppColors.surfaceDisabled,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // العنوان: الاسم/IP + status dot + RSSI badge
            Row(children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: c.online ? AppColors.success : AppColors.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: AppType.bodyBold(
                        color: c.online ? AppColors.textHi : AppColors.textMid),
                    overflow: TextOverflow.ellipsis),
              ),
              if (c.rssiDbm != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: rssiColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(R.pill),
                    border: Border.all(color: rssiColor.withValues(alpha: 0.3)),
                  ),
                  child: Text('${c.rssiDbm} dBm',
                      textDirection: TextDirection.ltr,
                      style: AppType.microBold(color: rssiColor)),
                ),
            ]),
            const SizedBox(height: 4),
            // MAC + IP row (لو الاسم غير الـIP)
            if (c.name?.trim().isNotEmpty == true && c.ip != null) ...[
              Row(children: [
                Icon(LucideIcons.globe, size: 10, color: AppColors.textLow),
                const SizedBox(width: 3),
                Text(c.ip!,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                        fontSize: 10.5, height: 1.3, color: AppColors.textMid)),
                const SizedBox(width: 8),
                Icon(LucideIcons.wifi, size: 10, color: AppColors.textLow),
                const SizedBox(width: 3),
                Expanded(
                    child: Text(c.mac,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                            fontSize: 9.5,
                            height: 1.2,
                            color: AppColors.textLow),
                        overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 4),
            ],
            // Metrics: SNR / TX rate / RX rate / distance / uptime
            Wrap(spacing: 8, runSpacing: 4, children: [
              if (c.snrDb != null)
                _clientMetric(LucideIcons.activity, '${c.snrDb} dB',
                    _snrColor(c.snrDb!.toDouble())),
              if (c.txRateMbps != null)
                _clientMetric(LucideIcons.arrowUp, '${c.txRateMbps} Mbps',
                    AppColors.brandAccent),
              if (c.rxRateMbps != null)
                _clientMetric(LucideIcons.arrowDown, '${c.rxRateMbps} Mbps',
                    AppColors.success),
              if (c.distanceMeters != null)
                _clientMetric(
                    LucideIcons.ruler,
                    c.distanceMeters! >= 1000
                        ? '${(c.distanceMeters! / 1000).toStringAsFixed(1)} km'
                        : '${c.distanceMeters} m',
                    AppColors.textMid),
              if (c.uptimeSec != null && c.uptimeSec! > 0)
                _clientMetric(LucideIcons.clock, _formatUptime(c.uptimeSec!),
                    AppColors.textMid),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _clientMetric(IconData icon, String value, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 10, color: color),
      const SizedBox(width: 3),
      Text(value,
          textDirection: TextDirection.ltr,
          style: AppType.microBold(color: color)),
    ]);
  }

  /// لون حسب قوّة الـRSSI (dBm — أقرب للصفر أفضل)
  Color _rssiColor(int? dbm) => Grade.signal(dbm).fill;

  Widget _chainMetric(String label, String value, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style:
              TextStyle(fontSize: 9.5, height: 1.2, color: AppColors.textLow)),
      const SizedBox(height: 2),
      Text(value,
          textDirection: TextDirection.ltr,
          style: AppType.pillBold(color: color)),
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // 📈 سير الترفك — من فارق عدّادات الأوكتِتات
  //
  // ⚠️ التسمية والتخطيط من لوحة ميكروتك حرفيّاً (`_trafficGraph`).
  // اخترعتُ لها اسماً ومظهراً مختلفَين فبدت غريبةً عن أخواتها
  // (بلاغ ٢٠٢٦-٠٩-٠٢: «التزم بمسمّيات بقيّة الأجهزة · شوف المايكروتيك
  // كيف مرتّب وسوّي مثله»). الشارات في الرأس لا بطاقتان ضخمتان،
  // والمحور بتنسيقٍ مختصر.
  // ═══════════════════════════════════════════════════════
  Widget _trafficGraph() {
    final rxSpots = <FlSpot>[];
    final txSpots = <FlSpot>[];
    for (var i = 0; i < _history.length; i++) {
      rxSpots.add(FlSpot(i.toDouble(), _history[i].rxBps.toDouble()));
      txSpots.add(FlSpot(i.toDouble(), _history[i].txBps.toDouble()));
    }
    final peak = _history.fold<int>(
        0, (m, x) => math.max(m, math.max(x.rxBps, x.txBps)));
    final maxY = (peak * 1.25).clamp(1000, double.infinity).toDouble();
    final lastRx = _history.isNotEmpty ? _history.last.rxBps : 0;
    final lastTx = _history.isNotEmpty ? _history.last.txBps : 0;

    final rxColor = AppColors.success;
    final txColor = AppColors.brandAccent;

    return _cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.chartLine, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('سير الترفك', style: AppType.pillBold(color: AppColors.textHi)),
          const Spacer(),
          // لا رقم قبل عيّنتين: «٠» يوحي بوصلةٍ صامتة وهي تحمل عشرات
          // الميغا، والعيّنة الأولى بلا سابقة فلا فارق.
          if (_history.isEmpty)
            Text('يقيس…', style: AppType.muted())
          else ...[
            _legendChip('↓', _formatBps(lastRx), rxColor),
            const SizedBox(width: 6),
            _legendChip('↑', _formatBps(lastTx), txColor),
          ],
        ]),
        if (_history.length >= 2) ...[
          const SizedBox(height: 12),
          SizedBox(
            // ⚠️ ١٢٨ لا ١٢٠، والفارق حشوٌ سفليّ داخل الصندوق.
            //
            // `fl_chart` يمدّ منطقة الرسم إلى حافّة صندوقها تماماً حين
            // تُخفى تسميات المحور السفليّ، فلا يفصل خطَّ الصفر عن حدّ
            // البطاقة إلّا حشوُها — ويبدو الرسم ملتصقاً بالقاع.
            // (بلاغ ٢٠٢٦-٠٩-٠٢)
            height: 128,
            child: RepaintBoundary(
              child: LineChart(
                duration: Duration.zero,
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: AppColors.borderSoft, strokeWidth: 0.5),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        interval: maxY / 3,
                        // ⚠️ مختصر («48M») لا «47.9 Mbps»: الثاني أعرض
                        // من الحيّز المحجوز فيلتفّ سطرين ويركب الرسم.
                        getTitlesWidget: (v, _) => Text(
                          _formatBpsShort(v.toInt()),
                          style: TextStyle(
                              fontSize: 9.5,
                              height: 1.2,
                              color: AppColors.textLow),
                        ),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  // حشوٌ داخل الرسم نفسه: يُبعد خطّ الصفر عن الحافّة
                  // ويترك للتعبئة أن تُقرأ.
                  minY: 0,
                  maxY: maxY,
                  minX: 0,
                  maxX: (_history.length - 1).toDouble(),
                  lineBarsData: [
                    _trafficLine(txSpots, txColor),
                    _trafficLine(rxSpots, rxColor),
                  ],
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) =>
                          AppColors.textHi.withValues(alpha: 0.9),
                      getTooltipItems: (spots) => spots.map((sp) {
                        final isTx = sp.barIndex == 0;
                        return LineTooltipItem(
                          '${isTx ? "↑" : "↓"} ${_formatBps(sp.y.toInt())}',
                          AppType.microBold(color: isTx ? txColor : rxColor),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Sp.xs),
        ],
      ]),
    );
  }

  LineChartBarData _trafficLine(List<FlSpot> spots, Color c) =>
      LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.25,
        color: c,
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: true, color: c.withValues(alpha: 0.14)),
      );

  Widget _legendChip(String arrow, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Text('$arrow $value', style: AppType.microBold(color: color)),
    );
  }

  /// نفس تنسيق ميكروتك حرفيّاً — الشاشتان تعرضان الشيء نفسه.
  String _formatBps(int bps) {
    if (bps <= 0) return '0';
    if (bps < 1000) return '${bps}bps';
    if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(1)}K';
    if (bps < 1000000000) return '${(bps / 1000000).toStringAsFixed(1)}M';
    return '${(bps / 1000000000).toStringAsFixed(2)}G';
  }

  String _formatBpsShort(int bps) {
    if (bps < 1000) return '0';
    if (bps < 1000000) return '${(bps / 1000).round()}K';
    if (bps < 1000000000) return '${(bps / 1000000).round()}M';
    return '${(bps / 1000000000).toStringAsFixed(1)}G';
  }

  // ═══════════════════════════════════════════════════════
  // 📊 Rates card
  // ═══════════════════════════════════════════════════════
  Widget _ratesCard(MimosaStats s) {
    return _cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.chartLine, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('سعة الوصلة (PHY)', style: AppType.bodyBold()),
        ]),
        // ⚠️ «سعة» لا «أداء»: هذان الرقمان معدّل الطبقة الفيزيائيّة —
        // أقصى ما تحمله الوصلة، لا ما تحمله فعلاً. والمرور الحقيقيّ في
        // البطاقة تحتها. تسميتُهما «أداءً» أوهمت أنّ الوصلة تحمل ٦٥٠
        // ميغا وهي تحمل بضعة.
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _valueCard(
            icon: LucideIcons.arrowDown,
            label: 'RX Rate',
            value: s.phyRxRateMbps?.toString() ?? '—',
            unit: 'Mbps',
            color: AppColors.success,
          )),
          const SizedBox(width: 8),
          Expanded(
              child: _valueCard(
            icon: LucideIcons.arrowUp,
            label: 'TX Rate',
            value: s.phyTxRateMbps?.toString() ?? '—',
            unit: 'Mbps',
            color: AppColors.brandAccent,
          )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: _valueCard(
            icon: LucideIcons.circleAlert,
            label: 'RX Errors',
            value: s.perRxRatePct != null
                ? s.perRxRatePct!.toStringAsFixed(1)
                : '—',
            unit: '%',
            color: _errColor(s.perRxRatePct),
          )),
          const SizedBox(width: 8),
          Expanded(
              child: _valueCard(
            icon: LucideIcons.circleAlert,
            label: 'TX Errors',
            value: s.perTxRatePct != null
                ? s.perTxRatePct!.toStringAsFixed(1)
                : '—',
            unit: '%',
            color: _errColor(s.perTxRatePct),
          )),
        ]),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 🌡️ System — Uptime + Antenna gain (CPU/RAM غير متوفّرين)
  // ═══════════════════════════════════════════════════════
  Widget _systemCard(MimosaStats s) {
    return _cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.cpu, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('النظام', style: AppType.bodyBold()),
        ]),
        const SizedBox(height: 12),
        // ⚠️ «زمن التشغيل» = منذ متى **والوصلة قائمة**. ولا سقوطَ إلى
        // عمر وكيل SNMP عند غيابها.
        //
        // 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «أوّل ما أفتح ميموزا يطلع زمن الاتصال
        // الذي قلتُ لك عليه». والسبب أنّ الحمولة الأولى (Tier 1) بلا
        // مدّة وصلة، فيسقط العرض إلى عمر الوكيل ويومض رقمٌ قصير خاطئ
        // (٤١ دقيقة) قبل أن يصحّح إلى ٩ أيّام.
        //
        // فالسطر يغيب حتّى تصل قيمتُه الصحيحة. غيابُ سطرٍ لحظةً أهون
        // من رقمٍ يكذب — والرقم هنا يقول إنّ البرج سقط قبل دقائق.
        if (s.linkUptimeSec != null)
          _infoRow('زمن التشغيل', _formatUptime(s.linkUptimeSec!)),
        if (s.antennaGainDbi != null)
          _infoRow('Antenna Gain', '${s.antennaGainDbi} dBi'),
        if (s.wirelessMode != null)
          _infoRow('Mode', _modeLabel(s.wirelessMode!)),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('CPU/RAM غير متوفّرين — firmware Mimosa يخفيهما',
              style: TextStyle(
                  fontSize: 9.5,
                  height: 1.2,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textLow)),
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 📍 GPS
  // ═══════════════════════════════════════════════════════
  Widget _gpsCard(MimosaStats s) {
    final lat = s.latitude!.toStringAsFixed(6);
    final lng = s.longitude!.toStringAsFixed(6);
    final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    return _cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.mapPin, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('GPS', style: AppType.bodyBold()),
          const Spacer(),
          if (s.gpsSats != null)
            Text('${s.gpsSats} satellites',
                style: TextStyle(
                    fontSize: 10.5, height: 1.3, color: AppColors.textLow)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: Text(
            '$lat, $lng',
            textDirection: TextDirection.ltr,
            style: AppType.pillBold(color: AppColors.textHi),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )),
          IconButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: mapsUrl));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('نُسخ رابط Google Maps'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating));
              }
            },
            icon: Icon(LucideIcons.externalLink,
                size: 16, color: AppColors.brand),
            tooltip: 'نسخ رابط Google Maps',
          ),
        ]),
        if (s.altitude != null) _infoRow('Altitude', '${s.altitude} m'),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ℹ️ Info
  // ═══════════════════════════════════════════════════════
  Widget _infoCard(MimosaStats s) {
    return ExpandableSection(
      key: PageStorageKey('mimosa-${widget.device.id}-info'),
      initiallyExpanded: false,
      header: Row(children: [
        Icon(LucideIcons.info, size: 14, color: AppColors.textMid),
        const SizedBox(width: 6),
        Text('معلومات الجهاز', style: AppType.bodyBold()),
      ]),
      content: Column(children: [
        if (s.firmwareVersion != null) _infoRow('Firmware', s.firmwareVersion!),
        if (s.serialNumber != null) _infoRow('Serial', s.serialNumber!),
      ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(label, style: AppType.pillBold(color: AppColors.textMid)),
        const SizedBox(width: Sp.sm),
        // ⚠️ `Expanded` لا `Spacer()+Flexible`: لكليهما flex=1 فيتقاسمان
        // الفراغ، و`Flexible` بالملاءمة الرخوة تأخذ مقاسها الطبيعي فقط
        // فيضيع نصيبها بلا إعادة توزيع — وتبقى القيمة بعيدةً عن النهاية
        // بفجوة. `Expanded` يبتلع الفراغ كلّه و`textAlign: end` يلصقها.
        Expanded(
            child: Text(value,
                textDirection: TextDirection.ltr,
                style: AppType.pillBold(color: AppColors.textHi),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end)),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════
  Widget _cardWrapper({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _valueCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: AppType.daysWordBold(color: AppColors.textMid)),
        ]),
        const SizedBox(height: 8),
        Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: color,
                      height: 1)),
              const SizedBox(width: 2),
              Text(unit, style: AppType.daysWord(color: AppColors.textLow)),
            ]),
      ]),
    );
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.dangerSoftBg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.dangerSoftBorder),
      ),
      child: Row(children: [
        Icon(LucideIcons.circleAlert, size: 20, color: AppColors.error),
        const SizedBox(width: 8),
        Expanded(
            child: Text(_error ?? 'خطأ',
                style: AppType.bodyStrong(color: AppColors.error))),
        TextButton(onPressed: _fetch, child: const Text('إعادة')),
      ]),
    );
  }

  Color _rxColor(double dbm) => Grade.rxPower(dbm).fill;

  Color _snrColor(double snr) => Grade.snr(snr).fill;

  Color _tempColor(double t) => Grade.temperature(t).fill;

  Color _errColor(double? pct) => Grade.errorRate(pct).fill;

  String _modeLabel(int mode) {
    switch (mode) {
      case 1:
        return 'AP';
      case 2:
        return 'STA';
      default:
        return 'mode $mode';
    }
  }

  String _formatUptime(int seconds) {
    if (seconds <= 0) return '—';
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _TrafficSample {
  const _TrafficSample(
      {required this.at, required this.rxBps, required this.txBps});
  final DateTime at;
  final int rxBps;
  final int txBps;
}
