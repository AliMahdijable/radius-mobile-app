import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/theme/spacing.dart';

/// حشو أسفل القوائم — بلاغ ٢٠٢٦-٠٩-٠٢: آخر بطاقة يبتلعها الشريط
/// السفليّ ولا يمكن التمرير إليها.
void main() {
  Future<double> measure(
    WidgetTester t,
    double Function(BuildContext) fn, {
    double safeBottom = 0,
  }) async {
    late double v;
    await t.pumpWidget(MediaQuery(
      data: MediaQueryData(padding: EdgeInsets.only(bottom: safeBottom)),
      child: Builder(builder: (c) {
        v = fn(c);
        return const SizedBox();
      }),
    ));
    return v;
  }

  testWidgets('🚨 المنطقة الآمنة تُضاف — لا رقم ثابت', (t) async {
    // الشريط السفليّ ملفوفٌ بـSafeArea، فيزيد ارتفاعه بمقدار مؤشّر
    // الشاشة. قائمةٌ تبدو كاملةً على أندرويد تُقتطع على آيفون.
    final android = await measure(t, Inset.tabBar);
    final iphone = await measure(t, Inset.tabBar, safeBottom: 34);
    expect(iphone - android, 34,
        reason: 'الحشو لا يتبع مؤشّر الشاشة — البطاقة الأخيرة تُقتطع');
  });

  testWidgets('حشو التبويب أكبر من حشو المسار المدفوع', (t) async {
    // المسار المدفوع بلا شريط سفليّ، فلا يحتاج ارتفاعه.
    final tab = await measure(t, Inset.tabBar, safeBottom: 34);
    final route = await measure(t, Inset.route, safeBottom: 34);
    expect(tab, greaterThan(route));
    expect(route, greaterThan(34), reason: 'ويظلّ يتجاوز المؤشّر نفسه');
  });

  testWidgets('يطابق ما تستعمله شاشة المشتركين', (t) async {
    // نفس التعبير الذي يعمل هناك منذ شهور — لا رقم مخترع.
    final v = await measure(t, Inset.tabBar, safeBottom: 34);
    expect(v, Sp.huge * 3 + 34);
  });

  test('🚨 لا رقم سائب باقٍ في شاشات الأجهزة', () {
    // كلّ شاشات القسم كانت تكتب 90 ثابتة — وهو ما أنتج البلاغ.
    final offenders = <String>[];
    for (final f in Directory('lib/screens/network_devices')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final line in f.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        // ⚠️ الحدّ ٤٠: أرقام كـ8 و10 و12 حشوٌ بصريّ مشروع. وما تجاوز
        // ٤٠ في الخانة السفليّة لا يكون إلّا محاولةَ خلوصٍ لشريطٍ أو
        // مؤشّر — وتلك يجب أن تُحسب لا تُكتب.
        final m = RegExp(r'fromLTRB\([^)]*,\s*(\d{2,3})\s*\)').firstMatch(line);
        if (m != null && int.parse(m[1]!) >= 40) {
          offenders.add('${f.path.split('/').last}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'حشوٌ ثابت لا يحسب المنطقة الآمنة:\n${offenders.join('\n')}');
  });
}
