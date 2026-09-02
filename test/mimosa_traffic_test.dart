import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// المرور الفعليّ لميموزا — بلاغ ٢٠٢٦-٠٩-٠٢: «ترفك لحد هسه ماكو».
///
/// ما كان يُعرض (٦٥٠/٦٥٠) **سعةُ** الوصلة لا حركتها.
void main() {
  late String api;
  late String panel;

  setUpAll(() {
    api = File('lib/api/mimosa_api.dart').readAsStringSync();
    panel = File('lib/screens/network_devices/widgets/mimosa_live_panel.dart')
        .readAsStringSync();
  });

  group('المصدر', () {
    test('🚨 أوكتِتات IF-MIB لا mimosaPerfInfo', () {
      // `mimosaPerfInfo` يعيد على C5c حيّ ١٤٦٧٢٨٣ و٣٥٩٣١٧١ بوحدة
      // «kbps» المذكورة في الـMIB = ١٫٥ و٣٫٦ غيغابت، وسعة الجهاز ٦٥٠
      // ميغا. فالوحدة ليست ما يقوله المصدر، وعرضُ رقمٍ بوحدةٍ مجهولة
      // أسوأ من عدم عرضه.
      expect(api.contains("_oidIfHcIn = '1.3.6.1.2.1.31.1.1.1.6'"), isTrue);
      expect(api.contains("_oidIfHcOut = '1.3.6.1.2.1.31.1.1.1.10'"), isTrue);
    });

    test('عدّاد ٦٤-بت أوّلاً و٣٢-بت احتياطاً', () {
      // عدّاد ٣٢-بت يلتفّ كلّ ٣٤ ثانية على غيغابت — أي بين نبضتين.
      final iHc = api.indexOf('_oidIfHcIn, chunkSize');
      final i32 = api.indexOf('_oidIfIn32, chunkSize');
      expect(iHc, greaterThan(0));
      expect(i32, greaterThan(iHc), reason: 'السقوط بعد المحاولة لا قبلها');
      expect(api.contains('inRows.isEmpty || outRows.isEmpty'), isTrue);
    });
  });

  group('حساب المعدّل', () {
    // نُعيد القواعد هنا حرفيّاً؛ الدالّة private في اللوحة.
    ({int rx, int tx})? rate({
      required int rxNow,
      required int txNow,
      required int rxBefore,
      required int txBefore,
      double secs = 15,
    }) {
      if (secs < 1 || secs > 300) return null;
      if (rxNow < rxBefore || txNow < txBefore) return null;
      return (
        rx: ((rxNow - rxBefore) * 8 / secs).round(),
        tx: ((txNow - txBefore) * 8 / secs).round(),
      );
    }

    test('الفارق ÷ الزمن الحقيقيّ', () {
      // ٩٠ ميغابايت في ١٥ث = ٤٨ ميغابت/ث
      final r = rate(rxNow: 90000000, txNow: 0, rxBefore: 0, txBefore: 0);
      expect(r!.rx, 48000000);
    });

    test('🚨 نافذة قصيرة تُرفَض — فخّ ٤ غيغا مكان ١٣٠ ميغا', () {
      expect(
          rate(
              rxNow: 90000000,
              txNow: 0,
              rxBefore: 0,
              txBefore: 0,
              secs: 0.5),
          isNull);
    });

    test('نافذة طويلة تُرفَض — متوسّط لا معدّل', () {
      expect(
          rate(rxNow: 9, txNow: 0, rxBefore: 0, txBefore: 0, secs: 600),
          isNull);
    });

    test('ارتداد العدّاد لا يُنتج رقماً', () {
      // إقلاعٌ أو التفافُ ٣٢-بت — الطرح يُخرج سالباً أو ضخماً كاذباً.
      expect(rate(rxNow: 5, txNow: 5, rxBefore: 999999999, txBefore: 0),
          isNull);
    });
  });

  group('العرض', () {
    test('لا رقم قبل عيّنتين', () {
      // «٠ بت» يوحي بوصلةٍ صامتة وهي تحمل عشرات الميغا.
      expect(panel.contains("Text('يقيس…'"), isTrue);
      expect(panel.contains('if (_history.isEmpty)'), isTrue);
    });

    test('🚨 «سعة» لا «أداء» للـPHY', () {
      // تسميتُهما «أداءً» أوهمت أنّ الوصلة تحمل ٦٥٠ ميغا وهي تحمل بضعة.
      expect(panel.contains("Text('سعة الوصلة (PHY)'"), isTrue);
      expect(panel.contains("'الأداء (PHY 5s)'"), isFalse);
    });

    test('المرور الفعليّ يسبق السعة', () {
      final iT = panel.indexOf('_trafficCard(),');
      final iR = panel.indexOf('_ratesCard(s),');
      expect(iT, greaterThan(0));
      expect(iT, lessThan(iR), reason: 'السعة سقفٌ ثابت — المرور هو المتغيّر');
    });

    test('الوحدة منفصلة عن الرقم', () {
      expect(panel.contains('static String _fmtRate('), isTrue);
      expect(panel.contains('static String _fmtUnit('), isTrue);
    });
  });
}
