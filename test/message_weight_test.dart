import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/message_style_api.dart';
import 'package:rad_mysvcs/screens/whatsapp/widgets/message_weight_card.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'sim_el/sim_harness.dart';

/// «سُمك خطّ الرسائل» (٢ نوفمبر — الخادم server/messageStyle.js): القراءة، والعرض العريض للمعاينة، والحفظ فور الاختيار، والقفل
/// للموظّف بلا «قوالب الواتساب»، واختفاء البطاقة مع خادمٍ أقدم.
const _v = SimVariant(390, dark: false);
const _path = '/api/whatsapp/message-style/watani:2963757';

Map<String, Object?> _style({String weight = 'normal'}) => {
      'success': true,
      'data': {
        'weight': weight,
        'options': ['normal', 'values', 'bold'],
        'previews': {
          'normal': 'مرحباً علي،\n📦 الباقة: فايبر 75',
          'values': 'مرحباً علي،\n📦 الباقة: *فايبر 75*',
          'bold': '*مرحباً علي،*\n*📦 الباقة: فايبر 75*',
        },
      },
    };

bool _isBold(WidgetTester t, String text) {
  final rich = t.widgetList<RichText>(find.byType(RichText));
  for (final r in rich) {
    var found = false;
    r.text.visitChildren((s) {
      if (s is TextSpan && s.text == text && s.style?.fontWeight == FontWeight.w700) found = true;
      return !found;
    });
    if (found) return true;
  }
  return false;
}

void main() {
  test('النموذج والمقاطع العريضة', () {
    final s = MessageStyle.fromJson(_style(weight: 'values')['data'])!;
    expect((s.weight, s.previews.length), ('values', 3));
    expect(s.options, ['normal', 'values', 'bold']);
    expect(MessageStyle.fromJson({'weight': 'x'})!.weight, 'normal');
    expect(MessageStyle.fromJson('x'), isNull);
    final spans = waBoldSpans('أ *ب* ج', const TextStyle());
    expect(spans.map((e) => (e.text, e.style?.fontWeight)).toList(), [('أ ', null), ('ب', FontWeight.w700), (' ج', null)]);
  });

  group('البطاقة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
      PermissionsService.debugSet(isEmployee: false);
    });
    tearDown(PermissionsService.debugReset);

    Future<void> open(WidgetTester t) async {
      await pumpSim(t, _v, home: (_) => const Scaffold(body: Padding(padding: EdgeInsets.all(16), child: MessageWeightCard())));
      await t.pumpAndSettle();
    }

    testWidgets('المعاينة بالدرجة المحفوظة، والاختيار يحفظ فوراً ويعرض العريض', (t) async {
      server.reply('GET', _path, 200, _style());
      server.reply('PUT', _path, 200, {'success': true, 'data': {'weight': 'values'}});
      await open(t);
      expect(find.text('سُمك خطّ الرسائل'), findsOneWidget);
      expect(_isBold(t, 'فايبر 75'), isFalse);
      await t.tap(find.text('القيم عريضة'));
      await t.pumpAndSettle();
      expect(server.bodies('PUT', _path).single, {'weight': 'values'});
      expect(_isBold(t, 'فايبر 75'), isTrue);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('رفض الخادم ⇒ تعود الدرجة السابقة برسالته', (t) async {
      server.reply('GET', _path, 200, _style(weight: 'bold'));
      server.reply('PUT', _path, 403, {'success': false, 'message': 'لا صلاحيّة'});
      await open(t);
      expect(_isBold(t, 'مرحباً علي،'), isTrue);
      await t.tap(find.text('عادي'));
      await t.pumpAndSettle();
      expect(find.text('لا صلاحيّة'), findsOneWidget);
      expect(_isBold(t, 'مرحباً علي،'), isTrue, reason: 'بقيت كلّها عريضة');
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('الموظّف بلا «قوالب الواتساب» يراها مقفلةً ولا يُرسل شيء؛ وخادمٌ أقدم ⇒ لا بطاقة', (t) async {
      PermissionsService.debugSet(isEmployee: true);
      server.reply('GET', _path, 200, _style());
      await open(t);
      await t.tap(find.text('كلّها عريضة'));
      await t.pumpAndSettle();
      expect(server.calls('PUT', _path), isEmpty);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('خادمٌ أقدم (404) ⇒ لا بطاقة', (t) async {
      await open(t);
      expect(find.text('سُمك خطّ الرسائل'), findsNothing);
    });
  });
}
