import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';

/// الرقم بإشارته في الإطار الموحّد (٢٢ نوفمبر): formatIQD يأخذ القيمة المطلقة، فكان صافي ربحٍ بالخسارة (−50,000) يظهر «50,000 د.ع»
/// بلونٍ أحمر وحده — رقمٌ كاذب. السالب معزولٌ (FSI…PDI) فلا يقفز «−» يمين الرقم في السطر العربيّ.
void main() {
  const fsi = '\u2068', pdi = '\u2069';

  test('rpNum/rpMoney: الموجب كما كان، والسالب بـ«−» معزولاً', () {
    expect(rpNum(1234567), '1,234,567');
    expect(rpNum(0), '0');
    expect(rpNum(-50000), '$fsi−50,000$pdi');
    expect(rpMoney(65000), '65,000 د.ع');
    expect(rpMoney(-50000), '$fsi−50,000$pdi د.ع');
  });

  test('بطاقة الرقم تحمل الإشارة', () {
    const k = RpKpi(label: 'الصافي', value: -12500, icon: LucideIcons.trendingDown, tone: RpTone.loss);
    expect(k.text, '$fsi−12,500$pdi د.ع');
    const c = RpKpi(label: 'تفعيل', value: 12, icon: LucideIcons.zap, tone: RpTone.info, isCount: true, unit: 'تفعيل');
    expect(c.text, '12 تفعيل');
  });

  testWidgets('جدول «حسب الشركة»: ربحٌ بالخسارة ومجموعه بإشارتهما', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: RpCompanyTable(
              heads: ['الواصل', 'الدين', 'الربح'],
              lines: [
                RpCompanyLine(company: RpCompany(key: 'a', name: 'أ', colorIndex: 0), a: 100000, b: 0, c: -20000),
              ],
              total: [100000, 0, -20000],
            ),
          ),
        ),
      ),
    ));
    expect(find.text('$fsi−20,000$pdi'), findsNWidgets(2), reason: 'سطر الشركة والمجموع');
    expect(t.takeException(), isNull);
  });
}
