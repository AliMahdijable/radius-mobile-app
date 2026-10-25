import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/network_devices_api.dart';
import '../../../api/ubnt_api.dart';
import '../../../models/network_device.dart';
import '../../../services/device_stats_cache.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import 'expandable_section.dart';
import '_grade.dart';
import '../../../theme/typography.dart';
import '../detected_model.dart';
import '../../../core/util/error_text.dart';
import '../../desktop/desk_widgets.dart';
import '../../../core/widgets/copyable.dart';
import '../../../core/platform/desktop_layout.dart';
import '../../../core/util/bidi.dart';
import 'desk_device_kit.dart';

/// Panel للمراقبة الحيّة لجهاز UBNT airMax/airFiber.
/// التركيز على **wireless quality** (signal/SNR) لأنه المهم في PtP/PtMP.
class UbntLivePanel extends StatefulWidget {
  final NetworkDevice device;

  /// callback يُطلق مرّة واحدة حين نكتشف من الـstats أن الجهاز فعلاً
  /// airFiber 60 (رغم أن الـdevice.model ما مذكور فيه). الـcaller
  /// (details screen) يستخدمها ليبدّل للـAirFiber60LivePanel.
  /// 2026-08-18.
  final VoidCallback? onAirFiber60Detected;
  const UbntLivePanel(
      {super.key, required this.device, this.onAirFiber60Detected});

  @override
  State<UbntLivePanel> createState() => _UbntLivePanelState();
}

class _UbntLivePanelState extends State<UbntLivePanel> {
  UbntStats? _stats;
  bool _loading = false;
  String? _error;
  Timer? _timer;
  bool _monitoring = false;
  DateTime? _lastFetch;

  // rate tracking للـinterfaces
  final Map<String, _BytesPoint> _lastBytes = {};
  final Map<String, _IfaceRate> _rates = {};

  /// history للـtraffic (أعلى interface بكل جولة) — للـgraph
  /// 30 samples × 15s ≈ 7 دقائق تاريخ. مماثل لـMikrotik.
  final List<_TrafficSample> _history = [];
  static const int _maxHistory = 30;

  /// 2026-08-18: local guard — الـcallback onAirFiber60Detected تُطلق
  /// مرّة واحدة فقط عبر lifecycle الـpanel (بدل كل fetch بعد الاكتشاف).
  bool _af60Notified = false;

  /// 2026-08-20: sticky snapshot لآخر stations معروفة (مثل Mikrotik).
  /// يمنع اختفاء "قسم العملاء" عند refresh عابر يرجع wstalist فارغ
  /// (permission glitch، SSH timeout، firmware ذُبذبة).
  List<UbntStation> _stickyStations = const [];

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
    _stats = DeviceStatsCache.instance.seedFor<UbntStats>(widget.device.id);
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
    setState(() => _loading = true);
    try {
      final creds = await NetworkDevicesApi.getCredentials(widget.device.id);
      final user = (creds['user'] ?? '').toString();
      final pass = (creds['pass'] ?? '').toString();
      if (user.isEmpty || pass.isEmpty) {
        throw UbntException('لم يتم إعداد credentials للجهاز');
      }
      // 2026-08-18: partial فقط لأوّل تحميل — refresh لا يستفيد منه لأنّ
      // partial يفرغ stations/interfaces مؤقّتاً → ExpandableSections تختفي
      // → تفقد حالتها (expanded/collapsed) → تُرندَر بالوضع الافتراضي.
      // نفس bug AF60 الي أصلحته سابقاً.
      final isFirstLoad = _stats == null;
      final stats = await UbntApi.fetchStats(
        ip: widget.device.ip,
        port: widget.device.apiPort ?? 22, // SSH default
        user: user,
        pass: pass,
        // ⚡ Tier 1 partial بعد mca-status (~500ms-1s): CPU/RAM/temp/signal
        // بدل انتظار wstalist + ifconfig + link speeds (~2-3s كامل)
        // ⚠️ **لا** نلمس _lastFetch/_lastBytes هنا (نفس bug Mikrotik السابق —
        // rate calc يستعمل elapsed مغلوط).
        onPartialReady: isFirstLoad
            ? (partial) {
                if (!mounted) return;
                setState(() {
                  _stats = partial;
                });
              }
            : null, // ← refresh: تجاهل partial، انتظر البيانات الكاملة
      );
      if (!mounted) return;

      final now = DateTime.now();
      // احسب rates
      if (_lastFetch != null) {
        final elapsed = now.difference(_lastFetch!).inMilliseconds / 1000.0;
        if (elapsed > 0) {
          for (final iface in stats.interfaces) {
            final prev = _lastBytes[iface.ifname];
            if (prev != null &&
                iface.rxBytes != null &&
                iface.txBytes != null) {
              final dRx = iface.rxBytes! - prev.rxBytes;
              final dTx = iface.txBytes! - prev.txBytes;
              if (dRx >= 0 && dTx >= 0) {
                _rates[iface.ifname] = _IfaceRate(
                  rxBps: (dRx * 8 / elapsed).round(),
                  txBps: (dTx * 8 / elapsed).round(),
                );
              }
            }
          }
        }
      }
      for (final iface in stats.interfaces) {
        if (iface.rxBytes != null && iface.txBytes != null) {
          _lastBytes[iface.ifname] = _BytesPoint(
            rxBytes: iface.rxBytes!,
            txBytes: iface.txBytes!,
          );
        }
      }
      // 2026-08-18: أضف sample لـtraffic graph — أعلى interface هذه الجولة
      // (نفس نمط Mikrotik). لا نُضيف قبل _lastFetch لأنّ الـrates لسّه 0.
      if (_lastFetch != null) {
        int maxRx = 0, maxTx = 0;
        for (final iface in _headlinePool(stats.interfaces)) {
          final r = _rates[iface.ifname];
          if (r != null) {
            if (r.rxBps > maxRx) maxRx = r.rxBps;
            if (r.txBps > maxTx) maxTx = r.txBps;
          }
        }
        _history.add(_TrafficSample(at: now, rxBps: maxRx, txBps: maxTx));
        if (_history.length > _maxHistory) _history.removeAt(0);
      }

      // 2026-08-20: sticky stations — keep last known non-empty snapshot
      // إذا wstalist رجع فارغاً عابراً (permission، SSH glitch)، UI يبقى
      // يعرض آخر عملاء بدل ما القسم يختفي. صفّرها فقط لو wireless غاب
      // كلياً (الجهاز ما عاد AP).
      final freshStations = stats.stations;
      final noWireless = stats.wireless == null;
      _stickyStations = noWireless
          ? const <UbntStation>[]
          : (freshStations.isNotEmpty ? freshStations : _stickyStations);

      setState(() {
        _stats = stats;
        DeviceStatsCache.instance.putRaw(widget.device.id, stats);
        _loading = false;
        _error = null;
        _lastFetch = now;
      });
      // airOS يُبلّغ الطراز في `devmodel` — أدقّ من «AirMax» التي
      // يكتبها المدير (خطّ منتجات لا موديل).
      DetectedModel.save(widget.device, stats.host.devmodel);
      // 2026-08-18: كشف AF60 من الـstats — مرّة واحدة فقط عبر lifecycle.
      // كنا نطلق الـcallback كل fetch (بين إطلاقها وrebuild+dispose، أي
      // fetch جارٍ سيُطلقها ثانية). local flag يمنع الإطلاق المتكرّر.
      if (!_af60Notified &&
          stats.isAirFiber60 &&
          widget.onAirFiber60Detected != null) {
        _af60Notified = true;
        widget.onAirFiber60Detected!();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is UbntException ? e.message : humanError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stats == null && _error == null) {
      return _connectingBox();
    }
    // 2026-08-18: أُعيد بناء البانل بنمط "كل قسم في كارت منفصل" مطابق
    // لـAirFiber60LivePanel + mode-aware ordering:
    //   - PtP link (Station mode): إشارة كبيرة + التركيز على peer واحد
    //   - PtMP AP mode: mode chip + التركيز على قائمة العملاء
    final s = _stats;
    if (s != null && DesktopScope.of(context)) return _deskBuild(s);
    final isAp = s?.isAp ?? false;
    final isStation = s?.isStation ?? false;
    return Column(children: [
      // Header (control bar — pause/refresh/آخر تحديث)
      _cardWrapper(child: _header()),
      if (_error != null) ...[
        const SizedBox(height: Sp.md),
        _cardWrapper(child: _errorBox()),
      ],
      if (s != null) ...[
        // Board banner (airOS / airFiber badge + uptime + mode indicator)
        const SizedBox(height: Sp.md),
        _cardWrapper(child: _boardBanner()),
        // Mode indicator (PtP link / PtMP access point) — 2026-08-18
        if (isAp || isStation) ...[
          const SizedBox(height: Sp.md),
          _cardWrapper(child: _modeIndicator(isAp: isAp)),
        ],
        // System metrics (Uptime / حرارة / CPU)
        const SizedBox(height: Sp.md),
        _cardWrapper(child: _systemMetrics()),
        // Signal hero — لو فيه wireless. حجم أكبر لـPtP (peer link)،
        // أصغر لـPtMP (فيه clients متعدّدين — القسم مو الأهم)
        if (s.wireless != null) ...[
          const SizedBox(height: Sp.md),
          _cardWrapper(child: _signalHero(s.wireless!)),
        ],
        // Traffic graph — widget مستقلّ مع KeepAlive → state ينجو من
        // parent rebuilds (كان يختفي/يعود على كل refresh قبل الإصلاح).
        // ValueKey('ubnt-graph-<id>') يضمن نفس الـState instance عبر builds.
        if (_history.length >= 2) ...[
          const SizedBox(height: Sp.md),
          _TrafficGraphCard(
            key: ValueKey('ubnt-graph-${widget.device.id}'),
            history: List.unmodifiable(_history),
            cardWrapper: _cardWrapper,
          ),
        ],
        // Expandable sections — للـPtMP نُظهر Stations أوّلاً (الأهم)
        ..._buildExpandables(),
      ],
    ]);
  }

  // ══════════════════════════════════════════════════════════════
  // الحاسبة — كصفحة المايكروتك: الحقائق في شريط، والأرقام كبيرةً في صفّ، والرسم بنافذةٍ ثابتة،
  // والعملاء والواجهات جداول (المالك ٢٤ أكتوبر: «بشكل حاسبة وليس موبايل»). الهاتف كما هو.
  // ══════════════════════════════════════════════════════════════
  Widget _deskBuild(UbntStats s) {
    final h = s.host;
    final w = s.wireless;
    return Column(children: [
      DeskPanelCard(children: [
        _header(),
        if (_error != null) _errorBox(),
        DeskFactsBanner(facts: [
          (icon: LucideIcons.radioTower, label: 'الطراز', value: h.devmodel),
          (icon: LucideIcons.package, label: 'airOS', value: h.fwversion),
          if (h.uptime > 0) (icon: LucideIcons.clock, label: 'يعمل منذ', value: deskUptimeAr(Duration(seconds: h.uptime))),
          if (w != null) (icon: LucideIcons.arrowLeftRight, label: 'الوضع', value: _modeLabel(w.mode)),
          if (w != null && w.frequency > 0)
            (
              icon: LucideIcons.satellite,
              label: 'التردّد',
              value: iso(isoJoin(['${w.frequency} MHz', if (w.chanbw > 0) '${w.chanbw} MHz'], ' · ')),
            ),
        ]),
        DeskTilesRow(tiles: _deskTiles(s)),
        DeskTrafficCard(
          samples: [for (final p in _history) (rx: p.rxBps, tx: p.txBps)],
          capacity: _maxHistory,
          interval: _refreshInterval,
          subtitle: 'أعلى واجهةٍ في كلّ لحظة',
        ),
      ]),
      ..._deskExpandables(s),
    ]);
  }

  List<Widget> _deskTiles(UbntStats s) {
    final h = s.host;
    final w = s.wireless;
    final down = _deskTopRate(rx: true), up = _deskTopRate(rx: false);
    return [
      DeskPercentTile(icon: LucideIcons.cpu, label: 'المعالج', percent: h.cpuload.toDouble()),
      if (s.memUsedPercent case final mem?)
        DeskPercentTile(
          icon: LucideIcons.memoryStick,
          label: 'الذاكرة',
          percent: mem,
          sub: (s.memUsedMb != null && s.memTotalMb != null) ? '${iso('${s.memUsedMb} MB')} من ${iso('${s.memTotalMb} MB')}' : null,
        ),
      DeskTempTile(celsius: h.temperature),
      // نقطة وصولٍ لعدّة عملاء: عددهم وأضعفهم — إشارتها وحدها متوسّطٌ لا يدلّ على أحد. الوصلة: إشارتها.
      if (s.isAp && _stickyStations.length != 1)
        _deskClientsTile()
      else if (w != null)
        DeskMetricTile(
          icon: LucideIcons.signal,
          label: 'الإشارة',
          color: Grade.signal(w.signal).fill,
          value: DeskBigValue('${w.signal}', 'dBm', color: Grade.signal(w.signal).fill),
          footer: deskSub(isoJoin([_signalLabel(w.signal), if (w.snr != null) 'SNR ${w.snr} dB'], ' · ')),
        ),
      DeskRateTile(down: true, bps: down?.bps, source: down?.name, measuring: _rates.isEmpty),
      DeskRateTile(down: false, bps: up?.bps, source: up?.name, measuring: _rates.isEmpty),
    ];
  }

  Widget _deskClientsTile() {
    final list = _stickyStations;
    final weakest = list.isEmpty ? null : list.map((c) => c.signal).reduce(math.min);
    return DeskMetricTile(
      icon: LucideIcons.users,
      label: 'العملاء',
      color: AppColors.brand,
      value: DeskBigValue('${list.length}', ''),
      footer: weakest == null
          ? deskSub('لا عملاء الآن')
          : deskSub('أضعفهم ${iso('$weakest dBm')}', color: Grade.signal(weakest).fill),
    );
  }

  /// أعلى واجهةٍ تنزيلاً أو رفعاً الآن — من [_headlinePool] كالرسم.
  ({String name, int bps})? _deskTopRate({required bool rx}) {
    ({String name, int bps})? best;
    for (final i in _headlinePool()) {
      final r = _rates[i.ifname];
      if (r == null) continue;
      final v = rx ? r.rxBps : r.txBps;
      if (best == null || v > best.bps) best = (name: i.ifname, bps: v);
    }
    return best;
  }

  List<Widget> _deskExpandables(UbntStats s) {
    final id = widget.device.id;
    final w = s.wireless;
    final ifaces = s.interfaces.where(_isDataIface).toList();
    final stations = _stickyStations.isEmpty
        ? null
        : ExpandableSection(
            key: PageStorageKey('ubnt-$id-stations'),
            initiallyExpanded: true,
            header: DeskSectionHeader(
              icon: LucideIcons.users,
              title: s.isAp ? 'العملاء المتّصلون' : 'الطرف الآخر',
              count: s.isAp ? _stickyStations.length : null,
            ),
            content: RepaintBoundary(child: _deskStationsTable(_stickyStations)),
          );
    final ifaceSection = ifaces.isEmpty
        ? null
        : ExpandableSection(
            key: PageStorageKey('ubnt-$id-interfaces'),
            initiallyExpanded: true,
            header: DeskSectionHeader(icon: LucideIcons.network, title: 'الواجهات', count: ifaces.length),
            content: RepaintBoundary(child: _deskInterfacesTable(ifaces)),
          );
    final wifi = w == null
        ? null
        : ExpandableSection(
            key: PageStorageKey('ubnt-$id-wireless'),
            initiallyExpanded: true,
            header: const DeskSectionHeader(icon: LucideIcons.wifi, title: 'اللاسلكيّ'),
            content: _deskWirelessFacts(w),
          );
    // نقطة الوصول: العملاء أوّلاً بعرض الصفحة؛ الوصلة: الطرف الآخر بعد الواجهات واللاسلكيّ.
    return [
      if (s.isAp && stations != null) ...[const SizedBox(height: Sp.md), stations],
      if (ifaceSection != null || wifi != null) ...[
        const SizedBox(height: Sp.md),
        deskSideBySide(ifaceSection, wifi),
      ],
      if (!s.isAp && stations != null) ...[const SizedBox(height: Sp.md), stations],
    ];
  }

  Widget _deskWirelessFacts(UbntWireless w) {
    return DeskFactsGrid(facts: [
      if (w.essid.isNotEmpty) DeskFact('اسم الشبكة (SSID)', w.essid, ltr: true, copy: true),
      DeskFact('الوضع', _modeLabel(w.mode), ltr: true),
      DeskFact('سرعة الوصلة', '↓${w.rxRate} / ↑${w.txRate} Mbps', ltr: true),
      if (w.frequency > 0) DeskFact('التردّد', '${w.frequency} MHz', ltr: true),
      if (w.chanbw > 0) DeskFact('عرض القناة', '${w.chanbw} MHz', ltr: true),
      if (w.channel > 0) DeskFact('القناة', '${w.channel}', ltr: true),
      if (w.signal != 0) DeskFact('الإشارة', '${w.signal} dBm', ltr: true, color: Grade.signal(w.signal).fill),
      if (w.snr != null) DeskFact('SNR', '${w.snr} dB', ltr: true, color: Grade.snr(w.snr).fill),
      if (w.hasCcq) DeskFact('جودة الوصلة (CCQ)', '${w.ccq}%', ltr: true, color: Grade.percentHigherBetter(w.ccq).fill),
      if (w.hasNoise) DeskFact('الضوضاء', '${w.noise} dBm', ltr: true),
      if (w.distance > 0)
        DeskFact('المسافة', w.distance >= 1000 ? '${(w.distance / 1000).toStringAsFixed(1)} km' : '${w.distance} m',
            ltr: true),
    ]);
  }

  /// العملاء جدولاً كـ«Registration Table»: الاسم والـIP والماك تُنسخ، وأعمدة IP وCCQ والمسافة بقدر ما يعطيه الجهاز.
  Widget _deskStationsTable(List<UbntStation> list) {
    const limit = 100;
    final ip = list.any((c) => (c.ip ?? '').isNotEmpty);
    final ccq = list.any((c) => c.ccq > 0);
    final dist = list.any((c) => (c.distanceMeters ?? 0) > 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DeskTable(
        columns: [
          ('العميل', 4),
          if (ip) ('IP', 3),
          ('الماك', 3),
          ('الإشارة', 3),
          if (ccq) ('CCQ', 2),
          ('السرعة', 3),
          if (dist) ('المسافة', 2),
          ('متّصل منذ', 2),
        ],
        rows: [
          for (final c in list.take(limit))
            [
              if ((c.hostname ?? '').isNotEmpty)
                Copyable(
                  label: 'اسم الجهاز',
                  value: c.hostname!,
                  child: Text(c.hostname!,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.rowValue(color: AppColors.textHi)),
                )
              else
                Text('بلا اسم', style: AppType.body(color: AppColors.textLow)),
              if (ip) (c.ip ?? '').isNotEmpty ? DeskMonoCell(c.ip!, label: 'IP') : deskDash(),
              DeskMonoCell(c.mac, label: 'الماك'),
              DeskDotValue(value: c.signalDisplay, unit: 'dBm', color: Grade.signal(c.signal).fill),
              if (ccq)
                c.ccq > 0
                    ? Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: DeskPill('${c.ccq}%', Grade.percentHigherBetter(c.ccq)))
                    : deskDash(),
              DeskRatePair(rx: c.rxRate, tx: c.txRate),
              if (dist)
                (c.distanceMeters ?? 0) > 0
                    ? Text(
                        iso(c.distanceMeters! >= 1000
                            ? '${(c.distanceMeters! / 1000).toStringAsFixed(1)} km'
                            : '${c.distanceMeters} m'),
                        style: AppType.body(color: AppColors.textBody))
                    : deskDash(),
              Text(c.connTime > 0 ? deskDurationAr(c.connTime) : '—',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textBody)),
            ],
        ],
      ),
      if (list.length > limit)
        deskMoreRows(list.length - limit, one: 'عميلٌ آخر', two: 'عميلان آخران', few: 'عملاء آخرين', many: 'عميلاً آخر'),
    ]);
  }

  Widget _deskInterfacesTable(List<UbntInterface> rows) {
    int maxRx = 0, maxTx = 0;
    for (final i in rows) {
      final r = _rates[i.ifname];
      if (r != null) {
        maxRx = math.max(maxRx, r.rxBps);
        maxTx = math.max(maxTx, r.txBps);
      }
    }
    return DeskTable(
      columns: const [('الواجهة', 4), ('الربط', 2), ('الماك', 4), ('تنزيل ↓', 3), ('رفع ↑', 3)],
      rows: [
        for (final i in rows)
          () {
            final up = i.plugged && i.enabled;
            final r = _rates[i.ifname];
            return <Widget>[
              DeskNameCell(
                name: i.ifname,
                sub: !i.enabled ? 'معطّلة' : (i.plugged ? 'تعمل' : 'مفصولة'),
                tone: up ? AppTone.success : (i.enabled ? AppTone.danger : AppTone.neutral),
                dim: !i.enabled,
              ),
              (i.speed != null && up)
                  ? Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: DeskPill(_speedLabel(i.speed!), Grade.speedMbps(i.speed!)))
                  : deskDash(),
              i.hwaddr.isNotEmpty ? DeskMonoCell(i.hwaddr, label: 'الماك') : deskDash(),
              DeskRateCell(bps: r?.rxBps, down: true, max: maxRx, live: up),
              DeskRateCell(bps: r?.txBps, down: false, max: maxTx, live: up),
            ];
          }(),
      ],
    );
  }

  /// شارة تُظهر نمط عمل الجهاز — لينك PtP أم AP PtMP.
  /// 2026-08-18: طلب المستخدم — يريد فرق مرئي واضح بين الاثنين.
  Widget _modeIndicator({required bool isAp}) {
    final color = isAp
        ? AppColors.brandAccent // بنفسجي — AP يخدم عملاء
        : AppColors.info; // فيروزي — لينك PtP
    final icon = isAp ? LucideIcons.radioTower : LucideIcons.arrowLeftRight;
    final title =
        isAp ? 'نقطة وصول (Access Point)' : 'لينك نقطة-إلى-نقطة (PtP)';
    final subtitle =
        isAp ? 'يخدم عدة عملاء — PtMP' : 'اتصال مباشر مع peer واحد';
    // 2026-08-20: نستعمل _stickyStations لعرض العدد كي ما يتذبذب عند refresh عابر
    final count = isAp && _stickyStations.isNotEmpty
        ? '${_stickyStations.length} عميل'
        : null;
    return Row(children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: AppType.rowLabelBold()),
            const SizedBox(height: 2),
            Text(subtitle,
                style: AppType.muted(color: AppColors.textMid)),
          ],
        ),
      ),
      if (count != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Text(count,
              style: AppType.pillBold(color: AppColors.onBrand)),
        ),
    ]);
  }

  /// Card wrapper — نفس نمط AirFiber60LivePanel لتوحيد الشكل بين الاثنين.
  /// 2026-08-18.
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

  List<Widget> _buildExpandables() {
    final s = _stats!;
    // 2026-08-18: ترتيب حسب نمط الجهاز — PtMP يُظهر Stations أوّلاً
    // (الأهم للـWISP)، PtP يُظهر Wireless details أوّلاً.
    final isAp = s.isAp;
    // 2026-08-18: PageStorageKey — يحفظ حالة expanded عبر rebuilds
    // (وحتى لو موقع القسم في الـColumn تغيّر). أساسي لأنّ refresh قد
    // يُغيّر ترتيب/وجود الأقسام (لكن الحالة تبقى محفوظة).
    final deviceId = widget.device.id;
    final wirelessSection = s.wireless == null
        ? null
        : [
            const SizedBox(height: Sp.md),
            ExpandableSection(
              key: PageStorageKey('ubnt-$deviceId-wireless'),
              initiallyExpanded: !isAp, // AP: مطويّ افتراضياً (المهمّ العملاء)
              header: Row(children: [
                Icon(LucideIcons.wifi, size: 14, color: AppColors.brandAccent),
                const SizedBox(width: 6),
                Text('تفاصيل Wireless',
                    style: AppType.bodyBold()),
              ]),
              content: _wirelessDetails(s.wireless!),
            ),
          ];
    // 2026-08-20: نستعمل _stickyStations بدل s.stations كي القسم لا يختفي
    // عند refresh عابر يرجع wstalist فارغاً.
    final stationsSection = _stickyStations.isEmpty
        ? null
        : [
            const SizedBox(height: Sp.md),
            ExpandableSection(
              key: PageStorageKey('ubnt-$deviceId-stations'),
              initiallyExpanded: isAp, // AP: مفتوح افتراضياً
              header: Row(children: [
                Icon(LucideIcons.users, size: 14, color: AppColors.brandAccent),
                const SizedBox(width: 6),
                Text(
                  isAp
                      ? 'العملاء المتّصلون (${_stickyStations.length})'
                      : 'الطرف الآخر (peer)',
                  style: AppType.bodyBold(),
                ),
              ]),
              content: Column(children: [
                DeskRows(children: [for (final st in _stickyStations.take(20)) _stationRow(st)]),
                if (_stickyStations.length > 20)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('+ ${_stickyStations.length - 20} عميل آخر',
                        style: TextStyle(
                            fontSize: 10.5, height: 1.3, color: AppColors.textLow)),
                  ),
              ]),
            ),
          ];
    final ethernetSection = s.interfaces.isEmpty
        ? null
        : [
            const SizedBox(height: Sp.md),
            ExpandableSection(
              key: PageStorageKey('ubnt-$deviceId-interfaces'),
              initiallyExpanded: false, // دائماً مطويّ — معلومات ثانويّة
              header: Row(children: [
                Icon(LucideIcons.network,
                    size: 14, color: AppColors.brandAccent),
                const SizedBox(width: 6),
                Text('Interfaces (${s.interfaces.where(_isDataIface).length})',
                    style: AppType.bodyBold()),
              ]),
              content: Column(children: [
                for (final iface in s.interfaces.where(_isDataIface))
                  _interfaceRow(iface),
              ]),
            ),
          ];
    // ترتيب mode-aware:
    // - PtMP AP: Stations أوّلاً (العملاء = الأهم) ثمّ Wireless ثمّ Ethernet
    // - PtP link: Wireless (peer info) أوّلاً ثمّ Stations (peer الوحيد) ثمّ Ethernet
    return [
      if (isAp) ...[
        if (stationsSection != null) ...stationsSection,
        if (wirelessSection != null) ...wirelessSection,
      ] else ...[
        if (wirelessSection != null) ...wirelessSection,
        if (stationsSection != null) ...stationsSection,
      ],
      if (ethernetSection != null) ...ethernetSection,
    ];
  }

  Widget _connectingBox() {
    return Container(
      padding: const EdgeInsets.all(Sp.xl),
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
                strokeWidth: 2, color: AppColors.brand)),
        const SizedBox(width: 10),
        Text('جاري الاتصال بـUBNT…',
            style: AppType.body(color: AppColors.textMid)),
      ]),
    );
  }

  Widget _header() {
    // 2026-08-18: أُزيل الـPadding — الآن _cardWrapper يهتمّ بالـpadding
    return Row(children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.brandSoftBg,
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Icon(LucideIcons.radioTower,
            size: 16, color: AppColors.brandAccent),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('مراقبة حيّة (UBNT via SSH)',
              style: AppType.bodyBold()),
          const SizedBox(height: 2),
          Row(children: [
            if (_monitoring) ...[
              // 2026-08-18: opacity pulse بدل استبدال النصّ بـ"جاري التحديث…"
              // — لتفادي ظهور الجهاز كأنّه فُصل ورجع عند كل fetch
              AnimatedOpacity(
                duration: const Duration(milliseconds: 400),
                opacity: _loading ? 0.35 : 1.0,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: AppColors.success, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              _monitoring
                  ? 'مباشر · كل ${_refreshInterval.inSeconds}s'
                  : 'متوقّف',
              style: TextStyle(fontSize: 10.5, height: 1.3, color: AppColors.textMid),
            ),
          ]),
        ]),
      ),
      IconButton(
        icon: const Icon(LucideIcons.refreshCw, size: 16),
        onPressed: _loading ? null : _fetch,
        color: AppColors.brandAccent,
        visualDensity: VisualDensity.compact,
      ),
      IconButton(
        icon: Icon(_monitoring ? LucideIcons.pause : LucideIcons.play,
            size: 16, color: _monitoring ? AppColors.error : AppColors.success),
        onPressed: _monitoring ? _stopMonitoring : _startMonitoring,
        visualDensity: VisualDensity.compact,
      ),
    ]);
  }

  Widget _errorBox() {
    return Container(
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
            child: Text(_error!,
                style: TextStyle(
                    fontSize: 11, color: AppColors.error, height: 1.4))),
      ]),
    );
  }

  Widget _boardBanner() {
    final h = _stats!.host;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brandSoftBg,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(children: [
        Icon(LucideIcons.radioTower, size: 14, color: AppColors.brandAccent),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${h.devmodel} • airOS ${h.fwversion}',
            style: TextStyle(
                fontSize: 11, height: 1.25,
                fontWeight: FontWeight.w600,
                color: AppColors.textHi),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.brandSoftBg,
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.clock, size: 9, color: AppColors.brandAccent),
            const SizedBox(width: 3),
            Text(_formatUptime(h.uptime),
                style: AppType.microBold(color: AppColors.brandAccent)),
          ]),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // System metrics — CPU / RAM / Temperature (لو متوفّرة)
  // ══════════════════════════════════════════════════════════════
  Widget _systemMetrics() {
    final h = _stats!.host;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
              child: _percentCard(
            icon: LucideIcons.cpu,
            label: 'CPU',
            percent: h.cpuload.toDouble(),
          )),
          const SizedBox(width: 8),
          Expanded(
              child: _valueCard(
            icon: LucideIcons.thermometer,
            label: 'حرارة',
            value: h.temperature > 0 ? '${h.temperature}' : '—',
            unit: h.temperature > 0 ? '°C' : '',
            color: _tempColor(h.temperature),
          )),
          const SizedBox(width: 8),
          Expanded(
              child: _valueCard(
            icon: LucideIcons.clock,
            label: 'Uptime',
            value: h.uptime > 0 ? _formatUptime(h.uptime) : '—',
            unit: '', // نضم كل النصّ في value بحجم موحّد
            color: AppColors.brandAccent,
          )),
        ],
      ),
    );
  }

  Widget _percentCard({
    required IconData icon,
    required String label,
    required double percent,
  }) {
    final color = _percentGradeColor(percent);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: AppType.microBold(color: AppColors.textMid)),
        ]),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('${percent.round()}',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHi,
                    height: 1)),
            const SizedBox(width: 2),
            Text('%',
                style: TextStyle(fontSize: 10.5, height: 1.3, color: AppColors.textLow)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(R.pill),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ]),
    );
  }

  Widget _valueCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    // إذا القيمة تحتوي مسافة (مثل "4d 1h") نُصغّرها قليلاً لتتّسع
    final hasSpace = value.contains(' ');
    final valueSize = hasSpace ? 15.0 : 18.0;
    return Container(
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
            Text(label,
                style: AppType.microBold(color: AppColors.textMid)),
          ]),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: valueSize,
                      fontWeight: FontWeight.w700,
                      color: value == '—' ? AppColors.textLow : color,
                      height: 1)),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(unit,
                    style: AppType.muted()),
              ],
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Color _percentGradeColor(double p) => Grade.percentLowerBetter(p).fill;

  Color _tempColor(int t) => Grade.temperature(t).fill;

  // ══════════════════════════════════════════════════════════════
  // Signal Hero — النجم! semi-circular gauge بلوّن حسب جودة الإشارة
  // ══════════════════════════════════════════════════════════════
  Widget _signalHero(UbntWireless w) {
    final signalColor = _signalColor(w.signal);
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            signalColor.withValues(alpha: 0.08),
            signalColor.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(R.icon),
        border:
            Border.all(color: signalColor.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(children: [
        // Gauge on the right — RepaintBoundary لعزل الـCustomPaint (rebuild
        // كل fetch كان يُعيد رسم الـpainter → jank بسيط لكن ملحوظ)
        SizedBox(
          width: 120,
          height: 90,
          child: RepaintBoundary(
              child: CustomPaint(
            painter: _SignalGaugePainter(
              percent: w.signalQualityPercent,
              color: signalColor,
              background: AppColors.border,
            ),
            child: Center(
              child:
                  Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('${w.signal}',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: signalColor,
                        height: 1)),
                const SizedBox(height: 2),
                Text('dBm',
                    style: AppType.microBold(color: AppColors.textMid)),
              ]),
            ),
          )),
        ),
        const SizedBox(width: 16),
        // Details on the left
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('جودة الإشارة',
                style: AppType.microBold(color: AppColors.textMid)),
            const SizedBox(height: 4),
            Text(_signalLabel(w.signal),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: signalColor,
                    height: 1.1)),
            const SizedBox(height: 10),
            _metric('SNR', w.snr != null ? '${w.snr}' : '—',
                w.snr != null ? 'dB' : '',
                color: w.snr != null ? _snrColor(w.snr!) : AppColors.textLow),
            const SizedBox(height: 4),
            _metric('Noise', w.hasNoise ? '${w.noise}' : '—',
                w.hasNoise ? 'dBm' : '',
                color: w.hasNoise ? AppColors.textMid : AppColors.textLow),
            const SizedBox(height: 4),
            _metric('CCQ', w.hasCcq ? '${w.ccq}' : '—', w.hasCcq ? '%' : '',
                color: w.hasCcq
                    ? _percentColor(w.ccq.toDouble())
                    : AppColors.textLow),
          ]),
        ),
      ]),
    );
  }

  Widget _metric(String label, String value, String unit,
      {required Color color}) {
    return Row(children: [
      SizedBox(
          width: 42,
          child: Text(label,
              style: TextStyle(fontSize: 10.5, height: 1.3, color: AppColors.textLow))),
      Text(value,
          style: AppType.bodyBold(color: color)),
      const SizedBox(width: 2),
      Text(unit, style: TextStyle(fontSize: 9.5, height: 1.2, color: AppColors.textLow)),
    ]);
  }

  // ══════════════════════════════════════════════════════════════
  // Wireless details section
  // ══════════════════════════════════════════════════════════════
  Widget _wirelessDetails(UbntWireless w) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
      child: Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          _detailRow(
              LucideIcons.wifi, 'ESSID', w.essid.isEmpty ? '—' : w.essid),
          _detailRow(LucideIcons.radioTower, 'الوضع', _modeLabel(w.mode)),
          Row(children: [
            Expanded(
              child: _detailRow(LucideIcons.arrowDown, 'RX', '${w.rxRate}',
                  suffix: 'Mbps', color: AppColors.success),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _detailRow(LucideIcons.arrowUp, 'TX', '${w.txRate}',
                  suffix: 'Mbps', color: AppColors.brandAccent),
            ),
          ]),
          _detailRow(LucideIcons.satellite, 'التردد',
              '${w.frequency} MHz${w.chanbw > 0 ? " (${w.chanbw}MHz)" : ""}${w.channel > 0 ? " • ch ${w.channel}" : ""}'),
          if (w.distance > 0)
            _detailRow(
                LucideIcons.mapPin,
                'المسافة',
                w.distance >= 1000
                    ? '${(w.distance / 1000).toStringAsFixed(1)}km'
                    : '${w.distance}m'),
        ]),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value,
      {String? suffix, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 12, color: color ?? AppColors.textLow),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 10.5, height: 1.3, color: AppColors.textMid)),
        const Spacer(),
        Text(value,
            style: AppType.pillBold(color: color ?? AppColors.textHi)),
        if (suffix != null) ...[
          const SizedBox(width: 3),
          Text(suffix,
              style: TextStyle(fontSize: 9.5, height: 1.2, color: AppColors.textLow)),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Interfaces section
  // ══════════════════════════════════════════════════════════════
Widget _interfaceRow(UbntInterface iface) {
    final rate = _rates[iface.ifname];
    final up = iface.plugged && iface.enabled;
    final color = up ? AppColors.success : AppColors.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(children: [
        Icon(up ? LucideIcons.arrowUp : LucideIcons.arrowDown,
            size: 12, color: color),
        const SizedBox(width: 6),
        Text(iface.ifname,
            style: TextStyle(
                fontSize: 11, height: 1.25,
                fontWeight: FontWeight.w600,
                color: AppColors.textHi)),
        if (iface.speed != null && up) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: _speedColor(iface.speed!).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(R.pill),
            ),
            child: Text(_speedLabel(iface.speed!),
                style: AppType.daysWordBold(color: _speedColor(iface.speed!))),
          ),
        ],
        const Spacer(),
        if (rate != null) ...[
          Icon(LucideIcons.arrowDown, size: 9, color: AppColors.success),
          const SizedBox(width: 2),
          Text(_formatBps(rate.rxBps),
              style: AppType.microBold(color: AppColors.textHi)),
          const SizedBox(width: 8),
          Icon(LucideIcons.arrowUp, size: 9, color: AppColors.brandAccent),
          const SizedBox(width: 2),
          Text(_formatBps(rate.txBps),
              style: AppType.microBold(color: AppColors.textHi)),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Stations section (لو AP mode)
  // ══════════════════════════════════════════════════════════════
Widget _stationRow(UbntStation s) {
    final signalColor = _signalColor(s.signal);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(children: [
        Container(
          width: 4,
          height: 30,
          decoration: BoxDecoration(
            color: signalColor,
            borderRadius: BorderRadius.circular(R.pill),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // كلّ قيمةٍ تُنسخ وحدها بالضغط المطوّل (أو الزرّ الأيمن على الحاسبة) — المالك ٢٤ أكتوبر.
            Copyable(
              label: s.hostname != null ? 'اسم الجهاز' : (s.ip != null ? 'IP' : 'الماك'),
              value: s.hostname ?? s.ip ?? s.mac,
              child: Text(s.hostname ?? s.ip ?? s.mac,
                  style: AppType.pillBold(color: AppColors.textHi),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            if ((s.ip ?? '').isNotEmpty || s.mac.isNotEmpty)
              Row(children: [
                if ((s.ip ?? '').isNotEmpty)
                  Copyable(
                    label: 'IP',
                    value: s.ip,
                    child: Text(s.ip!,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(fontSize: 9.5, height: 1.2, color: AppColors.textLow)),
                  ),
                if ((s.ip ?? '').isNotEmpty && s.mac.isNotEmpty)
                  Text(' • ', style: TextStyle(fontSize: 9.5, height: 1.2, color: AppColors.textLow)),
                if (s.mac.isNotEmpty)
                  Flexible(
                    child: Copyable(
                      label: 'الماك',
                      value: s.mac,
                      child: Text(s.mac,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(fontSize: 9.5, height: 1.2, color: AppColors.textLow),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
              ]),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${s.signalDisplay} dBm',
                textDirection: TextDirection.ltr,
                style: AppType.pillBold(color: signalColor)),
            if (s.ccq > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      _percentColor(s.ccq.toDouble()).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(R.pill),
                ),
                child: Text('${s.ccq}%',
                    textDirection: TextDirection.ltr,
                    style: AppType.pillBold(color: _percentColor(s.ccq.toDouble()))),
              ),
            ],
          ]),
          const SizedBox(height: 2),
          Text('↓${s.rxRate} / ↑${s.txRate} Mbps',
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 9.5, height: 1.2, color: AppColors.textMid)),
        ]),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Helpers
  // ══════════════════════════════════════════════════════════════
  Color _signalColor(int dbm) => Grade.signal(dbm).fill;

  String _signalLabel(int dbm) {
    if (dbm >= -60) return 'ممتازة';
    if (dbm >= -70) return 'جيّدة';
    if (dbm >= -80) return 'مقبولة';
    return 'ضعيفة';
  }

  Color _snrColor(int snr) => Grade.snr(snr).fill;

  Color _percentColor(double p) => Grade.percentHigherBetter(p).fill;

  Color _speedColor(int mbps) => Grade.speedMbps(mbps).fill;

  String _speedLabel(int mbps) {
    if (mbps >= 1000) return '${mbps ~/ 1000}G';
    return '${mbps}M';
  }

  String _modeLabel(String m) => switch (m) {
        'ap-ptp' => 'Access Point • PtP',
        'sta-ptp' => 'Station • PtP',
        'ap-ptmp' => 'Access Point • PtMP',
        'sta-ptmp' => 'Station • PtMP',
        _ => m.isEmpty ? '—' : m,
      };

  String _formatUptime(int seconds) {
    if (seconds <= 0) return '—';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    if (days > 7) {
      final weeks = days ~/ 7;
      return '${weeks}w ${days % 7}d';
    }
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  String _formatBps(int bps) {
    if (bps <= 0) return '0';
    if (bps < 1000) return '${bps}bps';
    if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(1)}K';
    if (bps < 1000000000) return '${(bps / 1000000).toStringAsFixed(1)}M';
    return '${(bps / 1000000000).toStringAsFixed(2)}G';
  }

  /// الواجهات التي يُقرأ منها الرسم و«أعلى تنزيل/رفع»: السلكيّة (eth/br/ppp) كالمايكروتك — اللاسلكيّة تحمل
  /// الحركة نفسها بالاتّجاه المعاكس، فخلطُها بها يرسم التنزيل خطّين (تنزيل eth0 = رفع ath0 إلى العملاء).
  /// بلا سلكيّةٍ لها سرعة: كلّ واجهات البيانات (airFiber بـbr0/wlan0 وحدها).
  List<UbntInterface> _headlinePool([List<UbntInterface>? from]) {
    final all = (from ?? _stats?.interfaces ?? const <UbntInterface>[]).where(_isDataIface).toList();
    final wired = [
      for (final i in all)
        if (!i.ifname.startsWith('wlan') && !i.ifname.startsWith('ath') && _rates.containsKey(i.ifname)) i,
    ];
    return wired.isNotEmpty ? wired : all;
  }

  /// 2026-08-18: أي واجهة تحمل بيانات فعليّة (تظهر بالـUI + traffic
  /// يُحسَب لها). كان الفلتر السابق `startsWith('eth')` يستثني br0/wlan0
  /// الي أحياناً تكون الواجهة الوحيدة على airFiber 60 GP → traffic ما يظهر.
  static bool _isDataIface(UbntInterface i) {
    final n = i.ifname;
    if (n.startsWith('eth')) return true;
    if (n.startsWith('br')) return true; // bridge (airFiber 60)
    if (n.startsWith('wlan') || n.startsWith('ath')) return true; // wireless
    if (n == 'ppp0' || n == 'wan') return true;
    return false;
  }
}

// ══════════════════════════════════════════════════════════════
// Signal Gauge Painter — semi-circular arc مع لون متدرّج
// ══════════════════════════════════════════════════════════════
class _SignalGaugePainter extends CustomPainter {
  final double percent; // 0..100
  final Color color;
  final Color background;
  _SignalGaugePainter(
      {required this.percent, required this.color, required this.background});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.88);
    final radius = math.min(size.width / 2 - 6, size.height * 0.85);
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    // background arc
    final bgPaint = Paint()
      ..color = background.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // foreground arc based on percent
    final fgPaint = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: [color.withValues(alpha: 0.4), color],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final sweep = (percent / 100).clamp(0.0, 1.0) * sweepAngle;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep,
      false,
      fgPaint,
    );

    // scale ticks
    final tickPaint = Paint()
      ..color = background.withValues(alpha: 0.8)
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final angle = startAngle + (sweepAngle * i / 4);
      final outer = Offset(
        center.dx + math.cos(angle) * (radius + 4),
        center.dy + math.sin(angle) * (radius + 4),
      );
      final inner = Offset(
        center.dx + math.cos(angle) * (radius - 4),
        center.dy + math.sin(angle) * (radius - 4),
      );
      canvas.drawLine(outer, inner, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignalGaugePainter old) =>
      old.percent != percent || old.color != color;
}

class _BytesPoint {
  final int rxBytes;
  final int txBytes;
  const _BytesPoint({required this.rxBytes, required this.txBytes});
}

class _IfaceRate {
  final int rxBps;
  final int txBps;
  const _IfaceRate({required this.rxBps, required this.txBps});
}

/// عيّنة traffic لحظة واحدة — أعلى interface بها. 2026-08-18.
class _TrafficSample {
  final DateTime at;
  final int rxBps;
  final int txBps;
  const _TrafficSample(
      {required this.at, required this.rxBps, required this.txBps});
}

/// كارت traffic graph مستقلّ — StatefulWidget مع KeepAlive لضمان أن
/// الـchart ينجو من parent rebuilds ولا يختفي/يتومض على كل refresh.
/// يستقبل history + cardWrapper من الـparent كـcallbacks.
/// 2026-08-18.
class _TrafficGraphCard extends StatefulWidget {
  final List<_TrafficSample> history;
  final Widget Function({required Widget child}) cardWrapper;

  const _TrafficGraphCard({
    super.key,
    required this.history,
    required this.cardWrapper,
  });

  @override
  State<_TrafficGraphCard> createState() => _TrafficGraphCardState();
}

class _TrafficGraphCardState extends State<_TrafficGraphCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // ينجو من ListView/Column rebuilds

  @override
  Widget build(BuildContext context) {
    super.build(context); // مطلوب لـAutomaticKeepAlive
    final history = widget.history;
    final rxSpots = <FlSpot>[];
    final txSpots = <FlSpot>[];
    for (int i = 0; i < history.length; i++) {
      final x = i.toDouble();
      rxSpots.add(FlSpot(x, history[i].rxBps.toDouble()));
      txSpots.add(FlSpot(x, history[i].txBps.toDouble()));
    }
    final maxRx = history.map((s) => s.rxBps).fold<int>(0, math.max);
    final maxTx = history.map((s) => s.txBps).fold<int>(0, math.max);
    final peak = math.max(maxRx, maxTx);
    final maxY = (peak * 1.25).clamp(1000, double.infinity).toDouble();

    final lastRx = history.isNotEmpty ? history.last.rxBps : 0;
    final lastTx = history.isNotEmpty ? history.last.txBps : 0;

    final rxColor = AppColors.success;
    final txColor = AppColors.brandAccent;

    return widget.cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.chartLine, size: 14, color: AppColors.brandAccent),
          const SizedBox(width: 6),
          // ⚠️ مرنٌ لأنّ الصفّ بلا مرنٍ يفيض ولا يُقصّ: النصّ غير المرن
          // يُقاس بلا حدٍّ أعلى، فـ`maxLines` و`ellipsis` عليه لا تعملان
          // أبداً — يأخذ مقاسه كاملاً ويدفع الصفّ إلى الخطوط الصفراء.
          Flexible(
            child: Text('أعلى interface (سير الترفك)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.pillBold(color: AppColors.textHi)),
          ),
          const Spacer(),
          _legendChip('↓', _formatBps(lastRx), rxColor),
          const SizedBox(width: 6),
          _legendChip('↑', _formatBps(lastTx), txColor),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: RepaintBoundary(
              child: LineChart(
            duration: Duration.zero, // لا animation → لا وميض
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: AppColors.borderSoft,
                  strokeWidth: 0.5,
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: maxY / 3,
                    getTitlesWidget: (value, _) => Text(
                      _formatBpsShort(value.toInt()),
                      style: TextStyle(fontSize: 9.5, height: 1.2, color: AppColors.textLow),
                    ),
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minY: 0,
              maxY: maxY,
              minX: 0,
              maxX: (history.length - 1).toDouble(),
              lineBarsData: [
                _lineBarData(txSpots, txColor),
                _lineBarData(rxSpots, rxColor),
              ],
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) =>
                      AppColors.textHi.withValues(alpha: 0.9),
                  getTooltipItems: (spots) => spots.map((s) {
                    final isTx = s.barIndex == 0;
                    return LineTooltipItem(
                      '${isTx ? "↑" : "↓"} ${_formatBps(s.y.toInt())}',
                      AppType.microBold(color: isTx ? txColor : rxColor),
                    );
                  }).toList(),
                ),
              ),
            ),
          )),
        ),
      ]),
    );
  }

  LineChartBarData _lineBarData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.28,
      color: color,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.25),
            color.withValues(alpha: 0.02),
          ],
        ),
      ),
    );
  }

  Widget _legendChip(String arrow, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Text('$arrow $value',
          style: AppType.microBold(color: color)),
    );
  }

  String _formatBps(int bps) {
    if (bps <= 0) return '0';
    if (bps < 1000) return '${bps}bps';
    if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(1)}K';
    if (bps < 1000000000) return '${(bps / 1000000).toStringAsFixed(1)}M';
    return '${(bps / 1000000000).toStringAsFixed(2)}G';
  }

  String _formatBpsShort(int bps) {
    // دون العشرة بمنزلةٍ عشريّة («2.5M»، «1.2M») وما فوقها مقرَّب («48M») — كان 2.5M يُكتب «3M» و1.2M «1M».
    String t(double v) {
      if (v >= 10) return '${v.round()}';
      final s = v.toStringAsFixed(1);
      return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    }
    if (bps <= 0) return '0';
    if (bps < 1000) return '$bps';
    if (bps < 1000000) return '${t(bps / 1000)}K';
    if (bps < 1000000000) return '${t(bps / 1000000)}M';
    return '${t(bps / 1000000000)}G';
  }
}
