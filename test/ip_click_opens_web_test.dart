import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/desk_device_kit.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_ip_link.dart';

/// نقر الآيبي يفتح صفحة الجهاز (١٨ نوفمبر — المالك: «الآيبي بصفحات المشتركين بنسخة الحاسوب (مايكروسوفت) النقر يسوي نسخ — خلّه
/// يفتح صفحة الويب مثل كارت المشترك، ونفسه بقسم الأجهزة وأقسام الفحص الشامل للمشتركين والأجهزة»). [DeviceIpLink] في كلّ موضع:
/// النقر يفتح http://IP، والضغط المطوّل/الزرّ الأيمن ينسخ كما كان.
void main() {
  final opened = <Uri>[];
  setUp(() {
    opened.clear();
    DeviceIpLink.launcher = (u) async {
      opened.add(u);
      return true;
    };
  });

  Widget host(Widget child) => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: SizedBox(width: 320, child: child))),
        ),
      );

  testWidgets('DeskFact(link): العنوان رابطٌ يفتح الجهاز، وبلا link كما كان (نصٌّ أو نسخٌ بالمطوّل)', (t) async {
    await t.pumpWidget(host(const DeskFact('عنوان الطرف المقابل', '10.20.30.40', ltr: true, link: true)));
    expect(find.byType(DeviceIpLink), findsOneWidget);
    await t.tap(find.text('10.20.30.40'));
    await t.pump();
    expect(opened.map((u) => '$u'), ['http://10.20.30.40']);

    await t.pumpWidget(host(const DeskFact('المنصّة', 'AF60-LR', ltr: true, copy: true)));
    expect(find.byType(DeviceIpLink), findsNothing);
  });

  testWidgets('DeskMonoCell(link): عنوان العميل بجدول الحاسبة يفتح صفحته', (t) async {
    await t.pumpWidget(host(const DeskMonoCell('10.1.2.3', label: 'IP', link: true)));
    await t.tap(find.text('10.1.2.3'));
    await t.pump();
    expect(opened.map((u) => '$u'), ['http://10.1.2.3']);

    await t.pumpWidget(host(const DeskMonoCell('AA:BB:CC:DD:EE:FF', label: 'الماك')));
    expect(find.byType(DeviceIpLink), findsNothing);
  });

  test('المواضع: جدول المشتركين والفحص الشامل ولوحات الأجهزة تعرض العنوان رابطاً لا نسخاً بالنقر', () {
    String src(String p) => File(p).readAsStringSync();

    final table = src('lib/screens/subscribers/widgets/subscriber_table_row.dart');
    expect(table, contains('if (ip.isNotEmpty) DeviceIpLink(ip, style: _monoStyle(sub.isOnline)),'));
    expect(table, isNot(contains('_copyableValue(context, ip,')), reason: 'IP الجلسة لا يُنسخ بالنقر');
    expect(table, contains('_copyableValue(context, mac,'), reason: 'الماك يبقى نسخاً بالنقر كما كان');

    final check = src('lib/screens/network_devices/check/devices_check_screen.dart');
    expect(check, contains('Flexible(child: DeviceIpLink(ip, style: style)),'));
    expect(check, contains('_subLine(r),'));

    final ubnt = src('lib/screens/network_devices/widgets/ubnt_live_panel.dart');
    expect(ubnt, contains('DeviceIpLink(s.ip!,'));
    final mikrotik = src('lib/screens/network_devices/widgets/mikrotik_live_panel.dart');
    expect(mikrotik, contains('DeviceIpLink(c.ip!,'));
    final mimosa = src('lib/screens/network_devices/widgets/mimosa_live_panel.dart');
    expect(mimosa, contains('DeviceIpLink(c.ip!,'));
    expect(mimosa, contains("DeskMonoCell(c.ip!, label: 'IP', link: true)"));
    final ruijie = src('lib/screens/network_devices/widgets/ruijie_live_panel.dart');
    expect(ruijie, contains("DeskFact('عنوان الطرف المقابل', p.ip!, ltr: true, link: true)"));
  });
}
