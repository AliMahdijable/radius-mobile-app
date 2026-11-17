import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../../api/portal_services_api.dart' show ServiceImage;

/// صورة الباقة مرفوعةً من الهاتف (١٧ نوفمبر ٢٠٢٦ — المالك: «بقسم باقات وكيلك احنه هسه مخلين وصف الباقة يكون كتابه ورابط اريد تسوي
/// امكانيه رفع صوره من التطبيق مالتنا بعد ضغطها حتى لاتاخذ حجم»).
///
/// التطبيق يضغطها قبل الرفع: أطول ضلعٍ [packageImageMaxSide] بكسل بنسبتها، بلا EXIF ولا ملفّ ألوان (يُطبَّق الاتّجاه أوّلاً)، JPEG بجودة
/// 82 ثمّ 72 ثمّ 62، ثمّ ضلعٌ أصغر — عادةً عشرات إلى مئتي كيلوبايت، وتحت [packageImageMaxBytes] دائماً. PNG لصورةٍ فيها شفافيّة
/// حقيقيّة إن بقيت تحت الحدّ (وإلّا تُسطَّح على الأبيض). الخادم (server/portalPackageImages.js) يفحص بايتاتها (≤ 400 ك.ب و1600
/// بكسل) ويخزّنها ويكتب في image_url عنوانها على نطاقنا — فيراها المشترك بتطبيق MyServices والموقع كأيّ صورة باقة.

const packageImageMaxSide = 1280;
const packageImageMaxBytes = 300 * 1024;

/// عنوان صورةٍ رفعها الوكيل من التطبيق (على خادمنا) — كـHOSTED_RE في الخادم.
final _uploadedRe = RegExp(
  r'^https://(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*mysvcs\.net/api/portal/pkg-img/[1-9][0-9]{0,9}-[0-9a-f]{12}\.(?:webp|png|jpg)$',
  caseSensitive: false,
);

bool isUploadedPackageImage(String? url) => url != null && _uploadedRe.hasMatch(url.trim());

class PackageImageError implements Exception {
  const PackageImageError(this.reason);

  /// decode · too-big
  final String reason;

  @override
  String toString() => 'PackageImageError($reason)';
}

/// الصورة بعد الضغط وأبعادها (لسطر «بعد الضغط» تحت المعاينة).
class PreparedPackageImage {
  const PreparedPackageImage(this.image, this.width, this.height);
  final ServiceImage image;
  final int width;
  final int height;
  int get bytes => image.bytes.length;
}

/// صورةٌ كما اختيرت ⇒ مضغوطةٌ جاهزةٌ للرفع. نقيّة (تُشغَّل في معزل). [PackageImageError] = تعذّرت.
PreparedPackageImage preparePackageImage(
  Uint8List raw, {
  int maxSide = packageImageMaxSide,
  int maxBytes = packageImageMaxBytes,
}) {
  final decoded = img.decodeImage(raw);
  if (decoded == null || decoded.width == 0 || decoded.height == 0) throw const PackageImageError('decode');
  final base = img.bakeOrientation(decoded);
  final sides = <int>{maxSide, for (final s in const [1024, 800, 640]) if (s < maxSide) s};
  for (final side in sides) {
    var im = base;
    if (math.max(im.width, im.height) > side) {
      im = im.width >= im.height
          ? img.copyResize(im, width: side, interpolation: img.Interpolation.average)
          : img.copyResize(im, height: side, interpolation: img.Interpolation.average);
    }
    im.exif = img.ExifData();
    im.iccProfile = null;
    final transparent = _hasTransparency(im);
    if (transparent) {
      final png = img.encodePng(im, level: 9);
      if (png.length <= maxBytes) return PreparedPackageImage(ServiceImage(png, 'image/png'), im.width, im.height);
    }
    final flat = im.hasAlpha ? _flatten(im) : im;
    for (final q in const [82, 72, 62]) {
      final jpg = img.encodeJpg(flat, quality: q);
      if (jpg.length <= maxBytes) return PreparedPackageImage(ServiceImage(jpg, 'image/jpeg'), flat.width, flat.height);
    }
  }
  throw const PackageImageError('too-big');
}

/// قناة شفافيّة فيها بكسلٌ غير معتم فعلاً (لقطات الشاشة PNG معتمة بقناةٍ رابعة ⇒ JPEG أصغر بكثير).
bool _hasTransparency(img.Image im) {
  if (!im.hasAlpha) return false;
  final max = im.maxChannelValue;
  for (final p in im) {
    if (p.a < max) return true;
  }
  return false;
}

/// على خلفيّةٍ بيضاء (JPEG بلا شفافيّة — لا سواد مكانها).
img.Image _flatten(img.Image im) {
  final flat = img.Image(width: im.width, height: im.height, numChannels: 3);
  img.fill(flat, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(flat, im);
  return flat;
}

(PreparedPackageImage?, String?) _prepareInIsolate(Uint8List raw) {
  try {
    return (preparePackageImage(raw), null);
  } on PackageImageError catch (e) {
    return (null, e.reason);
  } catch (_) {
    return (null, 'decode');
  }
}

/// يختار صورةً من المعرض ويضغطها. null = ألغى. [PackageImageError] = تعذّرت.
typedef PackageImagePicker = Future<PreparedPackageImage?> Function();

Future<PreparedPackageImage?> pickPackageImage() async {
  final XFile? f;
  try {
    // المنصّة تصغّر صور الكاميرا الكبيرة أوّلاً (أسرع فكّاً هنا)، والضغط الحقيقيّ في [preparePackageImage].
    f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 95,
      requestFullMetadata: false,
    );
  } catch (_) {
    throw const PackageImageError('decode');
  }
  if (f == null) return null;
  final raw = await f.readAsBytes();
  if (raw.isEmpty) throw const PackageImageError('decode');
  final (PreparedPackageImage?, String?) r;
  try {
    r = await compute(_prepareInIsolate, raw);
  } catch (_) {
    throw const PackageImageError('decode');
  }
  if (r.$1 == null) throw PackageImageError(r.$2 ?? 'decode');
  return r.$1;
}

/// حجمٌ مقروء: «85 ك.ب» / «1.2 م.ب».
String packageImageSizeLabel(int bytes) {
  if (bytes < 1024 * 1024) return '${math.max(1, (bytes / 1024).round())} ك.ب';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
}
