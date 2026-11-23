/// أحجام البيانات — الوحدة تكبر وحدها: B ⇒ KB ⇒ MB ⇒ GB ⇒ TB ⇒ PB (أساس ١٠٢٤ كبقيّة التطبيق والموقع وتطبيق المشترك)
/// (المالك ٢٣ نوفمبر: «اجمالي السحوبات سوي بوحدات التيرا وفما فوق حسب العدد»). كلّ ما يعرض حجماً يأخذ وحدته من [scaleBytes]
/// وتُبقي كلّ شاشةٍ شكل أرقامها؛ و[formatBytes] صيغة المجاميع (تقارير الجلسات): منزلتان من GB فصاعداً، وواحدة لـKB/MB.
library;

const kByteUnits = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

/// الوحدة الكبرى التي يبقى فيها الرقم ≥ ١ (حتى PB): القيمة بها، واسمها، ومقسومها، ورتبتها (٠ = B).
({double value, String unit, double div, int index}) scaleBytes(num bytes) {
  var div = 1.0;
  var i = 0;
  final a = bytes.abs();
  while (i < kByteUnits.length - 1 && a >= div * 1024) {
    div *= 1024;
    i++;
  }
  return (value: bytes / div, unit: kByteUnits[i], div: div, index: i);
}

/// صيغة المجاميع: «712.88 GB»، «8.81 TB»، «1.5 MB»، «900 B». تقريبٌ يبلغ ١٠٢٤ يرتقي للوحدة التالية (1023.999 GB ⇒ 1.00 TB).
String formatBytes(num bytes) {
  if (bytes.isNaN || bytes.isInfinite) return '—';
  var s = scaleBytes(bytes);
  String fixed(({double value, String unit, double div, int index}) x) => x.value.toStringAsFixed(x.index == 0 ? 0 : (x.index <= 2 ? 1 : 2));
  var out = fixed(s);
  if (s.index < kByteUnits.length - 1 && (double.tryParse(out)?.abs() ?? 0) >= 1024) {
    final div = s.div * 1024;
    s = (value: bytes / div, unit: kByteUnits[s.index + 1], div: div, index: s.index + 1);
    out = fixed(s);
  }
  return '$out ${s.unit}';
}
