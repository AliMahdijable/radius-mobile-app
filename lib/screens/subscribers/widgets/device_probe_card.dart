import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/device_config_api.dart';
import '../../../api/device_probe_api.dart';
import '../../../models/device_health.dart';
import '../sheets/device_config_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Probes the subscriber's IP on first build and renders a section
/// card with the relevant metric rows. Matches v1's device-health
/// card: ONT shows RX/TX power + voltage + temp; Ubiquiti shows
/// signal/CCQ/LAN + peer.
///
/// Two-button header:
///   • gear → opens DeviceConfigSheet (IP / kind / user / pass / notes)
///   • refresh → forces a re-probe ignoring the 5-min cache.
class DeviceProbeCard extends StatefulWidget {
  const DeviceProbeCard({
    super.key,
    this.ip = '',
    required this.username,
  });
  /// IP من SAS4 (framedipaddress). قد يكون فارغاً — الـprobe() داخلياً
  /// يجرّب customIp من DeviceConfig أوّلاً، فحتى المشتركون بلا session
  /// نشط يحصلون على فحص لو المدير خزّن customIp في إعدادات الجهاز.
  final String ip;
  final String username;

  @override
  State<DeviceProbeCard> createState() => _DeviceProbeCardState();
}

class _DeviceProbeCardState extends State<DeviceProbeCard> {
  bool _loading = true;
  DeviceHealthSnapshot? _snap;
  String? _notes;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run({bool force = false}) async {
    setState(() => _loading = true);
    // Probe + notes in parallel — both go through small caches so the
    // total cost on a warm session is sub-100ms.
    final results = await Future.wait([
      DeviceProbeApi.probe(
        fallbackIp: widget.ip,
        subscriberUsername: widget.username,
        force: force,
      ),
      DeviceConfigApi.fetchConfig(widget.username),
    ]);
    if (!mounted) return;
    final snap = results[0] as DeviceHealthSnapshot?;
    final cfg = results[1] as DeviceConfig?;
    setState(() {
      _snap = snap;
      _notes = cfg?.notes?.trim();
      _loading = false;
    });
  }

  Future<void> _openConfig() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DeviceConfigSheet(username: widget.username),
    );
    if (changed == true && mounted) {
      // The sheet already invalidated per-IP cache when it saved.
      _run(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return _Card(
      icon: LucideIcons.router,
      title: 'معلومات الجهاز',
      accent: const Color(0xFF7C3AED),
      onRefresh: () => _run(force: true),
      onConfig: _openConfig,
      busy: _loading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _body(),
          // مطلب 2026-06-11: سطر ملاحظة المدير من DeviceConfig.notes.
          // مخفي إذا فاضي حتى لا يضيف ارتفاع ع الكرت بدون فائدة.
          if ((_notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE08F2D).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(
                  color: const Color(0xFFE08F2D).withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.fileText,
                      size: 11, color: Color(0xFFE08F2D)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _notes!,
                      style: AppType.muted(color: AppColors.textHi).copyWith(
                          fontSize: 10.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
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
            Icon(LucideIcons.signalLow, size: 14, color: AppColors.textLow),
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
        // مطلب 2026-06-11: عرض كل المنافذ (لا فقط primary) — كل
        // eth interface بسطر منفصل مع plugged/speed وحدوده الخاصة.
        if (u.lanPorts.isNotEmpty) _lanPortsBlock(u.lanPorts),
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

  /// Renders the LAN port grid for Ubiquiti devices — one chip per
  /// eth interface. plugged ports show their speed colored by health
  /// (1G good / 100M warn / 10M bad). unplugged ports use a grey
  /// disabled style so the row still communicates port-presence.
  Widget _lanPortsBlock(List<LanPort> ports) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.cable, size: 12, color: AppColors.textMid),
              const SizedBox(width: 6),
              Text(
                'المنافذ',
                style: AppType.muted().copyWith(fontSize: 10.5),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [for (final p in ports) _lanChip(p)],
          ),
        ],
      ),
    );
  }

  Widget _lanChip(LanPort p) {
    final unplugged = !p.plugged;
    final speed = p.displaySpeed;
    Color color;
    if (unplugged) {
      color = AppColors.textLow;
    } else if (speed.contains('Gbps')) {
      color = AppColors.brand;
    } else {
      final m = RegExp(r'(\d+)\s*Mbps').firstMatch(speed);
      final mbps = m == null ? null : int.tryParse(m.group(1)!);
      if (mbps == null) {
        color = AppColors.textMid;
      } else if (mbps >= 100) {
        color = AppColors.brand;
      } else {
        color = const Color(0xFFE08F2D);
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            unplugged ? LucideIcons.unplug : LucideIcons.cable,
            size: 9.5,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            p.label,
            style: AppType.label(color: color)
                .copyWith(fontSize: 10, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 4),
          Text(
            unplugged ? 'مفصول' : speed,
            style: AppType.muted(color: color)
                .copyWith(fontSize: 9.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
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
    required this.onConfig,
    required this.busy,
  });
  final IconData icon;
  final String title;
  final Color accent;
  final Widget child;
  final VoidCallback onRefresh;
  final VoidCallback onConfig;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
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
                onTap: onConfig,
                borderRadius: BorderRadius.circular(R.sm),
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(LucideIcons.settings,
                      size: 12, color: AppColors.textMid),
                ),
              ),
              const SizedBox(width: 2),
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
                      : Icon(LucideIcons.refreshCw,
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
