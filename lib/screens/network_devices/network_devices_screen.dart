import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/network_devices_api.dart';
import '../../models/network_device.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import 'network_device_details_screen.dart';
import 'network_device_form_sheet.dart';
import 'widgets/brand_badge.dart';

/// قائمة أجهزة الشبكة. راجع project_devices_monitoring_plan.
///
/// التصميم:
/// - Row 1 (chips): فلتر بالنوع (لنكات/سويتشات/سكاتر/راوترات/AP/كاميرات/أخرى)
/// - Row 2 (chips): فلتر بالحالة (الكلّ/متصل/غير متصل/لم يُفحص)
/// - القائمة: cards بتصميم متسق مع باقي المشروع (AppColors)
class NetworkDevicesScreen extends StatefulWidget {
  const NetworkDevicesScreen({super.key});

  @override
  State<NetworkDevicesScreen> createState() => _NetworkDevicesScreenState();
}

class _NetworkDevicesScreenState extends State<NetworkDevicesScreen> {
  List<NetworkDevice> _all = [];
  bool _loading = true;
  String? _error;
  String? _typeFilter;
  String? _statusFilter;
  String _search = '';
  final _searchCtrl = TextEditingController();

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

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<NetworkDevice> get _filtered {
    final q = _search.trim().toLowerCase();
    return _all.where((d) {
      if (_typeFilter != null && d.type != _typeFilter) return false;
      if (_statusFilter != null && d.lastStatus != _statusFilter) return false;
      if (q.isNotEmpty) {
        final haystack = '${d.name} ${d.ip} ${d.mac ?? ''} ${d.location ?? ''} ${d.model ?? ''}'.toLowerCase();
        if (!haystack.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  int _countByType(String type) => _all.where((d) => d.type == type).length;
  int _countByStatus(String s) => _all.where((d) => d.lastStatus == s).length;

  IconData _typeIcon(String type) {
    return switch (type) {
      'link' => LucideIcons.satellite,
      'switch' => LucideIcons.network,
      'sector' => LucideIcons.radioTower,
      'router' => LucideIcons.router,
      'ap' => LucideIcons.wifi,
      'camera' => LucideIcons.video,
      _ => LucideIcons.circuitBoard,
    };
  }

  Color _statusColor(String status) => switch (status) {
        'online' => const Color(0xFF10B981),
        'offline' => AppColors.error,
        _ => AppColors.textLow,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('الأجهزة'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textHi,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 18),
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
              ? Center(child: Text(_error!, style: TextStyle(color: AppColors.textMid)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Column(
                    children: [
                      _searchBar(),
                      _typeFilterRow(),
                      _statusFilterRow(),
                      const Divider(height: 1),
                      Expanded(child: _list()),
                    ],
                  ),
                ),
    );
  }

  Widget _searchBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _search = v),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'ابحث باسم أو IP أو MAC أو موقع…',
          hintStyle: TextStyle(fontSize: 12, color: AppColors.textLow),
          prefixIcon: Icon(LucideIcons.search, size: 16, color: AppColors.textMid),
          suffixIcon: _search.isEmpty ? null : IconButton(
            icon: Icon(LucideIcons.x, size: 16, color: AppColors.textMid),
            onPressed: () {
              _searchCtrl.clear();
              setState(() => _search = '');
            },
          ),
          isDense: true,
          filled: true,
          fillColor: AppColors.surfaceInput,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.brand, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _typeFilterRow() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _typeChip(null, 'الكلّ', _all.length, LucideIcons.layoutGrid),
          const SizedBox(width: 6),
          for (final entry in NetworkDeviceLabels.types.entries) ...[
            _typeChip(entry.key, entry.value, _countByType(entry.key), _typeIcon(entry.key)),
            const SizedBox(width: 6),
          ],
        ]),
      ),
    );
  }

  Widget _typeChip(String? type, String label, int count, IconData icon) {
    final active = _typeFilter == type;
    return InkWell(
      onTap: () => setState(() => _typeFilter = active ? null : type),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.brand : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.brand : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(children: [
          Icon(icon, size: 14, color: active ? Colors.white : AppColors.textMid),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppColors.textHi,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: active ? Colors.white.withValues(alpha: 0.25) : AppColors.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: active ? Colors.white : AppColors.brand,
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _statusFilterRow() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      child: Row(children: [
        _statusChip(null, 'الكلّ', _all.length),
        const SizedBox(width: 6),
        _statusChip('online', 'متّصل', _countByStatus('online')),
        const SizedBox(width: 6),
        _statusChip('offline', 'غير متّصل', _countByStatus('offline')),
        const SizedBox(width: 6),
        _statusChip('unknown', 'لم يُفحص', _countByStatus('unknown')),
      ]),
    );
  }

  Widget _statusChip(String? status, String label, int count) {
    final active = _statusFilter == status;
    final color = status == null ? AppColors.brand : _statusColor(status);
    return InkWell(
      onTap: () => setState(() => _statusFilter = active ? null : status),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? color : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(children: [
          if (status != null) ...[
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: active ? Colors.white : color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            '$label ($count)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppColors.textHi,
            ),
          ),
        ]),
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
              Icon(LucideIcons.router, size: 64, color: AppColors.textLow),
              const SizedBox(height: Sp.lg),
              Text(
                _all.isEmpty ? 'لا توجد أجهزة بعد' : 'لا توجد نتائج للفلتر الحالي',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMid),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Sp.sm),
              if (_all.isEmpty)
                Text(
                  'اضغط "إضافة جهاز" لبدء تسجيل أجهزتك',
                  style: TextStyle(fontSize: 12, color: AppColors.textLow),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      itemCount: data.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _deviceCard(data[i]),
    );
  }

  Widget _deviceCard(NetworkDevice d) {
    final statusCol = _statusColor(d.lastStatus);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 0,
      child: InkWell(
        onTap: () => _openDetails(d),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          padding: const EdgeInsets.all(Sp.md),
          child: Row(
            children: [
              Stack(children: [
                BrandBadge(brand: d.brand, size: 44),
                // Type icon صغير في الزاوية العلوى (لتمييز router عن switch عن link)
                Positioned(
                  top: -3, right: -3,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border, width: 1),
                    ),
                    child: TypeIcon(type: d.type, size: 10, color: AppColors.textMid),
                  ),
                ),
                // Status dot سفلى يمين
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      color: statusCol,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                  ),
                ),
              ]),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHi,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(LucideIcons.globe, size: 11, color: AppColors.textLow),
                      const SizedBox(width: 3),
                      Text(
                        d.ip,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMid,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceInput,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          NetworkDeviceLabels.brandLabel(d.brand),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMid,
                          ),
                        ),
                      ),
                      if (d.protocol != null) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.brand.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            d.protocol!.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brand,
                            ),
                          ),
                        ),
                      ],
                    ]),
                    if (d.location != null && d.location!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(LucideIcons.mapPin, size: 10, color: AppColors.textLow),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            d.location!,
                            style: TextStyle(fontSize: 10, color: AppColors.textLow),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (d.lastResponseMs != null && d.lastStatus == 'online')
                    Text(
                      '${d.lastResponseMs} ms',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusCol,
                        fontFamily: 'monospace',
                      ),
                    ),
                  const SizedBox(height: 4),
                  Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
