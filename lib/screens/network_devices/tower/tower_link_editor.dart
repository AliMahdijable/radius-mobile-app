import 'dart:async';

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
import '../device_vitals.dart';
import 'tower_logic.dart';
import 'tower_paint.dart';
import 'tower_reading.dart';
import 'tower_topology_logic.dart';

/// قراءة جهازٍ الآن (منافذه بحالها وما يعبرها) — لمنتقي منفذ الكيبل. null: تعذّرت.
typedef TowerDeviceReader = Future<TowerReading?> Function(NetworkDevice device);

/// «ربط برجين» — طرفٌ في البرج الرئيسيّ (الماستر) وطرفٌ في الفرعيّ (السليف)، والترافيك يسير من الأوّل للثاني.
///
/// نوعان (المالك ١١ نوفمبر: «اكو ابراج ترتبط مع بعضها فايبر… مرات مو لنك يعني مباشر كيبل ضوئي بين سوجات»):
///   • لنكٌ لاسلكيّ — جهازا اللنك (الصحون أوّلاً في المنتقي)، وما تراه الأجهزة من بعضها مقترَح.
///   • كيبلٌ ضوئيّ — سويجان/راوتران/أولت (أوّلاً في المنتقي) ومنفذ الكيبل عند كلٍّ منهما: منه يُقرأ ما يعبر الكيبل نفسه.
///     المنفذ يُختار من منافذ الجهاز كما تُقرأ الآن ([readDevice])، أو يُكتب، أو يُترك لوقتٍ لاحق.
/// تُرجع الربط المحفوظ ([TowerApi.addLink])، أو null إن خرج بلا ربط.
class TowerLinkEditorScreen extends StatefulWidget {
  const TowerLinkEditorScreen({
    super.key,
    required this.devices,
    required this.towerName,
    required this.links,
    this.suggestions = const [],
    this.fromTower,
    this.fiberReady = false,
    this.readDevice,
    this.knownReading,
  });

  final List<NetworkDevice> devices;
  final String Function(int towerId) towerName;
  final List<TowerLink> links;
  final List<LinkSuggestion> suggestions;

  /// برجٌ فُتح الربط منه — أجهزته أوّلاً عند اختيار طرف الرئيسيّ.
  final int? fromTower;

  /// الخادم يحفظ الكيبل الضوئيّ (الهجرة 087) — false: اللنك اللاسلكيّ وحده.
  final bool fiberReady;

  /// قراءة منافذ جهازٍ الآن، وما عندنا عنه فوراً — لمنتقي منفذ الكيبل.
  final TowerDeviceReader? readDevice;
  final TowerReading? Function(int deviceId)? knownReading;

  @override
  State<TowerLinkEditorScreen> createState() => _TowerLinkEditorScreenState();
}

class _TowerLinkEditorScreenState extends State<TowerLinkEditorScreen> {
  TowerLinkKind _kind = TowerLinkKind.radio;
  NetworkDevice? _a;
  NetworkDevice? _b;
  String? _aPort;
  String? _bPort;
  bool _saving = false;

  bool get _fiber => _kind == TowerLinkKind.fiber;

  int _tower(NetworkDevice d) => d.regionId ?? 0;

  bool get _sameTower => _a != null && _b != null && _tower(_a!) == _tower(_b!);
  bool get _canSave => _a != null && _b != null && !_sameTower && !_saving;

  void _setKind(TowerLinkKind k) {
    if (k == _kind) return;
    HapticFeedback.selectionClick();
    // اللنك بين صحنين والكيبل بين سويجين — الطرفان يُختاران من جديد
    setState(() {
      _kind = k;
      _a = null;
      _b = null;
      _aPort = null;
      _bPort = null;
    });
  }

  Future<void> _pick({required bool main}) async {
    final other = main ? _b : _a;
    // لنكٌ لاسلكيّ واحد للطرف الفرعيّ (راديو واحد = وصلةٌ واحدة)؛ والسويج يقبل عدّة كيابل
    final radioSubs = {
      for (final l in widget.links)
        if (!l.isFiber) l.bDeviceId,
    };
    final picked = await showAppSheet<NetworkDevice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (_) => _DevicePickerSheet(
        title: main ? 'طرف البرج الرئيسي' : 'طرف البرج الفرعي',
        subtitle: _fiber
            ? (main ? 'السويج الذي يخرج منه الكيبل' : 'السويج الذي يصله الكيبل')
            : (main ? 'الماستر — منه يخرج الترافيك' : 'السليف — إليه يصل الترافيك'),
        devices: widget.devices,
        towerName: widget.towerName,
        current: main ? _a : _b,
        firstTower: main ? widget.fromTower : null,
        wiredFirst: _fiber,
        disabledWhy: (d) {
          if (other != null && d.id == other.id) return 'الطرف الآخر';
          if (other != null && _tower(d) == _tower(other)) return 'في برج الطرف الآخر';
          if (!_fiber && !main && radioSubs.contains(d.id)) return 'مربوطٌ بلنكٍ آخر';
          return null;
        },
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (main) {
        if (_a?.id != picked.id) _aPort = null;
        _a = picked;
      } else {
        if (_b?.id != picked.id) _bPort = null;
        _b = picked;
      }
    });
    // الكيبل: المنفذ مباشرةً بعد جهازه
    if (_fiber) await _pickPort(main: main);
  }

  Future<void> _pickPort({required bool main}) async {
    final d = main ? _a : _b;
    if (d == null) return;
    // قراءة الطرف الآخر (إن اختير منفذه وقُرئ جهازه) — بها يُعلَّم المنفذ المطابق عند هذا الطرف ([FiberPortMatch])
    final other = main ? _b : _a;
    final peer = other == null ? null : widget.knownReading?.call(other.id);
    final r = await showTowerPortPicker(
      context,
      device: d,
      main: main,
      current: main ? _aPort : _bPort,
      taken: fiberPortsTaken(widget.links, d.id),
      readDevice: widget.readDevice,
      known: widget.knownReading?.call(d.id),
      peer: peer?.port(main ? _bPort : _aPort),
      peerAt: peer?.at,
    );
    if (r == null || !mounted) return;
    setState(() => main ? _aPort = r.port : _bPort = r.port);
  }

  void _swap() {
    HapticFeedback.selectionClick();
    setState(() {
      final t = _a;
      _a = _b;
      _b = t;
      final p = _aPort;
      _aPort = _bPort;
      _bPort = p;
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final r = await TowerApi.addLink(_a!.id, _b!.id, kind: _kind, aPort: _fiber ? _aPort : null, bPort: _fiber ? _bPort : null);
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
    final suggestions = _fiber
        ? const <LinkSuggestion>[]
        : [
            for (final s in widget.suggestions)
              if (!(picked.contains(s.a.id) && picked.contains(s.b.id))) s,
          ];
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          title: const Text('ربط برجين'),
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
          if (widget.fiberReady) ...[
            SheetSegmented(
              labels: const ['لنك لاسلكي', 'كيبل ضوئي'],
              icons: const [LucideIcons.radioTower, LucideIcons.cable],
              selectedIndex: _fiber ? 1 : 0,
              onSelect: (i) => _setKind(i == 1 ? TowerLinkKind.fiber : TowerLinkKind.radio),
            ),
            const SizedBox(height: Sp.md),
          ],
          Text(
            _fiber
                ? 'كيبل ضوئي (فايبر) مباشر بين سويجين: اختر السويج بكلّ برج ومنفذ الكيبل فيه — يظهر ما يعبر ذاك المنفذ بالضبط، وسرعته، وضوء الـSFP إن كان الجهاز يقرؤه.'
                : 'اللنك يربط برجين: طرفه في البرج الرئيسي (الماستر) وطرفه في البرج الفرعي (السليف). الترافيك يُرسم سائراً من الرئيسي للفرعي.',
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
            keyName: 'main',
            step: '1',
            title: 'طرف البرج الرئيسي',
            hint: _fiber ? 'السويج الذي يخرج منه الكيبل' : 'الماستر — منه يخرج الترافيك',
            device: _a,
            port: _aPort,
            onTap: () => _pick(main: true),
            onPort: () => _pickPort(main: true),
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
            keyName: 'sub',
            step: '2',
            title: 'طرف البرج الفرعي',
            hint: _fiber ? 'السويج الذي يصله الكيبل' : 'السليف — إليه يصل الترافيك',
            device: _b,
            port: _bPort,
            onTap: () => _pick(main: false),
            onPort: () => _pickPort(main: false),
          ),
          if (_sameTower)
            Padding(
              padding: const EdgeInsets.only(top: Sp.sm),
              child: Text(_fiber ? 'الجهازان في البرج نفسه — الكيبل يربط برجين.' : 'الجهازان في البرج نفسه — اللنك يربط برجين.',
                  style: AppType.body(color: AppColors.error)),
            ),
          if (_fiber && _a != null && _b != null && _aPort == null && _bPort == null)
            Padding(
              padding: const EdgeInsets.only(top: Sp.sm),
              child: Text('بلا منفذ يُحفظ الربط ويُرسم، وما يعبر الكيبل يظهر حين تحدّد منفذه (من تفاصيله).',
                  style: AppType.muted(color: AppColors.textMid)),
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
                  : Icon(_fiber ? LucideIcons.cable : LucideIcons.link, size: 18),
              label: Text('احفظ الربط', style: AppType.buttonBold(color: _canSave || _saving ? AppColors.onBrand : AppColors.textLow)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _endCard({
    required String keyName,
    required String step,
    required String title,
    required String hint,
    required NetworkDevice? device,
    required String? port,
    required VoidCallback onTap,
    required VoidCallback onPort,
  }) {
    final d = device;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: d == null ? AppColors.border : AppColors.brand),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Semantics(
          button: true,
          child: Material(
            key: ValueKey('link-end-$keyName'),
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(Sp.md),
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
        ),
        // منفذ الكيبل عند هذا الطرف — بعد اختيار جهازه
        if (_fiber && d != null) ...[
          Container(height: 1, color: AppColors.divider),
          Semantics(
            button: true,
            child: Material(
              key: ValueKey('link-port-$keyName'),
              color: Colors.transparent,
              child: InkWell(
                onTap: onPort,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 11),
                  child: Row(children: [
                    Icon(LucideIcons.cable, size: 16, color: port == null ? AppColors.brand : AppColors.textMid),
                    const SizedBox(width: 8),
                    Text('المنفذ', style: AppType.muted(color: AppColors.textMid)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        port == null ? 'اختر المنفذ' : iso(port),
                        style: AppType.bodyBold(color: port == null ? AppColors.brand : AppColors.textHi),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// منافذ جهازٍ عليها كيبلٌ من قبل (طرفاً رئيسيّاً أو فرعيّاً) — منفذٌ واحد يحمل كيبلاً واحداً. [except] وصلةٌ تُستثنى (التي يُعدَّل منفذها).
Set<String> fiberPortsTaken(Iterable<TowerLink> links, int deviceId, {int? except}) => {
      for (final l in links)
        if (l.isFiber && l.id != except) ...[
          if (l.aDeviceId == deviceId && l.aPort != null) l.aPort!.toLowerCase(),
          if (l.bDeviceId == deviceId && l.bPort != null) l.bPort!.toLowerCase(),
        ],
    };

/// منتقي منفذ الكيبل عند [device]. يُرجع `(port: اسمه)`، أو `(port: null)` لـ«أحدّده لاحقاً»، أو null إن أُغلق بلا اختيار.
Future<({String? port})?> showTowerPortPicker(
  BuildContext context, {
  required NetworkDevice device,
  required bool main,
  String? current,
  Set<String> taken = const {},
  TowerDeviceReader? readDevice,
  TowerReading? known,
  PortTraffic? peer,
  DateTime? peerAt,
}) =>
    showAppSheet<({String? port})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (_) => _PortPickerSheet(
        device: device,
        main: main,
        current: current,
        taken: taken,
        readDevice: readDevice,
        known: known,
        peer: peer,
        peerAt: peerAt,
      ),
    );

/// منافذ الجهاز كما تُقرأ الآن — الشغّالة أوّلاً ومنافذ الـSFP قبل غيرها — بسرعتها وما يعبرها وضوئها، فيُعرف منفذ الكيبل منها.
/// الجهاز لا يُقرأ الآن (خارج الشبكة، بلا بيانات دخول)؟ يُكتب اسم المنفذ، أو يُترك لوقتٍ لاحق.
class _PortPickerSheet extends StatefulWidget {
  const _PortPickerSheet({
    required this.device,
    required this.main,
    required this.current,
    required this.taken,
    required this.readDevice,
    required this.known,
    this.peer,
    this.peerAt,
  });

  final NetworkDevice device;
  final bool main;
  final String? current;
  final Set<String> taken;
  final TowerDeviceReader? readDevice;
  final TowerReading? known;

  /// منفذ الطرف الآخر كما قُرئ ولحظة قراءته — المنفذ الذي يعبره مقداره معكوساً يُعلَّم «يطابق ما يعبر الطرف الآخر».
  final PortTraffic? peer;
  final DateTime? peerAt;

  @override
  State<_PortPickerSheet> createState() => _PortPickerSheetState();
}

class _PortPickerSheetState extends State<_PortPickerSheet> {
  final _manual = TextEditingController();
  TowerReading? _reading;
  bool _loading = false;
  Timer? _again;

  @override
  void initState() {
    super.initState();
    _reading = widget.known;
    _manual.text = widget.current ?? '';
    _loading = widget.readDevice != null && _reading == null;
    _read();
  }

  @override
  void dispose() {
    _again?.cancel();
    _manual.dispose();
    super.dispose();
  }

  bool get _hasRates => _reading?.wiredPorts.any((p) => p.rxBps != null || p.txBps != null) ?? false;

  /// القراءة الأولى بحال المنافذ؛ والسرعة فرقُ عدّادين فتُعاد مرّةً بعد ثوانٍ ليظهر ما يعبر كلّ منفذ.
  Future<void> _read({bool second = false}) async {
    final read = widget.readDevice;
    if (read == null) return;
    final r = await read(widget.device);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r != null) _reading = r;
    });
    if (!second && r != null && !_hasRates) {
      _again = Timer(const Duration(seconds: 4), () => _read(second: true));
    }
  }

  void _useManual() {
    final v = _manual.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (v.isEmpty || v.length > 64) return;
    // المكتوب كالمختار: منفذٌ عليه كيبلٌ آخر لا يُؤخذ
    if (widget.taken.contains(v.toLowerCase())) {
      showSheetSnack(context, 'على هذا المنفذ كيبلٌ آخر — اختر منفذاً غيره', isError: true, autoExplain: false);
      return;
    }
    // باسمه كما يكتبه الجهاز إن كان بين منافذه المقروءة
    Navigator.of(context).pop((port: _reading?.port(v)?.name ?? v));
  }

  @override
  Widget build(BuildContext context) {
    final ports = [...?_reading?.wiredPorts]..sort((x, y) {
        if (x.up != y.up) return x.up ? -1 : 1;
        final sx = x.name.toLowerCase().contains('sfp') ? 0 : 1;
        final sy = y.name.toLowerCase().contains('sfp') ? 0 : 1;
        if (sx != sy) return sx - sy;
        final t = y.total - x.total;
        return t != 0 ? t : naturalCompare(x.name, y.name);
      });
    final at = _reading?.at;
    final match = at == null || widget.peerAt == null
        ? null
        : FiberPortMatch.find(
            ports.where((p) => !widget.taken.contains(p.name.toLowerCase())),
            widget.peer,
            skew: at.difference(widget.peerAt!),
          );
    if (match != null) {
      // المطابق أوّلاً — هو منفذ الكيبل على الأرجح
      final i = ports.indexWhere((p) => p.name == match);
      if (i > 0) ports.insert(0, ports.removeAt(i));
    }
    return DesignSheet(
      scrollable: false,
      header: SheetHeaderBar(
        icon: LucideIcons.cable,
        title: 'منفذ الكيبل',
        subtitle: '${widget.device.name} — ${widget.main ? 'طرف الرئيسي' : 'طرف الفرعي'}',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.lg),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text('نقرأ منافذ الجهاز…', style: AppType.body(color: AppColors.textMid)),
            ]),
          )
        else if (ports.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.sm),
            child: Text(
              _reading == null
                  ? 'تعذّرت قراءة منافذ «${widget.device.name}» الآن — اكتب اسم المنفذ كما يسمّيه الجهاز، أو حدّده لاحقاً.'
                  : 'هذا الجهاز لا يعرض منافذه — اكتب اسم المنفذ كما يسمّيه، أو حدّده لاحقاً.',
              style: AppType.body(color: AppColors.textMid),
            ),
          )
        else
          Flexible(
            child: ListView(shrinkWrap: true, children: [for (final p in ports) _row(p, matches: p.name == match)]),
          ),
        const SizedBox(height: Sp.sm),
        Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('port-manual'),
              controller: _manual,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              enableSuggestions: false,
              style: AppType.body(color: AppColors.textHi),
              inputFormatters: [LengthLimitingTextInputFormatter(64)],
              onSubmitted: (_) => _useManual(),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'أو اكتب اسمه: sfp1',
                hintTextDirection: TextDirection.rtl,
                hintStyle: AppType.body(color: AppColors.textLow),
                filled: true,
                fillColor: AppColors.surfaceInput,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.sm), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const ValueKey('port-manual-use'),
            onPressed: _useManual,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brand,
              backgroundColor: AppColors.brandSoftBg,
              minimumSize: const Size(64, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm)),
            ),
            child: Text('استعمله', style: AppType.bodyBold(color: AppColors.brand)),
          ),
        ]),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            key: const ValueKey('port-later'),
            onPressed: () => Navigator.of(context).pop((port: null)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textMid,
              minimumSize: const Size(44, 40),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            child: Text(widget.current == null ? 'أحدّده لاحقاً' : 'بلا منفذ (أحدّده لاحقاً)', style: AppType.bodyStrong(color: AppColors.textMid)),
          ),
        ),
      ]),
    );
  }

  Widget _row(PortTraffic p, {bool matches = false}) {
    final on = (widget.current ?? '').toLowerCase() == p.name.toLowerCase();
    final off = !on && widget.taken.contains(p.name.toLowerCase());
    final facts = [
      if (p.rxBps != null || p.txBps != null) '↓ ${TowerText.bps(p.rxBps)} ↑ ${TowerText.bps(p.txBps)}',
      if (p.sfpRx != null) TopoText.lightFact(p.sfpRx),
      if (!p.up) 'طافي',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        key: ValueKey('pick-port-${p.name}'),
        color: on ? AppColors.brandSoftBg : AppColors.bg,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: off ? null : () => Navigator.of(context).pop((port: p.name)),
          child: Opacity(
            opacity: off ? 0.5 : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: p.up ? AppColors.success : AppColors.textLow, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(iso(p.name), style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (facts.isNotEmpty)
                      Text(isoJoin(facts, ' · '),
                          style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (matches)
                      Text('يطابق ما يعبر الطرف الآخر', style: AppType.microBold(color: AppColors.brand)),
                  ]),
                ),
                const SizedBox(width: 8),
                if (off)
                  Text('عليه كيبلٌ آخر', style: AppType.micro(color: AppColors.textMid))
                else ...[
                  if (p.up && (p.linkSpeed ?? '').isNotEmpty)
                    Text(iso(TopoText.speed(p.linkSpeed)), style: AppType.bodyStrong(color: AppColors.textMid)),
                  if (on) ...[
                    const SizedBox(width: 6),
                    Icon(LucideIcons.check, size: 18, color: AppColors.brand),
                  ],
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// منتقي جهازٍ لطرف ربط: الأجهزة ببرجها — صحون اللنكات أوّلاً للّنك اللاسلكيّ، والسويجات والراوترات للكيبل — وما لا يصلح
/// معطّلٌ بسببه.
class _DevicePickerSheet extends StatefulWidget {
  const _DevicePickerSheet({
    required this.title,
    required this.subtitle,
    required this.devices,
    required this.towerName,
    required this.disabledWhy,
    this.current,
    this.firstTower,
    this.wiredFirst = false,
  });

  final String title;
  final String subtitle;
  final List<NetworkDevice> devices;
  final String Function(int towerId) towerName;
  final String? Function(NetworkDevice d) disabledWhy;
  final NetworkDevice? current;
  final int? firstTower;

  /// الكيبل: السويجات والراوترات والأولت أوّلاً في كلّ برج (لا الصحون).
  final bool wiredFirst;

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
    const wired = {TowerShape.sw, TowerShape.router, TowerShape.olt};
    int rank(NetworkDevice d) {
      final shape = TowerShapes.detect(d).shape;
      return (widget.wiredFirst ? wired.contains(shape) : shape == TowerShape.dish) ? 0 : 1;
    }

    for (final list in byTower.values) {
      list.sort((x, y) {
        final r = rank(x) - rank(y);
        return r != 0 ? r : naturalCompare(x.name, y.name);
      });
    }
    return DesignSheet(
      scrollable: false,
      header: SheetHeaderBar(
        icon: widget.wiredFirst ? LucideIcons.cable : LucideIcons.link,
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
