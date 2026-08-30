import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/ruijie_api.dart';
import '../../../api/network_devices_api.dart';
import '../../../models/network_device.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import 'expandable_section.dart';
import '_grade.dart';
import '../../../theme/typography.dart';

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

  /// آخر bytes لكل interface — لحساب rate delta
  final Map<int, _BytesPoint> _lastBytes = {};
  final Map<int, _IfaceRate> _rates = {};

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

      setState(() {
        _stats = stats;
        _loading = false;
        _error = null;
        _lastFetch = now;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is RuijieException ? e.message : e.toString();
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

class _IfaceRate {
  final int rxBps, txBps;
  _IfaceRate({required this.rxBps, required this.txBps});
}

// _math unused shim (keeps analyzer quiet if math ref is trimmed later)
// ignore: unused_element
void _keepMathImportAlive() {
  math.max(0, 0);
}
