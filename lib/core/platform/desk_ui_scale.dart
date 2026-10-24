import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'app_platform.dart';

/// حجم واجهة الحاسبة (المالك ٢٤ أكتوبر: «اكو حاسبات بيها شاشات صغار التطبيق يطلع بيها كلش جبير — لازم نسوي فد
/// داله تحسس الابعاد وتصحح»).
///
/// التصميم مضبوطٌ على شاشةٍ منطقيّة 1440×900. الشاشة الأصغر (1366×768، أو 1920×1080 بتكبير ويندوز 150٪ = 1280×720)
/// تصغر عليها الواجهة كلّها بنسبتها — نصوصٌ وأيقوناتٌ ومسافاتٌ معاً كتصغير المتصفّح — بخطوات 5٪ حتى 75٪، ولا تكبر
/// فوق 100٪ تلقائيّاً. القياس من **الشاشة** لا النافذة: تصغير النافذة باليد لا يغيّر حجم الخطّ وهو يُسحب.
///
/// والمدير يختار بنفسه: Ctrl و+ يكبّر، Ctrl و− يصغّر، Ctrl و0 يرجعه تلقائيّاً (⌘ على الماك)، أو من الإعدادات —
/// ويُحفظ على هذا الجهاز.
class DeskUiScale {
  DeskUiScale._();

  static const Size designSize = Size(1440, 900);
  static const double autoMin = 0.75;
  static const List<double> levels = [0.7, 0.75, 0.8, 0.85, 0.9, 1.0, 1.1, 1.25];

  static const _storage = FlutterSecureStorage();
  static const _key = 'desk.ui.scale.v1';

  /// اختيار المدير؛ null = تلقائيّ.
  static final ValueNotifier<double?> choice = ValueNotifier<double?>(null);

  /// المطبَّق الآن والتلقائيّ لهذه الشاشة — يحدّثهما [DeskUiScaleScope] (لقراراتٍ تقرأ النافذة مباشرة، وللإعدادات).
  static double current = 1;
  static double auto = 1;

  /// الحجم التلقائيّ لشاشةٍ بمقاسها المنطقيّ.
  static double autoFor(Size screen) {
    if (screen.isEmpty) return 1;
    final r = math.min(screen.width / designSize.width, screen.height / designSize.height);
    // خطوات 5٪ إلى الأسفل: 1366×768 ⇐ 85٪، 1280×720 ⇐ 80٪، 1536×864 ⇐ 95٪.
    final stepped = (r * 20 + 1e-6).floor() / 20;
    return stepped.clamp(autoMin, 1.0).toDouble();
  }

  /// مرّةً قبل runApp — فلا تقفز الواجهة من التلقائيّ إلى المختار بعد أوّل إطار.
  static Future<void> load() async {
    try {
      final v = double.tryParse(await _storage.read(key: _key) ?? '');
      if (v != null && v >= 0.5 && v <= 2) choice.value = v;
    } catch (_) {}
  }

  static Future<void> set(double? v) async {
    choice.value = v;
    try {
      if (v == null) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: v.toStringAsFixed(2));
      }
    } catch (_) {}
  }

  static void zoomIn() =>
      set(levels.firstWhere((l) => l > current + 0.001, orElse: () => levels.last));

  static void zoomOut() =>
      set(levels.lastWhere((l) => l < current - 0.001, orElse: () => levels.first));

  static void reset() => set(null);

  /// «85٪».
  static String percent(double v) => '${(v * 100).round()}٪';
}

/// يلفّ التطبيق كلّه على الحاسبة (في `MaterialApp.builder`، فوق الـNavigator — النوافذ والقوائم والتلميحات معه):
/// يصغّر بالحجم المطبَّق، ويلتقط Ctrl + / − / 0، ويُظهر الحجم الجديد لحظةً حين يتغيّر.
class DeskUiScaleScope extends StatelessWidget {
  const DeskUiScaleScope({super.key, required this.child});

  final Widget child;

  /// مقاس الشاشة المنطقيّ (الشاشة التي عليها النافذة)؛ وإن لم يُعرف فالنافذة.
  static Size screenOf(BuildContext context) {
    final view = View.of(context);
    try {
      final d = view.display;
      final s = d.size / d.devicePixelRatio;
      if (!s.isEmpty) return s;
    } catch (_) {}
    return view.physicalSize / view.devicePixelRatio;
  }

  @override
  Widget build(BuildContext context) {
    if (!AppPlatform.isDesktop) return child;
    // يُعاد الحساب حين تنتقل النافذة لشاشةٍ بكثافةٍ أخرى أو يتغيّر مقاسها.
    MediaQuery.sizeOf(context);
    MediaQuery.devicePixelRatioOf(context);
    final mac = AppPlatform.isMacDesktop;
    SingleActivator key(LogicalKeyboardKey k, {bool shift = false}) =>
        SingleActivator(k, control: !mac, meta: mac, shift: shift);
    return CallbackShortcuts(
      bindings: {
        key(LogicalKeyboardKey.equal): DeskUiScale.zoomIn,
        key(LogicalKeyboardKey.equal, shift: true): DeskUiScale.zoomIn,
        key(LogicalKeyboardKey.add): DeskUiScale.zoomIn,
        key(LogicalKeyboardKey.numpadAdd): DeskUiScale.zoomIn,
        key(LogicalKeyboardKey.minus): DeskUiScale.zoomOut,
        key(LogicalKeyboardKey.numpadSubtract): DeskUiScale.zoomOut,
        key(LogicalKeyboardKey.digit0): DeskUiScale.reset,
        key(LogicalKeyboardKey.numpad0): DeskUiScale.reset,
      },
      child: ValueListenableBuilder<double?>(
        valueListenable: DeskUiScale.choice,
        builder: (context, choice, _) {
          final auto = DeskUiScale.autoFor(screenOf(context));
          final s = choice ?? auto;
          DeskUiScale.auto = auto;
          DeskUiScale.current = s;
          return Stack(
            children: [
              Positioned.fill(child: (s - 1).abs() < 0.001 ? child : _Scaled(scale: s, child: child)),
              const _ScaleFlash(),
            ],
          );
        },
      ),
    );
  }
}

/// الابن يُبنى بمقاسٍ منطقيٍّ أكبر (المقاس ÷ [scale]) ثمّ يُرسم مصغَّراً ليملأ النافذة — والنقر والتمرير والكتابة
/// تمرّ عبر التحويل. MediaQuery بالداخل بالمقاس المنطقيّ، فالشاشات تقرّر على ما تراه فعلاً.
class _Scaled extends StatelessWidget {
  const _Scaled({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth / scale;
      final h = c.maxHeight / scale;
      final mq = MediaQuery.of(context);
      return FittedBox(
        fit: BoxFit.fill,
        alignment: AlignmentDirectional.topStart,
        child: SizedBox(
          width: w,
          height: h,
          child: MediaQuery(data: mq.copyWith(size: Size(w, h)), child: child),
        ),
      );
    });
  }
}

/// «حجم الواجهة 90٪» أعلى الشاشة ثانيةً ونصف بعد كلّ تغيير — بحجمه الحقيقيّ خارج التصغير.
class _ScaleFlash extends StatefulWidget {
  const _ScaleFlash();

  @override
  State<_ScaleFlash> createState() => _ScaleFlashState();
}

class _ScaleFlashState extends State<_ScaleFlash> {
  Timer? _hide;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    DeskUiScale.choice.addListener(_changed);
  }

  void _changed() {
    _hide?.cancel();
    setState(() => _show = true);
    _hide = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _show = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    DeskUiScale.choice.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = DeskUiScale.choice.value;
    final text = c == null
        ? 'desktop.ui_scale_flash_auto'.tr(args: [DeskUiScale.percent(DeskUiScale.auto)])
        : 'desktop.ui_scale_flash'.tr(args: [DeskUiScale.percent(c)]);
    return Positioned(
      top: 18,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _show ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: Center(
            child: Material(
              color: AppColors.textHi,
              borderRadius: BorderRadius.circular(R.pill),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.sm),
                child: Text(
                  text,
                  style: AppType.bodyBold(color: AppColors.surface).copyWith(
                    fontSize: 14,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// اختيار الحجم من الإعدادات: تلقائيّ (بنسبته لهذه الشاشة) أو أحد المستويات.
Future<void> showDeskUiScaleDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => ValueListenableBuilder<double?>(
      valueListenable: DeskUiScale.choice,
      builder: (dialogCtx, c, _) {
        Widget option(double? v, String label) {
          final on = c == v || (v != null && c != null && (c - v).abs() < 0.001);
          return ListTile(
            dense: true,
            leading: Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: on ? AppColors.brand : AppColors.textLow),
            title: Text(label, style: AppType.body(color: AppColors.textHi)),
            onTap: () => DeskUiScale.set(v),
          );
        }

        return AlertDialog(
          title: Text('desktop.ui_scale'.tr()),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                option(null, 'desktop.ui_scale_auto'.tr(args: [DeskUiScale.percent(DeskUiScale.auto)])),
                for (final l in DeskUiScale.levels) option(l, DeskUiScale.percent(l)),
                const SizedBox(height: Sp.sm),
                Text('desktop.ui_scale_hint'.tr(),
                    style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: Text('common.close'.tr())),
          ],
        );
      },
    ),
  );
}
