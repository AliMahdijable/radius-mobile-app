/// Tiny formatting helpers. No locale dance — IQD only, en_US digits for
/// readability (per user feedback: ٥٤٠٬٠٠٠ harder than 540,000).

final _grouper = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');

/// 540000 → "540,000". Negative-safe (strips the sign — callers add it).
String formatIQD(num value) {
  final s = value.abs().round().toString();
  return s.replaceAllMapped(_grouper, (m) => '${m[1]},');
}

/// 0.12 → "+12%", -0.05 → "-5%", 0 → "0%".
String formatDeltaPct(double ratio) {
  final pct = (ratio * 100).round();
  if (pct == 0) return '0%';
  return '${pct > 0 ? '+' : ''}$pct%';
}

/// يحوّل الأرقام العربيّة الهنديّة (٠-٩) والفارسيّة (۰-۹) إلى Latin (0-9).
///
/// السبب: أسماء الأجهزة الي فيها أرقام هنديّة تظهر مشوّشة بالخط Cairo
/// (١ يشبه l، ٢ يشبه r)، والمستخدم يظنّ العرض مكسور. iOS يحوّل تلقائياً
/// عند الكتابة بلوحة عربيّة. نطبّق التحويل عند العرض بدون تعديل الـDB
/// (المستخدم يقدر يعدّل الاسم لاحقاً لو حبّ).
///
/// null-safe، empty-safe.
String? normalizeDigits(String? input) {
  if (input == null || input.isEmpty) return input;
  const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  const extendedArabic = '۰۱۲۳۴۵۶۷۸۹'; // Persian/Urdu
  final sb = StringBuffer();
  for (final code in input.runes) {
    // Arabic-Indic 0-9: U+0660 → U+0669
    if (code >= 0x0660 && code <= 0x0669) {
      sb.writeCharCode(0x0030 + (code - 0x0660));
    }
    // Extended Arabic-Indic (Persian/Urdu): U+06F0 → U+06F9
    else if (code >= 0x06F0 && code <= 0x06F9) {
      sb.writeCharCode(0x0030 + (code - 0x06F0));
    } else {
      sb.writeCharCode(code);
    }
  }
  final s = sb.toString();
  assert(!s.contains(RegExp('[$arabicIndic$extendedArabic]')));
  return s;
}

/// 3 → "قبل 3د", 67 → "قبل 1س", 1500 → "قبل يوم".
String humanMinutesAgo(int minutes) {
  if (minutes < 1) return 'الآن';
  if (minutes < 60) return 'قبل $minutes د';
  final hours = minutes ~/ 60;
  if (hours < 24) return 'قبل $hours س';
  final days = hours ~/ 24;
  if (days == 1) return 'قبل يوم';
  return 'قبل $days أيام';
}
