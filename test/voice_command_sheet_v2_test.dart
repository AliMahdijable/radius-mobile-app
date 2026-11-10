// «الأمر الصوتي ٢» (١٠ نوفمبر — المالك: «تسديد دين تفعيل جزئي وباقي العمليات… ويتعرف على اللغة انكليزي عربي»): الجملة ⇒ كرت
// التأكيد بما فُهم (الدفع، المبلغ، الباقة) ⇒ صفحة المشترك وشاشة العمليّة نفسها بما قيل مختاراً — ولا تنفيذ بلا ضغطة الوكيل
// هناك. والمبلغ الناقص تكمّله جملةٌ تالية، والأوامر بلا مشترك، ولغة الكلام، وبدائل ما سمعه المحرّك.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/ai_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:rad_mysvcs/core/widgets/app_sheet.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/screens/voice/voice_command_sheet.dart';
import 'package:rad_mysvcs/services/voice/voice_lang_pref.dart';
import 'package:rad_mysvcs/services/voice/voice_resolver.dart';

import 'visual_perm/visual_perm_harness.dart';

Subscriber _s(String idx, String user, String first, String last, {String? notes, bool online = false}) =>
    Subscriber.fromJson({
      'idx': idx,
      'username': user,
      'firstname': first,
      'lastname': last,
      'enabled': true,
      'profile_name': 'Fiber 35',
      if (notes != null) 'notes': notes,
      if (online) 'online_status': 1,
    });

void main() {
  setUpAll(visualSetUpAll);

  final subs = [
    _s('11', 'ali.hussein', 'علي', 'حسين', online: true),
    _s('12', 'ali77', 'علي', 'كاظم'),
    _s('13', 'zainab', 'زينب', 'علي', notes: '-40000'),
  ];

  setUp(() {
    VoiceLangPref.debugReset('ar');
    VoiceResolver.bigProbe = () async => 0;
    VoiceResolver.loadSubscribers = () async => subs;
  });
  tearDown(() {
    VoiceLangPref.debugReset();
    VoiceResolver.bigProbe = () async => 0;
    VoiceResolver.loadSubscribers = () async => const [];
  });

  Future<void> settle(WidgetTester t, {int ms = 1500}) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester t, {bool autoListen = false}) async {
    final inner = await visualSetUp(s1bSasOwner);
    ApiClient.dio.httpClientAdapter = inner;
    await pumpVisual(t, phone,
        home: (_) => Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: ElevatedButton(
                    key: const ValueKey('open-voice'),
                    onPressed: () => showAppSheet<void>(
                      context: ctx,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => VoiceCommandSheet(rootContext: ctx, autoListen: autoListen),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ));
    await settle(t, ms: 500);
    await t.tap(find.byKey(const ValueKey('open-voice')));
    await settle(t, ms: 800);
  }

  Future<void> say(WidgetTester t, String text) async {
    await t.enterText(find.byKey(const ValueKey('voice-text')), text);
    await t.testTextInput.receiveAction(TextInputAction.go);
    await settle(t);
  }

  Future<SubscriberDetailScreen> confirm(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('voice-confirm')));
    await settle(t, ms: 2500);
    return t.widget<SubscriberDetailScreen>(find.byType(SubscriberDetailScreen));
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
    await visualTearDown();
  }

  testWidgets('«فعّل علي حسين جزئي ١٠ الاف» ⇒ الكرت يقول ما فُهم ⇒ شاشة التفعيل تُفتح بالجزئيّ ومبلغه مختارَين (لا تفعيل)', (t) async {
    await open(t);
    await say(t, 'فعّل علي حسين جزئي ١٠ الاف');
    expect(find.byKey(const ValueKey('voice-sub-card')), findsOneWidget);
    expect(find.textContaining('قلت: جزئي — دفع 10,000 والباقي دين'), findsOneWidget);
    final det = await confirm(t);
    expect(det.autoAction, SubscriberAutoAction.activate);
    expect([det.autoPrefill?.pay, det.autoPrefill?.paid], [ActivatePrefillPay.partial, 10000]);
    expect(det.sub.username, 'ali.hussein');
    await close(t);
  });

  testWidgets('جزئيّ بلا مبلغ ⇒ «كم دفع؟» ⇒ الجملة التالية بالمبلغ وحده تكمّله (لا أمرٌ جديد)', (t) async {
    await open(t);
    await say(t, 'فعّل علي حسين جزئي');
    expect(find.textContaining('كم دفع؟'), findsOneWidget);
    await say(t, 'عشرة آلاف');
    expect(find.byKey(const ValueKey('voice-sub-card')), findsOneWidget, reason: 'الكرت نفسه باقٍ');
    expect(find.textContaining('دفع 10,000 والباقي دين'), findsOneWidget);
    expect(find.textContaining('كم دفع؟'), findsNothing);
    final det = await confirm(t);
    expect([det.autoAction, det.autoPrefill?.paid], [SubscriberAutoAction.activate, 10000]);
    await close(t);
  });

  testWidgets('تسديدٌ بلا مبلغ لمديون ⇒ «المبلغ؟» ⇒ «٢٥ الف» تكمّله ⇒ نافذة التسديد بالمبلغ', (t) async {
    await open(t);
    await say(t, 'سدد دين زينب علي');
    expect(find.textContaining('المبلغ؟'), findsOneWidget);
    await say(t, '٢٥ الف');
    expect(find.textContaining('المبلغ: '), findsOneWidget);
    final det = await confirm(t);
    expect([det.autoAction, det.autoAmount, det.sub.username], [SubscriberAutoAction.payDebt, 25000, 'zainab']);
    await close(t);
  });

  testWidgets('باقي العمليّات بأزرارها: تغيير الباقة (ما قيل تذكير)، الفصل، التمديد — والحذف لا يُفتح بالصوت', (t) async {
    await open(t);
    await say(t, 'غيّر باقة علي حسين الى فايبر ٥٠');
    expect(find.text('غيّر الباقة'), findsOneWidget);
    expect(find.textContaining('الباقة المطلوبة: «فايبر 50»'), findsOneWidget);
    await say(t, 'مدد علي حسين');
    expect(find.text('مدّد'), findsOneWidget);
    await say(t, 'احذف علي حسين');
    expect(find.text('افتح المشترك'), findsOneWidget);
    expect(find.textContaining('الحذف نهائيّ'), findsOneWidget);
    await say(t, 'افصل علي حسين');
    expect(find.text('افصل'), findsOneWidget);
    final det = await confirm(t);
    expect(det.autoAction, SubscriberAutoAction.disconnect);
    expect(find.byType(AlertDialog), findsOneWidget, reason: 'تأكيد الفصل نفسه — التنفيذ بضغطته');
    await close(t);
  });

  testWidgets('«غيّر باقة…» ⇒ شاشة التعديل وما قيل سطرٌ أعلاها (الباقة تُختار باليد)', (t) async {
    await open(t);
    await say(t, 'غيّر باقة علي حسين الى فايبر ٥٠');
    final det = await confirm(t);
    expect([det.autoAction, det.autoHint], [SubscriberAutoAction.changePackage, 'فايبر 50']);
    expect(find.byKey(const ValueKey('edit-voice-note')), findsOneWidget);
    expect(find.textContaining('الباقة «فايبر 50»'), findsOneWidget);
    await close(t);
  });

  testWidgets('أوامر بلا مشترك: «مشترك جديد»، «افتح التقارير»، «المشتركين المنتهين» — كرتٌ بزرّه ولا بحث عن اسم', (t) async {
    var loads = 0;
    VoiceResolver.loadSubscribers = () async {
      loads++;
      return subs;
    };
    await open(t);
    await say(t, 'ضيف مشترك جديد');
    expect(find.byKey(const ValueKey('voice-add-sub')), findsOneWidget);
    await say(t, 'افتح التقارير');
    expect(find.byKey(const ValueKey('voice-section')), findsOneWidget);
    expect(find.text('التقارير'), findsOneWidget);
    await say(t, 'المشتركين المنتهين');
    expect(find.byKey(const ValueKey('voice-list')), findsOneWidget);
    expect(find.text('المنتهون'), findsOneWidget);
    expect(find.text('افتح القائمة'), findsOneWidget);
    expect(loads, 0, reason: 'لا قائمة مشتركين تُجلب لأمرٍ بلا مشترك');
    await close(t);
  });

  testWidgets('الأمر بالإنكليزيّة يطابق المسجَّل بالعربيّة: "activate Ali Hussein partial 10 thousand"', (t) async {
    VoiceResolver.loadSubscribers = () async => [
          _s('21', '07701', 'علي', 'حسين'),
          _s('22', '07702', 'محمد', 'كاظم'),
        ];
    await open(t);
    await say(t, 'activate Ali Hussein partial 10 thousand');
    expect(find.byKey(const ValueKey('voice-sub-card')), findsOneWidget);
    expect(find.text('علي حسين'), findsOneWidget);
    expect(find.textContaining('دفع 10,000'), findsOneWidget);
    final det = await confirm(t);
    expect([det.sub.idx, det.autoPrefill?.paid], ['21', 10000]);
    await close(t);
  });

  testWidgets('لغة الكلام: «عربي» و«English» (و«تلقائي» حين يفتحه الخادم وحده) — الإنكليزيّة تسمع بوسمها وتبقى محفوظة', (t) async {
    const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    final listened = <String?>[];
    void native(String method, Object value) => t.binding.channelBuffers
        .push(channel.name, const StandardMethodCodec().encodeMethodCall(MethodCall(method, value)), (_) {});
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'locales') return ['ar-IQ:العربية العراقية', 'en_US:English (United States)'];
      if (call.method == 'listen') listened.add((call.arguments as Map)['localeId'] as String?);
      if (call.method == 'stop' || call.method == 'cancel') {
        native('notifyStatus', 'notListening');
        native('notifyStatus', 'done');
      }
      return true;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await open(t, autoListen: true);
    await settle(t, ms: 400);
    expect(listened, ['ar-IQ'], reason: 'الافتراضيّ كما كان: عربيّ');
    expect(find.byKey(const ValueKey('voice-lang-ar')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-lang-en')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-lang-auto')), findsNothing, reason: 'لم يفتحه الخادم لهذه المنصّة');
    await t.tap(find.byKey(const ValueKey('voice-lang-en')));
    await settle(t, ms: 600);
    expect(listened.last, 'en_US', reason: 'النقر يبدأ الاستماع بالإنكليزيّة');
    expect(VoiceLangPref.current, 'en');
    expect(find.text('activate Ali Hussein'), findsOneWidget, reason: 'الأمثلة بلغة الكلام');
    // والنتيجة ببدائل المحرّك: «Hassan» كُتبت، و«Hussein» بديلٌ يطابق مشتركاً بجزم ⇒ هو المأخوذ
    native('notifyStatus', 'listening');
    native(
        'textRecognition',
        jsonEncode({
          'alternates': [
            {'recognizedWords': 'disable Ali Hassan', 'confidence': 0.6},
            {'recognizedWords': 'disable Ali Hussein', 'confidence': 0.5},
          ],
          'resultType': 2,
        }));
    await settle(t, ms: 1500);
    expect(find.byKey(const ValueKey('voice-sub-card')), findsOneWidget);
    expect(find.text('علي حسين'), findsOneWidget);
    expect(find.text('طفّي'), findsOneWidget);
    // (في الاختبار نفسه: قناة المحرّك تُسجَّل بمنطقة أوّل اختبارٍ يهيّئه) — العودة للعربيّة، والبدائل تحسم الاسم: كُتب «علي حسن»
    // ولا مشترك بهذا الاسم، والبديل «علي حسين» يطابق بجزم ⇒ هو المأخوذ والخانة تعرضه
    await t.tap(find.byKey(const ValueKey('voice-lang-ar')));
    await settle(t, ms: 600);
    expect(listened.last, 'ar-IQ');
    native('notifyStatus', 'listening');
    native(
        'textRecognition',
        jsonEncode({
          'alternates': [
            {'recognizedWords': 'فعل علي حسن', 'confidence': 0.6},
            {'recognizedWords': 'فعل علي حسين', 'confidence': 0.5},
          ],
          'resultType': 2,
        }));
    await settle(t, ms: 1500);
    expect(find.byKey(const ValueKey('voice-sub-card')), findsOneWidget, reason: 'مشتركٌ واحد بجزم — لا قائمة «علي»ات');
    expect(find.text('فعّل'), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const ValueKey('voice-text'))).controller!.text, 'فعل علي حسين',
        reason: 'الخانة تعرض ما أُخذ به');
    await close(t);
  });

  testWidgets('«تلقائي» يظهر حين يفتحه الخادم لهذه المنصّة: التسجيل لخادمنا بموافقةٍ أوّلاً (لا مايك قبلها)', (t) async {
    AiAssistantState.debugSet(const AiStatus(enabled: true, canUse: true, voice: true, voiceAuto: true, mode: AiMode.company));
    addTearDown(() => AiAssistantState.debugSet(null));
    await open(t);
    expect(find.byKey(const ValueKey('voice-lang-auto')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('voice-lang-auto')));
    await settle(t, ms: 400);
    expect(VoiceLangPref.current, 'auto');
    await t.tap(find.byIcon(Icons.mic_none_rounded));
    await settle(t, ms: 600);
    expect(find.textContaining('يُرسل صوتك إلى خادم MyServices'), findsOneWidget);
    await t.tap(find.text('ليس الآن'));
    await settle(t, ms: 300);
    await close(t);
  });
}
