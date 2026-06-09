import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/device_probe_api.dart';
import '../../../models/device_health.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Probes the subscriber's IP on first build and renders a section
/// card with the relevant metric rows. Matches v1's device-health
/// card: ONT shows RX/TX power + voltage + temp; Ubiquiti shows
/// signal/CCQ/LAN + peer.
///
/// Probes via DeviceProbeApi which caches per-IP for 5 minutes, so
/// flipping between detail screens doesn't re-hit the router.
class DeviceProbeCard extends StatefulWidget {
  const DeviceProbeCard({super.key, required this.ip});
  final String ip;

  @override
  State<DeviceProbeCard> createState() => _DeviceProbeCardState();
}

class _DeviceProbeCardState extends State<DeviceProbeCard> {
  bool _loading = true;
  DeviceHealthSnapshot? _snap;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run({bool force = false}) async {
    setState(() => _loading = true);
    final snap = await DeviceProbeApi.probe(ip: widget.ip, force: force);
    if (!mounted) return;
    setState(() {
      _snap = snap;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: LucideIcons.router,
      title: 'معلومات الجهاز',
      accent: const Color(0xFF7C3AED),
      onRefresh: () => _run(force: true),
      busy: _loading,
      child: _body(),
    );
  }

  Widget _body() {
    if (_loading && _snap == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final snap = _snap;
    if (snap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            const Icon(LucideIcons.signalLow, size: 14, color: AppColors.textLow),
            const SizedBox(width: 6),
            Text(
              'لم يُتمكّن من الوصول للجهاز',
              style: AppType.muted().copyWith(fontSize: 11),
            ),
          ],
        ),
      );
    }
    if (snap.kind == DeviceKind.ont) return _ontBody(snap.ont!);
    if (snap.kind == DeviceKind.ubiquiti) return _ubntBody(snap.ubnt!);
    return const SizedBox.shrink();
  }

  Widget _ontBody(OntOpticalInfo o) {
    return Column(
      children: [
        _row('نوع الجهاز', 'Huawei ONT', LucideIcons.cable, color: AppColors.brand),
        _row('RX Power', '${o.rxPower} dBm', LucideIcons.signalHigh,
            color: _rxColor(o)),
        _row('TX Power', '${o.txPower} dBm', LucideIcons.signal,
            color: o.txOk ? AppColors.brand : AppColors.error),
        _row('الفولتية', '${o.voltage} mV', LucideIcons.zap,
            color: o.voltageOk ? AppColors.brand : const Color(0xFFE08F2D)),
        _row('الحرارة', '${o.temperature} °C', LucideIcons.thermometer,
            color: o.tempOk ? AppColors.brand : const Color(0xFFE08F2D)),
        if (o.sendStatus.trim().isNotEmpty && o.sendStatus.trim() != '--')
          _row('الحالة', o.sendStatus, LucideIcons.activity,
              color: AppColors.textHi),
      ],
    );
  }

  Widget _ubntBody(UbiquitiStatus u) {
    return Column(
      children: [
        _row('نوع الجهاز',
            u.hostname.isEmpty ? 'Ubiquiti' : '${u.hostname} (UBNT)',
            LucideIcons.wifi,
            color: AppColors.brand),
        if (u.firmware.isNotEmpty)
          _row('الإصدار', u.firmware, LucideIcons.cpu,
              color: AppColors.textHi),
        if (u.ssid.isNotEmpty)
          _row('SSID', u.ssid, LucideIcons.wifi, color: AppColors.textHi),
        if (u.signalDbm != null)
          _row('قوة الإشارة', '${u.signalDbm} dBm', LucideIcons.signal,
              color: _healthColor(u.signalHealth)),
        if (u.snrDb != null)
          _row('SNR', '${u.snrDb} dB', LucideIcons.activity,
              color: AppColors.textHi),
        if (u.ccqPercent != null)
          _row('CCQ', '${u.ccqPercent}%', LucideIcons.gauge,
              color: _healthColor(u.ccqHealth)),
        if (u.lanSpeedShort != null)
          _row('LAN', u.lanSpeedShort!, LucideIcons.cable,
              color: _healthColor(u.lanHealth)),
        if ((u.txRateKbps ?? 0) > 0 || (u.rxRateKbps ?? 0) > 0)
          _row(
            'الإرسال / الاستقبال',
            '${_rate(u.txRateKbps)} / ${_rate(u.rxRateKbps)}',
            LucideIcons.arrowLeftRight,
            color: AppColors.textHi,
          ),
        if (u.peerMac != null && u.peerMac!.isNotEmpty)
          _row('Peer MAC', u.peerMac!, LucideIcons.link,
              color: AppColors.textHi),
        if (u.peerCount != null && u.peerCount! > 0)
          _row('المتصلون', '${u.peerCount}', LucideIcons.users,
              color: AppColors.textHi),
      ],
    );
  }

  static Color _rxColor(OntOpticalInfo o) {
    if (o.rxOk) return AppColors.brand;
    return AppColors.error;
  }

  static Color _healthColor(String h) {
    switch (h) {
      case 'good':
        return AppColors.brand;
      case 'warn':
        return const Color(0xFFE08F2D);
      case 'bad':
        return AppColors.error;
      default:
        return AppColors.textHi;
    }
  }

  static String _rate(int? kbps) {
    if (kbps == null || kbps == 0) return '—';
    if (kbps >= 1000) return '${(kbps / 1000).toStringAsFixed(1)} Mbps';
    return '$kbps Kbps';
  }

  Widget _row(String label, String value, IconData icon, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color ?? AppColors.textMid),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: AppType.muted().copyWith(fontSize: 10.5),
            ),
          ),
          Text(
            value,
            style: AppType.label(color: color ?? AppColors.textHi)
                .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.accent,
    required this.child,
    required this.onRefresh,
    required this.busy,
  });
  final IconData icon;
  final String title;
  final Color accent;
  final Widget child;
  final VoidCallback onRefresh;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon, color: accent, size: 11),
              ),
              const SizedBox(width: 5),
              Text(
                title,
                style: AppType.label(color: AppColors.textHi).copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: busy ? null : onRefresh,
                borderRadius: BorderRadius.circular(R.sm),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: busy
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(LucideIcons.refreshCw,
                          size: 12, color: AppColors.textMid),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          child,
        ],
      ),
    );
  }
}
