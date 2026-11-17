// {subscriber_name} = الاسم العربيّ وإلّا اليوزر (١٧ نوفمبر — المالك: «يظهر يوزر ميظهر الاسم العربي… ابد به ع ان يخضع لكل
// الشركات»). الرسائل التي يرسلها الوكيل بيده من التطبيق تُملأ هنا (WhatsAppApi.renderForSubscriber) — كالخادم
// templateHelper.subscriberDisplayName: الاسم من firstname + lastname (لكلّ الشركات: الساس، ايرث لنك، الوطنيّ، نبض، كلاود ساس،
// يوزر مانجر «التعليق»، اكس راديوس، AccessGate، فايبر اكس — كلٌّ يضع اسم الشخص في firstname/lastname واليوزر في username).
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';

Subscriber _sub({String username = 'na@abrahem111', String firstname = '', String lastname = ''}) =>
    Subscriber(username: username, firstname: firstname, lastname: lastname);

String _r(String tpl, Subscriber s) => WhatsAppApi.renderForSubscriber(tpl, s);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('«عزيزي {subscriber_name}» بالاسم العربيّ — الأوّل + الأخير', () {
    expect(_r('عزيزي {subscriber_name}', _sub(firstname: 'إبراهيم', lastname: 'علي')), 'عزيزي إبراهيم علي');
    expect(_r('عزيزي {subscriber_name}', _sub(firstname: 'إبراهيم')), 'عزيزي إبراهيم');
  });

  test('بلا اسمٍ في لوحة الشركة ⇒ اليوزر (كما كان)', () {
    expect(_r('عزيزي {subscriber_name}', _sub()), 'عزيزي na@abrahem111');
    expect(_r('عزيزي {subscriber_name}', _sub(firstname: '  ', lastname: '')), 'عزيزي na@abrahem111');
  });

  test('{firstname} و{username} كما كانا', () {
    final s = _sub(firstname: 'إبراهيم', lastname: 'علي');
    expect(_r('{firstname} | {username}', s), 'إبراهيم علي | na@abrahem111');
  });

  test('«اسم المستخدم/اليوزر/يوزرك: {subscriber_name}» يبقى يوزراً (قوالب كتبته بمعناه)', () {
    final s = _sub(firstname: 'إبراهيم');
    expect(_r('👤 اسم المستخدم: {subscriber_name}', s), '👤 اسم المستخدم: na@abrahem111');
    expect(_r('يوزرك: {subscriber_name}\nعزيزي {subscriber_name}', s), 'يوزرك: na@abrahem111\nعزيزي إبراهيم');
    expect(_r('اليوزر {subscriber_name}', s), 'اليوزر na@abrahem111');
  });
}
