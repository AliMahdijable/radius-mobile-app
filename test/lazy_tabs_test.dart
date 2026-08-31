import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';

/// التبويبات لا تُبنى قبل زيارتها.
///
/// 🐛 بلاغ 2026-08-31 («التطبيق ثكيل كلش»): `IndexedStack` يبني كلّ
/// أبنائه، فكان `NetworkDevicesScreen.initState` يُنفَّذ لحظة الإقلاع
/// ويُشغّل حلقة تفتح مقبساً TCP لكلّ جهاز على شبكة LAN بعيدة كلّ 20
/// ثانية — لشاشة لم يفتحها المستخدم قطّ. السجلّ كان يمتلئ بـ
/// `tcpProbe … errno = 110` والمستخدم على الرئيسيّة.
///
/// هذه الاختبارات تحرس الشكل لا النيّة: من يُعيد `children: tabs`
/// مباشرةً يُعيد العطل كاملاً، وسيسقط هنا.
void main() {
  final tabs = <Widget>[
    const Text('t0'),
    const Text('t1'),
    const Text('t2'),
    const Text('t3'),
  ];

  test('غير المزار لا يُمرَّر — يُستبدل بـSizedBox', () {
    final out = lazyTabChildren(tabs, {0});
    expect(out, hasLength(4));
    expect(out[0], same(tabs[0]));
    for (final i in [1, 2, 3]) {
      expect(out[i], isA<SizedBox>(),
          reason: 'التبويب $i لم يُزَر ومع ذلك بُني');
      expect(out[i], isNot(same(tabs[i])));
    }
  });

  test('المزار يمرّ كما هو — الحالة لا تضيع بالتنقّل', () {
    final out = lazyTabChildren(tabs, {0, 2});
    expect(out[0], same(tabs[0]));
    expect(out[2], same(tabs[2]));
    expect(out[1], isA<SizedBox>());
    expect(out[3], isA<SizedBox>());
  });

  test('الطول يبقى ثابتاً — الفهرسة تعتمد عليه', () {
    // `IndexedStack.index` فهرسٌ في هذه القائمة نفسها: أيّ حذف بدل
    // استبدال يزيح التبويبات ويعرض الشاشة الخطأ.
    for (final visited in [<int>{}, {0}, {0, 1, 2, 3}]) {
      expect(lazyTabChildren(tabs, visited), hasLength(tabs.length));
    }
  });

  test('كلّها مزارة — لا فرق عن السلوك القديم', () {
    final out = lazyTabChildren(tabs, {0, 1, 2, 3});
    for (var i = 0; i < tabs.length; i++) {
      expect(out[i], same(tabs[i]));
    }
  });

  testWidgets('SizedBox البديل لا يرسم شيئاً ولا يأخذ مساحة', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: IndexedStack(index: 0, children: lazyTabChildren(tabs, {0})),
      ),
    ));
    expect(find.text('t0'), findsOneWidget);
    // الحاسم: نصوص التبويبات غير المزارة غير موجودة في الشجرة أصلاً —
    // لا مخفيّة، بل لم تُنشأ.
    expect(find.text('t1'), findsNothing);
    expect(find.text('t2'), findsNothing);
    expect(find.text('t3'), findsNothing);
  });
}
