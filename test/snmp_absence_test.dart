import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';

/// غياب الـOID ≠ القيمة صفر.
///
/// 🐛 عطلٌ صامت (٢٠٢٦-٠٩-٠٢): `asInt` كان يعيد صفراً لأيّ وسمٍ مجهول،
/// بما فيها وسوم «هذا الـOID غير موجود». فظهرت في سجلّ ميموزا عشرون
/// قيمةً صفريّة تبدو بياناتٍ حقيقيّة، بينما الجهاز يقول «لا أملك هذه
/// الـOIDs أصلاً».
void main() {
  Varbind vb(int tag, [List<int> bytes = const []]) =>
      Varbind(oid: '1.3.6.1.4.1.43356.2.1.1.1.0', rawTag: tag,
          rawBytes: Uint8List.fromList(bytes));

  group('وسوم الغياب الثلاثة', () {
    test('noSuchObject · noSuchInstance · endOfMibView', () {
      for (final tag in [0x80, 0x81, 0x82]) {
        expect(vb(tag).isAbsent, isTrue,
            reason: 'الوسم 0x${tag.toRadixString(16)}');
        expect(vb(tag).asIntOrNull, isNull,
            reason: 'الغياب يجب أن يكون null لا صفراً');
      }
    });

    test('🚨 صفرٌ حقيقيّ يبقى صفراً', () {
      // INTEGER بقيمة صفر — قيمةٌ صادقة لا غياب.
      final zero = vb(0x02, [0x00]);
      expect(zero.isAbsent, isFalse);
      expect(zero.asIntOrNull, 0);
    });

    test('القيم العاديّة سليمة', () {
      expect(vb(0x02, [0x2A]).asIntOrNull, 42);
      expect(vb(0x43, [0x1B, 0x88]).asIntOrNull, 7048, reason: 'TimeTicks');
      expect(vb(0x42, [0xFF]).asIntOrNull, 255, reason: 'Gauge32');
    });
  });

  group('العرض النصّيّ', () {
    test('الغائب يُصرّح بغيابه لا يطبع صفراً', () {
      // السجلّ كان يطبع «0» فيبدو بياناتٍ — وهو ما ضلّل التشخيص.
      expect(vb(0x80).asString, '<غير موجود>');
      expect(vb(0x02, [0x00]).asString, '0', reason: 'والصفر الحقيقيّ يبقى');
    });

    test('النصّ العاديّ سليم', () {
      final s = vb(0x04, 'MIMOSA C5c'.codeUnits);
      expect(s.isAbsent, isFalse);
      expect(s.asString, 'MIMOSA C5c');
    });
  });
}
