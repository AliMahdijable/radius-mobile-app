import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/receipt_printer/escpos.dart';
import 'package:rad_mysvcs/services/receipt_printer/receipt_printer_prefs.dart';

/// «طابعة الوصولات» (٩ نوفمبر) — ترميز الصورة لأوامر ESC/POS:
///   ١. البكسلات (ألفا مضروبة، الشفّاف ورقٌ أبيض) ⇒ نقاطٌ بعرض الرأس ٣٨٤/٥٧٦ مقصوصةً من حافّة الورق.
///   ٢. «GS v 0» شرائط: رأس ٨ بايت (m · xL xH · yL yH) ثمّ البيانات كما هي، البتّ الأعلى أوّل نقطة.
///   ٣. المهمّة: «ESC @» أوّلاً، والتغذية (والقصّ لورق ٨٠) آخراً.
///   ٤. ردود أسئلة الحالة: النمط الثابت وإلّا null (طابعةٌ صامتة لا تُفهم خطأً).

/// صفحة RGBA بحبرٍ أسود كامل على البكسلات [black] (x,y) والباقي شفّاف — كما يرسم أندرويد.
Uint8List _rgba(int w, int h, Set<(int, int)> black, {int alpha = 255}) {
  final px = Uint8List(w * h * 4);
  for (final (x, y) in black) {
    final i = (y * w + x) * 4;
    px[i + 3] = alpha; // حبرٌ أسود مضروب: RGB صفر
  }
  return px;
}

void main() {
  group('١ البكسلات ⇒ نقاط', () {
    test('الشفّاف أبيض، الأسود الكامل نقطة، والبتّ الأعلى أوّل نقطة', () {
      final img = MonoImage.fromRgba(_rgba(16, 2, {(0, 0), (7, 0), (8, 1)}), 16, 2, targetWidth: 16);
      expect(img.rowBytes, 2);
      expect(img.bytes, [0x81, 0x00, 0x00, 0x80]);
      expect(img.isBlack(0, 0), isTrue);
      expect(img.isBlack(1, 0), isFalse);
      expect(img.isBlack(8, 1), isTrue);
    });

    test('أبيض معتم (ألفا كاملة، لون أبيض) ورماديّ فاتح ⇒ لا حبر؛ الرماديّ الداكن حبر', () {
      final px = Uint8List(3 * 1 * 4);
      // أبيض
      px.setAll(0, [255, 255, 255, 255]);
      // رماديّ فاتح ٢٠٠
      px.setAll(4, [200, 200, 200, 255]);
      // رماديّ داكن ١٠٠
      px.setAll(8, [100, 100, 100, 255]);
      final img = MonoImage.fromRgba(px, 3, 1, targetWidth: 8);
      expect(img.isBlack(0, 0), isFalse);
      expect(img.isBlack(1, 0), isFalse);
      expect(img.isBlack(2, 0), isTrue);
    });

    test('حافّة حرفٍ منعَّمة (ألفا جزئيّة) على الورق: أغمق من العتبة حبر، والأفتح لا', () {
      // ألفا ١٦٠ ⇒ على الأبيض لمعان ٩٥ (< ١٥٠) ⇒ حبر؛ ألفا ٦٠ ⇒ ١٩٥ ⇒ ورق.
      final dark = MonoImage.fromRgba(_rgba(1, 1, {(0, 0)}, alpha: 160), 1, 1, targetWidth: 8);
      final light = MonoImage.fromRgba(_rgba(1, 1, {(0, 0)}, alpha: 60), 1, 1, targetWidth: 8);
      expect(dark.isBlack(0, 0), isTrue);
      expect(light.isBlack(0, 0), isFalse);
    });

    test('٥٨ ملم: صفحة الورق كاملاً (٤٦٤) تُقصّ من النقطة ٤٠ إلى ٣٨٤ — حبر الحافّة غير المطبوعة لا يُرسل', () {
      const paper = ReceiptPaper.mm58;
      expect(paper.dots, 384);
      expect(paper.leftDots, 40);
      // حبرٌ عند العمود ٤٠ (أوّل نقطة مطبوعة) وعند ٤٢٣ (آخرها) وعند ٣٩ و٤٢٤ (خارج الرأس)
      final img = MonoImage.fromRgba(
        _rgba(464, 1, {(39, 0), (40, 0), (423, 0), (424, 0)}),
        464,
        1,
        targetWidth: paper.dots,
        left: paper.leftDots,
      );
      expect(img.width, 384);
      expect(img.rowBytes, 48);
      final dots = [for (var x = 0; x < 384; x++) if (img.isBlack(x, 0)) x];
      expect(dots, [0, 383]);
    });

    test('٨٠ ملم: ٥٧٦ نقطة (٧٢ بايت للصفّ)، وما بعد عرض الصورة أبيض لا حبرٌ مخترع', () {
      const paper = ReceiptPaper.mm80;
      expect(paper.dots, 576);
      expect(paper.leftDots, 32);
      // صورةٌ أضيق من المطلوب (رسمٌ قُرّب للأسفل): ما بعدها أبيض
      final img = MonoImage.fromRgba(_rgba(600, 1, {(599, 0)}), 600, 1, targetWidth: 576, left: 32);
      expect(img.rowBytes, 72);
      expect(img.isBlack(567, 0), isTrue);
      expect([for (var x = 568; x < 576; x++) img.isBlack(x, 0)], everyElement(isFalse));
    });

    test('الذيل الأبيض يُقصّ ويبقى منه ٨ أسطر', () {
      final img = MonoImage.fromRgba(_rgba(8, 50, {(0, 3)}), 8, 50, targetWidth: 8).trimBottom();
      expect(img.height, 4 + 8);
      expect(MonoImage.blank(8, 5).trimBottom().height, 5, reason: 'كلّه أبيض ⇒ ما بقي ≤ ٨');
    });

    test('بايتات ناقصة ⇒ خطأ لا صورةٌ مشوّهة', () {
      expect(() => MonoImage(16, 2, Uint8List(3)), throwsArgumentError);
      expect(() => MonoImage.fromRgba(Uint8List(10), 4, 4, targetWidth: 8), throwsArgumentError);
    });
  });

  group('٢ «GS v 0» شرائط', () {
    MonoImage stripes(int width, int height) {
      final rb = MonoImage.rowBytesOf(width);
      final bytes = Uint8List(rb * height);
      for (var y = 0; y < height; y++) {
        for (var i = 0; i < rb; i++) {
          bytes[y * rb + i] = y & 0xFF; // كلّ صفٍّ برقمه — يُتتبّع أين ذهب
        }
      }
      return MonoImage(width, height, bytes);
    }

    test('رأس الشريط: GS v 0 m=0 ثمّ عرض الصفّ بالبايت (٣٨٤ ⇒ ٤٨) وعدد الصفوف — ثمّ البيانات كما هي', () {
      final img = stripes(384, 10);
      final band = EscPos.rasterBand(img, 2, 5);
      expect(band.sublist(0, 8), [0x1D, 0x76, 0x30, 0x00, 48, 0, 5, 0]);
      expect(band.length, 8 + 48 * 5);
      expect(band.sublist(8, 8 + 48), everyElement(2), reason: 'أوّل صفٍّ في الشريط هو الصفّ ٢');
      expect(band.sublist(8 + 48 * 4), everyElement(6));
    });

    test('٥٧٦ نقطة ⇒ xL=72 xH=0، و٣٠٠ صفّ ⇒ yL=44 yH=1', () {
      final band = EscPos.rasterBand(stripes(576, 300), 0, 300);
      expect(band.sublist(0, 8), [0x1D, 0x76, 0x30, 0x00, 72, 0, 44, 1]);
    });

    test('١٣٠ صفّاً بشرائط ٦٤ ⇒ ٦٤ + ٦٤ + ٢، ومجموع بياناتها الصورة نفسها بالترتيب', () {
      final img = stripes(384, 130);
      final bands = EscPos.raster(img, bandRows: 64);
      expect(bands.map((b) => b[6] + b[7] * 256).toList(), [64, 64, 2]);
      final data = [for (final b in bands) ...b.sublist(8)];
      expect(data, img.bytes);
    });

    test('شريطٌ خارج الصورة ⇒ خطأ', () {
      expect(() => EscPos.rasterBand(stripes(8, 4), 3, 2), throwsRangeError);
    });
  });

  group('٣ المهمّة كاملة', () {
    test('ESC @ أوّلاً، ثمّ الشرائط، ثمّ التغذية ٤ أسطر — بلا قصّ على ٥٨', () {
      final job = EscPos.job(MonoImage.blank(384, 100), bandRows: 64);
      expect(job.first, [0x1B, 0x40]);
      expect(job.length, 1 + 2 + 1);
      expect(job.last, [0x1B, 0x64, 4]);
    });

    test('ورق ٨٠: التغذية ثمّ القصّ الجزئيّ GS V B 0', () {
      final job = EscPos.job(MonoImage.blank(576, 10), cut: true);
      expect(job.last, [0x1B, 0x64, 4, 0x1D, 0x56, 0x42, 0x00]);
    });

    test('أسئلة الحالة: DLE EOT n فوريّ، وGS r 1 بالدور', () {
      expect(EscPos.realtimeStatus(4), [0x10, 0x04, 4]);
      expect(EscPos.paperStatusInSequence(), [0x1D, 0x72, 0x01]);
    });
  });

  group('٤ ردود الحالة', () {
    test('DLE EOT 4: ‎0x12 سليمة · ‎0x72 نفد الورق · ‎0x1E قرب النهاية · غير النمط ⇒ null', () {
      expect(EscPos.parseRealtime(4, [0x12])!.paperOut, isFalse);
      expect(EscPos.parseRealtime(4, [0x72])!.paperOut, isTrue);
      final low = EscPos.parseRealtime(4, [0x1E])!;
      expect(low.paperLow, isTrue);
      expect(low.paperOut, isFalse);
      expect(EscPos.parseRealtime(4, [0xFF]), isNull);
      expect(EscPos.parseRealtime(4, const []), isNull, reason: 'طابعةٌ صامتة');
    });

    test('DLE EOT 2: الغطاء مفتوح ‎0x16 · نفاد الورق ‎0x32 · عطل ‎0x52', () {
      expect(EscPos.parseRealtime(2, [0x16])!.coverOpen, isTrue);
      expect(EscPos.parseRealtime(2, [0x32])!.paperOut, isTrue);
      expect(EscPos.parseRealtime(2, [0x52])!.error, isTrue);
      expect(EscPos.parseRealtime(1, [0x1A])!.offline, isTrue);
    });

    test('يُقرأ آخر بايتٍ صحيح (بقايا ضجيج قبله لا تهمّ)', () {
      expect(EscPos.parseRealtime(4, [0xFF, 0x72])!.paperOut, isTrue);
    });

    test('GS r 1: ‎0x00 سليم · ‎0x0C نفد · ‎0x03 قرب النهاية · ‎0x90 ليس ردّاً', () {
      expect(EscPos.parsePaperStatus([0x00])!.paperOut, isFalse);
      expect(EscPos.parsePaperStatus([0x0C])!.paperOut, isTrue);
      expect(EscPos.parsePaperStatus([0x03])!.paperLow, isTrue);
      expect(EscPos.parsePaperStatus([0x90]), isNull);
      expect(EscPos.parsePaperStatus(const []), isNull);
    });
  });
}
