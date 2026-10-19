import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/ai_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/core/platform/store_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sim_el/sim_harness.dart' show SimReply, SimServer, simTimeout;

/// المساعد الذكيّ — عقد `/api/v2/ai/*` كما يقرؤه التطبيق (SPEC §4).
///
/// ما لم يقل الخادم `enabled:true` صراحةً لا يظهر شيء؛ ورسائل الخادم تُعرض
/// كما هي؛ وما يغادر الهاتف تُخفى منه الهواتف والأرقام الطويلة والتوكنات.
/// توقيعٌ بشكل الخادم (٣٢ خانة base64url).
const sig32 = 'AbCdEfGhIjKlMnOpQrStUvWxYz012345';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const statusPath = '/api/v2/ai/status';
  const explainPath = '/api/v2/ai/explain';
  const askPath = '/api/v2/ai/ask';

  late SimServer server;
  late SimServer accountServer;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'auth.token': 'sim-token',
      'auth.admin_id': '2251',
    });
    SharedPreferences.setMockInitialValues({});
    server = SimServer();
    ApiClient.dio.httpClientAdapter = server;
    accountServer = SimServer();
    AiApi.accountDio.httpClientAdapter = accountServer;
    AiApi.hasAccount = () => false;
    AiApi.accountTokenSource = ({bool force = false}) async => null;
    StorePolicy.debugHidePurchaseFlows = null;
  });

  tearDown(() {
    StorePolicy.debugHidePurchaseFlows = null;
  });

  const on = {
    'success': true,
    'enabled': true,
    'can_use': true,
    'explain': true,
    'ask': true,
    'quota': {
      'left': 7,
      'limit': 10,
      'scope': 'account',
      'resets_at': '2026-10-19T00:00:00+03:00'
    },
    'plan': {'code': 'trial', 'label': 'تجربة'},
    'upgrade_hint': 'باقة الأعمال: 100 سؤال باليوم',
    'suggestions': ['شلون أفعّل مشترك بالكارت؟', 'شلون أربط الواتساب؟'],
    'slogan': 'أوّل نظام وكلاء بالعراق بيه مساعد ذكي',
    'disclaimer': 'المساعد يشرح ويرشد فقط — ما ينفّذ أيّ عمليّة',
  };

  group('الحالة (status)', () {
    test('مفتوحة: الحصّة والاقتراحات، و«اشرحلي» و«كيف أسوّي؟» لجلسة الشركة',
        () async {
      server.reply('GET', statusPath, 200, on);
      final s = (await AiApi.status())!;
      expect(s.enabled, isTrue);
      expect(s.canExplain, isTrue);
      expect(s.canAsk, isTrue);
      expect(s.locked, isFalse);
      expect(s.mode, AiMode.company);
      expect(s.quota!.left, 7);
      expect(s.quota!.limit, 10);
      expect(s.quota!.resetsAt, isNotNull);
      expect(s.planLabel, 'تجربة');
      expect(s.suggestions, hasLength(2));
      expect(s.upgradeHint, isNotNull);
    });

    test(
        '🚨 enabled:false · ردٌّ بلا كلام الميزة · ٤٠٤ · ٤٠٣ ⇒ مطفأة (لا شيء يظهر)',
        () async {
      for (final (code, body) in <(int, Map<String, dynamic>)>[
        (200, {'success': true, 'enabled': false}),
        (200, {'success': true}),
        (200, {'success': true, 'enabled': 'true'}),
        (404, {'success': false, 'message': 'غير موجود'}),
        (
          403,
          {
            'success': false,
            'code': 'EMPLOYEE_ACCESS_DENIED',
            'message': 'حساب الموظف معطّل'
          }
        ),
      ]) {
        server.reply('GET', statusPath, code, body);
        final s = await AiApi.status();
        expect(s, isNotNull, reason: '$code $body');
        expect(s!.enabled, isFalse, reason: '$code $body');
        expect(s.canExplain || s.canAsk || s.locked, isFalse,
            reason: '$code $body');
      }
    });

    test(
        '٥٠٣ «أعد المحاولة» وانقطاع الشبكة ⇒ لا نعرف (null) — تبقى الحالة كما هي',
        () async {
      server.reply('GET', statusPath, 503, {
        'success': false,
        'code': 'AI_IDENTITY_RETRY',
        'message': 'تعذّر التعرّف على حسابك — أعد المحاولة'
      });
      expect(await AiApi.status(), isNull);
      server.on('GET', statusPath, simTimeout);
      expect(await AiApi.status(), isNull);
    });

    test('موظّفٌ بلا الصلاحيّة ⇒ مقفلةٌ بمكانها (لا مخفيّة) ولا «اشرحلي»',
        () async {
      server.reply('GET', statusPath, 200, {
        'success': true,
        'enabled': true,
        'can_use': false,
        'reason': 'no_permission',
        'locked_text': 'ما عندك صلاحيّة المساعد — اطلبها من مديرك',
      });
      final s = (await AiApi.status())!;
      expect(s.locked, isTrue);
      expect(s.canExplain, isFalse);
      expect(s.canAsk, isFalse);
      expect(s.lockedText, contains('اطلبها من مديرك'));
    });

    test('بلا جلسة شركة ولا حساب ⇒ لا يُطرق الخادم', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final s = await AiApi.status();
      expect(s!.enabled, isFalse);
      expect(server.requests, isEmpty);
      expect(accountServer.requests, isEmpty);
    });

    test(
        'حساب Pro وحده (الدخول/«شركاتي») ⇒ توكن الحساب على عميلٍ مستقلّ، و«اشرحلي» وحده',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      AiApi.hasAccount = () => true;
      AiApi.accountTokenSource = ({bool force = false}) async => 'acct-token';
      accountServer.reply('GET', statusPath, 200,
          Map<String, dynamic>.from(on)..['ask'] = false);
      final s = (await AiApi.status())!;
      expect(s.mode, AiMode.account);
      expect(s.canExplain, isTrue);
      expect(s.canAsk, isFalse, reason: '«كيف أسوّي؟» لجلسة الشركة وحدها');
      expect(server.requests, isEmpty, reason: 'لا شيء على عميل الجلسة');
      final h = accountServer.requests.single.headers;
      expect(h['x-account-token'], 'acct-token');
      expect(h['x-device-id'], isNotNull);
      expect(h['x-device-label'], anyOf('ios', 'android'));
      expect(h.containsKey('Authorization'), isFalse);
    });
  });

  group('«اشرحلي» (explain)', () {
    final answer = {
      'success': true,
      'answer': {
        'title': 'ما تگدر تغيّر باقة مشترك فعّال «حالاً»',
        'body': 'الساس يصفّر تاريخ الانتهاء.',
        'steps': ['افتح المشترك', 'اختار «عند الانتهاء»', 'احفظ'],
        'status': 'answered',
        'related': ['تغيير الباقة'],
      },
      'support': null,
      'quota': {
        'left': 6,
        'limit': 10,
        'scope': 'account',
        'resets_at': '2026-10-19T00:00:00+03:00'
      },
      'cached': false,
      'tier': 'light',
      'ref': 'c8f1a2b3',
    };

    test(
        'الطلب: الرمز والشاشة والحالة والسياق المسموح وحده، والنصّ بلا هاتف ولا PIN',
        () async {
      server.reply('POST', explainPath, 200, answer);
      final r = await AiApi.explain(const ExplainRequest(
        code: 'PACKAGE_CHANGE_ACTIVE_FORBIDDEN',
        message: 'فشل للمشترك 07701234567 — PIN: 123456789012 — المبلغ 25,000',
        screen: 'package_change',
        httpStatus: 403,
        context: {
          'action': 'package_change',
          'package_change_mode': 'now',
          'method': 'free text not allowed',
          'username': 'ahmed',
        },
      ));
      expect(r.ok, isTrue);
      final body = server.bodies('POST', explainPath).single;
      expect(body['code'], 'PACKAGE_CHANGE_ACTIVE_FORBIDDEN');
      expect(body['screen'], 'package_change');
      expect(body['http_status'], 403);
      expect(body['lang'], 'ar');
      expect(body['context'],
          {'action': 'package_change', 'package_change_mode': 'now'});
      final msg = body['message'] as String;
      expect(msg, isNot(contains('07701234567')));
      expect(msg, isNot(contains('123456789012')));
      expect(msg, contains('[رقم مخفي]'));
      expect(msg, contains('25,000'), reason: 'المبالغ المجمّعة تبقى');
    });

    test('الجواب: العنوان والخطوات والحصّة والمرجع', () async {
      server.reply('POST', explainPath, 200, answer);
      final r = await AiApi.explain(
          const ExplainRequest(code: 'X_Y', screen: 'nope'));
      expect(server.bodies('POST', explainPath).single['screen'], 'other');
      expect(r.answer!.title, contains('ما تگدر'));
      expect(r.answer!.steps, hasLength(3));
      expect(r.answer!.related, ['تغيير الباقة']);
      expect(r.answer!.wantsSupport, isFalse);
      expect(r.quota!.left, 6);
      expect(r.ref, 'c8f1a2b3');
      expect(r.answer!.plainText, contains('1. افتح المشترك'));
    });

    test('ماكو ما يُشرح ⇒ لا طلب', () async {
      final r = await AiApi.explain(const ExplainRequest(message: '   '));
      expect(r.failure!.code, 'AI_BAD_INPUT');
      expect(server.requests, isEmpty);
    });

    test('روابط الدعم: https على تلغرام/واتساب وحدهما', () async {
      server.reply('POST', explainPath, 200, {
        ...answer,
        'answer': {
          ...answer['answer'] as Map<String, dynamic>,
          'status': 'needs_support'
        },
        'support': {
          'telegram': 'https://t.me/mysvcs',
          'whatsapp': 'http://wa.me/9647700000000'
        },
      });
      final r = await AiApi.explain(const ExplainRequest(code: 'SAS_REJECTED'));
      expect(r.answer!.wantsSupport, isTrue);
      expect(r.support!.telegram.toString(), 'https://t.me/mysvcs');
      expect(r.support!.whatsapp, isNull, reason: 'http لا يُفتح');
      server.reply('POST', explainPath, 200, {
        ...answer,
        'support': {'telegram': 'https://evil.example/t.me', 'whatsapp': null},
      });
      expect(
          (await AiApi.explain(const ExplainRequest(code: 'SAS_REJECTED')))
              .support,
          isNull);
    });

    test('رموز الرفض (SPEC §4.5) برسائل الخادم كما هي', () async {
      final cases = <(int, String, String)>[
        (403, 'AI_NO_PERMISSION', 'ما عندك صلاحيّة المساعد — اطلبها من مديرك'),
        (403, 'AI_ACCOUNT_REQUIRED', 'سجّل الدخول بحسابك أوّلاً'),
        (
          403,
          'AI_NO_PLAN',
          'المساعد يحتاج اشتراكاً فعّالاً — فعّل اشتراكك وارجع'
        ),
        (400, 'AI_BAD_INPUT', 'ماكو خطأ أشرحه'),
        (
          429,
          'AI_QUOTA_EXHAUSTED',
          'خلصت أسئلة اليوم — ترجع باچر أو رقّي باقتك'
        ),
        (
          429,
          'AI_RATE_LIMITED',
          'كثّرت الأسئلة بسرعة — استنّى دقيقة وارجع اسأل'
        ),
        (429, 'AI_BUSY', 'لحظة، دا أكمّل جواب سؤالك السابق'),
        (
          403,
          'EMPLOYEE_ACCESS_DENIED',
          'حساب الموظف معطّل أو تعذّر التحقق منه'
        ),
      ];
      for (final (code, serverCode, msg) in cases) {
        server.reply('POST', explainPath, code, {
          'success': false,
          'code': serverCode,
          'message': msg,
          if (serverCode == 'AI_QUOTA_EXHAUSTED')
            'quota': {'left': 0, 'limit': 10},
        });
        final r =
            await AiApi.explain(const ExplainRequest(code: 'SAS_REJECTED'));
        expect(r.ok, isFalse, reason: serverCode);
        expect(r.failure!.code, serverCode);
        expect(r.failure!.message, msg);
        expect(r.failure!.status, code);
      }
      final last = await AiApi.explain(const ExplainRequest(
          code: 'SAS_REJECTED')); // آخرها EMPLOYEE_ACCESS_DENIED
      expect(last.failure!.blocksInput, isTrue);
    });

    test('الحصّة والصلاحيّة تقفلان الحقل، والتعذّر العابر يقبل «أعد المحاولة»',
        () {
      AiFailure f(String code, int status) => AiApi.replyFrom(
          status, {'success': false, 'code': code, 'message': 'x'}).failure!;
      expect(f('AI_QUOTA_EXHAUSTED', 429).blocksInput, isTrue);
      expect(f('AI_NO_PERMISSION', 403).blocksInput, isTrue);
      expect(f('AI_RATE_LIMITED', 429).blocksInput, isFalse);
      expect(f('AI_RATE_LIMITED', 429).retryable, isTrue);
      expect(f('AI_UNAVAILABLE', 503).retryable, isTrue);
      expect(f('AI_QUOTA_EXHAUSTED', 429).retryable, isFalse);
    });

    test('٥٠٣ من خادمنا (استثناء Dio) يُقرأ حكماً برسالته', () async {
      server.reply('POST', explainPath, 503, {
        'success': false,
        'code': 'AI_UNAVAILABLE',
        'message': 'المساعد مو متاح هسه — جرّب بعد شوية (ما انحسب من أسئلتك)',
      });
      final r = await AiApi.explain(const ExplainRequest(code: 'SAS_REJECTED'));
      expect(r.failure!.code, 'AI_UNAVAILABLE');
      expect(r.failure!.message, contains('ما انحسب'));
      expect(r.failure!.retryable, isTrue);
    });

    test('٤٠٤ ⇒ أُطفئت (isOff)، وانقطاعٌ ⇒ رسالة شبكةٍ قابلة للإعادة',
        () async {
      server.reply(
          'POST', explainPath, 404, {'success': false, 'message': 'غير موجود'});
      final off =
          await AiApi.explain(const ExplainRequest(code: 'SAS_REJECTED'));
      expect(off.failure!.isOff, isTrue);
      expect(off.failure!.blocksInput, isTrue);
      server.on('POST', explainPath, simTimeout);
      final net =
          await AiApi.explain(const ExplainRequest(code: 'SAS_REJECTED'));
      expect(net.failure!.status, isNull);
      expect(net.failure!.retryable, isTrue);
      expect(server.calls('POST', explainPath), hasLength(2),
          reason: 'لا إعادة تلقائيّة لـPOST');
    });

    test('🍏 آيفون: جملة الترقية تسقط من الجواب حتى لو أفلتت من الخادم',
        () async {
      StorePolicy.debugHidePurchaseFlows = true;
      server.reply('POST', explainPath, 200, {
        ...answer,
        'answer': {
          'title': 'خلصت أسئلة اليوم — ترجع باچر أو رقّي باقتك',
          'body': 'رقّي باقتك',
          'steps': ['رقّي باقتك من الإعدادات', 'ارجع باچر'],
          'status': 'answered',
          'related': [],
        },
      });
      final a =
          (await AiApi.explain(const ExplainRequest(code: 'SAS_REJECTED')))
              .answer!;
      expect(a.title, 'خلصت أسئلة اليوم — ترجع باچر');
      expect(a.body, isEmpty);
      expect(a.steps, ['ارجع باچر']);
    });

    test('حساب Pro وحده: توكن حسابٍ رُفض ⇒ يُجدَّد مرّةً ويُعاد', () async {
      FlutterSecureStorage.setMockInitialValues({});
      AiApi.hasAccount = () => true;
      final forced = <bool>[];
      AiApi.accountTokenSource = ({bool force = false}) async {
        forced.add(force);
        return force ? 'fresh' : 'stale';
      };
      accountServer.on(
          'POST',
          explainPath,
          (o) => o.headers['x-account-token'] == 'fresh'
              ? SimReply(200, answer)
              : const SimReply(403, {
                  'success': false,
                  'code': 'AI_ACCOUNT_REQUIRED',
                  'message': 'سجّل الدخول بحسابك أوّلاً'
                }));
      final r = await AiApi.explain(
          const ExplainRequest(code: 'company-limit', screen: 'login'));
      expect(r.ok, isTrue);
      expect(forced, [false, true]);
      expect(server.requests, isEmpty);
    });
  });

  group('«كيف أسوّي؟» (ask)', () {
    test('السؤال والسياق: آخر ستّ رسائل تبدأ بسؤالٍ وتتناوب', () async {
      server.reply('POST', askPath, 200, {
        'success': true,
        'answer': {
          'title': 'جواب',
          'body': '',
          'steps': [],
          'status': 'answered',
          'related': []
        },
      });
      final history = [
        const AiTurn.assistant('يتيم يُسقَط', sig: sig32),
        for (var i = 0; i < 5; i++) ...[
          AiTurn.user('س$i'),
          AiTurn.assistant('ج$i', sig: sig32)
        ],
        const AiTurn.user('سؤالٌ بلا جواب'),
      ];
      await AiApi.ask('شلون أربط الواتساب؟ 07801234567',
          history: history, screen: 'whatsapp');
      final body = server.bodies('POST', askPath).single;
      expect(body['question'], isNot(contains('07801234567')));
      expect(body['screen'], 'whatsapp');
      final h = (body['history'] as List).cast<Map>();
      expect(h, hasLength(6));
      expect(h.first['role'], 'user');
      expect(h.last['role'], 'assistant');
      for (var i = 1; i < h.length; i++) {
        expect(h[i]['role'], isNot(h[i - 1]['role']));
      }
      expect(h.first['text'], 'س2');
    });

    test(
        'جواب المساعد يُرسل كما وقّعه الخادم حرفيّاً مع توقيعه؛ وغير الموقَّع يسقط مع سؤاله',
        () async {
      server.reply('POST', askPath, 200, {
        'success': true,
        'answer': {'title': 'جواب', 'status': 'answered'},
      });
      // نصّ الخادم فيه رقمٌ طويل ونقطتان — يُرسل كما هو (التوقيع على النصّ نفسه).
      const signedText = 'افتح «الإعدادات»\n1. اضغط «حفظ» 123456789';
      await AiApi.ask('سؤال طويل كفاية', history: const [
        AiTurn.user('سؤالٌ أوّل'),
        AiTurn.assistant('جوابٌ بلا توقيع (خادمٌ أقدم)'),
        AiTurn.user('سؤالٌ ثانٍ 07701234567'),
        AiTurn.assistant(signedText, sig: sig32),
      ]);
      final h = (server.bodies('POST', askPath).single['history'] as List)
          .cast<Map>();
      expect(h, hasLength(2));
      expect(h[0]['role'], 'user');
      expect(h[0]['text'], isNot(contains('07701234567')));
      expect(h[0].containsKey('sig'), isFalse);
      expect(h[1], {'role': 'assistant', 'text': signedText, 'sig': sig32});
    });

    test('الردّ: history_text/history_sig يُقرآن كما هما؛ والتالف يُهمَل', () {
      final ok = AiApi.replyFrom(200, {
        'success': true,
        'answer': {'title': 'جواب', 'status': 'answered'},
        'history_text': 'جواب\n1. خطوة',
        'history_sig': sig32,
      });
      expect(ok.signed, isTrue);
      expect(ok.historyText, 'جواب\n1. خطوة');
      expect(ok.historySig, sig32);
      for (final bad in [
        {'history_text': 'جواب', 'history_sig': 'قصير'},
        {'history_text': '', 'history_sig': sig32},
        {'history_text': 'x' * 701, 'history_sig': sig32},
        {'history_sig': sig32},
      ]) {
        final r = AiApi.replyFrom(200, {
          'success': true,
          'answer': {'title': 'جواب', 'status': 'answered'},
          ...bad,
        });
        expect(r.ok, isTrue);
        expect(r.signed, isFalse, reason: '$bad');
      }
    });

    test('شاشةٌ غير معروفة لا تُرسل', () async {
      server.reply('POST', askPath, 200, {
        'success': true,
        'answer': {'title': 'جواب', 'status': 'answered'},
      });
      await AiApi.ask('سؤال طويل كفاية', screen: 'more_menu');
      expect(
          server.bodies('POST', askPath).single.containsKey('screen'), isFalse);
    });

    test('جوابٌ بلا محتوى ⇒ تعذّر لا جوابٌ فارغ', () async {
      server.reply('POST', askPath, 200, {
        'success': true,
        'answer': {'title': '', 'body': '', 'steps': []},
      });
      final r = await AiApi.ask('سؤال طويل كفاية');
      expect(r.ok, isFalse);
      expect(r.failure!.retryable, isTrue);
    });
  });

  group('التنقية قبل الإرسال', () {
    test('تُخفى الهواتف والأرقام الطويلة والتوكنات والبريد وقيم كلمات السرّ',
        () {
      final iso = String.fromCharCode(0x2066);
      final pdi = String.fromCharCode(0x2069);
      final cases = {
        '+964 770 123 4567': '[رقم مخفي]',
        '00964-780-123-4567': '[رقم مخفي]',
        '0770 123 4567': '[رقم مخفي]',
        '$iso٠٧٧٠١٢٣٤٥٦٧$pdi': '[رقم مخفي]',
        'سيريال 1234567890123': 'سيريال [رقم مخفي]',
        'eyJhbGciOi.eyJzdWIiOjF9.c2lnbmF0dXJl': '[مخفي]',
        'user@gmail.com': '[بريد مخفي]',
        'password: hunter2': 'password: [مخفي]',
        'كلمة السر: abc123': 'كلمة السر: [مخفي]',
        'tok a1b2c3d4e5f6a7b8c9d0e1f2a3b4': 'tok [مخفي]',
      };
      cases.forEach((input, want) {
        expect(AiText.maskForSend(input), want, reason: input);
      });
    });

    test(
        'يبقى: المبالغ والتواريخ ورموز الخادم ويوزر الساس ونصّ «كلمة السر غير صحيحة»',
        () {
      for (final keep in [
        'المبلغ 1,324,930 د.ع',
        '2026-11-16 14:42',
        'PACKAGE_CHANGE_ACTIVE_FORBIDDEN',
        'next-gen:175',
        'admin@poox',
        'كلمة السر غير صحيحة',
      ]) {
        expect(AiText.maskForSend(keep), keep, reason: keep);
      }
    });

    // مراجعة: عبارات حقيقيّة كانت تمرّ (القيمة بعد كلمةٍ واصفة، أرقام الكارت،
    // توكن البوت، والهواتف بتجميعٍ آخر) — مرآة اختبار الخادم.
    test('مراجعة: لا تمرّ قيمة باسورد/PIN/كارت/توكن ولا هاتفٌ بأيّ تجميع', () {
      const leaks = <String, String>{
        'باسورد الإيداع 5544': '5544',
        'باسورد الإيداع: 5544': '5544',
        'باسورد الإيداع هو 5544': '5544',
        'كلمة المرور للمشترك: zz9911': 'zz9911',
        'باسورده: 112233': '112233',
        'باسوردي 123456': '123456',
        'الباسورد مالتي 123456': '123456',
        'الباس 123456': '123456',
        'يوزر ahmed77 باس ahmed77': 'باس ahmed77',
        'باسورد الواي فاي 12345678': '12345678',
        'كارت 1234 5678 9012 3456': '1234',
        'رقم الكارت 1234-5678-9012-3456': '5678',
        'الرمز السري للكارت 4455 7788': '7788',
        'PIN الكارت 4455': '4455',
        'رمز الكارت 1234 5678 9012': '9012',
        'رقمه 0770 1234 567': '1234',
        'رقمه 0770-1234-567': '1234',
        'رقمه (0770) 123 4567': '4567',
        'رقمه 0770.123.4567': '4567',
        'رقمه 964 770 1234 567': '1234',
        'رقمه +964 (770) 123 4567': '4567',
        'توكن البوت 7123456789:AAH-qTcvCH1vGWJxf_SeofSAs0K5PALDsa': 'qTcv',
        'pin1234': '1234',
        'PIN: 1234': '1234',
        'رمز التحقّق: 482913': '482913',
        'كود التفعيل ABCD-1234-EFGH': 'ABCD',
        'كلمة السر مالتي ali@2024': 'ali@2024',
        'الكارت 12345678 والـPIN 87654321': '87654321',
        'والباسورد abc123xyz': 'abc123xyz',
      };
      leaks.forEach((input, secret) {
        expect(AiText.maskForSend(input), isNot(contains(secret)),
            reason: input);
      });
      expect(
          AiText.maskForSend('باسورد الإيداع 5544'), 'باسورد الإيداع [مخفي]');
      expect(AiText.maskForSend('</سياق>'), '‹/سياق›');
    });

    test('مراجعة: يبقى نصّ الخادم والرموز والتواريخ والمبالغ', () {
      for (final keep in [
        'باسورد الإيداع غير صحيح',
        'شلون أغيّر باسورد الإيداع؟',
        'BAD_PIN',
        'PIN_LOCKED',
        'EL_DEPOSIT_PASSWORD',
        'اكتب رمز الكارت (PIN) كما هو مطبوع على الكارت',
        'سعر الكارت 25000',
        'رمز الوكيل 482913',
        '18-10-2026 14:42',
        'رصيدي 563.000.000',
        'كلمة المرور: 6 أحرف على الأقلّ',
        'باسم المستخدم',
        'نسخة 3.0.3+162',
      ]) {
        expect(AiText.maskForSend('قبل $keep بعد'), 'قبل $keep بعد',
            reason: keep);
      }
    });
  });

  group('روابط الدعم بقيم المالك كما خزّنها', () {
    String? tg(Object? v) =>
        AiSupport.fromJson({'telegram': v})?.telegram?.toString();
    String? wa(Object? v) =>
        AiSupport.fromJson({'whatsapp': v})?.whatsapp?.toString();

    test('🚨 يوزر تلغرام ورقم واتساب بلا رابط (شكل الإنتاج) ⇒ رابطان', () {
      final s = AiSupport.fromJson(
          {'telegram': 'MyServicesTeam', 'whatsapp': '9647701234567'})!;
      expect(s.telegram.toString(), 'https://t.me/MyServicesTeam');
      expect(s.whatsapp.toString(), 'https://wa.me/9647701234567');
      final r = AiApi.replyFrom(200, {
        'success': true,
        'answer': {'title': 'ما أعرف بالضبط', 'status': 'needs_support'},
        'support': {'telegram': 'MyServicesTeam'},
      });
      expect(r.answer!.wantsSupport, isTrue);
      expect(r.support!.telegram.toString(), 'https://t.me/MyServicesTeam');
    });

    test('صيغٌ أخرى معقولة', () {
      expect(tg('@MyServicesTeam'), 'https://t.me/MyServicesTeam');
      expect(tg('t.me/MyServicesTeam'), 'https://t.me/MyServicesTeam');
      expect(tg('https://telegram.me/mysvcs'), 'https://telegram.me/mysvcs');
      expect(wa('+964 770 123 4567'), 'https://wa.me/9647701234567');
      expect(wa('00964-770-123-4567'), 'https://wa.me/9647701234567');
      expect(wa('07701234567'), 'https://wa.me/9647701234567',
          reason: 'رقمٌ عراقيّ محلّيّ');
      expect(wa('wa.me/9647701234567'), 'https://wa.me/9647701234567');
    });

    test('ما ليس تلغرام/واتساب لا يُفتح', () {
      for (final bad in [
        'javascript:alert(1)',
        'https://evil.example/t.me',
        'http://t.me/mysvcs',
        'https://user@t.me/mysvcs',
        'https://t.me:8443/mysvcs',
        'ab',
        '1abcde',
        'name with space',
      ]) {
        expect(tg(bad), isNull, reason: bad);
      }
      for (final bad in ['12345', 'https://wa.me.evil.example/1', '+0']) {
        expect(wa(bad), isNull, reason: bad);
      }
      expect(AiSupport.fromJson({'telegram': '', 'whatsapp': null}), isNull);
    });
  });

  group('🍏 آيفون: لا «تواصل ويّا الدعم» في سياق اشتراك الحساب', () {
    const sup = {'telegram': 'mysvcs_support', 'whatsapp': '9647700000000'};
    AiReply reply(String status,
            {String title = 'ما أعرف بالضبط',
            String body = 'هذا عند الشركة.',
            bool ask = false,
            String? about,
            String? errorCode}) =>
        AiApi.replyFrom(
            200,
            {
              'success': true,
              'answer': {'title': title, 'body': body, 'status': status},
              'support': sup,
            },
            ask: ask,
            about: about,
            errorCode: errorCode);

    test('بديل الخادم لجوابٍ فرغ بعد التنقية ⇒ بلا روابط', () {
      StorePolicy.debugHidePurchaseFlows = true;
      final r = reply('unknown', title: 'ما أگدر أساعد بهذا هنا', body: '');
      expect(r.answer!.iosScrubbed, isTrue);
      expect(r.support, isNull);
    });

    test('جوابٌ سقطت منه جملة ترقية ⇒ بلا روابط', () {
      StorePolicy.debugHidePurchaseFlows = true;
      final r = reply('needs_support',
          title: 'وصلت الحدّ', body: 'ما أعرف بالضبط — رقّي باقتك');
      expect(r.answer!.body, 'ما أعرف بالضبط');
      expect(r.support, isNull);
    });

    test('«ما أعرف» في «كيف أسوّي؟» ⇒ بلا روابط (السؤال حرّ)', () {
      StorePolicy.debugHidePurchaseFlows = true;
      expect(reply('unknown', ask: true, about: 'شلون أربط الواتساب؟').support,
          isNull);
    });

    test('سؤالٌ أو خطأٌ عن الباقة/الحدود ⇒ بلا روابط', () {
      StorePolicy.debugHidePurchaseFlows = true;
      for (final about in [
        'شلون أرقّي باقتي؟',
        'شلون أزيد حدّ الموظّفين؟',
        'بلغت الحدّ الأقصى لعدد الموظّفين لهذا الحساب (3).',
        'وصلت حدّ الشركات',
        'انتهى اشتراكك',
        'طيب منو أكلّم؟\nشلون أرقّي باقتي؟',
      ]) {
        expect(reply('needs_support', ask: true, about: about).support, isNull,
            reason: about);
      }
      expect(
          reply('needs_support', errorCode: 'company-limit').support, isNull);
    });

    test('خطأ عمل المشتركين ⇒ الروابط باقية', () {
      StorePolicy.debugHidePurchaseFlows = true;
      final r = reply('needs_support',
          about: 'الساس رفض التفعيل — المشترك غير موجود',
          errorCode: 'SAS_REJECTED');
      expect(r.answer!.iosScrubbed, isFalse);
      expect(r.support!.telegram.toString(), 'https://t.me/mysvcs_support');
      expect(
          reply('needs_support', ask: true, about: 'شلون أغيّر باقة المشترك؟')
              .support,
          isNotNull,
          reason: 'باقة المشترك ليست باقة الحساب');
    });

    test('غير آيفون: كما يرسلها الخادم', () {
      StorePolicy.debugHidePurchaseFlows = false;
      expect(reply('unknown', ask: true, about: 'شلون أرقّي باقتي؟').support,
          isNotNull);
      expect(
          reply('unknown', title: 'ما أگدر أساعد بهذا هنا', body: '')
              .answer!
              .iosScrubbed,
          isFalse);
    });

    test('الطلب نفسه يحمل السياق: explain برسالته وask بأسئلة المحادثة',
        () async {
      StorePolicy.debugHidePurchaseFlows = true;
      final ok = {
        'success': true,
        'answer': {'title': 'جواب', 'status': 'needs_support'},
        'support': sup,
      };
      server.reply('POST', explainPath, 200, ok);
      server.reply('POST', askPath, 200, ok);
      expect(
          (await AiApi.explain(const ExplainRequest(
                  message:
                      'بلغت الحدّ الأقصى لعدد الموظّفين لهذا الحساب (3).')))
              .support,
          isNull);
      expect(
          (await AiApi.explain(
                  const ExplainRequest(message: 'المشترك غير موجود')))
              .support,
          isNotNull);
      expect(
          (await AiApi.ask('طيب منو أكلّم؟', history: const [
            AiTurn.user('شلون أرقّي باقتي؟'),
            AiTurn.assistant('ما أگدر أساعد بهذا هنا', sig: sig32),
          ]))
              .support,
          isNull,
          reason: 'متابعةٌ في سياق سؤال الباقة');
    });
  });

  group('«مفيد» / «الجواب غلط» (feedback)', () {
    const feedbackPath = '/api/v2/ai/feedback';

    test('المرجع والرأي وحدهما', () async {
      server.reply('POST', feedbackPath, 200, {'success': true, 'saved': true});
      expect(await AiApi.feedback('c8f1a2b3', helpful: false), isTrue);
      expect(server.bodies('POST', feedbackPath).single,
          {'ref': 'c8f1a2b3', 'helpful': false});
    });

    test('مرجعٌ غير صالح ⇒ لا طلب', () async {
      for (final bad in ['', 'C8F1A2B3', 'c8f1a2b', 'c8f1a2b3x', '../../x']) {
        expect(await AiApi.feedback(bad, helpful: true), isFalse, reason: bad);
      }
      expect(server.requests, isEmpty);
    });

    test('رفضٌ أو انقطاع ⇒ false', () async {
      server.reply('POST', feedbackPath, 404,
          {'success': false, 'message': 'غير موجود'});
      expect(await AiApi.feedback('c8f1a2b3', helpful: true), isFalse);
      server.on('POST', feedbackPath, simTimeout);
      expect(await AiApi.feedback('c8f1a2b3', helpful: true), isFalse);
    });

    test('مرجع الجواب: ٨ خانات hex وإلّا لا تقييم', () {
      AiReply r(Object? ref) => AiApi.replyFrom(200, {
            'success': true,
            'answer': {'title': 'جواب', 'status': 'answered'},
            'ref': ref,
          });
      expect(r('c8f1a2b3').ref, 'c8f1a2b3');
      expect(r('not-a-ref').ref, isNull);
      expect(r(12345678).ref, isNull);
    });
  });
}
