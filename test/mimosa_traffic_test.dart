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

  group('العرض يطابق ميكروتك', () {
    late String mt;
    setUpAll(() {
      mt = File('lib/screens/network_devices/widgets/mikrotik_live_panel.dart')
          .readAsStringSync();
    });

    test('🚨 التسمية من مفردات اللوحات لا مخترَعة', () {
      // بلاغ ٢٠٢٦-٠٩-٠٢: «التزم بمسمّيات بقيّة الأجهزة، شنو المرور
      // الفعليّ؟». شاشتان تعرضان الشيء نفسه يجب أن تُسمّياه سواءً.
      expect(panel.contains("Text('سير الترفك'"), isTrue);
      expect(mt.contains('سير الترفك'), isTrue,
          reason: 'المفردة مأخوذة من ميكروتك لا مخترَعة');
      // ⚠️ نفحص النصوص المعروضة وحدها — سطراً سطراً مع تخطّي
      // التعليقات، فالتعليق التاريخيّ يشرح العطل ولا يراه المستخدم.
      final ui = [
        for (final line in panel.split('\n'))
          if (!line.trimLeft().startsWith('//') &&
              line.contains("'المرور الفعليّ'"))
            line.trim()
      ];
      expect(ui, isEmpty, reason: 'بقي نصّ واجهة بالتسمية المخترَعة: $ui');
    });

    test('🚨 محور مختصر — «48M» لا «47.9 Mbps»', () {
      // الثاني أعرض من الحيّز المحجوز فيلتفّ سطرين ويركب الرسم.
      expect(panel.contains('_formatBpsShort(v.toInt())'), isTrue);
      expect(panel.contains('reservedSize: 44'), isTrue,
          reason: 'نفس حيّز ميكروتك');
      expect(panel.contains('_fmtUnit('), isFalse,
          reason: 'الوحدة داخل المحور هي ما لفّ السطر');
    });

    test('شارات في الرأس لا بطاقتان ضخمتان', () {
      expect(panel.contains('_legendChip('), isTrue);
      expect(mt.contains('_legendChip('), isTrue);
    });

    test('تنسيق الأرقام واحدٌ في اللوحتين', () {
      for (final fn in ['String _formatBps(int bps)',
                        'String _formatBpsShort(int bps)']) {
        expect(panel.contains(fn), isTrue, reason: 'ميموزا: $fn');
        expect(mt.contains(fn), isTrue, reason: 'ميكروتك: $fn');
      }
    });

    test('لا رقم قبل عيّنتين', () {
      // «٠» يوحي بوصلةٍ صامتة وهي تحمل عشرات الميغا.
      expect(panel.contains("Text('يقيس…'"), isTrue);
      expect(panel.contains('if (_history.isEmpty)'), isTrue);
      expect(panel.contains('if (_history.length >= 2)'), isTrue);
    });

    test('🚨 «سعة» لا «أداء» للـPHY', () {
      // تسميتُهما «أداءً» أوهمت أنّ الوصلة تحمل ٦٥٠ ميغا وهي تحمل بضعة.
      expect(panel.contains("Text('سعة الوصلة (PHY)'"), isTrue);
      expect(panel.contains("'الأداء (PHY 5s)'"), isFalse);
    });

    test('سير الترفك يسبق السعة', () {
      final iT = panel.indexOf('_trafficGraph(),');
      final iR = panel.indexOf('_ratesCard(s),');
      expect(iT, greaterThan(0));
      expect(iT, lessThan(iR), reason: 'السعة سقفٌ ثابت — الترفك هو المتغيّر');
    });
  });

  group('الواجهة مثبَّتة لا منتخَبة كلّ جولة', () {
    test('🚨 الانتخاب الدوريّ يقلب الخطّين', () {
      // بلاغ ٢٠٢٦-٠٩-٠٢: «شو مرّة أبلود أعلى ظاهر وهو نهائيّاً ماكو
      // هيج أبلود».
      //
      // نقطة الوصول لها واجهتان تحملان الحركة نفسها في اتّجاهين
      // متعاكسين: اللاسلكيّة تستقبل ٤٦ ميغا والإيثرنت تُرسلها.
      // ومجموعهما متساوٍ تقريباً — فالمحاكاة أدناه تُظهر كيف يقلب
      // الانتخاب الدوريّ الخطّين بتذبذبٍ طفيف.
      const wireless = (rx: 46000000, tx: 2800000); // if5
      const ethernet = (rx: 2800000, tx: 46100000); // if2 — مرآتها

      int sum(({int rx, int tx}) r) => r.rx + r.tx;
      expect(sum(ethernet) > sum(wireless), isTrue,
          reason: 'فرقٌ مئة كيلوبت يكفي لقلب الفائز');

      // بالتثبيت: الاختيار مرّةً ثمّ الالتزام.
      const pinned = 5;
      final rates = {5: wireless, 2: ethernet};
      expect(rates[pinned], wireless,
          reason: 'المثبَّتة تبقى مهما تفوّقت جارتها');
    });

    test('التثبيت مُعلَن في الشيفرة', () {
      expect(panel.contains('int? _pinnedIf;'), isTrue);
      expect(panel.contains('!rates.containsKey(pin)'), isTrue,
          reason: 'إعادة الانتخاب عند اختفاء المثبَّتة فقط');
      expect(panel.contains('_electBusiest('), isTrue);
    });

    test('لا نعلق على واجهةٍ ماتت', () {
      expect(panel.contains('_repinAfterIdle = 4'), isTrue);
      expect(panel.contains('if (r.rx + r.tx == 0)'), isTrue);
    });

    test('سقفٌ يرفض خللَ العدّاد', () {
      // عشرة غيغابت لا تبلغها وصلةٌ لاسلكيّة — ما فوقه قفزةُ عدّاد.
      expect(panel.contains('rx > 10000000000 || tx > 10000000000'), isTrue);
    });
  });

  group('لا انتظار ثلاثين ثانية', () {
    late String api;
    setUpAll(() => api = File('lib/api/mimosa_api.dart').readAsStringSync());

    test('🚨 عيّنة ثانية سريعة بعد أوّل جلب', () {
      // بلاغ ٢٠٢٦-٠٩-٠٢: «الترفك الوحيد يتأخّر — كلّ البيانات تظهر
      // وهو يأخذ ٣٠ ثانية». والسبب حسابيّ لا شبكيّ: المعدّل فارقُ
      // عيّنتين والنبضة كلّ ١٥ ثانية، أمّا بقيّة القيم فمطلقة.
      expect(panel.contains('_maybeQuickSecondSample()'), isTrue);
      expect(panel.contains('Timer(const Duration(seconds: 4)'), isTrue,
          reason: 'أربعٌ لا واحدة — نافذةٌ أقصر تُضخّم ضجيج العدّاد');
    });

    test('الجلب السريع مقتصر على العدّادات', () {
      // ثلاث مشيات بدل عشر، فلا يُثقل الجهاز.
      expect(api.contains('static Future<List<MimosaIfCounter>> fetchCounters('),
          isTrue);
      final i = api.indexOf('fetchCounters(');
      final body = api.substring(i, api.indexOf('_lastIndex(String oid)', i));
      for (final heavy in ['_oidChainTable', '_oidStreamTable',
                           '_oidChannelTable', '_oidSsid']) {
        expect(body.contains(heavy), isFalse, reason: 'الجلب السريع يجرّ $heavy');
      }
    });

    test('لا تتكرّر ولا تسبق نفسها', () {
      expect(panel.contains('if (_history.isNotEmpty || _quickSampleTimer != null) return;'),
          isTrue, reason: 'واحدةٌ فقط، ولا تعمل بعد وجود تاريخ');
      expect(panel.contains('_quickSampleTimer?.cancel();'), isTrue,
          reason: 'تُلغى مع الشاشة وإلّا نادت setState على ميّت');
    });
  });
}
