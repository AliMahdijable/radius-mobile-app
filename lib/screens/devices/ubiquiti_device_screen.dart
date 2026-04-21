import 'package:flutter/material.dart';

import '../../core/services/ubiquiti_service.dart';
import '../../models/ubiquiti_info.dart';

class UbiquitiDeviceArgs {
  final String host;
  final String user;
  final String pass;
  const UbiquitiDeviceArgs({required this.host, required this.user, required this.pass});
}

class UbiquitiDeviceScreen extends StatefulWidget {
  final UbiquitiDeviceArgs args;
  const UbiquitiDeviceScreen({super.key, required this.args});

  @override
  State<UbiquitiDeviceScreen> createState() => _UbiquitiDeviceScreenState();
}

class _UbiquitiDeviceScreenState extends State<UbiquitiDeviceScreen> {
  UbiquitiStatus? _status;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final session = await UbiquitiService.login(
      widget.args.host, widget.args.user, widget.args.pass,
    );
    if (session == null) {
      if (mounted) setState(() { _loading = false; _error = 'فشل تسجيل الدخول'; });
      return;
    }
    final status = await UbiquitiService.fetchStatus(session);
    if (mounted) {
      setState(() {
        _status = status;
        _loading = false;
        if (status == null) _error = 'تعذّر جلب الحالة';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ubiquiti — ${widget.args.host}'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HeaderCard(status: _status!),
                      const SizedBox(height: 12),
                      _MetricsCard(status: _status!),
                      const SizedBox(height: 12),
                      _WirelessCard(status: _status!),
                    ],
                  ),
                ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final UbiquitiStatus status;
  const _HeaderCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final up = Duration(seconds: status.uptimeSeconds ?? 0);
    final days = up.inDays;
    final hours = up.inHours.remainder(24);
    final uptimeStr = days > 0 ? '$days يوم $hoursس' : '${up.inHours}س ${up.inMinutes.remainder(60)}د';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.router, size: 20),
                const SizedBox(width: 8),
                Text(status.hostname.isEmpty ? '—' : status.hostname,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            Text('firmware: ${status.firmware.isEmpty ? '—' : status.firmware}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            Text('mode: ${status.mode.isEmpty ? '—' : status.mode}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            Text('uptime: $uptimeStr',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ── Compact 2×2 metrics card ─────────────────────────────────────────────────
class _MetricsCard extends StatelessWidget {
  final UbiquitiStatus status;
  const _MetricsCard({required this.status});

  static const _good = Color(0xFF2E7D32);
  static const _warn = Color(0xFFF9A825);

  Color _ccqColor(ColorScheme cs) {
    final c = status.ccqPercent;
    if (c == null) return cs.onSurfaceVariant;
    if (c >= 80) return _good;
    if (c >= 50) return _warn;
    return cs.error;
  }

  Color _lanColor(ColorScheme cs) {
    if (!status.lanUp) return cs.error;
    final s = status.lanSpeed ?? '';
    if (s.contains('1000')) return _good;
    if (s.contains('100')) return _warn;
    return cs.error;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tx = status.txRateKbps;
    final rx = status.rxRateKbps;
    final txStr = tx == null ? '—' : tx >= 1000 ? '${(tx / 1000).toStringAsFixed(1)} Mbps' : '$tx kbps';
    final rxStr = rx == null ? '—' : rx >= 1000 ? '${(rx / 1000).toStringAsFixed(1)} Mbps' : '$rx kbps';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _Tile(
              icon: Icons.network_check,
              label: 'CCQ',
              value: status.ccqPercent != null ? '${status.ccqPercent}%' : '—',
              color: _ccqColor(cs),
            ),
            _divider(),
            _Tile(
              icon: Icons.lan,
              label: 'LAN',
              value: status.lanSpeedShort ?? '—',
              color: _lanColor(cs),
            ),
            _divider(),
            _Tile(
              icon: Icons.arrow_upward,
              label: 'TX',
              value: txStr,
              color: cs.onSurface,
            ),
            _divider(),
            _Tile(
              icon: Icons.arrow_downward,
              label: 'RX',
              value: rxStr,
              color: cs.onSurface,
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1, height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: Colors.black12,
      );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _Tile({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          Text(label,
              style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _WirelessCard extends StatelessWidget {
  final UbiquitiStatus status;
  const _WirelessCard({required this.status});

  Color _healthColor(String h, ColorScheme cs) {
    switch (h) {
      case 'good': return const Color(0xFF2E7D32);
      case 'warn': return const Color(0xFFF9A825);
      case 'bad':  return cs.error;
      default:     return cs.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi, color: cs.primary),
                const SizedBox(width: 8),
                const Text('الاتصال اللاسلكي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
            const Divider(height: 20),
            _row('SSID', status.ssid.isEmpty ? '—' : status.ssid, null),
            _row('الإشارة',
                status.signalDbm != null ? '${status.signalDbm} dBm' : '—',
                _healthColor(status.signalHealth, cs),
                ref: '> -65 ممتاز، -75 إلى -65 متوسط'),
            _row('Noise floor',
                status.noiseFloorDbm != null ? '${status.noiseFloorDbm} dBm' : '—', null),
            _row('SNR',
                status.snrDb != null ? '${status.snrDb} dB' : '—', null,
                ref: 'الفرق بين الإشارة والضجيج'),
            _row('CCQ',
                status.ccqPercent != null ? '${status.ccqPercent}%' : '—',
                _healthColor(status.ccqHealth, cs),
                ref: '≥80% جيد، 50-79% متوسط'),
            _row('TX rate', _formatKbps(status.txRateKbps), null),
            _row('RX rate', _formatKbps(status.rxRateKbps), null),
            _row('المسافة',
                status.distanceMeters != null ? '${status.distanceMeters} م' : '—', null),
            if (status.peerMac != null)
              _row('Peer MAC', status.peerMac!, null),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, Color? valueColor, {String? ref}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(color: valueColor, fontWeight: valueColor != null ? FontWeight.w700 : null)),
                if (ref != null)
                  Text(ref, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatKbps(int? kbps) {
    if (kbps == null) return '—';
    if (kbps >= 1000) return '${(kbps / 1000).toStringAsFixed(1)} Mbps';
    return '$kbps kbps';
  }
}

