import 'dart:async';

// «أمر صوتي» (٧ نوفمبر): الجملة ⇒ كرت التأكيد ⇒ صفحة المشترك ونافذة العمليّة نفسها (لا تنفيذ بلا ضغطة الوكيل هناك).
// المايك لا يُشغَّل بالاختبار (autoListen:false) — النصّ يُكتب كما لو أملاه.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/device_sweep_coordinator.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/core/widgets/app_sheet.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/screens/voice/voice_command_sheet.dart';
import 'package:rad_mysvcs/services/agent_net_presence.dart';
import 'package:rad_mysvcs/services/devices_check.dart';
import 'package:rad_mysvcs/services/devices_check_runner.dart';
import 'package:rad_mysvcs/services/voice/voice_check.dart';
import 'package:rad_mysvcs/services/voice/voice_resolver.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';

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
    expect(find.textContaining('قلت: دين · شهرين'), findsOneWidget, reason: 'ما قيل عن الدفع والمدّة — يظهر مختاراً بشاشة التفعيل (١٠ نوفمبر)');
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
    expect(find.text('ما عليه دين'), findsOneWidget, reason: 'الكرت يقولها قبل الفتح — ولا مبلغ يُسأل عنه');
    expect(find.textContaining('المبلغ'), findsNothing);
    await t.tap(find.byKey(const ValueKey('voice-confirm')));
    await settle(t, ms: 2500);
    expect(t.widget<SubscriberDetailScreen>(find.byType(SubscriberDetailScreen)).autoAction, SubscriberAutoAction.payDebt);
    expect(find.text('ما عليه دين'), findsWidgets);
    await close(t);
  });

  testWidgets('«فحص شامل» ⇒ كرت الفحص الشامل', (t) async {
    await open(t);
    await say(t, 'فحص شامل');
    expect(find.byKey(const ValueKey('voice-check-all')), findsOneWidget);
    expect(find.text('ابدأ الفحص'), findsOneWidget);
    await close(t);
  });
  testWidgets('٨ نوفمبر: «افحص المشترك علي حسين» ⇒ الجواب أوّلاً: حاله ثمّ جهازه (الإشارة وCCQ) ثمّ «افتح المشترك»', (t) async {
    // المالك: «الكارت مباشره يجاوبه قبل يا اما مخلص متصل ومخلص طافي اذا متصل وفعال شنو حاله السي سي كيو، حاله الاشاره»
    VoiceResolver.loadSubscribers = () async => [
          Subscriber.fromJson({
            'idx': '11', 'username': 'ali.hussein', 'firstname': 'علي', 'lastname': 'حسين', 'online_status': 1,
            'remaining_days': 12, 'ip_address': '10.0.0.7',
          }),
        ];
    SubscriberVoiceCheck.debugLocalAllowed = () => true;
    SubscriberVoiceCheck.debugProbe = (_) async => const DeviceHealthSnapshot(
        kind: DeviceKind.ubiquiti,
        ip: '10.0.0.7',
        ubnt: UbiquitiStatus(
            hostname: 'Nano-Ali', firmware: 'XC', uptimeSeconds: 1, ssid: 's', mode: 'sta', signalDbm: -55,
            noiseFloorDbm: -95, ccqPercent: 92, distanceMeters: 1, txRateKbps: 1, rxRateKbps: 1,
            lanPorts: [LanPort(name: 'eth0', speed: '100Mbps-Full', plugged: true)], peerMac: null, peerCount: 1,
            baseUrl: 'http://x'));
    addTearDown(() {
      SubscriberVoiceCheck.debugLocalAllowed = null;
      SubscriberVoiceCheck.debugProbe = null;
    });
    await open(t);
    await say(t, 'افحص المشترك علي حسين');
    expect(find.byKey(const ValueKey('voice-sub-answer')), findsOneWidget);
    expect(find.text('فعّال ومتّصل'), findsOneWidget);
    expect(find.text('باقي 12 يوماً'), findsOneWidget);
    expect(find.text('92%'), findsOneWidget, reason: 'CCQ ظاهر');
    expect(find.text('-55 dBm'), findsOneWidget);
    expect(find.text('100M'), findsOneWidget);
    expect(find.text('الإشارة، CCQ والكيبل سليمة'), findsOneWidget);
    expect(find.text('افتح المشترك'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('voice-confirm')));
    await settle(t, ms: 2500);
    expect(find.byType(SubscriberDetailScreen), findsOneWidget);
    await close(t);
  });

  testWidgets('المراجعة ١٠ نوفمبر: «افحص المشترك» من آخر قراءةٍ عبر الـVPN ⇒ مصدرها بعمرها كـ«الفحص العامّ»',
      (t) async {
    // آخر فحصٍ عبر الـVPN قبل ١٢ دقيقة (يُقبل حتى ٣٠ د) — كان «عبر VPN الشركة» بلا عمر كأنّه الآن
    VoiceResolver.loadSubscribers = () async => [
          Subscriber.fromJson({
            'idx': '11', 'username': 'ali.hussein', 'firstname': 'علي', 'lastname': 'حسين', 'online_status': 1,
            'remaining_days': 12, 'ip_address': '10.0.0.7',
          }),
        ];
    SubscriberVoiceCheck.debugLocalAllowed = () => false;
    SubscriberVoiceCheck.debugVpnAllowed = () => true;
    SubscriberVoiceCheck.debugVpnRun = (s, c) async {};
    VpnNow.debugApply(
        VpnNowKind.subscribers,
        const VpnNowResult(
            ok: true, message: 'تم', readings: {'ali.hussein': VpnSubReading(src: 'sector', sig: -58, ccq: 93)}));
    SubscriberVoiceCheck.debugNow = () => DateTime.now().add(const Duration(minutes: 12));
    addTearDown(() {
      SubscriberVoiceCheck.debugLocalAllowed = null;
      SubscriberVoiceCheck.debugVpnAllowed = null;
      SubscriberVoiceCheck.debugVpnRun = null;
      SubscriberVoiceCheck.debugNow = null;
      VpnNow.reset();
    });
    await open(t);
    await say(t, 'افحص المشترك علي حسين');
    expect(find.byKey(const ValueKey('voice-sub-answer')), findsOneWidget);
    expect(find.text('الإشارة وCCQ سليمة'), findsOneWidget);
    expect(find.text('عبر VPN الشركة · منذ 12 دقيقة · من السكتر'), findsOneWidget);
    await close(t);
  });

  testWidgets('٨ نوفمبر: «افحص سكتر الشمال» ⇒ كرت الجهاز بنتيجة فحصه مباشرةً (حاله وما به) و«التقرير الكامل»', (t) async {
    // المالك: «يقول افحص سكتر فلان… يجيب له الكارت مباشره يعطي نتيجه الجهاز شنو اللي بي»
    final sector = NetworkDevice(
      id: 2, adminId: '2', name: 'سكتر الشمال', type: 'sector', brand: 'ubnt', ip: '10.9.0.2', port: 443,
      protocol: 'https', hasCredentials: true, lastStatus: 'online', createdAt: DateTime(2026, 11, 1),
    );
    VoiceResolver.loadDevices = () async => [sector];
    final route = VpnNow.routeSource;
    VpnNow.routeSource = () async => (linked: false, via: null);
    AgentNetPresence.debugSet(NetPresence.on);
    DevicesCheckRunner.debugLimits = () async => const CheckLimits(subSignal: -70, subCcq: 50);
    DevicesCheckRunner.debugSubscribers = () async => const [];
    DevicesCheckRunner.debugProbe = (d) async => (status: 'online', responseMs: 4, packetLoss: 0.0, serviceOk: true);
    DevicesCheckRunner.debugFetch = (d) async => const ProbeResult(
          vitals: [],
          counters: {},
          detail: DeviceDetail(glance: DeviceGlance(isAp: true, cpu: 20), peers: [
            PeerLink(name: 'ali.home', signal: -61, ccq: 95),
            PeerLink(name: 'omar.weak', signal: -79, ccq: 80),
          ]),
        );
    addTearDown(() {
      VoiceResolver.loadDevices = () async => const [];
      VpnNow.routeSource = route;
      DevicesCheckRunner.debugLimits = null;
      DevicesCheckRunner.debugSubscribers = null;
      DevicesCheckRunner.debugProbe = null;
      DevicesCheckRunner.debugFetch = null;
    });
    await open(t);
    await say(t, 'افحص سكتر الشمال');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await settle(t);
    expect(find.byKey(const ValueKey('voice-dev-answer')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-dev-state')), findsOneWidget, reason: 'حاله: طافي/ملاحظات/سليم');
    expect(find.textContaining('إشارة ضعيفة: 1'), findsOneWidget, reason: 'ما به');
    expect(find.textContaining('omar.weak (-79 dBm)'), findsOneWidget, reason: 'والضعيف باسمه');
    expect(find.text('التقرير الكامل'), findsOneWidget);
    expect(find.text('صفحة الجهاز'), findsOneWidget);
    await close(t);
  });

  testWidgets('المراجعة: «افحص سكتر…» يمسك قسم الأجهزة ما دام يجري، ويُظهر سطر البطيء بعد مهلته الأولى لا دوّارةً صامتة', (t) async {
    final sector = NetworkDevice(
      id: 3, adminId: '2', name: 'سكتر الجنوب', type: 'sector', brand: 'ubnt', ip: '10.9.0.3', port: 443,
      protocol: 'https', hasCredentials: true, lastStatus: 'online', createdAt: DateTime(2026, 11, 1),
    );
    VoiceResolver.loadDevices = () async => [sector];
    final route = VpnNow.routeSource;
    VpnNow.routeSource = () async => (linked: false, via: null);
    AgentNetPresence.debugSet(NetPresence.on);
    final slow = Completer<ProbeResult>();
    DevicesCheckRunner.debugLimits = () async => const CheckLimits();
    DevicesCheckRunner.debugSubscribers = () async => const [];
    DevicesCheckRunner.debugProbe = (d) async => (status: 'online', responseMs: 4, packetLoss: 0.0, serviceOk: true);
    DevicesCheckRunner.debugFetch = (d) => slow.future;
    DevicesCheckRunner.debugTimes = (soft: const Duration(milliseconds: 200), hard: const Duration(seconds: 20));
    addTearDown(() {
      if (!slow.isCompleted) slow.complete(const ProbeResult(vitals: [], counters: {}, detail: DeviceDetail()));
      VoiceResolver.loadDevices = () async => const [];
      VpnNow.routeSource = route;
      DevicesCheckRunner.debugLimits = null;
      DevicesCheckRunner.debugSubscribers = null;
      DevicesCheckRunner.debugProbe = null;
      DevicesCheckRunner.debugFetch = null;
      DevicesCheckRunner.debugTimes = null;
    });
    await open(t);
    await say(t, 'افحص سكتر الجنوب');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();
    expect(DeviceSweep.suspended, isTrue, reason: 'جولة الحال والبطاقات تقف ما دام يجري');
    // الفاحص بدأ داخل runAsync (ساعةٌ حقيقيّة) — ننتظر بالساعتين معاً
    for (var i = 0; i < 40 && find.textContaining('يكمل قراءته').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(t.widget<Text>(find.byKey(const ValueKey('voice-dev-progress'))).data, startsWith('يقرأ… — بطيء — يكمل قراءته'));
    slow.complete(const ProbeResult(
        vitals: [], counters: {}, detail: DeviceDetail(glance: DeviceGlance(isAp: true, peersKnown: true, cpu: 7))));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(t);
    expect(DeviceSweep.suspended, isFalse, reason: 'انتهى ⇒ يعود القسم');
    expect(find.byKey(const ValueKey('voice-dev-state')), findsOneWidget);
    await close(t);
  });

  testWidgets('المراجعة الثانية: «افحص سكتر…» مرّتين والطريق ما زال يُسأل ⇒ فاحصٌ واحد، ولا فاحصٌ يتيم يمسك القسم بعد الإغلاق',
      (t) async {
    final sector = NetworkDevice(
      id: 4, adminId: '2', name: 'سكتر الشرق', type: 'sector', brand: 'ubnt', ip: '10.9.0.4', port: 443,
      protocol: 'https', hasCredentials: true, lastStatus: 'online', createdAt: DateTime(2026, 11, 1),
    );
    VoiceResolver.loadDevices = () async => [sector];
    VpnNow.reset(); // لا طريقٌ مخبوء من اختبارٍ سابق — يُسأل الخادم فعلاً (والسؤال ينتظر)
    final route = VpnNow.routeSource;
    final routeGate = Completer<({bool linked, String? via})?>();
    VpnNow.routeSource = () => routeGate.future;
    AgentNetPresence.debugSet(NetPresence.on);
    final slow = Completer<ProbeResult>();
    var reads = 0;
    DevicesCheckRunner.debugLimits = () async => const CheckLimits();
    DevicesCheckRunner.debugSubscribers = () async => const [];
    DevicesCheckRunner.debugProbe = (d) async => (status: 'online', responseMs: 4, packetLoss: 0.0, serviceOk: true);
    DevicesCheckRunner.debugFetch = (d) {
      reads++;
      return slow.future;
    };
    DevicesCheckRunner.debugTimes = (soft: const Duration(seconds: 20), hard: const Duration(seconds: 40));
    addTearDown(() {
      if (!routeGate.isCompleted) routeGate.complete((linked: false, via: null));
      if (!slow.isCompleted) slow.complete(const ProbeResult(vitals: [], counters: {}, detail: DeviceDetail()));
      VoiceResolver.loadDevices = () async => const [];
      VpnNow.routeSource = route;
      DevicesCheckRunner.debugLimits = null;
      DevicesCheckRunner.debugSubscribers = null;
      DevicesCheckRunner.debugProbe = null;
      DevicesCheckRunner.debugFetch = null;
      DevicesCheckRunner.debugTimes = null;
    });
    await open(t);
    await say(t, 'افحص سكتر الشرق'); // ينتظر الطريق (نداء خادمٍ والمخبأ فارغ)
    await say(t, 'افحص سكتر الشرق'); // كرّرها قبل أن يجيب
    routeGate.complete((linked: false, via: null));
    for (var i = 0; i < 10; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 30));
    }
    expect(reads, 1, reason: 'فاحصٌ واحد يقرأ السكتر — لا جلستان على الجهاز نفسه');
    expect(DeviceSweep.suspended, isTrue, reason: 'يجري');
    await close(t);
    expect(DeviceSweep.suspended, isFalse, reason: 'أُغلق ⇒ لا فاحصٌ يتيم يمسك القسم حتى ينتهي');
  });
}
