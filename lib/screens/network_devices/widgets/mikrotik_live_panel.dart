import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/mikrotik_api.dart';
import '../../../api/network_devices_api.dart';
import '../../../models/network_device.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';

/// Panel للمراقبة الحيّة لجهاز Mikrotik.
/// - Auto-start عند فتح الصفحة (لا يحتاج المستخدم يضغط "بدء")
/// - CPU / RAM / أعلى interface throughput
/// - رسم بياني للـtraffic الإجمالي (RX + TX) آخر ~15 دقيقة
/// - قائمة interfaces من نوع ether/sfp فقط (بدون pppoe/bridge/vlan)
/// - كل ether يظهر مع سرعة RX/TX حاليّة
class MikrotikLivePanel extends StatefulWidget {
  final NetworkDevice device;
  const MikrotikLivePanel({super.key, required this.device});

  @override
  State<MikrotikLivePanel> createState() => _MikrotikLivePanelState();
}

class _MikrotikLivePanelState extends State<MikrotikLivePanel> {
  MikrotikStats? _stats;
  bool _loading = false;
  String? _error;
  Timer? _timer;
  bool _monitoring = false;
  DateTime? _lastFetch;

  /// آخر قيمة bytes لكل interface (لحساب rate من delta)
  final Map<String, _BytesPoint> _lastBytes = {};

  /// السرعات الحاليّة (bps) لكل interface — تُحسب بعد الـfetch الثاني
  final Map<String, _IfaceRate> _rates = {};

  /// history للـtraffic الإجمالي — للرسم البياني
  final List<_TrafficSample> _history = [];
  static const int _maxHistory = 30;              // 30 × 15s ≈ 7.5 دقائق
  static const _refreshInterval = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
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
    setState(() { _monitoring = false; });
  }

  Future<void> _fetch() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final creds = await NetworkDevicesApi.getCredentials(widget.device.id);
      final user = (creds['user'] ?? '').toString();
      final pass = (creds['pass'] ?? '').toString();
      if (user.isEmpty || pass.isEmpty) {
        throw MikrotikException('لم يتم إعداد credentials للجهاز');
      }
      final stats = await MikrotikApi.fetchStats(
        ip: widget.device.ip,
        port: widget.device.apiPort ?? 8728,
        user: user,
        pass: pass,
      );
      if (!mounted) return;

      final now = DateTime.now();
      // احسب السرعات من الفارق مع الـfetch السابق
      if (_lastFetch != null) {
        final elapsed = now.difference(_lastFetch!).inMilliseconds / 1000.0;
        if (elapsed > 0) {
          for (final iface in stats.interfaces) {
            final prev = _lastBytes[iface.name];
            if (prev != null && iface.rxBytes != null && iface.txBytes != null) {
              final dRx = iface.rxBytes! - prev.rxBytes;
              final dTx = iface.txBytes! - prev.txBytes;
              if (dRx >= 0 && dTx >= 0) {
                _rates[iface.name] = _IfaceRate(
                  rxBps: (dRx * 8 / elapsed).round(),
                  txBps: (dTx * 8 / elapsed).round(),
                );
              }
            }
            if (iface.rxBytes != null && iface.txBytes != null) {
              _lastBytes[iface.name] = _BytesPoint(
                rxBytes: iface.rxBytes!,
                txBytes: iface.txBytes!,
                at: now,
              );
            }
          }
        }
      } else {
        // أوّل fetch — نحفظ البيانات فقط للفارق التالي
        for (final iface in stats.interfaces) {
          if (iface.rxBytes != null && iface.txBytes != null) {
            _lastBytes[iface.name] = _BytesPoint(
              rxBytes: iface.rxBytes!,
              txBytes: iface.txBytes!,
              at: now,
            );
          }
        }
      }

      // احسب total traffic من الـethers فقط
      int totalRxBps = 0, totalTxBps = 0;
      for (final iface in stats.interfaces) {
        if (!_isEther(iface)) continue;
        final rate = _rates[iface.name];
        if (rate != null) {
          totalRxBps += rate.rxBps;
          totalTxBps += rate.txBps;
        }
      }
      if (_lastFetch != null) {
        _history.add(_TrafficSample(at: now, rxBps: totalRxBps, txBps: totalTxBps));
        if (_history.length > _maxHistory) _history.removeAt(0);
      }

      setState(() {
        _stats = stats;
        _loading = false;
        _error = null;
        _lastFetch = now;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is MikrotikException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  bool _isEther(MikrotikInterface i) =>
      i.type == 'ether' || i.type == 'sfp';

  /// أعلى interface throughput (RX+TX combined) — للـmetric card
  ({String name, int rxBps, int txBps})? _maxIface() {
    final ethers = (_stats?.interfaces ?? []).where(_isEther).toList();
    if (ethers.isEmpty) return null;
    ({String name, int rxBps, int txBps})? best;
    int bestTotal = 0;
    for (final i in ethers) {
      final r = _rates[i.name];
      if (r == null) continue;
      final total = r.rxBps + r.txBps;
      if (best == null || total > bestTotal) {
        best = (name: i.name, rxBps: r.rxBps, txBps: r.txBps);
        bestTotal = total;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    if (_stats == null && _error == null) {
      return Container(
        padding: const EdgeInsets.all(Sp.xl),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand)),
            const SizedBox(width: 10),
            Text('جاري الاتصال بـMikrotik…',
                style: TextStyle(fontSize: 12, color: AppColors.textMid)),
          ]),
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        _header(),
        if (_error != null) _errorBox(),
        if (_stats != null) ...[
          const Divider(height: 1),
          _boardBanner(),
          _metricsRow(),
          if (_history.length >= 2) ...[
            const SizedBox(height: 4),
            _trafficGraph(),
          ],
          const Divider(height: 1),
          _interfacesSection(),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Header
  // ══════════════════════════════════════════════════════════════
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.all(Sp.md),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(LucideIcons.activity, size: 16, color: AppColors.brand),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مراقبة حيّة (Mikrotik API)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi)),
            const SizedBox(height: 2),
            Row(children: [
              if (_monitoring) ...[
                _pulseDot(),
                const SizedBox(width: 4),
              ],
              Text(
                _loading ? 'جاري التحديث…' :
                (_monitoring ? 'يُحدَّث كل ${_refreshInterval.inSeconds}s' : 'متوقّف'),
                style: TextStyle(fontSize: 10, color: AppColors.textMid),
              ),
              if (_lastFetch != null) ...[
                Text(' • ', style: TextStyle(fontSize: 10, color: AppColors.textLow)),
                Text(
                  'آخر: ${_lastFetch!.hour.toString().padLeft(2, '0')}:${_lastFetch!.minute.toString().padLeft(2, '0')}:${_lastFetch!.second.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 10, color: AppColors.textLow, fontFamily: 'monospace'),
                ),
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
          icon: Icon(
            _monitoring ? LucideIcons.pause : LucideIcons.play,
            size: 16,
            color: _monitoring ? AppColors.error : const Color(0xFF10B981),
          ),
          onPressed: _monitoring ? _stopMonitoring : _startMonitoring,
          tooltip: _monitoring ? 'إيقاف' : 'استئناف',
          visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }

  Widget _pulseDot() => Container(
        width: 6, height: 6,
        decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
      );

  Widget _errorBox() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Sp.md),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(LucideIcons.triangleAlert, size: 14, color: AppColors.error),
        const SizedBox(width: 8),
        Expanded(child: Text(_error!,
            style: TextStyle(fontSize: 11, color: AppColors.error, height: 1.4))),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Board banner (moved from stats — since uptime moved to metric card)
  // ══════════════════════════════════════════════════════════════
  Widget _boardBanner() {
    final s = _stats!;
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(LucideIcons.router, size: 14, color: AppColors.brand),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${s.boardName} • RouterOS ${s.version}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textHi),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (s.pppActiveCount > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('PPP: ${s.pppActiveCount}',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: const Color(0xFF10B981), fontFamily: 'monospace')),
          ),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 3 metric cards: CPU / RAM / أعلى interface
  // ══════════════════════════════════════════════════════════════
  Widget _metricsRow() {
    final s = _stats!;
    final maxIf = _maxIface();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
      child: Row(children: [
        Expanded(child: _percentCard(
          icon: LucideIcons.cpu,
          label: 'CPU',
          percent: s.cpuLoad.toDouble(),
        )),
        const SizedBox(width: 8),
        Expanded(child: _percentCard(
          icon: LucideIcons.memoryStick,
          label: 'RAM',
          percent: s.memUsedPercent.toDouble(),
        )),
        const SizedBox(width: 8),
        Expanded(child: _topIfaceCard(maxIf)),
      ]),
    );
  }

  Widget _percentCard({
    required IconData icon,
    required String label,
    required double percent,
  }) {
    final color = _colorForPercent(percent);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMid)),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
          children: [
            Text('${percent.round()}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                    color: AppColors.textHi, fontFamily: 'monospace', height: 1)),
            const SizedBox(width: 2),
            Text('%', style: TextStyle(fontSize: 10, color: AppColors.textLow)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
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

  Widget _topIfaceCard(({String name, int rxBps, int txBps})? maxIf) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.arrowDownUp, size: 12, color: AppColors.brand),
          const SizedBox(width: 4),
          Text('أعلى', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMid)),
        ]),
        const SizedBox(height: 6),
        if (maxIf != null) ...[
          Text(maxIf.name,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                  color: AppColors.textHi, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(children: [
            Icon(LucideIcons.arrowDown, size: 9, color: const Color(0xFF10B981)),
            Text(_formatBps(maxIf.rxBps),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppColors.textHi, fontFamily: 'monospace')),
            const SizedBox(width: 6),
            Icon(LucideIcons.arrowUp, size: 9, color: const Color(0xFF3B82F6)),
            Text(_formatBps(maxIf.txBps),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppColors.textHi, fontFamily: 'monospace')),
          ]),
        ] else ...[
          Text('—',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                  color: AppColors.textLow, fontFamily: 'monospace')),
          const SizedBox(height: 4),
          Text('جارٍ حساب المعدّل…',
              style: TextStyle(fontSize: 9, color: AppColors.textLow)),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Traffic graph — RX + TX gradient area chart
  // ══════════════════════════════════════════════════════════════
  Widget _trafficGraph() {
    final rxSpots = <FlSpot>[];
    final txSpots = <FlSpot>[];
    for (int i = 0; i < _history.length; i++) {
      rxSpots.add(FlSpot(i.toDouble(), _history[i].rxBps.toDouble()));
      txSpots.add(FlSpot(i.toDouble(), _history[i].txBps.toDouble()));
    }
    final maxRx = _history.map((s) => s.rxBps).fold<int>(0, math.max);
    final maxTx = _history.map((s) => s.txBps).fold<int>(0, math.max);
    final maxY = (math.max(maxRx, maxTx) * 1.3).clamp(1000, double.infinity);

    final lastRx = _history.isNotEmpty ? _history.last.rxBps : 0;
    final lastTx = _history.isNotEmpty ? _history.last.txBps : 0;

    const rxColor = Color(0xFF10B981);
    const txColor = Color(0xFF3B82F6);

    return Container(
      margin: const EdgeInsets.all(Sp.md),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.chartLine, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('الحركة الإجماليّة (ether/sfp)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textHi)),
          const Spacer(),
          _legendChip('↓', _formatBps(lastRx), rxColor),
          const SizedBox(width: 6),
          _legendChip('↑', _formatBps(lastTx), txColor),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: AppColors.border.withValues(alpha: 0.5),
                  strokeWidth: 0.5,
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: maxY / 3,
                    getTitlesWidget: (value, _) => Text(
                      _formatBpsShort(value.toInt()),
                      style: TextStyle(fontSize: 9, color: AppColors.textLow, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minY: 0,
              maxY: maxY.toDouble(),
              minX: 0,
              maxX: (_history.length - 1).toDouble(),
              lineBarsData: [
                _lineBarData(rxSpots, rxColor),
                _lineBarData(txSpots, txColor),
              ],
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppColors.textHi.withValues(alpha: 0.9),
                  getTooltipItems: (spots) => spots.map((s) {
                    final isRx = s.barIndex == 0;
                    return LineTooltipItem(
                      '${isRx ? "↓" : "↑"} ${_formatBps(s.y.toInt())}',
                      TextStyle(
                        color: isRx ? rxColor : txColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    );
                  }).toList(),
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
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.28),
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
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$arrow $value',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
              color: color, fontFamily: 'monospace')),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Interfaces section — فقط ether + sfp، مع RX/TX rates
  // ══════════════════════════════════════════════════════════════
  Widget _interfacesSection() {
    final s = _stats!;
    final ethers = s.interfaces.where(_isEther).toList();
    if (ethers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Sp.md),
        child: Text('لا يوجد ethernet interfaces',
            style: TextStyle(fontSize: 11, color: AppColors.textLow)),
      );
    }
    final up = ethers.where((i) => i.running && !i.disabled).length;
    final down = ethers.where((i) => !i.running && !i.disabled).length;
    // ابحث عن أعلى معدّل لعرض bars نسبيّة
    int maxRate = 0;
    for (final iface in ethers) {
      final r = _rates[iface.name];
      if (r != null) {
        maxRate = math.max(maxRate, math.max(r.rxBps, r.txBps));
      }
    }

    return Padding(
      padding: const EdgeInsets.all(Sp.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.network, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('Ethernet Interfaces (${ethers.length})',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi)),
          const SizedBox(width: 8),
          _countBadge('↑ $up', const Color(0xFF10B981)),
          if (down > 0) ...[
            const SizedBox(width: 4),
            _countBadge('↓ $down', AppColors.error),
          ],
        ]),
        const SizedBox(height: 8),
        for (final iface in ethers) _interfaceRow(iface, maxRate),
      ]),
    );
  }

  Widget _countBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
              color: color, fontFamily: 'monospace')),
    );
  }

  Widget _interfaceRow(MikrotikInterface iface, int maxRate) {
    final rate = _rates[iface.name];
    final color = iface.disabled
        ? AppColors.textLow
        : (iface.running ? const Color(0xFF10B981) : AppColors.error);
    final statusIcon = iface.disabled
        ? LucideIcons.circleOff
        : (iface.running ? LucideIcons.arrowUp : LucideIcons.arrowDown);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        Row(children: [
          Icon(statusIcon, size: 12, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              iface.name,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: iface.disabled ? AppColors.textLow : AppColors.textHi,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (rate != null) ...[
            Icon(LucideIcons.arrowDown, size: 9, color: const Color(0xFF10B981)),
            const SizedBox(width: 2),
            Text(_formatBps(rate.rxBps),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppColors.textHi, fontFamily: 'monospace')),
            const SizedBox(width: 8),
            Icon(LucideIcons.arrowUp, size: 9, color: const Color(0xFF3B82F6)),
            const SizedBox(width: 2),
            Text(_formatBps(rate.txBps),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppColors.textHi, fontFamily: 'monospace')),
          ] else if (iface.running) ...[
            Text('—',
                style: TextStyle(fontSize: 10, color: AppColors.textLow, fontFamily: 'monospace')),
          ],
        ]),
        // شريط نسبي حسب أعلى traffic بين كل الـethers
        if (rate != null && maxRate > 0 && (rate.rxBps + rate.txBps) > 0) ...[
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: _miniBar((rate.rxBps + rate.txBps) / maxRate, color)),
          ]),
        ],
      ]),
    );
  }

  Widget _miniBar(double ratio, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: ratio.clamp(0.0, 1.0),
        minHeight: 2,
        backgroundColor: AppColors.border.withValues(alpha: 0.3),
        valueColor: AlwaysStoppedAnimation(color.withValues(alpha: 0.6)),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Helpers
  // ══════════════════════════════════════════════════════════════
  Color _colorForPercent(double p) {
    if (p >= 85) return AppColors.error;
    if (p >= 65) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  String _formatBps(int bps) {
    if (bps <= 0) return '0';
    if (bps < 1000) return '${bps}bps';
    if (bps < 1_000_000) return '${(bps / 1000).toStringAsFixed(1)}K';
    if (bps < 1_000_000_000) return '${(bps / 1_000_000).toStringAsFixed(1)}M';
    return '${(bps / 1_000_000_000).toStringAsFixed(2)}G';
  }

  String _formatBpsShort(int bps) {
    if (bps < 1000) return '0';
    if (bps < 1_000_000) return '${(bps / 1000).round()}K';
    if (bps < 1_000_000_000) return '${(bps / 1_000_000).round()}M';
    return '${(bps / 1_000_000_000).toStringAsFixed(1)}G';
  }
}

class _BytesPoint {
  final int rxBytes;
  final int txBytes;
  final DateTime at;
  const _BytesPoint({required this.rxBytes, required this.txBytes, required this.at});
}

class _IfaceRate {
  final int rxBps;
  final int txBps;
  const _IfaceRate({required this.rxBps, required this.txBps});
}

class _TrafficSample {
  final DateTime at;
  final int rxBps;
  final int txBps;
  const _TrafficSample({required this.at, required this.rxBps, required this.txBps});
}
