// «يخفي» (٢٦ نوفمبر — المالك عن «السعر: 0» برسائل الوطني): الرسالة التي يركّبها التطبيق للمشترك (WhatsAppApi.renderForSubscriber —
// «معلومات المشترك»، «تذكير الدين»، «تنبيه المشترك»…) حين لا يُعرف سعر الباقة (لا سعر على الصفّ، أو صفر) تحذف سطر السعر كلّه بدل
// «السعر: 0»، كسطر {password} المتعذّرة. والسعر المعروف كما كان حرفاً.
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/whatsapp/template_defaults.dart';

Subscriber _sub({double? price, double? discount, String? notes}) => Subscriber(
      username: 'u1@x',
      firstname: 'علي',
      lastname: 'حسن',
      profileName: 'Basic',
      price: price,
      discount: discount,
      notes: notes,
    );

const _info = '📋 معلومات اشتراكك\n\nمرحباً {subscriber_name} 👋\n\n👤 اسم المستخدم: {username}\n📦 الباقة: {package_name}\n'
    '💰 السعر: {package_price}\n📅 تاريخ الانتهاء: {expiry_date}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('سعرٌ معروف ⇒ السطر بالسعر كما كان حرفاً', () {
    final out = WhatsAppApi.renderForSubscriber(_info, _sub(price: 35000));
    expect(out, contains('💰 السعر: 35,000'));
    expect(out, contains('📦 الباقة: Basic'));
  });

  test('بلا سعر (null) أو صفر ⇒ سطر السعر يختفي وبقيّة الرسالة كما هي، بلا «0»', () {
    for (final p in <double?>[null, 0]) {
      final out = WhatsAppApi.renderForSubscriber(_info, _sub(price: p));
      expect(out, isNot(contains('السعر')), reason: 'price=$p');
      expect(out, isNot(contains('{package_price}')));
      expect(out, contains('👤 اسم المستخدم: u1@x'));
      expect(out, contains('📦 الباقة: Basic\n📅 تاريخ الانتهاء:'), reason: 'السطران متجاوران بلا فراغ');
      expect(out, startsWith('📋 معلومات اشتراكك\n\nمرحباً علي حسن 👋'));
    }
  });

  test('{discounted_price} يختفي معه، و{discount_amount} وما سواه لا يُمسّ', () {
    const tpl = 'الباقة: {package_name}\nبعد الخصم: {discounted_price}\nالخصم: {discount_amount}\nالدين: {debt_amount}';
    final out = WhatsAppApi.renderForSubscriber(tpl, _sub(notes: '-5000'));
    expect(out, 'الباقة: Basic\nالخصم: 0\nالدين: 5,000');
    final known = WhatsAppApi.renderForSubscriber(tpl, _sub(price: 30000, discount: 5000, notes: '-5000'));
    expect(known, 'الباقة: Basic\nبعد الخصم: 30,000\nالخصم: 5,000\nالدين: 5,000');
  });

  test('القوالب الافتراضيّة الثلاثة بالسعر: لا «0» ولا سطرٌ فارغٌ مزدوج حين لا سعر', () {
    for (final type in ['welcome_message', 'activation_notice', 'debt_reminder']) {
      final tpl = TemplateDefaults.forType(type)!;
      expect(tpl, contains('{package_price}'), reason: type);
      final out = WhatsAppApi.renderForSubscriber(tpl, _sub(notes: '-35000'));
      expect(out, isNot(contains('{package_price}')), reason: type);
      expect(RegExp(r'💰 (?:السعر|سعر الباقة): ?0?\s*$', multiLine: true).hasMatch(out), isFalse, reason: type);
      expect(out.contains('\n\n\n'), isFalse, reason: type);
      final known = WhatsAppApi.renderForSubscriber(tpl, _sub(price: 35000, notes: '-35000'));
      expect(known, contains('35,000'), reason: type);
    }
  });

  test('dropPriceLines: نصٌّ بلا السعر لا يُمسّ، والسطر وحده لا يُفرغ الرسالة', () {
    expect(WhatsAppApi.dropPriceLines('مرحباً {firstname}\n\nشكراً'), 'مرحباً {firstname}\n\nشكراً');
    expect(WhatsAppApi.dropPriceLines('السعر: {package_price}'), 'السعر: {package_price}');
    expect(WhatsAppApi.renderForSubscriber('السعر: {package_price}', _sub()), 'السعر: ');
    expect(WhatsAppApi.dropPriceLines('أ\n\nالسعر: {package_price}\n\nب'), 'أ\n\nب');
  });
}
