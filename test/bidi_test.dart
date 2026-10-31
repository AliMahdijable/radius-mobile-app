import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/util/bidi.dart';

/// عزل ثنائيّ الاتّجاه — حالات حقيقيّة من لقطتَي ٢٠٢٦-٠٩-٠١.
void main() {
  const fsi = '⁨';
  const pdi = '⁩';

  group('العزل', () {
    test('يلفّ القيمة بحرفَي العزل', () {
      expect(iso('23.1 V'), '$fsi${'23.1 V'}$pdi');
    });

    test('الفارغ يبقى فارغاً', () {
      // حرفا تحكّمٍ بلا محتوى يُنتجان مسافةً وهميّة في التخطيط.
      expect(iso(''), '');
    });

    test('لا يغيّر المحتوى نفسه', () {
      for (final v in ['23.1 V', '10 يوماً', 'CCR1009-7G-1C-1S+', '<pppoe-x>']) {
        expect(iso(v).replaceAll(fsi, '').replaceAll(pdi, ''), v);
      }
    });
  });

  group('الوصل', () {
    test('يعزل كلّ مقطع لا الناتج مجتمعاً', () {
      // 🚨 جوهر العطل: عزل «a · b» مجتمعةً يجعلهما وحدةً باتّجاه أوّلها
      // فيُقلب الثاني. الحالة الحقيقيّة: «86/78 Mbps · 10 يوماً» ظهرت
      // «86/78 10 Mbps · يوماً».
      final r = isoJoin(['86/78 Mbps', '10 يوماً'], ' · ');
      expect(r, '$fsi${'86/78 Mbps'}$pdi · $fsi${'10 يوماً'}$pdi');
      expect(r.startsWith(fsi), isTrue);
      expect(r.split(fsi).length, 3, reason: 'عازلان لا واحد');
    });

    test('يُسقط المقاطع الفارغة فلا يبقى فاصل يتيم', () {
      expect(isoJoin(['a', '', 'b'], ' · '), '${fsi}a$pdi · ${fsi}b$pdi');
      expect(isoJoin(['', ''], ' · '), '');
      expect(isoJoin(['a'], ' · '), '${fsi}a$pdi');
    });
  });

  group('مواضع البطاقة الكبيرة مغطّاة', () {
    // «نظرة عامّة» أُلغيت (٣١ أكتوبر) وصار عرضها «بطاقات كبيرة» — المواضع نفسها على البطاقة الجديدة.
    late String card;
    setUpAll(() {
      card = File('lib/screens/network_devices/widgets/device_big_card.dart')
          .readAsStringSync();
    });

    // كلّ سطر هنا عطلٌ رآه المستخدم بعينه في لقطة.
    const sites = {
      'قيمة رقاقة الوصلة (V 24.2)': 'child: Text(iso(f.value),',
      'إشارة المتّصل (-63)': "Text(iso(known ? '\${p.signal}' : '—')",
      'اسم المنفذ/المتّصل (pppoe-x> بقوس مقلوب)': 'child: Text(iso(p.name),',
      'اسم منفذ PON (EPON0/1)': 'child: Text(iso(p.label),',
      'معدّل النزول (M 251.2)': "Text(iso('↓ \${_bpsShort(p.rxBps)}')",
      'معدّل الصعود': "Text(iso('↑ \${_bpsShort(p.txBps)}')",
      'مرور التذييل': 'Text(iso(_bpsShort(busiest.port.rxBps))',
      'شارة الحالة (12ms)': 'Text(iso(text), style: AppType.pillBold(color: tone.fill))',
    };

    for (final e in sites.entries) {
      test(e.key, () {
        expect(card.contains(e.value), isTrue,
            reason: 'موضعٌ غير معزول — ستتفكّك قيمته في العربيّة');
      });
    }

    test('الرقم ووحدته باتّجاهٍ صريح في الخانات', () {
      final i = card.indexOf('class _Tile extends');
      final body = card.substring(i, card.indexOf('class _SectionTitle'));
      expect(body.contains('textDirection: TextDirection.ltr'), isTrue);
    });

    test('التسمية «غير متّصل» لا «معطّل»', () {
      // «معطّل» تعني مُوقَفاً بقرار المدير، وهذا جهازٌ لا يردّ فحسب. (بلاغ المستخدم ٢٠٢٦-٠٩-٠١)
      // ⚠️ سطراً سطراً مع تخطّي التعليقات.
      final offenders = <String>[];
      for (final line in card.split('\n')) {
        final t = line.trimLeft();
        if (t.startsWith('//')) continue;
        for (final m in RegExp("'[^']*معطّل[^']*'").allMatches(line)) {
          offenders.add(m[0]!);
        }
      }
      expect(offenders, isEmpty, reason: 'بقي نصّ واجهة يقول «معطّل»: $offenders');
      expect(card.contains("'offline' => 'غير متّصل'"), isTrue);
    });

    test('«آخر ظهور» سطر لا صندوق', () {
      // الصندوق كان يأخذ من البطاقة غير المتّصلة ضعف ما يأخذه شريط المقاييس من المتّصلة، لحقيقةٍ واحدة.
      final i = card.indexOf('class _DownLine');
      expect(i, greaterThan(0), reason: 'لم يُعثر على كتلة «آخر ظهور»');
      final block = card.substring(i, card.indexOf('// ═══', i));
      expect(block.contains('BoxDecoration'), isFalse, reason: 'عاد الصندوق');
      expect(block.contains('LucideIcons.clock'), isTrue);
      expect(block.contains('آخر ظهور'), isTrue);
    });

    test('لا شارة «الكلّ سليم»', () {
      expect(card.contains("'الكلّ سليم'"), isFalse);
    });
  });
}
