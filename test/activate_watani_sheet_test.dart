import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/kit_card_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/widgets/package_picker_field.dart';

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

  // other-recorded (تفعيلٌ آخر في سجلّنا منذ الطلب) وحالٌ لا يعرفها التطبيق (reversed) ⇒ نصٌّ متحفّظ، لا «سجّله يدويّاً» أبداً
  for (final debt in const ['maybe', 'none', 'other-recorded', 'reversed']) {
    testWidgets('بطاقة v2: «مجهول» ⇒ نصّ الدين بحاله ($debt)', (t) async {
      kitCardLauncher = (u) async => true;
      server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, activationData());
      server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {
        'success': true, 'outcome': 'payment_required', 'payment_url': payUrl, 'order_number': 'ORD111', 'amount': 40000, 'cost': 35000,
      });
      var status = 'link';
      final paidSeen = debt == 'maybe' || debt == 'other-recorded';
      server.on('GET', '/api/v2/ftth/card-orders/ORD111', (_) => SimReply(200, {
            'success': true,
            'data': {
              'order_number': 'ORD111', 'status': status, 'amount': 35000, 'price': 40000, 'payment_type': 'non-cash',
              'payment_url': status == 'link' ? payUrl : null, 'paid_seen': paidSeen, 'no_return': false,
              'debt_state': status == 'link' ? 'none' : debt, 'debt_write_failed': false,
            },
          }));
      await startCard(t);
      status = 'unknown';
      await t.pump(const Duration(seconds: 5));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining(paidSeen ? 'وصلنا أنّ الدفع تمّ' : 'تعذّر التأكّد من النتيجة'), findsOneWidget);
      switch (debt) {
        case 'maybe':
          expect(find.textContaining('ربّما سُجّل الدين عندنا'), findsOneWidget);
          expect(find.textContaining('لم يُسجَّل دينٌ لهذا الطلب'), findsNothing);
        case 'none':
          expect(find.textContaining('لم يُسجَّل دينٌ لهذا الطلب'), findsOneWidget);
          expect(find.textContaining('ربّما سُجّل الدين'), findsNothing);
        case 'other-recorded':
          expect(find.text('في سجلّنا تفعيلٌ آخر لهذا المشترك منذ الطلب — لا تسجّل ديناً يدويّاً قبل مراجعة حركاته وديونه'),
              findsOneWidget);
          expect(find.textContaining('لم يُسجَّل دينٌ لهذا الطلب'), findsNothing);
          expect(find.textContaining('سجّله يدويّاً'), findsNothing);
        default:
          expect(find.text('ربّما سُجّل الدين — راجع ديون المشترك قبل أيّ تسجيلٍ يدويّ'), findsOneWidget);
          expect(find.textContaining('لم يُسجَّل دينٌ لهذا الطلب'), findsNothing);
          expect(find.textContaining('سجّله يدويّاً'), findsNothing);
      }
      expect(find.text('محاولة جديدة'), findsNothing, reason: 'المجهول يُفحص أوّلاً — لا طلبٌ جديد من هنا');
      await t.tap(find.text('إغلاق'));
      await t.pumpAndSettle();
      await simDrain(t);
    });
  }

  // تفعّل والدين في شكّ: تفعيلٌ آخر في سجلّنا منذ الطلب (لم يُكتب دينٌ لهذا الطلب عمداً)، أو حالٌ لا يعرفها التطبيق
  for (final debt in const ['other-recorded', 'reversed']) {
    testWidgets('بطاقة v2: تفعّل والدين $debt ⇒ لا «سُجّل عندنا» ولا «سجّله يدويّاً»، واللوحة تبقى بتنبيهها', (t) async {
      kitCardLauncher = (u) async => true;
      server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, activationData());
      server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {
        'success': true, 'outcome': 'payment_required', 'payment_url': payUrl, 'order_number': 'ORD333', 'amount': 40000, 'cost': 35000,
      });
      var status = 'link';
      server.on('GET', '/api/v2/ftth/card-orders/ORD333', (_) => SimReply(200, {
            'success': true,
            'data': {
              'order_number': 'ORD333', 'status': status, 'amount': 35000, 'price': 40000, 'payment_type': 'non-cash',
              'payment_url': status == 'link' ? payUrl : null, 'paid_seen': status != 'link', 'no_return': false,
              'new_expiration': status == 'applied' ? '2026-12-01 10:00:00' : null,
              'debt_state': status == 'applied' ? debt : 'none', 'debt_write_failed': false,
            },
          }));
      await startCard(t);
      status = 'applied';
      await t.pump(const Duration(seconds: 5));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('ORD333'), findsOneWidget, reason: 'لا إغلاق تلقائيّ والدين في شكّ');
      expect(find.text('تمّ التفعيل ✓'), findsOneWidget);
      expect(
          find.text(debt == 'other-recorded'
              ? 'في سجلّنا تفعيلٌ آخر لهذا المشترك منذ الطلب — لا تسجّل ديناً يدويّاً قبل مراجعة حركاته وديونه'
              : 'ربّما سُجّل الدين — راجع ديون المشترك قبل أيّ تسجيلٍ يدويّ'),
          findsOneWidget);
      expect(find.textContaining('سُجّل عندنا'), findsNothing);
      expect(find.textContaining('سجّله يدويّاً'), findsNothing);
      await t.tap(find.text('إغلاق'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('ORD333'), findsNothing);
      expect(find.textContaining('سجّله يدويّاً'), findsNothing, reason: 'ولا تنبيه «سجّله يدويّاً» بعد الإغلاق');
      await simDrain(t);
    });
  }

  testWidgets('بطاقة v2: رُفضت البطاقة (link بلا رابطٍ بعد السؤال) ⇒ «لم يكتمل» و«محاولة جديدة»، والمتابعة باقية حتى التفعيل', (t) async {
    final opened = <Uri>[];
    kitCardLauncher = (u) async { opened.add(u); return true; };
    addTearDown(() => kitCardLauncher = (u) async => true);
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, activationData());
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {
      'success': true, 'outcome': 'payment_required', 'payment_url': payUrl, 'order_number': 'ORD444', 'amount': 40000, 'cost': 35000,
    });
    var status = 'link';
    var declined = false;
    server.on('GET', '/api/v2/ftth/card-orders/ORD444', (_) => SimReply(200, {
          'success': true,
          'data': {
            'order_number': 'ORD444', 'status': status, 'amount': 35000, 'price': 40000, 'payment_type': 'non-cash',
            'payment_url': status == 'link' && !declined ? payUrl : null, 'paid_seen': status != 'link', 'no_return': false,
            'debt_state': status == 'applied' ? 'written' : 'none', 'debt_write_failed': false,
          },
        }));
    await startCard(t);
    expect(opened.single.toString(), payUrl);
    // سؤالٌ والرابط قائم ⇒ ما زال بانتظار الدفع
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('بانتظار الدفع بالبطاقة…'), findsOneWidget);
    expect(find.text('افتح صفحة الدفع'), findsOneWidget);
    // رجع الدفع مرفوضاً (Status=1): الخادم يسحب الرابط والطلب link
    declined = true;
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('لم يكتمل الدفع — لم يُخصم شيء'), findsOneWidget);
    expect(find.textContaining('بانتظار الدفع'), findsNothing);
    expect(find.text('افتح صفحة الدفع'), findsNothing);
    expect(find.textContaining('تلقائيّاً حين يكتمل الدفع'), findsNothing, reason: 'لا وعدٌ بتسجيلٍ تلقائيّ لدفعٍ رُفض');
    expect(find.text('محاولة جديدة'), findsOneWidget);
    // نجاحٌ لاحق من صفحة الدفع نفسها يُحيي الطلب ⇒ المتابعة لم تتوقّف
    status = 'paid';
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('جارٍ تفعيل المشترك'), findsOneWidget);
    expect(find.text('محاولة جديدة'), findsNothing);
    status = 'applied';
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    expect(find.textContaining('ORD444'), findsNothing, reason: 'تفعّل وسُجّل ⇒ أُغلق الشيت');
    expect(server.calls('POST', '/api/v2/subscribers/$_idx/activate'), hasLength(1));
    await simDrain(t);
  });

  testWidgets('بطاقة v2: «محاولة جديدة» بعد رفض البطاقة ⇒ يعود النموذج', (t) async {
    kitCardLauncher = (u) async => true;
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, activationData());
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {
      'success': true, 'outcome': 'payment_required', 'payment_url': payUrl, 'order_number': 'ORD445', 'amount': 40000, 'cost': 35000,
    });
    server.reply('GET', '/api/v2/ftth/card-orders/ORD445', 200, {
      'success': true,
      'data': {
        'order_number': 'ORD445', 'status': 'link', 'amount': 35000, 'price': 40000, 'payment_type': 'non-cash',
        'payment_url': null, 'paid_seen': false, 'no_return': false, 'debt_state': 'none', 'debt_write_failed': false,
      },
    });
    await startCard(t);
    expect(find.text('افتح صفحة الدفع'), findsOneWidget, reason: 'قبل أيّ سؤال: رابط الإنشاء نفسه');
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('لم يكتمل الدفع — لم يُخصم شيء'), findsOneWidget);
    await t.ensureVisible(find.text('محاولة جديدة'));
    await t.tap(find.text('محاولة جديدة'));
    await t.pumpAndSettle();
    expect(find.textContaining('ORD445'), findsNothing);
    expect(find.text('إنشاء رابط الدفع'), findsOneWidget, reason: 'عاد النموذج لطلبٍ جديد');
    await simDrain(t);
  });

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
    expect(KitCardApi.parseStatus({'status': 'applied', 'debt_state': 'other-recorded'}).debt, KitCardDebt.otherRecorded);
    // حالٌ موجودةٌ لا يعرفها التطبيق ⇒ unknown (المتحفّظ) — null للحقل الغائب وحده (خادمٌ أقدم)
    for (final v in const ['reversed', '', null]) {
      expect(KitCardApi.parseStatus({'status': 'unknown', 'debt_state': v}).debt, KitCardDebt.unknown, reason: 'debt_state=$v');
    }
    final declined = KitCardApi.parseStatus({'status': 'link', 'payment_url': null, 'debt_state': 'none'});
    expect((declined.status, declined.paymentUrl), ('link', null));
  });

  // ── التفعيل لعدّة أشهر (٢ نوفمبر — الخادم: months_options + GET activation-quote + months/expected_cost بالتفعيل) ──

  Map<String, dynamic> monthsData({List<int> months = const [1, 2, 3, 6], bool card = false}) {
    final d = activationData(card: card);
    (d['data'] as Map)['months_options'] = months;
    return d;
  }

  Map<String, dynamic> quote({String? blocked, bool missing = false, num price = 80000, num cost = 59000}) => {
        'success': true,
        'data': {
          'months': 2, 'cost': cost, 'single_month_cost': 35000,
          'offers': [
            {'description': 'عرض الوطني الجديد', 'discount': 11000, 'percentage': null, 'valid_to': '2027-11-18'},
          ],
          'offers_discount': 11000, 'monthly_price': 40000, 'price': price, 'sale_price_missing': missing, 'blocked': blocked,
          'manager_balance': 478063, 'new_expiration': '2027-01-02',
        },
      };

  testWidgets('عدّة أشهر: «مدّة التفعيل» ⇒ معاينة الشركة (السعر والكلفة والعرض والانتهاء) ⇒ التفعيل يرسل months وexpected_cost', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, monthsData());
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-quote', 200, quote());
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {
      'success': true, 'months': 2, 'amount': 80000, 'data': {'new_balance': -80000},
    });
    await open(t);
    expect(find.text('مدّة التفعيل'), findsOneWidget);
    for (final l in ['شهر', 'شهران', '3 أشهر', '6 أشهر']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    expect(server.calls('GET', '/api/v2/subscribers/$_idx/activation-quote'), isEmpty, reason: 'شهرٌ واحد بلا معاينة');
    await t.tap(find.text('شهران'));
    await t.pump();
    await t.pumpAndSettle();
    final q = server.calls('GET', '/api/v2/subscribers/$_idx/activation-quote').single;
    expect(q.queryParameters, {'months': 2, 'profile_id': '11'});
    expect(find.textContaining('سعر المشترك لـشهران'), findsOneWidget);
    expect(find.textContaining('59,000'), findsWidgets);
    expect(find.textContaining('عرض الوطني الجديد'), findsOneWidget);
    expect(find.textContaining('2027-01-02'), findsOneWidget);
    await t.tap(find.text('تجديد الآن'));
    await t.pump();
    await t.pumpAndSettle();
    final body = server.bodies('POST', '/api/v2/subscribers/$_idx/activate').single;
    expect((body['months'], body['expected_cost']), (2, 59000));
    await simDrain(t);
  });

  testWidgets('عدّة أشهر: معاينةٌ محجوبة أو بلا سعر بيع ⇒ لا تفعيل؛ وشهرٌ واحد يرسل الطلب كما كان بلا months', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, monthsData());
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-quote', 200, quote(blocked: 'رصيدك في البوّابة لا يكفي لشهرين'));
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {'success': true, 'data': {'new_balance': -40000}});
    await open(t);
    await t.tap(find.text('شهران'));
    await t.pump();
    await t.pumpAndSettle();
    expect(find.text('رصيدك في البوّابة لا يكفي لشهرين'), findsOneWidget);
    await t.tap(find.text('تجديد الآن'));
    await t.pump();
    await t.pumpAndSettle();
    expect(server.calls('POST', '/api/v2/subscribers/$_idx/activate'), isEmpty, reason: 'محجوبة ⇒ لا تفعيل');
    expect(find.textContaining('انتظر معاينة الأشهر'), findsOneWidget);
    await t.pump(const Duration(seconds: 5)); // الإشعار يغطّي الزرّ حتى يختفي
    await t.pumpAndSettle();
    await t.tap(find.text('شهر'));
    await t.pump();
    await t.pumpAndSettle();
    await t.tap(find.text('تجديد الآن'));
    await t.pump();
    await t.pumpAndSettle();
    final body = server.bodies('POST', '/api/v2/subscribers/$_idx/activate').single;
    expect(body.containsKey('months'), isFalse);
    expect(body.containsKey('expected_cost'), isFalse);
    await simDrain(t);
  });

  testWidgets('عدّة أشهر: البطاقة شهرٌ واحد — «مدّة التفعيل» تختفي معها؛ وخيارٌ واحد لا يُظهرها', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, monthsData(card: true));
    await open(t);
    expect(find.text('مدّة التفعيل'), findsOneWidget);
    await t.tap(find.text('بطاقة'));
    await t.pumpAndSettle();
    expect(find.text('مدّة التفعيل'), findsNothing);
    await simDrain(t);
  });

  testWidgets('عدّة أشهر: خيارٌ واحد من الخادم ⇒ لا «مدّة التفعيل»', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, monthsData(months: const [1]));
    await open(t);
    expect(find.text('مدّة التفعيل'), findsNothing);
    await simDrain(t);
  });

  // ── «تبديل الباقة» (watani_beta بالخادم — providerKit: package_change_allowed + الباقات كلّها + package_change_note) ──

  testWidgets('تبديل الباقة: الباقة الأخرى «حالاً» بتنبيه المزوّد ⇒ التفعيل يرسل profile_id وchange_type now؛ ومعاينة الأشهر بالباقة المختارة', (t) async {
    final d = monthsData();
    final data = d['data'] as Map;
    data['package_change_allowed'] = true;
    data['packages'] = [
      {'id': 11, 'name': 'BASIC', 'price': 40000, 'cost': 35000, 'days': 30},
      {'id': 12, 'name': 'PLUS', 'price': 55000, 'cost': 48000, 'days': 30},
    ];
    data['package_change_note'] = 'باقةٌ أخرى «حالاً» لمشتركٍ فعّال: المشروع الوطني يقرّر بداية مدّتها';
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, d);
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-quote', 200, quote(price: 110000, cost: 96000));
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {'success': true, 'months': 2, 'data': {'new_balance': -110000}});
    await open(t);
    final picker = find.byType(PackagePickerField);
    await t.ensureVisible(picker);
    await t.pumpAndSettle();
    expect(find.textContaining('يقرّر بداية مدّتها'), findsNothing, reason: 'الباقة الحاليّة بلا تنبيه');
    await t.tap(picker);
    await t.pumpAndSettle();
    await t.tap(find.textContaining('PLUS').last); // الاسم بعزلٍ اتّجاهيّ (iso)
    await t.pumpAndSettle();
    expect(find.textContaining('يقرّر بداية مدّتها'), findsOneWidget);
    await t.tap(find.text('شهران'));
    await t.pump();
    await t.pumpAndSettle();
    expect(server.calls('GET', '/api/v2/subscribers/$_idx/activation-quote').last.queryParameters, {'months': 2, 'profile_id': '12'});
    await t.tap(find.text('تجديد الآن'));
    await t.pump();
    await t.pumpAndSettle();
    final body = server.bodies('POST', '/api/v2/subscribers/$_idx/activate').single;
    expect((body['profile_id'], body['change_type'], body['months'], body['expected_cost']), (12, 'now', 2, 96000));
    await simDrain(t);
  });

  testWidgets('خطأٌ غير مقصود (500) ⇒ الرسالة العامّة كما كانت', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 500, {'success': false, 'message': 'Internal'});
    await open(t);
    expect(find.textContaining('Internal'), findsNothing);
    await simDrain(t);
  });
}
