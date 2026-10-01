import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';

/// حرّاس تصنيف واجهات OLT من VSOL.
///
/// الأسماء هنا **منقولةٌ حرفيّاً** من V1600D فعليّ (‏٢٠٢٦-٠٩-٢٨):
/// ثمانية منافذ صعود، وأربعة منافذ PON، وستّة وعشرون ONU. والتصنيف
/// هو قلب الطبقة: خطأٌ فيه يجعل منفذ PON يُعَدّ مشتركاً، أو يُخفي
/// مشتركاً عن القائمة — وكلاهما يُقرأ في الميدان قراراً.
void main() {
  VsolIfRow r(int i, String name,
          {bool up = false,
          String? mac,
          int speed = 1000,
          int rx = 0,
          int tx = 0}) =>
      VsolIfRow(
        index: i,
        name: name,
        up: up,
        mac: mac,
        speedMbps: speed,
        rxBytes: rx,
        txBytes: tx,
      );

  /// ترتيب الواجهات كما قرأه SNMP من الجهاز — بما فيه عدم انتظام
  /// الفهارس: `EPON0/1:2` يأتي بعد `EPON0/2:2` لأنّ الترقيم بترتيب
  /// التسجيل لا بترتيب المنفذ.
  List<VsolIfRow> real() => [
        for (var i = 1; i <= 8; i++) r(i, 'GE0/$i', up: i == 5),
        r(9, 'EPON0/1', up: true, rx: 1572119618, tx: 4096321853),
        r(10, 'EPON0/2', up: true, rx: 500, tx: 700),
        r(11, 'EPON0/3', up: true, rx: 900, tx: 1100),
        r(12, 'EPON0/4'),
        r(13, 'EPON0/1:1'),
        r(14, 'EPON0/2:1'),
        r(16, 'EPON0/1:2'),
        r(22, 'EPON0/3:1'),
        r(26, 'EPON0/3:2',
            up: true, mac: '88:3f:d3:43:ff:3f', rx: 21444513, tx: 328828089),
        r(34, 'EPON0/2:9', up: true, mac: '7c:6a:60:0e:08:07'),
        r(38, 'EPON0/1:5', up: true, mac: '88:cf:98:ca:08:7e'),
      ];

  group('التصنيف', () {
    final b = VsolParse.build(real());

    test('منافذ الصعود ثمانيةٌ ولا تختلط بالـPON', () {
      expect(b.uplinks.length, 8);
      expect(b.uplinks.every((u) => u.name.startsWith('GE')), isTrue);
    });

    test('منافذ PON أربعةٌ — ولا يُعَدّ منها ONU', () {
      expect(b.ponPorts.length, 4);
      expect(b.ponPorts.map((p) => p.label),
          containsAll(['EPON0/1', 'EPON0/2', 'EPON0/3', 'EPON0/4']));
    });

    test('«EPON0/3» ليس ONU رقم صفر', () {
      // 🐛 المصيدة الأولى: تعبيرٌ يقبل غياب النقطتين ويضع صفراً مكانها
      // يُحوّل كلّ منفذ PON إلى مشترك — فيرتفع عدّ المشتركين أربعةً
      // بلا سبب، ويظهر «مشتركٌ» لا وجود له.
      expect(b.onus.any((o) => o.onuId == 0), isFalse);
    });

    test('الـONU سبعةٌ في هذه اللقطة', () {
      expect(b.onus.length, 7);
    });
  });

  group('الترتيب', () {
    test('بالمنفذ ثمّ برقم الـONU لا بفهرس SNMP', () {
      // فهارس SNMP بترتيب التسجيل لا بترتيب المنفذ، فالعرض بها
      // يبعثر مشتركي المنفذ الواحد في القائمة.
      final b = VsolParse.build(real());
      expect(b.onus.map((o) => o.label).toList(), [
        'EPON0/1:1',
        'EPON0/1:2',
        'EPON0/1:5',
        'EPON0/2:1',
        'EPON0/2:9',
        'EPON0/3:1',
        'EPON0/3:2',
      ]);
    });

    test('١٠ بعد ٩ لا قبله', () {
      final b = VsolParse.build([
        r(1, 'EPON0/2:10'),
        r(2, 'EPON0/2:9'),
        r(3, 'EPON0/2:2'),
      ]);
      expect(b.onus.map((o) => o.onuId).toList(), [2, 9, 10]);
    });
  });

  group('العدّ لكلّ منفذ', () {
    final b = VsolParse.build(real());

    test('المنفذ الأوّل ثلاثة مشتركين واحدٌ متّصل', () {
      final p1 = b.ponPorts.firstWhere((p) => p.port == 1);
      expect(p1.onuTotal, 3);
      expect(p1.onuOnline, 1);
    });

    test('المنفذ الرابع بلا مشتركين', () {
      final p4 = b.ponPorts.firstWhere((p) => p.port == 4);
      expect(p4.onuTotal, 0);
      expect(p4.onuOnline, 0);
    });

    test('مجموع المتّصلين ثلاثة', () {
      expect(b.onusOnline, 3);
    });
  });

  group('الترفك', () {
    test('الإجماليّ من منافذ PON لا من جمع الـONU', () {
      // ⚠️ ما يمرّ على ONU يمرّ على منفذ PON الذي يحمله، فجمعهما
      // يعدّ البايت مرّتين. (بلاغ المستخدم على لوحة روجي ٢٠٢٦-٠٩-٢٨.)
      final s = VsolOltStats(
        ponPorts: VsolParse.build(real()).ponPorts,
        onus: VsolParse.build(real()).onus,
      );
      expect(s.ponRxBytes, 1572119618 + 500 + 900);
      // ولو جمعنا الـONU لأضفنا 21444513 مرّةً ثانية.
      expect(s.ponRxBytes, isNot(greaterThan(1572119618 + 500 + 900)));
    });
  });

  group('صيغة التسمية الثانية — فيرموير V1600D آخر', () {
    // 🐛 ٢٠٢٦-١٠-٠١: جهازٌ ثانٍ من الطراز نفسه يسمّي مشتركيه
    // `EPON01ONU34` لا `EPON0/1:34`. ومنافذ PON صيغتها واحدة في
    // الفيرمويرين — فكانت تُقرأ بينما يسقط المشتركون كلّهم بصمت،
    // واللوحة تقول «٠ مشتركين» على جهازٍ فيه مئات.
    final alt = VsolParse.build([
      r(1, 'GE0/1', up: true),
      r(9, 'EPON0/1', up: true, rx: 700, tx: 900),
      r(60, 'EPON01ONU34', up: true, mac: 'aa:bb:cc:dd:ee:01'),
      r(61, 'EPON01ONU35'),
      r(62, 'EPON07ONU2', up: true, mac: 'aa:bb:cc:dd:ee:02'),
    ]);

    test('تُقرأ ويُستخرج منها المنفذ والرقم', () {
      expect(alt.onus.length, 3);
      final o = alt.onus.firstWhere((o) => o.onuId == 34);
      expect(o.ponPort, 1);
      expect(o.slot, 0);
    });

    test('ولا تختلط بمنفذ PON نفسه', () {
      expect(alt.ponPorts.length, 1);
      expect(alt.ponPorts.single.label, 'EPON0/1');
    });

    test('والترقيم يميّز المنفذ السابع عن الأوّل', () {
      final o7 = alt.onus.firstWhere((o) => o.ponPort == 7);
      expect(o7.onuId, 2);
    });

    test('وعدّ المتّصلين صحيح', () {
      expect(alt.onusOnline, 2);
    });
  });

  group('المتانة', () {
    test('قائمةٌ فارغة لا ترمي', () {
      final b = VsolParse.build(const []);
      expect(b.onus, isEmpty);
      expect(b.ponPorts, isEmpty);
      expect(b.uplinks, isEmpty);
    });

    test('أسماءٌ غريبة تُهمَل ولا تُصنَّف خطأً', () {
      final b = VsolParse.build([
        r(1, 'lo'),
        r(2, 'vlan100'),
        r(3, 'Null0'),
        r(4, ''),
      ]);
      expect(b.onus, isEmpty);
      expect(b.ponPorts, isEmpty);
      expect(b.uplinks, isEmpty);
    });

    test('حالة الأحرف لا تكسر المطابقة', () {
      final b = VsolParse.build([r(1, 'epon0/2:7'), r(2, 'ge0/1')]);
      expect(b.onus.single.label, 'EPON0/2:7');
      expect(b.uplinks.length, 1);
    });

    test('منافذ صعودٍ بأسماءٍ أخرى تُلتقط', () {
      // XGE/TE على الطُّرز الأكبر — نقبلها كي لا يُعرَض منفذ عشرة
      // جيجابت كأنّه غير موجود.
      final b = VsolParse.build([r(1, 'XGE0/1'), r(2, 'TE0/2')]);
      expect(b.uplinks.length, 2);
    });
  });

  group('عنوان MAC', () {
    test('يُقرأ للمتّصل', () {
      final b = VsolParse.build(
          [r(9, 'EPON0/3:2', up: true, mac: '88:3f:d3:43:ff:3f')]);
      expect(b.onus.single.mac, '88:3f:d3:43:ff:3f');
    });

    test('ويُسقَط للمفصول — الجهاز يُرجع عنواناً قديماً مكرّراً', () {
      // على V1600D فعليّ: `EPON0/1:1` المفصول حمل عنوان `EPON0/2:9`
      // المتّصل. وعرضُ عنوان مشتركٍ أمام اسم آخر يُبنى عليه قرار.
      final b = VsolParse.build(
          [r(9, 'EPON0/1:1', up: false, mac: '7c:6a:60:0e:08:07')]);
      expect(b.onus.single.mac, isNull);
    });
  });

  group('التسمية', () {
    test('التسمية تطابق ما يكتبه المشغّل في الـCLI', () {
      final b = VsolParse.build([r(9, 'EPON0/3:2', up: true)]);
      expect(b.onus.single.label, 'EPON0/3:2');
    });
  });

  group('المعدّل بدل التراكميّ', () {
    // 🐛 بلاغ المستخدم ٢٠٢٦-١٠-٠١: «قيم الترفك مبالغ بيها ٣٧ كيكا».
    //
    // قياسٌ فعليّ على `Popq3-olt`: مرفوعٌ ٦٨ ساعة، ١٨٩ مشتركاً متّصلاً،
    // ومجموع منافذه الثمانية ٣٧٫٥ جيجابايت — أي ١٫٥ كيلوبت/ث لكلّ
    // مشترك على مدى ثلاثة أيّام. والعدّادات الستّة عشر كلّها دون ٢³²
    // وأربعةٌ منها على بُعد ١٪ من السقف. المجموع لم يكن مبالغاً فيه،
    // بل بلا معنى: موضعُ كلّ عدّادٍ في لفّته الحاليّة.
    VsolOltStats snap(int rx, int tx, {bool narrow = true}) => VsolOltStats(
          ponPorts: [
            VsolPonPort(
                index: 9, slot: 0, port: 1, up: true, rxBytes: rx, txBytes: tx)
          ],
          narrowCounters: narrow,
        );

    test('الفرق بين لقطتين يعطي بتاتٍ في الثانية', () {
      final r = VsolTraffic.between(
          snap(1000, 0), snap(126000, 0), const Duration(seconds: 10));
      // ‏١٢٥٬٠٠٠ بايت في عشر ثوانٍ = ١٢٬٥٠٠ بايت/ث = ١٠٠ كيلوبت/ث
      expect(r['EPON0/1']!.rxBps, closeTo(100000, 1));
    });

    test('⚠️ الالتفاف يُصحَّح لا يُقرأ هبوطاً', () {
      // عدّادٌ عند ٤٫٢٩ جيجا ناقص ألفاً ثمّ صار ألفاً: مرّ ألفان لا أن
      // الجهاز «أرجع» أربع جيجات.
      final r = VsolTraffic.between(
        snap(4294966296, 0),
        snap(1000, 0),
        const Duration(seconds: 1),
      );
      expect(r['EPON0/1']!.rxBps, closeTo(2000 * 8, 1));
    });

    test('⚠️ ما يتجاوز سرعة المنفذ لا يُعرَض رقماً', () {
      // 🐛 لبّ العطل: عدّادٌ ضيّق على منفذ EPON يلتفّ كلّ ٢٧ ثانيةً عند
      // الإشباع. فحين يُنتج الفرق معدّلاً فوق ١٫٢٥ جيجابت فقد فاتتنا
      // لفّةٌ كاملة — والرقم عندها تخمينٌ يُبنى عليه قرار.
      final r = VsolTraffic.between(
        snap(0, 0),
        snap(4000000000, 0),
        const Duration(seconds: 1),
      );
      expect(r['EPON0/1']!.rxBps, isNull);
      expect(r['EPON0/1']!.known, isFalse);
    });

    test('وعلى ٦٤ بت الهبوط إعادة تصفيرٍ لا التفاف', () {
      // عدّاد ٦٤ بت لا يلتفّ في عمر الجهاز، فهبوطه يعني إقلاعاً — ولا
      // نُصحّحه بإضافة ٢³² فنخترع مروراً لم يحدث.
      final r = VsolTraffic.between(
        snap(5000000000, 0, narrow: false),
        snap(1000, 0, narrow: false),
        const Duration(seconds: 1),
      );
      expect(r['EPON0/1']!.rxBps, isNull);
    });

    test('لقطةٌ واحدة لا تعطي معدّلاً', () {
      final r = VsolTraffic.between(
          const VsolOltStats(), snap(1000, 0), const Duration(seconds: 10));
      expect(r, isEmpty);
    });

    test('زمنٌ صفر لا يقسم على صفر', () {
      final r = VsolTraffic.between(snap(0, 0), snap(1000, 0), Duration.zero);
      expect(r['EPON0/1']!.rxBps, isNull);
    });

    test('المفتاح هو الاسم لا فهرس SNMP', () {
      // الفهرس يتغيّر بإعادة تسجيل الـONU بينما `EPON0/3:2` يبقى هو هو،
      // فالمقارنة بالفهرس تُنتج معدّلاً لمشتركٍ آخر.
      VsolOltStats withOnu(int ifIndex, int rx) => VsolOltStats(
            onus: [
              VsolOnu(
                  ifIndex: ifIndex,
                  slot: 0,
                  ponPort: 3,
                  onuId: 2,
                  online: true,
                  speedMbps: 1000,
                  rxBytes: rx)
            ],
            narrowCounters: true,
          );
      final r = VsolTraffic.between(
          withOnu(26, 1000), withOnu(91, 126000), const Duration(seconds: 10));
      expect(r['EPON0/3:2']!.rxBps, closeTo(100000, 1));
    });
  });

  group('الطبقة السريعة لا تمحو المشتركين', () {
    // 🐛 بلاغ المستخدم ٢٠٢٦-١٠-٠١: «المشتركون يظهر ترفك ويصير صفر
    // بسرعة، أمّا البونات طبيعي».
    //
    // الطبقة السريعة تسأل عن منافذ PON والصعود وحدها (‏٢٤ واجهةً في
    // ثانية) وتنقل عدّادات المشتركين كما هي. فالفرق عليها صفرٌ
    // بالضرورة — وهو ليس «لا مرور» بل «لم نقِس».
    VsolOltStats snap({required int pon, required int onu}) => VsolOltStats(
          narrowCounters: true,
          ponPorts: [
            VsolPonPort(
                index: 9, slot: 0, port: 1, up: true, rxBytes: pon, txBytes: 0)
          ],
          onus: [
            VsolOnu(
                ifIndex: 26,
                slot: 0,
                ponPort: 1,
                onuId: 2,
                online: true,
                speedMbps: 1000,
                rxBytes: onu,
                txBytes: 0)
          ],
        );

    test('🚨 الفرق على عدّادٍ منقولٍ يعطي صفراً — فلا يُكتَب', () {
      // منفذ PON تحرّك، والمشترك لم تُقرأ عدّاداته (نُقلت كما هي).
      final r = VsolTraffic.between(
        snap(pon: 1000, onu: 5000),
        snap(pon: 126000, onu: 5000),
        const Duration(seconds: 10),
      );
      expect(r['EPON0/1']!.rxBps, closeTo(100000, 1));
      // الصفر هنا حقيقيٌّ حسابيّاً، ولذلك **يجب ألّا تدمجه اللوحة**:
      // هذا الحارس يوثّق أنّ المصدر يُنتجه، والتصفية مسؤوليّة الدامج.
      expect(r['EPON0/1:2']!.rxBps, 0);
    });

    test('الدمج الانتقائيّ يُبقي آخر معدّلٍ معروفٍ للمشترك', () {
      // محاكاةُ ما تفعله اللوحة: نبدأ بمعدّلٍ معروف، ثمّ تأتي نبضةٌ
      // سريعة — فلا يُكتَب إلّا ما جُدّد.
      final known = <String, VsolTraffic>{
        'EPON0/1': const VsolTraffic(1000, 0),
        'EPON0/1:2': const VsolTraffic(40000000, 0),
      };
      final now = snap(pon: 126000, onu: 5000);
      final fresh = VsolTraffic.between(
          snap(pon: 1000, onu: 5000), now, const Duration(seconds: 10));

      final merged = Map<String, VsolTraffic>.from(known);
      for (final p in now.ponPorts) {
        final v = fresh[p.label];
        if (v != null) merged[p.label] = v;
      }

      expect(merged['EPON0/1']!.rxBps, closeTo(100000, 1));
      // ولم يُمسّ المشترك — لا صفرَ ولا وميض.
      expect(merged['EPON0/1:2']!.rxBps, 40000000);
    });
  });
}
