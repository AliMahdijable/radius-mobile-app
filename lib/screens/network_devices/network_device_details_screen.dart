import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/network_devices_api.dart';
import '../../models/network_device.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import 'network_device_form_sheet.dart';

/// شاشة تفاصيل جهاز — Slice 1 = عرض + زر فحص. Slice 2 يضيف
/// live monitoring (Mikrotik/UBNT/Mimosa API) + auto-refresh + graph.
class NetworkDeviceDetailsScreen extends StatefulWidget {
  final NetworkDevice device;
  const NetworkDeviceDetailsScreen({super.key, required this.device});

  @override
  State<NetworkDeviceDetailsScreen> createState() => _NetworkDeviceDetailsScreenState();
}

class _NetworkDeviceDetailsScreenState extends State<NetworkDeviceDetailsScreen> {
  late NetworkDevice _d;
  bool _probing = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _d = widget.device;
  }

  Future<void> _probe() async {
    setState(() => _probing = true);
    try {
      final r = await NetworkDevicesApi.localTcpProbe(
        ip: _d.ip,
        port: _d.port,
      );
      // احفظ النتيجة على السيرفر (لا نـawait — لا يهمّ لو فشل)
      NetworkDevicesApi.saveProbeResult(
        deviceId: _d.id,
        status: r.status,
        responseMs: r.responseMs,
      );
      if (!mounted) return;
      // حدّث حالة الجهاز محلّياً
      setState(() {
        _d = NetworkDevice(
          id: _d.id,
          adminId: _d.adminId,
          regionId: _d.regionId,
          name: _d.name,
          type: _d.type,
          brand: _d.brand,
          model: _d.model,
          ip: _d.ip,
          port: _d.port,
          apiPort: _d.apiPort,
          protocol: _d.protocol,
          mac: _d.mac,
          location: _d.location,
          notes: _d.notes,
          hasCredentials: _d.hasCredentials,
          lastProbedAt: DateTime.now(),
          lastStatus: r.status,
          lastResponseMs: r.responseMs,
          createdAt: _d.createdAt,
        );
        _probing = false;
        _changed = true;
      });
      HapticFeedback.lightImpact();
      final color = r.status == 'online' ? Colors.green : Colors.red;
      final msg = r.status == 'online'
          ? '🟢 online (${r.responseMs}ms)'
          : '🔴 offline';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _probing = false);
    }
  }

  Future<void> _edit() async {
    final updated = await showModalBottomSheet<NetworkDevice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NetworkDeviceFormSheet(existing: _d),
    );
    if (updated != null) {
      setState(() { _d = updated; _changed = true; });
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الجهاز'),
        content: Text('هل أنت متأكّد من حذف "${_d.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الحذف: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Color _statusColor() {
    return switch (_d.lastStatus) {
      'online' => const Color(0xFF10B981),
      'offline' => const Color(0xFFEF4444),
      _ => const Color(0xFF9CA3AF),
    };
  }

  String _statusText() {
    return switch (_d.lastStatus) {
      'online' => '🟢 متّصل',
      'offline' => '🔴 غير متّصل',
      _ => '⚪ لم يُفحص بعد',
    };
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '—';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'منذ ${diff.inSeconds} ثانية';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return 'منذ ${diff.inDays} يوم';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _changed) {
          // signal parent list to reload — handled by pop(true) if needed
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_d.name, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(icon: const Icon(LucideIcons.pencil, size: 20), onPressed: _edit),
            IconButton(icon: const Icon(LucideIcons.trash2, size: 20, color: Colors.red), onPressed: _delete),
          ],
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowRight),
            onPressed: () => Navigator.pop(context, _changed),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(Sp.md),
          children: [
            // Status hero
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _statusColor().withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _statusColor().withValues(alpha: 0.3), width: 1.5),
              ),
              child: Column(
                children: [
                  Text(_statusText(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _statusColor())),
                  const SizedBox(height: 6),
                  if (_d.lastResponseMs != null)
                    Text('زمن الاستجابة: ${_d.lastResponseMs} ms',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text('آخر فحص: ${_timeAgo(_d.lastProbedAt)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _probing ? null : _probe,
                      icon: _probing
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(LucideIcons.zap, size: 18),
                      label: Text(_probing ? 'جاري الفحص…' : 'فحص الآن (TCP)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ℹ️ يجب أن يكون الموبايل على نفس شبكة الجهاز',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Info
            _infoCard('معلومات الجهاز', [
              _infoRow(LucideIcons.tag, 'البراند', NetworkDeviceLabels.brandLabel(_d.brand)),
              _infoRow(LucideIcons.circuitBoard, 'النوع', NetworkDeviceLabels.typeLabel(_d.type)),
              if (_d.model != null && _d.model!.isNotEmpty)
                _infoRow(LucideIcons.info, 'الموديل', _d.model!),
              _infoRow(LucideIcons.globe, 'عنوان IP', _d.ip),
              _infoRow(LucideIcons.plug, 'المنفذ', _d.port.toString()),
              if (_d.mac != null && _d.mac!.isNotEmpty)
                _infoRow(LucideIcons.fingerprint, 'MAC', _d.mac!),
              if (_d.location != null && _d.location!.isNotEmpty)
                _infoRow(LucideIcons.mapPin, 'الموقع', _d.location!),
            ]),
            if (_d.notes != null && _d.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _infoCard('ملاحظات', [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_d.notes!, style: const TextStyle(fontSize: 13)),
                ),
              ]),
            ],
            const SizedBox(height: 20),
            Text(
              'المرحلة القادمة ستضيف: مراقبة interfaces + traffic + CPU + reboot (Mikrotik/UBNT/Mimosa)',
              style: TextStyle(fontSize: 10, color: Colors.grey.withValues(alpha: 0.7)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(title,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 13, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
