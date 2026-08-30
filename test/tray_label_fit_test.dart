import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/dashboard.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/subscribers_card.dart';
import 'package:rad_mysvcs/theme/colors.dart';
import 'package:rad_mysvcs/theme/typography.dart';

/// تسميات درج الاستثناءات لا تُقصّ في أيّ عرض ولا في أيّ لغة.
///
/// شكوى متكرّرة من المستخدم («مقصوص من الاطراف»)، وسببها البنيويّ أنّ
/// الحالات الثلاث كانت بلاطات تتقاسم العرض أثلاثاً: بعد حسم الحشوات
/// والأيقونة والرقم يبقى للتسمية 36.5dp على شاشة 393 بينما «قربوا
/// الانتهاء» تقيس 53.7 و«Expiring soon» تقيس 72.1. الدرج أعطاها العرض
/// الكامل.
///
/// ⚠️ هذا الاختبار **لا** يقرأ `didExceedMaxLines` من الشجرة، وهي
/// الطريقة البديهيّة. سببان:
///   1. `easy_localization` غير مُهيَّأ هنا، فـ`.tr()` تُرجع المفتاح
///      («dashboard.online_no_plan») لا التسمية.
///   2. خطّ الاختبار الافتراضيّ يرسم كلّ محرف مربّعاً بعرض القياس
///      كاملاً، فالمفتاح ذو الـ24 محرفاً يقيس 276dp بدل 141.6.
/// فالنتيجة قصٌّ وهميّ لا علاقة له بالمنتَج.
///
/// فنجمع بدلها الحقيقتين: **الميزانيّة** تُقاس من الشجرة الفعليّة
/// (قيد العرض الذي يصل نصّ الدرج)، و**عرض النصّ** يُقاس بالخطّ
/// المُجمَّع نفسه الذي يشحن مع التطبيق. أيّ تضييق مستقبليّ للدرج
/// يُسقط هذا الاختبار حتّى لو ظلّت المفاتيح تمرّ.
Future<void> _loadRealFont() async {
  final loader = FontLoader(AppType.family);
  for (final weight in [400, 500, 600, 700]) {
    loader.addFont(File('assets/fonts/${AppType.family}-$weight.ttf')
        .readAsBytes()
        .then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
  }
  await loader.load();
}

double _measure(String text, TextStyle style, TextDirection dir) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: dir,
  )..layout();
  return painter.width;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // مرّة واحدة: `FontLoader.load` داخل `testWidgets` يعلّق حلقة الاختبار
  // لأنّها تنتظر عملاً غير متزامن خارج ساعة الاختبار الوهميّة.
  setUpAll(_loadRealFont);

  // أطول تسمية في كلّ لغة — من assets/translations/{ar,en}.json.
  const labels = <String, TextDirection>{
    'قربوا الانتهاء': TextDirection.rtl,
    'غير مفعّل': TextDirection.rtl,
    'بدون نت': TextDirection.rtl,
    'Expiring soon': TextDirection.ltr,
    'Disabled': TextDirection.ltr,
    'No plan': TextDirection.ltr,
  };

  const stats = SubscribersStats(
    total: 340,
    active: 254,
    online: 258,
    // أرقام من أربع خانات عمداً: الرقم يزاحم التسمية على العرض نفسه،
    // فالحكم يجب أن يُقاس على أعرض رقم واقعيّ لا على 9.
    offline: 79,
    expired: 86,
    nearExpiry: 3600,
    onlineNoPlan: 9999,
    disabled: 1600,
  );

  for (final width in [360.0, 393.0, 430.0]) {
    testWidgets('تسميات الدرج تتّسع بلا قصّ — عرض $width', (t) async {
      AppColors.setDarkMode(false);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: const SubscribersCard(stats: stats),
            ),
          ),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull);

      // الميزانيّة الحقيقيّة: قيد العرض الذي يصل نصّ الدرج بعد كلّ
      // الحشوات والحدود والرقاقة والرقم.
      const trayKeys = {
        'dashboard.near_expiry',
        'dashboard.disabled',
        'dashboard.online_no_plan',
      };
      final trayParagraphs = t
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .where((p) => trayKeys.contains(p.text.toPlainText()))
          .toList();
      expect(trayParagraphs, hasLength(3),
          reason: 'لم تُعثر صفوف الدرج الثلاثة عند عرض $width');

      final budget = trayParagraphs
          .map((p) => p.constraints.maxWidth)
          .reduce((a, b) => a < b ? a : b);
      expect(budget, greaterThan(0));

      final style = AppType.label(color: AppColors.textMid);
      labels.forEach((label, dir) {
        final measured = _measure(label, style, dir);
        expect(measured, lessThanOrEqualTo(budget),
            reason: '«$label» تقيس ${measured.toStringAsFixed(1)}dp '
                'والميزانيّة ${budget.toStringAsFixed(1)}dp عند عرض $width');
      });
    });
  }
}
