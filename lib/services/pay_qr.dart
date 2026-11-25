import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// «باركود الدفع» (٢٥ نوفمبر — المالك: «مكاتب الصيرفة ترفض الرقم وتطلب الباركود حصرا خاصة زين كاش… نرفع بيها صور الباركود وتظهر
/// بصف الرقم او وحدها حسب اختيارنا»): صورة باركود زين كاش/الماستر مع أرقام «طلب التجديد» — تظهر للمشترك (التجديد، «تسديد ديونك»،
/// المتجر) وللمدراء الفرعيّين («ادفع لمديرك»). الخادم server/portalPayQr.js (7bff612): تُرفع مع حفظ الإعداد نفسه —
/// `zaincash_qr` / `master_qr` (data URL أو null للإزالة) و`zaincash_show` / `master_show` (`both` | `qr`) — ويفحص بايتاتها
/// (≤ ٥٠٠ ك.ب و١٦٠٠ بكسل).

const payQrMaxSide = 1600;
const payQrMaxBytes = 450 * 1024;
const payQrMethods = ['zaincash', 'master'];

/// عنوان صورة باركودٍ على خادمنا وحده (كـIMG_RE في الخادم).
final _qrUrlRe = RegExp(
  r'^https://(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*mysvcs\.net/api/portal/pay-qr/[1-9][0-9]{0,9}-[0-9a-f]{12}\.(?:png|jpg|webp)$',
  caseSensitive: false,
);

String? payQrUrl(Object? v) {
  if (v is! String) return null;
  final s = v.trim();
  return _qrUrlRe.hasMatch(s) ? s : null;
}

/// الباركود كما يُعرض: العنوان وطريقة الظهور (`both` مع الرقم · `qr` وحده).
@immutable
class PayQr {
  const PayQr(this.url, {this.qrOnly = false});
  final String url;
  final bool qrOnly;

  /// null بلا عنوانٍ صالح؛ ظهورٌ مجهول = مع الرقم.
  static PayQr? of(Object? url, Object? show) {
    final u = payQrUrl(url);
    return u == null ? null : PayQr(u, qrOnly: show == 'qr');
  }

  @override
  bool operator ==(Object other) => other is PayQr && other.url == url && other.qrOnly == qrOnly;

  @override
  int get hashCode => Object.hash(url, qrOnly);
}

class PayQrError implements Exception {
  const PayQrError(this.reason);

  /// decode · too-big
  final String reason;

  String get message => reason == 'too-big' ? 'صورة الباركود كبيرة — اقصّ لقطة الشاشة على الباركود وأعد' : 'تعذّرت قراءة الصورة — اختر غيرها';

  @override
  String toString() => 'PayQrError($reason)';
}

/// صورة الباركود جاهزةً للرفع.
@immutable
class PayQrImage {
  const PayQrImage(this.bytes, this.mime, this.width, this.height);
  final Uint8List bytes;
  final String mime;
  final int width;
  final int height;
  int get length => bytes.length;
  String get dataUrl => 'data:$mime;base64,${base64Encode(bytes)}';
}

/// صورةٌ كما اختيرت ⇒ جاهزةٌ للرفع. نقيّة (تُشغَّل في معزل).
/// على خلفيّةٍ بيضاء دائماً (باركودٌ شفّاف يختفي على الوضع الداكن ولا تقرؤه الصيرفة)، PNG أوّلاً (أنقى للباركود وأصغر للقطة الشاشة)،
/// ثمّ JPEG بجودةٍ عالية، ثمّ ضلعٌ أصغر. [PayQrError] = تعذّرت.
PayQrImage preparePayQr(Uint8List raw, {int maxSide = payQrMaxSide, int maxBytes = payQrMaxBytes}) {
  final decoded = img.decodeImage(raw);
  if (decoded == null || decoded.width == 0 || decoded.height == 0) throw const PayQrError('decode');
  final base = img.bakeOrientation(decoded);
  final sides = <int>{maxSide, for (final s in const [1280, 1024]) if (s < maxSide) s};
  for (final side in sides) {
    var im = base;
    if (math.max(im.width, im.height) > side) {
      im = im.width >= im.height
          ? img.copyResize(im, width: side, interpolation: img.Interpolation.average)
          : img.copyResize(im, height: side, interpolation: img.Interpolation.average);
    }
    final flat = img.Image(width: im.width, height: im.height, numChannels: 3);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, im);
    final png = img.encodePng(flat, level: 9);
    if (png.length <= maxBytes) return PayQrImage(png, 'image/png', flat.width, flat.height);
    for (final q in const [92, 85]) {
      final jpg = img.encodeJpg(flat, quality: q);
      if (jpg.length <= maxBytes) return PayQrImage(jpg, 'image/jpeg', flat.width, flat.height);
    }
  }
  throw const PayQrError('too-big');
}

(PayQrImage?, String?) _prepareInIsolate(Uint8List raw) {
  try {
    return (preparePayQr(raw), null);
  } on PayQrError catch (e) {
    return (null, e.reason);
  } catch (_) {
    return (null, 'decode');
  }
}

/// يختار صورة الباركود من المعرض ويجهّزها. null = ألغى. [PayQrError] = تعذّرت.
typedef PayQrPicker = Future<PayQrImage?> Function();

Future<PayQrImage?> pickPayQr() async {
  final XFile? f;
  try {
    // بلا تصغيرٍ ولا ضغطٍ من المنصّة: لقطة الشاشة PNG تبقى نقيّة حتى التجهيز هنا.
    f = await ImagePicker().pickImage(source: ImageSource.gallery, requestFullMetadata: false);
  } catch (_) {
    throw const PayQrError('decode');
  }
  if (f == null) return null;
  final raw = await f.readAsBytes();
  if (raw.isEmpty) throw const PayQrError('decode');
  final (PayQrImage?, String?) r;
  try {
    r = await compute(_prepareInIsolate, raw);
  } catch (_) {
    throw const PayQrError('decode');
  }
  if (r.$1 == null) throw PayQrError(r.$2 ?? 'decode');
  return r.$1;
}

/// «85 ك.ب»
String payQrSizeLabel(int bytes) => '${math.max(1, (bytes / 1024).round())} ك.ب';
