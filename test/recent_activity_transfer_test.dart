import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/recent_activities.dart';
import 'package:rad_mysvcs/theme/typography.dart';

import 'support/app_fonts.dart';

/// «آخر النشاطات» — نقل مشترك ايرث لنك لمديرٍ فرعيّ (٢٨ أكتوبر، بلاغ المالك: «جاي تظهر اضافة وليس تعديل معلومات،
/// ووصف الحركه بنقل الى مدير ثاني»). الخادم يسجّلها SUBSCRIBER_EDIT بوصف «نقل إلى مدير ثاني: X (كان لدى Y)».
void main() {
  setUpAll(loadAppFonts);

  Future<void> pump(WidgetTester tester, Map<String, dynamic> row) => tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: AppType.family),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SizedBox(height: 300, child: RecentActivities(items: [row]))),
        ),
      ));

  testWidgets('النقل: «تعديل معلومات» ووصفه «نقل إلى مدير ثاني: …» — لا «إضافة مشترك»', (tester) async {
    await pump(tester, {
      'action_type': 'SUBSCRIBER_EDIT',
      'action_description': 'نقل إلى مدير ثاني: Lqmus842 (كان لدى Lqmus1212)',
      'target_name': 'asuios@waleed',
      'admin_username': 'admin@Lqmus625',
      'created_at': '2026-10-28T09:00:00Z',
    });
    expect(find.text('تعديل معلومات'), findsOneWidget);
    expect(find.textContaining('نقل إلى مدير ثاني: Lqmus842'), findsOneWidget);
    expect(find.text('إضافة مشترك'), findsNothing);
  });

  testWidgets('تعديلٌ عاديّ يبقى «تعديل مشترك»', (tester) async {
    await pump(tester, {
      'action_type': 'SUBSCRIBER_EDIT',
      'action_description': 'تعديل بيانات المشترك',
      'target_name': 'x@y',
      'created_at': '2026-10-28T09:00:00Z',
    });
    expect(find.text('تعديل مشترك'), findsOneWidget);
    expect(find.textContaining('نقل إلى مدير'), findsNothing);
  });
}
