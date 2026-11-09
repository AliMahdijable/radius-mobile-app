import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/util/ip_input.dart';

/// حقل IP (المالك ٩ نوفمبر: «بالايفون امكان يضع بيها ايبي ماكو . دوت»): لوحةٌ عشريّة فيها فاصل، والفاصل والأرقام بلغة الجهاز ⇒ نقطة وأرقام لاتينيّة.
void main() {
  test('لوحة IP عشريّة (فيها فاصلٌ على الآيفون) لا لوحة أرقام الهاتف', () {
    expect(ipKeyboard, const TextInputType.numberWithOptions(decimal: true));
    expect(ipKeyboard == TextInputType.number, isFalse);
  });

  test('التحويل: ٫ ، , ⇒ نقطة، والأرقام العربيّة والفارسيّة ⇒ لاتينيّة، والباقي يسقط', () {
    expect(IpInputFormatter.normalize('192.168.1.1'), '192.168.1.1');
    expect(IpInputFormatter.normalize('١٩٢٫١٦٨٫١٫١'), '192.168.1.1');
    expect(IpInputFormatter.normalize('10,0،0.5'), '10.0.0.5');
    expect(IpInputFormatter.normalize('۱۰.۲.۳.۴'), '10.2.3.4');
    expect(IpInputFormatter.normalize(' 10.0.0.1 a/b-'), '10.0.0.1');
  });

  test('المحوِّل يُبقي المؤشّر بعد ما كُتب', () {
    const f = IpInputFormatter();
    final out = f.formatEditUpdate(
      const TextEditingValue(text: '192'),
      const TextEditingValue(text: '192٫', selection: TextSelection.collapsed(offset: 4)),
    );
    expect(out.text, '192.');
    expect(out.selection.baseOffset, 4);
    final same = f.formatEditUpdate(
      const TextEditingValue(text: '1'),
      const TextEditingValue(text: '10', selection: TextSelection.collapsed(offset: 2)),
    );
    expect(same.text, '10');
  });
}
