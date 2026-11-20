import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_platform.dart';

/// «حجم العرض» على الهاتف (المالك ٢٠ نوفمبر ٢٠٢٦، بلقطتَي إعدادات التطبيق وإعدادات الهاتف: «نحتاج فد شي نكبر بي خط للعالم مجاي
/// تشوف»).
///
/// يكبّر **الواجهة كلّها** — النصوص والأزرار والأيقونات والمسافات معاً — كتكبير المتصفّح، لا الخطّ وحده: كلّ الشاشات مفحوصةٌ على عرض
/// 320 وخطٍّ ×1.2 (أقصى ما يسمح به التطبيق من خطّ الهاتف)، والخطّ وحده فوقها يقصّ الأرقام ويُخرج النصوص من بطاقاتها. فالتكبير هنا
/// يرسم التطبيق بعرضٍ منطقيٍّ أصغر ثمّ يكبّره ليملأ الشاشة، ولا ينزل ذلك العرض تحت 320 أبداً: «كبير جداً» أكبر ما تتّسع له
/// الشاشة حتى 130٪ (هاتفٌ 390 ⇐ 121٪، 430 ⇐ 130٪)، و«كبير» نصفه. ويُقاس بأقصر ضلعَي الشاشة فلا يتغيّر بتدوير الهاتف.
///
/// الحاسبة لها «حجم الواجهة» الخاصّ بها ([DeskUiScale]) — هذا للهاتف والتابلت وحدهما. يُحفظ على هذا الجهاز ويبقى بعد الخروج.
enum DisplaySize { normal, large, xlarge }

class DisplaySizePref {
  DisplaySizePref._();

  /// أضيق عرضٍ منطقيٍّ فُحصت عليه الشاشات — التكبير لا ينزل تحته.
  static const double minLogicalWidth = 320;

  /// سقف التكبير مهما اتّسعت الشاشة (التابلت).
  static const double maxScale = 1.3;

  static const _storage = FlutterSecureStorage(
    // كخزنة المظهر (ThemeService): خطأ قراءةٍ عابر لا يحذف المفتاح.
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  static const _key = 'app.display_size.v1';

  static final ValueNotifier<DisplaySize> choice = ValueNotifier<DisplaySize>(DisplaySize.normal);

  /// مرّةً قبل runApp — فلا تقفز الواجهة بعد أوّل إطار. تعذّر القراءة ⇒ «عادي» (تفضيلٌ لا أكثر).
  static Future<void> load() async {
    try {
      final v = await _storage.read(key: _key);
      choice.value = DisplaySize.values.firstWhere((s) => s.name == v, orElse: () => DisplaySize.normal);
    } catch (_) {
      choice.value = DisplaySize.normal;
    }
  }

  static Future<void> set(DisplaySize v) async {
    choice.value = v;
    try {
      if (v == DisplaySize.normal) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: v.name);
      }
    } catch (_) {}
  }

  /// أكبر تكبيرٍ تتّسع له شاشةٌ بمقاسها المنطقيّ ([screen]): أقصر ضلعيها ÷ 320 حتى 130٪، بخطوات 1٪ إلى الأسفل
  /// (فلا يصير العرض 319.9).
  static double maxFor(Size screen) {
    if (screen.isEmpty) return 1;
    final r = screen.shortestSide / minLogicalWidth;
    return ((math.min(r, maxScale) * 100 + 1e-6).floor() / 100).clamp(1.0, maxScale).toDouble();
  }

  /// التكبير لاختيارٍ على هذه الشاشة.
  static double scaleFor(DisplaySize s, Size screen) {
    final m = maxFor(screen);
    return switch (s) {
      DisplaySize.normal => 1.0,
      DisplaySize.large => ((1 + (m - 1) / 2) * 100 + 1e-6).floor() / 100,
      DisplaySize.xlarge => m,
    };
  }

  /// «121٪».
  static String percent(double v) => '${(v * 100).round()}٪';
}

/// يلفّ التطبيق كلّه على الهاتف (في `MaterialApp.builder`، فوق الـNavigator — النوافذ والقوائم والرسائل معه).
///
/// تغيير الحجم لا يعيد بناء التطبيق: ما تحته محمولٌ بمفتاحٍ ثابت ([GlobalKey]) فيُنقل كما هو بين «بلا تكبير» و«مكبَّر» — الشاشة
/// المفتوحة وما كُتب فيها يبقيان (يُختار الحجم من الإعدادات والمدير فيها).
class DisplaySizeScope extends StatefulWidget {
  const DisplaySizeScope({super.key, required this.child});

  final Widget child;

  @override
  State<DisplaySizeScope> createState() => _DisplaySizeScopeState();
}

class _DisplaySizeScopeState extends State<DisplaySizeScope> {
  final _subtree = GlobalKey(debugLabel: 'display-size-subtree');

  @override
  Widget build(BuildContext context) {
    if (AppPlatform.isDesktop) return widget.child;
    final screen = MediaQuery.sizeOf(context);
    final child = KeyedSubtree(key: _subtree, child: widget.child);
    return ValueListenableBuilder<DisplaySize>(
      valueListenable: DisplaySizePref.choice,
      builder: (context, s, _) {
        final scale = DisplaySizePref.scaleFor(s, screen);
        return (scale - 1).abs() < 0.001 ? child : DisplayZoom(scale: scale, child: child);
      },
    );
  }
}

/// الابن يُبنى بمقاسٍ منطقيٍّ أصغر (المقاس ÷ [scale]) ثمّ يُرسم مكبَّراً ليملأ الشاشة — والنقر والتمرير والكتابة تمرّ عبر
/// التحويل. وفي الداخل MediaQuery بالمقاس المنطقيّ نفسه، ومعه حواشي الشاشة (الشقّ وشريط الإيماءات) **ولوحة المفاتيح** مقسومةً على
/// التكبير — فتُرفع الأوراق فوق اللوحة بقدرها تماماً لا أكثر.
@visibleForTesting
class DisplayZoom extends StatelessWidget {
  const DisplayZoom({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth / scale;
      final h = c.maxHeight / scale;
      return FittedBox(
        fit: BoxFit.fill,
        alignment: AlignmentDirectional.topStart,
        child: SizedBox(
          width: w,
          height: h,
          child: MediaQuery(
            data: mq.copyWith(
              size: Size(w, h),
              padding: mq.padding / scale,
              viewPadding: mq.viewPadding / scale,
              viewInsets: mq.viewInsets / scale,
              systemGestureInsets: mq.systemGestureInsets / scale,
              devicePixelRatio: mq.devicePixelRatio * scale,
            ),
            child: child,
          ),
        ),
      );
    });
  }
}
