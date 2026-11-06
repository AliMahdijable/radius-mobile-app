/// تطبيع نصٍّ عربيّ قبل المقارنة — مصدرٌ واحد للبحث السريع والأوامر الصوتيّة.
///
/// iOS Speech Recognition (وأحياناً Google) يحقن أحرفاً غير مرئيّة تكسر المطابقة بـcontains:
/// • علامات الاتّجاه (U+200E LRM · U+200F RLM · U+202A..U+202E · U+2066..U+2069) — مكتوبة بأسمائها لا بحروفها: المحرف
///   الحرفيّ داخل تعليق يقلب ظاهر السطر عن حقيقته للمحلّل (صنف Trojan Source).
/// • مسافاتٌ خاصّة (NBSP وأخواتها) بدل المسافة العاديّة.
/// • التشكيل والألف الخنجريّة والتطويل، وZWJ/ZWNJ.
/// ثمّ توحيد الأشكال المتبادلة (أ/إ/آ ⇒ ا، ى/ئ ⇒ ي، ة ⇒ ه): الاسم المُخزَّن بشكلٍ والمنطوق يُكتب بآخر.
String normalizeArabic(String s) {
  if (s.isEmpty) return s;
  var t = s;
  t = t.replaceAll(
    RegExp('[\u200B-\u200F\u202A-\u202E\u2066-\u2069\u064B-\u065F\u0670\u0640]'),
    '',
  );
  t = t.replaceAll(RegExp('[\u00A0\u2000-\u200A\u202F\u205F\u3000]'), ' ');
  t = t
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ئ', 'ي')
      .replaceAll('ة', 'ه');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}

/// الأرقام العربيّة الهنديّة (٠–٩) والفارسيّة (۰–۹) ⇒ لاتينيّة: «علي ٧٧» يطابق يوزر «ali77».
String latinDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}
