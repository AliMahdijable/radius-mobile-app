import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/device_alerts_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';

/// شاشة تنبيهات الأجهزة — تاريخ الـalerts + تحديد كمقروء + حذف.
///
/// **مصدر البيانات**: [DeviceAlertsService] (client-side فقط، لا سيرفر).
/// عند فتح الشاشة نُميّز كل الـalerts كمقروءة.
class DeviceAlertsScreen extends StatefulWidget {
  const DeviceAlertsScreen({super.key});

  @override
  State<DeviceAlertsScreen> createState() => _DeviceAlertsScreenState();
}

class _DeviceAlertsScreenState extends State<DeviceAlertsScreen> {
  @override
  void initState() {
    super.initState();
    // نميّز الكل كمقروء عند فتح الشاشة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeviceAlertsService.instance.markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final alerts = DeviceAlertsService.instance.all;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('تنبيهات الأجهزة'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textHi,
        actions: [
          if (alerts.isNotEmpty)
            IconButton(
              onPressed: _confirmClear,
              icon: Icon(LucideIcons.trash2, color: AppColors.error),
              tooltip: 'حذف الكلّ',
            ),
        ],
      ),
      body: alerts.isEmpty ? _empty() : _list(alerts),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.bellOff, size: 32, color: AppColors.brand),
          ),
          const SizedBox(height: Sp.md),
          Text('لا توجد تنبيهات',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800,
                  color: AppColors.textHi)),
          const SizedBox(height: 4),
          Text('التنبيهات تظهر هنا لو جهاز فصل أو عاد للاتصال',
              style: TextStyle(fontSize: 12, color: AppColors.textMid),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _list(List<DeviceAlert> alerts) {
    return ListView.separated(
      padding: const EdgeInsets.all(Sp.md),
      itemCount: alerts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) => _alertRow(alerts[i]),
    );
  }

  Widget _alertRow(DeviceAlert a) {
    final isOffline = a.kind == DeviceAlertKind.offline;
    final color = isOffline ? AppColors.error : const Color(0xFF10B981);
    final icon = isOffline ? LucideIcons.wifiOff : LucideIcons.wifi;
    final label = isOffline ? 'فصل عن الشبكة' : 'عاد للاتصال';
    return Dismissible(
      key: ValueKey(a.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(LucideIcons.trash2, color: AppColors.error),
      ),
      direction: DismissDirection.endToStart,
      onDismissed: (_) async {
        await DeviceAlertsService.instance.dismiss(a.id);
        if (mounted) setState(() {});  // إعادة بناء بعد الحذف
      },
      child: Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(a.deviceName,
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800,
                          color: AppColors.textHi),
                      overflow: TextOverflow.ellipsis),
                ),
                Text(_formatTime(a.at),
                    style: TextStyle(fontSize: 10, color: AppColors.textLow)),
              ]),
              const SizedBox(height: 2),
              Text('$label · ${a.deviceIp}',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: color)),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف كل التنبيهات؟'),
        content: const Text('لا يمكن التراجع.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('حذف الكلّ')),
        ],
      ),
    );
    if (ok == true) {
      await DeviceAlertsService.instance.clear();
      if (mounted) setState(() {});
    }
  }

  String _formatTime(DateTime at) {
    final now = DateTime.now();
    final diff = now.difference(at);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes}د';
    if (diff.inHours < 24) return 'قبل ${diff.inHours}س';
    if (diff.inDays < 7) return 'قبل ${diff.inDays}ي';
    return '${at.day}/${at.month}';
  }
}
