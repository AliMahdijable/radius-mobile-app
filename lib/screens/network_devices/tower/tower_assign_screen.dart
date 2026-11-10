import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/tower_api.dart';
import '../../../core/util/bidi.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../models/network_device.dart';
import '../../../services/device_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import 'tower_logic.dart';
import 'tower_paint.dart';
import 'tower_topology_logic.dart';

/// «أجهزة البرج» — المالك ١١ نوفمبر: «نضيف ميزه الوكيل يسند الاجهزه للمنطقة معينه».
///
/// كلّ أجهزة الشركة بعلامة: ما في هذا البرج معلَّم، وما يُعلَّم يدخله (من «بلا منطقة» أو من برجٍ آخر)، وما تُرفع علامته يخرج
/// إلى «بلا منطقة». الحفظ دفعةٌ واحدة ([TowerApi.assignDevices]). تُرجع عدد ما نُقل، أو null إن خرج بلا حفظ.
class TowerAssignScreen extends StatefulWidget {
  const TowerAssignScreen({
    super.key,
    required this.regionId,
    required this.regionName,
    required this.devices,
    required this.towerName,
  });

  final int regionId;
  final String regionName;

  /// أجهزة الشركة كلّها.
  final List<NetworkDevice> devices;
  final String Function(int towerId) towerName;

  @override
  State<TowerAssignScreen> createState() => _TowerAssignScreenState();
}

class _TowerAssignScreenState extends State<TowerAssignScreen> {
  final _search = TextEditingController();
  String _q = '';
  bool _saving = false;

  late final Set<int> _initial = {
    for (final d in widget.devices)
      if (d.regionId == widget.regionId) d.id,
  };
  late final Set<int> _picked = {..._initial};

  Set<int> get _added => _picked.difference(_initial);
  Set<int> get _removed => _initial.difference(_picked);
  bool get _dirty => _added.isNotEmpty || _removed.isNotEmpty;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _match(NetworkDevice d) {
    if (_q.isEmpty) return true;
    final hay = '${d.name} ${d.ip} ${d.model ?? ''} ${widget.towerName(d.regionId ?? 0)}'.toLowerCase();
    return _q.split(RegExp(r'\s+')).every(hay.contains);
  }

  void _toggle(NetworkDevice d) {
    HapticFeedback.selectionClick();
    setState(() => _picked.contains(d.id) ? _picked.remove(d.id) : _picked.add(d.id));
  }

  Future<void> _save() async {
    if (!_dirty || _saving) return;
    setState(() => _saving = true);
    final added = _added;
    final removed = _removed;
    var moved = 0;
    String? error;
    if (added.isNotEmpty) {
      final r = await TowerApi.assignDevices(widget.regionId, added);
      if (r.ok) {
        moved += r.moved;
      } else {
        error = r.message ?? 'تعذّر نقل الأجهزة';
      }
    }
    if (error == null && removed.isNotEmpty) {
      final r = await TowerApi.assignDevices(0, removed);
      if (r.ok) {
        moved += r.moved;
      } else {
        error = r.message ?? 'تعذّر نقل الأجهزة';
      }
    }
    // ما نُقل نُقل ولو فشل النصف الثاني — القوائم تتحدّث على أيّ حال
    if (moved > 0) DeviceEvents.bump();
    if (!mounted) return;
    if (error != null) {
      setState(() => _saving = false);
      showSheetSnack(context, error, isError: true);
      return;
    }
    Navigator.of(context).pop(moved);
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty || _saving) return !_saving;
    final leave = await showConfirmSheet(
      context,
      title: 'الخروج بلا حفظ؟',
      message: 'اخترت أجهزةً ولم تحفظ. تخرج وتُترك كما كانت؟',
      confirmLabel: 'اخرج بلا حفظ',
      cancelLabel: 'ابقَ',
      icon: LucideIcons.triangleAlert,
      tone: AppTone.warning,
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    final here = <NetworkDevice>[];
    final free = <NetworkDevice>[];
    final elsewhere = <NetworkDevice>[];
    for (final d in widget.devices) {
      if (!_match(d)) continue;
      if (d.regionId == widget.regionId) {
        here.add(d);
      } else if (d.regionId == null) {
        free.add(d);
      } else {
        elsewhere.add(d);
      }
    }
    int byName(NetworkDevice x, NetworkDevice y) => naturalCompare(x.name, y.name);
    here.sort(byName);
    free.sort(byName);
    elsewhere.sort((x, y) {
      final t = naturalCompare(widget.towerName(x.regionId ?? 0), widget.towerName(y.regionId ?? 0));
      return t != 0 ? t : byName(x, y);
    });
    final shown = [...here, ...free, ...elsewhere];
    final allOn = shown.isNotEmpty && shown.every((d) => _picked.contains(d.id));

    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave() && nav.mounted) nav.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            title: Text('أجهزة «${widget.regionName}»'),
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textHi,
            elevation: 0,
            leading: IconButton(
              tooltip: 'إغلاق',
              icon: const Icon(LucideIcons.x, size: 20),
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
        ),
        body: Column(children: [
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SheetSearchField(
                controller: _search,
                hint: 'ابحث بالاسم أو العنوان أو البرج',
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text('علِّم الأجهزة التي على هذا البرج · المختار ${_picked.length}',
                      style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (shown.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() {
                      final ids = shown.map((d) => d.id);
                      allOn ? _picked.removeAll(ids) : _picked.addAll(ids);
                    }),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brand,
                      minimumSize: const Size(44, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(allOn ? 'ألغِ الظاهر' : 'علِّم الظاهر', style: AppType.bodyStrong(color: AppColors.brand)),
                  ),
              ]),
            ]),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Sp.xxl),
                      child: Text(widget.devices.isEmpty ? 'لا أجهزة بعد — أضفها من قسم الأجهزة.' : 'لا جهاز بهذا البحث',
                          textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.lg),
                    children: [
                      if (here.isNotEmpty) _header('على هذا البرج · ${here.length}'),
                      for (final d in here) _row(d),
                      if (free.isNotEmpty) _header('بلا منطقة · ${free.length}'),
                      for (final d in free) _row(d),
                      if (elsewhere.isNotEmpty) _header('على أبراجٍ أخرى · ${elsewhere.length}'),
                      for (final d in elsewhere) _row(d),
                    ],
                  ),
          ),
        ]),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.divider))),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.md),
            child: Row(children: [
              Expanded(
                child: Text(
                  !_dirty
                      ? 'لا تغيير'
                      : [
                          if (_added.isNotEmpty) 'يدخل ${TopoText.devices(_added.length)}',
                          if (_removed.isNotEmpty) 'يخرج ${TopoText.devices(_removed.length)}',
                        ].join(' · '),
                  style: AppType.body(color: _dirty ? AppColors.textHi : AppColors.textMid),
                  maxLines: 2,
                ),
              ),
              const SizedBox(width: Sp.md),
              SizedBox(
                height: H.button,
                child: FilledButton(
                  key: const ValueKey('assign-save'),
                  onPressed: _dirty && !_saving ? _save : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: AppColors.onBrand,
                    disabledBackgroundColor: AppColors.surfaceSunken,
                    disabledForegroundColor: AppColors.textLow,
                    minimumSize: const Size(120, H.button),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.button)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrand))
                      : Text('حفظ', style: AppType.buttonBold(color: _dirty ? AppColors.onBrand : AppColors.textLow)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, Sp.md, 2, 6),
        child: Text(text, style: AppType.microBold(color: AppColors.textMid)),
      );

  Widget _row(NetworkDevice d) {
    final on = _picked.contains(d.id);
    final was = _initial.contains(d.id);
    final other = d.regionId != null && d.regionId != widget.regionId;
    // ما سيحدث لهذا الجهاز عند الحفظ — يُقال صريحاً
    final String? change = on == was
        ? null
        : (on ? (other ? 'يُنقل من «${widget.towerName(d.regionId!)}»' : 'يدخل البرج') : 'يخرج إلى «بلا منطقة»');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        checked: on,
        child: Material(
          key: ValueKey('assign-device-${d.id}'),
          color: on ? AppColors.brandSoftBg : AppColors.surface,
          borderRadius: BorderRadius.circular(R.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.md),
            onTap: _saving ? null : () => _toggle(d),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: on ? AppColors.brand : AppColors.border),
              ),
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: on ? AppColors.brand : AppColors.surface,
                    borderRadius: BorderRadius.circular(R.check),
                    border: Border.all(color: on ? AppColors.brand : AppColors.textLow, width: 1.5),
                  ),
                  child: on ? const Icon(LucideIcons.check, size: 15, color: AppColors.onBrand) : null,
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 30,
                  height: 30,
                  child: Center(
                    child: DeviceGlyph(shape: TowerShapes.detect(d).shape, size: 22, color: on ? AppColors.brand : AppColors.textBody),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.name, style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      change ??
                          isoJoin([
                            if (other) widget.towerName(d.regionId!),
                            d.model ?? NetworkDeviceLabels.brandLabel(d.brand),
                            d.ip,
                          ], ' · '),
                      style: AppType.muted(color: change == null ? AppColors.textMid : AppColors.brand),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
