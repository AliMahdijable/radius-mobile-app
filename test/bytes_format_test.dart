import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/util/bytes_format.dart';
import 'package:rad_mysvcs/screens/national/national_more_widgets.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/consumption_sheet.dart';
import 'package:rad_mysvcs/services/subscriber_usage_store.dart';

/// المالك (٢٣ نوفمبر): «اجمالي السحوبات سوي بوحدات التيرا وفما فوق حسب العدد» — الوحدة تكبر وحدها حتى PB بدالّةٍ واحدة.
void main() {
  const kb = 1024, mb = kb * 1024, gb = mb * 1024, tb = gb * 1024, pb = tb * 1024;

  test('scaleBytes: الوحدة الكبرى التي يبقى فيها الرقم ≥ ١ — حتى PB', () {
    expect(scaleBytes(900).unit, 'B');
    expect(scaleBytes(1023).unit, 'B');
    expect(scaleBytes(kb).unit, 'KB');
    expect(scaleBytes(mb).unit, 'MB');
    expect(scaleBytes(gb - 1).unit, 'MB');
    expect(scaleBytes(gb).unit, 'GB');
    expect(scaleBytes(tb).unit, 'TB');
    expect(scaleBytes(pb).unit, 'PB');
    expect(scaleBytes(5000 * pb).unit, 'PB', reason: 'لا وحدة بعدها');
    expect(scaleBytes(3 * tb).value, 3);
  });

  test('formatBytes (المجاميع): «9022.83 GB» صارت «8.81 TB»، و«712.88 GB» تبقى، والتقريب إلى ١٠٢٤ يرتقي', () {
    expect(formatBytes(9022.83 * gb), '8.81 TB');
    expect(formatBytes(712.88 * gb), '712.88 GB');
    expect(formatBytes(900), '900 B');
    expect(formatBytes(1.5 * kb), '1.5 KB');
    expect(formatBytes(6 * mb), '6.0 MB');
    expect(formatBytes(2.5 * pb), '2.50 PB');
    expect(formatBytes(1023.999 * gb), '1.00 TB', reason: 'لا «1024.00 GB»');
    expect(formatBytes(1023.99 * mb), '1.00 GB');
    expect(formatBytes(0), '0 B');
    expect(formatBytes(double.nan), '—');
  });

  test('المنسّقات الأخرى بالوحدة الموحّدة وشكلها نفسه — الاستهلاك والوطني وقائمة الاستهلاك', () {
    expect(fmtBytes(660 * gb), '660 GB', reason: 'كما كانت تحت التيرا');
    expect(fmtBytes(12 * tb), '12 TB');
    expect(fmtBytes(1536 * gb), '1.5 TB');
    expect(unitForTest(2 * tb).name, 'TB');
    expect(unitForTest(3 * pb).name, 'PB');
    expect(nationalBytes(5 * tb), '5.0 TB');
    expect(nationalBytes(50 * gb), '50 GB');
    expect(formatUsageBytes(2 * tb), '2.00 TB');
    expect(formatUsageBytes(3 * pb), '3.00 PB');
  });
}
