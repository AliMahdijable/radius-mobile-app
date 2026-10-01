import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/ruijie_api.dart';
import '../../../api/network_devices_api.dart';
import '../../../models/network_device.dart';
import '../../../services/device_stats_cache.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import 'expandable_section.dart';
import '_grade.dart';
import '../../../theme/typography.dart';
import '../../../core/util/error_text.dart';

/// لوحة مراقبة حيّة لأجهزة Ruijie / Reyee (SNMP v2c فقط).
///
/// MVP: header + CPU/RAM/uptime + قائمة interfaces مع Rx/Tx rates.
/// المتبقّي: temperature، wireless clients، AP count، reboot (Phase 2).
class RuijieLivePanel extends StatefulWidget {
  final NetworkDevice device;
  const RuijieLivePanel({super.key, required this.device});

  @override
  State<RuijieLivePanel> createState() => _RuijieLivePanelState();
}

class _RuijieLivePanelState extends State<RuijieLivePanel> {
  RuijieStats? _stats;
  bool _loading = false;
  String? _error;
  Timer? _timer;
  bool _monitoring = false;
  DateTime? _lastFetch;

  /// آخر عمرِ ارتباطٍ رأيناه، ومتى رأيناه أوّل مرّة.
  ///
  /// ⚠️ فيرموير airMetro يُحدّث جدوله اللاسلكيّ على فتراتٍ متباعدة —
  /// رصدتُه ثابتاً عشر دقائق كاملة بينما `sysUpTime` يتقدّم لحظيّاً.
  /// فلو عرضنا «الإشارة −43 · مباشر» لكذبنا على المشغّل وهو يقرّر
  /// بناءً عليها. نتتبّع التكرار لنقول عمر القياس صراحةً.
  int? _lastActive;
  DateTime? _lastActiveSeenAt;

  /// سلسلة الترفك الكلّيّ للرسم. تُبنى من فروق العدّادات لأنّ IF-MIB
  /// لا يعطي معدّلاً — ولذلك تحتاج قراءتين قبل أن يظهر المنحنى.
  final List<_TrafficPoint> _traffic = [];
  static const _maxTraffic = 30;

  /// اسم المنفذ الذي يرسمه المنحنى — يُعرَض في العنوان حتّى لا يُقرأ
  /// الرسم على أنّه «كلّ شيء».
  String? _uplinkName;

  /// هل عُرف المنفذ بالاسم (‏WAN) أم اختير لأنّه الأثقل؟
  ///
  /// الفرق ليس تفصيلاً: على منفذ صعودٍ حقيقيّ «الوارد» تنزيلٌ من
  /// الإنترنت. وعلى منفذ سويتش لا اتّجاه إنترنت أصلاً — ما يدخل من
  /// منفذٍ يخرج من جاره، فتسميته «تنزيلاً» تُضلّل المشغّل.
  bool _uplinkIsWan = false;

  /// آخر bytes لكل interface — لحساب rate delta
  final Map<int, _BytesPoint> _lastBytes = {};
  final Map<int, _IfaceRate> _rates = {};

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
    // ⚡ بلا بذرٍ تُدفَع جلسةٌ كاملة في **كلّ** فتحةٍ للجهاز ولو أُغلق
    // قبل ثوانٍ، فيرى المدير دوّارةً على بياناتٍ كانت بين يديه.
    //
    // (طلب المستخدم ٢٠٢٦-١٠-٠١: «أهمّ شي عندي سرعة الاستجابة وعرض
    // البيانات وتحديثها… وهلشي بجميع الأجهزة»)
    _stats = DeviceStatsCache.instance.seedFor<RuijieStats>(widget.device.id);
    // وعمرُها معها: رقمٌ قديمٌ تحت شارة «مباشر» كذبة.
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final creds = await NetworkDevicesApi.getCredentials(widget.device.id);
      // نفس نمط Mimosa: community يُحفَظ في creds['community']، مع fallback
      // على 'pass' للتوافق مع أي form قديم.
      final community =
          (creds['community'] ?? creds['pass'] ?? '').toString().trim();
      if (kDebugMode) {
        debugPrint('🔵 Ruijie creds len=${community.length} '
            'port=${widget.device.apiPort ?? 161}');
      }
      if (community.isEmpty) {
        throw RuijieException(
          'لم يتم إعداد SNMP community.\n'
          'عدّل الجهاز وأدخل الـcommunity (أنشئه من Reyee web UI: '
          'Advanced → Basics → SNMP، ثمّ أنشئ Read Community).',
        );
      }

      final stats = await RuijieApi.fetchStats(
        host: widget.device.ip,
        port: widget.device.apiPort ?? 161,
        community: community,
        onPartialReady: _stats == null
            ? (partial) {
                if (!mounted) return;
                setState(() => _stats = partial);
              }
            : null,
      );
      if (!mounted) return;

      final now = DateTime.now();
      // احسب rates من delta
      if (_lastFetch != null) {
        final elapsed = now.difference(_lastFetch!).inMilliseconds / 1000.0;
        if (elapsed > 0) {
          for (final iface in stats.ifaces) {
            final prev = _lastBytes[iface.index];
            if (prev != null) {
              final dRx = iface.rxBytes - prev.rxBytes;
              final dTx = iface.txBytes - prev.txBytes;
              if (dRx >= 0 && dTx >= 0) {
                final rxBps = (dRx * 8 / elapsed).round();
                final txBps = (dTx * 8 / elapsed).round();
                const maxSaneBps = 10000000000; // 10 Gbps sanity
                if (rxBps <= maxSaneBps && txBps <= maxSaneBps) {
                  _rates[iface.index] = _IfaceRate(rxBps: rxBps, txBps: txBps);
                }
              }
            }
            _lastBytes[iface.index] = _BytesPoint(
              rxBytes: iface.rxBytes,
              txBytes: iface.txBytes,
              at: now,
            );
          }
        }
      } else {
        for (final iface in stats.ifaces) {
          _lastBytes[iface.index] = _BytesPoint(
            rxBytes: iface.rxBytes,
            txBytes: iface.txBytes,
            at: now,
          );
        }
      }
        // 🐛 بلاغ المستخدم ٢٠٢٦-٠٩-٢٨: «خابط أعلى أبلود وعلى داونلود».
        //
        // كان المنحنى يجمع معدّلات **كلّ** الواجهات. والبايت الواحد
        // يمرّ على منفذ LAN وعلى WAN وعلى الجسر، فيُعَدّ ثلاث مرّات —
        // رقمٌ مضخَّمٌ واتّجاهٌ بلا معنى: ما هو «صاعد» على LAN هو
        // «نازل» على WAN، فجمعهما يُلغي الدلالة أصلاً.
        //
        // الصواب منفذٌ واحدٌ يُسمّى في العنوان: منفذ الصعود. وعليه
        // «نازل» تعني من الإنترنت و«صاعد» إليه — كما يفهمها المشغّل.
        final up = stats.uplink;
        _uplinkName = up?.name;
        _uplinkIsWan = stats.uplinkIsWan;
        final r = up == null ? null : _rates[up.index];
        if (r != null) {
          _traffic.add(_TrafficPoint(rx: r.rxBps, tx: r.txBps));
          if (_traffic.length > _maxTraffic) {
            _traffic.removeRange(0, _traffic.length - _maxTraffic);
          }
        }

        final a = stats.link?.activeSeconds;
        if (a != null && a != _lastActive) {
          _lastActive = a;
          _lastActiveSeenAt = DateTime.now();
        }

      setState(() {
        _stats = stats;
        DeviceStatsCache.instance.putRaw(widget.device.id, stats);
        _loading = false;
        _error = null;
        _lastFetch = now;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is RuijieException ? e.message : humanError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stats == null && _error != null) return _errorCard();
    if (_stats == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    final s = _stats!;
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        if (_error != null && _stats != null) _staleBanner(),
        _header(s),
        const SizedBox(height: Sp.md),
        _monitorControls(),
        const SizedBox(height: Sp.md),
        _systemStats(s),
        if (_traffic.length >= 2) ...[
          const SizedBox(height: 4),
          _trafficGraph(),
        ],
        if (s.isBridge) ...[
          const SizedBox(height: Sp.md),
          ExpandableSection(
            key: PageStorageKey('ruijie-${widget.device.id}-bridge'),
            initiallyExpanded: true,
            header: Row(children: [
              Icon(LucideIcons.radioTower, size: 14, color: AppColors.brand),
              const SizedBox(width: 6),
              Text('الوصلة اللاسلكيّة', style: AppType.bodyBold()),
              if (s.bridgeRole != null) ...[
                const SizedBox(width: 6),
                Text('(${s.bridgeRole})',
                    style: AppType.micro(color: AppColors.textLow)),
              ],
            ]),
            content: RepaintBoundary(child: _bridgeContent(s)),
          ),
        ],
        if (s.ifaces.isNotEmpty) ...[
          const SizedBox(height: Sp.md),
          ExpandableSection(
            key: PageStorageKey('ruijie-${widget.device.id}-ifaces'),
            initiallyExpanded: true,
            header: Row(children: [
              Icon(LucideIcons.network, size: 14, color: AppColors.brand),
              const SizedBox(width: 6),
              Text('Interfaces (${s.ifaces.length})',
                  style: AppType.bodyBold()),
            ]),
            content: Column(children: [
              for (final iface in s.ifaces) _interfaceRow(iface),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _header(RuijieStats s) {
    final name =
        s.sysName?.isNotEmpty == true ? s.sysName! : (widget.device.name);
    return Row(children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.brandSoftBg,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.brandSoftBorder, width: 1.5),
        ),
        child: Icon(LucideIcons.router, color: AppColors.brandAccent, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                overflow: TextOverflow.ellipsis,
                style: AppType.rowLabelBold()),
            const SizedBox(height: 2),
            Text(s.sysDescr?.split('\n').first ?? 'Ruijie / Reyee',
                overflow: TextOverflow.ellipsis,
                style: AppType.muted(color: AppColors.textMid)),
          ],
        ),
      ),
      if (s.uptime != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.clock, size: 10, color: AppColors.textMid),
            const SizedBox(width: 4),
            Text(_formatUptime(s.uptime!),
                style: TextStyle(fontSize: 10.5, height: 1.3, color: AppColors.textMid)),
          ]),
        ),
    ]);
  }

  Widget _monitorControls() {
    return Row(children: [
      IconButton(
        onPressed: _monitoring ? _stopMonitoring : _startMonitoring,
        icon:
            Icon(_monitoring ? LucideIcons.pause : LucideIcons.play, size: 16),
        tooltip: _monitoring ? 'إيقاف' : 'تشغيل',
      ),
      IconButton(
        onPressed: _loading ? null : _fetch,
        icon: _loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(LucideIcons.refreshCw, size: 16),
        tooltip: 'تحديث',
      ),
      const SizedBox(width: 4),
      Expanded(
        child: Text(
          _monitoring
              ? 'مراقبة حيّة (SNMP) • تحديث كل ${_refreshInterval.inSeconds}s'
              : 'المراقبة متوقّفة',
          style: TextStyle(fontSize: 10.5, height: 1.3, color: AppColors.textLow),
        ),
      ),
    ]);
  }

  Widget _systemStats(RuijieStats s) {
    return Row(children: [
      Expanded(
          child: _metricCard(
        label: 'CPU',
        value: s.cpuPercent,
        unit: '%',
        color: _percentColor(s.cpuPercent),
        icon: LucideIcons.cpu,
      )),
      const SizedBox(width: Sp.sm),
      Expanded(
          child: _metricCard(
        label: 'RAM',
        value: s.memPercent,
        unit: '%',
        color: _percentColor(s.memPercent),
        icon: LucideIcons.memoryStick,
      )),
    ]);
  }

  Widget _metricCard({
    required String label,
    required double? value,
    required String unit,
    required Color color,
    required IconData icon,
  }) {
    final display = value != null ? '${value.toStringAsFixed(0)}$unit' : '—';
    final percent = (value ?? 0).clamp(0.0, 100.0) / 100.0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 12, color: AppColors.textMid),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10.5, height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMid)),
            const Spacer(),
            Text(display,
                style: AppType.rowLabelBold(color: color)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.pill),
            child: LinearProgressIndicator(
              value: value == null ? null : percent,
              minHeight: 4,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // منحنى الترفك
  // ══════════════════════════════════════════════════════════

  /// مجموع معدّلات المنافذ عبر الزمن.
  ///
  /// يحتاج قراءتين قبل أن يظهر لأنّه فروق عدّادات لا قيمةً جاهزة —
  /// ولذلك يُخفى عند أوّل فتح بدل أن يُرسَم خطّاً مسطّحاً على الصفر
  /// يوهم بأنّ الوصلة خامدة.
  Widget _trafficGraph() {
    final rx = <FlSpot>[], tx = <FlSpot>[];
    for (var i = 0; i < _traffic.length; i++) {
      rx.add(FlSpot(i.toDouble(), _traffic[i].rx.toDouble()));
      tx.add(FlSpot(i.toDouble(), _traffic[i].tx.toDouble()));
    }
    var peak = 0;
    for (final t in _traffic) {
      peak = math.max(peak, math.max(t.rx, t.tx));
    }
    final last = _traffic.last;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, 8, Sp.md, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(
            _uplinkName == null
                ? 'الترفك'
                : (_uplinkIsWan
                    ? 'ترفك ${_uplinkName!}'
                    : 'أنشط منفذ · ${_uplinkName!}'),
            style: AppType.microBold(),
          ),
          const Spacer(),
          // على منفذ صعودٍ حقيقيّ: تنزيلٌ ورفع. وعلى غيره — منفذ
          // سويتشٍ مثلاً — «وارد» و«صادر» لأنّ اتّجاه الإنترنت لا
          // معنى له هناك.
          _chip(_uplinkIsWan ? '▼ تنزيل' : '▼ وارد', _fmtBps(last.rx),
              AppColors.success),
          const SizedBox(width: 6),
          _chip(_uplinkIsWan ? '▲ رفع' : '▲ صادر', _fmtBps(last.tx),
              AppColors.brand),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          height: 64,
          child: LineChart(
            LineChartData(
              minY: 0,
              // سقفٌ أعلى بقليل من الذروة وإلّا لامس المنحنى الحافّة
              // فبدا مشبعاً دائماً.
              maxY: peak == 0 ? 1 : peak * 1.15,
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                _line(rx, AppColors.success),
                _line(tx, AppColors.brand),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color c) => LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.28,
        color: c,
        barWidth: 2.5,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.withValues(alpha: 0.25), c.withValues(alpha: 0.02)],
          ),
        ),
      );

  Widget _chip(String arrow, String v, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Text('$arrow $v', style: AppType.microBold(color: c)),
      );

  static String _fmtBps(int bps) {
    if (bps <= 0) return '0';
    if (bps >= 1000000000) return '${(bps / 1e9).toStringAsFixed(1)}Gb';
    if (bps >= 1000000) return '${(bps / 1e6).toStringAsFixed(1)}Mb';
    if (bps >= 1000) return '${(bps / 1e3).toStringAsFixed(0)}Kb';
    return '$bps';
  }

  // ══════════════════════════════════════════════════════════
  // الوصلة اللاسلكيّة — جسور airMetro
  // ══════════════════════════════════════════════════════════

  Widget _bridgeContent(RuijieStats s) {
    final l = s.link!;
    final age = _measurementAge();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (age != null) _ageNotice(age),
      if (l.ssid != null) _ssidRow(l),
      const SizedBox(height: 8),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
              child: _tile('الإشارة', l.signalDbm?.toString(), 'dBm',
                  _signalColor(l.signalDbm), LucideIcons.signal)),
          const SizedBox(width: 8),
          Expanded(
              child: _tile('الضجيج', l.noiseDbm?.toString(), 'dBm',
                  AppColors.textMid, LucideIcons.activity)),
          const SizedBox(width: 8),
          Expanded(
              child: _tile('SNR', l.snrDb?.toString(), 'dB',
                  _snrColor(l.snrDb), LucideIcons.chartNoAxesColumn)),
        ]),
      ),
      const SizedBox(height: 8),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // التردّد أوّلاً لا رقم القناة — بلاغ المستخدم ٢٠٢٦-٠٩-٢٨:
          // «٥٨٢٠ أوضح من ١٦٤». والمشغّل الميدانيّ يوائم الهوائيات
          // بالتردّد، ورقم القناة ترجمةٌ له تهمّ الإعداد لا التشخيص.
          Expanded(
              child: _tile(
                  l.channel == null ? 'التردّد' : 'التردّد (ق ${l.channel})',
                  l.freqMhz?.toString(),
                  'MHz',
                  AppColors.brand,
                  LucideIcons.radio)),
          const SizedBox(width: 8),
          Expanded(
              child: _tile('المسافة', l.distanceM?.toString(), 'م',
                  AppColors.brand, LucideIcons.ruler)),
          const SizedBox(width: 8),
          Expanded(
              child: _tile('الارتباط', _linkAge(l.activeSeconds), '',
                  AppColors.textMid, LucideIcons.clock)),
        ]),
      ),
      if (s.peer != null && !s.peer!.isEmpty) ...[
        const SizedBox(height: 10),
        _peerRow(s.peer!),
      ],
    ]);
  }

  /// ختمٌ صريحٌ لعمر القياس.
  ///
  /// نعرضه **فقط** حين يتجاوز العمر نصف دقيقة، لأنّ الطبيعيّ ألّا
  /// يُذكَر. وحين يظهر فهو يقول للمشغّل: ما تراه ليس الآن.
  Widget _ageNotice(Duration age) {
    final bad = age.inMinutes >= 5;
    final c = bad ? AppColors.warning : AppColors.textMid;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bad ? AppColors.warningSoftBg : AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(children: [
        Icon(LucideIcons.history, size: 12, color: c),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            bad
                ? 'الجهاز لم يُحدّث قياساته منذ ${_fmtAge(age)} — الأرقام أدناه قديمة'
                : 'عمر القياس ${_fmtAge(age)}',
            style: AppType.micro(color: c),
          ),
        ),
      ]),
    );
  }

  Duration? _measurementAge() {
    final at = _lastActiveSeenAt;
    if (at == null) return null;
    final d = DateTime.now().difference(at);
    return d.inSeconds < 30 ? null : d;
  }

  static String _fmtAge(Duration d) => d.inMinutes < 1
      ? '${d.inSeconds} ثانية'
      : (d.inMinutes < 60 ? '${d.inMinutes} دقيقة' : '${d.inHours} ساعة');

  static String? _linkAge(int? sec) {
    if (sec == null || sec <= 0) return null;
    final d = sec ~/ 86400, h = (sec % 86400) ~/ 3600;
    if (d > 0) return '${d}ي ${h}س';
    final m = (sec % 3600) ~/ 60;
    return h > 0 ? '${h}س ${m}د' : '${m}د';
  }

  Widget _ssidRow(RuijieWirelessLink l) => Row(children: [
        Icon(LucideIcons.wifi, size: 13, color: AppColors.brand),
        const SizedBox(width: 6),
        Expanded(
          child: Text(l.ssid!,
              style: AppType.bodyBold(), overflow: TextOverflow.ellipsis),
        ),
        if (l.band != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.brandSoftBg,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child:
                Text(l.band!, style: AppType.microBold(color: AppColors.brand)),
          ),
      ]);

  /// الطرف المقابل — صفٌّ لكلّ حقيقة.
  ///
  /// كان الثلاثة مكدّسين في سطرٍ واحدٍ فيُقصّ العنوان («10.162.167.»)
  /// ويلتصق الرقم التسلسليّ بالطراز. وهذه بياناتُ تشخيصٍ تُقرأ رقماً
  /// رقماً حين تتعطّل وصلة، لا عنواناً عابراً.
  Widget _peerRow(RuijiePeer p) {
    Widget line(IconData ic, String label, String? value) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ic, size: 11, color: AppColors.textLow),
          const SizedBox(width: 5),
          SizedBox(
            width: 62,
            child: Text(label, style: AppType.micro(color: AppColors.textMid)),
          ),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                value,
                textAlign: TextAlign.left,
                style: AppType.rowLabelBold(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.arrowLeftRight, size: 13, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('الطرف المقابل', style: AppType.bodyBold()),
          if (p.vendor != null) ...[
            const Spacer(),
            Text(p.vendor!, style: AppType.micro(color: AppColors.textLow)),
          ],
        ]),
        line(LucideIcons.cpu, 'الطراز', p.model),
        line(LucideIcons.globe, 'العنوان', p.ip),
        line(LucideIcons.hash, 'التسلسليّ', p.serial),
      ]),
    );
  }

  /// بطاقةٌ لقيمةٍ مفردة — «—» حين تغيب، ولا صفرٌ يوهم بقياسٍ حقيقيّ.
  Widget _tile(String label, String? value, String unit, Color color,
      IconData icon) {
    final has = value != null && value.isNotEmpty;
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
            Icon(icon, size: 12, color: has ? color : AppColors.textLow),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.microBold(color: AppColors.textMid)),
            ),
          ]),
          const SizedBox(height: 6),
          // ⚠️ اتّجاهٌ لاتينيٌّ مفروض. الصفحة عربيّةٌ من اليمين، فكانت
          // «−43 dBm» تُرسَم «dBm43−»: الوحدة قبل الرقم والإشارة
          // السالبة في آخره. والقراءة الخاطئة لقيمةٍ سالبةٍ ليست
          // تجميلاً — المشغّل يقرأ الإشارة ليقرّر.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(has ? value : '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          color: has ? color : AppColors.textLow)),
                ),
                if (has && unit.isNotEmpty) ...[
                  const SizedBox(width: 2),
                  Text(unit, style: AppType.muted()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// عتبات الإشارة كما يقرؤها مشغّلٌ ميدانيّ لا كما يقرؤها جدول.
  static Color _signalColor(int? dbm) {
    if (dbm == null) return AppColors.textLow;
    if (dbm >= -55) return AppColors.success;
    if (dbm >= -70) return AppColors.warning;
    return AppColors.error;
  }

  /// SNR هو الحَكم الحقيقيّ: تحت ١٥ الوصلة تتهاوى مهما بدت الإشارة قويّة.
  static Color _snrColor(int? db) {
    if (db == null) return AppColors.textLow;
    if (db >= 25) return AppColors.success;
    if (db >= 15) return AppColors.warning;
    return AppColors.error;
  }

  Widget _interfaceRow(RuijieInterface iface) {
    final rate = _rates[iface.index];
    final rxBps = rate?.rxBps ?? 0;
    final txBps = rate?.txBps ?? 0;
    final speedText = iface.speedMbps > 0
        ? (iface.speedMbps >= 1000
            ? '${iface.speedMbps ~/ 1000}G'
            : '${iface.speedMbps}M')
        : '—';
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
            color: iface.operUp ? AppColors.success : AppColors.textLow,
            borderRadius: BorderRadius.circular(R.pill),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(iface.name,
                style: AppType.pillBold(color: AppColors.textHi),
                overflow: TextOverflow.ellipsis),
            Text(iface.operUp ? 'up' : 'down',
                style: TextStyle(
                    fontSize: 9.5, height: 1.2,
                    color:
                        iface.operUp ? AppColors.success : AppColors.textLow)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.pill),
          ),
          child: Text(speedText,
              style: AppType.microBold(color: AppColors.textMid)),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('↓${_bpsShort(rxBps)}',
              textDirection: TextDirection.ltr,
              style: AppType.microBold(color: AppColors.success)),
          Text('↑${_bpsShort(txBps)}',
              textDirection: TextDirection.ltr,
              style: AppType.microBold(color: AppColors.brandAccent)),
        ]),
      ]),
    );
  }

  Widget _staleBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.dangerSoftBg,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.dangerSoftBorder),
      ),
      child: Row(children: [
        Icon(LucideIcons.triangleAlert, size: 14, color: AppColors.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text('آخر تحديث فشل — البيانات من آخر جولة ناجحة',
              style: AppType.muted(color: AppColors.error)),
        ),
      ]),
    );
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.dangerSoftBorder),
      ),
      child: Column(children: [
        Icon(LucideIcons.triangleAlert, color: AppColors.error, size: 32),
        const SizedBox(height: 8),
        Text('تعذّرت مراقبة الجهاز',
            style: AppType.rowLabelBold()),
        const SizedBox(height: 4),
        Text(_error ?? '',
            textAlign: TextAlign.center,
            style: AppType.muted(color: AppColors.textMid)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _fetch,
          icon: const Icon(LucideIcons.refreshCw, size: 14),
          label: const Text('إعادة المحاولة'),
        ),
      ]),
    );
  }

  // ── Helpers ──
  Color _percentColor(double? v) => Grade.percentHigherBetter(v).fill;

  String _bpsShort(int bps) {
    if (bps <= 0) return '0';
    if (bps >= 1e9) return '${(bps / 1e9).toStringAsFixed(1)}G';
    if (bps >= 1e6) return '${(bps / 1e6).toStringAsFixed(1)}M';
    if (bps >= 1e3) return '${(bps / 1e3).toStringAsFixed(1)}K';
    return '$bps';
  }

  String _formatUptime(Duration d) {
    final days = d.inDays;
    final hours = d.inHours % 24;
    final mins = d.inMinutes % 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }
}

class _BytesPoint {
  final int rxBytes, txBytes;
  final DateTime at;
  _BytesPoint({required this.rxBytes, required this.txBytes, required this.at});
}

class _TrafficPoint {
  const _TrafficPoint({required this.rx, required this.tx});
  final int rx, tx;
}

class _IfaceRate {
  final int rxBps, txBps;
  _IfaceRate({required this.rxBps, required this.txBps});
}

// _math unused shim (keeps analyzer quiet if math ref is trimmed later)
// ignore: unused_element
void _keepMathImportAlive() {
  math.max(0, 0);
}
