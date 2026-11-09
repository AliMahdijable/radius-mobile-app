import 'package:flutter/services.dart';

/// حقل عنوان IP (المالك ٩ نوفمبر: «بالايفون امكان يضع بيها ايبي ماكو . دوت»).
///
/// [TextInputType.number] يُظهر على الآيفون لوحة أرقامٍ كالهاتف بلا نقطة، فلا يُكتب IP أصلاً.
/// [ipKeyboard] = لوحة الأرقام العشريّة: فيها فاصلٌ عشريّ على الآيفون والأندرويد — وقد يكون «٫» أو «،»
/// بحسب لغة الجهاز، فيحوّله [IpInputFormatter] نقطةً (ويحوّل الأرقام العربيّة) ويُسقط ما سواها.
const TextInputType ipKeyboard = TextInputType.numberWithOptions(decimal: true);

/// أرقامٌ لاتينيّة ونقاطٌ وحدها: ٠-٩ و۰-۹ ⇒ 0-9، و«٫» «،» «,» ⇒ «.»، والباقي يسقط.
class IpInputFormatter extends TextInputFormatter {
  const IpInputFormatter();

  /// [raw] كما كتبه المستخدم ⇒ أرقامٌ لاتينيّة ونقاط.
  static String normalize(String raw) {
    final out = StringBuffer();
    for (final r in raw.runes) {
      if (r >= 0x30 && r <= 0x39) {
        out.writeCharCode(r); // 0-9
      } else if (r >= 0x0660 && r <= 0x0669) {
        out.writeCharCode(0x30 + r - 0x0660); // ٠-٩
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        out.writeCharCode(0x30 + r - 0x06F0); // ۰-۹
      } else if (r == 0x2E || r == 0x066B || r == 0x060C || r == 0x2C) {
        out.write('.'); // . ٫ ، ,
      }
    }
    return out.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = normalize(newValue.text);
    if (text == newValue.text) return newValue;
    // المؤشّر بعد ما بقي ممّا قبله (لا قفزٌ لآخر الحقل حين يُعدَّل وسطه)
    final cut = newValue.selection.end.clamp(0, newValue.text.length);
    final offset = normalize(newValue.text.substring(0, cut)).length;
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: offset));
  }
}
