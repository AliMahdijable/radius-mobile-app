// قناة «التطبيق» (١٨ نوفمبر — الخادم c8d41f0): ما يقرؤه التطبيق ويرسله —
//  - GET /api/whatsapp/broadcast/channels: app.enabled ⇒ البلاطات المعروضة، والأعداد والأقفال
//  - الحملات: حالة التطبيق (وصل/انفتح/بلا تطبيق/كاتم/فشل/ينتظر) وحملة التطبيق وحده
//  - الجدولات: «channels» من الخادم قبل العمود القديم، والحفظ يرسل الاختيار الجديد للحساب المفعّل وحده وقيمةً يفهمها العمود القديم دائماً
//  - شرح «تلقائي» بحسب القناة (القديم: تلغرام للي رابطه والباقي واتساب)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/broadcast_api.dart';
import 'package:rad_mysvcs/models/whatsapp_schedule.dart';
import 'package:rad_mysvcs/widgets/delivery_channels.dart';

void main() {
  group('حالة القنوات', () {
    test('مفعّلة: الثلاث معروضة بأعدادها وأقفالها', () {
      final i = BroadcastChannelsInfo.fromJson({
        'success': true,
        'app': {'enabled': true},
        'reach': {'telegram': 4, 'app': 9},
        'locks': {
          'whatsapp': {'sent': 3, 'total': 10, 'batchId': 'bc_x'},
        },
      });
      expect(i.appEnabled, isTrue);
      expect(i.available, DeliveryChannel.values);
      expect(i.reach[DeliveryChannel.app], 9);
      expect(i.reach[DeliveryChannel.whatsapp], isNull, reason: 'الخادم لا يعدّ الواتساب');
      expect(i.locks[DeliveryChannel.whatsapp]!.total, 10);
    });
    test('غير مفعّلة أو خادمٌ أقدم بلا app: لا بلاطة للتطبيق', () {
      for (final j in [
        {'success': true, 'app': {'enabled': false}, 'reach': {}, 'locks': {}},
        {'success': true, 'reach': {'telegram': 1}, 'locks': {}},
      ]) {
        final i = BroadcastChannelsInfo.fromJson(j);
        expect(i.appEnabled, isFalse);
        expect(i.available, [DeliveryChannel.whatsapp, DeliveryChannel.telegram]);
      }
    });
  });

  group('الحملات', () {
    test('حالة التطبيق وحملة التطبيق وحده', () {
      final c = BroadcastCampaign.fromJson({
        'batch_id': 'bc_1',
        'sample': 'عرض',
        'total': 0,
        'sent': 0,
        'pending': 0,
        'processing': 0,
        'failed': 0,
        'cancelled': 0,
        'telegram': 0,
        'app_only': true,
        'app': {'total': 12, 'sent': 8, 'opened': 3, 'no_device': 1, 'muted': 2, 'failed': 0, 'pending': 1, 'no_app': 30},
      })!;
      expect(c.appOnly, isTrue);
      expect(c.active, isFalse);
      expect(c.appActive, isTrue);
      expect(c.app!.sent, 8);
      expect(c.app!.opened, 3);
      expect(c.app!.noApp, 30);
      expect(c.app!.noDevice, 1);
      final legacy = BroadcastCampaign.fromJson({'batch_id': 'bc_2', 'total': 5, 'sent': 5})!;
      expect(legacy.app, isNull);
      expect(legacy.appOnly, isFalse);
    });
  });

  group('الجدولات', () {
    Map<String, dynamic> row(Map<String, dynamic> extra) => {
          'id': 1,
          'admin_id': '2251',
          'schedule_type': 'expiry_warning',
          'is_enabled': 1,
          'scheduled_time': '10:00:00',
          'active_days': [0, 1, 2],
          ...extra,
        };
    test('«channels» من الخادم قبل العمود القديم', () {
      expect(WhatsAppSchedule.fromJson(row({'channel_preference': 'auto', 'channels': ['app', 'whatsapp']})).channelPreference,
          'whatsapp,app');
      expect(WhatsAppSchedule.fromJson(row({'channel_preference': 'whatsapp', 'channels': 'auto'})).channelPreference, 'auto');
      expect(WhatsAppSchedule.fromJson(row({'channel_preference': 'telegram'})).channelPreference, 'telegram');
    });
    test('الحفظ: الاختيار الجديد للحساب المفعّل، والعمود القديم بقيمةٍ يفهمها دائماً', () {
      final s = WhatsAppSchedule.fromJson(row({'channels': ['whatsapp', 'app']}));
      final on = s.copyWith(sendChannels: true).toSaveJson()['scheduleData'] as Map;
      expect(on['channels'], ['whatsapp', 'app']);
      expect(on['channelPreference'], 'whatsapp');
      final off = s.toSaveJson()['scheduleData'] as Map;
      expect(off.containsKey('channels'), isFalse);
      expect(off['channelPreference'], 'whatsapp');
      final auto = WhatsAppSchedule.fromJson(row({'channels': 'auto'})).copyWith(sendChannels: true).toSaveJson()['scheduleData'] as Map;
      expect(auto['channels'], 'auto');
      expect(auto['channelPreference'], 'auto');
    });
    test('القيمة القديمة لكلّ اختيار', () {
      expect(WhatsAppSchedule.legacyChannelPreference('auto'), 'auto');
      expect(WhatsAppSchedule.legacyChannelPreference('whatsapp,telegram'), 'auto');
      expect(WhatsAppSchedule.legacyChannelPreference('whatsapp,telegram,app'), 'auto');
      expect(WhatsAppSchedule.legacyChannelPreference('telegram,app'), 'telegram');
      expect(WhatsAppSchedule.legacyChannelPreference('app'), 'whatsapp');
      expect(WhatsAppSchedule.legacyChannelPreference('whatsapp,app'), 'whatsapp');
    });
  });

  group('الشرح', () {
    test('«تلقائي» بحسب القناة', () {
      const auto = DeliveryChoice.auto();
      expect(deliveryChoiceHint(auto), contains('وبعدين التطبيق'));
      expect(deliveryChoiceHint(auto, app: false), 'رسالة وحدة لكل مشترك: تلغرام للي رابطه، والباقي واتساب');
      expect(deliveryChoiceHint(const DeliveryChoice.only({DeliveryChannel.app})), contains('التطبيق وحده'));
    });
    testWidgets('البلاطات: بلا «التطبيق» حين لا تُتاح', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: DeliveryChannelsPicker(
              value: const DeliveryChoice.auto(),
              onChanged: (_) {},
              available: const [DeliveryChannel.whatsapp, DeliveryChannel.telegram],
            ),
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('channel-app')), findsNothing);
      expect(find.byKey(const ValueKey('channel-whatsapp')), findsOneWidget);
      expect(find.text('رسالة وحدة لكل مشترك: تلغرام للي رابطه، والباقي واتساب'), findsOneWidget);
    });
  });
}
