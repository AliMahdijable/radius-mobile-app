import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/self_deposit_api.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/screens/more_modules_screen.dart';
import 'package:rad_mysvcs/screens/topup/topup_pay_page.dart';
import 'package:rad_mysvcs/screens/topup/topup_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/services/self_deposit_pending.dart';
import 'package:rad_mysvcs/services/self_deposit_sync.dart';

import 'sim_el/sim_harness.dart';
import 'support/fake_pay_engine.dart';

/// «شحن رصيد الصفحة» من أوّله لآخره أمام خادمٍ وهميّ ومتصفّحٍ بديل.
///
/// ⚠️ **المال:** الرجوع إلى الساس يُلتقط فلا يُحمَّل، ويُحفظ على الهاتف **قبل**
/// إرساله، ولا يُمحى إلّا بحكم الخادم — فانقطاع النت لحظة الرجوع لا يُضيع
/// دفعةً. وما لم يُحسم لا يُقال «فشل».
void main() {
  const v = SimVariant(390, dark: false);
  final psid = 'a' * 32;
  const payUrl = 'https://api.zaincash.iq/transaction/pay?id=ZC1';
  const ret = 'https://sas.example.iq/#/zaincash/process?token=aaaa.bbbb.cccc';
  late SimServer server;

  setUpAll(simSetUpAll);

  Future<void> setUpSas() async {
    server = await simSetUp(secure: {'auth.admin_id': '2251'});
    ProviderService.debugSet(null);
    PermissionsService.debugSet(isEmployee: false);
    SelfDepositState.reset();
    TopupPayPage.debugEngineFactory = FakePayEngine.new;
    FakePayEngine.last = null;
    SelfDepositSync.debugReset();
    // الإعادة المتباعدة بمؤقّتات حقيقيّة — لها اختبارها (self_deposit_api_test)؛ هنا بلاها فالعدّ ثابت.
    SelfDepositSync.retryDelays = const [];
  }

  tearDown(() {
    TopupPayPage.debugEngineFactory = null;
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
    SelfDepositState.reset();
    SelfDepositSync.debugReset();
    SelfDepositSync.retryDelays = const [
      Duration(seconds: 20),
      Duration(minutes: 1),
      Duration(minutes: 3),
      Duration(minutes: 10),
    ];
  });

  Map<String, dynamic> options({
    List<Map<String, Object?>>? methods,
    Object? supported = true,
    String? reason,
    num? balance = 46000,
  }) =>
      {
        'success': true,
        'enabled': true,
        'currency': 'IQD',
        'company': {'code': 'supernet', 'name': 'سوبرنت'},
        'manager': {'username': 'ali'},
        'balance': balance,
        'supported': supported,
        'reason': reason,
        'methods': methods ??
            [
              {
                'id': 3,
                'name': 'ZainCash',
                'type': 'zaincash',
                'flow': 'redirect',
                'in_app': true,
                'min_amount': 1000,
                'max_amount': 5000000,
              },
              {'id': 5, 'name': 'SAS Voucher', 'type': 'voucher', 'flow': 'pin', 'in_app': true},
            ],
      };

  void serve({Map<String, dynamic>? opts}) {
    server.reply('GET', '/api/v2/self-deposit/options', 200, opts ?? options());
    server.reply('GET', '/api/v2/self-deposit/history', 200,
        {'success': true, 'ready': true, 'items': []});
    server.reply('POST', '/api/v2/self-deposit/request', 200, {
      'success': true,
      'flow': 'redirect',
      'status': 'pending',
      'psid': psid,
      'pay_url': payUrl,
      'pay_ref': 'ZC1',
      'amount': 25000,
      'capture': {
        'routes': ['/zaincash/process', '/zaincashv2/process'],
        'sas_host': 'sas.example.iq',
      },
    });
  }

  Map<String, dynamic> success() => {
        'success': true,
        'psid': psid,
        'status': 'success',
        'flow': 'redirect',
        'credited': 25000,
        'amount': 25000,
        'pay_ref': 'ZC1',
        'balance': 71000,
        'final': true,
      };

  /// المبلغ ← «ادفع» ← تأكيد ← صفحة الدفع.
  Future<FakePayEngine> openPayPage(WidgetTester t) async {
    await t.tap(find.text('25,000'));
    await t.pump();
    await t.tap(find.text('ادفع بزين كاش'));
    await t.pumpAndSettle();
    expect(find.text('تأكيد الشحن'), findsOneWidget);
    await t.tap(find.text('متابعة للدفع'));
    // الطلب ثمّ قيد العمليّة في الخزنة ثمّ دفع الصفحة — وأوّل إطارٍ لها خارج
    // المسرح (قياس الأبطال) فيلزمه إطارٌ ثانٍ.
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    expect(find.byType(TopupPayPage), findsOneWidget);
    return FakePayEngine.last!;
  }

  Future<void> settleSpin(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('🚨 زين كاش: الرجوع يُلتقط ولا يُحمَّل، ويُحفظ قبل إرساله، ثمّ يُضاف الرصيد',
      (t) async {
    await setUpSas();
    serve();
    server.hold('POST', '/api/v2/self-deposit/complete');
    server.reply('POST', '/api/v2/self-deposit/complete', 200, success());
    await pumpSim(t, v, home: (_) => const TopupScreen());
    expect(simText('46,000'), findsOneWidget);
    expect(simText('ali · سوبرنت'), findsOneWidget);

    final engine = await openPayPage(t);
    expect(server.bodies('POST', '/api/v2/self-deposit/request').single,
        {'method_id': 3, 'amount': 25000, 'client': 'app'});
    expect(engine.opened.single.toString(), payUrl);
    expect(engine.wipes, 1, reason: 'لا كوكيز زين كاش من جلسةٍ سابقة');
    expect(find.text('الدفع عبر زين كاش'), findsOneWidget);
    expect(simText('api.zaincash.iq'), findsOneWidget);

    // صفحات زين كاش تمضي، والتطبيقات الخارجيّة تُمنع.
    expect(engine.navigate('https://api.zaincash.iq/transaction/otp'), isTrue);
    expect(engine.navigate('intent://pay#Intent;scheme=zaincash;end'), isFalse);
    await t.pump();

    // الرجوع إلى الساس: يُمنع تحميله ويُلتقط.
    expect(engine.navigate(ret), isFalse);
    await settleSpin(t);
    expect(find.text('الدفع عبر زين كاش'), findsNothing, reason: 'أُغلقت الصفحة');

    // التأكيد في الطريق — والتوكن محفوظٌ سلفاً.
    final stored = await SelfDepositPendingStore.forAdmin('2251');
    expect(stored.single.psid, psid);
    expect(stored.single.returnUrl, ret);
    expect(server.bodies('POST', '/api/v2/self-deposit/complete').single,
        {'psid': psid, 'return_url': ret, 'client': 'app'});

    server.release('POST', '/api/v2/self-deposit/complete');
    await t.pumpAndSettle();
    expect(find.text('تمّت إضافة الرصيد'), findsOneWidget);
    expect(simText('أُضيف 25,000 د.ع إلى رصيد صفحتك.'), findsOneWidget);
    expect(simText('رصيدك الآن 71,000 د.ع'), findsOneWidget);
    expect(simText('71,000'), findsOneWidget, reason: 'الرأس بالرصيد الجديد');
    expect(await SelfDepositPendingStore.forAdmin('2251'), isEmpty);
    expect(engine.wipes, 2, reason: 'يُمحى بعد الإغلاق أيضاً');
    expect(server.calls('POST', '/api/v2/self-deposit/complete'), hasLength(1));
    await simDrain(t);
  });

  testWidgets('🚨 الرجوع بلا نت: يُعاد ثلاثاً، يبقى محفوظاً، ويُسلَّم عند الفتح التالي',
      (t) async {
    await setUpSas();
    serve();
    server.on('POST', '/api/v2/self-deposit/complete', simTimeout);
    await pumpSim(t, v, home: (_) => const TopupScreen());
    final engine = await openPayPage(t);
    expect(engine.navigate(ret), isFalse);
    await settleSpin(t);
    await t.pump(const Duration(seconds: 3));
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(server.calls('POST', '/api/v2/self-deposit/complete'), hasLength(3));
    expect(find.text('لم يصل التأكيد بعد'), findsOneWidget);
    expect(find.text('لم تكتمل العمليّة'), findsNothing, reason: 'لا «فشل» بلا حكم');
    expect((await SelfDepositPendingStore.forAdmin('2251')).single.returnUrl, ret);

    // فتحٌ لاحق والخادم عاد: يُسلَّم الرجوع المحفوظ ويُحسم.
    server.reply('POST', '/api/v2/self-deposit/complete', 200, success());
    await pumpSim(t, v, home: (_) => const TopupScreen(key: ValueKey('again')));
    await t.pumpAndSettle();
    expect(server.calls('POST', '/api/v2/self-deposit/complete'), hasLength(4));
    expect(find.text('أُضيف رصيد دفعتك السابقة'), findsOneWidget);
    expect(await SelfDepositPendingStore.forAdmin('2251'), isEmpty);
    await simDrain(t);
  });

  testWidgets('الإغلاق قبل الرجوع يُسأل عنه، ثمّ «لم يكتمل الدفع؟» و«تحقّق الآن»',
      (t) async {
    await setUpSas();
    serve();
    server.reply('GET', '/api/v2/self-deposit/status/$psid', 200, {
      'success': true,
      'psid': psid,
      'status': 'pending',
      'state': 'redirected',
      'pay_ref': 'ZC1',
      'message': 'بانتظار إكمال الدفع في صفحة زين كاش',
    });
    await pumpSim(t, v, home: (_) => const TopupScreen());
    await openPayPage(t);

    // رجوع أندرويد لا يُغلقها بلا سؤال.
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('إغلاق صفحة الدفع؟'), findsOneWidget);
    await t.tap(find.text('متابعة الدفع'));
    await t.pumpAndSettle();
    expect(find.text('الدفع عبر زين كاش'), findsOneWidget, reason: 'بقيت مفتوحة');

    await t.tap(find.byTooltip('إغلاق'));
    await t.pumpAndSettle();
    await t.tap(find.text('إغلاق'));
    await settleSpin(t);
    await t.pumpAndSettle();
    final q = server.calls('GET', '/api/v2/self-deposit/status/$psid').single;
    expect(q.queryParameters['check'], 1);
    expect(find.text('لم يكتمل الدفع؟'), findsOneWidget);
    expect(simText('رقم العمليّة: ZC1'), findsOneWidget);

    // دُفع فعلاً (أكّده الساس بعد دقائق).
    server.reply('GET', '/api/v2/self-deposit/status/$psid', 200,
        {...success(), 'balance': null, 'balance_after': 71000});
    await t.tap(find.text('تحقّق الآن'));
    await t.pumpAndSettle();
    expect(find.text('تمّت إضافة الرصيد'), findsOneWidget);
    expect(await SelfDepositPendingStore.forAdmin('2251'), isEmpty);
    await simDrain(t);
  });

  testWidgets('🚨 الرجوع يصل وسؤال الإغلاق مفتوح: تُغلق الصفحة ويُسلَّم الرجوع (لا تعلق)',
      (t) async {
    await setUpSas();
    serve();
    server.reply('POST', '/api/v2/self-deposit/complete', 200, success());
    await pumpSim(t, v, home: (_) => const TopupScreen());
    final engine = await openPayPage(t);
    await t.tap(find.byTooltip('إغلاق'));
    await t.pumpAndSettle();
    expect(find.text('إغلاق صفحة الدفع؟'), findsOneWidget);
    // دفع وزين كاش رجع والسؤال ما زال فوق الصفحة.
    expect(engine.navigate(ret), isFalse);
    await settleSpin(t);
    await t.pumpAndSettle();
    expect(find.text('إغلاق صفحة الدفع؟'), findsNothing);
    expect(find.byType(TopupPayPage), findsNothing, reason: 'لا صفحةٌ عالقة');
    expect(find.text('تمّت إضافة الرصيد'), findsOneWidget);
    expect(server.calls('POST', '/api/v2/self-deposit/complete'), hasLength(1));
    expect(server.calls('GET', '/api/v2/self-deposit/status/$psid'), isEmpty);
    await simDrain(t);
  });

  testWidgets('كارت التعبئة: الرمز بلا مسافات، والخاطئ حكمٌ برسالة الخادم ويُمسح',
      (t) async {
    await setUpSas();
    serve();
    server.reply('POST', '/api/v2/self-deposit/request', 422, {
      'success': false,
      'code': 'BAD_PIN',
      'message': 'رمز الكارت غير صحيح أو مستعمل — لم يُضَف شيء إلى رصيدك',
      'psid': psid,
      'status': 'failed',
    });
    await pumpSim(t, v, home: (_) => const TopupScreen());
    await t.tap(find.text('كارت تعبئة'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '1234 5678 9012');
    await t.pump();
    await t.tap(find.text('تعبئة'));
    await t.pumpAndSettle();
    expect(find.text('تعبئة بالكارت'), findsOneWidget);
    await t.tap(find.text('تعبئة').last);
    await t.pumpAndSettle();
    expect(server.bodies('POST', '/api/v2/self-deposit/request').single,
        {'method_id': 5, 'pin': '123456789012', 'client': 'app'});
    expect(find.text('لم تكتمل العمليّة'), findsOneWidget);
    expect(find.text('رمز الكارت غير صحيح أو مستعمل — لم يُضَف شيء إلى رصيدك'),
        findsOneWidget);
    final field = t.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(server.calls('POST', '/api/v2/self-deposit/complete'), isEmpty);
    await simDrain(t);
  });

  testWidgets('كارت التعبئة الصحيح: المضاف والرصيد الجديد', (t) async {
    await setUpSas();
    serve();
    server.reply('POST', '/api/v2/self-deposit/request', 200, {
      'success': true,
      'flow': 'done',
      'status': 'success',
      'psid': psid,
      'credited': 50000,
      'balance': 96000,
    });
    await pumpSim(t, v, home: (_) => const TopupScreen());
    await t.tap(find.text('كارت تعبئة'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '12345678');
    await t.pump();
    await t.tap(find.text('تعبئة'));
    await t.pumpAndSettle();
    await t.tap(find.text('تعبئة').last);
    await t.pumpAndSettle();
    expect(find.text('تمّت إضافة الرصيد'), findsOneWidget);
    expect(simText('أُضيف 50,000 د.ع إلى رصيد صفحتك.'), findsOneWidget);
    expect(simText('96,000'), findsOneWidget);
    await simDrain(t);
  });


  testWidgets('🚨 رفضٌ بلا صفّ (٤٠٤) لا يمحو رابط الرجوع: «تعذّر التأكّد» ويبقى محفوظاً', (t) async {
    await setUpSas();
    serve();
    server.reply('POST', '/api/v2/self-deposit/complete', 404,
        {'success': false, 'code': 'NOT_FOUND', 'message': 'العمليّة غير موجودة'});
    await pumpSim(t, v, home: (_) => const TopupScreen());
    final engine = await openPayPage(t);
    expect(engine.navigate(ret), isFalse);
    await settleSpin(t);
    await t.pumpAndSettle();
    expect(find.text('لم تكتمل العمليّة'), findsNothing, reason: 'لا «فشل» بلا حكم');
    expect(find.text('تعذّر التأكّد من النتيجة'), findsOneWidget);
    expect((await SelfDepositPendingStore.forAdmin('2251')).single.returnUrl, ret,
        reason: 'الدليل الوحيد على الدفع لا يُمحى بردٍّ بلا صفّ');
    await simDrain(t);
  });

  testWidgets('🚨 الخادم حفظ رجوعاً لا يعرفه للمراجعة (received) ⇒ يُمحى من الهاتف وتُعرض رسالته', (t) async {
    await setUpSas();
    serve();
    server.reply('POST', '/api/v2/self-deposit/complete', 409, {
      'success': false,
      'psid': psid,
      'status': 'unverified',
      'state': 'unverified',
      'flow': 'redirect',
      'code': 'RETURN_UNRECOGNIZED',
      'pay_ref': 'ZC1',
      'message': 'وصل من صفحة الدفع رجوعٌ لم نستطع التحقّق منه — حفظناه ولم نُرسله للشركة. لا تُعِد الدفع.',
      'final': false,
      'received': true,
      'kept': true,
    });
    await pumpSim(t, v, home: (_) => const TopupScreen());
    final engine = await openPayPage(t);
    expect(engine.navigate(ret), isFalse);
    await settleSpin(t);
    await t.pumpAndSettle();
    expect(find.text('تعذّر التأكّد من النتيجة'), findsOneWidget);
    expect(find.textContaining('حفظناه ولم نُرسله للشركة'), findsOneWidget);
    expect(await SelfDepositPendingStore.forAdmin('2251'), isEmpty, reason: 'الخادم صار حامل الدليل');
    await simDrain(t);
  });

  testWidgets('🚨 خمس دفعاتٍ ملتقطة لم تُسلَّم ⇒ تُسلَّم **كلّها** عند فتح الشاشة (لا أحدث ثلاث)', (t) async {
    await setUpSas();
    serve();
    for (var i = 0; i < 5; i++) {
      await SelfDepositPendingStore.put(SelfDepositPending(
        psid: '$i' * 32,
        adminId: '2251',
        createdAt: DateTime.now().subtract(Duration(minutes: 10 - i)),
        amount: 10000,
        methodLabel: 'زين كاش',
        returnUrl: 'https://sas.example.iq/#/zaincash/process?token=t$i.aaaa.bbbb',
      ));
    }
    server.on('POST', '/api/v2/self-deposit/complete', (o) {
      final id = (o.data as Map)['psid'] as String;
      return SimReply(200, {...success(), 'psid': id});
    });
    await pumpSim(t, v, home: (_) => const TopupScreen());
    await t.pumpAndSettle();
    expect(server.calls('POST', '/api/v2/self-deposit/complete'), hasLength(5));
    expect(await SelfDepositPendingStore.forAdmin('2251'), isEmpty);
    expect(find.text('أُضيف رصيد دفعتك السابقة'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('«متوقّفٌ مؤقّتاً»: سجلّ العمليّات و«تحقّق» بلا نموذجٍ ولا رصيد — والدفعة الملتقطة تُسلَّم', (t) async {
    await setUpSas();
    server.reply('GET', '/api/v2/self-deposit/options', 200, {
      'success': true, 'enabled': true, 'paused': true, 'supported': false, 'reason': 'paused', 'open_count': 1,
      'message': 'عمليّاتك التي لم تُحسم تُتابَع هنا — ولا عمليّات شحنٍ جديدة الآن',
      'methods': [], 'balance': null,
    });
    server.reply('GET', '/api/v2/self-deposit/history', 200, {
      'success': true,
      'items': [
        {'psid': psid, 'status': 'expired', 'state': 'expired', 'flow': 'redirect', 'gateway': 'zaincash',
         'amount': 25000, 'pay_ref': 'ZC1', 'code': 'WEBHOOK_TIMEOUT', 'final': false,
         'message': 'لم يصلنا تأكيد زين كاش خلال يوم — اضغط «تحقّق» لمراجعة سجلّ الشركة',
         'created_at': DateTime.now().toUtc().toIso8601String()},
      ],
    });
    server.reply('GET', '/api/v2/self-deposit/status/$psid', 200, success());
    await pumpSim(t, v, home: (_) => const TopupScreen());
    await t.pumpAndSettle();
    expect(find.text('الشحن متوقّفٌ مؤقّتاً'), findsOneWidget);
    expect(find.text('طريقة الشحن'), findsNothing);
    expect(find.text('رصيد صفحتك'), findsNothing);
    // صفّ السجلّ كلّه زرّ «تحقّق» (أيقونة التحديث) — «انتهت المهلة» تُراجَع.
    final checkBtn = find.byIcon(LucideIcons.refreshCw);
    expect(checkBtn, findsOneWidget, reason: '«انتهت المهلة» تُراجَع بـ«تحقّق»');
    await t.tap(checkBtn);
    await t.pumpAndSettle();
    final q = server.calls('GET', '/api/v2/self-deposit/status/$psid').single;
    expect(q.queryParameters['check'], 1);
    expect(find.text('تمّت إضافة الرصيد'), findsOneWidget);
    expect(server.calls('POST', '/api/v2/self-deposit/request'), isEmpty);
    await simDrain(t);
  });

  group('المقفل لا يطلب شيئاً ويقول سببه', () {
    Future<void> check(WidgetTester t, Map<String, dynamic> opts, String title,
        {bool owner = true}) async {
      server.reply('GET', '/api/v2/self-deposit/options', 200, opts);
      server.reply('GET', '/api/v2/self-deposit/history', 200,
          {'success': true, 'items': []});
      await pumpSim(t, v, home: (_) => const TopupScreen());
      expect(find.text(title), findsOneWidget);
      expect(find.text('طريقة الشحن'), findsNothing);
      expect(server.calls('POST', '/api/v2/self-deposit/request'), isEmpty);
      if (!owner) {
        expect(server.calls('GET', '/api/v2/self-deposit/history'), isEmpty);
      }
    }

    testWidgets('موظّف: لصاحب الحساب وحده', (t) async {
      await setUpSas();
      PermissionsService.debugSet(isEmployee: true);
      await check(
          t,
          {
            'success': true,
            'enabled': true,
            'supported': false,
            'reason': 'owner_only',
            'methods': [],
          },
          'لصاحب الحساب وحده',
          owner: false);
    });

    testWidgets('🚨 مالك ايرث لنك: «غير متاح لدى ايرث لنك»', (t) async {
      await setUpSas();
      ProviderService.debugSet('earthlink');
      await check(
          t,
          {
            'success': true,
            'enabled': true,
            'supported': false,
            'reason': 'provider',
            'provider': 'earthlink',
            'methods': [],
          },
          'غير متاح لدى ايرث لنك',
          owner: false);
    });

    testWidgets('صفحةٌ بلا «ايداع مالي» في الساس', (t) async {
      await setUpSas();
      await check(t, options(supported: false, reason: 'no_permission', methods: []),
          'صفحتك بلا صلاحيّة «ايداع مالي»');
    });

    testWidgets('شركةٌ بلا وسائل دفع', (t) async {
      await setUpSas();
      await check(t, options(supported: false, reason: 'no_gateways', methods: []),
          'لا توجد وسائل دفعٍ إلكترونيّ');
    });

    testWidgets('الساس لم يردّ: «تعذّر قراءة وسائل الدفع» لا «غير مدعوم»', (t) async {
      await setUpSas();
      await check(t, options(supported: null, reason: 'read_failed', methods: [], balance: null),
          'تعذّر قراءة وسائل الدفع');
      expect(simText('—'), findsOneWidget, reason: 'رصيدٌ مجهول لا صفر');
    });
  });

  group('بطاقة «قوائم أخرى»', () {
    final card = find.text('شحن رصيد الصفحة', skipOffstage: false);

    testWidgets('🚨 الميزة مطفأة (الافتراضيّ في الإنتاج): لا بطاقة، وسؤالٌ واحد probe',
        (t) async {
      await setUpSas();
      server.reply('GET', '/api/v2/self-deposit/options', 200,
          {'success': true, 'enabled': false});
      await pumpSim(t, v, home: (_) => const MoreModulesScreen());
      await t.pumpAndSettle();
      expect(card, findsNothing);
      final calls = server.calls('GET', '/api/v2/self-deposit/options');
      expect(calls, hasLength(1));
      expect(calls.single.queryParameters['probe'], 1);
    });

    testWidgets('خادمٌ أقدم بلا المسار (٤٠٤): لا بطاقة', (t) async {
      await setUpSas();
      await pumpSim(t, v, home: (_) => const MoreModulesScreen());
      await t.pumpAndSettle();
      expect(card, findsNothing);
    });

    testWidgets('مفتوحة: البطاقة تفتح الشاشة', (t) async {
      await setUpSas();
      serve();
      server.reply('GET', '/api/v2/self-deposit/options', 200, options());
      SelfDepositState.debugSet(SelfDepositOptions.fromJson({'enabled': true}));
      await pumpSim(t, v, home: (_) => const MoreModulesScreen());
      expect(card, findsOneWidget);
      await t.scrollUntilVisible(find.text('شحن رصيد الصفحة'), 200);
      await t.tap(find.text('شحن رصيد الصفحة'));
      await t.pumpAndSettle();
      expect(find.text('طريقة الشحن'), findsOneWidget);
      await simDrain(t);
    });

    Future<void> lockedCard(WidgetTester t, String reason) async {
      await pumpSim(t, v, home: (_) => const MoreModulesScreen());
      await t.scrollUntilVisible(find.text('شحن رصيد الصفحة'), 200);
      final tile = find.ancestor(
          of: find.byIcon(LucideIcons.banknoteArrowUp),
          matching: find.byType(InkWell));
      expect(find.descendant(of: tile.first, matching: find.byType(PermLockIcon)),
          findsOneWidget);
      expect(find.text(reason), findsOneWidget);
      await t.tap(find.text('شحن رصيد الصفحة'));
      await t.pump();
      expect(find.text('طريقة الشحن'), findsNothing, reason: 'المقفل لا يفتح');
      await t.pump(const Duration(seconds: 3));
    }

    testWidgets('موظّف ساس ومفتاح مديره مفتوح: بمكانها مقفلة «لصاحب الحساب»', (t) async {
      await setUpSas();
      PermissionsService.debugSet(isEmployee: true);
      SelfDepositState.debugSet(SelfDepositOptions.fromJson({
        'enabled': true,
        'supported': false,
        'reason': 'owner_only',
      }));
      await lockedCard(t, 'شحن الرصيد لصاحب الحساب وحده');
    });

    testWidgets('🚨 مالك ايرث لنك: بمكانها مقفلة «غير متاح لدى ايرث لنك»', (t) async {
      await setUpSas();
      ProviderService.debugSet('earthlink');
      SelfDepositState.debugSet(SelfDepositOptions.fromJson({
        'enabled': true,
        'supported': false,
        'reason': 'provider',
      }));
      await lockedCard(t, 'غير متاح لدى ايرث لنك');
    });

    testWidgets('🚨 موظّف ايرث لنك ومفتاح مديره مفتوح: بمكانها مقفلة «غير متاح لدى ايرث لنك» (لا مخفيّة)', (t) async {
      await setUpSas();
      PermissionsService.debugSet(isEmployee: true);
      ProviderService.debugSet('earthlink');
      SelfDepositState.debugSet(SelfDepositOptions.fromJson({
        'enabled': true,
        'supported': false,
        'reason': 'provider',
        'provider': 'earthlink',
        'employee': true,
      }));
      await lockedCard(t, 'غير متاح لدى ايرث لنك');
    });

    testWidgets('متوقّفٌ مؤقّتاً: البطاقة مفتوحة بنصّها (للسجلّ و«تحقّق»)', (t) async {
      await setUpSas();
      serve();
      SelfDepositState.debugSet(SelfDepositOptions.fromJson(
          {'enabled': true, 'paused': true, 'supported': false, 'reason': 'paused'}));
      await pumpSim(t, v, home: (_) => const MoreModulesScreen());
      await t.scrollUntilVisible(find.text('شحن رصيد الصفحة'), 200);
      expect(find.text('متوقّف مؤقّتاً — تابِع عمليّاتك التي لم تُحسم'), findsOneWidget);
      final tile = find.ancestor(
          of: find.byIcon(LucideIcons.banknoteArrowUp),
          matching: find.byType(InkWell));
      expect(find.descendant(of: tile.first, matching: find.byType(PermLockIcon)), findsNothing);
      await simDrain(t);
    });

    testWidgets('صفحةٌ بلا صلاحيّة «ايداع مالي»: السبب مكان الوصف', (t) async {
      await setUpSas();
      SelfDepositState.debugSet(SelfDepositOptions.fromJson({
        'enabled': true,
        'supported': false,
        'reason': 'no_permission',
      }));
      await lockedCard(
          t, 'صفحتك بلا صلاحيّة «ايداع مالي» في الساس — اطلبها من مديرك');
    });
  });
}
