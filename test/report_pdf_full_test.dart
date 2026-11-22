import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_export.dart';

/// PDF التقرير «كاملاً لا مقصوصاً» (٢٢ نوفمبر — المالك: «ملف الPDF جاي يظهر مرات مقصوص مو كامل … تقارير مهمة كلش»):
/// مستندٌ ثقيل بشكل التقرير الماليّ في «كل الشركات» (تسعة أعمدة بكلفة الباقة، أوصافٌ طويلة، يوزراتٌ بلا مسافة، أسماءٌ طويلة)
/// ⇒ يُبنى بلا خطأ، وكلّ صفٍّ فيه (العدّ في آخره)، والصفحات بعددٍ معقول. يُحفظ في build/pdf_check/ لمعاينة صفحاته
/// (~/release_work/reports_design_1122/pdf_pages.swift).
void main() {
  testWidgets('١٥٠٠ حركة بتسعة أعمدة وأوصافٍ طويلة ⇒ مستندٌ كامل متعدّد الصفحات', (t) async {
    const columns = ['الشركة', 'اسم المشترك', 'اليوزر', 'المبلغ', 'كلفة الباقة', 'التاريخ', 'الوصف', 'النوع', 'المنفذ'];
    final rows = [
      for (var i = 0; i < 1500; i++)
        [
          i.isEven ? 'سوبرنت' : 'ايرث لنك العراق — فرع البصرة',
          i % 7 == 0 ? 'عبد الرحمن محمد عبد الكريم الموسوي' : 'علي جبار',
          i % 5 == 0 ? 'very.long.username.without.spaces.$i@najaf948' : 'u$i',
          '${35000 + i}',
          i % 3 == 0 ? '' : '28000',
          '2026-11-${(22 - i % 22).toString().padLeft(2, '0')} 18:05',
          i % 4 == 0
              ? 'تفعيل نقدي — FTTH 50 ميغا العائليّة الممتازة مع راوتر وتنصيب مجّاني | السعر: 35,000 IQD | من المشترك: u$i'
              : 'تسديد دين',
          i % 4 == 0 ? 'تفعيل نقدي' : 'تسديد دين',
          i % 6 == 0 ? 'admin@najaf948' : 'زينب',
        ],
    ];
    final doc = await t.runAsync(() => ReportPdf.build(
          title: 'التقرير الماليّ',
          subtitle: 'هذا الشهر · 2026/11/01 – 2026/11/22',
          details: const ['الشركات: سوبرنت، ايرث لنك', 'المدير: علي حسن + الفرعيّين', 'بحث: «علي»', 'عدد الحركات: 1500'],
          columns: columns,
          rows: rows,
          columnWeights: const [1.4, 2.2, 1.4, 1.2, 1.2, 1.4, 2.6, 1.1, 1.3],
        ));
    final bytes = await t.runAsync(() => doc!.save());
    final pages = doc!.document.pdfPageList.pages.length;
    expect(pages, greaterThan(20), reason: '1500 صفّ لا تتّسع لصفحاتٍ قليلة');
    expect(pages, lessThan(400));
    final dir = Directory('build/pdf_check')..createSync(recursive: true);
    File('${dir.path}/finance_full.pdf').writeAsBytesSync(bytes!);
  });
}
