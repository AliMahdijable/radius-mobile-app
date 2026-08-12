import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/mimosa_api.dart';
import '../../../api/network_devices_api.dart';
import '../../../models/network_device.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import 'expandable_section.dart';

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
  bool _loading = false;
  String? _error;
  Timer? _timer;
  bool _monitoring = false;
  DateTime? _lastFetch;

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
    setState(() { _loading = true; _error = null; });
    try {
      final creds = await NetworkDevicesApi.getCredentials(widget.device.id);
      // بالنسبة لـSNMP: community string يُخزَّن في حقل الـpassword
      // (user فارغ لأن SNMP v2c ما يستعمل username).
      final community = (creds['pass'] ?? '').toString().trim();
      if (community.isEmpty) {
        throw MimosaException(
            'لم يتم إعداد SNMP community string. '
            'أدخله في حقل "كلمة المرور" لهذا الجهاز.');
      }
      final port = widget.device.apiPort ?? 161;
      final s = await MimosaApi.fetchStats(
        host: widget.device.ip,
        port: port,
        community: community,
      );
      if (!mounted) return;
      setState(() {
        _stats = s;
        _lastFetch = DateTime.now();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is MimosaException ? e.message : e.toString();
        _loading = false;
      });
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
          color: _monitoring
              ? const Color(0xFF10B981).withValues(alpha: 0.12)
              : AppColors.border.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_loading)
            const SizedBox(width: 10, height: 10,
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
                ? (freshS != null ? 'مباشر · قبل ${freshS}ث' : 'جاري...')
                : 'موقوف',
            style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: _monitoring ? const Color(0xFF10B981) : AppColors.textMid,
            ),
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
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFEA580C).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFEA580C).withValues(alpha: 0.3)),
            ),
            child: const Center(
              child: Text('M',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900,
                      color: Color(0xFFEA580C))),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900,
                      color: AppColors.textHi)),
              if (s.sysDescr != null)
                Text(s.sysDescr!,
                    style: TextStyle(fontSize: 9, color: AppColors.textLow),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (s.temperatureC != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.thermometer, size: 12, color: _tempColor(s.temperatureC!)),
              const SizedBox(width: 2),
              Text('${s.temperatureC!.toStringAsFixed(1)}°C',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                      color: _tempColor(s.temperatureC!),
                      fontFamily: 'monospace')),
            ]),
        ]),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _heroMetric(
              icon: LucideIcons.arrowDown,
              label: 'RX Power',
              value: rx != null ? rx.toStringAsFixed(1) : '—',
              unit: rx != null ? 'dBm' : '',
              color: signalColor,
            )),
            _heroDivider(),
            Expanded(child: _heroMetric(
              icon: LucideIcons.arrowUp,
              label: 'TX Power',
              value: tx != null ? tx.toStringAsFixed(1) : '—',
              unit: tx != null ? 'dBm' : '',
              color: const Color(0xFF3B82F6),
            )),
            _heroDivider(),
            Expanded(child: _heroMetric(
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
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
              color: AppColors.textMid)),
      const SizedBox(height: 2),
      Text(value,
          textDirection: TextDirection.ltr,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
              color: color, fontFamily: 'monospace', height: 1)),
      if (unit.isNotEmpty)
        Text(unit,
            style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600,
                color: AppColors.textLow)),
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
        ? const Color(0xFF10B981)
        : margin >= -8
            ? const Color(0xFFF59E0B)
            : AppColors.error;
    return _cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.gauge, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('هامش الإشارة',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                  color: AppColors.textHi)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _marginTile('الفعلي', actual.toStringAsFixed(1), 'dBm', AppColors.textHi)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(LucideIcons.arrowRight, size: 12, color: AppColors.textLow)),
          Expanded(child: _marginTile('المتوقّع', target.toStringAsFixed(1), 'dBm', AppColors.textMid)),
          _heroDivider(),
          Expanded(child: _marginTile(
              'الهامش',
              margin >= 0 ? '+${margin.toStringAsFixed(1)}' : margin.toStringAsFixed(1),
              'dB', marginColor)),
        ]),
      ]),
    );
  }

  Widget _marginTile(String label, String value, String unit, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
              color: AppColors.textMid)),
      const SizedBox(height: 2),
      Row(mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
        Text(value,
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                color: color, fontFamily: 'monospace', height: 1)),
        const SizedBox(width: 2),
        Text(unit, style: TextStyle(fontSize: 9, color: AppColors.textLow)),
      ]),
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // 📶 Chains — per-chain signal
  // ═══════════════════════════════════════════════════════
  Widget _chainsSection(MimosaStats s) {
    return ExpandableSection(
      initiallyExpanded: true,
      header: Row(children: [
        Icon(LucideIcons.signal, size: 14, color: const Color(0xFFEA580C)),
        const SizedBox(width: 6),
        Text('Chains (${s.chains.length})',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: AppColors.textHi)),
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
          width: 26, height: 26,
          decoration: BoxDecoration(
            color: const Color(0xFFEA580C).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text('${c.index}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                    color: const Color(0xFFEA580C), fontFamily: 'monospace')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _chainMetric('RX',
            c.rxPowerDbm != null ? '${c.rxPowerDbm!.toStringAsFixed(1)} dBm' : '—',
            c.rxPowerDbm != null ? _rxColor(c.rxPowerDbm!) : AppColors.textLow)),
        Expanded(child: _chainMetric('Noise',
            c.rxNoiseDbm != null ? '${c.rxNoiseDbm!.toStringAsFixed(0)} dBm' : '—',
            AppColors.textMid)),
        Expanded(child: _chainMetric('SNR',
            c.snrDb != null ? '${c.snrDb!.toStringAsFixed(0)} dB' : '—',
            c.snrDb != null ? _snrColor(c.snrDb!) : AppColors.textLow)),
      ]),
    );
  }

  Widget _chainMetric(String label, String value, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(fontSize: 9, color: AppColors.textLow)),
      const SizedBox(height: 2),
      Text(value,
          textDirection: TextDirection.ltr,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
              color: color, fontFamily: 'monospace')),
    ]);
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
          Text('الأداء (PHY 5s)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                  color: AppColors.textHi)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _valueCard(
            icon: LucideIcons.arrowDown,
            label: 'RX Rate',
            value: s.phyRxRateMbps?.toString() ?? '—',
            unit: 'Mbps',
            color: const Color(0xFF10B981),
          )),
          const SizedBox(width: 8),
          Expanded(child: _valueCard(
            icon: LucideIcons.arrowUp,
            label: 'TX Rate',
            value: s.phyTxRateMbps?.toString() ?? '—',
            unit: 'Mbps',
            color: const Color(0xFF3B82F6),
          )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _valueCard(
            icon: LucideIcons.circleAlert,
            label: 'RX Errors',
            value: s.perRxRatePct != null ? s.perRxRatePct!.toStringAsFixed(1) : '—',
            unit: '%',
            color: _errColor(s.perRxRatePct),
          )),
          const SizedBox(width: 8),
          Expanded(child: _valueCard(
            icon: LucideIcons.circleAlert,
            label: 'TX Errors',
            value: s.perTxRatePct != null ? s.perTxRatePct!.toStringAsFixed(1) : '—',
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
          Text('النظام',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                  color: AppColors.textHi)),
        ]),
        const SizedBox(height: 12),
        _infoRow('Uptime', _formatUptime(s.sysUptimeSec)),
        if (s.antennaGainDbi != null)
          _infoRow('Antenna Gain', '${s.antennaGainDbi} dBi'),
        if (s.wirelessMode != null)
          _infoRow('Mode', _modeLabel(s.wirelessMode!)),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('CPU/RAM غير متوفّرين — firmware Mimosa يخفيهما',
              style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic,
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
          Text('GPS',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                  color: AppColors.textHi)),
          const Spacer(),
          if (s.gpsSats != null)
            Text('${s.gpsSats} satellites',
                style: TextStyle(fontSize: 10, color: AppColors.textLow)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('$lat, $lng',
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: AppColors.textHi, fontFamily: 'monospace'))),
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
        if (s.altitude != null)
          _infoRow('Altitude', '${s.altitude} m'),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ℹ️ Info
  // ═══════════════════════════════════════════════════════
  Widget _infoCard(MimosaStats s) {
    return ExpandableSection(
      initiallyExpanded: false,
      header: Row(children: [
        Icon(LucideIcons.info, size: 14, color: AppColors.textMid),
        const SizedBox(width: 6),
        Text('معلومات الجهاز',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: AppColors.textHi)),
      ]),
      content: Column(children: [
        if (s.firmwareVersion != null)
          _infoRow('Firmware', s.firmwareVersion!),
        if (s.serialNumber != null)
          _infoRow('Serial', s.serialNumber!),
      ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: AppColors.textMid)),
        const Spacer(),
        Flexible(child: Text(value,
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
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
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
              color: AppColors.textMid)),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
          Text(value,
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                  color: color, fontFamily: 'monospace', height: 1)),
          const SizedBox(width: 2),
          Text(unit, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
              color: AppColors.textLow)),
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
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: AppColors.error))),
        TextButton(onPressed: _fetch, child: const Text('إعادة')),
      ]),
    );
  }

  Color _rxColor(double dbm) {
    if (dbm >= -50) return const Color(0xFF10B981);
    if (dbm >= -65) return const Color(0xFF06B6D4);
    if (dbm >= -75) return const Color(0xFFF59E0B);
    return AppColors.error;
  }

  Color _snrColor(double snr) {
    if (snr >= 25) return const Color(0xFF10B981);
    if (snr >= 15) return const Color(0xFF06B6D4);
    if (snr >= 10) return const Color(0xFFF59E0B);
    return AppColors.error;
  }

  Color _tempColor(double t) {
    if (t >= 75) return AppColors.error;
    if (t >= 60) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  Color _errColor(double? pct) {
    if (pct == null) return AppColors.textLow;
    if (pct >= 5) return AppColors.error;
    if (pct >= 1) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  String _modeLabel(int mode) {
    switch (mode) {
      case 1: return 'AP';
      case 2: return 'STA';
      default: return 'mode $mode';
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
