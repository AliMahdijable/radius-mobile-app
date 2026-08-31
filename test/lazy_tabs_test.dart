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
Widget? _unwrap(Widget w) {
  var cur = w;
  if (cur is TickerMode) cur = cur.child;
  if (cur is ExcludeSemantics) return cur.child;
  return cur;
}

void main() {
  _semanticsGuard();
  final tabs = <Widget>[
    const Text('t0'),
    const Text('t1'),
    const Text('t2'),
    const Text('t3'),
  ];

  test('غير المزار لا يُمرَّر — يُستبدل بـSizedBox', () {
    final out = lazyTabChildren(tabs, {0}, 0);
    expect(out, hasLength(4));
    expect(_unwrap(out[0]), same(tabs[0]));
    for (final i in [1, 2, 3]) {
      expect(out[i], isA<SizedBox>(),
          reason: 'التبويب $i لم يُزَر ومع ذلك بُني');
      expect(out[i], isNot(same(tabs[i])));
    }
  });

  test('المزار يمرّ كما هو — الحالة لا تضيع بالتنقّل', () {
    final out = lazyTabChildren(tabs, {0, 2}, 0);
    expect(_unwrap(out[0]), same(tabs[0]));
    expect(_unwrap(out[2]), same(tabs[2]));
    expect(out[1], isA<SizedBox>());
    expect(out[3], isA<SizedBox>());
  });

  test('الطول يبقى ثابتاً — الفهرسة تعتمد عليه', () {
    // `IndexedStack.index` فهرسٌ في هذه القائمة نفسها: أيّ حذف بدل
    // استبدال يزيح التبويبات ويعرض الشاشة الخطأ.
    for (final visited in [<int>{}, {0}, {0, 1, 2, 3}]) {
      expect(lazyTabChildren(tabs, visited, 0), hasLength(tabs.length));
    }
  });

  test('كلّها مزارة — لا فرق عن السلوك القديم', () {
    final out = lazyTabChildren(tabs, {0, 1, 2, 3}, 0);
    for (var i = 0; i < tabs.length; i++) {
      expect(_unwrap(out[i]), same(tabs[i]));
    }
  });

  testWidgets('SizedBox البديل لا يرسم شيئاً ولا يأخذ مساحة', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: IndexedStack(index: 0, children: lazyTabChildren(tabs, {0}, 0)),
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

// ─────────────────────────────────────────────────────────────
void _semanticsGuard() {
  final tabs = <Widget>[
    const Text('t0'),
    const Text('t1'),
    const Text('t2'),
  ];

  test('المخفيّ يُستثنى من شجرة الدلالات، والمعروض لا', () {
    // ⚠️ ليس تحسيناً لإمكانيّة الوصول بل سدُّ فجوة في الإطار:
    // `RenderIndexedStack.index` يُبدّل مجموعة أبناء الدلالات كاملةً
    // لكنّه يستدعي `markNeedsLayout()` وحدها (stack.dart:792-797)،
    // فيُكشَف تبويبٌ بـparentData فارغة وتسقط الثابتة
    // `!semantics.parentDataDirty` في كلّ إطار. و`ExcludeSemantics`
    // مُعيِّنها يستدعي `markNeedsSemanticsUpdate()` — وهو الإشعار
    // الناقص.
    final out = lazyTabChildren(tabs, {0, 1, 2}, 1);
    for (var i = 0; i < tabs.length; i++) {
      final w = out[i];
      expect(w, isA<TickerMode>(),
          reason: 'الخانة $i بلا TickerMode — حركاتها تنبض وهي مخفيّة');
      final tm = w as TickerMode;
      expect(tm.enabled, i == 1,
          reason: 'الخانة $i: المعروض وحده تنبض حركاته');
      expect(tm.child, isA<ExcludeSemantics>(),
          reason: 'الخانة $i غير ملفوفة بـExcludeSemantics — يعود العطل');
      expect((tm.child as ExcludeSemantics).excluding, i != 1,
          reason: 'الخانة $i: المعروض وحده لا يُستثنى');
    }
  });

  test('غير المزار يبقى SizedBox لا ExcludeSemantics فارغة', () {
    final out = lazyTabChildren(tabs, {1}, 1);
    expect(out[0], isA<SizedBox>());
    expect(out[1], isA<TickerMode>());
    expect(out[2], isA<SizedBox>());
  });
}
