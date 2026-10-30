import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_ip_link.dart';

/// المالك ٣٠ أكتوبر: «بقسم الاجهزه ضيفلنا ميزه النقر على الايبي الجهاز يفتح كوكل يعني يفتح الرابط بالمتصفح في جميع المنصات».
/// النقر يفتح `http://IP` بالمتصفح الخارجيّ، والمطوّل ينسخ كما كان، وداخل بطاقةٍ تفتح الجهاز يبقى النقر خارج العنوان لها.
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
        home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: Center(child: child))),
      );

  test('الرابط: http://IP، وIPv6 بين قوسين، وhost:port كما هو، والفارغ لا رابط', () {
    expect(DeviceIpLink.urlFor('192.168.1.1').toString(), 'http://192.168.1.1');
    expect(DeviceIpLink.urlFor(' 10.0.0.5 ').toString(), 'http://10.0.0.5');
    expect(DeviceIpLink.urlFor('10.0.0.5:8080').toString(), 'http://10.0.0.5:8080');
    expect(DeviceIpLink.urlFor('fe80::1').toString(), 'http://[fe80::1]');
    expect(DeviceIpLink.urlFor('https://olt.local').toString(), 'https://olt.local');
    expect(DeviceIpLink.urlFor('router.lan').toString(), 'http://router.lan');
    expect(DeviceIpLink.urlFor(''), isNull);
    expect(DeviceIpLink.urlFor('—'), isNull);
    expect(DeviceIpLink.urlFor('1.2.3.4 x'), isNull);
  });

  testWidgets('النقر يفتح المتصفح على الجهاز', (t) async {
    await t.pumpWidget(host(const DeviceIpLink('192.168.88.1')));
    await t.tap(find.text('192.168.88.1'));
    await t.pump();
    expect(opened.map((u) => u.toString()), ['http://192.168.88.1']);
  });

  testWidgets('داخل بطاقةٍ تفتح الجهاز: النقر على العنوان للمتصفح وحده، وخارجه للبطاقة', (t) async {
    var cardTaps = 0;
    await t.pumpWidget(host(SizedBox(
      width: 300,
      height: 120,
      child: InkWell(
        onTap: () => cardTaps += 1,
        child: const Column(children: [
          SizedBox(height: 60, child: Text('اسم الجهاز')),
          DeviceIpLink('10.10.10.1'),
        ]),
      ),
    )));
    await t.tap(find.text('10.10.10.1'));
    await t.pump();
    expect([opened.length, cardTaps], [1, 0]);
    await t.tap(find.text('اسم الجهاز'));
    await t.pump();
    expect([opened.length, cardTaps], [1, 1]);
  });

  testWidgets('الضغط المطوّل ينسخ ولا يفتح المتصفح', (t) async {
    await t.pumpWidget(host(const DeviceIpLink('172.16.0.1')));
    await t.longPress(find.text('172.16.0.1'));
    await t.pump(const Duration(seconds: 1));
    expect(opened, isEmpty);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('تعذّر فتح المتصفح ⇒ رسالةٌ لا صمت', (t) async {
    DeviceIpLink.launcher = (u) async => false;
    await t.pumpWidget(host(const DeviceIpLink('192.168.1.20')));
    await t.tap(find.text('192.168.1.20'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('تعذّر فتح المتصفح'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('عنوانٌ فارغ ⇒ نصٌّ عاديّ بلا رابط', (t) async {
    await t.pumpWidget(host(const DeviceIpLink('—')));
    await t.tap(find.text('—'));
    await t.pump();
    expect(opened, isEmpty);
  });
}
