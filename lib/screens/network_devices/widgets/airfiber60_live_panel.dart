import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/network_devices_api.dart';
import '../../../api/ubnt_api.dart';
import '../../../models/network_device.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import 'expandable_section.dart';

/// لوحة مراقبة متخصّصة لـUBNT airFiber 60 (GP/LR) — PtP 60 GHz link view.
/// mca-status عنده مضلّل (signal=-93، wlanTxRate=0). البيانات الحقيقيّة في wstalist.prs_sta.
/// المعروض: SNR + RSSI + Distance + Capacity + Margin + MCS.
class AirFiber60LivePanel extends StatefulWidget {
  final NetworkDevice device;
  const AirFiber60LivePanel({super.key, required this.device});

  @override
  State<AirFiber60LivePanel> createState() => _AirFiber60LivePanelState();
}

class _AirFiber60LivePanelState extends State<AirFiber60LivePanel> {
  UbntStats? _stats;
  bool _loading = false;
  String? _error;
  Timer? _timer;
  bool _monitoring = false;
  DateTime? _lastFetch;

  // ethernet rate tracking (delta بين قراءتين)
  final Map<String, _BytesPoint> _lastBytes = {};
  final Map<String, _IfaceRate> _rates = {};

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
    setState(() => _monitoring = false);
  }

  Future<void> _fetch() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await NetworkDevicesApi.getCredentials(widget.device.id);
      final creds = result['credentials'] as Map<String, dynamic>?;
      final user = (creds?['username'] ?? '').toString();
      final pass = (creds?['password'] ?? '').toString();
      final port = widget.device.apiPort ?? 22;

      final s = await UbntApi.fetchStats(
        ip: widget.device.ip,
        port: port,
        user: user,
        pass: pass,
      );

      _updateInterfaceRates(s);

      if (!mounted) return;
      setState(() {
        _stats = s;
        _lastFetch = DateTime.now();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is UbntException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  void _updateInterfaceRates(UbntStats s) {
    final now = DateTime.now();
    for (final iface in s.interfaces) {
      if (iface.rxBytes == null || iface.txBytes == null) continue;
      final prev = _lastBytes[iface.ifname];
      _lastBytes[iface.ifname] = _BytesPoint(iface.rxBytes!, iface.txBytes!, now);
      if (prev != null) {
        final dt = now.difference(prev.at).inMilliseconds / 1000;
        if (dt > 0) {
          _rates[iface.ifname] = _IfaceRate(
            rxBps: ((iface.rxBytes! - prev.rx) * 8 / dt).round(),
            txBps: ((iface.txBytes! - prev.tx) * 8 / dt).round(),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stats == null && _loading) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator(),
      ));
    }
    if (_error != null && _stats == null) {
      return _errorCard();
    }
    if (_stats == null) return const SizedBox.shrink();

    final s = _stats!;
    final peer = s.stations.isNotEmpty ? s.stations.first : null;

    return Column(children: [
      // Header controls
      _controlBar(),
      const SizedBox(height: Sp.md),
      // 🎯 Hero: peer + signal + SNR + MCS
      if (peer != null) _heroCard(peer),
      if (peer != null) const SizedBox(height: Sp.md),
      // ⚖️ Signal margin + Capacity utilization
      if (peer != null && peer.dlSignalExpect != null) _marginCard(peer),
      if (peer != null && peer.dlSignalExpect != null) const SizedBox(height: Sp.md),
      // 📊 Link performance
      if (peer != null) _linkPerformanceCard(peer),
      if (peer != null) const SizedBox(height: Sp.md),
      // 🌡️ System (CPU/RAM/Uptime)
      _systemCard(s),
      const SizedBox(height: Sp.md),
      // 🔌 Ethernet
      if (s.interfaces.isNotEmpty) _ethernetCard(s),
      if (s.interfaces.isNotEmpty) const SizedBox(height: Sp.md),
      // 📍 Location
      if (s.hasLocation) _locationCard(s),
      if (s.hasLocation) const SizedBox(height: Sp.md),
      // ℹ️ Info (firmware + sector)
      _infoCard(s, peer),
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // Header controls
  // ═══════════════════════════════════════════════════════
  Widget _controlBar() {
    final freshMs = _lastFetch != null
        ? DateTime.now().difference(_lastFetch!).inSeconds
        : null;
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _monitoring
              ? const Color(0xFF10B981).withValues(alpha: 0.12)
              : AppColors.border.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_loading)
            const SizedBox(
                width: 10, height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.5))
          else
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _monitoring ? const Color(0xFF10B981) : AppColors.textLow,
              ),
            ),
          const SizedBox(width: 6),
          Text(
              _monitoring
                  ? (freshMs != null ? 'مباشر · قبل ${freshMs}ث' : 'جاري...')
                  : 'موقوف',
              style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: _monitoring ? const Color(0xFF10B981) : AppColors.textMid,
              )),
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
        tooltip: _monitoring ? 'إيقاف المراقبة' : 'بدء المراقبة',
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // 🎯 Hero — peer name + signal + SNR + MCS
  // ═══════════════════════════════════════════════════════
  Widget _heroCard(UbntStation peer) {
    final signalColor = _signalColor(peer.signal);
    final peerName = peer.hostname ?? peer.mac;
    final snr = peer.snr;

    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [
            signalColor.withValues(alpha: 0.10),
            signalColor.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: signalColor.withValues(alpha: 0.35)),
      ),
      child: Column(children: [
        // Peer name + link status
        Row(children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: peer.isLinked60 ? const Color(0xFF10B981) : AppColors.error,
              boxShadow: peer.isLinked60 ? [
                BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.4), blurRadius: 6),
              ] : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(peerName,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900,
                    color: AppColors.textHi)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('60 GHz',
                style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w900,
                    color: Color(0xFF7C3AED))),
          ),
        ]),
        const SizedBox(height: 12),
        // 4 metrics: RSSI | SNR | MCS RX | MCS TX
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _heroMetric(
                icon: LucideIcons.signal,
                label: 'RSSI',
                value: '${peer.signal}',
                unit: 'dBm',
                color: signalColor,
              )),
              _heroDivider(),
              Expanded(child: _heroMetric(
                icon: LucideIcons.activity,
                label: 'SNR',
                value: snr != null ? '$snr' : '—',
                unit: snr != null ? 'dB' : '',
                color: snr != null ? _snrColor(snr) : AppColors.textLow,
              )),
              _heroDivider(),
              Expanded(child: _heroMetric(
                icon: LucideIcons.arrowDown,
                label: 'RX MCS',
                value: peer.rxMcs?.toString() ?? '—',
                unit: '',
                color: const Color(0xFF10B981),
              )),
              _heroDivider(),
              Expanded(child: _heroMetric(
                icon: LucideIcons.arrowUp,
                label: 'TX MCS',
                value: peer.txMcs?.toString() ?? '—',
                unit: '',
                color: const Color(0xFF3B82F6),
              )),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Signal quality label + MAC
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_signalLabel(peer.signal),
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: signalColor)),
          Text(peer.mac,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                  fontSize: 10, color: AppColors.textLow, fontFamily: 'monospace')),
        ]),
      ]),
    );
  }

  Widget _heroDivider() => Container(
        width: 1, margin: const EdgeInsets.symmetric(horizontal: 4),
        color: AppColors.border.withValues(alpha: 0.5),
      );

  Widget _heroMetric({
    required IconData icon, required String label,
    required String value, required String unit, required Color color,
  }) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(height: 2),
      Text(label,
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textMid)),
      const SizedBox(height: 2),
      Text(value,
          textDirection: TextDirection.ltr,
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w900,
              color: color, fontFamily: 'monospace', height: 1)),
      if (unit.isNotEmpty)
        Text(unit,
            style: TextStyle(
                fontSize: 8, fontWeight: FontWeight.w600, color: AppColors.textLow)),
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // ⚖️ Signal margin card
  // ═══════════════════════════════════════════════════════
  Widget _marginCard(UbntStation peer) {
    final actual = peer.signal;
    final expected = peer.dlSignalExpect!;
    final margin = peer.signalMargin!;
    final utilization = peer.capacityUtilization;

    final marginColor = margin >= -3
        ? const Color(0xFF10B981)
        : margin >= -8
            ? const Color(0xFFF59E0B)
            : AppColors.error;

    final utilColor = utilization == null
        ? AppColors.textLow
        : utilization >= 90
            ? const Color(0xFF10B981)
            : utilization >= 60
                ? const Color(0xFFF59E0B)
                : AppColors.error;

    return _cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.gauge, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('هامش الإشارة والسعة',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w900,
                  color: AppColors.textHi)),
        ]),
        const SizedBox(height: 12),
        // Signal margin
        IntrinsicHeight(
          child: Row(children: [
            Expanded(child: _marginTile(
              label: 'الفعلي',
              value: '$actual',
              unit: 'dBm',
              color: AppColors.textHi,
            )),
            const _MarginArrow(),
            Expanded(child: _marginTile(
              label: 'المتوقّع',
              value: '$expected',
              unit: 'dBm',
              color: AppColors.textMid,
            )),
            _heroDivider(),
            Expanded(child: _marginTile(
              label: 'الهامش',
              value: margin >= 0 ? '+$margin' : '$margin',
              unit: 'dB',
              color: marginColor,
            )),
          ]),
        ),
        const SizedBox(height: 12),
        // Capacity utilization
        if (utilization != null) ...[
          Row(children: [
            Text('استغلال السعة',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMid)),
            const Spacer(),
            Text('${utilization.round()}%',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w900, color: utilColor,
                    fontFamily: 'monospace')),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (utilization / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(utilColor),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _marginTile({
    required String label, required String value,
    required String unit, required Color color,
  }) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label,
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textMid)),
      const SizedBox(height: 2),
      Row(mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(value,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900,
                  color: color, fontFamily: 'monospace', height: 1)),
          const SizedBox(width: 2),
          Text(unit,
              style: TextStyle(
                  fontSize: 9, color: AppColors.textLow)),
        ],
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // 📊 Link performance — distance, capacity, uptime, sector
  // ═══════════════════════════════════════════════════════
  Widget _linkPerformanceCard(UbntStation peer) {
    final distanceKm = peer.distanceMeters != null
        ? (peer.distanceMeters! / 1000).toStringAsFixed(2)
        : null;
    final dlMbps = peer.dlCapacityKbps != null
        ? (peer.dlCapacityKbps! / 1000).toStringAsFixed(0)
        : null;
    final ulMbps = peer.ulCapacityKbps != null
        ? (peer.ulCapacityKbps! / 1000).toStringAsFixed(0)
        : null;
    final linkUptime = peer.linkUptimeSec != null
        ? _formatUptime(peer.linkUptimeSec!)
        : null;

    return _cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.radioTower, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('أداء اللنك',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w900,
                  color: AppColors.textHi)),
        ]),
        const SizedBox(height: 12),
        // Row 1: DL Capacity | UL Capacity
        IntrinsicHeight(
          child: Row(children: [
            Expanded(child: _valueCard(
              icon: LucideIcons.arrowDown,
              label: 'DL Capacity',
              value: dlMbps ?? '—',
              unit: 'Mbps',
              color: const Color(0xFF10B981),
            )),
            const SizedBox(width: 8),
            Expanded(child: _valueCard(
              icon: LucideIcons.arrowUp,
              label: 'UL Capacity',
              value: ulMbps ?? '—',
              unit: 'Mbps',
              color: const Color(0xFF3B82F6),
            )),
          ]),
        ),
        const SizedBox(height: 8),
        // Row 2: Distance | Link uptime | Sector
        IntrinsicHeight(
          child: Row(children: [
            Expanded(child: _valueCard(
              icon: LucideIcons.mapPin,
              label: 'المسافة',
              value: distanceKm ?? '—',
              unit: 'km',
              color: const Color(0xFF7C3AED),
            )),
            const SizedBox(width: 8),
            Expanded(child: _valueCard(
              icon: LucideIcons.clock,
              label: 'مدّة اللنك',
              value: linkUptime ?? '—',
              unit: '',
              color: AppColors.textHi,
            )),
            const SizedBox(width: 8),
            Expanded(child: _valueCard(
              icon: LucideIcons.compass,
              label: 'Sector',
              value: peer.rxSector != null && peer.txSector != null
                  ? '${peer.rxSector}/${peer.txSector}'
                  : '—',
              unit: '',
              color: const Color(0xFFF59E0B),
            )),
          ]),
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 🌡️ System card — CPU/RAM/Uptime
  // ═══════════════════════════════════════════════════════
  Widget _systemCard(UbntStats s) {
    final cpuPercent = s.host.cpuload.toDouble();
    final memPercent = s.memUsedPercent ?? 0;

    return _cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.cpu, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('النظام',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w900,
                  color: AppColors.textHi)),
          const Spacer(),
          if (s.host.temperature != 0)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.thermometer, size: 12, color: _tempColor(s.host.temperature)),
              const SizedBox(width: 2),
              Text('${s.host.temperature}°C',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800,
                      color: _tempColor(s.host.temperature),
                      fontFamily: 'monospace')),
            ]),
        ]),
        const SizedBox(height: 12),
        // CPU
        _percentRow(
          icon: LucideIcons.cpu,
          label: 'CPU',
          percent: cpuPercent,
          detail: '${cpuPercent.round()}%',
        ),
        const SizedBox(height: 8),
        // RAM
        if (s.memTotalMb != null && s.memUsedMb != null)
          _percentRow(
            icon: LucideIcons.memoryStick,
            label: 'RAM',
            percent: memPercent,
            detail: '${s.memUsedMb} / ${s.memTotalMb} MB',
          ),
        const SizedBox(height: 8),
        // Uptime
        Row(children: [
          Icon(LucideIcons.timer, size: 14, color: AppColors.textMid),
          const SizedBox(width: 6),
          Text('Uptime',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMid)),
          const Spacer(),
          Text(_formatUptime(s.host.uptime),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800,
                  color: AppColors.textHi, fontFamily: 'monospace')),
        ]),
      ]),
    );
  }

  Widget _percentRow({
    required IconData icon, required String label,
    required double percent, required String detail,
  }) {
    final color = _percentColor(percent);
    return Row(children: [
      Icon(icon, size: 14, color: AppColors.textMid),
      const SizedBox(width: 6),
      SizedBox(
        width: 32,
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMid)),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 110,
        child: Text(detail,
            textAlign: TextAlign.end,
            textDirection: TextDirection.ltr,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800,
                color: color, fontFamily: 'monospace')),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // 🔌 Ethernet — lanSpeed + real-time RX/TX
  // ═══════════════════════════════════════════════════════
  Widget _ethernetCard(UbntStats s) {
    final eths = s.interfaces.where((i) => i.ifname.startsWith('eth')).toList();
    if (eths.isEmpty) return const SizedBox.shrink();

    return _cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.cable, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('Ethernet',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w900,
                  color: AppColors.textHi)),
          const Spacer(),
          if (s.lanSpeed != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(s.lanSpeed!,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w900,
                      color: Color(0xFF10B981), fontFamily: 'monospace')),
            ),
        ]),
        const SizedBox(height: 8),
        for (final iface in eths) _ethRow(iface),
      ]),
    );
  }

  Widget _ethRow(UbntInterface iface) {
    final rate = _rates[iface.ifname];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: iface.plugged ? const Color(0xFF10B981) : AppColors.textLow,
          ),
        ),
        const SizedBox(width: 6),
        Text(iface.ifname,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800,
                color: AppColors.textHi, fontFamily: 'monospace')),
        if (iface.speed != null && iface.speed! > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text('${iface.speed}M',
                style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w800,
                    color: AppColors.brand, fontFamily: 'monospace')),
          ),
        ],
        const Spacer(),
        if (rate != null) Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(LucideIcons.arrowDown, size: 10, color: const Color(0xFF10B981)),
          Text(' ${_formatBps(rate.rxBps)}',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: AppColors.textHi, fontFamily: 'monospace')),
          const SizedBox(width: 8),
          Icon(LucideIcons.arrowUp, size: 10, color: const Color(0xFF3B82F6)),
          Text(' ${_formatBps(rate.txBps)}',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: AppColors.textHi, fontFamily: 'monospace')),
        ]),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 📍 Location
  // ═══════════════════════════════════════════════════════
  Widget _locationCard(UbntStats s) {
    final lat = s.latitude!.toStringAsFixed(6);
    final lng = s.longitude!.toStringAsFixed(6);
    final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

    return _cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.mapPin, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('الموقع',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w900,
                  color: AppColors.textHi)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$lat, $lng',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.textHi, fontFamily: 'monospace')),
            const SizedBox(height: 2),
            Text('اضغط لنسخ الإحداثيّات',
                style: TextStyle(fontSize: 9, color: AppColors.textLow)),
          ])),
          IconButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: '$lat,$lng'));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('نُسخت الإحداثيّات'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating));
              }
            },
            icon: Icon(LucideIcons.copy, size: 16, color: AppColors.textMid),
            tooltip: 'نسخ',
          ),
          IconButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: mapsUrl));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('نُسخ رابط Google Maps'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating));
              }
            },
            icon: Icon(LucideIcons.externalLink, size: 16, color: AppColors.brand),
            tooltip: 'نسخ رابط Google Maps',
          ),
        ]),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ℹ️ Info
  // ═══════════════════════════════════════════════════════
  Widget _infoCard(UbntStats s, UbntStation? peer) {
    final essid = s.wireless?.essid ?? '—';
    // firmware مثل GP.ipq806x.v2.6.8.48409 → نُبرز v2.6.8
    final fw = s.host.fwversion;
    final fwShort = _extractVersion(fw);

    return ExpandableSection(
      initiallyExpanded: false,
      header: Row(children: [
        Icon(LucideIcons.info, size: 16, color: AppColors.brand),
        const SizedBox(width: 6),
        Text('معلومات الجهاز',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w900,
                color: AppColors.textHi)),
      ]),
      content: Column(children: [
        _infoRow('Platform', s.host.devmodel),
        _infoRow('Firmware', fwShort.isNotEmpty ? fwShort : fw),
        _infoRow('ESSID', essid),
        if (peer != null && peer.mac.isNotEmpty)
          _infoRow('Peer MAC', peer.mac),
      ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMid)),
        const Spacer(),
        Flexible(child: Text(value,
            textDirection: TextDirection.ltr,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800,
                color: AppColors.textHi, fontFamily: 'monospace'),
            overflow: TextOverflow.ellipsis, textAlign: TextAlign.end)),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _valueCard({
    required IconData icon, required String label,
    required String value, required String unit, required Color color,
  }) {
    final hasSpace = value.contains(' ');
    final valueSize = hasSpace ? 15.0 : 18.0;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
        Row(children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textMid)),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
          Text(value,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                  fontSize: valueSize, fontWeight: FontWeight.w900,
                  color: color, fontFamily: 'monospace', height: 1)),
          if (unit.isNotEmpty) ...[
            const SizedBox(width: 2),
            Text(unit,
                style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textLow)),
          ],
        ]),
      ]),
    );
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(LucideIcons.circleAlert, size: 20, color: AppColors.error),
        const SizedBox(width: 8),
        Expanded(child: Text(_error ?? 'خطأ',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.error))),
        TextButton(onPressed: _fetch, child: const Text('إعادة')),
      ]),
    );
  }

  // ── color/label helpers ─────────────────────────────
  Color _signalColor(int dbm) {
    if (dbm >= -60) return const Color(0xFF10B981);
    if (dbm >= -70) return const Color(0xFF06B6D4);
    if (dbm >= -80) return const Color(0xFFF59E0B);
    return AppColors.error;
  }

  String _signalLabel(int dbm) {
    if (dbm >= -60) return 'ممتازة';
    if (dbm >= -70) return 'جيّدة';
    if (dbm >= -80) return 'مقبولة';
    return 'ضعيفة';
  }

  Color _snrColor(int snr) {
    if (snr >= 25) return const Color(0xFF10B981);
    if (snr >= 15) return const Color(0xFF06B6D4);
    if (snr >= 10) return const Color(0xFFF59E0B);
    return AppColors.error;
  }

  Color _tempColor(int t) {
    if (t >= 75) return AppColors.error;
    if (t >= 60) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  Color _percentColor(double p) {
    if (p >= 85) return AppColors.error;
    if (p >= 65) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
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

  String _formatBps(int bps) {
    if (bps < 1000) return '${bps}b';
    if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(1)}K';
    if (bps < 1000000000) return '${(bps / 1000000).toStringAsFixed(1)}M';
    return '${(bps / 1000000000).toStringAsFixed(2)}G';
  }

  String _extractVersion(String fw) {
    // "GP.ipq806x.v2.6.8.48409.251217.1118" → "v2.6.8"
    final m = RegExp(r'v(\d+\.\d+\.\d+)').firstMatch(fw);
    return m != null ? 'v${m.group(1)}' : '';
  }
}

// Small arrow used between margin tiles
class _MarginArrow extends StatelessWidget {
  const _MarginArrow();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(LucideIcons.arrowRight, size: 12, color: AppColors.textLow),
    );
  }
}

class _BytesPoint {
  final int rx, tx;
  final DateTime at;
  const _BytesPoint(this.rx, this.tx, this.at);
}

class _IfaceRate {
  final int rxBps, txBps;
  const _IfaceRate({required this.rxBps, required this.txBps});
}
