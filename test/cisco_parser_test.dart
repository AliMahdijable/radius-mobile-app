import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/cisco_api.dart';

import 'support/cisco_fixtures.dart';

/// اختبارات محلّلات Cisco — على مخرجاتٍ حقيقيّة من WS-C2960-24TT-L
/// (IOS 12.2(35)SE5) بترقيم صفحاتها كما أرسله الجهاز.
///
/// المحلّلات صرفة ولا تعرف النقل، فلا شبكة هنا ولا بيانات اعتماد.
void main() {
  group('ترقيم الصفحات', () {
    test('يمحو --More-- وبايتات المسح', () {
      final out = CiscoParse.stripPaging(kShowInterfacesStatus);
      expect(out.contains('--More--'), isFalse);
      expect(out.contains('\x08'), isFalse);
    });

    test('يحفظ السطر الملتحم بعد كسر الصفحة', () {
      // الجهاز يمحو «--More--» بالـbackspace ثمّ **يُكمل على السطر
      // نفسه**: `...10.100.19.254/24` ثمّ المسح ثمّ `  MTU 1500 bytes`.
      // حذفٌ سطريّ يبتلع الـMTU معه — وهذا ما يحرسه الاختبار.
      final out = CiscoParse.stripPaging(kShowInterfaces);
      expect(out, contains('MTU 1500 bytes, BW 1000000 Kbit'));
      expect(out, contains('Hardware is Gigabit Ethernet'));
    });

    test('لا يبتلع مسافات بداية المحتوى التالي', () {
      const raw = 'x\n --More-- \x08\x08\x08        \x08\x08\x08  MTU 1500\n';
      expect(CiscoParse.stripPaging(raw), 'x\n  MTU 1500\n');
    });
  });

  group('show version', () {
    final v = CiscoParse.version(kShowVersion);

    test('الموديل', () => expect(v.model, 'WS-C2960-24TT-L'));

    test('نسخة IOS لا نسخة مُحمِّل الإقلاع', () {
      // في المخرجات سطران فيهما «Version»: نظامُ التشغيل
      // 12.2(35)SE5 وBOOTLDR‏ 12.2(25r)SEE6. الثاني ليس نسخة الجهاز.
      expect(v.iosVersion, '12.2(35)SE5');
      expect(v.iosVersion, isNot(contains('25r')));
    });

    test('الاسم والرقم التسلسليّ', () {
      expect(v.hostname, 'cisco-alsudany');
      expect(v.serial, 'FOC1302V76V');
    });

    test('مدّة التشغيل', () {
      // «6 weeks, 1 day, 15 hours, 20 minutes»
      expect(v.uptime, isNotNull);
      expect(v.uptime!.inDays, 6 * 7 + 1);
      expect(v.uptime!.inHours % 24, 15);
    });

    test('ذاكرة الإقلاع المُعلَنة', () {
      expect(v.mainMemKb, 61440);
      expect(v.ioMemKb, 4088);
    });

    test('مدّة التشغيل بصيغٍ أخرى', () {
      expect(CiscoParse.parseUptime('1 year, 2 weeks, 3 days')!.inDays,
          365 + 14 + 3);
      expect(CiscoParse.parseUptime('45 minutes')!.inMinutes, 45);
      expect(CiscoParse.parseUptime('لا شيء'), isNull);
    });
  });

  group('show interfaces status', () {
    final ifaces = CiscoParse.interfacesStatus(kShowInterfacesStatus);

    test('يقرأ المنافذ الستّة والعشرين رغم كسر الصفحة', () {
      // ٢٤ منفذ Fast + منفذا Gigabit. العنوان يتكرّر بعد «--More--»،
      // فإن عُدّ سطراً صار العدد أكبر، وإن أوقف التحليل صار أصغر.
      expect(ifaces.length, 26);
      expect(ifaces.first.name, 'FastEthernet0/1');
      expect(ifaces.last.name, 'GigabitEthernet0/2');
    });

    test('العنوان المتكرّر ليس منفذاً', () {
      expect(ifaces.where((i) => i.name.startsWith('Port')), isEmpty);
    });

    test('حالة المنفذ', () {
      final fa1 = ifaces.firstWhere((i) => i.name == 'FastEthernet0/1');
      expect(fa1.up, isFalse);
      expect(fa1.status, 'notconnect');
      expect(fa1.adminUp, isTrue); // مفصولٌ كبلاً لا مُطفأً إداريّاً

      final fa2 = ifaces.firstWhere((i) => i.name == 'FastEthernet0/2');
      expect(fa2.up, isTrue);
      expect(fa2.status, 'connected');
      expect(fa2.speedMbps, 100);
      expect(fa2.fullDuplex, isTrue);
      expect(fa2.vlan, '90');
    });

    test('العمود المُحاذى يميناً: a-1000 لا يلتهم عمود الـDuplex', () {
      // `a-1000` أعرض من عنوان عموده بخانة، فيبدأ قبله. تقطيعٌ بعرضٍ
      // ثابت يعطي Duplex = «a-full a» وSpeed مبتورة.
      final gi1 = ifaces.firstWhere((i) => i.name == 'GigabitEthernet0/1');
      expect(gi1.speedMbps, 1000);
      expect(gi1.fullDuplex, isTrue);
      expect(gi1.media, '10/100/1000BaseTX');
    });

    test('auto تعني «لم يُتَّفق» لا «نصف» ولا صفراً', () {
      final fa1 = ifaces.firstWhere((i) => i.name == 'FastEthernet0/1');
      expect(fa1.speedMbps, isNull);
      expect(fa1.fullDuplex, isNull);
    });

    test('لاحقة G تُقرأ آلاف الميغابت', () {
      // منفذ عشرة جيجا — لا يوجد على 2960، فالسطر مُركَّب بصيغة IOS.
      const tenGig = 'show interfaces status\r\n'
          'Port      Name               Status       Vlan       Duplex  Speed Type\r\n'
          'Te1/0/1                      connected    1            full    10G SFP-10GBase-SR\r\n'
          'sw#';
      final te = CiscoParse.interfacesStatus(tenGig).single;
      expect(te.name, 'TenGigabitEthernet1/0/1');
      expect(te.speedMbps, 10000);
    });

    test('الوصف قد يحوي مسافات', () {
      const withName = 'show interfaces status\r\n'
          'Port      Name               Status       Vlan       Duplex  Speed Type\r\n'
          'Fa0/5     link to tower A    connected    90         a-full  a-100 10/100BaseTX\r\n'
          'sw#';
      final p = CiscoParse.interfacesStatus(withName).single;
      expect(p.description, 'link to tower A');
      expect(p.speedMbps, 100);
    });
  });

  group('show interfaces (العدّادات)', () {
    final detail = CiscoParse.interfacesDetail(kShowInterfaces);

    test('يفصل الكتل', () {
      expect(detail.map((e) => e.name),
          containsAll(['Vlan90', 'FastEthernet0/1', 'GigabitEthernet0/1']));
    });

    test('عدّادات منفذٍ عامل', () {
      final gi1 = detail.firstWhere((i) => i.name == 'GigabitEthernet0/1');
      expect(gi1.up, isTrue);
      expect(gi1.adminUp, isTrue);
      expect(gi1.rxBytes, 56789619054608); // أكبر من 2³² — لا يُبتَر
      expect(gi1.txBytes, 4703208995538);
      expect(gi1.inErrors, 1119);
      expect(gi1.outErrors, 0);
      expect(gi1.speedMbps, 1000);
      expect(gi1.fullDuplex, isTrue);
    });

    test('معدّل الخمس دقائق يأتي من الجهاز', () {
      // يغنينا عن حساب الفروق بين جولتين، فيصحّ من أوّل لقطة.
      final gi1 = detail.firstWhere((i) => i.name == 'GigabitEthernet0/1');
      expect(gi1.rxBps, 225743000);
      expect(gi1.txBps, 19291000);
    });

    test('«مُطفأ إداريّاً» يختلف عن «مفصول»', () {
      final fa1 = detail.firstWhere((i) => i.name == 'FastEthernet0/1');
      expect(fa1.up, isFalse);
      expect(fa1.adminUp, isTrue);
    });
  });

  group('الدمج', () {
    test('يضمّ العدّادات إلى صفوف الحالة بلا تكرار', () {
      final merged = CiscoParse.merge(
        CiscoParse.interfacesStatus(kShowInterfacesStatus),
        CiscoParse.interfacesDetail(kShowInterfaces),
      );
      final gi1 = merged.firstWhere((i) => i.name == 'GigabitEthernet0/1');
      expect(gi1.vlan, '90'); // من الحالة
      expect(gi1.rxBytes, 56789619054608); // من التفاصيل
      expect(merged.where((i) => i.name == 'GigabitEthernet0/1').length, 1);
    });

    test('الواجهات المنطقيّة تُلحَق ولا تُفقَد', () {
      final merged = CiscoParse.merge(
        CiscoParse.interfacesStatus(kShowInterfacesStatus),
        CiscoParse.interfacesDetail(kShowInterfaces),
      );
      expect(merged.map((e) => e.name), contains('Vlan90'));
    });
  });

  group('المنافذ الفيزيائيّة', () {
    test('لا تُعدّ الواجهات المنطقيّة منافذ لوحة', () {
      const stats = CiscoStats(ifaces: [
        CiscoInterface(name: 'GigabitEthernet0/1', up: true),
        CiscoInterface(name: 'FastEthernet0/1', up: false),
        CiscoInterface(name: 'Vlan90', up: true),
        CiscoInterface(name: 'Port-channel1', up: true),
        CiscoInterface(name: 'Loopback0', up: true),
      ]);
      expect(stats.portsTotal, 2);
      expect(stats.portsUp, 1); // Gi0/1 وحده
    });
  });

  group('CPU والذاكرة', () {
    test('نسبة المعالج من سطر الخمس ثوانٍ', () {
      expect(CiscoParse.cpuPercent(kShowProcessesCpu), 4.0);
    });

    test('ذاكرة المعالج لا ذاكرة الإدخال/الإخراج', () {
      // للجدول ثلاثة صفوف؛ صفّ I/O ذاكرةُ مخازن لا ذاكرةُ نظام.
      final m = CiscoParse.memory(kShowMemoryStatistics)!;
      expect(m.totalBytes, 41031056);
      expect(m.usedBytes, 6365984);
      expect(m.freeBytes, 34665072);
      expect(m.usedPercent, closeTo(15.5, 0.5));
    });

    test('أمرٌ غير مدعوم يُرجع null لا يرمي', () {
      const bad = 'show processes cpu | include utilization\r\n'
          '% Invalid input detected at \'^\' marker.\r\nsw#';
      expect(CiscoParse.isUnsupportedCommand(bad), isTrue);
      expect(CiscoParse.cpuPercent(bad), isNull);
      expect(CiscoParse.memory(bad), isNull);
    });
  });

  group('أسماء المنافذ', () {
    test('البسط والاختصار', () {
      expect(CiscoParse.expandIfName('Fa0/1'), 'FastEthernet0/1');
      expect(CiscoParse.expandIfName('Gi1/0/24'), 'GigabitEthernet1/0/24');
      expect(CiscoParse.expandIfName('Po1'), 'Port-channel1');
      expect(CiscoParse.shortIfName('TenGigabitEthernet1/0/1'), 'Te1/0/1');
    });

    test('الاسم المطوّل يبقى كما هو', () {
      expect(CiscoParse.expandIfName('FastEthernet0/1'), 'FastEthernet0/1');
      expect(CiscoParse.expandIfName('Vlan90'), 'Vlan90');
    });
  });
}
