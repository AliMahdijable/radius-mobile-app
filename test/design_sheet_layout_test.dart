import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/theme/colors.dart';

/// اختبار تخطيط القوقعة المشتركة.
///
/// أربعة وعشرون مودلاً تبني عليها الآن، فأيّ خطأ تخطيط فيها يظهر في
/// التطبيق كلّه دفعةً واحدة. وثلاثة من أخطاء هذا العمل كانت تخطيطيّة
/// (صفّ يطلب ارتفاعاً لا نهائيّاً · جسم مقصوص · فيضان) — كلّها من نوع
/// لا يمسكه المحلّل ولا الاختبار المنطقي، بل الرسم الفعلي.
///
/// نرسم هنا على **شاشة قصيرة عمداً** (640×420) لأنّ الفيضان لا يظهر
/// على شاشة فسيحة.
void main() {
  setUp(() => AppColors.setDarkMode(false));

  Future<void> pumpSheet(WidgetTester t, Widget sheet,
      {Size size = const Size(360, 420)}) async {
    t.view.physicalSize = size * t.view.devicePixelRatio;
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = size;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: sheet)),
    ));
    await t.pump();
  }

  SheetHeaderBar header() => SheetHeaderBar(
        icon: Icons.info_outline_rounded,
        title: 'عنوان الشيت',
        subtitle: 'سطر فرعي',
        onClose: () {},
      );

  testWidgets('جسم قصير — لا فيضان ولا استثناء', (t) async {
    await pumpSheet(
      t,
      DesignSheet(
        header: header(),
        body: const Text('محتوى قصير'),
      ),
    );
    expect(tester_exception(t), isNull);
    expect(find.text('عنوان الشيت'), findsOneWidget);
  });

  testWidgets('جسم أطول من الشاشة — يُمرَّر ولا يفيض', (t) async {
    await pumpSheet(
      t,
      DesignSheet(
        header: header(),
        body: Column(
          children: [
            for (var i = 0; i < 40; i++)
              SizedBox(height: 40, child: Text('سطر $i')),
          ],
        ),
      ),
    );
    expect(tester_exception(t), isNull);
  });

  testWidgets('مع شريط سفلي — الزرّ يبقى مرئيّاً فوق جسم طويل', (t) async {
    await pumpSheet(
      t,
      DesignSheet(
        header: header(),
        footer: SheetFooterBar(
          label: 'تنفيذ',
          icon: Icons.check_rounded,
          onPressed: () {},
        ),
        body: Column(
          children: [
            for (var i = 0; i < 40; i++)
              SizedBox(height: 40, child: Text('سطر $i')),
          ],
        ),
      ),
    );
    expect(tester_exception(t), isNull);
    // الزرّ جزء من الشلّ لا من الجسم — يبقى مرسوماً مهما طال المحتوى.
    expect(find.text('تنفيذ'), findsOneWidget);
  });

  testWidgets('scrollable:false مع Expanded — النمط الذي تستعمله 11 شاشة',
      (t) async {
    await pumpSheet(
      t,
      DesignSheet(
        header: header(),
        scrollable: false,
        bodyPadding: EdgeInsets.zero,
        body: Column(
          children: [
            const SizedBox(height: 44, child: Text('شريط ثابت')),
            Expanded(
              child: ListView(
                children: [
                  for (var i = 0; i < 40; i++)
                    SizedBox(height: 40, child: Text('صفّ $i')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    expect(tester_exception(t), isNull);
    expect(find.text('شريط ثابت'), findsOneWidget);
  });

  testWidgets('الشريط السفلي بزرّ جانبي وصفّ علوي', (t) async {
    await pumpSheet(
      t,
      DesignSheet(
        header: header(),
        footer: SheetFooterBar(
          label: 'حفظ',
          icon: Icons.save_rounded,
          onPressed: () {},
          leading: SheetFooterIconButton(
            icon: Icons.delete_outline_rounded,
            color: AppColors.error,
            onTap: () {},
          ),
          above: const SizedBox(height: 24, child: Text('خانة إضافيّة')),
        ),
        body: const Text('محتوى'),
      ),
    );
    expect(tester_exception(t), isNull);
    expect(find.text('خانة إضافيّة'), findsOneWidget);
    expect(find.text('حفظ'), findsOneWidget);
  });

  testWidgets('عنوان طويل جدّاً لا يفيض أفقيّاً', (t) async {
    await pumpSheet(
      t,
      DesignSheet(
        header: SheetHeaderBar(
          icon: Icons.info_outline_rounded,
          title: 'عنوان طويل جدّاً جدّاً يتجاوز عرض الشاشة بكثير ولا ينبغي أن يفيض',
          subtitle: 'وسطر فرعي طويل كذلك يتجاوز العرض المتاح بمسافة كبيرة',
          onClose: () {},
        ),
        body: const Text('محتوى'),
      ),
    );
    expect(tester_exception(t), isNull);
  });

  testWidgets('يعمل في الوضع الليلي كما في النهاري', (t) async {
    AppColors.setDarkMode(true);
    addTearDown(() => AppColors.setDarkMode(false));
    await pumpSheet(
      t,
      DesignSheet(
        header: header(),
        footer: SheetFooterBar(
          label: 'تنفيذ',
          icon: Icons.check_rounded,
          onPressed: () {},
        ),
        body: const Text('محتوى ليلي'),
      ),
    );
    expect(tester_exception(t), isNull);
    expect(find.text('محتوى ليلي'), findsOneWidget);
  });
}

/// يلتقط أوّل استثناء رسم إن وقع — `takeException` تُفرّغ الطابور.
Object? tester_exception(WidgetTester t) => t.takeException();
