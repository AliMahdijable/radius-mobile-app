import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/extend_sheet.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «خدمة دايني» — فايبر الجزيرة على طريق موقع الشحن (المالك ١٤ نوفمبر: «ولاتنسى التمديد نفس الويب يظهر ويختار اليوم وماعتقد يحتاج
/// عرض طريقة الدفع لان ماكو طرق دفع»). الخادم (e814f1d) يعطي extension-options بـ`pay_rail.on` وباقتين اصطناعيّتين بسعر صفر؛ كان
/// الشيت يعاملهما كباقتين مدفوعتين: رصيد المدير، «0 د.ع»، «طريقة الدفع»، والزرّ معطّلٌ «السعر غير متوفر». الآن: اليوم يُختار
/// ويُرسل بلا مبلغٍ ولا طريقة (method balance يقبله الخادم ولا يقرؤه الطريق)، وسبب خلوّ القائمة من الخادم.
const _v = SimVariant(390, dark: false);
const _idx = '347779';
const _optsPath = '/api/v2/subscribers/$_idx/extension-options';
const _extendPath = '/api/v2/subscribers/$_idx/extend';

Subscriber _sub() => Subscriber.fromJson({
      'idx': _idx,
      'username': 'fiber.user',
      'firstname': 'علي حسن',
      'phone': '07701234567',
      'profile_id': 197,
      'profile_name': 'Speed Plus',
      'expiration': '2026-11-10 18:00:00',
      'remaining_days': -4,
    });

Map<String, dynamic> _railOpts({bool offer = true, String? note}) => {
      'success': true,
      'data': {
        'idx': _idx,
        'current_profile_id': 197,
        'current_profile_name': 'Speed Plus',
        'manager_balance': 7200,
        'reward_points_balance': 0,
        'packages': offer
            ? [
                {'id': 990001, 'name': 'خدمة دايني — يوم واحد', 'price': 0, 'reward_points_required': 0, 'duration': 'يوم واحد'},
                {'id': 990002, 'name': 'خدمة دايني — يومان', 'price': 0, 'reward_points_required': 0, 'duration': 'يومان'},
              ]
            : <Map<String, dynamic>>[],
        'pay_rail': {'on': true, 'ok': true, 'loan_available': offer, 'requires_otp': false, 'balance': 7200},
        'note': note,
      },
    };

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': 'ftth:1460', 'auth.admin_username': 'agent.fiber'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
  });

  tearDown(PermissionsService.debugReset);

  Future<void> open(WidgetTester t) async {
    await pumpSim(t, _v, home: (_) => simLauncher((ctx) => showExtendSheet(ctx, _sub())));
    await simOpen(t);
  }

  testWidgets('«دايني» تُعرض باليوم: بلا رصيدٍ ولا «0 د.ع» ولا طريقة دفع، والزرّ يعمل ⇒ profile_id اليومين + method balance', (t) async {
    server.reply('GET', _optsPath, 200, _railOpts());
    server.reply('POST', _extendPath, 200, {'success': true, 'message': 'تم'});
    await open(t);
    expect(find.text('خدمة دايني (موقع الشحن)'), findsOneWidget);
    expect(find.text('خدمة دايني — يوم واحد'), findsWidgets);
    expect(find.text('خدمة دايني — يومان'), findsOneWidget);
    expect(find.text('sheets.payment_method'.tr()), findsNothing, reason: 'لا طرق دفع لـ«دايني»');
    expect(find.text('الرصيد'), findsNothing);
    expect(find.text('dashboard.manager_balance'.tr()), findsNothing, reason: 'رصيد الموقع لا يُصرف بـ«دايني»');
    expect(find.textContaining('0 د.ع'), findsNothing, reason: '«0 د.ع» تضلّل');
    expect(find.text('بلا كلفة'), findsOneWidget);
    expect(find.textContaining('كلّ مرّةٍ يومٌ يبدأ من الآن'), findsOneWidget);
    expect(find.text('sheets.no_price'.tr()), findsNothing, reason: 'كان الزرّ «السعر غير متوفر» معطّلاً');

    await t.tap(find.text('خدمة دايني — يومان'));
    await t.pumpAndSettle();
    await t.tap(find.text('تمديد الآن'));
    await t.pumpAndSettle();
    final b = server.bodies('POST', _extendPath).single;
    expect([b['profile_id'], b['method']], ['990002', 'balance']);
    await simDrain(t);
  });

  testWidgets('الموقع لا يعرض «دايني» (مشتركٌ فعّال) ⇒ سبب الخادم لا «لا باقات»', (t) async {
    server.reply('GET', _optsPath, 200, _railOpts(offer: false, note: '«خدمة دايني» يعرضها موقع الشحن للمشترك المنتهي وحده'));
    await open(t);
    expect(find.text('«خدمة دايني» يعرضها موقع الشحن للمشترك المنتهي وحده'), findsOneWidget);
    expect(find.text('لا توجد باقات متاحة للتمديد'), findsNothing);
    // الزرّ بمكانه معطّلاً (لا اختيار) — النقر لا يرسل شيئاً
    await t.tap(find.text('تمديد الآن'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(server.calls('POST', _extendPath), isEmpty);
    await simDrain(t);
  });

  testWidgets('ساسٌ بلا الطريق وباقةٌ بسعر صفر ⇒ كما كان: طريقة الدفع بمكانها والزرّ «السعر غير متوفر»', (t) async {
    final opts = _railOpts();
    (opts['data'] as Map).remove('pay_rail');
    server.reply('GET', _optsPath, 200, opts);
    await open(t);
    expect(find.text('sheets.payment_method'.tr()), findsOneWidget);
    expect(find.text('sheets.no_price'.tr()), findsOneWidget);
    expect(server.calls('POST', _extendPath), isEmpty);
    await simDrain(t);
  });
}
