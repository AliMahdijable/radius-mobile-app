import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/el_card_order_gate.dart';
import 'package:rad_mysvcs/api/el_deposit_password.dart';
import 'package:rad_mysvcs/screens/el/card_order_screen.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_harness.dart';

/// «طلب الكارتات» حين يوقفه الخادم (503 `CARD_ORDER_OFF` — مفتاح
/// `el_card_order`، مطفأٌ في الإنتاج حتى يوافق المالك): تنبيهٌ مكان النموذج،
/// والرصيد والسجلّ باقيان، ولا إرسال. والباب في «قوائم أخرى» يُخفى معه
/// (test/el_card_order_gate_test.dart).
const _screen = 'el_card_order';
const _quotePath = '/api/v2/el/card-order/quote';
const _orderPath = '/api/v2/el/card-order';
const _off = {
  'success': false,
  'code': 'CARD_ORDER_OFF',
  'message': 'طلب الكروت موقوفٌ مؤقّتاً — لم يُرسَل شيء',
};

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp();
    ProviderService.debugSet('earthlink');
    ElDepositPassword.reset();
    ElCardOrderGate.reset();
    debugClearElCardOrderRecent();
    server.reply('GET', '/api/v2/admin-widgets', 200,
        {'success': true, 'balance': 1250000, 'cards': {'remaining': null}});
    server.reply('GET', '/api/v2/el/prepaid-needed', 200, {
      'success': true,
      'days': 7,
      'data': [
        {'profile_id': 7, 'name': 'Economy', 'cost': 20000, 'available': 12, 'used': 30, 'needed': 18},
        {'profile_id': 13, 'name': 'Business Pro 100M', 'cost': 180000, 'available': 3, 'used': 0, 'needed': 0},
      ],
    });
    server.reply('GET', '/api/v2/packages', 200, {
      'success': true,
      'data': [
        {'id': 7, 'name': 'Economy'},
        {'id': 13, 'name': 'Business Pro 100M'},
      ],
    });
    server.reply('GET', '/api/v2/el/card-orders', 200, {
      'success': true,
      'data': [
        {
          'batch_no': 5498,
          'status': 'Approved',
          'created_at': '2026-10-11T09:30:00',
          'can_cancel': false,
          'cards': [
            {'name': 'Economy', 'amount': 10, 'price': 22000, 'approved_count': 10},
          ],
        },
      ],
    });
    server.reply('POST', _quotePath, 503, _off);
  });

  tearDown(ElCardOrderGate.reset);

  simCase(_screen, 'off_banner', (t, v) async {
    await pumpSim(t, v,
        home: (_) => const ElCardOrderScreen(days: 7, initialCounts: {7: 18}));
    expect(find.textContaining('طلب الكارتات موقوفٌ مؤقّتاً'), findsOneWidget);
    expect(find.textContaining('مراجعة الطلب'), findsNothing);
    expect(find.text('1,250,000'), findsOneWidget, reason: 'الرصيد باقٍ');
    expect(server.calls('POST', _orderPath), isEmpty);
    expect(ElCardOrderGate.open.value, isFalse);
    await simCheck(t, v, _screen, 'off_banner');
  });
}
