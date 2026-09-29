import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/edgeswitch_api.dart';

import 'support/edgeswitch_fixtures.dart';

/// محلّلات EdgeSwitch على لقطاتٍ حقيقيّة من ES-24-250W.
///
/// كلّ ما هنا خالصٌ — لا شبكة ولا اعتماد. ما يُفحص هو ما أخطأنا فيه
/// من قبل في أجهزةٍ أخرى: خلط السرعة، وترتيبٌ نصّيٌّ يضع ١٠ قبل ٢،
/// وعدّ ما ليس منفذاً منفذاً.
void main() {
  dynamic dev() => jsonDecode(kEsDeviceJson);
  dynamic sys() => jsonDecode(kEsSystemJson);
  dynamic stx() => jsonDecode(kEsStatisticsJson);
  dynamic ifs() => jsonDecode(kEsInterfacesJson);

  EdgeSwitchStats parsed() => EdgeSwitchParse.stats(
        device: dev(),
        system: sys(),
        statistics: stx(),
        interfaces: ifs(),
      )!;

  group('التعريف', () {
    test('الطراز يُقرأ من الرمز القصير لا الاسم الطويل', () {
      // مطابقة الصور في DeviceImage تقوم على الرمز — «EdgeSwitch 24 250W»
      // لا يطابق أيّ أصل، و«ES-24-250W» يطابق.
      expect(EdgeSwitchParse.model(dev()), 'ES-24-250W');
    });

    test('الإصدار والـMAC واسم المضيف', () {
      final s = parsed();
      expect(s.firmware, '1.9.2');
      expect(s.mac, 'e4:38:83:db:b3:ab');
      expect(s.hostname, 'UBNT EdgeSwitch');
    });

    test('عنوان الإدارة والبوّابة يُنتقيان من الإصدار الرابع', () {
      // الجهاز يُرجع IPv6 link-local كذلك — أخذُ الأوّل يعطي fe80::…
      final s = parsed();
      expect(s.address, '10.64.100.3/24');
      expect(s.gateway, '10.64.100.1');
    });
  });

  group('الموارد', () {
    test('المعالج والذاكرة والحرارة', () {
      final s = parsed();
      expect(s.cpuPercent, isNotNull);
      expect(s.ramPercent, isNotNull);
      expect(s.temperatureC, isNotNull);
    });

    test('الحرارة المعروضة هي الأعلى لا الأولى ولا المتوسّط', () {
      final raw = stx()[0]['device']['temperatures'] as List;
      final top = raw
          .map((e) => (e['value'] as num))
          .reduce((a, b) => a > b ? a : b);
      expect(parsed().temperatureC, top);
    });

    test('مدّة التشغيل تُقرأ بالعربيّة لا تُختصر', () {
      final t = parsed().uptimeText;
      // «١٠ س ٣» خلط اليوم بالساعة في كارت المشترك وأبلغ عنه المستخدم.
      expect(t, isNotNull);
      expect(t, isNot(contains(' س ')));
      expect(
        t!.contains('يوم') || t.contains('أيّام') || t.contains('ساعة'),
        isTrue,
        reason: 'النصّ يجب أن يسمّي الوحدة: $t',
      );
    });
  });

  group('المنافذ', () {
    test('مدخلات LAG تُستبعَد — ليست منافذ فيزيائيّة', () {
      final all = (ifs() as List).length;
      final lags = (ifs() as List)
          .where((e) => e['identification']['type'] != 'port')
          .length;
      expect(lags, greaterThan(0), reason: 'اللقطة يجب أن تحوي LAG للفحص');
      expect(parsed().ports.length, all - lags);
    });

    test('«يعمل» يقتضي الكابل والتفعيل الإداريّ معاً', () {
      final s = parsed();
      final up = s.ports.where((p) => p.up).toList();
      for (final p in up) {
        expect(p.plugged, isTrue);
        expect(p.enabled, isTrue);
      }
      expect(s.portsUp, up.length);
    });

    test('منفذٌ بلا كابل ليس «يعمل» ولو كان مفعَّلاً', () {
      final s = parsed();
      final idle = s.ports.where((p) => !p.plugged);
      expect(idle, isNotEmpty, reason: 'اللقطة يجب أن تحوي منفذاً فارغاً');
      for (final p in idle) {
        expect(p.up, isFalse);
      }
    });

    test('«1000-full» تُقرأ ١٠٠٠ ميجابت', () {
      final p = parsed().ports.firstWhere((p) => p.plugged);
      expect(p.speedRaw, startsWith('1000'));
      expect(p.speed, 1000);
    });

    test('١٠ جيجابت لا تنهار إلى عشرة', () {
      // 🐛 هذه بالضبط مصيدة سسكو: أخذُ أوّل رقمين يحوّل منفذاً سليماً
      // إلى منهار في عين المشغّل.
      final j = jsonDecode(kEsInterfacesJson) as List;
      final one = Map<String, dynamic>.from(j.firstWhere(
          (e) => e['identification']['type'] == 'port') as Map);
      one['status'] = Map<String, dynamic>.from(one['status'] as Map)
        ..['currentSpeed'] = '10000-full';
      final s = EdgeSwitchParse.stats(
          device: dev(), system: sys(), statistics: stx(), interfaces: [one])!;
      expect(s.ports.single.speed, 10000);
    });

    test('الترتيب رقميٌّ لا نصّيّ — ٢ قبل ١٠', () {
      final j = jsonDecode(kEsInterfacesJson) as List;
      final tpl = j.firstWhere((e) => e['identification']['type'] == 'port');
      List<Map<String, dynamic>> mk(List<String> ids) => ids.map((id) {
            final m = jsonDecode(jsonEncode(tpl)) as Map<String, dynamic>;
            m['identification'] = Map<String, dynamic>.from(
                m['identification'] as Map)
              ..['id'] = id;
            return m;
          }).toList();
      final s = EdgeSwitchParse.stats(
        device: dev(),
        system: sys(),
        statistics: stx(),
        interfaces: mk(['0/10', '0/2', '0/1']),
      )!;
      expect(s.ports.map((p) => p.id).toList(), ['0/1', '0/2', '0/10']);
    });

    test('التسمية المختصرة هي الرقم وحده', () {
      final s = parsed();
      expect(s.ports.first.shortLabel, '1');
    });

    test('العدّادات تُدمَج من statistics بالمعرّف', () {
      // الحالة والسرعة في `interfaces`، والبايتات والمعدّلات في
      // `statistics` — مصدران يجب أن يلتقيا على المعرّف نفسه.
      final s = parsed();
      final p = s.ports.firstWhere((p) => p.id == '0/1');
      expect(p.txBytes, isNotNull);
      expect(p.rxBytes, isNotNull);
      expect(p.txRate, isNotNull);
    });
  });

  group('PoE', () {
    test('كلّ منافذ اللقطة مطفأة — فلا طاقة ولا عدّ', () {
      // الجهاز الفعليّ وقت الالتقاط لم يكن يغذّي شيئاً. نثبّت ذلك حتّى
      // لا يمرّ حسابٌ خاطئ بصمت لو تغيّرت اللقطة لاحقاً.
      final s = parsed();
      expect(s.poePorts, 0);
      expect(s.poeTotalWatts, 0);
    });

    test('منفذٌ يغذّي فعلاً يُحسَب — بطاقةٍ لا بإعدادٍ وحده', () {
      // `poe: active` مع صفر واط يعني منفذاً مهيّأً لا مغذّياً.
      const off = EdgeSwitchPort(
          id: '0/5', enabled: true, plugged: true, poe: 'active', poeWatts: 0);
      const on = EdgeSwitchPort(
          id: '0/6', enabled: true, plugged: true, poe: 'active', poeWatts: 6.4);
      expect(off.poeActive, isFalse);
      expect(on.poeActive, isTrue);
    });
  });

  group('التمييز عن airOS', () {
    test('صفحة الجذر تكشف EdgeSwitch قبل أيّ دخول', () {
      expect(EdgeSwitchParse.looksLikeEdgeSwitch(kEsRootHtml), isTrue);
    });

    test('صفحة airOS لا تُعَدّ EdgeSwitch', () {
      const airos = '<html><head><title>NanoStation M5</title></head>'
          '<body>airOS</body></html>';
      expect(EdgeSwitchParse.looksLikeEdgeSwitch(airos), isFalse);
    });
  });

  group('المتانة', () {
    test('جسمٌ فارغ لا يرمي', () {
      final s = EdgeSwitchParse.stats(
          device: const {}, system: const {}, statistics: const [], interfaces: const []);
      expect(s, isNotNull);
      expect(s!.ports, isEmpty);
      expect(s.uptimeText, isNull);
    });

    test('أنواعٌ غير متوقّعة لا ترمي', () {
      final s = EdgeSwitchParse.stats(
          device: 'نصّ', system: 42, statistics: 'لا شيء', interfaces: null);
      expect(s, isNotNull);
      expect(s!.ports, isEmpty);
    });
  });
}
