import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/reports/widgets/action_labels.dart';

// مزامنة الساس: التفعيل المسحوب من الساس يُسمّى بمصدره، وتفعيلات التطبيق كما هي.
void main() {
  test('تفعيلٌ مُزامَن من الساس', () {
    expect(arabicActionLabel('SUBSCRIBER_ACTIVATE', 'تفعيل من الساس — بكارت'), 'تفعيل (من الساس)');
    expect(arabicActionLabel('SUBSCRIBER_ACTIVATE', 'تفعيل من الساس — بالرصيد (أُلغي)'), 'تفعيل (من الساس)');
  });

  test('تفعيلات التطبيق لا تتغيّر', () {
    expect(arabicActionLabel('SUBSCRIBER_ACTIVATE', 'تفعيل نقدي - المستخدم: a | السعر: 35,000 د.ع'), 'تفعيل');
    expect(arabicActionLabel('SUBSCRIBER_ACTIVATE', 'تفعيل غير نقدي - المستخدم: a'), 'تفعيل (غير نقدي)');
  });
}
