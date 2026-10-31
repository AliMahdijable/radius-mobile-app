import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// المشروع الوطنيّ — التفعيل بالتطبيق (٣١ أكتوبر، الخادم server/watani/wataniAdapter quote/renew): رفضٌ مقصود من الخادم
/// (409 برسالةٍ عربيّة، مثل «لا سعر بيع… حدّده من «الباقات»») يُعرض نصّه في الشيت بدل «تعذّر تحميل بيانات التفعيل»،
/// والباقة الحاليّة وحدها تُعرض وتُجدَّد بلا profile_id آخر.
const _v = SimVariant(390, dark: false);
const _idx = '13293073';

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet('watani', label: 'المشروع الوطني');
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  Future<void> open(WidgetTester t) async {
    final sub = Subscriber.fromJson({'idx': _idx, 'username': 'dev-user', 'firstname': 'مشترك', 'profile_id': 11, 'profile_name': 'BASIC'});
    await pumpSim(t, _v, home: (_) => Scaffold(
          body: Builder(builder: (c) => Center(child: TextButton(onPressed: () => showActivateSheet(c, sub), child: const Text('open')))),
        ));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
  }

  testWidgets('بلا سعر بيع: رسالة الخادم نفسها بدل «تعذّر التحميل»', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 409, {
      'success': false,
      'code': 'SALE_PRICE_MISSING',
      'message': 'لا سعر بيع لباقة «BASIC» — حدّده من «الباقات» ثمّ فعّل (لم يُفعَّل شيء)',
    });
    await open(t);
    expect(find.textContaining('حدّده من «الباقات»'), findsOneWidget);
    expect(server.calls('POST', '/api/v2/subscribers/$_idx/activate'), isEmpty);
    await simDrain(t);
  });

  // ── الدفع بالبطاقة (٣١ أكتوبر — الخادم dd29815، مفتاح watani_card) ──

  Map<String, dynamic> activationData({bool card = true}) => {
        'success': true,
        'data': {
          'idx': _idx, 'username': 'dev-user', 'profile_name': 'BASIC', 'profile_id': 11, 'user_price': 40000,
          'price_after_discount': 40000, 'base_price': 40000, 'current_balance': 0, 'manager_balance': 478063,
          'provider': 'watani', 'provider_label': 'المشروع الوطني',
          'packages': [{'id': 11, 'name': 'BASIC', 'price': 40000, 'cost': 35000, 'days': 30}],
          'package_change_allowed': false, 'package_change_timing': ['now'],
          'card_payment': card,
        },
      };
  const payUrl = 'https://epg.tabadul.iq/payment/merchants/x/payment.html?mdOrder=abc';

  testWidgets('بطاقة: الخيار حين يسمح الخادم ⇒ رابط الدفع يُفتح والطلب يُتابَع حتى «تمّ» ثمّ يُغلق الشيت', (t) async {
    final opened = <Uri>[];
    kitCardLauncher = (u) async { opened.add(u); return true; };
    addTearDown(() => kitCardLauncher = (u) async => true);
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, activationData());
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {
      'success': true, 'outcome': 'payment_required', 'payment_url': payUrl, 'order_number': 'ORD90012', 'amount': 40000, 'cost': 35000,
    });
    var status = 'link';
    server.on('GET', '/api/v2/ftth/card-orders/ORD90012', (_) => SimReply(200, {
          'success': true, 'data': {'order_number': 'ORD90012', 'status': status, 'amount': 35000, 'price': 40000, 'payment_url': status == 'link' ? payUrl : null},
        }));
    await open(t);
    expect(find.text('بطاقة'), findsOneWidget);
    expect(find.text('محفظتي'), findsOneWidget);
    await t.tap(find.text('بطاقة'));
    await t.pumpAndSettle();
    expect(find.text('إنشاء رابط الدفع'), findsOneWidget);
    await t.tap(find.text('إنشاء رابط الدفع'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    final body = server.bodies('POST', '/api/v2/subscribers/$_idx/activate').single;
    expect(body['method'], 'card');
    expect(body['paymentType'], 'non-cash');
    expect(opened.single.toString(), payUrl);
    expect(find.textContaining('بانتظار الدفع'), findsOneWidget);
    expect(find.textContaining('ORD90012'), findsOneWidget);
    expect(find.text('افتح صفحة الدفع'), findsOneWidget);
    status = 'paid';
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('جارٍ تفعيل المشترك'), findsOneWidget);
    status = 'applied';
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    expect(find.textContaining('ORD90012'), findsNothing, reason: 'الشيت أُغلق بعد التفعيل');
    await simDrain(t);
  });

  testWidgets('بطاقة: لا خيار حين لا يسمح الخادم؛ وطلبٌ مفتوح ⇒ رابطه نفسه بلا طلبٍ ثانٍ', (t) async {
    kitCardLauncher = (u) async => true;
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, activationData(card: false));
    await open(t);
    expect(find.text('بطاقة'), findsNothing);
    expect(find.text('محفظتي'), findsNothing);
    await simDrain(t);
  });

  testWidgets('بطاقة: طلبٌ مفتوح (409 CARD_ORDER_OPEN) ⇒ لوحة الطلب نفسه برابطه', (t) async {
    kitCardLauncher = (u) async => true;
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, activationData());
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 409, {
      'success': false, 'code': 'CARD_ORDER_OPEN', 'payment_url': payUrl, 'order_number': 'ORD777',
      'message': 'لهذا المشترك طلب دفعٍ بالبطاقة مفتوح — أكمل الدفع من رابطه أو انتظر انتهاءه',
    });
    server.reply('GET', '/api/v2/ftth/card-orders/ORD777', 200, {'success': true, 'data': {'order_number': 'ORD777', 'status': 'link', 'amount': 35000, 'price': 40000, 'payment_url': payUrl}});
    await open(t);
    await t.tap(find.text('بطاقة'));
    await t.pumpAndSettle();
    await t.tap(find.text('إنشاء رابط الدفع'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('ORD777'), findsOneWidget);
    expect(find.text('افتح صفحة الدفع'), findsOneWidget);
    await t.tap(find.text('إغلاق'));
    await t.pumpAndSettle();
    expect(find.textContaining('ORD777'), findsNothing);
    await simDrain(t);
  });

  testWidgets('خطأٌ غير مقصود (500) ⇒ الرسالة العامّة كما كانت', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 500, {'success': false, 'message': 'Internal'});
    await open(t);
    expect(find.textContaining('Internal'), findsNothing);
    await simDrain(t);
  });
}
