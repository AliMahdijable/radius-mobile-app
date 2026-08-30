import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/network_devices_api.dart';
import '../../models/device_region.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../widgets/skeleton.dart';
import '../../theme/typography.dart';

/// شاشة إدارة مناطق الأجهزة — قائمة + إضافة + تعديل + حذف.
/// راجع [[project_devices_monitoring_plan]].
class RegionsScreen extends StatefulWidget {
  const RegionsScreen({super.key});

  @override
  State<RegionsScreen> createState() => _RegionsScreenState();
}

class _RegionsScreenState extends State<RegionsScreen> {
  List<DeviceRegion> _regions = [];
  bool _loading = true;
  String? _error;

  /// نتتبّع لو المستخدم غيّر شيئاً — نُرجع bool للـcaller ليعيد تحميل قائمة الأجهزة.
  bool _mutated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await NetworkDevicesApi.listRegions();
      if (!mounted) return;
      setState(() {
        _regions = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openForm({DeviceRegion? initial}) async {
    final result = await showModalBottomSheet<DeviceRegion>(
      barrierColor: AppColors.scrim,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.card)),
      ),
      builder: (_) => _RegionFormSheet(initial: initial),
    );
    if (result != null && mounted) {
      _mutated = true;
      await _load();
    }
  }

  Future<void> _confirmDelete(DeviceRegion r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(LucideIcons.triangleAlert, color: AppColors.error, size: 32),
        title: const Text('حذف المنطقة'),
        content: Text(
          r.deviceCount > 0
              ? 'سيتم حذف "${r.name}" — ${r.deviceCount} جهاز سيصبح "بدون منطقة" (لن يُحذف). متابعة؟'
              : 'سيتم حذف "${r.name}". متابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    HapticFeedback.mediumImpact();
    try {
      final unassigned = await NetworkDevicesApi.deleteRegion(r.id);
      if (!mounted) return;
      _mutated = true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(unassigned > 0
            ? 'حُذفت "${r.name}" — $unassigned جهاز صار بدون منطقة'
            : 'حُذفت المنطقة "${r.name}"'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('فشل الحذف: $e'),
        backgroundColor: AppColors.errorFill,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _mutated);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('مناطق الأجهزة'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textHi,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowRight, size: 20),
            onPressed: () => Navigator.pop(context, _mutated),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: Material(
                color: AppColors.brand,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () => _openForm(),
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(LucideIcons.plus,
                        size: 18, color: AppColors.onBrand),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: _loading
            ? ListView.separated(
                padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, 90),
                itemCount: 5,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, __) => const SkeletonRegionCard(),
              )
            : _error != null
                ? Center(
                    child: Text(_error!,
                        style: TextStyle(color: AppColors.textMid)))
                : _regions.isEmpty
                    ? _empty()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                              Sp.md, Sp.md, Sp.md, 90),
                          itemCount: _regions.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _regionCard(_regions[i]),
                        ),
                      ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.mapPin, size: 48, color: AppColors.textLow),
          const SizedBox(height: 12),
          Text('لا توجد مناطق بعد',
              style: TextStyle(color: AppColors.textMid, fontSize: 14, height: 1.3)),
          const SizedBox(height: 6),
          Text('اضغط + لإضافة أول منطقة',
              style: TextStyle(color: AppColors.textLow, fontSize: 12.5, height: 1.4)),
        ],
      ),
    );
  }

  Widget _regionCard(DeviceRegion r) {
    final color = _parseColor(r.color) ?? AppColors.brand;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.md),
        onTap: () => _openForm(initial: r),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                child: Icon(LucideIcons.mapPin, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name,
                        style: AppType.buttonBold()),
                    const SizedBox(height: 2),
                    Text(
                      r.deviceCount == 0
                          ? 'لا يوجد أجهزة'
                          : '${r.deviceCount} جهاز',
                      style:
                          TextStyle(color: AppColors.textMid, fontSize: 12.5, height: 1.4),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(LucideIcons.pencil,
                    size: 18, color: AppColors.textMid),
                onPressed: () => _openForm(initial: r),
                tooltip: 'تعديل',
              ),
              IconButton(
                icon:
                    Icon(LucideIcons.trash2, size: 18, color: AppColors.error),
                onPressed: () => _confirmDelete(r),
                tooltip: 'حذف',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color? _parseColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final s = hex.startsWith('#') ? hex.substring(1) : hex;
  final n = int.tryParse(s, radix: 16);
  if (n == null) return null;
  return Color(0xFF000000 | n);
}

// ─────────────────────────────────────────────────────────────
class _RegionFormSheet extends StatefulWidget {
  const _RegionFormSheet({this.initial});
  final DeviceRegion? initial;

  @override
  State<_RegionFormSheet> createState() => _RegionFormSheetState();
}

class _RegionFormSheetState extends State<_RegionFormSheet> {
  late final TextEditingController _nameCtrl;
  String? _color;
  bool _saving = false;

  static const _presetColors = <String>[
    '#DC2626', // red
    '#EA580C', // orange
    '#CA8A04', // yellow
    '#16A34A', // green
    '#0891B2', // cyan
    '#2563EB', // blue
    '#7C3AED', // violet
    '#DB2777', // pink
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initial?.name ?? '');
    _color = widget.initial?.color;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('اسم المنطقة مطلوب'),
        backgroundColor: AppColors.errorFill,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _saving = true);
    HapticFeedback.selectionClick();
    try {
      final r = widget.initial == null
          ? await NetworkDevicesApi.createRegion(name: name, color: _color)
          : await NetworkDevicesApi.updateRegion(widget.initial!.id,
              name: name, color: _color);
      if (!mounted) return;
      Navigator.pop(context, r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('فشل: $e'),
        backgroundColor: AppColors.errorFill,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.mapPin,
        title: isEdit ? 'تعديل منطقة' : 'إضافة منطقة',
        subtitle: '',
        onClose: _saving ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: isEdit ? 'حفظ التعديلات' : 'إضافة',
        icon: LucideIcons.save,
        busy: _saving,
        onPressed: _save,
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            autofocus: !isEdit,
            decoration: InputDecoration(
              labelText: 'اسم المنطقة',
              hintText: 'مثال: كرخ، رصافة، الجادرية…',
              filled: true,
              fillColor: AppColors.surfaceInput,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text('اللون (اختياري)',
              style: AppType.bodyStrong(color: AppColors.textMid)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _colorSwatch(null),
              for (final c in _presetColors) _colorSwatch(c),
            ],
          ),
        ],
      ),
    );
  }

  Widget _colorSwatch(String? hex) {
    final active = _color == hex;
    final color = _parseColor(hex);
    return GestureDetector(
      onTap: () => setState(() => _color = hex),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color ?? AppColors.surfaceInput,
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? AppColors.textHi : AppColors.border,
            width: active ? 3 : 1,
          ),
        ),
        child: color == null
            ? Icon(LucideIcons.slash, size: 16, color: AppColors.textMid)
            : (active
                ? const Icon(LucideIcons.check,
                    size: 16, color: AppColors.onBrand)
                : null),
      ),
    );
  }
}
