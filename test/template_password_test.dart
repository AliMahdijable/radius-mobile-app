import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/broadcast_api.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';

/// «كلمة سر المشترك» `{password}` في قوالب الرسائل (١٠ نوفمبر ٢٠٢٦ — الخادم add724a).
///
/// العقد: الخادم يملؤها في كلّ ما يُرسَل عبره (يقرؤها من الشركة لحظة الإرسال ولا تُخزَّن)، والتطبيق يملؤها فيما يخرج من
/// واتساب المدير نفسه (اليدويّ) وفي المعاينة — وبلا كلمةٍ يُحذف سطرها (لا «{password}» حرفيّاً للمشترك).
void main() {
  group('WhatsAppApi.applyPassword', () {
    const tpl = 'مرحباً علي\n👤 اليوزر: ali@net\n🔑 الباسورد: {password}\n🔐 رمز الوكيل: 550121';

    test('كلمةٌ معلومة تدخل مكان المتغيّر في كلّ مواضعه — بحروفها كما هي', () {
      expect(WhatsAppApi.applyPassword(tpl, r'S3cr$t&*1'),
          'مرحباً علي\n👤 اليوزر: ali@net\n🔑 الباسورد: S3cr\$t&*1\n🔐 رمز الوكيل: 550121');
      expect(WhatsAppApi.applyPassword('{password} / {password}', 'x1'), 'x1 / x1');
    });

    test('بلا كلمة (لا صلاحيّة، الشركة تمنعها): يُحذف سطرها كاملاً ولا يبقى المتغيّر', () {
      for (final pw in <String?>[null, '', '   ']) {
        final out = WhatsAppApi.applyPassword(tpl, pw);
        expect(out, 'مرحباً علي\n👤 اليوزر: ali@net\n🔐 رمز الوكيل: 550121');
        expect(out.contains('{password}'), isFalse);
      }
    });

    test('سطرٌ بين فراغين لا يترك فجوةً، ونصٌّ كلّه المتغيّر يصير «-»', () {
      expect(WhatsAppApi.applyPassword('أ\n\nكلمتك {password}\n\nب', null), 'أ\n\nب');
      expect(WhatsAppApi.applyPassword('{password}', null), '-');
    });

    test('نصٌّ بلا المتغيّر لا يُمسّ بحرف', () {
      const same = 'نصّ  بمسافتين\n\n\n\nوأسطر فارغة';
      expect(WhatsAppApi.applyPassword(same, 'x'), same);
      expect(WhatsAppApi.applyPassword(same, null), same);
    });
  });

  test('الشريحة معروضة في محرّر القوالب والتبليغات', () {
    expect(WhatsAppApi.kPasswordVariable, '{password}');
    expect(BroadcastVariables.all.any((v) => v.token == '{password}'), isTrue);
    final editor = File('lib/screens/whatsapp/whatsapp_templates_screen.dart').readAsStringSync();
    expect(editor.contains("'{password}': 'كلمة سر المشترك'"), isTrue);
    final vars = RegExp(r'static const _subscriberVariables = <String>\[(.*?)\];', dotAll: true).firstMatch(editor)!.group(1)!;
    expect(vars.contains("'{password}'"), isTrue);
    expect(vars.indexOf("'{username}'") < vars.indexOf("'{password}'"), isTrue);
  });

  test('التلقائيّ يرسل المتغيّر للخادم (لا الكلمة)، واليدويّ والمعاينة بالكلمة', () {
    final api = File('lib/api/whatsapp_api.dart').readAsStringSync();
    // sendTemplateWithPreview: المعاينة واليدويّ من rendered (fillPassword)، والتلقائيّ من base
    expect(api.contains('final rendered = await fillPassword(base, sub);'), isTrue);
    expect(RegExp(r'return sendMessage\(\s*to: phone,\s*message: base,\s*intent: templateType,').hasMatch(api), isTrue);
    final flow = File('lib/screens/subscribers/connection_alert_flow.dart').readAsStringSync();
    expect(flow.contains('final message = await WhatsAppApi.fillPassword(base, sub);'), isTrue);
    expect(RegExp(r"message: base,\s*intent: 'connection_alert'").hasMatch(flow), isTrue);
  });
}
