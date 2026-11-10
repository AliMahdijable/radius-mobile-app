import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/tower_api.dart';
import '../../../core/util/bidi.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../models/network_device.dart';
import '../../../models/tower_layout.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import 'tower_logic.dart';
import 'tower_paint.dart';
import 'tower_topology_logic.dart';

/// «ربط لنك» — طرفٌ في البرج الرئيسيّ (الماستر) وطرفٌ في الفرعيّ (السليف)، والترافيك يسير من الأوّل للثاني.
/// تُرجع اللنك المحفوظ ([TowerApi.addLink])، أو null إن خرج بلا ربط.
class TowerLinkEditorScreen extends StatefulWidget {
  const TowerLinkEditorScreen({
    super.key,
    required this.devices,
    required this.towerName,
    required this.links,
    this.suggestions = const [],
    this.fromTower,
  });

  final List<NetworkDevice> devices;
  final String Function(int towerId) towerName;
  final List<TowerLink> links;
  final List<LinkSuggestion> suggestions;

  /// برجٌ فُتح الربط منه — أجهزته أوّلاً عند اختيار طرف الرئيسيّ.
  final int? fromTower;

  @override
  State<TowerLinkEditorScreen> createState() => _TowerLinkEditorScreenState();
}

class _TowerLinkEditorScreenState extends State<TowerLinkEditorScreen> {
  NetworkDevice? _a;
  NetworkDevice? _b;
  bool _saving = false;

  int _tower(NetworkDevice d) => d.regionId ?? 0;

  bool get _sameTower => _a != null && _b != null && _tower(_a!) == _tower(_b!);
  bool get _canSave => _a != null && _b != null && !_sameTower && !_saving;

  Future<void> _pick({required bool main}) async {
    final other = main ? _b : _a;
    final subs = {for (final l in widget.links) l.bDeviceId};
    final picked = await showAppSheet<NetworkDevice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (_) => _DevicePickerSheet(
        title: main ? 'طرف البرج الرئيسي' : 'طرف البرج الفرعي',
        subtitle: main ? 'الماستر — منه يخرج الترافيك' : 'السليف — إليه يصل الترافيك',
        devices: widget.devices,
        towerName: widget.towerName,
        current: main ? _a : _b,
        firstTower: main ? widget.fromTower : null,
        disabledWhy: (d) {
          if (other != null && d.id == other.id) return 'الطرف الآخر';
          if (other != null && _tower(d) == _tower(other)) return 'في برج الطرف الآخر';
          if (!main && subs.contains(d.id)) return 'مربوطٌ بلنكٍ آخر';
          return null;
        },
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => main ? _a = picked : _b = picked);
  }

  void _swap() {
    HapticFeedback.selectionClick();
    setState(() {
      final t = _a;
      _a = _b;
      _b = t;
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final r = await TowerApi.addLink(_a!.id, _b!.id);
    if (!mounted) return;
    if (!r.ok || r.link == null) {
      setState(() => _saving = false);
      showSheetSnack(context, r.message ?? 'تعذّر حفظ الربط', isError: true);
      return;
    }
    Navigator.of(context).pop(r.link);
  }

  @override
  Widget build(BuildContext context) {
    final picked = {_a?.id, _b?.id};
    final suggestions = [
      for (final s in widget.suggestions)
        if (!(picked.contains(s.a.id) && picked.contains(s.b.id))) s,
    ];
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          title: const Text('ربط لنك'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textHi,
          elevation: 0,
          leading: IconButton(
            tooltip: 'إغلاق',
            icon: const Icon(LucideIcons.x, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.lg),
        children: [
          Text(
            'اللنك يربط برجين: طرفه في البرج الرئيسي (الماستر) وطرفه في البرج الفرعي (السليف). الترافيك يُرسم سائراً من الرئيسي للفرعي.',
            style: AppType.body(color: AppColors.textMid),
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            Text('مقترحة — أجهزةٌ ترى بعضها', style: AppType.bodyStrong(color: AppColors.textHi)),
            const SizedBox(height: 6),
            for (final s in suggestions.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(R.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(R.md),
                    onTap: () => setState(() {
                      _a = s.a;
                      _b = s.b;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(R.md),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(children: [
                        Icon(LucideIcons.sparkles, size: 16, color: AppColors.brand),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${iso(s.a.name)} ← ${iso(s.b.name)}',
                                style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(
                              '${iso(widget.towerName(_tower(s.a)))} ← ${iso(widget.towerName(_tower(s.b)))} · ${s.why}',
                              style: AppType.muted(color: AppColors.textMid),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ]),
                        ),
                        Text('اختر', style: AppType.bodyBold(color: AppColors.brand)),
                      ]),
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: Sp.md),
          _endCard(
            key: const ValueKey('link-end-main'),
            step: '1',
            title: 'طرف البرج الرئيسي',
            hint: 'الماستر — منه يخرج الترافيك',
            device: _a,
            onTap: () => _pick(main: true),
          ),
          SizedBox(
            height: 44,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(LucideIcons.arrowDown, size: 18, color: AppColors.brand),
              const SizedBox(width: 6),
              Text('الترافيك', style: AppType.muted(color: AppColors.textMid)),
              if (_a != null && _b != null) ...[
                const SizedBox(width: Sp.md),
                TextButton.icon(
                  onPressed: _swap,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.brand,
                    minimumSize: const Size(44, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(LucideIcons.arrowUpDown, size: 15),
                  label: Text('بدّل الطرفين', style: AppType.bodyStrong(color: AppColors.brand)),
                ),
              ],
            ]),
          ),
          _endCard(
            key: const ValueKey('link-end-sub'),
            step: '2',
            title: 'طرف البرج الفرعي',
            hint: 'السليف — إليه يصل الترافيك',
            device: _b,
            onTap: () => _pick(main: false),
          ),
          if (_sameTower)
            Padding(
              padding: const EdgeInsets.only(top: Sp.sm),
              child: Text('الجهازان في البرج نفسه — اللنك يربط برجين.', style: AppType.body(color: AppColors.error)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.md),
          child: SizedBox(
            height: H.button,
            child: FilledButton.icon(
              key: const ValueKey('link-save'),
              onPressed: _canSave ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: AppColors.onBrand,
                disabledBackgroundColor: AppColors.surfaceSunken,
                disabledForegroundColor: AppColors.textLow,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.button)),
              ),
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrand))
                  : const Icon(LucideIcons.link, size: 18),
              label: Text('احفظ الربط', style: AppType.buttonBold(color: _canSave || _saving ? AppColors.onBrand : AppColors.textLow)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _endCard({
    required Key key,
    required String step,
    required String title,
    required String hint,
    required NetworkDevice? device,
    required VoidCallback onTap,
  }) {
    final d = device;
    return Semantics(
      button: true,
      child: Material(
        key: key,
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.lg),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: d == null ? AppColors.border : AppColors.brand),
            ),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.chip)),
                child: d == null
                    ? Text(step, style: AppType.cardTitleBold(color: AppColors.brand))
                    : DeviceGlyph(shape: TowerShapes.detect(d).shape, size: 26, color: AppColors.brand),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppType.muted(color: AppColors.textMid)),
                  Text(d?.name ?? 'اختر الجهاز',
                      style: AppType.cardTitleBold(color: d == null ? AppColors.brand : AppColors.textHi),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    d == null ? hint : isoJoin([widget.towerName(_tower(d)), d.model ?? NetworkDeviceLabels.brandLabel(d.brand), d.ip], ' · '),
                    style: AppType.muted(color: AppColors.textMid),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
              Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textLow),
            ]),
          ),
        ),
      ),
    );
  }
}

/// منتقي جهازٍ لطرف لنك: الأجهزة ببرجها، والصحون (اللنكات) أوّلاً في كلّ برج، وما لا يصلح معطّلٌ بسببه.
class _DevicePickerSheet extends StatefulWidget {
  const _DevicePickerSheet({
    required this.title,
    required this.subtitle,
    required this.devices,
    required this.towerName,
    required this.disabledWhy,
    this.current,
    this.firstTower,
  });

  final String title;
  final String subtitle;
  final List<NetworkDevice> devices;
  final String Function(int towerId) towerName;
  final String? Function(NetworkDevice d) disabledWhy;
  final NetworkDevice? current;
  final int? firstTower;

  @override
  State<_DevicePickerSheet> createState() => _DevicePickerSheetState();
}

class _DevicePickerSheetState extends State<_DevicePickerSheet> {
  final _search = TextEditingController();
  String _q = '';

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

  @override
  Widget build(BuildContext context) {
    final byTower = <int, List<NetworkDevice>>{};
    for (final d in widget.devices) {
      if (_match(d)) byTower.putIfAbsent(d.regionId ?? 0, () => []).add(d);
    }
    final towers = byTower.keys.toList()
      ..sort((x, y) {
        if (x == widget.firstTower) return -1;
        if (y == widget.firstTower) return 1;
        // «بلا منطقة» آخراً
        if (x == 0 || y == 0) return x == 0 ? 1 : -1;
        return naturalCompare(widget.towerName(x), widget.towerName(y));
      });
    int rank(NetworkDevice d) => TowerShapes.detect(d).shape == TowerShape.dish ? 0 : 1;
    for (final list in byTower.values) {
      list.sort((x, y) {
        final r = rank(x) - rank(y);
        return r != 0 ? r : naturalCompare(x.name, y.name);
      });
    }
    return DesignSheet(
      scrollable: false,
      header: SheetHeaderBar(
        icon: LucideIcons.link,
        title: widget.title,
        subtitle: widget.subtitle,
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.devices.length > 8) ...[
          SheetSearchField(
            controller: _search,
            hint: 'ابحث بالاسم أو العنوان أو البرج',
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
          const SizedBox(height: Sp.sm),
        ],
        Flexible(
          child: towers.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: Sp.xl),
                  child: Text('لا جهاز بهذا البحث', textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
                )
              : ListView(shrinkWrap: true, children: [
                  for (final t in towers) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, Sp.sm, 2, 4),
                      child: Text('${widget.towerName(t)} · ${byTower[t]!.length}', style: AppType.microBold(color: AppColors.textMid)),
                    ),
                    for (final d in byTower[t]!) _row(d),
                  ],
                ]),
        ),
      ]),
    );
  }

  Widget _row(NetworkDevice d) {
    final why = widget.disabledWhy(d);
    final on = widget.current?.id == d.id;
    final off = why != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        key: ValueKey('pick-device-${d.id}'),
        color: on ? AppColors.brandSoftBg : AppColors.bg,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: off ? null : () => Navigator.of(context).pop(d),
          child: Opacity(
            opacity: off ? 0.5 : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: DeviceGlyph(shape: TowerShapes.detect(d).shape, size: 24, color: on ? AppColors.brand : AppColors.textBody),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.name, style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(isoJoin([d.model ?? NetworkDeviceLabels.brandLabel(d.brand), d.ip], ' · '),
                        style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                if (off)
                  Text(why, style: AppType.micro(color: AppColors.textMid))
                else if (on)
                  Icon(LucideIcons.check, size: 18, color: AppColors.brand),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
