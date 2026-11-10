import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «الأمر الصوتي ٢» (١٠ نوفمبر — المالك: «تفعيل جزئي»): ما قاله الوكيل («جزئي ١٠ الاف»، «نقد»، «بالكارت»، «شهرين») يظهر
/// **مختاراً** بشاشة التفعيل وبسطرٍ يقول من أين جاء — ولا يُرسل شيءٌ حتى يضغط بنفسه، وما يُرسل هو ما على الشاشة حرفاً.
/// وما لا تعرضه الشاشة (كارتٌ بلا صلاحيّته، أشهرٌ لشركةٍ دورتها واحدة) لا يُختار ويُقال.
const _v = SimVariant(390, dark: false);
const _idx = '55';

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'owner'});
    PermissionsService.debugSet(isEmployee: false);
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  Map<String, dynamic> sas({bool card = false, int? cards}) => {
        'success': true,
        'data': {
          'user_price': 35000,
          'price_after_discount': 35000,
          'profile_name': 'Fiber 35',
          'profile_duration': '30',
          'current_balance': 0,
          'manager_balance': 900000,
          if (card) 'activation_methods': {'credit': true, 'card': true},
          if (card) 'cards': {'enabled': true, 'profile_id': 7, 'profile_name': 'Fiber 35', 'available': cards ?? 4},
        },
      };

  Future<void> open(WidgetTester t, ActivatePrefill? prefill) async {
    final sub = Subscriber.fromJson(
        {'idx': _idx, 'username': 'ali.hussein', 'firstname': 'علي', 'lastname': 'حسين', 'profile_id': 7, 'profile_name': 'Fiber 35'});
    await pumpSim(t, _v,
        home: (_) => Scaffold(
              body: Builder(
                  builder: (c) => Center(
                      child: TextButton(
                          onPressed: () => showActivateSheet(c, sub, prefill: prefill), child: const Text('open')))),
            ));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
  }

  String note(WidgetTester t, String key) {
    final w = find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text));
    return t.widget<Text>(w.first).data ?? '';
  }

  Future<Map<String, dynamic>> submit(WidgetTester t) async {
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {'success': true, 'message': 'ok'});
    await t.tap(find.text('تجديد الآن'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    return server.bodies('POST', '/api/v2/subscribers/$_idx/activate').single;
  }

  testWidgets('«جزئي ١٠ الاف»: الجزئيّ مختارٌ والمبلغ بخانته وسطرٌ يقول مصدره — لا إرسال قبل ضغطته، وما يُرسل ما على الشاشة',
      (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, sas());
    await open(t, const ActivatePrefill(pay: ActivatePrefillPay.partial, paid: 10000));
    expect(note(t, 'activate-voice-note'), contains('جزئي'));
    expect(note(t, 'activate-voice-note'), contains('10,000'));
    expect(find.byWidgetPredicate((w) => w is TextField && (w.controller?.text ?? '') == '10,000'), findsOneWidget,
        reason: 'المدفوع بخانة «المبلغ المدفوع نقداً»');
    expect(find.textContaining('25,000'), findsWidgets, reason: 'الدين بعد التفعيل = السعر − المدفوع');
    expect(server.calls('POST', '/api/v2/subscribers/$_idx/activate'), isEmpty, reason: 'الشاشة لا تفعّل بنفسها');
    final body = await submit(t);
    expect(body['paymentType'], 'partial-cash');
    expect(body['partialAmount'], 10000);
    await simDrain(t);
  });

  testWidgets('الوكيل يصحّح ما قيل قبل الضغط: يختار «نقدي» ⇒ يُرسل نقديّاً بلا مبلغٍ جزئيّ', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, sas());
    await open(t, const ActivatePrefill(pay: ActivatePrefillPay.partial, paid: 10000));
    await t.tap(find.text('نقدي'));
    await t.pumpAndSettle();
    final body = await submit(t);
    expect(body['paymentType'], 'cash');
    expect(body['partialAmount'], isNull);
    await simDrain(t);
  });

  testWidgets('«نقد» و«دين» مختاران كما قيلا؛ وجزئيٌّ بمبلغٍ = السعر كلّه نقديّ؛ وجزئيٌّ بلا مبلغ لا يُرسل حتى يُكتب', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, sas());
    await open(t, const ActivatePrefill(pay: ActivatePrefillPay.cash));
    expect(note(t, 'activate-voice-note'), contains('نقدي'));
    expect((await submit(t))['paymentType'], 'cash');
    await simDrain(t);

    server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'owner'});
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, sas());
    await open(t, const ActivatePrefill(pay: ActivatePrefillPay.partial, paid: 35000));
    expect(note(t, 'activate-voice-note'), contains('نقدي'), reason: 'المدفوع = السعر');
    final full = await submit(t);
    expect([full['paymentType'], full['partialAmount']], ['cash', null]);
    await simDrain(t);

    server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'owner'});
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, sas());
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {'success': true});
    await open(t, const ActivatePrefill(pay: ActivatePrefillPay.partial));
    expect(note(t, 'activate-voice-note'), contains('اكتب المدفوع'));
    await t.tap(find.text('تجديد الآن'));
    await t.pump(const Duration(milliseconds: 400));
    expect(server.calls('POST', '/api/v2/subscribers/$_idx/activate'), isEmpty, reason: 'جزئيٌّ بلا مبلغ ⇒ الزرّ معطَّل كما كان');
    await simDrain(t);
  });

  testWidgets('مدفوعٌ مسموعٌ أكبر من السعر كلّه (سمعٌ خاطئ غالباً) لا يُملأ: الجزئيّ مختار والمبلغ يكتبه بيده — ولا إرسال بلاه', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, sas());
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {'success': true});
    await open(t, const ActivatePrefill(pay: ActivatePrefillPay.partial, paid: 500000));
    expect(note(t, 'activate-voice-skipped'), contains('أكبر من السعر'));
    expect(find.byWidgetPredicate((w) => w is TextField && (w.controller?.text ?? '').contains('500')), findsNothing);
    await t.tap(find.text('تجديد الآن'));
    await t.pump(const Duration(milliseconds: 400));
    expect(server.calls('POST', '/api/v2/subscribers/$_idx/activate'), isEmpty, reason: 'لا رصيدٌ يُخترع من سمعٍ خاطئ');
    await simDrain(t);
  });

  testWidgets('بلا شيءٍ قيل: الشاشة كما كانت حرفاً — «دين» افتراضيّ ولا سطر', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, sas());
    await open(t, null);
    expect(find.byKey(const ValueKey('activate-voice-note')), findsNothing);
    expect(find.byKey(const ValueKey('activate-voice-skipped')), findsNothing);
    expect((await submit(t))['paymentType'], 'non-cash');
    await simDrain(t);
  });

  testWidgets('«بالكارت»: يُختار حين يسمح به الخادم — ويُرسل كارتاً بضغطته', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, sas(card: true));
    await open(t, const ActivatePrefill(method: ActivatePrefillMethod.card, pay: ActivatePrefillPay.cash));
    expect(note(t, 'activate-voice-note'), contains('كارت'));
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {'success': true, 'message': 'ok'});
    expect(server.calls('POST', '/api/v2/subscribers/$_idx/activate'), isEmpty);
    await t.tap(find.text('cards.renew_with_card'.tr()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    final body = server.bodies('POST', '/api/v2/subscribers/$_idx/activate').single;
    expect([body['method'], body['paymentType']], ['card', 'cash']);
    await simDrain(t);
  });

  testWidgets('«بالكارت» بلا صلاحيّته: لا يُختار ويُقال — والرصيد يبقى مصدر المال', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, sas());
    await open(t, const ActivatePrefill(method: ActivatePrefillMethod.card));
    expect(note(t, 'activate-voice-skipped'), contains('الكارت غير متاح'));
    expect(find.byKey(const ValueKey('activate-voice-note')), findsNothing);
    final body = await submit(t);
    expect(body['method'], isNot('card'), reason: 'مصدر المال لا يتبدّل بما لا تعرضه الشاشة');
    await simDrain(t);
  });

  testWidgets('«شهرين»: لشركةٍ دورتها واحدة لا تُختار وتُقال؛ ولشركةٍ تعرض الأشهر تُختار وتُعاين كلفتها', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, sas());
    await open(t, const ActivatePrefill(months: 2, pay: ActivatePrefillPay.debt));
    expect(note(t, 'activate-voice-skipped'), contains('شهران'));
    expect(note(t, 'activate-voice-note'), contains('دين'));
    final body = await submit(t);
    expect(body['months'], isNull);
    await simDrain(t);

    server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
    ProviderService.debugSet('watani', label: 'المشروع الوطني');
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, {
      'success': true,
      'data': {
        'idx': _idx, 'username': 'ali.hussein', 'profile_name': 'BASIC', 'profile_id': 11, 'user_price': 40000,
        'price_after_discount': 40000, 'base_price': 40000, 'current_balance': 0, 'manager_balance': 478063,
        'provider': 'watani', 'provider_label': 'المشروع الوطني',
        'packages': [
          {'id': 11, 'name': 'BASIC', 'price': 40000, 'cost': 35000, 'days': 30}
        ],
        'package_change_allowed': false, 'package_change_timing': ['now'],
        'months_options': [1, 2, 3],
      },
    });
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-quote', 200, {
      'success': true,
      'data': {'months': 2, 'cost': 70000, 'price': 80000, 'monthly_price': 40000},
    });
    await open(t, const ActivatePrefill(months: 2));
    expect(note(t, 'activate-voice-note'), contains('شهران'));
    expect(server.calls('GET', '/api/v2/subscribers/$_idx/activation-quote').single.queryParameters['months'], 2,
        reason: 'معاينة الشهرين من الشركة كما لو اختارهما بيده');
    expect(find.textContaining('80,000'), findsWidgets);
    await simDrain(t);
  });
}
