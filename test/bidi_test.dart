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

  group('مواضع الجدار مغطّاة', () {
    late String wall;
    setUpAll(() {
      wall = File('lib/screens/network_devices/devices_wall_screen.dart')
          .readAsStringSync();
    });

    // كلّ سطر هنا عطلٌ رآه المستخدم بعينه في لقطة.
    const sites = {
      'قيمة صفّ المعلومات (V 24.2)': 'child: Text(iso(v),',
      'سطر المتّصل (86/78 10 Mbps · يوماً)': 'final sub = isoJoin([',
      'تذييل المنافذ (و133 منفذاً آخر)': 'live.add(_DetailFoot(isoJoin([',
      'اسم المنفذ (pppoe-x> بقوس مقلوب)': 'child: Text(iso(port.name),',
      'معدّل النزول (M 251.2)': 'Text(iso(DeviceVitals.fmtBps(port.rxBps))',
      'معدّل الصعود': 'Text(iso(DeviceVitals.fmtBps(port.txBps))',
      'عنوان البطاقة (+CCR1009 بعلامة سابقة)':
          "isoJoin([device.ip, device.model!], ' · ')",
      'اسم المتّصل': 'child: Text(iso(peer.name),',
    };

    for (final e in sites.entries) {
      test(e.key, () {
        expect(wall.contains(e.value), isTrue,
            reason: 'موضعٌ غير معزول — ستتفكّك قيمته في العربيّة');
      });
    }

    test('التسمية «غير متّصل» لا «معطّل»', () {
      // «معطّل» تعني مُوقَفاً بقرار المدير، وهذا جهازٌ لا يردّ فحسب.
      // وبقيّة التطبيق تستعملها أصلاً — الجدار وحده شذّ.
      // (بلاغ المستخدم ٢٠٢٦-٠٩-٠١)
      //
      // ⚠️ سطراً سطراً مع تخطّي التعليقات: مطابقةٌ على الملفّ كلّه
      // تعبر الأسطر فتلتقط تعليقاً بين اقتباسَي شيفرةٍ متباعدين.
      final offenders = <String>[];
      for (final line in wall.split('\n')) {
        final t = line.trimLeft();
        if (t.startsWith('//')) continue;
        for (final m in RegExp("'[^']*معطّل[^']*'").allMatches(line)) {
          offenders.add(m[0]!);
        }
      }
      expect(offenders, isEmpty,
          reason: 'بقي نصّ واجهة يقول «معطّل»: $offenders');
      expect(wall.contains("'offline' => 'غير متّصل'"), isTrue);
    });

    test('«آخر ظهور» سطر لا صندوق', () {
      // الصندوق كان يأخذ من البطاقة غير المتّصلة ضعف ما يأخذه شريط
      // المقاييس من المتّصلة، لحقيقةٍ واحدة.
      final i = wall.indexOf('if (isDown && since != null)');
      expect(i, greaterThan(0), reason: 'لم يُعثر على كتلة «آخر ظهور»');
      final block = wall.substring(i, wall.indexOf('if (open)', i));
      expect(block.contains('BoxDecoration'), isFalse, reason: 'عاد الصندوق');
      expect(block.contains('LucideIcons.clock'), isTrue);
      expect(block.contains('آخر ظهور'), isTrue);
    });

    test('لا شارة «الكلّ سليم»', () {
      // مكرّرةً فوق كلّ منطقة تُدرَّب العين على تجاهل ذلك الموضع، فحين
      // يظهر فيه «٣ معطّل» لا تراه. (طلب المستخدم ٢٠٢٦-٠٩-٠١)
      expect(wall.contains("'الكلّ سليم'"), isFalse);
      expect(wall.contains('if (summary != null)'), isTrue,
          reason: 'الشارة تحمل خبراً أو تغيب');
    });
  });
}
