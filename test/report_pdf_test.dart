import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rad_mysvcs/screens/reports/widgets/report_export.dart';
import 'package:rad_mysvcs/services/phone_output.dart';

/// PDF التقارير (٨ نوفمبر — المالك مع صورة «التقرير المالي»: «هذا ال pdf بي مشكله بالتنسيق الحروف والكتابات… فقط اصلحها»
/// و«التقرير المالي اني ماردتك تسوي صورة… امسحها»):
///   ١. كلّ خليّةٍ باتّجاه نصّها — العربيّ يُشكَّل ويُرتَّب مرّةً ويُرسم LTR (اتّجاه RTL في مكتبة pdf يضيّع المسافة بعد «ر»
///      و«د»: «عددالصفوف»، «غيرنقدي»)، والتاريخ واليوزر LTR كما هما.
///   ٢. «45000.0» ⇒ «45,000» بأعمدة المال، والهاتف لا يُمسّ.
///   ٣. A4 أفقيّ من ستّة أعمدة — «admin@poox» و«تسديد دين» لا يُقطعان حرفاً حرفاً.
///   ٤. لا زرّ «صورة» في شريط التقرير — Excel وPDF وحدهما.
void main() {
  test('١ اتّجاه الخليّة من نصّها', () {
    expect(ReportPdf.directionOf('تسديد دين'), pw.TextDirection.rtl);
    expect(ReportPdf.directionOf('تسديد دين 45000 د.ع للمشترك a1@ze'), pw.TextDirection.rtl);
    expect(ReportPdf.directionOf('2026-11-05 22:47'), pw.TextDirection.ltr);
    expect(ReportPdf.directionOf('a1@ze'), pw.TextDirection.ltr);
    expect(ReportPdf.directionOf('admin@poox'), pw.TextDirection.ltr);
  });

  test('١ب العربيّ بترتيبه المرئيّ مشكَّلاً — المسافات كما هي', () {
    final v = ReportPdf.visual('عدد الصفوف: 3');
    expect(v.split(' '), hasLength(3), reason: 'ثلاث كلماتٍ بمسافتين — لا مسافةٌ تضيع ولا تتضاعف');
    expect(v.startsWith('3 '), isTrue, reason: 'الرقم آخر الجملة ⇒ أقصى اليسار');
    final word = ReportPdf.visual('تسديد');
    expect(word.runes.every((r) => r >= 0xFE70 && r <= 0xFEFF), isTrue, reason: 'أشكال الحروف المتّصلة لا المنفصلة');
    expect(ReportPdf.visual('تفعيل غير نقدي').split(' '), hasLength(3));
  });

  test('٢ الأرقام: فواصل الآلاف بعمود المال وحده، وبلا «.0»', () {
    expect(ReportPdf.moneyColumn('المبلغ'), isTrue);
    expect(ReportPdf.moneyColumn('كلفة الباقة'), isTrue);
    expect(ReportPdf.moneyColumn('الهاتف'), isFalse);
    expect(ReportPdf.moneyColumn('اليوزر'), isFalse);
    expect(ReportPdf.cellText('45000.0', money: true), '45,000');
    expect(ReportPdf.cellText('120000', money: true), '120,000');
    expect(ReportPdf.cellText('-5000', money: true), '-5,000');
    expect(ReportPdf.cellText('750', money: true), '750');
    expect(ReportPdf.cellText('12.5', money: true), '12.5');
    expect(ReportPdf.cellText('45000.0'), '45000', reason: '«.0» يُحذف في كلّ عمود');
    expect(ReportPdf.cellText('07701234567'), '07701234567', reason: 'الهاتف ليس مالاً');
    expect(ReportPdf.cellText(''), '');
  });

  test('٣ أفقيّ من ستّة أعمدة', () {
    final wide = ReportPdf.formatFor(7);
    expect(wide.width, greaterThan(wide.height));
    final tall = ReportPdf.formatFor(5);
    expect(tall.width, lessThan(tall.height));
  });

  testWidgets('٣ب المستند يُبنى (خطّ التطبيق المضمَّن) — صفحةٌ واحدة لصفّين', (t) async {
    final bytes = await t.runAsync(() async {
      final doc = await ReportPdf.build(
        title: 'التقرير المالي',
        subtitle: '2026-11-01 → 2026-11-08',
        columns: const ['اسم المشترك', 'اليوزر', 'المبلغ', 'التاريخ', 'الوصف', 'النوع', 'المنفذ'],
        rows: const [
          ['أحمد', 'a1@ze', '45000.0', '2026-11-05 22:47', 'تسديد دين 45000 د.ع للمشترك a1@ze', 'تسديد دين', 'admin@poox'],
          ['', '', '120000', '2026-11-02 03:00', 'مصروف: إيجار (تشرين الثاني 2026)', 'مصروف', 'admin@poox'],
        ],
        columnWeights: const [2.2, 1.4, 1.2, 1.4, 2.6, 1.1, 1.3],
      );
      return doc.save();
    });
    expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
  });

  testWidgets('٤ لا زرّ «صورة» في شريط التقرير ولو بالهاتف', (t) async {
    PhoneOutput.debugActive = true;
    addTearDown(() => PhoneOutput.debugActive = null);
    await t.pumpWidget(const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: ReportExportBar(title: 'التقرير المالي', columns: ['المبلغ'], rows: [['15000']]),
          ),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('report-share-image')), findsNothing);
    expect(find.byType(Tooltip), findsNWidgets(2), reason: 'Excel وPDF وحدهما');
  });
}
