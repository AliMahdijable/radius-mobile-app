import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/mikrotik_api.dart';
import '../../../api/network_devices_api.dart';
import '../../../models/network_device.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';

/// Panel للمراقبة الحيّة لجهاز Mikrotik. يُعرض في details screen
/// فقط لو الجهاز mikrotik + protocol=api + hasCredentials.
///
/// - زر Start/Stop للـauto-refresh (30s)
/// - CPU + RAM + uptime + version + PPP count cards
/// - Interfaces list مع up/down + type
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

  static const _refreshInterval = Duration(seconds: 30);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleMonitoring() {
    if (_monitoring) {
      _timer?.cancel();
      setState(() => _monitoring = false);
    } else {
      _startMonitoring();
    }
  }

  Future<void> _startMonitoring() async {
    setState(() => _monitoring = true);
    await _fetch();
    _timer?.cancel();
    _timer = Timer.periodic(_refreshInterval, (_) => _fetch());
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
        port: widget.device.apiPort ?? 80,
        user: user,
        pass: pass,
      );
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
        _error = null;
        _lastFetch = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is MikrotikException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
          _systemCards(),
          const Divider(height: 1),
          _interfacesSection(),
        ] else if (_error == null && !_monitoring)
          _emptyState(),
      ]),
    );
  }

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
            if (_monitoring) ...[
              const SizedBox(height: 2),
              Row(children: [
                _pulseDot(),
                const SizedBox(width: 4),
                Text(
                  _loading ? 'جاري التحديث…' : 'يُحدَّث كل 30 ثانية',
                  style: TextStyle(fontSize: 10, color: AppColors.textMid),
                ),
              ]),
            ] else
              Text('اضغط "بدء" للاتصال بالراوتر عبر REST API',
                  style: TextStyle(fontSize: 10, color: AppColors.textLow)),
          ]),
        ),
        if (_monitoring && _stats != null) ...[
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            onPressed: _loading ? null : _fetch,
            tooltip: 'تحديث الآن',
            color: AppColors.brand,
          ),
        ],
        FilledButton.icon(
          onPressed: _toggleMonitoring,
          icon: Icon(_monitoring ? LucideIcons.square : LucideIcons.play, size: 14),
          label: Text(_monitoring ? 'إيقاف' : 'بدء',
              style: const TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(
            backgroundColor: _monitoring ? AppColors.error : AppColors.brand,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: const Size(0, 32),
          ),
        ),
      ]),
    );
  }

  Widget _pulseDot() => Container(
        width: 6, height: 6,
        decoration: BoxDecoration(
          color: const Color(0xFF10B981),
          shape: BoxShape.circle,
        ),
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
        Expanded(
          child: Text(_error!,
              style: TextStyle(fontSize: 11, color: AppColors.error, height: 1.4)),
        ),
      ]),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(Sp.xl),
      child: Column(children: [
        Icon(LucideIcons.cpu, size: 40, color: AppColors.textLow.withValues(alpha: 0.5)),
        const SizedBox(height: 8),
        Text('اضغط "بدء" لعرض CPU / RAM / interfaces مباشرة',
            style: TextStyle(fontSize: 11, color: AppColors.textLow),
            textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _systemCards() {
    final s = _stats!;
    return Padding(
      padding: const EdgeInsets.all(Sp.md),
      child: Column(children: [
        // Board info banner
        Container(
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
        ),
        const SizedBox(height: 10),
        // 3 stat cards row
        Row(children: [
          Expanded(child: _metricCard(
            icon: LucideIcons.cpu,
            label: 'CPU',
            value: '${s.cpuLoad}',
            unit: '%',
            progress: s.cpuLoad / 100,
            color: _colorForPercent(s.cpuLoad.toDouble()),
          )),
          const SizedBox(width: 8),
          Expanded(child: _metricCard(
            icon: LucideIcons.memoryStick,
            label: 'RAM',
            value: '${s.memUsedPercent}',
            unit: '%',
            progress: s.memUsedPercent / 100,
            color: _colorForPercent(s.memUsedPercent.toDouble()),
          )),
          const SizedBox(width: 8),
          Expanded(child: _metricCard(
            icon: LucideIcons.clock,
            label: 'Uptime',
            value: _formatUptime(s.uptime),
            unit: '',
            progress: null,
            color: AppColors.brand,
          )),
        ]),
      ]),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required double? progress,
    required Color color,
  }) {
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
            Flexible(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textHi,
                  fontFamily: 'monospace',
                  height: 1,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 2),
              Text(unit, style: TextStyle(fontSize: 10, color: AppColors.textLow)),
            ],
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _interfacesSection() {
    final s = _stats!;
    if (s.interfaces.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Sp.md),
        child: Text('لا يوجد interfaces', style: TextStyle(fontSize: 11, color: AppColors.textLow)),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(Sp.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.network, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('Interfaces (${s.interfaces.length})',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('↑ ${s.upInterfacesCount}',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: const Color(0xFF10B981), fontFamily: 'monospace')),
          ),
          if (s.downInterfacesCount > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('↓ ${s.downInterfacesCount}',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: AppColors.error, fontFamily: 'monospace')),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        for (final iface in s.interfaces) _interfaceRow(iface),
      ]),
    );
  }

  Widget _interfaceRow(MikrotikInterface iface) {
    final color = iface.disabled
        ? AppColors.textLow
        : (iface.running ? const Color(0xFF10B981) : AppColors.error);
    final statusIcon = iface.disabled
        ? LucideIcons.circleOff
        : (iface.running ? LucideIcons.arrowUp : LucideIcons.arrowDown);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(statusIcon, size: 12, color: color),
        const SizedBox(width: 8),
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.surfaceInput,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(iface.type,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textMid)),
        ),
      ]),
    );
  }

  Color _colorForPercent(double p) {
    if (p >= 85) return AppColors.error;
    if (p >= 65) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  /// اختصار uptime string من Mikrotik: "3w2d15h4m5s" → "3و 2ي" أو "15س 4د"
  String _formatUptime(String raw) {
    if (raw.isEmpty) return '—';
    final weeks = RegExp(r'(\d+)w').firstMatch(raw)?.group(1);
    final days = RegExp(r'(\d+)d').firstMatch(raw)?.group(1);
    final hours = RegExp(r'(\d+)h').firstMatch(raw)?.group(1);
    final mins = RegExp(r'(\d+)m(?!s)').firstMatch(raw)?.group(1);
    if (weeks != null) return '${weeks}أ ${days ?? "0"}ي';
    if (days != null) return '${days}ي ${hours ?? "0"}س';
    if (hours != null) return '${hours}س ${mins ?? "0"}د';
    if (mins != null) return '${mins}د';
    return raw;
  }
}
