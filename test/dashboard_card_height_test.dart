import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/dashboard.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/subscribers_card.dart';
import 'package:rad_mysvcs/theme/colors.dart';

/// ارتفاع بطاقة المشتركين مقابل هيكلها.
///
/// الهيكل يُرسم ريثما تصل البيانات، فإن اختلف ارتفاعه عن ارتفاع البطاقة
/// قفزت الشاشة كلّها تحته لحظة الوصول. كان الفرق 63px والتعليق فوق
/// الهيكل يزعم أنّه «مطابق» — أي أنّه انحرف بعد كتابته ولم يلاحظه أحد،
/// وهو ما سيتكرّر مع أيّ تعديل لاحق على البطاقة ما لم يُقَس.
void main() {
  const stats = SubscribersStats(
    total: 340,
    active: 254,
    online: 258,
    offline: 79,
    expired: 86,
    nearExpiry: 36,
    onlineNoPlan: 9,
    disabled: 16,
  );

  testWidgets('الهيكل بارتفاع البطاقة — لا قفزة عند وصول البيانات',
      (t) async {
    AppColors.setDarkMode(false);
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 360,
            child: SubscribersCard(stats: stats),
          ),
        ),
      ),
    ));
    await t.pump();
    final filled = t.getSize(find.byType(SubscribersCard)).height;

    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 360,
            child: SubscribersCard(stats: null),
          ),
        ),
      ),
    ));
    await t.pump();
    final skeleton = t.getSize(find.byType(SubscribersCard)).height;

    // ⚠️ المدى لا الرقم: حبّات الحالة تلتفّ بحسب عرض الشاشة وطول
    // التسميات (والاختبار يعمل بلا ترجمة محمَّلة فيرى المفاتيح
    // الإنجليزيّة الطويلة، وهي أعرض من العربيّة الفعليّة). فسطر واحد
    // أو سطران — والهيكل يُضبط على الحالة الشائعة.
    //
    // ما يحرسه الاختبار هو ألّا ينفلت الفرق: 63px كانت القفزة التي
    // وُلد منها، وأيّ تجاوز لسطر حبّات كامل يعني انحرافاً بنيويّاً.
    expect((filled - skeleton).abs(), lessThanOrEqualTo(56.0),
        reason: 'الهيكل $skeleton مقابل البطاقة $filled — '
            'الفرق يقفز الشاشة لحظة وصول البيانات');
  });

  testWidgets('الحلقة تُرسم حين لا مشترك نشط إطلاقاً', (t) async {
    // كان الرسّام يخرج مبكّراً عند activeRatio == 0 فتظهر حلقة رماديّة
    // فارغة — أسوأ حالة ممكنة تُرسم كأنّها لا شيء.
    AppColors.setDarkMode(false);
    const allExpired = SubscribersStats(
      total: 50, active: 0, online: 0, offline: 0,
      expired: 50, nearExpiry: 0, onlineNoPlan: 0, disabled: 0,
    );
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 360,
            child: SubscribersCard(stats: allExpired),
          ),
        ),
      ),
    ));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('50'), findsWidgets);
  });

  testWidgets('إجمالي أصغر من مجموع الأجزاء لا يلفّ القوس', (t) async {
    // `total` من SAS4 بينما active/expired محلّيّان — فقد يتناقضان.
    AppColors.setDarkMode(false);
    const skewed = SubscribersStats(
      total: 10, active: 90, online: 5, offline: 5,
      expired: 40, nearExpiry: 1, onlineNoPlan: 0, disabled: 2,
    );
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 360, child: SubscribersCard(stats: skewed)),
        ),
      ),
    ));
    await t.pump();
    expect(t.takeException(), isNull);
  });
}
