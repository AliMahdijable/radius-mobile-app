import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/tower_api.dart';
import '../../../core/util/bidi.dart';
import '../../../core/widgets/permission_locked.dart';
import '../../../models/network_device.dart';
import '../../../models/tower_layout.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';
import 'tower_logic.dart';
import 'tower_paint.dart';
import 'tower_place_screen.dart';
import 'tower_reading.dart';

/// ما يرجع لشاشة البرج: الشكل والمواقع كما صارت، و«افتح جولة البوصلة» إن اختارها الوكيل.
class TowerBuilderResult {
  const TowerBuilderResult({required this.settings, required this.saved, this.openTour = false});

  final TowerSettings settings;
  final Map<int, TowerPlacement> saved;
  final bool openTour;
}

/// بناء البرج — المالك ٢٧ أكتوبر: «يكدر كل وكيل يتحكم برسم البرج واضافت الاجهزه، او النظام ينقر على زر يفضهن بشكل
/// سحري». تلقائيّ: «رتّبها لي» يقرأ الأجهزة ويضع كلّاً بشكله ومكانه (حتميّ لا عشوائيّ — ما لا نعرفه يبقى «تقريبيّاً»
/// حتى يُثبَّت بالبوصلة). يدويّ: شكل البرج وارتفاعه وحلقاته، وكلّ جهاز بمكانه.
class TowerBuilderScreen extends StatefulWidget {
  const TowerBuilderScreen({
    super.key,
    required this.regionId,
    required this.regionName,
    required this.devices,
    required this.readings,
    required this.saved,
    required this.settings,
    required this.canEdit,
    required this.serverReady,
  });

  final int regionId;
  final String regionName;
  final List<NetworkDevice> devices;
  final Map<int, TowerReading> readings;
  final Map<int, TowerPlacement> saved;
  final TowerSettings settings;
  final bool canEdit;

  /// جلب الترتيب نجح — وإلّا فالحفظ لا يصل للخادم والتعديل يبقى على هذا الهاتف.
  final bool serverReady;

  @override
  State<TowerBuilderScreen> createState() => _TowerBuilderScreenState();
}

class _TowerBuilderScreenState extends State<TowerBuilderScreen> {
  static const _steps = [
    'يقرأ موديلات الأجهزة ويعرف شكل كلّ جهاز',
    'يحدّد الدور من الوايرلس وعدد المتّصلين',
    'يوزّع المستويات: اللنكات فوق والسكاترات حلقتين',
    'يضع الاتّجاهات المعروفة ويُعلّم الباقي تقريبيّاً',
  ];

  late TowerSettings _settings = widget.settings;
  late Map<int, TowerPlacement> _saved = Map.of(widget.saved);
  bool _manual = false;

  /// -1 لم يُشغَّل · 0..3 الخطوة الجارية · 4 انتهى.
  int _step = -1;
  Map<int, ArrangedDevice>? _result;
  bool _saving = false;
  Timer? _stepTimer;
  Timer? _settingsSave;

  bool get _canSave => widget.canEdit && widget.serverReady;

  Map<int, ArrangedDevice> get _arranged =>
      TowerArrange.arrange(widget.devices, readings: widget.readings, saved: _saved);

  @override
  void dispose() {
    _stepTimer?.cancel();
    if (_settingsSave?.isActive ?? false) {
      _settingsSave!.cancel();
      _saveSettingsNow();
    }
    super.dispose();
  }

  void _finish({bool openTour = false}) {
    Navigator.of(context).pop(TowerBuilderResult(settings: _settings, saved: _saved, openTour: openTour));
  }

  // ── رتّبها لي ──────────────────────────────────────────────────────────────────────────

  void _runArrange() {
    if (!widget.canEdit) {
      showNoPermission(context, action: true);
      return;
    }
    if (_step >= 0 && _step < _steps.length) return;
    HapticFeedback.selectionClick();
    final result = TowerArrange.arrange(widget.devices, readings: widget.readings, saved: _saved, rearrange: true);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    setState(() {
      _result = result;
      _step = still ? _steps.length : 0;
    });
    if (still) return;
    _stepTimer?.cancel();
    _stepTimer = Timer.periodic(const Duration(milliseconds: 340), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _step++);
      if (_step >= _steps.length) t.cancel();
    });
  }

  Future<void> _accept({required bool tour}) async {
    final result = _result;
    if (result == null || _saving) return;
    final next = {..._saved, for (final a in result.values) a.device.id: a.placement};
    if (_canSave) {
      setState(() => _saving = true);
      final r = await TowerApi.savePlacements(result.values.map((a) => a.placement));
      if (!mounted) return;
      setState(() => _saving = false);
      if (!r.ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'تعذّر حفظ الترتيب')));
        return;
      }
    }
    _saved = next;
    _finish(openTour: tour);
  }

  // ── شكل البرج ──────────────────────────────────────────────────────────────────────────

  void _setSettings(TowerSettings s) {
    if (!widget.canEdit) {
      showNoPermission(context, action: true);
      return;
    }
    if (s == _settings) return;
    HapticFeedback.selectionClick();
    setState(() => _settings = s);
    // نقراتٌ متتالية على «+» تُحفظ مرّةً واحدة.
    _settingsSave?.cancel();
    _settingsSave = Timer(const Duration(milliseconds: 700), _saveSettingsNow);
  }

  Future<void> _saveSettingsNow() async {
    if (!_canSave) return;
    final r = await TowerApi.saveTower(_settings);
    if (!r.ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'تعذّر حفظ شكل البرج')));
    }
  }

  Future<void> _openPlace(int deviceId) async {
    if (!widget.canEdit) {
      showNoPermission(context, action: true);
      return;
    }
    final res = await Navigator.of(context).push<Map<int, TowerPlacement>>(MaterialPageRoute(
      builder: (_) => TowerPlaceScreen(
        devices: widget.devices,
        arranged: _arranged,
        startDeviceId: deviceId,
        settings: _settings,
        serverReady: widget.serverReady,
      ),
    ));
    if (res == null || res.isEmpty || !mounted) return;
    setState(() => _saved = {..._saved, ...res});
  }

  // ── البناء ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            title: const Text('بناء البرج'),
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textHi,
            elevation: 0,
            leading: IconButton(icon: const Icon(LucideIcons.arrowRight, size: 20), onPressed: _finish),
          ),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Inset.route(context) + Sp.lg),
          children: [
            _intro(),
            if (!widget.serverReady) ...[const SizedBox(height: Sp.sm), _offlineNote()],
            const SizedBox(height: Sp.md),
            _tabs(),
            const SizedBox(height: Sp.md),
            if (_manual) ..._manualBody() else ..._autoBody(),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(Sp.md)}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  Widget _intro() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('«${widget.regionName}» · ${widget.devices.length} جهازاً',
            style: AppType.cardTitleBold(color: AppColors.textHi)),
        const SizedBox(height: 2),
        Text('كلّ منطقة في قسم الأجهزة تصير برجاً، وأجهزتها تُضاف إليه تلقائيّاً.',
            style: AppType.muted(color: AppColors.textMid)),
      ]);

  Widget _offlineNote() => Container(
        padding: const EdgeInsets.all(Sp.sm),
        decoration: BoxDecoration(color: AppTone.warning.softBg, borderRadius: BorderRadius.circular(R.md)),
        child: Row(children: [
          Icon(LucideIcons.cloudOff, size: 16, color: AppTone.warning.onSoft),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text('الحفظ غير متاح الآن — ما تغيّره يظهر على هذا الهاتف ولا يُحفظ.',
                style: AppType.body(color: AppTone.warning.onSoft)),
          ),
        ]),
      );

  Widget _tabs() {
    Widget seg(bool manual, String label, IconData icon) {
      final on = _manual == manual;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: InkWell(
            onTap: () => setState(() => _manual = manual),
            borderRadius: BorderRadius.circular(R.sm),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: on ? AppColors.surface : null, borderRadius: BorderRadius.circular(R.sm)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 16, color: on ? AppColors.brand : AppColors.textMid),
                const SizedBox(width: 6),
                Text(label, style: AppType.bodyStrong(color: on ? AppColors.brand : AppColors.textMid)),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
      child: Row(children: [
        seg(false, 'تلقائيّ', LucideIcons.sparkles),
        const SizedBox(width: 3),
        seg(true, 'يدويّ', LucideIcons.hand),
      ]),
    );
  }

  // ── التلقائيّ ──────────────────────────────────────────────────────────────────────────

  List<Widget> _autoBody() {
    final running = _step >= 0 && _step < _steps.length;
    final done = _step >= _steps.length && _result != null;
    return [
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.chip)),
              child: Icon(LucideIcons.wandSparkles, size: 22, color: AppColors.brand),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('رتّبها لي', style: AppType.cardTitleBold(color: AppColors.textHi)),
                Text('يقرأ أجهزتك ويضع كلّ جهاز بشكله ومكانه خلال ثوانٍ',
                    style: AppType.muted(color: AppColors.textMid)),
              ]),
            ),
          ]),
          const SizedBox(height: Sp.md),
          FilledButton.icon(
            onPressed: running ? null : _runArrange,
            icon: Icon(done ? LucideIcons.rotateCcw : LucideIcons.sparkles, size: 18),
            label: Text(running ? 'يرتّب…' : (done ? 'رتّبها من جديد' : 'رتّبها لي')),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          ),
          if (_step >= 0) ...[const SizedBox(height: Sp.md), _stepsList()],
        ]),
      ),
      if (done) ...[const SizedBox(height: Sp.md), _resultCard(_result!)],
      if (!done) ...[const SizedBox(height: Sp.md), _howItWorks()],
    ];
  }

  Widget _stepsList() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < _steps.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(
              width: 20,
              height: 20,
              child: i < _step
                  ? Icon(LucideIcons.circleCheck, size: 18, color: AppColors.success)
                  : i == _step
                      ? const Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(LucideIcons.circle, size: 16, color: AppColors.textLow),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text(_steps[i],
                  style: AppType.body(color: i <= _step ? AppColors.textHi : AppColors.textLow)),
            ),
          ]),
        ),
    ]);
  }

  Widget _howItWorks() {
    Widget row(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: AppColors.brand),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: AppType.bodyStrong(color: AppColors.textHi)),
                Text(iso(body), style: AppType.muted(color: AppColors.textMid)),
              ]),
            ),
          ]),
        );
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('كيف يرتّبها؟', style: AppType.bodyStrong(color: AppColors.textHi)),
        const SizedBox(height: 4),
        row(LucideIcons.shapes, 'الشكل', 'من الموديل: BaseBox سكتر، PowerBeam صحن، SXT لوحة، CCR راوتر'),
        row(LucideIcons.users, 'الدور', 'من وضع الوايرلس وعدد المتّصلين: مشتركون كثيرون = سكتر، طرفٌ واحد = لنك'),
        row(LucideIcons.layers, 'المستوى', 'اللنكات في القمّة، والسكاترات على حلقتين متناوبتين، والراوتر والسويجات في الكابينة'),
        row(LucideIcons.compass, 'الاتّجاه',
            'من اسم الجهاز إن ذكره (شمال، 120°…)، وإلّا يُوزَّع ويظهر «تقريبيّاً» حتى تثبّته بالبوصلة'),
      ]),
    );
  }

  Widget _resultCard(Map<int, ArrangedDevice> r) {
    final onTower = r.values.where((a) => a.onTower).toList();
    final fixed = onTower.where((a) => a.fixed).length;
    final approx = onTower.length - fixed;
    final cabinet = r.length - onTower.length;
    final notes = <String>[
      for (final a in r.values)
        if (a.nameSaysSectorButLink) '«${a.device.name}» اسمه سكتر لكنّه يعمل لنكاً — رُسم صحناً في القمّة',
      if (r.values.any((a) => a.azimuthSource == AzimuthSource.name))
        '${r.values.where((a) => a.azimuthSource == AzimuthSource.name).length} جهاز اتّجاهه من اسمه',
    ];
    Widget stat(String label, int n, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
            child: Column(children: [
              Text('$n', style: AppType.statValue(color: color)),
              Text(label, style: AppType.muted(color: AppColors.textMid)),
            ]),
          ),
        );
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(LucideIcons.circleCheck, size: 18, color: AppColors.success),
          const SizedBox(width: 6),
          Text('النتيجة · جاهز للعرض', style: AppType.bodyStrong(color: AppColors.textHi)),
        ]),
        const SizedBox(height: Sp.sm),
        Row(children: [
          stat('مثبّت', fixed, AppColors.success),
          const SizedBox(width: Sp.sm),
          stat('تقريبيّ', approx, AppColors.warning),
          const SizedBox(width: Sp.sm),
          stat('في الكابينة', cabinet, AppColors.textMid),
        ]),
        const SizedBox(height: Sp.sm),
        Text('ما نعرفه بالضبط يظهر «مثبّتاً»، والباقي «تقريبيّ» بخطّ متقطّع حتى تثبّته. لا نخمّن الاتّجاه عشوائيّاً.',
            style: AppType.muted(color: AppColors.textMid)),
        for (final n in notes) ...[
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(LucideIcons.info, size: 14, color: AppColors.info),
            const SizedBox(width: 6),
            Expanded(child: Text(iso(n), style: AppType.body(color: AppColors.textBody))),
          ]),
        ],
        const SizedBox(height: Sp.md),
        if (approx > 0)
          FilledButton.icon(
            onPressed: _saving ? null : () => _accept(tour: true),
            icon: const Icon(LucideIcons.compass, size: 18),
            label: const Text('ثبّت الاتّجاهات بجولة بوصلة'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          ),
        if (approx > 0) const SizedBox(height: Sp.sm),
        OutlinedButton(
          onPressed: _saving ? null : () => _accept(tour: false),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          child: Text(_saving ? 'يحفظ…' : 'اعرض البرج الآن'),
        ),
        if (approx > 0) ...[
          const SizedBox(height: 6),
          Text('الجولة دقيقتان تقريباً: تقف عند البرج وتوجّه الهاتف نحو كلّ جهاز.',
              textAlign: TextAlign.center, style: AppType.micro(color: AppColors.textMid)),
        ],
      ]),
    );
  }

  // ── اليدويّ ────────────────────────────────────────────────────────────────────────────

  List<Widget> _manualBody() {
    final arranged = _arranged.values.toList()
      ..sort((a, b) {
        final c = a.level.index.compareTo(b.level.index);
        return c != 0 ? c : (a.azimuth ?? 0).compareTo(b.azimuth ?? 0);
      });
    return [
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('شكل البرج', style: AppType.bodyStrong(color: AppColors.textHi)),
          const SizedBox(height: Sp.sm),
          Row(children: [
            for (final (i, t) in TowerType.values.indexed) ...[
              if (i > 0) const SizedBox(width: Sp.sm),
              Expanded(child: _typeTile(t)),
            ],
          ]),
          const SizedBox(height: Sp.md),
          _stepper(
            title: 'الارتفاع',
            hint: 'يطوّل البرج بالرسم',
            value: '${_settings.heightM} م',
            onMinus: _settings.heightM <= TowerSettings.minHeight
                ? null
                : () => _setSettings(_settings.copyWith(heightM: _settings.heightM - 3)),
            onPlus: _settings.heightM >= TowerSettings.maxHeight
                ? null
                : () => _setSettings(_settings.copyWith(heightM: _settings.heightM + 3)),
          ),
          const SizedBox(height: Sp.sm),
          _stepper(
            title: 'حلقات التثبيت',
            hint: 'مستويات تركيب الأجهزة',
            value: '${_settings.rings}',
            onMinus: _settings.rings <= TowerSettings.minRings
                ? null
                : () => _setSettings(_settings.copyWith(rings: _settings.rings - 1)),
            onPlus: _settings.rings >= TowerSettings.maxRings
                ? null
                : () => _setSettings(_settings.copyWith(rings: _settings.rings + 1)),
          ),
        ]),
      ),
      const SizedBox(height: Sp.md),
      _card(
        padding: const EdgeInsets.symmetric(vertical: Sp.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 4),
            child: Text('الأجهزة على البرج · ${arranged.length}',
                style: AppType.bodyStrong(color: AppColors.textHi)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, 4),
            child: Text('اضغط جهازاً لتغيير شكله أو مستواه أو اتّجاهه.', style: AppType.muted(color: AppColors.textMid)),
          ),
          for (final a in arranged) _deviceRow(a),
        ]),
      ),
    ];
  }

  Widget _typeTile(TowerType t) {
    final on = _settings.type == t;
    final icon = switch (t) {
      TowerType.lattice => LucideIcons.radioTower,
      TowerType.pole => LucideIcons.antenna,
      TowerType.roof => LucideIcons.building2,
    };
    return Semantics(
      button: true,
      selected: on,
      child: InkWell(
        onTap: () => _setSettings(_settings.copyWith(type: t)),
        borderRadius: BorderRadius.circular(R.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: on ? AppColors.brandSoftBg : AppColors.surface,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: on ? AppColors.brand : AppColors.border, width: on ? 1.5 : 1),
          ),
          child: Column(children: [
            Icon(icon, size: 22, color: on ? AppColors.brand : AppColors.textMid),
            const SizedBox(height: 4),
            Text(TowerText.type(t), style: AppType.bodyStrong(color: on ? AppColors.brand : AppColors.textHi)),
          ]),
        ),
      ),
    );
  }

  Widget _stepper({
    required String title,
    required String hint,
    required String value,
    required VoidCallback? onMinus,
    required VoidCallback? onPlus,
  }) {
    Widget btn(IconData icon, VoidCallback? onTap, String label) => Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(R.sm),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: Icon(icon, size: 18, color: onTap == null ? AppColors.textLow : AppColors.textHi),
            ),
          ),
        );
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppType.bodyStrong(color: AppColors.textHi)),
          Text(hint, style: AppType.muted(color: AppColors.textMid)),
        ]),
      ),
      btn(LucideIcons.minus, onMinus, 'نقّص $title'),
      SizedBox(
        width: 64,
        child: Text(value, textAlign: TextAlign.center, style: AppType.bodyStrong(color: AppColors.textHi)),
      ),
      btn(LucideIcons.plus, onPlus, 'زِد $title'),
    ]);
  }

  Widget _deviceRow(ArrangedDevice a) {
    final where = a.azimuth == null
        ? TowerText.level(a.level)
        : '${TowerText.levelShort(a.level)} · ${TowerText.dir(a.azimuth!)} ${a.azimuth}°';
    final tone = !a.onTower ? AppTone.neutral : (a.fixed ? AppTone.success : AppTone.warning);
    return InkWell(
      onTap: () => _openPlace(a.device.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 9),
        child: Row(children: [
          SizedBox(
            width: 40,
            height: 40,
            child: Center(child: DeviceGlyph(shape: a.shape, size: 28, color: AppColors.brand, dashed: a.onTower && !a.fixed)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.device.name,
                  style: AppType.bodyStrong(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(iso('${TowerText.shape(a.shape)} · $where'),
                  style: AppType.muted(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.pill)),
            child: Text(!a.onTower ? 'الكابينة' : (a.fixed ? 'مثبّت' : 'تقريبيّ'),
                style: AppType.pillBold(color: tone.onSoft)),
          ),
          const SizedBox(width: 4),
          Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textLow),
        ]),
      ),
    );
  }
}
