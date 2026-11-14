import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «طريق موقع الشحن» (فايبر الجزيرة) — لقطاتٌ للمراجعة (١٤ نوفمبر): شيت التفعيل بطريقة «كارت» وحقل رقم البطاقة الخارجيّة،
/// بعرض ٣٢٠ و٤٨٠ فاتحاً و٣٩٠ داكناً. بياناتٌ تجريبيّة وحدها. المخرجات: VISUAL_OUT (أو build/visual_perm المُتجاهَل بgit).
const _devices = [
  VisualDevice('320', Size(320, 760), 3),
  VisualDevice('480', Size(480, 960), 2),
  VisualDevice('390_dark', Size(390, 844), 3, dark: true),
];

Future<void> _shot(WidgetTester t, String name, VisualDevice d) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(visualRootKey));
  final png = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: d.dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final f = File('${visualOutDir()}/rail_${name}_${d.tag}.png');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(png!, flush: true);
  final ex = t.takeException();
  expect(ex, isNull, reason: 'استثناء في $name ${d.tag}:\n$ex');
}

void main() {
  setUpAll(visualSetUpAll);

  for (final d in _devices) {
    testWidgets('شيت التفعيل على طريق موقع الشحن ${d.tag}', (t) async {
      await visualSetUp(s1bSasOwner);
      ApiClient.dio.httpClientAdapter = _RailServer();
      final sub = Subscriber.fromJson({
        'idx': '55',
        'username': 'sub_17_5_8_10',
        'firstname': 'احمد',
        'lastname': 'علي',
        'profile_id': 197,
        'profile_name': 'Speed Plus',
      });
      await pumpVisual(
        t,
        d,
        home: (_) => Scaffold(
          body: Builder(
            builder: (c) => Center(
              child: TextButton(onPressed: () => showActivateSheet(c, sub), child: const Text('open')),
            ),
          ),
        ),
      );
      await settle(t, seconds: 1);
      await t.tap(find.text('open'));
      await settle(t, seconds: 2);
      await _shot(t, '01_credit', d);
      await t.tap(find.text('كارت (0)'));
      await settle(t, seconds: 1);
      await _shot(t, '02_card_empty', d);
      await t.enterText(find.byKey(const ValueKey('rail-card-pin')), 'AB12cd34');
      await settle(t, seconds: 1);
      await _shot(t, '03_card_pin', d);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 4));
      await visualTearDown();
    });
  }
}

class _RailServer implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final Map<String, dynamic> body = options.path.endsWith('/activation-data')
        ? {
            'success': true,
            'data': {
              'user_price': 40000,
              'price_after_discount': 40000,
              'base_price': 40000,
              'profile_name': 'Speed Plus',
              'profile_id': 197,
              'profile_duration': '30',
              'current_balance': 0,
              'manager_balance': 7200,
              'manager_cost': 35000,
              'activation_methods': {'credit': true, 'card': true},
              'cards': {'enabled': true, 'profile_id': 197, 'profile_name': 'Speed Plus', 'available': 0},
              'pay_rail': {
                'on': true, 'ok': true, 'balance': 7200, 'amount': 35000, 'own_cards': 0, 'requires_otp': false,
                'loan_available': false, 'external_card': true, 'option': {'id': '11', 'name': 'Speed Plus'},
              },
            },
          }
        : {'success': true, 'data': <String, dynamic>{}};
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
