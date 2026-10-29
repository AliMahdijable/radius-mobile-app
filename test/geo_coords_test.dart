import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/util/geo_coords.dart';

/// [parseLatLng] — المصدر الواحد لاستخراج الإحداثيّات (موقع المشترك + صندوق الألياف).
void main() {
  test('نصّ فارغ ⇒ لا قيمة ولا خطأ', () {
    expect(parseLatLng(''), (null, null, null));
    expect(parseLatLng('   '), (null, null, null));
  });

  test('«lat,lng» مباشرة', () {
    final (lat, lng, err) = parseLatLng('33.312345,44.361234');
    expect([lat, lng, err], [33.312345, 44.361234, null]);
  });

  test('بفراغٍ بين الرقمين وبإحداثيّاتٍ سالبة', () {
    expect(parseLatLng('33.31 44.36').$3, null);
    final (lat, lng, _) = parseLatLng('-12.34, -56.78');
    expect([lat, lng], [-12.34, -56.78]);
  });

  test('رابط Google Maps الكامل ⇒ أوّل زوج', () {
    final (lat, lng, err) = parseLatLng('https://www.google.com/maps/@33.315200,44.366100,17z');
    expect([lat, lng, err], [33.3152, 44.3661, null]);
  });

  test('روابط goo.gl القصيرة تُرفض برسالة', () {
    expect(parseLatLng('https://maps.app.goo.gl/abc123').$3, contains('goo.gl'));
  });

  test('بلا زوج أرقام ⇒ رسالة «ما قدرت أستخرج»', () {
    expect(parseLatLng('شارع المدارس').$3, contains('ما قدرت أستخرج'));
  });

  test('خارج المدى ⇒ رسالة المدى', () {
    expect(parseLatLng('95.123456,44.361234').$3, contains('خط العرض'));
    expect(parseLatLng('33.312345,200.361234').$3, contains('خط الطول'));
  });
}
