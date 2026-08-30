import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/network_devices_api.dart';
import '../../models/device_region.dart';
import '../../models/network_device.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// Bulk scanner — يفحص /24 subnet بالتوازي على 6 ports شائعة،
/// يعرض النتائج live، ويسمح للمستخدم يختار أجهزة يضيفها دفعة واحدة.
///
/// الاستعمال:
/// 1. المستخدم يدخل base (مثلاً 192.168.88) — نخمّنها من الـWiFi حالياً.
/// 2. يضغط "ابدأ" → workers 30 يفحصون .1-.254
/// 3. النتائج تظهر live مع icon البراند المُخمّن
/// 4. يختار الي يريد + prefix اسم + region → "أضف N جهاز"
class BulkScanScreen extends StatefulWidget {
  const BulkScanScreen({super.key, this.existingIps = const {}});

  /// IPs موجودة مسبقاً في قائمة أجهزة المدير — تظهر بالقائمة كـ"مضاف مسبقاً"
  /// وغير قابلة للتحديد (dedup ضد إضافة نفس الجهاز مرّتين). 2026-08-18.
  final Set<String> existingIps;

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
  List<DeviceRegion> _regions = const [];

  @override
  void initState() {
    super.initState();
    _detectLocalSubnet();
    _loadRegions();
  }

  Future<void> _loadRegions() async {
    try {
      final r = await NetworkDevicesApi.listRegions();
      if (mounted) setState(() => _regions = r);
    } catch (_) {}
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
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.')) {
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

  /// نتيجة parseRange — base + start/end octets.
  ({String base, int start, int end})? _parseRange(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (s.isEmpty) return null;
    // شيل /24 لو موجود
    s = s.replaceAll(RegExp(r'/\d+$'), '');
    // شيل نقطة تعليقة في النهاية (10.70.241.)
    s = s.replaceAll(RegExp(r'\.$'), '');

    // صيغة range: a.b.c.d-e (مثال 10.70.241.5-100)
    final rangeMatch =
        RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})-(\d{1,3})$')
            .firstMatch(s);
    if (rangeMatch != null) {
      final o1 = int.parse(rangeMatch.group(1)!);
      final o2 = int.parse(rangeMatch.group(2)!);
      final o3 = int.parse(rangeMatch.group(3)!);
      final start = int.parse(rangeMatch.group(4)!);
      final end = int.parse(rangeMatch.group(5)!);
      if (![o1, o2, o3].every((n) => n >= 0 && n <= 255)) return null;
      if (start < 1 || start > 254 || end < 1 || end > 254 || start > end)
        return null;
      return (base: '$o1.$o2.$o3', start: start, end: end);
    }
    // صيغة 4 octets: a.b.c.d → نتجاهل الرابع، scan كامل
    final fourMatch =
        RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.\d{1,3}$').firstMatch(s);
    if (fourMatch != null) {
      final o1 = int.parse(fourMatch.group(1)!);
      final o2 = int.parse(fourMatch.group(2)!);
      final o3 = int.parse(fourMatch.group(3)!);
      if (![o1, o2, o3].every((n) => n >= 0 && n <= 255)) return null;
      return (base: '$o1.$o2.$o3', start: 1, end: 254);
    }
    // صيغة 3 octets: a.b.c → scan كامل .1-.254
    final threeMatch =
        RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(s);
    if (threeMatch != null) {
      final o1 = int.parse(threeMatch.group(1)!);
      final o2 = int.parse(threeMatch.group(2)!);
      final o3 = int.parse(threeMatch.group(3)!);
      if (![o1, o2, o3].every((n) => n >= 0 && n <= 255)) return null;
      return (base: '$o1.$o2.$o3', start: 1, end: 254);
    }
    return null;
  }

  Future<void> _startScan() async {
    final parsed = _parseRange(_baseCtrl.text);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'صيغة غير صحيحة — أمثلة: 192.168.1  •  10.70.241.0/24  •  10.70.241.5-100'),
        backgroundColor: AppColors.errorFill,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ));
      return;
    }
    final total = parsed.end - parsed.start + 1;
    setState(() {
      _scanning = true;
      _done = 0;
      _total = total;
      _found.clear();
      _selected.clear();
    });
    HapticFeedback.mediumImpact();
    try {
      final results = await NetworkDevicesApi.bulkScanSubnet(
        base: parsed.base,
        startOctet: parsed.start,
        endOctet: parsed.end,
        onProgress: (done, total) {
          if (mounted)
            setState(() {
              _done = done;
              _total = total;
            });
        },
        onFound: (r) {
          if (mounted) {
            setState(() {
              _found.add(r);
              // 2026-08-18: لا نُحدّد أي جهاز افتراضياً (كان يُحدّد الكل
              // → subnet /24 = 200 جهاز يُضاف بضغطة واحدة بدون قصد).
              // المستخدم يختار يدوياً أو يستعمل "تحديد الكل" من bottom bar.
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
          backgroundColor: AppColors.errorFill,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _addSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;

    // 2026-08-18: confirm صريح لو >20 جهاز — يحمي من ضغطة خطأ
    if (count > 20) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(LucideIcons.triangleAlert,
              color: AppColors.warning, size: 32),
          title: Text('إضافة $count جهاز'),
          content: Text(
            'ستُضاف $count جهاز دفعة واحدة. هل أنت متأكّد؟',
            style: const TextStyle(fontSize: 14, height: 1.3),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
              child: Text('تابع'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }

    // Sheet قبل الإضافة — يجمع region + creds + prefix تُطبّق على كل المُحدَّد
    final opts = await showModalBottomSheet<_BulkAddOptions>(
      barrierColor: AppColors.scrim,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.card)),
      ),
      builder: (_) => _BulkAddOptionsSheet(
        count: count,
        regions: _regions,
        initialPrefix:
            _prefixCtrl.text.trim().isEmpty ? 'جهاز' : _prefixCtrl.text.trim(),
      ),
    );
    if (opts == null || !mounted) return;

    setState(() {
      _adding = true;
      _added = 0;
    });
    HapticFeedback.mediumImpact();

    // 2026-08-18: بنِ payload كامل واستدع bulk-create endpoint (طلب واحد
    // بدل N — يتفادى rate-limit + سرعة أعلى + atomic transaction).
    final payload = <Map<String, dynamic>>[];
    for (final r in _found.where((r) => _selected.contains(r.ip))) {
      final lastOctet = r.ip.split('.').last;
      final creds = <String, dynamic>{};
      if (r.guessProtocol == 'snmp') {
        if (opts.community != null && opts.community!.isNotEmpty) {
          creds['community'] = opts.community!;
          creds['version'] = 'v2c';
        }
      } else {
        if (opts.user != null && opts.user!.isNotEmpty)
          creds['user'] = opts.user!;
        if (opts.pass != null && opts.pass!.isNotEmpty)
          creds['pass'] = opts.pass!;
      }
      payload.add({
        'name': '${opts.prefix} $lastOctet',
        'type': _typeFromBrand(r.guessBrand),
        'brand': r.guessBrand,
        'ip': r.ip,
        'port': 80,
        'api_port': r.guessApiPort,
        'protocol': r.guessProtocol,
        'region_id': opts.regionId,
        'model': null,
        'mac': null,
        'location': null,
        'notes': 'أُضيف عبر Bulk scan',
        'credentials': creds.isEmpty ? null : creds,
      });
    }

    String snackText;
    Color snackColor;
    try {
      final created = await NetworkDevicesApi.bulkCreate(payload);
      _added = created.length;
      _mutated += created.length;
      snackText = 'أُضيف ${created.length} جهاز بنجاح';
      snackColor = AppColors.success;
    } catch (e) {
      snackText = 'فشل: ${e.toString().replaceFirst('Exception: ', '')}';
      snackColor = AppColors.error;
    }
    if (!mounted) return;
    setState(() {
      _adding = false;
      if (snackColor != AppColors.error) _selected.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(snackText),
      backgroundColor: snackColor,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  String _typeFromBrand(String brand) {
    return switch (brand) {
      'mikrotik' => 'router',
      'ubnt' => 'link',
      'mimosa' => 'link',
      'ruijie' => 'ap',
      _ => 'other',
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
        // 2026-08-18: BottomBar يظهر لو فيه نتائج (حتى لو ما مُحدَّد)
        // — يعرض زرّ "تحديد الكل" مفيد بعد ما شلنا auto-select.
        bottomNavigationBar: _found.isEmpty ? null : _bottomBar(),
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
                labelText: 'الشبكة أو النطاق',
                hintText: '10.70.241.0/24',
                prefixIcon: Icon(LucideIcons.network,
                    size: 18, color: AppColors.textMid),
                filled: true,
                fillColor: AppColors.surfaceInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.onBrand))
                  : const Icon(LucideIcons.radar, size: 16),
              label: Text(_scanning ? 'يمسح…' : 'ابدأ'),
            ),
          ),
        ]),
        // Helper text — أمثلة الصيغ المقبولة
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 4, left: 4),
          child: Text(
            'الصيغ المدعومة: 192.168.1  •  10.70.241.0/24  •  10.70.241.5-100',
            style: TextStyle(
                color: AppColors.textLow, fontSize: 10.5, height: 1.4),
            textDirection: TextDirection.rtl,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _prefixCtrl,
          enabled: !_scanning,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
            labelText: 'بادئة الاسم عند الإضافة',
            hintText: 'مثال: "جهاز" → جهاز 5، جهاز 10…',
            prefixIcon:
                Icon(LucideIcons.tag, size: 16, color: AppColors.textMid),
            filled: true,
            fillColor: AppColors.surfaceInput,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.sm),
              borderSide: BorderSide.none,
            ),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
              style: TextStyle(color: AppColors.textMid, fontSize: 11, height: 1.35)),
          Text('${_found.length} جهاز',
              style: AppType.pillBold(color: AppColors.brand)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(R.pill),
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
          _scanning
              ? 'جاري الفحص… تظهر النتائج مباشرةً'
              : 'اضغط "ابدأ" لفحص الشبكة',
          style: TextStyle(color: AppColors.textMid, fontSize: 13, height: 1.45),
        ),
      ]),
    );
  }

  Widget _resultTile(ScanResult r) {
    final alreadyExists = widget.existingIps.contains(r.ip);
    final selected = _selected.contains(r.ip);
    final label = NetworkDeviceLabels.brandLabel(r.guessBrand);
    // أجهزة مضافة مسبقاً: تظهر باهتة + badge + لا تُختار + لا onTap
    return Material(
      color: alreadyExists
          ? AppColors.surfaceDisabled
          : (selected ? AppColors.brandSoftBg : AppColors.surface),
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.sm),
        onTap: alreadyExists
            ? null
            : () => setState(() {
                  if (selected) {
                    _selected.remove(r.ip);
                  } else {
                    _selected.add(r.ip);
                  }
                }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
              color: alreadyExists
                  ? AppColors.border
                  : (selected ? AppColors.brand : AppColors.border),
              width: (selected && !alreadyExists) ? 1.5 : 1,
            ),
          ),
          child: Opacity(
            opacity: alreadyExists ? 0.55 : 1.0,
            child: Row(children: [
              if (alreadyExists)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(LucideIcons.circleCheck,
                      size: 18, color: AppColors.success),
                )
              else
                Checkbox(
                  value: selected,
                  activeColor: AppColors.brand,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(r.ip);
                    } else {
                      _selected.remove(r.ip);
                    }
                  }),
                ),
              Container(
                width: 32,
                height: 32,
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
                          style: AppType.cardTitleBold()),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceInput,
                          borderRadius: BorderRadius.circular(R.pill),
                        ),
                        child: Text('${r.responseMs}ms',
                            style: TextStyle(
                                color: AppColors.textLow, fontSize: 10.5, height: 1.3)),
                      ),
                      if (alreadyExists) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.successSoftBg,
                            borderRadius: BorderRadius.circular(R.pill),
                            border: Border.all(
                              color: AppColors.successSoftBorder,
                            ),
                          ),
                          child: Text('مضاف مسبقاً',
                              style: AppType.daysWordBold(color: AppColors.success)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text('$label · port ${r.openPort} · ${r.guessProtocol}',
                        style:
                            TextStyle(color: AppColors.textMid, fontSize: 11, height: 1.35)),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Color _brandColor(String b) => switch (b) {
        'mikrotik' => AppColors.brandAccent,
        'ubnt' => AppColors.info,
        'mimosa' => AppColors.brandAccent,
        'ruijie' => AppColors.brandAccent,
        _ => AppColors.textMid,
      };

  IconData _brandIcon(String b) => switch (b) {
        'mikrotik' => LucideIcons.router,
        'ubnt' => LucideIcons.satellite,
        'mimosa' => LucideIcons.radioTower,
        'ruijie' => LucideIcons.wifi,
        _ => LucideIcons.circuitBoard,
      };

  Widget _bottomBar() {
    // كم جهاز يمكن اختياره (ما عدا المضاف مسبقاً)
    final selectable =
        _found.where((r) => !widget.existingIps.contains(r.ip)).length;
    final allSelected = _selected.length == selectable && selectable > 0;
    return Material(
      elevation: 8,
      color: AppColors.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.md, 10, Sp.md, 10),
          child: Row(children: [
            // زرّ "تحديد الكل / إلغاء التحديد" — يظهر لو فيه جهاز واحد+
            if (selectable > 0)
              TextButton.icon(
                onPressed: _adding
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          if (allSelected) {
                            _selected.clear();
                          } else {
                            for (final r in _found) {
                              if (!widget.existingIps.contains(r.ip)) {
                                _selected.add(r.ip);
                              }
                            }
                          }
                        });
                      },
                icon: Icon(
                    allSelected ? LucideIcons.square : LucideIcons.checkSquare,
                    size: 16,
                    color: AppColors.brand),
                label: Text(allSelected ? 'إلغاء' : 'تحديد الكل',
                    style: TextStyle(color: AppColors.brand, fontSize: 12.5, height: 1.4)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'محدَّد: ${_selected.length}',
                style: AppType.rowLabelBold(),
              ),
            ),
            FilledButton.icon(
              onPressed: (_adding || _selected.isEmpty) ? null : _addSelected,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              icon: _adding
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.onBrand))
                  : const Icon(LucideIcons.plus, size: 14),
              label: Text(
                  _adding ? 'يُضيف $_added…' : 'أضف ${_selected.length}',
                  style: const TextStyle(fontSize: 13, height: 1.45)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Bulk add options sheet — يظهر قبل تنفيذ الإضافة
// كل الحقول اختياريّة. لو المستخدم ما ضاف شي → أسماء تلقائيّة من الـIP.
// ═════════════════════════════════════════════════════════════════════

/// نتيجة الـsheet — options تُطبَّق على كل الأجهزة المُحدَّدة.
class _BulkAddOptions {
  final String prefix; // بادئة الاسم (default "جهاز")
  final int? regionId; // null = بدون منطقة
  final String? user; // للـapi/ssh
  final String? pass;
  final String? community; // للـsnmp
  const _BulkAddOptions({
    required this.prefix,
    this.regionId,
    this.user,
    this.pass,
    this.community,
  });
}

class _BulkAddOptionsSheet extends StatefulWidget {
  const _BulkAddOptionsSheet({
    required this.count,
    required this.regions,
    required this.initialPrefix,
  });
  final int count;
  final List<DeviceRegion> regions;
  final String initialPrefix;

  @override
  State<_BulkAddOptionsSheet> createState() => _BulkAddOptionsSheetState();
}

class _BulkAddOptionsSheetState extends State<_BulkAddOptionsSheet> {
  late final TextEditingController _prefixCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _communityCtrl;
  int? _regionId;
  bool _obscurePass = true;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _prefixCtrl = TextEditingController(text: widget.initialPrefix);
    _userCtrl = TextEditingController();
    _passCtrl = TextEditingController();
    _communityCtrl = TextEditingController(text: 'public');
  }

  @override
  void dispose() {
    _prefixCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _communityCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final prefix =
        _prefixCtrl.text.trim().isEmpty ? 'جهاز' : _prefixCtrl.text.trim();
    Navigator.pop(
        context,
        _BulkAddOptions(
          prefix: prefix,
          regionId: _regionId,
          user: _userCtrl.text.trim().isEmpty ? null : _userCtrl.text.trim(),
          pass: _passCtrl.text.isEmpty ? null : _passCtrl.text,
          community: _communityCtrl.text.trim().isEmpty
              ? null
              : _communityCtrl.text.trim(),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.plus,
        title: 'إضافة ${widget.count} جهاز',
        subtitle: 'اضبط الاسم والمنطقة وبيانات الدخول قبل الإضافة',
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: 'تأكيد إضافة ${widget.count} جهاز',
        icon: LucideIcons.check,
        onPressed: _submit,
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),

          // 1. بادئة الاسم
          TextField(
            controller: _prefixCtrl,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              labelText: 'بادئة الاسم',
              hintText: 'مثال: "جهاز" → جهاز 5، جهاز 88',
              prefixIcon:
                  Icon(LucideIcons.tag, size: 16, color: AppColors.textMid),
              filled: true,
              fillColor: AppColors.surfaceInput,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide.none,
              ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 10),

          // 2. المنطقة (dropdown)
          DropdownButtonFormField<int?>(
            value: _regionId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'المنطقة',
              prefixIcon:
                  Icon(LucideIcons.mapPin, size: 16, color: AppColors.textMid),
              filled: true,
              fillColor: AppColors.surfaceInput,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide.none,
              ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Text('بدون منطقة',
                    style: TextStyle(color: AppColors.textMid)),
              ),
              for (final r in widget.regions)
                DropdownMenuItem<int?>(
                  value: r.id,
                  child: Row(children: [
                    Icon(LucideIcons.mapPin,
                        size: 12,
                        color: _parseRegionColor(r.color) ?? AppColors.brand),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(r.name, overflow: TextOverflow.ellipsis)),
                    if (r.deviceCount > 0)
                      Text(' (${r.deviceCount})',
                          style: TextStyle(
                              color: AppColors.textLow, fontSize: 11, height: 1.35)),
                  ]),
                ),
            ],
            onChanged: (v) => setState(() => _regionId = v),
          ),
          const SizedBox(height: 10),

          // 3. Advanced — user/pass/community (طيّ افتراضي)
          InkWell(
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon(
                    _showAdvanced
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronLeft,
                    size: 16,
                    color: AppColors.brand),
                const SizedBox(width: 4),
                Text('بيانات الدخول المشتركة (اختياريّة)',
                    style: AppType.bodyBold(color: AppColors.brand)),
              ]),
            ),
          ),
          if (_showAdvanced) ...[
            const SizedBox(height: 6),
            Text(
                'تُطبَّق على كل الأجهزة — Mikrotik/UBNT (user+pass) و Mimosa (community)',
                style: TextStyle(
                    color: AppColors.textLow, fontSize: 10.5, height: 1.4)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                controller: _userCtrl,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'User',
                  hintText: 'admin / ubnt',
                  filled: true,
                  fillColor: AppColors.surfaceInput,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(R.sm),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'Password',
                  filled: true,
                  fillColor: AppColors.surfaceInput,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(R.sm),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscurePass ? LucideIcons.eye : LucideIcons.eyeOff,
                        size: 16),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              )),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _communityCtrl,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'SNMP Community (لأجهزة Mimosa)',
                hintText: 'public',
                filled: true,
                fillColor: AppColors.surfaceInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Color? _parseRegionColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final s = hex.startsWith('#') ? hex.substring(1) : hex;
  final n = int.tryParse(s, radix: 16);
  if (n == null) return null;
  return Color(0xFF000000 | n);
}
