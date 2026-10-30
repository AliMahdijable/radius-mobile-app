import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/jtpay_api.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/screens/app_modules.dart';
import 'package:rad_mysvcs/screens/topup/jtpay_screen.dart';
import 'package:rad_mysvcs/screens/topup/pay_nav_policy.dart';
import 'package:rad_mysvcs/screens/topup/topup_pay_page.dart';
import 'package:rad_mysvcs/screens/topup/wallet_app_link.dart';
import 'package:rad_mysvcs/services/jtpay_pending.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'sim_el/sim_harness.dart';
import 'support/fake_pay_engine.dart';

/// «شحن من pay الجزيرة» أمام خادمٍ وهميّ ومتصفّحٍ بديل.
///
/// ⚠️ **المال:** أوّل انتقالٍ إلى موقع الشحن (رجوع البوّابة) يُلتقط فلا يُحمَّل، ويُحفظ على الهاتف **قبل**
/// تسليمه، ولا يُمحى إلّا حين يقول الخادم «استلمت». والتحويل بتأكيدٍ صريح، ومرّةً واحدة.
void main() {
  const v = SimVariant(390, dark: false);
  final op = 'c' * 32;
  const payUrl = 'https://pg.zaincash.iq/transaction/pay?id=11111111-2222-3333-4444-555555555555&token=a.b.c';
  const ret = 'https://pay.jt.iq/zaincash/callback?token=x.y.z';
  late SimServer server;

  setUpAll(simSetUpAll);

  Future<void> setUpJt() async {
    server = await simSetUp(secure: {'auth.admin_id': 'jt:6836', 'auth.admin_username': 'admin@ali122'});
    ProviderService.debugSet(null);
    PermissionsService.debugSet(isEmployee: false);
    JtpayState.reset();
    TopupPayPage.debugEngineFactory = FakePayEngine.new;
    FakePayEngine.last = null;
  }

  tearDown(() {
    TopupPayPage.debugEngineFactory = null;
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
    JtpayState.reset();
    AppPlatform.debugIsDesktop = null;
  });

  Map<String, dynamic> opJson({String status = 'awaiting_payment', String state = 'redirected', num? after, bool received = false, String kind = 'topup', num amount = 10000, String? target}) => {
        'id': op,
        'kind': kind,
        'kind_label': kind == 'topup' ? 'تعبئة رصيد pay' : kind == 'to_sas' ? 'تحويل لصفحتك بالساس' : 'تحويل لصفحة ثانية',
        'method': kind == 'topup' ? 'zaincash' : null,
        'method_label': kind == 'topup' ? 'زين كاش' : null,
        'amount': amount,
        'target': target,
        'status': status,
        'state': state,
        'status_label': status,
        'order_no': kind == 'topup' ? '311500' : null,
        'balance_before': 0,
        'balance_after': after,
        'received': received,
        'can_check': kind == 'topup' && status != 'success' && status != 'failed',
        'created_at': '2026-10-30T17:00:00.000Z',
      };

  void serve({num balance = 0}) {
    server.reply('GET', '/api/v2/jtpay/overview', 200, {
      'success': true,
      'section': 'wireless',
      'section_label': 'الجزيرة — لاسلكي',
      'balance': balance,
      'notice': null,
      'min_amount': 1000,
      'max_amount': 5000000,
      'quick_amounts': [10000, 25000, 50000],
      'methods': [
        {'id': 'zaincash', 'label': 'زين كاش'},
        {'id': 'qi', 'label': 'بطاقة بنكية'},
      ],
      'fee_rate': 0.01,
      'open': [],
      'recent': [],
    });
    server.reply('POST', '/api/v2/jtpay/quote', 200, {'success': true, 'amount': 10000, 'fee': 100, 'total': 10100});
    server.reply('POST', '/api/v2/jtpay/topup', 200, {
      'success': true,
      'op': opJson(),
      'pay_url': payUrl,
      'return_host': 'pay.jt.iq',
      'expires_in_sec': 1800,
    });
  }

  Future<void> settle(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  /// مبلغٌ سريع ⇒ الرسوم ⇒ «ادفع» ⇒ تأكيد ⇒ صفحة الدفع.
  Future<FakePayEngine> openPayPage(WidgetTester t) async {
    await t.tap(find.text('10,000'));
    await t.pump(const Duration(milliseconds: 600));
    await settle(t, 4);
    expect(find.text('رسوم الدفع الالكتروني'), findsOneWidget);
    expect(simText('100 د.ع'), findsOneWidget);
    expect(simText('10,100 د.ع'), findsOneWidget);
    await t.ensureVisible(find.text('ادفع 10,100 د.ع'));
    await t.tap(find.text('ادفع 10,100 د.ع'));
    await t.pumpAndSettle();
    expect(find.text('دفع 10,100 د.ع'), findsOneWidget);
    await t.tap(find.text('المتابعة للدفع'));
    await settle(t);
    expect(find.byType(TopupPayPage), findsOneWidget);
    return FakePayEngine.last!;
  }

  // ───────────── منطقٌ صافٍ ─────────────

  test('قاعدة التنقّل: أوّل انتقالٍ لموقع الشحن يُلتقط (بدليلٍ أو بلا)، البوّابات تمضي، الخارج يُمنع', () {
    final p = HostReturnNavPolicy(returnHost: 'Pay.JT.iq.');
    expect(p.decide('https://pay.jt.iq/zaincash/callback?token=1'), PayNavAction.capture);
    expect(p.decide('https://pay.jt.iq/dashboard'), PayNavAction.capture);
    expect(p.decide('http://pay.jt.iq/x'), PayNavAction.capture);
    expect(p.decide('https://pg.zaincash.iq/transaction/otp'), PayNavAction.allow);
    expect(p.decide('https://3ds-api.qi.iq/api/v1/payment/x'), PayNavAction.allow);
    expect(p.decide('https://pay.jt.iq.evil.com/'), PayNavAction.allow);
    expect(p.decide('intent://pay#Intent;scheme=zaincash;end'), PayNavAction.block);
    expect(p.decide('http://pg.zaincash.iq/x'), PayNavAction.block);
    expect(p.decide('about:blank'), PayNavAction.allow);
    expect(p.decide('javascript:alert(1)'), PayNavAction.block);
  });

  // صفحة كي بالموبايل: زرّ «Pay with SuperQi» يجلب رابط دفعٍ ولا يفعل به شيئاً (يعرضه QR على الحاسبة وحدها).
  test('SuperQi: رابطه المسجَّل وحده يُفتح بتطبيقه، وسكربت القراءة لصفحة كي وحدها', () {
    final p = HostReturnNavPolicy(returnHost: 'pay.jt.iq');
    const link = 'https://m.banqi.qi.iq/shortlink/h5/dxyvgq4m';
    expect(p.decide(link), PayNavAction.external);
    expect(WalletAppLink.of(link)!.name, 'SuperQi');
    for (final u in [
      'http://m.banqi.qi.iq/shortlink/h5/x',
      'https://m.banqi.qi.iq.evil.com/shortlink/h5/x',
      'https://evilm.banqi.qi.iq/shortlink/h5/x',
      'https://u:p@m.banqi.qi.iq/shortlink/h5/x',
      'https://m.banqi.qi.iq:8443/shortlink/h5/x',
      'https://m.banqi.qi.iq/page/qicard-web/index.html',
      'https://m.banqi.qi.iq/shortlink/',
      'superqi://pay?x=1',
    ]) {
      expect(WalletAppLink.of(u), isNull, reason: u);
      expect(p.decide(u) == PayNavAction.external, isFalse, reason: u);
    }
    expect(p.scriptFor('https://3ds-api.qi.iq/api/v1/payment/b321'), WalletAppLink.qiHookScript);
    for (final u in ['https://pg.zaincash.iq/transaction/pay?id=1', 'https://pay.jt.iq/x', 'http://3ds-api.qi.iq/api/v1/payment/b', 'https://3ds-api.qi.iq.evil.com/x']) {
      expect(p.scriptFor(u), isNull, reason: u);
    }
    // السكربت يراقب طلب الزرّ نفسه، ولا ينقل الصفحة إلّا لرابط SuperQi (شُغّل على ردٍّ حقيقيّ من كي، ٣٠ أكتوبر).
    expect(WalletAppLink.qiHookScript, contains(r'var REQ = /\/payment\/[^\/?#]+\/requisites(?:[?#]|$)/;'));
    expect(WalletAppLink.qiHookScript, contains(r'var LINK = /^https:\/\/m\.banqi\.qi\.iq\/shortlink\//;'));
    expect(WalletAppLink.qiHookScript, contains("d.type === 'ALIPAY'"));
  });

  test('النماذج: حالة الخادم ⇒ حالة العميل، الأرقام لا صفر كاذب، والعمليّة بلا معرّف ⇒ null', () {
    final o = JtpayOp.fromJson(opJson(status: 'success', state: 'paid', after: 10000, received: true))!;
    expect([o.status, o.isTopup, o.succeeded, o.received, o.orderNo, o.balanceAfter], [JtpayStatus.success, true, true, true, '311500', 10000]);
    expect(JtpayOp.fromJson({'kind': 'topup'}), isNull);
    expect(JtpayOp.fromJson({...opJson(), 'status': 'weird'})!.status, JtpayStatus.unknown);
    final ov = JtpayOverview.fromJson(const {'section': 'ftth', 'balance': null, 'methods': [{'id': 'qi'}]});
    expect([ov.section, ov.balance, ov.minAmount, ov.methods.single.label], ['ftth', null, 1000, 'qi']);
    expect(JtpayProbe.fromJson(const {'enabled': true, 'reason': 'owner_only'}).ownerOnly, isTrue);
  });

  test('بطاقة النتيجة: الشحن يسأل «تحوّله؟»، المعلّق والمجهول «تحقّق»، الفشل لا يُقال لغير المحسوم', () {
    final paid = describeJtpayOp(JtpayOp.fromJson(opJson(status: 'success', after: 10000))!);
    expect([paid.tone, paid.title, paid.checkable], [AppTone.success, 'انشحن 10,000 د.ع برصيد pay', false]);
    expect(paid.body, contains('لصفحتك بالساس'));
    for (final s in ['pending', 'unknown', 'awaiting_payment', 'expired']) {
      final d = describeJtpayOp(JtpayOp.fromJson(opJson(status: s))!);
      expect(d.checkable, isTrue, reason: s);
      expect(d.tone == AppTone.danger, isFalse, reason: s);
    }
    final t = describeJtpayOp(JtpayOp.fromJson(opJson(kind: 'to_page', status: 'unknown', target: 'admin@x'))!);
    expect(t.title, 'التحويل غير مؤكَّد');
  });

  test('الروابط المعلّقة: لصاحبها وحده، تُستبدل للعمليّة نفسها، وتُمحى بالاسم', () async {
    await setUpJt();
    await JtpayPendingStore.put(JtpayPending(opId: op, adminId: 'jt:6836', returnUrl: ret, at: DateTime.now(), amount: 1000));
    await JtpayPendingStore.put(JtpayPending(opId: op, adminId: 'jt:6836', returnUrl: '${ret}2', at: DateTime.now()));
    expect((await JtpayPendingStore.forAdmin('jt:6836')).single.returnUrl, '${ret}2');
    expect(await JtpayPendingStore.forAdmin('jt:7'), isEmpty);
    await JtpayPendingStore.remove(op);
    expect(await JtpayPendingStore.forAdmin('jt:6836'), isEmpty);
  });

  test('القائمة: مفعّلة ⇒ «شحن من pay الجزيرة»؛ الموظّف ⇒ مقفلة بسببها؛ مطفأة أو ويندوز ⇒ لا شيء', () async {
    await setUpJt();
    JtpayState.debugSet(const JtpayProbe(enabled: true, supported: true, section: 'wireless'));
    var m = buildAppModules().where((x) => x.id == 'jtpay').toList();
    expect(m.single.title, 'شحن من pay الجزيرة');
    expect(m.single.isLocked, isFalse);
    JtpayState.debugSet(const JtpayProbe(enabled: true, reason: 'owner_only'));
    m = buildAppModules().where((x) => x.id == 'jtpay').toList();
    expect(m.single.unavailable, contains('لصاحب الصفحة'));
    JtpayState.debugSet(JtpayProbe.off);
    expect(buildAppModules().where((x) => x.id == 'jtpay'), isEmpty);
    JtpayState.debugSet(const JtpayProbe(enabled: true, supported: true));
    AppPlatform.debugIsDesktop = true;
    expect(buildAppModules().where((x) => x.id == 'jtpay'), isEmpty);
  });

  // ───────────── التدفّق ─────────────

  testWidgets('🚨 التعبئة: الرجوع يُلتقط ولا يُحمَّل، يُحفظ قبل تسليمه، ثمّ «انشحن» وسؤال التحويل', (t) async {
    await setUpJt();
    serve();
    server.hold('POST', '/api/v2/jtpay/topup/$op/return');
    server.reply('POST', '/api/v2/jtpay/topup/$op/return', 200, {
      'success': true,
      'op': opJson(status: 'success', state: 'paid', after: 10000, received: true),
    });
    server.reply('GET', '/api/v2/jtpay/overview', 200, {
      'success': true, 'section': 'wireless', 'section_label': 'الجزيرة — لاسلكي', 'balance': 0, 'min_amount': 1000,
      'max_amount': 5000000, 'quick_amounts': [10000, 25000, 50000],
      'methods': [{'id': 'zaincash', 'label': 'زين كاش'}, {'id': 'qi', 'label': 'بطاقة بنكية'}], 'open': [], 'recent': [],
    });
    await pumpSim(t, v, home: (_) => const JtpayScreen());
    expect(find.text('رصيد pay'), findsOneWidget);
    expect(find.text('الجزيرة — لاسلكي'), findsWidgets);

    final engine = await openPayPage(t);
    expect(server.bodies('POST', '/api/v2/jtpay/topup').single, {'amount': 10000, 'method': 'zaincash'});
    expect(engine.opened.single.toString(), payUrl);
    expect(engine.wipes, 1, reason: 'لا كوكيز بوّابةٍ من جلسةٍ سابقة');

    // صفحات البوّابة تمضي، والتطبيقات الخارجيّة تُمنع.
    expect(engine.navigate('https://pg.zaincash.iq/transaction/otp'), isTrue);
    expect(engine.navigate('intent://pay#Intent;scheme=zaincash;end'), isFalse);
    await t.pump();

    // الرجوع لموقع الشحن: يُمنع تحميله ويُلتقط.
    expect(engine.navigate(ret), isFalse);
    await settle(t);
    expect(find.byType(TopupPayPage), findsNothing, reason: 'أُغلقت الصفحة');
    final stored = await JtpayPendingStore.forAdmin('jt:6836');
    expect(stored.single.returnUrl, ret, reason: 'محفوظٌ قبل أن يصل الحكم');
    expect(server.bodies('POST', '/api/v2/jtpay/topup/$op/return').single, {'return_url': ret});

    server.release('POST', '/api/v2/jtpay/topup/$op/return');
    await t.pumpAndSettle();
    expect(find.text('انشحن 10,000 د.ع برصيد pay'), findsOneWidget);
    expect(find.text('حوّله لصفحتك بالساس'), findsOneWidget);
    expect(find.text('حوّله لصفحة ثانية'), findsOneWidget);
    expect(await JtpayPendingStore.forAdmin('jt:6836'), isEmpty);
    expect(server.calls('POST', '/api/v2/jtpay/topup/$op/return'), hasLength(1));
    await simDrain(t);
  });

  testWidgets('🚨 الرجوع بلا نت: يُعاد ثلاثاً، يبقى محفوظاً، ويُسلَّم عند الفتح التالي', (t) async {
    await setUpJt();
    serve();
    server.on('POST', '/api/v2/jtpay/topup/$op/return', simTimeout);
    server.reply('GET', '/api/v2/jtpay/ops/$op', 200, {'success': true, 'op': opJson()});
    await pumpSim(t, v, home: (_) => const JtpayScreen());
    final engine = await openPayPage(t);
    expect(engine.navigate(ret), isFalse);
    await settle(t);
    await t.pump(const Duration(seconds: 3));
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(server.calls('POST', '/api/v2/jtpay/topup/$op/return'), hasLength(3));
    expect(find.text('لم يتمّ الدفع'), findsNothing, reason: 'لا «فشل» بلا حكم');
    expect((await JtpayPendingStore.forAdmin('jt:6836')).single.returnUrl, ret);

    // فتحٌ لاحق والخادم عاد: يُسلَّم المحفوظ ويُحسم.
    server.reply('POST', '/api/v2/jtpay/topup/$op/return', 200, {
      'success': true,
      'op': opJson(status: 'success', state: 'paid', after: 10000, received: true),
    });
    await pumpSim(t, v, home: (_) => const JtpayScreen(key: ValueKey('again')));
    await t.pumpAndSettle();
    expect(server.calls('POST', '/api/v2/jtpay/topup/$op/return'), hasLength(4));
    expect(find.text('انشحن 10,000 د.ع برصيد pay'), findsOneWidget);
    expect(await JtpayPendingStore.forAdmin('jt:6836'), isEmpty);
    await simDrain(t);
  });

  testWidgets('التحويل لصفحتك بالساس: المبلغ من الرصيد، تأكيد، طلبٌ واحد، ثمّ النتيجة', (t) async {
    await setUpJt();
    serve(balance: 10000);
    server.reply('POST', '/api/v2/jtpay/transfer', 200, {
      'success': true,
      'op': {...opJson(kind: 'to_sas', status: 'success', state: 'applied', after: 0), 'sas_after': 16000},
    });
    await pumpSim(t, v, home: (_) => const JtpayScreen());
    await t.ensureVisible(find.text('لصفحتك بالساس').first);
    await t.pumpAndSettle();
    await t.tap(find.text('لصفحتك بالساس').first);
    await t.pumpAndSettle();
    expect(find.text('تحويل لصفحتك بالساس'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, '10000');
    await t.tap(find.text('حوّل').last);
    await t.pumpAndSettle();
    expect(find.text('تأكيد التحويل'), findsOneWidget);
    await t.tap(find.text('حوّل').last);
    await t.pumpAndSettle();
    expect(server.bodies('POST', '/api/v2/jtpay/transfer').single, {'to': 'sas', 'amount': 10000});
    expect(find.text('تحوّل 10,000 د.ع لصفحتك بالساس'), findsOneWidget);
    expect(simText('رصيد صفحتك بالساس صار 16,000 د.ع.'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('التحويل لصفحة ثانية: الاسم يُتحقَّق محلّيّاً، والتكرار القريب يُسأل عنه ثمّ يُرسل بتأكيدٍ صريح', (t) async {
    await setUpJt();
    serve(balance: 25000);
    var n = 0;
    server.on('POST', '/api/v2/jtpay/transfer', (req) {
      n += 1;
      final body = Map<String, dynamic>.from(req.data as Map);
      if (body['confirm_repeat'] != true) {
        return const SimReply(409, {'success': false, 'code': 'RECENT_DUPLICATE', 'message': 'نفس التحويل صار قبل شوي — إذا تريده مرّة ثانية أكّد', 'confirm_required': true});
      }
      return SimReply(200, {'success': true, 'op': opJson(kind: 'to_page', status: 'success', state: 'applied', after: 15000, target: 'admin@other')});
    });
    await pumpSim(t, v, home: (_) => const JtpayScreen());
    await t.ensureVisible(find.text('لصفحة ثانية').first);
    await t.pumpAndSettle();
    await t.tap(find.text('لصفحة ثانية').first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(find.byType(TextField).evaluate().length - 2), 'bad name!');
    await t.enterText(find.byType(TextField).last, '10000');
    await t.tap(find.text('حوّل').last);
    await t.pumpAndSettle();
    expect(find.textContaining('اكتب اسم الصفحة'), findsOneWidget);
    expect(n, 0, reason: 'لا طلب باسمٍ غير صالح');

    await t.enterText(find.byType(TextField).at(find.byType(TextField).evaluate().length - 2), 'admin@other');
    await t.tap(find.text('حوّل').last);
    await t.pumpAndSettle();
    await t.tap(find.text('حوّل').last);
    await t.pumpAndSettle();
    expect(find.text('نفس التحويل صار قبل شوي'), findsOneWidget);
    await t.tap(find.text('حوّل مرّة ثانية'));
    await t.pumpAndSettle();
    expect(n, 2);
    expect(server.bodies('POST', '/api/v2/jtpay/transfer').last, {'to': 'page', 'amount': 10000, 'target': 'admin@other', 'confirm_repeat': true});
    expect(find.text('تحوّل 10,000 د.ع إلى admin@other'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('آخر العمليّات: ١٠ من الخادم، «عرض المزيد» ما قبل آخر صفّ، وبحثٌ برقم الطلب (العربيّة ⇒ لاتينيّة)', (t) async {
    await setUpJt();
    serve();
    String id(int i) => i.toRadixString(16).padLeft(32, '0');
    final ops = [
      for (var i = 20; i >= 1; i--)
        {...opJson(status: 'success', state: 'paid', after: 1000), 'id': id(i), 'order_no': '3115${i.toString().padLeft(2, '0')}', 'amount': 1000 * i},
    ];
    server.on('GET', '/api/v2/jtpay/history', (o) {
      final q = o.queryParameters;
      var list = ops;
      if (q['before'] != null) list = list.sublist(list.indexWhere((x) => x['id'] == q['before']) + 1);
      if (q['q'] != null) list = list.where((x) => (x['order_no'] as String).contains('${q['q']}')).toList();
      final lim = int.parse('${q['limit']}');
      return SimReply(200, {'success': true, 'tab': 'ops', 'rows': list.take(lim).toList(), 'has_more': list.length > lim});
    });
    await pumpSim(t, v, home: (_) => const JtpayScreen());
    await settle(t);
    final calls = server.calls('GET', '/api/v2/jtpay/history');
    expect([calls.first.queryParameters['tab'], calls.first.queryParameters['limit']], ['ops', 10]);
    // القائمة تُبنى عند الوصول إليها: تمريرٌ حتى تُبنى، ثمّ إلى وسط الشاشة.
    final main = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
    await t.scrollUntilVisible(find.text('عرض المزيد'), 300, scrollable: main);
    await t.ensureVisible(find.text('عرض المزيد'));
    await t.pumpAndSettle();
    expect(find.textContaining('311511'), findsOneWidget);
    expect(find.textContaining('311510'), findsNothing, reason: 'الصفحة الأولى ١٠ وحدها');
    await t.tap(find.text('عرض المزيد'));
    await settle(t);
    expect(server.calls('GET', '/api/v2/jtpay/history').last.queryParameters['before'], id(11), reason: 'ما قبل آخر صفٍّ معروض');
    await t.scrollUntilVisible(find.textContaining('311501'), 300, scrollable: main);
    expect(find.text('عرض المزيد'), findsNothing, reason: 'انتهت العمليّات');

    await t.scrollUntilVisible(find.byType(SheetSearchField), -300, scrollable: main);
    await t.ensureVisible(find.byType(SheetSearchField));
    await t.pumpAndSettle();
    await t.enterText(find.descendant(of: find.byType(SheetSearchField), matching: find.byType(TextField)), '#٣١١٥٠٥');
    await t.pump(const Duration(milliseconds: 500));
    await settle(t);
    expect(server.calls('GET', '/api/v2/jtpay/history').last.queryParameters['q'], '311505');
    expect(find.textContaining('311505'), findsOneWidget);
    expect(find.textContaining('311506'), findsNothing);
    await simDrain(t);
  });

  testWidgets('SuperQi: يُفتح بتطبيقه (أو بالمتصفّح إن لم يُثبَّت)، الصفحة تبقى تنتظر، والرجوع بعد الدفع يُلتقط', (t) async {
    await setUpJt();
    final launched = <(Uri, bool)>[];
    var installed = true;
    TopupPayPage.debugLaunch = (u, {required appOnly}) async {
      launched.add((u, appOnly));
      return appOnly ? installed : true;
    };
    addTearDown(() => TopupPayPage.debugLaunch = null);
    const qi = 'https://3ds-api.qi.iq/api/v1/payment/b321f92b-9594-4aa7-975d-8c2a328935d9';
    const link = 'https://m.banqi.qi.iq/shortlink/h5/dxyvgq4m';
    const back = 'https://pay.jt.iq/hook/qi?requestId=41590b53&paymentId=b321f92b';
    PayPageResult? result;
    await pumpSim(
      t,
      v,
      home: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async => result = await Navigator.of(ctx).push<PayPageResult>(MaterialPageRoute(
              builder: (_) => TopupPayPage(
                payUrl: Uri.parse(qi),
                policy: HostReturnNavPolicy(returnHost: 'pay.jt.iq'),
                methodLabel: 'بطاقة بنكية',
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await settle(t);
    final e = FakePayEngine.last!;
    e.pageFinished(qi);
    e.pageFinished('https://pg.zaincash.iq/transaction/pay?id=1');
    await t.pump();
    expect(e.scripts, [WalletAppLink.qiHookScript], reason: 'صفحة كي وحدها');
    expect(find.text('لا تغلق الصفحة بعد الدفع — يرجع التطبيق وحده'), findsOneWidget);
    expect(find.text('فتح SuperQi'), findsNothing);

    // إطارٌ داخليّ لا يفتح شيئاً.
    expect(e.navigate(link, mainFrame: false), isFalse);
    await t.pump();
    expect(launched, isEmpty);

    // الصفحة تنتقل لرابط SuperQi (بأمر السكربت): لا يُحمَّل، يُفتح بتطبيقه، والصفحة باقيةٌ تنتظر.
    expect(e.navigate(link), isFalse);
    await settle(t, 3);
    expect(launched, [(Uri.parse(link), true)]);
    expect(find.byType(TopupPayPage), findsOneWidget);
    expect(find.text('أكمل الدفع في SuperQi ثمّ ارجع هنا — يرجع التطبيق وحده'), findsOneWidget);
    expect(e.navigate(link), isFalse);
    await settle(t, 2);
    expect(launched, hasLength(1), reason: 'البلاغ المكرّر لا يفتحه ثانيةً');

    // «فتح SuperQi» يعيده؛ وغير مثبّت ⇒ المتصفّح (صفحة كي: «حمّل SuperQi»).
    installed = false;
    await t.tap(find.text('فتح SuperQi'));
    await settle(t, 2);
    expect(launched.skip(1).toList(), [(Uri.parse(link), true), (Uri.parse(link), false)]);

    // دُفع ⇒ صفحة كي تعرض النتيجة ثمّ تذهب وحدها لموقع الشحن ⇒ يُلتقط كرجوع البطاقة.
    expect(e.navigate(qi), isTrue);
    expect(e.navigate(back), isFalse);
    await settle(t);
    expect(find.byType(TopupPayPage), findsNothing);
    expect(result?.returnUrl, back);
    await simDrain(t);
  });
}
