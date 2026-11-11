// «وضع VPN» بالقسمين (٥ نوفمبر — المالك: «المشتركين مابي زر فحص ع vpn… اريد من ينقر ع vpn يتفعل الفحص يتوجه ع vpn… حارس…
// يحول الفحص للشبكه بدون vpn»، وصورته: «فُحصت أجهزتك ✓ — 14 من 14 واصل» والبطاقات حمراء «غير متّصل»):
// زرّ VPN بجنب البحث بالقسمين لمن له طريق VPN — خارج شبكته (أو والحال مجهولة) وطول ما الوضع شغّال؛ على شبكته لا زرّ.
// والأجهزة بالوضع تُعرض بحالها من الـVPN (الأعداد والبطاقات)، وما لم يُفحص «غير معروف» لا «مفصول».
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/agent_alerts_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/api/vpn_now_api.dart';
import 'package:rad_mysvcs/core/net/vpn_pipe.dart';
import 'package:rad_mysvcs/screens/network_devices/check/devices_check_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/network_device_details_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/screens/network_devices/network_devices_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_big_card.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/screens/whatsapp/conn_vpn_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/services/agent_net_presence.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:rad_mysvcs/services/device_alerts_service.dart';
import 'package:rad_mysvcs/services/devices_check.dart';
import 'package:rad_mysvcs/services/devices_check_runner.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_check_screen.dart';

import 'sim_el/sim_harness.dart';
import 'support/ai_status_overlay.dart';
import 'support/devices_demo_data.dart';
import 'visual_perm/visual_perm_harness.dart';

class _NoLocalNotifications extends FlutterLocalNotificationsPlatform {}

/// ممرّ «وضع VPN» بلا خادم: يسجّل ما فُتح عبره ويرفض (كممرٍّ لم يصل) — القارئ يرجع لما قرأه الخادم.
class _NoPipe implements VpnPipeTransport {
  final opens = <String>[];
  @override
  Future<({String id, int? ms})> open(String host, int port, Duration timeout) async {
    opens.add('$host:$port');
    throw SocketException('لا ممرّ في الاختبار', port: port);
  }

  @override
  Future<bool> write(String id, Uint8List data) async => false;
  @override
  Future<PipeRead?> read(String id, Duration wait) async => null;
  @override
  Future<void> close(String id) async {}
  @override
  Future<({Uint8List data, int? ms})> udp(String host, int port, Uint8List data, Duration timeout) async {
    opens.add('udp $host:$port');
    throw TimeoutException('لا ممرّ في الاختبار');
  }

  @override
  Future<List<int>> ping(String host, int count, Duration timeout) async {
    opens.add('ping $host');
    return const [];
  }

  @override
  Future<PipeRoute> route() async => const PipeRoute.ok('company');

  @override
  Future<void> release() async {}
}

/// ممرّ «وضع VPN» يردّ بنكه من داخل النفق لكلّ عنوانٍ إلّا [dead]؛ الاتّصالات (TCP/UDP) لا تصل — كجهازٍ يردّ على ping وخدمته مغلقة.
class _PingPipe extends _NoPipe {
  _PingPipe(this.dead);
  final Set<String> dead;
  @override
  Future<List<int>> ping(String host, int count, Duration timeout) async {
    opens.add('ping $host');
    return dead.contains(host) ? const [] : [for (var i = 0; i < count; i++) 20 + i];
  }
}

void main() {
  setUpAll(() async {
    await simSetUpAll();
    FlutterLocalNotificationsPlatform.instance = _NoLocalNotifications();
  });
  setUp(() {
    VpnNow.reset();
    AgentNetPresence.reset();
    VpnNow.guardProbe = () async => null; // لا شبكة بالاختبار
  });
  tearDown(() {
    VpnNow.routeSource = () async => null;
    VpnNow.guardProbe = null;
    VpnNow.reset();
    AgentNetPresence.reset();
  });

  Future<void> settleFor(WidgetTester t, {int seconds = 2}) async {
    for (var i = 0; i < seconds * 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester t) async {
    VpnNow.reset(); // نبضة الوضع مؤقّتٌ دوريّ — لا يبقى بعد الاختبار
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 25));
    await visualTearDown();
    AiAssistantState.reset();
    AgentAlertsApi.forget();
    DeviceAlertsService.instance.unreadCount.value = 0;
  }

  Future<void> openSubscribers(WidgetTester t) async {
    final inner = await visualSetUp(s1bSasOwner);
    ApiClient.dio.httpClientAdapter = AiStatusOverlay(inner, status: aiStatusOff);
    AiAssistantState.reset();
    SubscribersApi.clearAllCaches();
    await pumpVisual(t, phone,
        home: (_) => SubscribersScreen(filterCmd: ValueNotifier<SubscriberFilter?>(SubscriberFilter.all)));
    await settleFor(t);
  }

  final subsVpn = find.byKey(const ValueKey('subs-vpn-mode'));
  final devVpn = find.byKey(const ValueKey('devices-vpn-mode'));

  testWidgets('المشتركون: خارج شبكتك + مربوط ⇒ زرّ VPN بجنب البحث؛ الضغط يشغّل الوضع والرادار يحدّث عبر الـVPN؛ الضغط ثانيةً يطفئه', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    AgentNetPresence.debugSet(NetPresence.off);
    await openSubscribers(t);
    expect(subsVpn, findsOneWidget);
    await t.tap(subsVpn);
    await settleFor(t, seconds: 1);
    expect(VpnNow.mode.value, isTrue);
    expect(VpnNow.attached, contains(VpnNowKind.subscribers), reason: 'القسم الظاهر يُحدَّث بالوضع');
    expect(find.text('إيقاف'), findsOneWidget, reason: 'شريط الوضع');
    final before = VpnNow.subscribers.startedAt;
    // الرادار = «الفحص العامّ» (٨ نوفمبر): تقريره عبر الـVPN بالوضع، والفحص عبر الخادم لا موجة من الموبايل
    await t.tap(find.byIcon(Icons.radar_rounded));
    await settleFor(t, seconds: 1);
    expect(find.byType(SubscribersCheckScreen), findsOneWidget);
    expect(find.textContaining('عبر VPN'), findsWidgets);
    expect(VpnNow.subscribers.startedAt, isNotNull);
    expect(VpnNow.subscribers.startedAt == before || VpnNow.subscribers.phase != VpnBarPhase.idle, isTrue,
        reason: 'الرادار بالوضع = فحصٌ عبر الـVPN لا موجة من الموبايل');
    Navigator.of(t.element(find.byType(SubscribersCheckScreen))).pop();
    await settleFor(t, seconds: 1);
    await t.tap(subsVpn);
    await settleFor(t, seconds: 1);
    expect(VpnNow.mode.value, isFalse);
    await close(t);
  });

  // ١١ نوفمبر (المالك: «مرات جاي ينخدع البرنامج اني هسه مو على شبكه بس يشوف اي ايبي من ضمن شبكتي حتى لو وهمي يروح الزر… تبقي
  // زر يظهر حتى الوكيل مخير بالنقر ويفحص»): كان الزرّ يختفي و«على شبكتك» — الآن ظاهرٌ دائماً لمن له طريق VPN، وضغطته تشغّل الوضع.
  testWidgets('المشتركون: «على شبكتك» بنظر التطبيق ⇒ الزرّ باقٍ والضغطة تشغّل الوضع (الوكيل يقرّر)؛ بلا طريق VPN ⇒ لا زرّ', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    AgentNetPresence.debugSet(NetPresence.on);
    await openSubscribers(t);
    expect(subsVpn, findsOneWidget, reason: 'لا يختفي بتخمين «على شبكتك»');
    expect(find.descendant(of: subsVpn, matching: find.byIcon(LucideIcons.shield)), findsOneWidget, reason: 'مطفأ ⇒ درعٌ بإطار');
    await t.tap(subsVpn);
    await settleFor(t, seconds: 1);
    expect(VpnNow.mode.value, isTrue, reason: 'ضغطةٌ صريحة وهو «على شبكته» ⇒ الوضع يشتغل');
    expect(find.descendant(of: subsVpn, matching: find.byIcon(LucideIcons.shieldCheck)), findsOneWidget);
    await t.tap(find.byIcon(Icons.radar_rounded));
    await settleFor(t, seconds: 1);
    expect(t.widget<SubscribersCheckScreen>(find.byType(SubscribersCheckScreen)).viaVpn, isTrue, reason: 'الفحص العامّ بالوضع عبر الـVPN');
    Navigator.of(t.element(find.byType(SubscribersCheckScreen))).pop();
    await settleFor(t, seconds: 1);
    await t.tap(subsVpn);
    await settleFor(t, seconds: 1);
    expect(VpnNow.mode.value, isFalse);
    expect(subsVpn, findsOneWidget, reason: 'وبعد الإطفاء باقٍ');
    await close(t);

    VpnNow.routeSource = () async => (linked: false, via: null);
    AgentNetPresence.debugSet(NetPresence.off);
    await openSubscribers(t);
    expect(subsVpn, findsNothing);
    await close(t);
  });

  Future<void> openDevices(WidgetTester t) async {
    NetworkDevicesScreen.debugResetView();
    AgentAlertsApi.forget();
    final inner = await visualSetUp(s1bSasOwner);
    ApiClient.dio.httpClientAdapter = AiStatusOverlay(inner, status: aiStatusOff, routes: DevicesDemoData.routes());
    AiAssistantState.reset();
    await pumpSim(t, const SimVariant(412, dark: false),
        settle: false, home: (_) => NetworkDevicesScreen(isActive: ValueNotifier<bool>(true)));
    await settleFor(t);
  }

  Finder chipCount(String key, String n) =>
      find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(n));

  testWidgets('٧ نوفمبر (المالك: «كانما الوكيل يفعل vpn خارجي»): زرّ VPN ⇒ جولة القسم نفسها عبر الممرّ — البنك من داخل النفق يعدّ «متّصل/مفصول» كما على شبكته؛ الإطفاء يرجعها مباشرة', (t) async {
    final pipes = _PingPipe({'10.70.0.1'});
    final orig = VpnPipe.transport;
    VpnPipe.transport = pipes;
    addTearDown(() => VpnPipe.transport = orig);
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    AgentNetPresence.debugSet(NetPresence.off);
    await openDevices(t);
    expect(devVpn, findsOneWidget);
    await t.tap(devVpn);
    await settleFor(t, seconds: 2);
    expect(VpnNow.mode.value, isTrue);
    expect(VpnNow.attached, contains(VpnNowKind.devices));
    expect(pipes.opens.where((o) => o.startsWith('ping ')), isNotEmpty, reason: 'بنك الأجهزة عبر الـVPN');
    for (final o in pipes.opens) {
      final ip = o.split(' ').last.split(':').first;
      expect(RegExp(r'^(10|192\.168)\.').hasMatch(ip), isTrue, reason: 'عناوين شبكة الوكيل وحدها عبر الممرّ: $o');
    }
    // ١١ عنواناً خاصّاً بُنكت من داخل النفق (١٠ ردّت)؛ الأولتان بحالهما من قارئ الألياف (الجولة لا تبنكهما) — أحدهما مفصول بالعرض
    expect(chipCount('devices-status-online', '12'), findsOneWidget, reason: 'ردّوا من داخل النفق — منهم ما كان «مفصولاً» عند الموبايل');
    expect(chipCount('devices-status-offline', '2'), findsOneWidget, reason: 'الذي لا يردّ حتى عبر النفق، والأولت المفصول');
    expect(pipes.opens.where((o) => o.startsWith('ping ')).length, 11);
    expect(find.text('متّصل عبر الـVPN ✓'), findsOneWidget, reason: 'الشريط: الطريق قائم');
    await t.tap(devVpn);
    await settleFor(t, seconds: 1);
    expect(VpnNow.mode.value, isFalse);
    await close(t);
  });

  testWidgets('الأجهزة بالبطاقات الكبيرة + «وضع VPN»: حالها من جولة القسم عبر الممرّ ولا سطر «خارج شبكتك» — كأنّه على شبكته', (t) async {
    final pipes = _PingPipe(const {});
    final orig = VpnPipe.transport;
    VpnPipe.transport = pipes;
    addTearDown(() => VpnPipe.transport = orig);
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    AgentNetPresence.debugSet(NetPresence.off);
    NetworkDevicesScreen.debugResetView();
    AgentAlertsApi.forget();
    final inner = await visualSetUp(s1bSasOwner);
    await const FlutterSecureStorage().write(key: 'devices.view.v1', value: DevicesView.big.key);
    ApiClient.dio.httpClientAdapter = AiStatusOverlay(inner, status: aiStatusOff, routes: DevicesDemoData.routes());
    AiAssistantState.reset();
    await pumpSim(t, const SimVariant(412, dark: false),
        settle: false, home: (_) => NetworkDevicesScreen(isActive: ValueNotifier<bool>(true)));
    await settleFor(t);
    expect(find.byType(DeviceBigCard).evaluate().map((e) => (e.widget as DeviceBigCard).state.error), contains(DeviceVitals.offNetworkReason),
        reason: 'قبل الوضع: خارج شبكتك');
    await t.tap(devVpn);
    await settleFor(t, seconds: 2);
    final cards = t.widgetList<DeviceBigCard>(find.byType(DeviceBigCard)).toList();
    expect(cards, isNotEmpty, reason: 'البطاقات الكبيرة');
    for (final c in cards) {
      expect(c.state.error, isNot(DeviceVitals.offNetworkReason), reason: 'لا «خارج شبكتك» بالوضع');
      expect(c.device.lastStatus, 'online', reason: 'ردّ بنكه من داخل النفق');
    }
    await close(t);
  });

  testWidgets('«فحص شامل» (٦ نوفمبر) أوّل «المزيد» بوجود أجهزة (٧ نوفمبر) — على شبكتك يفحص منها، وبوضع VPN عبر الـVPN', (t) async {
    DevicesCheckRunner.debugLimits = () async => const CheckLimits();
    DevicesCheckRunner.debugSubscribers = () async => const [];
    DevicesCheckRunner.debugProbe = (d) async => (status: 'offline', responseMs: null, packetLoss: null, serviceOk: null);
    addTearDown(() {
      DevicesCheckRunner.debugLimits = null;
      DevicesCheckRunner.debugProbe = null;
      DevicesCheckRunner.debugSubscribers = null;
    });
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    AgentNetPresence.debugSet(NetPresence.on);
    await openDevices(t);
    expect(find.byKey(const ValueKey('devices-deep-check')), findsNothing, reason: 'الهاتف: داخل «المزيد» (المالك: «بتزاحم كبير»)');
    expect(find.byTooltip('تحديث فوري'), findsNothing, reason: 'التحديث في «المزيد»');
    await t.tap(find.byTooltip('المزيد'));
    await settleFor(t, seconds: 1);
    final deep = find.text('فحص شامل');
    expect(deep, findsOneWidget);
    expect(find.byIcon(LucideIcons.refreshCw), findsOneWidget, reason: '«تحديث» معه (نصّه «يُحدّث الآن…» أثناء الجولة)');
    await t.tap(deep);
    await settleFor(t, seconds: 2);
    final screen = t.widget<DevicesCheckScreen>(find.byType(DevicesCheckScreen));
    expect(screen.viaVpn, isFalse);
    expect(screen.devices.length, 14);
    expect(find.text('فُحصت 14 أجهزة'), findsOneWidget);
    await close(t);
  });

  testWidgets('الأجهزة: «على شبكتك» بنظر التطبيق ⇒ زرّ VPN باقٍ والضغطة تشغّل الوضع (١١ نوفمبر)؛ بلا طريق VPN ⇒ لا زرّ', (t) async {
    final pipes = _PingPipe(const {});
    final orig = VpnPipe.transport;
    VpnPipe.transport = pipes;
    addTearDown(() => VpnPipe.transport = orig);
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    AgentNetPresence.debugSet(NetPresence.on);
    await openDevices(t);
    expect(devVpn, findsOneWidget, reason: 'لا يختفي بتخمين «على شبكتك»');
    expect(find.byTooltip('الفحص عبر VPN'), findsOneWidget);
    await t.tap(devVpn);
    await settleFor(t, seconds: 2);
    expect(VpnNow.mode.value, isTrue, reason: 'ضغطةٌ صريحة وهو «على شبكته» ⇒ الوضع يشتغل');
    expect(pipes.opens.where((o) => o.startsWith('ping ')), isNotEmpty, reason: 'جولة القسم عبر الـVPN');
    await t.tap(devVpn);
    await settleFor(t, seconds: 1);
    expect(VpnNow.mode.value, isFalse);
    expect(devVpn, findsOneWidget, reason: 'وبعد الإطفاء باقٍ');
    await close(t);

    VpnNow.routeSource = () async => (linked: false, via: null);
    AgentNetPresence.debugSet(NetPresence.on);
    await openDevices(t);
    expect(devVpn, findsNothing);
    await close(t);
  });

  // ٦ نوفمبر (المالك: «ايرثلنك وكل الشركات البقية مجاي الكه بيها مكان اضيف ملف vpn» ثمّ «ابدي بي»): «ربط VPN» مدخلٌ ثابت في «المزيد»
  // بقسم الأجهزة — على شبكتك أو خارجها، مربوطاً أو لا؛ لصاحب الحساب حين يُفتح له، لا للموظّف.
  Future<void> openMore(WidgetTester t) async {
    await t.tap(find.byTooltip('المزيد'));
    await settleFor(t, seconds: 1);
  }

  final vpnItem = find.text('ربط VPN');

  testWidgets('«ربط VPN» في «المزيد»: يفتح صفحته وعلى شبكتك أيضاً، وبعد الرجوع يُسأل الطريق من جديد', (t) async {
    var asks = 0;
    VpnNow.routeSource = () async {
      asks++;
      return (linked: false, via: null);
    };
    AgentNetPresence.debugSet(NetPresence.on);
    await openDevices(t);
    await openMore(t);
    expect(vpnItem, findsOneWidget, reason: 'مكانٌ ثابت لا يحتاج «خارج شبكتك»');
    expect(find.byIcon(LucideIcons.shieldPlus), findsOneWidget, reason: 'غير مربوط ⇒ درعٌ بـ«+»');
    final before = asks;
    await t.tap(vpnItem);
    await settleFor(t, seconds: 1);
    expect(find.byType(ConnVpnScreen), findsOneWidget);
    Navigator.of(t.element(find.byType(ConnVpnScreen))).pop();
    await settleFor(t, seconds: 1);
    expect(find.byType(ConnVpnScreen), findsNothing);
    expect(asks, greaterThan(before), reason: 'ربطه هناك ⇒ زرّ «وضع VPN» يظهر بلا إعادة فتح القسم');
    await close(t);
  });

  testWidgets('«ربط VPN» مربوطاً: نفس المكان بدرع العلامة', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    AgentNetPresence.debugSet(NetPresence.on);
    await openDevices(t);
    await openMore(t);
    expect(vpnItem, findsOneWidget);
    expect(find.byIcon(LucideIcons.shieldCheck), findsOneWidget);
    await close(t);
  });

  testWidgets('لا «ربط VPN» في «المزيد»: الميزة غير مفتوحة لحسابه، أو موظّف (أسرار شبكة صاحب الحساب)', (t) async {
    VpnNow.routeSource = () async => null;
    AgentNetPresence.debugSet(NetPresence.on);
    await openDevices(t);
    await openMore(t);
    expect(vpnItem, findsNothing);
    expect(find.text('شبكة الألياف'), findsOneWidget, reason: 'القائمة نفسها مفتوحة');
    await close(t);

    VpnNow.routeSource = () async => (linked: true, via: 'company');
    await openDevices(t);
    PermissionsService.debugSet(isEmployee: true, permissions: const {'devices.monitor': true, 'devices.manage': true});
    addTearDown(() => PermissionsService.debugSet(isEmployee: false));
    await openMore(t);
    expect(vpnItem, findsNothing);
    await close(t);
  });

  testWidgets('٦ نوفمبر: الوطنيّ/فايبر اكس (الطريق subscribers=false) ⇒ لا زرّ VPN ولا هنت بالمشتركين — والأجهزة كما هي', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'own');
    VpnNowApi.lastSubscribers = false;
    AgentNetPresence.debugSet(NetPresence.off);
    await openSubscribers(t);
    expect(subsVpn, findsNothing);
    expect(find.text('تشغيل VPN'), findsNothing);
    expect(find.text('ربط VPN'), findsNothing);
    await close(t);
    VpnNowApi.lastSubscribers = false;
    addTearDown(() => VpnNowApi.lastSubscribers = true);
    await openDevices(t);
    expect(devVpn, findsOneWidget, reason: 'أجهزة الوكيل تُفحص عبر ملفّه');
    await close(t);
  });

  // ١١ نوفمبر (المالك: «خليها بلا موافقة يفتح تلقائي»): المدير الفرعيّ الداخل بحسابه — مشتركوه يُفحصون عبر VPN مديره الرئيسيّ، وأجهزة
  // صفحته بلا طريق («الطريق»: devices=false)
  testWidgets('١١ نوفمبر: الطريق devices=false ⇒ زرّ VPN بالمشتركين كما هو، ولا زرّ بقسم الأجهزة — وهنته «ربط VPN» لا «تشغيل VPN»', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'main');
    VpnNowApi.lastDevices = false;
    AgentNetPresence.debugSet(NetPresence.off);
    await openSubscribers(t);
    expect(subsVpn, findsOneWidget, reason: 'مشتركوه عبر VPN مديره');
    await close(t);
    VpnNowApi.lastDevices = false;
    addTearDown(() => VpnNowApi.lastDevices = true);
    AgentNetPresence.debugSet(NetPresence.off);
    await openDevices(t);
    expect(devVpn, findsNothing, reason: 'لا طريق لأجهزته عبر VPN مديره');
    expect(find.text('تشغيل VPN'), findsNothing);
    expect(find.text('ربط VPN'), findsOneWidget, reason: 'أجهزته تحتاج VPN لصفحته');
    await close(t);
  });
  testWidgets('٧ نوفمبر: بوضع VPN الضغط على الجهاز يفتح صفحته الحيّة نفسها — قرّاؤها عبر ممرّ الـVPN (المالك: «كل الفحصوات تمر من vpn»)', (t) async {
    final pipes = _NoPipe();
    final orig = VpnPipe.transport;
    VpnPipe.transport = pipes;
    addTearDown(() => VpnPipe.transport = orig);
    VpnNow.routeSource = () async => (linked: true, via: 'own');
    AgentNetPresence.debugSet(NetPresence.off);
    DevicesCheckRunner.debugLimits = () async => const CheckLimits();
    DevicesCheckRunner.debugSubscribers = () async => const [];
    addTearDown(() {
      DevicesCheckRunner.debugLimits = null;
      DevicesCheckRunner.debugSubscribers = null;
    });
    await openDevices(t);
    await t.tap(devVpn);
    await settleFor(t, seconds: 1);
    expect(VpnNow.mode.value, isTrue);
    VpnNow.debugApply(VpnNowKind.devices, VpnNowResult.fromJson({
      'ok': true,
      'message': 'فُحصت أجهزتك ✓',
      'devices': [
        for (var id = 1; id <= 14; id++) {'id': id, 'alive': true, 'ms': 20},
      ],
    }));
    await settleFor(t, seconds: 1);
    final name = find.text('راوتر المركز CCR');
    expect(name, findsOneWidget, reason: 'أوّل أجهزة القائمة');
    pipes.opens.clear();
    await t.tap(name.first, warnIfMissed: false);
    await settleFor(t, seconds: 3);
    expect(find.byType(NetworkDeviceDetailsScreen), findsOneWidget, reason: 'الصفحة الحيّة نفسها كما على شبكته');
    expect(find.byType(DevicesCheckScreen), findsNothing);
    await close(t);
  });
}
