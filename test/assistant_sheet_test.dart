import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/ai_api.dart';
import 'package:rad_mysvcs/core/platform/store_policy.dart';
import 'package:rad_mysvcs/screens/assistant/assistant_consent_sheet.dart';
import 'package:rad_mysvcs/screens/assistant/assistant_sheet.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:rad_mysvcs/services/ai_consent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sim_el/sim_harness.dart';

/// نافذة المساعد — السلوك لا الشكل (الشكل في sim_el/ai_assistant_sim_test):
/// «أعد المحاولة»، الانتقال من «اشرحلي» إلى السؤال بالخطأ سياقاً، الميزات
/// ذات الصلة، الإطفاء أثناء الجلسة، القفل، ووضع الحساب، ودعوة الترقية على آيفون،
/// والموافقة قبل أوّل طلب، وروابط الدعم على آيفون، و«مفيد»/«الجواب غلط».
void main() {
  const v = SimVariant(390, dark: false);
  const explainPath = '/api/v2/ai/explain';
  const askPath = '/api/v2/ai/ask';
  const statusPath = '/api/v2/ai/status';

  const on = <String, dynamic>{
    'success': true,
    'enabled': true,
    'can_use': true,
    'explain': true,
    'ask': true,
    'quota': {'left': 7, 'limit': 10},
    'upgrade_hint': 'باقة الأعمال: 100 سؤال باليوم',
  };

  Map<String, dynamic> answer(String title,
          {List<String> related = const [], int left = 6}) =>
      {
        'success': true,
        'answer': {
          'title': title,
          'body': 'نصّ الجواب.',
          'steps': ['خطوة أولى'],
          'status': 'answered',
          'related': related,
        },
        'quota': {'left': left, 'limit': 10},
        // الخادم يوقّع نصّ الجواب للسجلّ (يُعاد حرفيّاً مع السؤال التالي).
        'history_text': '$title\nنصّ الجواب.\n1. خطوة أولى',
        'history_sig': 'SigSigSigSigSigSigSigSigSigSig01',
      };

  const req = ExplainRequest(
    code: 'CREDIT_NOT_ALLOWED',
    message: 'حسابك ما يسمح بالتفعيل بالرصيد',
    screen: 'activate',
    httpStatus: 409,
  );

  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': '2251'});
    AiAssistantState.reset();
    server.reply('GET', statusPath, 200, on);
    AiAssistantState.debugSet(AiStatus.fromJson(on, mode: AiMode.company));
    StorePolicy.debugHidePurchaseFlows = null;
    // وافق من قبل — حالات الموافقة نفسها في آخر الملفّ.
    AiConsent.debugAccepted = true;
  });

  tearDown(() {
    AiAssistantState.reset();
    StorePolicy.debugHidePurchaseFlows = null;
    AiApi.hasAccount = () => false;
    AiConsent.debugReset();
  });

  Future<void> open(WidgetTester t, {ExplainRequest? explain}) async {
    await pumpSim(t, v,
        home: (_) => simLauncher((c) => explain == null
            ? AssistantSheet.showAsk(c)
            : AssistantSheet.showExplain(c, explain)));
    await simOpen(t);
  }

  Future<void> ask(WidgetTester t, String q) async {
    await t.enterText(find.byType(EditableText), q);
    await t.pump();
    await t.tap(find.byIcon(LucideIcons.sendHorizontalDir));
    await t.pumpAndSettle();
  }

  testWidgets(
      'تعذّرٌ عابر ⇒ «أعد المحاولة» يطلب مرّةً ثانية بنقرة المدير وحدها',
      (t) async {
    var n = 0;
    server.on('POST', explainPath, (o) {
      n++;
      return n == 1
          ? simTimeout(o)
          : SimReply(200, answer('الساس ما يسمح لحسابك بالتفعيل بالرصيد'));
    });
    await open(t, explain: req);
    expect(find.text('أعد المحاولة'), findsOneWidget);
    expect(n, 1, reason: 'لا إعادة تلقائيّة');
    await t.tap(find.text('أعد المحاولة'));
    await t.pumpAndSettle();
    expect(n, 2);
    expect(find.text('الساس ما يسمح لحسابك بالتفعيل بالرصيد'), findsOneWidget);
  });

  testWidgets('«اسأل سؤال ثاني» ⇒ المحادثة والخطأ وجوابه سياقٌ للسؤال',
      (t) async {
    server.reply('POST', explainPath, 200, answer('شرح الخطأ'));
    server.reply('POST', askPath, 200, answer('جواب السؤال', left: 5));
    await open(t, explain: req);
    await t.tap(find.text('اسأل سؤال ثاني'));
    await t.pumpAndSettle();
    expect(find.textContaining('اشرحلي هذا الخطأ'), findsOneWidget);
    await ask(t, 'وشلون أطلب الصلاحيّة؟');
    final body = server.bodies('POST', askPath).single;
    final h = (body['history'] as List).cast<Map>();
    expect(h, hasLength(2));
    expect(h[0]['role'], 'user');
    expect(h[0]['text'], contains('حسابك ما يسمح بالتفعيل بالرصيد'));
    expect(h[1]['role'], 'assistant');
    expect(h[1]['text'], 'شرح الخطأ\nنصّ الجواب.\n1. خطوة أولى',
        reason: 'نصّ الخادم الموقَّع حرفيّاً');
    expect(h[1]['sig'], 'SigSigSigSigSigSigSigSigSigSig01');
    expect(body['screen'], 'activate');
    expect(find.text('جواب السؤال'), findsOneWidget);
    expect(AiAssistantState.status!.quota!.left, 5, reason: 'الحصّة من الجواب');
  });

  testWidgets('ميزةٌ ذات صلة ⇒ سؤالٌ جاهز في الحقل (لا يُرسل وحده)', (t) async {
    server.reply('POST', explainPath, 200,
        answer('شرح', related: const ['تغيير الباقة']));
    await open(t, explain: req);
    await t.tap(find.text('تغيير الباقة'));
    await t.pumpAndSettle();
    final field = t.widget<EditableText>(find.byType(EditableText));
    expect(field.controller.text, 'شلون أستعمل «تغيير الباقة»؟');
    expect(server.calls('POST', askPath), isEmpty);
  });

  testWidgets('أُطفئ أثناء الجلسة (٤٠٤) ⇒ يختفي المساعد ويُقفل الحقل',
      (t) async {
    server.reply(
        'POST', askPath, 404, {'success': false, 'message': 'غير موجود'});
    await open(t);
    await ask(t, 'شلون أفعّل مشترك؟');
    expect(AiAssistantState.visible, isFalse);
    expect(AiAssistantState.canExplain, isFalse);
    expect(find.byType(EditableText), findsNothing);
    expect(find.text('المساعد غير متاح حالياً'), findsWidgets);
  });

  testWidgets(
      'بلا صلاحيّة المساعد (AI_NO_PERMISSION) ⇒ رسالة القفل والحقل مقفل',
      (t) async {
    server.reply('POST', askPath, 403, {
      'success': false,
      'code': 'AI_NO_PERMISSION',
      'message': 'ما عندك صلاحيّة المساعد — اطلبها من مديرك',
    });
    await open(t);
    await ask(t, 'شلون أفعّل مشترك؟');
    expect(
        find.text('ما عندك صلاحيّة المساعد — اطلبها من مديرك'), findsWidgets);
    expect(find.byIcon(LucideIcons.lock), findsWidgets);
    expect(find.byType(EditableText), findsNothing);
    expect(find.text('أعد المحاولة'), findsNothing);
  });

  testWidgets('كثّرت الأسئلة (AI_RATE_LIMITED) ⇒ رسالةٌ وإعادة، والحقل يبقى',
      (t) async {
    var n = 0;
    server.on('POST', askPath, (_) {
      n++;
      return n == 1
          ? const SimReply(429, {
              'success': false,
              'code': 'AI_RATE_LIMITED',
              'message': 'كثّرت الأسئلة بسرعة — استنّى دقيقة وارجع اسأل',
              'retry_after_sec': 40,
            })
          : SimReply(200, answer('جواب بعد الانتظار'));
    });
    await open(t);
    await ask(t, 'شلون أفعّل مشترك؟');
    expect(find.textContaining('كثّرت الأسئلة'), findsOneWidget);
    expect(find.byType(EditableText), findsOneWidget);
    await t.tap(find.text('أعد المحاولة'));
    await t.pumpAndSettle();
    expect(find.text('جواب بعد الانتظار'), findsOneWidget);
    expect(find.textContaining('كثّرت الأسئلة'), findsNothing);
  });

  testWidgets('🍏 آيفون: دعوة الترقية لا تظهر مع نفاد الحصّة مهما وصلت',
      (t) async {
    StorePolicy.debugHidePurchaseFlows = true;
    server.reply('POST', askPath, 429, {
      'success': false,
      'code': 'AI_QUOTA_EXHAUSTED',
      'message': 'خلصت أسئلة اليوم — ترجع باچر',
      'quota': {'left': 0, 'limit': 10},
    });
    await open(t);
    await ask(t, 'شلون أفعّل مشترك؟');
    expect(find.textContaining('خلصت أسئلة اليوم'), findsWidgets);
    expect(find.textContaining('باقة الأعمال'), findsNothing);
  });

  testWidgets('غير آيفون: دعوة الترقية (من الخادم) تحت رسالة نفاد الحصّة',
      (t) async {
    StorePolicy.debugHidePurchaseFlows = false;
    server.reply('POST', askPath, 429, {
      'success': false,
      'code': 'AI_QUOTA_EXHAUSTED',
      'message': 'خلصت أسئلة اليوم — ترجع باچر أو رقّي باقتك',
      'quota': {'left': 0, 'limit': 10},
    });
    await open(t);
    await ask(t, 'شلون أفعّل مشترك؟');
    expect(find.text('باقة الأعمال: 100 سؤال باليوم'), findsOneWidget);
    expect(find.text('باقي لك اليوم: 0'), findsOneWidget);
  });

  testWidgets('حساب Pro وحده (الدخول/«شركاتي») ⇒ «اشرحلي» بلا «اسأل سؤال ثاني»',
      (t) async {
    FlutterSecureStorage.setMockInitialValues({});
    AiApi.hasAccount = () => true;
    AiApi.accountTokenSource = ({bool force = false}) async => 'acct';
    final accountServer = SimServer();
    AiApi.accountDio.httpClientAdapter = accountServer;
    accountServer.reply('POST', explainPath, 200, answer('شرح حدّ الشركات'));
    AiAssistantState.debugSet(AiStatus.fromJson(
        Map<String, dynamic>.from(on)..['ask'] = false,
        mode: AiMode.account));
    await open(t,
        explain: const ExplainRequest(
            code: 'company-limit',
            message: 'وصلت حدّ الشركات',
            screen: 'companies'));
    expect(find.text('شرح حدّ الشركات'), findsOneWidget);
    expect(find.text('اسأل سؤال ثاني'), findsNothing);
    expect(accountServer.calls('POST', explainPath), hasLength(1));
    expect(server.calls('POST', explainPath), isEmpty);
  });

  testWidgets(
      'شاشةٌ قصيرة (٣٢٠×٥٦٨) ولوحة المفاتيح مفتوحة ⇒ الحقل فوقها بلا فيضان',
      (t) async {
    await pumpSim(t, const SimVariant(320, dark: false),
        home: (_) => simLauncher((c) => AssistantSheet.showAsk(c)));
    await simOpen(t);
    t.view.physicalSize = const Size(320, 568);
    t.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final field = t.getRect(find.byType(EditableText));
    expect(field.bottom, lessThanOrEqualTo(568 - 260),
        reason: 'فوق لوحة المفاتيح');
    expect(find.textContaining('أجوبة ذكاء اصطناعي'), findsNothing,
        reason: 'سطر التنبيه يُخفى أثناء الكتابة على الشاشة القصيرة');
    t.view.resetViewInsets();
    await t.pumpAndSettle();
    expect(find.textContaining('أجوبة ذكاء اصطناعي'), findsOneWidget);
  });

  testWidgets('التنبيه «أجوبة ذكاء اصطناعي وقد تخطئ» كاملٌ بعرض ٣٢٠ وخطّ ١٫٢',
      (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSim(t, const SimVariant(320, dark: false),
        home: (_) => simLauncher((c) => AssistantSheet.showAsk(c)));
    await simOpen(t);
    final note = t.widget<Text>(find.textContaining('أجوبة ذكاء اصطناعي'));
    expect(note.maxLines, isNull);
    expect(note.overflow, isNot(TextOverflow.ellipsis));
    expect(note.data, contains('المساعد يشرح فقط'));
    expect(t.takeException(), isNull);
  });

  group('الموافقة قبل أوّل طلب (App Store 5.1.2(i))', () {
    setUp(() {
      AiConsent.debugReset();
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('«مو هسه» ⇒ لا نافذة ولا طلب، وتُسأل ثانيةً', (t) async {
      server.reply('POST', explainPath, 200, answer('شرح'));
      await open(t, explain: req);
      expect(find.byType(AssistantConsentSheet), findsOneWidget);
      expect(find.textContaining('مزوّد خارجي'), findsOneWidget);
      expect(find.textContaining('الإخفاء محاولة مو ضمان'), findsOneWidget);
      // ما يحفظه الخادم ومدّته والفحص الآليّ (سياسة الخصوصيّة، البند ٣) — لا وعد «ما نحفظ».
      expect(find.textContaining('٢٤ ساعة'), findsOneWidget);
      expect(find.textContaining('٣٠ يوم'), findsOneWidget);
      expect(find.textContaining('يفحصها تلقائيّاً'), findsOneWidget);
      expect(find.textContaining('فريقنا'), findsOneWidget);
      expect(find.textContaining('ما نحفظ نصّ المحادثة'), findsNothing);
      // مراجعة ١٩ أكتوبر: مربوطة بالحساب، خارج النسخ الاحتياطيّة، سجلّات القاعدة التقنيّة، والشاشة والمنصّة فيما يُرسل.
      expect(find.textContaining('مربوطة بحسابك'), findsOneWidget);
      expect(find.textContaining('ما تدخل النسخ الاحتياطيّة'), findsOneWidget);
      expect(find.textContaining('سجلّات القاعدة التقنيّة'), findsOneWidget);
      expect(find.textContaining('والشاشة والمنصّة'), findsOneWidget);
      expect(AiConsent.prefKey, 'ai.consent.v2',
          reason: 'نصّ الموافقة تغيّر جوهريّاً (الحفظ المؤقّت) ⇒ يُسأل الكلّ ثانيةً');
      expect(find.text('سياسة الخصوصيّة'), findsOneWidget);
      expect(server.calls('POST', explainPath), isEmpty,
          reason: 'لا طلب قبل الموافقة');
      await t.tap(find.text('مو هسه'));
      await t.pumpAndSettle();
      expect(find.byType(AssistantSheet), findsNothing);
      expect(server.calls('POST', explainPath), isEmpty);
      expect(await AiConsent.accepted(), isFalse, reason: 'الرفض لا يُحفظ');
      await simOpen(t);
      expect(find.byType(AssistantConsentSheet), findsOneWidget);
    });

    testWidgets('«موافق، كمّل» ⇒ النافذة والطلب، وتُحفظ فلا تُسأل ثانيةً',
        (t) async {
      server.reply('POST', explainPath, 200, answer('شرح الخطأ'));
      await open(t, explain: req);
      await t.tap(find.text('موافق، كمّل'));
      await t.pumpAndSettle();
      expect(find.byType(AssistantSheet), findsOneWidget);
      expect(find.text('شرح الخطأ'), findsOneWidget);
      expect(server.calls('POST', explainPath), hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      final key = await AiConsent.currentKey();
      expect(key, startsWith('${AiConsent.prefKey}.'));
      expect(prefs.getBool(key), isTrue);
      Navigator.of(t.element(find.byType(AssistantSheet))).pop();
      await t.pumpAndSettle();
      await simOpen(t);
      expect(find.byType(AssistantConsentSheet), findsNothing);
      expect(find.byType(AssistantSheet), findsOneWidget);
    });

    testWidgets('«كيف أسوّي؟» كذلك: الموافقة قبل المحادثة', (t) async {
      await open(t);
      expect(find.byType(AssistantConsentSheet), findsOneWidget);
      expect(find.byType(AssistantSheet), findsNothing);
    });

    testWidgets('لكلّ شخص لا لكلّ جهاز: موظّفٌ على هاتف مديره يُسأل هو', (t) async {
      server.reply('POST', explainPath, 200, answer('شرح'));
      AiConsent.debugActor = 'acct:uid-owner';
      await open(t, explain: req);
      await t.tap(find.text('موافق، كمّل'));
      await t.pumpAndSettle();
      expect(find.byType(AssistantSheet), findsOneWidget);
      Navigator.of(t.element(find.byType(AssistantSheet))).pop();
      await t.pumpAndSettle();
      final ownerKey = await AiConsent.currentKey();
      AiConsent.debugActor = 'emp:jt:7:cashier';
      expect(await AiConsent.currentKey(), isNot(ownerKey));
      expect(await AiConsent.accepted(), isFalse, reason: 'موافقة المدير لا تُحسب للموظّف');
      await simOpen(t);
      expect(find.byType(AssistantConsentSheet), findsOneWidget);
      expect(ownerKey, isNot(contains('uid-owner')), reason: 'بصمةٌ لا معرّفٌ خامّ في التفضيلات');
      AiConsent.debugActor = 'acct:uid-owner';
      expect(await AiConsent.accepted(), isTrue, reason: 'المدير لا يُسأل ثانيةً');
    });
  });

  testWidgets(
      '🍏 آيفون: «ما أگدر أساعد بهذا هنا» (بديل الخادم) ⇒ لا تلغرام ولا واتساب',
      (t) async {
    StorePolicy.debugHidePurchaseFlows = true;
    server.reply('POST', askPath, 200, {
      'success': true,
      'answer': {'title': 'ما أگدر أساعد بهذا هنا', 'status': 'unknown'},
      'support': {'telegram': 'https://t.me/x', 'whatsapp': '9647700000000'},
    });
    await open(t);
    await ask(t, 'شلون أرقّي باقتي؟');
    expect(find.text('ما أگدر أساعد بهذا هنا'), findsOneWidget);
    expect(find.text('تلغرام'), findsNothing);
    expect(find.text('واتساب'), findsNothing);
    expect(find.text('تواصل ويّا الدعم'), findsNothing);
  });

  testWidgets('غير آيفون: روابط الدعم بقيم المالك (يوزر ورقم بلا رابط)',
      (t) async {
    StorePolicy.debugHidePurchaseFlows = false;
    server.reply('POST', askPath, 200, {
      'success': true,
      'answer': {
        'title': 'ما أعرف بالضبط',
        'body': 'سعر الجملة عند الشركة.',
        'status': 'unknown'
      },
      'support': {'telegram': 'MyServicesTeam', 'whatsapp': '9647701234567'},
    });
    await open(t);
    await ask(t, 'بيش سعر الكارت بالجملة؟');
    expect(find.text('تواصل ويّا الدعم'), findsOneWidget);
    expect(find.text('تلغرام'), findsOneWidget);
    expect(find.text('واتساب'), findsOneWidget);
  });

  group('«مفيد» / «الجواب غلط»', () {
    const feedbackPath = '/api/v2/ai/feedback';
    Map<String, dynamic> withRef(String title) =>
        answer(title)..['ref'] = 'c8f1a2b3';

    testWidgets('«الجواب غلط» ⇒ المرجع وhelpful:false، ثمّ «وصلنا رأيك»',
        (t) async {
      server.reply('POST', explainPath, 200, withRef('شرح'));
      server.reply('POST', feedbackPath, 200, {'success': true, 'saved': true});
      await open(t, explain: req);
      expect(find.text('مفيد'), findsOneWidget);
      await t.tap(find.text('الجواب غلط'));
      await t.pumpAndSettle();
      expect(server.bodies('POST', feedbackPath).single,
          {'ref': 'c8f1a2b3', 'helpful': false});
      expect(find.text('وصلنا رأيك — شكراً'), findsOneWidget);
      expect(find.text('مفيد'), findsNothing, reason: 'رأيٌ واحد للجواب');
    });

    testWidgets('في المحادثة لكلّ جواب، وتعذّر الإرسال ⇒ الزرّان باقيان',
        (t) async {
      server.reply('POST', askPath, 200, withRef('جواب السؤال'));
      server.on('POST', feedbackPath, simTimeout);
      await open(t);
      await ask(t, 'شلون أفعّل مشترك؟');
      await t.tap(find.text('مفيد'));
      await t.pumpAndSettle();
      expect(server.bodies('POST', feedbackPath).single['helpful'], isTrue);
      expect(find.text('وصلنا رأيك — شكراً'), findsNothing);
      expect(find.text('مفيد'), findsOneWidget);
      expect(find.text('ما وصل رأيك — جرّب مرّة ثانية'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('جوابٌ بلا مرجع (خادمٌ أقدم) ⇒ لا تقييم', (t) async {
      server.reply('POST', askPath, 200, answer('جواب'));
      await open(t);
      await ask(t, 'شلون أفعّل مشترك؟');
      expect(find.text('مفيد'), findsNothing);
      expect(find.text('الجواب غلط'), findsNothing);
    });
  });
}
