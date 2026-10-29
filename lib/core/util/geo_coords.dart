/// استخراج إحداثيّات GPS من نصٍّ يلصقه المدير — رابط Google Maps أو «lat,lng».
///
/// **مصدرٌ واحد** يتقاسمه تعديل موقع المشترك (`location_sheets.dart`) وموقع
/// صندوق الألياف (`fiber_sheets.dart`) حتّى يتطابق السلوك: نفس النمط، نفس
/// حدود المدى، ونفس رسائل العربيّة. يُرجع `(lat, lng, error)`:
///   • نصٌّ فارغ ⇒ (null, null, null) — لا قيمة ولا خطأ (الحقل فارغ).
///   • نجاح ⇒ (lat, lng, null).
///   • تعذّر ⇒ (null, null, رسالةٌ عربيّة تقول السبب).
///
/// روابط goo.gl القصيرة لا تحمل إحداثيّات (تحويلة خادم) ⇒ تُرفض برسالةٍ تشرح.
(double?, double?, String?) parseLatLng(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return (null, null, null);
  if (s.contains('goo.gl') || s.contains('maps.app.goo.gl')) {
    return (
      null,
      null,
      'روابط goo.gl القصيرة غير مدعومة — افتحها ثم انسخ الإحداثيّات',
    );
  }
  // نمط عام: أوّل زوجَي أرقام lat,lng في النصّ (رابطاً كان أو إحداثيّات مباشرة).
  final re = RegExp(r'(-?\d{1,2}\.\d{2,10})[,\s@=/]+(-?\d{1,3}\.\d{2,10})');
  final m = re.firstMatch(s);
  if (m == null) {
    return (
      null,
      null,
      'ما قدرت أستخرج إحداثيّات — الصق رابط Google Maps أو "lat,lng"',
    );
  }
  final lat = double.tryParse(m.group(1)!);
  final lng = double.tryParse(m.group(2)!);
  if (lat == null || lng == null) return (null, null, 'قيم غير صالحة');
  if (lat < -90 || lat > 90) return (null, null, 'خط العرض خارج المدى (±90)');
  if (lng < -180 || lng > 180) {
    return (null, null, 'خط الطول خارج المدى (±180)');
  }
  return (lat, lng, null);
}
