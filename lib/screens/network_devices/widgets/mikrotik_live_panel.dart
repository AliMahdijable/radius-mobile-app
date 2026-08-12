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
import 'expandable_section.dart';

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

  /// أعلى interface بالـRX (download) — منفصل عن الـTX
  ({String name, int bps})? _maxRxIface() {
    final ethers = (_stats?.interfaces ?? []).where(_isEther).toList();
    ({String name, int bps})? best;
    for (final i in ethers) {
      final r = _rates[i.name];
      if (r == null) continue;
      if (best == null || r.rxBps > best.bps) {
        best = (name: i.name, bps: r.rxBps);
      }
    }
    return best;
  }

  /// أعلى interface بالـTX (upload) — منفصل عن الـRX
  ({String name, int bps})? _maxTxIface() {
    final ethers = (_stats?.interfaces ?? []).where(_isEther).toList();
    ({String name, int bps})? best;
    for (final i in ethers) {
      final r = _rates[i.name];
      if (r == null) continue;
      if (best == null || r.txBps > best.bps) {
        best = (name: i.name, bps: r.txBps);
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

    return Column(children: [
      // Main card: header + metrics + graph (دائماً ظاهر)
      Container(
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
            const SizedBox(height: Sp.md),
          ],
        ]),
      ),
      // Expandable sections (تُطوى/تُفتح)
      if (_stats != null) ..._buildExpandables(),
    ]);
  }

  List<Widget> _buildExpandables() {
    final s = _stats!;
    final ethers = s.interfaces.where(_isEther).toList();
    return [
      if (ethers.isNotEmpty) ...[
        const SizedBox(height: Sp.md),
        ExpandableSection(
          initiallyExpanded: true,
          header: Row(children: [
            Icon(LucideIcons.network, size: 14, color: AppColors.brand),
            const SizedBox(width: 6),
            Text('Ethernet Interfaces (${ethers.length})',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi)),
          ]),
          content: _interfacesContent(ethers),
        ),
      ],
      if (s.hasWireless) ...[
        const SizedBox(height: Sp.md),
        ExpandableSection(
          initiallyExpanded: true,
          header: Row(children: [
            Icon(LucideIcons.wifi, size: 14, color: AppColors.brand),
            const SizedBox(width: 6),
            Text('Wireless (${s.wirelessInterfaces.length})',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi)),
          ]),
          content: Column(children: [
            for (final w in s.wirelessInterfaces) _wirelessCard(w),
          ]),
        ),
      ],
      if (s.wirelessClients.isNotEmpty) ...[
        const SizedBox(height: Sp.md),
        ExpandableSection(
          initiallyExpanded: true,
          header: Row(children: [
            Icon(LucideIcons.users, size: 14, color: AppColors.brand),
            const SizedBox(width: 6),
            Text('العملاء المتّصلون (${s.wirelessClients.length})',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi)),
          ]),
          content: _clientsContent(s.wirelessClients),
        ),
      ],
    ];
  }

  Widget _interfacesContent(List<MikrotikInterface> ethers) {
    int maxRate = 0;
    for (final iface in ethers) {
      final r = _rates[iface.name];
      if (r != null) maxRate = math.max(maxRate, math.max(r.rxBps, r.txBps));
    }
    return Column(children: [
      for (final iface in ethers) _interfaceRow(iface, maxRate),
    ]);
  }

  Widget _clientsContent(List<MikrotikWirelessClient> cs) {
    return Column(children: [
      for (final c in cs.take(30)) _clientRow(c),
      if (cs.length > 30)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('+ ${cs.length - 30} عميل آخر',
              style: TextStyle(fontSize: 10, color: AppColors.textLow)),
        ),
    ]);
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
            '${s.boardName} • ${s.version.split(' ').first}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textHi),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Uptime badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.clock, size: 9, color: AppColors.brand),
            const SizedBox(width: 3),
            Text(_formatUptime(s.uptime),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppColors.brand)),
          ]),
        ),
        if (s.pppActiveCount > 0) ...[
          const SizedBox(width: 4),
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
    final maxRx = _maxRxIface();
    final maxTx = _maxTxIface();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
      child: Column(children: [
        // Row 1: CPU | RAM | Temperature — كل الكارتات بنفس الارتفاع
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _percentCard(
                icon: LucideIcons.cpu, label: 'CPU',
                percent: s.cpuLoad.toDouble(),
              )),
              const SizedBox(width: 8),
              Expanded(child: _percentCard(
                icon: LucideIcons.memoryStick, label: 'RAM',
                percent: s.memUsedPercent.toDouble(),
              )),
              const SizedBox(width: 8),
              Expanded(child: _valueCard(
                icon: LucideIcons.thermometer,
                label: 'حرارة',
                value: s.temperature != null ? '${s.temperature}' : '—',
                unit: s.temperature != null ? '°C' : '',
                color: _tempColor(s.temperature),
              )),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Row 2: Voltage | أعلى تنزيل ↓ | أعلى رفع ↑
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _valueCard(
                icon: LucideIcons.plug,
                label: 'فولتيّة',
                value: s.voltage != null ? s.voltage!.toStringAsFixed(1) : '—',
                unit: s.voltage != null ? 'V' : '',
                color: _voltageColor(s.voltage),
              )),
              const SizedBox(width: 8),
              Expanded(child: _topRateCard(
                label: 'أعلى ↓',
                iface: maxRx,
                color: const Color(0xFF10B981),
              )),
              const SizedBox(width: 8),
              Expanded(child: _topRateCard(
                label: 'أعلى ↑',
                iface: maxTx,
                color: const Color(0xFF3B82F6),
              )),
            ],
          ),
        ),
      ]),
    );
  }

  /// كارت قيمة عامّة (بدون progress bar) — للحرارة والفولتيّة.
  /// mainAxisAlignment: spaceBetween يوزّع العناصر عند stretch (نفس ارتفاع _percentCard).
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
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMid)),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                      color: value == '—' ? AppColors.textLow : color,
                      fontFamily: 'monospace', height: 1)),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(unit, style: TextStyle(fontSize: 11, color: AppColors.textLow)),
              ],
            ],
          ),
          // مُسافة صغيرة أسفل لمحاذاة تقريبيّة مع progress bar في _percentCard
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Color _tempColor(int? t) {
    if (t == null) return AppColors.textLow;
    if (t >= 75) return AppColors.error;
    if (t >= 60) return const Color(0xFFF59E0B);
    if (t >= 45) return const Color(0xFF06B6D4);
    return const Color(0xFF10B981);
  }

  Color _voltageColor(double? v) {
    if (v == null) return AppColors.textLow;
    // فولتيّة PoE عادية 24V / 48V — انحراف كبير = مشكلة
    if (v < 20 || v > 60) return AppColors.error;
    if (v < 22 || v > 55) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
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

  Widget _topRateCard({
    required String label,
    required ({String name, int bps})? iface,
    required Color color,
  }) {
    final hasData = iface != null && iface.bps > 0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header row 1: icon + "أعلى" فقط (بدون اسم — يأخذ سطره الخاصّ)
          Row(children: [
            Icon(
              label.contains('↓') ? LucideIcons.arrowDown : LucideIcons.arrowUp,
              size: 12, color: color,
            ),
            const SizedBox(width: 4),
            Text(label.replaceAll(RegExp(r'[↓↑]'), '').trim(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMid)),
          ]),
          // Row 2: اسم الـiface بحجم مقروء بلا تقطيع (لأنّه في سطره الخاصّ)
          if (hasData)
            Text(iface.name,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: AppColors.textHi, fontFamily: 'monospace')),
          // Row 3: value (big number)
          Text(hasData ? _formatBps(iface.bps) : '—',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: hasData ? color : AppColors.textLow,
                  fontFamily: 'monospace', height: 1)),
        ],
      ),
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
          Text(
            iface.name,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: iface.disabled ? AppColors.textLow : AppColors.textHi,
            ),
          ),
          if (iface.linkSpeed != null && iface.linkSpeed!.isNotEmpty && iface.running) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: _linkSpeedColor(iface.linkSpeed!).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _shortLinkSpeed(iface.linkSpeed!),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: _linkSpeedColor(iface.linkSpeed!),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
          const Spacer(),
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
  // ══════════════════════════════════════════════════════════════
  // Wireless section — للـMikrotik links/sectors/APs
  // ══════════════════════════════════════════════════════════════
  Widget _wirelessSection() {
    final wls = _stats!.wirelessInterfaces;
    return Padding(
      padding: const EdgeInsets.all(Sp.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.wifi, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('Wireless (${wls.length})',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi)),
        ]),
        const SizedBox(height: 8),
        for (final w in wls) _wirelessCard(w),
      ]),
    );
  }

  Widget _wirelessCard(MikrotikWireless w) {
    final active = w.running && !w.disabled;
    final color = active ? const Color(0xFF10B981) : AppColors.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(w.isAp ? LucideIcons.radioTower : LucideIcons.satellite,
              size: 14, color: color),
          const SizedBox(width: 6),
          Text(w.name,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: AppColors.textHi, fontFamily: 'monospace')),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(_modeLabel(w.mode),
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
        const SizedBox(height: 6),
        if (w.ssid.isNotEmpty)
          _wlRow(LucideIcons.wifi, 'SSID', w.ssid),
        if (w.band.isNotEmpty)
          _wlRow(LucideIcons.radio, 'Band', w.band),
        if (w.frequency > 0)
          _wlRow(LucideIcons.satellite, 'التردد',
              '${w.frequency} MHz${w.channelWidth > 0 ? " • ${w.channelWidth}MHz" : ""}'),
        if (w.txPower > 0)
          _wlRow(LucideIcons.zap, 'TX Power', '${w.txPower} dBm'),
      ]),
    );
  }

  Widget _wlRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(icon, size: 10, color: AppColors.textLow),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 10, color: AppColors.textMid)),
        const Spacer(),
        Text(value,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: AppColors.textHi)),
      ]),
    );
  }

  String _modeLabel(String m) => switch (m) {
        'ap-bridge' => 'AP Bridge',
        'bridge' => 'Bridge',
        'station' => 'Station',
        'station-bridge' => 'Station Bridge',
        'station-wds' => 'Station WDS',
        'wds-slave' => 'WDS Slave',
        _ => m,
      };

  // ══════════════════════════════════════════════════════════════
  // Wireless clients (registration table)
  // ══════════════════════════════════════════════════════════════
  Widget _wirelessClientsSection() {
    final cs = _stats!.wirelessClients;
    return Padding(
      padding: const EdgeInsets.all(Sp.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.users, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('العملاء المتّصلون (${cs.length})',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi)),
        ]),
        const SizedBox(height: 8),
        for (final c in cs.take(30)) _clientRow(c),
        if (cs.length > 30)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('+ ${cs.length - 30} عميل آخر',
                style: TextStyle(fontSize: 10, color: AppColors.textLow)),
          ),
      ]),
    );
  }

  Widget _clientRow(MikrotikWirelessClient c) {
    final signalColor = _signalColorFor(c.signalStrength);
    final hasName = c.hostname != null || c.comment != null;
    // Use best CCQ (tx-ccq usually higher)
    final ccq = c.txCcq > 0 ? c.txCcq : c.rxCcq;
    final ccqColor = _ccqColor(ccq);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Container(width: 3, height: 30, decoration: BoxDecoration(
          color: signalColor, borderRadius: BorderRadius.circular(1.5),
        )),
        const SizedBox(width: 8),
        // Name + secondary
        // primary: hostname/comment لو موجود، وإلا نعرض IP لو موجود، وإلا MAC
        // secondary: MAC (لو الـprimary مو MAC) + IP (لو الـprimary مو IP)
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            () {
              // اختر الـprimary display
              String primary;
              bool isMonospace;
              if (hasName) {
                primary = c.hostname ?? c.comment!;
                isMonospace = false;   // Cairo — قد يكون عربي
              } else if (c.ip != null) {
                primary = c.ip!;
                isMonospace = true;
              } else {
                primary = c.mac;
                isMonospace = true;
              }
              return Text(primary,
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.textHi,
                    fontFamily: isMonospace ? 'monospace' : null,
                  ),
                  overflow: TextOverflow.ellipsis);
            }(),
            const SizedBox(height: 2),
            // secondary line: IP (لو الـprimary اسم) + MAC دائماً بعده
            Row(children: [
              if (hasName && c.ip != null) ...[
                Text(c.ip!,
                    style: TextStyle(fontSize: 9, color: AppColors.textMid, fontFamily: 'monospace')),
                const SizedBox(width: 6),
              ],
              // MAC يظهر فقط لو الـprimary مو نفس MAC
              if (hasName || c.ip != null)
                Flexible(
                  child: Text(c.mac,
                      style: TextStyle(fontSize: 9, color: AppColors.textLow, fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis),
                ),
            ]),
          ]),
        ),
        const SizedBox(width: 6),
        // Signal + CCQ + rates
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(c.signalDisplay,
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                    color: signalColor, fontFamily: 'monospace')),
            const SizedBox(width: 2),
            Text('dBm', style: TextStyle(fontSize: 8, color: AppColors.textLow)),
            if (ccq > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ccqColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$ccq%',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                        color: ccqColor, fontFamily: 'monospace')),
              ),
            ],
          ]),
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.arrowDown, size: 8, color: const Color(0xFF10B981)),
            Text(' ${c.rxRate}',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                    color: AppColors.textHi, fontFamily: 'monospace')),
            const SizedBox(width: 6),
            Icon(LucideIcons.arrowUp, size: 8, color: const Color(0xFF3B82F6)),
            Text(' ${c.txRate}',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                    color: AppColors.textHi, fontFamily: 'monospace')),
            Text(' Mbps', style: TextStyle(fontSize: 8, color: AppColors.textLow)),
          ]),
        ]),
      ]),
    );
  }

  Color _ccqColor(int ccq) {
    if (ccq >= 80) return const Color(0xFF10B981);
    if (ccq >= 50) return const Color(0xFFF59E0B);
    return AppColors.error;
  }

  Color _signalColorFor(int dbm) {
    if (dbm >= -60) return const Color(0xFF10B981);
    if (dbm >= -70) return const Color(0xFF06B6D4);
    if (dbm >= -80) return const Color(0xFFF59E0B);
    return AppColors.error;
  }

  Color _colorForPercent(double p) {
    if (p >= 85) return AppColors.error;
    if (p >= 65) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  /// اختصار الـlink speed: "1Gbps" → "1G", "100Mbps" → "100M", "10Mbps" → "10M"
  String _shortLinkSpeed(String raw) {
    final r = raw.toLowerCase().replaceAll('bps', '').trim();
    if (r.endsWith('g')) return '${r.substring(0, r.length - 1).trim()}G';
    if (r.endsWith('m')) return '${r.substring(0, r.length - 1).trim()}M';
    return raw;
  }

  /// اللون حسب سرعة الـport — 1G أخضر، 100M أزرق، 10M أصفر، أقلّ أحمر
  Color _linkSpeedColor(String raw) {
    final r = raw.toLowerCase();
    if (r.contains('g') || r.contains('10000') || r.contains('2500')) return const Color(0xFF10B981);
    if (r.contains('1000') || r.contains('100m')) return const Color(0xFF06B6D4);
    if (r.contains('10m')) return const Color(0xFFF59E0B);
    return AppColors.textMid;
  }

  /// اختصار uptime: "3w2d15h4m5s" → "3أ 2ي" (أسبوع/يوم) أو "17س 4د"
  String _formatUptime(String raw) {
    if (raw.isEmpty) return '—';
    final weeks = RegExp(r'(\d+)w').firstMatch(raw)?.group(1);
    final days = RegExp(r'(\d+)d').firstMatch(raw)?.group(1);
    final hours = RegExp(r'(\d+)h').firstMatch(raw)?.group(1);
    final mins = RegExp(r'(\d+)m(?!s)').firstMatch(raw)?.group(1);
    if (weeks != null) return '${weeks}w ${days ?? "0"}d';
    if (days != null) return '${days}d ${hours ?? "0"}h';
    if (hours != null) return '${hours}h ${mins ?? "0"}m';
    if (mins != null) return '${mins}m';
    return raw;
  }

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
