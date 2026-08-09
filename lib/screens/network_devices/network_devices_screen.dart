import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/network_devices_api.dart';
import '../../models/network_device.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import 'network_device_details_screen.dart';
import 'network_device_form_sheet.dart';

/// قائمة أجهزة الشبكة (Slice 1). راجع project_devices_monitoring_plan.
class NetworkDevicesScreen extends StatefulWidget {
  const NetworkDevicesScreen({super.key});

  @override
  State<NetworkDevicesScreen> createState() => _NetworkDevicesScreenState();
}

class _NetworkDevicesScreenState extends State<NetworkDevicesScreen> {
  List<NetworkDevice> _all = [];
  bool _loading = true;
  String? _error;
  String? _brandFilter;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await NetworkDevicesApi.list();
      if (!mounted) return;
      setState(() { _all = rows; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'فشل التحميل: $e'; _loading = false; });
    }
  }

  Future<void> _openForm({NetworkDevice? existing}) async {
    final result = await showModalBottomSheet<NetworkDevice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NetworkDeviceFormSheet(existing: existing),
    );
    if (result != null) _load();
  }

  Future<void> _openDetails(NetworkDevice d) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NetworkDeviceDetailsScreen(device: d)),
    );
    if (changed == true) _load();
  }

  List<NetworkDevice> get _filtered {
    return _all.where((d) {
      if (_brandFilter != null && d.brand != _brandFilter) return false;
      if (_statusFilter != null && d.lastStatus != _statusFilter) return false;
      return true;
    }).toList();
  }

  Widget _statusDot(String status) {
    final color = switch (status) {
      'online' => const Color(0xFF10B981),
      'offline' => const Color(0xFFEF4444),
      _ => const Color(0xFF9CA3AF),
    };
    return Container(
      width: 10, height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  IconData _brandIcon(String brand) {
    return switch (brand) {
      'mikrotik' || 'cisco' => LucideIcons.router,
      'ubnt' || 'mimosa' => LucideIcons.wifi,
      'roji' => LucideIcons.serverCog,
      _ => LucideIcons.circuitBoard,
    };
  }

  Color _brandColor(String brand) {
    return switch (brand) {
      'mikrotik' => const Color(0xFF3B82F6),
      'ubnt' => const Color(0xFF06B6D4),
      'mimosa' => const Color(0xFF8B5CF6),
      'cisco' => const Color(0xFFDC2626),
      'roji' => const Color(0xFFE08F2D),
      _ => const Color(0xFF6B7280),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأجهزة'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 20),
            onPressed: _load,
            tooltip: 'تحديث',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('إضافة جهاز'),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Column(
                    children: [
                      _filterBar(),
                      Expanded(child: _list()),
                    ],
                  ),
                ),
    );
  }

  Widget _filterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip('الكلّ (${_all.length})', _brandFilter == null && _statusFilter == null,
                    () => setState(() { _brandFilter = null; _statusFilter = null; })),
                const SizedBox(width: 6),
                _chip('🟢 online', _statusFilter == 'online',
                    () => setState(() => _statusFilter = _statusFilter == 'online' ? null : 'online')),
                const SizedBox(width: 6),
                _chip('🔴 offline', _statusFilter == 'offline',
                    () => setState(() => _statusFilter = _statusFilter == 'offline' ? null : 'offline')),
                const SizedBox(width: 6),
                for (final b in NetworkDeviceLabels.brands.entries) ...[
                  _chip(b.value, _brandFilter == b.key,
                      () => setState(() => _brandFilter = _brandFilter == b.key ? null : b.key)),
                  const SizedBox(width: 6),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.brand : Colors.grey.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.brand : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, 
            color: active ? Colors.white : null,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _list() {
    final data = _filtered;
    if (data.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Icon(LucideIcons.router, size: 64, color: Colors.grey.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                _all.isEmpty ? 'لا توجد أجهزة بعد' : 'لا توجد نتائج للفلتر الحالي',
                style: const TextStyle(fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              if (_all.isEmpty)
                Text(
                  'اضغط "إضافة جهاز" لبدء تسجيل أجهزتك',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: data.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final d = data[i];
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () => _openDetails(d),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(Sp.md),
              child: Row(
                children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: _brandColor(d.brand).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_brandIcon(d.brand), color: _brandColor(d.brand), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _statusDot(d.lastStatus),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                d.name,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${d.ip} • ${NetworkDeviceLabels.brandLabel(d.brand)} • ${NetworkDeviceLabels.typeLabel(d.type)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (d.location != null && d.location!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            '📍 ${d.location}',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(LucideIcons.chevronLeft, size: 18, color: Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
