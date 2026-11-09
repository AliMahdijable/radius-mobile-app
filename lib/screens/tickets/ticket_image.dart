import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/tickets_api.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// صور «التذاكر» (المالك ٩ نوفمبر: «نعم اكو إمكانية صورة ولا تنسى ضغط الصورة»).
///
/// الضغط إلزاميٌّ قبل الرفع: أطول ضلع ١٦٠٠ بكسل، JPEG بجودة ~٠٫٧، ≤ ٤٠٠ ك.ب، بلا EXIF/GPS (اتّجاه الصورة يُطبَّق قبل نزعه) —
/// يُعاد ترميزها دائماً ولو كانت صغيرة (image_picker يصغّر لكنّه ينسخ EXIF على أندرويد). والخادم يفحص البايتات وينزع الوصف أيضاً.
/// العرض بمسار الصورة الموثَّق ([TicketsApi.imageBytes]) — مصغّرةٌ في الفقاعة، وبالنقر ملء الشاشة بتكبير.
const ticketImageMaxSide = 1600;
const ticketImageTargetBytes = 400 * 1024;
const ticketImageQuality = 70;

class TicketImageError implements Exception {
  const TicketImageError(this.reason);

  /// decode · too-big
  final String reason;

  String get message => reason == 'too-big' ? 'الصورة كبيرة جداً — اختر صورةً أخرى' : 'تعذّر قراءة الصورة — اختر صورةً أخرى';

  @override
  String toString() => 'TicketImageError($reason)';
}

/// بايتات الصورة كما اختيرت ⇒ JPEG ≤ [target] بأطول ضلعٍ ≤ [maxSide]، بلا EXIF ولا ملفّ ألوان، والشفّاف على أبيض.
/// نقيّة (تُشغَّل في معزل): الجودة ٧٠ ثمّ ٦٠ ثمّ ٥٠ ثمّ ٤٠، ثمّ تصغيرٌ ٢٥٪ وإعادة — حتى تبلغ الحجم.
Uint8List prepareTicketJpeg(Uint8List raw, {int maxSide = ticketImageMaxSide, int target = ticketImageTargetBytes}) {
  final decoded = img.decodeImage(raw);
  if (decoded == null || decoded.width == 0 || decoded.height == 0) throw const TicketImageError('decode');
  var base = img.bakeOrientation(decoded);
  if (base.hasAlpha) {
    final white = img.Image(width: base.width, height: base.height, numChannels: 3);
    img.fill(white, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(white, base);
    base = white;
  }
  final longest = math.max(base.width, base.height);
  var scale = longest > maxSide ? maxSide / longest : 1.0;
  for (var round = 0; round < 6; round++) {
    final w = math.max(1, (base.width * scale).round());
    final h = math.max(1, (base.height * scale).round());
    final frame = w == base.width && h == base.height
        ? img.Image.from(base)
        : img.copyResize(base, width: w, height: h, interpolation: img.Interpolation.average);
    // بلا وصف الهاتف (الموقع، الطراز…) ولا ملفّ الألوان — encodeJpg يكتبهما إن وُجدا
    frame.exif = img.ExifData();
    frame.iccProfile = null;
    for (final q in const [ticketImageQuality, 60, 50, 40]) {
      final out = img.encodeJpg(frame, quality: q);
      if (out.length <= target) return out;
    }
    scale *= 0.75;
  }
  throw const TicketImageError('too-big');
}

/// في المعزل: النتيجة أو سبب التعذّر (السجلّ يعبر المعزل سليماً؛ الاستثناء قد يصل RemoteError).
(Uint8List?, String?) _prepareInIsolate(Uint8List raw) {
  try {
    return (prepareTicketJpeg(raw), null);
  } on TicketImageError catch (e) {
    return (null, e.reason);
  } catch (_) {
    return (null, 'decode');
  }
}

/// يختار صورةً ويجهّزها. null = ألغى الاختيار. [TicketImageError] = تعذّرت.
typedef TicketImagePicker = Future<Uint8List?> Function({required bool camera});

Future<Uint8List?> pickTicketImage({required bool camera}) async {
  final XFile? f;
  try {
    f = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: ticketImageMaxSide.toDouble(),
      maxHeight: ticketImageMaxSide.toDouble(),
      imageQuality: 90,
      requestFullMetadata: false,
    );
  } catch (_) {
    throw const TicketImageError('decode');
  }
  if (f == null) return null;
  final raw = await f.readAsBytes();
  if (raw.isEmpty) throw const TicketImageError('decode');
  final (Uint8List?, String?) r;
  try {
    r = await compute(_prepareInIsolate, raw);
  } catch (_) {
    throw const TicketImageError('decode');
  }
  final bytes = r.$1;
  if (bytes == null) throw TicketImageError(r.$2 ?? 'decode');
  return bytes;
}

/// الكاميرا متاحةٌ على الهاتف وحده (ويندوز والماك: ملفٌّ من الجهاز).
bool get ticketCameraAvailable =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// «الكاميرا» أم «المعرض» — null = أُغلق بلا اختيار. على الحاسبة المعرض مباشرةً.
Future<bool?> askTicketImageSource(BuildContext context) async {
  if (!ticketCameraAvailable) return false;
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.surface,
    barrierColor: AppColors.scrim,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.sm),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const ValueKey('ticket-image-camera'),
            leading: Icon(LucideIcons.camera, color: AppColors.brand),
            title: Text('الكاميرا', style: AppType.body(color: AppColors.textHi)),
            onTap: () => Navigator.pop(ctx, true),
          ),
          ListTile(
            key: const ValueKey('ticket-image-gallery'),
            leading: Icon(LucideIcons.image, color: AppColors.brand),
            title: Text('المعرض', style: AppType.body(color: AppColors.textHi)),
            onTap: () => Navigator.pop(ctx, false),
          ),
        ]),
      ),
    ),
  );
}

/// معاينة الصورة المختارة قبل الإرسال: مصغّرةٌ بزرّ «إزالة».
class TicketAttachPreview extends StatelessWidget {
  const TicketAttachPreview({super.key, required this.bytes, required this.onRemove});
  final Uint8List bytes;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final kb = (bytes.length / 1024).ceil();
    return Container(
      key: const ValueKey('ticket-attach-preview'),
      padding: const EdgeInsets.all(Sp.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(R.sm),
          child: Image.memory(bytes, width: 56, height: 56, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 168),
        ),
        const SizedBox(width: Sp.sm),
        Text('صورة · $kb ك.ب', style: AppType.micro(color: AppColors.textMid)),
        IconButton(
          key: const ValueKey('ticket-attach-remove'),
          tooltip: 'إزالة الصورة',
          visualDensity: VisualDensity.compact,
          onPressed: onRemove,
          icon: Icon(LucideIcons.x, size: 18, color: AppColors.textMid),
        ),
      ]),
    );
  }
}

/// جلب بايتات صورة رسالة — قابلٌ للتبديل في الاختبار.
typedef TicketImageLoader = Future<TicketImageResult> Function(int ticketId, int messageId);

/// صورة رسالةٍ في الفقاعة: مكانها بنسبتها حتى تصل، «حُذفت» بعد حذفها، و«تعذّر — اضغط للإعادة» عند الفشل؛ والنقر ملء الشاشة.
class TicketImageThumb extends StatefulWidget {
  const TicketImageThumb({super.key, required this.ticketId, required this.messageId, required this.image, this.loader});
  final int ticketId;
  final int messageId;
  final TicketImage image;
  final TicketImageLoader? loader;

  @override
  State<TicketImageThumb> createState() => _TicketImageThumbState();
}

class _TicketImageThumbState extends State<TicketImageThumb> {
  Uint8List? _bytes;
  bool _loading = false;
  bool _failed = false;
  late bool _expired = !widget.image.available;

  @override
  void initState() {
    super.initState();
    if (!_expired) _fetch();
  }

  Future<void> _fetch() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final r = await (widget.loader ?? TicketsApi.imageBytes)(widget.ticketId, widget.messageId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _bytes = r.bytes;
      _expired = r.expired;
      _failed = r.bytes == null && !r.expired;
    });
  }

  void _open() {
    final b = _bytes;
    if (b == null) return;
    // كعارض صورة التحويل (renew_widgets.dart): فوق كلّ شيء بستارة اللوحة
    Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: AppColors.scrim,
      pageBuilder: (ctx, _, __) => TicketImageViewer(bytes: b),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final key = ValueKey('ticket-img-${widget.messageId}');
    final ratio = widget.image.aspect;
    if (_expired) {
      return _note(key, LucideIcons.imageOff, 'حُذفت الصورة بعد ٣٠ يوماً من انتهاء التذكرة');
    }
    final b = _bytes;
    if (b == null) {
      if (_failed) {
        return InkWell(
          key: key,
          onTap: _fetch,
          borderRadius: BorderRadius.circular(R.md),
          child: _box(
              ratio,
              Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.imageOff, size: 22, color: AppColors.textLow),
                const SizedBox(height: 4),
                Text('تعذّر تحميل الصورة — اضغط للإعادة', textAlign: TextAlign.center, style: AppType.micro(color: AppColors.textMid)),
              ])),
        );
      }
      return KeyedSubtree(
          key: key, child: _box(ratio, const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    return Semantics(
      label: 'صورة — اضغط للتكبير',
      button: true,
      child: GestureDetector(
        key: key,
        onTap: _open,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(R.md),
          child: AspectRatio(
            aspectRatio: ratio,
            child: Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 720),
          ),
        ),
      ),
    );
  }

  Widget _box(double ratio, Widget child) => ClipRRect(
        borderRadius: BorderRadius.circular(R.md),
        child: AspectRatio(
          aspectRatio: ratio,
          child: ColoredBox(color: AppColors.surfaceSunken, child: Center(child: child)),
        ),
      );

  Widget _note(Key key, IconData icon, String text) => Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs),
        decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: AppColors.textLow),
          const SizedBox(width: Sp.xs),
          Flexible(child: Text(text, style: AppType.micro(color: AppColors.textMid))),
        ]),
      );
}

/// الصورة ملء الشاشة بتكبيرٍ وسحب (كعارض صورة التحويل).
class TicketImageViewer extends StatelessWidget {
  const TicketImageViewer({super.key, required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('ticket-image-viewer'),
      backgroundColor: AppColors.scrim,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.sm, Sp.sm),
            child: Row(children: [
              Expanded(child: Text('صورة التذكرة', style: AppType.bodyBold(color: AppColors.onBrand))),
              IconButton(
                key: const ValueKey('ticket-viewer-close'),
                tooltip: 'إغلاق',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(LucideIcons.x, color: AppColors.onBrand),
              ),
            ]),
          ),
          Expanded(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)),
            ),
          ),
        ]),
      ),
    );
  }
}
