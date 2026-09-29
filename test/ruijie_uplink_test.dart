import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/ruijie_api.dart';

/// حارسُ اختيار منفذ الترفك على أجهزة روجي بأنواعها.
///
/// 🐛 بلاغ المستخدم ٢٠٢٦-٠٩-٢٨: «خابط أعلى أبلود وعلى داونلود».
/// كان المنحنى يجمع معدّلات **كلّ** الواجهات — والبايت الواحد يمرّ على
/// منفذ LAN وعلى WAN وعلى الجسر، فيُعَدّ ثلاث مرّات. والأسوأ أنّ
/// الاتّجاه يُلغي نفسه: ما هو صادرٌ على منفذٍ واردٌ على جاره، فجمعهما
/// يُنتج رقماً بلا معنى يُبنى عليه قرارٌ ميدانيّ.
///
/// وهذا الملفّ يثبّت الصواب على الأنواع الثلاثة التي نلقاها فعلاً:
/// راوتر EG، وجسر airMetro، وسويتش NBS.
void main() {
  RuijieInterface i(String name, {int rx = 0, int tx = 0, int idx = 0}) =>
      RuijieInterface(
        index: idx,
        name: name,
        operUp: true,
        speedMbps: 1000,
        rxBytes: rx,
        txBytes: tx,
      );

  RuijieStats withIfaces(List<RuijieInterface> ifs) =>
      RuijieStats(ifaces: ifs);

  group('راوتر EG — منفذ WAN بالاسم', () {
    // ترتيب واجهات EG1510XS الفعليّ كما قرأه SNMP.
    final eg = withIfaces([
      i('LAN0', rx: 12171459558824, tx: 900, idx: 1),
      i('LAN1/WAN6', idx: 2),
      i('WAN', rx: 45103686638529, tx: 5, idx: 8),
      i('br-wan', rx: 1223443318439, tx: 7, idx: 9217),
      i('br-lan', idx: 9449),
      i('lo', rx: 999999999999999, tx: 999999999999999, idx: 14564),
    ]);

    test('يختار WAN ولو كان غيره أثقل', () {
      expect(eg.uplink?.name, 'WAN');
    });

    test('ويُسمّى منفذ صعودٍ حقيقيّاً', () {
      expect(eg.uplinkIsWan, isTrue);
    });

    test('lo لا يفوز مهما ضخُمت عدّاداته', () {
      // حلقةٌ محلّيّة لا تعبر شيئاً — وعدّادها هنا أكبر من الجميع عمداً.
      expect(eg.uplink?.name, isNot('lo'));
    });
  });

  group('جسر airMetro — لا WAN بل br-wan', () {
    // ترتيب واجهات AIRMETRO460G الفعليّ.
    final br = withIfaces([
      i('LAN1', idx: 1),
      i('br-wan', rx: 2495171158, tx: 3319955741, idx: 9217),
      i('br-lan', rx: 22541837, tx: 5238419, idx: 9449),
      i('lo', rx: 275248605, tx: 275248605, idx: 14564),
    ]);

    test('يختار br-wan', () {
      expect(br.uplink?.name, 'br-wan');
    });

    test('ويُعَدّ منفذ صعود', () {
      expect(br.uplinkIsWan, isTrue);
    });
  });

  group('سويتش NBS — لا WAN ولا br-wan', () {
    final sw = withIfaces([
      i('GigabitEthernet0/1', rx: 100, tx: 100, idx: 1),
      i('GigabitEthernet0/24', rx: 90000, tx: 80000, idx: 24),
      i('GigabitEthernet0/2', rx: 500, tx: 400, idx: 2),
      i('lo', rx: 1 << 60, tx: 1 << 60, idx: 99),
    ]);

    test('يختار الأثقل بين المنافذ الفيزيائيّة', () {
      expect(sw.uplink?.name, 'GigabitEthernet0/24');
    });

    test('ولا يُسمّى منفذ صعود — فلا «تنزيل» على سويتش', () {
      // على منفذ سويتشٍ لا اتّجاه إنترنت: ما يدخل من منفذٍ يخرج من
      // جاره. وتسميته «تنزيلاً» تُضلّل من يقرأ اللوحة ليقرّر.
      expect(sw.uplinkIsWan, isFalse);
    });
  });

  group('حالاتٌ حدّيّة', () {
    test('بلا واجهات — لا منفذ ولا ادّعاء', () {
      expect(withIfaces(const []).uplink, isNull);
      expect(withIfaces(const []).uplinkIsWan, isFalse);
    });

    test('الجسور وحدها بلا br-wan — لا نختار جسراً بالأثقليّة', () {
      // `br-lan` جسرٌ يُظلّل المنافذ تحته، فاختياره يعيد المشكلة نفسها.
      final s = withIfaces([i('br-lan', rx: 500, tx: 500), i('lo')]);
      expect(s.uplink, isNull);
    });

    test('حالة الأحرف لا تكسر المطابقة', () {
      final s = withIfaces([i('Wan', rx: 1, tx: 1), i('LAN0', rx: 99, tx: 99)]);
      expect(s.uplink?.name, 'Wan');
      expect(s.uplinkIsWan, isTrue);
    });
  });
}
