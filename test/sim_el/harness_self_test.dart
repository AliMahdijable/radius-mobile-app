import 'package:flutter_test/flutter_test.dart';

import 'sim_harness.dart';

/// فحص النصّ الخام ليس فارغاً: يمسك التسريبات التقنيّة، ولا يُنذر على بيانات
/// المشترك والباقة (لاتينيّةٍ بطبيعتها).
void main() {
  test('يمسك التسريبات التقنيّة', () {
    for (final leak in [
      'DioException [receive timeout]',
      'Exception: boom',
      'null',
      'الرصيد null د.ع',
      'https://pro.mysvcs.net/api/v2/subscribers',
      'Error',
      "type 'Null' is not a subtype of type 'String'",
      'Instance of \'ElCreateOptions\'',
      'CREATE_UNCONFIRMED',
      'RATE_LIMITED',
      'sheets.el_add.ok',
      'بقي {n}',
      'status=503',
      'NaN',
    ]) {
      expect(simForbiddenMatch(leak), isNotNull, reason: leak);
    }
  });

  test('لا يُنذر على البيانات', () {
    for (final data in [
      'Economy',
      'Ta3leem 50,000 Plus 3 Months',
      'Business Pro 100M',
      'ali1@alnoor-net',
      '${String.fromCharCode(0x2068)}ali1@alnoor-net${String.fromCharCode(0x2069)}',
      '07XX XXX XXXX',
      'Pin',
      'ahmed',
      '35,000 د.ع',
      '2026-10-13 14:22:05',
      'توكن EarthLink غير متوفر',
      'تمّ تحويل 10,000 د.ع إلى najaf40',
    ]) {
      expect(simForbiddenMatch(data), isNull, reason: data);
    }
  });
}
