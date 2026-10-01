import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/cisco_api.dart';
import '../../../api/network_devices_api.dart';
import '../../../core/util/error_text.dart';
import '../../../models/network_device.dart';
import '../../../services/permissions_service.dart';
import '../../../services/device_stats_cache.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../detected_model.dart';
import '_grade.dart';
import 'device_image.dart';
import 'expandable_section.dart';

/// لوحة مراقبة حيّة لسويتشات Cisco — قراءة فقط عبر SSH أو Telnet.
///
/// **بنيتها مطابقة للوحة Mikrotik** عمداً: البطاقة الرئيسة (رأس +
/// شريط اللوحة + كروت المقاييس + منحنى الترفك) ثمّ أقسامٌ قابلة
/// للطيّ. المستخدم ينتقل بين جهازٍ وآخر في الشاشة نفسها، فاختلاف
/// اللغة البصريّة بين براندٍ وآخر يُقرأ عطلاً لا تنوّعاً.
///
/// وما يخصّ سسكو وحده (خريطة المنافذ، البحث، VLAN، عدّادات الأخطاء)
/// موضوعٌ داخل القوالب نفسها لا بجانبها.
class CiscoLivePanel extends StatefulWidget {
  const CiscoLivePanel({super.key, required this.device});
  final NetworkDevice device;

  @override
  State<CiscoLivePanel> createState() => _CiscoLivePanelState();
}

class _CiscoLivePanelState extends State<CiscoLivePanel>
    with WidgetsBindingObserver {
  CiscoStats? _stats;
  DateTime? _lastFetch;
  String? _error;
  Timer? _timer;
  bool _loading = false;
  bool _monitoring = true;
  bool _foreground = true;
  bool _connectedOnly = false;
  String _query = '';
  int _generation = 0;

  final Map<String, ({int? rx, int? tx, DateTime at})> _counters = {};
  final Map<String, _IfaceRate> _rates = {};
  final List<_TrafficSample> _history = [];

  /// جلسة SSH/Telnet أثقل من نداء API — نبضةٌ أسرع من زمن الجلسة
  /// تُنتج طابوراً لا تحديثاً. (مايكروتك ثمانٍ لأنّ جلسته بأجزاء ثانية.)
  static const _refreshInterval = Duration(seconds: 15);
  static const _maxHistory = 30;

  @override
  void initState() {
    super.initState();
    // ── بذرةٌ من المخزن ────────────────────────────────────────────
    //
    // ⚡ بلا بذرٍ تُدفَع جلسةٌ كاملة في **كلّ** فتحةٍ للجهاز ولو أُغلق
    // قبل ثوانٍ، فيرى المدير دوّارةً على بياناتٍ كانت بين يديه.
    //
    // (طلب المستخدم ٢٠٢٦-١٠-٠١: «أهمّ شي عندي سرعة الاستجابة وعرض
    // البيانات وتحديثها… وهلشي بجميع الأجهزة»)
    _stats = DeviceStatsCache.instance.seedFor<CiscoStats>(widget.device.id);
    // وعمرُها معها: رقمٌ قديمٌ تحت شارة «مباشر» كذبة.
    final seedAge = DeviceStatsCache.instance.ageOf(widget.device.id);
    if (_stats != null && seedAge != null) {
      _lastFetch = DateTime.now().subtract(seedAge);
    }
    WidgetsBinding.instance.addObserver(this);
    _schedule();
    unawaited(_fetch());
  }

  @override
  void didUpdateWidget(CiscoLivePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id ||
        oldWidget.device.ip != widget.device.ip ||
        oldWidget.device.protocol != widget.device.protocol ||
        oldWidget.device.apiPort != widget.device.apiPort ||
        oldWidget.device.hasCredentials != widget.device.hasCredentials) {
      _generation++;
      _stats = null;
      _lastFetch = null;
      _loading = false;
      _error = null;
      _counters.clear();
      _rates.clear();
      _history.clear();
      unawaited(_fetch());
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _timer?.cancel();
    if (_foreground && _monitoring) {
      _schedule();
      unawaited(_fetch());
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_monitoring && _foreground) {
      _timer = Timer.periodic(_refreshInterval, (_) => _fetch());
    }
  }

  void _toggleMonitoring() {
    setState(() => _monitoring = !_monitoring);
    _schedule();
    if (_monitoring) unawaited(_fetch());
  }

  Future<void> _fetch({bool manual = false}) async {
    if (!mounted || _loading || !_foreground || (!_monitoring && !manual)) {
      return;
    }
    final generation = _generation;
    final device = widget.device;
    setState(() => _loading = true);
    try {
      final creds = await NetworkDevicesApi.getCredentials(device.id);
      if (!mounted || generation != _generation) return;
      final user = (creds['user'] ?? '').toString();
      final pass = (creds['pass'] ?? '').toString();
      if (user.isEmpty) {
        throw CiscoException('أدخل اسم مستخدم السويتش من إعدادات الجهاز.');
      }
      final stats = await CiscoApi.fetchStats(
        host: device.ip,
        user: user,
        pass: pass,
        protocol: device.protocol ?? 'ssh',
        port: device.apiPort ?? device.port,
        onPartialReady: (partial) {
          if (!mounted || generation != _generation || !_foreground) return;
          if (_stats == null) setState(() => _stats = partial);
        },
      );
      if (!mounted || generation != _generation) return;

      final now = DateTime.now();
      _computeRates(stats, now);
      setState(() {
        _stats = stats;
        DeviceStatsCache.instance.putRaw(widget.device.id, stats);
        _lastFetch = now;
        _error = null;
      });
      if (Perms.has('devices.manage')) {
        unawaited(DetectedModel.save(device, stats.model));
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(
            () => _error = e is CiscoException ? e.message : humanError(e));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  /// معدّلات المنافذ من فروق العدّادات، وإجماليّها للمنحنى.
  void _computeRates(CiscoStats stats, DateTime now) {
    // إعادة إقلاعٍ تُصفّر العدّادات — ومقارنةُ ما بعدها بما قبلها تعطي
    // قفزةً وهميّة. نُسقط الجولة كلّها بدل أن نرسم ذروةً لم تحدث.
    final rebooted = _stats?.uptime != null &&
        stats.uptime != null &&
        stats.uptime! < _stats!.uptime!;

    _rates.clear();
    for (final port in stats.ifaces) {
      final prev = _counters[port.name];
      int? delta(int? current, int? old) {
        if (rebooted || prev == null || current == null || old == null) {
          return null;
        }
        if (current < old) return null;
        final seconds = now.difference(prev.at).inMilliseconds / 1000;
        return seconds > 0 ? ((current - old) * 8 / seconds).round() : null;
      }

      _rates[port.name] = _IfaceRate(
        rxBps: delta(port.rxBytes, prev?.rx),
        txBps: delta(port.txBytes, prev?.tx),
      );
      _counters[port.name] = (rx: port.rxBytes, tx: port.txBytes, at: now);
    }
    _counters.removeWhere((name, _) => !stats.ifaces.any((p) => p.name == name));

    var totalRx = 0, totalTx = 0;
    for (final p in stats.physicalPorts) {
      totalRx += _rxOf(p) ?? 0;
      totalTx += _txOf(p) ?? 0;
    }
    _history.add(_TrafficSample(at: now, rxBps: totalRx, txBps: totalTx));
    if (_history.length > _maxHistory) _history.removeAt(0);
  }

  /// المعدّل المحسوب من الفروق، وإلّا معدّل الخمس دقائق من الجهاز —
  /// وهو ما يجعل أوّل لقطة تعرض أرقاماً بدل شرطات.
  int? _rxOf(CiscoInterface p) => _rates[p.name]?.rxBps ?? p.rxBps;
  int? _txOf(CiscoInterface p) => _rates[p.name]?.txBps ?? p.txBps;

  // ══════════════════════════════════════════════════════════════
  // Build
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    if (stats == null && _error == null) {
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
          Text('جاري الاتصال بـCisco…',
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
          if (stats != null) ...[
            RepaintBoundary(child: _boardBanner(stats)),
            RepaintBoundary(child: _metricsRow(stats)),
            if (_history.length >= 2) ...[
              const SizedBox(height: 4),
              _trafficGraph(),
            ],
            const SizedBox(height: Sp.md),
          ],
        ]),
      ),
      if (stats != null) ..._buildExpandables(stats),
    ]);
  }

  // ── الرأس ──

  Widget _header() {
    final proto = widget.device.protocol == 'telnet' ? 'Telnet' : 'SSH';
    return Padding(
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مراقبة حيّة (Cisco $proto)', style: AppType.bodyBold()),
            const SizedBox(height: 2),
            Row(children: [
              if (_monitoring) ...[
                _pulseDot(),
                const SizedBox(width: 4),
              ],
              Text(
                _monitoring
                    ? 'مباشر · كل ${_refreshInterval.inSeconds}s'
                    : 'متوقّف',
                style: TextStyle(
                    fontSize: 10.5, height: 1.3, color: AppColors.textMid),
              ),
              if (_lastFetch != null) ...[
                Text(' • ',
                    style: TextStyle(
                        fontSize: 10.5, height: 1.3, color: AppColors.textLow)),
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
          onPressed: _loading ? null : () => _fetch(manual: true),
          tooltip: 'تحديث الآن',
          color: AppColors.brand,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          icon: Icon(
            _monitoring ? LucideIcons.pause : LucideIcons.play,
            size: 16,
            color: _monitoring ? AppColors.error : AppColors.success,
          ),
          onPressed: _toggleMonitoring,
          tooltip: _monitoring ? 'إيقاف' : 'استئناف',
          visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }

  Widget _pulseDot() => Container(
        width: 6,
        height: 6,
        decoration:
            BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
      );

  Widget _errorBox() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Sp.md),
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_stats != null)
              Text('البيانات من آخر جولة ناجحة',
                  style: AppType.microBold(color: AppColors.error)),
            Text(_error!,
                style: TextStyle(
                    fontSize: 11, color: AppColors.error, height: 1.4)),
          ]),
        ),
      ]),
    );
  }

  // ── شريط اللوحة: الصورة + الموديل + IOS + مدّة التشغيل ──

  Widget _boardBanner(CiscoStats s) {
    final model = s.model ?? widget.device.model;
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brandSoftBg,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(children: [
        DeviceImage(brand: 'cisco', model: model, size: 28),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              s.hostname?.isNotEmpty == true ? s.hostname! : widget.device.name,
              style: TextStyle(
                  fontSize: 11,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textHi),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              [
                if (model != null && model.isNotEmpty) model,
                if (s.iosVersion != null) 'IOS ${s.iosVersion}',
              ].join(' • '),
              style: AppType.micro(color: AppColors.textMid),
              overflow: TextOverflow.ellipsis,
            ),
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
              Text(_formatUptime(s.uptime!),
                  style: AppType.microBold(color: AppColors.brand)),
            ]),
          ),
      ]),
    );
  }

  // ── كروت المقاييس: صفّان × ثلاثة (نفس شبكة مايكروتك) ──

  Widget _metricsRow(CiscoStats s) {
    final top = _topPorts();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
      child: Column(children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  child: _percentCard(
                icon: LucideIcons.cpu,
                label: 'CPU',
                percent: s.cpuPercent,
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _percentCard(
                icon: LucideIcons.memoryStick,
                label: 'RAM',
                percent: s.memPercent,
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _valueCard(
                icon: LucideIcons.ethernetPort,
                label: 'منافذ',
                value: '${s.portsUp}',
                unit: '/${s.portsTotal}',
                color: s.portsUp > 0 ? AppColors.success : AppColors.textLow,
              )),
            ],
          ),
        ),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  child: _valueCard(
                icon: LucideIcons.clock,
                label: 'تشغيل',
                value: s.uptime == null ? '—' : _formatUptime(s.uptime!),
                unit: '',
                color: AppColors.brand,
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _topRateCard(
                label: 'أعلى منفذ ↓',
                port: top.rx,
                color: AppColors.success,
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _topRateCard(
                label: 'أعلى منفذ ↑',
                port: top.tx,
                color: AppColors.brandAccent,
              )),
            ],
          ),
        ),
      ]),
    );
  }

  ({({String name, int bps})? rx, ({String name, int bps})? tx}) _topPorts() {
    ({String name, int bps})? bestRx, bestTx;
    for (final p in _stats?.physicalPorts ?? const <CiscoInterface>[]) {
      final name = p.shortName ?? p.name;
      final rx = _rxOf(p) ?? 0;
      final tx = _txOf(p) ?? 0;
      if (bestRx == null || rx > bestRx.bps) bestRx = (name: name, bps: rx);
      if (bestTx == null || tx > bestTx.bps) bestTx = (name: name, bps: tx);
    }
    return (rx: bestRx, tx: bestTx);
  }

  Widget _valueCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
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
            Text(label, style: AppType.microBold(color: AppColors.textMid)),
          ]),
          Row(
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
                        color: value == '—' ? AppColors.textLow : color,
                        height: 1)),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(unit, style: AppType.muted()),
              ],
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// نسبةٌ قد تكون غير متاحة — و«غير متاح» ليست صفراً: شريطٌ فارغ عند
  /// `null` يوحي بمعالجٍ خاملٍ بينما الجهاز لم يُعطِ الرقم أصلاً.
  Widget _percentCard({
    required IconData icon,
    required String label,
    required double? percent,
  }) {
    final has = percent != null;
    final color = has ? Grade.percentLowerBetter(percent).fill : AppColors.textLow;
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
          Text(label, style: AppType.microBold(color: AppColors.textMid)),
        ]),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(has ? '${percent.round()}' : '—',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: has ? AppColors.textHi : AppColors.textLow,
                    height: 1)),
            if (has) ...[
              const SizedBox(width: 2),
              Text('%',
                  style: TextStyle(
                      fontSize: 10.5, height: 1.3, color: AppColors.textLow)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(R.pill),
          child: LinearProgressIndicator(
            value: has ? (percent / 100).clamp(0.0, 1.0) : 0,
            minHeight: 4,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ]),
    );
  }

  Widget _topRateCard({
    required String label,
    required ({String name, int bps})? port,
    required Color color,
  }) {
    final hasData = port != null && port.bps > 0;
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
            Icon(
              label.contains('↓') ? LucideIcons.arrowDown : LucideIcons.arrowUp,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(label.replaceAll(RegExp(r'[↓↑]'), '').trim(),
                style: AppType.microBold(color: AppColors.textMid)),
          ]),
          if (hasData)
            Text(port.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.bodyBold()),
          Text(hasData ? _formatBps(port.bps) : '—',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: hasData ? color : AppColors.textLow,
                  height: 1)),
        ],
      ),
    );
  }

  // ── منحنى الترفك ──

  Widget _trafficGraph() {
    final rxSpots = <FlSpot>[];
    final txSpots = <FlSpot>[];
    for (var i = 0; i < _history.length; i++) {
      rxSpots.add(FlSpot(i.toDouble(), _history[i].rxBps.toDouble()));
      txSpots.add(FlSpot(i.toDouble(), _history[i].txBps.toDouble()));
    }
    final peak = math.max(
      _history.map((s) => s.rxBps).fold<int>(0, math.max),
      _history.map((s) => s.txBps).fold<int>(0, math.max),
    );
    final maxY = (peak * 1.25).clamp(1000, double.infinity).toDouble();
    final lastRx = _history.last.rxBps;
    final lastTx = _history.last.txBps;
    final rxColor = AppColors.success;
    final txColor = AppColors.brandAccent;

    return Container(
      margin: const EdgeInsets.all(Sp.md),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.chartLine, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          // مرنٌ لأنّ النصّ غير المرن يُقاس بلا حدٍّ أعلى فيفيض الصفّ.
          Flexible(
            child: Text('إجمالي المنافذ (سير الترفك)',
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
                      getTitlesWidget: (value, _) => Text(
                        _formatBpsShort(value.toInt()),
                        style: TextStyle(
                            fontSize: 9.5,
                            height: 1.2,
                            color: AppColors.textLow),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minY: 0,
                maxY: maxY,
                minX: 0,
                maxX: (_history.length - 1).toDouble(),
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
            ),
          ),
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
      child: Text('$arrow $value', style: AppType.microBold(color: color)),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // الأقسام القابلة للطيّ
  // ══════════════════════════════════════════════════════════════

  List<Widget> _buildExpandables(CiscoStats s) {
    final all = s.physicalPorts;
    final shown = all.where(_matchesFilter).toList();
    return [
      if (all.isNotEmpty) ...[
        const SizedBox(height: Sp.md),
        ExpandableSection(
          key: PageStorageKey('cisco-${widget.device.id}-map'),
          initiallyExpanded: true,
          header: Row(children: [
            Icon(LucideIcons.layoutGrid, size: 14, color: AppColors.brand),
            const SizedBox(width: 6),
            Text('خريطة المنافذ (${s.portsUp}/${all.length})',
                style: AppType.bodyBold()),
          ]),
          content: RepaintBoundary(child: _portMap(all)),
        ),
      ],
      const SizedBox(height: Sp.md),
      ExpandableSection(
        key: PageStorageKey('cisco-${widget.device.id}-ports'),
        initiallyExpanded: true,
        header: Row(children: [
          Icon(LucideIcons.network, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('تفاصيل المنافذ (${shown.length})', style: AppType.bodyBold()),
        ]),
        content: RepaintBoundary(child: _portsContent(all, shown)),
      ),
    ];
  }

  bool _matchesFilter(CiscoInterface p) {
    if (_connectedOnly && !p.up) return false;
    if (_query.trim().isEmpty) return true;
    final hay =
        '${p.name} ${p.shortName ?? ''} ${p.description ?? ''} ${p.vlan ?? ''}'
            .toLowerCase();
    return hay.contains(_query.trim().toLowerCase());
  }

  /// صفّ المنافذ كما تراه العين على اللوحة — مربّعٌ لكلّ منفذ بلونه.
  Widget _portMap(List<CiscoInterface> ports) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in ports)
          Tooltip(
            message: '${p.shortName ?? p.name} • ${_statusLabel(p)}'
                '${p.vlan != null ? ' • VLAN ${p.vlan}' : ''}',
            child: Container(
              width: 34,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _portColor(p).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(
                    color: p.up ? _portColor(p) : AppColors.borderSoft),
              ),
              child: Text(_portNumber(p),
                  textDirection: TextDirection.ltr,
                  style: AppType.microBold(color: _portColor(p))),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _mapLegend(AppColors.success, 'متّصل'),
        const SizedBox(width: 10),
        _mapLegend(AppColors.textLow, 'غير متّصل'),
        const SizedBox(width: 10),
        _mapLegend(AppColors.error, 'موقوف بخطأ'),
      ]),
    ]);
  }

  Widget _mapLegend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: color),
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: AppType.micro(color: AppColors.textLow)),
        ],
      );

  Widget _portsContent(List<CiscoInterface> all, List<CiscoInterface> shown) {
    var maxRate = 0;
    for (final p in shown) {
      maxRate = math.max(maxRate, (_rxOf(p) ?? 0) + (_txOf(p) ?? 0));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: SizedBox(
            height: 36,
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: AppType.body(),
              decoration: InputDecoration(
                hintText: 'ابحث بالمنفذ أو VLAN',
                hintStyle: AppType.micro(color: AppColors.textLow),
                prefixIcon:
                    Icon(LucideIcons.search, size: 14, color: AppColors.textLow),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                filled: true,
                fillColor: AppColors.surfaceSunken,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _filterChip(),
      ]),
      const SizedBox(height: 10),
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.all(Sp.md),
          child: Text(
            all.isEmpty
                ? 'لم تتوفّر بيانات المنافذ من الجهاز'
                : 'لا منافذ تطابق البحث',
            textAlign: TextAlign.center,
            style: AppType.body(color: AppColors.textLow),
          ),
        )
      else
        for (final p in shown) _portRow(p, maxRate),
    ]);
  }

  Widget _filterChip() {
    final on = _connectedOnly;
    return InkWell(
      onTap: () => setState(() => _connectedOnly = !on),
      borderRadius: BorderRadius.circular(R.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: on ? AppColors.successSoftBg : AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(R.sm),
          border:
              Border.all(color: on ? AppColors.success : AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(on ? LucideIcons.check : LucideIcons.filter,
              size: 12, color: on ? AppColors.success : AppColors.textMid),
          const SizedBox(width: 4),
          Text('المتّصلة',
              style: AppType.microBold(
                  color: on ? AppColors.success : AppColors.textMid)),
        ]),
      ),
    );
  }

  /// صفّ المنفذ — نفس هيكل صفّ مايكروتك: أيقونة حالة، اسم، شارة سرعة،
  /// معدّلان، ثمّ شريطٌ نسبيّ. وما يخصّ سسكو (VLAN، الوصف، الأخطاء)
  /// يسكن السطر الثاني بدل أن يفتح تخطيطاً آخر.
  Widget _portRow(CiscoInterface p, int maxRate) {
    final color = _portColor(p);
    final rx = _rxOf(p);
    final tx = _txOf(p);
    final statusIcon = !p.adminUp
        ? LucideIcons.circleOff
        : p.up
            ? LucideIcons.arrowUp
            : LucideIcons.arrowDown;
    final errors = (p.inErrors ?? 0) + (p.outErrors ?? 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Column(children: [
        Row(children: [
          Icon(statusIcon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            p.shortName ?? p.name,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 11,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: p.up ? AppColors.textHi : AppColors.textLow,
            ),
          ),
          if (p.speedMbps != null && p.up) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Grade.speedMbps(p.speedMbps)
                    .fill
                    .withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(R.pill),
              ),
              child: Text(
                _shortSpeed(p.speedMbps!),
                style: AppType.daysWordBold(
                    color: Grade.speedMbps(p.speedMbps).fill),
              ),
            ),
          ],
          const Spacer(),
          if (rx != null || tx != null) ...[
            Icon(LucideIcons.arrowDown, size: 9, color: AppColors.success),
            const SizedBox(width: 2),
            Text(_formatBps(rx ?? 0),
                style: AppType.microBold(color: AppColors.textHi)),
            const SizedBox(width: 8),
            Icon(LucideIcons.arrowUp, size: 9, color: AppColors.brandAccent),
            const SizedBox(width: 2),
            Text(_formatBps(tx ?? 0),
                style: AppType.microBold(color: AppColors.textHi)),
          ] else
            Text('—',
                style: TextStyle(
                    fontSize: 10.5, height: 1.3, color: AppColors.textLow)),
        ]),
        const SizedBox(height: 3),
        Row(children: [
          Text(_statusLabel(p), style: AppType.micro(color: color)),
          if (p.vlan != null) ...[
            Text(' • ', style: AppType.micro(color: AppColors.textLow)),
            Text('VLAN ${p.vlan}',
                style: AppType.micro(color: AppColors.textMid)),
          ],
          if (p.fullDuplex != null) ...[
            Text(' • ', style: AppType.micro(color: AppColors.textLow)),
            Text(p.fullDuplex! ? 'Full' : 'Half',
                style: AppType.micro(color: AppColors.textMid)),
          ],
          const Spacer(),
          if (errors > 0) ...[
            Icon(LucideIcons.triangleAlert, size: 9, color: AppColors.warning),
            const SizedBox(width: 3),
            Text('$errors',
                style: AppType.microBold(color: AppColors.warning)),
          ],
        ]),
        if (p.description?.isNotEmpty ?? false)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(p.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.micro(color: AppColors.textMid)),
          ),
        if (maxRate > 0 && ((rx ?? 0) + (tx ?? 0)) > 0) ...[
          const SizedBox(height: 4),
          _miniBar(((rx ?? 0) + (tx ?? 0)) / maxRate, color),
        ],
      ]),
    );
  }

  Widget _miniBar(double ratio, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(R.pill),
      child: LinearProgressIndicator(
        value: ratio.clamp(0.0, 1.0),
        minHeight: 2,
        backgroundColor: AppColors.borderSoft,
        valueColor: AlwaysStoppedAnimation(color.withValues(alpha: 0.6)),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Helpers
  // ══════════════════════════════════════════════════════════════

  Color _portColor(CiscoInterface p) {
    if (p.status == 'err-disabled') return AppColors.error;
    if (!p.adminUp) return AppColors.textLow;
    return p.up ? AppColors.success : AppColors.textLow;
  }

  static String _statusLabel(CiscoInterface p) => p.up
      ? 'متّصل'
      : !p.adminUp
          ? 'معطّل إداريّاً'
          : p.status == 'err-disabled'
              ? 'موقوف بخطأ'
              : 'غير متّصل';

  /// `Fa0/12` → `12`، و`Gi0/1` → `G1` — رقمُ المربّع في خريطة اللوحة.
  static String _portNumber(CiscoInterface p) {
    final short = p.shortName ?? p.name;
    final number = short.split('/').last;
    return short.startsWith('Gi') || short.startsWith('Te')
        ? 'G$number'
        : number;
  }

  static String _shortSpeed(int mbps) =>
      mbps >= 1000 ? '${mbps ~/ 1000}G' : '${mbps}M';

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  static String _formatUptime(Duration d) {
    final days = d.inDays;
    final hours = d.inHours % 24;
    final mins = d.inMinutes % 60;
    if (days >= 7) return '${days ~/ 7}w ${days % 7}d';
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  static String _formatBps(int bps) {
    if (bps <= 0) return '0';
    if (bps < 1000) return '${bps}bps';
    if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(1)}K';
    if (bps < 1000000000) return '${(bps / 1000000).toStringAsFixed(1)}M';
    return '${(bps / 1000000000).toStringAsFixed(2)}G';
  }

  static String _formatBpsShort(int bps) {
    if (bps < 1000) return '0';
    if (bps < 1000000) return '${(bps / 1000).round()}K';
    if (bps < 1000000000) return '${(bps / 1000000).round()}M';
    return '${(bps / 1000000000).toStringAsFixed(1)}G';
  }
}

class _IfaceRate {
  final int? rxBps;
  final int? txBps;
  const _IfaceRate({this.rxBps, this.txBps});
}

class _TrafficSample {
  final DateTime at;
  final int rxBps;
  final int txBps;
  const _TrafficSample(
      {required this.at, required this.rxBps, required this.txBps});
}
