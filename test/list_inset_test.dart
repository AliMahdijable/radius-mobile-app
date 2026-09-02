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
    //
    // ⚠️ الفحص على **النصّ كلّه بعد طيّ المسافات**، لا سطراً سطراً:
    // النسخة الأولى فحصت كلّ سطر وحده ففاتها استدعاءٌ ملفوف —
    //     padding: const EdgeInsets.fromLTRB(
    //         Sp.md, 0, Sp.md, 90),
    // وبقي في وضع التحديد حتّى بلّغ عنه المستخدم مرّةً ثانية
    // (٢٠٢٦-٠٩-٠٢). حارسٌ يفوته ما وُضع لأجله أسوأ من غيابه.
    final offenders = <String>[];
    for (final f in Directory('lib/screens/network_devices')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      // نُزيل التعليقات ثمّ نطوي كلّ فراغ إلى مسافةٍ واحدة.
      final body = f
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ');
      for (final m
          in RegExp(r'fromLTRB\([^)]*,\s*(\d{2,3})\s*\)').allMatches(body)) {
        // الحدّ ٤٠: أرقام كـ8 و10 و12 حشوٌ بصريّ مشروع. وما تجاوزه في
        // الخانة السفليّة لا يكون إلّا محاولةَ خلوصٍ لشريطٍ أو مؤشّر —
        // وتلك تُحسب لا تُكتب.
        if (int.parse(m[1]!) >= 40) {
          offenders.add('${f.path.split('/').last}: ${m[0]}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'حشوٌ ثابت لا يحسب المنطقة الآمنة:\n${offenders.join('\n')}');
  });
}
