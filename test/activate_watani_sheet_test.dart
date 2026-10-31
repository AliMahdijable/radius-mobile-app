import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/kit_card_api.dart';
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

  // ── البطاقة v2 (١ نوفمبر — مراجعة الخادم): مدفوعٌ بلا رابط، انتهاءٌ بلا رجوع، وحال الدين عندنا ──

  Future<void> startCard(WidgetTester t) async {
    await open(t);
    await t.tap(find.text('بطاقة'));
    await t.pumpAndSettle();
    await t.tap(find.text('إنشاء رابط الدفع'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('بطاقة v2: طلبٌ مفتوح مدفوعٌ بلا رابط ⇒ «لا تدفع مرّةً ثانية» بلا صفحة دفع، ويُتابَع حتى التفعيل', (t) async {
    final opened = <Uri>[];
    kitCardLauncher = (u) async { opened.add(u); return true; };
    addTearDown(() => kitCardLauncher = (u) async => true);
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, activationData());
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 409, {
      'success': false, 'code': 'CARD_ORDER_OPEN', 'payment_url': null, 'order_number': 'ORD555', 'paid': true,
      'message': 'دفعٌ بالبطاقة تمّ لهذا المشترك ويُنتظر تفعيله — لا تدفع مرّةً ثانية',
    });
    var status = 'paid';
    server.on('GET', '/api/v2/ftth/card-orders/ORD555', (_) => SimReply(200, {
          'success': true,
          'data': {
            'order_number': 'ORD555', 'status': status, 'amount': 35000, 'price': 40000, 'payment_type': 'non-cash',
            'payment_url': null, 'paid_seen': true, 'no_return': false, 'debt_state': status == 'applied' ? 'written' : 'none',
            'debt_write_failed': false,
          },
        }));
    await startCard(t);
    await t.pump(const Duration(milliseconds: 300));
    expect(opened, isEmpty, reason: 'المدفوع لا تُفتح له صفحة دفع');
    expect(find.text('افتح صفحة الدفع'), findsNothing);
    expect(find.textContaining('جارٍ تفعيل المشترك'), findsOneWidget);
    expect(find.textContaining('لا تدفع مرّةً ثانية'), findsWidgets);
    expect(find.textContaining('ORD555'), findsOneWidget);
    expect(find.textContaining('35,000'), findsOneWidget, reason: 'المبلغ من حالة الطلب فوراً');
    expect(find.text('دين'), findsOneWidget, reason: '«يُسجَّل عندنا» بشروط الطلب نفسه');
    expect(server.calls('POST', '/api/v2/subscribers/$_idx/activate'), hasLength(1));
    status = 'applied';
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    expect(find.textContaining('ORD555'), findsNothing, reason: 'تفعّل وسُجّل ⇒ أُغلق الشيت');
    await simDrain(t);
  });

  testWidgets('بطاقة v2: قيد الإنشاء بلا رقم ⇒ رسالة الخادم حالاً لا خطأ، ولا لوحة', (t) async {
    kitCardLauncher = (u) async => true;
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, activationData());
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 409, {
      'success': false, 'code': 'CARD_ORDER_OPEN', 'payment_url': null, 'order_number': null, 'paid': false,
      'message': 'طلب دفعٍ بالبطاقة لهذا المشترك قيد الإنشاء — انتظر لحظات ثمّ أعد المحاولة',
    });
    await startCard(t);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('قيد الإنشاء'), findsOneWidget);
    expect(find.text('إنشاء رابط الدفع'), findsOneWidget, reason: 'الشيت باقٍ على النموذج');
    await simDrain(t);
  });

  testWidgets('بطاقة v2: انتهى بلا رجوع ⇒ لا «بلا دفع»، وتنبيهٌ فوق «محاولة جديدة» التي تعيد النموذج', (t) async {
    kitCardLauncher = (u) async => true;
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, activationData());
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {
      'success': true, 'outcome': 'payment_required', 'payment_url': payUrl, 'order_number': 'ORD321', 'amount': 40000, 'cost': 35000,
    });
    var status = 'link';
    server.on('GET', '/api/v2/ftth/card-orders/ORD321', (_) => SimReply(200, {
          'success': true,
          'data': {
            'order_number': 'ORD321', 'status': status, 'amount': 35000, 'price': 40000, 'payment_type': 'non-cash',
            'payment_url': status == 'link' ? payUrl : null, 'paid_seen': false, 'no_return': status == 'expired',
            'debt_state': 'none', 'debt_write_failed': false,
          },
        }));
    await startCard(t);
    status = 'expired';
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('بلا دفع'), findsNothing);
    expect(find.textContaining('لم يصلنا رجوعٌ من صفحة الدفع'), findsOneWidget);
    expect(find.textContaining('فلا تدفع مرّةً ثانية'), findsOneWidget);
    expect(find.text('افتح صفحة الدفع'), findsNothing);
    final warn = t.getTopLeft(find.textContaining('فلا تدفع مرّةً ثانية'));
    final retry = t.getTopLeft(find.text('محاولة جديدة'));
    expect(warn.dy, lessThan(retry.dy), reason: 'التنبيه فوق «محاولة جديدة»');
    await t.ensureVisible(find.text('محاولة جديدة'));
    await t.tap(find.text('محاولة جديدة'));
    await t.pumpAndSettle();
    expect(find.textContaining('ORD321'), findsNothing);
    expect(find.text('إنشاء رابط الدفع'), findsOneWidget, reason: 'عاد النموذج لطلبٍ جديد');
    await simDrain(t);
  });

  testWidgets('بطاقة v2: تفعّل ولم يُكتب الدين ⇒ لا «سُجّل عندنا»، واللوحة تبقى بتنبيهها حتى «إغلاق»', (t) async {
    kitCardLauncher = (u) async => true;
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, activationData());
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {
      'success': true, 'outcome': 'payment_required', 'payment_url': payUrl, 'order_number': 'ORD222', 'amount': 40000, 'cost': 35000,
    });
    var status = 'link';
    server.on('GET', '/api/v2/ftth/card-orders/ORD222', (_) => SimReply(200, {
          'success': true,
          'data': {
            'order_number': 'ORD222', 'status': status, 'amount': 35000, 'price': 40000, 'payment_type': 'non-cash',
            'payment_url': status == 'link' ? payUrl : null, 'paid_seen': status != 'link', 'no_return': false,
            'new_expiration': status == 'applied' ? '2026-12-01 10:00:00' : null,
            'debt_state': status == 'applied' ? 'failed' : 'none', 'debt_write_failed': status == 'applied',
          },
        }));
    await startCard(t);
    status = 'applied';
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('ORD222'), findsOneWidget, reason: 'لا إغلاق تلقائيّ مع دينٍ لم يُكتب');
    expect(find.textContaining('لم يُسجَّل الدين في دفترنا'), findsWidgets);
    expect(find.textContaining('سُجّل عندنا'), findsNothing);
    expect(find.textContaining('2026-12-01'), findsOneWidget);
    await t.tap(find.text('إغلاق'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('ORD222'), findsNothing);
    expect(find.textContaining('لم يُسجَّل الدين في دفترنا — سجّله يدويّاً'), findsOneWidget, reason: 'التنبيه يبقى بعد الإغلاق');
    await simDrain(t);
  });

  for (final debt in const ['maybe', 'none']) {
    testWidgets('بطاقة v2: «مجهول» ⇒ نصّ الدين بحاله ($debt)', (t) async {
      kitCardLauncher = (u) async => true;
      server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, activationData());
      server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {
        'success': true, 'outcome': 'payment_required', 'payment_url': payUrl, 'order_number': 'ORD111', 'amount': 40000, 'cost': 35000,
      });
      var status = 'link';
      server.on('GET', '/api/v2/ftth/card-orders/ORD111', (_) => SimReply(200, {
            'success': true,
            'data': {
              'order_number': 'ORD111', 'status': status, 'amount': 35000, 'price': 40000, 'payment_type': 'non-cash',
              'payment_url': status == 'link' ? payUrl : null, 'paid_seen': debt == 'maybe', 'no_return': false,
              'debt_state': status == 'link' ? 'none' : debt, 'debt_write_failed': false,
            },
          }));
      await startCard(t);
      status = 'unknown';
      await t.pump(const Duration(seconds: 5));
      await t.pump(const Duration(milliseconds: 300));
      if (debt == 'maybe') {
        expect(find.textContaining('وصلنا أنّ الدفع تمّ'), findsOneWidget);
        expect(find.textContaining('ربّما سُجّل الدين'), findsOneWidget);
        expect(find.textContaining('لم يُسجَّل دينٌ لهذا الطلب'), findsNothing);
      } else {
        expect(find.textContaining('تعذّر التأكّد من النتيجة'), findsOneWidget);
        expect(find.textContaining('لم يُسجَّل دينٌ لهذا الطلب'), findsOneWidget);
        expect(find.textContaining('ربّما سُجّل الدين'), findsNothing);
      }
      expect(find.text('محاولة جديدة'), findsNothing, reason: 'المجهول يُفحص أوّلاً — لا طلبٌ جديد من هنا');
      await t.tap(find.text('إغلاق'));
      await t.pumpAndSettle();
      await simDrain(t);
    });
  }

  test('KitCardApi: parse/parseStatus بعقد الخادم v2', () {
    final paid = KitCardApi.parse({
      'success': false, 'code': 'CARD_ORDER_OPEN', 'payment_url': 'https://pay/x', 'order_number': 'ORD9', 'paid': true, 'message': 'm',
    }, noReply: false);
    expect(paid.ok, isTrue);
    expect(paid.open, isTrue);
    expect(paid.paid, isTrue);
    expect(paid.paymentUrl, isNull, reason: 'المدفوع بلا رابطٍ أبداً');
    final pending = KitCardApi.parse({'success': false, 'code': 'CARD_ORDER_OPEN', 'order_number': 'pending-abc', 'paid': false}, noReply: false);
    expect(pending.ok, isFalse);
    expect(pending.open, isTrue);
    final fresh = KitCardApi.parse({
      'success': true, 'outcome': 'payment_required', 'payment_url': 'https://pay/y', 'order_number': 'ORD8', 'amount': 40000, 'cost': 35000,
    }, noReply: false);
    expect((fresh.ok, fresh.open, fresh.cost, fresh.price), (true, false, 35000, 40000));
    final plain = KitCardApi.parse({'success': true, 'outcome': 'payment_required', 'payment_url': 'http://x', 'order_number': 'O'}, noReply: false);
    expect(plain.ok, isFalse, reason: 'رابطٌ غير https لا يُفتح');

    final s = KitCardApi.parseStatus({
      'status': 'applied', 'amount': 35000, 'price': 40000, 'payment_type': 'non-cash', 'paid_seen': true, 'no_return': false,
      'debt_state': 'written', 'debt_write_failed': true,
    });
    expect(s.debt, KitCardDebt.failed, reason: 'debt_write_failed يغلب');
    expect(s.debtWriteFailed, isTrue);
    final old = KitCardApi.parseStatus({'status': 'applied', 'amount': 35000});
    expect(old.debt, isNull);
    expect(old.debtWriteFailed, isFalse);
    expect(old.noReturn, isFalse);
    final maybe = KitCardApi.parseStatus({'status': 'unknown', 'debt_state': 'maybe'});
    expect(maybe.debt, KitCardDebt.maybe);
  });

  testWidgets('خطأٌ غير مقصود (500) ⇒ الرسالة العامّة كما كانت', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 500, {'success': false, 'message': 'Internal'});
    await open(t);
    expect(find.textContaining('Internal'), findsNothing);
    await simDrain(t);
  });
}
