import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/el_card_order_gate.dart';
import 'package:rad_mysvcs/api/el_deposit_password.dart';
import 'package:rad_mysvcs/api/self_deposit_api.dart';
import 'package:rad_mysvcs/screens/el/card_order_screen.dart';
import 'package:rad_mysvcs/screens/el/required_cards_screen.dart';
import 'package:rad_mysvcs/screens/more_modules_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «طلب الكارتات» (ايرث لنك) يتبع مفتاح الخادم.
///
/// الطلب يخصم من رصيد الإيداع، وللخادم مفتاح إيقافٍ (`pro_settings`
/// «el_card_order» — مطفأٌ في الإنتاج حتى يوافق المالك) يردّ التقدير والطلب
/// 503 `CARD_ORDER_OFF`. قبل الإصلاح كانت البطاقة والزرّ ظاهرَين لكلّ مالك ايرث
/// لنك: يملأ الأعداد فينتهي كلّ «مراجعة الطلب» بـ«موقوف مؤقّتاً». الآن: لا باب
/// ما لم يقل الخادم «مفتوح» (كـ«شحن رصيد الصفحة»)، والسؤال تقديرٌ بسلّةٍ فارغة
/// (الخادم يفحص المفتاح قبل أيّ شيء — بلا نداءٍ لايرث لنك).
const _quotePath = '/api/v2/el/card-order/quote';
const _orderPath = '/api/v2/el/card-order';
const _ordersPath = '/api/v2/el/card-orders';
const _neededPath = '/api/v2/el/prepaid-needed';
const _offMsg = 'طلب الكروت موقوفٌ مؤقّتاً — لم يُرسَل شيء';
const _offBody = {'success': false, 'code': 'CARD_ORDER_OFF', 'message': _offMsg};

/// ردّ الخادم الحيّ على السلّة الفارغة والمفتاح مفتوح (elCards.orderLimitError).
const _emptyCart = {'success': false, 'message': 'حدّد الباقة والعدد'};
const _banner = 'طلب الكارتات موقوفٌ مؤقّتاً';
const _secret = 'Dep#4417secret';

/// تقدير الخادم (elCards.quoteOrder) — سعر الكارت 22,000.
SimReply _quote(Object? data) {
  final cards = ((data as Map)['cards'] as List).cast<Map>();
  var total = 0;
  var count = 0;
  final items = <Map<String, Object?>>[];
  for (final c in cards) {
    final n = c['count'] as int;
    total += 22000 * n;
    count += n;
    items.add({
      'profile_id': c['profile_id'],
      'name': 'Economy',
      'count': n,
      'unit_cost': 22000,
      'total': 22000 * n,
    });
  }
  return SimReply(200, {
    'success': true,
    'data': {
      'items': items,
      'unknown': const <int>[],
      'total': total,
      'balance': 1250000,
      'enough': true,
      'after': 1250000 - total,
      'count': count,
      'expected_total': total,
    },
  });
}

void main() {
  late SimServer server;
  const v = SimVariant(390, dark: false);

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp();
    ProviderService.debugSet('earthlink');
    PermissionsService.debugSet(isEmployee: false);
    ElCardOrderGate.reset();
    SelfDepositState.reset();
    ElDepositPassword.reset();
    debugClearElCardOrderRecent();
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
    ElCardOrderGate.reset();
    SelfDepositState.reset();
  });

  List<Map<String, dynamic>> probes() => server.bodies('POST', _quotePath);

  // ═══════════════════════ حكم السؤال ═══════════════════════
  group('حكم السؤال (تقديرٌ بسلّةٍ فارغة)', () {
    test('موقوف · مفتوح · لا باب · لم يُعرف', () {
      expect(ElCardOrderGate.verdict(503, _offBody), isFalse, reason: 'المفتاح مطفأ');
      expect(ElCardOrderGate.verdict(400, _emptyCart), isTrue,
          reason: 'السلّة الفارغة رُفضت بعد فحص المفتاح');
      expect(ElCardOrderGate.verdict(200, {'success': true, 'data': {}}), isTrue);
      expect(ElCardOrderGate.verdict(403, {'success': false, 'code': 'OWNER_ONLY'}),
          isFalse,
          reason: 'ليس صاحب الحساب');
      expect(ElCardOrderGate.verdict(404, {'success': false}), isFalse,
          reason: 'خادمٌ بلا المسار');
      // لم يُعرف: لا ردّ، 5xx بلا الرمز، بوّابةٌ بصفحة HTML، جلسةٌ انتهت، حدّ طلبات.
      expect(ElCardOrderGate.verdict(null, null), isNull);
      expect(
          ElCardOrderGate.verdict(503, {'success': false, 'message': 'تعذّر حساب كلفة الطلب'}),
          isNull);
      expect(ElCardOrderGate.verdict(502, '<html>Bad gateway</html>'), isNull);
      expect(ElCardOrderGate.verdict(401, {'success': false}), isNull);
      expect(ElCardOrderGate.verdict(429, {'success': false, 'message': 'كثير'}), isNull);
      expect(
          ElCardOrderGate.verdict(400, {'success': false, 'code': 'APP_UPDATE_REQUIRED'}),
          isNull,
          reason: '400 برمزٍ آخر ليس رفض السلّة');
    });

    test('السؤال: POST التقدير بسلّةٍ فارغة، ولصاحب حساب ايرث لنك وحده', () async {
      server.reply('POST', _quotePath, 503, _offBody);
      await ElCardOrderGate.ensureFresh();
      expect(probes(), [
        {'cards': <Object>[]},
      ]);
      expect(ElCardOrderGate.open.value, isFalse);
      expect(server.calls('POST', _orderPath), isEmpty);
      // ضمن المهلة: لا سؤال ثانٍ.
      await ElCardOrderGate.ensureFresh();
      expect(probes(), hasLength(1));

      ElCardOrderGate.reset();
      PermissionsService.debugSet(isEmployee: true);
      await ElCardOrderGate.ensureFresh();
      ProviderService.debugSet(null);
      PermissionsService.debugSet(isEmployee: false);
      await ElCardOrderGate.ensureFresh();
      expect(probes(), hasLength(1), reason: 'الموظّف وشركات SAS4 لا يُسأل لهم');
      expect(ElCardOrderGate.open.value, isNull);
    });

    test('بلا جلسة: لا سؤال', () async {
      FlutterSecureStorage.setMockInitialValues({'auth.admin_id': 'earthlink:5'});
      server.reply('POST', _quotePath, 400, _emptyCart);
      await ElCardOrderGate.ensureFresh();
      expect(probes(), isEmpty);
      expect(ElCardOrderGate.open.value, isNull);
    });

    test('لم يُعرف (لا ردّ) ⇒ لا يُكتب شيء، ويُعاد بعد التبريد لا فوراً', () async {
      server.on('POST', _quotePath, simTimeout);
      await ElCardOrderGate.ensureFresh();
      expect(ElCardOrderGate.open.value, isNull);
      expect(ElCardOrderGate.visible, isFalse);
      await ElCardOrderGate.ensureFresh();
      expect(probes(), hasLength(1), reason: 'تبريد ٣٠ث بعد الفشل');
      // ما عُرف قبله يبقى: فشلٌ عابر لا يُخفي باباً مفتوحاً.
      ElCardOrderGate.debugSet(true);
      await ElCardOrderGate.ensureFresh(force: true);
      expect(ElCardOrderGate.open.value, isTrue);
    });
  });

  // ═══════════════════════ «قوائم أخرى» ═══════════════════════
  group('بطاقة «طلب الكارتات» في «قوائم أخرى»', () {
    Finder card() => find.text('طلب الكارتات', skipOffstage: false);

    Future<void> showMore(WidgetTester t) async {
      await pumpSim(t, v, home: (_) => const MoreModulesScreen());
      // القائمة كلّها مبنيّة (بطاقات ايرث لنك في آخرها).
      t.view.physicalSize = const Size(390, 3200);
      await t.pumpAndSettle();
    }

    testWidgets('🚨 موقوفٌ بالخادم: لا بطاقة، ولا طلب', (t) async {
      server.reply('POST', _quotePath, 503, _offBody);
      await showMore(t);
      expect(card(), findsNothing);
      expect(find.byIcon(LucideIcons.shoppingCart, skipOffstage: false), findsNothing);
      expect(probes(), [
        {'cards': <Object>[]},
      ]);
      expect(server.calls('POST', _orderPath), isEmpty);
      // ما لا يمسّ المال باقٍ بمكانه.
      expect(find.text('الكارتات المطلوبة', skipOffstage: false), findsOneWidget);
      expect(find.text('تحويل الرصيد', skipOffstage: false), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('مفتوح: البطاقة مفتوحة وتفتح الشاشة', (t) async {
      server.reply('POST', _quotePath, 400, _emptyCart);
      await showMore(t);
      expect(card(), findsOneWidget);
      expect(ElCardOrderGate.visible, isTrue);
      await t.tap(card());
      await t.pumpAndSettle();
      expect(find.byType(ElCardOrderScreen), findsOneWidget);
      expect(server.calls('POST', _orderPath), isEmpty);
    });

    testWidgets('لم يُعرف (انقطاع): لا بطاقة', (t) async {
      server.on('POST', _quotePath, simTimeout);
      await showMore(t);
      expect(card(), findsNothing);
    });

    testWidgets('موظّف ايرث لنك: لا سؤال ولا بطاقة', (t) async {
      PermissionsService.debugSet(
          isEmployee: true, permissions: const {'reports.financial': true});
      server.reply('POST', _quotePath, 400, _emptyCart);
      await showMore(t);
      expect(card(), findsNothing);
      expect(probes(), isEmpty);
    });

    testWidgets('شركة SAS4: لا سؤال ولا بطاقة', (t) async {
      ProviderService.debugSet(null);
      server.reply('POST', _quotePath, 400, _emptyCart);
      await showMore(t);
      expect(card(), findsNothing);
      expect(probes(), isEmpty);
    });

    testWidgets('المزوّد يُعرف بعد فتح القائمة: يُسأل حينها', (t) async {
      ProviderService.debugSet(null);
      server.reply('POST', _quotePath, 400, _emptyCart);
      await showMore(t);
      expect(probes(), isEmpty);
      ProviderService.debugSet('earthlink');
      // إطارٌ يعيد البناء (فيُسأل)، ثمّ يصل الجواب فيُعاد البناء ثانيةً.
      await t.pump();
      await t.pumpAndSettle();
      expect(probes(), hasLength(1));
      expect(card(), findsOneWidget);
    });
  });

  // ═══════════════════════ «الكارتات المطلوبة» ═══════════════════════
  group('زرّ «اطلب هذه الكارتات» في «الكارتات المطلوبة»', () {
    const label = 'اطلب هذه الكارتات من ايرث لنك';
    setUp(() {
      server.reply('GET', _neededPath, 200, {
        'success': true,
        'data': [
          {'profile_id': 7, 'name': 'Economy', 'cost': 20000, 'available': 1, 'used': 9, 'needed': 8},
        ],
      });
    });

    testWidgets('🚨 موقوف: لا زرّ، والتوقّع كما هو', (t) async {
      server.reply('POST', _quotePath, 503, _offBody);
      await pumpSim(t, v, home: (_) => const ElRequiredCardsScreen());
      expect(find.text('Economy'), findsOneWidget);
      expect(find.text(label), findsNothing);
      expect(probes(), hasLength(1));
    });

    testWidgets('مفتوح: الزرّ', (t) async {
      server.reply('POST', _quotePath, 400, _emptyCart);
      await pumpSim(t, v, home: (_) => const ElRequiredCardsScreen());
      expect(find.text(label), findsOneWidget);
    });
  });

  // ═══════════════════════ الشاشة ═══════════════════════
  group('شاشة «طلب الكارتات» حين يوقفه الخادم', () {
    setUp(() {
      server.reply('GET', '/api/v2/admin-widgets', 200,
          {'success': true, 'balance': 1250000, 'cards': {'remaining': null}});
      server.reply('GET', _neededPath, 200, {
        'success': true,
        'data': [
          {'profile_id': 7, 'name': 'Economy', 'cost': 20000, 'available': 1, 'used': 9, 'needed': 8},
        ],
      });
      server.reply('GET', '/api/v2/packages', 200, {
        'success': true,
        'data': [
          {'id': 7, 'name': 'Economy'},
        ],
      });
      server.reply('GET', _ordersPath, 200, {'success': true, 'data': <Object>[]});
      server.reply('POST', _ordersPath, 200, {'success': true, 'data': <Object>[]});
    });

    Future<void> open(WidgetTester t) => pumpSim(t, v,
        home: (_) => const ElCardOrderScreen(days: 7, initialCounts: {7: 2}));

    /// القائمة كسولة — يُمرَّر إلى ما تحت الشاشة.
    Future<void> reveal(WidgetTester t, Finder f) async {
      if (f.evaluate().isEmpty) {
        await t.scrollUntilVisible(f, 200,
            scrollable: find.byType(Scrollable).first);
      }
      await t.ensureVisible(f.first);
      await t.pumpAndSettle();
    }

    testWidgets('🚨 التقدير الأوّل يقول «موقوف»: تنبيهٌ مكان النموذج، ولا إرسال',
        (t) async {
      server.reply('POST', _quotePath, 503, _offBody);
      await open(t);
      expect(find.textContaining(_banner), findsOneWidget);
      expect(find.textContaining('مراجعة الطلب'), findsNothing);
      expect(find.text('باسورد الإيداع'), findsNothing);
      // الرصيد والسجلّ باقيان.
      expect(find.text('1,250,000'), findsOneWidget);
      expect(find.text('سجلّ الطلبات'), findsOneWidget);
      expect(ElCardOrderGate.open.value, isFalse, reason: 'الباب يُغلق معه');
      expect(server.calls('POST', _orderPath), isEmpty);
      expect(t.takeException(), isNull);
    });

    testWidgets('أُوقف بين المراجعة والإرسال: لا إعادة، والتنبيه مكان النموذج',
        (t) async {
      server.on('POST', _quotePath, (o) => _quote(o.data));
      server.reply('POST', _orderPath, 503, _offBody);
      await open(t);
      expect(ElCardOrderGate.open.value, isTrue, reason: 'التقدير نجح ⇒ مفتوح');
      final pass = find.widgetWithText(TextField, '••••••');
      await reveal(t, pass);
      await t.enterText(pass, _secret);
      await t.pumpAndSettle();
      final review = find.textContaining('مراجعة الطلب');
      await reveal(t, review);
      await t.tap(review);
      await t.pumpAndSettle();
      expect(find.text('تأكيد طلب الكارتات'), findsOneWidget);
      await t.tap(find.textContaining('تأكيد الطلب —'));
      await t.pumpAndSettle();
      expect(server.calls('POST', _orderPath), hasLength(1), reason: 'نداءٌ واحد');
      expect(find.text(_offMsg), findsOneWidget, reason: 'نصّ الخادم');
      expect(find.textContaining(_banner), findsWidgets);
      expect(find.textContaining('مراجعة الطلب'), findsNothing);
      expect(ElCardOrderGate.open.value, isFalse);
      await simDrain(t);
      expect(server.calls('POST', _orderPath), hasLength(1), reason: 'لا إعادة');
    });

    testWidgets('فُتح بالخادم بعدها: سحبٌ للتحديث يعيد النموذج', (t) async {
      server.reply('POST', _quotePath, 503, _offBody);
      await open(t);
      expect(find.textContaining(_banner), findsOneWidget);
      server.on('POST', _quotePath, (o) => _quote(o.data));
      await t.fling(find.byType(ListView).first, const Offset(0, 400), 1200);
      await t.pumpAndSettle();
      expect(find.textContaining(_banner), findsNothing);
      expect(find.textContaining('مراجعة الطلب'), findsOneWidget);
      expect(ElCardOrderGate.open.value, isTrue);
    });
  });
}
