import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `SliverFillRemaining(hasScrollBody: false)` لا يقبل طفلاً قابلاً للتمرير.
///
/// 🐛 بلاغ 2026-08-31: شاشة المشتركين تُرسم بيضاء فارغة، والسجلّ يفيض
/// بلا انقطاع بثلاثة أخطاء بدت غير مترابطة:
///   RenderViewport does not support returning intrinsic dimensions
///   Null check operator used on a null value
///   '!semantics.parentDataDirty': is not true
///
/// وهي عرَضٌ **واحد**: `_EmptyState` كان يُرجع `ListView` (تعليقه يقول
/// «حتى يعمل السحب للتحديث») وهو داخل `SliverFillRemaining` بلا جسم
/// تمرير. تلك تسأل طفلها عن ارتفاعه الذاتيّ، و`RenderViewport` لا يملكه
/// بحكم تعريفه. فيرمي، وتبقى `geometry` فارغة، فيرمي الأب على
/// `child.geometry!`، ثمّ يفيض محرّك الدلالات على `sliver.geometry!` في
/// كلّ إطار إلى الأبد.
///
/// ويقع حصراً حين يفرغ الفلتر — ولهذا لم يظهر إلّا في قسم «غير مفعّل».
void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
              SliverFillRemaining(hasScrollBody: false, child: child),
            ],
          ),
        ),
      );

  testWidgets('طفل قابل للتمرير يُفجّر التخطيط — توثيق المصيدة', (t) async {
    // ⚠️ الالتقاط عبر `FlutterError.onError` لا `takeException`: العطل
    // يتسلسل (الارتفاع الذاتيّ يرمي → `geometry` تبقى فارغة → الأب يرمي
    // عليها)، و`takeException` تُرجع عندها كائن ملخّص «Multiple
    // exceptions» لا الرسائل نفسها.
    final caught = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) => caught.add(d.exceptionAsString());
    await t.pumpWidget(wrap(ListView(children: const [Text('x')])));
    FlutterError.onError = prev;
    while (t.takeException() != null) {}

    expect(caught, isNotEmpty,
        reason: 'إن توقّف فلاتر عن الرمي هنا فقد زال سبب القيد أدناه');
    expect(caught.join('\n'), contains('intrinsic'),
        reason: 'الرسالة الأولى هي أصل السلسلة كلّها');
  });

  testWidgets('طفل غير قابل للتمرير سليم', (t) async {
    await t.pumpWidget(wrap(
      const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.inbox),
        Text('لا يوجد مشترك في هذا الفلتر'),
      ])),
    ));
    expect(t.takeException(), isNull);
  });

  test('_EmptyState لا يحتوي شيئاً قابلاً للتمرير', () {
    final src =
        File('lib/screens/subscribers/subscribers_screen.dart').readAsStringSync();
    final i = src.indexOf('class _EmptyState');
    expect(i, greaterThan(0), reason: 'رُبّما أُعيدت تسمية الصنف');
    final j = src.indexOf('\nclass ', i + 1);
    final body = (j > 0 ? src.substring(i, j) : src.substring(i))
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    for (final banned in [
      'ListView',
      'SingleChildScrollView',
      'GridView',
      'CustomScrollView',
      'PageView',
    ]) {
      expect(body.contains(banned), isFalse,
          reason: '$banned داخل _EmptyState يُعيد العطل — راجع تعليق الصنف');
    }
  });

  test('CustomScrollView تسمح بإفراط التمرير — وإلّا مات السحب للتحديث', () {
    final src =
        File('lib/screens/subscribers/subscribers_screen.dart').readAsStringSync();
    expect(src.contains('physics: const AlwaysScrollableScrollPhysics()'), isTrue,
        reason: 'حين يفرغ الفلتر يملأ المحتوى الشاشة تماماً فلا يفيض، '
            'ولا تلتقط RefreshIndicator شيئاً');
  });
}
