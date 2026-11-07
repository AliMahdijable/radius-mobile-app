// «أمر صوتي» (٧ نوفمبر): الجملة ⇒ كرت التأكيد ⇒ صفحة المشترك ونافذة العمليّة نفسها (لا تنفيذ بلا ضغطة الوكيل هناك).
// المايك لا يُشغَّل بالاختبار (autoListen:false) — النصّ يُكتب كما لو أملاه.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/core/widgets/app_sheet.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/screens/voice/voice_command_sheet.dart';
import 'package:rad_mysvcs/services/voice/voice_resolver.dart';

import 'visual_perm/visual_perm_harness.dart';

Subscriber _s(String idx, String user, String first, String last, {bool enabled = true}) => Subscriber.fromJson({
      'idx': idx,
      'username': user,
      'firstname': first,
      'lastname': last,
      'enabled': enabled,
      'profile_name': 'Fiber 35',
    });

void main() {
  setUpAll(visualSetUpAll);

  final subs = [
    _s('11', 'ali.hussein', 'علي', 'حسين'),
    _s('12', 'ali77', 'علي', 'كاظم'),
    _s('13', 'zainab', 'زينب', 'علي', enabled: false),
  ];

  setUp(() {
    VoiceResolver.bigProbe = () async => 0;
    VoiceResolver.loadSubscribers = () async => subs;
  });
  tearDown(() {
    VoiceResolver.bigProbe = () async => 0;
    VoiceResolver.loadSubscribers = () async => const [];
  });

  Future<void> settle(WidgetTester t, {int ms = 1500}) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester t) async {
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
                      builder: (_) => VoiceCommandSheet(rootContext: ctx, autoListen: false),
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

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
    await visualTearDown();
  }

  testWidgets('مايك الآيفون: نص جزئي ثم سكوت ⇒ كرت الأمر بلا إنتر وبلا تنفيذ', (t) async {
    const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    void native(String method, Object value) => t.binding.channelBuffers.push(
        channel.name, const StandardMethodCodec().encodeMethodCall(MethodCall(method, value)), (_) {});
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'locales') return ['ar-IQ:العربية العراقية'];
      if (call.method == 'stop') {
        native('notifyStatus', 'notListening');
        native('notifyStatus', 'done');
      }
      return true;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await open(t);
    await t.tap(find.byIcon(Icons.mic_none_rounded));
    await t.pump();
    await settle(t, ms: 200);
    native('notifyStatus', 'listening');
    native('textRecognition', jsonEncode({
      'alternates': [{'recognizedWords': 'طفي علي حسين.', 'confidence': 0.95}],
      'resultType': 0,
    }));
    await settle(t, ms: 5000);
    expect(find.byKey(const ValueKey('voice-sub-card')), findsOneWidget);
    expect(find.text('علي حسين'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-confirm')), findsOneWidget);
    expect(find.byType(SubscriberDetailScreen), findsNothing,
        reason: 'الكلام يجهّز كرت التأكيد فقط، لا يفتح العملية أو ينفّذها');
    await close(t);
  });

  testWidgets('«طفي علي حسين» ⇒ كرتٌ واحد بزرّ «طفّي» ⇒ صفحته ونافذة التطفية للتأكيد (لا تطفية قبلها)', (t) async {
    await open(t);
    expect(find.text('جرّب:'), findsOneWidget, reason: 'أمثلةٌ قبل أيّ أمر');
    await say(t, 'طفي علي حسين');
    expect(find.byKey(const ValueKey('voice-sub-card')), findsOneWidget);
    expect(find.text('علي حسين'), findsOneWidget);
    expect(find.text('طفّي'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('voice-confirm')));
    await settle(t, ms: 2500);
    final det = t.widget<SubscriberDetailScreen>(find.byType(SubscriberDetailScreen));
    expect(det.autoAction, SubscriberAutoAction.disable);
    expect(det.sub.username, 'ali.hussein');
    expect(find.byType(AlertDialog), findsOneWidget, reason: 'نافذة التطفية نفسها — التنفيذ بضغطة الوكيل');
    await close(t);
  });

  testWidgets('«فعل علي» ⇒ ثلاثة مرشّحين يختار منهم ⇒ كرت «فعّل»؛ ومن هو مطفي أصلاً ⇒ «شغّل» يعمل و«طفّي» يقول السبب', (t) async {
    await open(t);
    await say(t, 'فعل علي شهرين بالدين');
    expect(find.text('أكثر من مشترك — اختار:'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-sub-11')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-sub-12')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('voice-sub-12')));
    await settle(t, ms: 300);
    expect(find.byKey(const ValueKey('voice-sub-card')), findsOneWidget);
    expect(find.text('فعّل'), findsOneWidget);
    expect(find.textContaining('قلت: شهرين بالدين'), findsOneWidget, reason: 'المدّة والدفع تذكيرٌ — تُختار بشاشة التفعيل');
    // اسمٌ لا يُعرف
    await say(t, 'طفي سجاد الموسوي');
    expect(find.textContaining('ما لكيت مشترك باسم «سجاد الموسوي»'), findsOneWidget);
    // أمرٌ لا يُفهم
    await say(t, 'فعل');
    expect(find.textContaining('ما فهمت الأمر'), findsOneWidget);
    // «شغّل زينب» (مطفيّة) ⇒ الكرت يقول «مطفي» وزرّه «شغّل»
    await say(t, 'شغل زينب');
    expect(find.text('شغّل'), findsOneWidget);
    expect(find.textContaining('مطفي'), findsOneWidget);
    await close(t);
  });

  testWidgets('٧ نوفمبر: «ضيف دين على علي حسين ١٠ آلاف» ⇒ الكرت بالمبلغ ⇒ نافذة إضافة الدين نفسها والمبلغ بخانتها (التنفيذ بضغطته)', (t) async {
    await open(t);
    await say(t, 'ضيف دين على علي حسين ١٠ آلاف');
    expect(find.byKey(const ValueKey('voice-sub-card')), findsOneWidget);
    expect(find.text('أضف الدين'), findsOneWidget);
    expect(find.textContaining('المبلغ: '), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('voice-confirm')));
    await settle(t, ms: 2500);
    final det = t.widget<SubscriberDetailScreen>(find.byType(SubscriberDetailScreen));
    expect([det.autoAction, det.autoAmount], [SubscriberAutoAction.addDebt, 10000]);
    expect(find.byWidgetPredicate((w) => w is TextField && (w.controller?.text ?? '') == '10,000'), findsOneWidget,
        reason: 'المبلغ بخانة النافذة بفواصله');
    await close(t);
  });

  testWidgets('٧ نوفمبر: «سدد دين علي حسين» وما عليه دين ⇒ الصفحة تقول «ما عليه دين» بلا نافذة', (t) async {
    await open(t);
    await say(t, 'سدد دين علي حسين');
    expect(find.text('سدّد الدين'), findsOneWidget);
    expect(find.text('المبلغ تكتبه بالنافذة'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('voice-confirm')));
    await settle(t, ms: 2500);
    expect(t.widget<SubscriberDetailScreen>(find.byType(SubscriberDetailScreen)).autoAction, SubscriberAutoAction.payDebt);
    expect(find.text('ما عليه دين'), findsOneWidget);
    await close(t);
  });

  testWidgets('«فحص شامل» ⇒ كرت الفحص الشامل', (t) async {
    await open(t);
    await say(t, 'فحص شامل');
    expect(find.byKey(const ValueKey('voice-check-all')), findsOneWidget);
    expect(find.text('ابدأ الفحص'), findsOneWidget);
    await close(t);
  });
}
