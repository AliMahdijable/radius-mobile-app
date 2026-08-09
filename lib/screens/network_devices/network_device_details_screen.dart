import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/network_devices_api.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../models/network_device.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import 'network_device_form_sheet.dart';
import 'widgets/mikrotik_live_panel.dart';

/// شاشة تفاصيل جهاز — تصميم متقدّم:
/// - Hero card بـpulse للـonline + brand icon + stats
/// - Ping section مع sparkline لآخر 10 فحوصات
/// - Info grid منظّم
/// - Protocol/credentials info
/// - Placeholder cards لـSlice 2 (interfaces + traffic + reboot)
class NetworkDeviceDetailsScreen extends StatefulWidget {
  final NetworkDevice device;
  const NetworkDeviceDetailsScreen({super.key, required this.device});

  @override
  State<NetworkDeviceDetailsScreen> createState() => _NetworkDeviceDetailsScreenState();
}

class _NetworkDeviceDetailsScreenState extends State<NetworkDeviceDetailsScreen>
    with SingleTickerProviderStateMixin {
  late NetworkDevice _d;
  bool _probing = false;
  bool _changed = false;
  double? _lastPacketLoss;

  /// آخر 10 قراءات ping — للـsparkline
  final List<_PingSample> _history = [];

  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _d = widget.device;
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    // نضيف الحالة الحاليّة كأوّل نقطة لو معروفة
    if (_d.lastResponseMs != null) {
      _history.add(_PingSample(
        at: _d.lastProbedAt ?? DateTime.now(),
        ms: _d.lastResponseMs,
        online: _d.lastStatus == 'online',
      ));
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    if (_probing) return;
    setState(() => _probing = true);
    try {
      final r = await NetworkDevicesApi.localIcmpPing(ip: _d.ip);
      NetworkDevicesApi.saveProbeResult(
        deviceId: _d.id,
        status: r.status,
        responseMs: r.responseMs,
      );
      if (!mounted) return;
      setState(() {
        _d = NetworkDevice(
          id: _d.id, adminId: _d.adminId, regionId: _d.regionId,
          name: _d.name, type: _d.type, brand: _d.brand, model: _d.model,
          ip: _d.ip, port: _d.port, apiPort: _d.apiPort, protocol: _d.protocol,
          mac: _d.mac, location: _d.location, notes: _d.notes,
          hasCredentials: _d.hasCredentials,
          lastProbedAt: DateTime.now(),
          lastStatus: r.status,
          lastResponseMs: r.responseMs,
          createdAt: _d.createdAt,
        );
        _lastPacketLoss = r.packetLoss;
        _history.add(_PingSample(at: DateTime.now(), ms: r.responseMs, online: r.status == 'online'));
        if (_history.length > 10) _history.removeAt(0);
        _probing = false;
        _changed = true;
      });
      HapticFeedback.selectionClick();
    } catch (_) {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _edit() async {
    final updated = await showModalBottomSheet<NetworkDevice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NetworkDeviceFormSheet(existing: _d),
    );
    if (updated != null) setState(() { _d = updated; _changed = true; });
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(LucideIcons.trash2, color: AppColors.error, size: 32),
        title: const Text('حذف الجهاز'),
        content: Text('سيُحذف "${_d.name}" نهائياً.\nهذا الإجراء لا يمكن التراجع عنه.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            icon: const Icon(LucideIcons.trash2, size: 16),
            label: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await NetworkDevicesApi.delete(_d.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showSheetSnack(context, 'فشل الحذف: $e', isError: true);
    }
  }

  Color get _statusColor => switch (_d.lastStatus) {
        'online' => const Color(0xFF10B981),
        'offline' => AppColors.error,
        _ => AppColors.textLow,
      };

  IconData get _typeIcon => switch (_d.type) {
        'link' => LucideIcons.satellite,
        'switch' => LucideIcons.network,
        'sector' => LucideIcons.radioTower,
        'router' => LucideIcons.router,
        'ap' => LucideIcons.wifi,
        'camera' => LucideIcons.video,
        _ => LucideIcons.circuitBoard,
      };

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '—';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 10) return 'الآن';
    if (diff.inSeconds < 60) return 'منذ ${diff.inSeconds}ث';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes}د';
    if (diff.inHours < 24) return 'منذ ${diff.inHours}س';
    return 'منذ ${diff.inDays}ي';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(_d.name, overflow: TextOverflow.ellipsis),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textHi,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowRight),
          onPressed: () => Navigator.pop(context, _changed),
        ),
        actions: [
          IconButton(icon: const Icon(LucideIcons.pencil, size: 18), onPressed: _edit),
          IconButton(icon: Icon(LucideIcons.trash2, size: 18, color: AppColors.error), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Sp.md),
        children: [
          _heroCard(),
          const SizedBox(height: Sp.md),
          _statsRow(),
          const SizedBox(height: Sp.md),
          _pingSection(),
          // Mikrotik Live Panel — يظهر لأجهزة Mikrotik مع API + credentials.
          // لو ناقص شرط: نعرض hint واضح للمستخدم بما ينقص.
          if (_d.brand == 'mikrotik') ...[
            const SizedBox(height: Sp.md),
            if (_d.protocol == 'api' && _d.hasCredentials)
              MikrotikLivePanel(device: _d)
            else
              _mikrotikHint(),
          ],
          const SizedBox(height: Sp.md),
          _infoGrid(),
          if (_d.protocol != null) ...[
            const SizedBox(height: Sp.md),
            _protocolCard(),
          ],
          if (_d.notes != null && _d.notes!.isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            _notesCard(),
          ],
          const SizedBox(height: Sp.xl),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Hero card — الأيقونة + الاسم + IP + status hero + pulse
  // ══════════════════════════════════════════════════════════════
  Widget _heroCard() {
    final online = _d.lastStatus == 'online';
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.brand.withValues(alpha: 0.08),
            AppColors.brand.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(Sp.lg),
      child: Column(children: [
        Row(children: [
          // Big icon with brand corner badge
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(_typeIcon, color: AppColors.brand, size: 32),
            ),
            // Pulse ring when online
            if (online)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) {
                    final t = _pulseCtrl.value;
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16 + 6 * t),
                        border: Border.all(
                          color: _statusColor.withValues(alpha: (1 - t) * 0.5),
                          width: 2,
                        ),
                      ),
                    );
                  },
                ),
              ),
            // Brand badge (small chip on top-right)
            Positioned(
              top: -4, right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  NetworkDeviceLabels.brandLabel(_d.brand),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHi,
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _pulseDot(online),
                const SizedBox(width: 6),
                Text(
                  online ? 'متّصل' : (_d.lastStatus == 'offline' ? 'غير متّصل' : 'لم يُفحص'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _statusColor,
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                NetworkDeviceLabels.typeLabel(_d.type),
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMid,
                ),
              ),
              const SizedBox(height: 2),
              Row(children: [
                Icon(LucideIcons.globe, size: 12, color: AppColors.textLow),
                const SizedBox(width: 4),
                Text(
                  _d.ip,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHi,
                  ),
                ),
              ]),
            ]),
          ),
          // Response time + compact ICMP ping button
          Column(mainAxisSize: MainAxisSize.min, children: [
            if (online && _d.lastResponseMs != null) ...[
              Text(
                '${_d.lastResponseMs}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: _statusColor,
                  height: 1,
                  fontFamily: 'monospace',
                ),
              ),
              Text('ms', style: TextStyle(fontSize: 9, color: AppColors.textMid)),
              const SizedBox(height: 6),
            ],
            // زر ICMP مدمج — icon فقط
            InkWell(
              onTap: _probing ? null : _probe,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _probing
                    ? SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.brand))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(LucideIcons.zap, size: 11, color: AppColors.brand),
                        const SizedBox(width: 3),
                        Text('ping',
                            style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w700,
                              color: AppColors.brand,
                            )),
                      ]),
              ),
            ),
          ]),
        ]),
      ]),
    );
  }

  Widget _pulseDot(bool online) {
    if (!online) {
      return Container(
        width: 8, height: 8,
        decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle),
      );
    }
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) {
        final t = _pulseCtrl.value;
        return Stack(alignment: Alignment.center, children: [
          Container(
            width: 8 + 6 * t, height: 8 + 6 * t,
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: (1 - t) * 0.4),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle),
          ),
        ]);
      },
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Stats row — 3 stat cards (ping avg / packet loss / آخر فحص)
  // ══════════════════════════════════════════════════════════════
  Widget _statsRow() {
    final times = _history.where((h) => h.ms != null).map((h) => h.ms!).toList();
    final avg = times.isEmpty ? null : (times.reduce((a, b) => a + b) / times.length).round();
    final min = times.isEmpty ? null : times.reduce(math.min);
    final max = times.isEmpty ? null : times.reduce(math.max);

    return Row(children: [
      Expanded(child: _statCard(
        icon: LucideIcons.zap,
        label: 'المتوسّط',
        value: avg == null ? '—' : '$avg',
        unit: avg == null ? '' : 'ms',
        color: AppColors.brand,
      )),
      const SizedBox(width: 8),
      Expanded(child: _statCard(
        icon: LucideIcons.chartLine,
        label: 'الأدنى/الأقصى',
        value: (min == null || max == null) ? '—' : '$min/$max',
        unit: '',
        color: const Color(0xFF06B6D4),
      )),
      const SizedBox(width: 8),
      Expanded(child: _statCard(
        icon: LucideIcons.packageX,
        label: 'فقدان الحزم',
        value: _lastPacketLoss == null ? '—' : '${_lastPacketLoss!.toInt()}',
        unit: _lastPacketLoss == null ? '' : '%',
        color: _lastPacketLoss != null && _lastPacketLoss! > 0 ? AppColors.error : const Color(0xFF10B981),
      )),
    ]);
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textMid),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textHi,
                fontFamily: 'monospace',
                height: 1,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(unit, style: TextStyle(fontSize: 10, color: AppColors.textLow)),
            ],
          ],
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Ping mini section — sparkline + history dots فقط (بدون زر كبير).
  // زر الفحص انتقل لـHero card (compact).
  // ══════════════════════════════════════════════════════════════
  Widget _pingSection() {
    // لا نعرض شيء لو ما فيه history كافي — الـsparkline بلا نقاط غير مفيد
    if (_history.length < 2) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        Row(children: [
          Icon(LucideIcons.activity, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('سجلّ ICMP', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi)),
          const Spacer(),
          Text('آخر: ${_timeAgo(_d.lastProbedAt)}',
              style: TextStyle(fontSize: 10, color: AppColors.textLow)),
        ]),
        const SizedBox(height: 8),
        SizedBox(height: 40, child: _sparkline()),
        const SizedBox(height: 6),
        _historyDots(),
        const SizedBox(height: 2),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(LucideIcons.info, size: 9, color: AppColors.textLow),
          const SizedBox(width: 3),
          Text(
            'يجب أن يكون الموبايل على نفس شبكة الجهاز',
            style: TextStyle(fontSize: 9, color: AppColors.textLow),
          ),
        ]),
      ]),
    );
  }

  Widget _sparkline() {
    final spots = <FlSpot>[];
    for (int i = 0; i < _history.length; i++) {
      final ms = _history[i].ms?.toDouble() ?? 0;
      spots.add(FlSpot(i.toDouble(), ms));
    }
    final validMs = _history.where((h) => h.ms != null).map((h) => h.ms!).toList();
    final maxY = validMs.isEmpty ? 100.0 : (validMs.reduce(math.max) * 1.3);
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.brand,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3,
                color: _history[spot.x.toInt()].online
                    ? const Color(0xFF10B981) : AppColors.error,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.brand.withValues(alpha: 0.1),
            ),
          ),
        ],
        lineTouchData: const LineTouchData(enabled: false),
      ),
    );
  }

  Widget _historyDots() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (final sample in _history)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: sample.online ? const Color(0xFF10B981) : AppColors.error,
            shape: BoxShape.circle,
          ),
        ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════
  // Info grid — معلومات الجهاز بشكل grid منظّم
  // ══════════════════════════════════════════════════════════════
  Widget _infoGrid() {
    final items = <_InfoItem>[
      if (_d.model != null && _d.model!.isNotEmpty)
        _InfoItem(LucideIcons.info, 'الموديل', _d.model!),
      if (_d.mac != null && _d.mac!.isNotEmpty)
        _InfoItem(LucideIcons.fingerprint, 'MAC', _d.mac!),
      if (_d.location != null && _d.location!.isNotEmpty)
        _InfoItem(LucideIcons.mapPin, 'الموقع', _d.location!),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, 8),
          child: Row(children: [
            Icon(LucideIcons.info, size: 14, color: AppColors.brand),
            const SizedBox(width: 6),
            Text('معلومات الجهاز', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi,
            )),
          ]),
        ),
        const Divider(height: 1),
        for (int i = 0; i < items.length; i++) ...[
          _infoRow(items[i]),
          if (i < items.length - 1)
            Divider(height: 1, color: AppColors.border.withValues(alpha: 0.5), indent: 40),
        ],
      ]),
    );
  }

  Widget _infoRow(_InfoItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 12),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(item.icon, size: 14, color: AppColors.brand),
        ),
        const SizedBox(width: 10),
        Text(item.label, style: TextStyle(fontSize: 11, color: AppColors.textMid)),
        const Spacer(),
        Text(
          item.value,
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
            color: AppColors.textHi,
          ),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Protocol card
  // ══════════════════════════════════════════════════════════════
  Widget _protocolCard() {
    final protoIcon = switch (_d.protocol) {
      'api' => LucideIcons.globe,
      'ssh' => LucideIcons.terminal,
      'telnet' => LucideIcons.monitor,
      'snmp' => LucideIcons.activity,
      _ => LucideIcons.plug,
    };
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(protoIcon, size: 20, color: AppColors.brand),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              NetworkDeviceLabels.protocolLabel(_d.protocol!),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHi),
            ),
            const SizedBox(height: 2),
            Row(children: [
              Text('port ${_d.apiPort ?? "—"}',
                  style: TextStyle(fontSize: 11, color: AppColors.textMid, fontFamily: 'monospace')),
              if (_d.hasCredentials) ...[
                const SizedBox(width: 8),
                Icon(LucideIcons.keyRound, size: 11, color: const Color(0xFF10B981)),
                const SizedBox(width: 3),
                Text('credentials محفوظة',
                    style: TextStyle(fontSize: 10, color: const Color(0xFF10B981))),
              ],
            ]),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.textLow.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Slice 2',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textLow),
          ),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Notes card
  // ══════════════════════════════════════════════════════════════
  Widget _notesCard() {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.stickyNote, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('ملاحظات', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi,
          )),
        ]),
        const SizedBox(height: 8),
        Text(_d.notes!, style: TextStyle(fontSize: 12, color: AppColors.textMid, height: 1.6)),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Coming soon (Slice 2 preview)
  // ══════════════════════════════════════════════════════════════
  Widget _comingSoonCard() {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.brand.withValues(alpha: 0.05),
          AppColors.brand.withValues(alpha: 0.02),
        ]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.sparkles, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('قادم قريباً', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brand,
          )),
        ]),
        const SizedBox(height: 10),
        _comingItem(LucideIcons.wifi, 'UBNT + Mimosa API — signal + throughput + stations'),
        _comingItem(LucideIcons.chartLine, 'رسم بياني حيّ للـtraffic لكل interface (RX/TX Mbps)'),
        _comingItem(LucideIcons.zap, 'زر Reboot عن بُعد (للـMikrotik أولاً)'),
        _comingItem(LucideIcons.bellRing, 'تنبيهات (حرارة/CPU/فولتيّة) مع حدود مخصّصة'),
        _comingItem(LucideIcons.mapPin, 'تنظيم بالمناطق (regions) + bulk IP scan'),
      ]),
    );
  }

  Widget _comingItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 12, color: AppColors.textMid),
        const SizedBox(width: 6),
        Expanded(child: Text(
          text,
          style: TextStyle(fontSize: 11, color: AppColors.textMid, height: 1.4),
        )),
      ]),
    );
  }
}

extension _MikrotikHint on _NetworkDeviceDetailsScreenState {
  Widget _mikrotikHint() {
    final needsApi = _d.protocol != 'api';
    final needsCreds = _d.protocol == 'api' && !_d.hasCredentials;
    final msg = needsApi
        ? 'اختر بروتوكول API + أدخل user/password للراوتر لتفعيل المراقبة الحيّة (CPU/RAM/interfaces)'
        : (needsCreds ? 'أدخل user/password للراوتر لتفعيل المراقبة الحيّة' : '');
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: const Color(0xFF06B6D4).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF06B6D4).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(LucideIcons.zap, color: const Color(0xFF06B6D4), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مراقبة حيّة متوفّرة لـMikrotik',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi)),
            const SizedBox(height: 4),
            Text(msg, style: TextStyle(fontSize: 11, color: AppColors.textMid, height: 1.4)),
          ]),
        ),
        IconButton(
          icon: Icon(LucideIcons.pencil, size: 18, color: AppColors.brand),
          onPressed: _edit,
          tooltip: 'تعديل',
        ),
      ]),
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;
  const _InfoItem(this.icon, this.label, this.value);
}

class _PingSample {
  final DateTime at;
  final int? ms;
  final bool online;
  const _PingSample({required this.at, this.ms, required this.online});
}
