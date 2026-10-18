import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/self_deposit_api.dart';
import 'package:rad_mysvcs/screens/more_modules_screen.dart';
import 'package:rad_mysvcs/screens/topup/topup_pay_page.dart';
import 'package:rad_mysvcs/screens/topup/topup_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/services/self_deposit_sync.dart';

import '../support/fake_pay_engine.dart';
import 'sim_harness.dart';

/// محاكاة «شحن رصيد الصفحة» كما يراها المدير — بالعروض الثلاثة وبالوضعين.
/// اللقطات في `shots/topup/`. السلوك مفحوصٌ في `test/topup_flow_test.dart`؛
/// هنا الرسم: لا فيضان، ولا نصّ تقنيّ أو رابطٌ ظاهر، والأقفال بأسبابها.
const _shot = 'topup';

/// مضيف صفحة الدفع وقفلها في رأسها — دلالة أمانٍ مقصودة (كما في كلّ متصفّح).
final _allowHost = [RegExp(r'^api\.zaincash\.iq$')];

void main() {
  late SimServer server;
  final psid = 'a' * 32;

  setUpAll(simSetUpAll);

  tearDown(() {
    TopupPayPage.debugEngineFactory = null;
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
    SelfDepositState.reset();
    SelfDepositSync.debugReset();
  });

  Future<void> sas({bool employee = false, String? provider}) async {
    server = await simSetUp(secure: {'auth.admin_id': '2251'});
    ProviderService.debugSet(provider);
    PermissionsService.debugSet(isEmployee: employee);
    SelfDepositState.reset();
    TopupPayPage.debugEngineFactory = FakePayEngine.new;
  }

  const zaincash = {
    'id': 3,
    'name': 'ZainCash',
    'type': 'zaincash',
    'flow': 'redirect',
    'in_app': true,
    'min_amount': 1000,
    'max_amount': 5000000,
  };
  const voucher = {'id': 5, 'name': 'SAS Voucher', 'type': 'voucher', 'flow': 'pin', 'in_app': true};
  const tasdid = {
    'id': 7,
    'name': 'Tasdid',
    'type': 'tasdid',
    'flow': 'invoice',
    'in_app': true,
    'min_amount': 1000,
    'max_amount': 5000000,
  };
  const hyperpay = {'id': 9, 'name': 'HyperPay', 'type': 'hyperpay', 'flow': 'external', 'in_app': false};

  Map<String, dynamic> options(List<Map<String, Object?>> methods,
          {Object? supported = true, String? reason}) =>
      {
        'success': true,
        'enabled': true,
        'currency': 'IQD',
        'company': {'code': 'supernet', 'name': 'سوبرنت'},
        'manager': {'username': 'mustafa.alobaidi'},
        'balance': 1246000,
        'supported': supported,
        'reason': reason,
        'methods': methods,
        'panel_url': 'https://sas.example.iq/#/manager/selfDeposit',
      };

  void serve(Map<String, dynamic> opts, {List<Map<String, Object?>> history = const []}) {
    server.reply('GET', '/api/v2/self-deposit/options', 200, opts);
    server.reply('GET', '/api/v2/self-deposit/history', 200,
        {'success': true, 'ready': true, 'items': history});
    server.reply('POST', '/api/v2/self-deposit/request', 200, {
      'success': true,
      'flow': 'redirect',
      'status': 'pending',
      'psid': psid,
      'pay_url': 'https://api.zaincash.iq/transaction/pay?id=ZC77812',
      'pay_ref': 'ZC77812',
      'amount': 25000,
      'capture': {
        'routes': ['/zaincash/process', '/zaincashv2/process'],
        'sas_host': 'sas.example.iq',
      },
    });
  }

  String ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();

  List<Map<String, Object?>> history() => [
        {
          'psid': psid,
          'status': 'success',
          'flow': 'redirect',
          'gateway': 'zaincash',
          'gateway_name': 'ZainCash',
          'amount': 25000,
          'credited': 25000,
          'pay_ref': 'ZC77812',
          'created_at': ago(const Duration(minutes: 1)),
        },
        {
          'psid': 'b' * 32,
          'status': 'pending',
          'flow': 'redirect',
          'gateway': 'zaincash',
          'amount': 250000,
          'pay_ref': 'ZC77790',
          'created_at': ago(const Duration(minutes: 40)),
        },
        {
          'psid': 'c' * 32,
          'status': 'failed',
          'flow': 'pin',
          'gateway': 'voucher',
          'created_at': ago(const Duration(hours: 5)),
        },
        {
          'psid': 'd' * 32,
          'status': 'invoiced',
          'flow': 'invoice',
          'gateway': 'tasdid',
          'amount': 100000,
          'created_at': ago(const Duration(days: 2)),
        },
      ];

  Future<void> open(WidgetTester t, SimVariant v) =>
      pumpSim(t, v, home: (_) => const TopupScreen());

  Future<void> spin(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  /// المبلغ ← «ادفع» ← تأكيد ← صفحة الدفع.
  Future<FakePayEngine> toPayPage(WidgetTester t) async {
    await t.tap(find.text('25,000'));
    await t.pump();
    await t.tap(find.text('ادفع بزين كاش'));
    await t.pumpAndSettle();
    await t.tap(find.text('متابعة للدفع'));
    await spin(t);
    await t.pumpAndSettle();
    return FakePayEngine.last!;
  }

  simCase(_shot, 'zaincash', (t, v) async {
    await sas();
    serve(options([zaincash, voucher, hyperpay]));
    await open(t, v);
    await t.tap(find.text('25,000'));
    await t.pump();
    expect(find.text('ادفع بزين كاش'), findsOneWidget);
    await simCheck(t, v, _shot, 'zaincash');
  });

  simCase(_shot, 'zaincash_confirm', (t, v) async {
    await sas();
    serve(options([zaincash, voucher]));
    await open(t, v);
    await t.tap(find.text('25,000'));
    await t.pump();
    await t.tap(find.text('ادفع بزين كاش'));
    await t.pumpAndSettle();
    expect(find.text('تأكيد الشحن'), findsOneWidget);
    await simCheck(t, v, _shot, 'zaincash_confirm');
  });

  simCase(_shot, 'voucher', (t, v) async {
    await sas();
    serve(options([zaincash, voucher]));
    await open(t, v);
    await t.tap(find.text('كارت تعبئة'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '483920175562');
    await t.pump();
    await simCheck(t, v, _shot, 'voucher');
  });

  simCase(_shot, 'invoice', (t, v) async {
    await sas();
    serve(options([tasdid, voucher]));
    await open(t, v);
    await t.tap(find.text('50,000'));
    await t.pump();
    final fields = find.byType(TextField);
    await t.enterText(fields.at(1), 'مصطفى عبد الأمير العبيدي');
    await t.enterText(fields.at(2), '07812345678');
    await t.pump();
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pumpAndSettle();
    await simCheck(t, v, _shot, 'invoice');
  });

  simCase(_shot, 'pay_page', (t, v) async {
    await sas();
    serve(options([zaincash]));
    await open(t, v);
    await toPayPage(t);
    expect(find.text('الدفع عبر زين كاش'), findsOneWidget);
    await simCheck(t, v, _shot, 'pay_page', allow: _allowHost);
  });

  simCase(_shot, 'pay_close', (t, v) async {
    await sas();
    serve(options([zaincash]));
    await open(t, v);
    await toPayPage(t);
    await t.tap(find.byTooltip('إغلاق'));
    await t.pumpAndSettle();
    expect(find.text('إغلاق صفحة الدفع؟'), findsOneWidget);
    await simCheck(t, v, _shot, 'pay_close', allow: _allowHost);
  });

  simCase(_shot, 'success', (t, v) async {
    await sas();
    serve(options([zaincash, voucher]), history: history());
    server.reply('POST', '/api/v2/self-deposit/complete', 200, {
      'success': true,
      'psid': psid,
      'status': 'success',
      'credited': 25000,
      'amount': 25000,
      'pay_ref': 'ZC77812',
      'balance': 1271000,
      'final': true,
    });
    await open(t, v);
    final engine = await toPayPage(t);
    engine.navigate('https://sas.example.iq/#/zaincash/process?token=aaaa.bbbb.cccc');
    await spin(t);
    await t.pumpAndSettle();
    expect(find.text('تمّت إضافة الرصيد'), findsOneWidget);
    await simCheck(t, v, _shot, 'success');
    await simDrain(t);
  });

  simCase(_shot, 'history', (t, v) async {
    await sas();
    serve(options([zaincash, voucher]), history: history());
    await open(t, v);
    await t.drag(find.byType(ListView), const Offset(0, -900));
    await t.pumpAndSettle();
    expect(find.text('آخر العمليّات'), findsOneWidget);
    await simCheck(t, v, _shot, 'history');
  });

  simCase(_shot, 'closed_early', (t, v) async {
    await sas();
    serve(options([zaincash, voucher]));
    server.reply('GET', '/api/v2/self-deposit/status/$psid', 200, {
      'success': true,
      'psid': psid,
      'status': 'pending',
      'pay_ref': 'ZC77812',
    });
    await open(t, v);
    await toPayPage(t);
    await t.tap(find.byTooltip('إغلاق'));
    await t.pumpAndSettle();
    await t.tap(find.text('إغلاق'));
    await spin(t);
    await t.pumpAndSettle();
    expect(find.text('لم يكتمل الدفع؟'), findsOneWidget);
    await simCheck(t, v, _shot, 'closed_early');
  });

  simCase(_shot, 'bad_pin', (t, v) async {
    await sas();
    serve(options([zaincash, voucher]));
    server.reply('POST', '/api/v2/self-deposit/request', 422, {
      'success': false,
      'code': 'BAD_PIN',
      'message': 'رمز الكارت غير صحيح أو مستعمل — لم يُضَف شيء إلى رصيدك',
      'psid': psid,
      'status': 'failed',
    });
    await open(t, v);
    await t.tap(find.text('كارت تعبئة'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '0000111122');
    await t.pump();
    await t.tap(find.text('تعبئة'));
    await t.pumpAndSettle();
    await t.tap(find.text('تعبئة').last);
    await t.pumpAndSettle();
    expect(find.text('لم تكتمل العمليّة'), findsOneWidget);
    await simCheck(t, v, _shot, 'bad_pin');
  });

  simCase(_shot, 'earthlink', (t, v) async {
    await sas(provider: 'earthlink');
    serve({
      'success': true,
      'enabled': true,
      'supported': false,
      'reason': 'provider',
      'provider': 'earthlink',
      'methods': [],
    });
    await open(t, v);
    expect(find.text('غير متاح لدى ايرث لنك'), findsOneWidget);
    await simCheck(t, v, _shot, 'earthlink');
  });

  simCase(_shot, 'owner_only', (t, v) async {
    await sas(employee: true);
    serve({
      'success': true,
      'enabled': true,
      'supported': false,
      'reason': 'owner_only',
      'methods': [],
    });
    await open(t, v);
    expect(find.text('لصاحب الحساب وحده'), findsOneWidget);
    await simCheck(t, v, _shot, 'owner_only');
  });

  simCase(_shot, 'no_gateways', (t, v) async {
    await sas();
    serve(options(const [], supported: false, reason: 'no_gateways'));
    await open(t, v);
    expect(find.text('لا توجد وسائل دفعٍ إلكترونيّ'), findsOneWidget);
    await simCheck(t, v, _shot, 'no_gateways');
  });

  simCase(_shot, 'more_card', (t, v) async {
    await sas();
    SelfDepositState.debugSet(SelfDepositOptions.fromJson({'enabled': true}));
    await pumpSim(t, v, home: (_) => const MoreModulesScreen());
    expect(find.text('شحن رصيد الصفحة'), findsOneWidget);
    await simCheck(t, v, _shot, 'more_card');
  });

  simCase(_shot, 'more_card_earthlink', (t, v) async {
    await sas(provider: 'earthlink');
    SelfDepositState.debugSet(SelfDepositOptions.fromJson({
      'enabled': true,
      'supported': false,
      'reason': 'provider',
    }));
    await pumpSim(t, v, home: (_) => const MoreModulesScreen());
    expect(find.text('غير متاح لدى ايرث لنك'), findsOneWidget);
    await simCheck(t, v, _shot, 'more_card_earthlink');
  });

  simCase(_shot, 'review_kept', (t, v) async {
    await sas();
    serve(options([zaincash, voucher]));
    server.reply('POST', '/api/v2/self-deposit/complete', 409, {
      'success': false,
      'psid': psid,
      'status': 'unverified',
      'state': 'unverified',
      'flow': 'redirect',
      'code': 'RETURN_UNRECOGNIZED',
      'pay_ref': 'ZC77812',
      'message': 'وصل من صفحة الدفع رجوعٌ لم نستطع التحقّق منه — حفظناه ولم نُرسله للشركة. لا تُعِد الدفع؛ اضغط «تحقّق» بعد دقائق، وإن لم يُضَف الرصيد فتواصل مع الشركة برقم العمليّة ZC77812',
      'final': false,
      'received': true,
      'kept': true,
    });
    await open(t, v);
    final engine = await toPayPage(t);
    engine.navigate('https://10.0.0.5/zaincash/process?token=aaaa.bbbb.cccc');
    await spin(t);
    await t.pumpAndSettle();
    expect(find.text('تعذّر التأكّد من النتيجة'), findsOneWidget);
    await simCheck(t, v, _shot, 'review_kept');
    await simDrain(t);
  });

  simCase(_shot, 'paused', (t, v) async {
    await sas();
    serve({
      'success': true,
      'enabled': true,
      'paused': true,
      'supported': false,
      'reason': 'paused',
      'open_count': 2,
      'message': 'عمليّاتك التي لم تُحسم تُتابَع هنا — ولا عمليّات شحنٍ جديدة الآن',
      'methods': [],
      'balance': null,
    }, history: [
      {
        'psid': psid,
        'status': 'unverified',
        'flow': 'redirect',
        'gateway': 'zaincash',
        'amount': 25000,
        'pay_ref': 'ZC77812',
        'code': 'PAID_NOT_CREDITED',
        'final': false,
        'created_at': ago(const Duration(minutes: 20)),
      },
      {
        'psid': 'e' * 32,
        'status': 'expired',
        'flow': 'redirect',
        'gateway': 'zaincash',
        'amount': 50000,
        'pay_ref': 'ZC77801',
        'code': 'WEBHOOK_TIMEOUT',
        'final': false,
        'created_at': ago(const Duration(days: 1, hours: 2)),
      },
    ]);
    await open(t, v);
    expect(find.text('الشحن متوقّفٌ مؤقّتاً'), findsOneWidget);
    expect(find.text('آخر العمليّات'), findsOneWidget);
    await simCheck(t, v, _shot, 'paused');
  });

  simCase(_shot, 'more_card_el_employee', (t, v) async {
    await sas(employee: true, provider: 'earthlink');
    SelfDepositState.debugSet(SelfDepositOptions.fromJson({
      'enabled': true,
      'supported': false,
      'reason': 'provider',
      'provider': 'earthlink',
      'employee': true,
    }));
    await pumpSim(t, v, home: (_) => const MoreModulesScreen());
    expect(find.text('غير متاح لدى ايرث لنك'), findsOneWidget);
    await simCheck(t, v, _shot, 'more_card_el_employee');
  });

  simCase(_shot, 'more_card_paused', (t, v) async {
    await sas();
    SelfDepositState.debugSet(SelfDepositOptions.fromJson(
        {'enabled': true, 'paused': true, 'supported': false, 'reason': 'paused'}));
    await pumpSim(t, v, home: (_) => const MoreModulesScreen());
    expect(find.text('متوقّف مؤقّتاً — تابِع عمليّاتك التي لم تُحسم'), findsOneWidget);
    await simCheck(t, v, _shot, 'more_card_paused');
  });
}
