import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/mikrotik_api.dart';
import '../../api/mimosa_api.dart';
import '../../api/network_devices_api.dart';
import '../../api/ubnt_api.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../models/device_region.dart';
import '../../models/network_device.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import 'network_device_form_sheet.dart';
import 'widgets/brand_badge.dart';
import 'widgets/airfiber60_live_panel.dart';
import 'widgets/mikrotik_live_panel.dart';
import 'widgets/mimosa_live_panel.dart';
import 'widgets/ruijie_live_panel.dart';
import 'widgets/ubnt_live_panel.dart';

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
  State<NetworkDeviceDetailsScreen> createState() =>
      _NetworkDeviceDetailsScreenState();
}

class _NetworkDeviceDetailsScreenState extends State<NetworkDeviceDetailsScreen>
    with SingleTickerProviderStateMixin {
  late NetworkDevice _d;
  bool _probing = false;
  bool _changed = false;
  bool _rebooting = false; // spinner على زرّ reboot
  double? _lastPacketLoss;
  DeviceRegion? _region; // يُحمَّل asynchronously — لعرض اسم/لون المنطقة

  /// runtime override — لو UbntLivePanel اكتشف الجهاز فعلاً airFiber 60
  /// (رغم أن model حقلها ما فيه AF-60)، نبدّل تلقائياً للـAirFiber60LivePanel.
  /// 2026-08-18.
  bool _af60RuntimeDetected = false;

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
    );
    // pulse فقط لو الجهاز online — لأنّه animation مستمرّ (كل frame = rebuild)
    // ولا معنى للـpulse على جهاز offline. سنُعيد تشغيله لو تغيّرت الحالة.
    if (_d.lastStatus == 'online') _pulseCtrl.repeat();
    // نضيف الحالة الحاليّة كأوّل نقطة لو معروفة
    if (_d.lastResponseMs != null) {
      _history.add(_PingSample(
        at: _d.lastProbedAt ?? DateTime.now(),
        ms: _d.lastResponseMs,
        online: _d.lastStatus == 'online',
      ));
    }
    // اجلب معلومات المنطقة لو الجهاز مُسند لواحدة (يعرض الاسم في الهيرو).
    _loadRegionInfo();
    // Auto-ping فور فتح الشاشة — يضمن أن الحالة المعروضة حقيقيّة الآن
    // (وليس آخر ping ناجح قديم لمّا كان المدير داخل الشبكة).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _probe();
    });
  }

  Future<void> _loadRegionInfo() async {
    if (_d.regionId == null) return;
    try {
      final list = await NetworkDevicesApi.listRegions();
      if (!mounted) return;
      DeviceRegion? found;
      for (final x in list) {
        if (x.id == _d.regionId) {
          found = x;
          break;
        }
      }
      if (found != null) setState(() => _region = found);
    } catch (_) {}
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
      // TCP probe (أدقّ من ICMP على iOS)
      final r = await NetworkDevicesApi.localIcmpPing(
        ip: _d.ip,
        tcpPort: _d.apiPort ?? _d.port,
      );
      NetworkDevicesApi.saveProbeResult(
        deviceId: _d.id,
        status: r.status,
        responseMs: r.responseMs,
      );
      if (!mounted) return;
      setState(() {
        _d = _d.copyWith(
          lastProbedAt: DateTime.now(),
          lastStatus: r.status,
          lastResponseMs: r.responseMs,
        );
        _lastPacketLoss = r.packetLoss;
        _history.add(_PingSample(
            at: DateTime.now(),
            ms: r.responseMs,
            online: r.status == 'online'));
        if (_history.length > 10) _history.removeAt(0);
        _probing = false;
        _changed = true;
      });
      // بدّل pulse حسب الحالة — ما يشتغل عبثاً على offline
      if (r.status == 'online' && !_pulseCtrl.isAnimating) {
        _pulseCtrl.repeat();
      } else if (r.status != 'online' && _pulseCtrl.isAnimating) {
        _pulseCtrl.stop();
      }
      HapticFeedback.selectionClick();
    } catch (_) {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _edit() async {
    final updated = await showModalBottomSheet<NetworkDevice>(
      barrierColor: AppColors.scrim,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NetworkDeviceFormSheet(existing: _d),
    );
    if (updated != null)
      setState(() {
        _d = updated;
        _changed = true;
      });
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(LucideIcons.trash2, color: AppColors.error, size: 32),
        title: const Text('حذف الجهاز'),
        content: Text(
            'سيُحذف "${_d.name}" نهائياً.\nهذا الإجراء لا يمكن التراجع عنه.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
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
        'online' => AppColors.success,
        'offline' => AppColors.error,
        _ => AppColors.textLow,
      };

  /// هل reboot متاح لهذا الجهاز؟
  /// - يتطلّب صلاحيّة devices.manage (2026-08-18)
  /// - Mikrotik + api → نعم (Binary API 8728)
  /// - UBNT + api → نعم (SSH 22)
  /// - Mimosa → لا (SSH مقفول، SNMP SET غير موثّق)
  /// - أي جهاز بلا credentials → لا
  bool _canReboot() {
    if (!Perms.has('devices.manage')) return false;
    if (!_d.hasCredentials) return false;
    if (_d.protocol != 'api' && _d.protocol != 'ssh') return false;
    return _d.brand == 'mikrotik' || _d.brand == 'ubnt';
  }

  /// dialog تأكيد + spinner + snackbar للنجاح/الفشل.
  Future<void> _confirmAndReboot() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(LucideIcons.power, color: AppColors.warning, size: 32),
        title: const Text('إعادة تشغيل الجهاز'),
        content: Text(
          'سيُعاد تشغيل "${_d.name}" الآن.\n'
          'الجهاز سيكون غير متاح لمدة 1-2 دقيقة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            icon: const Icon(LucideIcons.power, size: 16),
            label: const Text('إعادة تشغيل'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _rebooting = true);
    HapticFeedback.mediumImpact();
    try {
      final creds = await NetworkDevicesApi.getCredentials(_d.id);
      final user = (creds['user'] ?? '').toString();
      final pass = (creds['pass'] ?? '').toString();

      switch (_d.brand) {
        case 'mikrotik':
          await MikrotikApi.rebootDevice(
            ip: _d.ip,
            port: _d.apiPort ?? 8728,
            user: user,
            pass: pass,
          );
          break;
        case 'ubnt':
          await UbntApi.rebootDevice(
            ip: _d.ip,
            port: _d.apiPort ?? 22,
            user: user,
            pass: pass,
          );
          break;
        default:
          throw Exception('البراند ${_d.brand} غير مدعوم للـreboot');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(LucideIcons.check, color: AppColors.onBrand, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  'تمّ إرسال reboot لـ${_d.name} — الجهاز يعيد التشغيل الآن')),
        ]),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      final msg = e is MikrotikException
          ? e.message
          : e is UbntException
              ? e.message
              : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(LucideIcons.circleAlert,
              color: AppColors.onBrand, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('فشل reboot: $msg')),
        ]),
        backgroundColor: AppColors.errorFill,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _rebooting = false);
    }
  }

  IconData _protocolIcon(String p) => switch (p) {
        'api' => LucideIcons.globe,
        'ssh' => LucideIcons.terminal,
        'telnet' => LucideIcons.monitor,
        'snmp' => LucideIcons.activity,
        _ => LucideIcons.plug,
      };

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
          // Reboot — يظهر فقط للأجهزة الي عندها credentials وبروتوكول مدعوم
          if (_canReboot())
            IconButton(
              icon: _rebooting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(LucideIcons.power, size: 18, color: AppColors.warning),
              tooltip: 'إعادة تشغيل الجهاز',
              onPressed: _rebooting ? null : _confirmAndReboot,
            ),
          if (Perms.has('devices.manage')) ...[
            IconButton(
                icon: const Icon(LucideIcons.pencil, size: 18),
                onPressed: _edit),
            IconButton(
                icon:
                    Icon(LucideIcons.trash2, size: 18, color: AppColors.error),
                onPressed: _delete),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Sp.md),
        children: [
          _heroCard(),
          const SizedBox(height: Sp.md),
          _statsRow(),
          // ICMP sparkline log أُزيل (2026-08-11) — لا فائدة عمليّة له
          // Live Panels حسب البراند — تحتاج devices.monitor (2026-08-18).
          // الـview-only يشوف كارت hint بدل الـpanel.
          if (Perms.has('devices.monitor')) ...[
            if (_d.brand == 'mikrotik') ...[
              const SizedBox(height: Sp.md),
              if (_d.protocol == 'api' && _d.hasCredentials)
                MikrotikLivePanel(device: _d)
              else
                _mikrotikHint(),
            ] else if (_d.brand == 'ubnt') ...[
              const SizedBox(height: Sp.md),
              if (_d.protocol == 'api' && _d.hasCredentials)
                // 2026-08-18: نستعمل static detection من model + runtime
                // detection من stats — الاثنين معاً يضمنان route صحيح
                // للأجهزة الي model حقلها ما مضبوطة كـAF-60.
                (_isAirFiber60(_d) || _af60RuntimeDetected)
                    ? AirFiber60LivePanel(device: _d)
                    : UbntLivePanel(
                        device: _d,
                        onAirFiber60Detected: () {
                          if (mounted && !_af60RuntimeDetected) {
                            setState(() => _af60RuntimeDetected = true);
                          }
                        },
                      )
              else
                _ubntHint(),
            ] else if (_d.brand == 'mimosa') ...[
              const SizedBox(height: Sp.md),
              if (_d.protocol == 'snmp' && _d.hasCredentials)
                MimosaLivePanel(device: _d)
              else
                _mimosaHint(),
            ] else if (_d.brand == 'ruijie') ...[
              const SizedBox(height: Sp.md),
              if (_d.protocol == 'snmp' && _d.hasCredentials)
                RuijieLivePanel(device: _d)
              else
                _ruijieHint(),
            ],
          ] else if ({'mikrotik', 'ubnt', 'mimosa', 'ruijie'}
              .contains(_d.brand)) ...[
            const SizedBox(height: Sp.md),
            _noMonitorPermHint(),
          ],
          // معلومات الجهاز + protocol انتقلا للـhero card (2026-08-12)
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
        borderRadius: BorderRadius.circular(R.card),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.brandSoftBg,
            AppColors.brand.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(Sp.lg),
      child: Column(children: [
        Row(children: [
          // Big brand badge with type icon corner + pulse ring
          Stack(clipBehavior: Clip.none, children: [
            BrandBadge(brand: _d.brand, size: 64),
            // Pulse ring when online
            if (online)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) {
                      final t = _pulseCtrl.value;
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16 + 6 * t),
                          border: Border.all(
                            color:
                                _statusColor.withValues(alpha: (1 - t) * 0.5),
                            width: 2,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            // Type icon (router/switch/link/sector) في زاوية علوى — يوضّح النوع
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border, width: 1.5),
                ),
                child:
                    TypeIcon(type: _d.type, size: 12, color: AppColors.textHi),
              ),
            ),
          ]),
          const SizedBox(width: Sp.md),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _pulseDot(online),
                const SizedBox(width: 6),
                Text(
                  online
                      ? 'متّصل'
                      : (_d.lastStatus == 'offline' ? 'غير متّصل' : 'لم يُفحص'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _statusColor,
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              // Type + Model على نفس السطر (لو model موجود)
              Row(children: [
                Text(
                  NetworkDeviceLabels.typeLabel(_d.type),
                  style: TextStyle(fontSize: 13, color: AppColors.textMid),
                ),
                if (_d.model != null && _d.model!.isNotEmpty) ...[
                  Text(' • ',
                      style: TextStyle(fontSize: 11, color: AppColors.textLow)),
                  Flexible(
                    child: Text(_d.model!,
                        style:
                            TextStyle(fontSize: 12.5, color: AppColors.textMid),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              // IP
              Row(children: [
                Icon(LucideIcons.globe, size: 12, color: AppColors.textLow),
                const SizedBox(width: 4),
                Text(_d.ip,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textHi,
                    )),
              ]),
              // Region (لو مُسند لواحدة) — 2026-08-18
              if (_region != null) ...[
                const SizedBox(height: 4),
                Builder(builder: (_) {
                  final color =
                      _parseRegionColorHex(_region!.color) ?? AppColors.brand;
                  return Row(children: [
                    Icon(LucideIcons.mapPin, size: 12, color: color),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border:
                            Border.all(color: color.withValues(alpha: 0.35)),
                      ),
                      child: Text(_region!.name,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: color)),
                    ),
                  ]);
                }),
              ],
              // Location (لو موجود)
              if (_d.location != null && _d.location!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  Icon(LucideIcons.building2,
                      size: 12, color: AppColors.textLow),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(_d.location!,
                        style:
                            TextStyle(fontSize: 11, color: AppColors.textMid),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ],
              // Protocol chip (لو محدَّد)
              if (_d.protocol != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.brandSoftBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_protocolIcon(_d.protocol!),
                          size: 10, color: AppColors.brand),
                      const SizedBox(width: 3),
                      Text(
                        '${NetworkDeviceLabels.protocolLabel(_d.protocol!)}${_d.apiPort != null ? ":${_d.apiPort}" : ""}',
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brand),
                      ),
                      if (_d.hasCredentials) ...[
                        const SizedBox(width: 4),
                        Icon(LucideIcons.keyRound,
                            size: 9, color: AppColors.success),
                      ],
                    ]),
                  ),
                ]),
              ],
            ]),
          ),
          // Response time + compact ICMP ping button
          Column(mainAxisSize: MainAxisSize.min, children: [
            if (online && _d.lastResponseMs != null) ...[
              Text(
                '${_d.lastResponseMs}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: _statusColor,
                  height: 1,
                ),
              ),
              Text('ms',
                  style: TextStyle(fontSize: 9.5, color: AppColors.textMid)),
              const SizedBox(height: 6),
            ],
            // زر ICMP مدمج — icon فقط
            InkWell(
              onTap: _probing ? null : _probe,
              borderRadius: BorderRadius.circular(R.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.brandSoftBg,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: _probing
                    ? SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: AppColors.brand))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(LucideIcons.zap, size: 11, color: AppColors.brand),
                        const SizedBox(width: 3),
                        Text('ping',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
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
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle),
      );
    }
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) {
        final t = _pulseCtrl.value;
        return Stack(alignment: Alignment.center, children: [
          Container(
            width: 8 + 6 * t,
            height: 8 + 6 * t,
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: (1 - t) * 0.4),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: _statusColor, shape: BoxShape.circle),
          ),
        ]);
      },
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Stats row — 3 stat cards (ping avg / packet loss / آخر فحص)
  // ══════════════════════════════════════════════════════════════
  Widget _statsRow() {
    final times =
        _history.where((h) => h.ms != null).map((h) => h.ms!).toList();
    final avg = times.isEmpty
        ? null
        : (times.reduce((a, b) => a + b) / times.length).round();
    final min = times.isEmpty ? null : times.reduce(math.min);
    final max = times.isEmpty ? null : times.reduce(math.max);

    return Row(children: [
      Expanded(
          child: _statCard(
        icon: LucideIcons.zap,
        label: 'المتوسّط',
        value: avg == null ? '—' : '$avg',
        unit: avg == null ? '' : 'ms',
        color: AppColors.brand,
      )),
      const SizedBox(width: 8),
      Expanded(
          child: _statCard(
        icon: LucideIcons.chartLine,
        label: 'الأدنى/الأقصى',
        value: (min == null || max == null) ? '—' : '$min/$max',
        unit: '',
        color: AppColors.info,
      )),
      const SizedBox(width: 8),
      Expanded(
          child: _statCard(
        icon: LucideIcons.packageX,
        label: 'فقدان الحزم',
        value: _lastPacketLoss == null ? '—' : '${_lastPacketLoss!.toInt()}',
        unit: _lastPacketLoss == null ? '' : '%',
        color: _lastPacketLoss != null && _lastPacketLoss! > 0
            ? AppColors.error
            : AppColors.success,
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
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMid),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textHi,
                height: 1,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(unit,
                  style: TextStyle(fontSize: 10.5, color: AppColors.textLow)),
            ],
          ],
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
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.stickyNote, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('ملاحظات',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textHi,
              )),
        ]),
        const SizedBox(height: 8),
        Text(_d.notes!,
            style: TextStyle(
                fontSize: 12.5, color: AppColors.textMid, height: 1.6)),
      ]),
    );
  }
}

/// airFiber 60 يُكتشف من model أو name — المستخدم يكتب أي variation:
/// "airFiber 60 LR" / "AF-60-LR" / "LR 60" / "60 GP" / "GP60" ...
/// نبحث في الحقلين معاً لتغطية كل الحالات.
///
/// 2026-08-18: نستثني موديلات AF-60-XG (5 GHz — مو 60 GHz) — كانت
/// `af60` تُطابقها بالخطأ. نتحقّق من variants الـ60 GHz الحقيقيّة:
/// LR / XR / XG (raw) لا / gp.
bool _isAirFiber60(NetworkDevice d) {
  final combined = '${d.model ?? ''} ${d.name}'.toLowerCase();
  if (combined.trim().isEmpty) return false;
  // Explicit 60 GHz mentions
  if (combined.contains('60ghz') || combined.contains('60 ghz')) return true;
  if (combined.contains('airfiber 60') || combined.contains('airfiber60'))
    return true;
  // AF-60 variants — لكن ليس AF-60-XG (5GHz backhaul)
  final af60Match =
      RegExp(r'af[\s-]?60[\s-]?(lr|xr|gp|lite)?\b').firstMatch(combined);
  if (af60Match != null) {
    // إذا كان جزء من "af-60-xg" → false
    if (combined.contains('af-60-xg') ||
        combined.contains('af60-xg') ||
        combined.contains('af 60 xg')) return false;
    return true;
  }
  // Suffix variants: "LR 60" / "60 LR" / "gp 60" / "60 gp"
  if (RegExp(r'\b(lr|xr|gp)\s?60\b').hasMatch(combined)) return true;
  if (RegExp(r'\b60\s?(lr|xr|gp)\b').hasMatch(combined)) return true;
  return false;
}

extension _UbntHint on _NetworkDeviceDetailsScreenState {
  Widget _ubntHint() {
    final needsApi = _d.protocol != 'api';
    final needsCreds = _d.protocol == 'api' && !_d.hasCredentials;
    final msg = needsApi
        ? 'اختر بروتوكول API + أدخل user/password للـUBNT لعرض signal + throughput + stations'
        : (needsCreds
            ? 'أدخل user/password لعرض المراقبة الحيّة (default: ubnt/ubnt)'
            : '');
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.brandAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.brandAccent.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.brandAccent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Icon(LucideIcons.radioTower,
              color: AppColors.brandAccent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مراقبة UBNT airOS متوفّرة',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHi)),
            const SizedBox(height: 4),
            Text(msg,
                style: TextStyle(
                    fontSize: 11, color: AppColors.textMid, height: 1.4)),
          ]),
        ),
        IconButton(
          icon: Icon(LucideIcons.pencil, size: 18, color: AppColors.brand),
          onPressed: _edit,
        ),
      ]),
    );
  }

  /// كارت مختصر لموظّف بدون صلاحيّة devices.monitor — يوضّح إنّ Live Panel
  /// يحتاج إذن، بدلاً من إخفاء الصف كاملاً (المستخدم قد يظنّ إنّ الميزة عاطلة).
  Widget _noMonitorPermHint() {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.textLow.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.textLow.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Icon(LucideIcons.lock, color: AppColors.textMid, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('المراقبة الحيّة مقفلة',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHi)),
            const SizedBox(height: 4),
            Text('تحتاج صلاحيّة "مراقبة Live" — راجع المدير.',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textMid, height: 1.4)),
          ]),
        ),
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
        : (needsCreds
            ? 'أدخل user/password للراوتر لتفعيل المراقبة الحيّة'
            : '');
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Icon(LucideIcons.zap, color: AppColors.info, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مراقبة حيّة متوفّرة لـMikrotik',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHi)),
            const SizedBox(height: 4),
            Text(msg,
                style: TextStyle(
                    fontSize: 11, color: AppColors.textMid, height: 1.4)),
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

extension _MimosaHint on _NetworkDeviceDetailsScreenState {
  Widget _mimosaHint() {
    final needsSnmp = _d.protocol != 'snmp';
    final needsCreds = _d.protocol == 'snmp' && !_d.hasCredentials;
    final msg = needsSnmp
        ? 'اختر بروتوكول SNMP + أدخل الـcommunity string (في حقل كلمة المرور) لعرض signal + throughput + margin.\n'
            'Mimosa يعطّل SSH/Telnet بشكل نهائي — SNMP هو الخيار الوحيد.'
        : (needsCreds
            ? 'أدخل SNMP community string (default: public). '
                'فعّل SNMP من web UI للجهاز: Preferences → Management → SNMP.'
            : '');
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Center(
            child: Text('M',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مراقبة Mimosa عبر SNMP',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHi)),
            const SizedBox(height: 4),
            Text(msg,
                style: TextStyle(
                    fontSize: 11, color: AppColors.textMid, height: 1.4)),
          ]),
        ),
        IconButton(
          icon: Icon(LucideIcons.pencil, size: 18, color: AppColors.brand),
          onPressed: _edit,
        ),
      ]),
    );
  }
}

extension _RuijieHint on _NetworkDeviceDetailsScreenState {
  Widget _ruijieHint() {
    final needsSnmp = _d.protocol != 'snmp';
    final needsCreds = _d.protocol == 'snmp' && !_d.hasCredentials;
    final msg = needsSnmp
        ? 'اختر بروتوكول SNMP + أدخل الـcommunity string (في حقل كلمة المرور).\n'
            'Ruijie/Reyee: فعّل SNMP من web UI (Advanced → Basics → SNMP) وأنشئ Read Community.'
        : (needsCreds
            ? 'أدخل SNMP community string. '
                'أنشئه من Reyee web UI: Advanced → Basics → SNMP → أضف Community مع صلاحية Read.'
            : '');
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.brandAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(R.lg),
        border:
            Border.all(color: AppColors.brandAccent.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.brandAccent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Center(
            child: Text('R',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandAccent)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مراقبة Ruijie / Reyee عبر SNMP',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHi)),
            const SizedBox(height: 4),
            Text(msg,
                style: TextStyle(
                    fontSize: 11, color: AppColors.textMid, height: 1.4)),
          ]),
        ),
        IconButton(
          icon: Icon(LucideIcons.pencil, size: 18, color: AppColors.brand),
          onPressed: _edit,
        ),
      ]),
    );
  }
}

class _PingSample {
  final DateTime at;
  final int? ms;
  final bool online;
  const _PingSample({required this.at, this.ms, required this.online});
}

/// نفس منطق _parseRegionColor في الشاشات الأخرى — top-level helper.
Color? _parseRegionColorHex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final s = hex.startsWith('#') ? hex.substring(1) : hex;
  final n = int.tryParse(s, radix: 16);
  if (n == null) return null;
  return Color(0xFF000000 | n);
}
