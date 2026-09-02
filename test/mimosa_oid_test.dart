import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// خريطة OIDs ميموزا.
///
/// المصدر: MIMOSA-NETWORKS-BFIVE-MIB (librenms/mibs/mimosa)، مُطابَقاً
/// على مسح جهاز C5c حيّ (najaf2262 · 10.220.191.34) قُورنت قيمُه بلوحته
/// الشبكيّة واحدةً واحدة — ٢٠٢٦-٠٩-٠٢.
void main() {
  late String src;
  setUpAll(() => src = File('lib/api/mimosa_api.dart').readAsStringSync());

  /// ما رآه الجهاز الحيّ ↔ ما عرضته لوحته.
  ///
  /// ⚠️ اللواحق بشكلها في المصدر (`$_bfive.<لاحقة>`) لا OID كاملاً:
  /// الشيفرة تبني العنوان من ثابتٍ مُدرَج، فالنصّ الكامل لا يظهر فيها.
  const groundTruth = {
    r"$_bfive.1.2.0": 'الرقم التسلسليّ · مسح 3089981883 · لوحة 3089981883',
    r"$_bfive.3.1.0": 'SSID · مسح najaf2262 · لوحة najaf2262',
    r"$_bfive.6.1.1.3": 'استقبال السلسلة · مسح −45 · لوحة −43.1 مجموعاً',
    r"$_bfive.6.1.1.4": 'أرضيّة الضجيج · مسح −74 · لوحة −74.4',
    r"$_bfive.6.1.1.5": 'SNR · مسح 29 · لوحة 28',
    r"$_bfive.6.2.1.2": 'PHY إرسال · مسح 325×2 · لوحة 650',
    r"$_bfive.6.3.1.3": 'عرض القناة · مسح 80 · لوحة 80 MHz',
    r"$_bfive.6.5.0": 'قدرة الإرسال الكلّيّة · مسح 240 ÷10 · لوحة 24 dBm',
    r"$_bfive.6.6.0": 'قدرة الاستقبال الكلّيّة · مسح −425 ÷10 · لوحة −43.1',
  };

  group('الجذر', () {
    test('🚨 مستوى `.2` موجود — لا يقع الاستعلام على فرع الفخّاخ', () {
      // كان `_bfive = enterprise.2.1`، فيسأل عن 43356.2.1.1.x وهي
      // mimosaTrapMessage/OldSpeed/NewSpeed — إشعاراتٌ تُرسَل لا
      // قياساتٌ تُقرأ. الجهاز يردّ noSuchObject على الجميع.
      expect(src.contains(r"_bfive = '$_enterprise.2.1.2'"), isTrue,
          reason: 'الجذر ناقصٌ مستوىً — كلّ القيم ستغيب');
      expect(src.contains(r"_bfive = '$_enterprise.2.1';"), isFalse);
    });
  });

  group('جدول السلاسل', () {
    test('🚨 الجدول 6.1.1 لا 6.3.1، والأعمدة غير منزاحة', () {
      // كان `6.3.1.4/5/6` — الجدول خطأ **والأعمدة منزاحةٌ بواحد**،
      // فيُقرأ الضجيج مكان الاستقبال وSNR مكان الضجيج.
      expect(src.contains(r"_oidChainRxPower = '$_bfive.6.1.1.3'"), isTrue);
      expect(src.contains(r"_oidChainRxNoise = '$_bfive.6.1.1.4'"), isTrue);
      expect(src.contains(r"_oidChainSnr = '$_bfive.6.1.1.5'"), isTrue);
      expect(src.contains('6.3.1.4'), isFalse, reason: 'عاد الجدول الخطأ');
    });

    test('🚨 قيم الجدول بلا قسمة — المقياسة هي المجاميع', () {
      // القسمة على عشرة كانت ستُظهر إشارةً بـ−4.5 dBm بدل −45.
      expect(src.contains('rxPowerDbm: _asPlain('), isTrue);
      expect(src.contains('snrDb: _asPlain('), isTrue);
      expect(src.contains('static double? _asDbmScaled'), isFalse,
          reason: 'ماتت وحُذفت — والتعليق التاريخيّ يبقى');
      // والمجاميع تبقى مقسومة.
      expect(src.contains('totalTxPowerDbm: n10('), isTrue);
      expect(src.contains('totalRxPowerDbm: n10('), isTrue);
    });
  });

  group('معدّلات PHY', () {
    test('🚨 من جدول التدفّقات لا من mimosaPerfInfo', () {
      // ‎7.1/7.2 يعيدان ١٤٦٧٢٨٣ و٣٥٩٣١٧١ على C5c حيّ — أي ١٫٥ و٣٫٦
      // غيغابت وسعة الجهاز ٦٥٠ ميغا. عدّادان تراكميّان لا معدّلان.
      expect(src.contains('txPhyMbps ?? n(MimosaApi._oidPhyTxRate)'), isTrue,
          reason: 'الجدول أوّلاً والسقوط إلى perfInfo احتياطاً');
      expect(src.contains('_sumStream('), isTrue,
          reason: 'الوصلة تحمل تدفّقين — المعدّل مجموعُهما لا واحدٌ منهما');
    });
  });

  group('الغياب لا يُترجَم صفراً', () {
    test('n10 يحترم isAbsent', () {
      expect(src.contains('if (vb == null || vb.isAbsent) return null;'),
          isTrue);
    });
  });

  group('كلّ OID مطابَقٌ على جهاز حيّ', () {
    for (final e in groundTruth.entries) {
      test(e.value, () {
        expect(src.contains(e.key), isTrue,
            reason: 'الـOID ${e.key} غاب عن الخريطة');
      });
    }
  });
}
