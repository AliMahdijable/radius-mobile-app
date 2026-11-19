// رسالة الكارت لمشتركٍ بلا رقم (١٩ نوفمبر — المالك: «إذا نقر إرسال رسالة مباشرة من داخل الكارت… ما عنده لا واتساب ولا تلي، فالخيار
// الأخير يروح للتطبيق»): التطبيق يُكمل القالب ويسأل ثمّ يرسل للخادم بلا رقم ومعه رقم المشترك — الخادم (bc0345a) يوصله لتطبيقه، أو يقول
// «بلا رقم واتساب ولا تلغرام ولا تطبيق». ومشتركٌ بلا رقمٍ ولا معرّف يبقى «لا يوجد رقم» كما كان.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';

import 'sim_el/sim_harness.dart';

void main() {
  late SimServer server;
  setUpAll(simSetUpAll);
  setUp(() async {
    WhatsAppApi.clearCaches();
    server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin@m'});
    server.reply('GET', '/api/whatsapp/templates/2', 200, {
      'success': true,
      'templates': [
        {'template_type': 'debt_reminder', 'is_active': 1, 'message_content': 'مرحباً {firstname}، عليك دين', 'default_channel': 'auto'},
      ],
    });
  });

  Future<WhatsSendResult?> run(WidgetTester t, Subscriber sub, {bool confirm = true}) async {
    WhatsSendResult? out;
    await pumpSim(t, const SimVariant(390, dark: false), home: (_) => Builder(
          builder: (ctx) => Center(
            child: TextButton(
              key: const ValueKey('go'),
              onPressed: () async => out = await WhatsAppApi.sendTemplateWithPreview(context: ctx, sub: sub, templateType: 'debt_reminder'),
              child: const Text('go'),
            ),
          ),
        ));
    await t.tap(find.byKey(const ValueKey('go')));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    if (find.byKey(const ValueKey('no-phone-app-confirm')).evaluate().isNotEmpty) {
      await t.tap(confirm ? find.byKey(const ValueKey('no-phone-app-send')) : find.text('إلغاء'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }
    return out;
  }

  testWidgets('بلا رقم ومعه معرّف: تأكيدٌ ثمّ الخادم بلا رقم ومعه المعرّف — وصلت لتطبيقه', (t) async {
    server.reply('POST', '/api/whatsapp/send-message', 200,
        {'success': true, 'channel': 'app', 'message': 'المشترك بلا رقم واتساب — أُرسلت الرسالة لتطبيق المشترك', 'messageId': 'app'});
    final sub = Subscriber.fromJson({'idx': '55', 'username': 'ali', 'firstname': 'علي', 'phone': '', 'mobile': ''});
    final r = await run(t, sub);
    expect(r, isNotNull);
    expect(r!.ok, isTrue);
    expect(r.channel, 'app');
    expect(r.channelArabic, 'التطبيق');
    final body = server.bodies('POST', '/api/whatsapp/send-message').single;
    expect(body['to'], '');
    expect(body['sas4Idx'], '55');
    expect(body['intent'], 'debt_reminder');
    expect(body['message'], 'مرحباً علي، عليك دين');
  });

  testWidgets('بلا تطبيقٍ أيضاً: سبب الخادم كما هو', (t) async {
    server.reply('POST', '/api/whatsapp/send-message', 400,
        {'success': false, 'code': 'NO_CHANNEL', 'message': 'المشترك بلا رقم واتساب ولا تلغرام ولا تطبيق — لم تُرسَل الرسالة'});
    final sub = Subscriber.fromJson({'idx': '56', 'username': 'omar', 'firstname': 'عمر', 'phone': ''});
    final r = await run(t, sub);
    expect(r!.ok, isFalse);
    expect(r.message, contains('بلا رقم واتساب ولا تلغرام ولا تطبيق'));
  });

  testWidgets('إلغاء التأكيد ⇒ لا طلب', (t) async {
    final sub = Subscriber.fromJson({'idx': '57', 'username': 'sara', 'firstname': 'سارة', 'phone': ''});
    final r = await run(t, sub, confirm: false);
    expect(r!.reason, 'cancelled');
    expect(server.calls('POST', '/api/whatsapp/send-message'), isEmpty);
  });

  testWidgets('بلا رقمٍ ولا معرّف: «لا يوجد رقم» كما كان (لا طلب)', (t) async {
    final sub = Subscriber.fromJson({'username': 'x', 'phone': ''});
    final r = await run(t, sub);
    expect(r!.reason, 'no_phone');
    expect(server.calls('POST', '/api/whatsapp/send-message'), isEmpty);
  });
}
