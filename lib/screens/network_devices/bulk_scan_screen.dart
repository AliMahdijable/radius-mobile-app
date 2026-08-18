import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/network_devices_api.dart';
import '../../models/network_device.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';

/// Bulk scanner — يفحص /24 subnet بالتوازي على 6 ports شائعة،
/// يعرض النتائج live، ويسمح للمستخدم يختار أجهزة يضيفها دفعة واحدة.
///
/// الاستعمال:
/// 1. المستخدم يدخل base (مثلاً 192.168.88) — نخمّنها من الـWiFi حالياً.
/// 2. يضغط "ابدأ" → workers 30 يفحصون .1-.254
/// 3. النتائج تظهر live مع icon البراند المُخمّن
/// 4. يختار الي يريد + prefix اسم + region → "أضف N جهاز"
class BulkScanScreen extends StatefulWidget {
  const BulkScanScreen({super.key});

  @override
  State<BulkScanScreen> createState() => _BulkScanScreenState();
}

class _BulkScanScreenState extends State<BulkScanScreen> {
  final _baseCtrl = TextEditingController(text: '192.168.1');
  final _prefixCtrl = TextEditingController(text: 'جهاز');

  bool _scanning = false;
  int _done = 0;
  int _total = 254;
  final List<ScanResult> _found = [];
  final Set<String> _selected = {}; // ip strings
  bool _adding = false;
  int _added = 0;
  int _mutated = 0; // كم جهاز أُضيف — للـcaller

  @override
  void initState() {
    super.initState();
    _detectLocalSubnet();
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _prefixCtrl.dispose();
    super.dispose();
  }

  /// يجرّب استخراج WiFi IP من NetworkInterface — يقترحه في الحقل.
  Future<void> _detectLocalSubnet() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in ifaces) {
        for (final a in iface.addresses) {
          final ip = a.address;
          // نتجاهل link-local (169.254.*) والـcellular typically 10.x
          if (ip.startsWith('169.254.')) continue;
          if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.')) {
            final parts = ip.split('.');
            if (parts.length == 4) {
              final base = '${parts[0]}.${parts[1]}.${parts[2]}';
              if (mounted) setState(() => _baseCtrl.text = base);
              return;
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _startScan() async {
    final base = _baseCtrl.text.trim().replaceAll(RegExp(r'\.$'), '');
    // تحقّق: 3 octets فقط (a.b.c) بلا الرابع
    if (!RegExp(r'^(\d{1,3}\.){2}\d{1,3}$').hasMatch(base)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('صيغة غير صحيحة — استعمل "192.168.1"'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() {
      _scanning = true;
      _done = 0;
      _total = 254;
      _found.clear();
      _selected.clear();
    });
    HapticFeedback.mediumImpact();
    try {
      final results = await NetworkDevicesApi.bulkScanSubnet(
        base: base,
        onProgress: (done, total) {
          if (mounted) setState(() { _done = done; _total = total; });
        },
        onFound: (r) {
          if (mounted) {
            setState(() {
              _found.add(r);
              _selected.add(r.ip); // بشكل افتراضي كل مكتشف مُحدّد
            });
            HapticFeedback.selectionClick();
          }
        },
      );
      if (mounted) {
        setState(() => _scanning = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('انتهى الـscan — ${results.length} جهاز موجود'),
          backgroundColor: AppColors.brand,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _scanning = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشل: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _addSelected() async {
    if (_selected.isEmpty) return;
    setState(() { _adding = true; _added = 0; });
    HapticFeedback.mediumImpact();
    final prefix = _prefixCtrl.text.trim().isEmpty ? 'جهاز' : _prefixCtrl.text.trim();
    var errors = 0;
    for (final r in _found.where((r) => _selected.contains(r.ip))) {
      try {
        final lastOctet = r.ip.split('.').last;
        await NetworkDevicesApi.create({
          'name': '$prefix $lastOctet',
          'type': _typeFromBrand(r.guessBrand),
          'brand': r.guessBrand,
          'ip': r.ip,
          'port': 80,
          'api_port': r.guessApiPort,
          'protocol': r.guessProtocol,
          'model': null,
          'mac': null,
          'location': null,
          'notes': 'أُضيف عبر Bulk scan',
          'credentials': null,
        });
        if (mounted) setState(() { _added++; _mutated++; });
      } catch (_) {
        errors++;
      }
    }
    if (!mounted) return;
    setState(() => _adding = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(errors > 0
          ? 'أُضيف $_added جهاز — $errors فشل'
          : 'أُضيف $_added جهاز بنجاح'),
      backgroundColor: errors > 0 ? AppColors.error : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
    if (errors == 0) {
      // نظّف الـselected لتجنّب double-add
      setState(() => _selected.clear());
    }
  }

  String _typeFromBrand(String brand) {
    return switch (brand) {
      'mikrotik' => 'router',
      'ubnt'     => 'link',
      'mimosa'   => 'link',
      _          => 'other',
    };
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _mutated > 0);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('اكتشاف الأجهزة'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textHi,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowRight, size: 20),
            onPressed: () => Navigator.pop(context, _mutated > 0),
          ),
        ),
        body: Column(children: [
          _scannerBar(),
          _progressBar(),
          Expanded(
            child: _found.isEmpty
                ? _empty()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(Sp.md, 8, Sp.md, 90),
                    itemCount: _found.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => _resultTile(_found[i]),
                  ),
          ),
        ]),
        bottomNavigationBar: _selected.isEmpty ? null : _bottomBar(),
      ),
    );
  }

  Widget _scannerBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.md, 12, Sp.md, 8),
      color: AppColors.surface,
      child: Column(children: [
        Row(children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _baseCtrl,
              enabled: !_scanning,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'Subnet /24',
                hintText: '192.168.1',
                prefixIcon: Icon(LucideIcons.network, size: 18, color: AppColors.textMid),
                filled: true,
                fillColor: AppColors.surfaceInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _scanning ? null : _startScan,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _scanning
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(LucideIcons.radar, size: 16),
              label: Text(_scanning ? 'يمسح…' : 'ابدأ'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _prefixCtrl,
          enabled: !_scanning,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
            labelText: 'بادئة الاسم عند الإضافة',
            hintText: 'مثال: "جهاز" → جهاز 5، جهاز 10…',
            prefixIcon: Icon(LucideIcons.tag, size: 16, color: AppColors.textMid),
            filled: true,
            fillColor: AppColors.surfaceInput,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ]),
    );
  }

  Widget _progressBar() {
    if (_total == 0) return const SizedBox.shrink();
    final pct = _done / _total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, 6, Sp.md, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$_done / $_total IP',
              style: TextStyle(color: AppColors.textMid, fontSize: 11)),
          Text('${_found.length} جهاز',
              style: TextStyle(
                  color: AppColors.brand, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _scanning ? pct : (pct == 1.0 ? 1.0 : 0.0),
            minHeight: 4,
            backgroundColor: AppColors.surfaceInput,
            valueColor: AlwaysStoppedAnimation(AppColors.brand),
          ),
        ),
      ]),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(LucideIcons.radar, size: 56, color: AppColors.textLow),
        const SizedBox(height: 12),
        Text(
          _scanning ? 'جاري الفحص… تظهر النتائج مباشرةً' : 'اضغط "ابدأ" لفحص الشبكة',
          style: TextStyle(color: AppColors.textMid, fontSize: 13),
        ),
      ]),
    );
  }

  Widget _resultTile(ScanResult r) {
    final selected = _selected.contains(r.ip);
    final label = NetworkDeviceLabels.brandLabel(r.guessBrand);
    return Material(
      color: selected
          ? AppColors.brand.withValues(alpha: 0.06)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() {
          if (selected) {
            _selected.remove(r.ip);
          } else {
            _selected.add(r.ip);
          }
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Checkbox(
              value: selected,
              activeColor: AppColors.brand,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => setState(() {
                if (v == true) { _selected.add(r.ip); } else { _selected.remove(r.ip); }
              }),
            ),
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: _brandColor(r.guessBrand).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(_brandIcon(r.guessBrand),
                  size: 16, color: _brandColor(r.guessBrand)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(r.ip,
                        style: TextStyle(
                            color: AppColors.textHi,
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceInput,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('${r.responseMs}ms',
                          style: TextStyle(color: AppColors.textLow, fontSize: 10)),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text('$label · port ${r.openPort} · ${r.guessProtocol}',
                      style: TextStyle(color: AppColors.textMid, fontSize: 11)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Color _brandColor(String b) => switch (b) {
        'mikrotik' => const Color(0xFF2563EB),
        'ubnt'     => const Color(0xFF0891B2),
        'mimosa'   => const Color(0xFF7C3AED),
        _          => AppColors.textMid,
      };

  IconData _brandIcon(String b) => switch (b) {
        'mikrotik' => LucideIcons.router,
        'ubnt'     => LucideIcons.satellite,
        'mimosa'   => LucideIcons.radioTower,
        _          => LucideIcons.circuitBoard,
      };

  Widget _bottomBar() {
    return Material(
      elevation: 8,
      color: AppColors.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.md, 10, Sp.md, 10),
          child: Row(children: [
            Expanded(
              child: Text(
                'محدَّد: ${_selected.length}',
                style: TextStyle(
                    color: AppColors.textHi, fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton.icon(
              onPressed: (_adding || _selected.isEmpty) ? null : _addSelected,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              icon: _adding
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(LucideIcons.plus, size: 16),
              label: Text(_adding ? 'يُضيف $_added…' : 'أضف ${_selected.length} جهاز'),
            ),
          ]),
        ),
      ),
    );
  }
}
