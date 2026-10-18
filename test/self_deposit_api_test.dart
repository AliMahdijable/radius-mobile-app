import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/self_deposit_api.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/services/app_resumed_signal.dart';
import 'package:rad_mysvcs/services/self_deposit_pending.dart';
import 'package:rad_mysvcs/services/self_deposit_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sim_el/sim_harness.dart' show SimReply, SimServer, simTimeout;

/// «شحن رصيد الصفحة» — قراءة ردود الخادم وحالة الجلسة والقيود المعلّقة.
///
/// ⚠️ مالٌ حقيقيّ خلف هذه الردود: ما لم يحسمه الخادم لا يُقرأ «فشلاً»، وما
/// لم يقل الخادم إنّه مفتوح لا يظهر، والتوكن الملتقط لا يُمحى بلا حكم.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SimServer server;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'auth.token': 'sim-token',
      'auth.admin_id': '2251',
    });
    SharedPreferences.setMockInitialValues({});
    server = SimServer();
    ApiClient.dio.httpClientAdapter = server;
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
    SelfDepositState.reset();
    SelfDepositSync.debugReset();
  });

  tearDown(() {
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

  const zc = {'id': 3, 'name': 'ZainCash', 'internal_name': 'zaincash'};
  const voucher = {'id': 5, 'name': 'SAS Voucher', 'internal_name': 'voucher'};

  group('الوسائل', () {
    test('النوع من الاسم الداخليّ حين لا يقول الخادم flow', () {
      SelfDepositMethod m(Map<String, Object?> j) =>
          SelfDepositMethod.fromJson(Map<String, dynamic>.from(j))!;
      expect(m(zc).flow, SelfDepositFlow.redirect);
      expect(m(zc).label, 'زين كاش');
      expect(m({'id': 1, 'internal_name': 'ZainCashV2'}).flow,
          SelfDepositFlow.redirect);
      expect(m(voucher).flow, SelfDepositFlow.pin);
      expect(m(voucher).label, 'كارت تعبئة');
      expect(m({'id': 2, 'internal_name': 'kushok'}).needsPin, isTrue);
      final tasdid = m({'id': 4, 'internal_name': 'tasdid'});
      expect(tasdid.flow, SelfDepositFlow.invoice);
      expect(tasdid.needsAmount && tasdid.needsPayer, isTrue);
      expect(m({'id': 6, 'internal_name': 'hyperpay'}).inApp, isFalse);
      expect(m({'id': 7, 'internal_name': 'switch'}).inApp, isFalse);
      // وسيلةٌ لا نعرفها: باسم الشركة، ومن لوحتها.
      final odd = m({'id': 8, 'internal_name': 'fastpay', 'name': 'FastPay'});
      expect(odd.inApp, isFalse);
      expect(odd.label, 'FastPay');
    });

    test('🚨 الخادم يقول in_app:false ⇒ لا تُفتح هنا مهما كان نوعها', () {
      final m = SelfDepositMethod.fromJson(
          {'id': 3, 'internal_name': 'zaincash', 'in_app': false})!;
      expect(m.inApp, isFalse);
    });

    test('🚨 تحويلٌ لغير زين كاش لا يُفتح في الصفحة (الالتقاط لزين كاش وحده)', () {
      final m = SelfDepositMethod.fromJson(
          {'id': 9, 'internal_name': 'hyperpay', 'flow': 'redirect'})!;
      expect(m.flow, SelfDepositFlow.panel);
    });

    test('بلا معرّف لا وسيلة', () {
      expect(SelfDepositMethod.fromJson({'internal_name': 'zaincash'}), isNull);
    });
  });

  group('الحالة من options', () {
    test('🚨 ردٌّ بلا كلام الميزة (الردّ الآمن الفارغ) ⇒ مطفأة لا مفتوحة', () {
      final o = SelfDepositOptions.fromJson(
          {'success': true, 'data': null, 'items': [], 'value': null, 'total': 0});
      expect(o.enabled, isFalse);
      expect(o.block, SelfDepositBlock.disabled);
    });

    test('enabled:false ⇒ مطفأة', () {
      final o = SelfDepositOptions.fromJson(
          {'success': true, 'enabled': false, 'methods': [zc]});
      expect(o.block, SelfDepositBlock.disabled);
    });

    test('مفتوحة بوسائلها ورصيدها وعملتها', () {
      final o = SelfDepositOptions.fromJson({
        'success': true,
        'enabled': true,
        'supported': true,
        'methods': [zc, voucher, {'id': 6, 'internal_name': 'hyperpay'}],
        'balance': '1,250,000',
        'currency': 'IQD',
      });
      expect(o.block, SelfDepositBlock.none);
      expect(o.methods, hasLength(3));
      expect(o.inAppMethods, hasLength(2));
      expect(o.balance, 1250000);
      expect(o.currencyLabel, 'د.ع');
    });

    test('الأسباب كلّها بقفلها', () {
      SelfDepositBlock b(String reason) => SelfDepositOptions.fromJson(
              {'enabled': true, 'supported': false, 'reason': reason})
          .block;
      expect(b('provider'), SelfDepositBlock.provider);
      expect(b('no_permission'), SelfDepositBlock.noPermission);
      expect(b('no_gateways'), SelfDepositBlock.noGateways);
      expect(b('employee'), SelfDepositBlock.ownerOnly);
      expect(b('owner_only'), SelfDepositBlock.ownerOnly);
      // مدعومةٌ بلا وسائل = لا وسائل.
      expect(
          SelfDepositOptions.fromJson({'enabled': true, 'supported': true})
              .block,
          SelfDepositBlock.noGateways);
      // supported:null = تعذّرت القراءة — ليست «غير مدعومة».
      expect(SelfDepositOptions.fromJson({'enabled': true}).block,
          SelfDepositBlock.none);
    });

    test('🚨 دفاعٌ ثانٍ: الموظّف وايرث لنك مقفلان مهما قال الخادم', () {
      final open = {'enabled': true, 'supported': true, 'methods': [zc]};
      PermissionsService.debugSet(isEmployee: true);
      expect(SelfDepositOptions.fromJson(open).block, SelfDepositBlock.ownerOnly);
      PermissionsService.debugSet(isEmployee: false);
      ProviderService.debugSet('earthlink');
      expect(SelfDepositOptions.fromJson(open).block, SelfDepositBlock.provider);
      ProviderService.debugSet('ftth');
      expect(SelfDepositOptions.fromJson(open).block, SelfDepositBlock.provider);
      // موظّف ايرث لنك: السبب الأصدق أنّ المزوّد لا يملكها — لا «لصاحب الحساب».
      PermissionsService.debugSet(isEmployee: true);
      ProviderService.debugSet('earthlink');
      expect(SelfDepositOptions.fromJson(open).block, SelfDepositBlock.provider);
    });

    test('«متوقّفٌ مؤقّتاً» (المفتاح أُغلق ولصاحب الحساب عمليّاتٌ لم تُحسم)', () {
      final o = SelfDepositOptions.fromJson({
        'success': true, 'enabled': true, 'paused': true, 'supported': false,
        'reason': 'paused', 'open_count': 2, 'methods': [],
      });
      expect(o.enabled, isTrue);
      expect(o.block, SelfDepositBlock.paused);
    });
  });

  group('النتائج', () {
    test('الحالات كما يكتبها الخادم', () {
      SelfDepositStatus s(Object v) =>
          SelfDepositOutcome.fromJson({'success': true, 'status': v}).status;
      expect(s('success'), SelfDepositStatus.success);
      expect(s('processed'), SelfDepositStatus.success);
      expect(s('failed'), SelfDepositStatus.failed);
      expect(s('expired'), SelfDepositStatus.expired);
      expect(s('awaiting_webhook'), SelfDepositStatus.awaiting);
      expect(s('unverified'), SelfDepositStatus.unverified);
      expect(s('redirected'), SelfDepositStatus.pending);
      expect(s('requested'), SelfDepositStatus.pending);
      // 🚨 ما لا نعرفه لا يُقرأ فشلاً.
      expect(s('something_new'), SelfDepositStatus.pending);
    });

    test('الحسم: النهائيّ يمحو القيد، والمعلّق يستحقّ «تحقّق»', () {
      const ok = SelfDepositOutcome(status: SelfDepositStatus.success);
      const off = SelfDepositOutcome(
          status: SelfDepositStatus.success, offline: true);
      const wait = SelfDepositOutcome(status: SelfDepositStatus.awaiting);
      expect(ok.isFinal, isTrue);
      expect(off.isFinal, isFalse);
      expect(wait.isFinal, isFalse);
      expect(wait.checkable, isTrue);
      expect(ok.checkable, isFalse);
    });

    test('🚨 «انتهت المهلة» ليست نهائيّة (تُراجَع بـ«تحقّق»)، والخادم يحكم بـfinal/received', () {
      final exp = SelfDepositOutcome.fromJson({'status': 'expired', 'final': false});
      expect(exp.isFinal, isFalse);
      expect(exp.checkable, isTrue);
      expect(exp.settled, isFalse, reason: 'رابطٌ متأخّر قد يُكمَل — لا يُمحى');
      // الخادم استلم الرجوع وحفظه للمراجعة: غير نهائيّ، لكنّه حامل الدليل الآن.
      final kept = SelfDepositOutcome.fromJson(
          {'status': 'unverified', 'final': false, 'received': true});
      expect(kept.isFinal, isFalse);
      expect(kept.settled, isTrue);
      expect(kept.checkable, isTrue);
      // final من الخادم يغلب التخمين المحلّيّ.
      expect(SelfDepositOutcome.fromJson({'status': 'failed', 'final': true}).settled, isTrue);
      expect(SelfDepositOutcome.fromJson({'status': 'pending', 'received': false}).settled, isFalse);
    });
  });

  group('الطلبات', () {
    final method = SelfDepositMethod.fromJson(Map<String, dynamic>.from(zc))!;
    final card = SelfDepositMethod.fromJson(Map<String, dynamic>.from(voucher))!;

    test('options بلا جلسة لا يطرق الخادم', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final r = await SelfDepositApi.options();
      expect(r.data, isNull);
      expect(server.requests, isEmpty);
    });

    test('options: ٤٠٤ (خادمٌ أقدم) و٤٠٣ بلا كلام الميزة ⇒ مطفأة', () async {
      server.reply('GET', '/api/v2/self-deposit/options', 404,
          {'success': false});
      expect((await SelfDepositApi.options()).data?.enabled, isFalse);
      server.reply('GET', '/api/v2/self-deposit/options', 403,
          {'success': false, 'code': 'OWNER_ONLY', 'message': 'هذه العمليّة لصاحب الحساب فقط'});
      expect((await SelfDepositApi.options()).data?.enabled, isFalse);
    });

    test('options: الموظّف يُخبَر بمفتاح مديره ⇒ مقفلةٌ له', () async {
      server.reply('GET', '/api/v2/self-deposit/options', 403, {
        'success': false,
        'enabled': true,
        'supported': false,
        'reason': 'employee',
      });
      final o = (await SelfDepositApi.options()).data!;
      expect(o.enabled, isTrue);
      expect(o.block, SelfDepositBlock.ownerOnly);
    });

    test('request زين كاش ⇒ رابط دفعٍ مشفَّر ومعرّف وقواعد الرجوع', () async {
      server.reply('POST', '/api/v2/self-deposit/request', 200, {
        'success': true,
        'flow': 'redirect',
        'psid': 'sd_9f2c',
        'pay_url': 'https://api.zaincash.iq/transaction/pay?id=XY',
        'capture': {'sas_host': 'sas.speed.iq', 'routes': ['#/zaincash/process']},
      });
      final s = await SelfDepositApi.request(method: method, amount: 25000);
      expect(s.isRedirect, isTrue);
      expect(s.psid, 'sd_9f2c');
      expect(s.capture!.hosts, contains('sas.speed.iq'));
      final sent = server.bodies('POST', '/api/v2/self-deposit/request').single;
      expect(sent, {'method_id': 3, 'amount': 25000, 'client': 'app'});
    });

    test('🚨 رابط دفعٍ غير مشفَّر لا يُفتح', () async {
      server.reply('POST', '/api/v2/self-deposit/request', 200, {
        'success': true,
        'flow': 'redirect',
        'psid': 'sd_1',
        'pay_url': 'http://api.zaincash.iq/transaction/pay?id=XY',
      });
      final s = await SelfDepositApi.request(method: method, amount: 25000);
      expect(s.isRedirect, isFalse);
      expect(s.message, isNotNull);
    });

    test('الكارت: نجاحٌ برصيدٍ جديد، والرمز الخاطئ حكمٌ لا عطل', () async {
      server.reply('POST', '/api/v2/self-deposit/request', 200, {
        'success': true,
        'flow': 'done',
        'status': 'success',
        'credited': 50000,
        'balance': 300000,
      });
      final ok = await SelfDepositApi.request(method: card, pin: '12345678');
      expect(ok.outcome!.status, SelfDepositStatus.success);
      expect(ok.outcome!.credited, 50000);
      expect(server.bodies('POST', '/api/v2/self-deposit/request').last,
          {'method_id': 5, 'pin': '12345678', 'client': 'app'});

      server.reply('POST', '/api/v2/self-deposit/request', 422, {
        'success': false,
        'code': 'BAD_PIN',
        'message': 'رمز الكارت غير صحيح',
        'psid': 'a' * 32,
        'status': 'failed',
      });
      final bad = await SelfDepositApi.request(method: card, pin: '0000');
      expect(bad.outcome!.status, SelfDepositStatus.failed);
      expect(bad.outcome!.message, 'رمز الكارت غير صحيح');
    });

    test('🚨 ٤٠٩ UNVERIFIED ⇒ «تعذّر التأكّد» لا «فشل»', () async {
      server.reply('POST', '/api/v2/self-deposit/request', 409, {
        'success': false,
        'code': 'UNVERIFIED',
        'message': 'تعذّر التأكّد من نتيجة العمليّة — راجع رصيدك',
      });
      final s = await SelfDepositApi.request(method: card, pin: '12345678');
      expect(s.outcome!.status, SelfDepositStatus.unverified);
    });

    test('🚨 مهلةٌ بعد الإرسال ⇒ غير محسومة؛ ولا إعادة تلقائيّة للطلب', () async {
      server.on('POST', '/api/v2/self-deposit/request', simTimeout);
      final s = await SelfDepositApi.request(method: card, pin: '12345678');
      expect(s.outcome!.status, SelfDepositStatus.unverified);
      expect(s.outcome!.offline, isTrue);
      expect(server.calls('POST', '/api/v2/self-deposit/request'), hasLength(1));
    });

    test('لا اتّصال أصلاً ⇒ لم يُرسل (إعادته آمنة)', () async {
      server.on(
          'POST',
          '/api/v2/self-deposit/request',
          (o) => throw DioException(
              requestOptions: o, type: DioExceptionType.connectionError));
      final s = await SelfDepositApi.request(method: card, pin: '12345678');
      expect(s.outcome, isNull);
      expect(s.notSent, isTrue);
    });

    test('complete: يرسل المعرّف ورابط الرجوع كما التُقط', () async {
      server.reply('POST', '/api/v2/self-deposit/complete', 200, {
        'success': true,
        'status': 'success',
        'credited': 25000,
        'balance': 1275000,
      });
      const ret = 'https://sas.speed.iq/#/zaincash/process?token=a.b.c';
      final o = await SelfDepositApi.complete(psid: 'sd_9', returnUrl: ret);
      expect(o.status, SelfDepositStatus.success);
      expect(o.isFinal, isTrue);
      expect(server.bodies('POST', '/api/v2/self-deposit/complete').single,
          {'psid': 'sd_9', 'return_url': ret, 'client': 'app'});
    });

    test('🚨 complete بلا ردّ (مهلة/٥xx) ⇒ معلّق غير محسوم — يُعاد لاحقاً', () async {
      server.on('POST', '/api/v2/self-deposit/complete', simTimeout);
      final a = await SelfDepositApi.complete(psid: 'sd_9', returnUrl: 'https://x/#/zaincash/process?token=1');
      expect(a.offline, isTrue);
      expect(a.isFinal, isFalse);
      server.reply('POST', '/api/v2/self-deposit/complete', 502, {'success': false});
      final b = await SelfDepositApi.complete(psid: 'sd_9', returnUrl: 'https://x/#/zaincash/process?token=1');
      expect(b.offline, isTrue);
    });

    test('🚨 status/complete: رفضٌ **بلا صفّ** (٤٠٤ · ٤٠٠ · ٤١٠ قديم) ⇒ «تعذّر التأكّد» لا حكم — ولا يُمحى القيد', () async {
      server.reply('GET', '/api/v2/self-deposit/status/sd_9', 404,
          {'success': false, 'code': 'NOT_FOUND', 'message': 'العمليّة غير موجودة'});
      final a = await SelfDepositApi.status('sd_9');
      expect(a.status, SelfDepositStatus.unverified);
      expect(a.isFinal, isFalse);
      expect(a.settled, isFalse);
      expect(a.code, 'NOT_FOUND');
      for (final r in [(400, 'NO_TOKEN'), (410, 'TOO_OLD'), (409, 'TOKEN_USED')]) {
        server.reply('POST', '/api/v2/self-deposit/complete', r.$1,
            {'success': false, 'code': r.$2, 'message': 'رسالة الخادم'});
        final o = await SelfDepositApi.complete(
            psid: 'sd_9', returnUrl: 'https://sas/#/zaincash/process?token=a.b.c');
        expect(o.settled, isFalse, reason: r.$2);
        expect(o.status, SelfDepositStatus.unverified, reason: r.$2);
        expect(o.message, 'رسالة الخادم');
      }
    });
  });

  group('حالة الجلسة (بطاقة «قوائم أخرى»)', () {
    test('🚨 الاستماع يطلب الحالة مرّةً، والقديمة وحدها تُطلب ثانيةً', () async {
      server.reply('GET', '/api/v2/self-deposit/options', 200,
          {'success': true, 'enabled': true, 'supported': true, 'methods': [zc]});
      void l() {}
      SelfDepositState.gate.addListener(l);
      SelfDepositState.gate.addListener(l);
      await Future<void>.delayed(Duration.zero);
      await SelfDepositState.ensureFresh();
      expect(server.calls('GET', '/api/v2/self-deposit/options'), hasLength(1));
      expect(SelfDepositState.visible, isTrue);
      await SelfDepositState.ensureFresh();
      expect(server.calls('GET', '/api/v2/self-deposit/options'), hasLength(1),
          reason: 'خلال المهلة لا طلب ثانٍ');
      SelfDepositState.gate.removeListener(l);
      SelfDepositState.gate.removeListener(l);
    });

    test('🚨 ردٌّ يصل بعد تبديل الجلسة لا يُكتب', () async {
      server.hold('GET', '/api/v2/self-deposit/options');
      server.reply('GET', '/api/v2/self-deposit/options', 200,
          {'success': true, 'enabled': true, 'supported': true, 'methods': [zc]});
      final f = SelfDepositState.ensureFresh();
      await Future<void>.delayed(Duration.zero);
      SelfDepositState.reset(); // خروج/تبديل شركة
      server.release('GET', '/api/v2/self-deposit/options');
      await f;
      expect(SelfDepositState.gate.value, isNull);
      expect(SelfDepositState.visible, isFalse);
    });

    test('٤٠٤ يُسجَّل مرّةً فلا يُطرق المسار كلّ مرّة', () async {
      server.reply('GET', '/api/v2/self-deposit/options', 404, {'success': false});
      await SelfDepositState.ensureFresh();
      await SelfDepositState.ensureFresh(); // لا طلب: غير مدعوم
      expect(server.calls('GET', '/api/v2/self-deposit/options'), hasLength(1));
      expect(SelfDepositState.visible, isFalse);
    });

    test('الفشل لا يُظهر ولا يمسح ما نعرفه', () async {
      SelfDepositState.debugSet(SelfDepositOptions.fromJson(
          {'enabled': true, 'supported': true, 'methods': [zc]}));
      server.on('GET', '/api/v2/self-deposit/options', simTimeout);
      await SelfDepositState.ensureFresh(force: true);
      expect(SelfDepositState.visible, isTrue);
    });
  });


  group('عقد خادم Pro (sasSelfDeposit.js)', () {
    final card = SelfDepositMethod.fromJson(Map<String, dynamic>.from(voucher))!;
    final psid = 'b' * 32;

    test('🚨 ٥٠٣ من خادمنا بحكمٍ (الشركة لا تُجيب) ⇒ «لم يُستعمل الكارت» لا «تعذّر التأكّد»', () async {
      server.reply('POST', '/api/v2/self-deposit/request', 503, {
        'success': false,
        'code': 'SAS_UNREACHABLE',
        'message': 'تعذّر الاتّصال بالشركة — لم يُستعمل الكارت، أعد المحاولة',
        'psid': psid,
        'status': 'failed',
      });
      final s = await SelfDepositApi.request(method: card, pin: '12345678');
      expect(s.outcome!.status, SelfDepositStatus.failed);
      expect(s.outcome!.offline, isFalse);
      expect(s.outcome!.message, contains('لم يُستعمل الكارت'));
    });

    test('رفضٌ قبل أن تبدأ (مبلغ، مشغول، حدّ المحاولات) ⇒ رسالة لا نتيجة', () async {
      server.reply('POST', '/api/v2/self-deposit/request', 429, {
        'success': false,
        'code': 'PIN_LOCKED',
        'message': 'محاولاتٌ كثيرة برمزٍ غير صحيح — انتظر نصف ساعة ثمّ حاول من جديد',
      });
      final s = await SelfDepositApi.request(method: card, pin: '12345678');
      expect(s.outcome, isNull);
      expect(s.code, 'PIN_LOCKED');
      expect(s.message, contains('نصف ساعة'));
    });

    test('٤٠٩ UNVERIFIED للكارت (بحالته) ⇒ غير مؤكَّدة', () async {
      server.reply('POST', '/api/v2/self-deposit/request', 409, {
        'success': false,
        'code': 'UNVERIFIED',
        'message': 'تعذّر التأكّد من نتيجة التعبئة — راجع رصيدك قبل إعادة المحاولة (الكارت لا يُشحن مرّتين)',
        'psid': psid,
        'status': 'unverified',
      });
      final s = await SelfDepositApi.request(method: card, pin: '12345678');
      expect(s.outcome!.status, SelfDepositStatus.unverified);
      expect(s.outcome!.checkable, isTrue);
    });

    test('complete: ٤٢٢ بصفّ العمليّة (لم يكتمل الدفع) ⇒ حكمٌ نهائيّ برسالته ورقم زين كاش', () async {
      server.reply('POST', '/api/v2/self-deposit/complete', 422, {
        'success': false,
        'psid': psid,
        'status': 'failed',
        'state': 'failed',
        'flow': 'redirect',
        'code': 'PAYMENT_NOT_COMPLETED',
        'pay_ref': 'ZC-7781',
        'message': 'لم يكتمل الدفع في زين كاش — لم يُضَف شيء إلى رصيدك',
        'final': true,
      });
      final o = await SelfDepositApi.complete(
          psid: psid, returnUrl: 'https://sas/#/zaincash/process?token=a.b.c');
      expect(o.status, SelfDepositStatus.failed);
      expect(o.isFinal, isTrue);
      expect(o.ref, 'ZC-7781');
    });

    test('🚨 complete: ٤٠٩ PAID_NOT_CREDITED (زين كاش قال دُفع) ⇒ غير مؤكَّدة لا فشل', () async {
      server.reply('POST', '/api/v2/self-deposit/complete', 409, {
        'success': false,
        'psid': psid,
        'status': 'unverified',
        'code': 'PAID_NOT_CREDITED',
        'message': 'زين كاش أكّد الدفع لكنّ الشركة لم تُضِف الرصيد بعد — راجع رصيدك بعد دقائق',
      });
      final o = await SelfDepositApi.complete(
          psid: psid, returnUrl: 'https://sas/#/zaincash/process?token=a.b.c');
      expect(o.status, SelfDepositStatus.unverified);
      expect(o.isFinal, isFalse);
    });

    test('🚨 complete: مشغولٌ/الشركة لا تُجيب/الجلسة ⇒ يبقى التوكن ويُعاد (لا حكم)', () async {
      for (final r in [
        (409, 'IN_PROGRESS'),
        (503, 'SAS_UNREACHABLE'),
        (503, 'NOT_READY'),
        (422, 'IDENTITY_UNKNOWN'),
      ]) {
        server.reply('POST', '/api/v2/self-deposit/complete', r.$1,
            {'success': false, 'code': r.$2, 'message': 'أعد المحاولة بعد لحظات (الدفع محفوظ)'});
        final o = await SelfDepositApi.complete(
            psid: psid, returnUrl: 'https://sas/#/zaincash/process?token=a.b.c');
        expect(o.offline, isTrue, reason: r.$2);
        expect(o.isFinal, isFalse, reason: r.$2);
      }
    });

    test('complete: ٢٠٢ (يُعالَج الآن) ⇒ قيد التحقّق — لا يُمحى التوكن', () async {
      server.reply('POST', '/api/v2/self-deposit/complete', 202,
          {'success': true, 'psid': psid, 'status': 'processing', 'message': 'جارٍ التأكّد من العمليّة…'});
      final o = await SelfDepositApi.complete(
          psid: psid, returnUrl: 'https://sas/#/zaincash/process?token=a.b.c');
      expect(o.status, SelfDepositStatus.pending);
      expect(o.isFinal, isFalse);
    });

    test('🚨 complete: رجوعٌ لا يعرفه الخادم ⇒ يحفظه للمراجعة (409 بصفّه، received) ⇒ يُمحى من الهاتف بلا «فشل»', () async {
      server.reply('POST', '/api/v2/self-deposit/complete', 409, {
        'success': false,
        'psid': psid,
        'status': 'unverified',
        'code': 'RETURN_UNRECOGNIZED',
        'message': 'وصل من صفحة الدفع رجوعٌ لم نستطع التحقّق منه — حفظناه ولم نُرسله للشركة.',
        'final': false,
        'received': true,
        'kept': true,
      });
      final o = await SelfDepositApi.complete(
          psid: psid, returnUrl: 'https://10.0.0.5/zaincash/process?token=a.b.c');
      expect(o.status, SelfDepositStatus.unverified);
      expect(o.isFinal, isFalse);
      expect(o.settled, isTrue);
      expect(o.code, 'RETURN_UNRECOGNIZED');
    });

    test('status يطلب المراجعة من الساس (check=1) ويقرأ الرصيد بعدها', () async {
      server.reply('GET', '/api/v2/self-deposit/status/$psid', 200, {
        'success': true,
        'psid': psid,
        'status': 'success',
        'credited': 25000,
        'balance': null,
        'balance_after': 1275000,
        'final': true,
      });
      final o = await SelfDepositApi.status(psid);
      expect(o.status, SelfDepositStatus.success);
      expect(o.balance, 1275000);
      final q = server.calls('GET', '/api/v2/self-deposit/status/$psid').single;
      expect(q.queryParameters['check'], 1);
    });

    test('history: الصفوف بحالها ووسيلتها ووقتها', () async {
      server.reply('GET', '/api/v2/self-deposit/history', 200, {
        'success': true,
        'ready': true,
        'items': [
          {
            'psid': psid,
            'status': 'pending',
            'flow': 'redirect',
            'gateway': 'zaincash',
            'gateway_name': 'ZainCash',
            'amount': 25000,
            'pay_ref': 'ZC-1',
            'created_at': '2026-10-18T09:00:00.000Z',
          },
          {
            'psid': 'c' * 32,
            'status': 'success',
            'flow': 'pin',
            'gateway': 'kushok',
            'credited': 10000,
            'created_at': '2026-10-18T08:00:00.000Z',
          },
          {'status': 'success'}, // بلا معرّف — يسقط
        ],
      });
      final h = (await SelfDepositApi.history())!;
      expect(h, hasLength(2));
      expect(h.first.label, 'زين كاش');
      expect(h.first.outcome.checkable, isTrue);
      expect(h.first.outcome.ref, 'ZC-1');
      expect(h.last.label, 'كارت كوشك');
      expect(h.last.outcome.credited, 10000);
      expect(h.first.createdAt!.isUtc, isFalse);
    });

    test('options الكامل: الوسائل بنوعها وحدودها، والشركة ويوزر الصفحة', () async {
      server.reply('GET', '/api/v2/self-deposit/options', 200, {
        'success': true,
        'enabled': true,
        'currency': 'IQD',
        'company': {'code': 'supernet', 'name': 'سوبرنت'},
        'limits': {'min_amount': 1000, 'max_amount': 5000000},
        'panel_url': 'https://sas.example.iq/#/manager/selfDeposit',
        'capture': {'routes': ['/zaincash/process', '/zaincashv2/process']},
        'balance': 46000.0,
        'manager': {'username': 'ali'},
        'supported': true,
        'reason': null,
        'message': null,
        'methods': [
          {
            'id': 3, 'name': 'ZainCash', 'type': 'zaincash', 'flow': 'redirect',
            'in_app': true, 'web': false,
            'needs': {'amount': true, 'pin': false, 'name': false, 'phone': false},
            'min_amount': 1000, 'max_amount': 5000000,
          },
          {
            'id': 9, 'name': 'HyperPay', 'type': 'hyperpay', 'flow': 'external',
            'in_app': false, 'web': false,
            'needs': {'amount': false, 'pin': false, 'name': false, 'phone': false},
            'min_amount': null, 'max_amount': null,
          },
        ],
      });
      final o = (await SelfDepositApi.options()).data!;
      expect(o.block, SelfDepositBlock.none);
      expect(o.companyName, 'سوبرنت');
      expect(o.sasUsername, 'ali');
      expect(o.methods.first.minAmount, 1000);
      expect(o.methods.first.maxAmount, 5000000);
      expect(o.methods.last.inApp, isFalse);
      expect(o.balance, 46000);
    });

    test('options: not_ready/read_failed ⇒ «تعذّرت القراءة» لا «غير مدعومة»', () async {
      for (final reason in ['not_ready', 'read_failed']) {
        final o = SelfDepositOptions.fromJson({
          'success': true, 'enabled': true, 'supported': null, 'reason': reason, 'methods': [],
        });
        expect(o.block, SelfDepositBlock.none, reason: reason);
        expect(o.supported, isNull);
      }
    });

    test('🚨 البطاقة تسأل probe (بلا نداءٍ للساس) — ولا يمحو ردُّه تفاصيل الشاشة', () async {
      server.reply('GET', '/api/v2/self-deposit/options', 200,
          {'success': true, 'enabled': true});
      await SelfDepositState.ensureFresh();
      final q = server.calls('GET', '/api/v2/self-deposit/options').single;
      expect(q.queryParameters['probe'], 1);
      expect(SelfDepositState.visible, isTrue);
      // الشاشة قرأت التفاصيل: صفحةٌ بلا صلاحيّة.
      SelfDepositState.apply(SelfDepositOptions.fromJson({
        'enabled': true, 'supported': false, 'reason': 'no_permission',
      }));
      await SelfDepositState.ensureFresh(force: true);
      expect(SelfDepositState.gate.value!.block, SelfDepositBlock.noPermission);
      // والإطفاء يغلب: probe يقول مطفأة ⇒ تختفي.
      server.reply('GET', '/api/v2/self-deposit/options', 200,
          {'success': true, 'enabled': false});
      await SelfDepositState.ensureFresh(force: true);
      expect(SelfDepositState.visible, isFalse);
    });
  });

  group('🚨 قيود زين كاش المعلّقة — لا يضيع توكن', () {
    SelfDepositPending p(String psid, {String admin = '2251', DateTime? at}) =>
        SelfDepositPending(
          psid: psid,
          adminId: admin,
          createdAt: at ?? DateTime.now(),
          amount: 25000,
          methodLabel: 'زين كاش',
        );

    test('يُحفظ، ثمّ يُلحق به الرجوع، ثمّ يُمحى بالحكم', () async {
      await SelfDepositPendingStore.put(p('sd_1'));
      await SelfDepositPendingStore.attachReturnUrl(
          'sd_1', 'https://sas/#/zaincash/process?token=t1');
      final got = await SelfDepositPendingStore.forAdmin('2251');
      expect(got.single.returnUrl, contains('token=t1'));
      expect(got.single.amount, 25000);
      await SelfDepositPendingStore.remove('sd_1');
      expect(await SelfDepositPendingStore.forAdmin('2251'), isEmpty);
    });

    test('لكلّ مديرٍ قيوده — لا تُرسل في جلسة غيره', () async {
      await SelfDepositPendingStore.put(p('sd_a', admin: '2251'));
      await SelfDepositPendingStore.put(p('sd_b', admin: 'jt:77'));
      expect((await SelfDepositPendingStore.forAdmin('2251')).map((e) => e.psid),
          ['sd_a']);
      expect(await SelfDepositPendingStore.forAdmin(null), isEmpty);
    });

    test('المذكّرات (بلا رجوع): القديمة تسقط والعدد محدود', () async {
      await SelfDepositPendingStore.put(
          p('old', at: DateTime.now().subtract(const Duration(hours: 30))));
      for (var i = 0; i < 7; i++) {
        await SelfDepositPendingStore.put(p('n$i'));
      }
      final got = await SelfDepositPendingStore.forAdmin('2251');
      expect(got.map((e) => e.psid), isNot(contains('old')));
      expect(got, hasLength(SelfDepositPendingStore.maxEntries));
      expect(got.last.psid, 'n6');
    });

    test('🚨 قيدٌ فيه رابط رجوع لا يُطرد بالعدد ولا يسقط بيوم — يبقى حتى حكم الخادم', () async {
      await SelfDepositPendingStore.put(SelfDepositPending(
        psid: 'cap_old',
        adminId: '2251',
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        returnUrl: 'https://sas/#/zaincash/process?token=t0',
      ));
      for (var i = 0; i < 8; i++) {
        await SelfDepositPendingStore.put(p('n$i'));
      }
      final got = await SelfDepositPendingStore.forAdmin('2251');
      expect(got.map((e) => e.psid), contains('cap_old'));
      expect(got.where((e) => e.returnUrl == null), hasLength(SelfDepositPendingStore.maxEntries));
      // وبعد ٣٠ يوماً يسقط (الخادم يمحو ما يحفظه بعد ٧).
      await SelfDepositPendingStore.put(SelfDepositPending(
        psid: 'cap_ancient',
        adminId: '2251',
        createdAt: DateTime.now().subtract(const Duration(days: 31)),
        returnUrl: 'https://sas/#/zaincash/process?token=t9',
      ));
      expect((await SelfDepositPendingStore.forAdmin('2251')).map((e) => e.psid),
          isNot(contains('cap_ancient')));
    });

    test('🚨 الرجوع وصل والقيد غائب (فشلت كتابته عند البدء) ⇒ يُنشأ ولا يبقى في الذاكرة وحدها', () async {
      await SelfDepositPendingStore.attachReturnUrl(
          'sd_new', 'https://sas/#/zaincash/process?token=z9',
          adminId: '2251', amount: 15000, methodLabel: 'زين كاش');
      final got = (await SelfDepositPendingStore.forAdmin('2251')).single;
      expect(got.psid, 'sd_new');
      expect(got.returnUrl, contains('token=z9'));
      expect(got.amount, 15000);
      // بلا معرّف مديرٍ لا يُنشأ قيدٌ يتيم.
      await SelfDepositPendingStore.attachReturnUrl('sd_x', 'https://sas/#/zaincash/process?token=q');
      expect((await SelfDepositPendingStore.forAdmin('2251')).map((e) => e.psid), ['sd_new']);
    });

    test('العمليّات المتزامنة لا تمحو بعضها', () async {
      await Future.wait([
        SelfDepositPendingStore.put(p('c1')),
        SelfDepositPendingStore.put(p('c2')),
        SelfDepositPendingStore.attachReturnUrl('c1', 'https://sas/#/zaincash/process?token=z'),
      ]);
      final got = await SelfDepositPendingStore.forAdmin('2251');
      expect(got.map((e) => e.psid).toSet(), {'c1', 'c2'});
      expect(got.firstWhere((e) => e.psid == 'c1').returnUrl, isNotNull);
    });
  });


  group('🚨 التسليم في الخلفيّة (SelfDepositSync) — مستقلٌّ عن الشاشة والمفتاح', () {
    SelfDepositPending cap(String psid, {int minutesAgo = 0, String admin = '2251'}) => SelfDepositPending(
          psid: psid,
          adminId: admin,
          createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
          amount: 25000,
          returnUrl: 'https://sas.x.iq/#/zaincash/process?token=$psid.aaaa.bbbb',
        );
    Map<String, Object?> settled(String psid) => {
          'success': true, 'psid': psid, 'status': 'success', 'final': true, 'received': true, 'credited': 25000,
        };

    test('كلّ القيود الملتقطة (لا ثلاثة فقط)، الأقدم أوّلاً، بلا سؤال options — والمحسومة تُمحى', () async {
      for (var i = 0; i < 5; i++) {
        await SelfDepositPendingStore.put(cap('p$i', minutesAgo: 50 - i));
      }
      await SelfDepositPendingStore.put(SelfDepositPending(psid: 'plain', adminId: '2251', createdAt: DateTime.now()));
      server.on('POST', '/api/v2/self-deposit/complete', (o) {
        final psid = (o.data as Map)['psid'] as String;
        return SimReply(200, settled(psid));
      });
      final rep = await SelfDepositSync.run(force: true);
      final sent = server.bodies('POST', '/api/v2/self-deposit/complete').map((b) => b['psid']).toList();
      expect(sent, ['p0', 'p1', 'p2', 'p3', 'p4']);
      expect(rep.results, hasLength(5));
      expect(server.calls('GET', '/api/v2/self-deposit/options'), isEmpty, reason: 'المفتاح لا يحكم التسليم');
      expect((await SelfDepositPendingStore.forAdmin('2251')).map((e) => e.psid), ['plain'],
          reason: 'المذكّرة بلا رجوع لا تُرسل هنا');
    });

    test('بلا اتّصال أو ردٌّ بلا صفّ ⇒ يبقى القيد؛ والمستلَم للمراجعة يُمحى', () async {
      await SelfDepositPendingStore.put(cap('a1', minutesAgo: 3));
      await SelfDepositPendingStore.put(cap('a2', minutesAgo: 2));
      await SelfDepositPendingStore.put(cap('a3', minutesAgo: 1));
      SelfDepositSync.retryDelays = const [];
      server.on('POST', '/api/v2/self-deposit/complete', (o) {
        final psid = (o.data as Map)['psid'] as String;
        if (psid == 'a1') return simTimeout(o);
        if (psid == 'a2') {
          return const SimReply(404, {'success': false, 'code': 'NOT_FOUND', 'message': 'غير موجودة'});
        }
        return SimReply(409, {'success': false, 'psid': psid, 'status': 'unverified', 'code': 'TOO_OLD', 'final': false, 'received': true});
      });
      final rep = await SelfDepositSync.run(force: true);
      expect(rep.pendingLeft, isTrue);
      expect((await SelfDepositPendingStore.forAdmin('2251')).map((e) => e.psid), ['a1', 'a2']);
    });

    test('مهلة الجولات للمصادر الآليّة، والعودة للواجهة تُطلقها؛ وجلسة مديرٍ آخر لا تُرسل قيوده', () async {
      await SelfDepositPendingStore.put(cap('b1'));
      await SelfDepositPendingStore.put(cap('other', admin: 'jt:77'));
      server.on('POST', '/api/v2/self-deposit/complete', (o) => SimReply(200, settled((o.data as Map)['psid'] as String)));
      SelfDepositSync.install();
      AppResumedSignal.bump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.bodies('POST', '/api/v2/self-deposit/complete').map((b) => b['psid']), ['b1']);
      await SelfDepositPendingStore.put(cap('b2'));
      AppResumedSignal.bump(); // خلال المهلة: لا جولة
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.calls('POST', '/api/v2/self-deposit/complete'), hasLength(1));
      await SelfDepositSync.run(force: true);
      expect(server.calls('POST', '/api/v2/self-deposit/complete'), hasLength(2));
      expect((await SelfDepositPendingStore.forAdmin('jt:77')).single.psid, 'other');
    });

    test('بعد رجوعٍ لم يصل: إعادةٌ متباعدة تلقائيّة حتى يُسلَّم', () async {
      await SelfDepositPendingStore.put(cap('r1'));
      SelfDepositSync.retryDelays = const [Duration(milliseconds: 40), Duration(milliseconds: 40)];
      var online = false;
      server.on('POST', '/api/v2/self-deposit/complete', (o) => online ? SimReply(200, settled('r1')) : simTimeout(o));
      await SelfDepositSync.run(force: true);
      expect(server.calls('POST', '/api/v2/self-deposit/complete'), hasLength(1));
      online = true;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(server.calls('POST', '/api/v2/self-deposit/complete'), hasLength(2));
      expect(await SelfDepositPendingStore.forAdmin('2251'), isEmpty);
    });

    test('بلا جلسة لا شيء', () async {
      await SelfDepositPendingStore.put(cap('n1'));
      FlutterSecureStorage.setMockInitialValues({});
      final rep = await SelfDepositSync.run(force: true);
      expect(rep.ran, isFalse);
      expect(server.requests, isEmpty);
    });
  });

  test('الجسم لا يُطبع: لا رمز ولا توكن في سجلّ التطوير', () {
    // حارسٌ نصّيّ: كلّ طباعةٍ في الملفّ نوع الخطأ وحده — لا جسم طلبٍ ولا ردّ
    // (فيهما رمز الكارت أو توكن زين كاش).
    final src = File('lib/api/self_deposit_api.dart').readAsStringSync();
    final prints = RegExp(r'debugPrint\((.*)\)').allMatches(src).toList();
    expect(prints, hasLength(1));
    expect(prints.single.group(1), contains(r'${e.runtimeType}'));
    expect(src.contains('print(r.data'), isFalse);
  });
}
