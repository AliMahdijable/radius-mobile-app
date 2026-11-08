import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_export.dart';

// مؤقّت: PDF التقرير المالي إلى ملفّ لأراه صورةً (لا يُحفظ في المستودع).
void main() {
  testWidgets('report pdf to file', (t) async {
    await t.runAsync(() async {
      final doc = await ReportPdf.build(
        title: 'التقرير المالي',
        subtitle: '2026-11-01 → 2026-11-08',
        columns: const ['اسم المشترك', 'اليوزر', 'المبلغ', 'التاريخ', 'الوصف', 'النوع', 'المنفذ'],
        rows: const [
          ['أحمد', 'a1@ze', '45000.0', '2026-11-05 22:47', 'تسديد دين 45000 د.ع للمشترك a1@ze', 'تسديد دين', 'admin@poox'],
          ['', '', '120000', '2026-11-02 03:00', 'مصروف: إيجار (تشرين الثاني 2026)', 'مصروف', 'admin@poox'],
          ['زينب علي حسين', 'zainab.a', '35000', '2026-11-01 10:15', 'تفعيل غير نقدي — السعر 35000 د.ع (باقة 35 ميكا)', 'تفعيل', 'موظف: كرار'],
        ],
        columnWeights: const [2.2, 1.4, 1.2, 1.4, 2.6, 1.1, 1.3],
      );
      File(Platform.environment['PDF_OUT'] ?? '/tmp/report.pdf').writeAsBytesSync(await doc.save());
    });
  });
}
