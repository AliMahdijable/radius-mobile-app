import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core/widgets/app_sheet.dart';
import '../core/widgets/design_sheet.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'print_output.dart';

/// ما يختاره المستخدم بالهاتف: صورةٌ للمشاركة أو نافذة الطباعة (PDF).
enum OutputChoice { image, print }

/// «صورة» بالهاتف (٨ نوفمبر — المالك: «الوصولات بالهاتف صوره تكون اختيار افضل من pdf»): الوصل والسند يُشارَكان صورةً
/// (واتساب وغيره) بدل ملف PDF بمقاس الورق — الصورة من المستند نفسه كما يُطبع. التقارير لا (المالك: «التقرير المالي اني
/// ماردتك تسوي صورة… امسحها نفسه هو مو يسوي pdf واسكل»). الحاسبة كما كانت: نافذة الطباعة وحدها.
class PhoneOutput {
  PhoneOutput._();

  @visibleForTesting
  static bool? debugActive;

  /// الهاتف (أندرويد/آيفون) — لا الحاسبة ولا الويب.
  static bool get active => debugActive ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

  /// المتصفّح الجذر (main.dart) — منه تُفتح نافذة الاختيار للوصل: خدمةٌ تُستدعى بعد التفعيل بلا سياق.
  static GlobalKey<NavigatorState>? navigatorKey;

  /// عرض الصورة بالبكسل — يُقرأ واضحاً على شاشات الهواتف ولا يثقل واتساب.
  static const double targetWidthPx = 1080;

  /// أقصى صفحاتٍ تُشارَك صوراً.
  static const int maxImages = 15;

  /// PDF ⇒ صور PNG (صفحةٌ لكلّ صورة). تُستبدل في الاختبارات (لا مكتبة رسمٍ هناك).
  @visibleForTesting
  static Future<List<Uint8List>> Function(Uint8List pdf, double dpi) rasterizer = _raster;

  /// مجلّد الصور المؤقّت. يُستبدل في الاختبارات (لا path_provider هناك).
  @visibleForTesting
  static Future<Directory> Function() tempDir = getTemporaryDirectory;

  /// المشاركة ⇒ false إن أُغلقت بلا مشاركة. تُستبدل في الاختبارات.
  @visibleForTesting
  static Future<bool> Function(List<XFile> files, {String? text, Rect? origin}) sharer = _share;

  static Future<List<Uint8List>> _raster(Uint8List pdf, double dpi) async {
    final out = <Uint8List>[];
    await for (final page in Printing.raster(pdf, dpi: dpi)) {
      final img = await page.toImage();
      try {
        out.add(await onWhite(img));
      } finally {
        img.dispose();
      }
      if (out.length >= maxImages) break;
    }
    return out;
  }

  /// الصفحة على خلفيّةٍ بيضاء ⇒ PNG. 🐛 ٨ نوفمبر (المالك: «الوصل من اسوي صورة يطلع بدون خلفيه يعني شفافه وكلشي ميبين منه
  /// بس pdf طبيعي»): رسم أندرويد للـPDF يترك ما حول الحبر شفّافاً، فيعرضه واتساب والمعرض على خلفيّةٍ داكنة ويختفي النصّ الأسود.
  @visibleForTesting
  static Future<Uint8List> onWhite(ui.Image img) async {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawImage(img, ui.Offset.zero, ui.Paint());
    final pic = rec.endRecording();
    final flat = await pic.toImage(img.width, img.height);
    pic.dispose();
    try {
      final data = await flat.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('png');
      return data.buffer.asUint8List();
    } finally {
      flat.dispose();
    }
  }

  static Future<bool> _share(List<XFile> files, {String? text, Rect? origin}) async {
    // ignore: deprecated_member_use
    final r = await Share.shareXFiles(files, text: text, sharePositionOrigin: origin);
    return r.status != ShareResultStatus.dismissed;
  }

  /// دقّة الرسم لصفحةٍ بعرض [widthPt] حتى تخرج الصورة بعرض [targetWidthPx] تقريباً (وصل ٥٨/٨٠ ملم أو A4 أو صفحة الهاتف).
  static double dpiFor(double widthPt) {
    if (!widthPt.isFinite || widthPt <= 0) return 200;
    return (targetWidthPx * PdfPageFormat.inch / widthPt).clamp(96, 420).toDouble();
  }

  /// صورةٌ أم طباعة؟ — null إن أُغلقت بلا اختيار (لا شيء يحدث).
  static Future<OutputChoice?> choose(BuildContext context, {required String title}) {
    return showAppSheet<OutputChoice>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (ctx) => DesignSheet(
        header: SheetHeaderBar(
          icon: LucideIcons.share2,
          title: title,
          subtitle: 'الصورة تُقرأ على الهاتف وتُرسل بواتساب مباشرةً',
          onClose: () => Navigator.of(ctx).pop(),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ChoiceTile(
              key: const ValueKey('output-image'),
              icon: LucideIcons.image,
              title: 'صورة',
              hint: 'للمشاركة — واتساب وتلغرام وغيرهما',
              primary: true,
              onTap: () => Navigator.of(ctx).pop(OutputChoice.image),
            ),
            const SizedBox(height: Sp.sm),
            _ChoiceTile(
              key: const ValueKey('output-print'),
              icon: LucideIcons.printer,
              title: 'طباعة أو PDF',
              hint: 'نافذة الطباعة كما كانت',
              onTap: () => Navigator.of(ctx).pop(OutputChoice.print),
            ),
          ],
        ),
      ),
    );
  }

  /// صفحات [pdf] صوراً ⇒ نافذة المشاركة. [widthPt] عرض الصفحة (لدقّة الرسم).
  static Future<PrintResult> sharePdf(
    Uint8List pdf, {
    required double widthPt,
    required String name,
    String? text,
    Rect? origin,
  }) async {
    try {
      final pngs = await rasterizer(pdf, dpiFor(widthPt));
      if (pngs.isEmpty) return const PrintResult.failed('raster: no pages');
      return shareImages(pngs.take(maxImages).toList(), name: name, text: text, origin: origin);
    } catch (e) {
      if (kDebugMode) debugPrint('[PhoneOutput] raster failed: $e');
      return PrintResult.failed('raster: $e');
    }
  }

  /// صورٌ جاهزة ⇒ ملفّاتٌ مؤقّتة ⇒ نافذة المشاركة.
  static Future<PrintResult> shareImages(
    List<Uint8List> pngs, {
    required String name,
    String? text,
    Rect? origin,
  }) async {
    try {
      final dir = await tempDir();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final files = <XFile>[];
      for (var i = 0; i < pngs.length; i++) {
        final f = File('${dir.path}/${safe}_${ts}_${i + 1}.png');
        await f.writeAsBytes(pngs[i], flush: true);
        files.add(XFile(f.path, mimeType: 'image/png'));
      }
      final shared = await sharer(files, text: text, origin: origin ?? _origin());
      return shared ? PrintResult.shared(images: files.length) : const PrintResult.cancelled();
    } catch (e) {
      if (kDebugMode) debugPrint('[PhoneOutput] share failed: $e');
      return PrintResult.failed('share: $e');
    }
  }

  /// موضع نافذة المشاركة على الآيباد (إلزاميٌّ هناك) — وسط الشاشة حين لا زرّ.
  static Rect? _origin() {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) return null;
    final size = MediaQuery.maybeSizeOf(ctx);
    if (size == null) return null;
    return Rect.fromCenter(center: size.center(Offset.zero), width: 1, height: 1);
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = primary ? AppColors.brand : AppColors.textHi;
    return Material(
      color: primary ? AppColors.brandSoftBg : AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.lg),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: primary ? AppColors.brand.withValues(alpha: 0.35) : AppColors.border),
          ),
          child: Row(children: [
            Icon(icon, size: 22, color: fg),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: AppType.label(color: fg).copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(hint, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textLow),
          ]),
        ),
      ),
    );
  }
}
